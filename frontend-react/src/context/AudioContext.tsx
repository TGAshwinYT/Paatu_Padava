import React, { createContext, useContext, useState, useRef, useEffect, useCallback } from 'react';
import type { Song, SpotifyTrack, PlaybackEngine } from '../types';
import api, { 
  addListenHistory, 
  getShuffleOrder, 
  searchTracks, 
  resolveStreamUrl,
  prefetchStreamUrls,
  savePlayerStateToRedis,
  getPlayerStateFromRedis,
  getRecommendations,
  downloadSongFile
} from '../services/api';
import { useAuth } from './AuthContext';
import AudioPlayer from '../components/AudioPlayer';
import { useEqualizer } from '../hooks/useEqualizer';
import type { EqPreset, EqBand } from '../hooks/useEqualizer';
import { isOfflineTrack, getOfflineTrackObjectUrl } from '../utils/offlineStorage';

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
  // ─── Silent Bridge additions ────────────────────────────────────────────────
  playbackEngine: PlaybackEngine;
  nativeAudioUrl: string | null;
  youtubeVideoId: string | null;
  playHybridTrack: (spotifyTrack: SpotifyTrack) => Promise<void>;
  isResolvingStream: boolean;
  // ─── Crossfade & Equalizer ────────────────────────────────────────────────
  crossfadeDuration: number;
  setCrossfadeDuration: (seconds: number) => void;
  eqBands: EqBand[];
  eqPreset: EqPreset;
  isEqAvailable: boolean;
  setEqBandGain: (bandIndex: number, gain: number) => void;
  applyEqPreset: (preset: EqPreset) => void;
  // ─── Autoplay & Song Radio ────────────────────────────────────────────────
  isAutoplay: boolean;
  toggleAutoplay: () => void;
  setIsAutoplay: (enabled: boolean) => void;
  startSongRadio: (seedSong: Song) => Promise<void>;
  downloadCurrentTrack: () => Promise<void>;
}

const AudioContext = createContext<AudioContextType | undefined>(undefined);

