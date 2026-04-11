from sqlalchemy import Column, String, DateTime, ForeignKey, Table, Integer, UniqueConstraint, Boolean, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import uuid
from base import Base

# 3. User Followed Artists (Mapping Table)
user_followed_artists = Table(
    "user_followed_artists",
    Base.metadata,
    Column("user_id", UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True),
    Column("artist_id", String(100), ForeignKey("artists.id"), primary_key=True),
    Column("followed_at", DateTime(timezone=True), server_default=func.now()),
)

class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    username = Column(String(50), unique=True, index=True, nullable=False)
    email = Column(String(255), unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    is_premium = Column(Boolean, default=False)
    is_verified = Column(Boolean, default=False)
    verification_token = Column(String, nullable=True)
    favorite_artists = Column(String, default="[]") # JSON string of artist names
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    playlists = relationship("Playlist", back_populates="user")
    followed_artists = relationship("Artist", secondary=user_followed_artists, back_populates="followers")
    history = relationship("ListeningHistory", back_populates="user")
    liked_songs = relationship("LikedSong", back_populates="user")
    search_history = relationship("SearchHistory", back_populates="user")
    search_click_history = relationship("SearchClickHistory", back_populates="user")

class Artist(Base):
    __tablename__ = "artists"

    id = Column(String(100), primary_key=True) # JioSaavn Artist ID
    name = Column(String(255), nullable=False)
    image_url = Column(String)

    followers = relationship("User", secondary=user_followed_artists, back_populates="followed_artists")

class Playlist(Base):
    __tablename__ = "playlists"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"))
    title = Column(String(100), nullable=False)
    is_public = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="playlists")
    tracks = relationship("PlaylistTrack", back_populates="playlist")

class PlaylistTrack(Base):
    __tablename__ = "playlist_tracks"

    playlist_id = Column(UUID(as_uuid=True), ForeignKey("playlists.id"), primary_key=True)
    yt_video_id = Column(String(100), primary_key=True)
    added_at = Column(DateTime(timezone=True), server_default=func.now())

    playlist = relationship("Playlist", back_populates="tracks")

class ListeningHistory(Base):
    __tablename__ = "listening_history"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), index=True)
    yt_video_id = Column(String(100), nullable=False)
    title = Column(String(255))
    artist = Column(String(255))
    cover_url = Column(String)
    audio_url = Column(String)
    played_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)

    __table_args__ = (
        Index('ix_user_played_at', 'user_id', 'played_at'),
    )

    user = relationship("User", back_populates="history")

class SearchHistory(Base):
    __tablename__ = "search_history"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"))
    query = Column(String(255), nullable=False)
    searched_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="search_history")

class SearchClickHistory(Base):
    __tablename__ = "search_click_history"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"))
    yt_video_id = Column(String(100), nullable=False)
    title = Column(String(255))
    artist = Column(String(255))
    cover_url = Column(String)
    audio_url = Column(String)
    clicked_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="search_click_history")

class LikedSong(Base):
    __tablename__ = "liked_songs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    yt_video_id = Column(String(100), nullable=False) # YouTube Video ID
    title = Column(String(255), nullable=False)
    artist = Column(String(255), nullable=False)
    cover_url = Column(String)
    audio_url = Column(String)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # Ensure a user can only like a song once
    __table_args__ = (UniqueConstraint("user_id", "yt_video_id", name="uq_user_song"),)

    user = relationship("User", back_populates="liked_songs")
