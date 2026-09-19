from fastapi import APIRouter, HTTPException, Query, Depends, Request
from fastapi.responses import RedirectResponse, StreamingResponse
import asyncio
import httpx
import re
import urllib.parse
from typing import List, Dict, Any, Optional
from pydantic import BaseModel
from services import youtube
from services.recommender import personal_recommender, canonical_title, extract_language_from_title
from services.saavn import search_saavn
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete
from connection import get_db, get_redis
from upstash_redis.asyncio import Redis as UpstashRedis
import models
from auth_utils import get_current_user, get_current_user_optional
import json
from utils.location import get_search_languages, resolve_user_languages, get_user_search_languages
from graph import recommendation_graph
from .history import get_user_top_artists


router = APIRouter(prefix="/api/music", tags=["music"])


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
        print(f"For-You Mix Error: {str(e)}")
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


import difflib

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
    if t_clean == c_clean or t_clean in c_clean or c_clean in t_clean:
        return True
    if difflib.SequenceMatcher(None, t_clean, c_clean).ratio() >= 0.70:
        return True
    t_words = set(t_clean.split())
    c_words = set(c_clean.split())
    if t_words and c_words and len(t_words & c_words) / max(len(t_words), 1) >= 0.7:
        return True
    return False


async def resolve_single_stream(
    song_id: str, 
    title: Optional[str] = None, 
    artist: Optional[str] = None, 
    redis_client: Optional[UpstashRedis] = None
) -> Dict[str, Any]:
    cache_key = f"stream_v2:{song_id}"
    
    # 1. Check Redis Cache with 1.5s timeout protection
    if redis_client:
        try:
            cached = await asyncio.wait_for(redis_client.get(cache_key), timeout=1.5)
            if cached:
                data = json.loads(cached)
                cached_title = data.get("title")
                # If title is provided and cached entry has a mismatched title, re-resolve to avoid poisoned cache
                if title and cached_title and not is_title_match(title, cached_title):
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
            # (e.g. JioSaavn tags music director instead of playback singer, like Mani Sharma instead of Harish Raghavendra)
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

        payload = {
            "song_id": song_id,
            "title": title,
            "audio_url": None,
            "download_urls": [],
            "youtube_id": yt_id,
            "engine": "youtube",
            "source": "youtube",
            "cached": False
        }

    # 4. Save to Redis (24 hr TTL for native, 12 hr TTL for youtube fallback) with timeout protection
    if redis_client:
        try:
            ttl = 86400 if audio_url else 43200
            await asyncio.wait_for(redis_client.setex(cache_key, ttl, json.dumps(payload)), timeout=1.5)
        except Exception as e:
            print(f"Redis set stream warning: {e}")

    return payload


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
async def download_track(
    song_id: Optional[str] = Query(None),
    title: Optional[str] = Query(None),
    artist: Optional[str] = Query(None),
    url: Optional[str] = Query(None),
    redis_client: UpstashRedis = Depends(get_redis)
):
    """
    Streams the highest quality 320kbps MP3 audio file with Content-Disposition attachment header
    for pristine offline downloading.
    """
    audio_url = None

    # 1. If explicit audio URL passed (e.g. already playing or resolved)
    if url and url.startswith("http"):
        audio_url = url
    elif song_id or title:
        # 2. Resolve via resolve_single_stream to find 320kbps JioSaavn stream
        resolved = await resolve_single_stream(song_id or "download", title, artist, redis_client)
        if resolved and resolved.get("audio_url"):
            audio_url = resolved["audio_url"]
        elif resolved and resolved.get("download_urls") and len(resolved["download_urls"]) > 0:
            audio_url = resolved["download_urls"][-1]

    # 3. Fallback: if audio_url is still missing and we have youtube_id or song_id
    if not audio_url and (song_id or title):
        try:
            import yt_dlp
            target = song_id
            if not target or len(target) != 11:
                q = f"{title} {artist}".strip() if artist else str(title).strip()
                yt_matches = await youtube.search_youtube(q, limit=1)
                if yt_matches and yt_matches[0].get("id"):
                    target = yt_matches[0]["id"]
            if target:
                ydl_opts = {
                    'format': 'bestaudio/best',
                    'quiet': True,
                    'no_warnings': True,
                    'skip_download': True,
                }
                def _extract():
                    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                        info = ydl.extract_info(f"https://www.youtube.com/watch?v={target}", download=False)
                        return info.get('url')
                audio_url = await asyncio.to_thread(_extract)
        except Exception as yt_err:
            print(f"yt_dlp download extract error: {yt_err}")

    if not audio_url:
        raise HTTPException(status_code=404, detail="Could not resolve audio stream for downloading")

    # Clean filename
    clean_title = re.sub(r'[^\w\s-]', '', title or 'Track').strip() or 'Track'
    clean_artist = re.sub(r'[^\w\s-]', '', artist or 'Paatu Padava').strip() or 'Paatu Padava'
    filename = f"{clean_title} - {clean_artist}.mp3"
    quoted_filename = urllib.parse.quote(filename)

    client = httpx.AsyncClient(follow_redirects=True, timeout=120.0)
    try:
        req = client.build_request("GET", audio_url)
        resp = await client.send(req, stream=True)
        if resp.status_code != 200:
            await client.aclose()
            raise HTTPException(status_code=502, detail="Failed to fetch upstream audio stream")

        async def stream_generator():
            try:
                async for chunk in resp.aiter_bytes(chunk_size=65536):
                    yield chunk
            finally:
                await resp.aclose()
                await client.aclose()

        headers = {
            "Content-Disposition": f'attachment; filename="{filename}"; filename*=UTF-8\'\'{quoted_filename}',
            "Content-Type": "audio/mpeg",
            "Accept-Ranges": "bytes",
            "Access-Control-Expose-Headers": "Content-Disposition, Content-Length"
        }
        if "content-length" in resp.headers:
            headers["Content-Length"] = resp.headers["content-length"]

        return StreamingResponse(
            stream_generator(),
            status_code=200,
            headers=headers,
            media_type="audio/mpeg"
        )
    except Exception as e:
        await client.aclose()
        print(f"Download stream error: {e}")
        raise HTTPException(status_code=500, detail=f"Download streaming error: {str(e)}")



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
    body: PlayerStateRequest,
    user: models.User = Depends(get_current_user_optional),
    redis_client: UpstashRedis = Depends(get_redis)
):
    """
    Saves active player state & queue in Redis for seamless session restore.
    """
    uid = str(user.id) if user else "guest_session"
    key = f"player_state:{uid}"
    try:
        await redis_client.setex(key, 86400 * 7, json.dumps(body.dict()))
        return {"saved": True}
    except Exception as e:
        print(f"Redis save player state error: {e}")
        return {"saved": False}


