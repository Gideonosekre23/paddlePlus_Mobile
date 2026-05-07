from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework import status
from .models import ChatRoom, Message, Notification
from Trip.models import Trip
from Owner.serializers import MessageSerializer, ChatRoomSerializer
from django.shortcuts import get_object_or_404
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync


def _is_trip_member(user, trip):
    return (
        (hasattr(user, 'owner_profile') and trip.bike_owner == user.owner_profile) or
        (hasattr(user, 'userprofile') and trip.renter == user.userprofile)
    )


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_chat_room(request, trip_id):
    trip = get_object_or_404(Trip, id=trip_id)
    if not _is_trip_member(request.user, trip):
        return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)
    chat_room, created = ChatRoom.objects.get_or_create(trip=trip)
    messages = Message.objects.filter(chat_room=chat_room)
    return Response({
        'chat_room_id': chat_room.id,
        'messages': MessageSerializer(messages, many=True).data
    })



@api_view(['PUT'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def mark_messages_read(request, chat_room_id):
    chat_room = get_object_or_404(ChatRoom, id=chat_room_id)
    if not _is_trip_member(request.user, chat_room.trip):
        return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)
    Message.objects.filter(chat_room=chat_room).exclude(sender=request.user).update(is_read=True)

    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        f'chat_{chat_room.trip_id}',
        {
            'type': 'messages_read',
            'reader_id': request.user.id,
        }
    )
    return Response({'status': 'messages marked as read'})


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_notification_history(request):
    limit = min(int(request.GET.get('limit', 50)), 100)
    offset = int(request.GET.get('offset', 0))
    unread_only = request.GET.get('unread') == 'true'

    qs = Notification.objects.filter(recipient=request.user)
    if unread_only:
        qs = qs.filter(is_read=False)
    notifications = qs[offset: offset + limit]

    return Response({
        'notifications': [
            {
                'id': n.id,
                'title': n.title,
                'message': n.message,
                'data': n.data,
                'is_read': n.is_read,
                'created_at': n.created_at.isoformat(),
            }
            for n in notifications
        ],
        'total_unread': Notification.objects.filter(recipient=request.user, is_read=False).count(),
    })


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def mark_notifications_read(request):
    notification_ids = request.data.get('ids')
    if notification_ids:
        Notification.objects.filter(recipient=request.user, id__in=notification_ids).update(is_read=True)
    else:
        Notification.objects.filter(recipient=request.user, is_read=False).update(is_read=True)
    return Response({'status': 'ok'})
