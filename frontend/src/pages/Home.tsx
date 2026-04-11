import { useState, useEffect, useRef } from 'react';
import { Search as SearchIcon, Play, ChevronRight, ChevronLeft } from 'lucide-react';
import SongCard from '../components/SongCard';
import HomeSection from '../components/HomeSection';
import PopularArtists from '../components/PopularArtists';
import PopularAlbums from '../components/PopularAlbums';
import type { Song } from '../types';
import { useNavigate } from 'react-router-dom';
import { getHomeFeed, getListenHistory, getFollowedArtists } from '../services/api';
import { useAudio } from '../context/AudioContext';
import 'swiper/css';

interface HomeProps {
  isLoggedIn: boolean;
}

const Home = ({ isLoggedIn }: HomeProps) => {
  const [recentlyPlayed, setRecentlyPlayed] = useState<Song[]>([]);
  const [topArtists, setTopArtists] = useState<any[]>([]);
  const [recommended, setRecommended] = useState<Song[]>([]);
  const [topAlbums, setTopAlbums] = useState<Song[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { playFromSearch, playContext } = useAudio();
  const navigate = useNavigate();

  const recommendedRef = useRef<HTMLDivElement>(null);
  const recentlyPlayedRef = useRef<HTMLDivElement>(null);

  const scrollAction = (ref: React.RefObject<HTMLDivElement>, direction: 'left' | 'right') => {
    if (ref.current) {
        const scrollAmount = direction === 'left' ? -400 : 400;
        ref.current.scrollBy({ left: scrollAmount, behavior: 'smooth' });
    }
  };

  useEffect(() => {
    const fetchFeed = async () => {
      setIsLoading(true);
      try {
        const [feedData, historyData, artistsData] = await Promise.all([
          getHomeFeed(),
          isLoggedIn ? getListenHistory() : Promise.resolve([]),
          isLoggedIn ? getFollowedArtists() : Promise.resolve([])
        ]);
        
        const data = feedData as any;
        setRecentlyPlayed((historyData || []).slice(0, 12));
        
        let normalizedArtists = (artistsData || []).map((a: any) => ({
          id: a.id || a.artist_id || '',
          name: a.name || a.artist_name || a.artist || 'Unknown Artist',
          image: [{ url: a.image_url || a.image || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200&h=200&fit=crop' }]
        }));

        const backendArtists = data.topArtists || data.popularArtists || [];
        const finalArtists = normalizedArtists.length > 0 ? normalizedArtists : backendArtists;

        setTopArtists(finalArtists.slice(0, 12));
        setRecommended(data.recommendedForYou || []);
        setTopAlbums(data.topAlbums || []);
      } catch (error) {
        console.error("Error fetching home feed:", error);
      } finally {
        setIsLoading(false);
      }
    };
    fetchFeed();
  }, [isLoggedIn]);


  if (isLoading) {
    return (
      <div className="flex flex-col gap-8 pb-24 items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-white"></div>
        <p className="text-neutral-400 mt-4">Loading your feed...</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-12 pb-24 pt-6">

      {recommended.length > 0 && (
        <HomeSection title="Recommended For You" showAllLink="/recommendations" className="bg-gradient-to-r from-green-500/10 to-transparent p-6 rounded-2xl border border-white/5">
          <div className="relative group/slider">
            <button 
                onClick={() => scrollAction(recommendedRef, 'left')} 
                className="absolute left-[-16px] top-1/2 -translate-y-1/2 z-10 hidden md:flex items-center justify-center w-10 h-10 bg-black/50 hover:bg-black/80 text-white rounded-full opacity-0 group-hover/slider:opacity-100 transition-opacity"
            >
                <ChevronLeft size={24} />
            </button>
            <div ref={recommendedRef} className="flex overflow-x-auto gap-4 pb-4 snap-x snap-mandatory scroll-smooth hide-scrollbar">
              {recommended.map((song, index) => (
                <div key={`${song.id}-${index}`} className="flex-shrink-0 w-36 md:w-44 lg:w-48 snap-start group bg-[#181818] p-4 rounded-lg hover:bg-[#282828] transition-all duration-300 cursor-pointer flex flex-col h-full" onClick={() => playContext(song, recommended)}>
                    <div className="relative mb-4">
                      <img 
                        src={song.coverUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200&h=200&fit=crop'} 
                        className="w-full aspect-square object-cover rounded-md shadow-[0_8px_24px_rgba(0,0,0,0.5)]" 
                        alt={song.title} 
                        loading="lazy"
                      />
                      <button 
                        className="absolute bottom-2 right-2 bg-[#1ed760] w-12 h-12 rounded-full shadow-lg opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0 transition-all duration-300 ease-out flex items-center justify-center hover:scale-105 active:scale-95"
                        onClick={(e) => {
                          e.stopPropagation();
                          playContext(song, recommended);
                        }}
                      >
                        <Play size={20} fill="black" className="text-black ml-1" />
                      </button>
                    </div>
                    <div className="flex flex-col">
                      <p className="text-white font-bold text-base truncate pb-1">{song.title}</p>
                      <p className="text-[#a7a7a7] text-sm font-medium truncate">{song.artist}</p>
                    </div>
                </div>
              ))}
            </div>
            <button 
                onClick={() => scrollAction(recommendedRef, 'right')} 
                className="absolute right-[-16px] top-1/2 -translate-y-1/2 z-10 hidden md:flex items-center justify-center w-10 h-10 bg-black/50 hover:bg-black/80 text-white rounded-full opacity-0 group-hover/slider:opacity-100 transition-opacity"
            >
                <ChevronRight size={24} />
            </button>
          </div>
        </HomeSection>
      )}

      {recentlyPlayed.length > 0 && (
        <HomeSection title="Recently Played" showAllLink="/history">
          <div className="relative group/slider">
            <button 
                onClick={() => scrollAction(recentlyPlayedRef, 'left')} 
                className="absolute left-[-16px] top-1/2 -translate-y-1/2 z-10 hidden md:flex items-center justify-center w-10 h-10 bg-black/50 hover:bg-black/80 text-white rounded-full opacity-0 group-hover/slider:opacity-100 transition-opacity"
            >
                <ChevronLeft size={24} />
            </button>
            <div ref={recentlyPlayedRef} className="flex overflow-x-auto gap-4 pb-4 snap-x snap-mandatory scroll-smooth hide-scrollbar">
              {recentlyPlayed.map((song, index) => (
                <div key={`${song.id}-${index}`} className="flex-shrink-0 w-36 md:w-44 lg:w-48 snap-start">
                  <SongCard song={song} context={recentlyPlayed} />
                </div>
              ))}
            </div>
            <button 
                onClick={() => scrollAction(recentlyPlayedRef, 'right')} 
                className="absolute right-[-16px] top-1/2 -translate-y-1/2 z-10 hidden md:flex items-center justify-center w-10 h-10 bg-black/50 hover:bg-black/80 text-white rounded-full opacity-0 group-hover/slider:opacity-100 transition-opacity"
            >
                <ChevronRight size={24} />
            </button>
          </div>
        </HomeSection>
      )}

      {topArtists?.length > 0 && (
        <PopularArtists artists={topArtists.slice(0, 5)} onArtistClick={(name) => {
          navigate(`/search?q=${encodeURIComponent(name)}`);
        }} />
      )}

      {topAlbums.length > 0 && <PopularAlbums albums={topAlbums} />}

      {isLoggedIn && recentlyPlayed.length === 0 && topArtists.length === 0 && topAlbums.length === 0 && (
        <div className="text-neutral-400 text-center mt-20 flex flex-col items-center">
          <p className="text-xl mb-2 font-semibold">No data available.</p>
          <p className="text-sm">Please ensure your FastAPI backend is running.</p>
        </div>
      )}
    </div>
  );
};

export default Home;
