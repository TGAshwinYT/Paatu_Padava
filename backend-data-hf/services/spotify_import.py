import re
import json
import asyncio
import logging
import httpx
from typing import Dict, Any, List, Optional
from services import youtube
from services.saavn import search_saavn

logger = logging.getLogger(__name__)

SPOTIFY_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.5",
}


async def parse_spotify_playlist_id(input_str: str) -> Optional[str]:
    """
    Extracts the Spotify playlist or album ID from URLs, URIs, shortlinks, or raw strings.
    Examples:
      - https://open.spotify.com/playlist/37i9dQZF1DX4WYpdgoIcn6?si=abc123
      - https://open.spotify.com/album/4eLPsYPBmXABThSJ821sqY
      - https://spotify.link/xyz123
      - https://spotify.app.link/abc
      - spotify:playlist:37i9dQZF1DX4WYpdgoIcn6
      - 37i9dQZF1DX4WYpdgoIcn6
    """
    if not input_str:
        return None
    s = input_str.strip()

    # Expand shortlinks (spotify.link or spotify.app.link)
    if "spotify.link" in s or "spotify.app.link" in s:
        try:
            async with httpx.AsyncClient(timeout=8.0, follow_redirects=True) as client:
                res = await client.head(s)
                s = str(res.url)
        except Exception as e:
            logger.debug(f"[SpotifyImport] Failed to resolve shortlink: {e}")

    # URL match (playlist, album, or track)
    url_match = re.search(r'(?:playlist|album|track)/([a-zA-Z0-9]{22})', s)
    if url_match:
        return url_match.group(1)

    # URI match
    uri_match = re.search(r'spotify:(?:playlist|album|track):([a-zA-Z0-9]{22})', s)
    if uri_match:
        return uri_match.group(1)

    # Direct 22-char base62 ID
    if re.fullmatch(r'[a-zA-Z0-9]{22}', s):
        return s

    return None


async def fetch_spotify_playlist_metadata(playlist_id: str, raw_url: Optional[str] = None) -> Dict[str, Any]:
    """
    Extracts full playlist/album details and tracklist using a multi-tier fallback architecture:
    1. Jina Reader Markdown extractor (100% resilient against Spotify client SPA changes)
    2. Public Spotify oEmbed API
    3. Direct Embed HTML scraper
    """
    entity_type = "album" if raw_url and "album" in raw_url.lower() else "playlist"
    canonical_url = f"https://open.spotify.com/{entity_type}/{playlist_id}"

    title = "Spotify Playlist"
    description = ""
    cover_url = ""
    extracted_tracks: List[Dict[str, Any]] = []

    # ── Tier 1: Jina Reader Markdown Extractor ─────────────────────────
    try:
        jina_url = f"https://r.jina.ai/{canonical_url}"
        async with httpx.AsyncClient(headers={"Accept": "text/plain"}, timeout=14.0) as client:
            res = await client.get(jina_url)
            if res.status_code == 200 and res.text:
                text = res.text

                # 1. Title extraction
                tm = re.search(r'Title:\s*([^|\n]+)', text)
                if tm and tm.group(1).strip():
                    title = tm.group(1).strip()
                elif "# " in text:
                    for line in text.splitlines():
                        if line.startswith("# ") and "main-view" not in line:
                            title = line.replace("# ", "").strip()
                            break

                # 2. Cover image extraction
                cm = re.search(r'!\[.*?\]\((https://i\.scdn\.co/image/[^\)]+)\)', text)
                if cm:
                    cover_url = cm.group(1)

                # 3. Track extraction: [Title](.../track/...) followed by [Artist](.../artist/...)
                track_pattern = re.findall(
                    r'\[([^\]]+)\]\(https://open\.spotify\.com/track/[^\)]+\)\s*\n\s*\[([^\]]+)\]\(https://open\.spotify\.com/artist/[^\)]+\)',
                    text
                )
                for t_title, t_artist in track_pattern:
                    t_title_clean = t_title.strip()
                    t_artist_clean = t_artist.strip()
                    if t_title_clean and not any(t["title"] == t_title_clean and t["artist"] == t_artist_clean for t in extracted_tracks):
                        extracted_tracks.append({
                            "title": t_title_clean,
                            "artist": t_artist_clean,
                            "album": title if entity_type == "album" else "",
                            "duration": 0,
                            "uri": ""
                        })
    except Exception as e:
        logger.debug(f"[SpotifyImport] Jina reader fallback triggered: {e}")

    # ── Tier 2: Spotify oEmbed API Fallback for Metadata ──────────────
    if not cover_url or title == "Spotify Playlist":
        try:
            oembed_url = f"https://open.spotify.com/oembed?url={canonical_url}"
            async with httpx.AsyncClient(timeout=8.0) as client:
                res = await client.get(oembed_url)
                if res.status_code == 200:
                    oembed_data = res.json()
                    title = oembed_data.get("title") or title
                    cover_url = oembed_data.get("thumbnail_url") or cover_url
        except Exception as e:
            logger.debug(f"[SpotifyImport] oEmbed fallback triggered: {e}")

    # ── Tier 3: Direct Embed HTML Scraper Fallback ────────────────────
    if not extracted_tracks:
        try:
            embed_url = f"https://open.spotify.com/embed/{entity_type}/{playlist_id}"
            async with httpx.AsyncClient(headers=SPOTIFY_HEADERS, timeout=10.0, follow_redirects=True) as client:
                response = await client.get(embed_url)
                if response.status_code == 200:
                    # 1. Try __NEXT_DATA__
                    match = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', response.text, re.DOTALL)
                    data = None
                    if match:
                        try:
                            data = json.loads(match.group(1))
                        except Exception:
                            pass

                    # 2. Try initial-state
                    if not data:
                        match_init = re.search(r'<script id="initial-state" type="text/plain">(.*?)</script>', response.text, re.DOTALL)
                        if match_init:
                            try:
                                import base64
                                raw_text = match_init.group(1).strip()
                                try:
                                    decoded = base64.b64decode(raw_text).decode('utf-8')
                                    data = json.loads(decoded)
                                except Exception:
                                    data = json.loads(raw_text)
                            except Exception:
                                pass

                    entity = None
                    if data:
                        entity = (
                            data.get('props', {}).get('pageProps', {}).get('state', {}).get('data', {}).get('entity', {})
                            or data.get('entity', {})
                            or data.get('data', {}).get('entity', {})
                        )

                    if entity:
                        title = entity.get('name') or entity.get('title') or title
                        description = entity.get('subtitle') or entity.get('description') or description
                        sources = entity.get('coverArt', {}).get('sources', [])
                        if sources and not cover_url:
                            cover_url = sources[-1].get('url') or sources[0].get('url') or ""

                        track_list_raw = entity.get('trackList', [])
                        for t in track_list_raw:
                            t_name = t.get('title') or ""
                            t_art = t.get('subtitle') or ""
                            d_ms = t.get('duration') or 0
                            if t_name:
                                extracted_tracks.append({
                                    "title": t_name,
                                    "artist": t_art,
                                    "album": t.get('album') or (title if entity_type == "album" else ""),
                                    "duration": int(d_ms) // 1000 if d_ms else 0,
                                    "uri": t.get('uri', '')
                                })
        except Exception as e:
            logger.debug(f"[SpotifyImport] Embed HTML fallback error: {e}")

    return {
        "spotify_id": playlist_id,
        "title": title or "Imported Spotify Playlist",
        "description": description or f"Imported Spotify {entity_type.capitalize()} ({len(extracted_tracks)} tracks)",
        "cover_url": cover_url,
        "total_tracks": len(extracted_tracks),
        "tracks": extracted_tracks
    }


