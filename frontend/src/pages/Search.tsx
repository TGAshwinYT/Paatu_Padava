import React, { useState, useEffect } from 'react';
import { Search as SearchIcon, Music, User as UserIcon, Album, Clock, X, Play } from 'lucide-react';
import SongCard from '../components/SongCard';
import type { Song } from '../types';
import { searchTracks, getSuggestions, getListenHistory, deleteHistoryItem } from '../services/api';
import { useAudio } from '../context/AudioContext';
import { useAuth } from '../context/AuthContext';

const Search = () => {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Song[]>([]);
  const [suggestions, setSuggestions] = useState<any>({ songs: [], artists: [], albums: [] });
  const [isSearching, setIsSearching] = useState(false);
  const [showDropdown, setShowDropdown] = useState(false);
  const [recentlyPlayed, setRecentlyPlayed] = useState<(Song & { historyId: string })[]>([]);
  const { playTrack } = useAudio();
  const { user } = useAuth();

  useEffect(() => {
    if (user && !query) {
      const fetchRecent = async () => {
        const history = await getListenHistory();
        setRecentlyPlayed(history);
      };
      fetchRecent();
    }
  }, [user, query]);

  const handleDeleteHistory = async (e: React.MouseEvent, historyId: string) => {
    e.stopPropagation();
    await deleteHistoryItem(historyId);
    setRecentlyPlayed(prev => prev.filter(item => item.historyId !== historyId));
  };

  useEffect(() => {
    const delayDebounceFn = setTimeout(async () => {
      if (query.trim().length > 0) {
        setIsSearching(true);
        // Fetch full results
        const data = await searchTracks(query);
        setResults(data);
        
        // Fetch suggestions for dropdown
        const suggestData = await getSuggestions(query);
        setSuggestions(suggestData);
        
        setIsSearching(false);
      } else {
        setResults([]);
        setSuggestions({ songs: [], artists: [], albums: [] });
        setShowDropdown(false);
      }
    }, 400);

    return () => clearTimeout(delayDebounceFn);
  }, [query]);

  const handleSuggestClick = (item: any, type: 'song' | 'artist' | 'album') => {
    if (type === 'song') {
      const song: Song = {
        id: item.id,
        title: item.name || item.title,
        artist: item.primaryArtists || item.artist || "Unknown",
        coverUrl: item.image?.[item.image.length-1]?.url || item.cover_url || "",
        audioUrl: item.downloadUrl?.[item.downloadUrl.length-1]?.url || item.audio_url || ""
      };
      playTrack(song);
    } else {
        // For artists/albums, we just set the query to trigger a full search
        setQuery(item.name || item.title);
    }
    setShowDropdown(false);
  };

  return (
    <div className="flex flex-col gap-6 pb-24">
      <div className="relative max-w-xl">
        <div className="absolute inset-y-0 left-4 flex items-center pointer-events-none">
          <SearchIcon className="h-5 w-5 text-neutral-400" />
        </div>
        <input
          type="text"
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setShowDropdown(true);
          }}
          onFocus={() => query.length > 0 && setShowDropdown(true)}
          placeholder="What do you want to listen to?"
          className="w-full bg-neutral-800 text-white rounded-full py-4 pl-12 pr-4 focus:outline-none focus:ring-2 focus:ring-white/20 transition-all font-medium placeholder-neutral-400"
        />

        {/* Suggestions Dropdown */}
        {showDropdown && (query.length > 0) && (
            <div className="absolute top-full left-0 right-0 mt-2 bg-[#181818] border border-white/10 rounded-xl shadow-2xl z-[100] overflow-hidden">
                {suggestions.songs?.length > 0 && (
                    <div className="p-2">
                        <h3 className="text-[10px] uppercase font-bold text-neutral-500 px-3 py-1">Songs</h3>
                        {suggestions.songs.slice(0, 4).map((s: any) => (
                            <div 
                                key={s.id} 
                                onClick={() => handleSuggestClick(s, 'song')}
                                className="flex items-center gap-3 p-2 hover:bg-white/5 rounded-lg cursor-pointer transition-colors"
                            >
                                <img src={s.image?.[0]?.url} className="w-8 h-8 rounded" alt="" />
                                <div className="truncate">
                                    <p className="text-sm font-medium text-white truncate">{s.name}</p>
                                    <p className="text-xs text-neutral-400 truncate">{s.primaryArtists}</p>
                                </div>
                            </div>
                        ))}
                    </div>
                )}

                {suggestions.artists?.length > 0 && (
                    <div className="p-2 border-t border-white/5">
                        <h3 className="text-[10px] uppercase font-bold text-neutral-500 px-3 py-1">Artists</h3>
                        {suggestions.artists.slice(0, 3).map((a: any) => (
                            <div 
                                key={a.id} 
                                onClick={() => handleSuggestClick(a, 'artist')}
                                className="flex items-center gap-3 p-2 hover:bg-white/5 rounded-lg cursor-pointer transition-colors"
                            >
                                <div className="w-8 h-8 rounded-full bg-neutral-800 flex items-center justify-center">
                                    {a.image?.[0]?.url ? <img src={a.image[0].url} className="w-8 h-8 rounded-full object-cover" /> : <UserIcon size={14} />}
                                </div>
                                <p className="text-sm font-medium text-white truncate">{a.name}</p>
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
          <div>
            <h2 className="text-xl font-bold mb-4">Top Results</h2>
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
              {results.map(song => (
                <SongCard key={song.id} song={song} />
              ))}
            </div>
          </div>
        ) : query.length > 0 ? (
          <p className="text-neutral-400 mt-8 font-medium">No results found for "{query}"</p>
        ) : recentlyPlayed.length > 0 ? (
          <div className="animate-in fade-in duration-500">
            <div className="flex items-center gap-2 mb-6 text-neutral-400">
              <Clock size={20} />
              <h2 className="text-xl font-bold text-white">Recently Played</h2>
            </div>
            <div className="flex flex-col gap-1 max-w-xl">
              {recentlyPlayed.map((song: Song & { historyId: string }) => (
                <div 
                  key={song.historyId}
                  onClick={() => playTrack(song)}
                  className="flex items-center justify-between p-2 rounded-lg hover:bg-neutral-800/60 cursor-pointer group transition-all duration-200 border border-transparent hover:border-white/5 shadow-sm"
                >
                  <div className="flex items-center gap-4 text-neutral-300 truncate">
                     <div className="relative w-12 h-12 flex-shrink-0 group-hover:scale-105 transition-transform duration-300">
                        <img 
                            src={song.coverUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=50&h=50&fit=crop'} 
                            className="w-full h-full rounded object-cover shadow-lg" 
                            alt="" 
                        />
                        <div className="absolute inset-0 bg-black/20 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity rounded">
                           <Play size={16} fill="white" className="text-white ml-0.5" />
                        </div>
                     </div>
                     <div className="truncate flex flex-col pt-0.5">
                        <p className="font-bold text-white truncate text-[15px] group-hover:text-green-400 transition-colors">{song.title}</p>
                        <p className="text-sm text-neutral-400 truncate group-hover:text-neutral-300 transition-colors">{song.artist}</p>
                     </div>
                  </div>
                  <button 
                    onClick={(e) => handleDeleteHistory(e, song.historyId)}
                    className="p-2 text-neutral-500 opacity-0 group-hover:opacity-100 hover:text-red-400 transition-all transform hover:scale-125 hover:bg-neutral-700/50 rounded-full"
                    title="Remove from history"
                  >
                    <X size={16} />
                  </button>
                </div>
              ))}
            </div>
          </div>
        ) : (
          <div className="flex flex-wrap gap-4 mt-4">
             <div className="bg-gradient-to-br from-[#E8115B] to-[#BC13FE] h-48 w-full xl:w-72 rounded-xl p-4 shadow-lg flex flex-col justify-between cursor-pointer hover:scale-[1.02] transition-transform">
                <span className="font-extrabold text-2xl">Podcasts</span>
                <div className="self-end rotate-[25deg] translate-x-4 translate-y-2">
                    <Album size={80} className="opacity-40" />
                </div>
             </div>
             <div className="bg-gradient-to-br from-[#1E3264] to-[#3371E4] h-48 w-full xl:w-72 rounded-xl p-4 shadow-lg flex flex-col justify-between cursor-pointer hover:scale-[1.02] transition-transform">
                <span className="font-extrabold text-2xl">Live Events</span>
                <div className="self-end rotate-[25deg] translate-x-4 translate-y-2">
                    <Music size={80} className="opacity-40" />
                </div>
             </div>
             <div className="bg-gradient-to-br from-[#608108] to-[#92cc0b] h-48 w-full xl:w-72 rounded-xl p-4 shadow-lg flex flex-col justify-between cursor-pointer hover:scale-[1.02] transition-transform">
                <span className="font-extrabold text-2xl">Made For You</span>
                <div className="self-end rotate-[25deg] translate-x-4 translate-y-2">
                    <SearchIcon size={80} className="opacity-40" />
                </div>
             </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default Search;
