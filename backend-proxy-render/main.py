import os
import sys
import httpx
import logging
import tempfile
import collections
import traceback
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv
import yt_dlp

load_dotenv()

app = FastAPI()

# --- Integrated Logging Buffer ---
LOG_BUFFER = collections.deque(maxlen=100)

class BufferHandler(logging.Handler):
    def emit(self, record):
        try:
            msg = self.format(record)
            LOG_BUFFER.append(msg)
        except Exception:
            self.handleError(record)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Standardize Logging for Render/Development
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add custom handlers
b_handler = BufferHandler()
b_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
logger.addHandler(b_handler)

s_handler = logging.StreamHandler(sys.stdout)
s_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
logger.addHandler(s_handler)

# --- Cookie Handling ---
def get_youtube_cookies():
    # 1. Environment Variable
    env_cookie = os.getenv("YOUTUBE_COOKIE")
    if env_cookie:
        masked = env_cookie[:15] + "..." + env_cookie[-5:] if len(env_cookie) > 20 else "RAW_TEXT"
        logger.info(f"✅ Found YOUTUBE_COOKIE (Len: {len(env_cookie)}): {masked}")
        if env_cookie.strip().startswith("# Netscape") or "\t" in env_cookie:
            return {"type": "netscape", "content": env_cookie}
        return {"type": "string", "content": env_cookie}

    local_path = os.path.join(os.path.dirname(__file__), "cookies.txt")
    if os.path.exists(local_path):
        logger.info(f"✅ Found cookies at {local_path}")
        try:
            with open(local_path, "r", encoding="utf-8") as f:
                content = f.read()
                return {"type": "file", "path": local_path, "content": content}
        except Exception as e:
            logger.error(f"Error reading cookie file: {e}")

    return None

@app.get("/")
async def status():
    cookies = get_youtube_cookies()
    logger.info("📡 Health Check Pinged from Frontend")
    return {
        "status": "ok",
        "message": "Python Renderer is ready!",
        "cookies_loaded": cookies is not None,
        "engine": "TLS Impersonation (Chrome)"
    }

@app.get("/api/logs")
async def get_logs():
    return list(LOG_BUFFER)

@app.get("/api/play")
async def play(id: str):
    if not id:
        raise HTTPException(status_code=400, detail="Missing ID")

    try:
        logger.info(f"📡 Extraction Proxy Request (TLS Impersonation Mode): {id}")
        cookie_info = get_youtube_cookies()
        audio_url = None
        
        # --- Attempt 1: yt-dlp with Chrome TLS Impersonation ---
        # This masks the datacenter IP to look like a standard desktop browser
        try:
            logger.info(f"🔍 [Attempt 1] Extracting with yt-dlp (Impersonate: Chrome) for: {id}")
            ydl_opts = {
                'format': 'm4a/bestaudio/best',
                'quiet': True,
                'no_warnings': True,
                'nocheckcertificate': True,
                'ignoreerrors': False,
                # 🔥 KEY: Byte-level TLS impersonation using curl-cffi
                'impersonate': 'chrome', 
            }

            temp_cookie_file = None
            if cookie_info:
                if cookie_info["type"] in ["netscape", "string"]:
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
                        logger.info("✅ [yt-dlp-impersonate] Success")
            finally:
                if temp_cookie_file and os.path.exists(temp_cookie_file.name):
                    try: os.unlink(temp_cookie_file.name)
                    except: pass
        except Exception as ye:
            logger.warning(f"⚠️ [Attempt 1] Impersonation failed: {str(ye)}")

        if not audio_url:
            raise Exception("TLS Impersonation extraction failed. YouTube may be strictly blocking this IP.")

        # Stream the audio
        async def stream_generator():
            async with httpx.AsyncClient(timeout=60, follow_redirects=True) as client:
                async with client.stream("GET", audio_url) as response:
                    if response.status_code >= 400:
                        logger.error(f"❌ Source Error: {response.status_code}")
                        return
                    async for chunk in response.aiter_bytes():
                        yield chunk

        return StreamingResponse(
            stream_generator(),
            media_type="audio/mpeg",
            headers={
                "Accept-Ranges": "bytes",
                "Access-Control-Allow-Origin": "*"
            }
        )

    except Exception as e:
        logger.error(f"❌ Final Proxy Error: {str(e)}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail={"error": str(e), "id": id})

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8001))
    uvicorn.run(app, host="0.0.0.0", port=port)
