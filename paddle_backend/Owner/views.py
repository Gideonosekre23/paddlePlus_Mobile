import logging
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
from .models import OwnerProfile
from .serializers import OwnerProfileSerializer
from django.db import transaction
import stripe

logger = logging.getLogger(__name__)

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
    username = request.data.get('username')
    email = request.data.get('email')
    
    if User.objects.filter(username=username).exists():
        return Response({'error': 'Username already exists'}, status=400)
    if User.objects.filter(email=email).exists():
        return Response({'error': 'Email already exists'}, status=400)

    try:
        verification_session = stripe.identity.VerificationSession.create(
            type='document',
            metadata={
                'username': username,
                'email': email,
                'password': request.data.get('password'),
                'phone_number': request.data.get('phone_number'),
                'cpn': request.data.get('cpn'),
                'latitude': request.data.get('latitude'),
                'longitude': request.data.get('longitude'),
                'profile_picture': request.data.get('profile_picture'),
                'registration_type': 'owner'
            }
        )

        websocket_url = f"ws://127.0.0.1:8000/ws/owner/verification/{verification_session.id}/"

        return Response({
            'message': 'Please complete verification',
            'verification_url': verification_session.url,
            'session_id': verification_session.id,
            'websocket_url': websocket_url
        })
            
    except Exception as e:
        return Response({'error': str(e)}, status=400)


@api_view(['POST'])
@permission_classes([AllowAny])
def Login_Owner(request):
    username = request.data.get('username')
    password = request.data.get('password')

    user = authenticate(username=username, password=password)
    if not user:
        return Response({'error': 'Invalid credentials'}, status=status.HTTP_400_BAD_REQUEST)

    owner = get_object_or_404(OwnerProfile, user=user)
    if owner.verification_status != 'verified':
        return Response({'error': 'Account not verified'}, status=status.HTTP_403_FORBIDDEN)

    refresh = RefreshToken.for_user(user)
    serializer = OwnerProfileSerializer(owner)
    
    # Generate unique notification channel ID
    notification_channel = f"user_{user.id}_{refresh.access_token}"
    
    return Response({
        'user': {
            'username': user.username,
            'email': user.email,
            'phone_number': serializer.data['phone_number'],
            'profile_picture': serializer.data['profile_picture'],
            'verification_status': owner.verification_status,

            'access': str(refresh.access_token),
            'refresh': str(refresh),
            'notification_channel': notification_channel,
            'ws_url': f"/ws/notifications/{notification_channel}/",
            'access_token' : str(refresh.access_token),
            'refresh_token': str(refresh)

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

@api_view(['PUT'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def update_Owner_profile(request):
    owner = request.user.ownerprofile
    serializer = OwnerProfileSerializer(owner, data=request.data, partial=True)
    
    if serializer.is_valid():
        serializer.save()
        return Response({'message': 'Profile updated successfully'})
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['DELETE'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def delete_Owner_profile(request):
    owner = request.user.ownerprofile
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
    payload = request.body
    sig_header = request.META['HTTP_STRIPE_SIGNATURE']
    
    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, settings.STRIPE_OWNER_WEBHOOK_SECRET
        )
        
        session = event['data']['object']
        session_id = session.id
        channel_layer = get_channel_layer()
        
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