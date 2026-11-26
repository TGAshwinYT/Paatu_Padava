import { useCallback } from 'react';
import type React from 'react';
import type { Song, PlaybackEngine } from '../../types';
import { getShuffleOrder, resolveStreamUrl } from '../../services/api';
import { isOfflineTrack, getOfflineTrackObjectUrl } from '../../utils/offlineStorage';
import { shuffleArray } from './audioTypes';

interface UseAudioQueueActionsDeps {
  queue: Song[];
  currentTrack: Song | null;
  history: Song[];
  isShuffle: boolean;
  repeatMode: 'none' | 'all' | 'one';
  contextMemory: Song[] | null;
  isShuffleRef: React.MutableRefObject<boolean>;
  isAutoplayRef: React.MutableRefObject<boolean>;
  currentTrackRef: React.MutableRefObject<Song | null>;
  currentTimeRef: React.MutableRefObject<number>;
  activePlayingTrackIdRef: React.MutableRefObject<string | null>;
  preloadedTrackRef: React.MutableRefObject<{ id: string; url: string } | null>;
  prefetchingSongIdRef: React.MutableRefObject<string | null>;
  shuffleRequestIdRef: React.MutableRefObject<number>;
  youtubePlayer: React.MutableRefObject<any>;
  actionLockRef: React.MutableRefObject<boolean>;
  setQueue: React.Dispatch<React.SetStateAction<Song[]>>;
  setCurrentTrack: (song: Song | null) => void;
  setContextMemory: (ctx: Song[] | null) => void;
  setHistory: React.Dispatch<React.SetStateAction<Song[]>>;
  setIsShuffle: (val: boolean) => void;
  setIsPlaying: (val: boolean) => void;
  setIsBuffering: (val: boolean) => void;
  setNativeAudioUrl: (url: string | null) => void;
  setYoutubeVideoId: (id: string | null) => void;
  setPlaybackEngine: (engine: PlaybackEngine) => void;
  setNextStreamUrl: (url: string | null) => void;
  replenishAutoplayQueue: (seed: Song) => Promise<Song[]>;
}

