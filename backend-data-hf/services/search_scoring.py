"""
Search relevance scoring, transliteration maps, script detection,
and search pipeline orchestration for Paatu Padava backend.
"""

import asyncio
import logging
import re
from typing import Any, Dict, List, Optional

import httpx
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

import models
from services import youtube
from services.recommender import (
    canonical_title,
    extract_language_from_title,
)
from services.saavn import search_saavn
from services.stream_resolver_backend import clean_song_title
from utils.location import get_user_search_languages

logger = logging.getLogger(__name__)


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
    - Language Preference match: +80
    - Language Mismatch penalty: -75
    - Derivative noise penalty (slowed, reverb, cover, status, ringtone, 8d): -30 to -80
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


def detect_script_language(text: str) -> Optional[str]:
    for ch in text:
        cp = ord(ch)
        if 0x0B80 <= cp <= 0x0BFF:
            return "tamil"
        if 0x0C00 <= cp <= 0x0C7F:
            return "telugu"
        if 0x0D00 <= cp <= 0x0D7F:
            return "malayalam"
        if 0x0C80 <= cp <= 0x0CFF:
            return "kannada"
        if 0x0900 <= cp <= 0x097F:
            return "hindi"
    return None


TANGLISH_TRANSLITERATION_MAP = {
    "mesaya muruku": "meesaya murukku",
    "mesaya murukku": "meesaya murukku",
    "meesaya muruku": "meesaya murukku",
    "puthu mazha": "puthumazha",
    "puthumazhai": "puthumazha",
    "oorum blood": "aarambam",
    "kanne kalaimane": "kanne kalaimane",
    "kannazhaga": "kannazhaga",
    "rowdy baby": "rowdy baby",
    "aalaporan tamizhan": "aalaporaan thamizhan",
    "anbil avan": "anbil avan",
    "vaseegara": "vaseegara",
    "munbe vaa": "munbe vaa",
    "maruvaarthai": "maruvaarthai",
    "enpt": "enai noki paayum thota",
}


