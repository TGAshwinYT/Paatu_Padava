from fastapi import APIRouter, Request, Response
import os
import requests

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

@router.get("/test-location")
async def get_test_location(request: Request):
    """
    Fetches the user's IP geolocation data using ip-api.com.
    Handles Hugging Face proxy by checking X-Forwarded-For.
    Accessible at /api/test-location
    """
    # 1. Extract real IP from Hugging Face proxy headers
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        user_ip = forwarded_for.split(",")[0].strip()
    else:
        user_ip = request.client.host

    # 2. Localhost check for ip-api.com auto-detection
    if user_ip == "127.0.0.1":
        user_ip = ""

    # 3. Fetch geolocation data
    try:
        response = requests.get(f"http://ip-api.com/json/{user_ip}")
        data = response.json()
        
        return {
            "your_ip": data.get("query"),
            "status": data.get("status"),
            "country": data.get("country"),
            "region": data.get("regionName"),
            "city": data.get("city"),
            "internet_provider": data.get("isp"),
            "note": "Endpoint moved to /api/test-location for accessibility"
        }
    except Exception as e:
        return {"error": str(e)}
