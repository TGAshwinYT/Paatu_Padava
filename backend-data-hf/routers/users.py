from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload
from connection import get_db
import models
from models import User, LikedSong
from auth_utils import get_current_user
import json
from typing import List
import asyncio
import requests

router = APIRouter(prefix="/api/users", tags=["users"])


@router.get("/export")
async def export_data(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Exports user data (Liked Songs and Playlists) as a clean JSON object.
    """
    # Load user with relationships
    result = await db.execute(
        select(User)
        .options(
            selectinload(User.liked_songs),
            selectinload(User.playlists).selectinload(models.Playlist.tracks),
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
            } for s in (db_user.liked_songs or [])
        ],
        "playlists": [
            {
                "title": p.title,
                "is_public": p.is_public,
                "tracks": [
                    {
                        "id": t.track_id,
                        "title": t.title,
                        "artist": t.artist,
                        "album": t.album,
                        "artwork_url": t.artwork_url,
                        "stream_url": t.stream_url,
                        "source_type": t.source_type,
                        "duration": t.duration
                    } for t in (p.tracks or [])
                ]
            } for p in (db_user.playlists or [])
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

    if not isinstance(data, dict):
        raise HTTPException(status_code=400, detail="JSON payload must be an object")

    # 1. Import Liked Songs
    imported_songs_count = 0
    if "liked_songs" in data and isinstance(data["liked_songs"], list):
        result = await db.execute(select(LikedSong.yt_video_id).where(LikedSong.user_id == user.id))
        existing_ids = set(result.scalars().all())

        for song in data["liked_songs"]:
            if not isinstance(song, dict):
                continue
            song_id = song.get("yt_video_id") or song.get("song_id") or song.get("id")
            title = song.get("title")
            artist = song.get("artist")
            if song_id and title and song_id not in existing_ids:
                new_liked = LikedSong(
                    user_id=user.id,
                    yt_video_id=str(song_id),
                    title=str(title),
                    artist=str(artist or "Unknown"),
                    cover_url=song.get("cover_url"),
                    audio_url=song.get("audio_url")
                )
                db.add(new_liked)
                existing_ids.add(str(song_id))
                imported_songs_count += 1

    # 2. Import Playlists
    imported_playlists_count = 0
    if "playlists" in data and isinstance(data["playlists"], list):
        for p_item in data["playlists"]:
            if not isinstance(p_item, dict):
                continue
            p_title = p_item.get("title", "").strip()
            if not p_title:
                continue

            # Find or create playlist
            p_res = await db.execute(
                select(models.Playlist).where(
                    models.Playlist.user_id == user.id,
                    models.Playlist.title == p_title
                )
            )
            playlist_obj = p_res.scalars().first()
            if not playlist_obj:
                playlist_obj = models.Playlist(
                    user_id=user.id,
                    title=p_title,
                    is_public=bool(p_item.get("is_public", False))
                )
                db.add(playlist_obj)
                await db.flush()
                imported_playlists_count += 1

            # Fetch existing track IDs in this playlist
            t_res = await db.execute(
                select(models.PlaylistTrack.track_id).where(
                    models.PlaylistTrack.playlist_id == playlist_obj.id
                )
            )
            existing_track_ids = set(t_res.scalars().all())

            raw_tracks = p_item.get("tracks", [])
            if isinstance(raw_tracks, list):
                pos = len(existing_track_ids)
                for tr in raw_tracks:
                    if isinstance(tr, dict):
                        tr_id = tr.get("id") or tr.get("track_id") or tr.get("yt_video_id")
                        tr_title = tr.get("title", "Track")
                        tr_artist = tr.get("artist", "Unknown")
                        album = tr.get("album", "")
                        artwork_url = tr.get("artwork_url", "")
                        stream_url = tr.get("stream_url", "")
                        source_type = tr.get("source_type", "saavn")
                        duration = int(tr.get("duration", 0)) if str(tr.get("duration", "")).isdigit() else 0
                    elif isinstance(tr, str):
                        tr_id = tr
                        tr_title = "Track"
                        tr_artist = "Unknown"
                        album = ""
                        artwork_url = ""
                        stream_url = ""
                        source_type = "saavn"
                        duration = 0
                    else:
                        continue

                    if tr_id and str(tr_id) not in existing_track_ids:
                        new_track = models.PlaylistTrack(
                            playlist_id=playlist_obj.id,
                            track_id=str(tr_id),
                            title=str(tr_title),
                            artist=str(tr_artist),
                            album=str(album),
                            artwork_url=str(artwork_url),
                            stream_url=str(stream_url),
                            source_type=str(source_type),
                            duration=duration,
                            position=pos
                        )
                        db.add(new_track)
                        existing_track_ids.add(str(tr_id))
                        pos += 1

    await db.commit()
    return {
        "message": f"Successfully imported {imported_songs_count} missing items.",
        "imported_songs": imported_songs_count,
        "imported_playlists": imported_playlists_count
    }

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
