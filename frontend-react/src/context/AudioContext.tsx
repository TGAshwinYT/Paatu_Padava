import React, { createContext, useContext, useState, useRef, useEffect, useCallback, useMemo } from 'react';
import type { Song, PlaybackEngine } from '../types';
import { addListenHistory, downloadSongFile } from '../services/api';
import { useAuth } from './AuthContext';
import { useEqualizer } from '../hooks/useEqualizer';
import { PlaybackProgressProvider } from './PlaybackProgressContext';
import { QueueProvider } from './QueueContext';
import type { AudioActionsContextType, AudioContextType } from './audio/audioTypes';
import { useAudioPlaylistState } from './audio/useAudioPlaylistState';
import { useAudioPersistence } from './audio/useAudioPersistence';
import { useHybridPlayback } from './audio/useHybridPlayback';
import { useAutoplayRadio } from './audio/useAutoplayRadio';
import { useAudioQueueActions } from './audio/useAudioQueueActions';
import { AudioPlayerBridge } from './audio/AudioPlayerBridge';

export { usePlaybackProgress } from './PlaybackProgressContext';
export type { PlaybackProgressContextType } from './PlaybackProgressContext';
export { useQueue, QueueProvider } from './QueueContext';
export type { QueueContextType } from './QueueContext';
export type { AudioActionsContextType, AudioContextType } from './audio/audioTypes';

const AudioActionsContext = createContext<AudioActionsContextType | undefined>(undefined);
const AudioContext = createContext<AudioContextType | undefined>(undefined);

export const useAudioActions = (): AudioActionsContextType => {
  const context = useContext(AudioActionsContext);
  if (context === undefined) throw new Error('useAudioActions must be used within an AudioProvider');
  return context;
};

