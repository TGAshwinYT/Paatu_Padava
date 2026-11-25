import axios from 'axios';
import type { Song } from '../types';
import { getValidImage } from '../utils/imageUtils';
import { saveOfflineTrack } from '../utils/offlineStorage';

export const mapHistoryToSong = (item: any): Song => {
  if (!item) return { id: '', title: 'Unknown', artist: 'Unknown', coverUrl: '', audioUrl: '' };
  
  return {
    id: item.yt_video_id || item.id || '',
    title: item.title || item.song_name || item.name || 'Unknown Title',
    artist: item.artist || item.artist_name || item.artists || 'Unknown Artist',
    album: item.album || item.album_name || '',
    duration: Number(item.duration || item.song_duration || 0),
    coverUrl: getValidImage(item),
    audioUrl: item.audio_url || item.audioUrl || item.url || item.streamUrl || '',
    downloadUrls: item.download_urls || item.downloadUrls || [],
    language: item.language || ''
  };
};

const API_URL = import.meta.env.VITE_DATA_API_URL || (import.meta.env.PROD ? 'https://tgashwinyt-paatu-padava.hf.space' : 'http://localhost:8000');

const api = axios.create({
  baseURL: API_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

// ── Silent Token Refresh Interceptor on 401 ──────────────────────────────────
let isRefreshing = false;
let failedQueue: Array<{
  resolve: (value?: unknown) => void;
  reject: (reason?: any) => void;
}> = [];

const processQueue = (error: any, token: string | null = null) => {
  failedQueue.forEach((prom) => {
    if (error) {
      prom.reject(error);
    } else {
      prom.resolve(token);
    }
  });
  failedQueue = [];
};

api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config;
    const status = error.response ? error.response.status : null;
    const url = originalRequest?.url || '';

    // Ignore 401s from login/register/refresh endpoints to avoid loops
    const isAuthEndpoint =
      url.includes('/api/auth/login') ||
      url.includes('/api/auth/register') ||
      url.includes('/api/auth/refresh');

    if (status === 401 && !originalRequest._retry && !isAuthEndpoint) {
      const currentToken = localStorage.getItem('token');
      if (!currentToken) {
        return Promise.reject(error);
      }

      if (isRefreshing) {
        return new Promise((resolve, reject) => {
          failedQueue.push({ resolve, reject });
        })
          .then((token) => {
            originalRequest.headers.Authorization = `Bearer ${token}`;
            return api(originalRequest);
          })
          .catch((err) => Promise.reject(err));
      }

      originalRequest._retry = true;
      isRefreshing = true;

      try {
        const refreshResponse = await axios.post(
          `${API_URL}/api/auth/refresh`,
          {},
          {
            headers: {
              Authorization: `Bearer ${currentToken}`,
              'Content-Type': 'application/json',
            },
          }
        );

        const newToken = refreshResponse.data?.access_token;
        if (newToken) {
          localStorage.setItem('token', newToken);
          api.defaults.headers.common.Authorization = `Bearer ${newToken}`;
          originalRequest.headers.Authorization = `Bearer ${newToken}`;
          processQueue(null, newToken);
          return api(originalRequest);
        } else {
          throw new Error('No access token returned from refresh');
        }
      } catch (refreshErr) {
        processQueue(refreshErr, null);
        localStorage.removeItem('token');
        window.dispatchEvent(new Event('auth-expired'));
        return Promise.reject(refreshErr);
      } finally {
        isRefreshing = false;
      }
    }

    return Promise.reject(error);
  }
);

export const getHomeFeed = async (): Promise<{ recentlyPlayed: Song[], topAlbums: Song[], topArtists: Song[], recommendedForYou: Song[], personalized: boolean }> => {
  try {
    const response = await api.get('/api/music/home');
    const { recentlyPlayed, topAlbums, topArtists, recommendedForYou, personalized } = response.data;
    return { 
      recentlyPlayed: (recentlyPlayed || []).map(mapHistoryToSong), 
      topAlbums: (topAlbums || []).map(mapHistoryToSong),
      topArtists: (topArtists || []).map(mapHistoryToSong),
      recommendedForYou: (recommendedForYou || []).map(mapHistoryToSong),
      personalized: !!personalized
    };
  } catch (error) {
    console.error("Error fetching home feed:", error);
    return { recentlyPlayed: [], topAlbums: [], topArtists: [], recommendedForYou: [], personalized: false };
  }
};

