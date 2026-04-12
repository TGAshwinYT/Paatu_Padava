import os
import json
import asyncio
from ytmusicapi import YTMusic
from dotenv import load_dotenv

# Load env vars
load_dotenv(dotenv_path='../.env')

HEADERS_RAW = os.getenv('YT_HEADERS', '{}')
COOKIES_RAW = os.getenv('YT_COOKIES', '')

import os
import json
import asyncio
import tempfile
from ytmusicapi import YTMusic
from dotenv import load_dotenv

# Load env vars
load_dotenv(dotenv_path='../.env')

HEADERS_RAW = os.getenv('YT_HEADERS', '{}')
COOKIES_RAW = os.getenv('YT_COOKIES', '')

def get_yt_instance():
    try:
        headers_json = json.loads(HEADERS_RAW)
        
        # Apply the Trojan Header Bypass
        safe_keys = {
            'User-Agent', 'user-agent', 'Cookie', 'cookie', 'Accept', 'accept',
            'Accept-Language', 'accept-language', 'Content-Type', 'content-type',
            'X-Goog-AuthUser', 'x-goog-auth-user', 'x-goog-authuser',
            'x-origin', 'Origin', 'Referer', 'x-youtube-client-name', 'x-youtube-client-version'
        }
        
        sanitized_headers = {k: v for k, v in headers_json.items() if k in safe_keys}
        sanitized_headers["Authorization"] = "SAPISIDHASH dummy"
        
        # FORCE DESKOP UA for parsing verification
        sanitized_headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tf:
            json.dump(sanitized_headers, tf)
            headers_path = tf.name
            
        print(f"Initializing YTMusic with diagnostic headers from {headers_path}")
        return YTMusic(headers_path)
    except Exception as e:
        print(f"Failed to init YTMusic: {e}")
        return None

async def probe():
    yt = get_yt_instance()
    if not yt:
        return

    print("\n--- Probing Home Feed ---")
    try:
        home = yt.get_home(limit=5)
        for shelf in home:
            title = shelf.get('title', 'Unknown Shelf')
            print(f"\nShelf: {title}")
            for item in shelf.get('contents', []):
                name = item.get('title', item.get('name', 'Unknown'))
                
                print(f"  - Item: {name}")
                print(f"    videoId: value='{item.get('videoId')}' (type: {type(item.get('videoId'))})")
                print(f"    video_id: value='{item.get('video_id')}'")
                print(f"    id: value='{item.get('id')}'")
                if 'browseId' in item: print(f"    browseId: value='{item.get('browseId')}'")
                
    except Exception as e:
        print(f"Home probe failed: {e}")

    print("\n--- Probing Search (Kadhal En Kaviye) ---")
    try:
        search_results = yt.search("Kadhal En Kaviye", filter="songs", limit=5)
        for res in search_results:
            name = res.get('title')
            print(f"  - Result: {name}")
            print(f"    videoId: value='{res.get('videoId')}'")
            print(f"    id: value='{res.get('id')}'")
            # print(f"    RAW: {str(res)[:100]}...")
    except Exception as e:
        print(f"Search probe failed: {e}")

if __name__ == "__main__":
    asyncio.run(probe())

if __name__ == "__main__":
    asyncio.run(probe())
