from ytmusicapi import YTMusic
import yt_dlp
import asyncio
import logging
import functools
import os
import httpx
import json

logger = logging.getLogger(__name__)

# ── Cookie Setup ──────────────────────────────────────────────────────────────
# Write YOUTUBE_COOKIES secret to /tmp/cookies.txt at import time
COOKIE_PATH = "/tmp/yt_cookies.txt"

def _setup_cookies():
    cookie_data = os.environ.get("YOUTUBE_COOKIES", "")
    if cookie_data.strip():
        try:
            with open(COOKIE_PATH, "w", encoding="utf-8") as f:
                f.write(cookie_data)
            logger.info("[COOKIES] cookies.txt written from YOUTUBE_COOKIES secret.")
            return True
        except Exception as e:
            logger.error(f"[COOKIES] Failed to write cookie file: {e}")
            return False
    logger.warning("[COOKIES] YOUTUBE_COOKIES secret not found. Requests may be blocked.")
    return False

HAS_COOKIES = _setup_cookies()
# ─────────────────────────────────────────────────────────────────────────────

# Initialize YTMusic
auth_file = os.path.join(os.path.dirname(__file__), "..", "headers.json")
try:
    if os.path.exists(auth_file) and os.path.getsize(auth_file) > 0:
        logger.info(f"Initializing YTMusic with authentication from {auth_file}")
        ytmusic = YTMusic(auth_file)
    else:
        logger.info("Initializing YTMusic as Guest")
        ytmusic = YTMusic()
except Exception as e:
    logger.error(f"Failed to initialize YTMusic: {e}")
    ytmusic = YTMusic()

def is_yt_authenticated():
    """
    Checks if the backend is currently authenticated with YouTube Music.
    """
    return os.path.exists(auth_file)

# --- Piped API Configuration ---
# Main public instance used for streaming
PIPED_BASE_URL = "https://pipedapi.kavin.rocks"

async def get_audio_url(video_id: str):
    """
    Uses the public Piped API proxy network to fetch the audio stream,
    completely bypassing YouTube's data-center IP blocks.
    Optimized for M4A/MP4 compatibility.
    """
    piped_url = f"{PIPED_BASE_URL}/streams/{video_id}"
    
    try:
        async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
            logger.info(f"Resolving {video_id} via Piped API ({PIPED_BASE_URL})...")
            response = await client.get(piped_url)
            
            if response.status_code == 200:
                data = response.json()
                audio_streams = data.get("audioStreams", [])
                
                if audio_streams:
                    best_audio_url = None
                    
                    # 1. Look specifically for M4A/MP4 audio (MIME type: audio/mp4). 
                    # Most universally supported format for web players.
                    for stream in audio_streams:
                        mime_type = stream.get("mimeType", "").lower()
                        if "audio/mp4" in mime_type or "m4a" in mime_type:
                            best_audio_url = stream.get("url")
                            logger.info(f"Found optimized M4A/MP4 stream for {video_id}")
                            break
                    
                    # 2. Fallback to the first available audio if M4A isn't found
                    if not best_audio_url:
                        best_audio_url = audio_streams[0].get("url")
                        logger.info(f"Falling back to first available audio stream for {video_id}")
                        
                    return best_audio_url
                else:
                    logger.warning(f"No audio streams found for {video_id} in Piped response.")
                    return None
            else:
                logger.error(f"Piped API Error: {response.status_code} - {response.text}")
                return None
                
    except Exception as e:
        logger.error(f"Backend transition to Piped failed: {e}")
        return None

async def resolve_stream_url(video_id):
    """
    Alias for get_audio_url.
    """
    return await get_audio_url(video_id)

def map_youtube_song(result):
    """
    Maps YTMusic search results to our internal Song format.
    """
    try:
        # 1. Extract artist name safely
        artists = result.get('artists', [])
        if artists:
            if isinstance(artists[0], dict):
                artist_name = ", ".join([a.get('name', 'Unknown') for a in artists])
            else:
                artist_name = str(artists[0])
        else:
            artist_name = result.get('author', 'Unknown Artist')
        
        # 2. Extract thumbnail safely
        thumbnails = result.get('thumbnails') or result.get('thumbnail') or []
        cover_url = thumbnails[-1].get('url') if thumbnails else ""
        
        # 3. Handle Duration (prefer seconds if available)
        duration = result.get('duration_seconds')
        if duration is None:
            duration_str = result.get('duration')
            if duration_str and ":" in duration_str:
                parts = duration_str.split(':')
                try:
                    if len(parts) == 2:
                        duration = int(parts[0]) * 60 + int(parts[1])
                    elif len(parts) == 3:
                        duration = int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
                except:
                    duration = 0
            else:
                duration = 0

        # 4. Handle Album (can be string or dict)
        album_data = result.get('album', "")
        album_name = ""
        if isinstance(album_data, dict):
            album_name = album_data.get('name', "")
        else:
            album_name = str(album_data)

        return {
            "id": result.get('videoId'),
            "title": result.get('title'),
            "artist": artist_name,
            "coverUrl": cover_url,
            "cover_url": cover_url,
            "image": cover_url,
            "audioUrl": "", 
            "duration": duration,
            "album": album_name,
            "isManual": False
        }
    except Exception as e:
        logger.error(f"Error mapping YTMusic result: {e}")
        return None

