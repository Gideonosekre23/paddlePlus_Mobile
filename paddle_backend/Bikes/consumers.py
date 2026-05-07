from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from django.utils import timezone
import json
from .models import Bikes, BikeHardware
from asgiref.sync import sync_to_async

class GPSConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        import os
        hw_key = os.getenv('HARDWARE_API_KEY', '')
        provided = self.scope.get('query_string', b'').decode()
        from urllib.parse import parse_qs
        params = parse_qs(provided)
        token = (params.get('api_key') or [''])[0]
        if not hw_key or token != hw_key:
            await self.close(code=4003)
            return

        self.serial_number = self.scope['url_route']['kwargs']['serial_number']
        try:
            self.bike = await Bikes.objects.select_related('hardware').aget(
                hardware__serial_number=self.serial_number,
                hardware__is_assigned=True
            )
        except Bikes.DoesNotExist:
            await self.close(code=4004)
            return
        self.group_name = f"bike_{self.bike.id}"

        await self.channel_layer.group_add(
            self.group_name,
            self.channel_name
        )
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(
            self.group_name,
            self.channel_name
        )

    async def receive(self, text_data):
        data = json.loads(text_data)
        
        if 'latitude' in data and 'longitude' in data:
            await self.handle_location_update(data)
        
        if 'battery_level' in data:
            await self.handle_status_update(data)
            
        await self.send(json.dumps({
            'message': 'Update received'
        }))

    async def handle_location_update(self, data):
        if not self.bike.hardware:
            return
        self.bike.hardware.latitude = data['latitude']
        self.bike.hardware.longitude = data['longitude']
        self.bike.hardware.last_location_update = timezone.now()
        await sync_to_async(self.bike.hardware.save)()

        # Sync Bikes record
        self.bike.latitude = data['latitude']
        self.bike.longitude = data['longitude']
        await sync_to_async(self.bike.save)(update_fields=['latitude', 'longitude'])

        await self.channel_layer.group_send(
            self.group_name,
            {
                'type': 'location_update',
                'latitude': data['latitude'],
                'longitude': data['longitude'],
                'timestamp': timezone.now().isoformat()
            }
        )

        # Push bike location to active trip rider via notification channel
        active_trip = await self._get_active_trip()
        if active_trip:
            await self.channel_layer.group_send(
                f'notifications_{active_trip["rider_id"]}',
                {
                    'type': 'send_notification',
                    'title': 'Bike Location',
                    'message': '',
                    'data': {
                        'notification_type': 'bike_location_update',
                        'trip_id': active_trip['trip_id'],
                        'bike_id': self.bike.id,
                        'latitude': data['latitude'],
                        'longitude': data['longitude'],
                        'battery_level': self.bike.hardware.battery_level,
                    }
                }
            )

    @database_sync_to_async
    def _get_active_trip(self):
        from Trip.models import Trip
        trip = Trip.objects.filter(
            bike=self.bike,
            status__in=['waiting', 'started', 'ontrip']
        ).select_related('renter__user').first()
        if trip:
            return {'trip_id': trip.id, 'rider_id': trip.renter.user.id}
        return None

    async def handle_status_update(self, data):
        if not self.bike.hardware:
            return
        await sync_to_async(self.bike.hardware.update_status)(
            battery_level=data.get('battery_level')
        )
        
        await self.channel_layer.group_send(
            self.group_name,
            {
                'type': 'status_update',
                'battery_level': data.get('battery_level'),
                'last_ping': timezone.now().isoformat()
            }
        )

    async def location_update(self, event):
        await self.send(text_data=json.dumps(event))

    async def status_update(self, event):
        await self.send(text_data=json.dumps(event))
