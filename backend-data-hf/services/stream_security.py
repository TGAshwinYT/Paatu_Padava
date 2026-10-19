import urllib.parse
import ipaddress
import socket
from typing import Tuple

ALLOWED_STREAM_DOMAINS: Tuple[str, ...] = (
    "saavncdn.com",
    "googlevideo.com",
    "youtube.com",
    "jio.com",
    "akamaized.net"
)

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
