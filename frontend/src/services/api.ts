import axios from 'axios';
import type { Song } from '../types';

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

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

export const getHomeFeed = async (): Promise<{ recentlyPlayed: Song[], topArtists: Song[], recommendedForYou: Song[] }> => {
  try {
    const response = await api.get('/api/music/home');
    const { recentlyPlayed, topArtists, recommendedForYou } = response.data;
    const mapSong = (item: any): Song => ({
      id: item.id,
      title: item.title,
      artist: item.artist,
      coverUrl: item.cover_url,
      audioUrl: item.audio_url,
      downloadUrls: item.download_urls
    });
    return { 
      recentlyPlayed: (recentlyPlayed || []).map(mapSong), 
      topArtists: (topArtists || []).map(mapSong),
      recommendedForYou: (recommendedForYou || []).map(mapSong)
    };
  } catch (error) {
    console.error("Error fetching home feed:", error);
    return { recentlyPlayed: [], topArtists: [], recommendedForYou: [] };
  }
};

export const searchTracks = async (query: string): Promise<Song[]> => {
  if (!query) return [];
  try {
    const response = await api.get('/api/music/search', { params: { query } });
    
    // We no longer track every search query character by character
    // api.post('/api/music/history/search', null, { params: { query } }).catch(() => {});
    
    return response.data.map((item: any) => ({
      id: item.id,
      title: item.title,
      artist: item.artist,
      coverUrl: item.cover_url,
      audioUrl: item.audio_url,
      downloadUrls: item.download_urls
    }));
  } catch (error) {
    console.error("Error searching tracks:", error);
    return [];
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
    const songs = (data.topSongs || []).map((item: any) => ({
      id: item.id,
      title: item.title,
      artist: item.artist,
      coverUrl: item.coverUrl || item.cover_url,
      audioUrl: item.audioUrl || item.audio_url,
      downloadUrls: item.downloadUrls || item.download_urls
    }));
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

export const getSuggestions = async (query: string): Promise<any> => {
  if (!query) return { songs: [], artists: [], albums: [] };
  try {
    const response = await api.get('/api/music/search/suggestions', { params: { query } });
    return response.data;
  } catch (error) {
    return { songs: [], artists: [], albums: [] };
  }
};

export const addListenHistory = async (track: Song) => {
  try {
    const songId = track.id || (track as any).jiosaavn_song_id;
    if (!songId) {
      console.warn("Skipping history log: Track ID missing", track);
      return;
    }

    await api.post('/api/history/listen', {
      id: songId,
      title: track.title || "Unknown Title",
      artist: track.artist || "Unknown Artist",
      cover_url: track.coverUrl || (track as any).cover_url || "",
      audio_url: track.audioUrl || (track as any).audio_url || ""
    });
  } catch (error) {
    console.error("Failed to add to history:", error);
  }
};

export const getRecommendations = async (songId: string): Promise<Song[]> => {
  try {
    const response = await api.get(`/api/music/recommendations/${songId}`);
    const results = response.data.map((item: any) => ({
      id: item.id,
      title: item.title,
      artist: item.artist,
      coverUrl: item.cover_url,
      audioUrl: item.audio_url,
      downloadUrls: item.download_urls
    }));

    // Deduplicate by ID and filter out the current song
    const seen = new Set();
    return results.filter((s: Song) => {
      if (s.id === songId || seen.has(s.id)) return false;
      seen.add(s.id);
      return true;
    });
  } catch (error) {
    return [];
  }
};

export const getRelatedSongs = async (songId: string): Promise<Song[]> => {
  try {
    const response = await api.get(`/api/music/related/${songId}`);
    const results = response.data.map((item: any) => ({
      id: item.id,
      title: item.title,
      artist: item.artist,
      coverUrl: item.cover_url,
      audioUrl: item.audio_url,
      downloadUrls: item.download_urls
    }));

    // Deduplicate and filter out the current song
    const seen = new Set();
    return results.filter((s: Song) => {
      if (s.id === songId || seen.has(s.id)) return false;
      seen.add(s.id);
      return true;
    });
  } catch (error) {
    return [];
  }
};

export const getLikedSongs = async (): Promise<Song[]> => {
  try {
    const response = await api.get('/api/music/liked');
    return response.data;
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
    return response.data.map((item: any) => ({
      id: item.jiosaavn_song_id,
      historyId: item.id, // The UUID of the history record
      title: item.title,
      artist: item.artist,
      coverUrl: item.cover_url,
      audioUrl: item.audio_url
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

export const saveSearchClick = async (track: Song) => {
  try {
    await api.post('/api/history/search-click', {
      id: track.id,
      title: track.title || "Unknown Title",
      artist: track.artist || "Unknown Artist",
      cover_url: track.coverUrl || "",
      audio_url: track.audioUrl || ""
    });
  } catch (error) {
    console.error("Error saving search click:", error);
  }
};

export const getRecentSearches = async (): Promise<(Song & { historyId: string })[]> => {
  try {
    const response = await api.get('/api/history/recent-searches');
    return response.data.map((item: any) => ({
      id: item.jiosaavn_song_id,
      historyId: item.id,
      title: item.title,
      artist: item.artist,
      coverUrl: item.cover_url,
      audioUrl: item.audio_url
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

export const getPlaylistDetail = async (id: string): Promise<{ title: string, songs: Song[] }> => {
  try {
    const response = await api.get(`/api/playlists/${id}`);
    const { title, tracks } = response.data;
    const songs = (tracks || []).map((t: any) => ({
      id: t.jiosaavn_song_id,
      title: t.title || "Unknown Title",
      artist: t.artist || "Unknown Artist",
      coverUrl: t.cover_url || t.coverUrl,
      audioUrl: t.audio_url || t.audioUrl
    }));
    return { title, songs };
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

export default api;
