from fastapi import Request
from slowapi import Limiter
from slowapi.util import get_remote_address


def get_client_ip(request: Request) -> str:
    """
    Extracts real client IP behind reverse proxies (Hugging Face Spaces, Vercel, Nginx).
    Falls back to get_remote_address or localhost.
    """
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        # First IP in comma-separated list is client IP
        return forwarded.split(",")[0].strip()
    real_ip = request.headers.get("x-real-ip")
    if real_ip:
        return real_ip.strip()
    return get_remote_address(request) or "127.0.0.1"


limiter = Limiter(key_func=get_client_ip)
