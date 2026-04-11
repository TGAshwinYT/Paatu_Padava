from ytmusicapi import YTMusic
import yt_dlp
import asyncio
import logging
import functools

logger = logging.getLogger(__name__)

# Initialize YTMusic
try:
    ytmusic = YTMusic()
except Exception as e:
    logger.error(f"Failed to initialize YTMusic: {e}")
    ytmusic = None

def map_youtube_song(result):
    """
    Maps YTMusic search results to our internal Song format.
    """
    try:
        # Extract artist name safely
        artists = result.get('artists', [])
        artist_name = artists[0].get('name') if artists else "Unknown Artist"
        
        # Extract thumbnail safely (ytmusicapi uses 'thumbnails' for search but 'thumbnail' for watch playlists)
        thumbnails = result.get('thumbnails') or result.get('thumbnail') or []
        cover_url = thumbnails[-1].get('url') if thumbnails else ""
        
        # Duration string to seconds (e.g., "3:45" -> 225)
        duration = 0
        duration_str = result.get('duration')
        if duration_str and ":" in duration_str:
            parts = duration_str.split(':')
            if len(parts) == 2:
                duration = int(parts[0]) * 60 + int(parts[1])
            elif len(parts) == 3:
                duration = int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])

        return {
            "id": result.get('videoId'),
            "title": result.get('title'),
            "artist": artist_name,
            "coverUrl": cover_url,
            "cover_url": cover_url,  # Modern key
            "image": cover_url,      # Legacy JioSaavn fallback key
            "audioUrl": "", # To be resolved just-in-time via stream endpoint
            "duration": duration,
            "album": result.get('album', {}).get('name') if result.get('album') else "",
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

def get_audio_stream_url(video_id):
    """
    Extracts the direct audio stream URL using yt-dlp.
    Synchronous function intended to be run in an executor.
    """
    ydl_opts = {
        'format': 'bestaudio[ext=m4a]/bestaudio/best', # Prioritize m4a, it streams faster to React
        'quiet': True,
        'no_warnings': True,
        'skip_download': True, # We only want the URL, not the file
        'noplaylist': True, # Prevents accidental massive playlist scraping
        'force_ipv4': True, # Bypasses common IPv6 routing timeouts on cloud servers
        'extractor_args': {
            'youtube': {
                'player_client': ['android'] # THE BIGGEST SPEED HACK
            }
        }
    }
    
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)
            if info and 'url' in info:
                return info['url']
    except Exception as e:
        logger.error(f"yt-dlp extraction error for {video_id}: {e}")
    
    return None

async def resolve_stream_url(video_id):
    """
    Async wrapper for get_audio_stream_url.
    """
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, get_audio_stream_url, video_id)

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

async def get_home_youtube(limit=5):
    """
    Fetches the YouTube Music home feed and parses shelves into categories.
    """
    if not ytmusic:
        return {"recommendedForYou": [], "topAlbums": [], "topArtists": []}

    loop = asyncio.get_event_loop()
    response = {
        "recommendedForYou": [],
        "topAlbums": [],
        "topArtists": []
    }

    try:
        # 1. Fetch Home Data from Shelves
        home_data = await loop.run_in_executor(
            None,
            functools.partial(ytmusic.get_home, limit=limit)
        )

        for shelf in home_data:
            contents = shelf.get('contents', [])
            if not contents:
                continue

            for item in contents:
                try:
                    # 1. Map Songs / Videos to "recommendedForYou"
                    if item.get('videoType') or item.get('videoId'):
                        song_obj = {
                            "id": item.get('videoId', ''),
                            "title": item.get('title', 'Unknown'),
                            "artist": item.get('artists', [{'name': 'Unknown'}])[0].get('name', 'Unknown') if item.get('artists') else 'Unknown',
                            "cover_url": item.get('thumbnails', [{'url': ''}])[-1].get('url', ''),
                            "type": "song"
                        }
                        if song_obj["id"] and len(response["recommendedForYou"]) < 10:
                            response["recommendedForYou"].append(song_obj)

                    # 2. Map Albums to "topAlbums"
                    elif item.get('browseId') and item['browseId'].startswith('MPREb'):
                        album_obj = {
                            "id": item.get('browseId', ''),
                            "title": item.get('title', 'Unknown'),
                            "artist": item.get('subscribers', item.get('artists', [{'name': 'Unknown'}])[0].get('name', 'Unknown')),
                            "cover_url": item.get('thumbnails', [{'url': ''}])[-1].get('url', ''),
                            "type": "album"
                        }
                        if album_obj["id"] and len(response["topAlbums"]) < 10:
                            response["topAlbums"].append(album_obj)

                    # 3. Map Artists to "topArtists"
                    elif item.get('browseId') and item['browseId'].startswith('UC'):
                        artist_obj = {
                            "id": item.get('browseId', ''),
                            "name": item.get('title', 'Unknown'),
                            "cover_url": item.get('thumbnails', [{'url': ''}])[-1].get('url', ''),
                            "type": "artist"
                        }
                        if artist_obj["id"] and len(response["topArtists"]) < 10:
                            response["topArtists"].append(artist_obj)

                except Exception as e:
                    logger.warning(f"Skipped item mapping: {e}")

        # 2. Fallback: Search for popular Tamil/Indian hits if feed is empty
        if not response["recommendedForYou"]:
            logger.info("Home feed empty, fetching fallback 'Tamil Hit Songs' search results.")
            fallback_search = await loop.run_in_executor(
                None,
                functools.partial(ytmusic.search, "Tamil Hit Songs", filter="songs", limit=10)
            )
            for item in fallback_search:
                response["recommendedForYou"].append({
                    "id": item.get('videoId', ''),
                    "title": item.get('title', 'Unknown'),
                    "artist": item.get('artists', [{'name': 'Unknown'}])[0].get('name', 'Unknown') if item.get('artists') else 'Unknown',
                    "cover_url": item.get('thumbnails', [{'url': ''}])[-1].get('url', ''),
                    "type": "song"
                })

        return response
    except Exception as e:
        logger.error(f"YTMusic get_home error: {e}")
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
