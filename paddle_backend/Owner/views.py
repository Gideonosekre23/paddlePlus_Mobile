from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated, AllowAny
from django.contrib.auth.models import User
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_POST
from django.http import HttpResponse

from django.conf import settings
from django.contrib.auth import authenticate, logout
from django.core.cache import cache
from django.core.mail import send_mail
from .models import OwnerProfile, PayoutRecord
from .serializers import OwnerProfileSerializer
from django.db.models import Sum
from django.db import transaction
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync
from paddle_backend.Social_Auth import verify_social_token_for_login
from paddle_backend.rate_limit import rate_limit
import base64
import stripe
import logging
import random
import uuid
from django.core.files.base import ContentFile
logger = logging.getLogger(__name__)

@rate_limit('5/15m')
@api_view(['POST'])
@permission_classes([AllowAny])
def forgot_password(request):
    email = request.data.get('email', '').strip().lower()
    if not email:
        return Response({'error': 'Email is required'}, status=400)
    try:
        user = User.objects.get(email__iexact=email)
        if not hasattr(user, 'owner_profile'):
            return Response({'message': 'If that email is registered, an OTP has been sent.'})
    except User.DoesNotExist:
        return Response({'message': 'If that email is registered, an OTP has been sent.'})
    otp = f"{random.randint(100000, 999999)}"
    cache.set(f"owner_pw_reset_otp_{email}", otp, timeout=900)
    send_mail(
        subject='PaddlePlus — Password Reset OTP',
        message=f'Your password reset code is: {otp}\nValid for 15 minutes.',
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[user.email],
        fail_silently=False,
    )
    return Response({'message': 'If that email is registered, an OTP has been sent.'})


@api_view(['POST'])
@permission_classes([AllowAny])
def verify_reset_otp(request):
    email = request.data.get('email', '').strip().lower()
    otp = request.data.get('otp', '').strip()
    stored = cache.get(f"owner_pw_reset_otp_{email}")
    if not stored or stored != otp:
        return Response({'error': 'Invalid or expired OTP'}, status=400)
    reset_token = str(uuid.uuid4())
    cache.set(f"owner_pw_reset_token_{reset_token}", email, timeout=600)
    cache.delete(f"owner_pw_reset_otp_{email}")
    return Response({'reset_token': reset_token})


@api_view(['POST'])
@permission_classes([AllowAny])
def reset_password(request):
    token = request.data.get('reset_token', '')
    new_password = request.data.get('new_password', '')
    email = cache.get(f"owner_pw_reset_token_{token}")
    if not email:
        return Response({'error': 'Invalid or expired reset token'}, status=400)
    if len(new_password) < 8:
        return Response({'error': 'Password must be at least 8 characters'}, status=400)
    try:
        user = User.objects.get(email__iexact=email)
    except User.DoesNotExist:
        return Response({'error': 'User not found'}, status=404)
    user.set_password(new_password)
    user.save()
    cache.delete(f"owner_pw_reset_token_{token}")
    return Response({'message': 'Password reset successfully'})


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def change_password(request):
    old_password = request.data.get('old_password', '')
    new_password = request.data.get('new_password', '')
    if not request.user.check_password(old_password):
        return Response({'error': 'Current password is incorrect'}, status=400)
    if len(new_password) < 8:
        return Response({'error': 'New password must be at least 8 characters'}, status=400)
    request.user.set_password(new_password)
    request.user.save()
    return Response({'message': 'Password changed successfully'})


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def check_token_validity(request):
    return Response({'message': 'Token is valid'}, status=status.HTTP_200_OK)



def _sign_phase1_owner(payload: dict) -> str:
    import jwt as pyjwt
    from datetime import datetime, timedelta
    payload = {**payload, 'exp': datetime.utcnow() + timedelta(minutes=30)}
    return pyjwt.encode(payload, settings.SECRET_KEY, algorithm='HS256')


def _decode_phase1_owner(token: str) -> dict:
    import jwt as pyjwt
    return pyjwt.decode(token, settings.SECRET_KEY, algorithms=['HS256'])


