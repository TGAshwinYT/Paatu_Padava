from fastapi import APIRouter, HTTPException, Query, Depends, Request
from fastapi.responses import RedirectResponse
import asyncio
from typing import List, Dict, Any
from services import youtube
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete
from connection import get_db, get_redis
from upstash_redis.asyncio import Redis as UpstashRedis
import models
from auth_utils import get_current_user, get_current_user_optional
import json
from utils.location import get_search_languages
from urllib.parse import quote
from graph import recommendation_graph
from .history import get_user_top_artists


router = APIRouter(prefix="/api/music", tags=["music"])

@router.get("/stream/{yt_video_id}")
async def stream_song(yt_video_id: str, quality: str = "normal"):
    """
    Extracts the direct playable audio stream URL and redirects the client.
    """
    # Use the new pytubefix resolver
    url = await asyncio.to_thread(youtube.get_audio_url, yt_video_id)
    if not url:
        raise HTTPException(
            status_code=404, 
            detail="Audio stream currently unavailable or blocked by bot detection. Please try again later."
        )
    
    return RedirectResponse(url=url)
@router.get("/home")
async def get_home_feed(
    request: Request,
    region: str = Query(None),
    user: models.User = Depends(get_current_user_optional), 
    db: AsyncSession = Depends(get_db),
    redis_client: UpstashRedis = Depends(get_redis)
):
    """
    Fetches the structured YouTube Music home feed.
    """
    # 1. Detect region/language from query or headers
    region_to_use = region
    if not region_to_use:
        accept_lang = request.headers.get("accept-language", "").lower()
        if "ta" in accept_lang: region_to_use = "Tamil Nadu"
        elif "ml" in accept_lang: region_to_use = "Kerala"
        elif "hi" in accept_lang: region_to_use = "India"
        else: region_to_use = "Tamil Nadu" # Default for this app

    try:
        cache_key = f"home_feed_yt_v4_{region_to_use}_{user.id if user else 'guest'}"
        
        # Safe Cache Retrieval
        try:
            cached_data = await redis_client.get(cache_key)
            if cached_data:
                return json.loads(cached_data)
        except Exception as cache_err:
            print(f"Redis Cache Warning (home get): {str(cache_err)}")

        # 2. Fetch Home Feed (Smart Logic: Personalized if auth exists, else Regional)
        home_feed = await youtube.get_home_youtube(limit=20, region=region_to_use)
        
        # Safe Cache Storage (30 mins)
        try:
            await redis_client.setex(cache_key, 1800, json.dumps(home_feed))
        except Exception as cache_err:
            print(f"Redis Cache Warning (home set): {str(cache_err)}")
            
        return home_feed
    except Exception as e:
        print(f"Home Feed Error: {str(e)}")
        raise HTTPException(status_code=500, detail="Error fetching home feed")

@router.get("/search")
async def search_tracks(
    query: str = Query(..., min_length=1), 
    region: str = Query(None)
):
    try:
        # Parallel search for Songs, Albums, and Artists using YouTube Music
        song_task = youtube.search_youtube(query, limit=10)
        album_task = youtube.search_albums_youtube(query, limit=6)
        artist_task = youtube.search_artists_youtube(query, limit=6)
        
        songs, albums, artists = await asyncio.gather(song_task, album_task, artist_task)
        
        # Determine top_result (closest match)
        top_result = None
        if artists and query.lower() in artists[0].get("name", "").lower():
            top_result = artists[0]
            top_result["type"] = "artist"
        elif songs:
            top_result = songs[0]
            top_result["type"] = "song"
        elif artists:
            top_result = artists[0]
            top_result["type"] = "artist"
        elif albums:
            top_result = albums[0]
            top_result["type"] = "album"
            
        return {
            "global_matches": {
                "top_result": top_result, 
                "songs": songs[:4] if songs else [], 
                "artists": artists, 
                "albums": albums 
            }
        }
    except Exception as e:
        print(f"Router Error (search): {str(e)}")
        raise HTTPException(status_code=500, detail="Error searching for music")

@router.get("/search/suggestions")
async def search_suggestions(query: str = Query(..., min_length=1)):
    """
    Global search suggestions for dropdown.
    """
    try:
        results = await youtube.search_youtube(query, limit=10)
        return {
            "songs": results,
            "artists": [],
            "albums": []
        }
    except Exception as e:
        print(f"Suggestions Error: {str(e)}")
        return {"songs": [], "artists": [], "albums": []}

@router.get("/search/artists")
async def search_artists(query: str = Query(..., min_length=1)):
    """
    Search specifically for artists for onboarding/preferences.
    """
    try:
        results = await youtube.search_artists_youtube(query, limit=10)
        return results
    except Exception as e:
        print(f"Artist Search Error: {str(e)}")
        return []

