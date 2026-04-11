from fastapi import APIRouter, Request, HTTPException
from pydantic import BaseModel
import os
import json
import logging
from google import genai
from google.genai import types
from services.youtube import search_youtube
from limiter_config import limiter

router = APIRouter(prefix="/api/ai", tags=["AI DJ"])
logger = logging.getLogger(__name__)

# Initialize Gemini client lazily or safely
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")
client = None

if GEMINI_API_KEY:
    try:
        client = genai.Client(api_key=GEMINI_API_KEY)
    except Exception as e:
        logger.error(f"Failed to initialize Gemini Client: {e}")

class DJRequest(BaseModel):
    prompt: str

@router.post("/dj")
@limiter.limit("5/minute")
async def ai_dj_endpoint(request: Request, dj_req: DJRequest):
    """
    AI DJ: Takes a mood/prompt, gets recommendations from Gemini, 
    and resolves them into playable tracks via JioSaavn.
    """
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="Gemini API Key not configured")

    # Rate limiting is handled by the @limiter.limit decorator which we'll add via app.state
    # For routers, we access the limiter from the app state
    limiter = request.app.state.limiter
    
    # Step 1: LLM Parsing
    try:
        prompt_text = f"Act as a master DJ. The user says: '{dj_req.prompt}'. Recommend exactly 5 songs that perfectly match this vibe."
        
        response = client.models.generate_content(
            model='gemini-2.5-flash',
            contents=prompt_text,
            config=types.GenerateContentConfig(
                system_instruction="You are a music curator. Return ONLY a valid JSON array of objects. Do not use markdown blocks like ```json. Each object must have 'title' and 'artist' keys.",
                response_mime_type="application/json",
            ),
        )
        
        # Parse the returned string into a Python list of dictionaries
        recommended_songs = json.loads(response.text)
        
        if not isinstance(recommended_songs, list):
            raise ValueError("Gemini returned invalid format")
            
    except Exception as e:
        logger.error(f"Gemini API Error: {str(e)}")
        raise HTTPException(status_code=502, detail=f"Failed to generate recommendations: {str(e)}")

    # Step 2: Audio Resolution
    playable_queue = []
    for song in recommended_songs:
        try:
            title = song.get("title")
            artist = song.get("artist")
            if not title: continue
            
            query = f"{title} {artist}" if artist else title
            
            # Use YouTube Music search utility
            search_results = await search_youtube(query, limit=1)
            
            if search_results:
                # Grab the top single song result
                top_song = search_results[0]
                playable_queue.append(top_song)
            
        except Exception as e:
            logger.error(f"Search resolution failed for {song}: {str(e)}")
            continue

    return {"queue": playable_queue}
