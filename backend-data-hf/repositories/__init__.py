"""
Repositories package for Paatu Padava backend.
Abstracts data access and database query operations away from API controllers (routers),
adhering to Clean / Hexagonal Architecture.
"""

from .playlist_repo import PlaylistRepository
from .history_repo import HistoryRepository
from .user_repo import UserRepository

__all__ = [
    "PlaylistRepository",
    "HistoryRepository",
    "UserRepository",
]
