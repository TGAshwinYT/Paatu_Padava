import React, { useState, useEffect, useRef } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Search as SearchIcon, Play, ChevronRight } from 'lucide-react';
import { getSuggestions } from '../services/api';
import { useAudio } from '../context/AudioContext';
import useDebounce from '../hooks/useDebounce';

const TopSearchBar: React.FC = () => {
    const [searchParams] = useSearchParams();
    const [query, setQuery] = useState(searchParams.get('q') || '');
    
    // Autocomplete states
    const [suggestions, setSuggestions] = useState<any>({ songs: [], artists: [], albums: [] });
    const [isDropdownOpen, setIsDropdownOpen] = useState(false);
    const searchContainerRef = useRef<HTMLDivElement>(null);
    const debouncedQuery = useDebounce(query, 500);

    const { playFromSearch } = useAudio();
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
        if (!query.trim()) return;
        setIsDropdownOpen(false);
        navigate(`/search?q=${encodeURIComponent(query)}`);
    };

    const handleKeyDown = (e: React.KeyboardEvent) => {
        if (e.key === 'Enter') {
            setIsDropdownOpen(false);
        }
    };

    return (
        <div ref={searchContainerRef} className="relative group z-40 max-w-xl w-full">
            <form onSubmit={handleNormalSearch} className="relative flex items-center">
                <div className="absolute inset-y-0 left-4 flex items-center pointer-events-none">
                    <SearchIcon className="h-5 w-5 text-neutral-400 group-focus-within:text-white transition-colors" />
                </div>
                
                <input
                    id="top-search-input"
                    type="text"
                    value={query}
                    onChange={(e) => {
                        setQuery(e.target.value);
                        if (e.target.value.length > 0) setIsDropdownOpen(true);
                    }}
                    onFocus={() => query.trim().length > 0 && setIsDropdownOpen(true)}
                    onKeyDown={handleKeyDown}
                    placeholder="Search songs, artists, albums... (Press / to search)"
                    className="w-full bg-surface text-white rounded-full py-3.5 pl-12 pr-6 focus:outline-none focus:ring-2 focus:ring-white/10 transition-all font-medium placeholder-muted shadow-xl border border-white/5 active:bg-surface-hover"
                />
            </form>

            {/* Live Search Dropdown */}
            {isDropdownOpen && (suggestions.songs?.length > 0 || suggestions.artists?.length > 0) && (
                <div className="absolute top-full left-0 mt-3 w-full bg-surface-card rounded-2xl shadow-2xl z-[100] overflow-hidden border border-white/10 animate-in fade-in zoom-in-95 duration-200 backdrop-blur-xl">
                    {/* Artists Section */}
                    {suggestions.artists && suggestions.artists.length > 0 && (
                        <div className="p-2">
                            <h3 className="text-[11px] uppercase font-black text-neutral-500 px-4 py-3 tracking-[0.1em]">Artists</h3>
                            {suggestions.artists.slice(0, 2).map((artist: any, index: number) => {
                                const artistName = artist.name || artist.title || artist.artist || 'Artist';
                                const artistImg = artist.image?.[0]?.url || artist.image || artist.coverUrl || '/logo.png';
                                return (
                                <div 
                                    key={`artist-${artist.id}-${index}`} 
                                    className="flex items-center gap-4 p-3 hover:bg-surface-hover rounded-xl cursor-pointer transition-all group/item mx-1"
                                    onClick={() => handleSuggestionClick({...artist, type: 'artist'})}
                                >
                                    <div className="relative flex-shrink-0">
                                        <img 
                                            src={artistImg} 
                                            alt={artistName}
                                            referrerPolicy="no-referrer"
                                            onError={(e) => { e.currentTarget.src = '/logo.png'; }}
                                            className="w-12 h-12 rounded-full object-cover border border-white/10 shadow-lg group-hover:scale-105 transition-transform bg-neutral-800" 
                                        />
                                    </div>
                                    <div className="flex-1 min-w-0">
                                        <p className="text-white font-bold text-sm group-hover/item:text-brand transition-colors uppercase tracking-tight truncate">{artistName}</p>
                                        <p className="text-neutral-500 text-[10px] font-bold uppercase tracking-widest mt-0.5">Artist</p>
                                    </div>
                                    <ChevronRight size={16} className="text-neutral-600 group-hover/item:text-white transition-colors mr-2 flex-shrink-0" />
                                </div>
                                );
                            })}
                        </div>
                    )}

                    {/* Songs Section */}
                    {suggestions.songs && suggestions.songs.length > 0 && (
                        <div className="p-2 border-t border-white/5 bg-neutral-900/40">
                            <h3 className="text-[11px] uppercase font-black text-neutral-500 px-4 py-3 tracking-[0.1em]">Songs</h3>
                            {suggestions.songs.slice(0, 4).map((song: any, index: number) => {
                                const songTitle = song.title || song.name || 'Song';
                                const songArtist = song.artist || (song.primaryArtists && song.primaryArtists[0]?.name) || '';
                                const songCover = song.coverUrl || song.image?.[song.image.length-1]?.url || song.image || '/logo.png';
                                return (
                                <div 
                                    key={`song-${song.id}-${index}`} 
                                    className="flex items-center gap-4 p-2 hover:bg-surface-hover rounded-xl cursor-pointer transition-all group/song mx-1"
                                    onClick={() => handleSuggestionClick({...song, type: 'song'})}
                                >
                                    <div className="relative w-10 h-10 flex-shrink-0 bg-neutral-800 rounded overflow-hidden">
                                        <img 
                                            src={songCover} 
                                            className="w-full h-full rounded shadow-md object-cover" 
                                            alt={songTitle}
                                            referrerPolicy="no-referrer"
                                            onError={(e) => { e.currentTarget.src = '/logo.png'; }}
                                        />
                                        <div className="absolute inset-0 bg-black/40 flex items-center justify-center opacity-0 group-hover/song:opacity-100 transition-opacity rounded">
                                            <Play size={14} fill="white" className="text-white ml-0.5" />
                                        </div>
                                    </div>
                                    <div className="flex-1 min-w-0">
                                        <p className="text-sm font-bold text-white truncate group-hover/song:text-brand transition-colors">{songTitle}</p>
                                        <p className="text-[11px] text-muted truncate font-semibold uppercase tracking-tight">{songArtist}</p>
                                    </div>
                                </div>
                                );
                            })}
                        </div>
                    )}
                </div>
            )}
        </div>
    );
};

export default TopSearchBar;
