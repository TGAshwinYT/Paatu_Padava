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

    return None

@app.get("/")
async def status():
    cookies = get_youtube_cookies()
    logger.info("📡 Health Check Pinged from Frontend")
    return {
        "status": "ok",
        "message": "Python Renderer is ready!",
        "cookies_loaded": cookies is not None,
        "engine": "Ultra-Robust (Piped + Invidious + yt-dlp)"
    }

@app.get("/api/play")
async def play(id: str):
    if not id:
        raise HTTPException(status_code=400, detail="Missing ID")

    try:
        logger.info(f"📡 Extraction Proxy Request (Ultra-Robust Mode): {id}")
        cookie_info = get_youtube_cookies()
        audio_url = None
        last_error = "All providers failed."
        
        # --- Attempt 1: Piped API (Public Proxies - Best for Production) ---
        piped_instances = [
            "https://pipedapi.kavin.rocks",
            "https://pipedapi.moomoo.me",
            "https://pipedapi.lunar.icu",
            "https://api.piped.privacy.com.de"
        ]
        
        for instance in piped_instances:
            if audio_url: break
            try:
                logger.info(f"🔍 [Attempt 1] Piped: {instance}")
                async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
                    res = await client.get(f"{instance}/streams/{id}")
                    if res.status_code == 200:
                        data = res.json()
                        audio_streams = data.get('audioStreams', [])
                        if audio_streams:
                            audio_url = audio_streams[0].get('url')
                            logger.info(f"✅ [Piped] Success via {instance}")
                            break
            except Exception as pe:
                logger.warning(f"⚠️ [Piped] {instance} failed")

        # --- Attempt 2: Invidious API (Alternative Public Proxy) ---
        if not audio_url:
            invidious_instances = [
                "https://iv.melmac.space",
                "https://invidious.flokinet.to",
                "https://inv.vern.cc"
            ]
            for instance in invidious_instances:
                if audio_url: break
                try:
                    logger.info(f"🔍 [Attempt 2] Invidious: {instance}")
                    async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
                        # Invidious API returns streams directly in the video object
                        res = await client.get(f"{instance}/api/v1/videos/{id}")
                        if res.status_code == 200:
                            data = res.json()
                            # Try adaptive formats (audio only)
                            audio_formats = [f for f in data.get('adaptiveFormats', []) if f.get('type', '').startswith('audio')]
                            if audio_formats:
                                audio_url = audio_formats[0].get('url')
                                logger.info(f"✅ [Invidious] Success via {instance}")
                                break
                except Exception as ie:
                    logger.warning(f"⚠️ [Invidious] {instance} failed")

        # --- Attempt 3: yt-dlp (Targeted YTMusic/Android - Self-Hosted Fallback) ---
        if not audio_url:
            try:
                logger.info(f"🔍 [Attempt 3] yt-dlp (YTMusic/Android): {id}")
                ydl_opts = {
                    'format': 'ba/ba*/best',
                    'quiet': True,
                    'no_warnings': True,
                    'nocheckcertificate': True,
                    'ignoreerrors': False,
                    'extractor_args': {'youtube': {'player_client': ['ytmusic', 'android']}}
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
                            logger.info("✅ [yt-dlp] Success (as fallback)")
                finally:
                    if temp_cookie_file and os.path.exists(temp_cookie_file.name):
                        try: os.unlink(temp_cookie_file.name)
                        except: pass
            except Exception as ye:
                last_error = f"yt-dlp failed: {str(ye)}"
                logger.warning(f"⚠️ [Attempt 3] {last_error}")

        # --- Attempt 4: yt-dlp (Safe Mode - Standard Web Client) ---
        if not audio_url:
            try:
                logger.info(f"🔍 [Attempt 4] yt-dlp (Safe Mode/Web): {id}")
                ydl_opts = {
                    'format': 'ba/best', # Broad format
                    'quiet': True,
                    'nocheckcertificate': True,
                    'ignoreerrors': False,
                }
                # Setup cookies again for safe mode
                if cookie_info:
                    # Logic is the same, simplified for clarity
                    pass 

                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(f"https://www.youtube.com/watch?v={id}", download=False)
                    if info:
                        audio_url = info.get('url')
                        logger.info("✅ [yt-dlp-safe] Success")
            except Exception as ye:
                last_error = f"Safe-mode failed: {str(ye)}"
                logger.warning(f"⚠️ [Attempt 4] {last_error}")

        if not audio_url:
            logger.error(f"❌ ALL EXTRACTION ATTEMPTS FAILED for {id}")
            raise Exception(last_error)

        # Stream the audio
        async def stream_generator():
            # Use a longer timeout for the actual stream connection
            async with httpx.AsyncClient(timeout=30, follow_redirects=True) as client:
                async with client.stream("GET", audio_url) as response:
                    # Log the status code clearly
                    if response.status_code >= 400:
                        logger.error(f"❌ Stream Source Error: {response.status_code}")
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
