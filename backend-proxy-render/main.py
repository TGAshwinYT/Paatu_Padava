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
        masked = env_cookie[:15] + "..." + env_cookie[-5:] if len(env_cookie) > 20 else "RAW_TEXT"
        logger.info(f"✅ Found YOUTUBE_COOKIE (Len: {len(env_cookie)}): {masked}")
        
        # Handle Netscape format specifically
        if env_cookie.strip().startswith("# Netscape") or "\t" in env_cookie:
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

    logger.warning("⚠️ No YouTube cookies found. Extraction will likely fail on Render.")
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
        last_error = "Unknown Error"
        
        # --- Common Options ---
        ydl_opts_base = {
            'format': 'bestaudio/best',
            'quiet': True,
            'no_warnings': True,
            'nocheckcertificate': True,
            'ignoreerrors': False,
        }

        # Setup Cookies
        temp_cookie_file = None
        if cookie_info:
            if cookie_info["type"] in ["netscape", "string"]:
                temp_cookie_file = tempfile.NamedTemporaryFile(delete=False, mode="w", suffix=".txt", encoding="utf-8")
                temp_cookie_file.write(cookie_info["content"])
                temp_cookie_file.flush()
                temp_cookie_file.close()
                ydl_opts_base['cookiefile'] = temp_cookie_file.name
            elif cookie_info["type"] == "file":
                ydl_opts_base['cookiefile'] = cookie_info["path"]

        try:
            # --- Attempt 1: yt-dlp (Android Client) ---
            try:
                logger.info(f"🔍 [Attempt 1] Extracting with yt-dlp (Android) for: {id}")
                opts = ydl_opts_base.copy()
                opts['extractor_args'] = {'youtube': {'player_client': ['android']}}
                with yt_dlp.YoutubeDL(opts) as ydl:
                    info = ydl.extract_info(f"https://www.youtube.com/watch?v={id}", download=False)
                    if info:
                        audio_url = info.get('url')
                        logger.info("✅ [yt-dlp-android] Success")
            except Exception as ye:
                last_error = str(ye)
                logger.warning(f"⚠️ [yt-dlp-android] Failed: {last_error}")

            # --- Attempt 2: yt-dlp (iOS Client) ---
            if not audio_url:
                try:
                    logger.info(f"🔍 [Attempt 2] Extracting with yt-dlp (iOS) for: {id}")
                    opts = ydl_opts_base.copy()
                    opts['extractor_args'] = {'youtube': {'player_client': ['ios']}}
                    with yt_dlp.YoutubeDL(opts) as ydl:
                        info = ydl.extract_info(f"https://www.youtube.com/watch?v={id}", download=False)
                        if info:
                            audio_url = info.get('url')
                            logger.info("✅ [yt-dlp-ios] Success")
                except Exception as ye:
                    last_error = str(ye)
                    logger.warning(f"⚠️ [yt-dlp-ios] Failed: {last_error}")

            # --- Attempt 3: pytubefix (Android) ---
            if not audio_url:
                try:
                    logger.info(f"🔍 [Attempt 3] Extracting with pytubefix (Android) for: {id}")
                    yt = YouTube(f"https://www.youtube.com/watch?v={id}", client='ANDROID')
                    stream = yt.streams.filter(only_audio=True).first()
                    if stream:
                        audio_url = stream.url
                        logger.info("✅ [pytubefix] Success")
                except Exception as pe:
                    last_error = str(pe)
                    logger.error(f"❌ [pytubefix] Failed: {last_error}")

        finally:
            if temp_cookie_file and os.path.exists(temp_cookie_file.name):
                try: os.unlink(temp_cookie_file.name)
                except: pass

        if not audio_url:
            # Log the final failure with the last error message
            logger.error(f"❌ ALL EXTRACTION ATTEMPTS FAILED for {id}")
            raise Exception(f"Extraction failed: {last_error}")

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
        # Crucial: Log the FULL error so user can find it in Render logs
        logger.error(f"❌ Proxy Stream Error: {str(e)}")
        logger.error(traceback.format_exc())
        
        # Return the error message to the frontend so it's visible in network tab
        raise HTTPException(
            status_code=500, 
            detail={
                "error": str(e),
                "hint": "Check Render logs for the detailed yt-dlp error message."
            }
        )

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8001))
    uvicorn.run(app, host="0.0.0.0", port=port)
