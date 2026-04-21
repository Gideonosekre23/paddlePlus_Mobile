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
    chat_room, created = ChatRoom.objects.get_or_create(trip=trip)
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
    
    return Response(MessageSerializer(message).data)

@api_view(['PUT'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def mark_messages_read(request, chat_room_id):
    chat_room = get_object_or_404(ChatRoom, id=chat_room_id)
    Message.objects.filter(chat_room=chat_room).exclude(sender=request.user).update(is_read=True)
    
    return Response({'status': 'messages marked as read'})
