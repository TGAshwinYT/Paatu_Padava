from fastapi import APIRouter, HTTPException, status
from typing import Optional, List
from pydantic import BaseModel
from services.spotify_import import (
    parse_spotify_playlist_id,
    fetch_spotify_playlist_metadata,
    resolve_spotify_tracks_batch,
)

router = APIRouter(prefix="/api/playlists", tags=["playlists"])

class SpotifyPreviewRequest(BaseModel):
    url: str

class SpotifyImportRequest(BaseModel):
    url: str
    custom_title: Optional[str] = None

@router.post("/preview-spotify")
async def preview_spotify_playlist(data: SpotifyPreviewRequest):
    """
    Extracts metadata, cover image, and track count from a Spotify playlist link.
    Works for both logged in users and guests.
    """
    spotify_id = await parse_spotify_playlist_id(data.url)
    if not spotify_id:
        raise HTTPException(
            status_code=400,
            detail="Invalid Spotify link. Format: https://open.spotify.com/playlist/{id} or /album/{id}",
        )

    try:
        metadata = await fetch_spotify_playlist_metadata(spotify_id, raw_url=data.url)
        return {
            "spotify_id": metadata["spotify_id"],
            "title": metadata["title"],
            "description": metadata["description"],
            "cover_url": metadata["cover_url"],
            "thumbnail": metadata["cover_url"],
            "total_tracks": metadata["total_tracks"],
            "track_count": metadata["total_tracks"],
            "sample_tracks": metadata["tracks"][:6],
            "tracks": metadata["tracks"],
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch Spotify playlist: {str(e)}")

@router.post("/import-spotify")
async def import_spotify_playlist(data: SpotifyImportRequest):
    """
    Imports a Spotify playlist by resolving tracks to the Paatu Padava catalog (via Saavn/YouTube).
    Returns complete list of resolved playable tracks for immediate client playback and Supabase cloud saving.
    """
    spotify_id = await parse_spotify_playlist_id(data.url)
    if not spotify_id:
        raise HTTPException(status_code=400, detail="Invalid Spotify playlist or album link")

    try:
        metadata = await fetch_spotify_playlist_metadata(spotify_id, raw_url=data.url)
        tracks_to_import = metadata.get("tracks", [])
        if not tracks_to_import:
            raise HTTPException(status_code=400, detail="The Spotify playlist contains no tracks.")

        # Asynchronously resolve tracks
        resolved_tracks = await resolve_spotify_tracks_batch(tracks_to_import, max_tracks=75)
        playlist_title = (data.custom_title or metadata.get("title") or "Imported Spotify Playlist").strip()

        return {
            "success": True,
            "title": playlist_title,
            "cover_url": metadata.get("cover_url"),
            "imported_count": len(resolved_tracks),
            "total_spotify_tracks": metadata.get("total_tracks", 0),
            "tracks": resolved_tracks,
            "songs": resolved_tracks,
        }

    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Import failed: {str(e)}")
