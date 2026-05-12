from datetime import timedelta
from django.shortcuts import render, get_object_or_404
from django.http import JsonResponse
from rest_framework import status
from rest_framework.exceptions import AuthenticationFailed
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from django.contrib.auth.models import User
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.authentication import JWTAuthentication
from django.contrib.auth import authenticate, logout
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_POST
from django.http import HttpResponse

from .models import UserProfile
from django.conf import settings
from Owner.serializers import UserProfileSerializer
from paddle_backend.Social_Auth import verify_social_token_for_login
from paddle_backend.rate_limit import rate_limit
from django.contrib.auth.decorators import login_required
from django.db import transaction
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync
import base64
import stripe
import logging
import random
import uuid
from django.core.files.base import ContentFile
from django.core.mail import send_mail
from django.core.cache import cache
logger = logging.getLogger(__name__)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def check_token_validity(request):
    return Response({'message': 'Token is valid'}, status=status.HTTP_200_OK)

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_rider_profile(request):
    profile = get_object_or_404(UserProfile, user=request.user)
    serializer = UserProfileSerializer(profile)
    return Response({
        'id': request.user.id,
        'username': request.user.username,
        'email': request.user.email,
        'phone_number': serializer.data['phone_number'],
        'address': serializer.data['address'],
        'profile_picture': serializer.data['profile_picture'],
        'verification_status': profile.verification_status,
        'has_payment_method': bool(profile.default_payment_method),
    })

def _sign_phase1(payload: dict) -> str:
    """Sign phase-1 registration data into a 30-minute JWT."""
    import jwt as pyjwt
    from datetime import datetime, timedelta
    payload = {**payload, 'exp': datetime.utcnow() + timedelta(minutes=30)}
    return pyjwt.encode(payload, settings.SECRET_KEY, algorithm='HS256')


def _decode_phase1(token: str) -> dict:
    import jwt as pyjwt
    return pyjwt.decode(token, settings.SECRET_KEY, algorithms=['HS256'])


