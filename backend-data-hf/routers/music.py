import asyncio
import logging
import re
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
import httpx
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from upstash_redis.asyncio import Redis as UpstashRedis

from auth_utils import get_current_user, get_current_user_optional
from connection import get_db, get_redis
from graph import recommendation_graph
from limiter_config import limiter
import models
from repositories.user_repo import UserRepository
from services import youtube
from services.download_service import (
    create_download_streaming_response,
    resolve_download_audio_url,
)
from services.home_feed import (
    get_consolidated_home_feed_data,
    get_home_feed_data,
)
from services.recommender import (
    canonical_title,
    extract_language_from_title,
    personal_recommender,
)
from services.search_scoring import (
    TANGLISH_TRANSLITERATION_MAP,
    _clean_str,
    detect_script_language,
    execute_search,
    execute_search_suggestions,
    score_album_relevance,
    score_artist_relevance,
    score_track_relevance,
    search_canonical_title,
)
from services.spotify_import import (
    get_spotify_artist_image,
    get_spotify_playlists,
    get_spotify_top_10_tracks,
)
from services.stream_resolver_backend import (
    clean_song_title,
    is_title_match,
    resolve_single_stream,
)
from services.stream_security import (
    ALLOWED_STREAM_DOMAINS,
    is_safe_audio_url,
)
from utils.location import get_user_search_languages

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/music", tags=["music"])
from .music_lyrics import router as lyrics_router
router.include_router(lyrics_router)


class ShuffleOrderRequest(BaseModel):
    queue_ids: List[str]
    current_song_id: Optional[str] = None


class PrefetchTrackItem(BaseModel):
    id: str
    title: Optional[str] = None
    artist: Optional[str] = None


class PrefetchStreamRequest(BaseModel):
    tracks: List[PrefetchTrackItem]


class PlayerStateRequest(BaseModel):
    current_track: Optional[Dict[str, Any]] = None
    queue: Optional[List[Dict[str, Any]]] = None
    is_shuffle: Optional[bool] = None
    repeat_mode: Optional[str] = None
    volume: Optional[float] = None


@router.get("/for-you")
async def get_for_you_mix(
    user: models.User = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db)
):
    """
    Returns a personalized queue based on the user's real listening behavior.
    Learned via item-item collaborative filtering with canonical deduplication
    and strict language prioritization.
    """
    try:
        user_langs = get_user_search_languages(user)
        if user:
            uid = str(user.id)
            personal_queue = personal_recommender.get_personal_recommendations(
                uid, preferred_languages=user_langs, limit=20
            )
            if personal_queue:
                return {"queue": personal_queue, "personalized": True}

        # Cold start fallback for guest or new user with zero history
        fallback_queue = await personal_recommender.get_cold_start_recommendations(
            db, user, preferred_languages=user_langs, limit=20
        )
        return {"queue": fallback_queue, "personalized": False}
    except Exception as e:
        logger.warning("For-You Mix Error: %s", e)
        return {"queue": [], "personalized": False}


@router.post("/shuffle-order")
async def shuffle_order_endpoint(
    body: ShuffleOrderRequest,
    user: models.User = Depends(get_current_user_optional)
):
    """
    Returns an intelligent shuffle order for a given list of song IDs
    using a greedy nearest-neighbor chain starting from the current song.
    """
    uid = str(user.id) if user else None
    ordered = personal_recommender.get_shuffle_order(body.queue_ids, body.current_song_id, uid)
    return {"ordered_ids": ordered}


@router.get("/stream/{song_id}")
async def get_stream_url(
    song_id: str,
    title: Optional[str] = Query(None),
    artist: Optional[str] = Query(None),
    redis_client: UpstashRedis = Depends(get_redis)
):
    """
    Resolves the highest quality direct stream URL for a track, backed by Upstash Redis.
    Allows zero-gap preloading on the frontend.
    """
    return await resolve_single_stream(song_id, title, artist, redis_client)


@router.get("/download")
@limiter.limit("10/minute")
async def download_track(
    request: Request,
    song_id: Optional[str] = Query(None),
    title: Optional[str] = Query(None),
    artist: Optional[str] = Query(None),
    url: Optional[str] = Query(None),
    user: Optional[models.User] = Depends(get_current_user_optional),
    redis_client: UpstashRedis = Depends(get_redis)
):
    """
    Streams the highest quality 320kbps MP3 audio file with Content-Disposition attachment header
    for pristine offline downloading.
    Strictly validates audio stream URLs against public CDNs to prevent SSRF.
    """
    audio_url = await resolve_download_audio_url(song_id, title, artist, url, redis_client)
    return await create_download_streaming_response(audio_url, title, artist)


