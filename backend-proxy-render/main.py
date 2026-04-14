import os
import httpx
import logging
import tempfile
import traceback
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv
import yt_dlp
from pytubefix import YouTube

load_dotenv()

app = FastAPI()

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Cookie Handling ---
def get_youtube_cookies():
    # 1. Environment Variable
    env_cookie = os.getenv("YOUTUBE_COOKIE")
    if env_cookie:
        logger.info("✅ Found YOUTUBE_COOKIE in environment variables")
        # Ensure it's in Netscape format if it's the raw content
        if env_cookie.strip().startswith("# Netscape"):
            return {"type": "netscape", "content": env_cookie}
        return {"type": "string", "content": env_cookie}

    # 2. Local File
    local_path = os.path.join(os.path.dirname(__file__), "cookies.txt")
    root_path = os.path.join(os.path.dirname(__file__), "..", "backend-data-hf", "cookies.txt")
    
    cookie_path = local_path if os.path.exists(local_path) else root_path
    if os.path.exists(cookie_path):
        logger.info(f"✅ Found cookies at {cookie_path}")
        try:
            with open(cookie_path, "r", encoding="utf-8") as f:
                content = f.read()
                return {"type": "file", "path": cookie_path, "content": content}
        except Exception as e:
            logger.error(f"Error reading cookie file: {e}")

    logger.warning("⚠️ No YouTube cookies found. Extraction may be limited.")
    return None

@app.get("/")
async def status():
    cookies = get_youtube_cookies()
    logger.info("📡 Health Check Pinged from Frontend")
    return {
        "status": "ok",
        "message": "Python Renderer is ready!",
        "cookies_loaded": cookies is not None
    }

@app.get("/api/play")
async def play(id: str):
    if not id:
        raise HTTPException(status_code=400, detail="Missing ID")

    try:
        logger.info(f"📡 Extraction Proxy Request: {id}")
        cookie_info = get_youtube_cookies()
        audio_url = None
        
        # --- Attempt 1: yt-dlp (Optimized for Cloud Proxies) ---
        try:
            logger.info(f"🔍 [Attempt 1] Extracting with yt-dlp (Android Client) for: {id}")
            ydl_opts = {
                'format': 'bestaudio/best',
                'quiet': True,
                'no_warnings': True,
                'nocheckcertificate': True,
                'ignoreerrors': False, # Set to False to see actual error
                # 🔥 CRITICAL: Spoof Android client which is less likely to be blocked on Render/HF
                'extractor_args': {'youtube': {'player_client': ['android', 'ios']}}
            }

            temp_cookie_file = None
            if cookie_info:
                if cookie_info["type"] == "netscape" or cookie_info["type"] == "string":
                    temp_cookie_file = tempfile.NamedTemporaryFile(delete=False, mode="w", suffix=".txt", encoding="utf-8")
                    temp_cookie_file.write(cookie_info["content"])
                    temp_cookie_file.flush()
                    temp_cookie_file.close()
                    ydl_opts['cookiefile'] = temp_cookie_file.name
                elif cookie_info["type"] == "file":
                    ydl_opts['cookiefile'] = cookie_info["path"]

            try:
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(f"https://www.youtube.com/watch?v={id}", download=False)
                    if info:
                        audio_url = info.get('url')
                        logger.info("✅ [yt-dlp] Extraction successful via Android client")
            finally:
                if temp_cookie_file and os.path.exists(temp_cookie_file.name):
                    try: os.unlink(temp_cookie_file.name)
                    except: pass
        except Exception as ye:
            logger.warning(f"⚠️ [yt-dlp] Failed: {str(ye)}")

        # --- Attempt 2: pytubefix (Fallback with Android Client) ---
        if not audio_url:
            try:
                logger.info(f"🔍 [Attempt 2] Extracting with pytubefix (Android Client) for: {id}")
                # pytubefix supports client selection to bypass bot detection
                yt = YouTube(f"https://www.youtube.com/watch?v={id}", client='ANDROID')
                stream = yt.streams.filter(only_audio=True).first()
                if stream:
                    audio_url = stream.url
                    logger.info("✅ [pytubefix] Extraction successful via Android client")
            except Exception as pe:
                logger.error(f"❌ [pytubefix] Failed: {str(pe)}")

        if not audio_url:
            raise Exception("Failed to extract audio URL from all providers (yt-dlp & pytubefix).")

        # Stream the audio
        async def stream_generator():
            async with httpx.AsyncClient(timeout=None, follow_redirects=True) as client:
                async with client.stream("GET", audio_url) as response:
                    if response.status_code >= 400:
                        logger.error(f"Failed to stream from YouTube: {response.status_code}")
                        return
                    async for chunk in response.aiter_bytes():
                        yield chunk

        return StreamingResponse(
            stream_generator(),
            media_type="audio/mpeg",
            headers={
                "Transfer-Encoding": "chunked",
                "Accept-Ranges": "bytes",
                "Access-Control-Allow-Origin": "*"
            }
        )

    except Exception as e:
        logger.error(f"❌ Proxy Stream Error: {str(e)}")
        # Log limited traceback to avoid cluttering but show the cause
        logger.error(traceback.format_exc().splitlines()[-2:])
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8001))
    uvicorn.run(app, host="0.0.0.0", port=port)
