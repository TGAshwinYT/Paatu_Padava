from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload
from connection import get_db
from models import User, LikedSong, Playlist, PlaylistTrack
from auth_utils import get_current_user
import json
from typing import List
from services import saavn
import asyncio
import requests

router = APIRouter(prefix="/api/users", tags=["users"])

@router.get("/test-location")
async def get_test_location(request: Request):
    """
    Fetches the user's IP geolocation data using ip-api.com.
    Handles Hugging Face proxy by checking X-Forwarded-For.
    """
    # 1. Extract real IP from Hugging Face proxy headers
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        # Get the first IP in the comma-separated list
        user_ip = forwarded_for.split(",")[0].strip()
    else:
        user_ip = request.client.host

    # 2. Localhost check for ip-api.com auto-detection
    if user_ip == "127.0.0.1":
        user_ip = ""

    # 3. Fetch geolocation data
    try:
        response = requests.get(f"http://ip-api.com/json/{user_ip}")
        data = response.json()
        
        return {
            "your_ip": data.get("query"),
            "status": data.get("status"),
            "country": data.get("country"),
            "region": data.get("regionName"),
            "city": data.get("city"),
            "internet_provider": data.get("isp")
        }
    except Exception as e:
        return {"error": str(e)}

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
                "song_id": s.song_id,
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
                "tracks": [t.jiosaavn_song_id for t in p.tracks]
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
        result = await db.execute(select(LikedSong.song_id).where(LikedSong.user_id == user.id))
        existing_ids = set(result.scalars().all())

        for song in data["liked_songs"]:
            if song["song_id"] not in existing_ids:
                new_liked = LikedSong(
                    user_id=user.id,
                    song_id=song["song_id"],
                    title=song["title"],
                    artist=song["artist"],
                    cover_url=song.get("cover_url"),
                    audio_url=song.get("audio_url")
                )
                db.add(new_liked)
                existing_ids.add(song["song_id"])
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
                            jiosaavn_song_id=song_id
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
    result = await db.execute(
        select(User)
        .options(selectinload(User.followed_artists))
        .where(User.id == user.id)
    )
    db_user = result.scalar_one()
    
    return [{
        "id": a.id,
        "name": a.name,
        "imageUrl": a.image_url
    } for a in db_user.followed_artists]
