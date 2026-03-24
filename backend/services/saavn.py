import httpx
import os
import json
import html
from typing import List, Dict, Any, Optional

# Primary API instance
SAAVN_API_URL = "https://saavn.sumit.co/api"

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
        # 1. Images are a list of {quality: str, url: str}
        images = item.get("image", [])
        cover_url = ""
        if isinstance(images, list) and len(images) > 0:
            cover_url = images[-1].get("url", "")
        elif isinstance(images, str):
            cover_url = images

        # 2. Download links are a list of {quality: str, url: str}
        downloads = item.get("downloadUrl", [])
        audio_url = ""
        
        if isinstance(downloads, list) and len(downloads) > 0:
            if len(downloads) > 4:
                audio_url = downloads[4].get("url", "")
            
            if not audio_url:
                audio_url = downloads[-1].get("url", "")

        # Universal Mapping Fallback (Task 1)
        if not audio_url:
            audio_url = item.get("url") or item.get("link")
            # If we found a direct URL, create a mock downloads structure for consistency
            if audio_url and not downloads:
                downloads = [{"quality": "320kbps", "url": audio_url}]

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

async def search_saavn(query: str) -> List[Dict[str, Any]]:
    """
    Official Search implementation. Strictly returns playable tracks.
    """
    response = await fetch_from_saavn("search/songs", {"query": query})
    results = response.get("data", {}).get("results", [])
    
    print(f"🔎 DEBUG: Found {len(results)} items in API results for '{query}'")
    
    mapped_songs = []
    for item in results:
        mapped = await map_saavn_song(item, lenient=False)
        if mapped and mapped.get("audio_url"):
            mapped_songs.append(mapped)
            
    return mapped_songs

async def get_trending() -> Dict[str, List[Dict[str, Any]]]:
    """
    Fetches trending modules for the home screen.
    Includes a robust fallback that uses search results if the 'modules' endpoint fails.
    """
    trending_raw = []
    albums_raw = []
    
    try:
        response = await fetch_from_saavn("modules", {"language": "hindi,english"})
        data = response.get("data", {})
        
        if data:
            if isinstance(data.get("trending"), dict):
                trending_raw = data["trending"].get("songs", [])
            elif isinstance(data.get("charts"), list):
                trending_raw = data["charts"]
            
            if isinstance(data.get("albums"), (list, dict)):
                albums_raw = data["albums"]
                if isinstance(albums_raw, dict):
                    albums_raw = albums_raw.get("results", [])
    except Exception as e:
        print(f"Primary modules endpoint failed: {str(e)}")

    # FALLBACK: If primary failed or returned nothing, use search to populate the UI
    if not trending_raw or not albums_raw:
        print("Using search-based fallback for home feed...")
        if not trending_raw:
            trending_raw = await search_saavn("Trending 2026")
        if not albums_raw:
            albums_raw = await search_saavn("Pop Hits")

    seen_ids = set()
    recently_played = []
    for s in (trending_raw or []):
        if len(recently_played) >= 12: break
        # item might already be mapped if coming from search_saavn
        m = await map_saavn_song(s, lenient=True) if isinstance(s, dict) and 'id' in s and 'title' not in s else s
        if m and m.get('id') not in seen_ids:
            recently_played.append(m)
            seen_ids.add(m['id'])
        
    top_artists = []
    for a in (albums_raw or []):
        if len(top_artists) >= 12: break
        m = await map_saavn_song(a, lenient=True) if isinstance(a, dict) and 'id' in a and 'title' not in a else a
        if m and m.get('id') not in seen_ids:
            top_artists.append(m)
            seen_ids.add(m['id'])
        
    return {
        "recentlyPlayed": recently_played,
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
    response = await fetch_from_saavn("songs", {"id": song_id})
    data = response.get("data", [])
    if data and isinstance(data, list):
        return await map_saavn_song(data[0], lenient=True)
    return {}

async def get_related_songs(song_id: str) -> List[Dict[str, Any]]:
    """
    Refined fetch for related songs using official JioSaavn API.
    Uses web6dot0 context and a browser User-Agent to avoid empty responses.
    """
    url = f"https://www.jiosaavn.com/api.php?__call=reco.getreco&api_version=4&_format=json&_marker=0&ctx=web6dot0&pid={song_id}"
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json",
        "Referer": "https://www.jiosaavn.com/"
    }
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(url, headers=headers, timeout=10.0)
            response.raise_for_status()
            
            try:
                data = response.json()
            except ValueError:
                print(f"❌ Failed to parse JSON from JioSaavn for {song_id}")
                return []

            # Task 2: Safe JSON Extraction
            # JioSaavn sometimes returns a list directly, sometimes a dict with 'results'
            raw_songs = []
            if isinstance(data, list):
                raw_songs = data
            elif isinstance(data, dict):
                raw_songs = data.get("results", [])
                # Fallback: some responses have the list at the top level even if it's a dict
                if not raw_songs and not any(k in data for k in ["song", "title"]):
                    # If it's a dict but doesn't look like a single song, maybe it's just a dict of songs?
                    # But usually, it's in 'results'.
                    pass
            
            mapped_songs = []
            for s in raw_songs:
                # Task 3: Data Mapping and High-Quality Images (500x500)
                image_url = s.get("image", "")
                if image_url:
                    image_url = image_url.replace("150x150", "500x500").replace("50x50", "500x500")

                # The user requested specific keys: id, title, artist, coverUrl, audioUrl
                mapped = {
                    "id": s.get("id"),
                    "title": html.unescape(str(s.get("song") or s.get("title") or "Unknown")),
                    "artist": html.unescape(str(s.get("subtitle") or s.get("singers") or s.get("primary_artists") or "Unknown")),
                    "coverUrl": image_url,
                    "audioUrl": s.get("media_url") or s.get("url") or s.get("perma_url") or "",
                    "duration": int(s.get("duration", 0))
                }
                
                if mapped["id"] and mapped["title"]:
                    mapped_songs.append(mapped)

            # Fallback if no results
            if not mapped_songs:
                print(f"⚠️ No related songs found for {song_id} via official API. Trying internal fallback...")
                details = await get_song_details(song_id)
                artist_name = details.get("artist")
                if artist_name and artist_name != "Unknown Artist":
                    artist_results = await search_saavn(artist_name)
                    # Standardize search results to match the requested format
                    for s in artist_results:
                        mapped_songs.append({
                            "id": s.get("id"),
                            "title": s.get("title"),
                            "artist": s.get("artist"),
                            "coverUrl": s.get("cover_url"),
                            "audioUrl": s.get("audio_url"),
                            "duration": s.get("duration")
                        })
            
            return mapped_songs

    except Exception as e:
        print(f"❌ Refined get_related_songs failed: {str(e)}")
        return []

