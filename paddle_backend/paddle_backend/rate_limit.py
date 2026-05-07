from functools import wraps
from django.core.cache import cache
from django.http import JsonResponse


def _parse_rate(rate: str) -> tuple[int, int]:
    """Parse "N/Xs|m|h" into (max_calls, window_seconds)."""
    count_str, period = rate.split('/')
    count = int(count_str)
    if period.endswith('s'):
        seconds = int(period[:-1])
    elif period.endswith('m'):
        seconds = int(period[:-1]) * 60
    elif period.endswith('h'):
        seconds = int(period[:-1]) * 3600
    else:
        seconds = int(period)
    return count, seconds


def _get_ip(request) -> str:
    forwarded = request.META.get('HTTP_X_FORWARDED_FOR', '')
    if forwarded:
        return forwarded.split(',')[0].strip()
    return request.META.get('REMOTE_ADDR', 'unknown')


def rate_limit(rate: str):
    """
    Cache-based rate limiter keyed by (view name + client IP).

    Usage:
        @rate_limit('10/15m')   # 10 calls per 15 minutes per IP
        @api_view(['POST'])
        def my_view(request): ...

    Rates: "N/Xs" (seconds), "N/Xm" (minutes), "N/Xh" (hours).
    Returns HTTP 429 with Retry-After header when the limit is exceeded.
    """
    max_calls, window = _parse_rate(rate)

    def decorator(view_func):
        @wraps(view_func)
        def wrapped(request, *args, **kwargs):
            ip = _get_ip(request)
            cache_key = f"rl:{view_func.__name__}:{ip}"

            try:
                count_now = cache.incr(cache_key)
            except ValueError:
                # Key did not exist — initialise it
                cache.set(cache_key, 1, timeout=window)
                count_now = 1

            if count_now > max_calls:
                response = JsonResponse(
                    {'error': 'Too many requests. Please try again later.'},
                    status=429,
                )
                response['Retry-After'] = str(window)
                return response

            return view_func(request, *args, **kwargs)
        return wrapped
    return decorator
