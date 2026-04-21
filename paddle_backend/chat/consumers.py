import logging

from djangochannelsrestframework.generics import GenericAsyncAPIConsumer
from djangochannelsrestframework.permissions import IsAuthenticated
from djangochannelsrestframework.decorators import action
from channels.db import database_sync_to_async
from .models import ChatRoom, Message
from .serializers import MessageSerializer
from Trip.models import Trip
from django.utils import timezone
from urllib.parse import parse_qs
from rest_framework_simplejwt.tokens import AccessToken
from django.contrib.auth.models import User
from channels.generic.websocket import AsyncJsonWebsocketConsumer
from Bikes.models import BikeHardware
import asyncio

logger = logging.getLogger(__name__)

# Module-level registry so a new consumer instance can cancel the previous
# instance's retry task when the same hardware_id reconnects.
_ARDUINO_RETRY_TASKS: dict = {}


class ChatConsumer(GenericAsyncAPIConsumer):
    queryset = Message.objects.all()
    serializer_class = MessageSerializer
    permission_classes = [IsAuthenticated]

    async def connect(self):
        self.trip_id = self.scope['url_route']['kwargs']['trip_id']
        self.room_group_name = f'chat_trip_{self.trip_id}'
        
        # Authenticate the connection
        authenticated = await self.authenticate()
        if not authenticated:
            await self.close(code=4001)
            return

        # Verify user is part of this trip
        is_participant = await self.verify_trip_participant()
        if not is_participant:
            await self.close(code=4003)
            return

        # Add to the chat group
        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name
        )
        
        await self.accept()
        
        # Send connection confirmation
        await self.send_json({
            'type': 'connection_established',
            'trip_id': self.trip_id,
            'message': f'Connected to chat for trip {self.trip_id}',
            'user': self.scope['user'].username
        })

    async def disconnect(self, close_code):
        if hasattr(self, 'room_group_name'):
            await self.channel_layer.group_discard(
                self.room_group_name,
                self.channel_name
            )

    @action()
    async def send_message(self, content, **kwargs):
        """Send a chat message"""
        try:
            if not content:
                return {'error': 'Message content is required'}
            if len(str(content)) > 1000:
                return {'error': 'Message exceeds 1000 character limit.'}

            chat_room = await self.get_chat_room()
            message_obj = await self.create_message({
                'content': content,
                'chat_room': chat_room.id,
                'sender': self.scope['user'].id
            })
            
            if message_obj:
                # Serialize message
                serialized_message = await self.serialize_message(message_obj)
                
                # Broadcast to chat group
                await self.channel_layer.group_send(
                    self.room_group_name,
                    {
                        'type': 'chat_message',
                        'message': serialized_message
                    }
                )
                
                # Send notifications to OTHER participants (not sender)
                trip_participants = await self.get_trip_participants()
                for participant in trip_participants:
                    # EXCLUDE THE SENDER from notifications
                    if participant['user_id'] != self.scope['user'].id:
                        await self.channel_layer.group_send(
                            f'notifications_{participant["user_id"]}',
                            {
                                'type': 'notify_chat_message',
                                'title': f'💬 {self.scope["user"].username}',
                                'message': content[:100] + '...' if len(content) > 100 else content,
                                'trip_id': self.trip_id,
                                'sender': self.scope['user'].username,
                                'sender_id': self.scope['user'].id,
                                'timestamp': message_obj.timestamp.isoformat(),
                                'chat_action': 'open_chat'
                            }
                        )
                
                return serialized_message
            
        except Exception as e:
            logger.error(f"Error sending message: {str(e)}")
            return {'error': 'Failed to send message'}

    
    async def chat_message(self, event):
        """Handle chat_message type from group_send"""
        await self.send_json({
            'type': 'new_message',
            'message': event['message'],
            'trip_id': self.trip_id,
            'timestamp': timezone.now().isoformat()
        })

    @database_sync_to_async
    def authenticate(self):
        """Authenticate WebSocket connection using JWT token"""
        try:
            query_string = self.scope.get('query_string', b'').decode()
            query_params = parse_qs(query_string)
            
            token = query_params.get('token', [None])[0]
            if not token:
                logger.error("No token provided in WebSocket connection")
                return False

            try:
                access_token = AccessToken(token)
                user_id = access_token['user_id']
                user = User.objects.get(id=user_id)
                self.scope['user'] = user
                logger.info(f"WebSocket authenticated for user: {user.username}")
                return True
            except Exception as token_error:
                logger.error(f"Invalid token: {str(token_error)}")
                return False
            
        except Exception as e:
            logger.error(f"Authentication error: {str(e)}")
            return False

    @database_sync_to_async
    def verify_trip_participant(self):
        """Verify that the authenticated user is part of this trip"""
        try:
            trip = Trip.objects.get(id=self.trip_id)
            user = self.scope['user']
            
            if trip.renter and trip.renter.user.id == user.id:
                return True
            if trip.bike_owner and trip.bike_owner.user.id == user.id:
                return True
            
            logger.error(f"User {user.username} is not a participant in trip {self.trip_id}")
            return False
            
        except Trip.DoesNotExist:
            logger.error(f"Trip {self.trip_id} does not exist")
            return False
        except Exception as e:
            logger.error(f"Error verifying trip participant: {str(e)}")
            return False

    @database_sync_to_async
    def get_chat_room(self):
        """Get or create chat room for this trip"""
        try:
            trip = Trip.objects.get(id=self.trip_id)
            chat_room, created = ChatRoom.objects.get_or_create(trip=trip)
            return chat_room
        except Exception as e:
            logger.error(f"Error getting chat room: {str(e)}")
            return None

    @database_sync_to_async
    def create_message(self, message_data):
        """Create a new message"""
        try:
            chat_room = ChatRoom.objects.get(id=message_data['chat_room'])
            user = User.objects.get(id=message_data['sender'])
            
            message = Message.objects.create(
                chat_room=chat_room,
                sender=user,
                content=message_data['content']
            )
            return message
        except Exception as e:
            logger.error(f"Error creating message: {str(e)}")
            return None

    @database_sync_to_async
    def serialize_message(self, message):
        """Serialize message for JSON response"""
        return MessageSerializer(message).data

    @database_sync_to_async
    def get_trip_participants(self):
        """Get all participants in this trip"""
        try:
            trip = Trip.objects.get(id=self.trip_id)
            participants = []
            
            if trip.renter:
                participants.append({
                    'user_id': trip.renter.user.id,
                    'username': trip.renter.user.username,
                    'role': 'rider'
                })
            
            if trip.bike_owner:
                participants.append({
                    'user_id': trip.bike_owner.user.id,
                    'username': trip.bike_owner.user.username,
                    'role': 'owner'
                })
            
            return participants
        except Exception as e:
            logger.error(f"Error getting trip participants: {str(e)}")
            return []








class UserNotificationConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        try:
            self.channel_id = self.scope['url_route']['kwargs']['channel_id']
            logger.info(f"WebSocket connection attempt for channel: {self.channel_id}")

            # Format: user_{id}_{jwt_access_token}
            if not self.channel_id.startswith('user_'):
                logger.error(f"Channel ID doesn't start with 'user_': {self.channel_id}")
                await self.close(code=4001)
                return

            parts = self.channel_id.split('_', 2)
            if len(parts) < 3:
                logger.error(f"Invalid channel_id format: {self.channel_id}")
                await self.close(code=4000)
                return

            self.user_id = parts[1]
            token = parts[2]

            # Verify JWT token belongs to the claimed user_id
            try:
                access_token = AccessToken(token)
                token_user_id = str(access_token['user_id'])
                if token_user_id != self.user_id:
                    logger.error(f"Token user_id {token_user_id} doesn't match channel user_id {self.user_id}")
                    await self.close(code=4003)
                    return
            except Exception as e:
                logger.error(f"Invalid or expired token: {str(e)}")
                await self.close(code=4001)
                return

            self.notification_group_name = f'notifications_{self.user_id}'
            await self.channel_layer.group_add(
                self.notification_group_name,
                self.channel_name
            )

            await self.accept()
            await self.send_json({
                'type': 'connection_established',
                'user_id': self.user_id,
                'status': 'connected',
                'message': 'Successfully connected to notifications',
                'channel': self.notification_group_name
            })
            logger.info(f"WebSocket connected for user {self.user_id}")

        except Exception as e:
            logger.error(f"Connection error: {str(e)}")
            await self.close(code=4002)
        
    async def disconnect(self, close_code):
        logger.info(f"WebSocket disconnected with code {close_code}")
        
        if hasattr(self, 'notification_group_name'):
            await self.channel_layer.group_discard(
                self.notification_group_name,
                self.channel_name
            )

    async def receive_json(self, content):
        """
        Handle messages received from WebSocket client
        """
        logger.info(f"Received message from client: {content}")
        
        # Echo back for testing
        await self.send_json({
            'type': 'echo',
            'message': 'Message received by server',
            'original': content,
            'user_id': self.user_id
        })

    

    async def notify_ride_request(self, event):
        """
        Handle ride request notifications sent from Riderequest views
        """
        logger.info(f"Sending ride request notification to user {self.user_id}: {event}")
        
        await self.send_json({
            'type': 'ride_request',
            'title': 'New Ride Request! 🚴‍♂️',
            'message': event['message'],
            'request_id': event['request_id'],
            'bike_id': event['bike_id'],
            'bike_name': event.get('bike_name', ''),
            'rider_username': event.get('rider_username', ''),
            'pickup_latitude': event.get('pickup_latitude'),
            'pickup_longitude': event.get('pickup_longitude'),
            'destination_latitude': event.get('destination_latitude'),
            'destination_longitude': event.get('destination_longitude'),
            'estimated_price': event.get('estimated_price'),
            'timestamp': event.get('timestamp'),
            'actions': ['accept', 'decline']
        })
    
    async def notify_chat_message(self, event):
        
        logger.info(f"Sending chat notification to user {self.user_id}: {event}")
        
        await self.send_json({
            'type': 'chat_message_notification',
            'title': event['title'],
            'message': event['message'],
            'trip_id': event['trip_id'],
            'sender': event['sender'],
            'sender_id': event['sender_id'],
            'timestamp': event['timestamp'],
            'action': event.get('chat_action', 'open_chat'),
            'notification_category': 'chat'
        })











    async def notify_ride_accepted(self, event):
        """
        Handle ride acceptance notifications
        """
        await self.send_json({
            'type': 'ride_accepted',
            'title': 'Ride Accepted! ✅',
            'message': event['message'],
            'request_id': event['request_id'],
            'trip_id': event.get('trip_id'),
            'bike_location': event.get('bike_location'),
            'unlock_code': event.get('unlock_code'),
            'timestamp': event.get('timestamp')
        })

    async def notify_ride_declined(self, event):
        """
        Handle ride decline notifications
        """
        await self.send_json({
            'type': 'ride_declined',
            'title': 'Ride Declined ❌',
            'message': event['message'],
            'request_id': event['request_id'],
            'reason': event.get('reason', 'No reason provided'),
            'timestamp': event.get('timestamp')
        })

    async def notify_trip_started(self, event):
        """
        Handle trip start notifications
        """
        await self.send_json({
            'type': 'trip_started',
            'title': 'Trip Started! 🚴‍♂️',
            'message': event['message'],
            'trip_id': event['trip_id'],
            'bike_id': event.get('bike_id'),
            'start_time': event.get('start_time'),
            'timestamp': event.get('timestamp')
        })

    async def notify_trip_ended(self, event):
        """
        Handle trip end notifications
        """
        await self.send_json({
            'type': 'trip_ended',
            'title': 'Trip Completed! 🏁',
            'message': event['message'],
            'trip_id': event['trip_id'],
            'total_cost': event.get('total_cost'),
            'duration': event.get('duration'),
            'distance': event.get('distance'),
            'timestamp': event.get('timestamp')
        })

    async def notify_payment(self, event):
        """
        Handle payment notifications
        """
        await self.send_json({
            'type': 'payment',
            'title': 'Payment Update 💰',
            'message': event['message'],
            'amount': event.get('amount'),
            'status': event.get('status'),
            'payment_method': event.get('payment_method'),
            'timestamp': event.get('timestamp')
        })

    async def notify_bike_status(self, event):
        """
        Handle bike status change notifications
        """
        await self.send_json({
            'type': 'bike_status',
            'title': 'Bike Status Update 🚲',
            'message': event['message'],
            'bike_id': event['bike_id'],
            'bike_name': event.get('bike_name'),
            'status': event.get('status'),
            'battery_level': event.get('battery_level'),
            'location': event.get('location'),
            'timestamp': event.get('timestamp')
        })

    async def notify_chat(self, event):
        """
        Handle chat room creation notifications sent from views.py
        This matches the 'type': 'notify_chat' in the get_chat_room view
        """
        await self.send_json({
            'type': 'chat_notification',
            'title': 'New Chat Message 💬',
            'chat_id': event['chat_id'],
            'message': event['message'],
            'trip_id': event.get('trip_id'),
            'sender': event.get('sender'),
            'timestamp': event['timestamp']
        })

    async def send_notification(self, event):
        """
        Generic notification handler for any custom notifications
        """
        await self.send_json({
            'type': 'notification',
            'title': event.get('title', 'Notification'),
            'message': event['message'],
            'data': event.get('data', {}),
            'timestamp': event.get('timestamp')
        })

    async def notify_system(self, event):
        """
        Handle system-wide notifications (maintenance, updates, etc.)
        """
        await self.send_json({
            'type': 'system_notification',
            'title': event.get('title', 'System Update'),
            'message': event['message'],
            'priority': event.get('priority', 'normal'),
            'action_required': event.get('action_required', False),
            'timestamp': event.get('timestamp')
        })



