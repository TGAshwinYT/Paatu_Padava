import React, { createContext, useContext, useState } from 'react';
import type { ReactNode } from 'react';
import type { Song } from '../types';

interface PlaylistModalContextType {
  isOpen: boolean;
  song: Song | null;
  openModal: (song: Song) => void;
  closeModal: () => void;
}

const PlaylistModalContext = createContext<PlaylistModalContextType | undefined>(undefined);

export const PlaylistModalProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [isOpen, setIsOpen] = useState(false);
  const [song, setSong] = useState<Song | null>(null);

  const openModal = (song: Song) => {
    setSong(song);
    setIsOpen(true);
  };

  const closeModal = () => {
    setIsOpen(false);
    setSong(null);
  };

  return (
    <PlaylistModalContext.Provider value={{ isOpen, song, openModal, closeModal }}>
      {children}
    </PlaylistModalContext.Provider>
  );
};

export const usePlaylistModal = () => {
  const context = useContext(PlaylistModalContext);
  if (!context) {
    throw new Error('usePlaylistModal must be used within a PlaylistModalProvider');
  }
  return context;
};
