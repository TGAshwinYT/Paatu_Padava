from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession
from connection import get_db
from models import User
from auth_utils import get_current_user
from typing import List, Optional, Dict, Any
from pydantic import BaseModel
from repositories.history_repo import HistoryRepository

class HistoryCreate(BaseModel):
    id: str
    title: Optional[str] = "Unknown Title"
    artist: Optional[str] = "Unknown Artist"
    cover_url: Optional[str] = None
    audio_url: Optional[str] = None
    language: Optional[str] = None

router = APIRouter(prefix="/api/history", tags=["history"])

async def run_history_cleanup(user_id: str):
    """
    Background Task: Cleans up listening history older than 90 days.
    Delegates to HistoryRepository.cleanup_old_history.
    """
    await HistoryRepository.cleanup_old_history(user_id, days=90)

# Backward compatibility export for services/routers importing get_user_top_artists
get_user_top_artists = HistoryRepository.get_user_top_artists

@router.post("/listen")
async def add_listen_history(
    song: HistoryCreate,
    background_tasks: BackgroundTasks,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Tracks when a user starts listening to a song.
    """
    try:
        msg = await HistoryRepository.record_listen(
            db=db,
            user_id=user.id,
            song_id=song.id,
            title=song.title,
            artist=song.artist,
            cover_url=song.cover_url,
            audio_url=song.audio_url,
            language=song.language,
        )
        # Schedule Background Cleanup (90-day retention policy)
        background_tasks.add_task(run_history_cleanup, str(user.id))
        return {"message": f"{msg} (Cleanup scheduled)"}
    except Exception as e:
        await db.rollback()
        print(f"History Error: {e}")
        raise HTTPException(status_code=500, detail="Failed to track history")

@router.post("/search")
async def add_search_history(
    query: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Tracks what a user searches for.
    """
    try:
        await HistoryRepository.record_search(db=db, user_id=user.id, query=query)
        return {"message": "Search history tracked"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Failed to track search")

@router.get("/listen")
async def get_listen_history(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Fetches the user's listening history strictly ordered by play date.
    """
    try:
        return await HistoryRepository.get_listen_history(db, user.id)
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to fetch history")

@router.delete("/song/{history_id}")
async def delete_history_item(
    history_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Removes a specific song from history.
    Handles both native UUIDs and JioSaavn ID strings.
    """
    try:
        await HistoryRepository.delete_history_item(db, user.id, history_id)
        return {"message": "Item removed from history"}
    except Exception as e:
        await db.rollback()
        print(f"Delete Error: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete history item")

@router.delete("/date/{date_string}")
async def delete_history_date(
    date_string: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Removes all songs played on a specific date (YYYY-MM-DD).
    """
    try:
        await HistoryRepository.delete_history_by_date(db, user.id, date_string)
        return {"message": f"History for {date_string} removed"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Failed to delete history for date")

@router.delete("/all")
async def delete_all_history(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Clears the completely history for a user.
    """
    try:
        await HistoryRepository.delete_all_history(db, user.id)
        return {"message": "All history cleared"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Failed to clear history")

@router.get("/search")
async def get_search_history(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Fetches the user's recent search queries.
    """
    try:
        return await HistoryRepository.get_search_history(db, user.id, limit=10)
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to fetch search history")

@router.post("/search-click")
async def add_search_click_history(
    song: HistoryCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Tracks songs clicked specifically from search results.
    """
    try:
        msg = await HistoryRepository.record_search_click(
            db=db,
            user_id=user.id,
            song_id=song.id,
            title=song.title,
            artist=song.artist,
            cover_url=song.cover_url,
            audio_url=song.audio_url,
            language=song.language,
            max_limit=10,
        )
        return {"message": msg}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Failed to track search click")

@router.get("/recent-searches")
async def get_recent_searches(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Fetches the user's 10 most recent search-clicked songs.
    """
    try:
        return await HistoryRepository.get_recent_searches(db, user.id, limit=10)
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to fetch recent searches")

@router.delete("/search-click/{history_id}")
async def delete_search_click_item(
    history_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Removes a specific song from search history.
    """
    try:
        deleted = await HistoryRepository.delete_search_click_item(db, user.id, history_id)
        if not deleted:
            raise HTTPException(status_code=404, detail="Item not found")
        return {"message": "Item removed from search history"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Failed to delete search history item")
