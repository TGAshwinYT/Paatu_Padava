import { useState, useEffect } from 'react';
import { Search as SearchIcon, Play } from 'lucide-react';
import api from '../services/api';
import SongCard from '../components/SongCard';
import HomeSection from '../components/HomeSection';
import PopularArtists from '../components/PopularArtists';
import PopularAlbums from '../components/PopularAlbums';
import type { Song, Album, Artist } from '../types';
import { useNavigate } from 'react-router-dom';
import { getHomeFeed, searchTracks, saveSearchClick, getListenHistory, getFollowedArtists } from '../services/api';
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
  const { playTrack } = useAudio();
  const navigate = useNavigate();

  // Search States
  const [query, setQuery] = useState('');
  const [searchResults, setSearchResults] = useState<{ songs: Song[], albums: Album[], artists: Artist[] }>({ songs: [], albums: [], artists: [] });
  const [isSearching, setIsSearching] = useState(false);
  
  // Trie Autocomplete state
  const [autoSuggestions, setAutoSuggestions] = useState<any[]>([]);
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);

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
        
        // 1. SPY ON THE BACKEND:
        console.log("🚨 DEBUG BACKEND DATA:", data);

        // 1. Normalize Personal Artists (from Supabase) TO MATCH JIOSAAVN FORMAT:
        let normalizedArtists = (artistsData || []).map((a: any) => ({
          id: a.id || a.artist_id || '',
          name: a.name || a.artist_name || a.artist || 'Unknown Artist',
          image: [{ url: a.image_url || a.image || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200&h=200&fit=crop' }]
        }));

        // 2. Use real data from backend
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

  // Search Logic (Debounced)
  useEffect(() => {
    const delayDebounceFn = setTimeout(async () => {
      if (query.trim().length > 0) {
        setIsSearching(true);
        try {
          // Fetch Trie-based artist autocomplete suggestions
          const response = await api.get(`/api/search/autocomplete?q=${query}`);
          const data = Array.isArray(response.data) ? response.data : [];
          setAutoSuggestions(data);
          
          // Original search logic for full results
          const results = await searchTracks(query);
          setSearchResults(results);
          setIsSearching(false);
          setIsDropdownOpen(true);
        } catch (error) {
          console.error("Autocomplete failed:", error);
          setAutoSuggestions([]);
          setIsSearching(false);
        }
      } else {
        setSearchResults({ songs: [], albums: [], artists: [] });
        setAutoSuggestions([]);
        setIsDropdownOpen(false);
      }
    }, 300);

    return () => clearTimeout(delayDebounceFn);
  }, [query]);

  const handleResultClick = (song: Song) => {
    saveSearchClick(song);
    playTrack(song);
    setIsDropdownOpen(false);
    setQuery('');
  };

  const handleArtistClick = (artistName: string) => {
    setQuery(artistName);
    setIsDropdownOpen(false);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      setIsDropdownOpen(false);
      navigate(`/search?q=${query}`);
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
      <div className="relative w-full max-w-2xl group mt-2 mb-2">
        {/* ... search input ... */}
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
        {isDropdownOpen && (autoSuggestions.length > 0 || searchResults.songs.length > 0) && (
          <div className="absolute top-full left-0 mt-2 w-full bg-[#282828] rounded-md shadow-2xl z-50 overflow-hidden border border-neutral-700 animate-in slide-in-from-top-2 duration-200">
            {/* 1. Artist Suggestions (from Trie) */}
            {Array.isArray(autoSuggestions) && autoSuggestions.length > 0 && (
              <div className="p-1">
                {autoSuggestions.map((artist) => (
                  <div 
                    key={artist.id} 
                    className="flex items-center gap-3 p-3 hover:bg-[#3E3E3E] cursor-pointer transition-colors group/item"
                    onClick={() => {
                       setIsDropdownOpen(false);
                       navigate(`/artist/${artist.id.startsWith('vip_') ? artist.name : artist.id}`);
                    }}
                  >
                    <img 
                      src={artist.image} 
                      alt={artist.name} 
                      className="w-10 h-10 rounded-full object-cover border border-white/10 shadow-lg" 
                    />
                    <div className="flex flex-col">
                      <span className="text-white font-bold text-sm group-hover/item:text-[#1ed760] transition-colors">{artist.name}</span>
                      <span className="text-neutral-400 text-xs font-semibold uppercase tracking-wider">Artist</span>
                    </div>
                  </div>
                ))}
              </div>
            )}

            {/* 2. Quick Track Results (from Search) */}
            {!isSearching && searchResults.songs.length > 0 && (
              <div className="p-1 border-t border-white/5">
                <h3 className="text-[10px] uppercase font-bold text-neutral-500 px-3 py-2 tracking-wider">Popular Results</h3>
                {searchResults.songs.slice(0, 3).map((song) => (
                  <div 
                    key={song.id} 
                    onClick={() => handleResultClick(song as Song)}
                    className="flex items-center gap-3 p-2 hover:bg-[#3E3E3E] rounded-md cursor-pointer transition-colors group/song"
                  >
                    <img src={song.coverUrl} className="w-8 h-8 rounded object-cover" alt="" />
                    <div className="truncate">
                      <p className="text-sm font-bold text-white truncate group-hover/song:text-[#1ed760]">{song.title}</p>
                      <p className="text-xs text-neutral-400 truncate">{song.artist}</p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>


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
            {recommended.map((song) => (
              <SwiperSlide key={song.id}>
                <div 
                   onClick={() => playTrack(song)}
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
            {recentlyPlayed.map((song) => (
              <SwiperSlide key={song.id}>
                <SongCard song={song} />
              </SwiperSlide>
            ))}
          </Swiper>
        </HomeSection>
      )}





      {topArtists?.length > 0 && (
        <PopularArtists artists={topArtists.slice(0, 5)} onArtistClick={handleArtistClick} />
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
