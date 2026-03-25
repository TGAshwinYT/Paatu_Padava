import { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { Play } from 'lucide-react';
import { getArtistDetails } from '../services/api';
import { useAudio } from '../context/AudioContext';
import type { Song } from '../types';

const ArtistView = () => {
  const { artistId } = useParams<{ artistId: string }>();
  const [artist, setArtist] = useState<{ id: string, name: string, image: string, topSongs: Song[] } | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const { playTrack } = useAudio();

  useEffect(() => {
    const fetchArtist = async () => {
      if (!artistId) return;
      setIsLoading(true);
      const data = await getArtistDetails(artistId);
      setArtist(data);
      setIsLoading(false);
    };
    fetchArtist();
  }, [artistId]);

  if (isLoading) {
    return (
      <div className="flex flex-col gap-8 pb-24 items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-white"></div>
      </div>
    );
  }

  if (!artist || !artist.id) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-neutral-500">
        <p className="text-xl font-medium">Artist not found</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-10 pb-24 animate-in fade-in duration-700">
      {/* Hero Section */}
      <div className="flex flex-col md:flex-row items-center md:items-end gap-8">
        <div className="w-48 h-48 md:w-64 md:h-64 flex-shrink-0">
          <img 
            src={artist.image || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&h=500&fit=crop'} 
            alt={artist.name} 
            className="w-full h-full object-cover rounded-full shadow-2xl border-4 border-white/10"
            loading="lazy"
          />
        </div>
        <div className="flex flex-col gap-2 text-center md:text-left">
          <span className="text-xs uppercase font-black tracking-[0.2em] text-green-500">Verified Artist</span>
          <h1 className="text-5xl md:text-8xl font-black text-white tracking-tighter">
            {artist.name}
          </h1>
        </div>
      </div>

      {/* Top Songs */}
      <div className="flex flex-col gap-6">
        <h2 className="text-2xl font-bold text-white mb-2">Popular Tracks</h2>
        
        <div className="flex flex-col">
          {artist.topSongs.length > 0 ? (
            artist.topSongs.map((song, idx) => (
              <div 
                key={song.id} 
                className="group flex items-center gap-4 p-4 rounded-xl hover:bg-white/5 transition-all cursor-pointer border border-transparent hover:border-white/5"
                onClick={() => playTrack(song)}
              >
                <div className="text-neutral-500 w-4 font-medium group-hover:hidden">
                  {idx + 1}
                </div>
                <div className="text-green-500 w-4 hidden group-hover:block">
                  <Play size={14} fill="currentColor" />
                </div>

                <img 
                  src={song.coverUrl} 
                  alt="" 
                  className="w-12 h-12 rounded-lg shadow-lg object-cover" 
                  loading="lazy"
                />
                
                <div className="flex-1 min-w-0">
                  <p className="font-bold text-white truncate group-hover:text-green-500 transition-colors">
                    {song.title}
                  </p>
                  <p className="text-xs text-neutral-400 truncate mt-0.5">
                    {song.artist}
                  </p>
                </div>

                <div className="hidden md:block text-neutral-500 text-sm">
                   3:45
                </div>

                <button 
                  onClick={(e) => {
                    e.stopPropagation();
                    playTrack(song);
                  }}
                  className="p-3 bg-green-500 rounded-full text-black opacity-0 group-hover:opacity-100 shadow-xl hover:scale-110 transition-all"
                >
                  <Play size={18} fill="currentColor" />
                </button>
              </div>
            ))
          ) : (
            <p className="text-neutral-500 italic">No popular tracks found.</p>
          )}
        </div>
      </div>
    </div>
  );
};

export default ArtistView;
