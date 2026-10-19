from fastapi import APIRouter, HTTPException, Query
import httpx
import asyncio

router = APIRouter(tags=["lyrics"])

@router.get("/lyrics/{song_id}")
async def get_song_lyrics(song_id: str):
    """
    Generic lyrics endpoint.
    """
    return {"lyrics": "Synced lyrics are available via /lyrics/synced", "isSynced": False}

@router.get("/lyrics/synced")
async def get_synced_lyrics(title: str = Query(...), artist: str = Query(...)):
    """
    Fetch synced lyrics (LRC) using the synced lyrics service.
    """
    try:
        from services import lyrics
        lrc_data = await lyrics.get_synced_lyrics(title, artist)
        if not lrc_data:
            return {"synced": False, "lrc": None}
        return {"synced": True, "lrc": lrc_data}
    except (httpx.ConnectError, httpx.TimeoutException, asyncio.TimeoutError) as ue:
        raise HTTPException(
            status_code=502,
            detail={"code": "UPSTREAM_UNAVAILABLE", "message": "Lyrics service is temporarily unreachable.", "retry_after": 5}
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={"code": "LYRICS_FETCH_FAILED", "message": "Error fetching synced lyrics", "retry_after": None}
        )

@router.get("/lyrics")
async def get_lrclib_lyrics_endpoint(
    title: str = Query(None), 
    artist: str = Query(None),
    track_name: str = Query(None),
    artist_name: str = Query(None),
    duration: int = Query(0)
):
    """
    Fetch lyrics from LRCLIB using the /get endpoint.
    Accepts [title, artist] OR [track_name, artist_name].
    """
    final_title = title or track_name
    final_artist = artist or artist_name
    
    if not final_title or not final_artist:
        return {"lyrics": "Title and artist are required.", "isSynced": False}
        
    try:
        from services import lyrics
        return await lyrics.get_synced_lyrics_lrclib(final_title, final_artist, duration)
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={"code": "LYRICS_FETCH_FAILED", "message": "Error fetching LRCLIB lyrics", "retry_after": None}
        )
