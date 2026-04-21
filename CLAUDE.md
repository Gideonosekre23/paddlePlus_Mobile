# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PaddlePlus is a bike-sharing platform with:
- **Django REST + Channels backend** (WebSocket + HTTP API)
- **Flutter Rider app** (`paddle_frontend_App/paddleapp/`)
- **Flutter Owner/Bike Manager app** (`paddle_frontend_App/paddlebike/`)

---

## Backend Commands

```bash
# Setup
cd paddle_backend
python -m venv paddleenv
source paddleenv/Scripts/activate      # Windows
pip install -r requirements.txt

# Run (HTTP only)
python manage.py runserver 0.0.0.0:8000

# Run with WebSocket support
daphne -b 0.0.0.0 -p 8000 paddle_backend.asgi:application

# Database
python manage.py migrate
python manage.py makemigrations

# Docker (includes Redis + PostgreSQL)
docker-compose up
```

## Frontend Commands

```bash
# Rider app
cd paddle_frontend_App/paddleapp
flutter pub get
flutter run

# Owner app
cd paddle_frontend_App/paddlebike
flutter pub get
flutter run
```

---

## Backend Architecture

### Django Apps

| App | Responsibility |
|-----|---------------|
| `Bikes` | Bike hardware (GPS, TOTP unlock codes), bike listings, availability |
| `Owner` | Owner profiles, Stripe webhooks, earnings |
| `Rider` | Rider profiles, location tracking, Stripe webhooks |
| `Riderequest` | Ride requests lifecycle (create → accept/decline/cancel) |
| `Trip` | Trip lifecycle (waiting → started → ontrip → completed), pricing |
| `chat` | Chat rooms scoped to trips, messages, read status |

### WebSocket Endpoints (`paddle_backend/routing.py`)

```
ws/verification/<session_id>/        # Rider KYC verification
ws/owner/verification/<session_id>/  # Owner KYC verification
ws/chat/<trip_id>/?token=<jwt>       # In-trip chat (JWT in query string)
ws/notifications/<channel_id>/       # Push notifications (format: user_<id>_<token>)
ws/arduino/<device_id>/              # Hardware IoT communication
```

Channel layer uses `InMemoryChannelLayer` locally; switch to `channels_redis` for production.

### Auth

JWT via `rest_framework_simplejwt`. Access tokens expire in 30 minutes; refresh tokens in 1 day with rotation + blacklisting. For WebSockets, the JWT is passed as a `?token=` query parameter.

Social auth (Google OAuth2, Apple Sign-In) is configured via `django-allauth`.

### Pricing & Payments

- Stripe handles all payments. Keys/webhook secrets live in `paddle_backend/paddle_backend/.env`.
- Platform commission is 15–20%, calculated in `Bikes/pricing.py`.
- Webhook endpoints: `/owner/webhook/stripe/` and `/rider/webhook/stripe/`.

### Bike Hardware

`BikeHardware` model generates TOTP-based unlock codes using `TOTP_FACTORY_KEY` from `.env`. The `ArduinoConsumer` WebSocket handles GPS updates, battery level, heartbeat, and emergency alerts from physical devices.

---

## Frontend Architecture

Both Flutter apps share the same structural pattern:

```
lib/
├── Apiendpoints/
│   ├── apiservices/    # HTTP + WebSocket service classes
│   └── models/         # Dart model classes
├── pages/              # Full-screen pages (GetX routing)
├── constants/          # API base URL, shared constants
└── themes/
```

**State management:** GetX (`get` package) for routing and controllers; `provider` for some shared state.

**Key services (both apps):**
- `auth_api_service.dart` — login, register, social auth
- `base_api_service.dart` — authenticated HTTP requests with token refresh
- `token_storage_service.dart` — `flutter_secure_storage` for JWT
- `user_session_manager.dart` — current user state
- `chat_api_service.dart` — chat REST + WebSocket

---

## Key Configuration

- **Settings:** `paddle_backend/paddle_backend/settings.py`
- **URLs:** `paddle_backend/paddle_backend/urls.py`
- **WebSocket routing:** `paddle_backend/paddle_backend/routing.py`
- **ASGI app:** `paddle_backend/paddle_backend/asgi.py`
- **Env vars:** `paddle_backend/paddle_backend/.env` — contains Stripe keys, Django secret, JWT secret, Google/Apple OAuth credentials, `TOTP_FACTORY_KEY`

In development, `DEBUG = True`, SQLite is used, and `CORS_ALLOW_ALL_ORIGINS = True`. The docker-compose setup switches to PostgreSQL + Redis.
