import React, { createContext, useContext, useState, useCallback, useMemo } from 'react';
import type { Song } from '../types';

export interface QueueContextType {
  queue: Song[];
  history: Song[];
  addToQueue: (track: Song) => void;
  removeFromQueue: (trackId: string) => void;
  reorderQueue: (startIndex: number, endIndex: number) => void;
  handleOnDragEnd: (result: any) => void;
  setQueue: React.Dispatch<React.SetStateAction<Song[]>>;
  clearHistory: () => void;
  pushToHistory: (track: Song) => void;
}

const QueueContext = createContext<QueueContextType | undefined>(undefined);

export const QueueProvider: React.FC<{
  children: React.ReactNode;
  initialQueue?: Song[];
}> = ({ children, initialQueue = [] }) => {
  const [queue, setQueue] = useState<Song[]>(initialQueue);
  const [history, setHistory] = useState<Song[]>(() => {
    try {
      const saved = localStorage.getItem('paatu_history');
      return saved ? JSON.parse(saved) : [];
    } catch {
      return [];
    }
  });

  const addToQueue = useCallback((track: Song) => {
    setQueue((prev) => {
      if (prev.some((s) => s.id === track.id)) return prev;
      return [...prev, { ...track, isManual: true }];
    });
  }, []);

  const removeFromQueue = useCallback((trackId: string) => {
    setQueue((prev) => prev.filter((s) => s.id !== trackId));
  }, []);

  const reorderQueue = useCallback((startIndex: number, endIndex: number) => {
    setQueue((prev) => {
      const result = Array.from(prev);
      const [removed] = result.splice(startIndex, 1);
      result.splice(endIndex, 0, removed);
      return result;
    });
  }, []);

  const handleOnDragEnd = useCallback(
    (result: any) => {
      if (!result.destination) return;
      reorderQueue(result.source.index, result.destination.index);
    },
    [reorderQueue]
  );

  const pushToHistory = useCallback((track: Song) => {
    setHistory((prev) => {
      const filtered = prev.filter((s) => s.id !== track.id);
      const next = [track, ...filtered].slice(0, 50);
      try {
        localStorage.setItem('paatu_history', JSON.stringify(next));
      } catch {}
      return next;
    });
  }, []);

  const clearHistory = useCallback(() => {
    setHistory([]);
    try {
      localStorage.removeItem('paatu_history');
    } catch {}
  }, []);

  const value = useMemo<QueueContextType>(
    () => ({
      queue,
      history,
      addToQueue,
      removeFromQueue,
      reorderQueue,
      handleOnDragEnd,
      setQueue,
      clearHistory,
      pushToHistory,
    }),
    [
      queue,
      history,
      addToQueue,
      removeFromQueue,
      reorderQueue,
      handleOnDragEnd,
      clearHistory,
      pushToHistory,
    ]
  );

  return <QueueContext.Provider value={value}>{children}</QueueContext.Provider>;
};

export const useQueue = (): QueueContextType => {
  const context = useContext(QueueContext);
  if (!context) {
    throw new Error('useQueue must be used within a QueueProvider');
  }
  return context;
};
