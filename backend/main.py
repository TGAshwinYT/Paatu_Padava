import uvicorn
import asyncio
import os
import socket
from contextlib import asynccontextmanager
from dotenv import load_dotenv
load_dotenv() # Load env vars before importing routers

# Setup YouTube Cookie File for Deployment (Bypasses bot detection)
COOKIE_PATH = "/tmp/youtube_cookies.txt"
cookies_content = os.getenv("YT_COOKIES")

if cookies_content:
    try:
        # Ensure directory exists (mostly for local testing on various OS)
        os.makedirs(os.path.dirname(COOKIE_PATH), exist_ok=True)
        with open(COOKIE_PATH, "w") as f:
            f.write(cookies_content)
        print("[INIT] Successfully loaded YouTube cookies from environment.")
    except Exception as e:
        print(f"[ERROR] Failed to write YouTube cookies: {e}")
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
from redis import asyncio as aioredis
from fastapi_cache import FastAPICache
from fastapi_cache.backends.redis import RedisBackend
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from limiter_config import limiter

from connection import check_redis_connection, check_db_connection, engine
from base import Base
from routers import music, auth, playlists, history, users, utils, ai
from services.youtube import get_trending_youtube
from trie import Trie
from graph import recommendation_graph
import models

# Global Autocomplete Engine
artist_trie = Trie()

# CORS Configuration
allowed_origins = [
    "http://localhost:5173",
    "http://localhost:5174",
    "http://127.0.0.1:5173",
    "http://127.0.0.1:5174"
]

# Ensure tables are created (Simple approach for development)
async def create_tables():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        try:
            await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_premium BOOLEAN DEFAULT FALSE"))
            await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT FALSE"))
            await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS verification_token TEXT"))
            await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS favorite_artists TEXT DEFAULT '[]'"))
            await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()"))
            
            await conn.execute(text("ALTER TABLE listening_history ADD COLUMN IF NOT EXISTS title TEXT"))
            await conn.execute(text("ALTER TABLE listening_history ADD COLUMN IF NOT EXISTS artist TEXT"))
            await conn.execute(text("ALTER TABLE listening_history ADD COLUMN IF NOT EXISTS cover_url TEXT"))
            await conn.execute(text("ALTER TABLE listening_history ADD COLUMN IF NOT EXISTS audio_url TEXT"))
            
            await conn.execute(text("ALTER TABLE liked_songs ADD COLUMN IF NOT EXISTS title TEXT"))
            await conn.execute(text("ALTER TABLE liked_songs ADD COLUMN IF NOT EXISTS artist TEXT"))
            await conn.execute(text("ALTER TABLE liked_songs ADD COLUMN IF NOT EXISTS cover_url TEXT"))
            await conn.execute(text("ALTER TABLE liked_songs ADD COLUMN IF NOT EXISTS audio_url TEXT"))
            
            await conn.execute(text("""
                CREATE TABLE IF NOT EXISTS search_click_history (
                    id UUID PRIMARY KEY,
                    user_id UUID REFERENCES users(id),
                    yt_video_id TEXT NOT NULL,
                    title TEXT,
                    artist TEXT,
                    cover_url TEXT,
                    audio_url TEXT,
                    clicked_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
                )
            """))
            
            await conn.execute(text("""
                CREATE TABLE IF NOT EXISTS artists (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    image_url TEXT
                )
            """))
            await conn.execute(text("""
                CREATE TABLE IF NOT EXISTS user_followed_artists (
                    user_id UUID REFERENCES users(id),
                    artist_id TEXT REFERENCES artists(id),
                    followed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                    PRIMARY KEY (user_id, artist_id)
                )
            """))
        except Exception as e:
            print(f"Migration Note: {e}")

