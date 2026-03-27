import asyncio
import json
import sys
import os

# Add the current directory to sys.path to import local modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from services import saavn

async def verify_home_feed(region=None):
    print(f"\nTesting get_trending(region={region})...")
    try:
        from utils.location import get_search_languages
        languages = get_search_languages(region)
        data = await saavn.get_trending(languages)
        
        # Check recommendedForYou
        for song in data.get("recommendedForYou", []):
            if not song.get("audioUrl"):
                print(f"❌ Verification FAILED: Song '{song.get('title')}' is missing audioUrl!")
                return
            if not song.get("coverUrl"):
                print(f"❌ Verification FAILED: Song '{song.get('title')}' is missing coverUrl!")
                return
        
        # Check structure
        expected_keys = {"recommendedForYou", "topAlbums", "topArtists"}
        actual_keys = set(data.keys())
        
        if not expected_keys.issubset(actual_keys):
            print(f"FAILED: Missing keys. Expected {expected_keys}, got {actual_keys}")
            return
            
        print("SUCCESS: Keys are present.")
        
        # Check normalization
        if data["recommendedForYou"]:
            item = data["recommendedForYou"][0]
            print(f"Sample Song: {item}")
            if not all(k in item for k in ["id", "title", "artist", "coverUrl"]):
                print("FAILED: Song mapping incorrect")
        
        if data["topAlbums"]:
            item = data["topAlbums"][0]
            print(f"Sample Album: {item}")
            if not all(k in item for k in ["id", "title", "subtitle", "image"]):
                print("FAILED: Album mapping incorrect")
                
        if data["topArtists"]:
            item = data["topArtists"][0]
            print(f"Sample Artist: {item}")
            if not all(k in item for k in ["id", "name", "image"]):
                print("FAILED: Artist mapping incorrect")

        print("\nVerification Complete!")
        
    except Exception as e:
        print(f"Verification ERROR: {str(e)}")

if __name__ == "__main__":
    async def run_tests():
        # Test 1: Global/Default
        await verify_home_feed(None)
        
        # Test 2: Localized (Tamil Nadu)
        await verify_home_feed("Tamil Nadu")
        
        # Test 3: Localized (Punjab)
        await verify_home_feed("Punjab")
        
    asyncio.run(run_tests())
