import logging
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.response import Response
from rest_framework import status
from datetime import timedelta
import stripe
import uuid
from django.conf import settings
from django.utils import timezone
from datetime import datetime
from .models import Ride_Request
from Rider.models import UserProfile
from Bikes.models import Bikes
from Trip.models import Trip
from chat.models import ChatRoom, Message
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync
import hashlib
import json
from django.db import transaction
from django.core.cache import cache
import time

from Bikes.pricing import calculate_distance, get_price_estimate

logger = logging.getLogger(__name__)
stripe.api_key = settings.STRIPE_SECRET_KEY


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_request_status(request, temp_request_id):
    """Rider polls the status of their pending ride request."""
    cached = cache.get(f"pending_request_{temp_request_id}")
    if not cached:
        return Response({
            'status': 'not_found',
            'message': 'Request expired, accepted, or does not exist.'
        }, status=status.HTTP_404_NOT_FOUND)

    return Response({
        'status': cached.get('status', 'pending_cache'),
        'temp_request_id': temp_request_id,
        'bike_name': cached.get('bike_name'),
        'owner_id': cached.get('owner_id'),
        'price': cached.get('price'),
        'requested_time': cached.get('requested_time'),
    }, status=status.HTTP_200_OK)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_owner_pending_requests(request):
    """Owner retrieves all pending ride requests for their bikes (cache-backed fallback)."""
    try:
        from Owner.models import OwnerProfile
        owner = OwnerProfile.objects.get(user=request.user)
    except Exception:
        return Response({'error': 'Owner profile not found'}, status=status.HTTP_404_NOT_FOUND)

    bikes = Bikes.objects.filter(owner=owner).values_list('id', flat=True)
    pending = []
    for bike_id in bikes:
        data = cache.get(f"pending_request_bike_{bike_id}")
        if data:
            pending.append({
                'temp_request_id': data.get('temp_id'),
                'bike_id': data.get('bike_id'),
                'bike_name': data.get('bike_name'),
                'rider_username': data.get('rider_username'),
                'price': data.get('price'),
                'distance': data.get('distance'),
                'pickup_latitude': data.get('pickup_latitude'),
                'pickup_longitude': data.get('pickup_longitude'),
                'destination_address': data.get('destination_address'),
                'origin_address': data.get('origin_address'),
                'requested_time': data.get('requested_time'),
                'owner_earnings': data.get('owner_earnings'),
            })

    return Response({
        'pending_requests': pending,
        'count': len(pending),
    }, status=status.HTTP_200_OK)


def unlock_bike(bike_id, rider_id):
    lock_key = f"bike_lock_{bike_id}"
    locked_by = cache.get(lock_key)
    if locked_by == rider_id:
        cache.delete(lock_key)



@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def estimate_price(request):
    """Estimate price with validation token to prevent price manipulation"""
    pickup_latitude = request.data.get('pickup_latitude')
    pickup_longitude = request.data.get('pickup_longitude')
    destination_latitude = request.data.get('destination_latitude')
    destination_longitude = request.data.get('destination_longitude')

    if not all([pickup_latitude, pickup_longitude, destination_latitude, destination_longitude]):
        return Response({
            'error': 'Missing coordinates',
            'required': ['pickup_latitude', 'pickup_longitude', 'destination_latitude', 'destination_longitude']
        }, status=status.HTTP_400_BAD_REQUEST)

    # Rate limit: max 10 estimates per minute per user
    rate_key = f"estimate_rate_{request.user.id}"
    request_count = cache.get(rate_key, 0)
    if request_count >= 10:
        return Response({'error': 'Too many requests. Please wait before requesting another estimate.'}, status=status.HTTP_429_TOO_MANY_REQUESTS)
    cache.set(rate_key, request_count + 1, timeout=60)

    try:
        rider_profile = UserProfile.objects.get(user=request.user)
    except UserProfile.DoesNotExist:
        return Response({'error': 'Rider profile not found.'}, status=status.HTTP_404_NOT_FOUND)
    
    # ✅ USE THE IMPORTED FUNCTION
    nearest_bike, distance_to_bike, estimated_price = get_price_estimate(
        pickup_latitude, pickup_longitude, destination_latitude, destination_longitude, rider_profile
    )

    if nearest_bike is None:
        return Response({
            'error': 'No available bikes nearby',
            'message': 'All bikes in your area are currently in use. Please try again later.'
        }, status=status.HTTP_404_NOT_FOUND)

    
    trip_distance = calculate_distance(pickup_latitude, pickup_longitude, destination_latitude, destination_longitude)
    
    price_data = {
        'bike_id': nearest_bike.id,
        'pickup_lat': pickup_latitude,
        'pickup_lng': pickup_longitude,
        'dest_lat': destination_latitude,
        'dest_lng': destination_longitude,
        'price': estimated_price,
        'timestamp': int(time.time()),
        'rider_id': rider_profile.id
    }
    
    price_token = hashlib.sha256(
        json.dumps(price_data, sort_keys=True).encode() +
        settings.SECRET_KEY.encode()
    ).hexdigest()
    
    cache_key = f"price_estimate_{rider_profile.id}_{price_token}"
    cache.set(cache_key, price_data, timeout=600)

    PLATFORM_COMMISSION_RATE = float(Trip.COMMISSION_RATE)
    platform_commission = estimated_price * PLATFORM_COMMISSION_RATE
    owner_earnings = estimated_price - platform_commission

    return Response({
        'estimated_price': float(estimated_price),
        'price_token': price_token,
        'valid_until': int(time.time()) + 600,
        'price_breakdown': {
            'total_amount': f"€{estimated_price:.2f}",
            'platform_commission': f"€{platform_commission:.2f}",
            'owner_earnings': f"€{owner_earnings:.2f}"
        },
        'nearest_bike': {
            'id': nearest_bike.id,
            'name': nearest_bike.bike_name,
            'brand': nearest_bike.brand,
            'model': nearest_bike.model,
            'distance_to_bike': round(distance_to_bike, 2),
            'location': {
                'latitude': float(nearest_bike.latitude),
                'longitude': float(nearest_bike.longitude)
            }
        },
        'trip_details': {
            'distance': round(trip_distance, 2),
            'estimated_duration_hours': round(trip_distance / 30, 2),
            'estimated_duration_minutes': round((trip_distance / 30) * 60, 0)
        },
        'warning': 'Price valid for 10 minutes. Bike availability not guaranteed until payment.'
    }, status=status.HTTP_200_OK)




