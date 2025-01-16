import django
django.setup()
from channels.generic.websocket import AsyncJsonWebsocketConsumer
from channels.db import database_sync_to_async
from .models import ChatRoom, Message
from django.contrib.auth.models import User

class ChatConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        self.room_id = self.scope['url_route']['kwargs']['room_id']
        self.room_group_name = f'chat_{self.room_id}'

        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name
        )
        await self.accept()

    async def disconnect(self, close_code):
        # Leave room group
        await self.channel_layer.group_discard(
            self.room_group_name,
            self.channel_name
        )

    async def receive_json(self, content):
        message_type = content.get('type', 'message')
        message = content.get('message', '')
        
        # Save message to database
        await self.save_message(message)

        # Send message to room group
        await self.channel_layer.group_send(
            self.room_group_name,
            {
                'type': 'chat_message',
                'message': message,
                'user_id': self.scope['user'].id,
                'username': self.scope['user'].username
            }
        )

    async def chat_message(self, event):
        # Send message to WebSocket
        await self.send_json({
            'message': event['message'],
            'user_id': event['user_id'],
            'username': event['username']
        })

    @database_sync_to_async
    def save_message(self, message):
        chat_room = ChatRoom.objects.get(id=self.room_id)
        Message.objects.create(
            chat_room=chat_room,
            sender=self.scope['user'],
            content=message
        )

class UserNotificationConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        self.channel_id = self.scope['url_route']['kwargs']['channel_id']
        
        try:
            token = self.channel_id.split('_')[-1]
            self.user = await self.get_user_from_token(token)
            
            if self.user:
                # Add user to their notification group
                self.notification_group = f"user_notifications_{self.user.id}"
                await self.channel_layer.group_add(
                    self.notification_group,
                    self.channel_name
                )
                
                # Add user to their chat notification group
                self.chat_group = f"chat_notifications_{self.user.id}"
                await self.channel_layer.group_add(
                    self.chat_group,
                    self.channel_name
                )
                
                await self.accept()
                await self.send_json({
                    'type': 'connection_status',
                    'status': 'connected',
                    'user_id': self.user.id
                })
            else:
                await self.close()
                
        except Exception:
            await self.close()

    async def disconnect(self, close_code):
        if hasattr(self, 'user'):
            # Remove from notification group
            await self.channel_layer.group_discard(
                self.notification_group,
                self.channel_name
            )
            # Remove from chat group
            await self.channel_layer.group_discard(
                self.chat_group,
                self.channel_name
            )

    async def notify_chat(self, event):
        # Handle chat notifications
        await self.send_json({
            'type': 'chat_notification',
            'chat_id': event['chat_id'],
            'message': event['message'],
            'sender': event['sender'],
            'timestamp': event['timestamp']
        })

    async def notify_general(self, event):
        # Handle general notifications
        await self.send_json({
            'type': 'general_notification',
            'title': event['title'],
            'message': event['message'],
            'data': event['data']
        })
