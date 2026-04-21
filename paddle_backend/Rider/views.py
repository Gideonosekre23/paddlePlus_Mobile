from datetime import timedelta, datetime
import logging
import os
import jwt 
from django.shortcuts import render, get_object_or_404
from django.http import JsonResponse
from rest_framework import status
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
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync
import stripe
from django.conf import settings
from .models import UserProfile
from Owner.serializers import UserProfileSerializer

# Import unified social auth functions
from paddle_backend.Social_Auth import (
    extract_email_from_social_token,
    create_social_payload,
    verify_social_token_for_login
)

stripe.api_key = settings.STRIPE_SECRET_KEY
logger = logging.getLogger(__name__)

@api_view(['GET']) 
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def Rider_list(request):
    riders = UserProfile.objects.all()
    serialized = UserProfileSerializer(riders, many=True)   
    return JsonResponse(serialized.data, safe=False)

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def check_token_validity(request):
    return Response({'message': 'Token is valid'}, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def register_Rider(request):
    token = request.data.get('token')
    
    if not token:
        # Check for social authentication first
        provider_token = request.data.get('provider_token')
        provider = request.data.get('provider')

        # Social Authentication
        if provider_token and provider:
            try:
                email = extract_email_from_social_token(provider, provider_token)
                
                if User.objects.filter(email=email).exists():
                    return Response({'error': 'Email already exists'}, status=400)

                payload = create_social_payload(provider, provider_token, email)

            except ValueError as e:
                return Response({'error': str(e)}, status=400)
            except Exception as e:
                return Response({'error': f'Social authentication failed: {str(e)}'}, status=400)

        # Traditional Authentication
        else:
            username = request.data.get('username')
            email = request.data.get('email')
            password = request.data.get('password')
            
            

            if not username or not email or not password:
                return Response({'error': 'Username, email, and password are required.'}, status=400)

            if User.objects.filter(username=username).exists():
                return Response({'error': 'Username already exists'}, status=400)
            if User.objects.filter(email=email).exists():
                return Response({'error': 'Email already exists'}, status=400)

            payload = {
                'username': username,
                'email': email,
                'password': password,
                
                'is_social': False,
                'exp': datetime.utcnow() + timedelta(minutes=30)
            }

        # Create JWT token for next step
        encoded_token = jwt.encode(payload, settings.SECRET_KEY, algorithm='HS256')

        return Response({
            'message': 'Basic info validated. Proceed to next step.',
            'token': encoded_token
        })

    # PHASE 2: Stripe Verification
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=['HS256'])
    except jwt.ExpiredSignatureError:
        return Response({'error': 'Token has expired'}, status=400)
    except jwt.InvalidTokenError:
        return Response({'error': 'Invalid token'}, status=400)

    cpn = request.data.get('cpn')
    phone_number = request.data.get('phone_number')
    latitude = request.data.get('latitude')
    longitude = request.data.get('longitude')
    profile_picture = request.data.get('profile_picture')
    address = request.data.get('address')

    try:
        verification_session = stripe.identity.VerificationSession.create(
            type='document',
            metadata={
                'username': payload['username'],
                'email': payload['email'],
                'password': payload.get('password', ''),
                'is_social': str(payload['is_social']),
                'provider': payload.get('provider', ''),
                'address': address,
                'phone_number': phone_number,
                'cpn': cpn,
                'latitude': latitude,
                'longitude': longitude,
                'apple_sub': payload.get('apple_sub', ''),
                'registration_type': 'rider'
            }
        )

        # Store profile picture in cache — too large for Stripe's 500-char metadata limit
        if profile_picture:
            from django.core.cache import cache
            cache.set(f"reg_profile_pic_{verification_session.id}", profile_picture, timeout=3600)

        ws_scheme = "wss" if not settings.DEBUG else "ws"
        ws_host = os.getenv('WS_HOST', request.get_host().split(':')[0])
        daphne_port = os.getenv('WS_PORT', '8000')
        websocket_url = f"{ws_scheme}://{ws_host}:{daphne_port}/ws/verification/{verification_session.id}/"

        return Response({
            'message': 'Verification session started',
            'verification_url': verification_session.url,
            'session_id': verification_session.id,
            'websocket_url': websocket_url
        })

    except Exception as e:
        logger.error(f"Error during Stripe verification session creation: {e}", exc_info=True)
        return Response({'error': 'A server error occurred. Please try again.'}, status=500)