@rate_limit('5/1h')
@api_view(['POST'])
@permission_classes([AllowAny])
def register_Rider(request):
    token = request.data.get('token')

    # ── Phase 2: token present → create Stripe session ─────────────────────
    if token:
        try:
            phase1 = _decode_phase1(token)
        except Exception:
            return Response({'error': 'Invalid or expired registration token'}, status=400)

        username = phase1.get('username')
        email    = phase1.get('email')
        password = phase1.get('password', '')
        apple_sub = phase1.get('apple_sub', '')

        # Final duplicate check (user may have registered in another tab)
        if User.objects.filter(username=username).exists():
            return Response({'error': 'Username already taken'}, status=400)
        if User.objects.filter(email__iexact=email).exists():
            return Response({'error': 'Email already registered'}, status=400)

        # ── DEMO MODE early return (new code — Stripe try/except below unchanged) ──
        if settings.DEMO_MODE:
            import uuid as _uuid
            fake_sid = f"vs_demo_{_uuid.uuid4().hex[:16]}"
            _demo_pw_key = str(uuid.uuid4())
            cache.set(f"reg_pw_{_demo_pw_key}", password, timeout=300)
            _demo_meta = {
                'username': username, 'email': email, 'pw_key': _demo_pw_key,
                'phone_number': request.data.get('phone_number', ''),
                'cpn': request.data.get('cpn', ''),
                'address': request.data.get('address', ''),
                'latitude': str(request.data.get('latitude', '')),
                'longitude': str(request.data.get('longitude', '')),
            }
            if apple_sub:
                _demo_meta['apple_sub'] = apple_sub
            cache.set(f"demo_reg_{fake_sid}", _demo_meta, 300)
            scheme = 'wss' if request.is_secure() else 'ws'
            host = request.get_host()
            return Response({
                'message': 'Demo mode — KYC skipped',
                'verification_url': 'about:blank',
                'session_id': fake_sid,
                'websocket_url': f"{scheme}://{host}/ws/verification/{fake_sid}/",
            })
        # ── end demo block ──────────────────────────────────────────────────────

        try:
            # Store password in cache with a random key — never send it to Stripe
            pw_key = str(uuid.uuid4())
            cache.set(f"reg_pw_{pw_key}", password, timeout=3600)

            metadata = {
                'username': username,
                'email': email,
                'pw_key': pw_key,
                'phone_number': request.data.get('phone_number', ''),
                'cpn': request.data.get('cpn', ''),
                'address': request.data.get('address', ''),
                'latitude': str(request.data.get('latitude', '')),
                'longitude': str(request.data.get('longitude', '')),
                'registration_type': 'rider',
            }
            if apple_sub:
                metadata['apple_sub'] = apple_sub

            verification_session = stripe.identity.VerificationSession.create(
                type='document',
                metadata=metadata,
            )

            profile_picture = request.data.get('profile_picture')
            if profile_picture:
                cache.set(f"reg_profile_pic_{verification_session.id}", profile_picture, timeout=3600)

            scheme = 'wss' if request.is_secure() else 'ws'
            host = request.get_host()
            return Response({
                'message': 'Please complete verification',
                'verification_url': verification_session.url,
                'session_id': verification_session.id,
                'websocket_url': f"{scheme}://{host}/ws/verification/{verification_session.id}/",
            })
        except Exception as e:
            return Response({'error': str(e)}, status=400)

    # ── Phase 1: validate and issue a short-lived token ──────────────────────
    username = request.data.get('username', '').strip()
    email    = request.data.get('email', '').strip().lower()
    password = request.data.get('password', '')

    if not username or not email or not password:
        return Response({'error': 'username, email and password are required'}, status=400)
    if User.objects.filter(username=username).exists():
        return Response({'error': 'Username already exists'}, status=400)
    if User.objects.filter(email__iexact=email).exists():
        return Response({'error': 'Email already exists'}, status=400)

    token = _sign_phase1({'username': username, 'email': email, 'password': password})
    return Response({'message': 'Proceed to step 2', 'token': token})



@rate_limit('10/15m')
@api_view(['POST'])
@permission_classes([AllowAny])
def Login_Rider(request):
    provider = request.data.get('provider')
    provider_token = request.data.get('provider_token')

    # Social login branch (Google / Apple)
    if provider and provider_token:
        try:
            email = verify_social_token_for_login(provider, provider_token)
        except ValueError as e:
            return Response({'error': str(e)}, status=status.HTTP_401_UNAUTHORIZED)
        try:
            user = User.objects.get(email__iexact=email)
        except User.DoesNotExist:
            # New social user — issue a phase-1 token so Flutter can go straight
            # to Register2Page (phone/CPN/photo) without the email/password form.
            from paddle_backend.Social_Auth import generate_username_from_email, get_apple_sub_from_token
            username = generate_username_from_email(email)
            payload = {
                'username': username,
                'email': email,
                'password': uuid.uuid4().hex,  # random, user will never use this
                'is_social': True,
                'provider': provider,
            }
            if provider.lower() == 'apple':
                try:
                    payload['apple_sub'] = get_apple_sub_from_token(provider_token)
                except Exception:
                    pass
            registration_token = _sign_phase1(payload)
            return Response({
                'needs_registration': True,
                'registration_token': registration_token,
                'email': email,
                'username': username,
            })
        if not hasattr(user, 'userprofile'):
            return Response({'error': 'Rider profile not found'}, status=status.HTTP_404_NOT_FOUND)
        return _build_login_response(user, request)

    # Standard email / password login
    email = request.data.get('email')
    username = request.data.get('username')
    password = request.data.get('password')

    if email and not username:
        try:
            username = User.objects.get(email__iexact=email).username
        except User.DoesNotExist:
            return Response({'error': 'Invalid credentials'}, status=status.HTTP_401_UNAUTHORIZED)

    user = authenticate(username=username, password=password)
    if not user:
        return Response({'error': 'Invalid credentials'}, status=status.HTTP_401_UNAUTHORIZED)

    return _build_login_response(user, request)