@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def accept_ride_request(request, temp_request_id):
    """Owner accepts cached ride request - creates DB record and trip instance"""
    try:
        cache_key = f"pending_request_{temp_request_id}"
        cached_request_data = cache.get(cache_key)

        if not cached_request_data:
            return Response({
                'error': 'Request not found or expired',
                'message': 'This ride request has expired or does not exist. The rider needs to make a new request.'
            }, status=status.HTTP_404_NOT_FOUND)

        try:
            bike = Bikes.objects.get(
                id=cached_request_data['bike_id'],
                is_active=True,
                is_available=True,
                bike_status='available'
            )
        except Bikes.DoesNotExist:
            cache.delete(cache_key)
            cache.delete(f"pending_request_bike_{cached_request_data['bike_id']}")
            cache.delete(f"pending_request_rider_{cached_request_data['rider_id']}")
            return Response({
                'error': 'Bike no longer available',
                'message': 'The bike is no longer available for rent.'
            }, status=status.HTTP_400_BAD_REQUEST)

        if bike.owner.user != request.user:
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)

        try:
            rider_profile = UserProfile.objects.get(id=cached_request_data['rider_id'])
        except UserProfile.DoesNotExist:
            return Response({'error': 'Rider profile not found'}, status=status.HTTP_404_NOT_FOUND)

        # Use real Stripe PI ID if this was a real payment; fall back to sim_ for test requests
        real_pi_id = cached_request_data.get('payment_intent_id') or \
            f"sim_{cached_request_data['rider_id']}_{cached_request_data['bike_id']}_{int(timezone.now().timestamp())}"

        with transaction.atomic():
            existing_request = Ride_Request.objects.filter(
                Rider=rider_profile,
                bike=bike,
                status__in=['pending', 'accepted']
            ).first()

            if existing_request:
                existing_request.Owner = bike.owner
                existing_request.pickup_latitude = cached_request_data['pickup_latitude']
                existing_request.pickup_longitude = cached_request_data['pickup_longitude']
                existing_request.destination_latitude = cached_request_data['destination_latitude']
                existing_request.destination_longitude = cached_request_data['destination_longitude']
                existing_request.distance = cached_request_data['distance']
                existing_request.price = cached_request_data['price']
                existing_request.payment_type = cached_request_data['payment_type']
                existing_request.duration = timedelta(hours=cached_request_data['duration_hours'])
                existing_request.payment_intent_id = real_pi_id
                existing_request.payment_status = 'completed'
                existing_request.total_amount = cached_request_data['total_amount']
                existing_request.platform_commission = cached_request_data['platform_commission']
                existing_request.owner_earnings = cached_request_data['owner_earnings']
                existing_request.destination_address = cached_request_data.get('destination_address', '')
                existing_request.origin_address = cached_request_data.get('origin_address', '')
                existing_request.status = 'accepted'
                existing_request.is_accepted = True
                existing_request.payment_processed_at = timezone.now()
                existing_request.requested_time = datetime.fromisoformat(cached_request_data['requested_time'].replace('Z', '+00:00'))
                existing_request.save()
                ride_request = existing_request
            else:
                ride_request = Ride_Request.objects.create(
                    Rider=rider_profile,
                    Owner=bike.owner,
                    bike=bike,
                    pickup_latitude=cached_request_data['pickup_latitude'],
                    pickup_longitude=cached_request_data['pickup_longitude'],
                    destination_latitude=cached_request_data['destination_latitude'],
                    destination_longitude=cached_request_data['destination_longitude'],
                    distance=cached_request_data['distance'],
                    price=cached_request_data['price'],
                    payment_type=cached_request_data['payment_type'],
                    duration=timedelta(hours=cached_request_data['duration_hours']),
                    payment_intent_id=real_pi_id,
                    payment_status='completed',
                    total_amount=cached_request_data['total_amount'],
                    platform_commission=cached_request_data['platform_commission'],
                    owner_earnings=cached_request_data['owner_earnings'],
                    destination_address=cached_request_data.get('destination_address', ''),
                    origin_address=cached_request_data.get('origin_address', ''),
                    status='accepted',
                    is_accepted=True,
                    payment_processed_at=timezone.now(),
                    requested_time=datetime.fromisoformat(cached_request_data['requested_time'].replace('Z', '+00:00'))
                )

            trip = Trip.objects.create(
                renter=rider_profile,
                bike_owner=bike.owner,
                bike=bike,
                origin_latitude=cached_request_data['pickup_latitude'],
                origin_longitude=cached_request_data['pickup_longitude'],
                destination_latitude=cached_request_data['destination_latitude'],
                destination_longitude=cached_request_data['destination_longitude'],
                distance=cached_request_data['distance'],
                price=cached_request_data['price'],
                payment_type=cached_request_data['payment_type'],
                status='waiting',
                payment_status='completed',
                payment_processed_at=timezone.now(),
                payment_intent_id=real_pi_id,
                destination_address=cached_request_data.get('destination_address', ''),
                origin_address=cached_request_data.get('origin_address', '')
            )

            bike.is_available = False
            bike.bike_status = 'reserved'
            bike.save()

            cache.delete(cache_key)
            cache.delete(f"pending_request_bike_{cached_request_data['bike_id']}")
            cache.delete(f"pending_request_rider_{cached_request_data['rider_id']}")
            cache.delete(f"bike_slot_lock_{cached_request_data['bike_id']}")

            chat_room = ChatRoom.objects.create(trip=trip)
            Message.objects.create(
                chat_room=chat_room,
                sender=request.user,
                content="Ride accepted! Please walk to the bike location to start your trip."
            )

            channel_layer = get_channel_layer()
            async_to_sync(channel_layer.group_send)(
                f'notifications_{rider_profile.user.id}',
                {
                    'type': 'send_notification',
                    'title': 'Ride Accepted ✅',
                    'message': f'{bike.owner.user.username} accepted your ride! Walk to the bike and click "Start Trip".',
                    'data': {
                        'trip_id': trip.id,
                        'chat_room_id': chat_room.id,
                        'bike_location': {
                            'latitude': float(bike.latitude),
                            'longitude': float(bike.longitude),
                            'name': bike.bike_name,
                            'bike_id': bike.id
                        },
                        'status': 'accepted',
                        'trip_status': 'waiting',
                        'owner_username': bike.owner.user.username,
                    }
                }
            )

            async_to_sync(channel_layer.group_send)(
                f'notifications_{bike.owner.user.id}',
                {
                    'type': 'send_notification',
                    'title': 'Ride Request Accepted ✅',
                    'message': f'Trip created for {rider_profile.user.username}. Waiting for rider to start trip.',
                    'data': {
                        'trip_id': trip.id,
                        'chat_room_id': chat_room.id,
                        'potential_earnings': f"€{cached_request_data['owner_earnings']:.2f}",
                        'rider_username': rider_profile.user.username,
                        'trip_status': 'waiting',
                    }
                }
            )

            return Response({
                'success': True,
                'message': 'Ride request accepted - trip created',
                'trip_id': trip.id,
                'ride_request_id': ride_request.id,
                'chat_room_id': chat_room.id,
                'trip_details': {
                    'id': trip.id,
                    'status': trip.status,
                    'distance': f"{trip.distance:.2f} km",
                    'estimated_duration': f"{(trip.distance / 30):.1f} hours",
                },
                'earnings_info': {
                    'will_earn_on_completion': f"€{cached_request_data['owner_earnings']:.2f}",
                },
                'bike_info': {
                    'name': bike.bike_name,
                    'location': {
                        'latitude': float(bike.latitude),
                        'longitude': float(bike.longitude)
                    },
                },
                'communication': {'chat_room_id': chat_room.id}
            }, status=status.HTTP_200_OK)

    except Exception as e:
        import logging
        logging.getLogger(__name__).exception("Error accepting ride request")
        try:
            cache.delete(f"pending_request_{temp_request_id}")
            if 'cached_request_data' in locals():
                cache.delete(f"pending_request_bike_{cached_request_data['bike_id']}")
                cache.delete(f"pending_request_rider_{cached_request_data['rider_id']}")
        except Exception:
            pass
        return Response({
            'error': 'Internal server error',
            'message': 'Failed to accept ride request. Please try again.',
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)



@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def decline_ride_request(request, temp_request_id):
    """Owner declines cached ride request - removes from cache, processes refunds, and notifies rider"""
    try:
        cache_key = f"pending_request_{temp_request_id}"
        cached_request_data = cache.get(cache_key)
        
        if not cached_request_data:
            return Response({
                'error': 'Request not found or expired',
                'message': 'This ride request has expired or does not exist.'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # VALIDATE OWNERSHIP
        try:
            bike = Bikes.objects.get(id=cached_request_data['bike_id'])
        except Bikes.DoesNotExist:
            # Clean up cache anyway
            cache.delete(cache_key)
            cache.delete(f"pending_request_bike_{cached_request_data['bike_id']}")
            cache.delete(f"pending_request_rider_{cached_request_data['rider_id']}")
            
            return Response({
                'error': 'Bike not found',
                'message': 'The bike associated with this request no longer exists.'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # 🔧 CHECK OWNERSHIP
        if bike.owner.user != request.user:
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)
        
        
        try:
            rider_profile = UserProfile.objects.get(id=cached_request_data['rider_id'])
        except UserProfile.DoesNotExist:
            return Response({'error': 'Rider profile not found'}, status=status.HTTP_404_NOT_FOUND)
        
        
        cache.delete(cache_key)
        cache.delete(f"pending_request_bike_{cached_request_data['bike_id']}")
        cache.delete(f"pending_request_rider_{cached_request_data['rider_id']}")

        # Refund Stripe payment if it was a real charge (not simulated)
        payment_intent_id = cached_request_data.get('payment_intent_id', '')
        refund_status = 'not_applicable'
        if payment_intent_id and not payment_intent_id.startswith('sim_'):
            try:
                stripe.Refund.create(payment_intent=payment_intent_id)
                refund_status = 'refunded'
            except stripe.error.StripeError as e:
                refund_status = 'refund_failed'
                logger.error(f"Refund failed for PI {payment_intent_id}: {e}")

        channel_layer = get_channel_layer()
        refund_message = ''
        if refund_status == 'refunded':
            refund_message = 'Your payment has been refunded.'
        elif refund_status == 'refund_failed':
            refund_message = 'Refund could not be processed automatically — please contact support.'
        rider_notification_data = {
            'status': 'declined',
            'refund_status': refund_status,
            'refund_message': refund_message,
            'bike_name': bike.bike_name,
            'owner_username': bike.owner.user.username,
            'declined_at': timezone.now().isoformat(),
            'next_step': 'You can request another bike',
        }
        
        async_to_sync(channel_layer.group_send)(
            f'notifications_{rider_profile.user.id}',
            {
                'type': 'send_notification',
                'title': 'Ride Request Declined ❌',
                'message': 'Your ride request has been declined.',
                'data': rider_notification_data
            }
        )
        
       
        return Response({
            'success': True,
            'message': 'Ride request declined successfully',
            'details': {
                'declined_request': {
                    'rider_username': rider_profile.user.username,
                    'bike_name': bike.bike_name,
                    'original_price': f"€{cached_request_data['price']:.2f}",
                    'declined_at': timezone.now().isoformat()
                },
                'bike_status': {
                    'name': bike.bike_name,
                    'status': 'available',
                    'note': 'Bike is now available for new requests'
                },
                'rider_notified': True
            }
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        logger.exception("Error declining ride request")
        try:
            cache.delete(f"pending_request_{temp_request_id}")
            if 'cached_request_data' in locals():
                cache.delete(f"pending_request_bike_{cached_request_data['bike_id']}")
                cache.delete(f"pending_request_rider_{cached_request_data['rider_id']}")
        except Exception:
            pass
        
        return Response({
            'error': 'Internal server error',
            'message': 'Failed to decline ride request. Please try again.',
            'note': 'If this was a real payment, please contact support for manual refund processing.'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

















@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def request_ride_with_payment(request):
    """
    Request ride with real Stripe payment (Apple Pay / Google Pay / card).

    Flow:
      1. Validates price token and bike availability (same checks as request_ride).
      2. Creates a Stripe PaymentIntent with setup_future_usage='off_session' so the
         payment method is saved automatically — works with Apple Pay, Google Pay, and cards.
      3. Returns client_secret to Flutter. Flutter opens the Payment Sheet which shows
         all available payment options on the device.
      4. After the user pays, Stripe fires payment_intent.succeeded to the rider webhook,
         which saves the payment method and notifies the owner.
    """
    pickup_latitude = request.data.get('pickup_latitude')
    pickup_longitude = request.data.get('pickup_longitude')
    destination_latitude = request.data.get('destination_latitude')
    destination_longitude = request.data.get('destination_longitude')
    payment_type = request.data.get('payment_type', 'card')
    price_token = request.data.get('price_token')
    destination_address = request.data.get('destination_address')
    origin_address = request.data.get('origin_address')

    if not all([pickup_latitude, pickup_longitude, destination_latitude, destination_longitude, price_token, destination_address, origin_address]):
        return Response({
            'error': 'Missing required fields',
            'required': ['pickup_latitude', 'pickup_longitude', 'destination_latitude', 'destination_longitude', 'price_token', 'destination_address', 'origin_address']
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        rider_profile = UserProfile.objects.get(user=request.user)
    except UserProfile.DoesNotExist:
        return Response({'error': 'Rider profile not found.'}, status=status.HTTP_404_NOT_FOUND)

    # Check for existing pending request from this rider
    existing_cache_key = f"pending_request_rider_{rider_profile.id}"
    existing_cached_request = cache.get(existing_cache_key)
    if existing_cached_request:
        return Response({
            'error': 'Duplicate request detected',
            'message': 'You already have a pending ride request.',
            'existing_request': {
                'bike_name': existing_cached_request.get('bike_name'),
                'requested_at': existing_cached_request.get('requested_time'),
            }
        }, status=status.HTTP_409_CONFLICT)

    # Validate price token
    cache_key = f"price_estimate_{rider_profile.id}_{price_token}"
    cached_price_data = cache.get(cache_key)
    if not cached_price_data:
        return Response({
            'error': 'Price estimate expired or invalid',
            'message': 'Please get a new price estimate before requesting.'
        }, status=status.HTTP_400_BAD_REQUEST)

    if int(time.time()) - cached_price_data['timestamp'] > 600:
        return Response({
            'error': 'Price estimate expired',
            'message': 'Price estimate is older than 10 minutes. Please get a new estimate.'
        }, status=status.HTTP_400_BAD_REQUEST)

    bike_id = cached_price_data['bike_id']

    # Request deduplication lock
    request_lock_key = f"ride_request_lock_{rider_profile.id}_{bike_id}"
    if cache.get(request_lock_key):
        return Response({
            'error': 'Request in progress',
            'message': 'A ride request is already being processed. Please wait.'
        }, status=status.HTTP_429_TOO_MANY_REQUESTS)
    cache.set(request_lock_key, True, timeout=30)

    try:
        # Validate bike availability
        try:
            bike = Bikes.objects.get(
                id=bike_id,
                is_active=True,
                is_available=True,
                bike_status='available'
            )
        except Bikes.DoesNotExist:
            cache.delete(request_lock_key)
            return Response({
                'error': 'Bike no longer available',
                'message': 'The bike from your estimate is no longer available. Please get a new estimate.'
            }, status=status.HTTP_404_NOT_FOUND)

        # Atomically claim the bike slot — cache.add() only succeeds if key doesn't exist.
        # This closes the race window where two riders pass the get() check simultaneously.
        bike_cache_key = f"pending_request_bike_{bike.id}"
        if not cache.add(f"bike_slot_lock_{bike.id}", True, timeout=1000):
            cache.delete(request_lock_key)
            # Preferred bike just got taken — find the next nearest available bike
            alt_bike, alt_distance, alt_price = get_price_estimate(
                pickup_latitude, pickup_longitude,
                destination_latitude, destination_longitude,
                rider_profile,
                exclude_bike_ids=[bike.id]
            )
            if alt_bike is None:
                return Response({
                    'error': 'No bikes available',
                    'message': 'All nearby bikes are currently requested. Please try again shortly.',
                }, status=status.HTTP_409_CONFLICT)

            # Generate a fresh price token for the alternative bike
            alt_price_data = {
                'bike_id': alt_bike.id,
                'pickup_lat': pickup_latitude,
                'pickup_lng': pickup_longitude,
                'dest_lat': destination_latitude,
                'dest_lng': destination_longitude,
                'price': alt_price,
                'timestamp': int(time.time()),
                'rider_id': rider_profile.id,
            }
            alt_token = hashlib.sha256(
                json.dumps(alt_price_data, sort_keys=True).encode() + settings.SECRET_KEY.encode()
            ).hexdigest()
            cache.set(f"price_estimate_{rider_profile.id}_{alt_token}", alt_price_data, timeout=600)

            return Response({
                'preferred_bike_unavailable': True,
                'message': 'That bike was just taken. Here is the next nearest available bike.',
                'alternative_bike': {
                    'id': alt_bike.id,
                    'name': alt_bike.bike_name,
                    'brand': alt_bike.brand,
                    'model': alt_bike.model,
                    'distance_km': round(alt_distance, 2),
                    'location': {
                        'latitude': float(alt_bike.latitude),
                        'longitude': float(alt_bike.longitude),
                    },
                    'bike_image': alt_bike.bike_image.url if alt_bike.bike_image else None,
                },
                'new_price_token': alt_token,
                'estimated_price': float(alt_price),
                'valid_until': int(time.time()) + 600,
            }, status=status.HTTP_200_OK)

        estimated_price = cached_price_data['price']
        trip_distance = calculate_distance(pickup_latitude, pickup_longitude, destination_latitude, destination_longitude)

        PLATFORM_COMMISSION_RATE = Trip.COMMISSION_RATE
        platform_commission = float(estimated_price) * float(PLATFORM_COMMISSION_RATE)
        owner_earnings = estimated_price - platform_commission

        # ---- STRIPE PAYMENT INTENT ----
        # Create or reuse Stripe customer (required for setup_future_usage)
        if not rider_profile.stripe_customer_id:
            customer = stripe.Customer.create(
                email=request.user.email,
                name=request.user.username,
                metadata={'rider_id': rider_profile.id}
            )
            rider_profile.stripe_customer_id = customer.id
            rider_profile.save(update_fields=['stripe_customer_id'])

        temp_request_id = str(uuid.uuid4())

        try:
            amount_cents = int(estimated_price * 100)
            payment_intent = stripe.PaymentIntent.create(
                amount=amount_cents,
                currency='eur',
                customer=rider_profile.stripe_customer_id,
                # setup_future_usage saves the payment method (card/Apple Pay/Google Pay)
                # for off_session charges like extra distance at trip end
                setup_future_usage='off_session',
                payment_method_types=['card'],
                metadata={
                    'rider_id': str(rider_profile.id),
                    'bike_id': str(bike.id),
                    'owner_user_id': str(bike.owner.user.id),
                    'temp_request_id': temp_request_id,
                    'trip_distance': str(round(trip_distance, 2)),
                    'platform_commission': str(round(platform_commission, 2)),
                    'owner_earnings': str(round(owner_earnings, 2)),
                    'estimated_price': str(round(estimated_price, 2)),
                    'pickup_location': f"{pickup_latitude},{pickup_longitude}",
                }
            )
        except stripe.error.StripeError as e:
            cache.delete(request_lock_key)
            cache.delete(f"bike_slot_lock_{bike.id}")
            return Response({
                'error': 'Payment processing error',
                'message': 'Unable to initialise payment. Please try again.'
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
        # ---- END STRIPE PAYMENT INTENT ----

        request_data = {
            'temp_id': temp_request_id,
            'rider_id': rider_profile.id,
            'rider_username': request.user.username,
            'owner_id': bike.owner.id,
            'owner_user_id': bike.owner.user.id,
            'bike_id': bike.id,
            'bike_name': bike.bike_name,
            'bike_brand': bike.brand,
            'bike_model': bike.model,
            'pickup_latitude': pickup_latitude,
            'pickup_longitude': pickup_longitude,
            'destination_latitude': destination_latitude,
            'destination_longitude': destination_longitude,
            'destination_address': destination_address,
            'origin_address': origin_address,
            'distance': trip_distance,
            'price': estimated_price,
            'payment_type': payment_type,
            'duration_hours': trip_distance / 30,
            'total_amount': estimated_price,
            'platform_commission': platform_commission,
            'owner_earnings': owner_earnings,
            'payment_intent_id': payment_intent.id,
            'requested_time': timezone.now().isoformat(),
            # payment_status starts as pending — webhook updates to completed and notifies owner
            'payment_status': 'pending_payment',
            'status': 'pending_cache'
        }

        # Store by rider and bike to prevent duplicates.
        # Also index by payment_intent_id so the webhook can find this entry.
        cache.set(f"pending_request_rider_{rider_profile.id}", request_data, timeout=1000)
        cache.set(f"pending_request_bike_{bike.id}", request_data, timeout=1000)
        cache.set(f"pending_request_{temp_request_id}", request_data, timeout=1000)
        cache.set(f"pending_request_pi_{payment_intent.id}", temp_request_id, timeout=1000)
        cache.delete(cache_key)
        cache.delete(request_lock_key)

        # Owner is NOT notified here — the stripe webhook fires after Flutter confirms
        # payment and sends the owner notification at that point.

        return Response({
            'success': True,
            'temp_request_id': temp_request_id,
            'payment': {
                'client_secret': payment_intent.client_secret,
                'payment_intent_id': payment_intent.id,
                'customer_id': rider_profile.stripe_customer_id,
                'total_amount': f"€{estimated_price:.2f}",
                'owner_earnings': f"€{owner_earnings:.2f}",
                'platform_commission': f"€{platform_commission:.2f}",
            },
            'bike': {
                'id': bike.id,
                'name': bike.bike_name,
                'brand': bike.brand,
                'model': bike.model,
                'location': {'latitude': float(bike.latitude), 'longitude': float(bike.longitude)}
            },
            'trip_details': {
                'distance': round(trip_distance, 2),
                'estimated_duration': round(trip_distance / 30, 2)
            },
            'message': 'Payment session created. Complete payment to send request to owner.',
            'note': 'Request will expire in 16 minutes if payment is not completed.',
            'expires_at': (timezone.now() + timedelta(minutes=16)).isoformat()
        }, status=status.HTTP_201_CREATED)

    except Exception as e:
        cache.delete(request_lock_key)
        return Response({
            'error': 'Internal server error',
            'message': 'Something went wrong. Please try again.'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def request_ride(request):
    """Request ride with cache-only storage until acceptance"""
    pickup_latitude = request.data.get('pickup_latitude')
    pickup_longitude = request.data.get('pickup_longitude')
    destination_latitude = request.data.get('destination_latitude')
    destination_longitude = request.data.get('destination_longitude')
    payment_type = request.data.get('payment_type', 'card')
    price_token = request.data.get('price_token')
    destination_address = request.data.get('destination_address')
    origin_address = request.data.get('origin_address')

    if not all([pickup_latitude, pickup_longitude, destination_latitude, destination_longitude, price_token, destination_address, origin_address]):
        return Response({
            'error': 'Missing required fields',
            'required': ['pickup_latitude', 'pickup_longitude', 'destination_latitude', 'destination_longitude', 'price_token', 'destination_address', 'origin_address']
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        rider_profile = UserProfile.objects.get(user=request.user)
    except UserProfile.DoesNotExist:
        return Response({'error': 'Rider profile not found.'}, status=status.HTTP_404_NOT_FOUND)

    # 🔧 CHECK 1: Look for existing cache requests from this rider
    rider_cache_pattern = f"pending_request_rider_{rider_profile.id}_*"
    # Simple check - one pending request per rider
    existing_cache_key = f"pending_request_rider_{rider_profile.id}"
    existing_cached_request = cache.get(existing_cache_key)
    
    if existing_cached_request:
        return Response({
            'error': 'Duplicate request detected',
            'message': f'You already have a pending ride request. Please wait for response or let it expire.',
            'existing_request': {
                'bike_name': existing_cached_request.get('bike_name'),
                'requested_at': existing_cached_request.get('requested_time'),
            }
        }, status=status.HTTP_409_CONFLICT)

    # 🔧 CHECK 2: Validate price token
    cache_key = f"price_estimate_{rider_profile.id}_{price_token}"
    cached_price_data = cache.get(cache_key)
    
    if not cached_price_data:
        return Response({
            'error': 'Price estimate expired or invalid',
            'message': 'Please get a new price estimate before requesting.'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    if int(time.time()) - cached_price_data['timestamp'] > 600:
        return Response({
            'error': 'Price estimate expired',
            'message': 'Price estimate is older than 10 minutes. Please get a new estimate.'
        }, status=status.HTTP_400_BAD_REQUEST)

    bike_id = cached_price_data['bike_id']
    
    # 🔧 CHECK 3: Request deduplication lock
    request_lock_key = f"ride_request_lock_{rider_profile.id}_{bike_id}"
    if cache.get(request_lock_key):
        return Response({
            'error': 'Request in progress',
            'message': 'A ride request is already being processed. Please wait.'
        }, status=status.HTTP_429_TOO_MANY_REQUESTS)
    
    # Set lock for 30 seconds
    cache.set(request_lock_key, True, timeout=30)
    
    try:
        # 🔧 CHECK 4: Validate bike availability
        try:
            bike = Bikes.objects.get(
                id=bike_id,
                is_active=True,
                is_available=True,
                bike_status='available'
            )
        except Bikes.DoesNotExist:
            return Response({
                'error': 'Bike no longer available',
                'message': 'The bike from your estimate is no longer available. Please get a new estimate.'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # 🔧 CHECK 5: Check for existing cache requests for this bike
        bike_cache_key = f"pending_request_bike_{bike.id}"
        if not cache.add(f"bike_slot_lock_{bike.id}", True, timeout=300):
            cache.delete(request_lock_key)
            alt_bike, alt_distance, alt_price = get_price_estimate(
                pickup_latitude, pickup_longitude,
                destination_latitude, destination_longitude,
                rider_profile,
                exclude_bike_ids=[bike.id]
            )
            if alt_bike is None:
                return Response({
                    'error': 'No bikes available',
                    'message': 'All nearby bikes are currently requested. Please try again shortly.',
                }, status=status.HTTP_409_CONFLICT)

            alt_price_data = {
                'bike_id': alt_bike.id,
                'pickup_lat': pickup_latitude,
                'pickup_lng': pickup_longitude,
                'dest_lat': destination_latitude,
                'dest_lng': destination_longitude,
                'price': alt_price,
                'timestamp': int(time.time()),
                'rider_id': rider_profile.id,
            }
            alt_token = hashlib.sha256(
                json.dumps(alt_price_data, sort_keys=True).encode() + settings.SECRET_KEY.encode()
            ).hexdigest()
            cache.set(f"price_estimate_{rider_profile.id}_{alt_token}", alt_price_data, timeout=600)

            return Response({
                'preferred_bike_unavailable': True,
                'message': 'That bike was just taken. Here is the next nearest available bike.',
                'alternative_bike': {
                    'id': alt_bike.id,
                    'name': alt_bike.bike_name,
                    'brand': alt_bike.brand,
                    'model': alt_bike.model,
                    'distance_km': round(alt_distance, 2),
                    'location': {
                        'latitude': float(alt_bike.latitude),
                        'longitude': float(alt_bike.longitude),
                    },
                    'bike_image': alt_bike.bike_image.url if alt_bike.bike_image else None,
                },
                'new_price_token': alt_token,
                'estimated_price': float(alt_price),
                'valid_until': int(time.time()) + 600,
            }, status=status.HTTP_200_OK)

        # CALCULATE TRIP DETAILS
        estimated_price = cached_price_data['price']
        trip_distance = calculate_distance(pickup_latitude, pickup_longitude, destination_latitude, destination_longitude)
        
        # Calculate commission
        PLATFORM_COMMISSION_RATE = float(Trip.COMMISSION_RATE)
        platform_commission = estimated_price * PLATFORM_COMMISSION_RATE
        owner_earnings = estimated_price - platform_commission
        
        # Generate temporary request ID
      
        temp_request_id = str(uuid.uuid4())
    
        request_data = {
            'temp_id': temp_request_id,
            'rider_id': rider_profile.id,
            'rider_username': request.user.username,
            'owner_id': bike.owner.id,
            'bike_id': bike.id,
            'bike_name': bike.bike_name,
            'bike_brand': bike.brand,
            'bike_model': bike.model,
            'pickup_latitude': pickup_latitude,
            'pickup_longitude': pickup_longitude,
            'destination_latitude': destination_latitude,
            'destination_longitude': destination_longitude,
            'destination_address': destination_address,
            'origin_address': origin_address,
            'distance': trip_distance,
            'price': estimated_price,
            'payment_type': payment_type,
            'duration_hours': trip_distance / 30,
            'total_amount': estimated_price,
            'platform_commission': platform_commission,
            'owner_earnings': owner_earnings,
            'requested_time': timezone.now().isoformat(),
            'payment_status': 'completed_simulated',
            'status': 'pending_cache'
        }
        
        # All three expire together at 5 minutes — if owner doesn't accept in time,
        # the rider's dedup lock is also released so they can request a different bike.
        cache.set(f"pending_request_rider_{rider_profile.id}", request_data, timeout=300)
        cache.set(f"pending_request_bike_{bike.id}", request_data, timeout=300)
        cache.set(f"pending_request_{temp_request_id}", request_data, timeout=300)
        
        # Clean up
        cache.delete(cache_key)  # Remove price estimate
        cache.delete(request_lock_key)  # Remove processing lock
        
      
        channel_layer = get_channel_layer()
        owner_user_id = bike.owner.user.id
        
        async_to_sync(channel_layer.group_send)(
            f'notifications_{owner_user_id}',
            {
                'type': 'send_notification',
                'title': 'New Ride Request - PAYMENT COMPLETED ✅',
                'message': f'{request.user.username} wants to rent your {bike.bike_name}',
                'data': {
                    'temp_request_id': temp_request_id, 
                    'pickup_location': {
                        'latitude': pickup_latitude,
                        'longitude': pickup_longitude
                    },
                    'destination_location': {
                        'latitude': destination_latitude,
                        'longitude': destination_longitude
                    },
                    'total_paid_by_rider': f"€{estimated_price:.2f}",
                    'your_earnings': f"€{owner_earnings:.2f}",
                    'platform_commission': f"€{platform_commission:.2f}",
                    'bike_name': bike.bike_name,
                    'rider_username': request.user.username,
                    'trip_distance': f"{trip_distance:.2f} km",
                    'payment_completed': True,
                    'expires_in_minutes': 5
                }
            }
        )
        
        return Response({
            'success': True,
            'temp_request_id': temp_request_id,  
            'bike': {
                'id': bike.id,
                'name': bike.bike_name,
                'brand': bike.brand,
                'model': bike.model,
                'location': {
                    'latitude': float(bike.latitude),
                    'longitude': float(bike.longitude)
                }
            },
            'payment': {
                'total_amount': f"€{estimated_price:.2f}",
                'owner_earnings': f"€{owner_earnings:.2f}",
                'platform_commission': f"€{platform_commission:.2f}",
                'status': 'completed (simulated)'
            },
            'trip_details': {
                'distance': round(trip_distance, 2),
                'estimated_duration': round(trip_distance / 30, 2)
            },
            'message': 'Payment successful (simulated). Waiting for owner acceptance.',
            'note': 'Request will expire in 5 minutes if not accepted.',
            'expires_at': (timezone.now() + timedelta(minutes=5)).isoformat()
        }, status=status.HTTP_201_CREATED)
        
        
    except Exception as e:
        cache.delete(request_lock_key)
        logger.exception("Error in request_ride")
        return Response({
            'error': 'Internal server error',
            'message': 'Something went wrong. Please try again.'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
 


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def cancel_ride_request(request, temp_request_id):
    """Rider cancels their pending ride request - only works before acceptance"""
    try:
        # Get rider profile 
        try:
            rider_profile = UserProfile.objects.get(user=request.user)
        except UserProfile.DoesNotExist:
            return Response({'error': 'Rider profile not found'}, status=status.HTTP_404_NOT_FOUND)
        
        # Check if request exists in cache
        cache_key = f"pending_request_{temp_request_id}"
        cached_request_data = cache.get(cache_key)
        
        if not cached_request_data:
            return Response({
                'error': 'Request not found or already processed',
                'message': 'This ride request has expired, been accepted, or already cancelled.'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Verify the request belongs to this rider
        if cached_request_data['rider_id'] != rider_profile.id:
            return Response({'error': 'Not authorized to cancel this request'}, status=status.HTTP_403_FORBIDDEN)
        
        # Get bike and owner info for notification
        try:
            bike = Bikes.objects.get(id=cached_request_data['bike_id'])
        except Bikes.DoesNotExist:
            # Clean up cache anyway
            cache.delete(cache_key)
            cache.delete(f"pending_request_bike_{cached_request_data['bike_id']}")
            cache.delete(f"pending_request_rider_{cached_request_data['rider_id']}")
            return Response({
                'error': 'Bike not found',
                'message': 'The bike associated with this request no longer exists.'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Clean up ALL cache entries
        cache.delete(cache_key)
        cache.delete(f"pending_request_bike_{cached_request_data['bike_id']}")
        cache.delete(f"pending_request_rider_{cached_request_data['rider_id']}")

        # Refund Stripe payment if it was a real charge (not simulated)
        payment_intent_id = cached_request_data.get('payment_intent_id', '')
        refund_status = 'not_applicable'
        if payment_intent_id and not payment_intent_id.startswith('sim_'):
            try:
                stripe.Refund.create(payment_intent=payment_intent_id)
                refund_status = 'refunded'
            except stripe.error.StripeError as e:
                refund_status = 'refund_failed'
                logger.error(f"Refund failed for PI {payment_intent_id} on cancel: {e}")

        # Notify owner about cancellation
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f'notifications_{bike.owner.user.id}',
            {
                'type': 'send_notification',
                'title': 'Ride Request Cancelled ❌',
                'message': f'{rider_profile.user.username} cancelled their ride request for {bike.bike_name}',
                'data': {
                    'action': 'cancelled_by_rider',
                    'rider_username': rider_profile.user.username,
                    'bike_name': bike.bike_name,
                    'cancelled_at': timezone.now().isoformat(),
                    'temp_request_id': temp_request_id,
                    'note': 'Your bike is now available for other requests'
                }
            }
        )
        
        # Notify rider (confirmation)
        async_to_sync(channel_layer.group_send)(
            f'notifications_{rider_profile.user.id}',
            {
                'type': 'send_notification',
                'title': 'Request Cancelled ✅',
                'message': f'Your ride request for {bike.bike_name} has been cancelled',
                'data': {
                    'action': 'cancelled',
                    'bike_name': bike.bike_name,
                    'cancelled_at': timezone.now().isoformat(),
                    'note': 'You can request another bike anytime'
                }
            }
        )
        
        return Response({
            'success': True,
            'message': 'Ride request cancelled successfully',
            'details': {
                'cancelled_request': {
                    'bike_name': bike.bike_name,
                    'owner_username': bike.owner.user.username,
                    'cancelled_at': timezone.now().isoformat()
                },
                'bike_status': {
                    'name': bike.bike_name,
                    'status': 'available',
                    'note': 'Bike is now available for new requests'
                },
                'owner_notified': True,
                'next_step': 'You can request another bike anytime'
            }
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        logger.exception("Error cancelling ride request")
        try:
            cache.delete(f"pending_request_{temp_request_id}")
            if 'cached_request_data' in locals():
                cache.delete(f"pending_request_bike_{cached_request_data['bike_id']}")
                cache.delete(f"pending_request_rider_{cached_request_data['rider_id']}")
        except Exception:
            pass
        
        return Response({
            'error': 'Internal server error',
            'message': 'Failed to cancel ride request. Please try again.'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
