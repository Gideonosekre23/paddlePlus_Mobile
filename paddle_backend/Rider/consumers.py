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
        from django.core.cache import cache as _cache
        pw_key = metadata.get('pw_key')
        if not pw_key:
            raise ValueError("Registration session has no password reference")
        password = _cache.get(f"reg_pw_{pw_key}")
        if not password:
            raise ValueError("Registration session expired — please register again")
        _cache.delete(f"reg_pw_{pw_key}")

        with transaction.atomic():
            user = User.objects.create_user(
                username=metadata['username'],
                email=metadata['email'],
                password=password
            )
            
            rider_profile = UserProfile.objects.create(
                user=user,
                phone_number=metadata.get('phone_number', ''),
                cpn=metadata.get('cpn', ''),
                address=metadata.get('address', ''),
                latitude=float(metadata['latitude']) if metadata.get('latitude', '').strip() else None,
                longitude=float(metadata['longitude']) if metadata.get('longitude', '').strip() else None,
                verification_status='verified',
                verification_session_id=self.session_id,
                apple_sub=metadata.get('apple_sub') or None,
            )

            from django.core.cache import cache
            import base64
            import uuid as _uuid
            from django.core.files.base import ContentFile
            profile_pic_b64 = cache.get(f"reg_profile_pic_{self.session_id}")
            if profile_pic_b64:
                try:
                    if ',' in profile_pic_b64:
                        profile_pic_b64 = profile_pic_b64.split(',', 1)[1]
                    # 5 MB limit for base64 profile pictures (~3.7 MB raw)
                    if len(profile_pic_b64) > 7_000_000:
                        logger.warning(f"Profile picture too large for session {self.session_id}, skipping")
                    else:
                        rider_profile.profile_picture.save(
                            f"profile_{_uuid.uuid4()}.jpg",
                            ContentFile(base64.b64decode(profile_pic_b64)),
                            save=True,
                        )
                    cache.delete(f"reg_profile_pic_{self.session_id}")
                except Exception as e:
                    logger.warning(f"Profile picture save failed for session {self.session_id}: {e}")

            refresh = RefreshToken.for_user(user)
            access = str(refresh.access_token)

            scheme = self.scope.get('scheme', 'ws')
            server = self.scope.get('server', ('localhost', 8000))
            host = f"{server[0]}:{server[1]}"

            return {
                'id': user.id,
                'username': user.username,
                'email': user.email,
                'phone_number': rider_profile.phone_number,
                'profile_picture': rider_profile.profile_picture.url if rider_profile.profile_picture else None,
                'verification_status': 'verified',
                'access': access,
                'refresh': str(refresh),
                'ws_url': f'{scheme}://{host}/ws/notifications/user_{user.id}/?token={access}',
                'chat_ws_url': f'{scheme}://{host}/ws/chat/',
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
                    
                    elif current_status == 'failed' or current_status == 'canceled' :
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