export const searchTracks = async (query: string): Promise<any> => {
  if (!query) return { local_matches: [], global_matches: { top_result: null, songs: [], albums: [], artists: [] } };
  try {
    const response = await api.get('/api/music/search', { params: { query } });
    const data = response.data;
    
    return {
      local_matches: data.local_matches || [],
      global_matches: {
        top_result: data.global_matches?.top_result ? (
          data.global_matches.top_result.type === 'song' 
            ? { ...mapHistoryToSong(data.global_matches.top_result), type: 'song' }
            : data.global_matches.top_result
        ) : null,
        songs: (data.global_matches?.songs || []).map(mapHistoryToSong),
        albums: data.global_matches?.albums || [],
        artists: data.global_matches?.artists || []
      }
    };
  } catch (error) {
    console.error("Error searching globally:", error);
    return { local_matches: [], global_matches: { top_result: null, songs: [], albums: [], artists: [] } };
  }
};

export const searchArtists = async (query: string): Promise<any[]> => {
  if (!query) return [];
  try {
    const response = await api.get('/api/music/search/artists', { params: { query } });
    return response.data;
  } catch (error) {
    console.error("Error searching artists:", error);
    return [];
  }
};

export const getArtistDetails = async (id: string): Promise<{ id: string, name: string, image: string, topSongs: Song[] }> => {
  try {
    const response = await api.get(`/api/music/artist/${id}`);
    const data = response.data;
    const songs = (data.topSongs || []).map(mapHistoryToSong);
    return { 
      id: data.id, 
      name: data.name, 
      image: data.image, 
      topSongs: songs 
    };
  } catch (error) {
    console.error("Error fetching artist details:", error);
    return { id: "", name: "Unknown Artist", image: "", topSongs: [] };
  }
};

export const getAlbumDetails = async (id: string): Promise<{ id: string, title: string, artist: string, image: string, songs: Song[] }> => {
  try {
    const response = await api.get(`/api/music/albums/${id}`);
    const data = response.data;
    
    return {
      id: data.id,
      title: data.title,
      artist: data.artist,
      image: data.image,
      songs: (data.songs || []).map(mapHistoryToSong)
    };
  } catch (error) {
    console.error("Error fetching album details:", error);
    throw error;
  }
};

export const getSuggestions = async (query: string): Promise<any> => {
  if (!query) return { songs: [], artists: [], albums: [] };
  try {
    const response = await api.get('/api/music/search/suggestions', { params: { query } });
    const data = response.data;
    return {
      songs: (data.songs || []).map(mapHistoryToSong),
      artists: (data.artists || []).map((a: any) => {
        const name = a.name || a.artist || a.title || 'Unknown Artist';
        const img = a.image || a.coverUrl || a.cover_url || (Array.isArray(a.thumbnails) ? a.thumbnails[a.thumbnails.length - 1]?.url : '') || '/logo.png';
        return {
          id: a.id || a.browseId || '',
          name,
          artist: name,
          title: name,
          image: img,
          coverUrl: img,
          type: 'artist'
        };
      }),
      albums: (data.albums || []).map((alb: any) => {
        const title = alb.title || alb.name || 'Unknown Album';
        const img = alb.coverUrl || alb.image || alb.cover_url || '/logo.png';
        return {
          id: alb.id || '',
          title,
          name: title,
          artist: alb.artist || alb.artists || '',
          coverUrl: img,
          image: img,
          type: 'album'
        };
      })
    };
  } catch (error) {
    console.error("Error fetching suggestions:", error);
    return { songs: [], artists: [], albums: [] };
  }
};

export const addListenHistory = async (track: Song) => {
  if (!localStorage.getItem('token')) return; // Silently skip for guests
  try {
    await api.post('/api/history/listen', {
      id: track.id,
      title: track.title || "Unknown Title",
      artist: track.artist || "Unknown Artist",
      cover_url: getValidImage(track),
      audio_url: track.audioUrl || "",
      language: track.language || ""
    });
  } catch (error) {
    console.error("Failed to add to history:", error);
  }
};

