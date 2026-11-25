import base64
import hashlib
import hmac
import ipaddress
import json
import os
import socket
import time
import urllib.parse
from typing import Optional, Tuple

ALLOWED_STREAM_DOMAINS: Tuple[str, ...] = (
    "saavncdn.com",
    "googlevideo.com",
    "youtube.com",
    "jio.com",
    "akamaized.net"
)


def get_stream_signing_secret() -> str:
    """
    Returns the HMAC signing secret for short-lived stream/download tokens.
    Uses STREAM_SIGNING_SECRET if set, otherwise falls back to JWT_SECRET.
    """
    secret = os.getenv("STREAM_SIGNING_SECRET") or os.getenv("JWT_SECRET") or ""
    if not secret:
        raise RuntimeError(
            "FATAL SECURITY ERROR: 'STREAM_SIGNING_SECRET' or 'JWT_SECRET' must be set."
        )
    return secret


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64url_decode(encoded: str) -> bytes:
    padding = "=" * (-len(encoded) % 4)
    return base64.urlsafe_b64decode(encoded + padding)


def create_signed_media_token(
    subject: str,
    purpose: str = "stream",
    ttl_seconds: int = 900,
    session_id: str = "",
) -> str:
    """
    Mints a short-lived HMAC-SHA256 signed token bound to a media subject
    (song_id, CDN URL, or sorted prefetch IDs), purpose, and optional session_id.
    """
    payload = {
        "sub": subject,
        "pur": purpose,
        "sid": session_id or "",
        "exp": int(time.time()) + ttl_seconds,
    }
    payload_bytes = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    payload_b64 = _b64url_encode(payload_bytes)
    sig = hmac.new(
        get_stream_signing_secret().encode("utf-8"),
        payload_b64.encode("ascii"),
        hashlib.sha256,
    ).hexdigest()
    return f"{payload_b64}.{sig}"


def verify_signed_media_token(
    token: Optional[str],
    subject: str,
    purpose: str = "stream",
    session_id: Optional[str] = None,
) -> bool:
    """
    Verifies a short-lived HMAC-SHA256 media token.
    Enforces signature integrity, expiration, purpose, subject match,
    and strict session_id binding whenever the token carries a non-empty 'sid'.
    """
    if not token or not isinstance(token, str) or "." not in token or not subject:
        return False
    try:
        payload_b64, sig_hex = token.rsplit(".", 1)
        if not payload_b64 or not sig_hex:
            return False
        expected_sig = hmac.new(
            get_stream_signing_secret().encode("utf-8"),
            payload_b64.encode("ascii"),
            hashlib.sha256,
        ).hexdigest()
        if not hmac.compare_digest(expected_sig, sig_hex):
            return False

        payload = json.loads(_b64url_decode(payload_b64).decode("utf-8"))
        if not isinstance(payload, dict):
            return False

        exp = payload.get("exp")
        if not isinstance(exp, (int, float)) or exp < time.time():
            return False
        if payload.get("pur") != purpose:
            return False
        if not hmac.compare_digest(str(payload.get("sub") or ""), subject):
            return False

        token_sid = str(payload.get("sid") or "")
        if token_sid:
            if not session_id or not hmac.compare_digest(token_sid, session_id):
                return False

        return True
    except Exception:
        return False

def is_safe_audio_url(url_str: str) -> bool:
    """
    Validates that a URL is a legitimate, public audio streaming CDN
    and blocks private/loopback/cloud metadata SSRF vectors.
    """
    if not url_str or not isinstance(url_str, str):
        return False
    try:
        parsed = urllib.parse.urlparse(url_str)
        if parsed.scheme not in ("http", "https"):
            return False
        host = (parsed.hostname or "").lower().strip()
        if not host:
            return False

        # Must end with or equal one of the whitelisted music CDN domains
        if not any(host == d or host.endswith("." + d) for d in ALLOWED_STREAM_DOMAINS):
            return False

        # Ensure hostname is not an internal/private IP or resolving to one
        try:
            ip_obj = ipaddress.ip_address(host)
            if ip_obj.is_private or ip_obj.is_loopback or ip_obj.is_link_local or ip_obj.is_multicast or ip_obj.is_reserved:
                return False
        except ValueError:
            # Domain name: verify DNS resolution does not pivot to private/internal CIDRs
            try:
                for addrinfo in socket.getaddrinfo(host, None):
                    resolved_ip = addrinfo[4][0]
                    ip_obj = ipaddress.ip_address(resolved_ip)
                    if ip_obj.is_private or ip_obj.is_loopback or ip_obj.is_link_local or ip_obj.is_multicast or ip_obj.is_reserved:
                        return False
            except socket.gaierror:
                # Hostname cannot currently be resolved (e.g. offline test environment).
                # The domain suffix whitelist check above ensures it belongs to authorized CDNs.
                pass
            except Exception:
                return False

        return True
    except Exception:
        return False