@router.post("/like")
async def like_song(song: Dict[str, Any], user: models.User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    try:
        query = select(models.LikedSong).where(
            models.LikedSong.user_id == user.id,
            models.LikedSong.yt_video_id == song["id"]
        )
        result = await db.execute(query)
        if result.scalar_one_or_none():
            return {"message": "Song already liked"}

        new_like = models.LikedSong(
            user_id=user.id,
            yt_video_id=song["id"],
            title=song["title"],
            artist=song["artist"],
            cover_url=song.get("coverUrl") or song.get("cover_url"),
            audio_url=song.get("audioUrl") or song.get("audio_url")
        )
        db.add(new_like)
        await db.commit()
        return {"message": "Song liked successfully"}
    except Exception as e:
        await db.rollback()
        print(f"Like Error: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to like song")

@router.delete("/unlike/{song_id}")
async def unlike_song(song_id: str, user: models.User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    try:
        query = delete(models.LikedSong).where(
            models.LikedSong.user_id == user.id,
            models.LikedSong.yt_video_id == song_id
        )
        await db.execute(query)
        await db.commit()
        return {"message": "Song unliked successfully"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Failed to unlike song")

@router.get("/liked")
async def get_liked_songs(
    limit: int = 20, 
    offset: int = 0, 
    user: models.User = Depends(get_current_user), 
    db: AsyncSession = Depends(get_db)
):
    try:
        query = select(models.LikedSong).where(models.LikedSong.user_id == user.id).order_by(models.LikedSong.created_at.desc()).limit(limit).offset(offset)
        result = await db.execute(query)
        likes = result.scalars().all()
        return [{
            "id": l.yt_video_id,
            "title": l.title,
            "artist": l.artist,
            "coverUrl": l.cover_url,
            "audioUrl": l.audio_url,
            "cover_url": l.cover_url, # Redundancy for compatibility
            "audio_url": l.audio_url
        } for l in likes]
    except Exception as e:
        print(f"Fetch Liked Error: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to fetch liked songs")

@router.get("/recommendations/{song_id}")
async def get_recommendations(
    song_id: str, 
    artist: str = Query(None), 
    lang: str = Query(None),
    user: models.User = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db)
):
    """
    Get recommended songs based on a YouTube video ID.
    """
    try:
        # First try the graph (which now uses YT IDs)
        results = recommendation_graph.get_recommendations(song_id, limit=6, current_language=lang)
        
        # Fallback to YouTube's related songs
        if not results:
            results = await youtube.get_related_songs(song_id, limit=12)
            
        return results
    except Exception as e:
        print(f"Recommendations Error (Router): {str(e)}")
        return []

@router.get("/related/{song_id}")
async def get_related_songs(song_id: str, artist: str = Query(None)):
    """
    Alias for recommendations.
    """
    return await get_recommendations(song_id)

@router.get("/lyrics/{song_id}")
async def get_song_lyrics(song_id: str):
    """
    Generic lyrics endpoint. YTMusic doesn't have direct lyrics in this wrapper easily,
    so we rely on synced lyrics services.
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
    except Exception as e:
        print(f"Synced Lyrics Error: {str(e)}")
        # return {"synced": False, "lrc": None}
        raise HTTPException(status_code=500, detail="Error fetching synced lyrics")

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
    Hyper-compatible: Accepts [title, artist] OR [track_name, artist_name].
    """
    final_title = title or track_name
    final_artist = artist or artist_name
    
    if not final_title or not final_artist:
        return {"lyrics": "Title and artist are required.", "isSynced": False}
        
    try:
        from services import lyrics
        return await lyrics.get_synced_lyrics_lrclib(final_title, final_artist, duration)
    except Exception as e:
        print(f"LRCLIB Endpoint Error: {str(e)}")
        return {"lyrics": "Lyrics not available for this track.", "isSynced": False}

@router.get("/artist/{artist_id}")
async def get_artist_details(artist_id: str):
    """
    Get artist profile and top songs from YouTube.
    """
    try:
        results = await youtube.get_artist_details_youtube(artist_id)
        return results
    except Exception as e:
        print(f"Artist Error (Router): {str(e)}")
        raise HTTPException(status_code=500, detail="Error fetching artist details")
@router.get("/albums/{album_id}")
async def get_album_details(album_id: str):
    """
    Fetch full details and tracklist for a specific album from YouTube.
    """
    try:
        results = await youtube.get_album_details_youtube(album_id)
        if not results:
            raise HTTPException(status_code=404, detail="Album not found or unavailable")
        return results
    except Exception as e:
        print(f"Album Error (Router): {str(e)}")
        raise HTTPException(status_code=500, detail="Error fetching album details")


@router.get("/debug/{yt_video_id}")
async def debug_stream(yt_video_id: str):
    """
    Diagnostic endpoint — shows all available formats per client.
    Use this to troubleshoot streaming issues.
    """
    result = await asyncio.to_thread(youtube.debug_formats, yt_video_id)
    return result
