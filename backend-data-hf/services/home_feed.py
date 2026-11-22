"""
Home feed retrieval, aggregation, and caching service for Paatu Padava.
"""

import asyncio
import json
import logging
from typing import Any, Dict, Optional

from sqlalchemy.ext.asyncio import AsyncSession
from upstash_redis.asyncio import Redis as UpstashRedis

import models
from services import youtube, saavn
from services.recommender import personal_recommender
from utils.location import get_user_search_languages

logger = logging.getLogger(__name__)


async def get_home_feed_data(
    user: Optional[models.User],
    db: AsyncSession,
    redis_client: UpstashRedis
) -> Dict[str, Any]:
    """
    Fetches the structured YouTube Music home feed based strictly on user's explicit language preferences.
    """
    user_langs = get_user_search_languages(user)
    primary_lang = user_langs.split(",")[0].capitalize() if user_langs else "Tamil"
    cache_key = f"home_feed_yt_v5_{primary_lang}_{user.id if user else 'guest'}"

    # Safe Cache Retrieval
    try:
        cached_data = await asyncio.wait_for(redis_client.get(cache_key), timeout=1.5)
        if cached_data:
            return json.loads(cached_data)
    except Exception as cache_err:
        logger.warning("Redis Cache Warning (home get): %s", cache_err)

    try:
        # Fetch Home Feed (Smart Logic: Personalized if auth exists, else Regional)
        home_feed = await asyncio.wait_for(
            youtube.get_home_youtube(limit=20, region=primary_lang),
            timeout=8.0
        )

        # Safe Cache Storage (30 mins)
        try:
            await asyncio.wait_for(redis_client.setex(cache_key, 1800, json.dumps(home_feed)), timeout=1.5)
        except Exception as cache_err:
            logger.warning("Redis Cache Warning (home set): %s", cache_err)

        return home_feed
    except Exception as e:
        logger.warning("Home Feed YouTube fetch error: %s. Using regional fallback.", e)
        # Safe Fallback: Never crash the frontend with a 500 error
        try:
            songs = await saavn.search_saavn_direct(f"{primary_lang} Hits", limit=15)
            albums = await saavn.search_saavn_albums_direct(f"{primary_lang} Hits", limit=15)
            return {
                "recommendedForYou": songs,
                "topAlbums": albums,
                "topArtists": youtube.CURATED_TOP_ARTISTS,
                "personalized": False
            }
        except Exception as fe:
            logger.error("Emergency home feed fallback failed: %s", fe)
            return {
                "recommendedForYou": [],
                "topAlbums": [],
                "topArtists": youtube.CURATED_TOP_ARTISTS,
                "personalized": False
            }


async def get_consolidated_home_feed_data(
    language: Optional[str],
    user: Optional[models.User],
    db: AsyncSession,
    redis_client: UpstashRedis
) -> Dict[str, Any]:
    """
    Consolidated single-payload home feed returning all sections:
    - madeForYou
    - trending / trendingMerged
    - newReleases
    - featuredAlbums
    - popularArtists
    Eliminates waterfall HTTP requests and client layout reflows.
    """
    user_langs = get_user_search_languages(user)
    primary_lang = language or (user_langs.split(",")[0].capitalize() if user_langs else "Tamil")

    cache_key = f"home_feed_consolidated_v2_{primary_lang}_{user.id if user else 'guest'}"
    try:
        cached = await asyncio.wait_for(redis_client.get(cache_key), timeout=1.5)
        if cached:
            return json.loads(cached)
    except Exception as cache_err:
        logger.warning("Redis Cache Warning (home-feed get): %s", cache_err)

    try:
        # Parallel fetch of all home feed sections
        recommender_coro = (
            personal_recommender.get_cold_start_recommendations(db, user, preferred_languages=primary_lang, limit=15)
            if not user else asyncio.to_thread(
                personal_recommender.get_personal_recommendations,
                str(user.id), preferred_languages=primary_lang, limit=15
            )
        )

        tasks = [
            recommender_coro,
            youtube.get_trending_youtube(region=primary_lang),
            saavn.search_saavn_direct(f"Latest {primary_lang} Releases", limit=15),
            saavn.search_saavn_albums_direct(f"{primary_lang} Hit Albums", limit=12),
        ]
        results = await asyncio.wait_for(
            asyncio.gather(*tasks, return_exceptions=True),
            timeout=8.0
        )

        made_for_you = results[0] if not isinstance(results[0], Exception) and results[0] else []
        if not made_for_you:
            try:
                made_for_you = await saavn.search_saavn_direct(f"{primary_lang} Melodies Hits", limit=15)
            except Exception:
                made_for_you = []

        trending = results[1] if not isinstance(results[1], Exception) and results[1] else []
        if not trending:
            try:
                trending = await saavn.search_saavn_direct(f"{primary_lang} Trending Hits", limit=15)
            except Exception:
                trending = []

        new_releases = results[2] if not isinstance(results[2], Exception) and results[2] else []
        raw_featured_albums = results[3] if not isinstance(results[3], Exception) and results[3] else []
        featured_albums = [
            a for a in raw_featured_albums
            if isinstance(a, dict)
            and int(a.get("song_count") or a.get("songs_count") or len(a.get("songs", [])) or 2) > 1
            and "single" not in (a.get("title") or "").lower()
        ]
        popular_artists = youtube.CURATED_TOP_ARTISTS
        youtube_trending = results[1] if not isinstance(results[1], Exception) and results[1] else []

        payload = {
            "madeForYou": made_for_you,
            "trending": trending,
            "trendingMerged": trending,
            "youtubeTrending": youtube_trending,
            "newReleases": new_releases,
            "featuredAlbums": featured_albums,
            "popularArtists": popular_artists,
            "language": primary_lang,
            "personalized": bool(user and results[0] and not isinstance(results[0], Exception)),
        }

        try:
            await asyncio.wait_for(redis_client.setex(cache_key, 1800, json.dumps(payload)), timeout=1.5)
        except Exception as cache_err:
            logger.warning("Redis Cache Warning (home-feed set): %s", cache_err)

        return payload
    except Exception as e:
        logger.error("Consolidated Home Feed Error: %s", e)
        return {
            "madeForYou": [],
            "trending": [],
            "trendingMerged": [],
            "youtubeTrending": [],
            "newReleases": [],
            "featuredAlbums": [],
            "popularArtists": youtube.CURATED_TOP_ARTISTS,
            "language": primary_lang,
            "personalized": False,
        }
