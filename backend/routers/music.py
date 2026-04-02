from fastapi import APIRouter, HTTPException, Query, Depends
import asyncio
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
from graph import recommendation_graph
from .history import get_user_top_artists


router = APIRouter(prefix="/api/music", tags=["music"])

@router.get("/home")
async def get_home_feed(
    region: str = Query(None),
    user: models.User = Depends(get_current_user_optional), 
    db: AsyncSession = Depends(get_db),
    redis_client: UpstashRedis = Depends(get_redis)
):
    """
    Fetches trending music and mixes in personalized recommendations.
    Localized by region if provided.
    """
    try:
        # Cache Key should include region for localization
        cache_key = f"trending_songs_{region or 'global'}"
        cached_data = await redis_client.get(cache_key)
        if cached_data:
            return json.loads(cached_data)

        # 1. Determine Language Priority based on Region
        languages = get_search_languages(region)
        
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

        # 2. Fetch standard trending feed as base (Songs, Albums, Artists)
        # Now passing regional languages to localize results
        feed_data = await saavn.get_trending(languages)
        
        # 3. If favorites exist, build and merge personalized recommendations
        if favorites:
            personalized = await saavn.get_personalized_feed(favorites)
            if personalized:
                # Map personalized songs to the required format
                mapped_personalized = []
                for p in personalized:
                    mapped_personalized.append({
                        "id": p.get("id"),
                        "title": p.get("title") or p.get("name"),
                        "artist": p.get("artist") or p.get("primaryArtists"),
                        "coverUrl": p.get("coverUrl") or p.get("cover_url") or saavn.extract_high_res_image(p.get("image")),
                        "audioUrl": p.get("audioUrl") or p.get("audio_url") or saavn.extract_audio_url(p)
                    })
                
                # Merge: Prepended personalized items to standard trending songs
                # Standard trending songs are already in feed_data["recommendedForYou"]
                standard_trending = feed_data.get("recommendedForYou", [])
                feed_data["recommendedForYou"] = (mapped_personalized + standard_trending)[:30]
        
        # 4. Cache the results for 1 hour
        await redis_client.setex(cache_key, 3600, json.dumps(feed_data))
        
        return feed_data
    except Exception as e:
        print(f"Router Error (home): {str(e)}")
        # Fallback to absolute minimum if something crashes but maintain structure
        return {"recommendedForYou": [], "topAlbums": [], "topArtists": []}

