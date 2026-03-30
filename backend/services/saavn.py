import httpx
import os
import json
import html
import logging
import time
from graph import recommendation_graph
from typing import List, Dict, Any, Optional
from functools import wraps

logger = logging.getLogger(__name__)

# Primary API instance
SAAVN_API_URL = "https://saavn.sumit.co/api"

REGIONAL_VIP_ARTISTS = {
    "tamil": ["Anirudh Ravichander", "A.R. Rahman", "G.V. Prakash Kumar", "Hiphop Tamizha", "Harris Jayaraj", "Yuvan Shankar Raja"],
    "telugu": ["Devi Sri Prasad", "Thaman S", "Sid Sriram", "Anurag Kulkarni", "K. S. Chithra"],
    "hindi": ["Arijit Singh", "Shreya Ghoshal", "Pritam", "Amit Trivedi", "Neha Kakkar"],
    "malayalam": ["Sushin Shyam", "Gopi Sundar", "Hesham Abdul Wahab", "Vineeth Sreenivasan"],
    "english": ["The Weeknd", "Taylor Swift", "Ed Sheeran", "Dua Lipa", "Drake"],
    "default": ["A.R. Rahman", "Arijit Singh", "Anirudh Ravichander", "Shreya Ghoshal"]
}

def async_ttl_cache(ttl_seconds=900):
    """
    Custom Async TTL Cache decorator for I/O bound FastAPI tasks.
    """
    def decorator(func):
        cache = {}

        @wraps(func)
        async def wrapper(*args, **kwargs):
            # Create a unique key from args and kwargs
            key = f"{args}_{kwargs}"
            now = time.time()

            if key in cache:
                result, timestamp = cache[key]
                if now - timestamp < ttl_seconds:
                    print(f"[CACHE HIT] Serving fast data for {func.__name__}!")
                    return result

            # Cache miss or expired
            print(f"[CACHE MISS] Fetching fresh data for {func.__name__}...")
            result = await func(*args, **kwargs)
            cache[key] = (result, now)
            return result
        return wrapper
    return decorator

def extract_artist_name(artist_data: Any) -> str:
    """
    Bulletproof extraction of artist name from various potential keys.
    Checks name, title, listname, subtitle in prioritized order.
    """
    if not artist_data:
        return "Unknown Artist"
    
    if isinstance(artist_data, str):
        return html.unescape(artist_data)
        
    # Priority keys for names/titles
    keys = ["name", "title", "listname", "subtitle", "artist"]
    
    for key in keys:
        val = artist_data.get(key)
        if val and isinstance(val, str) and val.strip().lower() not in ["null", "none", "artist", "unknown"]:
            return html.unescape(val.strip())
        if val and isinstance(val, list) and len(val) > 0:
            # Handle lists of strings or dicts
            item = val[0]
            if isinstance(item, str):
                return html.unescape(item)
            if isinstance(item, dict):
                inner_name = item.get("name") or item.get("title")
                if inner_name:
                    return html.unescape(inner_name)
                    
    return "Unknown Artist"

def extract_high_res_image(image_data: Any) -> str:
    """
    Robust extraction of highest resolution image from various formats.
    Handles strings (including comma-separated lists), lists of URLs, or lists of dictionaries.
    Forces 500x500 for JioSaavn CDN links to ensure premium quality.
    """
    default_image = "https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&h=500&fit=crop"
    
    if not image_data:
        return default_image

    url = default_image

    # 1. Handle String directly
    if isinstance(image_data, str):
        # Handle comma-separated strings (JioSaavn edge case)
        if ',' in image_data:
            urls = [url.strip() for url in image_data.split(',')]
            # Return the highest quality (last item)
            url = urls[-1] if urls and urls[-1].startswith('http') else default_image
        elif image_data.startswith('http'):
            url = image_data
    
    # 2. Handle List of URLs or Dictionaries (JioSaavn standard)
    elif isinstance(image_data, list) and len(image_data) > 0:
        best_img = image_data[-1]
        if isinstance(best_img, dict):
            url = best_img.get('link') or best_img.get('url') or default_image
        elif isinstance(best_img, str) and best_img.startswith('http'):
            url = best_img
            
    # 3. Handle Dictionary directly (Fallback for some modules)
    elif isinstance(image_data, dict):
        url = image_data.get("image") or image_data.get("image_url") or image_data.get("images") or default_image
        # If the extracted value inside the dict is still a list, recurse once
        if isinstance(url, list):
            return extract_high_res_image(url)

    # Final Step: Clean up and Force High Resolution
    if not isinstance(url, str) or not url.startswith("http"):
        return default_image

    # Transform 50x50 or 150x150 to 500x500
    if "jiosaavn.com" in url or "saavncdn.com" in url:
        url = url.replace("50x50", "500x500").replace("150x150", "500x500")
        
    return url

