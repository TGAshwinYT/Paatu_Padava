import asyncio
import logging

from fastapi import APIRouter, Depends, HTTPException, Query
import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from auth_utils import get_current_user_optional
from connection import get_db
from graph import recommendation_graph
import models
from services import youtube
from services.recommender import (
    canonical_title,
    extract_language_from_title,
    personal_recommender,
)
from services.search_scoring import get_user_search_languages

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/music", tags=["music-catalog"])


@router.get("/recommendations/{song_id}")
async def get_recommendations(
    song_id: str,
    artist: str = Query(None),
    lang: str = Query(None),
    limit: int = Query(25),
    user: models.User = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db),
):
    """
    Get recommended songs based on a song ID.
    Priority 1: Behavioral collaborative filtering from personal_recommender.
    Priority 2: Metadata recommendation_graph.
    Priority 3: YouTube related songs fallback.
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

        p1 = personal_recommender.get_similar_songs(
            song_id,
            preferred_languages=user_langs,
            user_id=uid,
            limit=target_limit,
        )
        if p1:
            results.extend(p1)

        if len(results) < target_limit:
            primary_lang = user_langs[0] if user_langs else lang
            needed = target_limit - len(results)
            graph_recs = recommendation_graph.get_recommendations(
                song_id, limit=needed + 5, current_language=primary_lang
            )
            if graph_recs:
                results.extend(graph_recs)

        if len(results) < target_limit:
            needed = target_limit - len(results)
            try:
                yt_recs = await asyncio.wait_for(
                    youtube.get_related_songs(song_id, limit=max(needed + 5, 16)),
                    timeout=5.0,
                )
                if yt_recs:
                    results.extend(yt_recs)
            except Exception as yte:
                logger.warning("YouTube related songs fetch warning: %s", yte)

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
    db: AsyncSession = Depends(get_db),
):
    """Alias for recommendations."""
    return await get_recommendations(song_id, artist=artist, lang=lang, user=user, db=db)


@router.get("/artist/{artist_id}")
async def get_artist_details(artist_id: str):
    """Get artist profile and top songs from YouTube."""
    try:
        results = await asyncio.wait_for(
            youtube.get_artist_details_youtube(artist_id),
            timeout=5.0,
        )
        if not results:
            raise HTTPException(
                status_code=404,
                detail={"code": "NOT_FOUND", "message": "Artist not found or unavailable"},
            )
        return results
    except HTTPException:
        raise
    except (httpx.ConnectError, httpx.TimeoutException, asyncio.TimeoutError) as ue:
        logger.warning("Artist Upstream Error: %s", ue)
        raise HTTPException(
            status_code=502,
            detail={"code": "UPSTREAM_UNAVAILABLE", "message": "Artist upstream service is unreachable.", "retry_after": 5},
        )
    except Exception as e:
        logger.error("Artist Error (Router): %s", e)
        raise HTTPException(
            status_code=500,
            detail={"code": "ARTIST_FETCH_FAILED", "message": "Error fetching artist details", "retry_after": None},
        )


@router.get("/albums/{album_id}")
async def get_album_details(album_id: str):
    """Fetch full details and tracklist for a specific album from YouTube."""
    try:
        results = await asyncio.wait_for(
            youtube.get_album_details_youtube(album_id),
            timeout=5.0,
        )
        if not results:
            raise HTTPException(
                status_code=404,
                detail={"code": "NOT_FOUND", "message": "Album not found or unavailable"},
            )
        return results
    except HTTPException:
        raise
    except (httpx.ConnectError, httpx.TimeoutException, asyncio.TimeoutError) as ue:
        logger.warning("Album Upstream Error: %s", ue)
        raise HTTPException(
            status_code=502,
            detail={"code": "UPSTREAM_UNAVAILABLE", "message": "Album upstream service is unreachable.", "retry_after": 5},
        )
    except Exception as e:
        logger.error("Album Error (Router): %s", e)
        raise HTTPException(
            status_code=500,
            detail={"code": "ALBUM_FETCH_FAILED", "message": "Error fetching album details", "retry_after": None},
        )
