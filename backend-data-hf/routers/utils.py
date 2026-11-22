import ipaddress
import logging
import os
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, Request, Response
import httpx

from auth_utils import get_current_user
from models import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["utils"])

DEFAULT_SCRAPER_CONFIG = {
    "version": 1,
    "lastUpdated": "2026-11-14T15:26:00Z",
    "saavn": {
        "enabled": True,
        "primaryDesKey": os.getenv("SAAVN_DES_KEY", "38346591"),
        "fallbackDesKeys": ["38346591", "29471958", "48201948"],
        "baseUrl": "https://www.jiosaavn.com/api.php",
        "headers": {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "application/json, text/plain, */*"
        }
    },
    "innertube": {
        "enabled": True,
        "clients": [
            {
                "name": "IOS",
                "client": {
                    "clientName": "IOS",
                    "clientVersion": "19.45.4",
                    "deviceMake": "Apple",
                    "deviceModel": "iPhone16,2",
                    "osName": "iPhone",
                    "osVersion": "18.1.0.22B83",
                    "hl": "en",
                    "gl": "IN"
                },
                "headers": {
                    "Content-Type": "application/json",
                    "User-Agent": "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)",
                    "X-YouTube-Client-Name": "5",
                    "X-YouTube-Client-Version": "19.45.4",
                    "Accept": "*/*"
                }
            },
            {
                "name": "IOS_UPDATED",
                "client": {
                    "clientName": "IOS",
                    "clientVersion": "21.26.4",
                    "deviceMake": "Apple",
                    "deviceModel": "iPhone16,2",
                    "osName": "iPhone",
                    "osVersion": "18.1.0.22B83",
                    "hl": "en",
                    "gl": "IN"
                },
                "headers": {
                    "Content-Type": "application/json",
                    "User-Agent": "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)",
                    "X-YouTube-Client-Name": "5",
                    "X-YouTube-Client-Version": "21.26.4",
                    "Accept": "*/*"
                }
            },
            {
                "name": "ANDROID_VR",
                "client": {
                    "clientName": "ANDROID_VR",
                    "clientVersion": "1.56.21",
                    "androidSdkVersion": 32,
                    "gl": "IN",
                    "hl": "en"
                },
                "headers": {
                    "Content-Type": "application/json",
                    "User-Agent": "com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12; en_US; Quest 2; Build/SQ3A.220605.009.A1) gzip",
                    "X-YouTube-Client-Name": "28",
                    "X-YouTube-Client-Version": "1.56.21",
                    "Accept": "*/*"
                }
            },
            {
                "name": "ANDROID",
                "client": {
                    "clientName": "ANDROID",
                    "clientVersion": "19.29.37",
                    "androidSdkVersion": 34,
                    "gl": "IN",
                    "hl": "en"
                },
                "headers": {
                    "Content-Type": "application/json",
                    "User-Agent": "com.google.android.youtube/19.29.37 (Linux; U; Android 14; en_US; Pixel 8 Pro; Build/UQ1A.240205.004) gzip",
                    "X-YouTube-Client-Name": "3",
                    "X-YouTube-Client-Version": "19.29.37",
                    "Accept": "*/*"
                }
            },
            {
                "name": "WEB_REMIX",
                "client": {
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20240722.01.00",
                    "gl": "IN",
                    "hl": "en"
                },
                "headers": {
                    "Content-Type": "application/json",
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
                    "X-YouTube-Client-Name": "67",
                    "X-YouTube-Client-Version": "1.20240722.01.00",
                    "Referer": "https://music.youtube.com/",
                    "Accept": "*/*"
                }
            },
            {
                "name": "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
                "client": {
                    "clientName": "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
                    "clientVersion": "2.0",
                    "gl": "IN",
                    "hl": "en"
                },
                "headers": {
                    "Content-Type": "application/json",
                    "User-Agent": "Mozilla/5.0 (PlayStation; PlayStation 4/10.01) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/10.01 Safari/605.1.15",
                    "X-YouTube-Client-Name": "85",
                    "X-YouTube-Client-Version": "2.0",
                    "Accept": "*/*"
                }
            }
        ]
    },
    "fallbackOrder": ["saavn_direct", "saavn_search", "youtube_innertube", "backend_proxy", "audius"],
    "backendResolver": {
        "enabled": True,
        "timeoutMs": 4000
    }
}

@router.get("/config/scraper")
async def get_scraper_config(response: Response):
    """
    Over-The-Air (OTA) Scraper & Decryption Configuration.
    Allows dynamic key rotation and InnerTube client updates without app store releases.
    """
    response.headers["Cache-Control"] = "public, max-age=3600"
    return DEFAULT_SCRAPER_CONFIG

@router.post("/config/scraper/report-failure")
async def report_scraper_failure(
    report: Dict[str, Any],
    user: User = Depends(get_current_user)
):
    """
    Receives failure telemetry from authenticated clients when an InnerTube client or decryption key fails.
    Enables fast proactive monitoring of upstream provider blocks.
    """
    client_name = str(report.get("client_name", "UNKNOWN"))[:50]
    reason = str(report.get("reason", "unspecified"))[:200]
    logger.warning("[ScraperTelemetry] User %s reported failure for client '%s': %s", user.id, client_name, reason)
    return {"status": "recorded", "client": client_name}

@router.get("/test-location")
async def get_test_location(
    request: Request,
    user: User = Depends(get_current_user)
):
    """
    Authenticated debug endpoint: fetches user's IP geolocation data using ip-api.com.
    Strictly validates client IP via ipaddress to prevent SSRF and parameter injection into outbound requests.
    """
    target_ip = ""
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        raw_ip = forwarded_for.split(",")[0].strip()
        try:
            parsed = ipaddress.ip_address(raw_ip)
            # Only allow global public IP addresses; reject private, loopback, link-local, multicast, etc.
            if parsed.is_global and not (parsed.is_private or parsed.is_loopback or parsed.is_reserved or parsed.is_link_local):
                target_ip = str(parsed)
        except ValueError:
            target_ip = ""

    # Fetch geolocation data safely
    try:
        url = f"http://ip-api.com/json/{target_ip}" if target_ip else "http://ip-api.com/json/"
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(url)
            data = response.json()
        
        return {
            "your_ip": data.get("query"),
            "status": data.get("status"),
            "country": data.get("country"),
            "region": data.get("regionName"),
            "city": data.get("city"),
            "internet_provider": data.get("isp"),
            "note": "Debug endpoint restricted to authenticated users"
        }
    except Exception as e:
        logger.error("Test location fetch error: %s", e)
        return {"error": "Failed to determine location"}
