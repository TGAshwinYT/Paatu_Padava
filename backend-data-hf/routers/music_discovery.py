import asyncio
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
import httpx
from sqlalchemy.ext.asyncio import AsyncSession
from upstash_redis.asyncio import Redis as UpstashRedis

from auth_utils import get_current_user_optional
from connection import get_db, get_redis
from limiter_config import limiter
import models
from services import youtube
from services.home_feed import (
    get_consolidated_home_feed_data,
    get_home_feed_data,
)
from services.search_scoring import execute_search, execute_search_suggestions
from services.spotify_import import (
    get_spotify_artist_image,
    get_spotify_playlists,
    get_spotify_top_10_tracks,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/music", tags=["music-discovery"])


@router.get("/spotify/token", operation_id="get_spotify_token_v1")
@router.get("/spotify-token", include_in_schema=False)
@router.post("/spotify/token", operation_id="post_spotify_token_v1")
@router.post("/spotify-token", include_in_schema=False)
@limiter.limit("20/minute")
async def get_spotify_token(
    request: Request,
    redis_client: UpstashRedis = Depends(get_redis),
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
            detail="Spotify client credentials are not configured on the backend server.",
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
    """Returns Spotify Top 10 Hits for a given language using /v1/search (non-editorial)."""
    return await get_spotify_top_10_tracks(language=language or "Tamil")


@router.get("/spotify/playlists")
async def get_spotify_playlists_endpoint(language: Optional[str] = Query("Tamil")):
    """Returns Spotify Playlists for a given language using /v1/search (non-editorial, owner != spotify)."""
    return await get_spotify_playlists(language=language or "Tamil")


@router.get("/spotify/artist-image")
async def get_spotify_artist_image_endpoint(artist_name: str = Query(...)):
    """Returns authentic artist profile image via Spotify search API."""
    img_url = await get_spotify_artist_image(artist_name=artist_name)
    return {"artist_name": artist_name, "image_url": img_url}


@router.get("/home")
async def get_home_feed(
    request: Request,
    user: models.User = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db),
    redis_client: UpstashRedis = Depends(get_redis),
):
    """Fetches the structured YouTube Music home feed based strictly on user's explicit language preferences."""
    return await get_home_feed_data(user, db, redis_client)


@router.get("/home-feed")
async def get_consolidated_home_feed(
    request: Request,
    language: Optional[str] = Query(None),
    user: models.User = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db),
    redis_client: UpstashRedis = Depends(get_redis),
):
    """Consolidated single-payload home feed returning all sections."""
    return await get_consolidated_home_feed_data(language, user, db, redis_client)


@router.get("/search")
async def search_tracks(
    query: Optional[str] = Query(None),
    q: Optional[str] = Query(None),
    user: models.User = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db),
):
    """Global search across JioSaavn and YouTube catalogs with transliteration and deduplication."""
    try:
        return await execute_search(query, q, user, db)
    except (httpx.ConnectError, httpx.TimeoutException, asyncio.TimeoutError) as ue:
        logger.warning("Router Upstream Error (search): %s", ue)
        raise HTTPException(
            status_code=502,
            detail={"code": "UPSTREAM_UNAVAILABLE", "message": "Upstream music provider is currently unreachable.", "retry_after": 5},
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Router Error (search): %s", e)
        raise HTTPException(
            status_code=500,
            detail={"code": "SEARCH_FAILED", "message": "Error searching for music", "retry_after": None},
        )


@router.get("/search/suggestions")
async def search_suggestions(
    query: str = Query(..., min_length=1),
    user: models.User = Depends(get_current_user_optional),
):
    """Global search suggestions with Spotify-style relevance ranking."""
    try:
        return await execute_search_suggestions(query, user)
    except Exception as e:
        logger.warning("Suggestions Error: %s", e)
        return {"songs": [], "artists": [], "albums": []}


@router.get("/search/artists")
async def search_artists(query: str = Query(..., min_length=1)):
    """Search specifically for artists for onboarding/preferences."""
    try:
        return await youtube.search_artists_youtube(query, limit=10)
    except Exception as e:
        logger.warning("Artist Search Error: %s", e)
        return []