@router.get("/player-state")
async def get_player_state(
    user: models.User = Depends(get_current_user_optional),
    redis_client: UpstashRedis = Depends(get_redis)
):
    """
    Retrieves the last saved active player state from Redis.
    """
    uid = str(user.id) if user else "guest_session"
    key = f"player_state:{uid}"
    try:
        cached = await redis_client.get(key)
        if cached:
            return json.loads(cached)
    except Exception as e:
        print(f"Redis get player state error: {e}")
    return {"current_track": None, "queue": []}


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
    # 1. Resolve user explicit languages (or neutral fallback)
    user_langs = get_user_search_languages(user)
    primary_lang = user_langs.split(",")[0].capitalize() if user_langs else "Tamil"

    try:
        cache_key = f"home_feed_yt_v5_{primary_lang}_{user.id if user else 'guest'}"
        
        # Safe Cache Retrieval
        try:
            cached_data = await redis_client.get(cache_key)
            if cached_data:
                return json.loads(cached_data)
        except Exception as cache_err:
            print(f"Redis Cache Warning (home get): {str(cache_err)}")

        # 2. Fetch Home Feed (Smart Logic: Personalized if auth exists, else Regional)
        home_feed = await youtube.get_home_youtube(limit=20, region=primary_lang)
        
        # Safe Cache Storage (30 mins)
        try:
            await redis_client.setex(cache_key, 1800, json.dumps(home_feed))
        except Exception as cache_err:
            print(f"Redis Cache Warning (home set): {str(cache_err)}")
            
        return home_feed
    except Exception as e:
        print(f"Home Feed Error: {str(e)}")
        # Safe Fallback: Never crash the frontend with a 500 error
        try:
            from services import saavn
            songs = await saavn.search_saavn_direct(f"{primary_lang} Hits", limit=15)
            albums = await saavn.search_saavn_albums_direct(f"{primary_lang} Hits", limit=15)
            return {
                "recommendedForYou": songs,
                "topAlbums": albums,
                "topArtists": youtube.CURATED_TOP_ARTISTS,
                "personalized": False
            }
        except Exception as fe:
            print(f"Emergency fallback failed: {fe}")
            return {
                "recommendedForYou": [],
                "topAlbums": [],
                "topArtists": youtube.CURATED_TOP_ARTISTS,
                "personalized": False
            }

