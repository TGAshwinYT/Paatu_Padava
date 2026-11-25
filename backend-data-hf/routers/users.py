from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from connection import get_db
from models import User
from auth_utils import get_current_user
import json
import logging
from typing import Optional
from repositories.user_repo import UserRepository

logger = logging.getLogger(__name__)
MAX_IMPORT_BYTES = 5 * 1024 * 1024  # 5 MB upload ceiling

router = APIRouter(prefix="/api/users", tags=["users"])


class FollowArtistRequest(BaseModel):
    id: str = Field(..., min_length=1, max_length=100)
    name: str = Field(default="Unknown Artist", min_length=1, max_length=255)
    image: Optional[str] = Field(None, max_length=2048)
    imageUrl: Optional[str] = Field(None, max_length=2048)
    image_url: Optional[str] = Field(None, max_length=2048)

@router.get("/export")
async def export_data(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Exports user data (Liked Songs and Playlists) as a clean JSON object.
    """
    data = await UserRepository.get_user_export_data(db, user.id)
    if not data:
        raise HTTPException(status_code=404, detail="User not found")
    return data

@router.post("/import")
async def import_data(
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Imports Liked Songs and Playlists from a JSON file, merging with existing data.
    """
    contents = await file.read(MAX_IMPORT_BYTES + 1)
    if len(contents) > MAX_IMPORT_BYTES:
        raise HTTPException(status_code=413, detail="Import file exceeds 5 MB limit")

    try:
        data = json.loads(contents)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON file")

    if not isinstance(data, dict):
        raise HTTPException(status_code=400, detail="JSON payload must be an object")

    imported_songs, imported_playlists = await UserRepository.import_user_data(db, user.id, data)

    return {
        "message": f"Successfully imported {imported_songs} missing items.",
        "imported_songs": imported_songs,
        "imported_playlists": imported_playlists
    }

@router.delete("/me")
async def delete_me(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Deletes the current user's account and all associated data.
    """
    try:
        await UserRepository.delete_account(db, user)
        return {"message": "Account deleted successfully"}
    except Exception as e:
        await db.rollback()
        print(f"DELETE ERROR: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to delete account")

@router.get("/me/followed-artists")
async def get_followed_artists(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Returns the full list of artists the user follows.
    """
    try:
        return await UserRepository.get_followed_artists(db, user.id)
    except Exception as e:
        logger.error("Failed to fetch followed artists for user %s: %s", user.id, e)
        raise HTTPException(status_code=500, detail="Failed to fetch followed artists")

@router.post("/follow-artist")
async def follow_artist(
    artist_data: FollowArtistRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Follows an artist. Creates the artist in the DB if they don't exist.
    """
    try:
        followed, artist_name = await UserRepository.follow_artist(
            db, user.id, artist_data.model_dump()
        )
        if followed:
            return {"message": f"Now following {artist_name}"}
        return {"message": "Already following this artist"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        await db.rollback()
        logger.error("Failed to follow artist for user %s: %s", user.id, e)
        raise HTTPException(status_code=500, detail="Failed to follow artist")

@router.delete("/unfollow-artist/{artist_id}")
async def unfollow_artist(
    artist_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Unfollows an artist.
    """
    try:
        unfollowed = await UserRepository.unfollow_artist(db, user.id, artist_id)
        if unfollowed:
            return {"message": "Unfollowed successfully"}
        raise HTTPException(status_code=404, detail="Artist not found in your following list")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        logger.error("Failed to unfollow artist %s for user %s: %s", artist_id, user.id, e)
        raise HTTPException(status_code=500, detail="Failed to unfollow artist")
