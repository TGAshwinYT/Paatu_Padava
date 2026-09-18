import re
import json
import asyncio
import logging
import httpx
from typing import Dict, Any, List, Optional
from services import youtube

logger = logging.getLogger(__name__)

SPOTIFY_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.5",
}


def parse_spotify_playlist_id(input_str: str) -> Optional[str]:
    """
    Extracts the Spotify playlist or album ID from URLs, URIs, or raw strings.
    Examples:
      - https://open.spotify.com/playlist/37i9dQZF1DX4WYpdgoIcn6?si=abc123
      - https://open.spotify.com/album/4eLPsYPBmXABThSJ821sqY
      - spotify:playlist:37i9dQZF1DX4WYpdgoIcn6
      - 37i9dQZF1DX4WYpdgoIcn6
    """
    if not input_str:
        return None
    s = input_str.strip()
    
    # URL match (playlist or album)
    url_match = re.search(r'(?:playlist|album)/([a-zA-Z0-9]{22})', s)
    if url_match:
        return url_match.group(1)
        
    # URI match
    uri_match = re.search(r'spotify:(?:playlist|album):([a-zA-Z0-9]{22})', s)
    if uri_match:
        return uri_match.group(1)
        
    # Direct 22-char base62 ID
    if re.fullmatch(r'[a-zA-Z0-9]{22}', s):
        return s
        
    return None


async def fetch_spotify_playlist_metadata(playlist_id: str, raw_url: Optional[str] = None) -> Dict[str, Any]:
    """
    Extracts full playlist/album details and tracklist directly from Spotify's public embed page.
    No OAuth tokens or API keys required.
    """
    entity_type = "album" if raw_url and "album" in raw_url.lower() else "playlist"
    url = f"https://open.spotify.com/embed/{entity_type}/{playlist_id}"
    
    async with httpx.AsyncClient(headers=SPOTIFY_HEADERS, timeout=12.0, follow_redirects=True) as client:
        response = await client.get(url)
        if response.status_code != 200 and entity_type == "playlist":
            # Fallback to album embed if playlist returned 404
            alt_url = f"https://open.spotify.com/embed/album/{playlist_id}"
            alt_res = await client.get(alt_url)
            if alt_res.status_code == 200:
                response = alt_res
        if response.status_code != 200:
            logger.error(f"[SpotifyImport] Failed to fetch embed page: status {response.status_code}")
            raise ValueError("Could not load Spotify playlist. Please ensure the playlist is public.")

        match = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', response.text, re.DOTALL)
        if not match:
            logger.error("[SpotifyImport] __NEXT_DATA__ script tag not found in embed HTML")
            raise ValueError("Could not parse Spotify playlist data. The playlist may be private or deleted.")

        try:
            data = json.loads(match.group(1))
        except Exception as e:
            logger.error(f"[SpotifyImport] Failed to parse JSON: {e}")
            raise ValueError("Invalid playlist response structure from Spotify.")

        entity = data.get('props', {}).get('pageProps', {}).get('state', {}).get('data', {}).get('entity', {})
        if not entity:
            raise ValueError("Spotify playlist entity is empty or unavailable.")

        title = entity.get('name') or entity.get('title') or "Imported Spotify Playlist"
        description = entity.get('subtitle') or entity.get('description') or ""
        
        # Extract cover image
        cover_url = ""
        sources = entity.get('coverArt', {}).get('sources', [])
        if sources:
            # Pick highest resolution image
            cover_url = sources[-1].get('url') or sources[0].get('url') or ""

        track_list_raw = entity.get('trackList', [])
        extracted_tracks: List[Dict[str, Any]] = []
        for t in track_list_raw:
            track_title = t.get('title') or ""
            track_artist = t.get('subtitle') or ""
            duration_ms = t.get('duration') or 0
            if track_title:
                extracted_tracks.append({
                    "title": track_title,
                    "artist": track_artist,
                    "duration": int(duration_ms) // 1000 if duration_ms else 0,
                    "uri": t.get('uri', '')
                })

        return {
            "spotify_id": playlist_id,
            "title": title,
            "description": description,
            "cover_url": cover_url,
            "total_tracks": len(extracted_tracks),
            "tracks": extracted_tracks
        }


async def _resolve_single_track(track: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Resolves a single Spotify track metadata (title + artist) to a Paatu Padava track.
    """
    query = f"{track['title']} {track['artist']}".strip()
    try:
        results = await youtube.search_youtube(query, limit=1)
        if results and len(results) > 0:
            top_match = results[0]
            return {
                "yt_video_id": top_match.get("id"),
                "title": track['title'],
                "artist": track['artist'] or top_match.get("artist", ""),
                "cover_url": top_match.get("cover_url") or top_match.get("coverUrl", ""),
                "duration": top_match.get("duration") or track.get("duration", 0)
            }
    except Exception as e:
        logger.debug(f"[SpotifyImport] Resolution error for '{query}': {e}")
    return None


async def resolve_spotify_tracks_batch(
    tracks: List[Dict[str, Any]], 
    max_tracks: int = 60
) -> List[Dict[str, Any]]:
    """
    Resolves a list of Spotify tracks to platform tracks in controlled concurrency.
    """
    to_resolve = tracks[:max_tracks]
    semaphore = asyncio.Semaphore(5)  # Limit 5 concurrent queries to protect backend resources

    async def sem_task(t):
        async with semaphore:
            return await _resolve_single_track(t)

    tasks = [sem_task(t) for t in to_resolve]
    resolved = await asyncio.gather(*tasks, return_exceptions=True)

    valid_tracks = []
    for r in resolved:
        if isinstance(r, dict) and r.get("yt_video_id"):
            valid_tracks.append(r)

    return valid_tracks
