from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import func # Added for func.now()
from connection import get_db
from models import ListeningHistory, SearchHistory, SearchClickHistory, User
from auth_utils import get_current_user
from typing import List, Optional, Dict, Any # Modified from typing import List
from services import saavn

from pydantic import BaseModel # Added

class HistoryCreate(BaseModel):
    id: str
    title: Optional[str] = "Unknown Title"
    artist: Optional[str] = "Unknown Artist"
    cover_url: Optional[str] = None
    audio_url: Optional[str] = None

router = APIRouter(prefix="/api/history", tags=["history"])

@router.post("/listen")
async def add_listen_history(song: HistoryCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
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
            msg = "History updated"
        else:
            new_entry = ListeningHistory(
                user_id=user.id,
                jiosaavn_song_id=song.id,
                title=song.title,
                artist=song.artist,
                cover_url=song.cover_url,
                audio_url=song.audio_url
            )
            db.add(new_entry)
            await db.commit()
            msg = "Listening history tracked"
            
        # Self-Cleaning Step (90-day retention policy) executes after commit
        from sqlalchemy import text
        cleanup_query = text("DELETE FROM listening_history WHERE user_id = :uid AND played_at < NOW() - INTERVAL '90 days'")
        await db.execute(cleanup_query, {"uid": user.id})
        await db.commit()

        return {"message": f"{msg} and cleaned"}
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
    Fetches the user's listening history strictly ordered by play date.
    """
    try:
        query = select(ListeningHistory).where(ListeningHistory.user_id == user.id).order_by(ListeningHistory.played_at.desc())
        result = await db.execute(query)
        
        return result.scalars().all()
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to fetch history")

@router.delete("/song/{history_id}")
async def delete_history_item(history_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Removes a specific song from history.
    Handles both native UUIDs and JioSaavn ID strings to resolve type-mismatch errors.
    """
    try:
        from sqlalchemy import delete
        import uuid
        
        # Determine if ID is a valid database UUID
        is_uuid = False
        try:
            uuid.UUID(str(history_id))
            is_uuid = True
        except ValueError:
            is_uuid = False
            
        if is_uuid:
            query = delete(ListeningHistory).where(ListeningHistory.id == history_id, ListeningHistory.user_id == user.id)
        else:
            # Fallback to JioSaavn ID if the provided string is not a UUID
            query = delete(ListeningHistory).where(ListeningHistory.jiosaavn_song_id == history_id, ListeningHistory.user_id == user.id)
            
        await db.execute(query)
        await db.commit()
        return {"message": "Item removed from history"}
    except Exception as e:
        await db.rollback()
        print(f"Delete Error: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete history item")

@router.delete("/date/{date_string}")
async def delete_history_date(date_string: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Removes all songs played on a specific date (YYYY-MM-DD).
    """
    try:
        from sqlalchemy import delete, func
        query = delete(ListeningHistory).where(ListeningHistory.user_id == user.id, func.date(ListeningHistory.played_at) == date_string)
        await db.execute(query)
        await db.commit()
        return {"message": f"History for {date_string} removed"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Failed to delete history for date")

@router.delete("/all")
async def delete_all_history(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Clears the completely history for a user.
    """
    try:
        from sqlalchemy import delete
        query = delete(ListeningHistory).where(ListeningHistory.user_id == user.id)
        await db.execute(query)
        await db.commit()
        return {"message": "All history cleared"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Failed to clear history")

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

@router.post("/search-click")
async def add_search_click_history(song: HistoryCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Tracks songs clicked specifically from search results.
    """
    try:
        # Check for duplicates (last clicked)
        last_query = select(SearchClickHistory).where(SearchClickHistory.user_id == user.id).order_by(SearchClickHistory.clicked_at.desc()).limit(1)
        last_result = await db.execute(last_query)
        last_entry = last_result.scalar_one_or_none()
        
        if last_entry and last_entry.jiosaavn_song_id == song.id:
            last_entry.clicked_at = func.now()
            await db.commit()
            return {"message": "Search history updated"}

        new_entry = SearchClickHistory(
            user_id=user.id,
            jiosaavn_song_id=song.id,
            title=song.title,
            artist=song.artist,
            cover_url=song.cover_url,
            audio_url=song.audio_url
        )
        db.add(new_entry)
        
        # Enforce 10-track limit for search clicks
        count_query = select(func.count()).select_from(SearchClickHistory).where(SearchClickHistory.user_id == user.id)
        count_result = await db.execute(count_query)
        count = count_result.scalar()
        
        if count + 1 > 10:
             oldest_query = (
                select(SearchClickHistory)
                .where(SearchClickHistory.user_id == user.id)
                .order_by(SearchClickHistory.clicked_at.asc())
                .limit((count + 1) - 10)
            )
             oldest_result = await db.execute(oldest_query)
             for item in oldest_result.scalars().all():
                 await db.delete(item)

        await db.commit()
        return {"message": "Search click tracked"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Failed to track search click")

@router.get("/recent-searches")
async def get_recent_searches(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Fetches the user's 10 most recent search-clicked songs.
    """
    try:
        query = select(SearchClickHistory).where(SearchClickHistory.user_id == user.id).order_by(SearchClickHistory.clicked_at.desc()).limit(10)
        result = await db.execute(query)
        return result.scalars().all()
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to fetch recent searches")

@router.delete("/search-click/{history_id}")
async def delete_search_click_item(history_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """
    Removes a specific song from search history.
    """
    try:
        query = select(SearchClickHistory).where(SearchClickHistory.id == history_id, SearchClickHistory.user_id == user.id)
        result = await db.execute(query)
        item = result.scalar_one_or_none()
        
        if not item:
            raise HTTPException(status_code=404, detail="Item not found")
            
        await db.delete(item)
        await db.commit()
        return {"message": "Item removed from search history"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Failed to delete search history item")

async def get_user_top_artists(db: AsyncSession, user_id: str, limit: int = 2):
    """
    Analyzes the user's PostgreSQL listening_history to find their top artists based on playback frequency.
    """
    try:
        # Fetch the most recent 50 listening history tracks
        query = select(ListeningHistory.artist).where(ListeningHistory.user_id == user_id).order_by(ListeningHistory.played_at.desc()).limit(50)
        result = await db.execute(query)
        artists = result.scalars().all()
        
        if not artists:
            return []
            
        freq = {}
        for artist in artists:
            if artist:
                # Naively extract primary artist and map frequencies
                primary = artist.split(',')[0].strip()
                freq[primary] = freq.get(primary, 0) + 1
                
        # Sort map by frequencies descending
        sorted_artists = sorted(freq.items(), key=lambda x: x[1], reverse=True)
        return [artist for artist, count in sorted_artists[:limit]]
    except Exception as e:
        print(f"Failed to extract top artists: {e}")
        return []