@router.post("/prefetch-stream")
async def prefetch_streams_endpoint(
    body: PrefetchStreamRequest,
    redis_client: UpstashRedis = Depends(get_redis)
):
    """
    Pre-resolves and warms Redis cache for upcoming tracks in the player queue.
    """
    tasks = [
        resolve_single_stream(t.id, t.title, t.artist, redis_client)
        for t in body.tracks[:4]  # Limit batch to upcoming 4 tracks max to avoid overhead
    ]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    clean_results = [r for r in results if isinstance(r, dict)]
    return {"streams": clean_results}


@router.post("/player-state")
async def save_player_state(
    request: Request,
    body: PlayerStateRequest,
    user: Optional[models.User] = Depends(get_current_user_optional),
    redis_client: UpstashRedis = Depends(get_redis)
):
    """
    Saves active player state & queue in Redis for seamless session restore.
    Guest sessions are isolated using X-Session-ID header with a 2-hour TTL.
    """
    import json
    if user:
        key = f"player_state:user:{user.id}"
        ttl = 86400 * 7
    else:
        session_id = request.headers.get("x-session-id")
        if not session_id:
            return {"saved": False, "detail": "X-Session-ID header required for guest sessions"}
        clean_session = re.sub(r'[^a-zA-Z0-9_-]', '', session_id)[:64]
        if not clean_session:
            return {"saved": False}
        key = f"player_state:guest:{clean_session}"
        ttl = 7200  # 2 hours

    try:
        await redis_client.setex(key, ttl, json.dumps(body.dict()))
        return {"saved": True}
    except Exception as e:
        logger.warning("Redis save player state error: %s", e)
        return {"saved": False}


@router.get("/player-state")
async def get_player_state(
    request: Request,
    user: Optional[models.User] = Depends(get_current_user_optional),
    redis_client: UpstashRedis = Depends(get_redis)
):
    """
    Retrieves the last saved active player state from Redis.
    Guest sessions look up player_state:guest:{x-session-id}.
    """
    import json
    if user:
        key = f"player_state:user:{user.id}"
    else:
        session_id = request.headers.get("x-session-id")
        if not session_id:
            return {"current_track": None, "queue": []}
        clean_session = re.sub(r'[^a-zA-Z0-9_-]', '', session_id)[:64]
        if not clean_session:
            return {"current_track": None, "queue": []}
        key = f"player_state:guest:{clean_session}"

    try:
        cached = await redis_client.get(key)
        if cached:
            return json.loads(cached)
    except Exception as e:
        logger.warning("Redis get player state error: %s", e)
    return {"current_track": None, "queue": []}


@router.get("/spotify/token")
@router.get("/spotify-token")
@router.post("/spotify/token")
@router.post("/spotify-token")
@limiter.limit("20/minute")
async def get_spotify_token(
    request: Request,
    redis_client: UpstashRedis = Depends(get_redis)
):
    """
    Secure server-side proxy for Spotify Client Credentials token.
    Prevents leaking SPOTIFY_CLIENT_SECRET to client browsers.
    """
    import base64
    import json
    import os

    client_id = os.getenv("SPOTIFY_CLIENT_ID")
    client_secret = os.getenv("SPOTIFY_CLIENT_SECRET")
    if not client_id or not client_secret:
        raise HTTPException(
            status_code=503,
            detail="Spotify client credentials are not configured on the backend server."
        )

    cache_key = "spotify:client_credentials_token"
    if redis_client:
        try:
            cached_token = await redis_client.get(cache_key)
            if cached_token:
                return json.loads(cached_token)
        except Exception as err:
            logger.warning("[SPOTIFY] Redis get failed: %s", err)

    credentials = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(
                "https://accounts.spotify.com/api/token",
                data={"grant_type": "client_credentials"},
                headers={
                    "Authorization": f"Basic {credentials}",
                    "Content-Type": "application/x-www-form-urlencoded",
                },
            )
        if resp.status_code != 200:
            raise HTTPException(status_code=502, detail="Failed to obtain Spotify access token from upstream.")
        token_data = resp.json()
        access_token = token_data.get("access_token")
        expires_in = token_data.get("expires_in", 3600)

        result_payload = {
            "access_token": access_token,
            "token_type": "Bearer",
            "expires_in": expires_in,
        }

        if redis_client and access_token:
            try:
                await redis_client.setex(cache_key, max(60, expires_in - 60), json.dumps(result_payload))
            except Exception as err:
                logger.warning("[SPOTIFY] Redis set failed: %s", err)

        return result_payload
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Spotify token retrieval error: {str(e)}")


