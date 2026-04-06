import React, { createContext, useContext, useState, useRef, useEffect, useCallback } from 'react';
import type { Song } from '../types';
import api, { addListenHistory, mapHistoryToSong } from '../services/api';
import { useAuth } from './AuthContext';
import { getValidImage } from '../utils/imageUtils';

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
  currentTime: number;
  setCurrentTime: React.Dispatch<React.SetStateAction<number>>;
  duration: number;
  isSeeking: boolean;
  setIsSeeking: React.Dispatch<React.SetStateAction<boolean>>;
  progress: number; 
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
  history: Song[];
  userPlaylists: any[];
  addToQueue: (track: Song) => void;
  removeFromQueue: (trackId: string) => void;
  reorderQueue: (startIndex: number, endIndex: number) => void;
  handleOnDragEnd: (result: any) => void;
  refreshPlaylists: () => Promise<void>;
  setQueue: React.Dispatch<React.SetStateAction<Song[]>>;
  clearHistory: () => void;
  playFromSearch: (track: Song) => void;
  audioRef: React.RefObject<HTMLAudioElement | null>;
  onEnded: () => void;
}

const AudioContext = createContext<AudioContextType | undefined>(undefined);

export const AudioProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { user } = useAuth();
  const [currentTrack, setCurrentTrack] = useState<Song | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [isSeeking, setIsSeeking] = useState(false);
  const [volume, setVolumeState] = useState(0.7);
  const [isShuffle, setIsShuffle] = useState(false);
  const [repeatMode, setRepeatMode] = useState<'none' | 'all' | 'one'>('none');
  const [contextMemory, setContextMemory] = useState<Song[] | null>(null);
  const [audioQuality, setAudioQualityState] = useState<'low' | 'medium' | 'high'>('high');
  const [queue, setQueue] = useState<Song[]>([]);
  const [history, setHistory] = useState<Song[]>([]);
  const [remainingSleepTime, setRemainingSleepTime] = useState<number | null>(null);
  const [isEndOfTrackTimer, setIsEndOfTrackTimer] = useState(false);
  const [userPlaylists, setUserPlaylists] = useState<any[]>([]);
  
  const audioRef = useRef<HTMLAudioElement>(null);
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
  const playNext = useCallback((e?: any) => {
    // Detect if this was called from the onEnded event
    const isNaturalEnd = e && typeof e === 'object' && e.target;

    if (isNaturalEnd && repeatMode === 'one' && audioRef.current) {
      audioRef.current.currentTime = 0;
      audioRef.current.play().then(() => setIsPlaying(true)).catch(err => console.error("Repeat failed:", err));
      return;
    }

    if (isActionLocked.current) return;
    
    setQueue(prevQueue => {
      if (prevQueue.length === 0) {
        if (isNaturalEnd && repeatMode === 'all' && contextMemory && contextMemory.length > 0) {
          const nextTrack = contextMemory[0];
          setCurrentTrack(prev => {
            if (prev) setHistory(h => [...h, prev]);
            return nextTrack;
          });
          setIsPlaying(true);
          return contextMemory.slice(1);
        }
        setIsPlaying(false);
        return prevQueue;
      }

      isActionLocked.current = true;
      setTimeout(() => isActionLocked.current = false, 800);

      const nextTrack = prevQueue[0];

      setCurrentTrack(currentlyPlaying => {
        if (currentlyPlaying) {
          setHistory(h => {
            if (h.length > 0 && h[h.length - 1].id === currentlyPlaying.id) return h;
            return [...h, currentlyPlaying];
          });
        }
        return nextTrack;
      });

      setIsPlaying(true);
      return prevQueue.slice(1);
    });
  }, [repeatMode, contextMemory]);

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
    if (isPlaying && audio) {
      audio.pause();
      setIsPlaying(false);
    } else if (audio) {
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

  const playFromSearch = useCallback((song: Song) => {
    // 1. Set the clicked song as the current track and update history
    setCurrentTrack(prev => {
      if (prev && prev.id !== song.id) {
        setHistory(h => {
          if (h.length > 0 && h[h.length - 1].id === prev.id) return h;
          return [...h, prev];
        });
      }
      return song;
    });

    // 2. Clear the old queue and set ONLY this song as a manual entry.
    // Because the queue length is now 1, our existing Pre-Fetch useEffect 
    // will automatically trigger and fetch the Radio Mix for this new song!
    setQueue([{ ...song, isManual: true }]);

    // 3. Ensure playback starts
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

  const addToQueue = useCallback((song: Song) => {
    setQueue(prevQueue => {
      // Prevent duplicates (including currently playing)
      if (prevQueue.some(s => s.id === song.id) || currentTrack?.id === song.id) return prevQueue;

      const manualSongs = prevQueue.filter(s => s.isManual);
      const autoSongs = prevQueue.filter(s => !s.isManual);

      // Add to the end of manual songs, before auto songs
      return [...manualSongs, { ...song, isManual: true }, ...autoSongs];
    });
  }, [currentTrack]);

  const removeFromQueue = (trackId: string) => {
    setQueue(prev => prev.filter(s => s.id !== trackId));
  };

  const reorderQueue = (startIndex: number, endIndex: number) => {
    setQueue(prev => {
      const result = Array.from(prev);
      const [removed] = result.splice(startIndex, 1);
      result.splice(endIndex, 0, removed);
      return result;
    });
  };

  const handleOnDragEnd = useCallback((result: any) => {
    // 1. Guard clause for invalid drops
    if (!result.destination || result.destination.index === result.source.index) return;

    // 2. Throttling lock
    if (isActionLocked.current) return;
    isActionLocked.current = true;
    setTimeout(() => isActionLocked.current = false, 500); // 500ms lock for drag-drop

    // 3. Perform atomic update
    reorderQueue(result.source.index, result.destination.index);
  }, [reorderQueue]);

  const seekTo = (value: number) => {
    if (audioRef.current) {
        audioRef.current.currentTime = value;
        setCurrentTime(value);
    }
  };

  const setVolume = (value: number) => {
    const vol = Math.max(0, Math.min(1, value));
    setVolumeState(vol);
    if (audioRef.current) audioRef.current.volume = vol;
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
    if (!audio) return;
    
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

    // Access the latest queue length and context memory via functional check
    setQueue(prevQueue => {
      if (repeatMode === 'all' && prevQueue.length === 0 && contextMemory && contextMemory.length > 0) {
        setCurrentTrack(prevTrack => {
          if (prevTrack) setHistory(h => [...h, prevTrack]);
          return contextMemory[0];
        });
        setIsPlaying(true);
        return contextMemory.slice(1);
      }
      
      // If we are not repeating all or still have items, let playNext handle it
      // We call playNext outside or handle it here. 
      // To keep it simple and bulletproof, we trigger playNext directly here.
      return prevQueue; 
    });

    playNext();
  }, [isEndOfTrackTimer, repeatMode, contextMemory, playNext]);

  useEffect(() => {
    if (audioRef.current) {
      audioRef.current.volume = volume;
    }
  }, [volume]);

  // Force Auto-play on Track/Quality Changes
  useEffect(() => {
    if (!currentTrack || !audioRef.current) return;
    const audio = audioRef.current;
    const targetUrl = getUrlByQuality(currentTrack, audioQuality);
    
    if (!targetUrl) {
      setIsPlaying(false);
      return;
    }

    const isQualitySwitch = lastTrackId.current === currentTrack.id;
    
    if (isQualitySwitch) {
        const currentTimeBefore = audio.currentTime;
        audio.src = targetUrl;
        audio.load();
        audio.currentTime = currentTimeBefore;
    } else {
        lastTrackId.current = currentTrack.id;
        // For new tracks, the src attribute update on the component re-render 
        // will handle it, but we force play here to ensure continuity.
    }

    // Force play immediately on track change
    audio.play()
      .then(() => {
        setIsPlaying(true);
        if (!isQualitySwitch) addListenHistory(currentTrack);
      })
      .catch(err => {
        console.error("Auto-play prevented:", err);
        // Don't set isPlaying(false) here, as it might just be the browser 
        // waiting for user interaction on the first-ever play.
      });
  }, [currentTrack, audioQuality]);

  // Media Session Metadata (OS Lock Screen & Media Hubs)
  useEffect(() => {
    if (!currentTrack || !('mediaSession' in navigator)) return;
    
    const artworkUrl = getValidImage(currentTrack);

    navigator.mediaSession.metadata = new MediaMetadata({
      title: currentTrack.title || 'Unknown Title',
      artist: currentTrack.artist || (currentTrack as any).subtitle || (currentTrack as any).primary_artists || 'Unknown Artist',
      album: (currentTrack as any).album || 'Paatu Padava',
      artwork: [
        { src: artworkUrl, sizes: '96x96', type: 'image/png' },
        { src: artworkUrl, sizes: '128x128', type: 'image/png' },
        { src: artworkUrl, sizes: '192x192', type: 'image/png' },
        { src: artworkUrl, sizes: '256x256', type: 'image/png' },
        { src: artworkUrl, sizes: '384x384', type: 'image/png' },
        { src: artworkUrl, sizes: '512x512', type: 'image/png' },
      ]
    });
  }, [currentTrack]);

  // Hardware Media Controls (Bluetooth, Lock Screen Buttons)
  useEffect(() => {
    if (!('mediaSession' in navigator)) return;

    navigator.mediaSession.setActionHandler('play', async () => {
      if (audioRef.current) {
        try {
          await audioRef.current.play();
          setIsPlaying(true);
          navigator.mediaSession.playbackState = "playing";
        } catch (err) {
          console.error("Hardware play failed:", err);
        }
      }
    });

    navigator.mediaSession.setActionHandler('pause', () => {
      if (audioRef.current) {
        audioRef.current.pause();
        setIsPlaying(false);
        navigator.mediaSession.playbackState = "paused";
      }
    });

    navigator.mediaSession.setActionHandler('nexttrack', () => {
      playNext();
    });

    navigator.mediaSession.setActionHandler('previoustrack', () => {
      playPrevious();
    });

    navigator.mediaSession.setActionHandler('seekto', (details) => {
      if (details.seekTime !== undefined && audioRef.current) {
        audioRef.current.currentTime = details.seekTime;
        setCurrentTime(details.seekTime);
      }
    });

    return () => {
      navigator.mediaSession.setActionHandler('play', null);
      navigator.mediaSession.setActionHandler('pause', null);
      navigator.mediaSession.setActionHandler('nexttrack', null);
      navigator.mediaSession.setActionHandler('previoustrack', null);
      navigator.mediaSession.setActionHandler('seekto', null);
    };
  }, [playNext, playPrevious]);

  // Keep MediaSession Playback State in sync with UI
  useEffect(() => {
    if ('mediaSession' in navigator) {
      navigator.mediaSession.playbackState = isPlaying ? "playing" : "paused";
    }
  }, [isPlaying]);

  // Pre-fetch
  useEffect(() => {
    if (!currentTrack || repeatMode !== 'none' || isFetchingRadio.current) return;
    if (queue.length > 2 || isFetchingRadio.current) return;
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
            // 1. Strict Deduplication (vital for DND)
            const existingIds = new Set(prevQueue.map(song => song.id));
            if (currentTrack) existingIds.add(currentTrack.id);
            // Also exclude recently played history for better variety
            history.forEach(h => existingIds.add(h.id));

            // Only add brand new songs
            const newGraphSongs = mappedSongs.filter((newSong: Song) => !existingIds.has(newSong.id));

            // 2. Blend: Add recommended songs to the bottom of the draggable queue (Auto-generated)
            const autoSongs = newGraphSongs.map((s: Song) => ({ ...s, isManual: false }));
            return [...prevQueue, ...autoSongs];
          });
        }
      } catch (e) { console.error("Pre-fetch failed:", e); }
      finally { isFetchingRadio.current = false; }
    };
    preFetch();
  }, [currentTrack?.id, queue.length, repeatMode, history]);

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
      currentTrack, isPlaying, currentTime, setCurrentTime, duration, isSeeking, setIsSeeking, volume, isShuffle, repeatMode, audioQuality,
      remainingSleepTime, queue, history, userPlaylists,
      togglePlay, seekTo, setVolume, toggleRepeat, toggleShuffle, setAudioQuality, playNext, playPrevious,
      setSleepTimer, addToQueue, removeFromQueue, reorderQueue, handleOnDragEnd, refreshPlaylists, setQueue, clearHistory, playContext, playFromSearch,
      audioRef, onEnded, progress: currentTime
    }}>
      {children}
      <audio
        ref={audioRef}
        src={currentTrack ? getUrlByQuality(currentTrack, audioQuality) : undefined}
        onTimeUpdate={() => {
          if (!isSeeking && audioRef.current) {
            setCurrentTime(audioRef.current.currentTime || 0);
          }
        }}
        onLoadedMetadata={() => {
          if (audioRef.current) {
            const d = audioRef.current.duration;
            setDuration(isFinite(d) ? d : 0);
          }
        }}
        onEnded={playNext} 
      />
    </AudioContext.Provider>
  );
};

export const useAudio = () => {
  const context = useContext(AudioContext);
  if (context === undefined) throw new Error('useAudio must be used within an AudioProvider');
  return context;
};
