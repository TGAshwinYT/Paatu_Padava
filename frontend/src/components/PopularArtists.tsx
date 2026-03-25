import React from 'react';
import HomeSection from './HomeSection';
import { User as UserIcon } from 'lucide-react';

interface Artist {
  id: string;
  name: string;
  image?: string;
  imageUrl?: string;
}

interface PopularArtistsProps {
  artists: Artist[];
  onArtistClick: (name: string) => void;
}

const PopularArtists: React.FC<PopularArtistsProps> = ({ artists, onArtistClick }) => {
  return (
    <HomeSection title="Popular artists" showAllLink="/artists">
      <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
        {artists.map((artist) => (
          <div 
            key={artist.id}
            onClick={() => onArtistClick(artist.name)}
            className="bg-[#181818] p-4 rounded-lg hover:bg-[#282828] transition-all duration-300 cursor-pointer group flex flex-col items-center text-center"
          >
            <div className="relative w-full aspect-square mb-4 shadow-[0_8px_24px_rgba(0,0,0,0.5)] rounded-full overflow-hidden">
              <img 
                src={artist.imageUrl || artist.image || `https://ui-avatars.com/api/?name=${encodeURIComponent(artist.name)}&background=random`} 
                className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500" 
                alt={artist.name} 
                loading="lazy"
              />
              {!artist.imageUrl && !artist.image && (
                <div className="absolute inset-0 flex items-center justify-center bg-neutral-800">
                   <UserIcon size={40} className="text-neutral-500" />
                </div>
              )}
            </div>
            <p className="text-white font-bold text-base truncate w-full">{artist.name}</p>
            <p className="text-[#a7a7a7] text-sm font-medium mt-1">Artist</p>
          </div>
        ))}
      </div>
    </HomeSection>
  );
};

export default PopularArtists;
