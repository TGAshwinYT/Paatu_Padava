import { describe, it, expect, beforeEach } from 'vitest';
import {
  getGuestPlaylists,
  saveGuestPlaylists,
  getAccountPlaylists,
  saveAccountPlaylists,
  clearAccountPlaylists,
  getUnhandledGuestPlaylists,
  markGuestImportHandled,
  type LocalPlaylist,
} from '../utils/offlineStorage';

describe('Guest vs Account Playlist Isolation', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it('keeps guest playlists and account playlists in separate buckets', () => {
    const guest: LocalPlaylist = {
      id: 'guest-1',
      title: 'Guest Mix',
      tracks: [],
      created_at: new Date().toISOString(),
      scope: 'guest',
    };
    const account: LocalPlaylist = {
      id: 'acc-1',
      title: 'Cloud Favorites',
      tracks: [],
      created_at: new Date().toISOString(),
      scope: 'account',
    };

    saveGuestPlaylists([guest]);
    saveAccountPlaylists('user-123', [account]);

    expect(getGuestPlaylists()).toHaveLength(1);
    expect(getGuestPlaylists()[0].id).toBe('guest-1');
    expect(getAccountPlaylists('user-123')).toHaveLength(1);
    expect(getAccountPlaylists('user-123')[0].id).toBe('acc-1');
  });

  it('purges account playlists on logout while preserving guest playlists', () => {
    saveGuestPlaylists([
      { id: 'guest-1', title: 'Local Roadtrip', tracks: [], created_at: '', scope: 'guest' },
    ]);
    saveAccountPlaylists('user-123', [
      { id: 'acc-1', title: 'Private Cloud', tracks: [], created_at: '', scope: 'account' },
    ]);

    clearAccountPlaylists('user-123');

    expect(getAccountPlaylists('user-123')).toEqual([]);
    expect(getGuestPlaylists()).toHaveLength(1);
    expect(getGuestPlaylists()[0].title).toBe('Local Roadtrip');
  });

  it('tracks unhandled guest playlists and respects import decision', () => {
    saveGuestPlaylists([
      { id: 'guest-a', title: 'A', tracks: [], created_at: '', scope: 'guest' },
      { id: 'guest-b', title: 'B', tracks: [], created_at: '', scope: 'guest' },
    ]);

    expect(getUnhandledGuestPlaylists('user-123')).toHaveLength(2);
    markGuestImportHandled('user-123', ['guest-a']);
    const remaining = getUnhandledGuestPlaylists('user-123');
    expect(remaining).toHaveLength(1);
    expect(remaining[0].id).toBe('guest-b');
  });
});