export const getPersonalMix = async (): Promise<{ queue: Song[], personalized: boolean }> => {
  try {
    const response = await api.get('/api/music/for-you');
    const queue = (response.data?.queue || []).map(mapHistoryToSong);
    return {
      queue,
      personalized: !!response.data?.personalized
    };
  } catch (error) {
    console.error("Error fetching personal mix:", error);
    return { queue: [], personalized: false };
  }
};

export const getShuffleOrder = async (queueIds: string[], currentSongId?: string): Promise<string[]> => {
  try {
    const response = await api.post('/api/music/shuffle-order', {
      queue_ids: queueIds,
      current_song_id: currentSongId
    });
    return response.data?.ordered_ids || [];
  } catch (error) {
    console.error("Error fetching shuffle order:", error);
    return [];
  }
};

export const getRecommendations = async (
  songId: string, 
  artist?: string, 
  language?: string, 
  limit: number = 25
): Promise<Song[]> => {
  try {
    const response = await api.get(`/api/music/recommendations/${songId}`, {
      params: {
        ...(artist ? { artist } : {}),
        ...(language ? { lang: language } : {}),
        limit
      }
    });
    return (response.data || []).map(mapHistoryToSong);
  } catch (error) {
    return [];
  }
};

export const getRelatedSongs = async (songId: string, artist?: string, language?: string): Promise<Song[]> => {
  try {
    const response = await api.get(`/api/music/related/${songId}`, {
      params: {
        ...(artist ? { artist } : {}),
        ...(language ? { lang: language } : {})
      }
    });
    return (response.data || []).map(mapHistoryToSong);
  } catch (error) {
    return [];
  }
};

export const getLikedSongs = async (): Promise<Song[]> => {
  try {
    const response = await api.get('/api/music/liked');
    return (response.data || []).map(mapHistoryToSong);
  } catch (error) {
    console.error("Error fetching liked songs:", error);
    return [];
  }
};

export const likeSong = async (song: Song) => {
  try {
    await api.post('/api/music/like', song);
  } catch (error) {
    console.error("Error liking song:", error);
  }
};

export const unlikeSong = async (songId: string) => {
  try {
    await api.delete(`/api/music/unlike/${songId}`);
  } catch (error) {
    console.error("Error unliking song:", error);
  }
};

export const getListenHistory = async (): Promise<(Song & { historyId: string })[]> => {
  try {
    const response = await api.get('/api/history/listen');
    return (response.data || []).map((item: any) => ({
      ...mapHistoryToSong(item),
      historyId: item.id,
      played_at: item.played_at // Preserve this for UI
    }));
  } catch (error) {
    console.error("Error fetching listen history:", error);
    return [];
  }
};

export const deleteHistoryItem = async (historyId: string) => {
    try {
        await api.delete(`/api/history/remove/${historyId}`);
    } catch (error) {
        console.error("Error deleting history item:", error);
    }
};

export const getSearchHistory = async () => {
  try {
    const response = await api.get('/api/history/search');
    return response.data;
  } catch (error) {
    console.error("Error fetching search history:", error);
    return [];
  }
};

export const updatePreferences = async (artists: string[]) => {
  try {
    const response = await api.patch('/api/auth/preferences', artists);
    return response.data;
  } catch (error) {
    console.error("Error updating preferences:", error);
    throw error;
  }
};

export const updatePreferredLanguages = async (languages: string[]) => {
  try {
    const response = await api.patch('/api/auth/language-preferences', languages);
    return response.data;
  } catch (error) {
    console.error("Error updating language preferences:", error);
    throw error;
  }
};


export const saveSearchClick = async (track: Song) => {
  if (!localStorage.getItem('token')) return; // Silently skip for guests
  try {
    await api.post('/api/history/search-click', {
      id: track.id,
      title: track.title || "Unknown Title",
      artist: track.artist || "Unknown Artist",
      cover_url: track.coverUrl || "",
      audio_url: track.audioUrl || "",
      language: track.language || ""
    });
  } catch (error) {
    console.error("Error saving search click:", error);
  }
};

