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
                        return {"syncedLyrics": synced, "plainLyrics": plain}
                    elif plain:
                        return {"syncedLyrics": None, "plainLyrics": plain}
        except Exception as e:
            print(f"LRCLIB Search Error: {e}")
            
    return {"syncedLyrics": None, "plainLyrics": "Lyrics not available for this track."}

async def get_synced_lyrics_lrclib(title: Optional[str] = None, artist: Optional[str] = None, duration: int = 0) -> Dict:
    """
    Queries LRCLIB /api/get endpoint for specific track details including synced lyrics.
    """
    if not title or not artist:
        return {"syncedLyrics": None, "plainLyrics": "Title and artist are required query parameters."}

    url = "https://lrclib.net/api/get"
    params = {
        "track_name": title,
        "artist_name": artist,
        "duration": duration
    }
    
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(url, params=params, timeout=10.0)
            if response.status_code == 200:
                return response.json()
            
            # Fallback for any other status (404, 500, etc)
            return await get_lrclib_lyrics(title, artist)
        except Exception as e:
            print(f"LRCLIB Get Error: {e}")
            return await get_lrclib_lyrics(title, artist)
    
    # Should not be reachable given the returns above, but for safety:
    return await get_lrclib_lyrics(title if title else "", artist if artist else "")
