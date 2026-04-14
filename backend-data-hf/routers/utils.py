from fastapi import APIRouter, Request
import requests

router = APIRouter(prefix="/api", tags=["utils"])

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
        # Get the first IP in the comma-separated list
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
