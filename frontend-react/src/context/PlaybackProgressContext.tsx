import React, { createContext, useContext, useState, useRef, useCallback } from 'react';

export interface PlaybackProgressContextType {
  currentTime: number;
  duration: number;
  progress: number;
  isSeeking: boolean;
  setIsSeeking: (seeking: boolean) => void;
  setCurrentTime: React.Dispatch<React.SetStateAction<number>>;
  setDuration: React.Dispatch<React.SetStateAction<number>>;
  seekToTime: number | null;
  seekTo: (value: number) => void;
  resetProgress: (initialDuration?: number) => void;
}

const PlaybackProgressContext = createContext<PlaybackProgressContextType | undefined>(undefined);

interface PlaybackProgressProviderProps {
  children: React.ReactNode;
  youtubePlayerRef?: React.RefObject<any>;
}

export const PlaybackProgressProvider: React.FC<PlaybackProgressProviderProps> = ({ 
  children, 
  youtubePlayerRef 
}) => {
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [isSeeking, setIsSeekingState] = useState(false);
  const [seekToTime, setSeekToTime] = useState<number | null>(null);
  const isSeekingRef = useRef(false);

  const setIsSeeking = useCallback((seeking: boolean) => {
    isSeekingRef.current = seeking;
    setIsSeekingState(seeking);
  }, []);

  const seekTo = useCallback((value: number) => {
    const validValue = Math.max(0, value);
    setCurrentTime(validValue);
    setSeekToTime(validValue);
    if (youtubePlayerRef?.current?.seekTo) {
      try {
        youtubePlayerRef.current.seekTo(validValue, true);
      } catch (err) {
        console.error('[PlaybackProgressContext] YouTube seek error:', err);
      }
    }
    // Clear seek trigger after brief delay so repeated seeks to same position work
    setTimeout(() => {
      setSeekToTime(null);
    }, 50);
  }, [youtubePlayerRef]);

  const resetProgress = useCallback((initialDuration: number = 0) => {
    setCurrentTime(0);
    setDuration(initialDuration > 0 ? Math.round(initialDuration) : 0);
  }, []);

  const value = {
    currentTime,
    duration,
    progress: currentTime,
    isSeeking,
    setIsSeeking,
    setCurrentTime,
    setDuration,
    seekToTime,
    seekTo,
    resetProgress,
  };

  return (
    <PlaybackProgressContext.Provider value={value}>
      {children}
    </PlaybackProgressContext.Provider>
  );
};

export const usePlaybackProgress = (): PlaybackProgressContextType => {
  const context = useContext(PlaybackProgressContext);
  if (!context) {
    throw new Error('usePlaybackProgress must be used within a PlaybackProgressProvider');
  }
  return context;
};