async def load_initial_graph_data():
    """
    Background task to populate the recommendation graph without blocking startup.
    """
    print("[INIT] Populating Music Recommendation Graph in background...")
    # Map for connections
    song_ids = []
    total_added = 0
    
    try:
        print("[GRAPH] Loading trending songs from YouTube Charts")
        # Fetch trending data from YouTube
        trending_songs = await get_trending_youtube('ZZ') # 'ZZ' for global
        
        # Step 1: Add Songs as Nodes
        for song in trending_songs:
            recommendation_graph.add_song({
                "id": song["id"],
                "title": song["title"],
                "artist": song["artist"],
                "cover_url": song["coverUrl"],
                "audio_url": "" # Handled JIT in AudioContext
            })
            song_ids.append(song["id"])
            total_added += 1
            
        # Connect every song in this trending batch to each other (Subset Clique)
        # Only connect first 20 to avoid explosion
        limit_ids = song_ids[:20]
        for i in range(len(limit_ids)):
            for j in range(i + 1, len(limit_ids)):
                recommendation_graph.add_connection(limit_ids[i], limit_ids[j])
                
    except Exception as e:
        print(f"[WARNING] Could not pre-load graph data from YouTube: {e}")

    print(f"[GRAPH] Successfully pre-loaded {total_added} songs into the recommendation engine!")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup logic
    print("[INIT] Starting PaaatuPadava Backend Lifespan...")
    
    # 0. Diagnostic DNS Check (Helpful for 'gaierror 11001' on Windows)
    mandatory_hosts = ["aws-1-ap-south-1.pooler.supabase.com"]
    for host in mandatory_hosts:
        try:
            socket.gethostbyname(host)
            print(f"[DNS] {host} resolved successfully.")
        except socket.gaierror:
            print(f"[CRITICAL] DNS Resolution failed for {host}.")

    # 1. Database & Tables
    try:
        await create_tables()
        await check_db_connection()
    except Exception as e:
        print(f"[CRITICAL ERROR] Database initialization failed: {e}")
        print("[TIP] The server will continue to start, but DB-dependent features will fail.")

    await check_redis_connection()
    
    # 2. Redis Cache Initialization (fastapi-cache2)
    # Use REDIS_URL from .env with fallback to localhost
    redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
    print(f"[INIT] Initializing Redis Cache with URL: {redis_url.split('@')[-1]}") # Hide credentials in logs
    
    try:
        redis = aioredis.from_url(redis_url)
        FastAPICache.init(RedisBackend(redis), prefix="paatu-cache")
        print("[SUCCESS] FastAPICache initialized!")
    except Exception as e:
        print(f"[ERROR] Redis Cache initialization failed: {e}")
    
    # 3. Populate Autocomplete Trie
    print("[INIT] Populating Artist Autocomplete Trie...")
    # NOTE: REGIONAL_VIP_ARTISTS was removed from saavn import. 
    # For now, we'll use a placeholder or eventually move it to a config.
    print("[INIT] Trie population skipped (Regional VIP Artists dependency removed).")
    
    # 4. Populate Recommendation Graph (Backgrounded)
    asyncio.create_task(load_initial_graph_data())
    
    yield
    # Shutdown logic
    print("[INIT] Shutting down PaaatuPadava Backend...")

app = FastAPI(title="Paaatu_Padava Backend", lifespan=lifespan)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(GZipMiddleware, minimum_size=1000)

app.include_router(music.router)
app.include_router(auth.router)
app.include_router(playlists.router)
app.include_router(history.router)
app.include_router(users.router)
app.include_router(utils.router)
app.include_router(ai.router)

@app.get("/api/health")
async def health_check():
    return {"status": "ok", "message": "Backend is awake!"}

@app.get("/api/search/autocomplete")
async def autocomplete(q: str = ""):
    """
    Instant in-memory artist autocomplete.
    """
    if not q or len(q) < 2:
        return []
        
    results = artist_trie.search_prefix(q)
    return results



@app.get("/")
async def root():
    return {"message": "Paaatu_Padava API is running!"}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)