@router.get("/search")
async def search_tracks(
    query: str = Query(..., min_length=1), 
    region: str = Query(None)
):
    try:
        # Step 1: Get weighted language string based on region
        lang_str = get_search_languages(region)
        
        # Step 2: Strict URI encoding for the query
        encoded_query = quote(query)
        
        # Step 3: Parallel search for Songs, Albums, and Artists
        # This provides a Spotify-like comprehensive result set
        song_task = saavn.search_saavn(encoded_query, language=lang_str)
        album_task = saavn.search_albums(encoded_query, language=lang_str)
        artist_task = saavn.search_artists(encoded_query, language=lang_str)
        
        songs, albums, artists = await asyncio.gather(song_task, album_task, artist_task)
        
        # 1. Smart Artist Injector
        top_song_artist = None
        if songs:
            top_song = songs[0]
            artist_name = top_song.get("artist", "Unknown Artist")
            top_song_artist = {
                "id": top_song.get("artist_id", "unknown"),
                "name": artist_name,
                "title": artist_name,
                "image": top_song.get("cover_url", ""), # Use song image as artist fallback
                "type": "artist"
            }
        
        # 2. Filter out junk artists (placeholder/default icon entries)
        valid_artists = [
            a for a in artists 
            if a.get("image") and "default" not in str(a.get("image")).lower() and "placeholder" not in str(a.get("image")).lower()
        ]
        
        # 3. Deduplicate and prepend Top Song Artist
        final_artists = []
        if top_song_artist:
            final_artists.append(top_song_artist)
            
        for artist in valid_artists:
            # Check for duplicate by ID or Name
            is_duplicate = (top_song_artist and (artist["id"] == top_song_artist["id"] or artist["name"] == top_song_artist["name"]))
            if not is_duplicate:
                final_artists.append(artist)
        
        # 4. Final results limiting (Top 6 artists)
        final_artists = final_artists[:6]
        
        # 5. Smart Album Injector
        top_song_album = None
        if songs:
            top_song = songs[0]
            album_name = top_song.get("album")
            album_id = top_song.get("album_id")
            
            # 🚨 CRITICAL QUALITY CHECK 🚨
            # Only create the injected album if we have BOTH a valid name and ID
            if album_name and album_name.lower() != "unknown album" and album_name.lower() != "unknown" and album_id != "unknown":
                top_song_album = {
                    "id": album_id,
                    "title": album_name,
                    "artist": top_song.get("artist", "Various Artists"),
                    "image": top_song.get("cover_url", ""), # Fallback to song image
                    "type": "album"
                }
        
        # 6. Filter out junk albums
        valid_albums = [
            a for a in albums 
            if a.get("image") and "default" not in str(a.get("image")).lower() and "placeholder" not in str(a.get("image")).lower()
        ]
        
        # 7. Deduplicate and prepend Top Song Album
        final_albums = []
        if top_song_album:
            final_albums.append(top_song_album)
            
        for album in valid_albums:
            is_duplicate = (top_song_album and (album["id"] == top_song_album["id"] or album["title"] == top_song_album["title"]))
            if not is_duplicate:
                final_albums.append(album)
                
        # 8. Limit results (Top 6 albums)
        final_albums = final_albums[:6]

        # Determine top_result (closest match)
        top_result = None
        if final_artists and query.lower() in final_artists[0].get("name", "").lower():
            top_result = final_artists[0]
            top_result["type"] = "artist"
        elif songs:
            top_result = songs[0]
            top_result["type"] = "song"
        elif final_artists:
            top_result = final_artists[0]
            top_result["type"] = "artist"
        elif albums:
            top_result = albums[0]
            top_result["type"] = "album"
            
        return {
            "global_matches": {
                # The absolute best match (usually the first song or artist)
                "top_result": top_result, 
                # List of top 4 songs
                "songs": songs[:4] if songs else [], 
                # List of artists
                "artists": final_artists, 
                # List of albums
                "albums": final_albums 
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
async def get_recommendations(
    song_id: str, 
    artist: str = Query(None), 
    lang: str = Query(None),
    user: models.User = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db)
):
    """
    Get recommended songs based on a song ID using the path-based BFS graph.
    Includes personal favorites blended into the fallback.
    """
    try:
        # Task 2: Use the global recommendation graph with language context
        results = recommendation_graph.get_recommendations(song_id, limit=6, current_language=lang)
        
        # Fetch user's top historical artists for personalization (if logged in)
        historical_artists = []
        if user:
            historical_artists = await get_user_top_artists(db, user.id, limit=2)
            print(f"[PERSONALIZATION] Blending top artists {historical_artists} into recommendations for {user.id}")

        # Fallback to standard suggestions if the graph is cold for this track
        if not results:
            results = await saavn.get_recommendations(song_id, target_language=lang, artist=artist, historical_artists=historical_artists)
            
        return results
    except Exception as e:
        print(f"Recommendations Error (Router): {str(e)}")
        return []

@router.get("/related/{song_id}")
async def get_related_songs(song_id: str, artist: str = Query(None)):
    """
    Alias for recommendations, used for infinite autoplay.
    """
    try:
        results = await saavn.get_recommendations(song_id, target_language=None, artist=artist)
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
@router.get("/albums/{album_id}")
async def get_album_details(album_id: str):
    """
    Fetch full details and tracklist for a specific album.
    """
    try:
        results = await saavn.get_album_details(album_id)
        if not results or not results.get("id"):
            raise HTTPException(status_code=404, detail="Album not found or unavailable")
        return results
    except HTTPException:
        raise
    except Exception as e:
        print(f"Album Error (Router): {str(e)}")
        raise HTTPException(status_code=500, detail="Error fetching album details")
