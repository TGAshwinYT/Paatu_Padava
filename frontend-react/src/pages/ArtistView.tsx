import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { 
  Play, 
  Pause,
  ArrowLeft, 
  Heart, 
  Plus, 
  Download, 
  Share2, 
  Shuffle, 
  Check, 
  Loader2,
  UserCheck,
  UserPlus
} from 'lucide-react';
import { getArtistDetails, likeSong, unlikeSong, downloadSongFile } from '../services/api';
import { useAudio } from '../context/AudioContext';
import { usePlaylistModal } from '../context/PlaylistModalContext';
import { useAuth } from '../context/AuthContext';
import type { Song } from '../types';
import { formatDuration } from '../utils/timeUtils';
import { isOfflineTrack } from '../utils/offlineStorage';

const ArtistView = () => {
  const { artistId } = useParams<{ artistId: string }>();
  const navigate = useNavigate();
  const [artist, setArtist] = useState<{ id: string, name: string, image: string, topSongs: Song[] } | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const { playContext, currentTrack, isPlaying, togglePlay } = useAudio();
  const { openModal } = usePlaylistModal();
  const { user } = useAuth();

  const [isFollowing, setIsFollowing] = useState(false);
  const [copiedLink, setCopiedLink] = useState(false);
  const [likedSongIds, setLikedSongIds] = useState<Set<string>>(new Set());
  const [downloadingSongId, setDownloadingSongId] = useState<string | null>(null);
  const [downloadedSongIds, setDownloadedSongIds] = useState<Set<string>>(new Set());

  // Check following state in localStorage
  useEffect(() => {
    if (!artistId) return;
    try {
      const followed = JSON.parse(localStorage.getItem('paatu_followed_artists') || '[]');
      setIsFollowing(followed.includes(artistId));
    } catch {
      setIsFollowing(false);
    }
  }, [artistId]);

  const toggleFollow = () => {
    if (!artistId) return;
    try {
      const followed = JSON.parse(localStorage.getItem('paatu_followed_artists') || '[]');
      let updated: string[];
      if (isFollowing) {
        updated = followed.filter((id: string) => id !== artistId);
        setIsFollowing(false);
      } else {
        updated = [...followed, artistId];
        setIsFollowing(true);
      }
      localStorage.setItem('paatu_followed_artists', JSON.stringify(updated));
    } catch (e) {
      console.error('Failed to toggle follow:', e);
    }
  };

  useEffect(() => {
    const fetchArtist = async () => {
      if (!artistId) return;
      setIsLoading(true);
      try {
        const data = await getArtistDetails(artistId);
        setArtist(data);
        
        // Populate downloaded songs state
        if (data.topSongs) {
          const dlSet = new Set<string>();
          data.topSongs.forEach(s => {
            if (isOfflineTrack(s.id)) dlSet.add(s.id);
          });
          setDownloadedSongIds(dlSet);
        }
      } catch (err) {
        console.error('Failed to load artist:', err);
      } finally {
        setIsLoading(false);
      }
    };
    fetchArtist();
  }, [artistId]);

  const handleShare = () => {
    navigator.clipboard.writeText(window.location.href);
    setCopiedLink(true);
    setTimeout(() => setCopiedLink(false), 2500);
  };

  const handleLikeSong = async (song: Song, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!user) {
      navigate('/login');
      return;
    }
    const isCurrentlyLiked = likedSongIds.has(song.id);
    if (isCurrentlyLiked) {
      await unlikeSong(song.id);
      setLikedSongIds(prev => {
        const next = new Set(prev);
        next.delete(song.id);
        return next;
      });
    } else {
      await likeSong(song);
      setLikedSongIds(prev => new Set(prev).add(song.id));
    }
  };

  const handleDownloadSong = async (song: Song, e: React.MouseEvent) => {
    e.stopPropagation();
    if (downloadingSongId) return;
    setDownloadingSongId(song.id);
    try {
      await downloadSongFile(song);
      setDownloadedSongIds(prev => new Set(prev).add(song.id));
    } catch (err) {
      console.error('Download failed:', err);
    } finally {
      setDownloadingSongId(null);
    }
  };

  if (isLoading) {
    return (
      <div className="flex flex-col gap-8 pb-24 items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-brand"></div>
      </div>
    );
  }

  if (!artist || !artist.id) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-neutral-500">
        <p className="text-xl font-medium">Artist not found</p>
        <button 
          onClick={() => navigate(-1)}
          className="mt-4 px-6 py-2 bg-neutral-800 text-white rounded-full hover:bg-neutral-700 transition"
        >
          Go Back
        </button>
      </div>
    );
  }

  const isCurrentArtistPlaying = isPlaying && artist.topSongs.some(s => s.id === currentTrack?.id);

  return (
    <div className="flex flex-col gap-8 pb-24 animate-in fade-in duration-500 relative pt-12">
      {/* Back Button */}
      <button 
        onClick={() => navigate(-1)}
        className="fixed top-6 left-6 z-50 p-2.5 bg-black/50 backdrop-blur-md rounded-full text-white hover:bg-black/80 transition-all border border-white/10 active:scale-90 shadow-lg"
        title="Go Back"
      >
        <ArrowLeft size={22} strokeWidth={2.5} />
      </button>

      {/* Hero Section */}
      <div className="flex flex-col md:flex-row items-center md:items-end gap-8 bg-gradient-to-b from-white/10 to-transparent p-6 rounded-2xl border border-white/5">
        <div className="w-44 h-44 md:w-56 md:h-56 flex-shrink-0">
          <img 
            src={artist.image || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&h=500&fit=crop'} 
            alt={artist.name} 
            className="w-full h-full object-cover rounded-full shadow-2xl border-4 border-white/10 ring-2 ring-brand/30"
            loading="lazy"
            onError={(e) => {
              e.currentTarget.onerror = null;
              e.currentTarget.src = 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500&h=500&fit=crop';
            }}
          />
        </div>
        <div className="flex flex-col gap-3 text-center md:text-left flex-1 min-w-0">
          <div className="flex items-center justify-center md:justify-start gap-2">
            <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-black uppercase tracking-wider bg-brand/20 text-brand border border-brand/30">
              Verified Artist
            </span>
            <span className="text-neutral-400 text-xs font-semibold">
              {artist.topSongs.length} Top Tracks
            </span>
          </div>
          <h1 className="text-4xl md:text-7xl font-black text-white tracking-tight break-words">
            {artist.name}
          </h1>

          {/* Action Row */}
          <div className="flex items-center justify-center md:justify-start gap-4 mt-2">
            {/* Play / Pause All */}
            {artist.topSongs.length > 0 && (
              <button
                onClick={() => {
                  if (isCurrentArtistPlaying) {
                    togglePlay();
                  } else {
                    playContext(artist.topSongs[0], artist.topSongs);
                  }
                }}
                className="w-14 h-14 bg-brand text-black rounded-full flex items-center justify-center hover:scale-105 active:scale-95 transition-all shadow-xl"
                title={isCurrentArtistPlaying ? "Pause" : "Play Popular Tracks"}
              >
                {isCurrentArtistPlaying ? (
                  <Pause size={24} fill="currentColor" />
                ) : (
                  <Play size={24} fill="currentColor" className="ml-1" />
                )}
              </button>
            )}

            {/* Shuffle Play */}
            {artist.topSongs.length > 1 && (
              <button
                onClick={() => {
                  const shuffled = [...artist.topSongs].sort(() => Math.random() - 0.5);
                  playContext(shuffled[0], shuffled);
                }}
                className="p-3 bg-neutral-800/80 hover:bg-neutral-700 text-white rounded-full border border-white/10 hover:scale-105 transition shadow-lg"
                title="Shuffle Artist"
              >
                <Shuffle size={20} />
              </button>
            )}

            {/* Follow Button */}
            <button
              onClick={toggleFollow}
              className={`flex items-center gap-2 px-5 py-2.5 rounded-full font-bold text-sm transition-all shadow border ${
                isFollowing
                  ? 'bg-neutral-800 text-brand border-brand/30 hover:bg-neutral-700'
                  : 'bg-white text-black border-transparent hover:scale-105 active:scale-95'
              }`}
            >
              {isFollowing ? (
                <>
                  <UserCheck size={16} />
                  <span>Following</span>
                </>
              ) : (
                <>
                  <UserPlus size={16} />
                  <span>Follow</span>
                </>
              )}
            </button>

            {/* Share Button */}
            <button
              onClick={handleShare}
              className="p-3 bg-neutral-800/80 hover:bg-neutral-700 text-neutral-300 hover:text-white rounded-full border border-white/10 hover:scale-105 transition"
              title="Share Artist Link"
            >
              {copiedLink ? <Check size={20} className="text-brand" /> : <Share2 size={20} />}
            </button>
            {copiedLink && (
              <span className="text-xs text-brand font-semibold animate-in fade-in">
                Link copied!
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Top Songs */}
      <div className="flex flex-col gap-4">
        <h2 className="text-2xl font-bold text-white mb-1 tracking-tight">Popular Tracks</h2>
        
        <div className="flex flex-col space-y-1">
          {artist.topSongs.length > 0 ? (
            artist.topSongs.map((song, idx) => {
              const isCurrent = currentTrack?.id === song.id;
              const isTrackPlaying = isCurrent && isPlaying;
              const isSongLiked = likedSongIds.has(song.id);
              const isSongDownloaded = downloadedSongIds.has(song.id);
              const isSongDownloading = downloadingSongId === song.id;

              return (
                <div 
                  key={song.id || idx} 
                  className={`group flex items-center justify-between gap-4 p-3 md:p-3.5 rounded-xl hover:bg-white/5 transition-all cursor-pointer border ${
                    isCurrent ? 'bg-white/10 border-brand/30' : 'border-transparent hover:border-white/5'
                  }`}
                  onClick={() => playContext(song, artist?.topSongs || [])}
                >
                  <div className="flex items-center gap-4 min-w-0 flex-1">
                    {/* Track Index / Play icon */}
                    <div className="w-6 flex items-center justify-center text-sm font-mono text-neutral-400">
                      {isTrackPlaying ? (
                        <div className="flex items-end gap-0.5 h-3.5">
                          <span className="w-0.5 bg-brand animate-pulse h-full" />
                          <span className="w-0.5 bg-brand animate-pulse h-2" />
                          <span className="w-0.5 bg-brand animate-pulse h-3" />
                        </div>
                      ) : (
                        <>
                          <span className={`group-hover:hidden ${isCurrent ? 'text-brand font-bold' : ''}`}>
                            {idx + 1}
                          </span>
                          <Play size={14} fill="currentColor" className="hidden group-hover:block text-white" />
                        </>
                      )}
                    </div>

                    <img 
                      src={song.coverUrl || '/logo.png'} 
                      alt="" 
                      className="w-12 h-12 rounded-lg shadow-md object-cover bg-neutral-800 flex-shrink-0" 
                      loading="lazy"
                      onError={(e) => {
                        e.currentTarget.onerror = null;
                        e.currentTarget.src = '/logo.png';
                      }}
                    />
                    
                    <div className="flex flex-col min-w-0">
                      <p className={`font-bold truncate text-sm md:text-base ${
                        isCurrent ? 'text-brand' : 'text-white group-hover:text-brand transition-colors'
                      }`}>
                        {song.title}
                      </p>
                      <p className="text-xs text-neutral-400 truncate mt-0.5">
                        {song.artist}
                      </p>
                    </div>
                  </div>

                  {/* Right side actions */}
                  <div className="flex items-center gap-2 md:gap-3 flex-shrink-0" onClick={(e) => e.stopPropagation()}>
                    {/* Like / Heart */}
                    <button
                      onClick={(e) => handleLikeSong(song, e)}
                      className={`p-2 rounded-full transition-all ${
                        isSongLiked 
                          ? 'text-brand hover:scale-110' 
                          : 'text-neutral-400 hover:text-white opacity-0 group-hover:opacity-100 hover:bg-white/10'
                      }`}
                      title={isSongLiked ? 'Unlike' : 'Like'}
                    >
                      <Heart size={18} fill={isSongLiked ? 'currentColor' : 'none'} />
                    </button>

                    {/* Add to Playlist */}
                    <button
                      onClick={() => openModal(song)}
                      className="p-2 text-neutral-400 hover:text-white rounded-full opacity-0 group-hover:opacity-100 hover:bg-white/10 transition"
                      title="Add to Playlist"
                    >
                      <Plus size={18} />
                    </button>

                    {/* 320kbps Download */}
                    <button
                      onClick={(e) => handleDownloadSong(song, e)}
                      className={`p-2 rounded-full transition ${
                        isSongDownloaded 
                          ? 'text-brand' 
                          : 'text-neutral-400 hover:text-white opacity-0 group-hover:opacity-100 hover:bg-white/10'
                      }`}
                      title={isSongDownloaded ? 'Downloaded Offline' : 'Download (320kbps MP3)'}
                    >
                      {isSongDownloading ? (
                        <Loader2 size={18} className="animate-spin text-brand" />
                      ) : isSongDownloaded ? (
                        <Check size={18} className="text-brand" />
                      ) : (
                        <Download size={18} />
                      )}
                    </button>

                    {/* Duration */}
                    <div className="text-neutral-400 text-xs md:text-sm font-mono w-12 text-right">
                      {formatDuration(song.duration)}
                    </div>
                  </div>
                </div>
              );
            })
          ) : (
            <p className="text-neutral-500 italic py-8">No popular tracks found for this artist.</p>
          )}
        </div>
      </div>
    </div>
  );
};

export default ArtistView;
