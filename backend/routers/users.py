from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload
from connection import get_db
import models
from models import User, LikedSong, Playlist, PlaylistTrack
from auth_utils import get_current_user
import json
from typing import List
import asyncio
import requests

router = APIRouter(prefix="/api/users", tags=["users"])


@router.get("/export")
async def export_data(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Exports all user data (Liked Songs and Playlists) as a JSON object.
    """
    # Load user with relationships
    result = await db.execute(
        select(User)
        .options(
            selectinload(User.liked_songs),
            selectinload(User.playlists).selectinload(Playlist.tracks)
        )
        .where(User.id == user.id)
    )
    db_user = result.scalar_one()

    data = {
        "username": db_user.username,
        "email": db_user.email,
        "liked_songs": [
            {
                "id": s.yt_video_id,
                "title": s.title,
                "artist": s.artist,
                "cover_url": s.cover_url,
                "audio_url": s.audio_url
            } for s in db_user.liked_songs
        ],
        "playlists": [
            {
                "title": p.title,
                "is_public": p.is_public,
                "tracks": [t.yt_video_id for t in p.tracks]
            } for p in db_user.playlists
        ]
    }
    return data

@router.post("/import")
async def import_data(file: UploadFile = File(...), user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Imports Liked Songs and Playlists from a JSON file, merging with existing data.
    """
    try:
        contents = await file.read()
        data = json.loads(contents)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON file")

    # 1. Import Liked Songs
    imported_count = 0
    if "liked_songs" in data:
        # Get existing song IDs to avoid duplicates
        result = await db.execute(select(LikedSong.yt_video_id).where(LikedSong.user_id == user.id))
        existing_ids = set(result.scalars().all())

        for song in data["liked_songs"]:
            song_id = song.get("yt_video_id") or song.get("song_id") or song.get("id")
            if song_id and song_id not in existing_ids:
                new_liked = LikedSong(
                    user_id=user.id,
                    yt_video_id=song_id,
                    title=song["title"],
                    artist=song["artist"],
                    cover_url=song.get("cover_url"),
                    audio_url=song.get("audio_url")
                )
                db.add(new_liked)
                existing_ids.add(song_id)
                imported_count += 1

    # 2. Import Playlists
    if "playlists" in data:
        for p_data in data["playlists"]:
            # Check if playlist with same title already exists
            result = await db.execute(
                select(Playlist).where(Playlist.user_id == user.id, Playlist.title == p_data["title"])
            )
            if not result.scalars().first():
                new_playlist = Playlist(
                    user_id=user.id,
                    title=p_data["title"],
                    is_public=p_data.get("is_public", False)
                )
                db.add(new_playlist)
                await db.flush() # Get the new playlist ID

                if "tracks" in p_data:
                    for song_id in p_data["tracks"]:
                        new_track = PlaylistTrack(
                            playlist_id=new_playlist.id,
                            yt_video_id=song_id
                        )
                        db.add(new_track)

    await db.commit()
    return {"message": f"Successfully imported {imported_count} missing items."}

@router.delete("/me")
async def delete_me(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Deletes the current user's account and all associated data.
    """
    try:
        await db.delete(user)
        await db.commit()
        return {"message": "Account deleted successfully"}
    except Exception as e:
        await db.rollback()
        print(f"DELETE ERROR: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to delete account")

@router.get("/me/followed-artists")
async def get_followed_artists(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Returns the full list of artists the user follows.
    """
    try:
        # 1. Fetch user with followed artists relationship preloaded
        result = await db.execute(
            select(User)
            .options(selectinload(User.followed_artists))
            .where(User.id == user.id)
        )
        db_user = result.scalar_one_or_none()
        
        if not db_user:
            return []

        # 2. Map and return followed artists
        return [{
            "id": a.id,
            "name": a.name,
            "image": a.image_url
        } for a in db_user.followed_artists]
        
    except Exception as e:
        print("\n" + "!" * 60)
        print(f"CRASH IN FOLLOWED ARTISTS: {str(e)}")
        print("!" * 60 + "\n")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/follow-artist")
async def follow_artist(artist_data: dict, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Follows an artist. Creates the artist in the DB if they don't exist.
    """
    artist_id = artist_data.get("id")
    if not artist_id:
        raise HTTPException(status_code=400, detail="Artist ID is required")

    # 1. Check if artist exists in our DB
    result = await db.execute(select(models.Artist).where(models.Artist.id == artist_id))
    artist = result.scalar_one_or_none()

    if not artist:
        # Create the artist in our DB
        artist = models.Artist(
            id=artist_id,
            name=artist_data.get("name", "Unknown Artist"),
            image_url=artist_data.get("image") or artist_data.get("imageUrl") or artist_data.get("image_url")
        )
        db.add(artist)
        await db.flush()

    # 2. Check if user is already following
    result = await db.execute(
        select(User)
        .options(selectinload(User.followed_artists))
        .where(User.id == user.id)
    )
    db_user = result.scalar_one()

    if artist not in db_user.followed_artists:
        db_user.followed_artists.append(artist)
        await db.commit()
        return {"message": f"Now following {artist.name}"}
    
    return {"message": "Already following this artist"}

@router.delete("/unfollow-artist/{artist_id}")
async def unfollow_artist(artist_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Unfollows an artist.
    """
    result = await db.execute(
        select(User)
        .options(selectinload(User.followed_artists))
        .where(User.id == user.id)
    )
    db_user = result.scalar_one()

    # Find the artist in the user's followed list
    artist_to_remove = next((a for a in db_user.followed_artists if a.id == artist_id), None)

    if artist_to_remove:
        db_user.followed_artists.remove(artist_to_remove)
        await db.commit()
        return {"message": "Unfollowed successfully"}
    
    raise HTTPException(status_code=404, detail="Artist not found in your following list")
