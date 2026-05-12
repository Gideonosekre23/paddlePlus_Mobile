import uuid
import stripe
from django.conf import settings
from django.core.cache import cache
from django.utils import timezone
from django.db import transaction
from django.shortcuts import get_object_or_404
from decimal import Decimal

from rest_framework.decorators import api_view, permission_classes, authentication_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.response import Response
from rest_framework import status

from .models import Ride_Request
from Bikes.models import Bikes
from Trip.models import Trip
from Bikes.pricing import calculate_price
from paddle_backend.geo_utils import calculate_distance
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync
from chat.models import ChatRoom, Message
from chat.utils import notify_user

stripe.api_key = settings.STRIPE_SECRET_KEY



def _find_nearest_bike(pickup_lat, pickup_lon):
    available_bikes = Bikes.objects.filter(is_available=True)
    if not available_bikes.exists():
        return None, None
    bikes_with_distance = [
        (bike, calculate_distance(pickup_lat, pickup_lon, bike.latitude, bike.longitude))
        for bike in available_bikes
        if bike.latitude and bike.longitude
    ]
    if not bikes_with_distance:
        return None, None
    return min(bikes_with_distance, key=lambda x: x[1])


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def estimate_price(request):
    try:
        pickup_lat = float(request.data.get('pickup_latitude', ''))
        pickup_lon = float(request.data.get('pickup_longitude', ''))
        dest_lat = float(request.data.get('destination_latitude', ''))
        dest_lon = float(request.data.get('destination_longitude', ''))
    except (ValueError, TypeError):
        return Response({'error': 'Missing or invalid coordinates'}, status=status.HTTP_400_BAD_REQUEST)

    distance_km = calculate_distance(pickup_lat, pickup_lon, dest_lat, dest_lon)
    duration_hours = distance_km / 15
    price = calculate_price(distance=distance_km, duration_hours=duration_hours)

    nearest_bike, distance_to_bike = _find_nearest_bike(pickup_lat, pickup_lon)
    if not nearest_bike:
        return Response({'error': 'No available bikes nearby'}, status=status.HTTP_404_NOT_FOUND)

    commission = Decimal(str(price)) * Decimal('0.15')
    owner_earnings = Decimal(str(price)) - commission
    valid_until = int((timezone.now() + timezone.timedelta(minutes=10)).timestamp())

    price_token = str(uuid.uuid4())
    cache.set(f"price_token_{price_token}", {
        'price': str(price),
        'distance_km': distance_km,
        'nearest_bike_id': nearest_bike.id,
    }, timeout=600)

    return Response({
        'estimated_price': round(float(price), 2),
        'price_token': price_token,
        'valid_until': valid_until,
        'price_breakdown': {
            'total_amount': str(round(float(price), 2)),
            'platform_commission': str(round(float(commission), 2)),
            'owner_earnings': str(round(float(owner_earnings), 2)),
        },
        'nearest_bike': {
            'id': nearest_bike.id,
            'name': nearest_bike.bike_name,
            'brand': nearest_bike.brand,
            'model': nearest_bike.model,
            'distance_to_bike': round(distance_to_bike, 2),
            'location': {
                'latitude': nearest_bike.latitude,
                'longitude': nearest_bike.longitude,
            },
        },
        'trip_details': {
            'distance': round(distance_km, 2),
            'estimated_duration_hours': round(duration_hours, 4),
            'estimated_duration_minutes': round(duration_hours * 60, 1),
        },
        'warning': None,
    })


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def request_ride_with_payment(request):
    pickup_lat = request.data.get('pickup_latitude')
    pickup_lon = request.data.get('pickup_longitude')
    dest_lat = request.data.get('destination_latitude')
    dest_lon = request.data.get('destination_longitude')
    payment_type = request.data.get('payment_type', 'card')
    origin_address = request.data.get('origin_address', '')
    destination_address = request.data.get('destination_address', '')

    if not all([pickup_lat, pickup_lon, dest_lat, dest_lon]):
        return Response({'error': 'Missing coordinates'}, status=status.HTTP_400_BAD_REQUEST)

    nearest_bike, distance_to_bike = _find_nearest_bike(pickup_lat, pickup_lon)
    if not nearest_bike:
        return Response({'error': 'No available bikes nearby'}, status=status.HTTP_404_NOT_FOUND)

    trip_distance = calculate_distance(pickup_lat, pickup_lon, dest_lat, dest_lon)
    duration_hours = trip_distance / 15
    estimated_price = calculate_price(distance=trip_distance, duration_hours=duration_hours)
    commission = Decimal(str(estimated_price)) * Decimal('0.15')
    owner_earnings = Decimal(str(estimated_price)) - commission

    ride_request = Ride_Request.objects.create(
        Rider=request.user.userprofile,
        Owner=nearest_bike.owner,
        bike=nearest_bike,
        pickup_latitude=pickup_lat,
        pickup_longitude=pickup_lon,
        destination_latitude=dest_lat,
        destination_longitude=dest_lon,
        distance=round(trip_distance, 2),
        price=round(estimated_price, 2),
        payment_type=payment_type,
        origin_address=origin_address,
        destination_address=destination_address,
        status='pending',
    )

    if getattr(settings, 'SKIP_PAYMENTS', False):
        ride_request.payment_intent_id = 'pi_demo'
        ride_request.save(update_fields=['payment_intent_id'])
    else:
        payment_intent = None
        try:
            payment_intent = stripe.PaymentIntent.create(
                amount=int(float(estimated_price) * 100),
                currency='usd',
                metadata={
                    'ride_request_id': ride_request.id,
                    'temp_request_id': str(ride_request.temp_request_id),
                },
                idempotency_key=f"ride_req_{ride_request.temp_request_id}",
            )
            ride_request.payment_intent_id = payment_intent.id
            ride_request.save(update_fields=['payment_intent_id'])
        except Exception as e:
            ride_request.delete()
            if payment_intent is not None:
                try:
                    stripe.PaymentIntent.cancel(payment_intent.id)
                except Exception:
                    pass
            return Response({'error': f'Payment setup failed: {str(e)}'}, status=status.HTTP_400_BAD_REQUEST)

    notify_user(
        nearest_bike.owner.user.id,
        'New Ride Request',
        f'New ride request worth ${round(float(owner_earnings), 2)}',
        {
            'payment_completed': True,
            'notification_type': 'ride_request',
            'request_id': ride_request.id,
            'temp_request_id': str(ride_request.temp_request_id),
            'target_owner_username': nearest_bike.owner.user.username,
            'rider_username': request.user.username,
            'bike_name': nearest_bike.bike_name,
            'your_earnings': f'${round(float(owner_earnings), 2)}',
            'trip_distance': str(round(trip_distance, 2)),
            'expires_in_minutes': 10,
            'pickup': f"{pickup_lat}, {pickup_lon}",
            'price': str(round(estimated_price, 2)),
        }
    )

    expires_at = (timezone.now() + timezone.timedelta(minutes=10)).isoformat()

    return Response({
        'success': True,
        'temp_request_id': str(ride_request.temp_request_id),
        'payment': {
            'client_secret': payment_intent.client_secret,
            'payment_intent_id': payment_intent.id,
            'customer_id': '',
            'total_amount': str(round(estimated_price, 2)),
            'owner_earnings': str(round(float(owner_earnings), 2)),
            'platform_commission': str(round(float(commission), 2)),
        },
        'message': 'Ride request created successfully',
        'expires_at': expires_at,
    }, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_request_status(request, temp_request_id):
    try:
        ride_request = Ride_Request.objects.get(temp_request_id=temp_request_id)
    except (Ride_Request.DoesNotExist, ValueError):
        return Response({'error': 'Request not found'}, status=status.HTTP_404_NOT_FOUND)

    trip_id = None
    if ride_request.status == 'accepted':
        t = Trip.objects.filter(
            renter=ride_request.Rider, bike=ride_request.bike
        ).order_by('-trip_date').first()
        if t:
            trip_id = t.id

    return Response({
        'status': ride_request.status,
        'temp_request_id': str(ride_request.temp_request_id),
        'bike_name': ride_request.bike.bike_name if ride_request.bike else None,
        'owner_id': ride_request.Owner.user.id if ride_request.Owner else None,
        'price': float(ride_request.price) if ride_request.price else None,
        'requested_time': ride_request.requested_time.isoformat(),
        'trip_id': trip_id,
    })


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def cancel_ride_request_by_temp_id(request, temp_request_id):
    try:
        ride_request = Ride_Request.objects.get(
            temp_request_id=temp_request_id,
            Rider=request.user.userprofile
        )
    except (Ride_Request.DoesNotExist, ValueError):
        return Response({'error': 'Request not found'}, status=status.HTTP_404_NOT_FOUND)

    if ride_request.status not in ('pending',):
        return Response({'error': 'Cannot cancel this request'}, status=status.HTTP_400_BAD_REQUEST)

    ride_request.status = 'cancelled'
    ride_request.save(update_fields=['status'])

    if ride_request.Owner:
        notify_user(
            ride_request.Owner.user.id,
            'Ride Request Cancelled',
            'The rider cancelled their request',
            {
                'notification_type': 'ride_cancelled',
                'action': 'cancelled_by_rider',
                'temp_request_id': str(ride_request.temp_request_id),
                'target_owner_username': ride_request.Owner.user.username,
                'rider_username': ride_request.Rider.user.username,
                'bike_name': ride_request.bike.bike_name if ride_request.bike else 'Unknown',
                'note': 'Your bike is now available for other requests',
            }
        )

    bike_name = ride_request.bike.bike_name if ride_request.bike else 'Unknown'
    owner_username = ride_request.Owner.user.username if ride_request.Owner else 'Unknown'

    return Response({
        'success': True,
        'message': 'Ride request cancelled successfully',
        'details': {
            'cancelled_request': {
                'bike_name': bike_name,
                'owner_username': owner_username,
                'cancelled_at': timezone.now().isoformat(),
            },
            'bike_status': {
                'name': bike_name,
                'status': 'available',
                'note': 'Bike is now available for other riders',
            },
            'owner_notified': bool(ride_request.Owner),
            'next_step': 'You can search for another bike nearby',
        }
    })


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def request_ride(request):
    pickup_latitude = request.data.get('pickup_latitude')
    pickup_longitude = request.data.get('pickup_longitude')
    destination_latitude = request.data.get('destination_latitude')
    destination_longitude = request.data.get('destination_longitude')
    payment_type = request.data.get('payment_type', 'card')
    origin_address = request.data.get('origin_address', '')
    destination_address = request.data.get('destination_address', '')

    trip_distance = calculate_distance(
        pickup_latitude, pickup_longitude,
        destination_latitude, destination_longitude
    )

    nearest_bike, distance_to_bike = _find_nearest_bike(pickup_latitude, pickup_longitude)
    if not nearest_bike:
        return Response({'error': 'No available bikes nearby'}, status=status.HTTP_404_NOT_FOUND)

    estimated_price = calculate_price(distance=trip_distance, duration_hours=trip_distance/15)

    ride_request = Ride_Request.objects.create(
        Rider=request.user.userprofile,
        bike=nearest_bike,
        Owner=nearest_bike.owner,
        pickup_latitude=pickup_latitude,
        pickup_longitude=pickup_longitude,
        destination_latitude=destination_latitude,
        destination_longitude=destination_longitude,
        distance=trip_distance,
        price=estimated_price,
        payment_type=payment_type,
        origin_address=origin_address,
        destination_address=destination_address,
        status='pending',
    )

    notify_user(
        nearest_bike.owner.user.id,
        'New Ride Request',
        f'New ride request worth ${estimated_price}',
        {
            'notification_type': 'ride_request',
            'request_id': ride_request.id,
            'temp_request_id': str(ride_request.temp_request_id),
            'rider_username': request.user.username,
            'bike_name': nearest_bike.bike_name,
            'pickup': f"{pickup_latitude}, {pickup_longitude}",
            'price': str(estimated_price),
        }
    )

    return Response({
        'preferred_bike_unavailable': False,
        'temp_request_id': str(ride_request.temp_request_id),
        'message': 'Ride request submitted. Waiting for owner to accept.',
    }, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def accept_ride_request(request, temp_request_id):
    try:
        with transaction.atomic():
            ride_request = Ride_Request.objects.select_for_update().get(
                temp_request_id=temp_request_id, status='pending'
            )
            # Lock the bike row to prevent double-booking from concurrent accepts
            bike = Bikes.objects.select_for_update().get(pk=ride_request.bike_id)

            if not bike.is_available:
                return Response({'error': 'Bike is no longer available'}, status=status.HTTP_409_CONFLICT)

            if bike.owner is None or bike.owner.user != request.user:
                return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)

            trip = Trip.objects.create(
                renter=ride_request.Rider,
                bike_owner=bike.owner,
                bike=bike,
                origin_latitude=ride_request.pickup_latitude,
                origin_longitude=ride_request.pickup_longitude,
                destination_latitude=ride_request.destination_latitude,
                destination_longitude=ride_request.destination_longitude,
                origin_address=ride_request.origin_address or '',
                destination_address=ride_request.destination_address or '',
                distance=ride_request.distance,
                price=ride_request.price,
                payment_type=ride_request.payment_type,
                status='waiting'
            )

            bike.is_available = False
            bike.bike_status = 'reserved'
            bike.save(update_fields=['is_available', 'bike_status'])

            chat_room = ChatRoom.objects.create(trip=trip)
            if bike.hardware:
                unlock_code = bike.hardware.generate_unlock_code()
                Message.objects.create(
                    chat_room=chat_room,
                    sender=request.user,
                    content=f"Your bike unlock code is: {unlock_code}\nValid for 5 minutes."
                )
            else:
                Message.objects.create(
                    chat_room=chat_room,
                    sender=request.user,
                    content="Your ride has been accepted. Please approach the bike."
                )

            ride_request.status = 'accepted'
            ride_request.is_accepted = True
            ride_request.save()

        notify_user(
            ride_request.Rider.user.id,
            'Ride Request Accepted',
            'Your ride request has been accepted!',
            {
                'trip_id': trip.id,
                'chat_room_id': chat_room.id,
                'bike_location': {
                    'latitude': bike.latitude,
                    'longitude': bike.longitude,
                    'name': bike.bike_name,
                    'bike_id': bike.id,
                },
                'status': 'accepted',
                'trip_status': 'waiting',
                'owner_username': request.user.username,
                'owner_id': request.user.id,
                'next_step': 'Head to the bike location',
                'instructions': 'Unlock code sent in chat. Valid for 5 minutes.',
            }
        )
        notify_user(
            request.user.id,
            'Trip Started',
            f'Trip with {ride_request.Rider.user.username} is now active',
            {
                'trip_id': trip.id,
                'chat_room_id': chat_room.id,
                'rider_username': ride_request.Rider.user.username,
                'rider_id': ride_request.Rider.user.id,
                'bike_name': bike.bike_name,
                'trip_status': 'waiting',
            }
        )

        return Response({
            'message': 'Ride request accepted',
            'trip_id': trip.id,
            'chat_room_id': chat_room.id
        })

    except Ride_Request.DoesNotExist:
        return Response({'error': 'Ride request not found'}, status=status.HTTP_404_NOT_FOUND)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_owner_pending_requests(request):
    from Owner.models import OwnerProfile
    owner = get_object_or_404(OwnerProfile, user=request.user)
    pending = Ride_Request.objects.filter(
        Owner=owner,
        status='pending'
    ).select_related('Rider__user', 'bike').order_by('-requested_time')

    data = []
    for req in pending:
        data.append({
            'temp_request_id': str(req.temp_request_id),
            'rider_username': req.Rider.user.username,
            'rider_id': req.Rider.user.id,
            'bike_name': req.bike.bike_name if req.bike else '',
            'bike_id': req.bike.id if req.bike else None,
            'pickup_latitude': req.pickup_latitude,
            'pickup_longitude': req.pickup_longitude,
            'destination_latitude': req.destination_latitude,
            'destination_longitude': req.destination_longitude,
            'price': str(req.price),
            'distance': str(req.distance) if req.distance else None,
            'payment_type': req.payment_type,
            'requested_time': req.requested_time.isoformat(),
        })

    return Response({'pending_requests': data, 'count': len(data)})


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def decline_ride_request(request, temp_request_id):
    try:
        ride_request = Ride_Request.objects.get(temp_request_id=temp_request_id, status='pending')

        if not ride_request.bike or ride_request.bike.owner.user != request.user:
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)

        ride_request.status = 'declined'
        ride_request.save()

        bike = ride_request.bike
        owner = ride_request.Owner
        notify_user(
            ride_request.Rider.user.id,
            'Ride Request Declined',
            'Your ride request has been declined',
            {
                'status': 'declined',
                'request_id': ride_request.id,
                'temp_request_id': str(ride_request.temp_request_id),
                'owner_name': owner.user.username if owner else 'The bike owner',
                'bike_name': bike.bike_name if bike else 'the bike',
                'message': 'The bike owner declined your request. Try selecting another bike.',
            }
        )

        return Response({'message': 'Ride request declined'})

    except Ride_Request.DoesNotExist:
        return Response({'error': 'Ride request not found'}, status=status.HTTP_404_NOT_FOUND)
