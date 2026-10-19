from typing import List, Optional, Dict, Any
from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import func, text, delete
import uuid
from models import ListeningHistory, SearchHistory, SearchClickHistory
from connection import AsyncSessionLocal

class HistoryRepository:
    """
    Data Access Layer for ListeningHistory, SearchHistory, and SearchClickHistory.
    """

    @staticmethod
    async def cleanup_old_history(user_id: str, days: int = 90) -> None:
        """
        Cleans up listening history older than specified days using an independent session.
        """
        try:
            async with AsyncSessionLocal() as db:
                cleanup_query = text(
                    f"DELETE FROM listening_history WHERE user_id = :uid AND played_at < NOW() - INTERVAL '{days} days'"
                )
                await db.execute(cleanup_query, {"uid": user_id})
                await db.commit()
        except Exception as e:
            print(f"Background cleanup failed for user {user_id}: {e}")

    @staticmethod
    async def record_listen(
        db: AsyncSession,
        user_id: Any,
        song_id: str,
        title: Optional[str] = "Unknown Title",
        artist: Optional[str] = "Unknown Artist",
        cover_url: Optional[str] = None,
        audio_url: Optional[str] = None,
        language: Optional[str] = None,
    ) -> str:
        last_query = (
            select(ListeningHistory)
            .where(ListeningHistory.user_id == user_id)
            .order_by(ListeningHistory.played_at.desc())
            .limit(1)
        )
        last_result = await db.execute(last_query)
        last_entry = last_result.scalar_one_or_none()

        if last_entry and last_entry.yt_video_id == song_id:
            last_entry.played_at = func.now()
            await db.commit()
            return "History updated"
        else:
            new_entry = ListeningHistory(
                user_id=user_id,
                yt_video_id=song_id,
                title=title,
                artist=artist,
                cover_url=cover_url,
                audio_url=audio_url,
                language=language,
            )
            db.add(new_entry)
            await db.commit()
            return "Listening history tracked"

    @staticmethod
    async def record_search(db: AsyncSession, user_id: Any, query: str) -> None:
        new_entry = SearchHistory(user_id=user_id, query=query)
        db.add(new_entry)
        await db.commit()

    @staticmethod
    async def get_listen_history(db: AsyncSession, user_id: Any) -> List[ListeningHistory]:
        query = (
            select(ListeningHistory)
            .where(ListeningHistory.user_id == user_id)
            .order_by(ListeningHistory.played_at.desc())
        )
        result = await db.execute(query)
        return list(result.scalars().all())

    @staticmethod
    async def delete_history_item(db: AsyncSession, user_id: Any, history_id: str) -> bool:
        is_uuid = False
        try:
            uuid.UUID(str(history_id))
            is_uuid = True
        except ValueError:
            is_uuid = False

        if is_uuid:
            del_stmt = delete(ListeningHistory).where(
                ListeningHistory.id == history_id,
                ListeningHistory.user_id == user_id,
            )
        else:
            del_stmt = delete(ListeningHistory).where(
                ListeningHistory.yt_video_id == history_id,
                ListeningHistory.user_id == user_id,
            )

        await db.execute(del_stmt)
        await db.commit()
        return True

    @staticmethod
    async def delete_history_by_date(db: AsyncSession, user_id: Any, date_string: str) -> bool:
        del_stmt = delete(ListeningHistory).where(
            ListeningHistory.user_id == user_id,
            func.date(ListeningHistory.played_at) == date_string,
        )
        await db.execute(del_stmt)
        await db.commit()
        return True

    @staticmethod
    async def delete_all_history(db: AsyncSession, user_id: Any) -> bool:
        del_stmt = delete(ListeningHistory).where(ListeningHistory.user_id == user_id)
        await db.execute(del_stmt)
        await db.commit()
        return True

    @staticmethod
    async def get_search_history(db: AsyncSession, user_id: Any, limit: int = 10) -> List[SearchHistory]:
        query = (
            select(SearchHistory)
            .where(SearchHistory.user_id == user_id)
            .order_by(SearchHistory.searched_at.desc())
            .limit(limit)
        )
        result = await db.execute(query)
        return list(result.scalars().all())

    @staticmethod
    async def record_search_click(
        db: AsyncSession,
        user_id: Any,
        song_id: str,
        title: Optional[str] = "Unknown Title",
        artist: Optional[str] = "Unknown Artist",
        cover_url: Optional[str] = None,
        audio_url: Optional[str] = None,
        language: Optional[str] = None,
        max_limit: int = 10,
    ) -> str:
        last_query = (
            select(SearchClickHistory)
            .where(SearchClickHistory.user_id == user_id)
            .order_by(SearchClickHistory.clicked_at.desc())
            .limit(1)
        )
        last_result = await db.execute(last_query)
        last_entry = last_result.scalar_one_or_none()

        if last_entry and last_entry.yt_video_id == song_id:
            last_entry.clicked_at = func.now()
            await db.commit()
            return "Search history updated"

        new_entry = SearchClickHistory(
            user_id=user_id,
            yt_video_id=song_id,
            title=title,
            artist=artist,
            cover_url=cover_url,
            audio_url=audio_url,
            language=language,
        )
        db.add(new_entry)

        count_query = (
            select(func.count())
            .select_from(SearchClickHistory)
            .where(SearchClickHistory.user_id == user_id)
        )
        count_result = await db.execute(count_query)
        count = count_result.scalar() or 0

        if count + 1 > max_limit:
            oldest_query = (
                select(SearchClickHistory)
                .where(SearchClickHistory.user_id == user_id)
                .order_by(SearchClickHistory.clicked_at.asc())
                .limit((count + 1) - max_limit)
            )
            oldest_result = await db.execute(oldest_query)
            for item in oldest_result.scalars().all():
                await db.delete(item)

        await db.commit()
        return "Search click tracked"

    @staticmethod
    async def get_recent_searches(db: AsyncSession, user_id: Any, limit: int = 10) -> List[SearchClickHistory]:
        query = (
            select(SearchClickHistory)
            .where(SearchClickHistory.user_id == user_id)
            .order_by(SearchClickHistory.clicked_at.desc())
            .limit(limit)
        )
        result = await db.execute(query)
        return list(result.scalars().all())

    @staticmethod
    async def delete_search_click_item(db: AsyncSession, user_id: Any, history_id: str) -> bool:
        query = select(SearchClickHistory).where(
            SearchClickHistory.id == history_id,
            SearchClickHistory.user_id == user_id,
        )
        result = await db.execute(query)
        item = result.scalar_one_or_none()
        if not item:
            return False

        await db.delete(item)
        await db.commit()
        return True

    @staticmethod
    async def get_user_top_artists(db: AsyncSession, user_id: str, limit: int = 2) -> List[str]:
        """
        Analyzes the user's PostgreSQL listening_history to find their top artists based on playback frequency.
        """
        try:
            query = (
                select(ListeningHistory.artist)
                .where(ListeningHistory.user_id == user_id)
                .order_by(ListeningHistory.played_at.desc())
                .limit(50)
            )
            result = await db.execute(query)
            artists = result.scalars().all()

            if not artists:
                return []

            freq: Dict[str, int] = {}
            for artist in artists:
                if artist:
                    primary = artist.split(",")[0].strip()
                    freq[primary] = freq.get(primary, 0) + 1

            sorted_artists = sorted(freq.items(), key=lambda x: x[1], reverse=True)
            return [art for art, _ in sorted_artists[:limit]]
        except Exception as e:
            print(f"Failed to extract top artists: {e}")
            return []
