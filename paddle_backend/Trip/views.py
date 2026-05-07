from django.shortcuts import get_object_or_404
from django.conf import settings
from django.utils import timezone
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework import status as drf_status
from .models import Trip
from Bikes.models import Bikes
from Owner.models import OwnerProfile
from Bikes.pricing import calculate_price
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync
from chat.models import ChatRoom
from chat.utils import notify_user
import stripe
from geopy.distance import geodesic
from decimal import Decimal
import logging

logger = logging.getLogger(__name__)

stripe.api_key = settings.STRIPE_SECRET_KEY

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def start_trip(request, trip_id):
    trip = get_object_or_404(Trip, pk=trip_id, renter=request.user.userprofile)
    
    if trip.status not in ('created', 'waiting'):
        return Response({'error': 'Trip cannot be started'}, status=drf_status.HTTP_400_BAD_REQUEST)

    trip.status = 'started'
    trip.start_time = timezone.now()

    rider_profile = trip.renter
    payment_held = False
    if rider_profile.default_payment_method and rider_profile.stripe_customer_id:
        try:
            pi = stripe.PaymentIntent.create(
                amount=int(float(trip.price) * 100),
                currency='usd',
                customer=rider_profile.stripe_customer_id,
                payment_method=rider_profile.default_payment_method,
                capture_method='manual',
                confirm=True,
                off_session=True,
                metadata={'trip_id': trip.id, 'stage': 'pre_auth'},
                idempotency_key=f"trip_{trip.id}_preauth",
            )
            trip.payment_intent_id = pi.id
            trip.payment_status = 'processing'
            payment_held = True
        except stripe.error.StripeError as e:
            logger.error(f"Pre-auth failed for trip {trip.id}: {e}")
            return Response(
                {'error': 'Payment authorization failed. Please check your card.'},
                status=drf_status.HTTP_402_PAYMENT_REQUIRED,
            )

    trip.save()

    for user_id in [trip.renter.user.id, trip.bike_owner.user.id]:
        notify_user(user_id, 'Trip Started', 'The trip has begun', {
            'trip_id': trip.id,
            'start_time': trip.start_time.isoformat(),
        })

    return Response({
        'message': 'Trip started successfully',
        'start_time': trip.start_time,
        'pre_auth_amount': float(trip.price),
        'payment_held': payment_held,
    })

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def end_trip(request, trip_id):
    trip = get_object_or_404(Trip, pk=trip_id, renter=request.user.userprofile)
    
    if trip.status != 'ontrip':
        return Response({'error': 'Trip cannot be ended'}, status=drf_status.HTTP_400_BAD_REQUEST)

    try:
        trip.end_time = timezone.now()
        if trip.start_time is None:
            trip.start_time = trip.end_time
        duration_hours = (trip.end_time - trip.start_time).total_seconds() / 3600
        
        if trip.distance is None:
            origin_coords = (trip.origin_latitude, trip.origin_longitude)
            destination_coords = (trip.destination_latitude, trip.destination_longitude)
            trip.distance = geodesic(origin_coords, destination_coords).kilometers
        
        final_price = calculate_price(
            distance=float(trip.distance),
            duration_hours=duration_hours
        )
        # Capture the original estimate BEFORE overwriting trip.price
        original_estimated_cents = int(float(trip.price) * 100) if trip.price else 0
        trip.price = Decimal(str(final_price))

        trip.calculate_commission()

        rider_profile = trip.renter
        saved_pm = rider_profile.default_payment_method
        stripe_customer = rider_profile.stripe_customer_id

        actual_cents = int(final_price * 100)
        estimated_cents = original_estimated_cents

        from django.db.models import F
        if trip.payment_intent_id:
            # Capture the pre-auth — platform keeps the full amount; owner share tracked in DB
            capture_cents = min(actual_cents, estimated_cents)
            stripe.PaymentIntent.capture(
                trip.payment_intent_id, amount_to_capture=capture_cents
            )

            # Charge the overage if actual exceeded estimate
            if actual_cents > estimated_cents:
                overage_cents = actual_cents - estimated_cents
                overage_kwargs = {
                    'amount': overage_cents,
                    'currency': 'usd',
                    'metadata': {'trip_id': trip.id, 'stage': 'overage'},
                    'idempotency_key': f"trip_{trip.id}_overage",
                }
                if saved_pm and stripe_customer:
                    overage_kwargs.update({
                        'customer': stripe_customer,
                        'payment_method': saved_pm,
                        'confirm': True,
                        'off_session': True,
                    })
                stripe.PaymentIntent.create(**overage_kwargs)

            # Credit owner only after capture confirmed successful
            OwnerProfile.objects.filter(pk=trip.bike_owner_id).update(
                pending_balance=F('pending_balance') + trip.owner_payout
            )
        else:
            # Fallback: no pre-auth (rider had no saved card at start_trip time)
            pi_kwargs = {
                'amount': actual_cents,
                'currency': 'usd',
                'metadata': {'trip_id': trip.id},
                'idempotency_key': f"trip_{trip.id}_fallback",
            }
            if saved_pm and stripe_customer:
                pi_kwargs['customer'] = stripe_customer
                pi_kwargs['payment_method'] = saved_pm
                pi_kwargs['confirm'] = True
                pi_kwargs['off_session'] = True
            stripe.PaymentIntent.create(**pi_kwargs)

            # Credit owner after fallback charge
            OwnerProfile.objects.filter(pk=trip.bike_owner_id).update(
                pending_balance=F('pending_balance') + trip.owner_payout
            )

        try:
            owner_profile = OwnerProfile.objects.get(pk=trip.bike_owner_id)
            owner_profile.refresh_from_db()
        except OwnerProfile.DoesNotExist:
            owner_profile = None

        # Mark payment completed and trip done (avoid double process_payment)
        trip.payment_status = 'completed'
        trip.payment_processed_at = timezone.now()
        trip.status = 'completed'
        trip.save(update_fields=['payment_status', 'payment_processed_at', 'status'])

        # Release the bike back to the marketplace (locked to prevent concurrent state change)
        if trip.bike:
            from django.db import transaction as _tx
            with _tx.atomic():
                from Bikes.models import Bikes as _Bikes
                _bike = _Bikes.objects.select_for_update().get(pk=trip.bike_id)
                _bike.is_available = True
                _bike.bike_status = 'available'
                _bike.save(update_fields=['is_available', 'bike_status'])
                _bike.update_trip_metrics(float(trip.distance) if trip.distance else 0)

        estimated_price = original_estimated_cents / 100
        extra_charge = round(max(0.0, final_price - estimated_price), 2)

        bike = trip.bike
        notification_data = {
            'trip_id': trip.id,
            'trip_status': 'completed',
            'duration_hours': round(duration_hours, 4),
            'estimated_distance_km': float(trip.distance),
            'actual_distance_km': float(trip.distance),
            'distance_difference': 0.0,
            'estimated_price': estimated_price,
            'extra_charge': extra_charge,
            'final_price': float(final_price),
            'distance_adjustment': {
                'type': 'overage' if extra_charge > 0 else 'none',
                'explanation': f'Extra ${extra_charge} charged for additional time/distance' if extra_charge > 0 else 'No adjustment',
                'extra_charge': extra_charge,
                'charged_immediately': extra_charge > 0,
            },
            'payment_status': 'completed',
            'bike_name': bike.bike_name if bike else '',
            'notification_type': 'earnings_updated',
            'new_total_earnings': float(owner_profile.pending_balance) if owner_profile else 0.0,
            'trip_earnings': float(trip.owner_payout),
        }
        for user_id in [trip.renter.user.id, trip.bike_owner.user.id]:
            notify_user(user_id, 'Trip Completed', f'Trip completed. Total cost: ${final_price}', notification_data)

        return Response({
            'message': 'Trip completed successfully',
            'trip_details': {
                'duration_hours': round(duration_hours, 4),
                'estimated_distance_km': float(trip.distance),
                'actual_distance_km': float(trip.distance),
                'distance_difference_km': 0.0,
                'estimated_price': estimated_price,
                'extra_charge': extra_charge,
                'final_price': float(final_price),
                'commission': float(trip.commission_amount),
                'owner_payout': float(trip.owner_payout),
            },
            'distance_adjustment': {
                'type': 'overage' if extra_charge > 0 else 'none',
                'explanation': f'Extra ${extra_charge} charged for additional time/distance' if extra_charge > 0 else 'No distance adjustment needed',
                'extra_charge_applied': extra_charge,
                'charged_immediately': extra_charge > 0,
            },
            'earnings_update': {
                'owner_total_earnings': float(trip.owner_payout),
                'bike_total_earnings': 0.0,
                'earnings_added': float(trip.owner_payout),
            },
            'bike_status': {
                'is_available': True,
                'status': 'available',
                'name': bike.bike_name if bike else 'Unknown',
            },
        })
        
    except stripe.error.StripeError as e:
        notify_user(trip.renter.user.id, 'Payment Failed', 'There was an issue processing your payment', {
            'trip_id': trip.id,
            'error': str(e),
        })
        return Response({'error': 'Payment failed', 'message': str(e)}, status=drf_status.HTTP_400_BAD_REQUEST)

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_active_trip(request):
    trip = Trip.objects.filter(
        renter=request.user.userprofile,
        status__in=['created', 'waiting', 'started', 'ontrip']
    ).first()

    if not trip:
        return Response({'active_trip': None})

    chat_room_id = None
    try:
        chat_room_id = ChatRoom.objects.get(trip=trip).id
    except ChatRoom.DoesNotExist:
        pass

    bike = trip.bike
    owner = trip.bike_owner

    return Response({
        'active_trip': {
            'id': trip.id,
            'status': trip.status,
            'trip_date': trip.trip_date.isoformat(),
            'start_time': trip.start_time.isoformat() if trip.start_time else None,
            'bike': {
                'id': bike.id,
                'name': bike.bike_name,
                'brand': bike.brand,
                'model': bike.model,
                'latitude': bike.latitude,
                'longitude': bike.longitude,
                'bike_image': request.build_absolute_uri(bike.bike_image.url) if bike.bike_image else None,
            } if bike else None,
            'owner': {
                'id': owner.user.id,
                'username': owner.user.username,
            } if owner else None,
            'origin': {
                'latitude': trip.origin_latitude,
                'longitude': trip.origin_longitude,
                'address': None,
            },
            'destination': {
                'latitude': trip.destination_latitude,
                'longitude': trip.destination_longitude,
                'address': None,
            },
            'price': float(trip.price) if trip.price else None,
            'distance': float(trip.distance) if trip.distance else None,
            'payment_status': trip.payment_status,
            'payment_intent_id': None,
            'chat_room_id': chat_room_id,
        }
    })


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def begin_trip(request, trip_id):
    trip = get_object_or_404(Trip, pk=trip_id, renter=request.user.userprofile)

    if trip.status != 'started':
        return Response(
            {'error': 'Trip must be in started state before riding (call /trip/start/ first)'},
            status=drf_status.HTTP_400_BAD_REQUEST,
        )

    # Verify the TOTP unlock code when hardware is present
    bike = trip.bike
    if bike and bike.hardware:
        provided_code = str(request.data.get('unlock_code', '')).strip()
        if not provided_code:
            return Response(
                {'error': 'unlock_code is required to begin the trip'},
                status=drf_status.HTTP_400_BAD_REQUEST,
            )
        expected_code = str(bike.hardware.generate_unlock_code()).strip()
        if provided_code != expected_code:
            return Response(
                {'error': 'Invalid unlock code. Please request a fresh code and try again.'},
                status=drf_status.HTTP_400_BAD_REQUEST,
            )

    trip.status = 'ontrip'
    trip.save(update_fields=['status'])

    for user_id in [trip.renter.user.id, trip.bike_owner.user.id]:
        notify_user(user_id, 'Trip In Progress', 'The trip is now in progress', {
            'trip_id': trip.id,
            'status': 'ontrip',
        })

    return Response({'message': 'Trip is now in progress', 'status': 'ontrip'})


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def rate_trip(request, trip_id):
    trip = get_object_or_404(Trip, pk=trip_id, renter=request.user.userprofile)

    if trip.status != 'completed':
        return Response({'error': 'Can only rate completed trips'}, status=drf_status.HTTP_400_BAD_REQUEST)

    if trip.is_rated:
        return Response({'error': 'This trip has already been rated'}, status=drf_status.HTTP_400_BAD_REQUEST)

    rating = request.data.get('rating')
    review = request.data.get('review', '')

    if not rating or not (1 <= int(rating) <= 5):
        return Response({'error': 'Rating must be between 1 and 5'}, status=drf_status.HTTP_400_BAD_REQUEST)

    rating = int(rating)
    bike = trip.bike
    bike_new_rating = None

    if bike:
        count = bike.rating_count
        if count == 0:
            # First real rating — replace the default 5.00
            bike.rating = Decimal(str(rating))
        else:
            bike.rating = round(
                (Decimal(str(float(bike.rating))) * count + Decimal(str(rating))) / (count + 1), 2
            )
        bike.rating_count = count + 1
        bike.save(update_fields=['rating', 'rating_count'])
        bike_new_rating = float(bike.rating)

    trip.is_rated = True
    trip.rider_rating = rating
    trip.rider_review = review or ''
    trip.save(update_fields=['is_rated', 'rider_rating', 'rider_review'])

    return Response({
        'success': True,
        'rating': rating,
        'review': review or None,
        'bike_new_rating': bike_new_rating,
    })


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_user_trips(request):
    trips = Trip.objects.filter(renter=request.user.userprofile).select_related('bike', 'bike_owner__user').order_by('-trip_date')
    trip_list = []
    for t in trips:
        bike = t.bike
        owner = t.bike_owner
        trip_list.append({
            'id': t.id,
            'bike_name': bike.bike_name if bike else '',
            'bike_info': {
                'name': bike.bike_name if bike else '',
                'brand': bike.brand if bike else '',
                'model': bike.model if bike else '',
                'color': bike.color if bike else '',
                'id': bike.id if bike else None,
            },
            'owner_info': {
                'username': owner.user.username if owner else '',
                'id': owner.user.id if owner else None,
            },
            'start_location': {
                'address': t.origin_address or (bike.bike_address if bike else ''),
                'latitude': float(t.origin_latitude) if t.origin_latitude else None,
                'longitude': float(t.origin_longitude) if t.origin_longitude else None,
            },
            'end_location': {
                'address': t.destination_address or '',
                'latitude': float(t.destination_latitude) if t.destination_latitude else None,
                'longitude': float(t.destination_longitude) if t.destination_longitude else None,
            },
            'date': t.trip_date.isoformat() if t.trip_date else None,
            'status': t.status,
            'price': float(t.price) if t.price else None,
            'distance': float(t.distance) if t.distance else None,
            'payment_status': t.payment_status,
            'created_at': t.trip_date.isoformat() if t.trip_date else None,
            'rider_rating': t.rider_rating,
            'rider_review': t.rider_review,
        })
    return Response({
        'success': True,
        'trips': trip_list,
        'total_trips': len(trip_list),
        'user': request.user.username,
    })


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def cancel_trip(request, trip_id):
    trip = get_object_or_404(Trip, pk=trip_id, renter=request.user.userprofile)
    
    if trip.status in ['completed', 'ontrip']:
        return Response({'error': 'Trip cannot be canceled at this stage'}, status=drf_status.HTTP_400_BAD_REQUEST)

    if trip.payment_intent_id:
        try:
            pi = stripe.PaymentIntent.retrieve(trip.payment_intent_id)
            if pi.status in ('requires_capture', 'requires_payment_method', 'requires_confirmation'):
                stripe.PaymentIntent.cancel(trip.payment_intent_id)
            elif pi.status == 'succeeded':
                stripe.Refund.create(
                    payment_intent=trip.payment_intent_id,
                    reason='requested_by_customer',
                )
        except stripe.error.StripeError as e:
            logger.error(f"Stripe cleanup failed for trip {trip.id}: {e}")
        trip.payment_intent_id = ''

    trip.status = 'canceled'
    trip.trip_canceled = True
    trip.save()

    # Release the bike back to the marketplace
    if trip.bike:
        trip.bike.is_available = True
        trip.bike.bike_status = 'available'
        trip.bike.save(update_fields=['is_available', 'bike_status'])

    for user_id in [trip.renter.user.id, trip.bike_owner.user.id]:
        notify_user(user_id, 'Trip Cancelled', 'The trip has been cancelled', {
            'trip_id': trip.id,
            'trip_status': 'canceled',
            'status': 'canceled',
        })

    return Response({'message': 'Trip canceled successfully'})


