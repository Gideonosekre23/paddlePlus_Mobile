from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework import status
from .models import ChatRoom, Message
from Trip.models import Trip
from Owner.serializers import MessageSerializer, ChatRoomSerializer
from django.shortcuts import get_object_or_404

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_chat_room(request, trip_id):
    trip = get_object_or_404(Trip, id=trip_id)
    # Auto-creates chat room if it doesn't exist
    chat_room, created = ChatRoom.objects.get_or_create(trip=trip)
    
    if created:
        # Notify both rider and owner about new chat room
        channel_layer = get_channel_layer()
        for user_id in [trip.renter.user.id, trip.bike_owner.user.id]:
            async_to_sync(channel_layer.group_send)(
                f"user_notifications_{user_id}",
                {
                    'type': 'notify_chat',
                    'chat_id': chat_room.id,
                    'message': 'Chat room created for your trip',
                    'trip_id': trip_id,
                    'timestamp': timezone.now().isoformat()
                }
            )
    
    messages = Message.objects.filter(chat_room=chat_room)
    return Response({
        'chat_room_id': chat_room.id,
        'messages': MessageSerializer(messages, many=True).data
    })


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def send_message(request, chat_room_id):
    chat_room = get_object_or_404(ChatRoom, id=chat_room_id)
    content = request.data.get('content')
    
    if not content:
        return Response({'error': 'Message content is required'}, status=status.HTTP_400_BAD_REQUEST)
    
    message = Message.objects.create(
        chat_room=chat_room,
        sender=request.user,
        content=content
    )

    # Send notification to recipient
    channel_layer = get_channel_layer()
    recipient_id = chat_room.get_other_user(request.user).id
    
    async_to_sync(channel_layer.group_send)(
        f"chat_notifications_{recipient_id}",
        {
            'type': 'notify_chat',
            'chat_id': chat_room_id,
            'message': content,
            'sender': request.user.username,
            'timestamp': message.timestamp.isoformat()
        }
    )
    
    return Response(MessageSerializer(message).data)


@api_view(['PUT'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def mark_messages_read(request, chat_room_id):
    chat_room = get_object_or_404(ChatRoom, id=chat_room_id)
    Message.objects.filter(chat_room=chat_room).exclude(sender=request.user).update(is_read=True)
    
    return Response({'status': 'messages marked as read'})
