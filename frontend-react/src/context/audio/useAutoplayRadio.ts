import { useRef, useCallback, useEffect } from 'react';
import type React from 'react';
import type { Song } from '../../types';
import { getRecommendations, getShuffleOrder } from '../../services/api';
import { shuffleArray } from './audioTypes';

interface UseAutoplayRadioDeps {
  isAutoplayRef: React.MutableRefObject<boolean>;
  queueRef: React.MutableRefObject<Song[]>;
  currentTrackRef: React.MutableRefObject<Song | null>;
  radioHistoryIdsRef: React.MutableRefObject<string[]>;
  isAutoplay: boolean;
  isPlaying: boolean;
  queueLength: number;
  currentTrack: Song | null;
  setQueue: React.Dispatch<React.SetStateAction<Song[]>>;
  setIsAutoplay: (enabled: boolean) => void;
  playContext: (track: Song, tracks?: Song[]) => void;
}

export function useAutoplayRadio({
  isAutoplayRef,
  queueRef,
  currentTrackRef,
  radioHistoryIdsRef,
  isAutoplay,
  isPlaying,
  queueLength,
  currentTrack,
  setQueue,
  setIsAutoplay,
  playContext,
}: UseAutoplayRadioDeps) {
  const isFetchingAutoplayRef = useRef<boolean>(false);

  const replenishAutoplayQueue = useCallback(async (seedTrack: Song): Promise<Song[]> => {
    if (!isAutoplayRef.current || isFetchingAutoplayRef.current || !seedTrack?.id) return [];
    isFetchingAutoplayRef.current = true;

    try {
      const recs = await getRecommendations(seedTrack.id, seedTrack.artist, undefined, 25);
      if (!recs || recs.length === 0) return [];

      const currentQueueIds = new Set(queueRef.current.map(s => s.id));
      const currentActiveId = currentTrackRef.current?.id;
      const recentHistoryIds = new Set(radioHistoryIdsRef.current.slice(-25));

      let candidates = recs.filter(
        s =>
          s.id !== seedTrack.id &&
          s.id !== currentActiveId &&
          !currentQueueIds.has(s.id) &&
          !recentHistoryIds.has(s.id)
      );

      if (candidates.length < 5) {
        const strictExcluded = new Set([
          seedTrack.id,
          ...(currentActiveId ? [currentActiveId] : []),
          ...queueRef.current.map(s => s.id),
          ...radioHistoryIdsRef.current.slice(-10),
        ]);
        const relaxed = recs.filter(s => !strictExcluded.has(s.id));
        if (relaxed.length > 0) {
          candidates = relaxed;
        }
      }

      if (candidates.length === 0) return [];

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
      } catch {
        // Keep Fisher-Yates shuffled order
      }

      const fresh = orderedSongs.map(s => ({ ...s, isManual: false, isRadio: true }));

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
  }, [isAutoplayRef, queueRef, currentTrackRef, radioHistoryIdsRef, setQueue]);

  useEffect(() => {
    if (isAutoplay && isPlaying && queueLength <= 1 && currentTrack) {
      replenishAutoplayQueue(currentTrack);
    }
  }, [isAutoplay, isPlaying, queueLength, currentTrack, replenishAutoplayQueue]);

  const startSongRadio = useCallback(async (seedSong: Song) => {
    if (!seedSong) return;

    playContext(seedSong, [seedSong]);
    setIsAutoplay(true);
    isAutoplayRef.current = true;
    radioHistoryIdsRef.current = [seedSong.id];

    try {
      const recs = await getRecommendations(seedSong.id, seedSong.artist, undefined, 25);
      if (recs && recs.length > 0) {
        const candidates = recs.filter(s => s.id !== seedSong.id);
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
  }, [playContext, setQueue, setIsAutoplay, isAutoplayRef, radioHistoryIdsRef]);

  return { replenishAutoplayQueue, startSongRadio };
}
