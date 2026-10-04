import axios from 'axios';
import type { SpotifyTrack } from '../types';

// ─────────────────────────────────────────────
// Spotify App Credentials (Client Credentials flow – no user login required)
// Set these in .env.local:
//   VITE_SPOTIFY_CLIENT_ID=your_client_id
//   VITE_SPOTIFY_CLIENT_SECRET=your_client_secret
// ─────────────────────────────────────────────
const CLIENT_ID     = import.meta.env.VITE_SPOTIFY_CLIENT_ID     as string | undefined;
const CLIENT_SECRET = import.meta.env.VITE_SPOTIFY_CLIENT_SECRET as string | undefined;

// In-memory token cache
let cachedToken: string | null = null;
let tokenExpiresAt: number = 0;

/**
 * Fetches (or returns cached) a Spotify Client Credentials access token.
 * Returns null if credentials are not configured.
 */
export const getSpotifyToken = async (): Promise<string | null> => {
  if (!CLIENT_ID || !CLIENT_SECRET) {
    console.warn('[SpotifyAPI] VITE_SPOTIFY_CLIENT_ID / VITE_SPOTIFY_CLIENT_SECRET not set.');
    return null;
  }

  // Return cached token if still valid (with 30s buffer)
  if (cachedToken && Date.now() < tokenExpiresAt - 30_000) {
    return cachedToken;
  }

  try {
    const credentials = btoa(`${CLIENT_ID}:${CLIENT_SECRET}`);
    const response = await axios.post(
      'https://accounts.spotify.com/api/token',
      new URLSearchParams({ grant_type: 'client_credentials' }),
      {
        headers: {
          Authorization: `Basic ${credentials}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      }
    );

    cachedToken = response.data.access_token;
    tokenExpiresAt = Date.now() + response.data.expires_in * 1000;
    return cachedToken;
  } catch (error) {
    console.error('[SpotifyAPI] Token fetch failed:', error);
    cachedToken = null;
    tokenExpiresAt = 0;
    return null;
  }
};

/**
 * Searches Spotify for tracks matching `query`.
 * Returns a clean SpotifyTrack array, or empty array on failure.
 */
export const searchSpotify = async (
  query: string,
  limit = 20
): Promise<SpotifyTrack[]> => {
  if (!query.trim()) return [];

  const token = await getSpotifyToken();
  if (!token) return [];

  try {
    const response = await axios.get('https://api.spotify.com/v1/search', {
      headers: { Authorization: `Bearer ${token}` },
      params: {
        q: query,
        type: 'track',
        limit,
        market: 'IN', // Prioritise Indian catalogue
      },
    });

    const items: any[] = response.data?.tracks?.items ?? [];

    return items
      .filter(Boolean)
      .map((item): SpotifyTrack => ({
        spotifyId:   item.id,
        name:        item.name,
        durationMs:  item.duration_ms,
        explicit:    item.explicit ?? false,
        artists:     (item.artists ?? []).map((a: any) => ({
          id:   a.id,
          name: a.name,
        })),
        album: {
          id:     item.album?.id ?? '',
          name:   item.album?.name ?? '',
          images: (item.album?.images ?? []).map((img: any) => ({
            url:    img.url,
            width:  img.width,
            height: img.height,
          })),
        },
        previewUrl: item.preview_url ?? null,
      }));
  } catch (error: any) {
    const errorMsg = error.response?.data?.error?.message || error.response?.data || error.message;
    console.error('[SpotifyAPI] Search failed:', errorMsg);
    throw new Error(errorMsg || 'Spotify search failed');
  }
};

/** Convenience: returns only the best (largest) album image URL. */
export const getSpotifyArt = (track: SpotifyTrack): string => {
  const images = track.album.images;
  if (!images.length) return '/logo.png';
  // Spotify returns images sorted by size (largest first)
  return images[0].url;
};

/** Formats ms duration → "3:45" */
export const formatSpotifyDuration = (ms: number): string => {
  const totalSec = Math.floor(ms / 1000);
  const mins = Math.floor(totalSec / 60);
  const secs = totalSec % 60;
  return `${mins}:${secs.toString().padStart(2, '0')}`;
};
