import syncedlyrics
import asyncio
import httpx
from typing import Optional, Dict

async def get_synced_lyrics(song_name: str, artist: str) -> Optional[str]:
    """
    Searches for synced lyrics (LRC) for a given song and artist using the syncedlyrics library.
    """
    query = f"{song_name} - {artist}"
    try:
        # syncedlyrics.search is a blocking call, so we run it in a thread
        loop = asyncio.get_event_loop()
        lrc_content = await loop.run_in_executor(None, syncedlyrics.search, query)
        return lrc_content
    except Exception as e:
        print(f"Error fetching synced lyrics for {query}: {str(e)}")
        return None

async def get_lrclib_lyrics(title: str, artist: str) -> Dict:
    """
    Queries LRCLIB /api/search endpoint for lyrics. Returns synced if available, else plain.
    """
    url = "https://lrclib.net/api/search"
    params = {"q": f"{artist} {title}"}
    
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(url, params=params, timeout=10.0)
            if response.status_code == 200:
                data = response.json()
                if data and len(data) > 0:
                    result = data[0]
                    synced = result.get("syncedLyrics")
                    plain = result.get("plainLyrics")
                    
                    if synced:
                        return {"lyrics": synced, "isSynced": True}
                    elif plain:
                        return {"lyrics": plain, "isSynced": False}
        except Exception as e:
            print(f"LRCLIB Search Error: {e}")
            
    return {"lyrics": "Lyrics not available for this track.", "isSynced": False}

async def get_synced_lyrics_lrclib(track_name: str, artist_name: str, duration: int) -> Dict:
    """
    Queries LRCLIB /api/get endpoint for specific track details including synced lyrics.
    """
    url = "https://lrclib.net/api/get"
    params = {
        "track_name": track_name,
        "artist_name": artist_name,
        "duration": duration
    }
    
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(url, params=params, timeout=10.0)
            if response.status_code == 200:
                return response.json()
            elif response.status_code == 404:
                # Fallback to search if /get fails
                return await get_lrclib_lyrics(track_name, artist_name)
        except Exception as e:
            print(f"LRCLIB Get Error: {e}")
            
    return {}
