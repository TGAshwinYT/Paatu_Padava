import React, { useState, useEffect, useRef } from 'react';
import { Search as SearchIcon, X, ArrowLeft, Clock, Music, Play, ChevronRight, MoreVertical } from 'lucide-react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { useAudio } from '../../context/AudioContext';
import { useAuth } from '../../context/AuthContext';
import type { Song } from '../../types';
import useDebounce from '../../hooks/useDebounce';
import { getRecentSearches, searchTracks, getSuggestions, deleteSearchHistoryItem, saveSearchClick } from '../../services/api';

const CATEGORIES = [
  { id: 'music', title: 'Music', color: 'bg-pink-600', query: 'Latest hits' },
  { id: 'podcasts', title: 'Podcasts', color: 'bg-emerald-700', query: 'Tamil Podcasts' },
  { id: 'live', title: 'Live Events', color: 'bg-purple-700', query: 'Concert' },
  { id: 'made_for_you', title: 'Made For You', color: 'bg-indigo-600', query: 'Recommended' },
  { id: 'new_releases', title: 'New Releases', color: 'bg-lime-700', query: 'New' },
  { id: 'hindi', title: 'Hindi', color: 'bg-rose-600', query: 'Hindi' },
  { id: 'tamil', title: 'Tamil', color: 'bg-orange-600', query: 'Tamil' },
  { id: 'punjabi', title: 'Punjabi', color: 'bg-fuchsia-700', query: 'Punjabi' },
  { id: 'charts', title: 'Charts', color: 'bg-violet-800', query: 'Top 50' },
  { id: 'podcast_charts', title: 'Podcast Charts', color: 'bg-blue-600', query: 'Top Podcasts' }
];