import re

def _clean_str(text: str) -> str:
    if not text:
        return ""
    # Strip bracketed text like (From "Idhayam Murali"), [Official Video], etc.
    text_clean = re.sub(r'[\(\[\{].*?[\)\]\}]', ' ', text)
    # Replace non-alphanumeric chars with spaces
    text_clean = re.sub(r'[^a-zA-Z0-9\s]', ' ', text_clean)
    return ' '.join(text_clean.lower().split())

def score_track_relevance(song: Dict[str, Any], query: str, user_pref_langs: List[str] = None) -> float:
    """
    Computes a Spotify-grade relevance score for a track against a search query.
    Signals:
    - Exact Title Match: +120
    - Title Starts With Query (Prefix): +75
    - Query in Title: +45
    - Word Token Intersection: Up to +40
    - Artist Match: +20 to +55
    - Studio Track boost: +25
    - Movie/Soundtrack contextual cue: +15
    - Language Preference match: +20
    - Junk / Derivative noise penalty (slowed, reverb, cover, status, ringtone, 8d): -50 to -80
    - Suspiciously short duration (< 55s): -50
    """
    raw_title = str(song.get("title") or "")
    raw_artist = str(song.get("artist") or "")
    duration = song.get("duration") or 0
    is_studio = song.get("is_studio", True)
    song_lang = str(song.get("language") or "").lower().strip()
    
    q_clean = _clean_str(query)
    t_clean = _clean_str(raw_title)
    a_clean = _clean_str(raw_artist)
    
    q_words = set(q_clean.split())
    t_words = set(t_clean.split())
    a_words = set(a_clean.split())
    
    if not q_clean or not t_clean:
        return 0.0

    score = 0.0

    # 1. Exact canonical title match
    if t_clean == q_clean:
        score += 120.0
    # 2. Prefix match (e.g. "Vaama Vaama" matches "Vaama Vaama (From Idhayam Murali)")
    elif t_clean.startswith(q_clean):
        score += 75.0
    # 3. Substring match
    elif q_clean in t_clean:
        score += 45.0
        
    # 4. Token Intersection Ratio
    if q_words:
        overlap = q_words.intersection(t_words)
        if len(overlap) == len(q_words):
            score += 40.0
        else:
            score += (len(overlap) / len(q_words)) * 30.0

    # 5. Artist Match
    if a_clean:
        if q_clean == a_clean:
            score += 55.0
        elif q_clean in a_clean:
            score += 35.0
        elif q_words.intersection(a_words):
            score += 20.0

    # 6. Studio track quality boost
    if is_studio:
        score += 25.0

    # 7. Official Movie / Soundtrack indicator boost
    raw_title_lower = raw_title.lower()
    if 'from "' in raw_title_lower or "from '" in raw_title_lower or "soundtrack" in raw_title_lower or "ost" in raw_title_lower:
        score += 15.0

    # 8. Language Affinity & Regional Variant Gate
    title_lang_tag = extract_language_from_title(raw_title)
    if user_pref_langs:
        is_pref_lang = (song_lang and song_lang in user_pref_langs) or (title_lang_tag and title_lang_tag in user_pref_langs)
        if is_pref_lang:
            score += 80.0  # Strong boost for user's explicit preferred language
        elif title_lang_tag and title_lang_tag not in user_pref_langs:
            score -= 75.0  # Strong penalty for competing dubbed version (e.g. Telugu when Tamil wanted)

    # 9. Noise penalties for derivative / fan / re-upload content
    q_lower = query.lower()
    noise_keywords = [
        ("slowed", 60.0),
        ("reverb", 60.0),
        ("status", 80.0),
        ("ringtone", 80.0),
        ("whatsapp", 80.0),
        ("cover", 50.0),
        ("remix", 30.0),
        ("dj ", 30.0),
        ("8d", 50.0),
        ("bass boosted", 50.0),
        ("karaoke", 50.0),
        ("instrumental", 40.0),
        ("short", 40.0),
        ("cut", 30.0)
    ]
    for kw, penalty in noise_keywords:
        if kw in raw_title_lower and kw not in q_lower:
            score -= penalty

    # 10. Short duration penalty (likely ringtone or status clip)
    if duration and duration < 55 and "ringtone" not in q_lower and "teaser" not in q_lower:
        score -= 50.0

    return score

