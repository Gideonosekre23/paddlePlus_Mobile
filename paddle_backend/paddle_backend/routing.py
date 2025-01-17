from django.urls import re_path
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack
from channels.security.websocket import AllowedHostsOriginValidator
from chat.consumers import ChatConsumer, UserNotificationConsumer
from Bikes.consumers import GPSConsumer
from Rider.consumers import VerificationRiderConsumer
from Owner.consumers import VerificationOwnerConsumer




websocket_urlpatterns = [
    re_path(r'^ws/verification/(?P<session_id>vs_[A-Za-z0-9]+)/$', VerificationRiderConsumer.as_asgi()),
    re_path(r'^ws/owner/verification/(?P<session_id>vs_[A-Za-z0-9]+)/$', VerificationOwnerConsumer.as_asgi()),
    re_path(r'^ws/chat/(?P<trip_id>\w+)/$', ChatConsumer.as_asgi()),
    re_path(r'^ws/hardware/(?P<serial_number>\w+)/gps/$', GPSConsumer.as_asgi()),
    re_path(r'^ws/notifications/(?P<channel_id>[\w.%+-]+)/$', UserNotificationConsumer.as_asgi()),
]