def extract_audio_url(item: Dict[str, Any]) -> str:
    """
    Robustly extracts the highest quality audio URL from JioSaavn song data.
    """
    if not item or not isinstance(item, dict):
        return ""
        
    # 1. Check downloadUrl list (Standard sumit.co 2026 format)
    downloads = item.get("downloadUrl", [])
    if isinstance(downloads, list) and len(downloads) > 0:
        # Prio: 320kbps (idx 4), then 160kbps (idx 3), etc.
        if len(downloads) > 4:
            url = downloads[4].get("url")
            if url: return url
        
        # Fallback to the last (highest available) in the list
        url = downloads[-1].get("url")
        if url: return url

    # 2. Check direct link/url fields (Some modules return this)
    direct_url = item.get("url") or item.get("link") or item.get("download_url")
    if direct_url and (".mp3" in direct_url or ".m4a" in direct_url or "http" in direct_url):
        return direct_url
        
    return ""

async def fetch_from_saavn(endpoint: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Generic fetch utility for JioSaavn API.
    """
    async with httpx.AsyncClient() as client:
        try:
            url = f"{SAAVN_API_URL.rstrip('/')}/{endpoint.lstrip('/')}"
            response = await client.get(url, params=params, timeout=15.0)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"API Request Failed ({endpoint}): {str(e)}")
            return {"success": False, "data": None}

async def map_saavn_song(item: Dict[str, Any], lenient: bool = False) -> Dict[str, Any]:
    """
    Matches the official saavn.sumit.co 2026 schema.
    If 'lenient' is True, it returns songs even if audio_url is missing (useful for Home feed).
    """
    if not item or not isinstance(item, dict):
        return {}

    try:
        # 1. Images are normalized using robust helper
        # Handle if the item was already partially mapped or has cover_url/coverUrl
        raw_image = item.get("image") or item.get("images") or item.get("cover_url") or item.get("coverUrl")
        cover_url = extract_high_res_image(raw_image)

        # 2. Audio URL extraction via robust helper
        audio_url = extract_audio_url(item)

        # Ensure downloads structure exists for backward compatibility if needed
        if audio_url and not item.get("downloadUrl"):
            downloads = [{"quality": "320kbps", "url": audio_url}]
        else:
            downloads = item.get("downloadUrl", [])

        # 3. Artists & Metadata Fallback Chain
        artist = item.get("primaryArtists")
        
        # Fallback 1: artists -> primary -> [0] -> name
        if not artist:
            artists_obj = item.get("artists", {})
            if isinstance(artists_obj, dict):
                primary_list = artists_obj.get("primary", [])
                if isinstance(primary_list, list) and len(primary_list) > 0:
                    artist = primary_list[0].get("name")
        
        # Fallback 2: more_info -> artistMap -> primary_artists -> [0] -> name
        if not artist:
            more_info = item.get("more_info", {})
            if isinstance(more_info, dict):
                artist_map = more_info.get("artistMap", {})
                if isinstance(artist_map, dict):
                    primary_artists = artist_map.get("primary_artists", [])
                    if isinstance(primary_artists, list) and len(primary_artists) > 0:
                        artist = primary_artists[0].get("name")
        
        # Fallback 3: generic artist field
        if not artist:
            artist = item.get("artist")
            
        artist = artist or "Unknown Artist"
        title = item.get("name") or item.get("title") or "Unknown Title"
        
        # Fix HTML entities (e.g. &quot; -> ")
        artist = html.unescape(str(artist))
        title = html.unescape(str(title))
        
        song_id = item.get("id", "unknown")

        # Strict check for search results, but lenient for home feed preview
        if not audio_url and not lenient:
            return {}

        return {
            "id": song_id,
            "title": title,
            "artist": artist,
            "cover_url": cover_url,
            "audio_url": audio_url,
            "duration": int(item.get("duration", 0)) if item.get("duration") else 0,
            "download_urls": [d.get("url") for d in downloads] if isinstance(downloads, list) else []
        }
    except Exception as e:
        print(f"⚠️ Mapping failed for item: {str(e)}")
        return {}

async def search_saavn(query: str, language: str = None) -> List[Dict[str, Any]]:
    """
    Official Search implementation. Strictly returns playable tracks.
    Expects 'query' to be potentially pre-encoded or contain special characters.
    'language' is a comma-separated string of prioritized languages.
    """
    # Note: httpx.get with params=params handles URI encoding automatically.
    # To avoid double-encoding if 'query' was pre-quoted, we ensure it's unquoted first
    # so that the library can handle it cleanly and consistently.
    from urllib.parse import unquote
    clean_query = unquote(query)
    
    params = {"query": clean_query}
    if language:
        params["language"] = language
        
    response = await fetch_from_saavn("search/songs", params)
    data = response.get("data") or {}
    results = data.get("results", [])
    
    print(f"[SEARCH DEBUG] Found {len(results)} items in API results for '{query}'")
    
    mapped_songs = []
    for item in results:
        mapped = await map_saavn_song(item, lenient=False)
        if mapped and mapped.get("audio_url"):
            mapped_songs.append(mapped)
            
    return mapped_songs

@async_ttl_cache(ttl_seconds=1800)
async def get_trending(languages: str = None) -> Dict[str, List[Dict[str, Any]]]:
    """
    Fetches trending music, albums, and artists for the home screen.
    Uses normalization loop and robust image extraction.
    Localized by prioritized languages if provided.
    """
    songs_raw = []
    albums_raw = []
    artists_raw = []
    
    # Extract primary language for fallback searches
    primary_lang = "hindi"
    if languages:
        primary_lang = languages.split(',')[0].strip()

    try:
        # 1. Fetch from modules (Default Home Feed) with language context
        response = await fetch_from_saavn("modules", {"language": languages or "hindi,english"})
        
        logger.error("============= RAW JIOSAAVN DATA START =============")
        logger.error(response)
        logger.error("============= RAW JIOSAAVN DATA END =============")
        
        data = response.get("data", {})
        
        if data:
            # Extract Songs
            if data.get("trending") and isinstance(data["trending"], dict):
                songs_raw = data["trending"].get("songs", [])
            
            # Extract Albums
            if data.get("albums") and isinstance(data["albums"], list):
                albums_raw = data["albums"]
                
            # Extract Artists (Check trending.artists or specific artist objects)
            if data.get("trending") and isinstance(data["trending"], dict):
                artists_raw = data["trending"].get("artists", [])
            
            # Fallback if trending.artists is empty, check if top_playlists contains artist objects (rare but possible)
            if not artists_raw and data.get("top_playlists") and isinstance(data["top_playlists"], list):
                # Only use it if they look like artists (e.g. have 'artist' or 'type' == 'artist')
                potential = data["top_playlists"]
                if potential and (potential[0].get("type") == "artist" or "artist" in potential[0]):
                    artists_raw = potential
    except Exception as e:
        print(f"Primary modules endpoint failed: {str(e)}")

    # 2. Robust Fallback: If modules are thin, search for fresh content using primary language
    if len(songs_raw) < 5 or len(albums_raw) < 5:
        print(f"Home feed thin for {primary_lang}, triggering search-based population...")
        
        # We fetch RAW data from saavn to avoid double mapping
        if not songs_raw:
            songs_resp = await fetch_from_saavn("search/songs", {"query": f"Trending {primary_lang.capitalize()} Songs"})
            songs_raw = songs_resp.get("data", {}).get("results", [])
        
        if not albums_raw:
            albums_resp = await fetch_from_saavn("search/albums", {"query": f"New {primary_lang.capitalize()} Albums"})
            albums_raw = albums_resp.get("data", {}).get("results", [])
            
        if not artists_raw:
            print(f"[LOCALIZATION] Fetching VIP regional artists for {primary_lang}...")
            import asyncio
            
            # Get the VIP list for the region, or use default
            vip_names = REGIONAL_VIP_ARTISTS.get(primary_lang, REGIONAL_VIP_ARTISTS["default"])
            
            # Helper function to fetch the top 1 exact match for a specific artist
            async def fetch_vip_artist(name):
                resp = await fetch_from_saavn("search/artists", {"query": name})
                results = resp.get("data", {}).get("results", [])
                return results[0] if results else None

            # Run all exact name searches concurrently for instant response
            tasks = [fetch_vip_artist(name) for name in vip_names]
            vip_results = await asyncio.gather(*tasks)
            
            # Filter out any None values if an artist search failed
            artists_raw = [artist for artist in vip_results if artist]
            
            print(f"DEBUG: Found {len(artists_raw)} VIP artists for {primary_lang}")

            # If that's still empty, fallback to generic trending
            if not artists_raw:
                artists_resp = await fetch_from_saavn("search/artists", {"query": "Trending Artists"})
                artists_raw = artists_resp.get("data", {}).get("results", [])
                print("DEBUG: RAW TRENDING ARTIST DATA FALLBACK:", artists_raw[:2] if artists_raw else "EMPTY")

    # 3. Normalization Loops (Task 2)
    # Songs: {id, title, artist, coverUrl, audioUrl}
    recommended_for_you = []
    for s in songs_raw[:15]:
        recommended_for_you.append({
            "id": s.get("id"),
            "title": html.unescape(s.get("name") or s.get("title") or "Unknown"),
            "artist": html.unescape(s.get("primaryArtists") or s.get("artist") or "Various Artists"),
            "coverUrl": extract_high_res_image(s.get("image")),
            "audioUrl": extract_audio_url(s)
        })

    # Albums: {id, title, subtitle, image}
    top_albums = []
    for a in albums_raw[:15]:
        top_albums.append({
            "id": a.get("id"),
            "title": html.unescape(a.get("name") or a.get("title") or "Unknown Album"),
            "subtitle": html.unescape(a.get("primaryArtists") or a.get("artist") or a.get("subtitle") or "Artist"),
            "image": extract_high_res_image(a.get("image"))
        })

    # Artists: {id, name, image}
    top_artists = []
    # Use a set to avoid duplicates
    seen_artist_names = set()
    
    for art in artists_raw:
        # 🚨 BULLETPROOF EXTRACTION 🚨
        name = extract_artist_name(art)
        
        # Filter out generic or invalid entries
        if name == "Unknown Artist":
            continue
            
        if name in seen_artist_names:
            continue
            
        seen_artist_names.add(name)
        
        top_artists.append({
            "id": art.get("id"),
            "name": name,
            "image": extract_high_res_image(art) # Pass entire object to helper
        })
        
        if len(top_artists) >= 15:
            break
        
    # Task 1: Feed songs into the global recommendation graph
    try:
        if recommended_for_you:
            for song in recommended_for_you:
                recommendation_graph.add_song(song)
                
            # Create connections (Clique) for trending batch
            song_ids = [s['id'] for s in recommended_for_you]
            for i in range(len(song_ids)):
                for j in range(i + 1, len(song_ids)):
                    recommendation_graph.add_connection(song_ids[i], song_ids[j])
    except Exception as e:
        print(f"[GRAPH WARNING] Trending injection failed: {e}")

    return {
        "recommendedForYou": recommended_for_you,
        "topAlbums": top_albums,
        "topArtists": top_artists
    }

async def get_lyrics(song_id: str) -> Dict[str, Any]:
    """
    Fetches lyrics for a specific song ID.
    Endpoint: lyrics?id={song_id}
    """
    response = await fetch_from_saavn("songs/lyrics", {"id": song_id})
    return response.get("data", {})

async def get_song_details(song_id: str) -> Dict[str, Any]:
    """
    Fetches comprehensive details for a single song.
    """
    response = await fetch_from_saavn("songs", {"ids": song_id})
    data = response.get("data", [])
    if data and isinstance(data, list):
        return await map_saavn_song(data[0], lenient=True)
    return {}

async def get_related_songs(song_id: str, target_language: str = None, artist: str = None, historical_artists: List[str] = None) -> List[Dict[str, Any]]:
    """
    Robust related-songs builder that replaces the broken /suggestions endpoint.
    Retrieves tracks from the primary artist AND historical user favorite artists, 
    enforcing a strict language gate and applying a DJ shuffle for a personalized Radio Mix.
    """
    import random
    import asyncio
    try:
        print(f"[FETCHING RADIO MIX] Bypassing broken suggestions for {song_id}...")
        
        # Step 0: Fetch current song metadata to extract identifiers
        current_resp = await fetch_from_saavn("songs", {"ids": song_id})
        current_data_list = current_resp.get("data", [])
        if not current_data_list:
            return []
            
        current_song = current_data_list[0]
        
        # Task 2: Robust Fallback extraction prioritize provided artist
        extracted_artist = current_song.get("primaryArtists") or current_song.get("primary_artists") or current_song.get("artist") or current_song.get("singers") or "Unknown"
        primary_artist = artist or extracted_artist.split(",")[0].split("&")[0].strip()
        
        # Normalization gate preparation
        target_lang = str(target_language).lower().strip() if target_language else str(current_song.get("language")).lower().strip()

        print(f"[RECORDS FOUND] Artist: {primary_artist}, Historical Favorites: {historical_artists}, Lang: {target_lang}")

        # Step 1: Broad Search Batch (Current Artist + Historical Favorites)
        search_targets = [primary_artist] if primary_artist and primary_artist != "Unknown" else []
        if historical_artists:
            # Only blend in unique historical artists that aren't the primary artist
            for ha in historical_artists:
                if ha and ha.lower().strip() != primary_artist.lower().strip():
                    search_targets.append(ha)
        
        # Parallel search for all target artists to ensure zero-latency impact
        print(f"[RECORDS BATCH] Triggering {len(search_targets)} searches for blended Radio Mix...")
        search_tasks = [search_saavn(target) for target in search_targets]
        search_results_batch = await asyncio.gather(*search_tasks, return_exceptions=True)
        
        # Flatten candidates and filter out errors
        candidates = []
        for res in search_results_batch:
            if isinstance(res, list):
                candidates.extend(res)
        
        # Step 2: Strict Language Filtering Gate
        filtered_songs = []
        seen_ids = {song_id} # Exclude the current song

        for song in candidates:
            s_id = song.get("id")
            if s_id in seen_ids:
                continue
                
            # Perform strict language check
            song_lang = str(song.get("language") or "").lower().strip()
            
            # If language is missing, map it and drop if it's the wrong language
            if not song_lang:
                song_lang = target_lang

            if song_lang == target_lang:
                # Check if song is already mapped
                if "cover_url" in song or "audio_url" in song:
                    mapped = song
                else:
                    mapped = await map_saavn_song(song, lenient=True)

                if mapped and mapped.get("id") not in seen_ids:
                    # Final sanity check: Ensure at least one image key is present for React
                    if not mapped.get("cover_url") and not mapped.get("coverUrl") and not mapped.get("image"):
                         mapped["cover_url"] = extract_high_res_image(None) # Use central default
                    
                    filtered_songs.append(mapped)
                    seen_ids.add(mapped.get("id"))
        
        # Step 3: The DJ Shuffle
        random.shuffle(filtered_songs)
        
        print(f"[RADIO MIX COMPLETE] Generated {len(filtered_songs)} blended & shuffled results for {song_id}")
        # Return top 10/12 songs from this shuffled pool
        return filtered_songs[:12]

    except Exception as e:
        print(f"[CRITICAL ERROR] Radio Mix fetch failed: {str(e)}")
        return []

# Alias for backward compatibility
async def get_recommendations(song_id: str, target_language: str = None, artist: str = None, historical_artists: List[str] = None) -> List[Dict[str, Any]]:
    return await get_related_songs(song_id, target_language, artist, historical_artists)

async def search_all(query: str) -> Dict[str, Any]:
    """
    Global search for songs, artists, and albums. Used for suggestions.
    🚨 REPLACED search/all WITH search/songs to fix 404 errors. 🚨
    Parsing follows the search/songs response format: data.get('results', [])
    """
    response = await fetch_from_saavn("search/songs", {"query": query})
    data = response.get("data") or {}
    
    # Extract results as required: response.json().get('data', {}).get('results', [])
    # In our fetch utility, response.json() is already returned.
    results = data.get("results", [])
    
    # Map raw results for the frontend suggestions dropdown
    # The frontend expects { "songs": [...], "artists": [], "albums": [] }
    return {
        "songs": results[:10], # suggestions songs
        "artists": [],          # search/songs doesn't provide artists
        "albums": []            # search/songs doesn't provide albums
    }

async def search_artists(query: str, language: str = None) -> List[Dict[str, Any]]:
    """
    Search specifically for artists.
    Endpoint: search/artists?query={query}
    """
    params = {"query": query}
    if language:
        params["language"] = language
        
    response = await fetch_from_saavn("search/artists", params)
    data = response.get("data") or {}
    results = data.get("results", [])
    mapped_artists = []
    for item in results:
        mapped_artists.append({
            "id": item.get("id"),
            "name": html.unescape(str(item.get("name", ""))),
            "image": extract_high_res_image(item.get("image")),
            "type": "artist"
        })
    return mapped_artists

async def search_albums(query: str, language: str = None) -> List[Dict[str, Any]]:
    """
    Search specifically for albums.
    Endpoint: search/albums?query={query}
    """
    params = {"query": query}
    if language:
        params["language"] = language
        
    response = await fetch_from_saavn("search/albums", params)
    data = response.get("data") or {}
    results = data.get("results", [])
    mapped_albums = []
    for item in results:
        mapped_albums.append({
            "id": item.get("id"),
            "title": html.unescape(str(item.get("name", ""))),
            "artist": html.unescape(str(item.get("primaryArtists", ""))),
            "image": extract_high_res_image(item.get("image")),
            "year": item.get("year"),
            "type": "album"
        })
    return mapped_albums

async def get_artist_details(artist_id: str) -> Dict[str, Any]:
    """
    Fetches artist details and top songs.
    Endpoint: artists?id={artist_id}
    """
    response = await fetch_from_saavn("artists", {"id": artist_id})
    data = response.get("data", {})
    
    if not data:
        return {"name": "Unknown Artist", "image": "", "topSongs": []}

    # Extract image
    image_url = extract_high_res_image(data.get("image"))

    # Extract and map top songs
    top_songs_raw = data.get("topSongs", [])
    mapped_songs = []
    for item in top_songs_raw:
        mapped = await map_saavn_song(item, lenient=False)
        if mapped:
            mapped_songs.append(mapped)

    return {
        "id": data.get("id"),
        "name": html.unescape(str(data.get("name", "Unknown Artist"))),
        "image": image_url,
        "topSongs": mapped_songs
    }

async def get_personalized_feed(artist_names: List[str]) -> List[Dict[str, Any]]:
    """
    Fetches top tracks for each artist in artist_names and returns a shuffled mix.
    """
    import random
    seen_ids = set()
    unique_tracks = []
    
    for artist in artist_names:
        try:
            # Search for the artist's songs
            artist_songs = await search_saavn(artist)
            if artist_songs:
                # Take up to 10 songs per artist to ensure variety
                for song in artist_songs[:10]:
                    if song['id'] not in seen_ids:
                        unique_tracks.append(song)
                        seen_ids.add(song['id'])
        except Exception as e:
            print(f"[WARNING] Error fetching tracks for {artist}: {str(e)}")
            continue
            
    # Shuffle for freshness
    random.shuffle(unique_tracks)
    
    # Limit total results
    return unique_tracks[:30]

@async_ttl_cache(ttl_seconds=86400)
async def get_album_details(album_id: str) -> Dict[str, Any]:
    """
    Fetches the full details and tracklist of a specific album from JioSaavn.
    """
    response = await fetch_from_saavn("albums", {"id": album_id})
    data = response.get("data", {})

    if not data:
        return {}

    # Extract cover art and map songs
    cover_url = extract_high_res_image(data.get("image"))
    raw_songs = data.get("songs", [])
    mapped_songs = []
    for song in raw_songs:
        # Use existing mapper with lenient mode to ensure we get as many playable tracks as possible
        mapped = await map_saavn_song(song, lenient=True)
        if mapped:
            mapped_songs.append(mapped)

    # Task 1: Feed album songs into the global recommendation graph
    try:
        if mapped_songs:
            for song in mapped_songs:
                recommendation_graph.add_song(song)
            
            # Create connections (Clique) for all songs in the same album
            song_ids = [s['id'] for s in mapped_songs]
            for i in range(len(song_ids)):
                for j in range(i + 1, len(song_ids)):
                    recommendation_graph.add_connection(song_ids[i], song_ids[j])
    except Exception as e:
        print(f"[GRAPH WARNING] Album injection failed: {e}")

    return {
        "id": data.get("id"),
        "title": html.unescape(data.get("name", "Unknown Album")),
        "artist": html.unescape(data.get("primaryArtists", "Various Artists")),
        "image": cover_url,
        "songs": mapped_songs
    }
