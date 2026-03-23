import asyncio
import json
import sys
import os

# Add the current directory to path to import saavn
sys.path.append(os.getcwd())
from services import saavn

async def main():
    try:
        print("Checking get_trending()...")
        data = await saavn.get_trending()
        print(f"Recently Played: {len(data['recentlyPlayed'])} tracks")
        print(f"Top Artists: {len(data['topArtists'])} tracks")
        
        if len(data['recentlyPlayed']) > 0:
            print("\nFirst track in Recently Played:")
            print(json.dumps(data['recentlyPlayed'][0], indent=2))
            
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    asyncio.run(main())
