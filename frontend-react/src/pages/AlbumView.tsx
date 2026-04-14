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
        className="relative pt-12 pb-8 px-6 flex flex-col items-center gap-6 transition-all duration-700 overflow-hidden"
        style={{ 
          background: `linear-gradient(to bottom, ${albumData.color || '#2a2a2a'} 0%, #000 100%)`,
          minHeight: '60vh'
        }}
      >
        {/* Top Spacer for Fixed Back Button */}
        <div className="h-6 w-full" />

        {/* Big Album Cover - Mobile Focused */}
        <div className="w-[85%] max-w-[300px] aspect-square flex-shrink-0 shadow-[0_20px_50px_rgba(0,0,0,0.8)] rounded-lg overflow-hidden transform hover:scale-[1.02] transition-all duration-500 border border-white/5">
          <img 
            src={albumData.image || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&h=500&fit=crop'} 
            alt={albumData.title}
            className="w-full h-full object-cover"
          />
        </div>

        {/* Album Details Block */}
        <div className="flex flex-col items-start w-full px-2 mt-4">
          <h1 className="text-3xl font-black text-white mb-2 leading-tight tracking-tight">
            {albumData.title}
          </h1>
          <div className="flex items-center gap-2 mb-4 group cursor-pointer">
             <div className="w-6 h-6 rounded-full overflow-hidden bg-neutral-800">
                <img src={albumData.image} className="w-full h-full object-cover opacity-80" alt="" />
             </div>
             <p className="text-sm text-neutral-300 font-bold hover:underline">
               {albumData.artist}
             </p>
          </div>
          
          <div className="flex items-center gap-2 text-[12px] font-bold text-neutral-400 uppercase tracking-wider">
            <span>Album</span>
            <span className="text-neutral-600">•</span>
            <span>2024</span>
          </div>
        </div>
      </div>

      {/* Persistent Content Area */}
      <div className="flex-1 bg-black px-6 pb-12">
        {/* Action Row (Shuffle, Play, Download) */}
        <div className="flex items-center justify-between py-6">
           <div className="flex items-center gap-6">
              <button 
                onClick={() => {
                  if (albumData.songs?.[0]) {
                    playContext(albumData.songs[0], albumData.songs);
                    saveCollectionPlay({
                      id: albumData.id || id || '',
                      title: albumData.title,
                      coverUrl: albumData.image,
                      type: 'album'
                    });
                  }
                }}
                className="w-14 h-14 bg-[#1ed760] rounded-full text-black flex items-center justify-center hover:scale-110 active:scale-95 transition-all shadow-xl"
              >
                <Play size={24} fill="black" className="ml-1" />
              </button>
              
              <button className="text-neutral-400 hover:text-white transition-all transform active:scale-90">
                <Heart size={28} />
              </button>
              
              <button className="text-neutral-400 hover:text-white transition-all transform active:scale-90">
                <MoreHorizontal size={28} />
              </button>
           </div>
           
           <div className="flex items-center gap-4">
              <button className="text-[#1ed760] transition-all transform active:scale-90">
                 <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor"><path d="M19.99 12.99a8 8 0 10-14.82 4.19L3 21l3.81-2.17A8 8 0 0019.99 12.99zM12 18a6 6 0 110-12 6 6 0 010 12z"></path></svg>
              </button>
           </div>
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
                    id: albumData.id || id || '',
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
