import React, { useRef } from 'react';
import { Link } from 'react-router-dom';
import HomeSection from './HomeSection';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import type { Song } from '../types';

interface PopularAlbumsProps {
  albums: Song[];
  title?: string;
}

const PopularAlbums: React.FC<PopularAlbumsProps> = ({ albums, title = "Popular albums" }) => {
  const scrollRef = useRef<HTMLDivElement>(null);

  const scrollAction = (direction: 'left' | 'right') => {
    if (scrollRef.current) {
        const scrollAmount = direction === 'left' ? -400 : 400;
        scrollRef.current.scrollBy({ left: scrollAmount, behavior: 'smooth' });
    }
  };

  if (!albums || albums.length === 0) return null;

  return (
    <HomeSection title={title} showAllLink="/albums">
      <div className="relative group/slider">
        <button 
            onClick={() => scrollAction('left')} 
            className="absolute left-[-16px] top-1/2 -translate-y-1/2 z-10 hidden md:flex items-center justify-center w-10 h-10 bg-black/50 hover:bg-black/80 text-white rounded-full opacity-0 group-hover/slider:opacity-100 transition-opacity"
        >
            <ChevronLeft size={24} />
        </button>
        <div ref={scrollRef} className="flex overflow-x-auto snap-x snap-mandatory gap-4 pb-4 hide-scrollbar pt-2 scroll-smooth">
        {albums.map((album: any) => {
          // 🚨 ULTIMATE IMAGE EXTRACTION (Same as PopularArtists)
          let albumImage = 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200&h=200&fit=crop';
          
          if (album.image) {
            if (typeof album.image === 'string') {
              albumImage = album.image;
            } else if (Array.isArray(album.image)) {
              // Priority: 2 (High), 1 (Medium), 0 (Low)
              const imgObj = album.image[2] || album.image[1] || album.image[0];
              albumImage = imgObj?.link || imgObj?.url || (typeof imgObj === 'string' ? imgObj : albumImage);
            }
          } else if (album.coverUrl) {
            albumImage = album.coverUrl;
          }

          return (
            <Link 
              key={album.id}
              to={`/album/${album.id}`}
              className="flex-shrink-0 w-36 md:w-44 lg:w-48 snap-start group cursor-pointer block"
            >
              <div className="relative mb-3">
                <img 
                  src={albumImage} 
                  className="w-full aspect-square rounded-md object-cover shadow-lg group-hover:shadow-2xl group-hover:scale-[1.02] transition-all duration-300" 
                  alt={album.title} 
                  loading="lazy"
                  onError={(e) => {
                    (e.target as HTMLImageElement).src = 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200&h=200&fit=crop';
                  }}
                />
              </div>
              <div className="px-1">
                <p className="text-white font-bold text-sm truncate pb-0.5">
                  {album.title}
                </p>
                <p className="text-neutral-400 text-xs font-medium">
                  Album
                </p>
              </div>
            </Link>
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

export default PopularAlbums;
