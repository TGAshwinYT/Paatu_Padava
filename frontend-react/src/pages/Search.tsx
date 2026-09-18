import React, { useState, useEffect, useRef } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { Search as SearchIcon, Music, Album, Clock, X, Play, PlusCircle, MoreHorizontal, ListMusic, Zap, Loader2, AlertCircle } from 'lucide-react';
import type { Song } from '../types';
import { searchTracks, getRecentSearches, deleteSearchHistoryItem, saveSearchClick } from '../services/api';
import { useAudio } from '../context/AudioContext';
import { useAuth } from '../context/AuthContext';
import { usePlaylistModal } from '../context/PlaylistModalContext';
import { getValidImage } from '../utils/imageUtils';
import useSpotifySearch from '../hooks/useSpotifySearch';
import { getSpotifyArt, formatSpotifyDuration } from '../services/spotifyApi';
import type { SpotifyTrack } from '../types';

// ─── Spotify Results Panel ────────────────────────────────────────────────────
interface SpotifyResultsPanelProps {
  query: string;
  onPlay: (track: SpotifyTrack) => void;
  isResolvingStream: boolean;
  resolvingTrackId: string | null;
}

const SpotifyResultsPanel: React.FC<SpotifyResultsPanelProps> = ({ query, onPlay, isResolvingStream, resolvingTrackId }) => {
  const { results, isLoading, error, hasCredentials } = useSpotifySearch(query);

  if (!hasCredentials) {
    return (
      <div className="flex flex-col items-center justify-center py-20 gap-4 text-neutral-500 bg-white/5 rounded-2xl border border-white/5 mt-4">
        <AlertCircle size={40} className="text-amber-500 opacity-70" />
        <p className="text-lg font-bold text-white/60">Spotify credentials not configured</p>
        <p className="text-sm text-center max-w-xs">
          Add <code className="bg-white/10 px-1.5 py-0.5 rounded text-amber-400">VITE_SPOTIFY_CLIENT_ID</code> and{' '}
          <code className="bg-white/10 px-1.5 py-0.5 rounded text-amber-400">VITE_SPOTIFY_CLIENT_SECRET</code>{' '}
          to your <code className="bg-white/10 px-1.5 py-0.5 rounded">.env.local</code> file.
        </p>
      </div>
    );
  }

  if (!query.trim()) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-neutral-500">
        <SearchIcon size={48} className="mb-4 opacity-10" />
        <p className="text-xl font-medium">Search Spotify's catalogue</p>
        <p className="mt-2 text-sm">Rich metadata, album art, then played via JioSaavn or YouTube</p>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="flex items-center gap-3 text-neutral-400 mt-8">
        <Loader2 className="animate-spin" size={20} />
        <span>Searching Spotify…</span>
      </div>
    );
  }

  if (error) {
    const isPremiumRequired = error.toLowerCase().includes('premium');
    return (
      <div className="flex flex-col items-center justify-center py-14 px-6 text-neutral-400 bg-white/5 rounded-2xl border border-white/5 mt-4 text-center">
        <AlertCircle size={36} className="mb-3 text-amber-400 opacity-80" />
        <p className="font-bold text-white text-base mb-2">
          {isPremiumRequired ? "Spotify Developer Policy: Active Premium Required" : error}
        </p>
        <p className="text-xs text-neutral-400 max-w-md leading-relaxed">
          {isPremiumRequired 
            ? "Under Spotify's November 2024 policy, Spotify requires the developer account owner to have an active Spotify Premium subscription to search their catalogue via Web API. In the meantime, switch to the 'All' tab to search our full 320kbps catalogue or use 'Import from Spotify' to import any public playlist directly!" 
            : "Please check your network connection or verify your Spotify developer credentials."}
        </p>
      </div>
    );
  }

  if (!results.length) {
    return (
      <div className="flex flex-col items-center justify-center py-16 text-neutral-500 mt-4">
        <Music size={40} className="mb-3 opacity-10" />
        <p className="font-bold text-white/50">No Spotify results for "{query}"</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2 mt-4">
      <div className="flex items-center gap-2 mb-2">
        <span className="text-xs font-black uppercase tracking-widest text-neutral-500">
          Spotify · {results.length} tracks found
        </span>
        <span className="text-[10px] bg-green-500/20 text-green-400 px-2 py-0.5 rounded-full font-bold border border-green-500/20">
          Silent Bridge Active
        </span>
      </div>
      {results.map((track) => {
        const isThisResolving = isResolvingStream && resolvingTrackId === track.spotifyId;
        const artistNames = track.artists.map(a => a.name).join(', ');

        return (
          <div
            key={track.spotifyId}
            className="group flex items-center justify-between hover:bg-white/10 rounded-lg p-2 cursor-pointer transition relative active:scale-[0.98]"
            onClick={() => onPlay(track)}
          >
            {/* Album Thumb */}
            <div className="relative flex-shrink-0 w-10 h-10 mr-3">
              <img
                src={getSpotifyArt(track)}
                alt={track.album.name}
                className="w-full h-full rounded object-cover shadow-md"
                onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
              />
              <div className="absolute inset-0 bg-black/50 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity rounded">
                {isThisResolving ? (
                  <Loader2 size={14} className="animate-spin text-white" />
                ) : (
                  <Play size={14} fill="white" className="text-white ml-0.5" />
                )}
              </div>
              {/* Spotify badge */}
              <div className="absolute -top-1 -right-1 w-3.5 h-3.5 bg-green-500 rounded-full border-2 border-[#121212] flex items-center justify-center">
                <span className="text-[5px] font-black text-black">S</span>
              </div>
            </div>

            {/* Track Info */}
            <div className="flex-1 min-w-0">
              <p className="text-sm font-bold text-white truncate group-hover:text-green-400 transition-colors">
                {track.name}
                {track.explicit && (
                  <span className="ml-1.5 text-[9px] bg-neutral-600 text-neutral-300 px-1 py-0.5 rounded font-bold align-middle">E</span>
                )}
              </p>
              <p className="text-xs text-neutral-400 truncate">{artistNames} · {track.album.name}</p>
            </div>

            {/* Duration */}
            <div className="text-neutral-500 text-xs px-3 hidden sm:block tabular-nums">
              {formatSpotifyDuration(track.durationMs)}
            </div>

            {/* Resolving indicator */}
            {isThisResolving && (
              <div className="flex items-center gap-1.5 text-green-400 text-xs font-bold mr-2 animate-pulse">
                <Zap size={12} />
                <span className="hidden sm:inline">Bridging…</span>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};

// ─── Main Search Page ─────────────────────────────────────────────────────────
const Search = () => {
  const [results, setResults] = useState<any>(null);
  const [isSearching, setIsSearching] = useState(false);
  const [recentlyPlayed, setRecentlyPlayed] = useState<(Song & { historyId: string })[]>([]);
  const menuRef = useRef<HTMLDivElement>(null);
  const [activeMenuId, setActiveMenuId] = useState<string | null>(null);
  const [activeFilter, setActiveFilter] = useState<'all' | 'songs' | 'albums' | 'artists' | 'spotify'>('all');
  
  // Track which Spotify track is currently being resolved for loading state
  const [resolvingSpotifyId, setResolvingSpotifyId] = useState<string | null>(null);

  const { playFromSearch, playHybridTrack, isResolvingStream } = useAudio();
  const { user } = useAuth();
  const primaryLang = React.useMemo(() => {
    const raw = user?.preferredLanguages || user?.preferred_languages;
    if (!raw) return 'Tamil';
    if (Array.isArray(raw) && raw.length > 0) {
      const first = String(raw[0]).trim();
      return first ? first.charAt(0).toUpperCase() + first.slice(1).toLowerCase() : 'Tamil';
    }
    if (typeof raw === 'string') {
      if (raw.startsWith('[')) {
        try {
          const parsed = JSON.parse(raw);
          if (Array.isArray(parsed) && parsed.length > 0) {
            const first = String(parsed[0]).trim();
            return first ? first.charAt(0).toUpperCase() + first.slice(1).toLowerCase() : 'Tamil';
          }
        } catch {}
      }
      const parts = raw.split(',').map(p => p.trim()).filter(Boolean);
      if (parts.length > 0) {
        return parts[0].charAt(0).toUpperCase() + parts[0].slice(1).toLowerCase();
      }
    }
    return 'Tamil';
  }, [user]);
  const { openModal } = usePlaylistModal();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  
  const formatTime = (seconds: number) => {
    if (!seconds) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  const handleOpenMenu = (e: React.MouseEvent, songId: string) => {
    e.stopPropagation();
    setActiveMenuId(activeMenuId === songId ? null : songId);
  };

  const initialQuery = searchParams.get('q') ?? '';
  
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
  
  // Fetch history on mount
  useEffect(() => {
    if (user && !initialQuery) {
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
  }, [user, initialQuery]);

  // Handle query from URL
  useEffect(() => {
    if (initialQuery) {
      const performSearch = async () => {
        setIsSearching(true);
        try {
          const data = await searchTracks(initialQuery);
          setResults(data);
        } catch (error) {
          console.error("Search failed:", error);
        } finally {
          setIsSearching(false);
        }
      };
      performSearch();
    } else {
      setResults(null);
    }
  }, [initialQuery]);

  const handleDeleteHistory = async (e: React.MouseEvent, historyId: string) => {
    e.stopPropagation();
    try {
      await deleteSearchHistoryItem(historyId);
      setRecentlyPlayed(prev => prev.filter(item => item.historyId !== historyId));
    } catch (error) {
      console.error("Failed to delete history item:", error);
    }
  };

  // ── Spotify play handler ──────────────────────────────────────────────────
  const handleSpotifyPlay = async (track: SpotifyTrack) => {
    setResolvingSpotifyId(track.spotifyId);
    await playHybridTrack(track);
    setResolvingSpotifyId(null);
  };

  // All filter chips
  const filterChips = ['all', 'songs', 'albums', 'artists', 'spotify'] as const;

  return (
    <div className="flex flex-col gap-6 pb-24 max-w-7xl mx-auto px-4 sm:px-6 pt-4">
        {isSearching ? (
          <div className="flex items-center gap-3 text-neutral-400 mt-8">
             <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-white"></div>
             <span>Searching database...</span>
          </div>
        ) : results?.global_matches && (results.global_matches?.top_result || results.global_matches?.songs?.length > 0 || results.global_matches?.artists?.length > 0 || results.global_matches?.albums?.length > 0) ? (
          <div className="flex flex-col gap-6">
            <div className="flex flex-col gap-4">
              <div className="flex items-center justify-between">
                <h2 className="text-2xl font-black">Search Results</h2>
                <button onClick={() => setResults(null)} className="text-sm text-neutral-500 hover:text-white transition-colors">Clear Results</button>
              </div>

              {/* Category Filter Chips — including Spotify */}
              <div className="flex items-center gap-2 overflow-x-auto no-scrollbar py-2 -mx-4 px-4 sticky top-0 z-20 bg-surface-base/90 backdrop-blur-md">
                {filterChips.map((filter) => (
                  <button
                    key={filter}
                    onClick={() => setActiveFilter(filter)}
                    className={`px-4 py-1.5 rounded-full text-xs font-bold transition-all whitespace-nowrap border flex items-center gap-1.5 ${
                      activeFilter === filter 
                        ? filter === 'spotify' ? 'bg-brand text-black border-brand' : 'bg-white text-black border-white'
                        : 'bg-white/10 text-white border-transparent hover:bg-white/20'
                    }`}
                  >
                    {filter === 'spotify' && <span className="text-[9px] font-black">♫</span>}
                    {filter.charAt(0).toUpperCase() + filter.slice(1)}
                  </button>
                ))}
              </div>
            </div>

            {/* ── Spotify Results Tab ────────────────────────────────────── */}
            {activeFilter === 'spotify' && (
              <SpotifyResultsPanel
                query={initialQuery}
                onPlay={handleSpotifyPlay}
                isResolvingStream={isResolvingStream}
                resolvingTrackId={resolvingSpotifyId}
              />
            )}

            {/* ── Standard Results ──────────────────────────────────────── */}
            {activeFilter !== 'spotify' && (
              <div className="flex flex-col gap-10 mt-2">
                
                {/* Top Result + Songs */}
                {(activeFilter === 'all' || activeFilter === 'songs' || activeFilter === (results?.global_matches?.top_result?.type === 'artist' ? 'artists' : results?.global_matches?.top_result?.type === 'album' ? 'albums' : 'songs')) && (
                  <section className={`grid grid-cols-1 ${activeFilter === 'all' && results?.global_matches?.top_result ? 'lg:grid-cols-[1fr_2fr]' : ''} gap-8`}>
                    
                    {/* Top Result */}
                    {(activeFilter === 'all' || activeFilter === (results?.global_matches?.top_result?.type === 'artist' ? 'artists' : results?.global_matches?.top_result?.type === 'album' ? 'albums' : 'songs')) && results?.global_matches?.top_result && (
                      <div className="flex flex-col gap-4">
                        <h3 className="text-xl font-bold">Top result</h3>
                        <div 
                          className="bg-surface-card hover:bg-neutral-800/80 p-6 rounded-2xl transition-all duration-500 cursor-pointer flex flex-col gap-5 shadow-lg group relative overflow-hidden"
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
                              className={`w-32 h-32 md:w-36 md:h-36 object-cover shadow-2xl transition-transform duration-500 ${results.global_matches.top_result.type === 'artist' ? 'rounded-full' : 'rounded-xl'}`}
                              onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                            />
                          </div>
                          <div>
                            <h4 className="text-2xl md:text-4xl font-black text-white truncate max-w-[280px] tracking-tight">{results.global_matches.top_result?.name || results.global_matches.top_result?.title}</h4>
                            <div className="flex items-center gap-3 mt-3">
                              <span className="text-[11px] font-black uppercase tracking-widest bg-black/40 px-3 py-1 rounded-full text-neutral-300">
                                {results.global_matches.top_result.type}
                              </span>
                            </div>
                          </div>
                        </div>
                      </div>
                    )}

                    {/* Songs Section */}
                    {(results?.global_matches?.songs?.length > 0 || (results?.global_matches?.top_result?.type === 'song' && (activeFilter === 'all' || activeFilter === 'songs'))) ? (
                      results?.global_matches?.songs?.length > 0 && (
                      <div className="flex flex-col gap-4">
                        <h3 className="text-xl font-bold">Songs</h3>
                        <div className="flex flex-col gap-1" ref={menuRef}>
                          {(activeFilter === 'all' ? results.global_matches.songs.slice(0, 5) : results.global_matches.songs).map((song: any) => (
                            <div 
                              key={song.id}
                              className="group flex items-center justify-between hover:bg-white/10 rounded-lg p-2 cursor-pointer transition relative active:scale-[0.98]"
                              onClick={() => {
                                  playFromSearch(song);
                                  saveSearchClick(song);
                              }}
                            >
                              <div className="flex items-center gap-3 flex-1 min-w-0">
                                <img src={getValidImage(song)} className="w-10 h-10 rounded shrink-0 object-cover" alt="" onError={(e) => { e.currentTarget.src = '/logo.png'; }} />
                                <div className="truncate">
                                  <p className="text-sm font-bold text-white truncate">{song.title}</p>
                                  <p className="text-xs text-neutral-400 truncate">{song.artist}</p>
                                </div>
                              </div>
                              <div className="text-neutral-400 text-xs px-2 hidden sm:block">
                                {formatTime(song.duration)}
                              </div>
                              <button onClick={(e) => handleOpenMenu(e, song.id)} className="p-2 text-neutral-400 hover:text-white">
                                 <MoreHorizontal size={18} />
                              </button>
                              {activeMenuId === song.id && (
                                  <div className="absolute right-0 top-12 w-48 bg-surface rounded shadow-2xl z-50 py-1 border border-white/10">
                                      <button onClick={(e) => { e.stopPropagation(); openModal(song); setActiveMenuId(null); }} className="w-full text-left px-4 py-2 hover:bg-white/10 text-sm flex items-center gap-2"><PlusCircle size={14}/> Add to Playlist</button>
                                  </div>
                              )}
                            </div>
                          ))}
                        </div>
                      </div>
                    )) : activeFilter === 'songs' && (
                      <div className="flex flex-col items-center justify-center py-20 text-neutral-500 bg-white/5 rounded-2xl border border-white/5">
                        <Music size={40} className="mb-3 opacity-20" />
                        <p className="text-lg font-bold text-white/50">No songs found</p>
                        <p className="text-sm">Try searching with a different term or clear filters</p>
                      </div>
                    )}
                  </section>
                )}

                {/* Artists Grid */}
                {(activeFilter === 'all' || activeFilter === 'artists') && (
                  <section>
                    {(results?.global_matches?.artists?.length > 0 || (results?.global_matches?.top_result?.type === 'artist' && (activeFilter === 'all' || activeFilter === 'artists'))) ? (
                      <>
                        {results?.global_matches?.artists?.length > 0 && (
                          <>
                            <div className="flex items-center justify-between mb-4">
                              <h2 className="text-xl font-bold">Artists</h2>
                              {activeFilter === 'all' && results.global_matches.artists.length > 6 && (
                                <button onClick={() => setActiveFilter('artists')} className="text-xs font-bold text-neutral-400 hover:text-white transition-colors">See all</button>
                              )}
                            </div>
                            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4 sm:gap-6">
                              {(activeFilter === 'all' ? results.global_matches.artists.slice(0, 6) : results.global_matches.artists).map((artist: any, index: number) => (
                                <div key={`artist-${index}`} className="bg-white/5 hover:bg-white/10 p-4 rounded-xl flex flex-col items-center gap-3 cursor-pointer transition group" onClick={() => navigate(`/artist/${artist.id}`)}>
                                  <img src={getValidImage(artist)} className="w-full aspect-square rounded-full object-cover shadow-lg" alt="" onError={(e) => { e.currentTarget.src = '/logo.png'; }} />
                                  <p className="text-sm font-bold text-white truncate w-full text-center">{artist.name || artist.title}</p>
                                </div>
                              ))}
                            </div>
                          </>
                        )}
                      </>
                    ) : activeFilter === 'artists' && (
                      <div className="flex flex-col items-center justify-center py-20 text-neutral-500 bg-white/5 rounded-2xl border border-white/5">
                        <PlusCircle size={40} className="mb-3 opacity-20" />
                        <p className="text-lg font-bold text-white/50">No artists found</p>
                        <p className="text-sm">Try searching with a different term or clear filters</p>
                      </div>
                    )}
                  </section>
                )}

                {/* Albums Grid */}
                {(activeFilter === 'all' || activeFilter === 'albums') && (
                  <section>
                    {(results?.global_matches?.albums?.length > 0 || (results?.global_matches?.top_result?.type === 'album' && (activeFilter === 'all' || activeFilter === 'albums'))) ? (
                      <>
                        {results?.global_matches?.albums?.length > 0 && (
                          <>
                            <div className="flex items-center justify-between mb-4">
                              <h2 className="text-xl font-bold">Albums</h2>
                              {activeFilter === 'all' && results.global_matches.albums.length > 6 && (
                                <button onClick={() => setActiveFilter('albums')} className="text-xs font-bold text-neutral-400 hover:text-white transition-colors">See all</button>
                              )}
                            </div>
                            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4 sm:gap-6">
                              {(activeFilter === 'all' ? results.global_matches.albums.slice(0, 6) : results.global_matches.albums).map((album: any, index: number) => (
                                <div key={`album-${index}`} className="bg-white/5 hover:bg-white/10 p-4 rounded-xl cursor-pointer transition group" onClick={() => navigate(`/album/${album.id}`)}>
                                  <img src={getValidImage(album)} className="w-full aspect-square rounded-lg object-cover shadow-lg mb-2" alt="" onError={(e) => { e.currentTarget.src = '/logo.png'; }} />
                                  <p className="text-sm font-bold text-white truncate w-full">{album.title}</p>
                                  <p className="text-xs text-neutral-400 truncate w-full">{album.artist || 'Album'}</p>
                                </div>
                              ))}
                            </div>
                          </>
                        )}
                      </>
                    ) : activeFilter === 'albums' && (
                      <div className="flex flex-col items-center justify-center py-20 text-neutral-500 bg-white/5 rounded-2xl border border-white/5">
                        <Album size={40} className="mb-3 opacity-20" />
                        <p className="text-lg font-bold text-white/50">No albums found</p>
                        <p className="text-sm">Try searching with a different term or clear filters</p>
                      </div>
                    )}
                  </section>
                )}
              </div>
            )}
          </div>
        ) : initialQuery && !isSearching ? (
          // No DB results — still show Spotify tab
          <div className="flex flex-col gap-6">
            <div className="flex items-center justify-between">
              <div className="flex flex-col gap-1">
                <h2 className="text-2xl font-black">No local results for "{initialQuery}"</h2>
                <p className="text-sm text-neutral-500">Try the Spotify tab to find it globally and play via Silent Bridge.</p>
              </div>
            </div>
            <div className="flex items-center gap-2 overflow-x-auto no-scrollbar py-2 -mx-4 px-4 sticky top-0 z-20 bg-surface-base/90 backdrop-blur-md">
              {filterChips.map((filter) => (
                <button
                  key={filter}
                  onClick={() => setActiveFilter(filter)}
                  className={`px-4 py-1.5 rounded-full text-xs font-bold transition-all whitespace-nowrap border flex items-center gap-1.5 ${
                    activeFilter === filter 
                      ? filter === 'spotify' ? 'bg-brand text-black border-brand' : 'bg-white text-black border-white'
                      : 'bg-white/10 text-white border-transparent hover:bg-white/20'
                  }`}
                >
                  {filter === 'spotify' && <span className="text-[9px] font-black">♫</span>}
                  {filter.charAt(0).toUpperCase() + filter.slice(1)}
                </button>
              ))}
            </div>
            <SpotifyResultsPanel
              query={initialQuery}
              onPlay={handleSpotifyPlay}
              isResolvingStream={isResolvingStream}
              resolvingTrackId={resolvingSpotifyId}
            />
          </div>
        ) : recentlyPlayed.length > 0 ? (
          <div className="animate-in fade-in duration-700 slide-in-from-bottom-4">
            <div className="flex items-center gap-2 mb-6 text-neutral-400">
              <Clock size={20} className="text-brand" />
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
                        <p className="font-bold text-white truncate text-[15px] group-hover:text-brand transition-colors">{song.title}</p>
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
          <>
            <h2 className="text-2xl font-bold mb-6 text-white">Browse all</h2>
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4 sm:gap-6">
               <div className="bg-gradient-to-br from-[#E8115B] to-[#BC13FE] h-32 sm:h-48 rounded-2xl p-4 sm:p-6 shadow-2xl flex flex-col justify-between cursor-pointer hover:scale-[1.04] transition-all group overflow-hidden relative" onClick={() => navigate('/search?q=Podcasts')}>
                  <span className="font-black text-xl sm:text-2xl z-10">Podcasts</span>
                  <div className="absolute bottom-0 right-0 rotate-[25deg] translate-x-4 translate-y-2 group-hover:scale-110 transition-transform duration-500">
                      <Album size={100} className="text-black/20" />
                  </div>
               </div>
               <div className="bg-gradient-to-br from-[#1E3264] to-[#3371E4] h-32 sm:h-48 rounded-2xl p-4 sm:p-6 shadow-2xl flex flex-col justify-between cursor-pointer hover:scale-[1.04] transition-all group overflow-hidden relative" onClick={() => navigate('/search?q=New Releases')}>
                  <span className="font-black text-xl sm:text-2xl z-10">New Releases</span>
                  <div className="absolute bottom-0 right-0 rotate-[25deg] translate-x-4 translate-y-2 group-hover:scale-110 transition-transform duration-500">
                      <Music size={100} className="text-black/20" />
                  </div>
               </div>
               <div className="bg-gradient-to-br from-[#608108] to-[#92cc0b] h-32 sm:h-48 rounded-2xl p-4 sm:p-6 shadow-2xl flex flex-col justify-between cursor-pointer hover:scale-[1.04] transition-all group overflow-hidden relative" onClick={() => navigate(`/search?q=${encodeURIComponent(primaryLang + ' Hits')}`)}>
                  <span className="font-black text-xl sm:text-2xl z-10">{primaryLang} Hits</span>
                  <div className="absolute bottom-0 right-0 rotate-[25deg] translate-x-4 translate-y-2 group-hover:scale-110 transition-transform duration-500">
                      <SearchIcon size={100} className="text-black/20" />
                  </div>
               </div>
               <div className="bg-gradient-to-br from-[#BA5D07] to-[#e8115b] h-32 sm:h-48 rounded-2xl p-4 sm:p-6 shadow-2xl flex flex-col justify-between cursor-pointer hover:scale-[1.04] transition-all group overflow-hidden relative" onClick={() => navigate('/search?q=Charts')}>
                  <span className="font-black text-xl sm:text-2xl z-10">Charts</span>
                  <div className="absolute bottom-0 right-0 rotate-[25deg] translate-x-4 translate-y-2 group-hover:scale-110 transition-transform duration-500">
                      <ListMusic size={100} className="text-black/20" />
                  </div>
               </div>
            </div>
          </>
        )}
    </div>
  );
};

export default Search;
