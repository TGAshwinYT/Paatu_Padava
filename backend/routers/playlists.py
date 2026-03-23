from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import delete
from connection import get_db
from models import Playlist, PlaylistTrack, User
from auth_utils import get_current_user
from typing import List, Optional
from pydantic import BaseModel
import uuid

router = APIRouter(prefix="/api/playlists", tags=["playlists"])

class PlaylistCreate(BaseModel):
    title: str
    is_public: bool = False

class PlaylistUpdate(BaseModel):
    title: str

class TrackAdd(BaseModel):
    jiosaavn_song_id: str

@router.get("/")
async def get_playlists(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Get all playlists owned by the current user.
    """
    result = await db.execute(select(Playlist).where(Playlist.user_id == user.id))
    return result.scalars().all()

@router.post("/")
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
            PlaylistTrack.jiosaavn_song_id == data.jiosaavn_song_id
        )
    )
    if check_exists.scalars().first():
        return {"message": "Song already in playlist"}

    new_track = PlaylistTrack(
        playlist_id=playlist_uuid,
        jiosaavn_song_id=data.jiosaavn_song_id
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
        PlaylistTrack.jiosaavn_song_id == song_id
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
    Get a playlist with its songs.
    """
    try:
        playlist_uuid = uuid.UUID(playlist_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid playlist ID format")

    result = await db.execute(select(Playlist).where(Playlist.id == playlist_uuid, Playlist.user_id == user.id))
    playlist = result.scalars().first()
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")
        
    return playlist
