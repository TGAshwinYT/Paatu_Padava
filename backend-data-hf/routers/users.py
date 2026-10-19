from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from sqlalchemy.ext.asyncio import AsyncSession
from connection import get_db
from models import User
from auth_utils import get_current_user
import json
from repositories.user_repo import UserRepository

router = APIRouter(prefix="/api/users", tags=["users"])

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
    try:
        contents = await file.read()
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
        print("\n" + "!" * 60)
        print(f"CRASH IN FOLLOWED ARTISTS: {str(e)}")
        print("!" * 60 + "\n")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/follow-artist")
async def follow_artist(
    artist_data: dict,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Follows an artist. Creates the artist in the DB if they don't exist.
    """
    try:
        followed, artist_name = await UserRepository.follow_artist(db, user.id, artist_data)
        if followed:
            return {"message": f"Now following {artist_name}"}
        return {"message": "Already following this artist"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

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
        raise HTTPException(status_code=500, detail=str(e))