def _build_login_response(user, request):
    rider = get_object_or_404(UserProfile, user=user)

    if rider.verification_status != 'verified':
        return Response({
            'error': 'Account not verified',
            'verification_status': rider.verification_status
        }, status=status.HTTP_403_FORBIDDEN)

    refresh = RefreshToken.for_user(user)
    access = str(refresh.access_token)
    serializer = UserProfileSerializer(rider)
    scheme = 'wss' if request.is_secure() else 'ws'
    host = request.get_host()

    return Response({
        'user': {
            'id': user.id,
            'username': user.username,
            'email': user.email,
            'phone_number': serializer.data['phone_number'],
            'profile_picture': serializer.data['profile_picture'],
            'address': serializer.data['address'],
            'verification_status': rider.verification_status,
            'has_payment_method': bool(rider.default_payment_method),
            'access': access,
            'refresh': str(refresh),
            'ws_url': f'{scheme}://{host}/ws/notifications/user_{user.id}/?token={access}',
            'chat_ws_url': f'{scheme}://{host}/ws/chat/',
        }
    })


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def Logout_Rider(request):
    try:
        refresh_token = request.data["refresh"]
        token = RefreshToken(refresh_token)
        token.blacklist()
        return Response({'message': 'Successfully logged out'}, status=status.HTTP_200_OK)
    except Exception:
        return Response({'error': 'Invalid token'}, status=status.HTTP_400_BAD_REQUEST)