export const AudioProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { user } = useAuth();
  const {
    bands: eqBands, activePreset: eqPreset, isEqAvailable,
    setBandGain: setEqBandGain, applyPreset: applyEqPreset,
    connectSource: connectEqSource, setEqEnabled,
  } = useEqualizer();

  const [crossfadeDuration, setCrossfadeDurationState] = useState<number>(() => {
    try {
      const saved = localStorage.getItem('paatu_crossfade_duration');
      if (saved !== null) {
        const val = parseFloat(saved);
        if (!isNaN(val) && val >= 0 && val <= 12) return val;
      }
    } catch { /* ignore */ }
    return 0;
  });

  const setCrossfadeDuration = useCallback((seconds: number) => {
    const clamped = Math.max(0, Math.min(12, seconds));
    setCrossfadeDurationState(clamped);
    try { localStorage.setItem('paatu_crossfade_duration', String(clamped)); } catch { /* ignore */ }
  }, []);

  const [isAutoplay, setIsAutoplayState] = useState<boolean>(() => {
    try {
      const saved = localStorage.getItem('paatu_autoplay');
      return saved === null ? true : saved === 'true';
    } catch { return true; }
  });

  const isAutoplayRef = useRef(isAutoplay);
  useEffect(() => { isAutoplayRef.current = isAutoplay; }, [isAutoplay]);

  const setIsAutoplay = useCallback((enabled: boolean) => {
    setIsAutoplayState(enabled);
    isAutoplayRef.current = enabled;
    try { localStorage.setItem('paatu_autoplay', String(enabled)); } catch { /* ignore */ }
  }, []);

  const toggleAutoplay = useCallback(() => {
    setIsAutoplayState(prev => {
      const next = !prev;
      isAutoplayRef.current = next;
      try { localStorage.setItem('paatu_autoplay', String(next)); } catch { /* ignore */ }
      return next;
    });
  }, []);

  const [currentTrack, setCurrentTrack] = useState<Song | null>(() => {
    try {
      const saved = localStorage.getItem('paatu_current_track');
      return saved ? JSON.parse(saved) : null;
    } catch { return null; }
  });

  const [isPlaying, setIsPlaying] = useState(false);
  const currentTimeRef = useRef(0);

  const [volume, setVolumeState] = useState<number>(() => {
    try {
      const saved = localStorage.getItem('paatu_player_volume');
      if (saved !== null) {
        const val = parseFloat(saved);
        if (!isNaN(val) && val >= 0 && val <= 1) return val;
      }
    } catch { /* ignore */ }
    return 1;
  });

  const [isShuffle, setIsShuffle] = useState<boolean>(() => {
    try { return localStorage.getItem('paatu_player_shuffle') === 'true'; } catch { return false; }
  });

  const [repeatMode, setRepeatMode] = useState<'none' | 'all' | 'one'>(() => {
    try {
      const saved = localStorage.getItem('paatu_player_repeat');
      if (saved === 'none' || saved === 'all' || saved === 'one') return saved;
    } catch { /* ignore */ }
    return 'none';
  });

  const [contextMemory, setContextMemory] = useState<Song[] | null>(() => {
    try {
      const saved = localStorage.getItem('paatu_context_memory');
      return saved ? JSON.parse(saved) : null;
    } catch { return null; }
  });

  const [isBuffering, setIsBuffering] = useState(false);
  const [queue, setQueueState] = useState<Song[]>(() => {
    try {
      const saved = localStorage.getItem('paatu_player_queue');
      return saved ? JSON.parse(saved) : [];
    } catch { return []; }
  });

  const queueRef = useRef<Song[]>(queue);
  const radioHistoryIdsRef = useRef<string[]>([]);

  const setQueue = useCallback((action: Song[] | ((prev: Song[]) => Song[])) => {
    setQueueState(prev => {
      const next = typeof action === 'function' ? action(prev) : action;
      queueRef.current = next;
      return next;
    });
  }, []);

  const [history, setHistory] = useState<Song[]>([]);
  const [remainingSleepTime, setRemainingSleepTime] = useState<number | null>(null);
  const [isEndOfTrackTimer, setIsEndOfTrackTimer] = useState(false);

  const {
    guestPlaylists, accountPlaylists, userPlaylists, refreshPlaylists,
    createGuestPlaylist, renameGuestPlaylist, deleteGuestPlaylist,
    removeSongFromGuestPlaylist, addSongToGuestPlaylist,
  } = useAudioPlaylistState(user?.id);

  const [playbackEngine, setPlaybackEngine] = useState<PlaybackEngine>(() =>
    currentTrack?.audioUrl?.trim() ? 'native' : 'youtube'
  );
  const [nativeAudioUrl, setNativeAudioUrl] = useState<string | null>(() =>
    currentTrack?.audioUrl?.trim() ? currentTrack.audioUrl : null
  );
  const [youtubeVideoId, setYoutubeVideoId] = useState<string | null>(null);
  const [isResolvingStream, setIsResolvingStream] = useState(false);

  useEffect(() => { setEqEnabled(playbackEngine === 'native'); }, [playbackEngine, setEqEnabled]);

  const [, setNextStreamUrl] = useState<string | null>(null);
  const preloadedTrackRef = useRef<{ id: string; url: string } | null>(null);
  const prefetchingSongIdRef = useRef<string | null>(null);
  const activePlayingTrackIdRef = useRef<string | null>(null);
  const isInitialMountRef = useRef(true);

  const youtubePlayer = useRef<any>(null);
  const actionLockRef = useRef(false);
  const shuffleRequestIdRef = useRef(0);
  const isShuffleRef = useRef(isShuffle);
  const currentTrackRef = useRef(currentTrack);

  useAudioPersistence({
    user, currentTrack, queue, isShuffle, repeatMode, volume, contextMemory,
    isShuffleRef, currentTrackRef, currentTimeRef, preloadedTrackRef, prefetchingSongIdRef,
    setNextStreamUrl, setQueue, setCurrentTrack, setIsShuffle, setRepeatMode, setIsPlaying,
  });

  const playContextRef = useRef<(track: Song, tracks?: Song[]) => void>(() => {});
  const { replenishAutoplayQueue, startSongRadio } = useAutoplayRadio({
    isAutoplayRef, queueRef, currentTrackRef, radioHistoryIdsRef,
    isAutoplay, isPlaying, queueLength: queue.length, currentTrack,
    setQueue, setIsAutoplay,
    playContext: useCallback((t: Song, tr?: Song[]) => playContextRef.current(t, tr), []),
  });

  const { playContext, playNext, playPrevious, playFromSearch, toggleShuffle } = useAudioQueueActions({
    queue, currentTrack, history, isShuffle, repeatMode, contextMemory,
    isShuffleRef, isAutoplayRef, currentTrackRef, currentTimeRef,
    activePlayingTrackIdRef, preloadedTrackRef, prefetchingSongIdRef, shuffleRequestIdRef,
    youtubePlayer, actionLockRef, setQueue, setCurrentTrack, setContextMemory, setHistory,
    setIsShuffle, setIsPlaying, setIsBuffering, setNativeAudioUrl, setYoutubeVideoId,
    setPlaybackEngine, setNextStreamUrl, replenishAutoplayQueue,
  });
  useEffect(() => { playContextRef.current = playContext; }, [playContext]);

  const togglePlay = useCallback(() => {
    if (isPlaying) {
      youtubePlayer.current?.pauseVideo();
      setIsPlaying(false);
    } else {
      if (!currentTrack) return;
      if (playbackEngine === 'youtube' && !youtubeVideoId && currentTrack.id) {
        setYoutubeVideoId(currentTrack.id);
      }
      youtubePlayer.current?.playVideo();
      setIsPlaying(true);
    }
  }, [isPlaying, currentTrack, playbackEngine, youtubeVideoId]);

  const playHybridTrack = useHybridPlayback({
    setCurrentTrack, setQueue, setContextMemory, setIsResolvingStream,
    setNativeAudioUrl, setYoutubeVideoId, setPlaybackEngine, setIsPlaying,
  });

  const addToQueue = useCallback((track: Song) => setQueue(prev => [...prev, track]), [setQueue]);
  const removeFromQueue = useCallback((trackId: string) => setQueue(prev => prev.filter(t => t.id !== trackId)), [setQueue]);

  const reorderQueue = useCallback((startIndex: number, endIndex: number) => {
    setQueue(prev => {
      const result = Array.from(prev);
      const [removed] = result.splice(startIndex, 1);
      result.splice(endIndex, 0, removed);
      return result;
    });
  }, [setQueue]);

  const handleOnDragEnd = useCallback((result: any) => {
    if (!result.destination) return;
    reorderQueue(result.source.index, result.destination.index);
  }, [reorderQueue]);

  const seekTo = useCallback((value: number) => {
    const validValue = Math.max(0, value);
    currentTimeRef.current = validValue;
    try { youtubePlayer.current?.seekTo?.(validValue, true); } catch { /* ignore */ }
    window.dispatchEvent(new CustomEvent('paatu:seek-to', { detail: validValue }));
  }, []);

  const setVolume = useCallback((value: number) => {
    const vol = Math.max(0, Math.min(1, value));
    setVolumeState(vol);
    youtubePlayer.current?.setVolume?.(vol * 100);
  }, []);

  const toggleRepeat = useCallback(() => {
    setRepeatMode(prev => (prev === 'none' ? 'all' : prev === 'all' ? 'one' : 'none'));
  }, []);

  const setSleepTimer = useCallback((minutes: number | 'end' | null) => {
    if (minutes === null) { setRemainingSleepTime(null); setIsEndOfTrackTimer(false); return; }
    if (minutes === 'end') { setIsEndOfTrackTimer(true); setRemainingSleepTime(null); return; }
    setRemainingSleepTime(minutes * 60);
    setIsEndOfTrackTimer(false);
  }, []);

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

  const clearHistory = useCallback(() => setHistory([]), []);

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

  useEffect(() => {
    if (!currentTrack) return;
    if (isInitialMountRef.current) {
      isInitialMountRef.current = false;
      return;
    }
    currentTimeRef.current = 0;
    if (isPlaying) addListenHistory(currentTrack);
  }, [currentTrack]);

  const downloadCurrentTrack = useCallback(async () => {
    if (!currentTrack) return;
    await downloadSongFile(currentTrack);
  }, [currentTrack]);

  const audioActionsValue = useMemo<AudioActionsContextType>(() => ({
    playContext, playFromSearch, playHybridTrack, togglePlay, seekTo, setVolume, toggleRepeat, toggleShuffle,
    playNext, playPrevious, setSleepTimer, addToQueue, removeFromQueue, reorderQueue, handleOnDragEnd,
    refreshPlaylists, createGuestPlaylist, renameGuestPlaylist, deleteGuestPlaylist, removeSongFromGuestPlaylist,
    addSongToGuestPlaylist, setQueue, clearHistory, setCrossfadeDuration, setEqBandGain, applyEqPreset,
    toggleAutoplay, setIsAutoplay, startSongRadio, downloadCurrentTrack,
  }), [
    playContext, playFromSearch, playHybridTrack, togglePlay, seekTo, setVolume, toggleRepeat, toggleShuffle,
    playNext, playPrevious, setSleepTimer, addToQueue, removeFromQueue, reorderQueue, handleOnDragEnd,
    refreshPlaylists, createGuestPlaylist, renameGuestPlaylist, deleteGuestPlaylist, removeSongFromGuestPlaylist,
    addSongToGuestPlaylist, setQueue, clearHistory, setCrossfadeDuration, setEqBandGain, applyEqPreset,
    toggleAutoplay, setIsAutoplay, startSongRadio, downloadCurrentTrack,
  ]);

  const audioContextValue = useMemo<AudioContextType>(() => ({
    ...audioActionsValue, currentTrack, isPlaying, volume, isShuffle, repeatMode, remainingSleepTime,
    queue, history, userPlaylists, guestPlaylists, accountPlaylists, isBuffering, onEnded, playbackEngine,
    nativeAudioUrl, youtubeVideoId, isResolvingStream, crossfadeDuration, eqBands, eqPreset, isEqAvailable, isAutoplay,
  }), [
    audioActionsValue, currentTrack, isPlaying, volume, isShuffle, repeatMode, remainingSleepTime,
    queue, history, userPlaylists, guestPlaylists, accountPlaylists, isBuffering, onEnded, playbackEngine,
    nativeAudioUrl, youtubeVideoId, isResolvingStream, crossfadeDuration, eqBands, eqPreset, isEqAvailable, isAutoplay,
  ]);

  return (
    <AudioActionsContext.Provider value={audioActionsValue}>
      <AudioContext.Provider value={audioContextValue}>
        <QueueProvider initialQueue={queue}>
          <PlaybackProgressProvider youtubePlayerRef={youtubePlayer}>
            {children}
            <AudioPlayerBridge
              currentTrack={currentTrack}
              isPlaying={isPlaying}
              volume={volume}
              playbackEngine={playbackEngine}
              nativeAudioUrl={nativeAudioUrl}
              youtubeVideoId={youtubeVideoId}
              crossfadeDuration={crossfadeDuration}
              connectEqualizer={connectEqSource}
              onReady={(player) => { youtubePlayer.current = player; }}
              onEnd={onEnded}
              playNext={playNext}
              playPrevious={playPrevious}
              setIsPlaying={setIsPlaying}
              setIsBuffering={setIsBuffering}
              currentTimeRef={currentTimeRef}
            />
          </PlaybackProgressProvider>
        </QueueProvider>
      </AudioContext.Provider>
    </AudioActionsContext.Provider>
  );
};

export const useAudio = () => {
  const context = useContext(AudioContext);
  if (context === undefined) throw new Error('useAudio must be used within an AudioProvider');
  return context;
};
