import React, { createContext, useContext, useState, useRef, useEffect, useCallback } from 'react';
import type { Song } from '../types';
import api, { addListenHistory } from '../services/api';
import { useAuth } from './AuthContext';
import AudioPlayer from '../components/AudioPlayer';
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
  playContext: (track: Song, tracks?: Song[]) => void;
  togglePlay: () => void;
  seekTo: (value: number) => void;
  setVolume: (value: number) => void;
  toggleRepeat: () => void;
  toggleShuffle: () => void;
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
  isBuffering: boolean;
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
  const [isBuffering, setIsBuffering] = useState(false);
  const [seekToTime, setSeekToTime] = useState<number | null>(null);

  const [queue, setQueue] = useState<Song[]>([]);
  const [history, setHistory] = useState<Song[]>([]);
  const [remainingSleepTime, setRemainingSleepTime] = useState<number | null>(null);
  const [isEndOfTrackTimer, setIsEndOfTrackTimer] = useState(false);
  const [userPlaylists, setUserPlaylists] = useState<any[]>([]);
  
  const youtubePlayer = useRef<any>(null);
  const isActionLocked = useRef(false);

  // --- 2. STABLE ACTION HANDLERS ---
  const playNext = useCallback(() => {
    if (repeatMode === 'one' && youtubePlayer.current) {
      youtubePlayer.current.seekTo(0);
      youtubePlayer.current.playVideo();
      setIsPlaying(true);
      return;
    }

    if (queue.length > 0) {
      const nextTrack = queue[0];
      setQueue(prev => prev.slice(1));
      
      if (currentTrack) {
        setHistory(prev => [currentTrack, ...prev.slice(0, 49)]);
      }
      
      setCurrentTrack(nextTrack);
    } else {
      setIsPlaying(false);
    }
  }, [queue, currentTrack, repeatMode]);

  const playPrevious = useCallback(() => {
    if (isActionLocked.current) return;

    if (currentTime > 3) {
      if (youtubePlayer.current) {
        youtubePlayer.current.seekTo(0);
      }
      return;
    }

    if (history.length === 0) {
      if (youtubePlayer.current) {
        youtubePlayer.current.seekTo(0);
      }
      return;
    }

    isActionLocked.current = true;
    const prevTrack = history[0];
    setHistory(prev => prev.slice(1));
    
    if (currentTrack) {
      setQueue(prev => [currentTrack, ...prev]);
    }
    
    setCurrentTrack(prevTrack);
    setTimeout(() => { isActionLocked.current = false; }, 500);
  }, [history, currentTrack, currentTime]);

  const togglePlay = useCallback(() => {
    if (isPlaying) {
      youtubePlayer.current?.pauseVideo();
      setIsPlaying(false);
    } else {
      youtubePlayer.current?.playVideo();
      setIsPlaying(true);
    }
  }, [isPlaying]);

  const playContext = useCallback((clickedSong: Song, contextArray: Song[] = []) => {
    setCurrentTrack(clickedSong);
    
    const songIndex = contextArray.findIndex(s => s.id === clickedSong.id);
    if (songIndex !== -1) {
      const nextSongs = contextArray.slice(songIndex + 1);
      setQueue(nextSongs);
      setContextMemory(contextArray);
    }
    
    setIsPlaying(true);
  }, []);

  const playFromSearch = useCallback((track: Song) => {
    setQueue([]);
    setContextMemory(null);
    setCurrentTrack(track);
    setIsPlaying(true);
  }, []);

  const addToQueue = (track: Song) => {
    setQueue(prev => [...prev, track]);
  };

  const removeFromQueue = (trackId: string) => {
    setQueue(prev => prev.filter(t => t.id !== trackId));
  };

  const reorderQueue = useCallback((startIndex: number, endIndex: number) => {
    setQueue(prev => {
      const result = Array.from(prev);
      const [removed] = result.splice(startIndex, 1);
      result.splice(endIndex, 0, removed);
      return result;
    });
  }, []);

  const handleOnDragEnd = useCallback((result: any) => {
    if (!result.destination) return;
    reorderQueue(result.source.index, result.destination.index);
  }, [reorderQueue]);

  const seekTo = (value: number) => {
    setSeekToTime(value);
    setTimeout(() => setSeekToTime(null), 10);
  };

  const setVolume = (value: number) => {
    const vol = Math.max(0, Math.min(1, value));
    setVolumeState(vol);
    if (youtubePlayer.current) {
        youtubePlayer.current.setVolume(vol * 100);
    }
  };

  const toggleRepeat = () => {
    setRepeatMode(prev => prev === 'none' ? 'all' : prev === 'all' ? 'one' : 'none');
  };

  const toggleShuffle = () => {
    setIsShuffle(prev => !prev);
    if (!isShuffle) {
      setQueue(prev => shuffleArray(prev));
    } else if (contextMemory && currentTrack) {
      const songIndex = contextMemory.findIndex(s => s.id === currentTrack.id);
      if (songIndex !== -1) {
        setQueue(contextMemory.slice(songIndex + 1));
      }
    }
  };

  const setSleepTimer = (minutes: number | 'end' | null) => {
    if (minutes === null) {
      setRemainingSleepTime(null);
      setIsEndOfTrackTimer(false);
      return;
    }
    if (minutes === 'end') {
      setIsEndOfTrackTimer(true);
      setRemainingSleepTime(null);
      return;
    }
    setRemainingSleepTime(minutes * 60);
    setIsEndOfTrackTimer(false);
  };

  useEffect(() => {
    if (remainingSleepTime === null || remainingSleepTime <= 0) return;
    const timer = setInterval(() => {
      setRemainingSleepTime(prev => {
        if (prev !== null && prev <= 1) {
          setIsPlaying(false);
          youtubePlayer.current?.pauseVideo();
          return null;
        }
        return prev !== null ? prev - 1 : null;
      });
    }, 1000);
    return () => clearInterval(timer);
  }, [remainingSleepTime]);

  const refreshPlaylists = async () => {
    try {
      const response = await api.get('/api/playlists');
      setUserPlaylists(response.data || []);
    } catch (error) {
      console.error("Failed to fetch playlists:", error);
    }
  };

  useEffect(() => {
    if (user) refreshPlaylists();
  }, [user]);

  const clearHistory = () => {
    setHistory([]);
  };

  const onEnded = useCallback(() => {
    if (isEndOfTrackTimer) {
      setIsEndOfTrackTimer(false);
      setIsPlaying(false);
      youtubePlayer.current?.pauseVideo();
      return;
    }
    
    if (repeatMode === 'one') {
      youtubePlayer.current?.seekTo(0);
      youtubePlayer.current?.playVideo();
      setIsPlaying(true);
      return;
    }

    playNext();
  }, [isEndOfTrackTimer, repeatMode, playNext]);

  // --- 3. EFFECTS ---
  useEffect(() => {
    if (!currentTrack) return;
    setIsPlaying(true);
    addListenHistory(currentTrack);
  }, [currentTrack]);


  useEffect(() => {
    if (!currentTrack || !('mediaSession' in navigator)) return;
    navigator.mediaSession.metadata = new MediaMetadata({
      title: currentTrack.title,
      artist: currentTrack.artist,
      album: currentTrack.album || '',
      artwork: [{ src: getValidImage(currentTrack), sizes: '512x512', type: 'image/png' }]
    });
  }, [currentTrack]);

  useEffect(() => {
    if (!('mediaSession' in navigator)) return;

    navigator.mediaSession.setActionHandler('play', () => {
      youtubePlayer.current?.playVideo();
      setIsPlaying(true);
    });

    navigator.mediaSession.setActionHandler('pause', () => {
      youtubePlayer.current?.pauseVideo();
      setIsPlaying(false);
    });

    navigator.mediaSession.setActionHandler('nexttrack', () => {
      playNext();
    });

    navigator.mediaSession.setActionHandler('previoustrack', () => {
      playPrevious();
    });

    navigator.mediaSession.setActionHandler('seekto', (details) => {
      if (details.seekTime !== undefined && youtubePlayer.current) {
        youtubePlayer.current.seekTo(details.seekTime);
        setCurrentTime(details.seekTime);
      }
    });
  }, [playNext, playPrevious]);

  useEffect(() => {
    if ('mediaSession' in navigator) {
      navigator.mediaSession.playbackState = isPlaying ? 'playing' : 'paused';

      navigator.mediaSession.setActionHandler('play', () => {
        youtubePlayer.current?.playVideo();
        setIsPlaying(true);
      });

      navigator.mediaSession.setActionHandler('pause', () => {
         youtubePlayer.current?.pauseVideo();
         setIsPlaying(false);
      });

      navigator.mediaSession.setActionHandler('previoustrack', playPrevious);
      navigator.mediaSession.setActionHandler('nexttrack', playNext);
    }
  }, [isPlaying, playPrevious, playNext]);

  return (
    <AudioContext.Provider value={{ 
      currentTrack, isPlaying, currentTime, setCurrentTime, duration, isSeeking, setIsSeeking, volume, isShuffle, repeatMode,
      remainingSleepTime, queue, history, userPlaylists,
      togglePlay, seekTo, setVolume, toggleRepeat,
      toggleShuffle,
      playNext, playPrevious,
      setSleepTimer, addToQueue, removeFromQueue, reorderQueue, handleOnDragEnd, refreshPlaylists, setQueue, clearHistory, playContext, playFromSearch,
      onEnded, progress: currentTime, isBuffering
    }}>
      {children}
      <AudioPlayer 
        currentVideoId={currentTrack?.id || null}
        isPlaying={isPlaying}
        volume={volume}
        seekToTime={seekToTime}
        onTimeUpdate={setCurrentTime}
        onDurationChange={setDuration}
        onReady={(player) => {
           youtubePlayer.current = player;
        }}
        onEnd={onEnded}
        onStateChange={() => {
           // We keep the contextual callback for any side-effects, 
           // but the primary state sync now happens inside AudioPlayer.
        }}
        setIsPlaying={setIsPlaying}
        setIsBuffering={setIsBuffering}
      />
    </AudioContext.Provider>
  );
};

export const useAudio = () => {
  const context = useContext(AudioContext);
  if (context === undefined) throw new Error('useAudio must be used within an AudioProvider');
  return context;
};
