from channels.generic.websocket import AsyncWebsocketConsumer
import json
import logging
import stripe
import asyncio
from django.conf import settings
from django.contrib.auth.models import User
from Owner.models import OwnerProfile
from django.db import transaction
from rest_framework_simplejwt.tokens import RefreshToken
from asgiref.sync import sync_to_async

stripe.api_key = settings.STRIPE_SECRET_KEY
logger = logging.getLogger(__name__)

class VerificationOwnerConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        try:
            logger.info(f"WebSocket Scope: {self.scope}")
            self.session_id = self.scope['url_route']['kwargs'].get('session_id')
            
            if not self.session_id:
                logger.error("No session_id found in URL route")
                await self.close(code=4000)
                return

            self.group_name = f"verification_{self.session_id}"
            await self.channel_layer.group_add(
                self.group_name,
                self.channel_name
            )
            
            await self.accept()
            asyncio.create_task(self.check_verification_status())
            
            await self.send(text_data=json.dumps({
                'type': 'connection_established',
                'session_id': self.session_id,
                'status': 'connected'
            }))

            logger.info(f"WebSocket connection established for {self.session_id}")

        except Exception as e:
            logger.error(f"Connection error: {str(e)}")
            await self.close(code=4001)

    @sync_to_async
    def create_user_and_profile(self, metadata):
        try:
            with transaction.atomic():
                user = User.objects.create_user(
                    username=metadata['username'],
                    email=metadata['email'],
                    password=metadata['password']
                )
                
                owner_profile = OwnerProfile.objects.create(
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
        except Exception as e:
            logger.error(f"User creation failed: {str(e)}")
            raise

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
                logger.info(f"Current verification status: {current_status}")
                
                if current_status != previous_status:
                    logger.info(f"Status transition detected: {previous_status} -> {current_status}")
                    
                    status_data = {
                        'type': 'status_update',
                        'status': current_status,
                        'message': self.get_status_message(current_status),
                        'timestamp': str(session.created)
                    }

                    if current_status == 'verified':
                        try:
                            user_data = await self.create_user_and_profile(session.metadata)
                            status_data.update({
                                'registration': 'success',
                                'user': user_data
                            })
                            logger.info(f"User registration successful: {user_data['username']}")
                            
                        except Exception as e:
                            logger.error(f"Registration failed: {str(e)}")
                            status_data.update({
                                'registration': 'failed',
                                'error': str(e)
                            })
                    
                    await self.send(text_data=json.dumps(status_data))
                    previous_status = current_status
                    
                    if current_status in ['verified', 'failed', 'canceled']:
                        break
                
                retry_count += 1
                await asyncio.sleep(2)
                
            except stripe.error.StripeError as e:
                logger.error(f"Stripe API Error: {str(e)}")
                await self.send(text_data=json.dumps({
                    'type': 'error',
                    'message': 'Stripe API error occurred',
                    'error': str(e)
                }))
                await asyncio.sleep(2)
                continue

    def get_status_message(self, status):
        status_messages = {
            'requires_input': 'Please complete the verification process',
            'processing': 'Processing your verification',
            'verified': 'Verification successful!',
            'failed': 'Verification failed. Please try again',
            'canceled': 'Verification was canceled'
        }
        return status_messages.get(status, 'Unknown status')

    async def disconnect(self, close_code):
        logger.info(f"WebSocket disconnected with code {close_code}")
        await self.channel_layer.group_discard(
            self.group_name,
            self.channel_name
        )

    async def verification_status(self, event):
        logger.info(f"Received verification status: {event}")
        message = event['message']
        await self.send(text_data=json.dumps({
            'type': 'verification_status',
            'data': message
        }))