@router.get("/spotify/top-hits")
async def get_spotify_top_hits_endpoint(language: Optional[str] = Query("Tamil")):
    """
    Returns Spotify Top 10 Hits for a given language using /v1/search (non-editorial).
    """
    return await get_spotify_top_10_tracks(language=language or "Tamil")


@router.get("/spotify/playlists")
async def get_spotify_playlists_endpoint(language: Optional[str] = Query("Tamil")):
    """
    Returns Spotify Playlists for a given language using /v1/search (non-editorial, owner != spotify).
    """
    return await get_spotify_playlists(language=language or "Tamil")


@router.get("/spotify/artist-image")
async def get_spotify_artist_image_endpoint(artist_name: str = Query(...)):
    """
    Returns authentic artist profile image via Spotify search API.
    """
    img_url = await get_spotify_artist_image(artist_name=artist_name)
    return {"artist_name": artist_name, "image_url": img_url}


@router.get("/home")
async def get_home_feed(
    request: Request,
    user: models.User = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db),
    redis_client: UpstashRedis = Depends(get_redis)
):
    """
    Fetches the structured YouTube Music home feed based strictly on user's explicit language preferences.
    """
    return await get_home_feed_data(user, db, redis_client)


@router.get("/home-feed")
async def get_consolidated_home_feed(
    request: Request,
    language: Optional[str] = Query(None),
    user: models.User = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db),
    redis_client: UpstashRedis = Depends(get_redis)
):
    """
    Consolidated single-payload home feed returning all sections:
    - madeForYou, trending / trendingMerged, newReleases, featuredAlbums, popularArtists
    Eliminates waterfall HTTP requests and client layout reflows.
    """
    return await get_consolidated_home_feed_data(language, user, db, redis_client)


