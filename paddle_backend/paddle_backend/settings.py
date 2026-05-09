from pathlib import Path
from datetime import timedelta
import os
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / '.env')

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.getenv('DJANGO_SECRET_KEY')

DEBUG = os.getenv('DEBUG', 'False').lower() == 'true'

_EXTRA_HOSTS = os.getenv('ALLOWED_HOSTS', '')
ALLOWED_HOSTS = ['127.0.0.1', 'localhost', '.onrender.com']
if _EXTRA_HOSTS:
    ALLOWED_HOSTS += [h.strip() for h in _EXTRA_HOSTS.split(',') if h.strip()]
elif DEBUG:
    # Dev only — never set DEBUG=True in production
    ALLOWED_HOSTS += ['192.168.1.7', '.ngrok-free.app']

_CSRF_EXTRA = os.getenv('CSRF_TRUSTED_ORIGINS', '')
CSRF_TRUSTED_ORIGINS = ['https://*.ngrok-free.app', 'https://*.onrender.com']
if _CSRF_EXTRA:
    CSRF_TRUSTED_ORIGINS += [o.strip() for o in _CSRF_EXTRA.split(',') if o.strip()]
elif DEBUG:
    CSRF_TRUSTED_ORIGINS += ['http://localhost:3000']

# Trust Render's (and other reverse-proxy's) X-Forwarded-Proto header so that
# request.is_secure() returns True and WebSocket URLs are built with wss://.
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
USE_X_FORWARDED_HOST = True

CORS_ALLOW_CREDENTIALS = True

INSTALLED_APPS = [
    'django.contrib.auth',
    'django.contrib.admin',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework_simplejwt',
    'channels',
    'rest_framework',
    'Rider', 
    'Bikes',
    'Owner',
    'corsheaders',
    'Riderequest',
    'Trip',
    'stripe',
    'chat',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
]

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ],
}

SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=30),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=1),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'AUTH_HEADER_TYPES': ('Bearer',),
    'AUTH_TOKEN_CLASSES': ('rest_framework_simplejwt.tokens.AccessToken',),
}

# Stripe Configuration
STRIPE_PUBLISHABLE_KEY = os.getenv('STRIPE_PUBLISHABLE_KEY')
STRIPE_SECRET_KEY = os.getenv('STRIPE_SECRET_KEY')
STRIPE_WEBHOOK_SECRET = os.getenv('STRIPE_WEBHOOK_SECRET')

GOOGLE_CLIENT_ID = os.getenv('GOOGLE_OAUTH_CLIENT_ID', '')
APPLE_CLIENT_ID = os.getenv('APPLE_CLIENT_ID', '')
FRONTEND_URL = os.getenv('FRONTEND_URL', 'http://localhost:3000')

ROOT_URLCONF = 'paddle_backend.urls'
ASGI_APPLICATION = 'paddle_backend.asgi.application'

_REDIS_URL = os.getenv('REDIS_URL')
if _REDIS_URL:
    CHANNEL_LAYERS = {
        'default': {
            'BACKEND': 'channels_redis.core.RedisChannelLayer',
            'CONFIG': {'hosts': [_REDIS_URL]},
        }
    }
    # Share the cache across workers so rate limits are enforced cluster-wide
    CACHES = {
        'default': {
            'BACKEND': 'django.core.cache.backends.redis.RedisCache',
            'LOCATION': _REDIS_URL,
        }
    }
else:
    CHANNEL_LAYERS = {
        'default': {
            'BACKEND': 'channels.layers.InMemoryChannelLayer'
        }
    }
    # Development: in-process memory cache (already the Django default)

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

_DB_URL = os.getenv('DATABASE_URL', '')
if _DB_URL:
    import dj_database_url  # type: ignore
    DATABASES = {'default': dj_database_url.parse(_DB_URL, conn_max_age=600)}
else:
    # SQLite is fine for development. In production set DATABASE_URL to a PostgreSQL URL.
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': str(BASE_DIR / 'db.sqlite3'),
        }
    }

# Logging Configuration
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
        },
    },
    'root': {
        'handlers': ['console'],
        'level': 'INFO',
    },
}

# Email configuration
EMAIL_BACKEND = os.getenv('EMAIL_BACKEND', 'django.core.mail.backends.console.EmailBackend')
EMAIL_HOST = os.getenv('EMAIL_HOST', 'smtp.gmail.com')
EMAIL_PORT = int(os.getenv('EMAIL_PORT', '587'))
EMAIL_USE_TLS = True
EMAIL_HOST_USER = os.getenv('EMAIL_HOST_USER', '')
EMAIL_HOST_PASSWORD = os.getenv('EMAIL_HOST_PASSWORD', '')
DEFAULT_FROM_EMAIL = os.getenv('DEFAULT_FROM_EMAIL', 'noreply@paddleplus.app')

PLATFORM_COMMISSION_RATE = os.getenv('PLATFORM_COMMISSION_RATE', '0.15')

DEMO_MODE = os.getenv('DEMO_MODE', 'False').lower() == 'true'

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'
STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')

MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# CORS Configuration
_CORS_ORIGINS = os.getenv('CORS_ALLOWED_ORIGINS', '')
if _CORS_ORIGINS:
    CORS_ALLOW_ALL_ORIGINS = False
    CORS_ALLOWED_ORIGINS = [o.strip() for o in _CORS_ORIGINS.split(',') if o.strip()]
elif DEBUG:
    CORS_ALLOW_ALL_ORIGINS = True  # dev only — never reaches production if DEBUG=False
else:
    # Production with no CORS_ALLOWED_ORIGINS set: lock down, allow nothing
    CORS_ALLOW_ALL_ORIGINS = False
    CORS_ALLOWED_ORIGINS = []

CORS_ALLOW_METHODS = [
    'DELETE',
    'GET',
    'OPTIONS',
    'PATCH',
    'POST',
    'PUT',
]
