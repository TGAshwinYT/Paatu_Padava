from fastapi import APIRouter, HTTPException, Query, Depends
from typing import List, Dict, Any
from services import saavn
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete
from connection import get_db, get_redis
from upstash_redis.asyncio import Redis as UpstashRedis
import models
from auth_utils import get_current_user, get_current_user_optional
import json
from utils.location import get_search_languages
from urllib.parse import quote


router = APIRouter(prefix="/api/music", tags=["music"])

@router.get("/home")
async def get_home_feed(
    user: models.User = Depends(get_current_user_optional), 
    db: AsyncSession = Depends(get_db),
    redis_client: UpstashRedis = Depends(get_redis)
):
    """
    Fetches trending music and mixes in personalized recommendations.
    Caches the global trending feed to Redis for 1 hour.
    """
    try:
        # 1. Check Cache
        cached_data = await redis_client.get("trending_songs")
        if cached_data:
            return json.loads(cached_data)

        favorites = []
        if user:
            # 1. Fetch preferences from DB
            result = await db.execute(select(models.User).where(models.User.id == user.id))
            db_user = result.scalar_one()
            
            if db_user.favorite_artists:
                try:
                    favorites = json.loads(db_user.favorite_artists)
                except:
                    pass

        # 2. Fetch standard trending feed as base
        feed_data = await saavn.get_trending()
        
        # 3. If favorites exist, build personalized section
        if favorites:
            # Build a dedicated personalized feed
            personalized = await saavn.get_personalized_feed(favorites)
            if personalized:
                # Add to feed_data
                feed_data["recommendedForYou"] = personalized
        
        # 4. Cache the results for 1 hour
        await redis_client.setex("trending_songs", 3600, json.dumps(feed_data))
        
        return feed_data
    except Exception as e:
        print(f"Router Error (home): {str(e)}")
        # Fallback to absolute minimum if something crashes
        return {"recentlyPlayed": [], "topArtists": [], "recommendedForYou": []}

@router.get("/search")
async def search_tracks(query: str = Query(..., min_length=1), region: str = Query(None)):
    try:
        # Step 1: Get weighted language string based on region
        lang_str = get_search_languages(region)
        
        # Step 2: Strict URI encoding for the query
        encoded_query = quote(query)
        
        # Step 3: Pass to JioSaavn service
        results = await saavn.search_saavn(encoded_query, language=lang_str)
        return results
    except Exception as e:
        print(f"Router Error (search): {str(e)}")
        raise HTTPException(status_code=500, detail="Error searching for music")

@router.get("/search/suggestions")
async def search_suggestions(query: str = Query(..., min_length=1)):
    """
    Global search suggestions for dropdown.
    """
    try:
        results = await saavn.search_all(query)
        return results
    except Exception as e:
        print(f"Suggestions Error: {str(e)}")
        return {"songs": [], "artists": [], "albums": []}

@router.get("/search/artists")
async def search_artists(query: str = Query(..., min_length=1)):
    """
    Search specifically for artists for onboarding/preferences.
    """
    try:
        results = await saavn.search_artists(query)
        return results
    except Exception as e:
        print(f"Artist Search Error: {str(e)}")
        return []

@router.post("/like")
async def like_song(song: Dict[str, Any], user: models.User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    try:
        query = select(models.LikedSong).where(
            models.LikedSong.user_id == user.id,
            models.LikedSong.song_id == song["id"]
        )
        result = await db.execute(query)
        if result.scalar_one_or_none():
            return {"message": "Song already liked"}

        new_like = models.LikedSong(
            user_id=user.id,
            song_id=song["id"],
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
            models.LikedSong.song_id == song_id
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
            "id": l.song_id,
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
async def get_recommendations(song_id: str, artist: str = Query(None)):
    """
    Get recommended songs based on a song ID.
    """
    try:
        results = await saavn.get_recommendations(song_id, artist)
        return results
    except Exception as e:
        print(f"Recommendations Error (Router): {str(e)}")
        # Task 2: Return 200 OK with empty list instead of 500
        return []

@router.get("/related/{song_id}")
async def get_related_songs(song_id: str, artist: str = Query(None)):
    """
    Alias for recommendations, used for infinite autoplay.
    """
    try:
        results = await saavn.get_recommendations(song_id, artist)
        return results
    except Exception as e:
        print(f"Related Songs Error (Router): {str(e)}")
        return []

@router.get("/lyrics/{song_id}")
async def get_song_lyrics(song_id: str):
    try:
        lyrics_data = await saavn.get_lyrics(song_id)
        return lyrics_data
    except Exception as e:
        print(f"Lyrics Error: {str(e)}")
        raise HTTPException(status_code=500, detail="Error fetching lyrics")

@router.get("/lyrics/synced")
async def get_synced_lyrics(title: str = Query(...), artist: str = Query(...)):
    """
    Fetch synced lyrics (LRC) using the syncedlyrics service.
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
    Get artist profile and top songs.
    """
    try:
        results = await saavn.get_artist_details(artist_id)
        return results
    except Exception as e:
        print(f"Artist Error (Router): {str(e)}")
        raise HTTPException(status_code=500, detail="Error fetching artist details")