def _trip_to_owner_dict(t):
    bike = t.bike
    renter = t.renter
    return {
        'id': t.id,
        'bike_name': bike.bike_name if bike else '',
        'bike_info': {
            'id': bike.id if bike else None,
            'brand': bike.brand if bike else '',
            'model': bike.model if bike else '',
            'color': bike.color if bike else '',
        },
        'start_location': {
            'address': t.origin_address or (bike.bike_address if bike else ''),
            'latitude': float(t.origin_latitude) if t.origin_latitude else None,
            'longitude': float(t.origin_longitude) if t.origin_longitude else None,
        },
        'end_location': {
            'address': t.destination_address or '',
            'latitude': float(t.destination_latitude) if t.destination_latitude else None,
            'longitude': float(t.destination_longitude) if t.destination_longitude else None,
        },
        'date': t.trip_date.isoformat() if t.trip_date else None,
        'status': t.status,
        'price': float(t.price) if t.price else None,
        'owner_payout': float(t.owner_payout) if t.owner_payout else None,
        'distance': float(t.distance) if t.distance else None,
        'payment_status': t.payment_status,
        'renter': {
            'username': renter.user.username,
            'id': renter.user.id,
            'phone': renter.phone_number if hasattr(renter, 'phone_number') else None,
        } if renter else None,
    }


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_owner_trips(request):
    from django.db.models import Sum
    owner = get_object_or_404(OwnerProfile, user=request.user)
    trips_qs = Trip.objects.filter(bike_owner=owner).select_related('bike', 'renter__user').order_by('-trip_date')

    status_filter = request.GET.get('status')
    date_from = request.GET.get('date_from')
    date_to = request.GET.get('date_to')
    if status_filter:
        trips_qs = trips_qs.filter(status=status_filter)
    if date_from:
        trips_qs = trips_qs.filter(trip_date__gte=date_from)
    if date_to:
        trips_qs = trips_qs.filter(trip_date__lte=date_to)

    trip_list = [_trip_to_owner_dict(t) for t in trips_qs]
    total_earnings = Trip.objects.filter(
        bike_owner=owner, status='completed'
    ).aggregate(Sum('owner_payout'))['owner_payout__sum'] or 0

    return Response({
        'success': True,
        'trips': trip_list,
        'total_trips': len(trip_list),
        'owner': {
            'username': request.user.username,
            'id': request.user.id,
            'total_earnings': float(total_earnings),
            'pending_balance': float(owner.pending_balance),
            'verification_status': owner.verification_status,
        },
    })


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_owner_trip_detail(request, trip_id):
    owner = get_object_or_404(OwnerProfile, user=request.user)
    trip = get_object_or_404(Trip, pk=trip_id, bike_owner=owner)
    return Response(_trip_to_owner_dict(trip))


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_owner_earnings(request):
    from django.db.models import Sum, Count
    owner = get_object_or_404(OwnerProfile, user=request.user)
    agg = Trip.objects.filter(bike_owner=owner, status='completed').aggregate(
        total_earnings=Sum('owner_payout'),
        total_trips=Count('id'),
    )
    return Response({
        'total_earnings': float(agg['total_earnings'] or 0),
        'total_trips': agg['total_trips'] or 0,
        'owner': {
            'username': request.user.username,
            'id': request.user.id,
            'total_earnings': float(agg['total_earnings'] or 0),
            'verification_status': owner.verification_status,
        },
    })


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_rider_trip_detail(request, trip_id):
    trip = get_object_or_404(Trip, pk=trip_id, renter=request.user.userprofile)
    bike = trip.bike
    owner = trip.bike_owner
    return Response({
        'id': trip.id,
        'status': trip.status,
        'trip_date': trip.trip_date.isoformat(),
        'start_time': trip.start_time.isoformat() if trip.start_time else None,
        'end_time': trip.end_time.isoformat() if trip.end_time else None,
        'bike_name': bike.bike_name if bike else '',
        'bike_info': {
            'id': bike.id if bike else None,
            'name': bike.bike_name if bike else '',
            'brand': bike.brand if bike else '',
            'model': bike.model if bike else '',
            'color': bike.color if bike else '',
        },
        'owner_info': {
            'username': owner.user.username if owner else '',
            'id': owner.user.id if owner else None,
        },
        'start_location': {
            'latitude': float(trip.origin_latitude) if trip.origin_latitude else None,
            'longitude': float(trip.origin_longitude) if trip.origin_longitude else None,
        },
        'end_location': {
            'latitude': float(trip.destination_latitude) if trip.destination_latitude else None,
            'longitude': float(trip.destination_longitude) if trip.destination_longitude else None,
        },
        'price': float(trip.price) if trip.price else None,
        'distance': float(trip.distance) if trip.distance else None,
        'payment_status': trip.payment_status,
        'is_rated': trip.is_rated,
    })


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def report_trip(request, trip_id):
    trip = get_object_or_404(Trip, id=trip_id)

    # Only the rider of this trip can report it
    if trip.renter.user != request.user:
        return Response({'error': 'Not your trip'}, status=403)

    category = request.data.get('category', '').strip()
    details = request.data.get('details', '').strip()

    if not category:
        return Response({'error': 'category is required'}, status=400)

    from django.core.mail import send_mail
    from django.conf import settings as _settings

    body = (
        f"Trip report submitted\n\n"
        f"Trip ID: {trip.id}\n"
        f"Rider: {request.user.username} ({request.user.email})\n"
        f"Category: {category}\n"
        f"Details: {details or 'None'}\n"
    )

    try:
        send_mail(
            subject=f"PaddlePlus Trip Report — Trip #{trip.id} — {category}",
            message=body,
            from_email=_settings.DEFAULT_FROM_EMAIL,
            recipient_list=[_settings.DEFAULT_FROM_EMAIL],
            fail_silently=True,
        )
    except Exception as e:
        logger.warning(f"report_trip: email failed: {e}")

    logger.info(f"Trip #{trip.id} reported by {request.user.username}: {category}")
    return Response({'message': 'Report submitted. Our team will review it within 24 hours.'})
