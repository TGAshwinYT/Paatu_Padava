import axios from 'axios';
import api from './api';
import type { SpotifyTrack } from '../types';

interface RawSpotifyArtist {
  id: string;
  name: string;
}

interface RawSpotifyImage {
  url: string;
  width?: number;
  height?: number;
}

interface RawSpotifyItem {
  id: string;
  name: string;
  duration_ms: number;
  explicit?: boolean;
  artists?: RawSpotifyArtist[];
  album?: {
    id?: string;
    name?: string;
    images?: RawSpotifyImage[];
  };
  preview_url?: string | null;
}

// In-memory token cache
let cachedToken: string | null = null;
let tokenExpiresAt: number = 0;

/**
 * Fetches (or returns cached) a Spotify Client Credentials access token
 * securely proxied through the Paatu Padava FastAPI backend.
 * Never exposes SPOTIFY_CLIENT_SECRET to the client browser.
 */
export const getSpotifyToken = async (): Promise<string | null> => {
  // Return cached token if still valid (with 30s buffer)
  if (cachedToken && Date.now() < tokenExpiresAt - 30_000) {
    return cachedToken;
  }

  try {
    const response = await api.get<{ access_token: string; expires_in: number }>('/api/music/spotify-token');
    if (response.data?.access_token) {
      cachedToken = response.data.access_token;
      tokenExpiresAt = Date.now() + (response.data.expires_in || 3600) * 1000;
      return cachedToken;
    }
    return null;
  } catch (error) {
    console.warn('[SpotifyAPI] Backend token proxy unavailable:', error);
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

    const items: RawSpotifyItem[] = response.data?.tracks?.items ?? [];

    return items
      .filter(Boolean)
      .map((item): SpotifyTrack => ({
        spotifyId:   item.id,
        name:        item.name,
        durationMs:  item.duration_ms,
        explicit:    item.explicit ?? false,
        artists:     (item.artists ?? []).map((a) => ({
          id:   a.id,
          name: a.name,
        })),
        album: {
          id:     item.album?.id ?? '',
          name:   item.album?.name ?? '',
          images: (item.album?.images ?? []).map((img) => ({
            url:    img.url,
            width:  img.width ?? 0,
            height: img.height ?? 0,
          })),
        },
        previewUrl: item.preview_url ?? null,
      }));
  } catch (error: unknown) {
    const axiosErr = error as { response?: { data?: { error?: { message?: string } } }; message?: string };
    const errorMsg = axiosErr.response?.data?.error?.message || axiosErr.message;
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
