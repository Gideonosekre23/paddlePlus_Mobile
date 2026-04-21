from django.shortcuts import get_object_or_404
from django.conf import settings
from django.http import JsonResponse
from django.utils import timezone
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated
from .models import Trip
from Bikes.models import Bikes
from Bikes.pricing import calculate_price
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync
import stripe
from geopy.distance import geodesic
from decimal import Decimal

stripe.api_key = settings.STRIPE_SECRET_KEY

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def start_trip(request, trip_id):
    trip = get_object_or_404(Trip, pk=trip_id, renter=request.user.userprofile)
    
    if trip.status != 'created':
        return JsonResponse({'error': 'Trip cannot be started'}, status=400)
    
    trip.status = 'started'
    trip.start_time = timezone.now()
    trip.save()

    channel_layer = get_channel_layer()
    for user_id in [trip.renter.user.id, trip.bike_owner.user.id]:
        async_to_sync(channel_layer.group_send)(
            f'notifications_{user_id}',
            {
                'type': 'send_notification',
                'title': 'Trip Started',
                'message': 'The trip has begun',
                'data': {
                    'trip_id': trip.id,
                    'start_time': trip.start_time.isoformat()
                }
            }
        )
    
    return JsonResponse({
        'message': 'Trip started successfully',
        'start_time': trip.start_time
    })

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def end_trip(request, trip_id):
    trip = get_object_or_404(Trip, pk=trip_id, renter=request.user.userprofile)
    
    if trip.status != 'started':
        return JsonResponse({'error': 'Trip cannot be ended'}, status=400)
    
    try:
        trip.end_time = timezone.now()
        duration_hours = (trip.end_time - trip.start_time).total_seconds() / 3600
        
        if trip.distance is None:
            origin_coords = (trip.origin_latitude, trip.origin_longitude)
            destination_coords = (trip.destination_latitude, trip.destination_longitude)
            trip.distance = geodesic(origin_coords, destination_coords).kilometers
        
        final_price = calculate_price(
            distance=float(trip.distance),
            duration_hours=duration_hours
        )
        trip.price = Decimal(str(final_price))
        
        trip.calculate_commission()
        
        payment_intent = stripe.PaymentIntent.create(
            amount=int(final_price * 100),
            currency='usd',
            customer=request.user.stripe_customer_id,
            transfer_data={
                'destination': trip.bike_owner.stripe_account_id,
                'amount': int(trip.owner_payout * 100)
            },
            metadata={
                'trip_id': trip.id,
                'distance': trip.distance,
                'duration': duration_hours,
                'commission': float(trip.commission_amount)
            }
        )
        
        trip.process_payment()
        trip.complete_trip()

        channel_layer = get_channel_layer()
        for user_id in [trip.renter.user.id, trip.bike_owner.user.id]:
            async_to_sync(channel_layer.group_send)(
                f'notifications_{user_id}',
                {
                    'type': 'send_notification',
                    'title': 'Trip Completed',
                    'message': f'Trip completed. Total cost: ${final_price}',
                    'data': {
                        'trip_id': trip.id,
                        'duration_hours': duration_hours,
                        'distance_km': float(trip.distance),
                        'final_price': float(final_price),
                        'payment_status': 'completed'
                    }
                }
            )
        
        return JsonResponse({
            'message': 'Trip completed successfully',
            'duration_hours': duration_hours,
            'distance_km': trip.distance,
            'final_price': final_price,
            'commission': float(trip.commission_amount),
            'owner_payout': float(trip.owner_payout),
            'payment_intent': payment_intent.client_secret
        })
        
    except stripe.error.StripeError as e:
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f'notifications_{trip.renter.user.id}',
            {
                'type': 'send_notification',
                'title': 'Payment Failed',
                'message': 'There was an issue processing your payment',
                'data': {
                    'trip_id': trip.id,
                    'error': str(e)
                }
            }
        )
        return JsonResponse({
            'error': 'Payment failed',
            'message': str(e)
        }, status=400)

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def cancel_trip(request, trip_id):
    trip = get_object_or_404(Trip, pk=trip_id, renter=request.user.userprofile)
    
    if trip.status in ['completed', 'ontrip']:
        return JsonResponse({'error': 'Trip cannot be canceled at this stage'}, status=400)
    
    trip.status = 'canceled'
    trip.trip_canceled = True
    trip.save()

    channel_layer = get_channel_layer()
    for user_id in [trip.renter.user.id, trip.bike_owner.user.id]:
        async_to_sync(channel_layer.group_send)(
            f'notifications_{user_id}',
            {
                'type': 'send_notification',
                'title': 'Trip Cancelled',
                'message': 'The trip has been cancelled',
                'data': {
                    'trip_id': trip.id,
                    'status': 'canceled'
                }
            }
        )
    
    return JsonResponse({'message': 'Trip canceled successfully'})
