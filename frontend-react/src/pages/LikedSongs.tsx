import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import SongCard from '../components/SongCard';
import type { Song } from '../types';
import { getLikedSongs } from '../services/api';
import { useAuth } from '../context/AuthContext';
import { useAudio } from '../context/AudioContext';
import { Heart, Play, Pause, Shuffle, Sparkles, Compass } from 'lucide-react';

const LikedSongs = () => {
  const [songs, setSongs] = useState<Song[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { user } = useAuth();
  const { playContext, currentTrack, isPlaying, togglePlay } = useAudio();
  const navigate = useNavigate();

  useEffect(() => {
    const fetchLiked = async () => {
      if (!user) {
        setIsLoading(false);
        return;
      }
      setIsLoading(true);
      try {
        const data = await getLikedSongs();
        setSongs(data);
      } catch (err) {
        console.error("Failed to load liked songs:", err);
      } finally {
        setIsLoading(false);
      }
    };
    fetchLiked();
  }, [user]);

  if (isLoading) {
    return (
      <div className="flex flex-col gap-8 pb-24 items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-brand"></div>
      </div>
    );
  }

  if (!user) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[50vh] text-center p-8">
        <Heart size={64} className="text-neutral-600 mb-4" />
        <h2 className="text-2xl font-bold mb-2">Login to see your favorites</h2>
        <p className="text-neutral-400 max-w-sm mb-6">
          Save songs, albums, and playlists to your library and listen whenever you want.
        </p>
        <button
          onClick={() => navigate('/login')}
          className="px-8 py-3 bg-brand text-black font-bold rounded-full hover:scale-105 transition shadow-lg"
        >
          Log in
        </button>
      </div>
    );
  }

  const isLikedPlaying = isPlaying && songs.some(s => s.id === currentTrack?.id);

  return (
    <div className="flex flex-col gap-8 pb-24 animate-in fade-in duration-500">
      {/* Hero Header */}
      <div className="flex flex-col md:flex-row items-center md:items-end gap-6 p-6 rounded-2xl bg-gradient-to-br from-indigo-900/60 via-purple-900/40 to-neutral-900 border border-white/5 shadow-2xl">
        <div className="w-44 h-44 sm:w-52 sm:h-52 bg-gradient-to-br from-indigo-600 to-purple-700 rounded-2xl shadow-2xl flex items-center justify-center flex-shrink-0 border border-white/10 ring-2 ring-purple-500/20">
          <Heart size={80} fill="white" stroke="white" className="drop-shadow-lg" />
        </div>
        <div className="flex flex-col gap-3 text-center md:text-left flex-1 min-w-0">
          <span className="text-xs uppercase font-extrabold tracking-widest text-purple-300">Playlist</span>
          <h1 className="text-4xl sm:text-6xl md:text-7xl font-black text-white tracking-tight">
            Liked Songs
          </h1>
          <p className="text-sm font-semibold text-neutral-300">
            {user.username} <span className="text-neutral-500">•</span> {songs.length} {songs.length === 1 ? 'song' : 'songs'}
          </p>

          {/* Action Row */}
          {songs.length > 0 && (
            <div className="flex items-center justify-center md:justify-start gap-4 mt-2">
              <button
                onClick={() => {
                  if (isLikedPlaying) {
                    togglePlay();
                  } else {
                    playContext(songs[0], songs);
                  }
                }}
                className="w-14 h-14 bg-brand text-black rounded-full flex items-center justify-center hover:scale-105 active:scale-95 transition-all shadow-xl"
                title={isLikedPlaying ? "Pause Liked Songs" : "Play All Liked Songs"}
              >
                {isLikedPlaying ? (
                  <Pause size={24} fill="currentColor" />
                ) : (
                  <Play size={24} fill="currentColor" className="ml-1" />
                )}
              </button>

              <button
                onClick={() => {
                  const shuffled = [...songs].sort(() => Math.random() - 0.5);
                  playContext(shuffled[0], shuffled);
                }}
                className="p-3 bg-neutral-800/80 hover:bg-neutral-700 text-white rounded-full border border-white/10 hover:scale-105 transition shadow-lg"
                title="Shuffle Liked Songs"
              >
                <Shuffle size={20} />
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Song Grid */}
      {songs.length > 0 ? (
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
          {songs.map(song => (
            <SongCard 
              key={song.id} 
              song={song} 
              isInitiallyLiked={true} 
              context={songs}
            />
          ))}
        </div>
      ) : (
        <div className="text-neutral-400 text-center mt-16 flex flex-col items-center justify-center py-12 border border-dashed border-white/10 rounded-2xl">
          <Compass size={48} className="text-neutral-600 mb-3" />
          <p className="text-xl mb-2 font-semibold text-white">Your liked songs collection is empty</p>
          <p className="text-sm text-neutral-400 max-w-sm mb-6">
            Tap the heart icon on any song, search results, or albums to collect your favorite tracks here.
          </p>
          <button
            onClick={() => navigate('/search')}
            className="flex items-center gap-2 px-6 py-2.5 bg-neutral-800 hover:bg-neutral-700 text-white rounded-full font-bold text-sm transition"
          >
            <Sparkles size={16} className="text-brand" />
            <span>Discover Music</span>
          </button>
        </div>
      )}
    </div>
  );
};

export default LikedSongs;
