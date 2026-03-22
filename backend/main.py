from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
import os
from dotenv import load_dotenv
from connection import check_redis_connection, check_db_connection, engine
from base import Base
from routers import music, auth, playlists, history, users
import models

load_dotenv()

app = FastAPI(title="Paaatu_Padava Backend")

# CORS Configuration
# Hardcoded for local development to prevent port mismatch errors
allowed_origins = [
    "http://localhost:5173",
    "http://localhost:5174",
    "http://127.0.0.1:5173",
    "http://127.0.0.1:5174"
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Ensure tables are created (Simple approach for development)
# In production, use Alembic migrations!
async def create_tables():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        # Ensure new columns are added if the table already existed (Simple Migration)
        try:
            await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_premium BOOLEAN DEFAULT FALSE"))
            await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT FALSE"))
            await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS verification_token TEXT"))
            await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS favorite_artists TEXT DEFAULT '[]'"))
            await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()"))
            
            # Listening History Metadata Migrations
            await conn.execute(text("ALTER TABLE listening_history ADD COLUMN IF NOT EXISTS title TEXT"))
            await conn.execute(text("ALTER TABLE listening_history ADD COLUMN IF NOT EXISTS artist TEXT"))
            await conn.execute(text("ALTER TABLE listening_history ADD COLUMN IF NOT EXISTS cover_url TEXT"))
            await conn.execute(text("ALTER TABLE listening_history ADD COLUMN IF NOT EXISTS audio_url TEXT"))
            
            # Liked Songs Metadata Migrations
            await conn.execute(text("ALTER TABLE liked_songs ADD COLUMN IF NOT EXISTS title TEXT"))
            await conn.execute(text("ALTER TABLE liked_songs ADD COLUMN IF NOT EXISTS artist TEXT"))
            await conn.execute(text("ALTER TABLE liked_songs ADD COLUMN IF NOT EXISTS cover_url TEXT"))
            await conn.execute(text("ALTER TABLE liked_songs ADD COLUMN IF NOT EXISTS audio_url TEXT"))
        except Exception as e:
            print(f"Migration Note: {e}")

@app.on_event("startup")
async def startup_event():
    await create_tables()
    await check_redis_connection()
    await check_db_connection()

app.include_router(music.router)
app.include_router(auth.router)
app.include_router(playlists.router)
app.include_router(history.router)
app.include_router(users.router)

from sqlalchemy import select
from connection import get_db

@app.get("/api/users/{user_id}/artists")
async def get_user_followed_artists(user_id: str, db: AsyncSession = Depends(get_db)):
    """
    Returns the JioSaavn artist IDs a user follows.
    """
    # Note: In a real app, this would query the association table
    # For now, we return a sample list to satisfy the requirement
    query = select(models.Artist.id).join(models.user_followed_artists).where(models.user_followed_artists.c.user_id == user_id)
    result = await db.execute(query)
    artist_ids = result.scalars().all()
    
    return {"user_id": user_id, "followed_artist_ids": artist_ids}

@app.get("/")
async def root():
    return {"message": "Paaatu_Padava API is running!"}
