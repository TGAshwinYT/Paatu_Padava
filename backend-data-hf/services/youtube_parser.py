import logging

logger = logging.getLogger(__name__)


def safe_get(obj, key, default=None):
    """
    Safely extract data from YTMusic API responses which can be either a dict or a list.
    """
    if isinstance(obj, dict):
        val = obj.get(key)
        if val is not None:
            return val
    elif isinstance(obj, list):
        for shelf in obj:
            if isinstance(shelf, dict):
                title = shelf.get("title", "").lower()
                if key.lower() in title:
                    return shelf.get("contents") or shelf.get("items")
                if key in shelf:
                    return shelf[key]
    return default


def map_youtube_song(result):
    """
    Maps YTMusic search results to our internal Song format.
    """
    try:
        artists = result.get("artists", [])
        if artists:
            if isinstance(artists[0], dict):
                artist_name = ", ".join([a.get("name", "Unknown") for a in artists])
            else:
                artist_name = str(artists[0])
        else:
            artist_name = result.get("author", "Unknown Artist")

        thumbnails = result.get("thumbnails") or result.get("thumbnail") or []
        cover_url = thumbnails[-1].get("url") if thumbnails else ""

        duration = result.get("duration_seconds")
        if duration is None:
            duration_str = result.get("duration")
            if duration_str and ":" in duration_str:
                parts = duration_str.split(":")
                try:
                    if len(parts) == 2:
                        duration = int(parts[0]) * 60 + int(parts[1])
                    elif len(parts) == 3:
                        duration = int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
                except Exception:
                    duration = 0
            else:
                duration = 0

        album_data = result.get("album", "")
        if isinstance(album_data, dict):
            album_name = album_data.get("name", "")
        else:
            album_name = str(album_data)

        return {
            "id": result.get("videoId"),
            "title": result.get("title"),
            "artist": artist_name,
            "coverUrl": cover_url,
            "cover_url": cover_url,
            "image": cover_url,
            "audioUrl": "",
            "duration": duration,
            "album": album_name,
            "isManual": False,
        }
    except Exception as e:
        logger.error("Error mapping YTMusic result: %s", e)
        return None
