from channels.generic.websocket import AsyncJsonWebsocketConsumer
from channels.db import database_sync_to_async
from .models import ChatRoom, Message
from django.contrib.auth.models import User

class ChatConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        user = self.scope.get('user')
        if not user or not user.is_authenticated:
            await self.close(code=4001)
            return

        self.trip_id = self.scope['url_route']['kwargs']['trip_id']

        if not await self.user_is_trip_member(user, self.trip_id):
            await self.close(code=4003)
            return

        self.room_group_name = f'chat_{self.trip_id}'

        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name
        )
        await self.accept()

    @database_sync_to_async
    def user_is_trip_member(self, user, trip_id):
        from Trip.models import Trip
        try:
            trip = Trip.objects.select_related('renter__user', 'bike_owner__user').get(id=trip_id)
            return (
                (hasattr(trip.renter, 'user') and trip.renter.user_id == user.id) or
                (hasattr(trip.bike_owner, 'user') and trip.bike_owner.user_id == user.id)
            )
        except Trip.DoesNotExist:
            return False

    async def disconnect(self, close_code):
        if hasattr(self, 'room_group_name'):
            await self.channel_layer.group_discard(
                self.room_group_name,
                self.channel_name
            )

    async def receive_json(self, content):
        text = (content.get('content') or content.get('message', '')).strip()
        if not text:
            return
        if len(text) > 2000:
            await self.send_json({'type': 'error', 'message': 'Message too long (max 2000 characters)'})
            return
        msg = await self.save_message(text)
        if msg is None:
            return

        await self.channel_layer.group_send(
            self.room_group_name,
            {
                'type': 'chat_message',
                'msg_id': msg['id'],
                'content': msg['content'],
                'sender': msg['sender'],
                'sender_id': msg['sender_id'],
                'sender_username': msg['sender_username'],
                'timestamp': msg['timestamp'],
                'is_read': msg['is_read'],
            }
        )

    async def chat_message(self, event):
        await self.send_json({
            'type': 'new_message',
            'message': {
                'id': event['msg_id'],
                'content': event['content'],
                'sender': event['sender'],
                'sender_id': event['sender_id'],
                'sender_username': event['sender_username'],
                'timestamp': event['timestamp'],
                'is_read': event['is_read'],
            },
        })

    async def messages_read(self, event):
        await self.send_json({
            'type': 'messages_read',
            'reader_id': event['reader_id'],
        })

    @database_sync_to_async
    def save_message(self, text):
        from Trip.models import Trip
        try:
            trip = Trip.objects.get(id=self.trip_id)
        except Trip.DoesNotExist:
            return None
        chat_room, _ = ChatRoom.objects.get_or_create(trip=trip)
        msg = Message.objects.create(
            chat_room=chat_room,
            sender=self.scope['user'],
            content=text,
        )
        return {
            'id': msg.id,
            'content': msg.content,
            'sender': msg.sender_id,
            'sender_id': msg.sender_id,
            'sender_username': msg.sender.username,
            'timestamp': msg.timestamp.isoformat(),
            'is_read': False,
        }

class NotificationConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        user = self.scope.get('user')
        if not user or not user.is_authenticated:
            await self.close(code=4001)
            return

        self.user_id = user.id
        self.notification_group = f'notifications_{self.user_id}'

        await self.channel_layer.group_add(
            self.notification_group,
            self.channel_name
        )
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(
            self.notification_group,
            self.channel_name
        )

    async def send_notification(self, event):
        await self.send_json({
            'type': 'notification',
            'title': event['title'],
            'message': event['message'],
            'data': event['data'],
        })