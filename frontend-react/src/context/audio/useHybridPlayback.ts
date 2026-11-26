import { useCallback } from 'react';
import type { Song, SpotifyTrack, PlaybackEngine } from '../../types';
import { searchTracks } from '../../services/api';

interface UseHybridPlaybackDeps {
  setCurrentTrack: (song: Song | null) => void;
  setQueue: (queue: Song[]) => void;
  setContextMemory: (ctx: Song[] | null) => void;
  setIsResolvingStream: (loading: boolean) => void;
  setNativeAudioUrl: (url: string | null) => void;
  setYoutubeVideoId: (id: string | null) => void;
  setPlaybackEngine: (engine: PlaybackEngine) => void;
  setIsPlaying: (playing: boolean) => void;
}

export function useHybridPlayback({
  setCurrentTrack,
  setQueue,
  setContextMemory,
  setIsResolvingStream,
  setNativeAudioUrl,
  setYoutubeVideoId,
  setPlaybackEngine,
  setIsPlaying,
}: UseHybridPlaybackDeps) {
  return useCallback(async (spotifyTrack: SpotifyTrack) => {
    const primaryArtist = spotifyTrack.artists[0]?.name ?? '';
    const searchQuery = `${spotifyTrack.name} ${primaryArtist}`.trim();
    const coverArt = spotifyTrack.album.images[0]?.url ?? '/logo.png';

    const spotifySong: Song = {
      id: spotifyTrack.spotifyId,
      title: spotifyTrack.name,
      artist: primaryArtist,
      coverUrl: coverArt,
      audioUrl: '',
      album: spotifyTrack.album.name,
      duration: Math.floor(spotifyTrack.durationMs / 1000),
    };

    setCurrentTrack(spotifySong);
    setQueue([]);
    setContextMemory(null);
    setIsResolvingStream(true);
    setNativeAudioUrl(null);
    setYoutubeVideoId(null);
    setIsPlaying(true);

    try {
      const searchResult = await searchTracks(searchQuery);
      const songs: Song[] = searchResult?.global_matches?.songs ?? [];
      const topSong: Song | null =
        searchResult?.global_matches?.top_result?.type === 'song'
          ? searchResult.global_matches.top_result
          : null;
      const bestMatch: Song | null = topSong ?? songs[0] ?? null;

      const rawUrls: any[] = (bestMatch as any)?.downloadUrls ?? [];
      const highQualityUrl: string | undefined =
        rawUrls[4]?.url ?? rawUrls[3]?.url ?? rawUrls[2]?.url ?? undefined;

      if (bestMatch && highQualityUrl) {
        const resolvedSong: Song = {
          ...spotifySong,
          id: bestMatch.id,
          audioUrl: highQualityUrl,
          downloadUrls: rawUrls,
        };
        setCurrentTrack(resolvedSong);
        setNativeAudioUrl(highQualityUrl);
        setYoutubeVideoId(null);
        setPlaybackEngine('native');
        setIsResolvingStream(false);
        return;
      }

      throw new Error('JioSaavn: no downloadUrl found');
    } catch {
      try {
        const fallbackResult = await searchTracks(searchQuery);
        const fallbackSongs: Song[] = fallbackResult?.global_matches?.songs ?? [];
        const fallbackTop: Song | null =
          fallbackResult?.global_matches?.top_result?.type === 'song'
            ? fallbackResult.global_matches.top_result
            : null;
        const fallback: Song | null = fallbackTop ?? fallbackSongs[0] ?? null;

        if (fallback?.id) {
          const ytSong: Song = { ...spotifySong, id: fallback.id, audioUrl: '' };
          setCurrentTrack(ytSong);
          setNativeAudioUrl(null);
          setYoutubeVideoId(fallback.id);
          setPlaybackEngine('youtube');
        } else {
          setIsPlaying(false);
        }
      } catch {
        setIsPlaying(false);
      } finally {
        setIsResolvingStream(false);
      }
    }
  }, [
    setCurrentTrack,
    setQueue,
    setContextMemory,
    setIsResolvingStream,
    setNativeAudioUrl,
    setYoutubeVideoId,
    setPlaybackEngine,
    setIsPlaying,
  ]);
}
