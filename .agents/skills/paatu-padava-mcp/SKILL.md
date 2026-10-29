---
name: paatu-padava-mcp
description: Interact with the Paatu Padava music platform via Model Context Protocol (MCP) tools for searching songs, getting collaborative filtering recommendations, building smart shuffle queues, and fetching regional trending music.
---

# Paatu Padava MCP Tools & Workflows

This workspace provides an MCP server exposing Paatu Padava's music catalog, collaborative filtering recommendation engine, and smart playback tools.

## Available MCP Tools

| Tool Name | Description | Key Arguments |
|:---|:---|:---|
| `search_music` | Searches JioSaavn (direct CDN audio) and YouTube for tracks. | `query` (str), `region` (str, default 'Tamil Nadu'), `limit` (int) |
| `get_song_recommendations` | Finds similar songs via item-item collaborative filtering & metadata graph. | `song_id` (str), `limit` (int) |
| `get_smart_shuffle_order` | Generates a greedy nearest-neighbor queue order starting from a current song. | `queue_ids` (list[str]), `current_song_id` (str) |
| `get_trending_music` | Retrieves regional trending music from YouTube Music. | `region` (str), `limit` (int) |
| `get_regional_languages` | Resolves the 4-tier language priority cascade (Tamil-first). | `region` (str) |

## Available MCP Resources

- `music://languages`: Supported languages, native scripts, and regional priority mappings.
- `music://recommender/stats`: In-memory collaborative filtering engine metrics (catalog size, similarity nodes, user taste profiles).

## Available MCP Prompts

- `curate_mood_mix`: Structured template for curating a 10-track playlist around a mood or artist.

## Server Execution

The MCP server is configured in `.agents/mcp_config.json` and runs over stdio via `mcp_server.py`.
