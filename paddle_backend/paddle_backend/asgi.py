import os





os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'paddle_backend.settings')
import django
django.setup()


from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack
from channels.security.websocket import AllowedHostsOriginValidator


django_asgi_app = get_asgi_application()

from .routing import websocket_urlpatterns
application = ProtocolTypeRouter({
    "http": get_asgi_application(),
    "websocket": URLRouter(websocket_urlpatterns),
})