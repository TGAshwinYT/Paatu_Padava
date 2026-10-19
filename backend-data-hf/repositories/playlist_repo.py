import uuid
from typing import Optional, List, Dict, Any
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete, func
from sqlalchemy.orm import selectinload
import models

class PlaylistRepository:
    """
    Data Access Layer for Playlist entities and their associated PlaylistTrack items.
    """

    @staticmethod
    async def get_user_playlists(db: AsyncSession, user_id: Any) -> List[models.Playlist]:
        stmt = (
            select(models.Playlist)
            .where(models.Playlist.user_id == user_id)
            .options(selectinload(models.Playlist.tracks))
            .order_by(models.Playlist.created_at.desc())
        )
        result = await db.execute(stmt)
        return list(result.scalars().all())

    @staticmethod
    async def find_by_title(db: AsyncSession, user_id: Any, clean_title: str) -> Optional[models.Playlist]:
        stmt = (
            select(models.Playlist)
            .where(
                models.Playlist.user_id == user_id,
                func.lower(func.trim(models.Playlist.title)) == clean_title.lower(),
            )
            .options(selectinload(models.Playlist.tracks))
        )
        result = await db.execute(stmt)
        return result.scalar_one_or_none()

    @staticmethod
    async def create_playlist(
        db: AsyncSession,
        user_id: Any,
        title: str,
        description: str = "",
        cover_url: str = "",
        is_public: bool = False,
    ) -> models.Playlist:
        playlist = models.Playlist(
            user_id=user_id,
            title=title,
            description=description or "",
            cover_url=cover_url or "",
            is_public=is_public or False,
        )
        db.add(playlist)
        await db.commit()
        await db.refresh(playlist)
        return playlist

    @staticmethod
    async def get_by_id(
        db: AsyncSession,
        playlist_id: uuid.UUID,
        load_tracks: bool = True,
        user_id: Optional[Any] = None,
    ) -> Optional[models.Playlist]:
        stmt = select(models.Playlist).where(models.Playlist.id == playlist_id)
        if user_id is not None:
            stmt = stmt.where(models.Playlist.user_id == user_id)
        if load_tracks:
            stmt = stmt.options(selectinload(models.Playlist.tracks))
        result = await db.execute(stmt)
        return result.scalar_one_or_none()

    @staticmethod
    async def update_playlist(
        db: AsyncSession,
        playlist: models.Playlist,
        title: Optional[str] = None,
        description: Optional[str] = None,
        cover_url: Optional[str] = None,
        is_public: Optional[bool] = None,
    ) -> models.Playlist:
        if title is not None and title.strip():
            playlist.title = title.strip()
        if description is not None:
            playlist.description = description
        if cover_url is not None:
            playlist.cover_url = cover_url
        if is_public is not None:
            playlist.is_public = is_public

        await db.commit()
        await db.refresh(playlist)
        return playlist

    @staticmethod
    async def delete_playlist(db: AsyncSession, playlist: models.Playlist) -> None:
        await db.delete(playlist)
        await db.commit()

    @staticmethod
    async def add_track(
        db: AsyncSession,
        playlist: models.Playlist,
        track_id: str,
        title: str,
        artist: str,
        album: str = "",
        cover_url: str = "",
        stream_url: str = "",
        source: str = "saavn",
        duration: int = 0,
    ) -> bool:
        # Prevent duplicates
        if any(t.track_id == track_id for t in (playlist.tracks or [])):
            return False

        position = len(playlist.tracks or [])
        track = models.PlaylistTrack(
            playlist_id=playlist.id,
            track_id=track_id,
            title=title,
            artist=artist,
            album=album or "",
            artwork_url=cover_url or "",
            stream_url=stream_url or "",
            source_type=source or "saavn",
            duration=duration or 0,
            position=position,
        )
        db.add(track)

        if not playlist.cover_url and cover_url:
            playlist.cover_url = cover_url

        await db.commit()
        return True

    @staticmethod
    async def remove_track(
        db: AsyncSession,
        playlist_id: uuid.UUID,
        song_id: str,
    ) -> None:
        del_stmt = delete(models.PlaylistTrack).where(
            models.PlaylistTrack.playlist_id == playlist_id,
            models.PlaylistTrack.track_id == song_id,
        )
        await db.execute(del_stmt)
        await db.commit()
