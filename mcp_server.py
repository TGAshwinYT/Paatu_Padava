#!/usr/bin/env python3
"""
Paatu Padava - Model Context Protocol (MCP) Server
Exposes music search, recommendations, smart shuffle, and playback metadata
to AI agents via the MCP standard.
"""

import sys
import os
import json
import asyncio
from typing import List, Dict, Any, Optional

# Ensure backend-data-hf is on sys.path
backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "backend-data-hf"))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from mcp.server.mcpserver import MCPServer

# Import core Paatu Padava services
from services.saavn import search_saavn
from services.youtube import search_youtube, get_home_youtube, get_related_songs
from services.recommender import personal_recommender
from utils.location import resolve_user_languages, get_search_languages, DEFAULT_APP_LANGUAGES
from graph import recommendation_graph

# Initialize MCP Server
app = MCPServer("paatu-padava-mcp")


# ==============================================================================
# MCP TOOLS
# ==============================================================================

@app.tool()
async def search_music(query: str, region: str = "Tamil Nadu", limit: int = 10) -> str:
    """
    Search for songs, tracks, or music albums across JioSaavn and YouTube.
    Prioritizes direct CDN stream URLs (JioSaavn) for background playback and
    fills catalog gaps with YouTube results.

    Args:
        query: Song title, movie name, or artist to search for (e.g. 'Kanmani Anbodu', 'Anirudh', 'A.R. Rahman').
        region: Geographic region for language prioritization (defaults to 'Tamil Nadu').
        limit: Maximum number of tracks to return (default 10).
    """
    try:
        langs = get_search_languages(region)
        primary_lang = langs.split(",")[0] if langs else "tamil"

        results: List[Dict[str, Any]] = []

        # 1. Search JioSaavn first for direct stream URLs
        saavn_res = await search_saavn(query)
        if saavn_res and isinstance(saavn_res, dict):
            saavn_songs = saavn_res.get("songs") or []
            for s in saavn_songs:
                results.append({
                    "id": s.get("id"),
                    "title": s.get("title"),
                    "artist": s.get("artist"),
                    "duration": s.get("duration"),
                    "coverUrl": s.get("image") or s.get("coverUrl"),
                    "audioUrl": s.get("audioUrl") or s.get("audio_url"),
                    "language": s.get("language") or primary_lang,
                    "source": "saavn"
                })

        # 2. Fill gaps with YouTube search
        if len(results) < limit:
            yt_res = await search_youtube(query, limit=limit - len(results))
            if yt_res:
                for s in yt_res:
                    results.append({
                        "id": s.get("id") or s.get("videoId"),
                        "title": s.get("title"),
                        "artist": s.get("artist"),
                        "duration": s.get("duration"),
                        "coverUrl": s.get("thumbnail") or s.get("coverUrl"),
                        "audioUrl": "",
                        "language": primary_lang,
                        "source": "youtube"
                    })

        return json.dumps({
            "query": query,
            "region": region,
            "languages": langs,
            "count": len(results[:limit]),
            "tracks": results[:limit]
        }, indent=2)
    except Exception as e:
        return json.dumps({"error": f"Search failed: {str(e)}"})


@app.tool()
async def get_song_recommendations(song_id: str, limit: int = 10) -> str:
    """
    Get similar songs and recommendations for a given song ID.
    Uses the in-process item-item collaborative filtering engine (behavioral co-occurrence)
    with fallbacks to the metadata graph and YouTube related tracks.

    Args:
        song_id: YouTube video ID or JioSaavn song ID.
        limit: Number of recommendations to return (default 10).
    """
    try:
        # 1. Item-Item collaborative filtering
        recs = personal_recommender.get_similar_songs(song_id, limit=limit)
        method = "collaborative_filtering"

        # 2. Metadata graph fallback
        if not recs and recommendation_graph:
            graph_recs = recommendation_graph.get_recommendations(song_id, max_results=limit)
            if graph_recs:
                recs = [
                    {
                        "id": r.get("id"),
                        "title": r.get("title") or r.get("name"),
                        "artist": r.get("artist"),
                        "coverUrl": r.get("cover_url") or r.get("coverUrl"),
                        "audioUrl": r.get("audio_url") or r.get("audioUrl")
                    }
                    for r in graph_recs
                ]
                method = "metadata_graph"

        # 3. YouTube related fallback
        if not recs:
            yt_recs = await get_related_songs(song_id)
            if yt_recs:
                recs = yt_recs[:limit]
                method = "youtube_related"

        return json.dumps({
            "seed_song_id": song_id,
            "method": method,
            "count": len(recs),
            "recommendations": recs
        }, indent=2)
    except Exception as e:
        return json.dumps({"error": f"Recommendations failed: {str(e)}"})


