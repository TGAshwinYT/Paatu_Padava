import React from 'react';
import HomeSection from './HomeSection';
import type { Song } from '../types';

interface PopularAlbumsProps {
  albums: Song[];
  title?: string;
}

const PopularAlbums: React.FC<PopularAlbumsProps> = ({ albums, title = "Popular albums" }) => {
  if (!albums || albums.length === 0) return null;

  return (
    <HomeSection title={title} showAllLink="/albums">
      <style>{`
        .hide-scrollbar::-webkit-scrollbar { display: none; }
        .hide-scrollbar { -ms-overflow-style: none; scrollbar-width: none; }
      `}</style>

      <div className="flex gap-6 overflow-x-auto pb-4 pt-2 hide-scrollbar">
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
            <div 
              key={album.id}
              className="flex-shrink-0 w-36 group cursor-pointer"
            >
              <div className="relative mb-3">
                <img 
                  src={albumImage} 
                  className="w-36 h-36 rounded-md object-cover shadow-lg group-hover:shadow-2xl group-hover:scale-[1.02] transition-all duration-300" 
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
            </div>
          );
        })}
      </div>
    </HomeSection>
  );
};

export default PopularAlbums;