@api_view(['POST'])
@permission_classes([AllowAny])
def Login_Rider(request):
    provider = request.data.get('provider')
    provider_token= request.data.get('provider_token')
    username = request.data.get('username')
    email = request.data.get('email')       
    password = request.data.get('password')

    # Social login
    if provider and provider_token:
        try:
            email = verify_social_token_for_login(provider, provider_token)
            user = User.objects.get(email=email)
        except User.DoesNotExist:
            return Response({'error': 'User does not exist. Please register first.'}, status=404)
        except ValueError as e:
            return Response({'error': str(e)}, status=400)

    # Traditional login - Accept BOTH username and email
    elif (username or email) and password:
        user = None
        
        if email:
            # Login with email
            try:
                user_obj = User.objects.get(email=email)
                user = authenticate(username=user_obj.username, password=password)
            except User.DoesNotExist:
                return Response({'error': 'Invalid email or password'}, status=400)
        elif username:
            # Login with username
            user = authenticate(username=username, password=password)
        
        if not user:
            return Response({'error': 'Invalid credentials'}, status=400)
            
    else:
        return Response({'error': 'Please provide username/email and password'}, status=400)

    # Check verification 
    try:
        rider = get_object_or_404(UserProfile, user=user)
    except Exception:
        return Response({'error': 'Rider profile not found'}, status=404)

    if rider.verification_status != 'verified':
        return Response({
            'error': 'Account not verified',
            'verification_status': rider.verification_status
        }, status=status.HTTP_403_FORBIDDEN)

    refresh = RefreshToken.for_user(user)
    serialized_rider = UserProfileSerializer(rider)
    notification_channel = f"user_{user.id}_{refresh.access_token}"

    return Response({
        'user': {
            "id": user.id,
            'username': user.username,
            'email': user.email,
            'phone_number': serialized_rider.data['phone_number'],
            'profile_picture': serialized_rider.data['profile_picture'],
            'address': serialized_rider.data['address'],
            'verification_status': rider.verification_status,
            'access': str(refresh.access_token),
            'refresh': str(refresh),
            'chat_ws_url': f"/ws/chat/{{trip_id}}/?token={str(refresh.access_token)}",
            'ws_url': f"/ws/notifications/{notification_channel}/",
        }
    })
 




@csrf_exempt
@require_POST
def stripe_webhook(request):
    from django.core.cache import cache

    payload = request.body
    sig_header = request.META.get('HTTP_STRIPE_SIGNATURE', '')

    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, settings.STRIPE_WEBHOOK_SECRET
        )
    except ValueError:
        return HttpResponse(status=400)
    except stripe.error.SignatureVerificationError:
        return HttpResponse(status=400)

    # Idempotency: Stripe retries failed webhooks — skip if already processed
    event_id = event.get('id', '')
    if event_id and cache.get(f"stripe_event_{event_id}"):
        return HttpResponse(status=200)
    if event_id:
        cache.set(f"stripe_event_{event_id}", True, timeout=86400)

    if event['type'] == 'identity.verification_session.verified':
        session = event['data']['object']
        session_id = session.get('id')
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f"verification_{session_id}",
            {
                "type": "verification_status",
                "status": event['type'],
                "session": session,
            }
        )

    elif event['type'] == 'payment_intent.succeeded':
        pi = event['data']['object']
        pi_id = pi.get('id')
        metadata = pi.get('metadata', {})
        rider_id = metadata.get('rider_id')
        owner_user_id = metadata.get('owner_user_id')
        payment_method_id = pi.get('payment_method')

        # Save default payment method to rider profile
        if rider_id and payment_method_id:
            try:
                rider_profile = UserProfile.objects.get(id=rider_id)
                rider_profile.default_payment_method = payment_method_id
                rider_profile.save(update_fields=['default_payment_method'])
            except UserProfile.DoesNotExist:
                logger.error(f"Rider {rider_id} not found for payment_intent webhook")

        # Update cached request payment_status and notify owner.
        # Fall back to PI metadata if the cache key was set before webhook arrived.
        temp_request_id = cache.get(f"pending_request_pi_{pi_id}") or metadata.get('temp_request_id')
        if temp_request_id:
            request_data = cache.get(f"pending_request_{temp_request_id}")
            if request_data:
                request_data['payment_status'] = 'completed'
                timeout = 1000
                cache.set(f"pending_request_{temp_request_id}", request_data, timeout=timeout)
                cache.set(f"pending_request_bike_{request_data.get('bike_id')}", request_data, timeout=timeout)
                cache.set(f"pending_request_rider_{rider_id}", request_data, timeout=timeout)

            if owner_user_id:
                channel_layer = get_channel_layer()
                async_to_sync(channel_layer.group_send)(
                    f'notifications_{owner_user_id}',
                    {
                        'type': 'send_notification',
                        'title': 'New Ride Request',
                        'message': f"Rider payment confirmed. New ride request at {metadata.get('pickup_location', 'unknown location')}",
                        'data': {
                            'temp_request_id': temp_request_id,
                            'rider_id': rider_id,
                            'bike_id': metadata.get('bike_id'),
                            'estimated_price': metadata.get('estimated_price'),
                            'pickup_location': metadata.get('pickup_location'),
                        }
                    }
                )

    return HttpResponse(status=200)

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def setup_payment(request):
    """Create a Stripe SetupIntent so Flutter can save a card for future charges."""
    if not hasattr(request.user, 'userprofile'):
        return Response({'error': 'Rider profile not found'}, status=status.HTTP_404_NOT_FOUND)

    rider_profile = request.user.userprofile

    try:
        # Create or reuse Stripe customer
        if not rider_profile.stripe_customer_id:
            customer = stripe.Customer.create(
                email=request.user.email,
                name=request.user.username,
                metadata={'rider_id': rider_profile.id}
            )
            rider_profile.stripe_customer_id = customer.id
            rider_profile.save(update_fields=['stripe_customer_id'])

        setup_intent = stripe.SetupIntent.create(
            customer=rider_profile.stripe_customer_id,
            payment_method_types=['card'],
            metadata={'rider_id': rider_profile.id}
        )

        return Response({
            'client_secret': setup_intent.client_secret,
            'customer_id': rider_profile.stripe_customer_id,
        }, status=status.HTTP_200_OK)

    except stripe.error.StripeError as e:
        return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)