@app.tool()
async def get_smart_shuffle_order(queue_ids: List[str], current_song_id: Optional[str] = None, user_id: Optional[str] = None) -> str:
    """
    Reorders a queue of song IDs using a greedy nearest-neighbor chain starting
    from the current track. Pairs songs that have strong behavioral co-occurrence,
    falling back to user taste profile, and finally random placement.

    Args:
        queue_ids: List of song IDs in the upcoming queue.
        current_song_id: Currently playing song ID (used as the chain starting anchor).
        user_id: Optional user ID for taste profile affinity fallback.
    """
    try:
        ordered = personal_recommender.get_shuffle_order(queue_ids, current_song_id, user_id)
        return json.dumps({
            "original_count": len(queue_ids),
            "current_song_id": current_song_id,
            "ordered_ids": ordered
        }, indent=2)
    except Exception as e:
        return json.dumps({"error": f"Shuffle ordering failed: {str(e)}"})


@app.tool()
async def get_trending_music(region: str = "Tamil Nadu", limit: int = 15) -> str:
    """
    Fetches regional trending songs and top home feed tracks from YouTube Music.

    Args:
        region: Geographic region for trending tracks (e.g. 'Tamil Nadu', 'Kerala', 'India').
        limit: Number of trending tracks to retrieve (default 15).
    """
    try:
        feed = await get_home_youtube(limit=limit, region=region)
        recommended = feed.get("recommendedForYou") or []
        return json.dumps({
            "region": region,
            "count": len(recommended),
            "tracks": recommended[:limit]
        }, indent=2)
    except Exception as e:
        return json.dumps({"error": f"Failed to fetch trending music: {str(e)}"})


@app.tool()
async def get_regional_languages(region: Optional[str] = None) -> str:
    """
    Resolves the language priority cascade for a given region (defaults to Tamil-first).

    Args:
        region: Optional region name (e.g. 'Tamil Nadu', 'Kerala', 'Karnataka', 'Maharashtra').
    """
    langs = get_search_languages(region)
    return json.dumps({
        "input_region": region,
        "resolved_languages": langs.split(","),
        "default_app_languages": DEFAULT_APP_LANGUAGES.split(",")
    }, indent=2)


# ==============================================================================
# MCP RESOURCES
# ==============================================================================

@app.resource("music://recommender/stats")
async def recommender_stats() -> str:
    """Current in-memory collaborative filtering recommender engine status."""
    return json.dumps({
        "catalog_size": len(personal_recommender.song_catalog),
        "similarity_nodes": len(personal_recommender.similarities),
        "user_profiles": len(personal_recommender.user_taste),
        "last_built_at": str(personal_recommender.last_built_at) if personal_recommender.last_built_at else "not_built_yet",
        "parameters": {
            "session_window_minutes": 45,
            "session_weight": 1.5,
            "liked_weight": 3.0,
            "search_click_weight": 0.5
        }
    }, indent=2)


@app.resource("music://languages")
async def supported_languages() -> str:
    """List of supported languages and default regional priorities."""
    return json.dumps({
        "default_priority": DEFAULT_APP_LANGUAGES.split(","),
        "available_languages": [
            {"id": "tamil", "name": "Tamil", "native": "தமிழ்"},
            {"id": "english", "name": "English", "native": "English"},
            {"id": "hindi", "name": "Hindi", "native": "हिन्दी"},
            {"id": "telugu", "name": "Telugu", "native": "తెలుగు"},
            {"id": "malayalam", "name": "Malayalam", "native": "മലയാളം"},
            {"id": "kannada", "name": "Kannada", "native": "ಕನ್ನಡ"},
            {"id": "punjabi", "name": "Punjabi", "native": "ਪੰਜਾਬੀ"},
            {"id": "marathi", "name": "Marathi", "native": "मराठी"},
            {"id": "bengali", "name": "Bengali", "native": "বাংলা"}
        ]
    }, indent=2)


# ==============================================================================
# MCP PROMPTS
# ==============================================================================

@app.prompt()
def curate_mood_mix(mood_or_artist: str) -> str:
    """Template for AI pair programmer to curate a personalized cohesive playlist."""
    return f"""Please create a 10-track playlist based on '{mood_or_artist}'.
Follow these steps:
1. Call 'search_music' with query='{mood_or_artist}' to find seed tracks.
2. Select the best matching seed track and call 'get_song_recommendations' to find behaviorally similar songs.
3. Once you have 10 candidate song IDs, call 'get_smart_shuffle_order' with the seed song ID to create a smooth transition chain.
4. Present the final ordered playlist with Track Titles, Artists, and playback sources (Saavn CDN vs YouTube)."""


# ==============================================================================
# MAIN ENTRYPOINT
# ==============================================================================

if __name__ == "__main__":
    app.run(transport="stdio")