export const AudioProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { user } = useAuth();

  // ─── Equalizer ──────────────────────────────────────────────────────────────
  const {
    bands: eqBands,
    activePreset: eqPreset,
    isEqAvailable,
    setBandGain: setEqBandGain,
    applyPreset: applyEqPreset,
    connectSource: connectEqSource,
    setEqEnabled,
  } = useEqualizer();

  // ─── Crossfade ──────────────────────────────────────────────────────────────
  const [crossfadeDuration, setCrossfadeDurationState] = useState<number>(() => {
    try {
      const saved = localStorage.getItem('paatu_crossfade_duration');
      if (saved !== null) {
        const val = parseFloat(saved);
        if (!isNaN(val) && val >= 0 && val <= 12) return val;
      }
      return 0;
    } catch {
      return 0;
    }
  });

  const setCrossfadeDuration = useCallback((seconds: number) => {
    const clamped = Math.max(0, Math.min(12, seconds));
    setCrossfadeDurationState(clamped);
    try { localStorage.setItem('paatu_crossfade_duration', String(clamped)); } catch {}
  }, []);

  // ─── Autoplay & Infinite Song Radio ─────────────────────────────────────────
  const [isAutoplay, setIsAutoplayState] = useState<boolean>(() => {
    try {
      const saved = localStorage.getItem('paatu_autoplay');
      return saved !== null ? saved === 'true' : true;
    } catch {
      return true;
    }
  });
  const isAutoplayRef = useRef(isAutoplay);
  useEffect(() => {
    isAutoplayRef.current = isAutoplay;
  }, [isAutoplay]);

  const setIsAutoplay = useCallback((enabled: boolean) => {
    setIsAutoplayState(enabled);
    isAutoplayRef.current = enabled;
    try { localStorage.setItem('paatu_autoplay', String(enabled)); } catch {}
  }, []);

  const toggleAutoplay = useCallback(() => {
    setIsAutoplayState(prev => {
      const next = !prev;
      isAutoplayRef.current = next;
      try { localStorage.setItem('paatu_autoplay', String(next)); } catch {}
      return next;
    });
  }, []);
  
  // Persistent Player States across browser refreshes
  const [currentTrack, setCurrentTrack] = useState<Song | null>(() => {
    try {
      const saved = localStorage.getItem('paatu_current_track');
      return saved ? JSON.parse(saved) : null;
    } catch {
      return null;
    }
  });
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [isSeeking, setIsSeeking] = useState(false);
  const [volume, setVolumeState] = useState<number>(() => {
    try {
      const saved = localStorage.getItem('paatu_player_volume');
      if (saved !== null) {
        const val = parseFloat(saved);
        if (!isNaN(val) && val >= 0 && val <= 1) return val;
      }
      return 0.7;
    } catch {
      return 0.7;
    }
  });
  const [isShuffle, setIsShuffle] = useState<boolean>(() => {
    try {
      const saved = localStorage.getItem('paatu_player_shuffle');
      if (saved !== null) {
        return saved === 'true';
      }
      return true; // Shuffle ON by default
    } catch {
      return true;
    }
  });
  const [repeatMode, setRepeatMode] = useState<'none' | 'all' | 'one'>(() => {
    try {
      const saved = localStorage.getItem('paatu_player_repeat');
      if (saved === 'all' || saved === 'one') return saved;
      return 'none';
    } catch {
      return 'none';
    }
  });
  const [contextMemory, setContextMemory] = useState<Song[] | null>(() => {
    try {
      const saved = localStorage.getItem('paatu_context_memory');
      return saved ? JSON.parse(saved) : null;
    } catch {
      return null;
    }
  });
  const [isBuffering, setIsBuffering] = useState(false);
  const [seekToTime, setSeekToTime] = useState<number | null>(null);

  const [queue, setQueueState] = useState<Song[]>(() => {
    try {
      const saved = localStorage.getItem('paatu_player_queue');
      return saved ? JSON.parse(saved) : [];
    } catch {
      return [];
    }
  });
  const queueRef = useRef<Song[]>(queue);
  const radioHistoryIdsRef = useRef<string[]>([]);

  const setQueue = useCallback((action: Song[] | ((prev: Song[]) => Song[])) => {
    setQueueState(prev => {
      const next = typeof action === 'function' ? action(prev) : action;
      queueRef.current = next;
      try {
        localStorage.setItem('paatu_player_queue', JSON.stringify(next));
      } catch {}
      return next;
    });
  }, []);
  const [history, setHistory] = useState<Song[]>([]);
  const [remainingSleepTime, setRemainingSleepTime] = useState<number | null>(null);
  const [isEndOfTrackTimer, setIsEndOfTrackTimer] = useState(false);
  const [userPlaylists, setUserPlaylists] = useState<any[]>([]);

  // ─── Silent Bridge & Preloader State ────────────────────────────────────────
  const [playbackEngine, setPlaybackEngine] = useState<PlaybackEngine>('native');
  const [nativeAudioUrl, setNativeAudioUrl] = useState<string | null>(null);
  const [youtubeVideoId, setYoutubeVideoId] = useState<string | null>(null);
  const [isResolvingStream, setIsResolvingStream] = useState(false);

  // Sync EQ availability with playback engine
  useEffect(() => {
    setEqEnabled(playbackEngine === 'native');
  }, [playbackEngine, setEqEnabled]);

  // Next song preloaded stream URL with strict track ID verification
  const [, setNextStreamUrl] = useState<string | null>(null);
  const preloadedTrackRef = useRef<{ id: string; url: string } | null>(null);
  const prefetchingSongIdRef = useRef<string | null>(null);
  const activePlayingTrackIdRef = useRef<string | null>(null);
  const isInitialMountRef = useRef(true);

  const youtubePlayer = useRef<any>(null);
  const isActionLocked = useRef(false);
  const shuffleRequestIdRef = useRef(0);
  const isShuffleRef = useRef(isShuffle);
  const currentTrackRef = useRef(currentTrack);

  // ─── Persistence Side-Effects ───────────────────────────────────────────────
  useEffect(() => {
    isShuffleRef.current = isShuffle;
    try {
      localStorage.setItem('paatu_player_shuffle', String(isShuffle));
    } catch {}
  }, [isShuffle]);

  useEffect(() => {
    try {
      localStorage.setItem('paatu_player_repeat', repeatMode);
    } catch {}
  }, [repeatMode]);

  useEffect(() => {
    try {
      localStorage.setItem('paatu_player_volume', String(volume));
    } catch {}
  }, [volume]);

  useEffect(() => {
    currentTrackRef.current = currentTrack;
    try {
      if (currentTrack) {
        localStorage.setItem('paatu_current_track', JSON.stringify(currentTrack));
      } else {
        localStorage.removeItem('paatu_current_track');
      }
    } catch {}
  }, [currentTrack]);

  useEffect(() => {
    try {
      localStorage.setItem('paatu_player_queue', JSON.stringify(queue));
    } catch {}
  }, [queue]);

  useEffect(() => {
    try {
      if (contextMemory) {
        localStorage.setItem('paatu_context_memory', JSON.stringify(contextMemory));
      } else {
        localStorage.removeItem('paatu_context_memory');
      }
    } catch {}
  }, [contextMemory]);

  // Proactive Next-Song Pre-Resolution via Redis cache with track ID binding
  useEffect(() => {
    if (!queue || queue.length === 0) {
      setNextStreamUrl(null);
      preloadedTrackRef.current = null;
      prefetchingSongIdRef.current = null;
      return;
    }

    const nextTrack = queue[0];
    if (!nextTrack || !nextTrack.id) {
      setNextStreamUrl(null);
      preloadedTrackRef.current = null;
      prefetchingSongIdRef.current = null;
      return;
    }

    // Invalidate preloaded stream if queue[0] has changed to a different track
    if (preloadedTrackRef.current && preloadedTrackRef.current.id !== nextTrack.id) {
      preloadedTrackRef.current = null;
      setNextStreamUrl(null);
    }

    // If nextTrack already has audioUrl, prime preloader directly
    if (nextTrack.audioUrl && nextTrack.audioUrl.trim() !== '') {
      preloadedTrackRef.current = { id: nextTrack.id, url: nextTrack.audioUrl };
      setNextStreamUrl(nextTrack.audioUrl);
      return;
    }

    // Prevent duplicate in-flight requests for the same track
    if (prefetchingSongIdRef.current === nextTrack.id) return;
    prefetchingSongIdRef.current = nextTrack.id;

    let isMounted = true;
    resolveStreamUrl(nextTrack.id, nextTrack.title, nextTrack.artist)
      .then(res => {
        if (!isMounted) return;
        if (res && res.audio_url) {
          const streamUrl = res.audio_url;
          preloadedTrackRef.current = { id: nextTrack.id, url: streamUrl };
          setNextStreamUrl(streamUrl);
          setQueue(prevQueue => {
            if (prevQueue.length === 0 || prevQueue[0].id !== nextTrack.id) return prevQueue;
            const updated = [...prevQueue];
            updated[0] = { ...updated[0], audioUrl: streamUrl };
            return updated;
          });
        }
      })
      .catch(err => console.debug('[AudioContext] Next stream pre-resolution warning:', err));

    // Warm Redis cache for up to 3 subsequent tracks in background
    if (queue.length > 1) {
      const upcoming = queue.slice(1, 4).filter(t => !t.audioUrl);
      if (upcoming.length > 0) {
        prefetchStreamUrls(upcoming);
      }
    }

    return () => {
      isMounted = false;
    };
  }, [queue]);

  // Sync player state to Redis for logged-in user
  useEffect(() => {
    if (!user) return;
    const timer = setTimeout(() => {
      savePlayerStateToRedis({
        current_track: currentTrack,
        queue: queue.slice(0, 30),
        is_shuffle: isShuffle,
        repeat_mode: repeatMode,
        volume: volume
      });
    }, 2000);
    return () => clearTimeout(timer);
  }, [user, currentTrack, queue, isShuffle, repeatMode, volume]);

  // Restore player state from Redis on login if local session had empty queue
  useEffect(() => {
    if (!user || currentTrackRef.current) return;
    getPlayerStateFromRedis().then(state => {
      if (state && state.current_track && !currentTrackRef.current) {
        setCurrentTrack(state.current_track);
        if (state.queue && state.queue.length > 0) setQueue(state.queue);
        if (typeof state.is_shuffle === 'boolean') setIsShuffle(state.is_shuffle);
        if (state.repeat_mode) setRepeatMode(state.repeat_mode);
        setIsPlaying(false);
      }
    });
  }, [user]);

  // ─── Autoplay Queue Replenishment ───────────────────────────────────────────
  const isFetchingAutoplayRef = useRef<boolean>(false);

  const replenishAutoplayQueue = useCallback(async (seedTrack: Song): Promise<Song[]> => {
    if (!isAutoplayRef.current || isFetchingAutoplayRef.current || !seedTrack?.id) return [];
    isFetchingAutoplayRef.current = true;

    try {
      // 1. Request up to 25 recommendations
      const recs = await getRecommendations(seedTrack.id, seedTrack.artist, undefined, 25);
      if (!recs || recs.length === 0) return [];

      const currentQueueIds = new Set(queueRef.current.map(s => s.id));
      const currentActiveId = currentTrackRef.current?.id;
      const recentHistoryIds = new Set(radioHistoryIdsRef.current.slice(-25));

      // 2. Filter candidates not recently played (protecting last 20+ songs)
      let candidates = recs.filter(s => 
        s.id !== seedTrack.id &&
        s.id !== currentActiveId &&
        !currentQueueIds.has(s.id) &&
        !recentHistoryIds.has(s.id)
      );

      // 3. If candidates pool exhausted after 20+ songs, allow recycling older songs,
      // but strictly protect currently queued, active song, and last 10 songs!
      if (candidates.length < 5) {
        const strictExcluded = new Set([
          seedTrack.id,
          ...(currentActiveId ? [currentActiveId] : []),
          ...queueRef.current.map(s => s.id),
          ...radioHistoryIdsRef.current.slice(-10)
        ]);
        const relaxed = recs.filter(s => !strictExcluded.has(s.id));
        if (relaxed.length > 0) {
          candidates = relaxed;
        }
      }

      if (candidates.length === 0) return [];

      // 4. Smart Shuffle (Fisher-Yates + ML Nearest-Neighbor ordering)
      // Ensures songs are NEVER appended in the same static order!
      const shuffledCandidates = shuffleArray(candidates);
      const queueIds = shuffledCandidates.map(s => s.id);
      
      let orderedSongs = shuffledCandidates;
      try {
        const smartOrder = await getShuffleOrder(queueIds, seedTrack.id);
        if (smartOrder && smartOrder.length > 0) {
          const songMap = new Map(shuffledCandidates.map(s => [s.id, s]));
          const reordered: Song[] = [];
          for (const id of smartOrder) {
            const song = songMap.get(id);
            if (song) reordered.push(song);
          }
          if (reordered.length > 0) {
            orderedSongs = reordered;
          }
        }
      } catch (err) {
        // Keep Fisher-Yates shuffled order
      }

      const fresh = orderedSongs.map(s => ({ ...s, isManual: false, isRadio: true }));

      // Track in session radio history
      for (const s of fresh) {
        if (!radioHistoryIdsRef.current.includes(s.id)) {
          radioHistoryIdsRef.current.push(s.id);
        }
      }
      if (radioHistoryIdsRef.current.length > 60) {
        radioHistoryIdsRef.current = radioHistoryIdsRef.current.slice(-40);
      }

      setQueue(prev => {
        const prevIds = new Set(prev.map(p => p.id));
        const toAdd = fresh.filter(f => !prevIds.has(f.id));
        return [...prev, ...toAdd];
      });

      return fresh;
    } catch (err) {
      console.debug('[AudioContext] Autoplay queue replenishment warning:', err);
      return [];
    } finally {
      isFetchingAutoplayRef.current = false;
    }
  }, [setQueue]);

  // Background auto-replenishment: keep queue populated when Autoplay is ON
  useEffect(() => {
    if (isAutoplay && isPlaying && queue.length <= 1 && currentTrack) {
      replenishAutoplayQueue(currentTrack);
    }
  }, [isAutoplay, isPlaying, queue.length, currentTrack, replenishAutoplayQueue]);

  // --- 2. STABLE ACTION HANDLERS ---
  const playNext = useCallback(async () => {
    if (repeatMode === 'one' && youtubePlayer.current) {
      youtubePlayer.current.seekTo(0);
      youtubePlayer.current.playVideo();
      setIsPlaying(true);
      return;
    }

    if (queue.length > 0) {
      const nextTrack = queue[0];
      const remainingQueue = queue.slice(1);
      setQueue(remainingQueue);
      
      if (currentTrack) {
        setHistory(prev => [currentTrack, ...prev.slice(0, 49)]);
      }

      // Mark the active playing track ID immediately to abort any stale in-flight fetches
      activePlayingTrackIdRef.current = nextTrack.id;

      // Check if we have an exact preloaded stream URL for THIS SPECIFIC TRACK ID
      let resolvedUrl: string | null = null;
      if (isOfflineTrack(nextTrack.id)) {
        try {
          const offlineUrl = await getOfflineTrackObjectUrl(nextTrack.id);
          if (offlineUrl) resolvedUrl = offlineUrl;
        } catch {}
      }
      if (!resolvedUrl && nextTrack.audioUrl && nextTrack.audioUrl.trim() !== '') {
        resolvedUrl = nextTrack.audioUrl;
      } else if (
        preloadedTrackRef.current &&
        preloadedTrackRef.current.id === nextTrack.id &&
        preloadedTrackRef.current.url
      ) {
        resolvedUrl = preloadedTrackRef.current.url;
      }

      // Clear preloaded buffer immediately so it CANNOT leak to subsequent rapid clicks
      preloadedTrackRef.current = null;
      setNextStreamUrl(null);
      prefetchingSongIdRef.current = null;

      if (resolvedUrl && resolvedUrl.trim() !== '') {
        nextTrack.audioUrl = resolvedUrl;
        setNativeAudioUrl(resolvedUrl);
        setYoutubeVideoId(null);
        setPlaybackEngine('native');
        setIsBuffering(false);
      } else {
        // Stream URL not ready yet (rapid skip).
        // STOP previous audio immediately so it does not bleed into the new song!
        setNativeAudioUrl(null);
        setYoutubeVideoId(null);
        setIsBuffering(true);

        const targetTrackId = nextTrack.id;
        resolveStreamUrl(nextTrack.id, nextTrack.title, nextTrack.artist)
          .then(res => {
            // Drop stale resolution if user skipped away
            if (activePlayingTrackIdRef.current !== targetTrackId) return;
            if (res && res.audio_url) {
              nextTrack.audioUrl = res.audio_url;
              setNativeAudioUrl(res.audio_url);
              setYoutubeVideoId(null);
              setPlaybackEngine('native');
              setIsBuffering(false);
            } else {
              const ytId = res?.youtube_id || targetTrackId;
              setNativeAudioUrl(null);
              setYoutubeVideoId(ytId);
              setPlaybackEngine('youtube');
              setIsBuffering(false);
            }
          })
          .catch(() => {
            if (activePlayingTrackIdRef.current !== targetTrackId) return;
            setNativeAudioUrl(null);
            setYoutubeVideoId(targetTrackId);
            setPlaybackEngine('youtube');
            setIsBuffering(false);
          });
      }
      
      setCurrentTrack(nextTrack);
      setIsPlaying(true);

    } else if (repeatMode === 'all' && contextMemory && contextMemory.length > 0) {
      // Loop context memory if repeatMode === 'all'
      const firstTrack = contextMemory[0];
      const rest = contextMemory.slice(1);
      setQueue(isShuffleRef.current ? shuffleArray(rest) : rest);
      setCurrentTrack(firstTrack);
      activePlayingTrackIdRef.current = firstTrack.id;
      if (firstTrack.audioUrl && firstTrack.audioUrl.trim() !== '') {
        setNativeAudioUrl(firstTrack.audioUrl);
        setYoutubeVideoId(null);
        setPlaybackEngine('native');
        setIsBuffering(false);
      } else {
        setNativeAudioUrl(null);
        setYoutubeVideoId(null);
        setIsBuffering(true);
        const targetId = firstTrack.id;
        resolveStreamUrl(firstTrack.id, firstTrack.title, firstTrack.artist)
          .then(res => {
            if (activePlayingTrackIdRef.current !== targetId) return;
            if (res && res.audio_url) {
              firstTrack.audioUrl = res.audio_url;
              setNativeAudioUrl(res.audio_url);
              setYoutubeVideoId(null);
              setPlaybackEngine('native');
            } else {
              const ytId = res?.youtube_id || targetId;
              setNativeAudioUrl(null);
              setYoutubeVideoId(ytId);
              setPlaybackEngine('youtube');
            }
            setIsBuffering(false);
          })
          .catch(() => {
            if (activePlayingTrackIdRef.current !== targetId) return;
            setYoutubeVideoId(targetId);
            setPlaybackEngine('youtube');
            setIsBuffering(false);
          });
      }
      setIsPlaying(true);
    } else if (isAutoplayRef.current && currentTrack) {
      // 🚀 Infinite Autoplay / Song Radio: Fetch fresh recommendations for current track!
      setIsBuffering(true);
      replenishAutoplayQueue(currentTrack).then(newTracks => {
        if (newTracks && newTracks.length > 0) {
          const nextTrack = newTracks[0];
          const remaining = newTracks.slice(1);
          setQueue(remaining);
          activePlayingTrackIdRef.current = nextTrack.id;
          setCurrentTrack(nextTrack);

          if (nextTrack.audioUrl && nextTrack.audioUrl.trim() !== '') {
            setNativeAudioUrl(nextTrack.audioUrl);
            setYoutubeVideoId(null);
            setPlaybackEngine('native');
            setIsBuffering(false);
          } else {
            setNativeAudioUrl(null);
            setYoutubeVideoId(null);
            setIsBuffering(true);
            resolveStreamUrl(nextTrack.id, nextTrack.title, nextTrack.artist)
              .then(res => {
                if (activePlayingTrackIdRef.current !== nextTrack.id) return;
                if (res && res.audio_url) {
                  nextTrack.audioUrl = res.audio_url;
                  setNativeAudioUrl(res.audio_url);
                  setYoutubeVideoId(null);
                  setPlaybackEngine('native');
                } else {
                  setNativeAudioUrl(null);
                  setYoutubeVideoId(res?.youtube_id || nextTrack.id);
                  setPlaybackEngine('youtube');
                }
                setIsBuffering(false);
              })
              .catch(() => {
                setYoutubeVideoId(nextTrack.id);
                setPlaybackEngine('youtube');
                setIsBuffering(false);
              });
          }
          setIsPlaying(true);
        } else {
          setIsPlaying(false);
          setIsBuffering(false);
        }
      }).catch(() => {
        setIsPlaying(false);
        setIsBuffering(false);
      });
    } else {
      setIsPlaying(false);
    }
  }, [queue, currentTrack, repeatMode, contextMemory, replenishAutoplayQueue]);

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
      if (!currentTrack) return;
      if (playbackEngine === 'youtube' && !youtubeVideoId && currentTrack.id) {
        setYoutubeVideoId(currentTrack.id);
      }
      youtubePlayer.current?.playVideo();
      setIsPlaying(true);
    }
  }, [isPlaying, currentTrack, playbackEngine, youtubeVideoId]);

  const playContext = useCallback((clickedSong: Song, contextArray: Song[] = []) => {
    activePlayingTrackIdRef.current = clickedSong.id;
    preloadedTrackRef.current = null;
    setNextStreamUrl(null);
    prefetchingSongIdRef.current = null;

    setCurrentTrack(clickedSong);
    
    setContextMemory(contextArray);

    if (isShuffleRef.current && contextArray.length > 1) {
      // Shuffle mode ON: Fill queue with remaining tracks ordered by Smart Shuffle
      const otherSongs = contextArray.filter(s => s.id !== clickedSong.id);
      // 1. Instant local Fisher-Yates shuffle for zero lag
      const instantShuffled = shuffleArray(otherSongs);
      setQueue(instantShuffled);

      // 2. Query ML Smart Shuffle order in background starting from clickedSong
      const reqId = ++shuffleRequestIdRef.current;
      const queueIds = otherSongs.map(s => s.id);
      getShuffleOrder(queueIds, clickedSong.id)
        .then(orderedIds => {
          if (
            reqId !== shuffleRequestIdRef.current ||
            !isShuffleRef.current ||
            activePlayingTrackIdRef.current !== clickedSong.id ||
            !orderedIds ||
            orderedIds.length === 0
          ) {
            return;
          }

          setQueue(() => {
            const songMap = new Map(otherSongs.map(s => [s.id, s]));
            const smartQueue: Song[] = [];
            for (const id of orderedIds) {
              const s = songMap.get(id);
              if (s) {
                smartQueue.push(s);
                songMap.delete(id);
              }
            }
            for (const remaining of songMap.values()) {
              smartQueue.push(remaining);
            }
            return smartQueue;
          });
        })
        .catch(err => {
          console.debug('[AudioContext] Smart shuffle order fallback:', err);
        });
    } else {
      // Shuffle mode OFF: Play in line with the playlist (sequential)
      const songIndex = contextArray.findIndex(s => s.id === clickedSong.id);
      if (songIndex !== -1) {
        setQueue(contextArray.slice(songIndex + 1));
      } else {
        setQueue([]);
      }
    }

    if (isOfflineTrack(clickedSong.id)) {
      getOfflineTrackObjectUrl(clickedSong.id).then(offlineUrl => {
        if (offlineUrl && activePlayingTrackIdRef.current === clickedSong.id) {
          clickedSong.audioUrl = offlineUrl;
          setNativeAudioUrl(offlineUrl);
          setYoutubeVideoId(null);
          setPlaybackEngine('native');
          setIsBuffering(false);
        }
      });
    }

    if (clickedSong.audioUrl && clickedSong.audioUrl.trim() !== '') {
      setNativeAudioUrl(clickedSong.audioUrl);
      setYoutubeVideoId(null);
      setPlaybackEngine('native');
      setIsBuffering(false);
    } else if (clickedSong.id) {
      setNativeAudioUrl(null);
      setYoutubeVideoId(null);
      setIsBuffering(true);

      const targetId = clickedSong.id;
      resolveStreamUrl(clickedSong.id, clickedSong.title, clickedSong.artist)
        .then(res => {
          if (activePlayingTrackIdRef.current !== targetId) return;
          if (res && res.audio_url) {
            clickedSong.audioUrl = res.audio_url;
            setNativeAudioUrl(res.audio_url);
            setYoutubeVideoId(null);
            setPlaybackEngine('native');
          } else {
            const ytId = res?.youtube_id || targetId;
            setNativeAudioUrl(null);
            setYoutubeVideoId(ytId);
            setPlaybackEngine('youtube');
          }
          setIsBuffering(false);
        })
        .catch(() => {
          if (activePlayingTrackIdRef.current !== targetId) return;
          setYoutubeVideoId(targetId);
          setPlaybackEngine('youtube');
          setIsBuffering(false);
        });
    }
    
    setIsPlaying(true);
  }, []);

  const playFromSearch = useCallback((track: Song) => {
    activePlayingTrackIdRef.current = track.id;
    preloadedTrackRef.current = null;
    setNextStreamUrl(null);
    prefetchingSongIdRef.current = null;

    setQueue([]);
    setContextMemory(null);
    setCurrentTrack(track);
    if (isOfflineTrack(track.id)) {
      getOfflineTrackObjectUrl(track.id).then(offlineUrl => {
        if (offlineUrl && activePlayingTrackIdRef.current === track.id) {
          track.audioUrl = offlineUrl;
          setNativeAudioUrl(offlineUrl);
          setYoutubeVideoId(null);
          setPlaybackEngine('native');
          setIsBuffering(false);
        }
      });
    }

    if (track.audioUrl && track.audioUrl.trim() !== '') {
      setNativeAudioUrl(track.audioUrl);
      setYoutubeVideoId(null);
      setPlaybackEngine('native');
      setIsBuffering(false);
    } else if (track.id) {
      setNativeAudioUrl(null);
      setYoutubeVideoId(null);
      setIsBuffering(true);

      const targetId = track.id;
      resolveStreamUrl(track.id, track.title, track.artist)
        .then(res => {
          if (activePlayingTrackIdRef.current !== targetId) return;
          if (res && res.audio_url) {
            track.audioUrl = res.audio_url;
            setNativeAudioUrl(res.audio_url);
            setYoutubeVideoId(null);
            setPlaybackEngine('native');
          } else {
            const ytId = res?.youtube_id || targetId;
            setNativeAudioUrl(null);
            setYoutubeVideoId(ytId);
            setPlaybackEngine('youtube');
          }
          setIsBuffering(false);
        })
        .catch(() => {
          if (activePlayingTrackIdRef.current !== targetId) return;
          setYoutubeVideoId(targetId);
          setPlaybackEngine('youtube');
          setIsBuffering(false);
        });
    }
    setIsPlaying(true);
  }, []);

  // ─── Silent Bridge Core ─────────────────────────────────────────────────────
  /**
   * playHybridTrack()
   * 1. Instantly sets UI metadata from Spotify's clean data
   * 2. Silently tries JioSaavn via our existing /api/music/search backend
   * 3. Falls back to the hidden YouTube IFrame if JioSaavn fails
   */
  const playHybridTrack = useCallback(async (spotifyTrack: SpotifyTrack) => {
    const primaryArtist = spotifyTrack.artists[0]?.name ?? '';
    const searchQuery   = `${spotifyTrack.name} ${primaryArtist}`.trim();
    const coverArt      = spotifyTrack.album.images[0]?.url ?? '/logo.png';

    // ── Step 1: Instant UI update with Spotify metadata ──────────────────────
    const spotifySong: Song = {
      id:       spotifyTrack.spotifyId, // temp id; replaced below
      title:    spotifyTrack.name,
      artist:   primaryArtist,
      coverUrl: coverArt,
      audioUrl: '',
      album:    spotifyTrack.album.name,
      duration: Math.floor(spotifyTrack.durationMs / 1000),
    };

    setCurrentTrack(spotifySong);
    setQueue([]);
    setContextMemory(null);
    setIsResolvingStream(true);
    setNativeAudioUrl(null);
    setYoutubeVideoId(null);
    setIsPlaying(true);

    try {
      // ── Step 2: Silent Primary Search → JioSaavn (via our backend) ──────────
      const searchResult = await searchTracks(searchQuery);
      const songs: Song[] = searchResult?.global_matches?.songs ?? [];
      const topSong: Song | null = searchResult?.global_matches?.top_result?.type === 'song'
        ? searchResult.global_matches.top_result
        : null;
      const bestMatch: Song | null = topSong ?? songs[0] ?? null;

      // downloadUrls is an array of { quality, url } objects from our backend
      // index 4 = 320kbps; fall back to index 3 (160kbps) if unavailable
      const rawUrls: any[] = (bestMatch as any)?.downloadUrls ?? [];
      const highQualityUrl: string | undefined =
        rawUrls[4]?.url ?? rawUrls[3]?.url ?? rawUrls[2]?.url ?? undefined;

      if (bestMatch && highQualityUrl) {
        // ✅ JioSaavn success — native HTML5 audio
        console.log('[SilentBridge] JioSaavn resolved:', highQualityUrl);
        const resolvedSong: Song = {
          ...spotifySong,
          id:       bestMatch.id, // use the real song ID (YouTube compatible)
          audioUrl: highQualityUrl,
          downloadUrls: rawUrls,
        };
        setCurrentTrack(resolvedSong);
        setNativeAudioUrl(highQualityUrl);
        setYoutubeVideoId(null);
        setPlaybackEngine('native');
        setIsResolvingStream(false);
        return;
      }

      throw new Error('JioSaavn: no downloadUrl found');

    } catch (jioSaavnError) {
      console.log('[SilentBridge] JioSaavn failed, falling back to YouTube IFrame…', jioSaavnError);

      // ── Step 3: Silent Fallback → YouTube IFrame ─────────────────────────
      try {
        // Re-use JioSaavn search result id (which is already a YouTube video ID in our system)
        const fallbackResult = await searchTracks(searchQuery);
        const fallbackSongs: Song[] = fallbackResult?.global_matches?.songs ?? [];
        const fallbackTop: Song | null = fallbackResult?.global_matches?.top_result?.type === 'song'
          ? fallbackResult.global_matches.top_result
          : null;
        const fallback: Song | null = fallbackTop ?? fallbackSongs[0] ?? null;

        if (fallback?.id) {
          console.log('[SilentBridge] YouTube fallback resolved, videoId:', fallback.id);
          const ytSong: Song = { ...spotifySong, id: fallback.id, audioUrl: '' };
          setCurrentTrack(ytSong);
          setNativeAudioUrl(null);
          setYoutubeVideoId(fallback.id);
          setPlaybackEngine('youtube');
        } else {
          console.error('[SilentBridge] Track completely unavailable on both JioSaavn and YouTube.');
          setIsPlaying(false);
        }
      } catch (ytError) {
        console.error('[SilentBridge] YouTube fallback also failed:', ytError);
        setIsPlaying(false);
      } finally {
        setIsResolvingStream(false);
      }
    }
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
    const nextShuffleState = !isShuffle;
    setIsShuffle(nextShuffleState);
    isShuffleRef.current = nextShuffleState;

    if (nextShuffleState) {
      // 1. Instantly apply local Fisher-Yates shuffle for zero lag
      const localShuffled = shuffleArray(queue);
      setQueue(localShuffled);

      if (localShuffled.length > 1) {
        // 2. Request smart behavioral shuffle in background
        const reqId = ++shuffleRequestIdRef.current;
        const queueIds = localShuffled.map(s => s.id);
        const startingTrackId = currentTrack?.id;

        getShuffleOrder(queueIds, startingTrackId)
          .then(orderedIds => {
            // Guard against race conditions explicitly:
            // - Check if this request is still the active one
            // - Check if shuffle is still enabled
            // - Check if the playing track hasn't changed while waiting
            if (
              reqId !== shuffleRequestIdRef.current ||
              !isShuffleRef.current ||
              currentTrackRef.current?.id !== startingTrackId ||
              !orderedIds ||
              orderedIds.length === 0
            ) {
              return;
            }

            setQueue(prevQueue => {
              // Guard against queue mutations (e.g. song popped or added) while waiting
              if (prevQueue.length !== queueIds.length) return prevQueue;
              const prevIdSet = new Set(prevQueue.map(s => s.id));
              if (!queueIds.every(id => prevIdSet.has(id))) return prevQueue;

              const songMap = new Map(prevQueue.map(s => [s.id, s]));
              const newQueue: Song[] = [];
              for (const id of orderedIds) {
                const s = songMap.get(id);
                if (s) {
                  newQueue.push(s);
                  songMap.delete(id);
                }
              }
              // Append any songs not in orderedIds to prevent missing tracks
              for (const remainingSong of songMap.values()) {
                newQueue.push(remainingSong);
              }
              return newQueue;
            });
          })
          .catch(err => {
            // Silently keep the plain random shuffle already applied
            console.debug('[AudioContext] Smart shuffle fallback to random:', err);
          });
      }
    } else if (contextMemory && currentTrack) {
      shuffleRequestIdRef.current++;
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
      const response = await api.get('/api/playlists/');
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

    if (isInitialMountRef.current) {
      isInitialMountRef.current = false;
      setIsPlaying(false);
      // Setup engine for restored track without autoplaying or mounting YouTube prematurely
      if (currentTrack.audioUrl && currentTrack.audioUrl.trim() !== '') {
        setNativeAudioUrl(currentTrack.audioUrl);
        setYoutubeVideoId(null);
        setPlaybackEngine('native');
      } else {
        setNativeAudioUrl(null);
        setYoutubeVideoId(null);
        setPlaybackEngine('youtube');
      }
      return;
    }

    // ── Resets for Track Switch ──
    setCurrentTime(0);
    setDuration(0);

    if (isPlaying) {
      addListenHistory(currentTrack);
    }
  }, [currentTrack]);

  const startSongRadio = useCallback(async (seedSong: Song) => {
    if (!seedSong) return;
    
    // Play the seed song immediately
    playContext(seedSong, [seedSong]);
    
    // Ensure Autoplay is enabled for continuous Song Radio discovery
    setIsAutoplay(true);
    isAutoplayRef.current = true;
    
    // Reset session radio history starting with this seed song
    radioHistoryIdsRef.current = [seedSong.id];
    
    try {
      const recs = await getRecommendations(seedSong.id, seedSong.artist, undefined, 25);
      if (recs && recs.length > 0) {
        const candidates = recs.filter(s => s.id !== seedSong.id);
        
        // Smart Shuffle candidates so radio provides an engaging, fresh discovery queue
        const shuffled = shuffleArray(candidates);
        const queueIds = shuffled.map(s => s.id);
        
        let ordered = shuffled;
        try {
          const smartOrder = await getShuffleOrder(queueIds, seedSong.id);
          if (smartOrder && smartOrder.length > 0) {
            const songMap = new Map(shuffled.map(s => [s.id, s]));
            const reordered: Song[] = [];
            for (const id of smartOrder) {
              const song = songMap.get(id);
              if (song) reordered.push(song);
            }
            if (reordered.length > 0) {
              ordered = reordered;
            }
          }
        } catch {
          // Keep Fisher-Yates shuffled order
        }

        const radioQueue = ordered.map(s => ({ ...s, isManual: false, isRadio: true }));
        
        for (const s of radioQueue) {
          radioHistoryIdsRef.current.push(s.id);
        }
        
        setQueue(radioQueue);
      }
    } catch (err) {
      console.debug('[AudioContext] startSongRadio error:', err);
    }
  }, [playContext, setQueue, setIsAutoplay]);

  const downloadCurrentTrack = useCallback(async () => {
    if (!currentTrack) return;
    await downloadSongFile(currentTrack);
  }, [currentTrack]);

  return (
    <AudioContext.Provider value={{ 
      currentTrack, isPlaying, currentTime, setCurrentTime, duration, isSeeking, setIsSeeking, volume, isShuffle, repeatMode,
      remainingSleepTime, queue, history, userPlaylists,
      togglePlay, seekTo, setVolume, toggleRepeat,
      toggleShuffle,
      playNext, playPrevious,
      setSleepTimer, addToQueue, removeFromQueue, reorderQueue, handleOnDragEnd, refreshPlaylists, setQueue, clearHistory, playContext, playFromSearch,
      onEnded, progress: currentTime, isBuffering,
      // Silent Bridge
      playbackEngine, nativeAudioUrl, youtubeVideoId, playHybridTrack, isResolvingStream,
      // Crossfade & Equalizer
      crossfadeDuration, setCrossfadeDuration,
      eqBands, eqPreset, isEqAvailable, setEqBandGain, applyEqPreset,
      // Autoplay & Song Radio
      isAutoplay, toggleAutoplay, setIsAutoplay, startSongRadio, downloadCurrentTrack,
    }}>
      {children}
        <AudioPlayer 
          currentTrack={currentTrack}
          isPlaying={isPlaying}
          volume={volume}
          seekToTime={seekToTime}
          playbackEngine={playbackEngine}
          nativeAudioUrl={nativeAudioUrl}
          youtubeVideoId={youtubeVideoId}
          crossfadeDuration={crossfadeDuration}
          connectEqualizer={connectEqSource}
          onTimeUpdate={setCurrentTime}
          onDurationChange={setDuration}
          onReady={(player) => {
             youtubePlayer.current = player;
          }}
          onEnd={onEnded}
          playNext={playNext}
          playPrevious={playPrevious}
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
