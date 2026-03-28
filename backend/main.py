import uvicorn
import asyncio
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
from services.saavn import REGIONAL_VIP_ARTISTS, get_trending
from trie import Trie
from graph import recommendation_graph
import models

load_dotenv()

# Global Autocomplete Engine
artist_trie = Trie()



from contextlib import asynccontextmanager

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
                    jiosaavn_song_id TEXT NOT NULL,
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
    languages = ["tamil", "hindi", "telugu"]
    total_added = 0
    
    for lang in languages:
        try:
            print(f"[GRAPH] Loading trending songs for: {lang}")
            # Fetch trending data for the specific language
            trending_data = await get_trending(lang)
            trending_songs = trending_data.get("recommendedForYou", [])
            
            # Map for connections
            song_ids = []
            
            # Step 1: Add Songs as Nodes
            for song in trending_songs:
                recommendation_graph.add_song({
                    "id": song["id"],
                    "title": song["title"],
                    "artist": song["artist"],
                    "cover_url": song["coverUrl"],
                    "audio_url": song["audioUrl"]
                })
                song_ids.append(song["id"])
                total_added += 1
                
            # Connect every song in this trending batch to each other (Clique)
            for i in range(len(song_ids)):
                for j in range(i + 1, len(song_ids)):
                    recommendation_graph.add_connection(song_ids[i], song_ids[j])
                    
        except Exception as e:
            # We fail silently here to ensure the server starts even if JioSaavn is down
            print(f"[WARNING] Could not pre-load {lang} graph data: {e}")

    print(f"[GRAPH] Successfully pre-loaded {total_added} songs into the recommendation engine!")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup logic
    print("[INIT] Starting PaaatuPadava Backend Lifespan...")
    
    # 0. Diagnostic DNS Check (Helpful for 'gaierror 11001' on Windows)
    import socket
    mandatory_hosts = ["aws-1-ap-south-1.pooler.supabase.com", "saavn.sumit.co"]
    for host in mandatory_hosts:
        try:
            socket.gethostbyname(host)
            print(f"[DNS] {host} resolved successfully.")
        except socket.gaierror:
            print(f"[CRITICAL] DNS Resolution failed for {host}. check your internet connection or use a stable DNS like 8.8.8.8")

    # 1. Database & Tables
    try:
        await create_tables()
        await check_db_connection()
    except Exception as e:
        print(f"[CRITICAL ERROR] Database initialization failed: {e}")
        print("[TIP] The server will continue to start, but DB-dependent features will fail.")

    await check_redis_connection()
    
    # Populate Autocomplete Trie
    print("[INIT] Populating Artist Autocomplete Trie...")
    count = 0
    for region, artists in REGIONAL_VIP_ARTISTS.items():
        for name in artists:
            artist_trie.insert(name, {
                "id": f"vip_{name.lower().replace(' ', '_')}",
                "name": name,
                "image": "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=200&h=200&fit=crop",
                "type": "artist"
            })
            count += 1
    print(f"[INIT] Trie populated with {count} VIP artists.")
    
    # 2. Populate Recommendation Graph (Backgrounded)
    asyncio.create_task(load_initial_graph_data())
    
    yield
    # Shutdown logic (can be added here)

app = FastAPI(title="Paaatu_Padava Backend", lifespan=lifespan)

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
