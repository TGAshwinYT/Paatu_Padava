import syncedlyrics
import asyncio
from typing import Optional

async def get_synced_lyrics(song_name: str, artist: str) -> Optional[str]:
    """
    Searches for synced lyrics (LRC) for a given song and artist.
    Returns the LRC string if found, else None.
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