# Alias for backward compatibility if needed
async def get_recommendations(song_id: str) -> List[Dict[str, Any]]:
    return await get_related_songs(song_id)

async def search_all(query: str) -> Dict[str, Any]:
    """
    Global search for songs, artists, and albums. Used for suggestions.
    Endpoint: search/all?query={query}
    """
    response = await fetch_from_saavn("search/all", {"query": query})
    data = response.get("data", {})
    
    # We want to return a simplified structure for the dropdown
    return {
        "songs": data.get("songs", {}).get("results", [])[:5],
        "artists": data.get("artists", {}).get("results", [])[:3],
        "albums": data.get("albums", {}).get("results", [])[:3]
    }

async def search_artists(query: str) -> List[Dict[str, Any]]:
    """
    Search specifically for artists.
    Endpoint: search/artists?query={query}
    """
    response = await fetch_from_saavn("search/artists", {"query": query})
    results = response.get("data", {}).get("results", [])
    
    mapped_artists = []
    for item in results:
        # Extract the highest quality image
        images = item.get("image", [])
        image_url = ""
        if isinstance(images, list) and len(images) > 0:
            image_url = images[-1].get("url", "")
        elif isinstance(images, str):
            image_url = images
            
        mapped_artists.append({
            "id": item.get("id"),
            "name": html.unescape(str(item.get("name", ""))),
            "imageUrl": image_url
        })
    return mapped_artists

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
    images = data.get("image", [])
    image_url = ""
    if isinstance(images, list) and len(images) > 0:
        image_url = images[-1].get("url", "")
    elif isinstance(images, str):
        image_url = images

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
            print(f"⚠️ Error fetching tracks for {artist}: {str(e)}")
            continue
            
    # Shuffle for freshness
    random.shuffle(unique_tracks)
    
    # Limit total results
    return unique_tracks[:30]