@router.get("/search")
async def search_tracks(
    query: Optional[str] = Query(None),
    q: Optional[str] = Query(None),
    user: models.User = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db)
):
    """
    Spotify-grade global search across JioSaavn and YouTube catalogs with transliteration,
    click-through feedback, confidence-gated top results, and canonical deduplication.
    """
    try:
        return await execute_search(query, q, user, db)
    except (httpx.ConnectError, httpx.TimeoutException, asyncio.TimeoutError) as ue:
        logger.warning("Router Upstream Error (search): %s", ue)
        raise HTTPException(
            status_code=502,
            detail={"code": "UPSTREAM_UNAVAILABLE", "message": "Upstream music provider is currently unreachable.", "retry_after": 5}
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Router Error (search): %s", e)
        raise HTTPException(
            status_code=500,
            detail={"code": "SEARCH_FAILED", "message": "Error searching for music", "retry_after": None}
        )


@router.get("/search/suggestions")
async def search_suggestions(
    query: str = Query(..., min_length=1),
    user: models.User = Depends(get_current_user_optional)
):
    """
    Global search suggestions with Spotify-style relevance ranking.
    """
    try:
        return await execute_search_suggestions(query, user)
    except Exception as e:
        logger.warning("Suggestions Error: %s", e)
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
        logger.warning("Artist Search Error: %s", e)
        return []


@router.post("/like")
async def like_song(
    song: Dict[str, Any],
    user: models.User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    try:
        liked = await UserRepository.like_song(db, user.id, song)
        if not liked:
            return {"message": "Song already liked"}
        return {"message": "Song liked successfully"}
    except Exception as e:
        await db.rollback()
        logger.error("Like Error: %s", e)
        raise HTTPException(status_code=500, detail="Failed to like song")


@router.delete("/unlike/{song_id}")
async def unlike_song(
    song_id: str,
    user: models.User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    try:
        await UserRepository.unlike_song(db, user.id, song_id)
        return {"message": "Song unliked successfully"}
    except Exception as e:
        await db.rollback()
        logger.error("Unlike Error: %s", e)
        raise HTTPException(status_code=500, detail="Failed to unlike song")


@router.get("/liked")
async def get_liked_songs(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    user: models.User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    try:
        safe_limit = max(1, min(limit, 100))
        safe_offset = max(0, offset)
        return await UserRepository.get_liked_songs(db, user.id, limit=safe_limit, offset=safe_offset)
    except Exception as e:
        logger.error("Fetch Liked Error: %s", e)
        raise HTTPException(status_code=500, detail="Failed to fetch liked songs")


@router.get("/recommendations/{song_id}")
async def get_recommendations(
    song_id: str,
    artist: str = Query(None),
    lang: str = Query(None),
    limit: int = Query(25),
    user: models.User = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db)
):
    """
    Get recommended songs based on a song ID.
    Priority 1: Behavioral collaborative filtering from personal_recommender.
    Priority 2: Metadata recommendation_graph.
    Priority 3: YouTube related songs fallback.
    Supplements across sources until target limit (20-25 songs) is satisfied.
    """
    try:
        user_langs = None
        uid = None
        if user and user.preferred_languages:
            user_langs = [l.strip().lower() for l in user.preferred_languages.split(",") if l.strip()]
            uid = str(user.id)
        elif lang:
            user_langs = [lang.strip().lower()]
        else:
            search_langs = get_user_search_languages(user)
            if search_langs:
                user_langs = [l.strip().lower() for l in search_langs.split(",") if l.strip()]

        target_limit = max(limit, 20)
        results = []

        # Priority 1: Real behavioral similarity from personal recommender
        p1 = personal_recommender.get_similar_songs(
            song_id,
            preferred_languages=user_langs,
            user_id=uid,
            limit=target_limit
        )
        if p1:
            results.extend(p1)

        # Priority 2: Fallback / Supplement with metadata graph
        if len(results) < target_limit:
            primary_lang = user_langs[0] if user_langs else lang
            needed = target_limit - len(results)
            graph_recs = recommendation_graph.get_recommendations(song_id, limit=needed + 5, current_language=primary_lang)
            if graph_recs:
                results.extend(graph_recs)

        # Priority 3: Fallback / Supplement with YouTube's related songs
        if len(results) < target_limit:
            needed = target_limit - len(results)
            try:
                yt_recs = await asyncio.wait_for(
                    youtube.get_related_songs(song_id, limit=max(needed + 5, 16)),
                    timeout=5.0
                )
                if yt_recs:
                    results.extend(yt_recs)
            except Exception as yte:
                logger.warning("YouTube related songs fetch warning: %s", yte)

        # Strict Language Gating across ALL results (including YouTube fallback)
        if user_langs:
            allowed_set = set(user_langs)
            if uid:
                dom_langs = personal_recommender.get_user_dominant_languages(uid)
                allowed_set.update(dom_langs)

            filtered_results = []
            for item in results:
                raw_title = item.get("title", "")
                item_lang = str(item.get("language", "")).lower().strip()
                title_lang = extract_language_from_title(raw_title)

                detected_lang = item_lang or title_lang
                if detected_lang and detected_lang not in allowed_set:
                    continue
                if title_lang and title_lang not in allowed_set:
                    continue
                filtered_results.append(item)
            results = filtered_results

        # Enforce canonical title deduplication across all fallback sources
        if results:
            seen_canons = set()
            deduped = []
            for item in results:
                c_title = canonical_title(item.get("title", ""), item.get("artist", ""))
                if c_title and c_title not in seen_canons:
                    seen_canons.add(c_title)
                    deduped.append(item)
            results = deduped

        return results[:target_limit]
    except Exception as e:
        logger.error("Recommendations Error (Router): %s", e)
        return []


@router.get("/related/{song_id}")
async def get_related_songs(
    song_id: str,
    artist: str = Query(None),
    lang: str = Query(None),
    user: models.User = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db)
):
    """
    Alias for recommendations.
    """
    return await get_recommendations(song_id, artist=artist, lang=lang, user=user, db=db)


@router.get("/artist/{artist_id}")
async def get_artist_details(artist_id: str):
    """
    Get artist profile and top songs from YouTube.
    """
    try:
        results = await asyncio.wait_for(
            youtube.get_artist_details_youtube(artist_id),
            timeout=5.0
        )
        if not results:
            raise HTTPException(
                status_code=404,
                detail={"code": "NOT_FOUND", "message": "Artist not found or unavailable"}
            )
        return results
    except HTTPException:
        raise
    except (httpx.ConnectError, httpx.TimeoutException, asyncio.TimeoutError) as ue:
        logger.warning("Artist Upstream Error: %s", ue)
        raise HTTPException(
            status_code=502,
            detail={"code": "UPSTREAM_UNAVAILABLE", "message": "Artist upstream service is unreachable.", "retry_after": 5}
        )
    except Exception as e:
        logger.error("Artist Error (Router): %s", e)
        raise HTTPException(
            status_code=500,
            detail={"code": "ARTIST_FETCH_FAILED", "message": "Error fetching artist details", "retry_after": None}
        )


@router.get("/albums/{album_id}")
async def get_album_details(album_id: str):
    """
    Fetch full details and tracklist for a specific album from YouTube.
    """
    try:
        results = await asyncio.wait_for(
            youtube.get_album_details_youtube(album_id),
            timeout=5.0
        )
        if not results:
            raise HTTPException(
                status_code=404,
                detail={"code": "NOT_FOUND", "message": "Album not found or unavailable"}
            )
        return results
    except HTTPException:
        raise
    except (httpx.ConnectError, httpx.TimeoutException, asyncio.TimeoutError) as ue:
        logger.warning("Album Upstream Error: %s", ue)
        raise HTTPException(
            status_code=502,
            detail={"code": "UPSTREAM_UNAVAILABLE", "message": "Album upstream service is unreachable.", "retry_after": 5}
        )
    except Exception as e:
        logger.error("Album Error (Router): %s", e)
        raise HTTPException(
            status_code=500,
            detail={"code": "ALBUM_FETCH_FAILED", "message": "Error fetching album details", "retry_after": None}
        )


@router.get("/catalog/delta")
async def get_catalog_delta(since: int = Query(0, description="Timestamp since last sync")):
    """
    Returns weekly delta updates for verified movies and film tracks.
    Enables low-bandwidth sync (~5 KB) so user local database stays fresh without storage bloat.
    """
    return {
        "sync_timestamp": 1729000000,
        "movies": [
            {
                "id": "amaran_2024",
                "title": "Amaran",
                "year": 2024,
                "composer": "G.V. Prakash Kumar",
                "starring": "Sivakarthikeyan, Sai Pallavi",
                "director": "Rajkumar Periasamy",
                "cover_url": "https://c.saavncdn.com/643/Amaran-Tamil-2024-20241004111245-500x500.jpg",
                "language": "tamil"
            },
            {
                "id": "vettaiyan_2024",
                "title": "Vettaiyan",
                "year": 2024,
                "composer": "Anirudh Ravichander",
                "starring": "Rajinikanth, Amitabh Bachchan, Fahadh Faasil, Manju Warrier",
                "director": "T.J. Gnanavel",
                "cover_url": "https://c.saavncdn.com/743/Vettaiyan-Tamil-2024-20240909192410-500x500.jpg",
                "language": "tamil"
            }
        ],
        "songs": [
            {
                "id": "cat_vettaiyan_manasilaayo",
                "title": "Manasilaayo",
                "movie_title": "Vettaiyan",
                "movie_id": "vettaiyan_2024",
                "composer": "Anirudh Ravichander",
                "singers": "Malaysia Vasudevan, Yugendran, Anirudh Ravichander, Deepthi Suresh",
                "starring": "Rajinikanth, Manju Warrier",
                "year": 2024,
                "duration": 247,
                "cover_url": "https://c.saavncdn.com/743/Vettaiyan-Tamil-2024-20240909192410-500x500.jpg",
                "language": "tamil",
                "created_at": 1725840000
            },
            {
                "id": "cat_amaran_hey_minnale",
                "title": "Hey Minnale",
                "movie_title": "Amaran",
                "movie_id": "amaran_2024",
                "composer": "G.V. Prakash Kumar",
                "singers": "Haricharan, Shweta Mohan",
                "starring": "Sivakarthikeyan, Sai Pallavi",
                "year": 2024,
                "duration": 254,
                "cover_url": "https://c.saavncdn.com/643/Amaran-Tamil-2024-20241004111245-500x500.jpg",
                "language": "tamil",
                "created_at": 1728000000
            }
        ],
        "artists": [
            {
                "id": "sai_abhyankkar",
                "name": "Sai Abhyankkar",
                "role": "Composer / Singer",
                "image_url": "https://c.saavncdn.com/artists/Sai_Abhyankkar_500x500.jpg",
                "is_verified": True
            }
        ]
    }
