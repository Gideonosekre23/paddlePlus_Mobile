import logging
from django.shortcuts import get_object_or_404
from django.conf import settings
from django.http import JsonResponse
from django.utils import timezone
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework import status
from .models import Trip
from Bikes.models import Bikes
from Bikes.pricing import calculate_price
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync
import stripe
from geopy.distance import geodesic
from decimal import Decimal
from Riderequest.models import Ride_Request
from chat.models import ChatRoom, Message
from django.contrib.auth.models import User

logger = logging.getLogger(__name__)
stripe.api_key = settings.STRIPE_SECRET_KEY


def calculate_distance_adjustment(estimated_distance, actual_distance):
    """
    Calculate if extra charge is needed based on distance variance
    Auto-charge any amount without asking permission
    Returns: (extra_charge_amount, adjustment_type, explanation)
    """
    
    if actual_distance <= estimated_distance:
        return 0, "no_adjustment", "Actual distance less than or equal to estimated"
    
    distance_difference = actual_distance - estimated_distance
    variance_percentage = (distance_difference / estimated_distance) * 100

    within_percentage = variance_percentage <= 15
    within_fixed_distance = distance_difference <= 1.0
    
    if within_percentage or within_fixed_distance:
        return 0, "within_threshold", f"Within acceptable range: +{variance_percentage:.1f}% or +{distance_difference:.1f}km"
    
    price_per_km = 1.5 
    extra_charge = distance_difference * price_per_km
    
    if extra_charge < 0.50:
        return 0, "difference_too_small", "Extra charge less than €0.50"
    
    return extra_charge, "auto_charge", f"Auto-charging €{extra_charge:.2f} for additional +{distance_difference:.1f}km"


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def end_trip(request, trip_id):
    if not hasattr(request.user, 'userprofile'):
        return JsonResponse({'error': 'Rider profile not found'}, status=403)
    trip = get_object_or_404(Trip, pk=trip_id, renter=request.user.userprofile)
    
    if trip.status not in ['started', 'ontrip']:
        return JsonResponse({'error': 'Trip cannot be ended'}, status=400)
    
    try:
        trip.end_time = timezone.now()
        duration_hours = (trip.end_time - trip.start_time).total_seconds() / 3600
        
        # Calculate actual distance
        if trip.distance is None:
            origin_coords = (trip.origin_latitude, trip.origin_longitude)
            destination_coords = (trip.destination_latitude, trip.destination_longitude)
            trip.distance = geodesic(origin_coords, destination_coords).kilometers
        
        actual_distance = float(trip.distance)
        
        
        try:
            ride_request = Ride_Request.objects.get(
                Rider=trip.renter,
                bike=trip.bike,
                status='accepted'
            )
            estimated_distance = float(ride_request.distance)
            estimated_price = float(ride_request.price)
        except Ride_Request.DoesNotExist:
            
            estimated_distance = actual_distance
            estimated_price = float(trip.price)
        
        logger.debug(f"Distance check: estimated {estimated_distance}km → actual {actual_distance}km")
        
        
        extra_charge, adjustment_type, explanation = calculate_distance_adjustment(
            estimated_distance, actual_distance
        )
        
       
        final_price = estimated_price + extra_charge
        trip.price = Decimal(str(final_price))
        
        logger.debug(f"Price: €{estimated_price} + €{extra_charge} extra = €{final_price} final")
        
        rider_profile = request.user.userprofile
        if extra_charge > 0:
            try:
                stripe_customer_id = getattr(rider_profile, 'stripe_customer_id', None)
                default_payment_method = getattr(rider_profile, 'default_payment_method', None)
                if not stripe_customer_id or not default_payment_method:
                    raise stripe.error.StripeError("No payment method on file for extra charge")
                extra_payment = stripe.PaymentIntent.create(
                    amount=int(extra_charge * 100),
                    currency='eur',
                    customer=stripe_customer_id,
                    payment_method=default_payment_method,
                    confirm=True,
                    off_session=True,
                    idempotency_key=f"extra_charge_trip_{trip.id}",
                    metadata={
                        'trip_id': trip.id,
                        'type': 'distance_adjustment',
                        'estimated_distance': estimated_distance,
                        'actual_distance': actual_distance,
                        'extra_distance': actual_distance - estimated_distance,
                        'extra_charge': extra_charge,
                        'adjustment_reason': explanation
                    }
                )
                
                logger.info(f"Extra charge €{extra_charge} confirmed for rider {request.user.username}")
                
            except stripe.error.StripeError as e:
                failed_amount = extra_charge
                extra_charge = 0
                final_price = estimated_price
                trip.price = Decimal(str(final_price))
                adjustment_type = 'charge_failed'
                explanation = f"Extra distance charge of €{failed_amount:.2f} failed — payment method issue."
        
        trip.process_payment()
        trip.complete_trip()

        
        bike_owner = trip.bike_owner
        bike_owner.total_earnings += trip.owner_payout
        bike_owner.save()

        bike = trip.bike
        bike.total_earnings += trip.owner_payout
        bike.is_available = True
        bike.bike_status = 'available'
        bike.save()

        channel_layer = get_channel_layer()
        
      
        rider_message = f'Trip completed. Total cost: €{final_price:.2f}'
        if extra_charge > 0:
            rider_message += f' (includes €{extra_charge:.2f} for additional {actual_distance - estimated_distance:.1f}km)'
        
        async_to_sync(channel_layer.group_send)(
            f'notifications_{trip.renter.user.id}',
            {
                'type': 'send_notification',
                'title': 'Trip Completed ✅',
                'message': rider_message,
                'data': {
                    'trip_id': trip.id,
                    'duration_hours': round(duration_hours, 2),
                    'estimated_distance_km': estimated_distance,
                    'actual_distance_km': actual_distance,
                    'distance_difference': round(actual_distance - estimated_distance, 2),
                    'estimated_price': estimated_price,
                    'extra_charge': extra_charge,
                    'final_price': float(final_price),
                    'distance_adjustment': {
                        'type': adjustment_type,
                        'explanation': explanation,
                        'extra_charge': extra_charge,
                        'charged_immediately': extra_charge > 0
                    },
                    'payment_status': 'completed',
                    'bike_name': bike.bike_name
                }
            }
        )

        # Notify owner
        owner_message = f'€{trip.owner_payout:.2f} added to your earnings from {trip.renter.user.username}\'s trip'
        if extra_charge > 0:
            owner_message += f' (trip was {actual_distance - estimated_distance:.1f}km longer - extra €{extra_charge:.2f} charged)'
        
        async_to_sync(channel_layer.group_send)(
                f'notifications_{trip.bike_owner.user.id}',
                {
                    'type': 'send_notification',
                    'title': 'Trip Completed - Earnings Added! 💰',
                    'message': owner_message,
                    'data': {
                        'notification_type': 'earnings_updated', 
                        'new_total_earnings': float(bike_owner.total_earnings),  
                        'trip_earnings': float(trip.owner_payout), 
                        'trip_id': trip.id,
                        'earnings_added': float(trip.owner_payout),
                        'owner_total_earnings': float(bike_owner.total_earnings),
                        'bike_total_earnings': float(bike.total_earnings),
                        'rider_username': trip.renter.user.username,
                        'bike_name': bike.bike_name,
                        'trip_duration': f"{duration_hours:.1f} hours",
                        'estimated_distance': f"{estimated_distance:.2f} km",
                        'actual_distance': f"{actual_distance:.2f} km",
                        'distance_adjustment': {
                            'extra_charge': extra_charge,
                            'explanation': explanation,
                            'distance_difference': round(actual_distance - estimated_distance, 2)
                        }
                    }
                }
            )
        
        return JsonResponse({
            'message': 'Trip completed successfully',
            'trip_details': {
                'duration_hours': round(duration_hours, 2),
                'estimated_distance_km': estimated_distance,
                'actual_distance_km': actual_distance,
                'distance_difference_km': round(actual_distance - estimated_distance, 2),
                'estimated_price': estimated_price,
                'extra_charge': extra_charge,
                'final_price': float(final_price),
                'commission': float(trip.commission_amount),
                'owner_payout': float(trip.owner_payout)
            },
            'distance_adjustment': {
                'type': adjustment_type,
                'explanation': explanation,
                'extra_charge_applied': extra_charge,
                'charged_immediately': extra_charge > 0
            },
            'earnings_update': {
                'owner_total_earnings': float(bike_owner.total_earnings),
                'bike_total_earnings': float(bike.total_earnings),
                'earnings_added': float(trip.owner_payout)
            },
            'bike_status': {
                'is_available': bike.is_available,
                'status': bike.bike_status,
                'name': bike.bike_name
            }
        })
        
    except stripe.error.StripeError as e:
        logger.error(f"Payment error ending trip {trip_id}: {e}")
        return JsonResponse({'error': 'Payment failed', 'message': 'A payment error occurred. Please contact support.'}, status=400)

    except Exception as e:
        logger.exception(f"Error ending trip {trip_id}")
        return JsonResponse({'error': 'Internal server error', 'message': 'Failed to end trip. Please try again.'}, status=500)