async def execute_search(
    query: Optional[str],
    q: Optional[str],
    user: Optional[models.User],
    db: AsyncSession
) -> Dict[str, Any]:
    """
    Orchestrates the multi-stage search pipeline:
    1. Language & script detection, Tanglish transliteration
    2. Parallel retrieval with timeouts (Saavn first, YouTube fallback if Saavn weak)
    3. Click-through boost integration from SearchClickHistory
    4. Studio quality scoring & deduplication
    5. Top result confidence bar and Did-you-mean generation
    """
    raw_query = (query or q or "").strip()
    if not raw_query:
        return {"global_matches": {"top_result": None, "songs": [], "artists": [], "albums": [], "did_you_mean": None}}

    # 1. Script detection and explicit language override extraction
    script_lang = detect_script_language(raw_query)
    detected_lang = script_lang
    known_languages = ["tamil", "telugu", "hindi", "malayalam", "kannada", "english", "punjabi"]

    clean_query = raw_query
    for kl in known_languages:
        pattern = re.compile(rf'\b{kl}\b', re.IGNORECASE)
        if pattern.search(clean_query):
            detected_lang = kl
            clean_query = pattern.sub('', clean_query).strip()

    clean_query = ' '.join(clean_query.split())
    if not clean_query:
        clean_query = raw_query

    # Handle Tanglish-to-native transliteration / typo mapping
    cq_lower = clean_query.lower()
    did_you_mean_suggestion = None
    for typo, correction in TANGLISH_TRANSLITERATION_MAP.items():
        if typo in cq_lower:
            clean_query = cq_lower.replace(typo, correction)
            did_you_mean_suggestion = correction
            break

    if detected_lang:
        search_languages = detected_lang
    else:
        search_languages = get_user_search_languages(user)

    pref_langs = [l.strip().lower() for l in search_languages.split(",") if l.strip()]

    # 2. Retrieve in parallel with timeouts: Query JioSaavn first, YouTube only when JioSaavn is weak
    saavn_songs = []
    try:
        target_saavn_lang = detected_lang if detected_lang else search_languages
        saavn_res = await asyncio.wait_for(search_saavn(clean_query, language=target_saavn_lang), timeout=4.0)
        if isinstance(saavn_res, list):
            saavn_songs = saavn_res
    except Exception as se:
        logger.warning("Saavn search notice: %s", se)

    # JioSaavn is weak if < 3 results or top score < 55.0
    is_saavn_weak = len(saavn_songs) < 3
    if not is_saavn_weak:
        top_saavn_score = max([score_track_relevance(s, clean_query, pref_langs) for s in saavn_songs[:3]], default=0.0)
        if top_saavn_score < 55.0:
            is_saavn_weak = True

    yt_songs = []
    albums = []
    artists = []

    if is_saavn_weak:
        song_task = youtube.search_youtube(clean_query, limit=20)
        album_task = youtube.search_albums_youtube(clean_query, limit=6)
        artist_task = youtube.search_artists_youtube(clean_query, limit=6)
        try:
            yt_res, alb_res, art_res = await asyncio.wait_for(
                asyncio.gather(song_task, album_task, artist_task, return_exceptions=True),
                timeout=5.0
            )
            yt_songs = yt_res if isinstance(yt_res, list) else []
            albums = alb_res if isinstance(alb_res, list) else []
            artists = art_res if isinstance(art_res, list) else []
        except asyncio.TimeoutError:
            logger.warning("YouTube search gather timed out after 5.0s")
    else:
        # Load albums and artists lazily in parallel with timeout protection
        album_task = youtube.search_albums_youtube(clean_query, limit=6)
        artist_task = youtube.search_artists_youtube(clean_query, limit=6)
        try:
            alb_res, art_res = await asyncio.wait_for(
                asyncio.gather(album_task, artist_task, return_exceptions=True),
                timeout=4.0
            )
            albums = alb_res if isinstance(alb_res, list) else []
            artists = art_res if isinstance(art_res, list) else []
        except asyncio.TimeoutError:
            logger.warning("YouTube album/artist gather timed out after 4.0s")

    # 3. Query click-through feedback from SearchClickHistory to boost ranking over time
    click_boosts = {}
    try:
        click_stmt = (
            select(models.SearchClickHistory.yt_video_id, func.count().label("cnt"))
            .group_by(models.SearchClickHistory.yt_video_id)
        )
        click_res = await db.execute(click_stmt)
        for vid, cnt in click_res.all():
            if vid:
                click_boosts[str(vid)] = min(float(cnt) * 5.0, 25.0)
    except Exception as c_err:
        logger.warning("Search click model query warning: %s", c_err)

    # 4. Relevance Scoring & Deduplication
    candidates = []
    all_songs = saavn_songs + yt_songs
    for s in all_songs:
        if not s.get("id"):
            continue
        if detected_lang and not s.get("language"):
            s["language"] = detected_lang
        score = score_track_relevance(s, clean_query, pref_langs)
        sid = str(s.get("id") or "")
        if sid in click_boosts:
            score += click_boosts[sid]
        candidates.append((score, s))

    # Sort candidates descending by score FIRST so highest quality studio release wins
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

    # 5. Top Result Confidence Bar (threshold >= 70.0)
    CONFIDENCE_THRESHOLD = 70.0

    best_song = ranked_songs[0] if ranked_songs else None
    best_song_score = ranked_scores[0] if ranked_scores else -999.0

    best_artist = artists[0] if artists else None
    best_artist_score = score_artist_relevance(best_artist, clean_query) if best_artist else -999.0

    best_album = albums[0] if albums else None
    best_album_score = score_album_relevance(best_album, clean_query) if best_album else -999.0

    best_score = max(best_song_score, best_artist_score, best_album_score)

    top_result = None
    did_you_mean = did_you_mean_suggestion

    if best_score >= CONFIDENCE_THRESHOLD:
        if best_artist and best_artist_score >= best_score:
            top_result = best_artist
            top_result["type"] = "artist"
        elif best_album and best_album_score >= best_score:
            top_result = best_album
            top_result["type"] = "album"
        elif best_song:
            top_result = best_song
            top_result["type"] = "song"
    else:
        # Confidence bar not cleared: show "Did you mean..." instead of a random song
        top_result = None
        if not did_you_mean and ranked_songs:
            candidate_title = ranked_songs[0].get("title", "")
            if candidate_title and clean_song_title(candidate_title) != clean_song_title(clean_query):
                did_you_mean = candidate_title

    return {
        "global_matches": {
            "top_result": top_result,
            "songs": ranked_songs[:20],
            "artists": artists,
            "albums": albums,
            "did_you_mean": did_you_mean,
        }
    }


async def execute_search_suggestions(query: str, user: Optional[models.User]) -> Dict[str, List[Any]]:
    """
    Search suggestions with timeout safety and Spotify-style relevance ranking.
    """
    user_langs = get_user_search_languages(user)
    pref_langs = [l.strip().lower() for l in user_langs.split(",") if l.strip()]

    songs_task = youtube.search_youtube(query, limit=10)
    artists_task = youtube.search_artists_youtube(query, limit=3)

    try:
        songs, artists = await asyncio.wait_for(
            asyncio.gather(songs_task, artists_task, return_exceptions=True),
            timeout=3.5
        )
    except asyncio.TimeoutError:
        logger.warning("Search suggestions gather timed out after 3.5s")
        return {"songs": [], "artists": [], "albums": []}

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
