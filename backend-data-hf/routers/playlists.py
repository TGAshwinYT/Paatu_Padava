from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import delete
from connection import get_db
from models import Playlist, PlaylistTrack, User
from auth_utils import get_current_user, get_current_user_optional
from typing import List, Optional
from pydantic import BaseModel
import uuid
from services.spotify_import import (
    parse_spotify_playlist_id,
    fetch_spotify_playlist_metadata,
    resolve_spotify_tracks_batch
)

router = APIRouter(prefix="/api/playlists", tags=["playlists"])

class PlaylistCreate(BaseModel):
    title: str
    is_public: bool = False
    cover_url: Optional[str] = None
    description: Optional[str] = None

class PlaylistUpdate(BaseModel):
    title: str

class TrackAdd(BaseModel):
    yt_video_id: str
    title: Optional[str] = None
    artist: Optional[str] = None
    cover_url: Optional[str] = None
    duration: Optional[int] = None

class SpotifyPreviewRequest(BaseModel):
    url: str

class SpotifyImportRequest(BaseModel):
    url: str
    custom_title: Optional[str] = None

@router.get("/")
@router.get("")
async def get_playlists(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Get all playlists owned by the current user.
    """
    result = await db.execute(select(Playlist).where(Playlist.user_id == user.id))
    return result.scalars().all()

@router.post("/")
@router.post("")
async def create_playlist(data: PlaylistCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Create a new custom playlist.
    """
    new_playlist = Playlist(
        title=data.title,
        is_public=data.is_public,
        user_id=user.id
    )
    db.add(new_playlist)
    await db.commit()
    await db.refresh(new_playlist)
    return new_playlist

@router.post("/{playlist_id}/songs")
async def add_song_to_playlist(playlist_id: str, data: TrackAdd, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Add a song to a specific playlist.
    """
    try:
        playlist_uuid = uuid.UUID(playlist_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid playlist ID format")

    result = await db.execute(select(Playlist).where(Playlist.id == playlist_uuid, Playlist.user_id == user.id))
    playlist = result.scalars().first()
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found or unauthorized")
        
    # Check if already exists (Composite PK will handle this but error handling is better)
    check_exists = await db.execute(
        select(PlaylistTrack).where(
            PlaylistTrack.playlist_id == playlist_uuid, 
            PlaylistTrack.yt_video_id == data.yt_video_id
        )
    )
    if check_exists.scalars().first():
        return {"message": "Song already in playlist"}

    new_track = PlaylistTrack(
        playlist_id=playlist_uuid,
        yt_video_id=data.yt_video_id
    )
    db.add(new_track)
    await db.commit()
    return {"message": "Song added to playlist"}

@router.post("/{playlist_id}/add-song")
async def add_song_to_playlist_alias(playlist_id: str, data: TrackAdd, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Alias for song addition (requested in Task 4).
    """
    return await add_song_to_playlist(playlist_id, data, user, db)

@router.delete("/{playlist_id}/songs/{song_id}")
async def remove_song_from_playlist(playlist_id: str, song_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Remove a song from a specific playlist.
    """
    try:
        playlist_uuid = uuid.UUID(playlist_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid playlist ID format")

    # Verify ownership
    result = await db.execute(select(Playlist).where(Playlist.id == playlist_uuid, Playlist.user_id == user.id))
    playlist = result.scalars().first()
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found or unauthorized")

    # Delete the track record
    delete_query = delete(PlaylistTrack).where(
        PlaylistTrack.playlist_id == playlist_uuid,
        PlaylistTrack.yt_video_id == song_id
    )
    await db.execute(delete_query)
    await db.commit()
    return {"message": "Song removed from playlist"}

@router.patch("/{playlist_id}")
async def rename_playlist(playlist_id: str, data: PlaylistUpdate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Rename a specific playlist.
    """
    try:
        playlist_uuid = uuid.UUID(playlist_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid playlist ID format")

    result = await db.execute(select(Playlist).where(Playlist.id == playlist_uuid, Playlist.user_id == user.id))
    playlist = result.scalars().first()
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found or unauthorized")
    
    playlist.title = data.title
    await db.commit()
    await db.refresh(playlist)
    return playlist

@router.delete("/{playlist_id}")
async def delete_playlist(playlist_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Delete a specific playlist and its associations.
    """
    try:
        playlist_uuid = uuid.UUID(playlist_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid playlist ID format")

    result = await db.execute(select(Playlist).where(Playlist.id == playlist_uuid, Playlist.user_id == user.id))
    playlist = result.scalars().first()
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found or unauthorized")
    
    # 1. Delete associated tracks first
    await db.execute(delete(PlaylistTrack).where(PlaylistTrack.playlist_id == playlist_uuid))
    
    # 2. Delete the playlist itself
    await db.execute(delete(Playlist).where(Playlist.id == playlist_uuid))
    
    await db.commit()
    return {"message": "Playlist deleted successfully"}

@router.get("/{playlist_id}")
async def get_playlist_detail(playlist_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Get full playlist details including tracks with metadata.
    """
    try:
        playlist_uuid = uuid.UUID(playlist_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid playlist ID format")

    result = await db.execute(select(Playlist).where(Playlist.id == playlist_uuid, Playlist.user_id == user.id))
    playlist = result.scalars().first()
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")
        
    # Fetch all tracks for this playlist ordered by added_at
    tracks_result = await db.execute(
        select(PlaylistTrack).where(PlaylistTrack.playlist_id == playlist_uuid).order_by(PlaylistTrack.added_at.asc())
    )
    raw_tracks = tracks_result.scalars().all()
    tracks = [{
        "id": t.yt_video_id,
        "title": t.title or "Unknown Title",
        "artist": t.artist or "Unknown Artist",
        "coverUrl": t.cover_url or "",
        "cover_url": t.cover_url or "",
        "duration": t.duration or 0,
        "added_at": t.added_at
    } for t in raw_tracks]

    return {
        "id": str(playlist.id),
        "title": playlist.title,
        "description": playlist.description,
        "cover_url": playlist.cover_url,
        "is_public": playlist.is_public,
        "created_at": playlist.created_at,
        "tracks": tracks
    }

@router.get("/{playlist_id}/tracks")
async def get_playlist_tracks(
    playlist_id: str, 
    limit: int = 50, 
    offset: int = 0, 
    user: User = Depends(get_current_user), 
    db: AsyncSession = Depends(get_db)
):
    """
    Get paginated tracks for a specific playlist with complete metadata.
    """
    try:
        playlist_uuid = uuid.UUID(playlist_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid playlist ID format")

    # Verify ownership
    result = await db.execute(select(Playlist).where(Playlist.id == playlist_uuid, Playlist.user_id == user.id))
    if not result.scalars().first():
        raise HTTPException(status_code=404, detail="Playlist not found or unauthorized")

    # Fetch paginated tracks
    query = select(PlaylistTrack).where(PlaylistTrack.playlist_id == playlist_uuid).order_by(PlaylistTrack.added_at.asc()).limit(limit).offset(offset)
    result = await db.execute(query)
    tracks = result.scalars().all()
    
    return [{
        "id": t.yt_video_id,
        "title": t.title or "Unknown Title",
        "artist": t.artist or "Unknown Artist",
        "coverUrl": t.cover_url or "",
        "cover_url": t.cover_url or "",
        "duration": t.duration or 0,
        "added_at": t.added_at
    } for t in tracks]


@router.post("/preview-spotify")
async def preview_spotify_playlist(
    data: SpotifyPreviewRequest,
    user: Optional[User] = Depends(get_current_user_optional)
):
    """
    Extracts metadata, cover image, and track count from a Spotify playlist link.
    Works for both logged in users and guests.
    """
    spotify_id = await parse_spotify_playlist_id(data.url)
    if not spotify_id:
        raise HTTPException(status_code=400, detail="Invalid Spotify link. Format: https://open.spotify.com/playlist/{id} or /album/{id}")

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
            "tracks": metadata["tracks"]
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch Spotify playlist: {str(e)}")


@router.post("/import-spotify")
async def import_spotify_playlist(
    data: SpotifyImportRequest,
    user: Optional[User] = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db)
):
    """
    Imports a Spotify playlist directly into the user's Paatu Padava library:
    1. Extracts playlist metadata & track list from Spotify
    2. Resolves each track to Paatu Padava catalog (via Saavn/YouTube)
    3. Creates playlist in database if user is authenticated
    4. Returns complete list of resolved playable tracks for immediate client playback
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

        playlist_id_str = ""
        playlist_title = (data.custom_title or metadata.get("title") or "Imported Spotify Playlist").strip()

        # If user is authenticated, save playlist in DB
        if user:
            new_playlist = Playlist(
                user_id=user.id,
                title=playlist_title,
                description=metadata.get("description") or f"Imported from Spotify ({metadata.get('total_tracks')} tracks)",
                cover_url=metadata.get("cover_url"),
                is_public=False
            )
            db.add(new_playlist)
            await db.commit()
            await db.refresh(new_playlist)
            playlist_id_str = str(new_playlist.id)

            for item in resolved_tracks:
                track_record = PlaylistTrack(
                    playlist_id=new_playlist.id,
                    yt_video_id=item.get("yt_video_id") or item.get("id", ""),
                    title=item.get("title"),
                    artist=item.get("artist"),
                    cover_url=item.get("cover_url"),
                    duration=item.get("duration", 0)
                )
                db.add(track_record)

            await db.commit()

        return {
            "success": True,
            "playlist_id": playlist_id_str,
            "title": playlist_title,
            "cover_url": metadata.get("cover_url"),
            "imported_count": len(resolved_tracks),
            "total_spotify_tracks": metadata.get("total_tracks", 0),
            "tracks": resolved_tracks,
            "songs": resolved_tracks
        }

    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        if user:
            await db.rollback()
        raise HTTPException(status_code=500, detail=f"Import failed: {str(e)}")
