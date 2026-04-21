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
        self._verification_task = asyncio.create_task(self.check_verification_status())

    @sync_to_async
    def create_user_and_profile(self, metadata):
        with transaction.atomic():
            # Check if this is social authentication
            is_social = metadata.get('is_social', 'False').lower() == 'true'
            
            # Create user (same for both social and traditional)
            user = User.objects.create_user(
                username=metadata['username'],
                email=metadata['email'],
                password=metadata['password']
            )

            lat = metadata.get('latitude')
            lon = metadata.get('longitude')

            apple_sub = metadata.get('apple_sub') or None

            # Create rider profile
            rider_profile = UserProfile.objects.create(
                user=user,
                phone_number=metadata.get('phone_number', ''),
                cpn=metadata.get('cpn', ''),
                address=metadata.get('address', ''),
                latitude=float(lat) if lat else None,
                longitude=float(lon) if lon else None,
                verification_status='verified',
                verification_session_id=self.session_id,
                apple_sub=apple_sub,
            )
            
            # Retrieve profile picture from cache (stored there because Stripe metadata
            # enforces a 500-char value limit — base64 images are far too large)
            from django.core.cache import cache
            import base64, uuid
            from django.core.files.base import ContentFile
            profile_pic_b64 = cache.get(f"reg_profile_pic_{self.session_id}")
            if profile_pic_b64:
                try:
                    if ',' in profile_pic_b64:
                        profile_pic_b64 = profile_pic_b64.split(',', 1)[1]
                    rider_profile.profile_picture.save(
                        f"profile_{uuid.uuid4()}.jpg",
                        ContentFile(base64.b64decode(profile_pic_b64)),
                        save=True,
                    )
                    cache.delete(f"reg_profile_pic_{self.session_id}")
                except Exception as e:
                    logger.warning(f"Profile picture save failed for session {self.session_id}: {e}")

            # Generate tokens
            refresh = RefreshToken.for_user(user)
            return {
                'user_id': user.id,
                'username': user.username,
                'email': user.email,
                'is_social': is_social,
                'provider': metadata.get('provider', ''),
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
                    # Send status update for all state changes
                    await self.send(text_data=json.dumps({
                        'type': 'status_update',
                        'status': current_status,
                        'message': self.get_status_message(current_status)
                    }))

                    if current_status == 'verified':
                        try:
                            user_data = await self.create_user_and_profile(session.metadata)
                            await self.send(text_data=json.dumps({
                                'type': 'verification_complete',
                                'status': 'verified',
                                'message': 'Verification successful',
                                'user': user_data
                            }))
                            await asyncio.sleep(2)
                            await self.close()
                            break
                        except ValueError as e:
                            logger.error(f"User creation failed: {str(e)}")
                            await self.send(text_data=json.dumps({
                                'type': 'verification_complete',
                                'status': 'unverified',
                                'message': f'Registration failed: {str(e)}'
                            }))
                            await self.close()
                            break
                        except Exception as e:
                            logger.error(f"Unexpected error during user creation: {str(e)}")
                            await self.send(text_data=json.dumps({
                                'type': 'verification_complete',
                                'status': 'unverified',
                                'message': 'Registration failed due to system error'
                            }))
                            await self.close()
                            break
                    
                    elif current_status in ["error", "canceled"]:
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
                
            except stripe.error.StripeError as e:
                logger.error(f"Stripe API error: {str(e)}")
                await self.send(text_data=json.dumps({
                    'type': 'error',
                    'message': 'Verification service error',
                    'error': str(e)
                }))
                await asyncio.sleep(2)
                continue
            except Exception as e:
                logger.error(f"Status check error: {str(e)}")
                await self.send(text_data=json.dumps({
                    'type': 'verification_complete',
                    'status': 'unverified',
                    'message': 'Verification error occurred'
                }))
                await self.close()
                break

        # If we exit the loop without completing, close with timeout message
        if retry_count >= max_retries:
            await self.send(text_data=json.dumps({
                'type': 'verification_complete',
                'status': 'timeout',
                'message': 'Verification timeout - please try again'
            }))
            await self.close()

    def get_status_message(self, status):
        """Get user-friendly status messages"""
        status_messages = {
            'requires_input': 'Please complete the verification process',
            'processing': 'Processing your verification...',
            'verified': 'Verification successful!',
            'failed': 'Verification failed. Please try again',
            'canceled': 'Verification was canceled'
        }
        return status_messages.get(status, f'Status: {status}')

    async def disconnect(self, close_code):
        logger.info(f"WebSocket disconnected with code {close_code}")
        if hasattr(self, '_verification_task') and not self._verification_task.done():
            self._verification_task.cancel()
        await self.channel_layer.group_discard(
            self.group_name,
            self.channel_name
        )

    async def verification_status(self, event):
        logger.info(f"Received verification status: {event}")
        message = event['status']
        await self.send(text_data=json.dumps({
            'type': 'verification_status',
            'data': message
        }))