export const getRecentSearches = async (): Promise<(Song & { historyId: string })[]> => {
  try {
    const response = await api.get('/api/history/recent-searches');
    return (response.data || []).map((item: any) => ({
      ...mapHistoryToSong(item),
      historyId: item.id
    }));
  } catch (error) {
    console.error("Error fetching recent searches:", error);
    return [];
  }
};

export const deleteSearchHistoryItem = async (historyId: string) => {
  try {
    await api.delete(`/api/history/search-click/${historyId}`);
  } catch (error) {
    console.error("Error deleting search history item:", error);
  }
};

export const getPlaylistDetail = async (id: string): Promise<{ title: string, description?: string, coverUrl?: string, songs: Song[] }> => {
  try {
    const response = await api.get(`/api/playlists/${id}`);
    const { title, description, cover_url, tracks } = response.data;
    const songs = (tracks || []).map(mapHistoryToSong);
    return { title, description, coverUrl: cover_url, songs };
  } catch (error) {
    console.error("Error fetching playlist detail:", error);
    return { title: "Playlist", songs: [] };
  }
};

export const renamePlaylist = async (playlistId: string, title: string) => {
  try {
    const response = await api.patch(`/api/playlists/${playlistId}`, { title });
    return response.data;
  } catch (error) {
    console.error("Error renaming playlist:", error);
    throw error;
  }
};

export const getLyrics = async (track: Song) => {
  try {
    const response = await api.get('/api/music/lyrics', {
      params: {
        title: track.title,
        artist: track.artist,
        track_name: track.title,   // Added for legacy backend compatibility
        artist_name: track.artist, // Added for legacy backend compatibility
        duration: Math.floor(track.duration || 0)
      }
    });
    return response.data;
  } catch (error) {
    console.error("Error fetching lyrics:", error);
    return null;
  }
};

export const deletePlaylist = async (playlistId: string) => {
  try {
    await api.delete(`/api/playlists/${playlistId}`);
  } catch (error) {
    console.error("Error deleting playlist:", error);
    throw error;
  }
};

export const removeSongFromPlaylist = async (playlistId: string, songId: string) => {
  try {
    await api.delete(`/api/playlists/${playlistId}/songs/${songId}`);
  } catch (error) {
    console.error("Error removing song from playlist:", error);
  }
};

export const getFollowedArtists = async (): Promise<any[]> => {
  try {
    const response = await api.get('/api/users/me/followed-artists');
    return response.data;
  } catch (error) {
    console.error("Error fetching followed artists:", error);
    return [];
  }
};

export const followArtist = async (artist: { id: string, name: string, imageUrl: string }) => {
  try {
    const response = await api.post('/api/users/follow-artist', artist);
    return response.data;
  } catch (error) {
    console.error("Error following artist:", error);
    throw error;
  }
};

export const unfollowArtist = async (artistId: string) => {
  try {
    const response = await api.delete(`/api/users/unfollow-artist/${artistId}`);
    return response.data;
  } catch (error) {
    console.error("Error unfollowing artist:", error);
    throw error;
  }
};

export interface StreamResolution {
  song_id: string;
  title?: string;
  audio_url: string | null;
  url?: string;
  download_urls?: string[];
  youtube_id?: string;
  engine: 'native' | 'youtube';
  source: string;
  cached?: boolean;
  download_token?: string;
}

const GUEST_SID_STORAGE_KEY = 'pp_guest_sid';
let inMemoryGuestSid: string | null = null;
const mediaTokenCache = new Map<string, { token: string; sid: string; expiresAt: number }>();

export const getOrCreateGuestSessionId = (): string => {
  if (inMemoryGuestSid) return inMemoryGuestSid;
  try {
    const existing = localStorage.getItem(GUEST_SID_STORAGE_KEY);
    if (existing && /^[a-zA-Z0-9_-]{8,64}$/.test(existing)) {
      inMemoryGuestSid = existing;
      return existing;
    }
    const generated =
      typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
        ? crypto.randomUUID()
        : `guest_${Math.random().toString(36).slice(2)}_${Date.now()}`;
    localStorage.setItem(GUEST_SID_STORAGE_KEY, generated);
    inMemoryGuestSid = generated;
    return generated;
  } catch {
    inMemoryGuestSid = `guest_${Date.now()}_${Math.random().toString(36).slice(2)}`;
    return inMemoryGuestSid;
  }
};

