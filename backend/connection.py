import os
from dotenv import load_dotenv
from upstash_redis.asyncio import Redis as UpstashRedis
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase

load_dotenv()

# Redis Setup (REST API for Firewall Bypass)
REDIS_REST_URL = os.getenv("UPSTASH_REDIS_REST_URL", "")
REDIS_REST_TOKEN = os.getenv("UPSTASH_REDIS_REST_TOKEN", "")

if not REDIS_REST_URL or not REDIS_REST_TOKEN:
    print("WARNING: UPSTASH_REDIS_REST credentials not found in environment variables!")

async def get_redis():
    """
    Connect to Upstash Redis using REST (HTTPS) to bypass port 6379 blocks.
    """
    if not REDIS_REST_URL:
        raise ValueError("REDIS_REST_URL is missing in the .env file")
    
    # Initialize the Upstash HTTP client
    redis_client = UpstashRedis(url=REDIS_REST_URL, token=REDIS_REST_TOKEN)
    
    try:
        yield redis_client
    finally:
        # upstash-redis uses 'close' for async cleanup
        await redis_client.close()

async def check_redis_connection():
    """Verify Redis connectivity"""
    try:
        # Diagnostic: Log the host to help identify network blocks
        display_url = REDIS_REST_URL
        print(f"[*] Attempting to connect to Redis REST URL: {display_url}")
        
        # Consuming the async generator
        async for client in get_redis():
            await client.ping()
            print("[SUCCESS] Redis (REST): Connected!")
            return True
    except Exception as e:
        print(f"[ERROR] Redis: Connection failed: {str(e)}")
        if "10061" in str(e):
            print("[TIP] 'Errno 10061' usually means port 6379 is blocked by your firewall/network OR the port in your dashboard is different. Please verify the port on Upstash!")
        return False

import ssl

# Supabase / PostgreSQL Setup
# Convert postgresql:// to postgresql+asyncpg:// for SQLAlchemy async
DB_URL_RAW = os.getenv("DATABASE_URL", "")
print(f"[*] RAW DATABASE_URL from .env: {repr(DB_URL_RAW)}")
DB_URL = DB_URL_RAW.replace("postgresql://", "postgresql+asyncpg://")
print(f"[*] Processed DB_URL for SQLAlchemy: {repr(DB_URL)}")

# 1. Create a custom SSL context that ignores verification (for MSYS/Local dev issues)
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

# 2. Inject the custom context into the engine
if not DB_URL or DB_URL == "postgresql+asyncpg://":
    print("[ERROR] DATABASE_URL is missing or empty!")
    print("[INFO] Please add DATABASE_URL (along with Redis credentials) to your environment.")
    # Provide a placeholder to prevent immediate SQLAlchemy crash, 
    # but the app will still fail gracefully during check_db_connection
    DB_URL = "postgresql+asyncpg://missing_db_url_check_hf_secrets"

engine = create_async_engine(
    DB_URL,
    echo=True,
    pool_size=5,
    max_overflow=10,
    connect_args={
        "ssl": ctx  # This forces asyncpg to use our permissive context
    }
)
AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

# Base class moved to base.py to avoid circular imports

async def get_db():
    """Dependency for providing database sessions"""
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()

async def check_db_connection():
    """Verify Supabase connectivity"""
    try:
        async with engine.connect() as conn:
            # Task 2 Fix: Wrap raw SQL in text() for SQLAlchemy 2.0 compatibility
            await conn.execute(text("SELECT 1"))
            print("[SUCCESS] Supabase/Postgres: Connected!")
        return True
    except Exception as e:
        print(f"[ERROR] Supabase/Postgres: Connection failed: {e}")
        return False