export function useAudioQueueActions(deps: UseAudioQueueActionsDeps) {
  const {
    queue,
    currentTrack,
    history,
    isShuffle,
    repeatMode,
    contextMemory,
    isShuffleRef,
    isAutoplayRef,
    currentTrackRef,
    currentTimeRef,
    activePlayingTrackIdRef,
    preloadedTrackRef,
    prefetchingSongIdRef,
    shuffleRequestIdRef,
    youtubePlayer,
    actionLockRef,
    setQueue,
    setCurrentTrack,
    setContextMemory,
    setHistory,
    setIsShuffle,
    setIsPlaying,
    setIsBuffering,
    setNativeAudioUrl,
    setYoutubeVideoId,
    setPlaybackEngine,
    setNextStreamUrl,
    replenishAutoplayQueue,
  } = deps;

  const resolveAndPlayTrack = useCallback((track: Song) => {
    const targetId = track.id;
    setNativeAudioUrl(null);
    setYoutubeVideoId(null);
    setIsBuffering(true);
    resolveStreamUrl(track.id, track.title, track.artist)
      .then(res => {
        if (activePlayingTrackIdRef.current !== targetId) return;
        if (res && res.audio_url) {
          track.audioUrl = res.audio_url;
          setNativeAudioUrl(res.audio_url);
          setYoutubeVideoId(null);
          setPlaybackEngine('native');
        } else {
          setNativeAudioUrl(null);
          setYoutubeVideoId(res?.youtube_id || targetId);
          setPlaybackEngine('youtube');
        }
        setIsBuffering(false);
      })
      .catch(() => {
        if (activePlayingTrackIdRef.current !== targetId) return;
        setNativeAudioUrl(null);
        setYoutubeVideoId(targetId);
        setPlaybackEngine('youtube');
        setIsBuffering(false);
      });
  }, [activePlayingTrackIdRef, setIsBuffering, setNativeAudioUrl, setPlaybackEngine, setYoutubeVideoId]);

  const playContext = useCallback((clickedSong: Song, contextArray: Song[] = []) => {
    activePlayingTrackIdRef.current = clickedSong.id;
    preloadedTrackRef.current = null;
    setNextStreamUrl(null);
    prefetchingSongIdRef.current = null;

    setCurrentTrack(clickedSong);
    setContextMemory(contextArray);

    if (isShuffleRef.current && contextArray.length > 1) {
      const otherSongs = contextArray.filter(s => s.id !== clickedSong.id);
      setQueue(shuffleArray(otherSongs));

      const reqId = ++shuffleRequestIdRef.current;
      getShuffleOrder(otherSongs.map(s => s.id), clickedSong.id)
        .then(orderedIds => {
          if (reqId !== shuffleRequestIdRef.current || !isShuffleRef.current || activePlayingTrackIdRef.current !== clickedSong.id || !orderedIds?.length) {
            return;
          }
          setQueue(() => {
            const songMap = new Map(otherSongs.map(s => [s.id, s]));
            const smartQueue: Song[] = [];
            for (const id of orderedIds) {
              const s = songMap.get(id);
              if (s) { smartQueue.push(s); songMap.delete(id); }
            }
            for (const remaining of songMap.values()) smartQueue.push(remaining);
            return smartQueue;
          });
        })
        .catch(err => console.debug('[AudioContext] Smart shuffle order fallback:', err));
    } else {
      const songIndex = contextArray.findIndex(s => s.id === clickedSong.id);
      setQueue(songIndex !== -1 ? contextArray.slice(songIndex + 1) : []);
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

    if (clickedSong.audioUrl?.trim()) {
      setNativeAudioUrl(clickedSong.audioUrl);
      setYoutubeVideoId(null);
      setPlaybackEngine('native');
      setIsBuffering(false);
    } else if (clickedSong.id) {
      resolveAndPlayTrack(clickedSong);
    }
    setIsPlaying(true);
  }, [
    activePlayingTrackIdRef, preloadedTrackRef, prefetchingSongIdRef, shuffleRequestIdRef,
    isShuffleRef, setNextStreamUrl, setCurrentTrack, setContextMemory, setQueue,
    setNativeAudioUrl, setYoutubeVideoId, setPlaybackEngine, setIsBuffering, setIsPlaying,
    resolveAndPlayTrack,
  ]);

  const playNext = useCallback(async () => {
    if (repeatMode === 'one' && youtubePlayer.current) {
      youtubePlayer.current.seekTo(0);
      youtubePlayer.current.playVideo();
      setIsPlaying(true);
      return;
    }

    if (queue.length > 0) {
      const nextTrack = queue[0];
      setQueue(queue.slice(1));
      if (currentTrack) setHistory(prev => [currentTrack, ...prev.slice(0, 49)]);
      activePlayingTrackIdRef.current = nextTrack.id;

      let resolvedUrl: string | null = null;
      if (isOfflineTrack(nextTrack.id)) {
        try {
          const offlineUrl = await getOfflineTrackObjectUrl(nextTrack.id);
          if (offlineUrl) resolvedUrl = offlineUrl;
        } catch { /* ignore */ }
      }
      if (!resolvedUrl && nextTrack.audioUrl?.trim()) {
        resolvedUrl = nextTrack.audioUrl;
      } else if (preloadedTrackRef.current?.id === nextTrack.id && preloadedTrackRef.current.url) {
        resolvedUrl = preloadedTrackRef.current.url;
      }

      preloadedTrackRef.current = null;
      setNextStreamUrl(null);
      prefetchingSongIdRef.current = null;

      let activeNextTrack = nextTrack;
      if (resolvedUrl?.trim()) {
        activeNextTrack = { ...nextTrack, audioUrl: resolvedUrl };
        setNativeAudioUrl(resolvedUrl);
        setYoutubeVideoId(null);
        setPlaybackEngine('native');
        setIsBuffering(false);
      } else {
        resolveAndPlayTrack(nextTrack);
      }
      setCurrentTrack(activeNextTrack);
      setIsPlaying(true);
    } else if (repeatMode === 'all' && contextMemory?.length) {
      const firstTrack = contextMemory[0];
      const rest = contextMemory.slice(1);
      setQueue(isShuffleRef.current ? shuffleArray(rest) : rest);
      setCurrentTrack(firstTrack);
      activePlayingTrackIdRef.current = firstTrack.id;
      if (firstTrack.audioUrl?.trim()) {
        setNativeAudioUrl(firstTrack.audioUrl);
        setYoutubeVideoId(null);
        setPlaybackEngine('native');
        setIsBuffering(false);
      } else {
        resolveAndPlayTrack(firstTrack);
      }
      setIsPlaying(true);
    } else if (isAutoplayRef.current && currentTrack) {
      setIsBuffering(true);
      replenishAutoplayQueue(currentTrack).then(newTracks => {
        if (newTracks?.length) {
          const nextTrack = newTracks[0];
          setQueue(newTracks.slice(1));
          activePlayingTrackIdRef.current = nextTrack.id;
          setCurrentTrack(nextTrack);
          if (nextTrack.audioUrl?.trim()) {
            setNativeAudioUrl(nextTrack.audioUrl);
            setYoutubeVideoId(null);
            setPlaybackEngine('native');
            setIsBuffering(false);
          } else {
            resolveAndPlayTrack(nextTrack);
          }
          setIsPlaying(true);
        } else {
          setIsPlaying(false);
          setIsBuffering(false);
        }
      }).catch(() => { setIsPlaying(false); setIsBuffering(false); });
    } else {
      setIsPlaying(false);
    }
  }, [
    queue, currentTrack, repeatMode, contextMemory, youtubePlayer, activePlayingTrackIdRef,
    preloadedTrackRef, prefetchingSongIdRef, isShuffleRef, isAutoplayRef, replenishAutoplayQueue,
    setQueue, setHistory, setNextStreamUrl, setNativeAudioUrl, setYoutubeVideoId, setPlaybackEngine,
    setIsBuffering, setCurrentTrack, setIsPlaying, resolveAndPlayTrack,
  ]);

  const playPrevious = useCallback(() => {
    if (actionLockRef.current) return;
    if (currentTimeRef.current > 3 || history.length === 0) {
      youtubePlayer.current?.seekTo?.(0);
      return;
    }
    actionLockRef.current = true;
    const prevTrack = history[0];
    setHistory(prev => prev.slice(1));
    if (currentTrack) setQueue(prev => [currentTrack, ...prev]);
    setCurrentTrack(prevTrack);
    setTimeout(() => { actionLockRef.current = false; }, 500);
  }, [history, currentTrack, actionLockRef, currentTimeRef, youtubePlayer, setHistory, setQueue, setCurrentTrack]);

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

    if (track.audioUrl?.trim()) {
      setNativeAudioUrl(track.audioUrl);
      setYoutubeVideoId(null);
      setPlaybackEngine('native');
      setIsBuffering(false);
    } else if (track.id) {
      resolveAndPlayTrack(track);
    }
    setIsPlaying(true);
  }, [
    activePlayingTrackIdRef, preloadedTrackRef, prefetchingSongIdRef, setNextStreamUrl,
    setQueue, setContextMemory, setCurrentTrack, setNativeAudioUrl, setYoutubeVideoId,
    setPlaybackEngine, setIsBuffering, setIsPlaying, resolveAndPlayTrack,
  ]);

  const toggleShuffle = useCallback(() => {
    const nextShuffleState = !isShuffle;
    setIsShuffle(nextShuffleState);
    isShuffleRef.current = nextShuffleState;

    if (nextShuffleState) {
      const localShuffled = shuffleArray(queue);
      setQueue(localShuffled);
      if (localShuffled.length > 1) {
        const reqId = ++shuffleRequestIdRef.current;
        const queueIds = localShuffled.map(s => s.id);
        const startingTrackId = currentTrack?.id;
        getShuffleOrder(queueIds, startingTrackId)
          .then(orderedIds => {
            if (reqId !== shuffleRequestIdRef.current || !isShuffleRef.current || currentTrackRef.current?.id !== startingTrackId || !orderedIds?.length) return;
            setQueue(prevQueue => {
              if (prevQueue.length !== queueIds.length) return prevQueue;
              const prevIdSet = new Set(prevQueue.map(s => s.id));
              if (!queueIds.every(id => prevIdSet.has(id))) return prevQueue;
              const songMap = new Map(prevQueue.map(s => [s.id, s]));
              const newQueue: Song[] = [];
              for (const id of orderedIds) {
                const s = songMap.get(id);
                if (s) { newQueue.push(s); songMap.delete(id); }
              }
              for (const remainingSong of songMap.values()) newQueue.push(remainingSong);
              return newQueue;
            });
          })
          .catch(err => console.debug('[AudioContext] Smart shuffle fallback to random:', err));
      }
    } else if (contextMemory && currentTrack) {
      shuffleRequestIdRef.current++;
      const songIndex = contextMemory.findIndex(s => s.id === currentTrack.id);
      if (songIndex !== -1) setQueue(contextMemory.slice(songIndex + 1));
    }
  }, [isShuffle, queue, currentTrack, contextMemory, isShuffleRef, shuffleRequestIdRef, currentTrackRef, setIsShuffle, setQueue]);

  return { playContext, playNext, playPrevious, playFromSearch, toggleShuffle };
}