async def _resolve_single_track(track: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Resolves a single Spotify track to a playable stream:
    1. First tries JioSaavn for pristine 320kbps native audio.
    2. Falls back to YouTube audio stream matching.
    """
    title = track.get('title', '').strip()
    artist = track.get('artist', '').strip()
    album = track.get('album', '').strip()

    if not title:
        return None

    # 1. Search JioSaavn first for pristine studio quality 320kbps stream
    query = f"{title} {artist}".strip()
    try:
        saavn_results = await search_saavn(query, limit=2)
        if saavn_results and len(saavn_results) > 0:
            top_saavn = saavn_results[0]
            if top_saavn.get("audio_url"):
                return {
                    "id": top_saavn.get("id"),
                    "yt_video_id": top_saavn.get("id"),
                    "title": top_saavn.get("title") or title,
                    "artist": top_saavn.get("artist") or artist,
                    "album": top_saavn.get("album") or album,
                    "cover_url": top_saavn.get("cover_url") or top_saavn.get("image") or "",
                    "audio_url": top_saavn.get("audio_url"),
                    "duration": top_saavn.get("duration") or track.get("duration", 0),
                    "source": "saavn"
                }
    except Exception as e:
        logger.debug(f"[SpotifyImport] JioSaavn match failed for '{query}': {e}")

    # 2. Fallback to YouTube
    try:
        results = await youtube.search_youtube(query, limit=3)
        if results and len(results) > 0:
            top_match = results[0]
            clean_t = re.sub(r'[^a-zA-Z0-9]', '', title).lower()
            for r in results:
                r_title = re.sub(r'[^a-zA-Z0-9]', '', r.get('title', '')).lower()
                if clean_t in r_title:
                    top_match = r
                    break

            return {
                "id": top_match.get("id"),
                "yt_video_id": top_match.get("id"),
                "title": title,
                "artist": artist or top_match.get("artist", ""),
                "album": album or top_match.get("album", ""),
                "cover_url": top_match.get("cover_url") or top_match.get("coverUrl", ""),
                "audio_url": top_match.get("audio_url") or "",
                "duration": top_match.get("duration") or track.get("duration", 0),
                "source": "youtube"
            }
    except Exception as e:
        logger.debug(f"[SpotifyImport] YouTube resolution error for '{query}': {e}")

    return None


async def resolve_spotify_tracks_batch(
    tracks: List[Dict[str, Any]], 
    max_tracks: int = 60
) -> List[Dict[str, Any]]:
    """
    Resolves a list of Spotify tracks to playable platform tracks in controlled concurrency.
    """
    to_resolve = tracks[:max_tracks]
    semaphore = asyncio.Semaphore(6)

    async def sem_task(t):
        async with semaphore:
            return await _resolve_single_track(t)

    tasks = [sem_task(t) for t in to_resolve]
    resolved = await asyncio.gather(*tasks, return_exceptions=True)

    valid_tracks = []
    for r in resolved:
        if isinstance(r, dict) and (r.get("yt_video_id") or r.get("id")):
            valid_tracks.append(r)

    return valid_tracks
