from channels.generic.websocket import AsyncWebsocketConsumer
import json
import logging
import stripe
import asyncio
from django.conf import settings
from django.contrib.auth.models import User
from Rider.models import UserProfile
from django.db import transaction
from rest_framework_simplejwt.tokens import RefreshToken
from asgiref.sync import sync_to_async

stripe.api_key = settings.STRIPE_SECRET_KEY
logger = logging.getLogger(__name__)

class VerificationRiderConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.session_id = self.scope['url_route']['kwargs'].get('session_id')
        if not self.session_id:
            await self.close(code=4000)
            return

        self.group_name = f"verification_{self.session_id}"
        await self.channel_layer.group_add(
            self.group_name,
            self.channel_name
        )
        
        await self.accept()
        asyncio.create_task(self.check_verification_status())

    @sync_to_async
    def create_user_and_profile(self, metadata):
        with transaction.atomic():
            user = User.objects.create_user(
                username=metadata['username'],
                email=metadata['email'],
                password=metadata['password']
            )
            
            rider_profile = UserProfile.objects.create(
                user=user,
                phone_number=metadata['phone_number'],
                cpn=metadata['cpn'],
                latitude=float(metadata['latitude']),
                longitude=float(metadata['longitude']),
                verification_status='verified',
                verification_session_id=self.session_id
            )
            
            refresh = RefreshToken.for_user(user)
            return {
                'user_id': user.id,
                'username': user.username,
                'access_token': str(refresh.access_token),
                'refresh_token': str(refresh)
            }

    async def check_verification_status(self):
        previous_status = None
        retry_count = 0
        max_retries = 60
        
        while retry_count < max_retries:
            try:
                session = stripe.identity.VerificationSession.retrieve(
                    self.session_id,
                    expand=['last_error']
                )
                
                current_status = session.status
                logger.info(f"Current status: {current_status}")
                
                if current_status != previous_status:

                    if current_status == 'verified':
                        user_data = await self.create_user_and_profile(session.metadata)
                        await self.send(text_data=json.dumps({
                            'type': 'verification_complete',
                            'status': 'verified',
                            'message': 'Verification successful',
                            'user': user_data
                        }))
                        await self.close()
                        break
                    
                    elif current_status == 'error' or current_status == 'canceled' :
                        await self.send(text_data=json.dumps({
                            'type': 'verification_complete',
                            'status': 'unverified',
                            'message': 'Verification unsuccessful'
                        }))
                        await self.close()
                        break
                    
                    
                    previous_status = current_status
                
                retry_count += 1
                await asyncio.sleep(2)
                
            except Exception as e:
                logger.error(f"Status check error: {str(e)}")
                await self.send(text_data=json.dumps({
                    'type': 'verification_complete',
                    'status': 'unverified',
                    'message': 'Verification error occurred'
                }))
                await self.close()
                break

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(
            self.group_name,
            self.channel_name
        )