async def search_youtube(query, filter="songs", limit=20):
    """
    Async wrapper for YTMusic search.
    """
    if not ytmusic:
        return []
    
    loop = asyncio.get_event_loop()
    try:
        results = await loop.run_in_executor(
            None, 
            functools.partial(ytmusic.search, query, filter=filter, limit=limit)
        )
        
        mapped_results = []
        for res in results:
            if res.get('videoId'):
                mapped = map_youtube_song(res)
                if mapped:
                    mapped_results.append(mapped)
        
        return mapped_results
    except Exception as e:
        logger.error(f"YTMusic search error: {e}")
        return []

async def search_albums_youtube(query, limit=10):
    if not ytmusic:
        return []
    
    loop = asyncio.get_event_loop()
    try:
        results = await loop.run_in_executor(
            None, 
            functools.partial(ytmusic.search, query, filter="albums", limit=limit)
        )
        
        mapped_albums = []
        for res in results:
            thumbnails = res.get('thumbnails', [])
            mapped_albums.append({
                "id": res.get('browseId'),
                "title": res.get('title'),
                "artist": res.get('artists', [{}])[0].get('name', 'Unknown Artist'),
                "image": thumbnails[-1].get('url') if thumbnails else "",
                "year": res.get('year'),
                "type": "album"
            })
        
        return mapped_albums
    except Exception as e:
        logger.error(f"YTMusic album search error: {e}")
        return []

async def search_artists_youtube(query, limit=10):
    if not ytmusic:
        return []
    
    loop = asyncio.get_event_loop()
    try:
        results = await loop.run_in_executor(
            None, 
            functools.partial(ytmusic.search, query, filter="artists", limit=limit)
        )
        
        mapped_artists = []
        for res in results:
            thumbnails = res.get('thumbnails', [])
            mapped_artists.append({
                "id": res.get('browseId'),
                "name": res.get('artist'),
                "image": thumbnails[-1].get('url') if thumbnails else "",
                "type": "artist"
            })
        
        return mapped_artists
    except Exception as e:
        logger.error(f"YTMusic artist search error: {e}")
        return []

async def get_trending_youtube(region="global"):
    """
    Fetches trending songs from YouTube Music Charts.
    """
    if not ytmusic:
        return []
    
    loop = asyncio.get_event_loop()
    try:
        # region should be a 2-letter country code for charts, or 'ZZ' for global
        # map 'global' or None to 'ZZ'
        chart_region = region if region and len(region) == 2 else 'ZZ'
        
        results = await loop.run_in_executor(
            None, 
            functools.partial(ytmusic.get_charts, country=chart_region)
        )
        
        songs = results.get('songs', {}).get('items', [])
        mapped_songs = []
        for s in songs:
            mapped = map_youtube_song(s)
            if mapped:
                mapped_songs.append(mapped)
        
        return mapped_songs
    except Exception as e:
        logger.error(f"YTMusic charts error: {e}")
        return []

async def get_home_youtube(limit=20, region=""):
    if not ytmusic:
        return {"recommendedForYou": [], "topAlbums": [], "topArtists": [], "personalized": False}

    response = {
        "recommendedForYou": [],
        "topAlbums": [],
        "topArtists": [],
        "personalized": False
    }

    try:
        # PATH A: Authenticated Personalized Feed
        if is_yt_authenticated():
            logger.info("Fetching personalized home shelves for authenticated session.")
            loop = asyncio.get_event_loop()
            home_data = await loop.run_in_executor(None, functools.partial(ytmusic.get_home, limit=limit))
            
            for shelf in home_data:
                title = shelf.get('title', '').lower()
                contents = shelf.get('contents', [])
                
                if 'listen again' in title or 'recommended' in title:
                    for item in contents:
                        if item.get('videoId') and len(response["recommendedForYou"]) < 12:
                            mapped = map_youtube_song(item)
                            if mapped:
                                response["recommendedForYou"].append(mapped)
                
                for item in contents:
                    browse_id = item.get('browseId', '')
                    if browse_id.startswith('MPREb'):
                        if len(response["topAlbums"]) < 20:
                            response["topAlbums"].append({
                                "id": browse_id,
                                "title": item.get('title', 'Unknown Album'),
                                "artist": item.get('artists', [{'name': 'Various Artists'}])[0].get('name') if item.get('artists') else 'Various Artists',
                                "cover_url": item.get('thumbnails', [{'url': ''}])[-1].get('url')
                            })
                    elif browse_id.startswith('UC'):
                        if len(response["topArtists"]) < 20:
                            response["topArtists"].append({
                                "id": browse_id,
                                "name": item.get('title', 'Unknown Artist'),
                                "cover_url": item.get('thumbnails', [{'url': ''}])[-1].get('url')
                            })
            
            response["personalized"] = len(response["recommendedForYou"]) > 0

        # PATH B: Guest Regional Fallback
        if not response["recommendedForYou"] or not response["personalized"]:
            logger.info(f"Using regional fallback logic for region: {region}")
            fallback = await fetch_regional_fallback(region)
            response["recommendedForYou"] = fallback["recommendedForYou"]
            if not response["topAlbums"]: response["topAlbums"] = fallback["topAlbums"]
            if not response["topArtists"]: response["topArtists"] = fallback["topArtists"]
            response["personalized"] = False

        return response
    except Exception as e:
        logger.error(f"Home Feed Logic Error: {e}")
        return await fetch_regional_fallback(region)

