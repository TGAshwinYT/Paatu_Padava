"""
Offline audio download stream resolution and proxy streaming service for Paatu Padava.
"""

import asyncio
import logging
import re
import urllib.parse
from typing import Optional

from fastapi import HTTPException
from fastapi.responses import StreamingResponse
import httpx
from upstash_redis.asyncio import Redis as UpstashRedis

from services import youtube
from services.stream_resolver_backend import resolve_single_stream
from services.stream_security import is_safe_audio_url

logger = logging.getLogger(__name__)

MAX_DOWNLOAD_BYTES = 50 * 1024 * 1024  # 50MB ceiling


async def resolve_download_audio_url(
    song_id: Optional[str] = None,
    title: Optional[str] = None,
    artist: Optional[str] = None,
    url: Optional[str] = None,
    redis_client: Optional[UpstashRedis] = None
) -> str:
    """
    Resolves the highest quality direct audio stream URL for offline download.
    Validates the domain against authorized CDN hosts to prevent SSRF.
    """
    # 1. If explicit audio URL passed
    if url and url.startswith("http"):
        if not is_safe_audio_url(url):
            raise HTTPException(status_code=400, detail="Invalid or untrusted download audio URL")
        return url

    audio_url = None

    # 2. Resolve via resolve_single_stream to find 320kbps JioSaavn stream
    if song_id or title:
        try:
            resolved = await resolve_single_stream(song_id or "download", title, artist, redis_client)
            if resolved and resolved.get("audio_url"):
                audio_url = resolved["audio_url"]
            elif resolved and resolved.get("download_urls") and len(resolved["download_urls"]) > 0:
                audio_url = resolved["download_urls"][-1]
        except Exception as e:
            logger.debug("Download stream pre-resolution notice: %s", e)

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
            logger.warning("yt_dlp download extract error: %s", yt_err)

    if not audio_url:
        raise HTTPException(status_code=404, detail="Could not resolve audio stream for downloading")

    if not is_safe_audio_url(audio_url):
        raise HTTPException(status_code=403, detail="Resolved audio stream domain is not authorized for download")

    return audio_url


async def create_download_streaming_response(
    audio_url: str,
    title: Optional[str] = None,
    artist: Optional[str] = None
) -> StreamingResponse:
    """
    Creates an asynchronous chunked StreamingResponse for downloading audio,
    following authorized redirects and enforcing stream bounds.
    """
    # Pure ASCII fallback for legacy HTTP clients and Latin-1 header compliance
    ascii_title = re.sub(r'[^a-zA-Z0-9\s-]', '', title or '').strip() or 'Track'
    ascii_artist = re.sub(r'[^a-zA-Z0-9\s-]', '', artist or '').strip() or 'Paatu Padava'
    ascii_filename = f"{ascii_title} - {ascii_artist}.mp3"

    # Full Unicode filename preserved for modern clients via RFC 5987 / RFC 6266 filename*=
    # Strips only filesystem reserved chars (\\/*?:"<>|) and control chars, preserving all Unicode scripts and combining vowel marks
    unicode_title = re.sub(r'[\x00-\x1f\\/*?:"<>|]', '', title or 'Track').strip() or 'Track'
    unicode_artist = re.sub(r'[\x00-\x1f\\/*?:"<>|]', '', artist or 'Paatu Padava').strip() or 'Paatu Padava'
    unicode_filename = f"{unicode_title} - {unicode_artist}.mp3"
    quoted_filename = urllib.parse.quote(unicode_filename)

    client = httpx.AsyncClient(follow_redirects=False, timeout=60.0)
    try:
        # Secure redirect resolution (max 3 hops, each hop verified against domain whitelist)
        current_target_url = audio_url
        hops = 0
        resp = None

        while hops < 3:
            req = client.build_request("GET", current_target_url)
            resp = await client.send(req, stream=True)
            if resp.status_code in (301, 302, 303, 307, 308):
                loc = resp.headers.get("Location")
                await resp.aclose()
                if not loc or not is_safe_audio_url(loc):
                    await client.aclose()
                    raise HTTPException(status_code=400, detail="Disallowed redirect from upstream audio source")
                current_target_url = loc
                hops += 1
                continue
            break

        if not resp or resp.status_code != 200:
            if resp:
                await resp.aclose()
            await client.aclose()
            raise HTTPException(status_code=502, detail="Failed to fetch upstream audio stream")

        async def stream_generator():
            bytes_streamed = 0
            try:
                async for chunk in resp.aiter_bytes(chunk_size=65536):
                    bytes_streamed += len(chunk)
                    if bytes_streamed > MAX_DOWNLOAD_BYTES:
                        break
                    yield chunk
            finally:
                await resp.aclose()
                await client.aclose()

        headers = {
            "Content-Disposition": f'attachment; filename="{ascii_filename}"; filename*=UTF-8\'\'{quoted_filename}',
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
    except HTTPException:
        raise
    except Exception as e:
        await client.aclose()
        logger.error("Download stream error: %s", e)
        raise HTTPException(status_code=500, detail=f"Download streaming error: {str(e)}")
