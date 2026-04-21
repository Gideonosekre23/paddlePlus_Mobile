import logging
from django.utils import timezone
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework import status
from asgiref.sync import async_to_sync
from .models import ChatRoom, Message
from Trip.models import Trip
from channels.layers import get_channel_layer
from .serializers import MessageSerializer, ChatRoomSerializer
from django.shortcuts import get_object_or_404

logger = logging.getLogger(__name__)
MAX_MESSAGE_LENGTH = 1000



@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_chat_room(request, trip_id):
    trip = get_object_or_404(Trip, id=trip_id)
    
    # Check if user is part of the trip
    if request.user.id != trip.renter.user.id and request.user.id != trip.bike_owner.user.id:
        return Response({'error': 'You are not authorized to access this chat room'}, 
                        status=status.HTTP_403_FORBIDDEN)
    
    # Auto-creates chat room if it doesn't exist
    chat_room, created = ChatRoom.objects.get_or_create(trip=trip)
    
    if created:
        try:
            # Notify both rider and owner about new chat room
            channel_layer = get_channel_layer()
            for user_id in [trip.renter.user.id, trip.bike_owner.user.id]:
                async_to_sync(channel_layer.group_send)(
                    f"notifications_{user_id}",
                    {
                        'type': 'notify_chat',
                        'chat_id': chat_room.id,
                        'message': 'Chat room created for your trip',
                        'trip_id': trip_id,
                        'timestamp': timezone.now().isoformat()
                    }
                )
        except Exception as e:
            logger.warning(f"WebSocket notification failed: {e}")
    
   
    serializer = ChatRoomSerializer(chat_room)
    return Response(serializer.data)

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def send_message(request, chat_room_id):
    chat_room = get_object_or_404(ChatRoom, id=chat_room_id)
    
    # Check if user is part of the trip
    trip = chat_room.trip
    if request.user.id != trip.renter.user.id and request.user.id != trip.bike_owner.user.id:
        return Response({'error': 'You are not authorized to send messages in this chat room'}, 
                        status=status.HTTP_403_FORBIDDEN)
    
    content = request.data.get('content')

    if not content:
        return Response({'error': 'Message content is required'}, status=status.HTTP_400_BAD_REQUEST)
    if len(content) > MAX_MESSAGE_LENGTH:
        return Response({'error': f'Message exceeds {MAX_MESSAGE_LENGTH} character limit.'}, status=status.HTTP_400_BAD_REQUEST)
    
    message = Message.objects.create(
        chat_room=chat_room,
        sender=request.user,
        content=content
    )

    try:
        # Send notification to recipient
        channel_layer = get_channel_layer()
        recipient_id = chat_room.get_other_user(request.user).id
        
        async_to_sync(channel_layer.group_send)(
            f"notifications_{recipient_id}",
            {
                'type': 'notify_chat_message',
                'title': f'💬 {request.user.username}',
                'message': content,
                'trip_id': trip.id,
                'sender': request.user.username,
                'sender_id': request.user.id,
                'timestamp': message.timestamp.isoformat(),
                'chat_action': 'open_chat'
            }
        )
    except Exception as e:
        logger.warning(f"WebSocket notification failed on send_message: {e}")
    
    # Use the new serializer
    serializer = MessageSerializer(message)
    return Response(serializer.data)



@api_view(['PUT'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def mark_messages_read(request, chat_room_id):
    chat_room = get_object_or_404(ChatRoom, id=chat_room_id)
    
    # Check if user is part of the trip
    trip = chat_room.trip
    if request.user.id != trip.renter.user.id and request.user.id != trip.bike_owner.user.id:
        return Response({'error': 'You are not authorized to mark messages in this chat room'}, 
                        status=status.HTTP_403_FORBIDDEN)
    
    Message.objects.filter(chat_room=chat_room).exclude(sender=request.user).update(is_read=True)
    
    return Response({'status': 'messages marked as read'})
