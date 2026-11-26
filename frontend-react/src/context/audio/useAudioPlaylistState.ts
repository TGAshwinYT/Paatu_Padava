import { useState, useCallback, useEffect, useMemo } from 'react';
import type { Song } from '../../types';
import api from '../../services/api';
import {
  getGuestPlaylists,
  saveGuestPlaylists,
  getAccountPlaylists,
  saveAccountPlaylists,
  clearAccountPlaylists,
  type LocalPlaylist,
} from '../../utils/offlineStorage';

export function useAudioPlaylistState(userId?: string) {
  const [guestPlaylists, setGuestPlaylists] = useState<LocalPlaylist[]>(() => getGuestPlaylists());
  const [accountPlaylists, setAccountPlaylists] = useState<LocalPlaylist[]>([]);

  const userPlaylists = useMemo(
    () => (userId ? [...accountPlaylists, ...guestPlaylists] : [...guestPlaylists]),
    [userId, accountPlaylists, guestPlaylists]
  );

  const refreshPlaylists = useCallback(async () => {
    const guests = getGuestPlaylists();
    setGuestPlaylists(guests);
    if (!userId) {
      setAccountPlaylists([]);
      return;
    }
    try {
      const response = await api.get('/api/playlists/');
      const remote: LocalPlaylist[] = (response.data || []).map((p: any) => ({
        ...p,
        scope: 'account' as const,
      }));
      saveAccountPlaylists(userId, remote);
      setAccountPlaylists(remote);
    } catch (error) {
      console.error('Failed to fetch playlists:', error);
      setAccountPlaylists(getAccountPlaylists(userId));
    }
  }, [userId]);

  const createGuestPlaylist = useCallback((title: string): LocalPlaylist => {
    const cleanTitle = title.trim() || 'My Guest Playlist';
    const newPl: LocalPlaylist = {
      id: `guest-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      title: cleanTitle,
      tracks: [],
      created_at: new Date().toISOString(),
      scope: 'guest',
    };
    const next = [newPl, ...getGuestPlaylists()];
    saveGuestPlaylists(next);
    setGuestPlaylists(next);
    window.dispatchEvent(new Event('playlists-updated'));
    return newPl;
  }, []);

  const renameGuestPlaylist = useCallback((id: string, title: string) => {
    const next = getGuestPlaylists().map((p) => (p.id === id ? { ...p, title } : p));
    saveGuestPlaylists(next);
    setGuestPlaylists(next);
    window.dispatchEvent(new Event('playlists-updated'));
  }, []);

  const deleteGuestPlaylist = useCallback((id: string) => {
    const next = getGuestPlaylists().filter((p) => p.id !== id);
    saveGuestPlaylists(next);
    setGuestPlaylists(next);
    window.dispatchEvent(new Event('playlists-updated'));
  }, []);

  const removeSongFromGuestPlaylist = useCallback((playlistId: string, songId: string) => {
    const next = getGuestPlaylists().map((p) =>
      p.id === playlistId
        ? { ...p, tracks: (p.tracks || []).filter((t: any) => t.id !== songId) }
        : p
    );
    saveGuestPlaylists(next);
    setGuestPlaylists(next);
  }, []);

  const addSongToGuestPlaylist = useCallback((playlistId: string, song: Song) => {
    const next = getGuestPlaylists().map((p) => {
      if (p.id !== playlistId) return p;
      const tracks = p.tracks || [];
      if (tracks.some((t: any) => t.id === song.id)) return p;
      return {
        ...p,
        cover_url: p.cover_url || song.coverUrl,
        tracks: [...tracks, song],
      };
    });
    saveGuestPlaylists(next);
    setGuestPlaylists(next);
  }, []);

  useEffect(() => {
    let cancelled = false;
    Promise.resolve().then(() => {
      if (cancelled) return;
      if (userId) {
        refreshPlaylists();
      } else {
        clearAccountPlaylists();
        setAccountPlaylists([]);
        setGuestPlaylists(getGuestPlaylists());
      }
    });
    return () => {
      cancelled = true;
    };
  }, [userId, refreshPlaylists]);

  return {
    guestPlaylists,
    accountPlaylists,
    userPlaylists,
    refreshPlaylists,
    createGuestPlaylist,
    renameGuestPlaylist,
    deleteGuestPlaylist,
    removeSongFromGuestPlaylist,
    addSongToGuestPlaylist,
  };
}
