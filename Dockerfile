FROM python:3.11

ENV PYTHONUNBUFFERED=1

WORKDIR /app

# requirements.txt lives inside paddle_backend/ (root one was removed)
COPY paddle_backend/requirements.txt .
RUN pip install -r requirements.txt

COPY . .

# Daphne must run from the Django project root so "paddle_backend.asgi" resolves
WORKDIR /app/paddle_backend

EXPOSE 8000

CMD ["sh", "-c", "python manage.py migrate --noinput && daphne -b 0.0.0.0 -p 8000 paddle_backend.asgi:application"]
