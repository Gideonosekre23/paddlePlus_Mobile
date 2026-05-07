import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'paddle_backend.settings')
django.setup()

from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from .routing import websocket_urlpatterns
from .jwt_ws_middleware import JWTWebSocketMiddleware

django_asgi_app = get_asgi_application()

application = ProtocolTypeRouter({
    "http": get_asgi_application(),
    "websocket": JWTWebSocketMiddleware(URLRouter(websocket_urlpatterns)),
})