@rate_limit('5/1h')
@api_view(['POST'])
@permission_classes([AllowAny])
def register_Owner(request):
    token = request.data.get('token')

    # ── Phase 2: token present → create Stripe session ──────────────────────
    if token:
        try:
            phase1 = _decode_phase1_owner(token)
        except Exception:
            return Response({'error': 'Invalid or expired registration token'}, status=400)

        username = phase1.get('username')
        email    = phase1.get('email')
        password = phase1.get('password', '')

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
            cache.set(f"demo_reg_{fake_sid}", _demo_meta, 300)
            scheme = 'wss' if request.is_secure() else 'ws'
            host = request.get_host()
            return Response({
                'message': 'Demo mode — KYC skipped',
                'verification_url': 'about:blank',
                'session_id': fake_sid,
                'websocket_url': f"{scheme}://{host}/ws/owner/verification/{fake_sid}/",
            })
        # ── end demo block ──────────────────────────────────────────────────────

        try:
            pw_key = str(uuid.uuid4())
            cache.set(f"reg_pw_{pw_key}", password, timeout=3600)

            verification_session = stripe.identity.VerificationSession.create(
                type='document',
                metadata={
                    'username': username,
                    'email': email,
                    'pw_key': pw_key,
                    'phone_number': request.data.get('phone_number', ''),
                    'cpn': request.data.get('cpn', ''),
                    'address': request.data.get('address', ''),
                    'latitude': str(request.data.get('latitude', '')),
                    'longitude': str(request.data.get('longitude', '')),
                    'registration_type': 'owner',
                }
            )

            scheme = 'wss' if request.is_secure() else 'ws'
            host = request.get_host()
            return Response({
                'message': 'Please complete verification',
                'verification_url': verification_session.url,
                'session_id': verification_session.id,
                'websocket_url': f"{scheme}://{host}/ws/owner/verification/{verification_session.id}/",
            })
        except Exception as e:
            return Response({'error': str(e)}, status=400)

    # ── Phase 1: validate and issue a short-lived token ─────────────────────
    username = request.data.get('username', '').strip()
    email    = request.data.get('email', '').strip().lower()
    password = request.data.get('password', '')

    if not username or not email or not password:
        return Response({'error': 'username, email and password are required'}, status=400)
    if User.objects.filter(username=username).exists():
        return Response({'error': 'Username already exists'}, status=400)
    if User.objects.filter(email__iexact=email).exists():
        return Response({'error': 'Email already exists'}, status=400)

    token = _sign_phase1_owner({'username': username, 'email': email, 'password': password})
    return Response({'message': 'Proceed to step 2', 'token': token})





