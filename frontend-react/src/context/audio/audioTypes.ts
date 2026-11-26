import type React from 'react';
import type { Song, SpotifyTrack, PlaybackEngine } from '../../types';
import type { EqPreset, EqBand } from '../../hooks/useEqualizer';
import type { LocalPlaylist } from '../../utils/offlineStorage';

export const shuffleArray = <T,>(array: T[]): T[] => {
  const shuffled = [...array];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled;
};

export interface AudioActionsContextType {
  playContext: (track: Song, tracks?: Song[]) => void;
  togglePlay: () => void;
  seekTo: (value: number) => void;
  setVolume: (value: number) => void;
  toggleRepeat: () => void;
  toggleShuffle: () => void;
  playNext: () => void;
  playPrevious: () => void;
  setSleepTimer: (minutes: number | 'end' | null) => void;
  addToQueue: (track: Song) => void;
  removeFromQueue: (trackId: string) => void;
  reorderQueue: (startIndex: number, endIndex: number) => void;
  handleOnDragEnd: (result: any) => void;
  refreshPlaylists: () => Promise<void>;
  createGuestPlaylist: (title: string) => LocalPlaylist;
  renameGuestPlaylist: (id: string, title: string) => void;
  deleteGuestPlaylist: (id: string) => void;
  removeSongFromGuestPlaylist: (playlistId: string, songId: string) => void;
  addSongToGuestPlaylist: (playlistId: string, song: Song) => void;
  setQueue: React.Dispatch<React.SetStateAction<Song[]>>;
  clearHistory: () => void;
  playFromSearch: (track: Song) => void;
  playHybridTrack: (spotifyTrack: SpotifyTrack) => Promise<void>;
  setCrossfadeDuration: (seconds: number) => void;
  setEqBandGain: (bandIndex: number, gain: number) => void;
  applyEqPreset: (preset: EqPreset) => void;
  toggleAutoplay: () => void;
  setIsAutoplay: (enabled: boolean) => void;
  startSongRadio: (seedSong: Song) => Promise<void>;
  downloadCurrentTrack: () => Promise<void>;
}

export interface AudioContextType extends AudioActionsContextType {
  currentTrack: Song | null;
  isPlaying: boolean;
  volume: number;
  isShuffle: boolean;
  repeatMode: 'none' | 'all' | 'one';
  remainingSleepTime: number | null;
  queue: Song[];
  history: Song[];
  userPlaylists: any[];
  guestPlaylists: LocalPlaylist[];
  accountPlaylists: LocalPlaylist[];
  isBuffering: boolean;
  onEnded: () => void;
  playbackEngine: PlaybackEngine;
  nativeAudioUrl: string | null;
  youtubeVideoId: string | null;
  isResolvingStream: boolean;
  crossfadeDuration: number;
  eqBands: EqBand[];
  eqPreset: EqPreset;
  isEqAvailable: boolean;
  isAutoplay: boolean;
}
