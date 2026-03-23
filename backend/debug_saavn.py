import asyncio
import json
import httpx
import sys
import os

# Add the current directory to path to import saavn
sys.path.append(os.getcwd())
from services import saavn

async def probe(endpoint, params=None):
    print(f"\n--- Probing /{endpoint} with {params} ---")
    try:
        data = await saavn.fetch_from_saavn(endpoint, params)
        if data and data.get("success") is not False:
            print(f"SUCCESS: {endpoint}")
            # print(json.dumps(data, indent=2)[:500] + "...")
            return data
        else:
            print(f"FAILED: {endpoint}")
    except Exception as e:
        print(f"ERROR: {endpoint} -> {e}")
    return None

async def main():
    endpoints = [
        ("modules", {"language": "hindi"}),
        ("modules", {"language": "english"}),
        ("charts", {}),
        ("featured", {}),
        ("new", {}),
        ("top", {}),
        ("get/home", {}),
        ("get/trending", {})
    ]
    
    for ep, p in endpoints:
        await probe(ep, p)

if __name__ == "__main__":
    asyncio.run(main())
