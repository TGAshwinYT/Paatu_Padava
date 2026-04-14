import React, { useState, useEffect, useRef } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Search as SearchIcon, Sparkles, Loader2, Play, ChevronRight } from 'lucide-react';
import { getSuggestions } from '../services/api';
import api from '../services/api';
import { useAudio } from '../context/AudioContext';
import useDebounce from '../hooks/useDebounce';

const TopSearchBar: React.FC = () => {
    const [searchParams] = useSearchParams();
    const [query, setQuery] = useState(searchParams.get('q') || '');
    const [isGenerating, setIsGenerating] = useState(false);
    
    // Autocomplete states
    const [suggestions, setSuggestions] = useState<any>({ songs: [], artists: [], albums: [] });
    const [isDropdownOpen, setIsDropdownOpen] = useState(false);
    const searchContainerRef = useRef<HTMLDivElement>(null);
    const debouncedQuery = useDebounce(query, 500);

    const { playContext, playFromSearch } = useAudio();
    const navigate = useNavigate();

    // Sync input with route params
    useEffect(() => {
        setQuery(searchParams.get('q') || '');
    }, [searchParams]);

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

    // Suggestions Fetch Logic
    useEffect(() => {
        let ignore = false;
        const fetchSuggestions = async () => {
            // Only fetch if query has changed from the initial URL route and isn't empty
            if (debouncedQuery.trim().length > 0 && debouncedQuery !== searchParams.get('q')) {
                try {
                    const suggestData = await getSuggestions(debouncedQuery);
                    if (!ignore) {
                        setSuggestions(suggestData);
                        setIsDropdownOpen(true);
                    }
                } catch (error) {
                    console.error("Suggestions fetch failed:", error);
                }
            } else {
                setSuggestions({ songs: [], artists: [], albums: [] });
                setIsDropdownOpen(false);
            }
        };
        fetchSuggestions();
        return () => { ignore = true; };
    }, [debouncedQuery, searchParams]);

    const handleSuggestionClick = (suggestion: any) => {
        setIsDropdownOpen(false);
        setSuggestions({ songs: [], artists: [], albums: [] });
        
        if (suggestion.type === 'artist') {
            const artistId = suggestion.id?.startsWith('vip_') ? suggestion.name : suggestion.id;
            navigate(`/artist/${artistId}`);
        } else {
            setQuery(suggestion.name || suggestion.title);
            playFromSearch(suggestion);
        }
    };

    // PATH A: Normal Search
    const handleNormalSearch = (e: React.FormEvent) => {
        e.preventDefault();
        if (!query.trim() || isGenerating) return;
        setIsDropdownOpen(false);
        navigate(`/search?q=${encodeURIComponent(query)}`);
    };

    const handleKeyDown = (e: React.KeyboardEvent) => {
        if (e.key === 'Enter') {
            setIsDropdownOpen(false);
        }
    };

    // PATH B: AI DJ Background Generation
    const handleAIDJGenerate = async (e: React.MouseEvent) => {
        e.preventDefault();
        if (!query.trim() || isGenerating) return;

        setIsGenerating(true);
        try {
            const res = await api.post('/api/ai/dj', { prompt: query });
            const aiQueue = res.data.queue;

            if (aiQueue && aiQueue.length > 0) {
                const playableQueue = aiQueue.map((s: any) => ({ ...s, isManual: true }));
                
                // Instantly load without changing page route
                playContext(playableQueue[0], playableQueue);
                
                setQuery(''); // Clear input after successful load
            }
        } catch (error: any) {
            console.error("AI DJ Error:", error);
            if (error.response?.status === 429) {
                alert("Rate limit exceeded. Please wait a minute.");
            } else {
                alert("Failed to curate AI playlist. Try again later.");
            }
        } finally {
            setIsGenerating(false);
        }
    };

    return (
        <div ref={searchContainerRef} className="relative group z-40 max-w-xl w-full">
            <form onSubmit={handleNormalSearch} className="relative flex items-center">
                <div className="absolute inset-y-0 left-4 flex items-center pointer-events-none">
                    <SearchIcon className="h-5 w-5 text-neutral-400 group-focus-within:text-white transition-colors" />
                </div>
                
                <input
                    type="text"
                    value={query}
                    onChange={(e) => {
                        setQuery(e.target.value);
                        if (e.target.value.length > 0) setIsDropdownOpen(true);
                    }}
                    onFocus={() => query.trim().length > 0 && setIsDropdownOpen(true)}
                    onKeyDown={handleKeyDown}
                    disabled={isGenerating}
                    placeholder="Search songs or Describe a Mood..."
                    className="w-full bg-[#242424] text-white rounded-full py-3.5 pl-12 pr-32 focus:outline-none focus:ring-2 focus:ring-white/10 transition-all font-medium placeholder-neutral-500 shadow-xl border border-white/5 active:bg-[#2a2a2a]"
                />

                <div className="absolute right-2 top-0 bottom-0 flex items-center py-2">
                    <button
                        type="button"
                        onClick={handleAIDJGenerate}
                        disabled={isGenerating || !query.trim()}
                        className="h-full px-5 bg-gradient-to-r from-purple-600 to-pink-600 text-white rounded-full font-bold text-sm hover:from-purple-500 hover:to-pink-500 disabled:opacity-30 disabled:grayscale transition-all shadow-lg flex items-center gap-2 active:scale-95"
                    >
                        {isGenerating ? (
                            <Loader2 className="animate-spin" size={16} />
                        ) : (
                            <Sparkles size={16} className="text-purple-100" />
                        )}
                        <span className="hidden sm:inline">{isGenerating ? 'Mixing...' : 'AI DJ'}</span>
                    </button>
                </div>
            </form>

            {/* Live Search Dropdown */}
            {isDropdownOpen && (suggestions.songs?.length > 0 || suggestions.artists?.length > 0) && (
                <div className="absolute top-full left-0 mt-3 w-full bg-[#181818] rounded-2xl shadow-2xl z-[100] overflow-hidden border border-[#333] animate-in fade-in zoom-in-95 duration-200 backdrop-blur-xl">
                    {/* Artists Section */}
                    {suggestions.artists && suggestions.artists.length > 0 && (
                        <div className="p-2">
                            <h3 className="text-[11px] uppercase font-black text-neutral-500 px-4 py-3 tracking-[0.1em]">Artists</h3>
                            {suggestions.artists.slice(0, 2).map((artist: any, index: number) => (
                                <div 
                                    key={`artist-${artist.id}-${index}`} 
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
                            {suggestions.songs.slice(0, 4).map((song: any, index: number) => (
                                <div 
                                    key={`song-${song.id}-${index}`} 
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
    );
};

export default TopSearchBar;