const MobileSearch: React.FC = () => {
  const { user } = useAuth();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Song[]>([]);
  const [topResult, setTopResult] = useState<any>(null);
  const [suggestions, setSuggestions] = useState<any>({ songs: [], artists: [], albums: [] });
  const [activeFilter, setActiveFilter] = useState<'all' | 'songs' | 'albums' | 'artists'>('all');
  const [isSearching, setIsSearching] = useState(false);
  const [isOverlayOpen, setIsOverlayOpen] = useState(false);
  const [recentlyPlayed, setRecentlyPlayed] = useState<(Song & { historyId: string })[]>([]);
  
  const { playFromSearch, currentTrack } = useAudio();
  const inputRef = useRef<HTMLInputElement>(null);
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const initialQuery = searchParams.get('q');

  // Debounce the search query with 500ms delay
  const debouncedQuery = useDebounce(query, 500);

  // Fetch history on mount
  useEffect(() => {
    const fetchRecent = async () => {
      if (!user) return;
      try {
        const history = await getRecentSearches();
        setRecentlyPlayed(history);
      } catch (error) {
        console.error("Failed to fetch search history:", error);
      }
    };
    fetchRecent();
  }, [user]);

  // Handle initial query from URL (Handoff from Home)
  useEffect(() => {
    if (initialQuery && initialQuery !== query) {
      setQuery(initialQuery);
      setIsOverlayOpen(true);
      
      const performInitialSearch = () => performSearch(initialQuery);
      
      performInitialSearch();
    }
  }, [initialQuery]);

  // Use the debounced query for suggestions
  useEffect(() => {
    let ignore = false;

    const fetchSuggestions = async () => {
      if (debouncedQuery.trim().length > 0) {
        setIsSearching(true);
        try {
          const suggestData = await getSuggestions(debouncedQuery);
          if (!ignore) {
            setSuggestions(suggestData);
          }
        } catch (error) {
          console.error("Mobile suggestions failed:", error);
        } finally {
          if (!ignore) setIsSearching(false);
        }
      } else {
        setSuggestions({ songs: [], artists: [], albums: [] });
      }
    };

    fetchSuggestions();

    return () => {
      ignore = true;
    };
  }, [debouncedQuery]);

  const performSearch = async (searchTerm: string) => {
    if (!searchTerm.trim()) return;
    setSuggestions({ songs: [], artists: [], albums: [] });
    setIsSearching(true);
    try {
      const data = await searchTracks(searchTerm);
      setTopResult(data.global_matches?.top_result || null);
      setResults(data.global_matches?.songs || []);
    } catch (error) {
      console.error("Search failed:", error);
    } finally {
      setIsSearching(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      performSearch(query);
    }
  };

  // Handle auto-focus when overlay opens
  useEffect(() => {
    if (isOverlayOpen && inputRef.current) {
      setTimeout(() => inputRef.current?.focus(), 100);
    }
  }, [isOverlayOpen]);

  const handleDeleteHistory = async (e: React.MouseEvent, historyId: string) => {
    e.stopPropagation();
    await deleteSearchHistoryItem(historyId);
    setRecentlyPlayed((prev: any[]) => prev.filter((item: any) => item.historyId !== historyId));
  };

  const handleSongSelect = (song: Song) => {
    saveSearchClick(song);
    playFromSearch(song);
    setIsOverlayOpen(false);
    setQuery('');
    setSuggestions({ songs: [], artists: [], albums: [] });
    // Refresh history only if logged in
    if (user) {
      getRecentSearches().then(setRecentlyPlayed);
    }
  };

  const handleArtistSelect = (artist: any) => {
    setIsOverlayOpen(false);
    setQuery('');
    setSuggestions({ songs: [], artists: [], albums: [] });
    const artistId = artist.id.startsWith('vip_') ? artist.name : artist.id;
    navigate(`/artist/${artistId}`);
  };

  // Merge results and suggestions for a complete list
  const getMergedList = (primary: any[], secondary: any[]) => {
     const seen = new Set();
     if (topResult?.id) seen.add(topResult.id);
     
     const merged = [...(primary || []), ...(secondary || [])].filter(item => {
        if (!item?.id || seen.has(item.id)) return false;
        seen.add(item.id);
        return true;
     });
     return merged;
  };

  const displaySongs = getMergedList(results, suggestions.songs);
  const displayArtists = getMergedList([], suggestions.artists); // results usually contains songs

  return (
    <div className="min-h-screen bg-black text-white pb-32 animate-in fade-in duration-500">
      {/* Header Area */}
      <div className="px-6 pt-12 pb-6">
        <h1 className="text-4xl font-black mb-8 tracking-tight">Search</h1>
        
        {/* Fake Search Bar (pinned trigger) */}
        <div 
          onClick={() => setIsOverlayOpen(true)}
          className="sticky top-4 z-40 flex items-center gap-4 bg-white text-black py-3.5 px-5 rounded-lg shadow-xl cursor-text active:scale-[0.98] transition-transform"
        >
          <SearchIcon size={24} strokeWidth={2.5} />
          <span className="font-bold text-lg">What do you want to listen to?</span>
        </div>
      </div>

      {/* Main Content (History & Browse) */}
      <div className="px-6 space-y-10">
        {recentlyPlayed.length > 0 && (
          <section>
            <div className="flex items-center gap-2 mb-6">
               <Clock size={20} className="text-neutral-400" />
               <h2 className="text-xl font-bold">Recently Played</h2>
            </div>
            <div className="flex flex-col gap-4">
              {recentlyPlayed.map((song: any) => (
                <div 
                  key={song.historyId} 
                  onClick={() => playFromSearch(song)}
                  className={`flex items-center gap-4 group rounded-xl p-2 transition-colors ${
                    currentTrack?.id === song.id ? 'bg-neutral-800/80' : 'active:bg-neutral-900'
                  }`}
                >
                  <div className="relative w-14 h-14 flex-shrink-0">
                    <img 
                      src={song.coverUrl || (song as any).cover_url || (song as any).image || (song as any).thumbnail || '/logo.png'} 
                      className="w-full h-full rounded-lg object-cover shadow-lg" 
                      alt="" 
                      onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                    />
                    <div className="absolute inset-0 bg-black/20 flex items-center justify-center rounded-lg opacity-0 group-active:opacity-100 transition-opacity">
                       <Play size={20} fill="white" className="ml-1" />
                    </div>
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className={`font-bold truncate text-[15px] ${currentTrack?.id === song.id ? 'text-green-500' : 'text-white'}`}>
                      {song.title}
                    </p>
                    <p className="text-sm text-neutral-400 truncate">{song.artist}</p>
                  </div>
                  <button onClick={(e) => handleDeleteHistory(e, song.historyId)} className="p-2 text-neutral-500">
                     <X size={18} />
                  </button>
                </div>
              ))}
            </div>
          </section>
        )}

        {/* Categories / Browse Section */}
        <section className="pb-8">
          <h2 className="text-xl font-bold mb-6">Browse all</h2>
          <div className="grid grid-cols-2 gap-4">
            {CATEGORIES.map((cat) => (
              <div 
                key={cat.id}
                onClick={() => {
                   setQuery(cat.query);
                   setIsOverlayOpen(true);
                   performSearch(cat.query);
                }}
                className={`${cat.color} h-28 rounded-xl p-4 relative overflow-hidden active:scale-95 transition-transform shadow-lg cursor-pointer group`}
              >
                <span className="font-extrabold text-lg relative z-10">{cat.title}</span>
                <div className="absolute -bottom-2 -right-4 w-20 h-20 bg-black/20 rounded-lg rotate-25 group-hover:rotate-15 transition-transform origin-bottom-right" />
                <Music size={60} className="absolute -bottom-2 -right-4 rotate-25 opacity-20 text-white" />
              </div>
            ))}
          </div>
        </section>
      </div>

      {/* Full Screen Search Overlay */}
      {isOverlayOpen && (
        <div className="fixed inset-0 z-[100] bg-neutral-900 flex flex-col animate-in slide-in-from-bottom duration-300">
          {/* Top Search Bar & Filters */}
          <div className="flex flex-col gap-4 p-4 pt-8 bg-neutral-900/95 backdrop-blur-xl border-b border-white/5 sticky top-0 z-50">
            <div className="flex items-center gap-2">
               <button 
                 onClick={() => setIsOverlayOpen(false)}
                 className="p-2 text-white active:scale-95 transition-transform"
               >
                 <ArrowLeft size={28} />
               </button>
               <div className="flex-1 relative">
                 <input
                   ref={inputRef}
                   type="text"
                   value={query}
                   onChange={(e) => setQuery(e.target.value)}
                   onKeyDown={handleKeyDown}
                   placeholder="What do you want to listen to?"
                   className="w-full bg-neutral-800 text-white py-3 pl-4 pr-11 rounded-lg font-bold placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-white/10 transition-all text-lg"
                 />
                 {query && (
                   <button 
                     onClick={() => { setQuery(''); setResults([]); setTopResult(null); }}
                     className="absolute right-3 top-1/2 -translate-y-1/2 p-1 bg-neutral-700 rounded-full"
                   >
                     <X size={16} />
                   </button>
                 )}
               </div>
            </div>

            {/* Filter Chips */}
            <div className="flex gap-2 overflow-x-auto pb-1 hide-scrollbar -mx-4 px-4">
              {['all', 'songs', 'artists', 'albums'].map((f) => (
                <button
                  key={f}
                  onClick={() => setActiveFilter(f as any)}
                  className={`px-5 py-1.5 rounded-full text-sm font-bold capitalize transition-colors whitespace-nowrap ${
                    activeFilter === f ? 'bg-green-500 text-black' : 'bg-neutral-800 text-white border border-white/5'
                  }`}
                >
                  {f === 'all' ? 'All' : f}
                </button>
              ))}
            </div>
          </div>

          {/* Results Area */}
          <div className="flex-1 overflow-y-auto p-4 pb-32">
            {isSearching ? (
              <div className="flex flex-col items-center justify-center py-20 gap-4 text-neutral-400">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white"></div>
                <p className="font-medium">Searching for "{query}"...</p>
              </div>
            ) : query.length > 0 ? (
              <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500">
                {/* Top Result Card (Stage 3) */}
                {topResult && activeFilter === 'all' && (
                  <section>
                    <h3 className="text-xl font-black mb-4 px-2">Top result</h3>
                    <div 
                      onClick={() => topResult.type === 'artist' ? handleArtistSelect(topResult) : handleSongSelect(topResult)}
                      className="bg-[#181818] p-5 rounded-2xl flex flex-col gap-5 border border-white/5 active:scale-[0.98] transition-all relative group"
                    >
                      <div className="relative w-32 h-32">
                        <img 
                          src={topResult.image?.[0]?.url || topResult.coverUrl || topResult.image || '/logo.png'} 
                          className={`w-full h-full object-cover shadow-2xl ${topResult.type === 'artist' ? 'rounded-full' : 'rounded-lg'}`}
                          alt="" 
                          onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                        />
                        {topResult.type === 'song' && (
                          <div className="absolute inset-0 flex items-center justify-center">
                            <div className="w-12 h-12 bg-green-500 rounded-full flex items-center justify-center shadow-2xl scale-100 group-active:scale-90 transition-transform">
                              <Play size={24} fill="black" className="text-black ml-1" />
                            </div>
                          </div>
                        )}
                      </div>
                      <div className="flex flex-col gap-1">
                        <h4 className="text-2xl font-black truncate max-w-[280px] leading-tight">{topResult.name || topResult.title}</h4>
                        <div className="flex items-center gap-2.5">
                           <span className="text-sm font-bold text-neutral-400 truncate max-w-[200px]">{topResult.type === 'artist' ? 'Verified Artist' : topResult.artist}</span>
                           <span className="text-[10px] font-black uppercase tracking-widest bg-black/40 px-2.5 py-1 rounded-full text-neutral-300">
                             {topResult.type || 'result'}
                           </span>
                        </div>
                      </div>
                    </div>
                  </section>
                )}

                {/* Featuring Artist Carousel (Stage 3) */}
                {topResult?.type === 'artist' && activeFilter === 'all' && (
                  <section className="-mx-4">
                    <h3 className="text-xl font-black mb-4 px-4">Featuring {topResult.name || topResult.title}</h3>
                    <div className="flex overflow-x-auto gap-4 px-4 pb-2 hide-scrollbar">
                      {[
                        { id: 'radio', title: `${topResult.name || topResult.title} Radio`, color: 'bg-neutral-800' },
                        { id: 'mix', title: `${topResult.name || topResult.title} Mix`, color: 'bg-neutral-800' },
                        { id: 'hits', title: `${topResult.name || topResult.title} Hits`, color: 'bg-neutral-800' },
                        { id: 'essential', title: 'Essentials', color: 'bg-neutral-800' }
                      ].map((item) => (
                        <div 
                          key={item.id}
                          className="flex-shrink-0 w-36 group cursor-pointer"
                          onClick={() => {
                             const q = `${topResult.name || topResult.title} ${item.id}`;
                             setQuery(q);
                             performSearch(q);
                          }}
                        >
                          <div className={`aspect-square ${item.color} rounded-xl mb-3 shadow-lg overflow-hidden relative active:scale-95 transition-transform`}>
                            <img 
                              src={topResult.image?.[0]?.url || topResult.coverUrl || topResult.image || '/logo.png'} 
                              className="w-full h-full object-cover opacity-60 group-hover:opacity-100 transition-opacity"
                              alt="" 
                            />
                            <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent flex items-end p-3">
                               <p className="text-xs font-black uppercase tracking-widest">{item.id}</p>
                            </div>
                          </div>
                          <p className="text-sm font-bold truncate px-1">{item.title}</p>
                        </div>
                      ))}
                    </div>
                  </section>
                )}

                {/* Merged Results Section: Artists */}
                {(activeFilter === 'all' || activeFilter === 'artists') && displayArtists.length > 0 && (
                   <section>
                      <h3 className="text-[11px] font-black text-neutral-500 uppercase tracking-widest px-2 mb-4">ARTISTS</h3>
                      <div className="flex flex-col gap-4">
                        {displayArtists.slice(0, 3).map((a: any) => (
                           <div 
                              key={a.id} 
                              onClick={() => handleArtistSelect(a)}
                              className="flex items-center gap-4 px-2 py-1 rounded-xl active:bg-neutral-800/50 transition-colors cursor-pointer"
                           >
                              <img 
                                src={a.image?.[0]?.url || a.image || '/logo.png'} 
                                className="w-14 h-14 rounded-full object-cover shadow-md" 
                                alt="" 
                                onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                              />
                              <div className="flex-1 min-w-0">
                                 <p className="font-bold text-[15px] truncate">{a.title || a.name || a.artist}</p>
                                 <p className="text-xs text-neutral-400 truncate font-bold">Artist</p>
                              </div>
                              <ChevronRight size={18} className="text-neutral-600 mr-2" />
                           </div>
                        ))}
                      </div>
                   </section>
                )}

                {/* Merged Results Section: Songs */}
                {(activeFilter === 'all' || activeFilter === 'songs') && displaySongs.length > 0 && (
                   <section>
                      <h3 className="text-[11px] font-black text-neutral-500 uppercase tracking-widest px-2 mb-4">SONGS</h3>
                      <div className="flex flex-col gap-3">
                         {displaySongs.slice(0, 12).map((s: any) => (
                            <div 
                               key={s.id} 
                               onClick={() => handleSongSelect(s)}
                               className="flex items-center gap-4 px-2 py-1.5 rounded-xl active:bg-neutral-800/50 transition-colors cursor-pointer group"
                            >
                               <img 
                                 src={s.coverUrl || '/logo.png'} 
                                 className="w-14 h-14 rounded object-cover shadow-sm" 
                                 alt="" 
                                 onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                               />
                               <div className="flex-1 min-w-0">
                                  <p className="font-bold text-[15px] truncate group-active:text-green-500 transition-colors">{s.title}</p>
                                  <p className="text-xs text-neutral-400 truncate font-medium">Song • {s.artist}</p>
                               </div>
                               <button className="p-2 text-neutral-500 hover:text-white transition-colors">
                                 <MoreVertical size={18} />
                               </button>
                            </div>
                         ))}
                      </div>
                   </section>
                )}
                
                {displaySongs.length === 0 && displayArtists.length === 0 && !isSearching && !topResult && (
                   <div className="flex flex-col items-center justify-center py-20 text-neutral-500">
                      <Music size={40} className="mb-4 opacity-30" />
                      <p className="font-medium text-center px-10">No matches found for "{query}"</p>
                      <p className="text-xs mt-2">Try a different song or artist</p>
                   </div>
                )}
              </div>
            ) : (
              <div className="flex flex-col items-center justify-center py-32 text-neutral-500">
                <SearchIcon size={56} className="mb-6 opacity-20" />
                <p className="font-bold text-xl">Search Paaatu_Padava</p>
                <p className="text-sm mt-2 max-w-[240px] text-center px-4">Find your favorite music, albums, and artists in one place.</p>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default MobileSearch;