class ArduinoConsumer(AsyncJsonWebsocketConsumer):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.hardware_id = None
        self.retry_count = 0
        self._retry_task = None

    async def connect(self):
        self.hardware_id = self.scope['url_route']['kwargs']['hardware_id']

        # Cancel any orphaned retry task from a previous consumer instance for this device
        old_task = _ARDUINO_RETRY_TASKS.pop(self.hardware_id, None)
        if old_task and not old_task.done():
            old_task.cancel()

        hardware_exists = await self.verify_hardware()
        if not hardware_exists:
            await self.close(code=4004)
            return

        await self.accept()
        await self.mark_online()
        logger.info(f"Arduino {self.hardware_id} connected")

    async def disconnect(self, close_code):
        logger.info(f"Arduino {self.hardware_id} disconnected (code={close_code})")
        task = asyncio.ensure_future(self.start_retry_logic())
        _ARDUINO_RETRY_TASKS[self.hardware_id] = task
        self._retry_task = task

    async def receive_json(self, content):
        message_type = content.get('type')
        
        if message_type == 'gps_update':
            await self.handle_gps_update(content)
        elif message_type == 'status_update':
            await self.handle_status_update(content)
        elif message_type == 'heartbeat':
            await self.handle_heartbeat(content)
        elif message_type == 'emergency_alert':
            await self.handle_emergency_alert(content)

    async def handle_gps_update(self, data):
        """Update bike location"""
        latitude = data.get('latitude')
        longitude = data.get('longitude')
        battery_level = data.get('battery_level')
        
        if latitude and longitude:
            await self.update_location(latitude, longitude, battery_level)
            await self.send_json({'type': 'gps_ack', 'status': 'success'})
        else:
            await self.send_json({'type': 'gps_ack', 'status': 'error'})

    async def handle_status_update(self, data):
        """Update hardware status"""
        battery_level = data.get('battery_level')
        lock_status = data.get('lock_status')
        await self.update_status(battery_level, lock_status)

    async def handle_heartbeat(self, data):
        """Handle heartbeat"""
        await self.update_ping()
        await self.send_json({'type': 'heartbeat_ack'})

    async def handle_emergency_alert(self, data):
        """Handle emergency alerts"""
        alert_type = data.get('alert_type')
        message = data.get('message', 'Emergency alert')
        logger.warning(f"🚨 Emergency: {alert_type} from {self.hardware_id}")
        await self.notify_emergency(alert_type, message)

    # Commands to Arduino
    async def send_unlock_command(self, event):
        await self.send_json({
            'type': 'unlock_command',
            'trip_id': event['trip_id'],
            'timestamp': timezone.now().isoformat()
        })

    async def send_lock_command(self, event):
        await self.send_json({
            'type': 'lock_command',
            'timestamp': timezone.now().isoformat()
        })

    # Retry Logic
    async def start_retry_logic(self):
        try:
            for attempt in range(1, 6):  # 5 attempts, 30s apart
                await asyncio.sleep(30)
                is_online = await self.check_online()
                if is_online:
                    await self.mark_online()
                    return
            # All retries exhausted
            await self.mark_offline()
            await self.notify_offline()
        except asyncio.CancelledError:
            pass  # New connection cancelled this task — normal, do nothing
        finally:
            _ARDUINO_RETRY_TASKS.pop(self.hardware_id, None)

    # Database Operations
    @database_sync_to_async
    def verify_hardware(self):
        try:
            BikeHardware.objects.get(serial_number=self.hardware_id)
            return True
        except BikeHardware.DoesNotExist:
            return False

    @database_sync_to_async
    def mark_online(self):
        try:
            hardware = BikeHardware.objects.select_related('assigned_bike').get(serial_number=self.hardware_id)
            hardware.is_online = True
            hardware.save(update_fields=['is_online', 'updated_at'])

            bike = hardware.assigned_bike
            if bike:
                # Only restore availability if the bike is not currently on an active trip
                from Trip.models import Trip
                on_active_trip = Trip.objects.filter(
                    bike=bike, status__in=['waiting', 'started', 'ontrip']
                ).exists()
                if not on_active_trip:
                    bike.is_available = True
                    bike.hardware_status = 'active'
                    bike.save(update_fields=['is_available', 'hardware_status'])
        except BikeHardware.DoesNotExist:
            pass

    @database_sync_to_async
    def mark_offline(self):
        try:
            hardware = BikeHardware.objects.get(serial_number=self.hardware_id)
            hardware.is_online = False
            hardware.save()
            
            if hardware.assigned_bike:
                hardware.assigned_bike.is_available = False
                hardware.assigned_bike.hardware_status = 'offline'
                hardware.assigned_bike.save()
        except BikeHardware.DoesNotExist:
            pass

    @database_sync_to_async
    def update_location(self, latitude, longitude, battery_level):
        try:
            hardware = BikeHardware.objects.get(serial_number=self.hardware_id)
            hardware.latitude = latitude
            hardware.longitude = longitude
            hardware.last_ping = timezone.now()
            
            if battery_level:
                hardware.battery_level = battery_level
            
            hardware.save()
            
            if hardware.assigned_bike:
                hardware.assigned_bike.latitude = latitude
                hardware.assigned_bike.longitude = longitude
                hardware.assigned_bike.save()
        except BikeHardware.DoesNotExist:
            pass

    @database_sync_to_async
    def update_status(self, battery_level, lock_status):
        try:
            hardware = BikeHardware.objects.get(serial_number=self.hardware_id)
            
            if battery_level:
                hardware.battery_level = battery_level
            
            hardware.last_ping = timezone.now()
            hardware.save()
        except BikeHardware.DoesNotExist:
            pass

    @database_sync_to_async
    def update_ping(self):
        try:
            hardware = BikeHardware.objects.get(serial_number=self.hardware_id)
            hardware.last_ping = timezone.now()
            hardware.save()
        except BikeHardware.DoesNotExist:
            pass

    @database_sync_to_async
    def check_online(self):
        try:
            hardware = BikeHardware.objects.get(serial_number=self.hardware_id)
            return hardware.is_online
        except BikeHardware.DoesNotExist:
            return False

    async def notify_emergency(self, alert_type, message):
        hardware = await self.get_hardware_with_bike()
        if hardware and hasattr(hardware, 'assigned_bike') and hardware.assigned_bike:
            owner_id = hardware.assigned_bike.owner.user.id
            await self.channel_layer.group_send(
                f'notifications_{owner_id}',
                {
                    'type': 'send_notification',
                    'title': f'Emergency Alert: {alert_type}',
                    'message': message,
                    'data': {
                        'bike_id': hardware.assigned_bike.id,
                        'hardware_id': self.hardware_id,
                        'alert_type': alert_type,
                    }
                }
            )

    async def notify_offline(self):
        hardware = await self.get_hardware_with_bike()
        if hardware and hasattr(hardware, 'assigned_bike') and hardware.assigned_bike:
            owner_id = hardware.assigned_bike.owner.user.id
            await self.channel_layer.group_send(
                f'notifications_{owner_id}',
                {
                    'type': 'send_notification',
                    'title': 'Bike Hardware Offline',
                    'message': f'Hardware {self.hardware_id} went offline after 5 reconnection attempts.',
                    'data': {
                        'hardware_id': self.hardware_id,
                        'bike_id': hardware.assigned_bike.id,
                        'bike_name': hardware.assigned_bike.bike_name,
                    }
                }
            )

    @database_sync_to_async
    def get_hardware_with_bike(self):
        try:
            from Bikes.models import BikeHardware
            return BikeHardware.objects.select_related(
                'assigned_bike__owner__user'
            ).get(serial_number=self.hardware_id)
        except Exception:
            return None



