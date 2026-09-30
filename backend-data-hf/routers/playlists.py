from fastapi import APIRouter, HTTPException, status, Depends
from typing import Optional, List, Dict, Any
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete, func
from sqlalchemy.orm import selectinload
import uuid
import models
from connection import get_db
from auth_utils import get_current_user, get_current_user_optional
from services.spotify_import import (
    parse_spotify_playlist_id,
    fetch_spotify_playlist_metadata,
    resolve_spotify_tracks_batch,
)

router = APIRouter(prefix="/api/playlists", tags=["playlists"])

class CreatePlaylistRequest(BaseModel):
    title: str
    description: Optional[str] = ""
    is_public: Optional[bool] = False
    cover_url: Optional[str] = ""

class UpdatePlaylistRequest(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    is_public: Optional[bool] = None
    cover_url: Optional[str] = None

class AddSongRequest(BaseModel):
    id: str
    title: str
    artist: str
    album: Optional[str] = ""
    coverUrl: Optional[str] = ""
    streamUrl: Optional[str] = ""
    source: Optional[str] = "saavn"
    duration: Optional[int] = 0

class SpotifyPreviewRequest(BaseModel):
    url: str

class SpotifyImportRequest(BaseModel):
    url: str
    custom_title: Optional[str] = None

@router.get("/")
async def get_user_playlists(
    user: models.User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = (
        select(models.Playlist)
        .where(models.Playlist.user_id == user.id)
        .options(selectinload(models.Playlist.tracks))
        .order_by(models.Playlist.created_at.desc())
    )
    result = await db.execute(stmt)
    playlists = result.scalars().all()
    return [
        {
            "id": str(p.id),
            "title": p.title,
            "description": p.description,
            "cover_url": p.cover_url,
            "is_public": p.is_public,
            "created_at": p.created_at.isoformat() if p.created_at else None,
            "track_count": len(p.tracks),
            "tracks": [
                {
                    "id": t.track_id,
                    "title": t.title,
                    "artist": t.artist,
                    "album": t.album,
                    "coverUrl": t.artwork_url,
                    "streamUrl": t.stream_url,
                    "source": t.source_type,
                    "duration": t.duration,
                    "position": t.position,
                }
                for t in p.tracks
            ],
        }
        for p in playlists
    ]

@router.post("/")
async def create_user_playlist(
    data: CreatePlaylistRequest,
    user: models.User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    clean_title = data.title.strip() if data.title else "My Playlist"
    if not clean_title:
        clean_title = "My Playlist"

    # Idempotency check: reuse existing playlist with same title if present
    stmt = select(models.Playlist).where(
        models.Playlist.user_id == user.id,
        func.lower(func.trim(models.Playlist.title)) == clean_title.lower()
    ).options(selectinload(models.Playlist.tracks))
    result = await db.execute(stmt)
    existing = result.scalar_one_or_none()

    if existing:
        return {
            "id": str(existing.id),
            "title": existing.title,
            "description": existing.description,
            "cover_url": existing.cover_url,
            "is_public": existing.is_public,
            "track_count": len(existing.tracks),
            "reused": True,
        }

    playlist = models.Playlist(
        user_id=user.id,
        title=clean_title,
        description=data.description or "",
        cover_url=data.cover_url or "",
        is_public=data.is_public or False,
    )
    db.add(playlist)
    await db.commit()
    await db.refresh(playlist)

    return {
        "id": str(playlist.id),
        "title": playlist.title,
        "description": playlist.description,
        "cover_url": playlist.cover_url,
        "is_public": playlist.is_public,
        "track_count": 0,
        "reused": False,
    }

@router.get("/{playlist_id}")
async def get_playlist_by_id(
    playlist_id: str,
    user: Optional[models.User] = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db)
):
    try:
        pl_uuid = uuid.UUID(playlist_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid playlist UUID format")

    stmt = select(models.Playlist).where(models.Playlist.id == pl_uuid).options(selectinload(models.Playlist.tracks))
    result = await db.execute(stmt)
    playlist = result.scalar_one_or_none()

    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")

    if not playlist.is_public and (not user or user.id != playlist.user_id):
        raise HTTPException(status_code=403, detail="You do not have permission to view this playlist")

    return {
        "id": str(playlist.id),
        "title": playlist.title,
        "description": playlist.description,
        "cover_url": playlist.cover_url,
        "is_public": playlist.is_public,
        "created_at": playlist.created_at.isoformat() if playlist.created_at else None,
        "tracks": [
            {
                "id": t.track_id,
                "title": t.title,
                "artist": t.artist,
                "album": t.album,
                "coverUrl": t.artwork_url,
                "streamUrl": t.stream_url,
                "source": t.source_type,
                "duration": t.duration,
                "position": t.position,
            }
            for t in playlist.tracks
        ],
    }

@router.patch("/{playlist_id}")
async def update_playlist(
    playlist_id: str,
    data: UpdatePlaylistRequest,
    user: models.User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    try:
        pl_uuid = uuid.UUID(playlist_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid playlist UUID format")

    stmt = select(models.Playlist).where(models.Playlist.id == pl_uuid, models.Playlist.user_id == user.id)
    result = await db.execute(stmt)
    playlist = result.scalar_one_or_none()

    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")

    if data.title is not None and data.title.strip():
        playlist.title = data.title.strip()
    if data.description is not None:
        playlist.description = data.description
    if data.cover_url is not None:
        playlist.cover_url = data.cover_url
    if data.is_public is not None:
        playlist.is_public = data.is_public

    await db.commit()
    await db.refresh(playlist)
    return {"success": True, "id": str(playlist.id), "title": playlist.title}

@router.delete("/{playlist_id}")
async def delete_playlist(
    playlist_id: str,
    user: models.User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    try:
        pl_uuid = uuid.UUID(playlist_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid playlist UUID format")

    stmt = select(models.Playlist).where(models.Playlist.id == pl_uuid, models.Playlist.user_id == user.id)
    result = await db.execute(stmt)
    playlist = result.scalar_one_or_none()

    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")

    await db.delete(playlist)
    await db.commit()
    return {"success": True, "message": "Playlist deleted successfully"}

@router.post("/{playlist_id}/songs")
async def add_song_to_playlist(
    playlist_id: str,
    data: AddSongRequest,
    user: models.User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    try:
        pl_uuid = uuid.UUID(playlist_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid playlist UUID format")

    stmt = select(models.Playlist).where(models.Playlist.id == pl_uuid, models.Playlist.user_id == user.id).options(selectinload(models.Playlist.tracks))
    result = await db.execute(stmt)
    playlist = result.scalar_one_or_none()

    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")

    # Prevent duplicates within playlist
    if any(t.track_id == data.id for t in playlist.tracks):
        return {"success": False, "message": "Song already exists in playlist"}

    position = len(playlist.tracks)
    track = models.PlaylistTrack(
        playlist_id=playlist.id,
        track_id=data.id,
        title=data.title,
        artist=data.artist,
        album=data.album or "",
        artwork_url=data.coverUrl or "",
        stream_url=data.streamUrl or "",
        source_type=data.source or "saavn",
        duration=data.duration or 0,
        position=position,
    )
    db.add(track)

    if not playlist.cover_url and data.coverUrl:
        playlist.cover_url = data.coverUrl

    await db.commit()
    return {"success": True, "message": "Song added to playlist"}

@router.delete("/{playlist_id}/songs/{song_id}")
async def remove_song_from_playlist(
    playlist_id: str,
    song_id: str,
    user: models.User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    try:
        pl_uuid = uuid.UUID(playlist_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid playlist UUID format")

    stmt = select(models.Playlist).where(models.Playlist.id == pl_uuid, models.Playlist.user_id == user.id)
    result = await db.execute(stmt)
    playlist = result.scalar_one_or_none()

    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")

    del_stmt = delete(models.PlaylistTrack).where(
        models.PlaylistTrack.playlist_id == playlist.id,
        models.PlaylistTrack.track_id == song_id
    )
    await db.execute(del_stmt)
    await db.commit()
    return {"success": True, "message": "Song removed from playlist"}

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