def score_artist_relevance(artist: Dict[str, Any], query: str) -> float:
    name = str(artist.get("name") or artist.get("title") or "")
    q_clean = _clean_str(query)
    n_clean = _clean_str(name)
    if not q_clean or not n_clean:
        return 0.0
    if n_clean == q_clean:
        return 130.0
    if n_clean.startswith(q_clean):
        return 80.0
    if q_clean in n_clean:
        return 50.0
    q_words = set(q_clean.split())
    n_words = set(n_clean.split())
    if q_words and q_words.issubset(n_words):
        return 60.0
    return 0.0

def score_album_relevance(album: Dict[str, Any], query: str) -> float:
    title = str(album.get("title") or "")
    q_clean = _clean_str(query)
    t_clean = _clean_str(title)
    if not q_clean or not t_clean:
        return 0.0
    if t_clean == q_clean:
        return 115.0
    if t_clean.startswith(q_clean):
        return 65.0
    if q_clean in t_clean:
        return 40.0
    return 0.0

def search_canonical_title(title: str, artist: str = "") -> str:
    """
    Normalizes titles for search deduplication.
    Preserves meaningful version descriptors (e.g. Airport Version, Reprise, Acoustic, Extended)
    while deduplicating exact re-uploads, lyrical/video tags, and label noise.
    """
    if not title:
        return ""
    t = str(title).lower()

    version_tags = ['airport', 'reprise', 'acoustic', 'unplugged', 'lofi', 'slowed', 'extended', 'theme', 'instrumental', 'female', 'male', 'duet']
    matched_versions = [v for v in version_tags if v in t]

    t = re.sub(r'[\(\[\{]\s*(from|ost|soundtrack).*?[\)\]\}]', ' ', t, flags=re.IGNORECASE)
    t = re.sub(r'\b(official|video|audio|lyric|lyrical|hd|4k|full video|song|teaser|trailer|whatsapp|status)\b', ' ', t, flags=re.IGNORECASE)
    t = re.sub(r'\|.*$', ' ', t)
    t = re.sub(r'[^a-z0-9\s]', ' ', t)
    base = ' '.join(t.split())
    if matched_versions:
        base += ' ' + ' '.join(matched_versions)
    return base

