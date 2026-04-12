from ytmusicapi import YTMusic
import httpx
import asyncio
import logging
import functools
import os

logger = logging.getLogger(__name__)

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
    
    # Run synchronous YTMusic search in a thread pool to avoid blocking
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

INVIDIOUS_INSTANCES = [
    "https://inv.nadeko.net",
    "https://invidious.nerdvpn.de",
    "https://invidious.privacydev.net"
]

def get_audio_url(video_id: str):
    """
    Extracts the direct audio stream URL using the Invidious API with multi-instance fallback.
    Targeting audio/mp4 for standard compatibility.
    """
    for instance in INVIDIOUS_INSTANCES:
        try:
            url = f"{instance}/api/v1/videos/{video_id}"
            logger.info(f"Attempting audio extraction via Invidious instance: {instance}")
            
            with httpx.Client(timeout=10.0, follow_redirects=True) as client:
                response = client.get(url)
                if response.status_code != 200:
                    logger.warning(f"Invidious instance {instance} returned status {response.status_code}")
                    continue
                
                data = response.json()
                formats = data.get("adaptiveFormats", [])
                
                # Look for the first audio-only format with mp4 container (most compatible)
                audio_format = next(
                    (f for f in formats if "audio/mp4" in f.get("type", "")),
                    next((f for f in formats if f.get("container") == "m4a"), None)
                )
                
                if audio_format and audio_format.get("url"):
                    logger.info(f"Successfully extracted audio URL from {instance}")
                    return audio_format["url"]
                
                logger.warning(f"No suitable audio format found on instance: {instance}")
        except Exception as e:
            logger.error(f"Error calling Invidious instance {instance}: {e}")
            continue
    
    logger.error(f"All Invidious instances failed for video {video_id}")
    return None

async def resolve_stream_url(video_id):
    """
    Async wrapper for get_audio_url.
    """
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, get_audio_url, video_id)

async def search_albums_youtube(query, limit=10):
    """
    Async wrapper for YTMusic album search.
    """
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
    """
    Async wrapper for YTMusic artist search.
    """
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
    """
    Main entry point for the home feed. Switches between Personalized and Regional.
    """
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
                
                # Use 'Listen Again' or 'Recommended' for the top shelf
                if 'listen again' in title or 'recommended' in title:
                    for item in contents:
                        if item.get('videoId') and len(response["recommendedForYou"]) < 12:
                            mapped = map_youtube_song(item)
                            if mapped:
                                response["recommendedForYou"].append(mapped)
                
                # Extract Albums and Artists from other shelves
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

        # PATH B: Guest Regional Fallback (used if not auth OR auth returned nothing)
        if not response["recommendedForYou"] or not response["personalized"]:
            logger.info(f"Using regional fallback logic for region: {region}")
            fallback = await fetch_regional_fallback(region)
            # Merge or Overwrite
            response["recommendedForYou"] = fallback["recommendedForYou"]
            if not response["topAlbums"]: response["topAlbums"] = fallback["topAlbums"]
            if not response["topArtists"]: response["topArtists"] = fallback["topArtists"]
            response["personalized"] = False

        return response

    except Exception as e:
        logger.error(f"Home Feed Logic Error: {e}")
        return await fetch_regional_fallback(region)

async def fetch_regional_fallback(region=""):
    """
    Fetches high-quality localized content based on region when personalization is unavailable.
    """
    loop = asyncio.get_event_loop()
    response = {"recommendedForYou": [], "topAlbums": [], "topArtists": []}
    
    # 1. Localized Search for Songs
    song_query = f"{region} Hit Songs" if region else "Tamil Hit Songs"
    search_songs = await loop.run_in_executor(None, functools.partial(ytmusic.search, song_query, filter="songs", limit=12))
    for item in search_songs:
        mapped = map_youtube_song(item)
        if mapped: response["recommendedForYou"].append(mapped)

    # 2. Localized Search for Albums
    album_query = f"{region} Hit Albums" if region else "Tamil Hit Albums"
    search_albums = await loop.run_in_executor(None, functools.partial(ytmusic.search, album_query, filter="albums", limit=20))
    for item in search_albums:
        response["topAlbums"].append({
            "id": item.get('browseId', ''),
            "title": item.get('title', 'Unknown Album'),
            "artist": item.get('artists', [{'name': 'Various Artists'}])[0].get('name') if item.get('artists') else 'Various Artists',
            "cover_url": item.get('thumbnails', [{'url': ''}])[-1].get('url', '')
        })

    # 3. Localized Search for Artists
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
    """
    Fetches related songs (Watch Next) for a given video ID.
    """
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
            # map_youtube_song expects some keys that get_watch_playlist might provide differently
            mapped = map_youtube_song(t)
            if mapped:
                mapped_tracks.append(mapped)
        
        return mapped_tracks
    except Exception as e:
        logger.error(f"YTMusic related songs error: {e}")
        return []

async def get_artist_details_youtube(channel_id):
    """
    Fetches artist details and their top tracks.
    """
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
    """
    Fetches album details and its tracks.
    """
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
            # get_album tracks often lack thumbnails; we must inject the album cover manually
            if not t.get('thumbnails') and not t.get('thumbnail'):
                t['thumbnails'] = thumbnails

            # get_album tracks might lack videoId if they are unavailable or placeholders
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