@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def start_trip(request, trip_id):
    if not hasattr(request.user, 'userprofile'):
        return JsonResponse({'error': 'Rider profile not found'}, status=403)
    trip = get_object_or_404(Trip, pk=trip_id, renter=request.user.userprofile)

    if trip.status != 'waiting':
        return JsonResponse({'error': 'Trip cannot be started'}, status=400)

    trip.status = 'started'
    trip.start_time = timezone.now()
    trip.save()

    bike = trip.bike
    bike.is_available = False
    bike.bike_status = 'rented'
    bike.save()
    
    # generate and send code to trip chat room 
    try:
        if trip.bike and trip.bike.hardware:
            unlock_code = trip.bike.hardware.generate_unlock_code()
            if unlock_code:
                send_unlock_code_to_chat(trip, unlock_code)
    except Exception as e:
        logger.warning(f"Failed to send unlock code to chat for trip {trip_id}: {e}")



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

def send_unlock_code_to_chat(trip, unlock_code):
    try:
        chat_room = ChatRoom.objects.get(trip=trip)
        Message.objects.create(
            chat_room=chat_room,
            sender=trip.bike_owner.user,
            content=f"🔓 Unlock Code: {unlock_code}\n\n✅ Trip started! Enter this code on the bike to unlock.\n⏰ Valid for 5 minutes."
        )
        return True
    except ChatRoom.DoesNotExist:
        logger.warning(f"No chat room for trip {trip.id} when sending unlock code")
        return False
    except Exception as e:
        logger.error(f"Error sending unlock code for trip {trip.id}: {e}")
        return False




