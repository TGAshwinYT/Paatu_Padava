import type { Song } from '../types';

const CACHE_NAME = 'paatu-offline-audio-v1';
const OFFLINE_METADATA_KEY = 'paatu_offline_tracks_meta';

export interface OfflineTrackMetadata {
  id: string;
  title: string;
  artist: string;
  album?: string;
  duration?: number;
  coverUrl?: string;
  downloadedAt: number;
  sizeBytes?: number;
  quality: string;
}

export const isOfflineStorageSupported = (): boolean => {
  return typeof window !== 'undefined' && 'caches' in window;
};

export const getOfflineTracks = (): OfflineTrackMetadata[] => {
  if (typeof window === 'undefined') return [];
  try {
    const raw = localStorage.getItem(OFFLINE_METADATA_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
};

export const isOfflineTrack = (songId: string): boolean => {
  if (!songId) return false;
  const list = getOfflineTracks();
  return list.some(item => item.id === songId);
};

export const saveOfflineTrack = async (
  song: Song,
  blob: Blob,
  quality: string = '320kbps'
): Promise<void> => {
  if (!isOfflineStorageSupported() || !song?.id) return;

  try {
    const cache = await caches.open(CACHE_NAME);
    const cacheUrl = `/offline-audio/${song.id}`;

    const response = new Response(blob, {
      headers: {
        'Content-Type': 'audio/mpeg',
        'Content-Length': blob.size.toString(),
        'X-Paatu-Downloaded': 'true'
      }
    });

    await cache.put(cacheUrl, response);

    // Save metadata
    const list = getOfflineTracks().filter(t => t.id !== song.id);
    const newMeta: OfflineTrackMetadata = {
      id: song.id,
      title: song.title || 'Unknown Title',
      artist: song.artist || 'Unknown Artist',
      album: song.album,
      duration: song.duration,
      coverUrl: song.cover_url || song.coverUrl || (song as any).image,
      downloadedAt: Date.now(),
      sizeBytes: blob.size,
      quality
    };

    list.unshift(newMeta);
    localStorage.setItem(OFFLINE_METADATA_KEY, JSON.stringify(list));

    window.dispatchEvent(new CustomEvent('paatu:offline-storage-updated', { detail: { songId: song.id } }));
  } catch (error) {
    console.error('Failed to save track for offline playback:', error);
  }
};

export const getOfflineTrackBlob = async (songId: string): Promise<Blob | null> => {
  if (!isOfflineStorageSupported() || !songId) return null;

  try {
    const cache = await caches.open(CACHE_NAME);
    const cacheUrl = `/offline-audio/${songId}`;
    const response = await cache.match(cacheUrl);
    if (!response) return null;
    return await response.blob();
  } catch (error) {
    console.error('Failed to load offline track blob:', error);
    return null;
  }
};

export const getOfflineTrackObjectUrl = async (songId: string): Promise<string | null> => {
  const blob = await getOfflineTrackBlob(songId);
  if (!blob) return null;
  return URL.createObjectURL(blob);
};

export const removeOfflineTrack = async (songId: string): Promise<void> => {
  if (!isOfflineStorageSupported() || !songId) return;

  try {
    const cache = await caches.open(CACHE_NAME);
    await cache.delete(`/offline-audio/${songId}`);

    const list = getOfflineTracks().filter(t => t.id !== songId);
    localStorage.setItem(OFFLINE_METADATA_KEY, JSON.stringify(list));

    window.dispatchEvent(new CustomEvent('paatu:offline-storage-updated', { detail: { songId } }));
  } catch (error) {
    console.error('Failed to remove offline track:', error);
  }
};

export const clearAllOfflineTracks = async (): Promise<void> => {
  if (!isOfflineStorageSupported()) return;

  try {
    await caches.delete(CACHE_NAME);
    localStorage.removeItem(OFFLINE_METADATA_KEY);
    window.dispatchEvent(new CustomEvent('paatu:offline-storage-updated'));
  } catch (error) {
    console.error('Failed to clear offline storage:', error);
  }
};

export const getOfflineStorageStats = async (): Promise<{
  count: number;
  totalBytes: number;
  formattedSize: string;
}> => {
  const tracks = getOfflineTracks();
  const count = tracks.length;
  const totalBytes = tracks.reduce((sum, t) => sum + (t.sizeBytes || 0), 0);

  let formattedSize = '0 MB';
  if (totalBytes > 1024 * 1024 * 1024) {
    formattedSize = `${(totalBytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
  } else if (totalBytes > 0) {
    formattedSize = `${(totalBytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  return { count, totalBytes, formattedSize };
};