async def fetch_regional_fallback(region=""):
    loop = asyncio.get_event_loop()
    response = {"recommendedForYou": [], "topAlbums": [], "topArtists": []}
    
    song_query = f"{region} Hit Songs" if region else "Tamil Hit Songs"
    search_songs = await loop.run_in_executor(None, functools.partial(ytmusic.search, song_query, filter="songs", limit=12))
    for item in search_songs:
        mapped = map_youtube_song(item)
        if mapped: response["recommendedForYou"].append(mapped)

    album_query = f"{region} Hit Albums" if region else "Tamil Hit Albums"
    search_albums = await loop.run_in_executor(None, functools.partial(ytmusic.search, album_query, filter="albums", limit=20))
    for item in search_albums:
        response["topAlbums"].append({
            "id": item.get('browseId', ''),
            "title": item.get('title', 'Unknown Album'),
            "artist": item.get('artists', [{'name': 'Various Artists'}])[0].get('name') if item.get('artists') else 'Various Artists',
            "cover_url": item.get('thumbnails', [{'url': ''}])[-1].get('url', '')
        })

    artist_query = f"Trending {region} Artists" if region else "Trending Tamil Artists"
    search_artists = await loop.run_in_executor(None, functools.partial(ytmusic.search, artist_query, filter="artists", limit=20))
    for item in search_artists:
        response["topArtists"].append({
            "id": item.get('browseId', ''),
            "name": item.get('artist', item.get('title', 'Unknown Artist')),
            "cover_url": item.get('thumbnails', [{'url': ''}])[-1].get('url', '')
        })

    return response

async def get_related_songs(video_id, limit=10):
    if not ytmusic:
        return []
    
    loop = asyncio.get_event_loop()
    try:
        results = await loop.run_in_executor(
            None, 
            functools.partial(ytmusic.get_watch_playlist, videoId=video_id, limit=limit)
        )
        
        tracks = results.get('tracks', [])
        mapped_tracks = []
        for t in tracks:
            mapped = map_youtube_song(t)
            if mapped:
                mapped_tracks.append(mapped)
        
        return mapped_tracks
    except Exception as e:
        logger.error(f"YTMusic related songs error: {e}")
        return []

async def get_artist_details_youtube(channel_id):
    if not ytmusic:
        return {"name": "Unknown Artist", "image": "", "topSongs": []}
    
    loop = asyncio.get_event_loop()
    try:
        results = await loop.run_in_executor(
            None, 
            functools.partial(ytmusic.get_artist, channelId=channel_id)
        )
        
        thumbnails = results.get('thumbnails', [])
        image_url = thumbnails[-1].get('url') if thumbnails else ""
        
        top_songs_raw = results.get('songs', {}).get('results', [])
        mapped_songs = []
        for s in top_songs_raw:
            mapped = map_youtube_song(s)
            if mapped:
                mapped_songs.append(mapped)
                
        return {
            "id": results.get('channelId'),
            "name": results.get('name'),
            "image": image_url,
            "topSongs": mapped_songs
        }
    except Exception as e:
        logger.error(f"YTMusic artist details error: {e}")
        return {"name": "Unknown Artist", "image": "", "topSongs": []}

async def get_album_details_youtube(browse_id):
    if not ytmusic:
        return {}
    
    loop = asyncio.get_event_loop()
    try:
        results = await loop.run_in_executor(
            None, 
            functools.partial(ytmusic.get_album, browseId=browse_id)
        )
        
        thumbnails = results.get('thumbnails', [])
        image_url = thumbnails[-1].get('url') if thumbnails else ""
        
        tracks_raw = results.get('tracks', [])
        mapped_songs = []
        for t in tracks_raw:
            if not t.get('thumbnails') and not t.get('thumbnail'):
                t['thumbnails'] = thumbnails

            if t.get('videoId'):
                mapped = map_youtube_song(t)
                if mapped:
                    mapped_songs.append(mapped)
        
        return {
            "id": results.get('browseId'),
            "title": results.get('title'),
            "artist": results.get('artists', [{}])[0].get('name', 'Unknown Artist'),
            "image": image_url,
            "songs": mapped_songs
        }
    except Exception as e:
        logger.error(f"YTMusic album details error: {e}")
        return {}


def debug_formats(video_id: str):
    """
    Diagnostic: probes Piped API directly.
    """
    try:
        res = httpx.get(f"{PIPED_BASE_URL}/streams/{video_id}", timeout=10)
        return {
            "piped": {
                "status_code": res.status_code,
                "data": res.json() if res.status_code == 200 else "error"
            }
        }
    except Exception as e:
        return {"error": str(e)}