export const fetchSignedMediaToken = async (opts: {
  purpose: 'stream' | 'download' | 'prefetch';
  songId?: string;
  songIds?: string[];
  url?: string;
}): Promise<{ token: string; sid: string } | null> => {
  const sid = getOrCreateGuestSessionId();
  const subjectKey =
    opts.purpose === 'prefetch'
      ? [...(opts.songIds ?? [])].map((s) => s.trim()).filter(Boolean).sort().join(',')
      : opts.url || opts.songId || '';

  if (!subjectKey) return null;
  const cacheKey = `${opts.purpose}:${sid}:${subjectKey}`;
  const cached = mediaTokenCache.get(cacheKey);
  if (cached && Date.now() < cached.expiresAt - 30_000) {
    return { token: cached.token, sid: cached.sid };
  }

  try {
    const response = await api.post<{ token: string; expires_in?: number }>(
      '/api/music/stream-token',
      {
        purpose: opts.purpose,
        ...(opts.songId ? { song_id: opts.songId } : {}),
        ...(opts.songIds ? { song_ids: opts.songIds.slice(0, 4) } : {}),
        ...(opts.url ? { url: opts.url } : {}),
      },
      { headers: { 'X-Session-ID': sid } }
    );
    const token = response.data?.token;
    if (!token) return null;
    const ttlMs = (response.data?.expires_in || 900) * 1000;
    mediaTokenCache.set(cacheKey, { token, sid, expiresAt: Date.now() + ttlMs });
    return { token, sid };
  } catch (error) {
    console.debug('[API] fetchSignedMediaToken error:', error);
    return null;
  }
};

export const resolveStreamUrl = async (
  songId: string, 
  title?: string, 
  artist?: string
): Promise<StreamResolution | null> => {
  if (!songId) return null;
  try {
    const params: Record<string, string> = {};
    if (title) params.title = title;
    if (artist) params.artist = artist;
    if (!localStorage.getItem('token')) {
      const signed = await fetchSignedMediaToken({ purpose: 'stream', songId });
      if (signed) {
        params.st = signed.token;
        params.sid = signed.sid;
      }
    }
    const response = await api.get(`/api/music/stream/${encodeURIComponent(songId)}`, { params });
    return response.data;
  } catch (error) {
    console.debug('[API] resolveStreamUrl error:', error);
    return null;
  }
};

export const prefetchStreamUrls = async (
  tracks: { id: string; title?: string; artist?: string }[]
): Promise<StreamResolution[]> => {
  if (!tracks || tracks.length === 0) return [];
  const batch = tracks.slice(0, 4);
  try {
    const headers: Record<string, string> = {};
    if (!localStorage.getItem('token')) {
      const signed = await fetchSignedMediaToken({
        purpose: 'prefetch',
        songIds: batch.map((t) => t.id),
      });
      if (signed) {
        headers['X-Stream-Token'] = signed.token;
        headers['X-Session-ID'] = signed.sid;
      }
    }
    const response = await api.post(
      '/api/music/prefetch-stream',
      { tracks: batch.map((t) => ({ id: t.id, title: t.title, artist: t.artist })) },
      { headers }
    );
    return response.data?.streams || [];
  } catch (error) {
    console.debug('[API] prefetchStreamUrls error:', error);
    return [];
  }
};

export const savePlayerStateToRedis = async (state: any): Promise<boolean> => {
  try {
    const response = await api.post('/api/music/player-state', state);
    return !!response.data?.saved;
  } catch (error) {
    console.debug('[API] savePlayerStateToRedis error:', error);
    return false;
  }
};

export const getPlayerStateFromRedis = async (): Promise<any> => {
  try {
    const response = await api.get('/api/music/player-state');
    return response.data;
  } catch (error) {
    console.debug('[API] getPlayerStateFromRedis error:', error);
    return null;
  }
};

export interface SpotifyPlaylistPreview {
  spotify_id: string;
  title: string;
  description: string;
  cover_url: string;
  total_tracks: number;
  sample_tracks: { title: string; artist: string; duration: number }[];
}

export interface SpotifyImportResult {
  success: boolean;
  playlist_id: string;
  title: string;
  cover_url: string;
  imported_count: number;
  total_spotify_tracks: number;
}

