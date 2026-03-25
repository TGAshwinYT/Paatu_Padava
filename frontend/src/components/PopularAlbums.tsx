import React from 'react';
import HomeSection from './HomeSection';
import type { Song } from '../types';

interface PopularAlbumsProps {
  albums: Song[];
}

const PopularAlbums: React.FC<PopularAlbumsProps> = ({ albums }) => {
  return (
    <HomeSection title="Popular albums" showAllLink="/albums">
      <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
        {albums.map((album) => (
          <div 
            key={album.id}
            className="bg-[#181818] p-4 rounded-lg hover:bg-[#282828] transition-all duration-300 cursor-pointer group flex flex-col h-full"
          >
            <div className="relative mb-4">
              <img 
                src={album.coverUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200&h=200&fit=crop'} 
                className="w-full aspect-square object-cover rounded-md shadow-[0_8px_24px_rgba(0,0,0,0.5)]" 
                alt={album.title} 
                loading="lazy"
              />
            </div>
            <div className="flex flex-col">
              <p className="text-white font-bold text-base truncate pb-1">{album.title}</p>
              <p className="text-[#a7a7a7] text-sm font-medium truncate">
                {album.artist}
              </p>
            </div>
          </div>
        ))}
      </div>
    </HomeSection>
  );
};

export default PopularAlbums;
