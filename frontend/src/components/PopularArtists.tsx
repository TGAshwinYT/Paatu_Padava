import React, { useRef } from 'react';
import HomeSection from './HomeSection';
import { ChevronLeft, ChevronRight } from 'lucide-react';
interface Artist {
  id: string;
  name: string;
  image?: any;
  image_url?: string;
  imageUrl?: string;
  coverUrl?: string;
}

interface Props {
  artists: Artist[];
  onArtistClick: (name: string) => void;
}

const PopularArtists = ({ artists, onArtistClick }: Props) => {
  const scrollRef = useRef<HTMLDivElement>(null);

  const scrollAction = (direction: 'left' | 'right') => {
    if (scrollRef.current) {
        const scrollAmount = direction === 'left' ? -400 : 400;
        scrollRef.current.scrollBy({ left: scrollAmount, behavior: 'smooth' });
    }
  };

  // If the array is empty, don't crash, just hide the section
  if (!artists || artists.length === 0) return null;

  return (
    <HomeSection title="Popular artists" showAllLink="/local-artists">
      <div className="relative group/slider">
        <button 
            onClick={() => scrollAction('left')} 
            className="absolute left-[-16px] top-1/2 -translate-y-1/2 z-10 hidden md:flex items-center justify-center w-10 h-10 bg-black/50 hover:bg-black/80 text-white rounded-full opacity-0 group-hover/slider:opacity-100 transition-opacity"
        >
            <ChevronLeft size={24} />
        </button>
        <div ref={scrollRef} className="flex overflow-x-auto snap-x snap-mandatory gap-6 pb-4 hide-scrollbar pt-2 scroll-smooth">
        {artists.map((artist, index) => {
          
          // 🚨 AGGRESSIVE BULLETPROOF IMAGE EXTRACTION 🚨
          const imageUrl = artist.image || artist.coverUrl || artist.imageUrl || 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=200&h=200&fit=crop';
          const displayName = artist.name || (artist as any).title || "UNKNOWN ARTIST";

          return (
            <div 
              key={artist.id || index}
              onClick={() => onArtistClick(displayName)}
              className="flex flex-col items-center gap-3 cursor-pointer group flex-shrink-0 w-32 md:w-36 lg:w-40 snap-start"
            >
              {/* The Perfect Circle Image */}
              <div className="w-32 h-32 md:w-36 md:h-36 rounded-full overflow-hidden shadow-lg group-hover:shadow-2xl transition-all duration-300 ring-1 ring-white/5 group-hover:ring-white/20">
                <img 
                  src={imageUrl} 
                  alt={displayName} 
                  className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500"
                  loading="lazy"
                  onError={(e) => {
                      (e.target as HTMLImageElement).src = 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200&h=200&fit=crop';
                  }}
                />
              </div>
              
              {/* Artist Name & Tag */}
              <div className="flex flex-col items-center text-center w-full px-2">
                <p className="text-white font-bold text-sm md:text-base truncate w-full hover:text-green-500 transition-colors uppercase tracking-tight">{displayName}</p>
                <p className="text-neutral-500 text-[10px] md:text-xs font-bold uppercase tracking-widest mt-0.5">Artist</p>
              </div>
            </div>
          );
        })}
        </div>
        <button 
            onClick={() => scrollAction('right')} 
            className="absolute right-[-16px] top-1/2 -translate-y-1/2 z-10 hidden md:flex items-center justify-center w-10 h-10 bg-black/50 hover:bg-black/80 text-white rounded-full opacity-0 group-hover/slider:opacity-100 transition-opacity"
        >
            <ChevronRight size={24} />
        </button>
      </div>
    </HomeSection>
  );
};

export default PopularArtists;
