import logging
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.apps import apps

logger = logging.getLogger(__name__)


def notify_user(user_id: int, title: str, message: str, data: dict) -> None:
    """Persist a notification to DB and push it to the user's notification WebSocket group.

    Works from any synchronous context (views, signals). The notification is
    saved regardless of whether the user is currently connected.
    """
    Notification = apps.get_model('chat', 'Notification')
    try:
        Notification.objects.create(
            recipient_id=user_id,
            title=title,
            message=message,
            data=data,
        )
    except Exception as e:
        logger.warning(f"notify_user: failed to persist notification for user {user_id}: {e}")

    channel_layer = get_channel_layer()
    try:
        async_to_sync(channel_layer.group_send)(
            f'notifications_{user_id}',
            {
                'type': 'send_notification',
                'title': title,
                'message': message,
                'data': data,
            }
        )
    except Exception as e:
        logger.warning(f"notify_user: failed to broadcast notification for user {user_id}: {e}")
