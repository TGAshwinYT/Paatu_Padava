import uvicorn
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
import os
from dotenv import load_dotenv
from connection import check_redis_connection, check_db_connection, engine
from base import Base
from routers import music, auth, playlists, history, users, utils
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
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(GZipMiddleware, minimum_size=1000)

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
            
            # Search Click History Migrations
            await conn.execute(text("""
                CREATE TABLE IF NOT EXISTS search_click_history (
                    id UUID PRIMARY KEY,
                    user_id UUID REFERENCES users(id),
                    jiosaavn_song_id TEXT NOT NULL,
                    title TEXT,
                    artist TEXT,
                    cover_url TEXT,
                    audio_url TEXT,
                    clicked_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
                )
            """))
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
app.include_router(utils.router)

@app.get("/")
async def root():
    return {"message": "Paaatu_Padava API is running!"}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=7860, reload=False)
