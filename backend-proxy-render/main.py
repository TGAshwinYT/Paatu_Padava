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
        if env_cookie.startswith("# Netscape"):
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
        
        # --- Attempt 1: pytubefix (Modern & Resilient) ---
        try:
            logger.info(f"🔍 [Attempt 1] Extracting with pytubefix for: {id}")
            # pytubefix handles signatures well with the latest updates
            yt = YouTube(f"https://www.youtube.com/watch?v={id}")
            stream = yt.streams.filter(only_audio=True).first()
            if stream:
                audio_url = stream.url
                logger.info("✅ [pytubefix] Extraction successful")
        except Exception as pe:
            logger.warning(f"⚠️ [pytubefix] Failed: {str(pe)}")

        # --- Attempt 2: yt-dlp (Reliable Fallback) ---
        if not audio_url:
            try:
                logger.info(f"🔍 [Attempt 2] Extracting with yt-dlp for: {id}")
                ydl_opts = {
                    'format': 'bestaudio/best',
                    'quiet': True,
                    'no_warnings': True,
                    'nocheckcertificate': True,
                    'ignoreerrors': True,
                }

                temp_cookie_file = None
                if cookie_info:
                    if cookie_info["type"] == "netscape":
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
                            logger.info("✅ [yt-dlp] Extraction successful")
                finally:
                    if temp_cookie_file and os.path.exists(temp_cookie_file.name):
                        try: os.unlink(temp_cookie_file.name)
                        except: pass
            except Exception as ye:
                logger.error(f"❌ [yt-dlp] Failed: {str(ye)}")

        if not audio_url:
            raise Exception("Failed to extract audio URL from all providers.")

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
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8001))
    uvicorn.run(app, host="0.0.0.0", port=port)