@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def begin_trip(request, trip_id):
    """Rider confirms bike is unlocked — transitions started → ontrip."""
    if not hasattr(request.user, 'userprofile'):
        return JsonResponse({'error': 'Rider profile not found'}, status=403)
    trip = get_object_or_404(Trip, pk=trip_id, renter=request.user.userprofile)

    if trip.status != 'started':
        return JsonResponse({'error': 'Trip must be in started state to begin riding'}, status=400)

    trip.status = 'ontrip'
    trip.save(update_fields=['status'])

    channel_layer = get_channel_layer()
    for user_id in [trip.renter.user.id, trip.bike_owner.user.id]:
        async_to_sync(channel_layer.group_send)(
            f'notifications_{user_id}',
            {
                'type': 'send_notification',
                'title': 'Ride In Progress',
                'message': 'The bike has been unlocked and the ride is underway.',
                'data': {'trip_id': trip.id, 'status': 'ontrip'}
            }
        )

    return JsonResponse({'message': 'Ride is now in progress', 'status': 'ontrip'})


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def cancel_trip(request, trip_id):
    if not hasattr(request.user, 'userprofile'):
        return JsonResponse({'error': 'Rider profile not found'}, status=403)
    trip = get_object_or_404(Trip, pk=trip_id, renter=request.user.userprofile)
    
    if trip.status in ['completed', 'ontrip', 'canceled']:
        return JsonResponse({'error': 'Trip cannot be canceled at this stage'}, status=400)

    # Refund if trip was paid but never started (waiting = rider hasn't reached bike yet)
    refund_status = 'not_applicable'
    if trip.status == 'waiting' and trip.payment_intent_id and not trip.payment_intent_id.startswith('sim_'):
        try:
            stripe.Refund.create(payment_intent=trip.payment_intent_id)
            refund_status = 'refunded'
        except stripe.error.StripeError as e:
            refund_status = 'refund_failed'
            logger.error(f"Refund failed for trip {trip.id}: {e}")

    trip.status = 'canceled'
    trip.trip_canceled = True
    trip.save()

    bike = trip.bike
    bike.is_available = True
    bike.bike_status = 'available'
    bike.save()
    

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
                    'status': 'canceled',
                    'refund_status': refund_status,
                }
            }
        )

    return JsonResponse({'message': 'Trip canceled successfully', 'refund_status': refund_status})


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_user_trips(request):
    try:
        if not hasattr(request.user, 'userprofile'):
            return JsonResponse({'success': False, 'error': 'Rider profile not found'}, status=403)
        trips = Trip.objects.filter(
            renter=request.user.userprofile
        ).select_related('bike', 'bike__owner', 'bike_owner').order_by('-trip_date')
        
        trips_data = []
        
        for trip in trips:
          
            bike_info = {
                'name': trip.bike.bike_name if trip.bike else "Unknown bike",
                'brand': trip.bike.brand if trip.bike else "Unknown brand",
                'model': trip.bike.model if trip.bike else "Unknown model",
                'color': trip.bike.color if trip.bike else "Unknown color",
                'id': trip.bike.id if trip.bike else None
            }
            
            # 🔧 OWNER INFO:
            owner_info = {
                'username': trip.bike_owner.user.username if trip.bike_owner else "Unknown owner",
                'id': trip.bike_owner.user.id if trip.bike_owner else None
            }
            
            trip_data = {
                'id': trip.id,
                'bike_name': bike_info['name'],  
                'bike_info': bike_info,
                'owner_info': owner_info,
                'start_location': {
                    'address': trip.origin_address or "Unknown location",
                    'latitude': trip.origin_latitude,
                    'longitude': trip.origin_longitude
                },
                'end_location': {
                    'address': trip.destination_address or "Unknown location",
                    'latitude': trip.destination_latitude,
                    'longitude': trip.destination_longitude
                },
                'date': trip.trip_date.isoformat() if trip.trip_date else None,
                'status': trip.status,
                'price': float(trip.price) if trip.price else None,
                'distance': float(trip.distance) if trip.distance else None,
                'payment_status': trip.payment_status,
                'created_at': trip.trip_date.isoformat() if trip.trip_date else None,
                'rider_rating': trip.rider_rating,
                'rider_review': trip.rider_review,
                'owner_rating': trip.owner_rating,
                'owner_review': trip.owner_review,
            }
            
            trips_data.append(trip_data)
        
        return JsonResponse({
            'success': True,
            'trips': trips_data,
            'total_trips': len(trips_data),
            'user': request.user.username
        })
        
    except Exception as e:
        logger.exception("Error in get_user_trips")
        return JsonResponse({'success': False, 'error': 'Internal server error'}, status=500)



