import asyncio
import difflib
import json
import re
from typing import Any, Dict, Optional
from fastapi import HTTPException
from upstash_redis.asyncio import Redis as UpstashRedis

from services import youtube
from services.saavn import search_saavn


def clean_song_title(t: str) -> str:
    if not t:
        return ""
    # Remove text in parentheses or brackets like (From "Movie"), [8D Audio], etc.
    t = re.sub(r'[\(\[\{].*?[\)\]\}]', '', t)
    # Replace non-alphanumeric chars with spaces
    t = re.sub(r'[^a-zA-Z0-9\s]', ' ', t)
    return ' '.join(t.lower().split())


def is_title_match(target_title: str, candidate_title: str) -> bool:
    t_clean = clean_song_title(target_title)
    c_clean = clean_song_title(candidate_title)
    if not t_clean or not c_clean:
        return False
    if t_clean == c_clean:
        return True

    t_words = t_clean.split()
    c_words = c_clean.split()

    # Prefix match with whole word boundary (e.g. "naan un" matches "naan un azhaginile")
    if c_clean.startswith(t_clean) or t_clean.startswith(c_clean):
        longer = c_clean if len(c_clean) >= len(t_clean) else t_clean
        shorter = t_clean if len(c_clean) >= len(t_clean) else c_clean
        if len(shorter) >= 4 and (len(longer) == len(shorter) or longer[len(shorter)] == ' '):
            return True

    # High SequenceMatcher ratio (0.75+)
    ratio = difflib.SequenceMatcher(None, t_clean, c_clean).ratio()
    if ratio >= 0.75:
        return True

    # Overlapping token ratio
    t_set = set(t_words)
    c_set = set(c_words)
    if t_set and c_set:
        intersection = t_set & c_set
        overlap_ratio = len(intersection) / max(len(t_set), len(c_set))
        if overlap_ratio >= 0.65:
            return True

    return False


async def resolve_single_stream(
    song_id: str,
    title: Optional[str] = None,
    artist: Optional[str] = None,
    redis_client: Optional[UpstashRedis] = None
) -> Dict[str, Any]:
    """
    Resolves a playable stream payload using a multi-stage fallback:
    1. Upstash Redis Cache (stream_v2:{song_id})
    2. JioSaavn high-bitrate matching with two-pass fuzzy title resolution
    3. YouTube / yt-dlp backend extraction
    """
    cache_key = f"stream_v2:{song_id}"

    # 1. Check Redis Cache with 1.5s timeout protection
    if redis_client:
        try:
            cached = await asyncio.wait_for(redis_client.get(cache_key), timeout=1.5)
            if cached:
                data = json.loads(cached)
                cached_title = data.get("title")
                cached_audio_url = data.get("audio_url")
                # If cached audio_url is missing/empty, or title is mismatched, discard poisoned entry
                if not cached_audio_url or (title and cached_title and not is_title_match(title, cached_title)):
                    try:
                        await redis_client.delete(cache_key)
                    except Exception:
                        pass
                else:
                    data["cached"] = True
                    return data
        except Exception as e:
            print(f"Redis get stream warning: {e}")

    # 2. If title provided, attempt high quality JioSaavn 320kbps resolution with strict title matching
    audio_url = None
    download_urls = []
    matched_title = None
    if title:
        try:
            # Pass 1: Search with title + artist
            query = f"{title} {artist}".strip() if artist else title.strip()
            saavn_results = await search_saavn(query)
            candidate = None
            if saavn_results:
                for item in saavn_results:
                    if is_title_match(title, item.get("title", "")):
                        candidate = item
                        break

            # Pass 2: Fallback to searching clean title alone if Pass 1 had no matching title
            if not candidate:
                saavn_fallback = await search_saavn(title.strip())
                if saavn_fallback:
                    for item in saavn_fallback:
                        if is_title_match(title, item.get("title", "")):
                            candidate = item
                            break

            if candidate and candidate.get("audio_url"):
                audio_url = candidate.get("audio_url")
                download_urls = candidate.get("download_urls", [audio_url])
                matched_title = candidate.get("title")
        except Exception as e:
            print(f"JioSaavn stream resolution warning: {e}")

    # 3. Formulate Payload
    if audio_url:
        payload = {
            "song_id": song_id,
            "title": matched_title or title,
            "audio_url": audio_url,
            "download_urls": download_urls,
            "engine": "native",
            "source": "saavn",
            "cached": False
        }
    else:
        yt_id = song_id
        if len(song_id) != 11 and title:
            try:
                yt_query = f"{title} {artist}".strip() if artist else title.strip()
                yt_matches = await youtube.search_youtube(yt_query, limit=1)
                if yt_matches and yt_matches[0].get("id"):
                    yt_id = yt_matches[0]["id"]
            except Exception:
                pass

        yt_audio_url = None
        if yt_id and len(yt_id) == 11:
            try:
                from services import youtube as yt_service
                yt_audio_url = await asyncio.wait_for(yt_service.get_audio_stream_url(yt_id), timeout=7.0)
            except Exception as yt_err:
                print(f"Backend yt_dlp stream resolution notice: {yt_err}")

        if not yt_audio_url:
            # Resolution failed across both JioSaavn and YouTube
            raise HTTPException(
                status_code=404,
                detail=f"Stream resolution unavailable for track '{title or song_id}'"
            )

        payload = {
            "song_id": song_id,
            "title": title,
            "audio_url": yt_audio_url,
            "download_urls": [yt_audio_url],
            "youtube_id": yt_id,
            "engine": "youtube",
            "source": "youtube",
            "cached": False
        }

    # 4. Save to Redis (24 hr TTL for native, 12 hr TTL for youtube) with timeout protection
    if redis_client and payload.get("audio_url"):
        try:
            ttl = 86400 if payload.get("source") == "saavn" else 43200
            await asyncio.wait_for(redis_client.setex(cache_key, ttl, json.dumps(payload)), timeout=1.5)
        except Exception as e:
            print(f"Redis set stream warning: {e}")

    return payload
