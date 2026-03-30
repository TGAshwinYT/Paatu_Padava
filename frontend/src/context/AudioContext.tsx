import React, { createContext, useContext, useState, useRef, useEffect, useCallback } from 'react';
import type { Song } from '../types';
import api, { addListenHistory, mapHistoryToSong } from '../services/api';
import { useAuth } from './AuthContext';

const shuffleArray = (array: any[]) => {
  const shuffled = [...array];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled;
};

interface AudioContextType {
  currentTrack: Song | null;
  isPlaying: boolean;
  progress: number;
  duration: number;
  volume: number;
  isShuffle: boolean;
  repeatMode: 'none' | 'all' | 'one';
  audioQuality: 'low' | 'medium' | 'high';
  playContext: (track: Song, tracks?: Song[]) => void;
  togglePlay: () => void;
  seekTo: (value: number) => void;
  setVolume: (value: number) => void;
  toggleRepeat: () => void;
  toggleShuffle: () => void;
  setAudioQuality: (quality: 'low' | 'medium' | 'high') => void;
  playNext: () => void;
  playPrevious: () => void;
  setSleepTimer: (minutes: number | 'end' | null) => void;
  remainingSleepTime: number | null;
  queue: Song[]; 
  userQueue: Song[];
  history: Song[];
  userPlaylists: any[];
  addToQueue: (track: Song) => void;
  removeFromQueue: (trackId: string) => void;
  reorderQueue: (startIndex: number, endIndex: number) => void;
  refreshPlaylists: () => Promise<void>;
  setQueue: React.Dispatch<React.SetStateAction<Song[]>>;
  clearHistory: () => void;
  audioRef: React.RefObject<HTMLAudioElement>;
  onEnded: () => void;
}

const AudioContext = createContext<AudioContextType | undefined>(undefined);