@router.get("/search")
async def search_tracks(
    query: str = Query(..., min_length=1), 
    user: models.User = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db)
):
    try:
        # 1. Detect if the user explicitly typed a language name in their query
        detected_lang = None
        known_languages = ["tamil", "telugu", "hindi", "malayalam", "kannada", "english", "punjabi"]
        q_lower = query.lower()
        for kl in known_languages:
            if kl in q_lower:
                detected_lang = kl
                break

        if detected_lang:
            search_languages = detected_lang
        else:
            search_languages = get_user_search_languages(user)

        # 2. Parallel search: JioSaavn (for direct stream URLs) and YouTube Music (Songs, Albums, Artists)
        saavn_task = search_saavn(query, language=search_languages)
        song_task = youtube.search_youtube(query, limit=20)
        album_task = youtube.search_albums_youtube(query, limit=6)
        artist_task = youtube.search_artists_youtube(query, limit=6)

        saavn_res, songs, albums, artists = await asyncio.gather(
            saavn_task, song_task, album_task, artist_task, return_exceptions=True
        )

        saavn_songs = saavn_res if isinstance(saavn_res, list) else []
        yt_songs = songs if isinstance(songs, list) else []
        albums = albums if isinstance(albums, list) else []
        artists = artists if isinstance(artists, list) else []

        # 3. Spotify-Grade Relevance Scoring & Version-Aware Deduplication
        pref_langs = [l.strip().lower() for l in search_languages.split(",") if l.strip()]

        candidates = []
        all_songs = saavn_songs + yt_songs
        for s in all_songs:
            if not s.get("id"):
                continue
            if detected_lang and not s.get("language"):
                s["language"] = detected_lang
            score = score_track_relevance(s, query, pref_langs)
            candidates.append((score, s))

        # Sort candidates descending by score FIRST so the highest quality studio release wins
        candidates.sort(key=lambda x: x[0], reverse=True)

        seen_canonical = set()
        seen_ids = set()
        ranked_songs = []
        ranked_scores = []

        for score, s in candidates:
            sid = s.get("id")
            if sid in seen_ids:
                continue

            c_key = search_canonical_title(s.get("title", ""), s.get("artist", ""))
            if c_key in seen_canonical:
                continue

            seen_canonical.add(c_key)
            seen_ids.add(sid)
            ranked_songs.append(s)
            ranked_scores.append(score)

        # 4. Top Result Determination across Artist, Album, and Song
        best_song = ranked_songs[0] if ranked_songs else None
        best_song_score = ranked_scores[0] if ranked_scores else -999.0

        best_artist = artists[0] if artists else None
        best_artist_score = score_artist_relevance(best_artist, query) if best_artist else -999.0

        best_album = albums[0] if albums else None
        best_album_score = score_album_relevance(best_album, query) if best_album else -999.0

        # Crown highest scoring entity as Top Result
        top_result = None
        if best_artist and best_artist_score > best_song_score and best_artist_score > best_album_score:
            top_result = best_artist
            top_result["type"] = "artist"
        elif best_album and best_album_score > best_song_score and best_album_score > best_artist_score:
            top_result = best_album
            top_result["type"] = "album"
        elif best_song:
            top_result = best_song
            top_result["type"] = "song"
        elif best_artist:
            top_result = best_artist
            top_result["type"] = "artist"
        elif best_album:
            top_result = best_album
            top_result["type"] = "album"
            
        return {
            "global_matches": {
                "top_result": top_result, 
                "songs": ranked_songs[:20], 
                "artists": artists, 
                "albums": albums 
            }
        }
    except Exception as e:
        print(f"Router Error (search): {str(e)}")
        raise HTTPException(status_code=500, detail="Error searching for music")


@router.get("/search/suggestions")
async def search_suggestions(
    query: str = Query(..., min_length=1),
    user: models.User = Depends(get_current_user_optional)
):
    """
    Global search suggestions with Spotify-style relevance ranking.
    """
    try:
        user_langs = get_user_search_languages(user)
        pref_langs = [l.strip().lower() for l in user_langs.split(",") if l.strip()]
        
        songs_task = youtube.search_youtube(query, limit=10)
        artists_task = youtube.search_artists_youtube(query, limit=3)
        songs, artists = await asyncio.gather(songs_task, artists_task, return_exceptions=True)
        
        songs_list = songs if isinstance(songs, list) else []
        artists_list = artists if isinstance(artists, list) else []
        
        valid_artists = []
        for a in artists_list:
            if isinstance(a, dict):
                name = a.get("name") or a.get("artist") or a.get("title")
                if name and str(name).strip() and str(name).strip().lower() != "unknown artist":
                    valid_artists.append({
                        "id": a.get("id") or a.get("browseId") or "",
                        "name": str(name).strip(),
                        "image": a.get("image") or (a.get("thumbnails", [{}])[-1].get("url") if a.get("thumbnails") else ""),
                        "type": "artist"
                    })

        scored = [(score_track_relevance(s, query, pref_langs), s) for s in songs_list]
        scored.sort(key=lambda x: x[0], reverse=True)
        ranked = [item[1] for item in scored]
        
        return {
            "songs": ranked[:8],
            "artists": valid_artists[:3],
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
            audio_url=song.get("audioUrl") or song.get("audio_url"),
            language=song.get("language")
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
            "audio_url": l.audio_url,
            "language": l.language
        } for l in likes]
    except Exception as e:
        print(f"Fetch Liked Error: {str(e)}")
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
            yt_recs = await youtube.get_related_songs(song_id, limit=max(needed + 5, 16))
            if yt_recs:
                results.extend(yt_recs)

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
        print(f"Recommendations Error (Router): {str(e)}")
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


