from typing import List, Optional, Dict, Any, Tuple
from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
import models
from models import User, LikedSong

class UserRepository:
    """
    Data Access Layer for User profiles, account export/import, and followed artists.
    """

    @staticmethod
    async def get_user_export_data(db: AsyncSession, user_id: Any) -> Optional[Dict[str, Any]]:
        result = await db.execute(
            select(User)
            .options(
                selectinload(User.liked_songs),
                selectinload(User.playlists).selectinload(models.Playlist.tracks),
            )
            .where(User.id == user_id)
        )
        db_user = result.scalar_one_or_none()
        if not db_user:
            return None

        return {
            "username": db_user.username,
            "email": db_user.email,
            "liked_songs": [
                {
                    "id": s.yt_video_id,
                    "title": s.title,
                    "artist": s.artist,
                    "cover_url": s.cover_url,
                    "audio_url": s.audio_url,
                }
                for s in (db_user.liked_songs or [])
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
                            "duration": t.duration,
                        }
                        for t in (p.tracks or [])
                    ],
                }
                for p in (db_user.playlists or [])
            ],
        }

    @staticmethod
    async def import_user_data(
        db: AsyncSession, user_id: Any, data: Dict[str, Any]
    ) -> Tuple[int, int]:
        imported_songs_count = 0
        imported_playlists_count = 0

        # 1. Liked Songs
        if "liked_songs" in data and isinstance(data["liked_songs"], list):
            result = await db.execute(
                select(LikedSong.yt_video_id).where(LikedSong.user_id == user_id)
            )
            existing_ids = set(result.scalars().all())

            for song in data["liked_songs"]:
                if not isinstance(song, dict):
                    continue
                song_id = song.get("yt_video_id") or song.get("song_id") or song.get("id")
                title = song.get("title")
                artist = song.get("artist")
                if song_id and title and song_id not in existing_ids:
                    new_liked = LikedSong(
                        user_id=user_id,
                        yt_video_id=str(song_id),
                        title=str(title),
                        artist=str(artist or "Unknown"),
                        cover_url=song.get("cover_url"),
                        audio_url=song.get("audio_url"),
                    )
                    db.add(new_liked)
                    existing_ids.add(str(song_id))
                    imported_songs_count += 1

        # 2. Playlists
        if "playlists" in data and isinstance(data["playlists"], list):
            for p_item in data["playlists"]:
                if not isinstance(p_item, dict):
                    continue
                p_title = p_item.get("title", "").strip()
                if not p_title:
                    continue

                p_res = await db.execute(
                    select(models.Playlist).where(
                        models.Playlist.user_id == user_id,
                        models.Playlist.title == p_title,
                    )
                )
                playlist_obj = p_res.scalars().first()
                if not playlist_obj:
                    playlist_obj = models.Playlist(
                        user_id=user_id,
                        title=p_title,
                        is_public=bool(p_item.get("is_public", False)),
                    )
                    db.add(playlist_obj)
                    await db.flush()
                    imported_playlists_count += 1

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
                            duration = (
                                int(tr.get("duration", 0))
                                if str(tr.get("duration", "")).isdigit()
                                else 0
                            )
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
                                position=pos,
                            )
                            db.add(new_track)
                            existing_track_ids.add(str(tr_id))
                            pos += 1

        await db.commit()
        return imported_songs_count, imported_playlists_count

    @staticmethod
    async def delete_account(db: AsyncSession, user: User) -> None:
        await db.delete(user)
        await db.commit()

    @staticmethod
    async def get_followed_artists(db: AsyncSession, user_id: Any) -> List[Dict[str, Any]]:
        result = await db.execute(
            select(User)
            .options(selectinload(User.followed_artists))
            .where(User.id == user_id)
        )
        db_user = result.scalar_one_or_none()
        if not db_user:
            return []

        return [
            {
                "id": a.id,
                "name": a.name,
                "image": a.image_url,
            }
            for a in db_user.followed_artists
        ]

    @staticmethod
    async def follow_artist(
        db: AsyncSession, user_id: Any, artist_data: Dict[str, Any]
    ) -> Tuple[bool, str]:
        artist_id = artist_data.get("id")
        if not artist_id:
            raise ValueError("Artist ID is required")

        result = await db.execute(select(models.Artist).where(models.Artist.id == artist_id))
        artist = result.scalar_one_or_none()

        if not artist:
            artist = models.Artist(
                id=artist_id,
                name=artist_data.get("name", "Unknown Artist"),
                image_url=artist_data.get("image") or artist_data.get("imageUrl") or artist_data.get("image_url"),
            )
            db.add(artist)
            await db.flush()

        result = await db.execute(
            select(User)
            .options(selectinload(User.followed_artists))
            .where(User.id == user_id)
        )
        db_user = result.scalar_one()

        if artist not in db_user.followed_artists:
            db_user.followed_artists.append(artist)
            await db.commit()
            return True, artist.name

        return False, artist.name

    @staticmethod
    async def unfollow_artist(db: AsyncSession, user_id: Any, artist_id: str) -> bool:
        result = await db.execute(
            select(User)
            .options(selectinload(User.followed_artists))
            .where(User.id == user_id)
        )
        db_user = result.scalar_one()

        artist_to_remove = next((a for a in db_user.followed_artists if a.id == artist_id), None)
        if artist_to_remove:
            db_user.followed_artists.remove(artist_to_remove)
            await db.commit()
            return True

        return False

    @staticmethod
    async def like_song(db: AsyncSession, user_id: Any, song_dict: Dict[str, Any]) -> bool:
        query = select(LikedSong).where(
            LikedSong.user_id == user_id,
            LikedSong.yt_video_id == song_dict["id"]
        )
        result = await db.execute(query)
        if result.scalar_one_or_none():
            return False

        new_like = LikedSong(
            user_id=user_id,
            yt_video_id=song_dict["id"],
            title=song_dict["title"],
            artist=song_dict["artist"],
            cover_url=song_dict.get("coverUrl") or song_dict.get("cover_url"),
            audio_url=song_dict.get("audioUrl") or song_dict.get("audio_url"),
            language=song_dict.get("language")
        )
        db.add(new_like)
        await db.commit()
        return True

    @staticmethod
    async def unlike_song(db: AsyncSession, user_id: Any, song_id: str) -> None:
        from sqlalchemy import delete
        query = delete(LikedSong).where(
            LikedSong.user_id == user_id,
            LikedSong.yt_video_id == song_id
        )
        await db.execute(query)
        await db.commit()

    @staticmethod
    async def get_liked_songs(
        db: AsyncSession, user_id: Any, limit: int = 20, offset: int = 0
    ) -> List[Dict[str, Any]]:
        query = (
            select(LikedSong)
            .where(LikedSong.user_id == user_id)
            .order_by(LikedSong.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        result = await db.execute(query)
        likes = result.scalars().all()
        return [
            {
                "id": l.yt_video_id,
                "title": l.title,
                "artist": l.artist,
                "coverUrl": l.cover_url,
                "audioUrl": l.audio_url,
                "cover_url": l.cover_url,
                "audio_url": l.audio_url,
                "language": l.language,
            }
            for l in likes
        ]
