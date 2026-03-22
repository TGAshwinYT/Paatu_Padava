import TrackPlayer from 'react-native-track-player';
import axios from 'axios';

const BACKEND_URL = 'http://localhost:8000'; // Replace with your production URL

/**
 * Bridges JioSaavn IDs to playable tracks in TrackPlayer.
 * Fetches the 320kbps stream URL from our FastAPI backend.
 */
export const playJioSaavnSong = async (songId: string) => {
  try {
    // 1. Fetch song details from our backend (which proxy calls JioSaavn)
    // Assuming our search/details endpoint returns the direct audio_url
    const response = await axios.get(`${BACKEND_URL}/api/music/search`, {
      params: { query: songId } // Or a dedicated details endpoint if implemented
    });

    const song = response.data.find((s: any) => s.id === songId);

    if (!song || !song.audio_url) {
      throw new Error('Could not find stream URL for this song');
    }

    // 2. Add to TrackPlayer and start playback
    await TrackPlayer.add({
      id: song.id,
      url: song.audio_url,
      title: song.title,
      artist: song.artist,
      artwork: song.cover_url,
    });

    await TrackPlayer.play();
  } catch (error) {
    console.error('Bridge Error:', error);
  }
};
