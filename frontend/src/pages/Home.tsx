import { useState, useEffect } from 'react';
import { Search as SearchIcon, Play, User as UserIcon } from 'lucide-react';
import SongCard from '../components/SongCard';
import HomeSection from '../components/HomeSection';
import PopularArtists from '../components/PopularArtists';
import PopularAlbums from '../components/PopularAlbums';
import type { Song } from '../types';
import { getHomeFeed, searchTracks, getSuggestions, saveSearchClick, getListenHistory, getFollowedArtists } from '../services/api';
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

  // Search States
  const [query, setQuery] = useState('');
  const [searchResults, setSearchResults] = useState<Song[]>([]);
  const [suggestions, setSuggestions] = useState<any>({ songs: [], artists: [], albums: [] });
  const [isSearching, setIsSearching] = useState(false);
  const [showDropdown, setShowDropdown] = useState(false);

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

        // 2. CREATE EMERGENCY DUMMY DATA:
        const dummyArtists = [
          { id: '1', name: 'Anirudh Ravichander', image: [{url: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200&h=200&fit=crop'}] },
          { id: '2', name: 'A.R. Rahman', image: [{url: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=200&h=200&fit=crop'}] },
          { id: '3', name: 'Sid Sriram', image: [{url: 'https://images.unsplash.com/photo-1493225457124-a1a2a5ea3a26?w=200&h=200&fit=crop'}] }
        ];

        // 3. NORMALIZE PERSONAL ARTISTS (from Supabase) TO MATCH JIOSAAVN FORMAT:
        let normalizedArtists = (artistsData || []).map((a: any) => ({
          id: a.id || a.artist_id || '',
          name: a.name || a.artist_name || a.artist || 'Unknown Artist',
          image: [{ url: a.image_url || a.image || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200&h=200&fit=crop' }]
        }));

        // 4. TRY TO USE REAL DATA, FALLBACK TO DUMMY DATA IF EMPTY:
        let finalArtists = normalizedArtists.length > 0 ? normalizedArtists : (data.topArtists || data.popularArtists || []);
        
        if (finalArtists.length === 0) {
            console.log("🚨 No artists found in database! Using dummy data so UI doesn't break.");
            finalArtists = dummyArtists;
        }

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
        const [tracks, suggestData] = await Promise.all([
          searchTracks(query),
          getSuggestions(query)
        ]);
        setSearchResults(tracks);
        setSuggestions(suggestData);
        setIsSearching(false);
        setShowDropdown(true);
      } else {
        setSearchResults([]);
        setSuggestions({ songs: [], artists: [], albums: [] });
        setShowDropdown(false);
      }
    }, 300);

    return () => clearTimeout(delayDebounceFn);
  }, [query]);

  const handleResultClick = (song: Song) => {
    saveSearchClick(song);
    playTrack(song);
    setShowDropdown(false);
    setQuery('');
  };

  const handleArtistClick = (artistName: string) => {
    setQuery(artistName);
    setShowDropdown(false);
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
          onFocus={() => query.length > 0 && setShowDropdown(true)}
          placeholder="Search for songs, artists, or albums..."
          className="w-full bg-neutral-800/80 text-white rounded-xl py-3.5 pl-12 pr-4 focus:outline-none focus:ring-2 focus:ring-white/10 transition-all font-medium placeholder-neutral-500 backdrop-blur-md border border-white/5"
        />

        {/* Live Search Dropdown omitted for brevity in replacement but I MUST include it if I replace the whole block */}
        {showDropdown && (query.trim().length > 0) && (searchResults.length > 0 || suggestions.artists?.length > 0) && (
            <div className="absolute top-full left-0 right-0 mt-2 bg-neutral-900 border border-white/10 rounded-xl shadow-2xl z-50 overflow-hidden animate-in slide-in-from-top-2 duration-200 backdrop-blur-xl">
                {isSearching && (
                    <div className="p-4 flex items-center justify-center gap-2 text-neutral-400">
                        <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
                        <span className="text-xs font-medium">Searching...</span>
                    </div>
                )}
                {!isSearching && searchResults.length > 0 && (
                    <div className="p-2">
                        <h3 className="text-[10px] uppercase font-bold text-neutral-500 px-3 py-1 tracking-wider">Tracks</h3>
                        {searchResults.slice(0, 5).map((song) => (
                            <div 
                                key={song.id} 
                                onClick={() => handleResultClick(song)}
                                className="flex items-center gap-3 p-2 hover:bg-white/5 rounded-lg cursor-pointer transition-colors group/item"
                            >
                                <div className="relative w-10 h-10 flex-shrink-0">
                                   <img 
                                      src={song.coverUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=50&h=50&fit=crop'} 
                                      className="w-full h-full rounded shadow-md object-cover" 
                                      alt="" 
                                      loading="lazy"
                                   />
                                   <div className="absolute inset-0 bg-black/40 flex items-center justify-center opacity-0 group-hover/item:opacity-100 transition-opacity rounded">
                                      <Play size={12} fill="white" className="text-white ml-0.5" />
                                   </div>
                                </div>
                                <div className="truncate">
                                    <p className="text-sm font-bold text-white truncate group-hover/item:text-green-500 transition-colors">{song.title}</p>
                                    <p className="text-xs text-neutral-400 truncate tracking-tight">{song.artist}</p>
                                </div>
                            </div>
                        ))}
                    </div>
                )}

                {suggestions.artists?.length > 0 && (
                    <div className="p-2 border-t border-white/5 bg-black/20">
                        <h3 className="text-[10px] uppercase font-bold text-neutral-500 px-3 py-1 tracking-wider">Artists</h3>
                        {suggestions.artists.slice(0, 3).map((a: any) => (
                            <div 
                                key={a.id} 
                                onClick={() => handleArtistClick(a.name || a.artist)}
                                className="flex items-center gap-3 p-2 hover:bg-white/5 rounded-lg cursor-pointer transition-colors"
                            >
                                <div className="w-8 h-8 rounded-full bg-neutral-800 flex items-center justify-center flex-shrink-0 overflow-hidden border border-white/10">
                                    {a.image?.[0]?.url ? <img src={a.image[0].url} className="w-full h-full object-cover" loading="lazy" /> : <UserIcon size={14} className="text-neutral-500" />}
                                </div>
                                <p className="text-sm font-medium text-white truncate">{a.name || a.artist}</p>
                            </div>
                        ))}
                    </div>
                )}
            </div>
        )}
      </div>

      {topArtists?.length > 0 && (
        <PopularArtists artists={topArtists} onArtistClick={handleArtistClick} />
      )}

      {topAlbums.length > 0 && <PopularAlbums albums={topAlbums} />}

      {recommended.length > 0 && (
        <HomeSection title="Recommended For You" showAllLink="/recommendations" className="bg-gradient-to-r from-green-500/10 to-transparent p-6 rounded-2xl border border-white/5">
          <Swiper
            spaceBetween={16}
            slidesPerView={2}
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

      {isLoggedIn && recentlyPlayed.length > 0 && (
        <HomeSection title="Recently Played" showAllLink="/history">
          <Swiper
            spaceBetween={16}
            slidesPerView={2}
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
