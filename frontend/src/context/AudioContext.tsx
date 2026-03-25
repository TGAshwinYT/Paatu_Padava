import React, { createContext, useContext, useState, useRef, useEffect } from 'react';
import type { Song } from '../types';
import api, { addListenHistory, getRelatedSongs } from '../services/api';
import { useAuth } from './AuthContext';


interface AudioContextType {
  currentTrack: Song | null;
  isPlaying: boolean;
  progress: number;
  duration: number;
  volume: number;
  isRepeating: boolean;
  isShuffled: boolean;
  audioQuality: 'low' | 'medium' | 'high';
  playTrack: (track: Song, queue?: Song[]) => void;
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
  userQueue: Song[];
  userPlaylists: any[];
  addToQueue: (track: Song) => void;
  removeFromQueue: (trackId: string) => void;
  reorderQueue: (startIndex: number, endIndex: number) => void;
  refreshPlaylists: () => Promise<void>;
}

const AudioContext = createContext<AudioContextType | undefined>(undefined);

export const AudioProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { user } = useAuth();
  const [currentTrack, setCurrentTrack] = useState<Song | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [progress, setProgress] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolumeState] = useState(0.7);
  const [isRepeating, setIsRepeating] = useState(false);
  const [isShuffled, setIsShuffled] = useState(false);
  const [audioQuality, setAudioQualityState] = useState<'low' | 'medium' | 'high'>('high');
  const [queue, setQueue] = useState<Song[]>([]);
  const [currentIndex, setCurrentIndex] = useState(-1);
  const [remainingSleepTime, setRemainingSleepTime] = useState<number | null>(null);
  const [isEndOfTrackTimer, setIsEndOfTrackTimer] = useState(false);
  const [userQueue, setUserQueue] = useState<Song[]>([]);
  const [userPlaylists, setUserPlaylists] = useState<any[]>([]);
  
  const audioRef = useRef<HTMLAudioElement>(new Audio());
  const lastTrackId = useRef<string | null>(null);

  // Helper to get URL by quality
  const getUrlByQuality = (song: Song, quality: 'low' | 'medium' | 'high') => {
    if (!song.downloadUrls || song.downloadUrls.length === 0) return song.audioUrl;
    
    // Mapping: low -> index 0, medium -> index 2, high -> index 4
    const index = quality === 'low' ? 0 : quality === 'medium' ? 2 : 4;
    return song.downloadUrls[Math.min(index, song.downloadUrls.length - 1)] || song.audioUrl;
  };

  useEffect(() => {
    const audio = audioRef.current;
    audio.volume = volume;

    const onTimeUpdate = () => setProgress(audio.currentTime);
    const onLoadedMetadata = () => setDuration(audio.duration);
    const onEnded = () => {
      if (isEndOfTrackTimer) {
        setIsEndOfTrackTimer(false);
        setIsPlaying(false);
        audio.pause();
        return;
      }

      if (isRepeating) {
        audio.currentTime = 0;
        audio.play().then(() => setIsPlaying(true));
        return;
      }
      
      // If we're at the end of the queue and autoplay is off, stop
      const isLastInQueue = currentIndex === queue.length - 1;
      if (isLastInQueue && userQueue.length === 0) {
        setIsPlaying(false);
        // We still call playNext() to trigger autoplay/related songs if possible
        playNext();
        return;
      }

      playNext();
    };

    audio.addEventListener('timeupdate', onTimeUpdate);
    audio.addEventListener('loadedmetadata', onLoadedMetadata);
    audio.addEventListener('ended', onEnded);

    return () => {
      audio.removeEventListener('timeupdate', onTimeUpdate);
      audio.removeEventListener('loadedmetadata', onLoadedMetadata);
      audio.removeEventListener('ended', onEnded);
    };
  }, [isRepeating, currentIndex, queue, userQueue, isShuffled]); // Re-bind onEnded when dependencies change

  // Handle track or quality changes
  useEffect(() => {
    if (!currentTrack) return;

    const audio = audioRef.current;
    const targetUrl = getUrlByQuality(currentTrack, audioQuality);
    
    if (!targetUrl) {
      console.warn("⚠️ Cannot play track: audioUrl is empty");
      setIsPlaying(false);
      return;
    }

    // ONLY restore currentTime if the track hasn't changed (quality switch)
    const isQualitySwitch = lastTrackId.current === currentTrack.id;
    const currentTime = isQualitySwitch ? audio.currentTime : 0;
    const wasPlaying = !audio.paused;

    audio.src = targetUrl;
    audio.currentTime = currentTime;
    lastTrackId.current = currentTrack.id;
    
    if (wasPlaying || isPlaying) {
      audio.play()
        .then(() => {
          setIsPlaying(true);
          if (currentTrack) addListenHistory(currentTrack);
        })
        .catch((err) => {
          console.error("Playback failed:", err);
          setIsPlaying(false);
        });
    }

    // MediaSession API
    if ('mediaSession' in navigator && currentTrack) {
      navigator.mediaSession.metadata = new MediaMetadata({
        title: currentTrack.title,
        artist: currentTrack.artist,
        album: 'Paaatu_Padava',
        artwork: [
          { src: currentTrack.coverUrl, sizes: '512x512', type: 'image/jpeg' },
        ],
      });

      navigator.mediaSession.setActionHandler('play', () => togglePlay());
      navigator.mediaSession.setActionHandler('pause', () => togglePlay());
      navigator.mediaSession.setActionHandler('previoustrack', () => playPrevious());
      navigator.mediaSession.setActionHandler('nexttrack', () => playNext());
    }
  }, [currentTrack, audioQuality, isPlaying]);

  // Timer Countdown Logic
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
  }, [remainingSleepTime]);

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

  const refreshPlaylists = async () => {
    try {
      const { data } = await api.get('/api/playlists/');
      setUserPlaylists(data);
    } catch (error) {
      console.error("Error refreshing playlists:", error);
    }
  };

  useEffect(() => {
    if (user) {
      refreshPlaylists();
    } else {
      setUserPlaylists([]);
    }
  }, [user]);

  const addToQueue = (track: Song) => {
    setUserQueue(prev => {
      if (prev.some(s => s.id === track.id)) return prev;
      return [...prev, track];
    });
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

  const playTrack = (track: Song, newQueue?: Song[]) => {
    if (newQueue) {
      setQueue(newQueue);
      const index = newQueue.findIndex(s => s.id === track.id);
      setCurrentIndex(index);
    } else {
      setQueue(prev => {
        const exists = prev.findIndex(s => s.id === track.id);
        if (exists !== -1) {
          setCurrentIndex(exists);
          return prev;
        }
        const updated = [...prev, track];
        setCurrentIndex(updated.length - 1);
        return updated;
      });
    }
    
    // REMOVED audioRef.current.load() and currentTime = 0
    // Let the main useEffect handle the actual audio element
    setIsPlaying(true);
    setCurrentTrack(track);
  };

  const togglePlay = () => {
    const audio = audioRef.current;
    if (isPlaying) {
      audio.pause();
      setIsPlaying(false);
    } else {
      // Task 2: Restart if song finished
      if (audio.currentTime >= audio.duration) {
        audio.currentTime = 0;
      }
      audio.play().then(() => setIsPlaying(true));
    }
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

  const toggleRepeat = () => setIsRepeating(prev => !prev);
  const toggleShuffle = () => setIsShuffled(prev => !prev);

  const setAudioQuality = (quality: 'low' | 'medium' | 'high') => {
    setAudioQualityState(quality);
  };

  const playNext = async () => {
    if (queue.length === 0 && !currentTrack) return;

    // 1. User Queue Logic (Prioritize)
    if (userQueue.length > 0) {
      const nextTrack = userQueue[0];
      setUserQueue(prev => prev.slice(1)); 
      setCurrentTrack(nextTrack);
      setIsPlaying(true);
      return;
    }

    // 2. Shuffle Logic
    if (isShuffled && queue.length > 1) {
      let nextIndex;
      do {
        nextIndex = Math.floor(Math.random() * queue.length);
      } while (nextIndex === currentIndex && queue.length > 1);
      setCurrentIndex(nextIndex);
      setCurrentTrack(queue[nextIndex]);
      setIsPlaying(true);
      return;
    }

    // 2. Autoplay / Related Songs Logic
    const isLastSong = currentIndex === queue.length - 1 || currentIndex === -1;
    if (isLastSong && currentTrack) {
      try {
        const related = await getRelatedSongs(currentTrack.id, currentTrack.artist);
        if (related && related.length > 0) {
          // Filter to avoid immediate duplicates
          const newSongs = related.filter(s => !queue.some(q => q.id === s.id));
          if (newSongs.length > 0) {
            setQueue(prev => [...prev, ...newSongs]);
            const nextIdx = queue.length; // The index of the first new song
            setCurrentIndex(nextIdx);
            setCurrentTrack(newSongs[0]);
            setIsPlaying(true);
            return;
          }
        }
      } catch (error) {
        console.error("Autoplay failed:", error);
      }
    }

    // 3. Default Sequential Logic
    if (queue.length > 0) {
      const nextIndex = (currentIndex + 1) % queue.length;
      setCurrentIndex(nextIndex);
      setCurrentTrack(queue[nextIndex]);
      setIsPlaying(true);
    }
  };

  const playPrevious = () => {
    if (queue.length === 0) return;
    const prevIndex = (currentIndex - 1 + queue.length) % queue.length;
    setCurrentIndex(prevIndex);
    setCurrentTrack(queue[prevIndex]);
    setIsPlaying(true);
  };

  return (
    <AudioContext.Provider value={{ 
      currentTrack, isPlaying, progress, duration, volume, isRepeating, isShuffled, audioQuality,
      remainingSleepTime,
      userQueue,
      userPlaylists,
      playTrack, togglePlay, seekTo, setVolume, toggleRepeat, toggleShuffle, setAudioQuality, playNext, playPrevious,
      setSleepTimer, addToQueue, removeFromQueue, reorderQueue, refreshPlaylists
    }}>
      {children}
    </AudioContext.Provider>
  );
};

export const useAudio = () => {
  const context = useContext(AudioContext);
  if (context === undefined) {
    throw new Error('useAudio must be used within an AudioProvider');
  }
  return context;
};
