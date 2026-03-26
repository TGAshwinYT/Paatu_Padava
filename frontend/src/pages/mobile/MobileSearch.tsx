import React, { useState, useEffect, useRef } from 'react';
import { Search as SearchIcon, X, ArrowLeft, Clock, Music, Play, User as UserIcon } from 'lucide-react';
import { searchTracks, getSuggestions, getRecentSearches, deleteSearchHistoryItem, saveSearchClick } from '../../services/api';
import { useAudio } from '../../context/AudioContext';
import type { Song } from '../../types';

const MobileSearch: React.FC = () => {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Song[]>([]);
  const [suggestions, setSuggestions] = useState<any>({ songs: [], artists: [], albums: [] });
  const [isSearching, setIsSearching] = useState(false);
  const [isOverlayOpen, setIsOverlayOpen] = useState(false);
  const [recentlyPlayed, setRecentlyPlayed] = useState<(Song & { historyId: string })[]>([]);
  
  const { playTrack, currentTrack } = useAudio();
  const inputRef = useRef<HTMLInputElement>(null);

  // Fetch history on mount
  useEffect(() => {
    const fetchRecent = async () => {
      const history = await getRecentSearches();
      setRecentlyPlayed(history);
    };
    fetchRecent();
  }, []);

  // Debounced Search Logic
  useEffect(() => {
    const delayDebounceFn = setTimeout(async () => {
      if (query.trim().length > 0) {
        setIsSearching(true);
        const data = await searchTracks(query);
        setResults(data.songs);
        
        const suggestData = await getSuggestions(query);
        setSuggestions(suggestData);
        setIsSearching(false);
      } else {
        setResults([]);
        setSuggestions({ songs: [], artists: [], albums: [] });
      }
    }, 400);

    return () => clearTimeout(delayDebounceFn);
  }, [query]);

  // Handle auto-focus when overlay opens
  useEffect(() => {
    if (isOverlayOpen && inputRef.current) {
      setTimeout(() => inputRef.current?.focus(), 100);
    }
  }, [isOverlayOpen]);

  const handleDeleteHistory = async (e: React.MouseEvent, historyId: string) => {
    e.stopPropagation();
    await deleteSearchHistoryItem(historyId);
    setRecentlyPlayed(prev => prev.filter(item => item.historyId !== historyId));
  };

  const handleSongSelect = (song: Song) => {
    saveSearchClick(song);
    playTrack(song);
    setIsOverlayOpen(false);
    setQuery('');
    // Refresh history
    getRecentSearches().then(setRecentlyPlayed);
  };

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
              {recentlyPlayed.map((song) => (
                <div 
                  key={song.historyId} 
                  onClick={() => playTrack(song)}
                  className={`flex items-center gap-4 group rounded-xl p-2 transition-colors ${
                    currentTrack?.id === song.id ? 'bg-neutral-800/80' : 'active:bg-neutral-900'
                  }`}
                >
                  <div className="relative w-14 h-14 flex-shrink-0">
                    <img src={song.coverUrl} className="w-full h-full rounded-lg object-cover shadow-lg" alt="" />
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
        <section>
          <h2 className="text-xl font-bold mb-6">Browse all</h2>
          <div className="grid grid-cols-2 gap-4">
            <div className="bg-[#E8115B] h-28 rounded-xl p-4 relative overflow-hidden active:scale-95 transition-transform shadow-lg cursor-pointer">
              <span className="font-extrabold text-lg relative z-10">Podcasts</span>
              <Music size={60} className="absolute -bottom-2 -right-4 rotate-25 opacity-30 text-white" />
            </div>
            <div className="bg-[#1E3264] h-28 rounded-xl p-4 relative overflow-hidden active:scale-95 transition-transform shadow-lg cursor-pointer">
              <span className="font-extrabold text-lg relative z-10">Live Events</span>
              <Play size={60} className="absolute -bottom-2 -right-4 rotate-25 opacity-30 text-white" />
            </div>
            <div className="bg-[#608108] h-28 rounded-xl p-4 relative overflow-hidden active:scale-95 transition-transform shadow-lg cursor-pointer">
              <span className="font-extrabold text-lg relative z-10">New Releases</span>
              <UserIcon size={60} className="absolute -bottom-2 -right-4 rotate-25 opacity-30 text-white" />
            </div>
            <div className="bg-[#BC13FE] h-28 rounded-xl p-4 relative overflow-hidden active:scale-95 transition-transform shadow-lg cursor-pointer">
              <span className="font-extrabold text-lg relative z-10">Bollywood</span>
              <div className="absolute -bottom-2 -right-4 bg-white/20 w-16 h-16 rounded-full rotate-25 translate-x-4 translate-y-2" />
            </div>
          </div>
        </section>
      </div>

      {/* Full Screen Search Overlay */}
      {isOverlayOpen && (
        <div className="fixed inset-0 z-[100] bg-neutral-900 flex flex-col animate-in slide-in-from-bottom duration-300">
          {/* Top Search Bar */}
          <div className="flex items-center gap-2 p-4 pt-8 bg-neutral-800 shadow-md">
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
                placeholder="Search artists, songs..."
                className="w-full bg-neutral-700 text-white py-3 pl-4 pr-11 rounded-lg font-bold placeholder-neutral-400 focus:outline-none focus:ring-2 focus:ring-white/20 transition-all text-lg"
              />
              {query && (
                <button 
                  onClick={() => setQuery('')}
                  className="absolute right-3 top-1/2 -translate-y-1/2 p-1 bg-neutral-600 rounded-full"
                >
                  <X size={16} />
                </button>
              )}
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
              <div className="space-y-8 animate-in fade-in duration-300">
                {/* Suggestions Section */}
                {suggestions.songs?.length > 0 && (
                   <section>
                      <h3 className="text-sm font-bold text-neutral-500 uppercase tracking-widest px-2 mb-4">Songs</h3>
                      <div className="flex flex-col gap-2">
                        {suggestions.songs.slice(0, 5).map((s: any) => (
                           <div 
                              key={s.id} 
                              onClick={() => {
                                 const song: Song = {
                                    id: s.id,
                                    title: s.name,
                                    artist: s.primaryArtists,
                                    coverUrl: s.image?.[s.image.length-1]?.url || "",
                                    audioUrl: s.downloadUrl?.[s.downloadUrl.length-1]?.url || ""
                                 };
                                 handleSongSelect(song);
                              }}
                              className="flex items-center gap-4 p-2 rounded-xl active:bg-neutral-800 transition-colors cursor-pointer"
                           >
                              <img src={s.image?.[0]?.url} className="w-12 h-12 rounded object-cover" alt="" />
                              <div className="flex-1 min-w-0">
                                 <p className="font-bold text-[15px] truncate">{s.name}</p>
                                 <p className="text-xs text-neutral-400 truncate">{s.primaryArtists}</p>
                              </div>
                           </div>
                        ))}
                      </div>
                   </section>
                )}

                {/* Main Results */}
                {results.length > 0 && (
                   <section>
                      <h3 className="text-sm font-bold text-neutral-500 uppercase tracking-widest px-2 mb-4">Top Matches</h3>
                      <div className="grid grid-cols-2 gap-4">
                        {results.slice(0, 10).map((song) => (
                           <div 
                              key={song.id} 
                              onClick={() => handleSongSelect(song)}
                              className="bg-neutral-800 rounded-xl p-3 flex flex-col gap-3 active:scale-[0.97] transition-transform"
                           >
                              <img src={song.coverUrl} className="w-full aspect-square rounded-lg object-cover shadow-lg" alt="" />
                              <div className="min-w-0">
                                 <p className="font-bold text-sm truncate">{song.title}</p>
                                 <p className="text-xs text-neutral-400 truncate">{song.artist}</p>
                              </div>
                           </div>
                        ))}
                      </div>
                   </section>
                )}
                
                {results.length === 0 && !isSearching && (
                   <div className="flex flex-col items-center justify-center py-20 text-neutral-500">
                      <Music size={40} className="mb-4 opacity-30" />
                      <p className="font-medium text-center px-10">No matches found for "{query}"</p>
                      <p className="text-xs mt-2">Try a different song or artist</p>
                   </div>
                )}
              </div>
            ) : (
              <div className="flex flex-col items-center justify-center py-32 text-neutral-500">
                <SearchIcon size={48} className="mb-4 opacity-30" />
                <p className="font-bold text-lg">Search Paaatu_Padava</p>
                <p className="text-sm mt-1">Find your favorite music and podcasts</p>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default MobileSearch;