@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_owner_trips(request):
    try:
        if not hasattr(request.user, 'owner_profile'):
            return JsonResponse({'success': False, 'error': 'Owner profile not found'}, status=403)
        trips = Trip.objects.filter(
            bike_owner=request.user.owner_profile
        ).select_related('bike', 'renter__user').order_by('-trip_date')
        
        trips_data = []
        
        for trip in trips:
            trip_data = {
                'id': trip.id,
                'bike_name': trip.bike.bike_name if trip.bike else "Unknown bike",
                'bike_info': {
                    'id': trip.bike.id if trip.bike else None,
                    'brand': trip.bike.brand if trip.bike else "Unknown brand",
                    'model': trip.bike.model if trip.bike else "Unknown model",
                    'color': trip.bike.color if trip.bike else "Unknown color"
                } if trip.bike else None,
                'start_location': {
                    'address': trip.origin_address or "Unknown location",
                    'latitude': trip.origin_latitude,
                    'longitude': trip.origin_longitude
                },
                'end_location': {
                    'address': trip.destination_address or "Unknown location",
                    'latitude': trip.destination_latitude,
                    'longitude': trip.destination_longitude
                },
                'date': trip.trip_date.isoformat() if trip.trip_date else None,
                'status': trip.status,
                'price': float(trip.price) if trip.price else None,
                'owner_payout': float(trip.owner_payout) if trip.owner_payout else None,
                'distance': float(trip.distance) if trip.distance else None,
                'payment_status': trip.payment_status,
                'rider_rating': trip.rider_rating,
                'rider_review': trip.rider_review,
                'owner_rating': trip.owner_rating,
                'owner_review': trip.owner_review,
                'renter': {
                    'username': trip.renter.user.username,
                    'id': trip.renter.user.id,
                    'phone': trip.renter.phone_number if hasattr(trip.renter, 'phone_number') else None
                } if trip.renter else None
            }
            
            trips_data.append(trip_data)
        
        return JsonResponse({
            'success': True,
            'trips': trips_data,
            'total_trips': len(trips_data),
            'owner': {
                'username': request.user.username,
                'id': request.user.id,
                'total_earnings': float(request.user.owner_profile.total_earnings) if hasattr(request.user, 'owner_profile') else None,
                'verification_status': request.user.owner_profile.verification_status if hasattr(request.user, 'owner_profile') else None,
            }
        })
        
    except Exception as e:
        logger.exception("Error in get_owner_trips")
        return JsonResponse({'success': False, 'error': 'Internal server error'}, status=500)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_active_trip(request):
    """Return the rider's current active trip (waiting / started / ontrip), if any."""
    if not hasattr(request.user, 'userprofile'):
        return Response({'error': 'Rider profile not found'}, status=status.HTTP_404_NOT_FOUND)

    trip = Trip.objects.filter(
        renter=request.user.userprofile,
        status__in=['waiting', 'started', 'ontrip']
    ).select_related('bike', 'bike_owner__user', 'bike__hardware').order_by('-trip_date').first()

    if not trip:
        return Response({'active_trip': None}, status=status.HTTP_200_OK)

    chat_room_id = None
    try:
        chat_room_id = trip.chat_room.id
    except Exception:
        pass

    return Response({
        'active_trip': {
            'id': trip.id,
            'status': trip.status,
            'trip_date': trip.trip_date.isoformat(),
            'start_time': trip.start_time.isoformat() if trip.start_time else None,
            'bike': {
                'id': trip.bike.id,
                'name': trip.bike.bike_name,
                'brand': trip.bike.brand,
                'model': trip.bike.model,
                'latitude': trip.bike.latitude,
                'longitude': trip.bike.longitude,
                'bike_image': trip.bike.bike_image.url if trip.bike.bike_image else None,
            } if trip.bike else None,
            'owner': {
                'username': trip.bike_owner.user.username,
                'id': trip.bike_owner.user.id,
            } if trip.bike_owner else None,
            'origin': {
                'latitude': trip.origin_latitude,
                'longitude': trip.origin_longitude,
                'address': trip.origin_address,
            },
            'destination': {
                'latitude': trip.destination_latitude,
                'longitude': trip.destination_longitude,
                'address': trip.destination_address,
            },
            'price': float(trip.price) if trip.price else None,
            'distance': float(trip.distance) if trip.distance else None,
            'payment_status': trip.payment_status,
            'payment_intent_id': trip.payment_intent_id,
            'chat_room_id': chat_room_id,
        }
    }, status=status.HTTP_200_OK)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def rate_trip(request, trip_id):
    """Rider submits a rating (1-5) and optional review for a completed trip."""
    if not hasattr(request.user, 'userprofile'):
        return Response({'error': 'Rider profile not found'}, status=status.HTTP_404_NOT_FOUND)

    trip = get_object_or_404(Trip, pk=trip_id, renter=request.user.userprofile)

    if trip.status != 'completed':
        return Response({'error': 'Can only rate completed trips'}, status=status.HTTP_400_BAD_REQUEST)

    if trip.rider_rating is not None:
        return Response({'error': 'Trip already rated'}, status=status.HTTP_400_BAD_REQUEST)

    rating = request.data.get('rating')
    review = request.data.get('review', '')

    try:
        rating = int(rating)
        if not 1 <= rating <= 5:
            raise ValueError
    except (TypeError, ValueError):
        return Response({'error': 'Rating must be an integer between 1 and 5'}, status=status.HTTP_400_BAD_REQUEST)

    trip.rider_rating = rating
    trip.rider_review = review
    trip.save(update_fields=['rider_rating', 'rider_review'])

    bike = trip.bike
    if bike:
        prev_count = bike.rating_count
        prev_rating = float(bike.rating)
        new_count = prev_count + 1
        new_rating = ((prev_rating * prev_count) + rating) / new_count
        bike.rating = round(new_rating, 2)
        bike.rating_count = new_count
        bike.save(update_fields=['rating', 'rating_count'])

        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f'notifications_{trip.bike_owner.user.id}',
            {
                'type': 'send_notification',
                'title': 'New Trip Rating',
                'message': f'{request.user.username} rated their trip {rating}/5',
                'data': {
                    'trip_id': trip.id,
                    'rating': rating,
                    'review': review,
                    'bike_id': bike.id,
                    'bike_name': bike.bike_name,
                    'new_bike_rating': float(bike.rating),
                }
            }
        )

    return Response({
        'success': True,
        'rating': rating,
        'review': review,
        'bike_new_rating': float(bike.rating) if bike else None,
    }, status=status.HTTP_200_OK)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def rate_rider(request, trip_id):
    """Owner submits a rating (1-5) for the rider on a completed trip."""
    if not hasattr(request.user, 'owner_profile'):
        return Response({'error': 'Owner profile not found'}, status=status.HTTP_404_NOT_FOUND)

    trip = get_object_or_404(Trip, pk=trip_id, bike_owner=request.user.owner_profile)

    if trip.status != 'completed':
        return Response({'error': 'Can only rate completed trips'}, status=status.HTTP_400_BAD_REQUEST)

    if trip.owner_rating is not None:
        return Response({'error': 'Rider already rated for this trip'}, status=status.HTTP_400_BAD_REQUEST)

    rating = request.data.get('rating')
    review = request.data.get('review', '')

    try:
        rating = int(rating)
        if not 1 <= rating <= 5:
            raise ValueError
    except (TypeError, ValueError):
        return Response({'error': 'Rating must be an integer between 1 and 5'}, status=status.HTTP_400_BAD_REQUEST)

    trip.owner_rating = rating
    trip.owner_review = review
    trip.save(update_fields=['owner_rating', 'owner_review'])

    # Update rolling average on rider's profile
    rider_profile = trip.renter
    prev_count = rider_profile.rider_rating_count
    prev_rating = float(rider_profile.rider_rating)
    new_count = prev_count + 1
    new_rating = ((prev_rating * prev_count) + rating) / new_count
    rider_profile.rider_rating = round(new_rating, 2)
    rider_profile.rider_rating_count = new_count
    rider_profile.save(update_fields=['rider_rating', 'rider_rating_count'])

    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        f'notifications_{rider_profile.user.id}',
        {
            'type': 'send_notification',
            'title': 'New Rating',
            'message': f'{request.user.username} rated you {rating}/5',
            'data': {
                'trip_id': trip.id,
                'rating': rating,
                'review': review,
                'new_rider_rating': float(rider_profile.rider_rating),
            }
        }
    )

    return Response({
        'success': True,
        'rating': rating,
        'review': review,
        'rider_new_rating': float(rider_profile.rider_rating),
    }, status=status.HTTP_200_OK)
