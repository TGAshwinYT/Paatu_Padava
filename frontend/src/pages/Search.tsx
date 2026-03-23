import React, { useState, useEffect } from 'react';
import { Search as SearchIcon, Music, User as UserIcon, Album, Clock, X, Play } from 'lucide-react';
import SongCard from '../components/SongCard';
import type { Song } from '../types';
import { searchTracks, getSuggestions, getRecentSearches, deleteSearchHistoryItem, saveSearchClick } from '../services/api';
import { useAudio } from '../context/AudioContext';
import { useAuth } from '../context/AuthContext';

const Search = () => {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Song[]>([]);
  const [suggestions, setSuggestions] = useState<any>({ songs: [], artists: [], albums: [] });
  const [isSearching, setIsSearching] = useState(false);
  const [recentlyPlayed, setRecentlyPlayed] = useState<(Song & { historyId: string })[]>([]);
  const { playTrack } = useAudio();
  const { user } = useAuth();

  useEffect(() => {
    if (user && !query) {
      const fetchRecent = async () => {
        const history = await getRecentSearches();
        setRecentlyPlayed(history);
      };
      fetchRecent();
    }
  }, [user, query]);

  const handleDeleteHistory = async (e: React.MouseEvent, historyId: string) => {
    e.stopPropagation();
    await deleteSearchHistoryItem(historyId);
    setRecentlyPlayed(prev => prev.filter(item => item.historyId !== historyId));
  };

  useEffect(() => {
    const delayDebounceFn = setTimeout(async () => {
      if (query.trim().length > 0) {
        setIsSearching(true);
        // Fetch results directly to page
        const [data, suggestData] = await Promise.all([
          searchTracks(query),
          getSuggestions(query)
        ]);
        setResults(data);
        setSuggestions(suggestData);
        setIsSearching(false);
      } else {
        setResults([]);
        setSuggestions({ songs: [], artists: [], albums: [] });
      }
    }, 300);

    return () => clearTimeout(delayDebounceFn);
  }, [query]);

  const handleArtistClick = (artistName: string) => {
    setQuery(artistName);
  };

  return (
    <div className="flex flex-col gap-6 pb-24">
      <div className="relative max-w-xl group">
        <div className="absolute inset-y-0 left-4 flex items-center pointer-events-none z-10">
          <SearchIcon className="h-5 w-5 text-neutral-400 group-focus-within:text-white transition-colors" />
        </div>
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="What do you want to listen to?"
          className="w-full bg-neutral-800 text-white rounded-full py-4 pl-12 pr-4 focus:outline-none focus:ring-2 focus:ring-white/20 transition-all font-medium placeholder-neutral-400 shadow-lg"
        />
      </div>

      <div className="mt-4">
        {isSearching ? (
          <div className="flex items-center gap-3 text-neutral-400 mt-8">
             <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-white"></div>
             <span>Searching database...</span>
          </div>
        ) : results.length > 0 || (suggestions.artists && suggestions.artists.length > 0) ? (
          <div className="flex flex-col gap-10">
            {/* Artists Section */}
            {suggestions.artists && suggestions.artists.length > 0 && (
              <section>
                <h2 className="text-2xl font-black mb-6">Artists</h2>
                <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-6">
                  {suggestions.artists.slice(0, 6).map((a: any) => (
                    <div 
                      key={a.id} 
                      onClick={() => handleArtistClick(a.name || a.artist)}
                      className="bg-neutral-900/40 p-4 rounded-xl hover:bg-neutral-800 transition-all cursor-pointer group border border-white/5 active:scale-95 text-center"
                    >
                      <div className="aspect-square w-full mb-4 relative overflow-hidden rounded-full shadow-2xl border-2 border-white/5">
                        {a.image?.[0]?.url ? (
                          <img src={a.image[0].url} className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500" />
                        ) : (
                          <div className="w-full h-full bg-neutral-800 flex items-center justify-center">
                            <UserIcon size={40} className="text-neutral-500" />
                          </div>
                        )}
                      </div>
                      <p className="text-white font-bold truncate text-sm">{a.name || a.artist}</p>
                      <p className="text-neutral-500 text-xs mt-1 font-medium uppercase tracking-widest">Artist</p>
                    </div>
                  ))}
                </div>
              </section>
            )}

            {/* Songs Section */}
            {results.length > 0 && (
              <section>
                <div className="flex items-center justify-between mb-6">
                   <h2 className="text-2xl font-black">Songs</h2>
                   <button onClick={() => setResults([])} className="text-sm text-neutral-500 hover:text-white transition-colors">Clear</button>
                </div>
                <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-6">
                  {results.map(song => (
                    <SongCard key={song.id} song={song} onPlay={(s) => saveSearchClick(s)} />
                  ))}
                </div>
              </section>
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
                  onClick={() => playTrack(song)}
                  className="flex items-center justify-between p-2 rounded-xl hover:bg-neutral-800/80 cursor-pointer group transition-all duration-300 border border-transparent hover:border-white/5 active:scale-95 translate-y-0 hover:-translate-y-0.5"
                >
                  <div className="flex items-center gap-4 text-neutral-300 truncate">
                     <div className="relative w-12 h-12 flex-shrink-0 group-hover:rotate-3 transition-transform duration-300">
                        <img 
                            src={song.coverUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=50&h=50&fit=crop'} 
                            className="w-full h-full rounded-lg object-cover shadow-2xl" 
                            alt="" 
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
