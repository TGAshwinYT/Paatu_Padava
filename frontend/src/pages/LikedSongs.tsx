import React, { useState, useEffect } from 'react';
import SongCard from '../components/SongCard';
import type { Song } from '../types';
import { getLikedSongs } from '../services/api';
import { useAuth } from '../context/AuthContext';
import { Heart } from 'lucide-react';

const LikedSongs = () => {
  const [songs, setSongs] = useState<Song[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { user } = useAuth();

  useEffect(() => {
    const fetchLiked = async () => {
      if (!user) {
        setIsLoading(false);
        return;
      }
      setIsLoading(true);
      const data = await getLikedSongs();
      setSongs(data);
      setIsLoading(false);
    };
    fetchLiked();
  }, [user]);

  if (isLoading) {
    return (
      <div className="flex flex-col gap-8 pb-24 items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-white"></div>
      </div>
    );
  }

  if (!user) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[50vh] text-center p-8">
        <Heart size={64} className="text-neutral-600 mb-4" />
        <h2 className="text-2xl font-bold mb-2">Login to see your favorites</h2>
        <p className="text-neutral-400 max-w-sm">
          Save songs, albums, and playlists to your library and listen whenever you want.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-8 pb-24">
      <div className="flex items-center gap-6 mb-8">
        <div className="w-52 h-52 bg-gradient-to-br from-indigo-700 to-purple-800 rounded-md shadow-2xl flex items-center justify-center">
            <Heart size={80} fill="white" stroke="white" />
        </div>
        <div className="flex flex-col gap-2">
            <span className="text-xs uppercase font-bold tracking-widest">Playlist</span>
            <h1 className="text-7xl font-bold">Liked Songs</h1>
            <span className="text-sm font-semibold opacity-80">{user.email} • {songs.length} songs</span>
        </div>
      </div>

      {songs.length > 0 ? (
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
          {songs.map(song => (
            <SongCard key={song.id} song={song} isInitiallyLiked={true} />
          ))}
        </div>
      ) : (
        <div className="text-neutral-400 text-center mt-20">
          <p className="text-xl mb-2 font-semibold">Your liked songs will appear here.</p>
          <p className="text-sm">Start searching and liking your favorite tracks!</p>
        </div>
      )}
    </div>
  );
};

export default LikedSongs;