@csrf_exempt
@require_POST
def stripe_setup_webhook(request):
    """
    Handle setup_intent.succeeded webhook to persist saved payment method.
    Register this URL in your Stripe dashboard for the rider webhook.
    """
    payload = request.body
    sig_header = request.META.get('HTTP_STRIPE_SIGNATURE', '')

    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, settings.STRIPE_WEBHOOK_SECRET
        )
    except (ValueError, stripe.error.SignatureVerificationError):
        return HttpResponse(status=400)

    from django.core.cache import cache
    event_id = event.get('id', '')
    if event_id and cache.get(f"stripe_event_{event_id}"):
        return HttpResponse(status=200)
    if event_id:
        cache.set(f"stripe_event_{event_id}", True, timeout=86400)

    if event['type'] == 'setup_intent.succeeded':
        si = event['data']['object']
        rider_id = si.get('metadata', {}).get('rider_id')
        payment_method_id = si.get('payment_method')

        if rider_id and payment_method_id:
            try:
                rider_profile = UserProfile.objects.get(id=rider_id)
                rider_profile.default_payment_method = payment_method_id
                rider_profile.save(update_fields=['default_payment_method'])
                logger.info(f"Saved payment method for rider {rider_id}")
            except UserProfile.DoesNotExist:
                logger.error(f"Rider {rider_id} not found for setup_intent webhook")

    return HttpResponse(status=200)


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

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_Rider_profile(request):
    if not hasattr(request.user, 'userprofile'):
        return Response({'error': 'Rider profile not found'}, status=status.HTTP_404_NOT_FOUND)
    rider = request.user.userprofile
    serializer = UserProfileSerializer(rider)
    return Response({
        **serializer.data,
        'rider_rating': float(rider.rider_rating),
        'rider_rating_count': rider.rider_rating_count,
        'stripe_customer_id': rider.stripe_customer_id,
        'has_payment_method': bool(rider.default_payment_method),
    })


@api_view(['PUT'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def update_Rider_profile(request):
    if not hasattr(request.user, 'userprofile'):
        return Response({'error': 'Rider profile not found'}, status=status.HTTP_404_NOT_FOUND)
    user_profile = request.user.userprofile
    serializer = UserProfileSerializer(user_profile, data=request.data, partial=True)
    
    if serializer.is_valid():
        serializer.save()
        
        # Refresh from database
        user_profile.refresh_from_db()
        request.user.refresh_from_db()
        
        
        user_data = {
            
            'username': request.user.username,
            'email': request.user.email,
            'phone_number': user_profile.phone_number,       
            'address': user_profile.address,
            'profile_picture': request.build_absolute_uri(user_profile.profile_picture.url) if user_profile.profile_picture else None,  # ← snake_case
            'verification_status': user_profile.verification_status  
        }
        
        return Response(user_data)
    
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)



@api_view(['DELETE'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def delete_Rider_profile(request):
    if not hasattr(request.user, 'userprofile'):
        return Response({'error': 'Rider profile not found'}, status=status.HTTP_404_NOT_FOUND)
    user_profile = request.user.userprofile
    user_profile.delete()
    logout(request)
    return Response({'message': 'User profile deleted successfully'}, status=status.HTTP_204_NO_CONTENT)

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def search_Rider_profile(request, username):
    try:
        user = User.objects.get(username=username)
        user_profile = user.userprofile
        serializer = UserProfileSerializer(user_profile)
        return Response(serializer.data)
    except (User.DoesNotExist, User.userprofile.RelatedObjectDoesNotExist):
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def update_location(request):
    if not hasattr(request.user, 'userprofile'):
        return Response({'error': 'Rider profile not found'}, status=status.HTTP_404_NOT_FOUND)
    user_profile = request.user.userprofile
    latitude = request.data.get('latitude')
    longitude = request.data.get('longitude')
    
    if latitude and longitude:
        user_profile.latitude = float(latitude)
        user_profile.longitude = float(longitude)
        user_profile.save()
        return Response({'status': 'location updated'})
    return Response({'error': 'Invalid data'}, status=400)

