import HomeSection from './HomeSection';

interface Artist {
  id: string;
  name: string;
  image?: any; 
  image_url?: string;
}

interface Props {
  artists: Artist[];
  onArtistClick: (name: string) => void;
}

const PopularArtists = ({ artists, onArtistClick }: Props) => {
  // If the array is empty, don't crash, just hide the section
  if (!artists || artists.length === 0) return null;

  return (
    <HomeSection title="Popular artists" showAllLink="/artists">
      {/* Horizontal scrolling container for the circular cards */}
      <div className="flex gap-6 overflow-x-auto pb-4 pt-2 scrollbar-hide">
        {artists.map((artist, index) => {
          
          // 🚨 ULTIMATE IMAGE FALLBACK LOGIC 🚨
          // This ensures the image NEVER crashes the app, no matter what format the database uses
          let imageUrl = 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=200&h=200&fit=crop'; 
          
          if (typeof artist.image === 'string') {
            imageUrl = artist.image;
          } else if (Array.isArray(artist.image) && artist.image.length > 0) {
            imageUrl = artist.image[0].url || artist.image[0]; 
          } else if (artist.image_url) {
            imageUrl = artist.image_url;
          }

          // Fallback for name if backend uses 'artist' instead of 'name'
          const displayName = artist.name || (artist as any).artist || "Unknown Artist";

          return (
            <div 
              key={artist.id || index} 
              onClick={() => onArtistClick(displayName)}
              className="flex flex-col items-center gap-3 cursor-pointer group min-w-[150px]"
            >
              {/* The Perfect Circle Image */}
              <div className="w-36 h-36 rounded-full overflow-hidden shadow-lg group-hover:shadow-2xl transition-all duration-300">
                <img 
                  src={imageUrl} 
                  alt={displayName} 
                  className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                  loading="lazy"
                />
              </div>
              
              {/* Artist Name & Tag */}
              <div className="flex flex-col items-center text-center">
                <p className="text-white font-bold text-base truncate w-32 hover:underline">{displayName}</p>
                <p className="text-[#a7a7a7] text-sm mt-1">Artist</p>
              </div>
            </div>
          );
        })}
      </div>
    </HomeSection>
  );
};

export default PopularArtists;
