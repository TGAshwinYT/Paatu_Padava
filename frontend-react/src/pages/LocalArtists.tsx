import { useState, useEffect } from 'react';
import { ArrowLeft } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { getHomeFeed } from '../services/api';

const LocalArtists = () => {
  const [artists, setArtists] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const navigate = useNavigate();

  useEffect(() => {
    const fetchArtists = async () => {
      try {
        const data = await getHomeFeed();
        const topArtists = (data as any).topArtists || (data as any).popularArtists || [];
        setArtists(topArtists);
      } catch (error) {
        console.error("Error fetching local artists:", error);
      } finally {
        setIsLoading(false);
      }
    };
    fetchArtists();
  }, []);

  if (isLoading) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-white"></div>
      </div>
    );
  }

  return (
    <div className="pb-24">
      <div className="flex items-center gap-4 mb-8">
        <button 
          onClick={() => navigate(-1)}
          className="p-2 hover:bg-white/10 rounded-full transition-colors"
        >
          <ArrowLeft size={24} className="text-white" />
        </button>
        <h1 className="text-3xl font-bold text-white tracking-tight">Top Artists in Your Region</h1>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-8">
        {artists.map((artist, index) => {
          const imageUrl = artist.image || artist.coverUrl || artist.imageUrl || 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=200&h=200&fit=crop';
          const displayName = artist.name || (artist as any).title || "UNKNOWN ARTIST";

          return (
            <div 
              key={artist.id || index}
              className="flex flex-col items-center gap-4 group cursor-pointer"
              onClick={() => navigate(`/search?q=${encodeURIComponent(displayName)}`)}
            >
              <div className="w-full aspect-square rounded-full overflow-hidden shadow-xl ring-1 ring-white/10 group-hover:ring-white/30 transition-all duration-300">
                <img 
                  src={imageUrl} 
                  alt={displayName}
                  className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500"
                  loading="lazy"
                />
              </div>
              <div className="text-center">
                <p className="text-white font-bold text-base truncate px-2 group-hover:text-green-500 transition-colors uppercase tracking-tight">
                  {displayName}
                </p>
                <p className="text-neutral-500 text-xs font-bold uppercase tracking-widest mt-1">Artist</p>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

export default LocalArtists;
