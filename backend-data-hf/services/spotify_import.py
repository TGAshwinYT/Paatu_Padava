import os
import base64
import time
import re
import json
import asyncio
import logging
import httpx
import urllib.parse
from typing import Dict, Any, List, Optional
from services import youtube
from services.saavn import search_saavn

logger = logging.getLogger(__name__)

SPOTIFY_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.5",
}

_cached_spotify_token: Optional[str] = None
_token_expiry_timestamp: float = 0.0


async def get_spotify_access_token() -> Optional[str]:
    """
    Retrieves a cached or fresh Spotify access token using Client Credentials.
    """
    global _cached_spotify_token, _token_expiry_timestamp
    if _cached_spotify_token and time.time() < (_token_expiry_timestamp - 300):
        return _cached_spotify_token

    client_id = os.getenv("SPOTIFY_CLIENT_ID", "").strip()
    client_secret = os.getenv("SPOTIFY_CLIENT_SECRET", "").strip()
    if not client_id or not client_secret or client_id.startswith("REPLACE_"):
        return None

    try:
        credentials = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.post(
                "https://accounts.spotify.com/api/token",
                data={"grant_type": "client_credentials"},
                headers={
                    "Authorization": f"Basic {credentials}",
                    "Content-Type": "application/x-www-form-urlencoded",
                },
            )
            if resp.status_code == 200:
                data = resp.json()
                token = data.get("access_token")
                expires_in = data.get("expires_in", 3600)
                if token:
                    _cached_spotify_token = token
                    _token_expiry_timestamp = time.time() + expires_in
                    logger.info("[SpotifyImport] Acquired official Spotify access token")
                    return token
    except Exception as e:
        logger.warning(f"[SpotifyImport] Failed to obtain official access token: {e}")

    return None


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
    1. Official Spotify Web API (if credentials configured & app owner has premium)
    2. Direct Embed HTML scraper (__NEXT_DATA__ - 100% resilient & instant)
    3. Public Spotify oEmbed API (for metadata)
    4. Jina Reader Markdown extractor (deep fallback)
    """
    entity_type = "album" if raw_url and "album" in raw_url.lower() else "playlist"
    canonical_url = f"https://open.spotify.com/{entity_type}/{playlist_id}"

    title = "Spotify Playlist"
    description = ""
    cover_url = ""
    extracted_tracks: List[Dict[str, Any]] = []

    # ── Tier 1: Official Spotify Web API ──────────────────────────────
    try:
        token = await get_spotify_access_token()
        if token:
            api_headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
            api_url = f"https://api.spotify.com/v1/{entity_type}s/{playlist_id}"
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(api_url, headers=api_headers)
                if resp.status_code == 200:
                    api_data = resp.json()
                    title = api_data.get("name") or title
                    description = api_data.get("description") or description
                    images = api_data.get("images") or []
                    if images:
                        cover_url = images[0].get("url") or ""

                    # Paginated tracks extraction
                    tracks_data = api_data.get("tracks", {})
                    items = tracks_data.get("items", [])
                    total_tracks = tracks_data.get("total", len(items))

                    for item in items:
                        t = item.get("track") if entity_type == "playlist" else item
                        if not t:
                            continue
                        t_name = t.get("name", "").strip()
                        artists = t.get("artists", [])
                        t_artist = artists[0].get("name", "").strip() if artists else ""
                        duration_ms = t.get("duration_ms", 0)
                        if t_name:
                            extracted_tracks.append({
                                "title": t_name,
                                "artist": t_artist,
                                "album": t.get("album", {}).get("name", title) if entity_type == "playlist" else title,
                                "duration": int(duration_ms) // 1000 if duration_ms else 0,
                                "uri": t.get("uri", "")
                            })

                    # If remaining pages exist, fetch up to 200 tracks
                    offset = len(items)
                    while offset < total_tracks and offset < 200:
                        page_url = f"https://api.spotify.com/v1/{entity_type}s/{playlist_id}/tracks?offset={offset}&limit=50"
                        page_resp = await client.get(page_url, headers=api_headers)
                        if page_resp.status_code != 200:
                            break
                        page_data = page_resp.json()
                        page_items = page_data.get("items", [])
                        if not page_items:
                            break
                        for item in page_items:
                            t = item.get("track") if entity_type == "playlist" else item
                            if not t:
                                continue
                            t_name = t.get("name", "").strip()
                            artists = t.get("artists", [])
                            t_artist = artists[0].get("name", "").strip() if artists else ""
                            duration_ms = t.get("duration_ms", 0)
                            if t_name:
                                extracted_tracks.append({
                                    "title": t_name,
                                    "artist": t_artist,
                                    "album": t.get("album", {}).get("name", title) if entity_type == "playlist" else title,
                                    "duration": int(duration_ms) // 1000 if duration_ms else 0,
                                    "uri": t.get("uri", "")
                                })
                        offset += len(page_items)

                    if extracted_tracks:
                        return {
                            "spotify_id": playlist_id,
                            "title": title or "Imported Spotify Playlist",
                            "description": description or f"Imported Spotify {entity_type.capitalize()} ({len(extracted_tracks)} tracks)",
                            "cover_url": cover_url,
                            "total_tracks": len(extracted_tracks),
                            "tracks": extracted_tracks,
                        }
    except Exception as e:
        logger.debug(f"[SpotifyImport] Official Web API notice: {e}")

    # ── Tier 2: Direct Embed HTML Scraper (__NEXT_DATA__) ────────────
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

    # ── Tier 3: Spotify oEmbed API Fallback for Metadata ──────────────
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

    # ── Tier 4: Jina Reader Markdown Extractor ─────────────────────────
    if not extracted_tracks:
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
                    if cm and not cover_url:
                        cover_url = cm.group(1)

                    # 3. Track extraction
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


async def get_spotify_top_10_tracks(language: str = "Tamil") -> List[Dict[str, Any]]:
    """
    Fetches Spotify Top 10 Tracks for a given language using /v1/search.
    Replaces deprecated /v1/browse/featured-playlists and hardcoded 37i9dQZF playlist IDs.
    Queries: GET https://api.spotify.com/v1/search?q=$language%20Top%20Hits&type=track&market=IN&limit=10
    """
    token = await get_spotify_access_token()
    if not token:
        return []

    clean_lang = language.strip() if language else "Tamil"
    query = f"{clean_lang} Top Hits"
    url = f"https://api.spotify.com/v1/search?q={urllib.parse.quote(query)}&type=track&market=IN&limit=10"
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}

    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code == 200:
                data = resp.json()
                items = data.get("tracks", {}).get("items", [])
                tracks = []
                for item in items:
                    if not item or not isinstance(item, dict):
                        continue
                    t_id = item.get("id", "")
                    name = item.get("name", "").strip()
                    artists = item.get("artists", [])
                    artist_name = artists[0].get("name", "").strip() if artists else "Artist"
                    album_obj = item.get("album", {})
                    album_name = album_obj.get("name", "").strip()
                    images = album_obj.get("images", [])
                    cover_url = images[0].get("url", "") if images else ""
                    duration_ms = item.get("duration_ms", 0)

                    if name:
                        tracks.append({
                            "id": t_id,
                            "title": name,
                            "artist": artist_name,
                            "album": album_name,
                            "cover_url": cover_url,
                            "duration": int(duration_ms) // 1000 if duration_ms else 0,
                            "source": "spotify",
                            "language": clean_lang.lower(),
                        })
                return tracks
    except Exception as e:
        logger.warning(f"[SpotifyImport] get_spotify_top_10_tracks failed: {e}")
    return []


async def get_spotify_playlists(language: str = "Tamil") -> List[Dict[str, Any]]:
    """
    Fetches non-editorial Spotify Playlists using /v1/search.
    Filters out items where item is None or item['owner']['id'] == 'spotify' to avoid
    404/403 restrictions on developer key access to Spotify editorial 37i9dQZF playlists.
    Queries: GET https://api.spotify.com/v1/search?q=$language%20Hits&type=playlist&market=IN&limit=15
    """
    token = await get_spotify_access_token()
    if not token:
        return []

    clean_lang = language.strip() if language else "Tamil"
    query = f"{clean_lang} Hits"
    url = f"https://api.spotify.com/v1/search?q={urllib.parse.quote(query)}&type=playlist&market=IN&limit=15"
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}

    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code == 200:
                data = resp.json()
                items = data.get("playlists", {}).get("items", [])
                playlists = []
                for item in items:
                    if not item or not isinstance(item, dict):
                        continue
                    # Skip items where owner is 'spotify' to avoid 404 restrictions on editorial playlists
                    owner_id = item.get("owner", {}).get("id", "").lower()
                    if owner_id == "spotify":
                        continue

                    p_id = item.get("id", "")
                    title = item.get("name", "").strip()
                    description = item.get("description", "").strip()
                    images = item.get("images", [])
                    cover_url = images[0].get("url", "") if images else ""
                    tracks_info = item.get("tracks", {})
                    total_tracks = tracks_info.get("total", 0)

                    if p_id and title:
                        playlists.append({
                            "id": p_id,
                            "title": title,
                            "description": description,
                            "cover_url": cover_url,
                            "total_tracks": total_tracks,
                            "owner": item.get("owner", {}).get("display_name", owner_id),
                        })
                return playlists
    except Exception as e:
        logger.warning(f"[SpotifyImport] get_spotify_playlists failed: {e}")
    return []


async def get_spotify_artist_image(artist_name: str) -> Optional[str]:
    """
    Fetches authentic artist profile image via Spotify Web API.
    Queries: GET https://api.spotify.com/v1/search?q=$artistName&type=artist&market=IN&limit=1
    and returns artists.items[0].images[0].url.
    """
    if not artist_name or not artist_name.strip():
        return None

    token = await get_spotify_access_token()
    if not token:
        return None

    clean_name = artist_name.strip()
    url = f"https://api.spotify.com/v1/search?q={urllib.parse.quote(clean_name)}&type=artist&market=IN&limit=1"
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}

    try:
        async with httpx.AsyncClient(timeout=6.0) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code == 200:
                data = resp.json()
                items = data.get("artists", {}).get("items", [])
                if items and isinstance(items[0], dict):
                    images = items[0].get("images", [])
                    if images and isinstance(images, list) and len(images) > 0 and isinstance(images[0], dict):
                        return images[0].get("url")
    except Exception as e:
        logger.debug(f"[SpotifyImport] get_spotify_artist_image failed for '{artist_name}': {e}")
    return None