export const previewSpotifyPlaylist = async (url: string): Promise<SpotifyPlaylistPreview> => {
  const response = await api.post('/api/playlists/preview-spotify', { url });
  return response.data;
};

export const importSpotifyPlaylist = async (url: string, customTitle?: string): Promise<SpotifyImportResult> => {
  const response = await api.post('/api/playlists/import-spotify', {
    url,
    custom_title: customTitle
  });
  return response.data;
};

export const getDownloadTrackUrl = (song: Song): string => {
  const baseURL = api.defaults.baseURL || '';
  const params = new URLSearchParams();
  if (song.id) params.append('song_id', song.id);
  if (song.title) params.append('title', song.title);
  if (song.artist) params.append('artist', song.artist);
  if (song.audioUrl && song.audioUrl.startsWith('http')) {
    params.append('url', song.audioUrl);
  }
  return `${baseURL}/api/music/download?${params.toString()}`;
};

export const getSignedDownloadTrackUrl = async (
  song: Song,
  preFetched?: { token: string; sid: string } | null
): Promise<string> => {
  const baseURL = api.defaults.baseURL || '';
  const params = new URLSearchParams();
  if (song.id) params.append('song_id', song.id);
  if (song.title) params.append('title', song.title);
  if (song.artist) params.append('artist', song.artist);
  const hasHttpUrl = Boolean(song.audioUrl && song.audioUrl.startsWith('http'));
  if (hasHttpUrl && song.audioUrl) {
    params.append('url', song.audioUrl);
  }

  const signed =
    preFetched ??
    (await fetchSignedMediaToken({
      purpose: 'download',
      ...(hasHttpUrl && song.audioUrl ? { url: song.audioUrl } : { songId: song.id }),
    }));
  if (signed) {
    params.append('token', signed.token);
    params.append('sid', signed.sid);
  }
  return `${baseURL}/api/music/download?${params.toString()}`;
};

export const downloadSongFile = async (
  song: Song,
  onProgress?: (percent: number) => void
): Promise<void> => {
  if (!song) return;

  const hasHttpUrl = Boolean(song.audioUrl && song.audioUrl.startsWith('http'));
  const signed = await fetchSignedMediaToken({
    purpose: 'download',
    ...(hasHttpUrl && song.audioUrl ? { url: song.audioUrl } : { songId: song.id }),
  });
  const downloadUrl = await getSignedDownloadTrackUrl(song, signed);

  try {
    const response = await api.get('/api/music/download', {
      params: {
        ...(song.id ? { song_id: song.id } : {}),
        ...(song.title ? { title: song.title } : {}),
        ...(song.artist ? { artist: song.artist } : {}),
        ...(hasHttpUrl && song.audioUrl ? { url: song.audioUrl } : {}),
        ...(signed ? { token: signed.token, sid: signed.sid } : {}),
      },
      headers: signed ? { 'X-Session-ID': signed.sid } : undefined,
      responseType: 'blob',
      onDownloadProgress: (progressEvent) => {
        if (progressEvent.total && onProgress) {
          const percent = Math.round((progressEvent.loaded * 100) / progressEvent.total);
          onProgress(percent);
        }
      }
    });

    const blob = new Blob([response.data], { type: 'audio/mpeg' });

    // 1. Save for offline playback
    await saveOfflineTrack(song, blob, '320kbps');

    // 2. Trigger native download to user's device
    const cleanTitle = (song.title || 'Track').replace(/[^\w\s-]/g, '').trim() || 'Track';
    const cleanArtist = (song.artist || 'Paatu Padava').replace(/[^\w\s-]/g, '').trim() || 'Paatu Padava';
    const filename = `${cleanTitle} - ${cleanArtist}.mp3`;

    const blobUrl = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = blobUrl;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    setTimeout(() => URL.revokeObjectURL(blobUrl), 10000);

  } catch (error) {
    console.error('Direct download blob failed, using fallback URL:', error);
    const fallbackLink = document.createElement('a');
    fallbackLink.href = downloadUrl;
    fallbackLink.target = '_blank';
    document.body.appendChild(fallbackLink);
    fallbackLink.click();
    document.body.removeChild(fallbackLink);
  }
};

export default api;
