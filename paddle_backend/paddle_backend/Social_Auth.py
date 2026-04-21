import jwt
import logging
import requests
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests
from django.conf import settings
from django.core.cache import cache
from django.contrib.auth.models import User
from django.utils.crypto import get_random_string
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)


def _verify_google_token(token: str) -> str:
    """Verify Google OAuth2 ID token and return email."""
    try:
        if not getattr(settings, 'GOOGLE_CLIENT_ID', None):
            raise ValueError("Google client ID not configured")

        idinfo = google_id_token.verify_oauth2_token(
            token,
            google_requests.Request(),
            audience=settings.GOOGLE_CLIENT_ID
        )

        if not idinfo.get('email_verified', False):
            raise ValueError("Email not verified by Google")

        email = idinfo.get('email')
        if not email:
            raise ValueError("Email not found in Google token")

        logger.info(f"Verified Google token for: {email}")
        return email

    except Exception as e:
        logger.error(f"Google token verification failed: {str(e)}")
        raise ValueError(f"Invalid Google token: {str(e)}")


def _verify_apple_token(token: str) -> tuple:
    """
    Verify Apple Sign In JWT and return (email_or_none, sub).

    Apple only includes email on the FIRST sign-in. On all subsequent
    sign-ins the email field is absent. The `sub` (subject) is always
    present and is a stable unique identifier per user per app.
    """
    try:
        if not getattr(settings, 'APPLE_CLIENT_ID', None):
            raise ValueError("Apple client ID not configured")

        keys = _get_apple_public_keys()

        header = jwt.get_unverified_header(token)
        key = next((k for k in keys if k['kid'] == header['kid']), None)
        if key is None:
            raise ValueError("Apple public key not found for kid: " + header.get('kid', '?'))

        public_key = jwt.algorithms.RSAAlgorithm.from_jwk(key)
        decoded = jwt.decode(
            token,
            public_key,
            audience=settings.APPLE_CLIENT_ID,
            algorithms=['RS256']
        )

        # Validate audience (Apple can send it as string or list)
        aud = decoded.get('aud')
        expected = settings.APPLE_CLIENT_ID
        if isinstance(aud, list):
            if expected not in aud:
                raise ValueError("Invalid audience in Apple token")
        elif aud != expected:
            raise ValueError("Invalid audience in Apple token")

        sub = decoded.get('sub')
        if not sub:
            raise ValueError("Missing sub in Apple token")

        email = decoded.get('email')  # None on returning users — intentional
        logger.info(f"Verified Apple token sub={sub} email={'present' if email else 'absent'}")
        return email, sub

    except Exception as e:
        logger.warning(f"Apple token verification failed: {str(e)}")
        raise ValueError(f"Invalid Apple token: {str(e)}")


def _get_apple_public_keys():
    """Fetch (and cache for 1 hour) Apple's public signing keys."""
    keys = cache.get("apple_public_keys")
    if not keys:
        try:
            response = requests.get("https://appleid.apple.com/auth/keys", timeout=10)
            response.raise_for_status()
            keys = response.json()['keys']
            cache.set("apple_public_keys", keys, timeout=3600)
        except Exception as e:
            logger.error(f"Failed to fetch Apple public keys: {str(e)}")
            raise ValueError("Unable to fetch Apple public keys")
    return keys


def extract_email_from_social_token(provider: str, token: str) -> str:
    """
    Verify social token and return the user's email.
    Used during registration (Apple always includes email on first sign-up).
    """
    provider = provider.lower()
    if provider == 'google':
        return _verify_google_token(token)
    elif provider == 'apple':
        email, sub = _verify_apple_token(token)
        if not email:
            raise ValueError(
                "Apple did not provide an email. "
                "This account may already be registered — please use login instead."
            )
        return email
    else:
        raise ValueError(f"Unsupported social provider: {provider}")


def get_apple_sub_from_token(token: str) -> str:
    """Extract Apple sub from token without requiring email (for registration payload)."""
    _, sub = _verify_apple_token(token)
    return sub


def verify_social_token_for_login(provider: str, token: str) -> str:
    """
    Verify social token for login and return the user's email.
    For Apple returning users (no email in token) looks up the account
    by the stable `sub` field stored during registration.
    """
    provider = provider.lower()

    if provider == 'google':
        return _verify_google_token(token)

    elif provider == 'apple':
        email, sub = _verify_apple_token(token)

        if email:
            return email

        # Returning Apple user — email absent, look up by stored sub
        from Rider.models import UserProfile
        from Owner.models import OwnerProfile

        profile = (
            UserProfile.objects.filter(apple_sub=sub).select_related('user').first()
            or OwnerProfile.objects.filter(apple_sub=sub).select_related('user').first()
        )
        if profile:
            logger.info(f"Apple returning user matched via sub={sub}")
            return profile.user.email

        raise ValueError(
            "Apple account not recognised. "
            "If this is your first sign-in, please use the registration flow."
        )

    else:
        raise ValueError(f"Unsupported social provider: {provider}")


def validate_social_provider(provider: str) -> bool:
    return provider.lower() in ('google', 'apple')


def generate_username_from_email(email: str) -> str:
    """Generate a unique username from email, with collision handling."""
    base = email.split('@')[0]
    username = base
    counter = 1
    while User.objects.filter(username=username).exists():
        username = f"{base}{counter}"
        counter += 1
    return username


def create_social_payload(provider: str, provider_token: str, email: str) -> dict:
    """
    Build the short-lived JWT payload for phase-2 registration.
    Includes apple_sub so it can be saved to the profile after verification.
    """
    username = generate_username_from_email(email)
    payload = {
        'username': username,
        'email': email,
        'password': get_random_string(length=16),
        'is_social': True,
        'provider': provider,
        'exp': datetime.utcnow() + timedelta(minutes=30),
    }

    if provider.lower() == 'apple':
        try:
            _, sub = _verify_apple_token(provider_token)
            payload['apple_sub'] = sub
        except Exception:
            pass  # sub missing won't break registration, just won't be stored

    return payload