@rate_limit('10/15m')
@api_view(['POST'])
@permission_classes([AllowAny])
def Login_Owner(request):
    provider = request.data.get('provider')
    provider_token = request.data.get('provider_token') or request.data.get('id_token')

    # Social login branch (Google / Apple) — mirrors Login_Rider behaviour
    if provider and provider_token:
        try:
            email = verify_social_token_for_login(provider, provider_token)
        except ValueError as e:
            return Response({'error': str(e)}, status=status.HTTP_401_UNAUTHORIZED)
        try:
            user = User.objects.get(email__iexact=email)
        except User.DoesNotExist:
            return Response(
                {'error': 'No owner account found for this account. Please register first.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        if not hasattr(user, 'owner_profile'):
            return Response({'error': 'Owner profile not found'}, status=status.HTTP_404_NOT_FOUND)
        return _build_owner_login_response(user, request)

    # Standard username / password login
    username = request.data.get('username', '').strip()
    email = request.data.get('email', '').strip().lower()
    password = request.data.get('password', '')

    if email and not username:
        try:
            username = User.objects.get(email__iexact=email).username
        except User.DoesNotExist:
            return Response({'error': 'Invalid credentials'}, status=status.HTTP_400_BAD_REQUEST)

    user = authenticate(username=username, password=password)
    if not user:
        return Response({'error': 'Invalid credentials'}, status=status.HTTP_400_BAD_REQUEST)

    if not hasattr(user, 'owner_profile'):
        return Response({'error': 'No owner account found for this user'}, status=status.HTTP_403_FORBIDDEN)

    return _build_owner_login_response(user, request)

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def Logout_Owner(request):
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
def update_Owner_profile(request):
    owner = request.user.owner_profile
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
            owner.profile_picture.save(
                f'owner_profile_{owner.pk}.jpg',
                ContentFile(img_bytes),
                save=False,
            )
        except Exception as e:
            logger.warning(f'Profile picture decode failed for owner {owner.pk}: {e}')
    elif 'profile_picture' in request.FILES:
        owner.profile_picture = request.FILES['profile_picture']

    # Update OwnerProfile fields
    for field in ('phone_number', 'address'):
        val = request.data.get(field)
        if val is not None:
            setattr(owner, field, val)
    owner.save()

    serializer = OwnerProfileSerializer(owner)
    return Response({
        'id': user.id,
        'username': user.username,
        'email': user.email,
        'phone_number': owner.phone_number,
        'profile_picture': serializer.data.get('profile_picture'),
        'verification_status': owner.verification_status,
        'address': owner.address,
    })

@api_view(['DELETE'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def delete_Owner_profile(request):
    owner = request.user.owner_profile
    owner.delete()
    logout(request)
    return Response({'message': 'Profile deleted successfully'}, status=status.HTTP_204_NO_CONTENT)

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_owner_profile(request):
    user = request.user
    if not hasattr(user, 'owner_profile'):
        return Response({'error': 'Owner profile not found'}, status=status.HTTP_404_NOT_FOUND)
    owner = user.owner_profile
    serializer = OwnerProfileSerializer(owner)
    return Response(serializer.data)


def _build_owner_login_response(user, request=None):
    from Trip.models import Trip
    owner = get_object_or_404(OwnerProfile, user=user)
    if owner.verification_status != 'verified':
        return Response(
            {'error': 'Account not verified', 'verification_status': owner.verification_status},
            status=status.HTTP_403_FORBIDDEN,
        )
    refresh = RefreshToken.for_user(user)
    access = str(refresh.access_token)
    serializer = OwnerProfileSerializer(owner)

    total_earnings = Trip.objects.filter(
        bike_owner=owner, status='completed'
    ).aggregate(Sum('owner_payout'))['owner_payout__sum'] or 0

    if request is not None:
        scheme = 'wss' if request.is_secure() else 'ws'
        host = request.get_host()
    else:
        scheme = 'ws'
        host = 'localhost:8000'

    return Response({
        'user': {
            'id': user.id,
            'username': user.username,
            'email': user.email,
            'phone_number': serializer.data['phone_number'],
            'profile_picture': serializer.data['profile_picture'],
            'verification_status': owner.verification_status,
            'total_earnings': float(total_earnings),
            'pending_balance': float(owner.pending_balance),
            'access': access,
            'refresh': str(refresh),
            'ws_url': f'{scheme}://{host}/ws/notifications/user_{user.id}/?token={access}',
            'chat_ws_url': f'{scheme}://{host}/ws/chat/',
        }
    })



@csrf_exempt
@require_POST
def stripe_webhook(request):
    payload = request.body
    sig_header = request.META.get('HTTP_STRIPE_SIGNATURE', '')

    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, settings.STRIPE_WEBHOOK_SECRET
        )
    except stripe.error.SignatureVerificationError:
        return HttpResponse(status=400)
    except Exception as e:
        logger.error(f"Webhook error: {str(e)}")
        return HttpResponse(status=400)

    event_type = event['type']
    obj = event['data']['object']

    # Stripe Connect: owner completed bank account onboarding
    if event_type == 'account.updated':
        stripe_account_id = obj.get('id')
        if stripe_account_id and obj.get('payouts_enabled'):
            OwnerProfile.objects.filter(
                stripe_account_id=stripe_account_id
            ).update(stripe_account_id=stripe_account_id)
            logger.info(f"Owner Stripe account {stripe_account_id} payouts enabled")
        return HttpResponse(status=200)

    # Stripe Identity: verification session events → forward to WebSocket
    session_id = obj.get('id', '')
    channel_layer = get_channel_layer()
    try:
        async_to_sync(channel_layer.group_send)(
            f"verification_{session_id}",
            {
                "type": "verification_status",
                "status": event_type,
                "session": obj,
            }
        )
    except Exception as e:
        logger.warning(f"WebSocket group_send failed: {e}")

    return HttpResponse(status=200)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def connect_stripe_account(request):
    owner = get_object_or_404(OwnerProfile, user=request.user)

    if not owner.stripe_account_id:
        account = stripe.Account.create(
            type='express',
            email=request.user.email,
            capabilities={'transfers': {'requested': True}},
            metadata={'owner_id': owner.id}
        )
        owner.stripe_account_id = account.id
        owner.save(update_fields=['stripe_account_id'])

    frontend_url = getattr(settings, 'FRONTEND_URL', 'http://localhost:3000')
    account_link = stripe.AccountLink.create(
        account=owner.stripe_account_id,
        refresh_url=f"{frontend_url}/owner/payment/connect/refresh/",
        return_url=f"{frontend_url}/owner/payment/connect/complete/",
        type='account_onboarding',
    )

    return Response({
        'onboarding_url': account_link.url,
        'stripe_account_id': owner.stripe_account_id,
    })


@api_view(['GET', 'POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def request_withdrawal(request):
    owner = get_object_or_404(OwnerProfile, user=request.user)

    if request.method == 'GET':
        stripe_ready = False
        if owner.stripe_account_id:
            try:
                acct = stripe.Account.retrieve(owner.stripe_account_id)
                stripe_ready = acct.charges_enabled and acct.payouts_enabled
            except stripe.error.StripeError:
                pass
        return Response({
            'pending_balance': float(owner.pending_balance),
            'stripe_ready': stripe_ready,
        })

    # POST — trigger payout
    if owner.pending_balance <= 0:
        return Response({'error': 'No balance to withdraw'}, status=400)

    min_withdrawal = 100  # cents ($1)
    amount_cents = int(owner.pending_balance * 100)
    if amount_cents < min_withdrawal:
        return Response({'error': 'Minimum withdrawal is $1'}, status=400)

    if getattr(settings, 'SKIP_PAYMENTS', False):
        from django.db import transaction
        with transaction.atomic():
            PayoutRecord.objects.create(
                owner=owner,
                amount=owner.pending_balance,
                stripe_transfer_id='tr_demo',
                stripe_payout_id='po_demo',
                method='instant',
                status='paid',
            )
            OwnerProfile.objects.filter(pk=owner.pk).update(pending_balance=0)
        owner.refresh_from_db()
        return Response({
            'message': 'Withdrawal successful. Arrives in minutes.',
            'amount': float(owner.pending_balance),
            'method': 'instant',
            'stripe_transfer_id': 'tr_demo',
            'stripe_payout_id': 'po_demo',
        })

    if not owner.stripe_account_id:
        return Response({
            'error': 'Connect your bank account first',
            'setup_required': True,
        }, status=400)

    try:
        acct = stripe.Account.retrieve(owner.stripe_account_id)
    except stripe.error.StripeError as e:
        return Response({'error': f'Could not verify Stripe account: {e}'}, status=400)

    if not (acct.charges_enabled and acct.payouts_enabled):
        return Response({
            'error': 'Bank account onboarding is not complete',
            'setup_required': True,
        }, status=400)

    # Transfer from platform Stripe balance → owner's Stripe Connect account
    try:
        transfer = stripe.Transfer.create(
            amount=amount_cents,
            currency='usd',
            destination=owner.stripe_account_id,
            metadata={'owner_id': owner.id, 'type': 'wallet_withdrawal'},
        )
    except stripe.error.StripeError as e:
        logger.error(f"Withdrawal transfer failed for owner {owner.id}: {e}")
        return Response({'error': 'Transfer failed', 'message': str(e)}, status=400)

    # Payout from owner's Stripe account → their bank/debit card
    payout_method = 'instant'
    payout_id = ''
    try:
        payout = stripe.Payout.create(
            amount=amount_cents,
            currency='usd',
            method='instant',
            stripe_account=owner.stripe_account_id,
        )
        payout_id = payout.id
    except stripe.error.InvalidRequestError:
        # Instant payout not supported for this account — fall back to standard (2 days)
        payout_method = 'standard'
        try:
            payout = stripe.Payout.create(
                amount=amount_cents,
                currency='usd',
                method='standard',
                stripe_account=owner.stripe_account_id,
            )
            payout_id = payout.id
        except stripe.error.StripeError as e:
            logger.error(f"Payout creation failed for owner {owner.id}: {e}")
            return Response({'error': 'Payout failed', 'message': str(e)}, status=400)
    except stripe.error.StripeError as e:
        logger.error(f"Payout creation failed for owner {owner.id}: {e}")
        return Response({'error': 'Payout failed', 'message': str(e)}, status=400)

    # Record the payout and zero out the balance atomically
    from django.db import transaction
    with transaction.atomic():
        PayoutRecord.objects.create(
            owner=owner,
            amount=owner.pending_balance,
            stripe_transfer_id=transfer.id,
            stripe_payout_id=payout_id,
            method=payout_method,
            status='paid',
        )
        OwnerProfile.objects.filter(pk=owner.pk).update(pending_balance=0)

    owner.refresh_from_db()
    arrival_message = 'Arrives in minutes' if payout_method == 'instant' else 'Arrives in 1–2 business days'
    return Response({
        'message': f'Withdrawal successful. {arrival_message}.',
        'amount': float(owner.pending_balance),
        'method': payout_method,
        'stripe_transfer_id': transfer.id,
        'stripe_payout_id': payout_id,
    })


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def payout_history(request):
    owner = get_object_or_404(OwnerProfile, user=request.user)
    records = owner.payouts.order_by('-created_at')[:50]
    return Response({
        'payouts': [
            {
                'id': r.id,
                'amount': float(r.amount),
                'method': r.method,
                'status': r.status,
                'created_at': r.created_at.isoformat(),
            }
            for r in records
        ]
    })


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def connect_stripe_status(request):
    owner = get_object_or_404(OwnerProfile, user=request.user)

    if not owner.stripe_account_id:
        return Response({
            'connected': False,
            'charges_enabled': False,
            'payouts_enabled': False,
            'message': 'Bank account not connected yet',
        })

    account = stripe.Account.retrieve(owner.stripe_account_id)
    ready = account.charges_enabled and account.payouts_enabled
    return Response({
        'connected': ready,
        'charges_enabled': account.charges_enabled,
        'payouts_enabled': account.payouts_enabled,
        'message': 'Ready to receive payouts' if ready else 'Onboarding incomplete',
    })