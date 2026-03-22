import React, { createContext, useContext, useState } from 'react';
import type { ReactNode } from 'react';

interface PlaylistModalContextType {
  isOpen: boolean;
  songId: string;
  openModal: (songId: string) => void;
  closeModal: () => void;
}

const PlaylistModalContext = createContext<PlaylistModalContextType | undefined>(undefined);

export const PlaylistModalProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [isOpen, setIsOpen] = useState(false);
  const [songId, setSongId] = useState('');

  const openModal = (id: string) => {
    setSongId(id);
    setIsOpen(true);
  };

  const closeModal = () => {
    setIsOpen(false);
    setSongId('');
  };

  return (
    <PlaylistModalContext.Provider value={{ isOpen, songId, openModal, closeModal }}>
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
