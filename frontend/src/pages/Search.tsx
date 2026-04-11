import React, { useState, useEffect, useRef } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { Search as SearchIcon, Music, Album, Clock, X, Play, ChevronRight, PlusCircle, MoreHorizontal, Heart, ListMusic, User } from 'lucide-react';
import type { Song } from '../types';
import { searchTracks, getSuggestions, getRecentSearches, deleteSearchHistoryItem, saveSearchClick, likeSong } from '../services/api';
import { useAudio } from '../context/AudioContext';
import { useAuth } from '../context/AuthContext';
import { usePlaylistModal } from '../context/PlaylistModalContext';
import useDebounce from '../hooks/useDebounce';
import { getValidImage } from '../utils/imageUtils';

const Search = () => {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<any>(null);
  const [suggestions, setSuggestions] = useState<any>({ songs: [], artists: [], albums: [] });
  const [isSearching, setIsSearching] = useState(false);
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const [recentlyPlayed, setRecentlyPlayed] = useState<(Song & { historyId: string })[]>([]);
  const searchContainerRef = useRef<HTMLDivElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const [activeMenuId, setActiveMenuId] = useState<string | null>(null);
  
  const { playFromSearch, addToQueue } = useAudio();
  const { user } = useAuth();
  const { openModal } = usePlaylistModal();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  
  const formatTime = (seconds: number) => {
    if (!seconds) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  const handleToggleLike = async (e: React.MouseEvent, song: Song) => {
    e.stopPropagation();
    if (!user) {
      navigate('/login');
      return;
    }
    // Simple API trigger for now as per plan
    await likeSong(song);
  };

  const handleOpenMenu = (e: React.MouseEvent, songId: string) => {
    e.stopPropagation();
    setActiveMenuId(activeMenuId === songId ? null : songId);
  };
  const initialQuery = searchParams.get('q');
  
  // Click outside listener for context menu
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
        if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
            setActiveMenuId(null);
        }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);
  
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
          setResults(data);
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
      playFromSearch(suggestion);
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
        setResults(data);
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
                        loading="lazy"
                        onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
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
                      <img src={song.image?.[song.image.length-1]?.url || song.coverUrl || 'https://via.placeholder.com/40'} className="w-full h-full rounded shadow-md object-cover" alt="" loading="lazy" onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }} />
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
        ) : results?.global_matches && (results.global_matches?.songs?.length > 0 || results.global_matches?.artists?.length > 0 || results.global_matches?.albums?.length > 0) ? (
          <div className="flex flex-col gap-10">
            <div className="flex items-center justify-between">
              <h2 className="text-2xl font-black">Search Results</h2>
              <button onClick={() => setResults(null)} className="text-sm text-neutral-500 hover:text-white transition-colors">Clear Results</button>
            </div>

            {/* Global Search Results */}
            
            {/* Task 1: Top Section */}
            <section className="grid grid-cols-1 md:grid-cols-[1fr_2fr] gap-6">
              {/* Left Column: Top Result */}
              {results?.global_matches?.top_result && (
                <div className="flex flex-col gap-4">
                  <h3 className="text-xl font-bold">Top result</h3>
                  <div 
                    className="bg-[#181818] hover:bg-neutral-800/80 p-6 rounded-2xl transition-all duration-500 cursor-pointer flex flex-col gap-5 shadow-lg hover:shadow-2xl hover:shadow-black/60 group relative overflow-hidden"
                    onClick={() => {
                        if (results.global_matches.top_result.type === 'artist') {
                            navigate(`/artist/${results.global_matches.top_result.id}`);
                        } else {
                            playFromSearch(results.global_matches.top_result);
                            saveSearchClick(results.global_matches.top_result);
                        }
                    }}
                  >
                    <div className="relative w-fit">
                      <img 
                        src={getValidImage(results.global_matches.top_result)} 
                        alt={results.global_matches.top_result?.name || results.global_matches.top_result?.title}
                        className={`w-36 h-36 object-cover shadow-2xl group-hover:scale-105 transition-transform duration-500 ${results.global_matches.top_result.type === 'artist' ? 'rounded-full' : 'rounded-xl border border-white/5'}`}
                        loading="lazy"
                        onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                      />
                    </div>
                    <div>
                      <h4 className="text-4xl font-black text-white truncate max-w-[280px] tracking-tight">{results.global_matches.top_result?.name || results.global_matches.top_result?.title}</h4>
                      <div className="flex items-center gap-3 mt-3">
                        {results.global_matches.top_result.type === 'song' && (
                          <span className="text-neutral-400 text-sm font-semibold hover:text-white transition-colors">{results.global_matches.top_result?.artist}</span>
                        )}
                        <span className="text-[11px] font-black uppercase tracking-[0.15em] bg-black/40 px-3.5 py-1.5 rounded-full text-neutral-300 w-fit backdrop-blur-md">
                          {results.global_matches.top_result.type}
                        </span>
                      </div>
                    </div>
                    {results.global_matches.top_result.type === 'song' && (
                        <div className="absolute bottom-6 right-6 w-14 h-14 bg-green-500 rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 translate-y-4 group-hover:translate-y-0 transition-all duration-300 shadow-2xl shadow-green-500/40 hover:scale-110 hover:bg-green-400">
                            <Play size={24} fill="black" className="text-black ml-1" />
                        </div>
                    )}
                  </div>
                </div>
              )}

              {/* Right Column: Songs */}
              {results?.global_matches?.songs && results?.global_matches?.songs?.length > 0 && (
                <div className="flex flex-col gap-4">
                  <h3 className="text-xl font-bold">Songs</h3>
                  <div className="flex flex-col gap-1">
                    {results.global_matches.songs.map((song: any) => (
                      <div 
                        key={song.id}
                        className="group flex items-center justify-between hover:bg-[#2a2a2a] rounded-md p-2 cursor-pointer transition relative"
                        onClick={() => {
                            playFromSearch(song);
                            saveSearchClick(song);
                        }}
                      >
                        <div className="flex items-center flex-1 min-w-0">
                          <div className="relative w-10 h-10 mr-4 shrink-0 overflow-hidden rounded shadow-md group-hover:shadow-lg transition-all">
                            <img 
                              src={getValidImage(song)} 
                              className="w-full h-full object-cover" 
                              alt={song.title} 
                              loading="lazy"
                              onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                            />
                            <div className="absolute inset-0 bg-black/50 hidden group-hover:flex items-center justify-center rounded transition-opacity duration-300">
                              <Play size={16} fill="white" className="text-white ml-0.5" />
                            </div>
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className="text-sm font-bold text-white truncate">{song.title}</p>
                            <p className="text-[13px] font-medium text-neutral-400 truncate">{song.artist}</p>
                          </div>
                        </div>

                        <div className="flex items-center gap-4 text-neutral-400 pr-2">
                           <button 
                             onClick={(e) => handleToggleLike(e, song)} 
                             className="hidden group-hover:block hover:text-white transition transform hover:scale-110"
                           >
                             <PlusCircle size={18} />
                           </button>
                           
                           <span className="text-xs font-medium w-10 text-right group-hover:hidden">{formatTime(song.duration)}</span>
                           
                           <button 
                             onClick={(e) => handleOpenMenu(e, song.id)} 
                             className="hidden group-hover:block hover:text-white transition transform hover:scale-110"
                           >
                             <MoreHorizontal size={18} />
                           </button>

                           {/* Context Menu Dropdown */}
                           {activeMenuId === song.id && (
                             <div 
                               ref={menuRef} 
                               className="absolute right-8 top-10 w-56 bg-[#282828] text-[#eaeaea] text-sm rounded shadow-2xl z-[100] py-1 border border-[#3e3e3e] animate-in fade-in zoom-in-95 duration-100"
                               onClick={(e) => e.stopPropagation()}
                             >
                               <button 
                                 onClick={(e) => { e.stopPropagation(); openModal(song); setActiveMenuId(null); }} 
                                 className="w-full text-left px-4 py-3 hover:bg-[#3e3e3e] flex items-center gap-3 transition-colors"
                               >
                                 <PlusCircle size={16} className="text-neutral-400" /> Add to playlist
                               </button>
                               <button 
                                 onClick={(e) => { handleToggleLike(e, song); setActiveMenuId(null); }} 
                                 className="w-full text-left px-4 py-3 hover:bg-[#3e3e3e] flex items-center gap-3 transition-colors"
                               >
                                 <Heart size={16} className="text-neutral-400" /> Save to Liked Songs
                               </button>
                               <button 
                                 onClick={(e) => { e.stopPropagation(); addToQueue(song); setActiveMenuId(null); }} 
                                 className="w-full text-left px-4 py-3 hover:bg-[#3e3e3e] flex items-center gap-3 transition-colors"
                               >
                                 <ListMusic size={16} className="text-neutral-400" /> Add to queue
                               </button>
                               <hr className="border-[#3e3e3e] my-1" />
                               <button 
                                 onClick={(e) => { e.stopPropagation(); navigate(`/artist/${song.artist_id || song.id}`); setActiveMenuId(null); }} 
                                 className="w-full text-left px-4 py-3 hover:bg-[#3e3e3e] flex items-center gap-3 transition-colors"
                               >
                                 <User size={16} className="text-neutral-400" /> Go to artist
                               </button>
                               <button 
                                 onClick={(e) => { e.stopPropagation(); navigate(`/album/${song.album_id || song.id}`); setActiveMenuId(null); }} 
                                 className="w-full text-left px-4 py-3 hover:bg-[#3e3e3e] flex items-center gap-3 transition-colors"
                               >
                                 <Music size={16} className="text-neutral-400" /> Go to album
                               </button>
                             </div>
                           )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </section>

            {/* Task 2: Artists Grid */}
            {results?.global_matches?.artists && results?.global_matches?.artists?.length > 0 && (
              <section>
                <h2 className="text-2xl font-black mb-6">Artists</h2>
                <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-6">
                  {results.global_matches.artists
                    .filter((artist: any) => {
                      const imgUrl = getValidImage(artist);
                      return imgUrl && !imgUrl.includes('logo.png') && !imgUrl.includes('default-artist-avatar'); 
                    })
                    .slice(0, 6)
                    .map((artist: any, index: number) => (
                      <div 
                        key={`artist-${index}`}
                        className="bg-[#181818]/60 hover:bg-[#282828] p-5 rounded-2xl flex flex-col gap-4 items-center cursor-pointer transition-all duration-300 group hover:-translate-y-2 hover:shadow-2xl hover:shadow-black/50"
                        onClick={() => navigate(`/artist/${artist.id}`)}
                      >
                        <div className="relative w-full aspect-square overflow-hidden rounded-full shadow-lg group-hover:shadow-2xl transition-all duration-500 bg-neutral-800">
                          <img 
                            src={getValidImage(artist)} 
                            className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-700" 
                            alt={artist.name || artist.title}
                            loading="lazy"
                            onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                          />
                        </div>
                        <div className="w-full">
                          <p className="text-base font-bold text-white truncate px-1 text-center">{artist.name || artist.title}</p>
                          <p className="text-[13px] font-semibold text-neutral-400 mt-0.5 capitalize text-center">Artist</p>
                        </div>
                      </div>
                    ))}
                </div>
              </section>
            )}

            {/* Task 3: Albums Grid */}
            {results?.global_matches?.albums && results?.global_matches?.albums?.length > 0 && (
              <div className="mt-8">
                <h2 className="text-2xl font-bold mb-6 text-white">Albums</h2>
                <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-6">
                  {results.global_matches.albums.map((album: any, index: number) => (
                    <div 
                      key={`album-${index}`} 
                      className="bg-[#181818] hover:bg-[#282828] p-4 rounded-xl cursor-pointer transition group shadow-lg hover:shadow-2xl hover:-translate-y-1 duration-300"
                      onClick={() => navigate(`/album/${album.id}`)}
                    >
                      <img 
                        src={getValidImage(album)} 
                        alt={album.title} 
                        className="w-full aspect-square rounded-md object-cover shadow-lg mb-4 bg-gray-800 group-hover:scale-[1.02] transition-transform duration-500"
                        loading="lazy"
                        onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                      />
                      <h3 className="text-white font-semibold truncate px-1">{album.title}</h3>
                      <p className="text-gray-400 text-sm truncate px-1 mt-1">{album.music || album.artist || 'Album'}</p>
                    </div>
                  ))}
                </div>
              </div>
            )}
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
                  onClick={() => playFromSearch(song)}
                  className="flex items-center justify-between p-2 rounded-xl hover:bg-neutral-800/80 cursor-pointer group transition-all duration-300 border border-transparent hover:border-white/5 active:scale-95 translate-y-0 hover:-translate-y-0.5"
                >
                  <div className="flex items-center gap-4 text-neutral-300 truncate">
                     <div className="relative w-12 h-12 flex-shrink-0 group-hover:rotate-3 transition-transform duration-300">
                        <img 
                            src={song.coverUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=50&h=50&fit=crop'} 
                            className="w-full h-full rounded-lg object-cover shadow-2xl" 
                            alt="" 
                            loading="lazy"
                            onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
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
