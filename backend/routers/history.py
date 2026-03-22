from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import func # Added for func.now()
from connection import get_db
from models import ListeningHistory, SearchHistory, User
from auth_utils import get_current_user
from typing import List, Optional, Dict, Any # Modified from typing import List
from services import saavn

from pydantic import BaseModel # Added

class SongSchema(BaseModel): # Added
    id: str
    title: str
    artist: str
    cover_url: Optional[str] = None
    audio_url: Optional[str] = None

router = APIRouter(prefix="/api/history", tags=["history"])

@router.post("/listen")
async def add_listen_history(song: SongSchema, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)): # Modified song_id to song: SongSchema
    """
    Tracks when a user starts listening to a song.
    """
    try:
        # Check if this song was the LAST one played to avoid duplicates from seeking/reloads
        last_query = select(ListeningHistory).where(ListeningHistory.user_id == user.id).order_by(ListeningHistory.played_at.desc()).limit(1)
        last_result = await db.execute(last_query)
        last_entry = last_result.scalar_one_or_none()
        
        if last_entry and last_entry.jiosaavn_song_id == song.id:
            # Update the played_at timestamp instead of creating a new entry
            last_entry.played_at = func.now()
            await db.commit()
            return {"message": "History updated"}

        new_entry = ListeningHistory(
            user_id=user.id,
            jiosaavn_song_id=song.id,
            title=song.title,
            artist=song.artist,
            cover_url=song.cover_url,
            audio_url=song.audio_url
        )
        db.add(new_entry)
        
        # Enforce 20-track limit per user
        count_query = select(func.count()).select_from(ListeningHistory).where(ListeningHistory.user_id == user.id)
        count_result = await db.execute(count_query)
        count = count_result.scalar()
        
        if count >= 20:
            # Delete the oldest entries (over the 20 limit)
            oldest_query = (
                select(ListeningHistory.id)
                .where(ListeningHistory.user_id == user.id)
                .order_by(ListeningHistory.played_at.asc())
                .limit(count - 19) # If 21 items, delete 2 to get back to 19 (so new one makes 20) 
                # Wait, if count is 20 before adding new one, it's fine. 
                # After adding, if count is 21, delete 1.
            )
            # Actually, let's just delete anything beyond the last 19
            # So the new one makes it 20.
            await db.flush() # Ensure ID is assigned if needed? 
            # Re-count after add
            if count + 1 > 20:
                oldest_items_query = (
                    select(ListeningHistory)
                    .where(ListeningHistory.user_id == user.id)
                    .order_by(ListeningHistory.played_at.asc())
                    .limit((count + 1) - 20)
                )
                oldest_result = await db.execute(oldest_items_query)
                for item in oldest_result.scalars().all():
                    await db.delete(item)

        await db.commit()
        return {"message": "Listening history tracked"}
    except Exception as e:
        await db.rollback()
        print(f"History Error: {e}") # Added print statement
        raise HTTPException(status_code=500, detail="Failed to track history")

@router.post("/search")
async def add_search_history(query: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Tracks what a user searches for.
    """
    try:
        new_entry = SearchHistory(
            user_id=user.id,
            query=query
        )
        db.add(new_entry)
        await db.commit()
        return {"message": "Search history tracked"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Failed to track search")

@router.get("/listen")
async def get_listen_history(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Fetches the user's 10 most recent tracks. # Modified docstring
    """
    try:
        query = select(ListeningHistory).where(ListeningHistory.user_id == user.id).order_by(ListeningHistory.played_at.desc()).limit(20)
        result = await db.execute(query)
        history = result.scalars().all()
        
        # We might need to fetch metadata for these songs if they aren't in the DB
        # For simplicity, we'll return the IDs for now, or just the list
        return history
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to fetch history")

@router.delete("/remove/{history_id}") # Task Fix: Move to specific subpath to avoid potential 404/collision
async def delete_history_item(history_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Removes a specific song from history.
    """
    print(f"DEBUG: DELETE hit for {history_id} by user {user.id}")
    try:
        query = select(ListeningHistory).where(ListeningHistory.id == history_id, ListeningHistory.user_id == user.id)
        result = await db.execute(query)
        item = result.scalar_one_or_none()
        
        if not item:
            raise HTTPException(status_code=404, detail="Item not found")
            
        await db.delete(item)
        await db.commit()
        return {"message": "Item removed from history"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Failed to delete history item")

@router.get("/search")
async def get_search_history(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Fetches the user's recent search queries.
    """
    try:
        query = select(SearchHistory).where(SearchHistory.user_id == user.id).order_by(SearchHistory.searched_at.desc()).limit(10)
        result = await db.execute(query)
        history = result.scalars().all()
        return history
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to fetch search history")
