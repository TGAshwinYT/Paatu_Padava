import axios from 'axios';
import type { Song } from '../types';
import { getValidImage } from '../utils/imageUtils';

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

// 🚨 REGION DETECTION HELPER 🚨
const getUserRegion = async (): Promise<string> => {
  const cachedRegion = localStorage.getItem('user_region');
  if (cachedRegion) return cachedRegion;

  try {
    const response = await axios.get('https://ipapi.co/json/');
    const region = response.data.region || 'Maharashtra';
    localStorage.setItem('user_region', region);
    return region;
  } catch (error) {
    console.warn("Region detection failed, falling back to Maharashtra:", error);
    return 'Maharashtra';
  }
};

export const getHomeFeed = async (): Promise<{ recentlyPlayed: Song[], topAlbums: Song[], topArtists: Song[], recommendedForYou: Song[], personalized: boolean }> => {
  try {
    // 1. Fetch user region for localization
    const region = await getUserRegion();
    
    // 2. Pass region as query param
    const response = await api.get('/api/music/home', { params: { region } });
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
      artists: (data.artists || []).map(mapHistoryToSong),
      albums: (data.albums || []).map(mapHistoryToSong)
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
      audio_url: track.audioUrl || ""
    });
  } catch (error) {
    console.error("Failed to add to history:", error);
  }
};

export const getRecommendations = async (songId: string, artist?: string, language?: string): Promise<Song[]> => {
  try {
    const response = await api.get(`/api/music/recommendations/${songId}`, {
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

export const saveSearchClick = async (track: Song) => {
  if (!localStorage.getItem('token')) return; // Silently skip for guests
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

export const getPlaylistDetail = async (id: string): Promise<{ title: string, songs: Song[] }> => {
  try {
    const response = await api.get(`/api/playlists/${id}`);
    const { title, tracks } = response.data;
    const songs = (tracks || []).map(mapHistoryToSong);
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

export default api;
