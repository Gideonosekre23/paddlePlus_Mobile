import re
from urllib.parse import parse_qs

from channels.middleware import BaseMiddleware
from channels.db import database_sync_to_async
from django.contrib.auth.models import AnonymousUser
from rest_framework_simplejwt.tokens import AccessToken
from django.contrib.auth import get_user_model

User = get_user_model()


@database_sync_to_async
def _user_from_token(token_str):
    try:
        token = AccessToken(token_str)
        return User.objects.get(id=token['user_id'])
    except Exception:
        return AnonymousUser()


class JWTWebSocketMiddleware(BaseMiddleware):
    """
    Authenticates WebSocket connections via JWT.
    Checks two locations (in order):
      1. ?token=<jwt> query parameter  (used by the chat consumer)
      2. URL path segment matching user_<id>_<token> (used by the notification consumer)
    Sets scope['user'] to the authenticated User or AnonymousUser.
    """

    async def __call__(self, scope, receive, send):
        token_str = None

        # 1. Query string
        query_string = scope.get('query_string', b'').decode()
        params = parse_qs(query_string)
        token_list = params.get('token', [])
        if token_list:
            token_str = token_list[0]

        # 2. URL path (notification channel format: user_<id>_<access_token>)
        if not token_str:
            path = scope.get('path', '')
            match = re.search(r'/user_\d+_([^/]+)/', path)
            if match:
                token_str = match.group(1)

        scope['user'] = (
            await _user_from_token(token_str) if token_str else AnonymousUser()
        )

        return await super().__call__(scope, receive, send)
