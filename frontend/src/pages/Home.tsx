import { useState, useEffect, useRef } from 'react';
import { Search as SearchIcon, Play, ChevronRight } from 'lucide-react';
import SongCard from '../components/SongCard';
import HomeSection from '../components/HomeSection';
import PopularArtists from '../components/PopularArtists';
import PopularAlbums from '../components/PopularAlbums';
import AIDJInput from '../components/AIDJInput';
import type { Song } from '../types';
import { useNavigate } from 'react-router-dom';
import { getHomeFeed, getListenHistory, getFollowedArtists, getSuggestions } from '../services/api';
import { useAudio } from '../context/AudioContext';
import { Swiper, SwiperSlide } from 'swiper/react';
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

  // Search States
  const [query, setQuery] = useState('');
  const [suggestions, setSuggestions] = useState<any>({ songs: [], artists: [], albums: [] });
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const searchContainerRef = useRef<HTMLDivElement>(null);

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

  // Click Outside Listener
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (searchContainerRef.current && !searchContainerRef.current.contains(event.target as Node)) {
        setIsDropdownOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Search Logic (Debounced)
  useEffect(() => {
    let ignore = false;

    const fetchSuggestions = async () => {
      if (query.trim().length > 0) {
        try {
          const data = await getSuggestions(query);
          if (!ignore) {
            setSuggestions(data);
            setIsDropdownOpen(true);
          }
        } catch (error) {
          console.error("Home suggestions failed:", error);
        }
      } else {
        setSuggestions({ songs: [], artists: [], albums: [] });
        setIsDropdownOpen(false);
      }
    };

    const delayDebounceFn = setTimeout(() => {
      fetchSuggestions();
    }, 400);

    return () => {
      ignore = true;
      clearTimeout(delayDebounceFn);
    };
  }, [query]);

  const handleSuggestionClick = (suggestion: any) => {
    setIsDropdownOpen(false);
    setSuggestions({ songs: [], artists: [], albums: [] });
    setQuery('');
    
    if (suggestion.type === 'artist') {
      const artistId = suggestion.id.startsWith('vip_') ? suggestion.name : suggestion.id;
      navigate(`/artist/${artistId}`);
    } else {
      playFromSearch(suggestion);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && query.trim()) {
      setIsDropdownOpen(false);
      setSuggestions({ songs: [], artists: [], albums: [] });
      navigate(`/search?q=${encodeURIComponent(query.trim())}`);
    }
  };

  if (isLoading) {
    return (
      <div className="flex flex-col gap-8 pb-24 items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-white"></div>
        <p className="text-neutral-400 mt-4">Loading your feed...</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-12 pb-24">
      {/* Global Search Bar */}
      <div ref={searchContainerRef} className="relative w-full max-w-2xl group mt-2 mb-2">
        <div className="absolute inset-y-0 left-4 flex items-center pointer-events-none z-10">
          <SearchIcon className={`h-5 w-5 transition-colors ${query ? 'text-white' : 'text-neutral-400 group-focus-within:text-white'}`} />
        </div>
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onFocus={() => query.length > 0 && setIsDropdownOpen(true)}
          onKeyDown={handleKeyDown}
          placeholder="Search for songs, artists, or albums..."
          className="w-full bg-neutral-800/80 text-white rounded-xl py-3.5 pl-12 pr-4 focus:outline-none focus:ring-2 focus:ring-white/10 transition-all font-medium placeholder-neutral-500 backdrop-blur-md border border-white/5"
        />

        {/* Live Search Dropdown */}
        {isDropdownOpen && (suggestions.songs.length > 0 || (suggestions.artists && suggestions.artists.length > 0)) && (
          <div className="absolute top-full left-0 mt-3 w-full bg-[#181818] rounded-2xl shadow-2xl z-[100] overflow-hidden border border-[#333] animate-in fade-in zoom-in-95 duration-200 backdrop-blur-xl">
            {/* Artists Section */}
            {suggestions.artists && suggestions.artists.length > 0 && (
              <div className="p-2">
                <h3 className="text-[11px] uppercase font-black text-neutral-500 px-4 py-3 tracking-[0.1em]">Artists</h3>
                {suggestions.artists.slice(0, 3).map((artist: any, index: number) => (
                  <div 
                    key={`${artist.id}-${index}`} 
                    className="flex items-center gap-4 p-3 hover:bg-neutral-800/80 rounded-xl cursor-pointer transition-all group/item mx-1"
                    onClick={() => handleSuggestionClick({...artist, type: 'artist'})}
                  >
                    <div className="relative">
                      <img 
                        src={artist.image?.[0]?.url || artist.image || 'https://via.placeholder.com/40'} 
                        alt="" 
                        className="w-12 h-12 rounded-full object-cover border border-white/10 shadow-lg group-hover:scale-105 transition-transform" 
                      />
                    </div>
                    <div className="flex-1">
                      <p className="text-white font-bold text-sm group-hover/item:text-green-500 transition-colors uppercase tracking-tight">{artist.name || artist.artist}</p>
                      <p className="text-neutral-500 text-[10px] font-bold uppercase tracking-widest mt-0.5">Artist</p>
                    </div>
                    <ChevronRight size={16} className="text-neutral-600 group-hover/item:text-white transition-colors mr-2" />
                  </div>
                ))}
              </div>
            )}

            {/* Songs Section */}
            {suggestions.songs && suggestions.songs.length > 0 && (
              <div className="p-2 border-t border-white/5 bg-neutral-900/40">
                <h3 className="text-[11px] uppercase font-black text-neutral-500 px-4 py-3 tracking-[0.1em]">Songs</h3>
                {suggestions.songs.slice(0, 5).map((song: any, index: number) => (
                  <div 
                    key={`${song.id}-${index}`} 
                    className="flex items-center gap-4 p-2 hover:bg-neutral-800/80 rounded-xl cursor-pointer transition-all group/song mx-1"
                    onClick={() => handleSuggestionClick({...song, type: 'song'})}
                  >
                    <div className="relative w-10 h-10 flex-shrink-0">
                      <img src={song.image?.[song.image.length-1]?.url || song.coverUrl || 'https://via.placeholder.com/40'} className="w-full h-full rounded shadow-md object-cover" alt="" />
                      <div className="absolute inset-0 bg-black/40 flex items-center justify-center opacity-0 group-hover/song:opacity-100 transition-opacity rounded">
                        <Play size={14} fill="white" className="text-white ml-0.5" />
                      </div>
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-bold text-white truncate group-hover/song:text-green-500 transition-colors">{song.name || song.title}</p>
                      <p className="text-[11px] text-neutral-500 truncate font-semibold uppercase tracking-tight">{song.artist || (song.primaryArtists && song.primaryArtists[0]?.name)}</p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>

      <AIDJInput />

      {recommended.length > 0 && (
        <HomeSection title="Recommended For You" showAllLink="/recommendations" className="bg-gradient-to-r from-green-500/10 to-transparent p-6 rounded-2xl border border-white/5">
          <style>{`
            .hide-scrollbar::-webkit-scrollbar { display: none; }
            .hide-scrollbar { -ms-overflow-style: none; scrollbar-width: none; }
          `}</style>
          <Swiper
            spaceBetween={16}
            slidesPerView={2}
            className="hide-scrollbar"
            breakpoints={{
              640: { slidesPerView: 3 },
              768: { slidesPerView: 4 },
              1024: { slidesPerView: 5 },
              1280: { slidesPerView: 6 },
            }}
          >
            {recommended.map((song, index) => (
              <SwiperSlide key={`${song.id}-${index}`}>
                <div 
                   onClick={() => playContext(song, recommended)}
                   className="bg-[#181818] p-4 rounded-lg hover:bg-[#282828] transition-all duration-300 cursor-pointer group flex flex-col h-full"
                >
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
              </SwiperSlide>
            ))}
          </Swiper>
        </HomeSection>
      )}

      {recentlyPlayed.length > 0 && (
        <HomeSection title="Recently Played" showAllLink="/history">
          <Swiper
            spaceBetween={16}
            slidesPerView={2}
            className="hide-scrollbar"
            breakpoints={{
              640: { slidesPerView: 3 },
              768: { slidesPerView: 4 },
              1024: { slidesPerView: 5 },
              1280: { slidesPerView: 6 },
            }}
          >
            {recentlyPlayed.map((song, index) => (
              <SwiperSlide key={`${song.id}-${index}`}>
                <SongCard song={song} context={recentlyPlayed} />
              </SwiperSlide>
            ))}
          </Swiper>
        </HomeSection>
      )}

      {topArtists?.length > 0 && (
        <PopularArtists artists={topArtists.slice(0, 5)} onArtistClick={(name) => {
          setQuery(name);
          setIsDropdownOpen(false);
          // Trigger navigation or direct search
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
