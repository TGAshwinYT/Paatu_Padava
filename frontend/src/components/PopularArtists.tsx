import HomeSection from './HomeSection';
import { Swiper, SwiperSlide } from 'swiper/react';
import 'swiper/css';

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
      {/* CSS to hide scrollbars while keeping functionality */}
      <style>{`
        .hide-scrollbar::-webkit-scrollbar { display: none; }
        .hide-scrollbar { -ms-overflow-style: none; scrollbar-width: none; }
      `}</style>

      {/* Premium Swiper Slider for Artists */}
      <Swiper
        spaceBetween={24}
        slidesPerView={2}
        breakpoints={{
          480: { slidesPerView: 3 },
          640: { slidesPerView: 4 },
          768: { slidesPerView: 5 },
          1024: { slidesPerView: 6 },
          1280: { slidesPerView: 7 },
          1536: { slidesPerView: 8 },
        }}
        className="pt-2 pb-4 hide-scrollbar"
      >
        {artists.map((artist, index) => {
          
          // 🚨 AGGRESSIVE BULLETPROOF IMAGE EXTRACTION 🚨
          let imageUrl = 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=200&h=200&fit=crop'; 
          
          const imgData = artist.image;
          
          if (typeof imgData === 'string' && imgData.startsWith('http')) {
            imageUrl = imgData;
          } else if (Array.isArray(imgData) && imgData.length > 0) {
            // Priority: Index 2 (high res), then 1, then 0. Check both .link and .url
            const bestImage = imgData[2] || imgData[1] || imgData[0];
            if (typeof bestImage === 'string') {
                imageUrl = bestImage;
            } else {
                imageUrl = bestImage.link || bestImage.url || imageUrl;
            }
          } else if (artist.image_url) {
            imageUrl = artist.image_url;
          }

          const displayName = artist.name || (artist as any).artist || "Unknown Artist";

          return (
            <SwiperSlide key={artist.id || index}>
              <div 
                onClick={() => onArtistClick(displayName)}
                className="flex flex-col items-center gap-3 cursor-pointer group"
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
            </SwiperSlide>
          );
        })}
      </Swiper>
    </HomeSection>
  );
};

export default PopularArtists;