@api_view(['PUT', 'PATCH'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def update_Rider_profile(request):
    user_profile = request.user.userprofile
    user = request.user

    # Update User model fields (username, email)
    new_username = request.data.get('username', '').strip()
    new_email = request.data.get('email', '').strip().lower()
    if new_username and new_username != user.username:
        if User.objects.filter(username=new_username).exclude(pk=user.pk).exists():
            return Response({'error': 'Username already taken'}, status=400)
        user.username = new_username
    if new_email and new_email != user.email.lower():
        if User.objects.filter(email__iexact=new_email).exclude(pk=user.pk).exists():
            return Response({'error': 'Email already taken'}, status=400)
        user.email = new_email
    user.save()

    # Profile picture: accept base64 string from JSON body or multipart file
    profile_pic = request.data.get('profile_picture')
    if profile_pic and isinstance(profile_pic, str):
        try:
            if ',' in profile_pic:
                profile_pic = profile_pic.split(',', 1)[1]
            img_bytes = base64.b64decode(profile_pic)
            user_profile.profile_picture.save(
                f'rider_profile_{user_profile.pk}.jpg',
                ContentFile(img_bytes),
                save=False,
            )
        except Exception as e:
            logger.warning(f'Profile picture decode failed for rider {user_profile.pk}: {e}')
    elif 'profile_picture' in request.FILES:
        user_profile.profile_picture = request.FILES['profile_picture']

    # Update UserProfile fields
    for field in ('phone_number', 'address'):
        val = request.data.get(field)
        if val is not None:
            setattr(user_profile, field, val)
    user_profile.save()

    serializer = UserProfileSerializer(user_profile)
    return Response({
        'id': user.id,
        'username': user.username,
        'email': user.email,
        'phone_number': user_profile.phone_number,
        'profile_picture': serializer.data.get('profile_picture'),
        'verification_status': user_profile.verification_status,
        'address': user_profile.address,
    })

@api_view(['DELETE'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def delete_Rider_profile(request):
    user_profile = request.user.userprofile
    user_profile.delete()
    logout(request)
    return Response({'message': 'User profile deleted successfully'}, status=status.HTTP_204_NO_CONTENT)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def update_location(request):
    user_profile = request.user.userprofile
    latitude = request.data.get('latitude')
    longitude = request.data.get('longitude')

    if not latitude or not longitude:
        return Response({'error': 'Invalid data'}, status=400)

    user_profile.latitude = float(latitude)
    user_profile.longitude = float(longitude)
    user_profile.save(update_fields=['latitude', 'longitude'])

    # Broadcast rider's live position to the bike owner during an active trip
    from Trip.models import Trip
    active_trip = Trip.objects.filter(
        renter=user_profile,
        status='ontrip'
    ).select_related('bike_owner__user').first()

    if active_trip:
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f'notifications_{active_trip.bike_owner.user.id}',
            {
                'type': 'send_notification',
                'title': 'Rider Location',
                'message': '',
                'data': {
                    'notification_type': 'rider_location_update',
                    'trip_id': active_trip.id,
                    'latitude': float(latitude),
                    'longitude': float(longitude),
                }
            }
        )

    return Response({'status': 'location updated'})


@csrf_exempt
@require_POST
def stripe_webhook(request):
    payload = request.body
    sig_header = request.META.get('HTTP_STRIPE_SIGNATURE', '')
    
    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, settings.STRIPE_WEBHOOK_SECRET
        )
        
        session = event['data']['object']
        session_id = session.get('id', '')
        channel_layer = get_channel_layer()
        
        # Send verification status to WebSocket consumer
        async_to_sync(channel_layer.group_send)(
            f"verification_{session_id}",
            {
                "type": "verification_status",
                "status": event['type'],
                "session": session
            }
        )
        
        return HttpResponse(status=200)
        
    except stripe.error.SignatureVerificationError:
        return HttpResponse(status=400)
    except Exception as e:
        logger.error(f"Webhook error: {str(e)}")
        return HttpResponse(status=400)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def setup_payment_method(request):
    profile = request.user.userprofile

    if getattr(settings, 'SKIP_PAYMENTS', False):
        profile.default_payment_method = 'pm_demo'
        profile.save(update_fields=['default_payment_method'])
        return Response({
            'setup_intent_client_secret': 'demo_secret',
            'ephemeral_key': 'demo_ephemeral_key',
            'customer_id': 'cus_demo',
        })

    if not profile.stripe_customer_id:
        customer = stripe.Customer.create(
            email=request.user.email,
            name=request.user.get_full_name() or request.user.username,
            metadata={'rider_id': profile.id}
        )
        profile.stripe_customer_id = customer.id
        profile.save(update_fields=['stripe_customer_id'])

    ephemeral_key = stripe.EphemeralKey.create(
        customer=profile.stripe_customer_id,
        stripe_version='2024-06-20',
    )

    setup_intent = stripe.SetupIntent.create(
        customer=profile.stripe_customer_id,
        payment_method_types=['card'],
        usage='off_session',
    )

    return Response({
        'setup_intent_client_secret': setup_intent.client_secret,
        'ephemeral_key': ephemeral_key.secret,
        'customer_id': profile.stripe_customer_id,
    })


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def confirm_payment_method(request):
    profile = request.user.userprofile

    if getattr(settings, 'SKIP_PAYMENTS', False):
        profile.default_payment_method = 'pm_demo'
        profile.save(update_fields=['default_payment_method'])
        return Response({'success': True, 'message': 'Payment method saved'})

    payment_method_id = request.data.get('payment_method_id')
    setup_intent_secret = request.data.get('setup_intent_client_secret')

    if not payment_method_id and setup_intent_secret:
        si_id = setup_intent_secret.split('_secret_')[0]
        si = stripe.SetupIntent.retrieve(si_id)
        payment_method_id = si.payment_method

    if not payment_method_id:
        return Response({'error': 'payment_method_id required'}, status=status.HTTP_400_BAD_REQUEST)

    if not profile.stripe_customer_id:
        return Response({'error': 'No Stripe customer found'}, status=status.HTTP_400_BAD_REQUEST)

    stripe.Customer.modify(
        profile.stripe_customer_id,
        invoice_settings={'default_payment_method': payment_method_id}
    )
    profile.default_payment_method = payment_method_id
    profile.save(update_fields=['default_payment_method'])

    return Response({'success': True, 'message': 'Payment method saved'})



@rate_limit('5/15m')
@api_view(["POST"])
@permission_classes([AllowAny])
def forgot_password(request):
    email = request.data.get("email", "").strip().lower()
    if not email:
        return Response({"error": "Email is required"}, status=400)
    try:
        user = User.objects.get(email__iexact=email)
    except User.DoesNotExist:
        return Response({"message": "If that email is registered, an OTP has been sent."})

    otp = f"{random.randint(100000, 999999)}"
    cache.set(f"pw_reset_otp_{email}", otp, timeout=900)

    send_mail(
        subject="PaddlePlus - Password Reset OTP",
        message=f"Your password reset code is: {otp}\nValid for 15 minutes.\n\nIf you did not request this, ignore this email.",
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[user.email],
        fail_silently=False,
    )
    return Response({"message": "If that email is registered, an OTP has been sent."})


@api_view(["POST"])
@permission_classes([AllowAny])
def verify_reset_otp(request):
    email = request.data.get("email", "").strip().lower()
    otp = request.data.get("otp", "").strip()
    stored = cache.get(f"pw_reset_otp_{email}")
    if not stored or stored != otp:
        return Response({"error": "Invalid or expired OTP"}, status=400)

    reset_token = str(uuid.uuid4())
    cache.set(f"pw_reset_token_{reset_token}", email, timeout=600)
    cache.delete(f"pw_reset_otp_{email}")
    return Response({"reset_token": reset_token})


@api_view(["POST"])
@permission_classes([AllowAny])
def reset_password(request):
    token = request.data.get("reset_token", "")
    new_password = request.data.get("new_password", "")
    email = cache.get(f"pw_reset_token_{token}")
    if not email:
        return Response({"error": "Invalid or expired reset token"}, status=400)
    if len(new_password) < 8:
        return Response({"error": "Password must be at least 8 characters"}, status=400)
    try:
        user = User.objects.get(email__iexact=email)
    except User.DoesNotExist:
        return Response({"error": "User not found"}, status=404)
    user.set_password(new_password)
    user.save()
    cache.delete(f"pw_reset_token_{token}")
    return Response({"message": "Password reset successfully"})


@api_view(["POST"])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def change_password(request):
    old_password = request.data.get("old_password", "")
    new_password = request.data.get("new_password", "")
    if not request.user.check_password(old_password):
        return Response({"error": "Current password is incorrect"}, status=400)
    if len(new_password) < 8:
        return Response({"error": "New password must be at least 8 characters"}, status=400)
    request.user.set_password(new_password)
    request.user.save()
    return Response({"message": "Password changed successfully"})


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def list_payment_methods(request):
    profile = request.user.userprofile
    if not profile.stripe_customer_id:
        return Response({'payment_methods': []})
    pms = stripe.PaymentMethod.list(
        customer=profile.stripe_customer_id,
        type='card',
    )
    result = []
    default_pm = profile.default_payment_method
    for pm in pms.data:
        card = pm.card
        result.append({
            'id': pm.id,
            'brand': card.brand,
            'last4': card.last4,
            'exp_month': card.exp_month,
            'exp_year': card.exp_year,
            'is_default': pm.id == default_pm,
        })
    return Response({'payment_methods': result})


@api_view(['DELETE'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def delete_payment_method(request, pm_id):
    profile = request.user.userprofile
    # Verify the PM belongs to this customer before detaching
    try:
        pm = stripe.PaymentMethod.retrieve(pm_id)
        if pm.customer != profile.stripe_customer_id:
            return Response({'error': 'Not your payment method'}, status=403)
        stripe.PaymentMethod.detach(pm_id)
    except stripe.error.StripeError as e:
        return Response({'error': str(e)}, status=400)

    if profile.default_payment_method == pm_id:
        profile.default_payment_method = ''
        profile.save(update_fields=['default_payment_method'])

    return Response({'message': 'Payment method removed'})
