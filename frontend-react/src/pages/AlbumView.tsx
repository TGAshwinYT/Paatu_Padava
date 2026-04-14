import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Play, Heart, MoreHorizontal, ArrowLeft } from 'lucide-react';
import { useAudio } from '../context/AudioContext';
import { getAlbumDetails, getRecommendations } from '../services/api';
import type { Song } from '../types';
import { saveCollectionPlay } from '../utils/historyUtils';

const AlbumView = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { playContext } = useAudio();
  const [albumData, setAlbumData] = useState<any>(null);
  const [recommendations, setRecommendations] = useState<Song[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const fetchAlbum = async () => {
      if (!id) return;
      setIsLoading(true);
      try {
        const data = await getAlbumDetails(id);
        setAlbumData(data);
      } catch (error) {
        console.error("Error loading album:", error);
      } finally {
        setIsLoading(false);
      }
    };
    fetchAlbum();
  }, [id]);

  useEffect(() => {
    const fetchRecs = async () => {
      if (albumData?.songs?.[0]?.id) {
        const recs = await getRecommendations(albumData.songs[0].id);
        setRecommendations(recs);
      }
    };
    fetchRecs();
  }, [albumData]);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-white"></div>
      </div>
    );
  }

  if (!albumData) {
    return (
      <div className="p-8 text-center">
        <h2 className="text-2xl font-bold text-white">Album not found</h2>
        <p className="text-neutral-400 mt-2">The album you're looking for is unavailable.</p>
      </div>
    );
  }


  return (
    <div className="flex flex-col min-h-full bg-black">
      {/* Back Button */}
      <button 
        onClick={() => navigate(-1)}
        className="fixed top-6 left-6 z-50 p-2.5 bg-black/40 backdrop-blur-md rounded-full text-white hover:bg-black/60 transition-all border border-white/10 active:scale-90"
      >
        <ArrowLeft size={24} strokeWidth={2.5} />
      </button>

      {/* Hero Header */}
      <div 
        className="relative pt-20 pb-10 px-8 flex flex-col md:flex-row items-center md:items-end gap-10 transition-colors duration-500"
        style={{ backgroundImage: `linear-gradient(to bottom, #2a2a2a, #121212)` }} 
      >
        {/* Album Cover */}
        <div className="w-64 h-64 flex-shrink-0 shadow-[0_12px_60px_rgba(0,0,0,0.9)] rounded-lg overflow-hidden transform hover:scale-[1.03] transition-transform duration-500">
          <img 
            src={albumData.image || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&h=500&fit=crop'} 
            alt={albumData.title}
            className="w-full h-full object-cover"
          />
        </div>

        {/* Album Details */}
        <div className="flex flex-col items-center md:items-start text-center md:text-left">
          <span className="text-xs font-bold uppercase tracking-widest text-white/50 mb-3 ml-1">Album</span>
          <h1 className="text-5xl md:text-7xl font-bold text-white mb-2 tracking-tight">
            {albumData.title}
          </h1>
          <p className="text-xl md:text-2xl text-neutral-300 font-semibold mb-6 ml-1">
            {albumData.artist}
          </p>
          
          <div className="flex items-center gap-2 text-sm font-bold text-white/40 ml-1">
            <span>{albumData.songs?.length || 0} tracks</span>
            <span className="text-white/20">•</span>
            <span>2024</span>
          </div>
        </div>
      </div>

      {/* Content Area */}
      <div className="flex-1 bg-gradient-to-b from-[#121212]/80 via-[#121212] to-black px-8 pb-12">
        {/* Action Bar */}
        <div className="flex items-center gap-8 py-10">
          <button 
            onClick={() => {
              if (albumData.songs?.[0]) {
                playContext(albumData.songs[0], albumData.songs);
                saveCollectionPlay({
                  id: albumData.id,
                  title: albumData.title,
                  coverUrl: albumData.image,
                  type: 'album'
                });
              }
            }}
            className="w-16 h-16 bg-[#1ed760] rounded-full text-black flex items-center justify-center hover:scale-110 active:scale-95 transition-all shadow-2xl hover:bg-[#1fdf64]"
            title="Play"
          >
            <Play size={28} fill="black" className="ml-1" />
          </button>

          <button className="text-neutral-500 hover:text-white transition-colors transform hover:scale-110" title="Add to Library">
            <Heart size={36} />
          </button>

          <button className="text-neutral-500 hover:text-white transition-colors transform hover:scale-110" title="More options">
            <MoreHorizontal size={36} />
          </button>
        </div>

        {/* Tracklist Table */}
        <div className="mt-4 max-w-7xl">
          <div className="grid grid-cols-[32px_1fr_120px] gap-6 px-4 py-3 border-b border-white/5 text-neutral-500 text-[11px] uppercase font-bold tracking-[0.2em] mb-4">
            <div className="text-center">#</div>
            <div>Title</div>
            <div className="flex justify-end pr-8 italic">Duration</div>
          </div>

          <div className="flex flex-col space-y-1">
            {albumData.songs?.map((track: Song, index: number) => (
              <div 
                key={track.id}
                onClick={() => {
                  playContext(track, albumData.songs);
                  saveCollectionPlay({
                    id: albumData.id,
                    title: albumData.title,
                    coverUrl: albumData.image,
                    type: 'album'
                  });
                }}
                className="grid grid-cols-[32px_1fr_120px] gap-6 px-4 py-4 hover:bg-[#2a2a2a] rounded-lg group transition-all cursor-pointer items-center border border-transparent hover:border-white/5"
              >
                <div className="flex items-center justify-center w-8 h-8 text-neutral-500 font-bold font-mono">
                  <span className="group-hover:hidden">{index + 1}</span>
                  <Play size={14} fill="white" className="hidden group-hover:block text-white" />
                </div>
                <div className="flex flex-col min-w-0">
                  <span className="text-white font-bold truncate group-hover:text-[#1ed760] transition-colors text-base tracking-tight">{track.title}</span>
                  <span className="text-xs font-semibold text-neutral-500 group-hover:text-neutral-300 transition-colors truncate mt-0.5">{track.artist}</span>
                </div>
                <div className="flex justify-end text-sm text-neutral-400 font-mono pr-8 group-hover:text-white">
                  {track.duration ? `${Math.floor(track.duration / 60)}:${(track.duration % 60).toString().padStart(2, '0')}` : '4:15'}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Recommendations Section */}
        {recommendations.length > 0 && (
          <div className="mt-20 mb-10 max-w-7xl">
            <h2 className="text-2xl font-bold text-white mb-6 tracking-tight">You Might Also Like</h2>
            <div className="flex overflow-x-auto gap-6 pb-6 scrollbar-hide -mx-2 px-2">
              {recommendations.map((rec) => (
                <div 
                  key={rec.id}
                  onClick={() => playContext(rec, recommendations)}
                  className="flex-shrink-0 w-40 md:w-48 bg-[#181818] p-4 rounded-xl hover:bg-[#282828] transition-all cursor-pointer group shadow-lg border border-white/5 active:scale-95"
                >
                  <div className="relative aspect-square mb-4 shadow-[0_8px_24px_rgba(0,0,0,0.5)] rounded-lg overflow-hidden">
                    <img 
                      src={rec.coverUrl} 
                      alt={rec.title}
                      className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500"
                    />
                    <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                      <div className="w-12 h-12 bg-[#1ed760] rounded-full flex items-center justify-center shadow-xl transform translate-y-4 group-hover:translate-y-0 transition-transform duration-300">
                        <Play size={20} fill="black" className="ml-1" />
                      </div>
                    </div>
                  </div>
                  <div className="flex flex-col gap-1">
                    <h3 className="text-white font-bold truncate text-sm tracking-tight group-hover:text-[#1ed760] transition-colors">{rec.title}</h3>
                    <p className="text-neutral-400 text-xs font-semibold truncate group-hover:text-neutral-300 transition-colors">{rec.artist}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default AlbumView;