export const AudioProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { user } = useAuth();
  const [currentTrack, setCurrentTrack] = useState<Song | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [progress, setProgress] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolumeState] = useState(0.7);
  const [isShuffle, setIsShuffle] = useState(false);
  const [repeatMode, setRepeatMode] = useState<'none' | 'all' | 'one'>('none');
  const [contextMemory, setContextMemory] = useState<Song[] | null>(null);
  const [audioQuality, setAudioQualityState] = useState<'low' | 'medium' | 'high'>('high');
  const [queue, setQueue] = useState<Song[]>([]);
  const [history, setHistory] = useState<Song[]>([]);
  const [remainingSleepTime, setRemainingSleepTime] = useState<number | null>(null);
  const [isEndOfTrackTimer, setIsEndOfTrackTimer] = useState(false);
  const [userQueue, setUserQueue] = useState<Song[]>([]);
  const [userPlaylists, setUserPlaylists] = useState<any[]>([]);
  
  const audioRef = useRef<HTMLAudioElement>(new Audio());
  const lastTrackId = useRef<string | null>(null);
  const isFetchingRadio = useRef(false);
  const isActionLocked = useRef(false);

  // --- 1. HELPERS ---
  const getUrlByQuality = useCallback((song: Song | any, quality: 'low' | 'medium' | 'high') => {
    const backupUrl = song.audioUrl || song.audio_url || song.url;
    if (!song.downloadUrls || song.downloadUrls.length === 0) return backupUrl;
    const index = quality === 'low' ? 0 : quality === 'medium' ? 2 : 4;
    return song.downloadUrls[Math.min(index, song.downloadUrls.length - 1)] || backupUrl;
  }, []);

  // --- 2. STABLE ACTION HANDLERS ---
  const playNext = useCallback(() => {
    if (isActionLocked.current) return;
    if (queue.length === 0 && userQueue.length === 0) {
      setIsPlaying(false);
      return;
    }

    isActionLocked.current = true;
    setTimeout(() => isActionLocked.current = false, 800);

    const nextTrack = userQueue.length > 0 ? userQueue[0] : queue[0];

    setCurrentTrack(currentlyPlaying => {
      if (currentlyPlaying) {
        setHistory(h => {
          if (h.length > 0 && h[h.length - 1].id === currentlyPlaying.id) return h;
          return [...h, currentlyPlaying];
        });
      }
      return nextTrack;
    });

    if (userQueue.length > 0) {
      setUserQueue(prev => prev.slice(1));
    } else {
      setQueue(prev => prev.slice(1));
    }
    
    setIsPlaying(true);
  }, [queue, userQueue]);

  const playPrevious = useCallback(() => {
    if (isActionLocked.current) return;

    const currentTime = audioRef.current ? audioRef.current.currentTime : 0;
    if (currentTime > 3) {
      if (audioRef.current) audioRef.current.currentTime = 0;
      return;
    }

    if (history.length === 0) {
      if (audioRef.current) audioRef.current.currentTime = 0;
      return;
    }

    isActionLocked.current = true;
    setTimeout(() => isActionLocked.current = false, 800);

    const songToRestore = history[history.length - 1];

    setCurrentTrack(currentlyPlaying => {
      if (currentlyPlaying && currentlyPlaying.id !== songToRestore.id) {
        setQueue(prevQueue => {
          const cleanQueue = prevQueue.filter(s => s.id !== currentlyPlaying.id && s.id !== songToRestore.id);
          return [currentlyPlaying, ...cleanQueue];
        });
      }
      return songToRestore;
    });

    setHistory(prevHistory => prevHistory.slice(0, -1));
    setIsPlaying(true);
  }, [history]);

  const togglePlay = useCallback(() => {
    const audio = audioRef.current;
    if (isPlaying) {
      audio.pause();
      setIsPlaying(false);
    } else {
      if (!audio.src || audio.src.includes('undefined')) {
         if (currentTrack) {
            const url = getUrlByQuality(currentTrack, audioQuality);
            if (url) audio.src = url;
         }
      }
      if (audio.currentTime >= audio.duration) {
        audio.currentTime = 0;
      }
      audio.play().then(() => setIsPlaying(true)).catch(e => console.error("Play failed:", e));
    }
  }, [isPlaying, currentTrack, audioQuality, getUrlByQuality]);


  const playContext = useCallback((clickedSong: Song, contextArray: Song[] = []) => {
    // 1. Save current track to history before switching
    setCurrentTrack(prev => {
      if (prev && prev.id !== clickedSong.id) {
        setHistory(h => {
          if (h.length > 0 && h[h.length - 1].id === prev.id) return h;
          return [...h, prev];
        });
      }
      return clickedSong;
    });

    // 2. Overwrite the Queue with the REST of the array
    if (contextArray.length > 0) {
      const songIndex = contextArray.findIndex(s => s.id === clickedSong.id);
      if (songIndex !== -1) {
        setQueue(contextArray.slice(songIndex + 1));
      } else {
        setQueue([]); // Fallback
      }
      setContextMemory(contextArray);
    } else {
      setQueue([]);
      setContextMemory(null);
    }
    setIsPlaying(true);
  }, []);

  const setSleepTimer = (value: number | 'end' | null) => {
    if (value === 'end') {
      setIsEndOfTrackTimer(true);
      setRemainingSleepTime(null);
    } else if (typeof value === 'number') {
      setIsEndOfTrackTimer(false);
      setRemainingSleepTime(value * 60);
    } else {
      setIsEndOfTrackTimer(false);
      setRemainingSleepTime(null);
    }
  };

  const addToQueue = (track: Song) => {
    setUserQueue(prev => prev.some(s => s.id === track.id) ? prev : [...prev, track]);
  };

  const removeFromQueue = (trackId: string) => {
    setUserQueue(prev => prev.filter(s => s.id !== trackId));
  };

  const reorderQueue = (startIndex: number, endIndex: number) => {
    setUserQueue(prev => {
      const result = Array.from(prev);
      const [removed] = result.splice(startIndex, 1);
      result.splice(endIndex, 0, removed);
      return result;
    });
  };

  const seekTo = (value: number) => {
    audioRef.current.currentTime = value;
    setProgress(value);
  };

  const setVolume = (value: number) => {
    const vol = Math.max(0, Math.min(1, value));
    setVolumeState(vol);
    audioRef.current.volume = vol;
  };

  const toggleRepeat = () => {
    setRepeatMode(prev => {
      if (contextMemory) {
        if (prev === 'none') return 'all';
        if (prev === 'all') return 'one';
        return 'none';
      }
      return prev === 'none' ? 'one' : 'none';
    });
  };

  const toggleShuffle = () => {
    setIsShuffle(prev => {
      const next = !prev;
      if (next) {
        setQueue(current => shuffleArray(current));
      } else if (contextMemory && currentTrack) {
        const idx = contextMemory.findIndex(s => s.id === currentTrack.id);
        if (idx !== -1) setQueue(contextMemory.slice(idx + 1));
      }
      return next;
    });
  };

  const setAudioQuality = (quality: 'low' | 'medium' | 'high') => {
    setAudioQualityState(quality);
  };

  const refreshPlaylists = async () => {
    if (!user) return;
    try {
      const { data } = await api.get('/api/playlists/');
      setUserPlaylists(data);
    } catch (error) {
      console.error("Error refreshing playlists:", error);
    }
  };

  const clearHistory = () => setHistory([]);

  // --- 3. EFFECTS ---
  
  // Audio Lifecycle & Event Listeners
  const onEnded = useCallback(() => {
    const audio = audioRef.current;
    if (isEndOfTrackTimer) {
      setIsEndOfTrackTimer(false);
      setIsPlaying(false);
      audio.pause();
      return;
    }
    if (repeatMode === 'one') {
      audio.currentTime = 0;
      audio.play().then(() => setIsPlaying(true)).catch(e => console.error("Repeat failed:", e));
      return;
    }
    if (repeatMode === 'all' && (queue.length === 0 && userQueue.length === 0) && contextMemory && contextMemory.length > 0) {
      setCurrentTrack(prev => {
        if (prev) setHistory(h => [...h, prev]);
        return contextMemory[0];
      });
      setQueue(contextMemory.slice(1));
      setIsPlaying(true);
      return;
    }
    playNext();
  }, [isEndOfTrackTimer, repeatMode, queue.length, userQueue.length, contextMemory, playNext]);

  useEffect(() => {
    const audio = audioRef.current;
    audio.volume = volume;

    const onTimeUpdate = () => setProgress(audio.currentTime);
    const onLoadedMetadata = () => setDuration(audio.duration);

    audio.addEventListener('timeupdate', onTimeUpdate);
    audio.addEventListener('loadedmetadata', onLoadedMetadata);
    // audio.addEventListener('ended', onEnded); // Moving to synthetic event to prevent desync
    return () => {
      audio.removeEventListener('timeupdate', onTimeUpdate);
      audio.removeEventListener('loadedmetadata', onLoadedMetadata);
      // audio.removeEventListener('ended', onEnded);
    };
  }, [volume, isEndOfTrackTimer, repeatMode, queue.length, userQueue.length, contextMemory, playNext]);

  // Track/Quality Changes
  useEffect(() => {
    if (!currentTrack) return;
    const audio = audioRef.current;
    const targetUrl = getUrlByQuality(currentTrack, audioQuality);
    if (!targetUrl) {
      setIsPlaying(false);
      return;
    }
    const isQualitySwitch = lastTrackId.current === currentTrack.id;
    const currentTime = isQualitySwitch ? audio.currentTime : 0;
    const wasPlaying = !audio.paused || isPlaying;
    audio.pause();
    audio.src = targetUrl;
    audio.load();
    audio.currentTime = currentTime;
    lastTrackId.current = currentTrack.id;
    if (wasPlaying) {
      audio.play().then(() => {
        setIsPlaying(true);
        if (!isQualitySwitch) addListenHistory(currentTrack);
      }).catch(err => {
        console.error("Playback failed:", err);
        setIsPlaying(false);
      });
    }
    if ('mediaSession' in navigator) {
      const art = currentTrack.coverUrl || (currentTrack as any).cover_url || (currentTrack as any).image || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=512&h=512&fit=crop';
      navigator.mediaSession.metadata = new MediaMetadata({
        title: currentTrack.title,
        artist: currentTrack.artist,
        artwork: [{ src: art, sizes: '512x512', type: 'image/jpeg' }]
      });
      navigator.mediaSession.setActionHandler('play', () => togglePlay());
      navigator.mediaSession.setActionHandler('pause', () => togglePlay());
      navigator.mediaSession.setActionHandler('previoustrack', () => playPrevious());
      navigator.mediaSession.setActionHandler('nexttrack', () => playNext());
    }
  }, [currentTrack, audioQuality, getUrlByQuality, playNext, playPrevious, togglePlay, isPlaying]);

  // Pre-fetch
  useEffect(() => {
    if (!currentTrack || repeatMode !== 'none' || isFetchingRadio.current) return;
    if (queue.length > 2 || userQueue.length > 0) return;
    const preFetch = async () => {
      isFetchingRadio.current = true;
      try {
        const token = localStorage.getItem('token');
        const res = await api.get(`/api/music/recommendations/${currentTrack.id}`, {
          params: { lang: currentTrack.language || 'tamil', artist: (currentTrack as any).primaryArtists || currentTrack.artist || '' },
          headers: token ? { Authorization: `Bearer ${token}` } : {}
        });
        
        if (res.data && res.data.length > 0) {
          const mappedSongs = res.data.map(mapHistoryToSong);
          setQueue(prevQueue => {
            // Create a Set of all IDs currently in the queue, history, and the currently playing song
            const existingIds = new Set(prevQueue.map(song => song.id));
            if (currentTrack) existingIds.add(currentTrack.id);
            history.forEach(h => existingIds.add(h.id));

            // Only keep mapped songs that are NOT already in the existingIds Set
            const completelyNewSongs = mappedSongs.filter((newSong: Song) => !existingIds.has(newSong.id));

            return [...prevQueue, ...completelyNewSongs];
          });
        }
      } catch (e) { console.error("Pre-fetch failed:", e); }
      finally { isFetchingRadio.current = false; }
    };
    preFetch();
  }, [currentTrack?.id, queue.length, userQueue.length, repeatMode, history]);

  // Playlist Refresh
  useEffect(() => {
    if (user) refreshPlaylists();
    else setUserPlaylists([]);
  }, [user]);

  // Sleep Timer
  useEffect(() => {
    let interval: any;
    if (remainingSleepTime !== null && remainingSleepTime > 0) {
      interval = setInterval(() => {
        setRemainingSleepTime(prev => {
          if (prev === null || prev <= 1) {
            clearInterval(interval);
            togglePlay(); 
            return null;
          }
          return prev - 1;
        });
      }, 1000);
    }
    return () => clearInterval(interval);
  }, [remainingSleepTime, togglePlay]);

  return (
    <AudioContext.Provider value={{ 
      currentTrack, isPlaying, progress, duration, volume, isShuffle, repeatMode, audioQuality,
      remainingSleepTime, queue, userQueue, history, userPlaylists,
      togglePlay, seekTo, setVolume, toggleRepeat, toggleShuffle, setAudioQuality, playNext, playPrevious,
      setSleepTimer, addToQueue, removeFromQueue, reorderQueue, refreshPlaylists, setQueue, clearHistory, playContext,
      audioRef, onEnded
    }}>
      {children}
    </AudioContext.Provider>
  );
};

export const useAudio = () => {
  const context = useContext(AudioContext);
  if (context === undefined) throw new Error('useAudio must be used within an AudioProvider');
  return context;
};
