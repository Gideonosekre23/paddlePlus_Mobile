import logging
import os
import jwt
from datetime import timedelta, datetime 
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
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync
from django.contrib.auth import authenticate, logout
from django.conf import settings
from django.utils import timezone
from .models import OwnerProfile
from .serializers import OwnerProfileSerializer
from django.db import transaction
import stripe

# Import unified social auth functions
from paddle_backend.Social_Auth import (
    extract_email_from_social_token,
    create_social_payload,
    verify_social_token_for_login
)

logger = logging.getLogger(__name__)

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def owner_dashboard(request):
    """Aggregated earnings, trip counts, and per-bike performance for the owner."""
    from django.db.models import Sum, Count
    from Trip.models import Trip
    from Bikes.models import Bikes

    try:
        owner = request.user.owner_profile
    except Exception:
        return Response({'error': 'Owner profile not found'}, status=status.HTTP_404_NOT_FOUND)

    now = timezone.now()
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    completed_trips = Trip.objects.filter(bike_owner=owner, payment_status='completed')

    totals = completed_trips.aggregate(
        total_earnings=Sum('owner_payout'),
        total_trips=Count('id'),
    )
    month_totals = completed_trips.filter(trip_date__gte=month_start).aggregate(
        this_month_earnings=Sum('owner_payout'),
        this_month_trips=Count('id'),
    )

    bikes = Bikes.objects.filter(owner=owner).order_by('-total_earnings')
    bikes_data = [
        {
            'id': b.id,
            'name': b.bike_name,
            'brand': b.brand,
            'model': b.model,
            'total_earnings': float(b.total_earnings),
            'total_trips': b.total_trips,
            'rating': float(b.rating),
            'rating_count': b.rating_count,
            'is_available': b.is_available,
            'is_active': b.is_active,
            'bike_status': b.bike_status,
            'hardware_status': b.hardware_status,
        }
        for b in bikes
    ]

    return Response({
        'total_earnings': float(totals['total_earnings'] or 0),
        'total_trips': totals['total_trips'] or 0,
        'this_month_earnings': float(month_totals['this_month_earnings'] or 0),
        'this_month_trips': month_totals['this_month_trips'] or 0,
        'bikes': bikes_data,
    }, status=status.HTTP_200_OK)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def customer_list(request):
    owners = OwnerProfile.objects.all()
    serialized = OwnerProfileSerializer(owners, many=True)   
    return Response(serialized.data)

@api_view(['POST'])
@permission_classes([AllowAny])
def register_Owner(request):
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
            
            phone_number = request.data.get('phone_number')

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
                'phone_number' : phone_number,
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
                # 'provider_token': payload.get('provider_token', ''),
                'phone_number': phone_number,
                'address': address, 
                'cpn': cpn,
                'latitude': latitude,
                'longitude': longitude,
                # 'profile_picture': profile_picture,
                'apple_sub': payload.get('apple_sub', ''),
                'registration_type': 'owner'
            }
        )
        ws_scheme = "wss" if not settings.DEBUG else "ws"
        ws_host = os.getenv('WS_HOST', request.get_host().split(':')[0])
        daphne_port = os.getenv('WS_PORT', '8000')
        websocket_url = f"{ws_scheme}://{ws_host}:{daphne_port}/ws/owner/verification/{verification_session.id}/"
        return Response({
            'message': 'Please complete verification',
            'verification_url': verification_session.url,
            'session_id': verification_session.id,
            'websocket_url': websocket_url
        })
            
    except Exception as e:
        logger.error(f"Error during owner verification session creation: {e}", exc_info=True)
        return Response({'error': 'A server error occurred. Please try again.'}, status=500)
    





@api_view(['POST'])
@permission_classes([AllowAny])
def Login_Owner(request):
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
        owner = get_object_or_404(OwnerProfile, user=user)
    except Exception:
        return Response({'error': 'Owner profile not found'}, status=404)

    if owner.verification_status != 'verified':
        return Response({
            'error': 'Account not verified',
            'verification_status': owner.verification_status
        }, status=status.HTTP_403_FORBIDDEN)

    refresh = RefreshToken.for_user(user)
    serializer = OwnerProfileSerializer(owner)
    notification_channel = f"user_{user.id}_{refresh.access_token}"
    
    return Response({
        'user': {
            'id': user.id,
            'username': user.username,
            'email': user.email,
            'phone_number': serializer.data['phone_number'],
            'profile_picture': serializer.data['profile_picture'],
            'total_earnings': owner.total_earnings,
            'verification_status': owner.verification_status,
            'access': str(refresh.access_token),
            'refresh': str(refresh),
            'chat_ws_url': f"/ws/chat/{{trip_id}}/?token={str(refresh.access_token)}",
            'ws_url': f"/ws/notifications/{notification_channel}/",
        }
    })



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

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_Owner_profile(request):
    try:
        owner = request.user.owner_profile
    except Exception:
        return Response({'error': 'Owner profile not found'}, status=status.HTTP_404_NOT_FOUND)
    serializer = OwnerProfileSerializer(owner)
    return Response({
        **serializer.data,
        'total_earnings': float(owner.total_earnings),
        'verification_status': owner.verification_status,
        'stripe_customer_id': owner.stripe_customer_id,
    })


@api_view(['PUT'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def update_Owner_profile(request):
    owner_profile = request.user.owner_profile
    serializer = OwnerProfileSerializer(owner_profile, data=request.data, partial=True)
    
    if serializer.is_valid():
        serializer.save()
        
        # Refresh from database
        owner_profile.refresh_from_db()
        request.user.refresh_from_db()
        
        user_data = {
            'username': request.user.username,
            'email': request.user.email,
            'phone_number': owner_profile.phone_number,       
            'address': owner_profile.address,
            'total_earnings': float(owner_profile.total_earnings),
            'profile_picture': request.build_absolute_uri(owner_profile.profile_picture.url) if owner_profile.profile_picture else None,  # ← snake_case
            'verification_status': owner_profile.verification_status  
        }
        
        return Response(user_data)
    
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)










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
def search_Owner_profile(request, username):
    user = get_object_or_404(User, username=username)
    owner = get_object_or_404(OwnerProfile, user=user)
    serializer = OwnerProfileSerializer(owner)
    return Response(serializer.data)

@csrf_exempt
@require_POST
def stripe_webhook(request):
    from django.core.cache import cache

    payload = request.body
    sig_header = request.META.get('HTTP_STRIPE_SIGNATURE', '')

    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, settings.STRIPE_OWNER_WEBHOOK_SECRET
        )
    except stripe.error.SignatureVerificationError:
        return HttpResponse(status=400)
    except Exception as e:
        logger.error(f"Owner webhook error: {str(e)}")
        return HttpResponse(status=400)

    # Idempotency: skip if already processed
    event_id = event.get('id', '')
    if event_id and cache.get(f"stripe_event_{event_id}"):
        return HttpResponse(status=200)
    if event_id:
        cache.set(f"stripe_event_{event_id}", True, timeout=86400)

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

    return HttpResponse(status=200)
