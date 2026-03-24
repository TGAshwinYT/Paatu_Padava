import httpx
import asyncio

BASE_URL = "http://localhost:8000"

async def test_home_feed():
    async with httpx.AsyncClient() as client:
        # 1. Test Unauthenticated
        print("Testing Unauthenticated Home Feed...")
        try:
            response = await client.get(f"{BASE_URL}/api/music/home")
            print(f"Status: {response.status_code}")
            if response.status_code == 200:
                data = response.json()
                print(f"Keys in response: {list(data.keys())}")
                print(f"Charts count: {len(data.get('charts', []))}")
                print(f"Recommended count: {len(data.get('recommendedForYou', []))}") # Should be 0 for guest
            else:
                print(f"Error: {response.text}")
        except Exception as e:
            print(f"Request failed: {str(e)}")

        print("\n" + "="*30 + "\n")

        # 2. Test Authenticated (Simulated)
        # Note: You'd need a valid token to test this properly, 
        # but the check above confirms the endpoint is no longer strictly blocking.
        print("Note: Authenticated test requires a valid JWT token.")

if __name__ == "__main__":
    asyncio.run(test_home_feed())
