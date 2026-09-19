from ytmusicapi import YTMusic
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
        ytmusic = YTMusic(auth_file, language="en", location="IN")
    else:
        logger.info("Initializing YTMusic as Guest")
        ytmusic = YTMusic(language="en", location="IN")
except Exception as e:
    logger.error(f"Failed to initialize YTMusic: {e}")
    ytmusic = YTMusic(language="en", location="IN")

def is_yt_authenticated():
    """
    Checks if the backend is currently authenticated with YouTube Music.
    """
    return os.path.exists(auth_file)

def safe_get(obj, key, default=None):
    """
    Safely extract data from YTMusic API responses which can be either a dict or a list.
    """
    if isinstance(obj, dict):
        val = obj.get(key)
        if val is not None:
            return val
    elif isinstance(obj, list):
        # If it's a list, it's likely a list of sections/shelves
        for shelf in obj:
            if isinstance(shelf, dict):
                title = shelf.get('title', '').lower()
                # Check for key matches in titles (e.g., 'songs', 'videos')
                if key.lower() in title:
                    return shelf.get('contents') or shelf.get('items')
                # Also check direct key in shelf
                if key in shelf:
                    return shelf[key]
    return default



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
    Async wrapper for YTMusic search with dual-retrieval (songs + official videos)
    and robust deduplication.
    """
    if not ytmusic or not query:
        return []
    
    loop = asyncio.get_event_loop()
    
    # If filter is explicitly set to something other than songs (e.g., 'videos'), respect it.
    # Otherwise, default to dual-stream retrieval ('songs' + 'videos')
    if filter and filter != "songs":
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
            logger.error(f"YTMusic search error ({filter}): {e}")
            return []

    # Dual-stream retrieval: Fetch studio songs AND official music videos concurrently
    try:
        def _fetch_songs():
            try:
                return ytmusic.search(query, filter="songs", limit=limit)
            except Exception as e:
                logger.warning(f"YTMusic songs filter search failed: {e}")
                return []

        def _fetch_videos():
            try:
                return ytmusic.search(query, filter="videos", limit=min(limit, 10))
            except Exception as e:
                logger.warning(f"YTMusic videos filter search failed: {e}")
                return []

        songs_raw, videos_raw = await asyncio.gather(
            loop.run_in_executor(None, _fetch_songs),
            loop.run_in_executor(None, _fetch_videos),
            return_exceptions=True
        )

        songs_list = songs_raw if isinstance(songs_raw, list) else []
        videos_list = videos_raw if isinstance(videos_raw, list) else []

        seen_ids = set()
        mapped_results = []

        # 1. First add studio songs (highest quality audio and official album tags)
        for res in songs_list:
            vid = res.get('videoId')
            if vid and vid not in seen_ids:
                seen_ids.add(vid)
                mapped = map_youtube_song(res)
                if mapped:
                    mapped["is_studio"] = True
                    mapped_results.append(mapped)

        # 2. Then add official music videos / lyric videos (for catalog breadth)
        for res in videos_list:
            vid = res.get('videoId')
            if vid and vid not in seen_ids:
                seen_ids.add(vid)
                mapped = map_youtube_song(res)
                if mapped:
                    mapped["is_studio"] = False
                    mapped_results.append(mapped)

        # If both specific filters yielded empty results (rare), fallback to unfiltered search
        if not mapped_results:
            fallback = await loop.run_in_executor(
                None,
                functools.partial(ytmusic.search, query, limit=limit)
            )
            for res in fallback:
                vid = res.get('videoId')
                if vid and vid not in seen_ids:
                    seen_ids.add(vid)
                    mapped = map_youtube_song(res)
                    if mapped:
                        mapped_results.append(mapped)

        return mapped_results
    except Exception as e:
        logger.error(f"YTMusic dual search error: {e}")
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
            thumbnails = res.get('thumbnails') or res.get('thumbnail') or []
            if isinstance(thumbnails, dict):
                img_url = thumbnails.get('url', '')
            elif isinstance(thumbnails, list) and thumbnails:
                img_url = thumbnails[-1].get('url', '') if isinstance(thumbnails[-1], dict) else str(thumbnails[-1])
            else:
                img_url = res.get('image', '')

            artist_name = res.get('artist') or res.get('name') or res.get('title') or ''
            if not artist_name or not str(artist_name).strip() or str(artist_name).strip().lower() == 'unknown artist':
                continue

            mapped_artists.append({
                "id": res.get('browseId') or res.get('id') or '',
                "name": str(artist_name).strip(),
                "image": img_url or "",
                "type": "artist"
            })
        
        return mapped_artists
    except Exception as e:
        logger.error(f"YTMusic artist search error: {e}")
        return []

async def get_trending_youtube(region="global"):
    """
    Fetches trending songs from YouTube Music Charts.
    Improved with fallback logic to handle empty 'songs' sections for Guest sessions.
    """
    if not ytmusic:
        return []
    
    loop = asyncio.get_event_loop()
    try:
        # region should be a 2-letter country code for charts, or 'ZZ' for global
        chart_region = region if region and len(region) == 2 else 'ZZ'
        
        logger.info(f"[GRAPH] Fetching charts for region: {chart_region}")
        results = await loop.run_in_executor(
            None, 
            functools.partial(ytmusic.get_charts, country=chart_region)
        )
        
        # Priority 1: Songs section
        songs = safe_get(results, 'songs')
        
        # Priority 2: Videos section
        if not songs:
            logger.info(f"[GRAPH] 'songs' section empty for {chart_region}, falling back to 'videos'")
            songs = safe_get(results, 'videos')
            
        # Priority 3: Regional Fallback if still empty
        if not songs and chart_region == 'ZZ':
            logger.info("[GRAPH] Global charts empty, trying regional fallback (IN)")
            try:
                results_fb = await loop.run_in_executor(None, functools.partial(ytmusic.get_charts, country='IN'))
                songs = safe_get(results_fb, 'songs') or safe_get(results_fb, 'videos')
            except Exception as fe:
                logger.error(f"[GRAPH] Regional fallback failed: {fe}")

        mapped_songs = []
        if isinstance(songs, list):
            for s in songs:
                if isinstance(s, dict):
                    mapped = map_youtube_song(s)
                    if mapped:
                        mapped_songs.append(mapped)
        
        logger.info(f"[GRAPH] Successfully extracted {len(mapped_songs)} trending items.")
        return mapped_songs
    except Exception as e:
        logger.error(f"YTMusic charts error: {e}")
        return []

CURATED_TOP_ARTISTS = [
    {
        "id": "UCwzzSiogpjsYBMoyVcwDXwQ",
        "name": "Ilaiyaraaja",
        "cover_url": "https://lh3.googleusercontent.com/QxbV6wK_wcQWcBY9rBicZlsl1-gX5M6nGjfNN3BTzgknhaSJ6yhnHW7NmF4dTx0Ch9g9-VTD6YUD2crW=w500-h500-p-l90-rj"
    },
    {
        "id": "UC7_KgmSrwM247k2lnh5GhHw",
        "name": "Sid Sriram",
        "cover_url": "https://yt3.googleusercontent.com/Ip35qauI_vMztXkJ3Wd6etvLwiyRrHIGvDyKK3714vyWMBx1ogHxPxkA8ohPnOLyy68wzEVBblPmsHHU=w500-h500-p-l90-rj"
    },
    {
        "id": "UCtJe0RYzgPddQXKtWduxz_w",
        "name": "A. R. Rahman",
        "cover_url": "https://yt3.googleusercontent.com/vHMOuDn8gr3SW9Pm8yFgmtYzM5kj4ayng5HKRjW0OyjG9mPK923XMVtTZTt4NUG_1aemWNLSQ27zjtA=w500-h500-l90-rj"
    },
    {
        "id": "UCbRSywya_rl8YS15Lo9ttsA",
        "name": "Anirudh Ravichander",
        "cover_url": "https://lh3.googleusercontent.com/wBG4jypwBcEGHd-qSbM2_4B46WPEhlOCjusCOEkxdnsoIC4WLS9LmFARZsE854pB-vAEYlsp4x2yiHE=w500-h500-p-l90-rj"
    },
    {
        "id": "UCQXg6kTstIOwbrjBwE3IlDw",
        "name": "Yuvan Shankar Raja",
        "cover_url": "https://lh3.googleusercontent.com/-IRVL5B0n7-V9Gh9XZvQG161HYqkH_SNSHfJwWYeIcVVh35sMq9-jHTk1FCeAmeUHSdEq7UMpoVzUPw=w500-h500-p-l90-rj"
    },
    {
        "id": "UCv6xCP3bn5Pdq0E4SJ4iEKg",
        "name": "Harris Jayaraj",
        "cover_url": "https://yt3.googleusercontent.com/uGytpfjALdTSzoh2hU7FJAqTRrhgWy0Qrio8wrpzRKwAeREv4yBQJpXm-KcOLM3LJW9VQKRNdaeXrL4=w500-h500-l90-rj"
    },
    {
        "id": "UCl4iPtukwe7m0kIxUMskkgA",
        "name": "S. P. Balasubrahmanyam",
        "cover_url": "https://yt3.googleusercontent.com/i-PUJfHy7H3_s1AUBWUaulTzhclF5MobqSIw_3nM3a2-kfCGsY_67K-dEOW7baAiBdfHvSOuHVjR_g=w500-h500-p-l90-rj"
    },
    {
        "id": "UCWUjYIas3aSW65lQOpGiRrg",
        "name": "K. J. Yesudas",
        "cover_url": "https://yt3.googleusercontent.com/R6D0x83Uvnnhdy55hbdpi4SS0I3xqYZsqr_WcsGY0SlQOimmh2HJrkq3KMunG0l9ymm1gGbvtY_HJw=w500-h500-p-l90-rj"
    },
    {
        "id": "UCAMJ6FZcDvdrSRoYcZ14x1Q",
        "name": "Santhosh Narayanan",
        "cover_url": "https://yt3.googleusercontent.com/YfMj32x0B85XqpZCgWu1KXSSXsy8t4Ajt3GUIJw5oLLU94for_wN4HMDQYNvO3U-Hou1TiML9w=w500-h500-l90-rj"
    },
    {
        "id": "UCK-E95XlAlzJtXKIrF4-hjA",
        "name": "G. V. Prakash Kumar",
        "cover_url": "https://yt3.googleusercontent.com/jEh-GLa0VeT7J8D3IhnDH9WqfdPNTp0OthFle0NNtpU6b2nVHUr3vS_trVXlBeYROz-36bAQYw=w500-h500-l90-rj"
    },
    {
        "id": "UC0tPcuSe25Ly0wksSzN4iKg",
        "name": "Pradeep Kumar",
        "cover_url": "https://yt3.googleusercontent.com/g5vebpXaepoLnJv5fBGFmZB1NDwy8IK6VC4BK-iAOnHjdO57Fbg8py5XkgGkJ_S-hNd2_2lW=w500-h500-l90-rj"
    },
    {
        "id": "UCrC-7fsdTCYeaRBpwA6j-Eg",
        "name": "Shreya Ghoshal",
        "cover_url": "https://yt3.ggpht.com/PgINZNe0qVxgMSXKG5vF82bNN4WCC12zgWsz9I7OLs4CLF9Cn0Vxq7Xc1ToupnzXrCv0nKfe3VM=w500-c-h500-k-c0x00ffffff-no-l90-rj"
    },
    {
        "id": "UCX4g5pMVYlYN9K6D8n6HmGg",
        "name": "Shankar Mahadevan",
        "cover_url": "https://lh3.googleusercontent.com/dJy5Bpwx4qENTOXxk9YPXrjAhghP4pRdlzvoOZq8uZXihEPMN8PXnZzM-05R1TDDJkjU7oEij8LhEfw=w500-h500-p-l90-rj"
    },
    {
        "id": "UCdSwA2RiBJIQKhCO4NXTJqQ",
        "name": "Vijay Antony",
        "cover_url": "https://yt3.googleusercontent.com/yneoKhPb7HK9XiZkRKK-S_2nY1cU0eY0_u0P6smf1vKGB1Z2AY9Kjt2rrnbSuKkFaTNMyPhMYePUlg=w500-h500-p-l90-rj"
    },
    {
        "id": "UCm9LbLvK2bAy3pemdtduZCw",
        "name": "D. Imman",
        "cover_url": "https://yt3.googleusercontent.com/vyWvssNMFaoGKP2VQvVrWMcsUotLTZfzp4-nGsMEbSAngEJBvXCMEo6rbM1di1kYkTz88zbNGiaabxI=w500-h500-l90-rj"
    },
    {
        "id": "UCO59Hgc5qAqhLr6EW9vy9pg",
        "name": "Karthik",
        "cover_url": "https://lh3.googleusercontent.com/OUTEpU0QNlUG7I21rEHkvCokmM8GsmYiIhUYcYThaiT0QsXANrcvk99WNskRIas0PZVG_eDR8XAtLwC6=w500-h500-p-l90-rj"
    },
    {
        "id": "UCz087dh7lLqMBb0CipRYNjA",
        "name": "Chinmayi Sripaada",
        "cover_url": "https://yt3.ggpht.com/ytc/AIdro_mPEnSp0WmCq864i3bcGKgC9XGPJy07U6khn_GmIYMLGw=w500-h500-l90-rj-dcrSSejhkK"
    },
    {
        "id": "UC8_JHp4od83YimfxGWqrefQ",
        "name": "Hiphop Tamizha",
        "cover_url": "https://yt3.googleusercontent.com/zkX7FBr1BBzAhH7U5KT6hzBbPx8kjfK1QpTRbW-oM-J8v2f6P0t9idQuPZkssxnIk3U5yBC3KcmU5g=w500-h500-p-l90-rj"
    },
    {
        "id": "UCLQiZGceMt_IvFVCMOq5TCQ",
        "name": "Deva",
        "cover_url": "https://yt3.ggpht.com/ytc/AIdro_lNlmHeHlwCPvq1t6tEKVaXCuWqKoOxNJX9EnhHMhv6r8E=w500-h500-l90-rj-dcHWSQraUH"
    },
    {
        "id": "UCMMzoPx_YAFFYP-qKoFk9rg",
        "name": "Vidyasagar",
        "cover_url": "https://yt3.googleusercontent.com/W_a-fL77QPLAfg_VjUFgI5yUqGV7iPWjJV2cen9SudtT4p1Ivpx-8CxyAJX9y7xK_ts7rHzpAqvob_J9=w500-h500-l90-rj"
    }
]

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
        else:
            return await fetch_regional_fallback(region)

        # Ensure topArtists is always rich and contains all iconic artists
        existing_artist_ids = {a.get("id") for a in response["topArtists"] if a.get("id")}
        for artist in CURATED_TOP_ARTISTS:
            if artist["id"] not in existing_artist_ids:
                response["topArtists"].append(artist)
                existing_artist_ids.add(artist["id"])

        return response
    except Exception as e:
        logger.error(f"Home Feed Logic Error: {e}")
        return await fetch_regional_fallback(region)

async def fetch_regional_fallback(region=""):
    loop = asyncio.get_event_loop()
    response = {
        "recommendedForYou": [], 
        "topAlbums": [], 
        "topArtists": list(CURATED_TOP_ARTISTS)
    }
    query_lang = region or "Tamil"
    
    # 1. Try YouTube Music first with safe exception handling
    try:
        song_query = f"{region} Hit Songs" if region else "Tamil Hit Songs"
        search_songs = await loop.run_in_executor(None, functools.partial(ytmusic.search, song_query, filter="songs", limit=12))
        for item in (search_songs or []):
            mapped = map_youtube_song(item)
            if mapped:
                response["recommendedForYou"].append(mapped)
    except Exception as se:
        logger.warning(f"YouTube song fallback failed (falling back to JioSaavn): {se}")

    try:
        album_query = f"{region} Hit Albums" if region else "Tamil Hit Albums"
        search_albums = await loop.run_in_executor(None, functools.partial(ytmusic.search, album_query, filter="albums", limit=20))
        for item in (search_albums or []):
            response["topAlbums"].append({
                "id": item.get('browseId', ''),
                "title": item.get('title', 'Unknown Album'),
                "artist": item.get('artists', [{'name': 'Various Artists'}])[0].get('name') if item.get('artists') else 'Various Artists',
                "cover_url": item.get('thumbnails', [{'url': ''}])[-1].get('url', '')
            })
    except Exception as ae:
        logger.warning(f"YouTube album fallback failed (falling back to JioSaavn): {ae}")

    # 2. Resilient JioSaavn Direct Fallback if YouTube failed or gave empty results
    if not response["recommendedForYou"] or not response["topAlbums"]:
        try:
            from services.saavn import search_saavn_direct, search_saavn_albums_direct
            if not response["recommendedForYou"]:
                saavn_songs = await search_saavn_direct(f"{query_lang} Hits", limit=15)
                response["recommendedForYou"] = saavn_songs
            if not response["topAlbums"]:
                saavn_albums = await search_saavn_albums_direct(f"{query_lang} Hits", limit=15)
                response["topAlbums"] = saavn_albums
        except Exception as fe:
            logger.warning(f"JioSaavn direct fallback failed: {fe}")

    # 3. Enrich artists
    try:
        artist_query = f"Trending {region} Artists" if region else "Trending Tamil Artists"
        search_artists = await loop.run_in_executor(None, functools.partial(ytmusic.search, artist_query, filter="artists", limit=10))
        existing_ids = {a.get("id") for a in response["topArtists"]}
        for item in (search_artists or []):
            b_id = item.get('browseId', '')
            if b_id and b_id not in existing_ids:
                response["topArtists"].append({
                    "id": b_id,
                    "name": item.get('artist', item.get('title', 'Unknown Artist')),
                    "cover_url": item.get('thumbnails', [{'url': ''}])[-1].get('url', '')
                })
                existing_ids.add(b_id)
    except Exception as ae:
        logger.warning(f"Regional artist search error: {ae}")

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
        
        tracks = safe_get(results, 'tracks', [])
        mapped_tracks = []
        if isinstance(tracks, list):
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
        results = None
        # Attempt direct lookup if ID looks like a valid YouTube browse/channel ID
        if channel_id and (channel_id.startswith("UC") or channel_id.startswith("FE") or len(channel_id) > 20):
            try:
                results = await loop.run_in_executor(
                    None, 
                    functools.partial(ytmusic.get_artist, channelId=channel_id)
                )
            except Exception:
                results = None

        # Fallback: search for artist by name/query if direct lookup failed or channel_id was a name
        if not results or not results.get('name'):
            search_query = channel_id.replace("%20", " ")
            try:
                search_res = await loop.run_in_executor(
                    None,
                    functools.partial(ytmusic.search, query=search_query, filter="artists")
                )
                if search_res and len(search_res) > 0:
                    first_artist = search_res[0]
                    browse_id = first_artist.get("browseId")
                    if browse_id:
                        try:
                            results = await loop.run_in_executor(
                                None,
                                functools.partial(ytmusic.get_artist, channelId=browse_id)
                            )
                        except Exception:
                            results = None

                    if not results:
                        results = {
                            "channelId": browse_id or channel_id,
                            "name": first_artist.get("artist", search_query),
                            "thumbnails": first_artist.get("thumbnails", [])
                        }
            except Exception as se:
                logger.warning(f"Artist search fallback error: {se}")

        if not results:
            return {"name": channel_id.replace("%20", " "), "image": "", "topSongs": []}

        thumbnails = safe_get(results, 'thumbnails', [])
        image_url = thumbnails[-1].get('url') if isinstance(thumbnails, list) and thumbnails else ""
        
        top_songs_raw = safe_get(results, 'songs', {})
        if isinstance(top_songs_raw, dict):
            top_songs_raw = top_songs_raw.get('results', [])
        
        mapped_songs = []
        if isinstance(top_songs_raw, list):
            for s in top_songs_raw:
                mapped = map_youtube_song(s)
                if mapped:
                    mapped_songs.append(mapped)
                
        # If no songs in artist profile, query top songs for this artist so the page is rich
        if not mapped_songs:
            artist_name = safe_get(results, 'name', channel_id.replace("%20", " "))
            try:
                songs_search = await loop.run_in_executor(
                    None,
                    functools.partial(ytmusic.search, query=f"{artist_name} hits", filter="songs")
                )
                if songs_search and isinstance(songs_search, list):
                    for s in songs_search[:10]:
                        mapped = map_youtube_song(s)
                        if mapped:
                            mapped_songs.append(mapped)
            except Exception as sq_err:
                logger.warning(f"Top songs search fallback error: {sq_err}")

        return {
            "id": safe_get(results, 'channelId', channel_id),
            "name": safe_get(results, 'name', channel_id.replace("%20", " ")),
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
        results = None
        if browse_id and (browse_id.startswith("MPRE") or len(browse_id) > 20):
            try:
                results = await loop.run_in_executor(
                    None, 
                    functools.partial(ytmusic.get_album, browseId=browse_id)
                )
            except Exception:
                results = None
        
        # Fallback: search for album by title if not found directly
        if not results:
            album_query = browse_id.replace("%20", " ")
            try:
                search_res = await loop.run_in_executor(
                    None,
                    functools.partial(ytmusic.search, query=album_query, filter="albums")
                )
                if search_res and len(search_res) > 0:
                    found_id = search_res[0].get("browseId")
                    if found_id:
                        results = await loop.run_in_executor(
                            None,
                            functools.partial(ytmusic.get_album, browseId=found_id)
                        )
            except Exception as se:
                logger.warning(f"Album search fallback error: {se}")

        if not results:
            return {}

        thumbnails = safe_get(results, 'thumbnails', [])
        image_url = thumbnails[-1].get('url') if isinstance(thumbnails, list) and thumbnails else ""
        
        tracks_raw = safe_get(results, 'tracks', [])
        mapped_songs = []
        if isinstance(tracks_raw, list):
            for t in tracks_raw:
                if isinstance(t, dict):
                    if not t.get('thumbnails') and not t.get('thumbnail'):
                        t['thumbnails'] = thumbnails
                    if t.get('videoId'):
                        mapped = map_youtube_song(t)
                        if mapped:
                            mapped_songs.append(mapped)
        
        return {
            "id": safe_get(results, 'browseId', browse_id),
            "title": safe_get(results, 'title', 'Album'),
            "artist": safe_get(results, 'artists', [{}])[0].get('name', 'Unknown Artist') if isinstance(safe_get(results, 'artists'), list) and results.get('artists') else 'Unknown Artist',
            "image": image_url,
            "songs": mapped_songs
        }
    except Exception as e:
        logger.error(f"YTMusic album details error: {e}")
        return {}


