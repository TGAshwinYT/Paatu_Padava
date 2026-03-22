import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import SongCard from '../components/SongCard';
import type { Song } from '../types';
import { getPlaylistDetail, removeSongFromPlaylist } from '../services/api';
import { useAuth } from '../context/AuthContext';
import { Music, Trash2, Play } from 'lucide-react';
import { useAudio } from '../context/AudioContext';

const PlaylistDetail = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [songs, setSongs] = useState<Song[]>([]);
  const [playlistTitle, setPlaylistTitle] = useState('Playlist');
  const [isLoading, setIsLoading] = useState(true);
  const { user } = useAuth();
  const { playTrack } = useAudio();

  useEffect(() => {
    const fetchDetail = async () => {
      if (!id || !user) {
        setIsLoading(false);
        return;
      }
      setIsLoading(true);
      const { title, songs: playlistSongs } = await getPlaylistDetail(id);
      setPlaylistTitle(title);
      setSongs(playlistSongs);
      setIsLoading(false);
    };
    fetchDetail();
  }, [id, user]);

  const handleRemove = async (songId: string) => {
    if (!id) return;
    await removeSongFromPlaylist(id, songId);
    setSongs(prev => prev.filter(s => s.id !== songId));
  };

  const handlePlayAll = () => {
    if (songs.length > 0) {
      playTrack(songs[0], songs);
    }
  };

  if (isLoading) {
    return (
      <div className="flex flex-col gap-8 pb-24 items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-white"></div>
      </div>
    );
  }

  if (!user) {
    navigate('/login');
    return null;
  }

  return (
    <div className="flex flex-col gap-8 pb-24">
      <div className="flex items-center gap-6 mb-8 flex-wrap md:flex-nowrap">
        <div className="w-52 h-52 bg-neutral-800 rounded-md shadow-2xl flex items-center justify-center">
            <Music size={100} className="text-neutral-600" />
        </div>
        <div className="flex flex-col gap-4 flex-1">
            <span className="text-xs uppercase font-bold tracking-widest text-neutral-400">Playlist</span>
            <h1 className="text-5xl md:text-7xl font-bold text-white">{playlistTitle}</h1>
            <div className="flex items-center gap-2">
                <span className="text-sm font-semibold opacity-80">{user.username} • {songs.length} songs</span>
            </div>
            <div className="flex items-center gap-4 mt-2">
                <button 
                  onClick={handlePlayAll}
                  className="bg-green-500 text-black p-4 rounded-full hover:scale-105 transition shadow-lg flex items-center justify-center"
                >
                  <Play fill="currentColor" size={24} />
                </button>
            </div>
        </div>
      </div>

      <div className="flex flex-col gap-1">
        {songs.length > 0 ? (
          songs.map((song) => (
             <div key={song.id} className="group relative">
                <SongCard song={song} />
                <button 
                  onClick={(e) => {
                    e.stopPropagation();
                    handleRemove(song.id);
                  }}
                  className="absolute bottom-4 left-4 opacity-0 group-hover:opacity-100 p-2 bg-red-500/20 text-red-500 rounded-full hover:bg-red-500 hover:text-white transition-all z-10"
                  title="Remove from playlist"
                >
                  <Trash2 size={16} />
                </button>
             </div>
          ))
        ) : (
          <div className="text-neutral-400 text-center mt-20">
            <p className="text-xl mb-2 font-semibold">This playlist is empty.</p>
            <p className="text-sm">Find some great music to add!</p>
          </div>
        )}
      </div>
    </div>
  );
};

export default PlaylistDetail;
