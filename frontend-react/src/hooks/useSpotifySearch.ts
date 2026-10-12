import { useState, useEffect } from 'react';
import { searchSpotify, getSpotifyToken } from '../services/spotifyApi';
import type { SpotifyTrack } from '../types';
import useDebounce from './useDebounce';

interface UseSpotifySearchResult {
  results: SpotifyTrack[];
  isLoading: boolean;
  error: string | null;
  hasCredentials: boolean;
}

/**
 * Debounced Spotify full-text track search hook.
 * Returns SpotifyTrack[] results after a 500ms debounce.
 */
const useSpotifySearch = (query: string): UseSpotifySearchResult => {
  const [results, setResults] = useState<SpotifyTrack[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasCredentials, setHasCredentials] = useState(true);

  const debouncedQuery = useDebounce(query, 500);

  useEffect(() => {
    let active = true;
    getSpotifyToken().then((token) => {
      if (active) {
        setHasCredentials(Boolean(token));
      }
    }).catch(() => {
      if (active) {
        setHasCredentials(false);
      }
    });

    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (!debouncedQuery.trim()) {
      setResults([]);
      setError(null);
      return;
    }

    let cancelled = false;

    const doSearch = async () => {
      setIsLoading(true);
      setError(null);
      try {
        const tracks = await searchSpotify(debouncedQuery);
        if (!cancelled) {
          setResults(tracks);
        }
      } catch (err: unknown) {
        if (!cancelled) {
          const errObj = err as { message?: string };
          setError(errObj?.message || 'Spotify search failed.');
          setResults([]);
        }
      } finally {
        if (!cancelled) setIsLoading(false);
      }
    };

    doSearch();

    return () => {
      cancelled = true;
    };
  }, [debouncedQuery]);

  return { results, isLoading, error, hasCredentials };
};

export default useSpotifySearch;
