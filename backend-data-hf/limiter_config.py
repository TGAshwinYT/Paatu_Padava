from fastapi import Request
from slowapi import Limiter
from slowapi.util import get_remote_address


def get_client_ip(request: Request) -> str:
    """
    Extracts real client IP from trusted reverse proxy hop (Hugging Face Spaces, Vercel, Nginx).
    The last IP in the X-Forwarded-For chain is appended by the nearest trusted reverse proxy,
    preventing client-controlled IP spoofing attacks via arbitrary header prefix injection.
    Falls back to request.client.host, get_remote_address, or localhost.
    """
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        ips = [ip.strip() for ip in forwarded.split(",") if ip.strip()]
        if ips:
            # The right-most IP is the one appended by the nearest trusted reverse proxy
            return ips[-1]

    real_ip = request.headers.get("x-real-ip")
    if real_ip and real_ip.strip():
        return real_ip.strip()

    if getattr(request, "client", None) and getattr(request.client, "host", None):
        return request.client.host

    return get_remote_address(request) or "127.0.0.1"


limiter = Limiter(key_func=get_client_ip)
