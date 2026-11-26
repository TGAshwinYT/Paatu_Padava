import { useEffect } from 'react';
import type React from 'react';
import type { Song } from '../../types';
import {
  resolveStreamUrl,
  prefetchStreamUrls,
  savePlayerStateToRedis,
  getPlayerStateFromRedis,
} from '../../services/api';

interface UseAudioPersistenceDeps {
  user: any;
  currentTrack: Song | null;
  queue: Song[];
  isShuffle: boolean;
  repeatMode: 'none' | 'all' | 'one';
  volume: number;
  contextMemory: Song[] | null;
  isShuffleRef: React.MutableRefObject<boolean>;
  currentTrackRef: React.MutableRefObject<Song | null>;
  currentTimeRef: React.MutableRefObject<number>;
  preloadedTrackRef: React.MutableRefObject<{ id: string; url: string } | null>;
  prefetchingSongIdRef: React.MutableRefObject<string | null>;
  setNextStreamUrl: (url: string | null) => void;
  setQueue: React.Dispatch<React.SetStateAction<Song[]>>;
  setCurrentTrack: (song: Song | null) => void;
  setIsShuffle: (val: boolean) => void;
  setRepeatMode: (mode: 'none' | 'all' | 'one') => void;
  setIsPlaying: (playing: boolean) => void;
}

export function useAudioPersistence({
  user,
  currentTrack,
  queue,
  isShuffle,
  repeatMode,
  volume,
  contextMemory,
  isShuffleRef,
  currentTrackRef,
  currentTimeRef,
  preloadedTrackRef,
  prefetchingSongIdRef,
  setNextStreamUrl,
  setQueue,
  setCurrentTrack,
  setIsShuffle,
  setRepeatMode,
  setIsPlaying,
}: UseAudioPersistenceDeps) {
  useEffect(() => {
    isShuffleRef.current = isShuffle;
    try {
      localStorage.setItem('paatu_player_shuffle', String(isShuffle));
    } catch { /* ignore storage quota */ }
  }, [isShuffle, isShuffleRef]);

  useEffect(() => {
    try {
      localStorage.setItem('paatu_player_repeat', repeatMode);
    } catch { /* ignore storage quota */ }
  }, [repeatMode]);

  useEffect(() => {
    try {
      localStorage.setItem('paatu_player_volume', String(volume));
    } catch { /* ignore storage quota */ }
  }, [volume]);

  useEffect(() => {
    currentTrackRef.current = currentTrack;
    try {
      if (currentTrack) {
        localStorage.setItem('paatu_current_track', JSON.stringify(currentTrack));
      } else {
        localStorage.removeItem('paatu_current_track');
      }
    } catch { /* ignore storage quota */ }

    currentTimeRef.current = 0;
  }, [currentTrack?.id, currentTrack, currentTrackRef, currentTimeRef]);

  useEffect(() => {
    try {
      localStorage.setItem('paatu_player_queue', JSON.stringify(queue));
    } catch { /* ignore storage quota */ }
  }, [queue]);

  useEffect(() => {
    try {
      if (contextMemory) {
        localStorage.setItem('paatu_context_memory', JSON.stringify(contextMemory));
      } else {
        localStorage.removeItem('paatu_context_memory');
      }
    } catch { /* ignore storage quota */ }
  }, [contextMemory]);

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

    if (preloadedTrackRef.current && preloadedTrackRef.current.id !== nextTrack.id) {
      preloadedTrackRef.current = null;
      setNextStreamUrl(null);
    }

    if (nextTrack.audioUrl && nextTrack.audioUrl.trim() !== '') {
      preloadedTrackRef.current = { id: nextTrack.id, url: nextTrack.audioUrl };
      setNextStreamUrl(nextTrack.audioUrl);
      return;
    }

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

    if (queue.length > 1) {
      const upcoming = queue.slice(1, 4).filter(t => !t.audioUrl);
      if (upcoming.length > 0) {
        prefetchStreamUrls(upcoming);
      }
    }

    return () => {
      isMounted = false;
    };
  }, [queue, preloadedTrackRef, prefetchingSongIdRef, setNextStreamUrl, setQueue]);

  useEffect(() => {
    if (!user) return;
    const timer = setTimeout(() => {
      savePlayerStateToRedis({
        current_track: currentTrack,
        queue: queue.slice(0, 30),
        is_shuffle: isShuffle,
        repeat_mode: repeatMode,
        volume,
      });
    }, 2000);
    return () => clearTimeout(timer);
  }, [user, currentTrack, queue, isShuffle, repeatMode, volume]);

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
  }, [user, currentTrackRef, setCurrentTrack, setQueue, setIsShuffle, setRepeatMode, setIsPlaying]);
}
