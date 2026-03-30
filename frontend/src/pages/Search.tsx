import React, { useState, useEffect, useRef } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { Search as SearchIcon, Music, Album, Clock, X, Play, ChevronRight } from 'lucide-react';
import SongCard from '../components/SongCard';
import type { Song } from '../types';
import { searchTracks, getSuggestions, getRecentSearches, deleteSearchHistoryItem, saveSearchClick } from '../services/api';
import { useAudio } from '../context/AudioContext';
import { useAuth } from '../context/AuthContext';
import useDebounce from '../hooks/useDebounce';

const Search = () => {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Song[]>([]);
  const [suggestions, setSuggestions] = useState<any>({ songs: [], artists: [], albums: [] });
  const [isSearching, setIsSearching] = useState(false);
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const [recentlyPlayed, setRecentlyPlayed] = useState<(Song & { historyId: string })[]>([]);
  const searchContainerRef = useRef<HTMLDivElement>(null);
  
  const { playContext } = useAudio();
  const { user } = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const initialQuery = searchParams.get('q');
  
  // Debounce the search query with 500ms delay
  const debouncedQuery = useDebounce(query, 500);

  // Fetch history on mount
  useEffect(() => {
    if (user && !query && !initialQuery) {
      const fetchRecent = async () => {
        try {
          const history = await getRecentSearches();
          setRecentlyPlayed(history);
        } catch (error) {
          console.error("Failed to fetch search history:", error);
        }
      };
      fetchRecent();
    }
  }, [user, query, initialQuery]);

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

  // Handle initial query from URL (Handoff from Home)
  useEffect(() => {
    if (initialQuery && initialQuery !== query) {
      setQuery(initialQuery);
      
      const performInitialSearch = async () => {
        setIsSearching(true);
        try {
          const data = await searchTracks(initialQuery);
          setResults(data.songs);
        } catch (error) {
          console.error("Initial search failed:", error);
        } finally {
          setIsSearching(false);
        }
      };
      
      performInitialSearch();
    }
  }, [initialQuery]);

  // Suggestions Fetch Logic
  useEffect(() => {
    let ignore = false;

    const fetchSuggestions = async () => {
      if (debouncedQuery.trim().length > 0) {
        setIsSearching(true);
        try {
          const suggestData = await getSuggestions(debouncedQuery);
          if (!ignore) {
            setSuggestions(suggestData);
            setIsDropdownOpen(true);
          }
        } catch (error) {
          console.error("Suggestions fetch failed:", error);
        } finally {
          if (!ignore) setIsSearching(false);
        }
      } else {
        setSuggestions({ songs: [], artists: [], albums: [] });
        setIsDropdownOpen(false);
      }
    };

    if (debouncedQuery) {
        fetchSuggestions();
    } else {
      setSuggestions({ songs: [], artists: [], albums: [] });
      setIsDropdownOpen(false);
    }

    return () => {
      ignore = true;
    };
  }, [debouncedQuery]);

  const handleDeleteHistory = async (e: React.MouseEvent, historyId: string) => {
    e.stopPropagation();
    try {
      await deleteSearchHistoryItem(historyId);
      setRecentlyPlayed(prev => prev.filter(item => item.historyId !== historyId));
    } catch (error) {
      console.error("Failed to delete history item:", error);
    }
  };

  const handleSuggestionClick = async (suggestion: any) => {
    setIsDropdownOpen(false);
    if (suggestion.type === 'artist') {
      const artistId = suggestion.id.startsWith('vip_') ? suggestion.name : suggestion.id;
      navigate(`/artist/${artistId}`);
    } else {
      setQuery(suggestion.name || suggestion.title);
      playContext(suggestion, suggestions.songs);
    }
  };

  const handleKeyDown = async (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' && query.trim().length > 0) {
      // CRITICAL: Close dropdown and clear suggestions immediately
      setIsDropdownOpen(false);
      setSuggestions({ songs: [], artists: [], albums: [] });
      
      setIsSearching(true);
      try {
        const data = await searchTracks(query);
        setResults(data.songs);
      } catch (error) {
        console.error("Full search failed:", error);
      } finally {
        setIsSearching(false);
      }
    }
  };

  return (
    <div className="flex flex-col gap-6 pb-24 max-w-7xl mx-auto px-4 sm:px-6">
      <div ref={searchContainerRef} className="relative max-w-2xl group mx-auto w-full">
        <div className="absolute inset-y-0 left-4 flex items-center pointer-events-none z-10">
          <SearchIcon className="h-5 w-5 text-neutral-400 group-focus-within:text-white transition-colors" />
        </div>
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={handleKeyDown}
          onFocus={() => query.trim().length > 0 && setIsDropdownOpen(true)}
          placeholder="What do you want to listen to?"
          className="w-full bg-[#242424] text-white rounded-full py-4 pl-12 pr-4 focus:outline-none focus:ring-2 focus:ring-white/10 transition-all font-medium placeholder-neutral-500 shadow-2xl border border-white/5 active:bg-[#2a2a2a]"
        />

        {/* Suggestions Dropdown (Desktop Style) */}
        {isDropdownOpen && (suggestions.songs.length > 0 || (suggestions.artists && suggestions.artists.length > 0)) && (
          <div className="absolute top-full left-0 mt-3 w-full bg-[#181818] rounded-2xl shadow-2xl z-[100] overflow-hidden border border-[#333] animate-in fade-in zoom-in-95 duration-200 backdrop-blur-xl">
            {/* Artists Section */}
            {suggestions.artists && suggestions.artists.length > 0 && (
              <div className="p-2">
                <h3 className="text-[11px] uppercase font-black text-neutral-500 px-4 py-3 tracking-[0.1em]">Best Matches: Artists</h3>
                {suggestions.artists.slice(0, 2).map((artist: any) => (
                  <div 
                    key={artist.id} 
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
                      <p className="text-neutral-500 text-[10px] font-bold uppercase tracking-widest mt-0.5">Verified Artist</p>
                    </div>
                    <ChevronRight size={16} className="text-neutral-600 group-hover/item:text-white transition-colors mr-2" />
                  </div>
                ))}
              </div>
            )}

            {/* Songs Section */}
            {suggestions.songs && suggestions.songs.length > 0 && (
              <div className="p-2 border-t border-white/5 bg-neutral-900/40">
                <h3 className="text-[11px] uppercase font-black text-neutral-500 px-4 py-3 tracking-[0.1em]">Popular Tracks</h3>
                {suggestions.songs.slice(0, 5).map((song: any) => (
                  <div 
                    key={song.id} 
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

      <div className="mt-4">
        {isSearching ? (
          <div className="flex items-center gap-3 text-neutral-400 mt-8">
             <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-white"></div>
             <span>Searching database...</span>
          </div>
        ) : results.length > 0 ? (
          <div className="flex flex-col gap-10">
            {/* Songs Section */}
            <section>
              <div className="flex items-center justify-between mb-6">
                 <h2 className="text-2xl font-black">Songs</h2>
                 <button onClick={() => setResults([])} className="text-sm text-neutral-500 hover:text-white transition-colors">Clear Results</button>
              </div>
              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-6">
                {results.map(song => (
                  <SongCard key={song.id} song={song} context={results} onPlay={(s) => saveSearchClick(s)} />
                ))}
              </div>
            </section>
          </div>
        ) : query.length > 0 && !isSearching ? (
          <div className="flex flex-col items-center justify-center py-20 text-neutral-500">
             <SearchIcon size={48} className="mb-4 opacity-10" />
             <p className="text-xl font-medium">No results found for "{query}"</p>
             <p className="mt-2 text-sm">Check your spelling or try search for something else</p>
          </div>
        ) : recentlyPlayed.length > 0 ? (
          <div className="animate-in fade-in duration-700 slide-in-from-bottom-4">
            <div className="flex items-center gap-2 mb-6 text-neutral-400">
              <Clock size={20} className="text-green-500" />
              <h2 className="text-xl font-bold text-white">Your Search History</h2>
            </div>
            <div className="flex flex-col gap-1 max-w-xl bg-neutral-900/40 rounded-2xl p-2 border border-white/5 shadow-inner">
              {recentlyPlayed.map((song: Song & { historyId: string }) => (
                <div 
                  key={song.historyId}
                  onClick={() => playContext(song, recentlyPlayed)}
                  className="flex items-center justify-between p-2 rounded-xl hover:bg-neutral-800/80 cursor-pointer group transition-all duration-300 border border-transparent hover:border-white/5 active:scale-95 translate-y-0 hover:-translate-y-0.5"
                >
                  <div className="flex items-center gap-4 text-neutral-300 truncate">
                     <div className="relative w-12 h-12 flex-shrink-0 group-hover:rotate-3 transition-transform duration-300">
                        <img 
                            src={song.coverUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=50&h=50&fit=crop'} 
                            className="w-full h-full rounded-lg object-cover shadow-2xl" 
                            alt="" 
                            loading="lazy"
                        />
                        <div className="absolute inset-0 bg-black/40 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity rounded-lg">
                           <Play size={16} fill="white" className="text-white ml-0.5" />
                        </div>
                     </div>
                     <div className="truncate flex flex-col pt-0.5">
                        <p className="font-bold text-white truncate text-[15px] group-hover:text-green-400 transition-colors">{song.title}</p>
                        <p className="text-sm text-neutral-400 truncate group-hover:text-neutral-200 transition-colors uppercase tracking-tight text-[11px] font-bold">{song.artist}</p>
                     </div>
                  </div>
                  <button 
                    onClick={(e) => handleDeleteHistory(e, song.historyId)}
                    className="p-2 text-neutral-600 opacity-0 group-hover:opacity-100 hover:text-red-400 transition-all transform hover:scale-125 hover:bg-red-500/10 rounded-full"
                    title="Remove from history"
                  >
                    <X size={16} />
                  </button>
                </div>
              ))}
            </div>
          </div>
        ) : (
          <div className="flex flex-wrap gap-6 mt-4">
             <div className="bg-gradient-to-br from-[#E8115B] to-[#BC13FE] h-48 w-full xl:w-72 rounded-2xl p-6 shadow-2xl flex flex-col justify-between cursor-pointer hover:scale-[1.04] active:scale-95 transition-all group overflow-hidden relative">
                <span className="font-black text-3xl z-10">Podcasts</span>
                <div className="absolute bottom-0 right-0 rotate-[25deg] translate-x-4 translate-y-2 group-hover:scale-110 transition-transform duration-500">
                    <Album size={120} className="text-black/20" />
                </div>
             </div>
             <div className="bg-gradient-to-br from-[#1E3264] to-[#3371E4] h-48 w-full xl:w-72 rounded-2xl p-6 shadow-2xl flex flex-col justify-between cursor-pointer hover:scale-[1.04] active:scale-95 transition-all group overflow-hidden relative">
                <span className="font-black text-3xl z-10">Live Events</span>
                <div className="absolute bottom-0 right-0 rotate-[25deg] translate-x-4 translate-y-2 group-hover:scale-110 transition-transform duration-500">
                    <Music size={120} className="text-black/20" />
                </div>
             </div>
             <div className="bg-gradient-to-br from-[#608108] to-[#92cc0b] h-48 w-full xl:w-72 rounded-2xl p-6 shadow-2xl flex flex-col justify-between cursor-pointer hover:scale-[1.04] active:scale-95 transition-all group overflow-hidden relative">
                <span className="font-black text-3xl z-10">Made For You</span>
                <div className="absolute bottom-0 right-0 rotate-[25deg] translate-x-4 translate-y-2 group-hover:scale-110 transition-transform duration-500">
                    <SearchIcon size={120} className="text-black/20" />
                </div>
             </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default Search;
