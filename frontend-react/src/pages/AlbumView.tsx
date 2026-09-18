import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { 
  Play, 
  Pause,
  Heart, 
  ArrowLeft, 
  Download, 
  Share2, 
  Plus, 
  Check, 
  Loader2,
  Disc3
} from 'lucide-react';
import { useAudio } from '../context/AudioContext';
import { usePlaylistModal } from '../context/PlaylistModalContext';
import { useAuth } from '../context/AuthContext';
import { getAlbumDetails, getRecommendations, likeSong, unlikeSong, downloadSongFile } from '../services/api';
import type { Song } from '../types';
import { saveCollectionPlay } from '../utils/historyUtils';
import { formatDuration } from '../utils/timeUtils';
import { isOfflineTrack } from '../utils/offlineStorage';

const AlbumView = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { playContext, currentTrack, isPlaying, togglePlay } = useAudio();
  const { openModal } = usePlaylistModal();
  const { user } = useAuth();

  const [albumData, setAlbumData] = useState<any>(null);
  const [recommendations, setRecommendations] = useState<Song[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const [isAlbumLiked, setIsAlbumLiked] = useState(false);
  const [copiedLink, setCopiedLink] = useState(false);
  const [likedSongIds, setLikedSongIds] = useState<Set<string>>(new Set());
  const [downloadingSongId, setDownloadingSongId] = useState<string | null>(null);
  const [downloadedSongIds, setDownloadedSongIds] = useState<Set<string>>(new Set());
  const [isDownloadingAlbum, setIsDownloadingAlbum] = useState(false);

  // Check album liked state
  useEffect(() => {
    if (!id) return;
    try {
      const likedAlbums = JSON.parse(localStorage.getItem('paatu_liked_albums') || '[]');
      setIsAlbumLiked(likedAlbums.includes(id));
    } catch {
      setIsAlbumLiked(false);
    }
  }, [id]);

  const toggleAlbumLike = () => {
    if (!id) return;
    try {
      const likedAlbums = JSON.parse(localStorage.getItem('paatu_liked_albums') || '[]');
      let updated: string[];
      if (isAlbumLiked) {
        updated = likedAlbums.filter((albumId: string) => albumId !== id);
        setIsAlbumLiked(false);
      } else {
        updated = [...likedAlbums, id];
        setIsAlbumLiked(true);
      }
      localStorage.setItem('paatu_liked_albums', JSON.stringify(updated));
    } catch (e) {
      console.error('Failed to toggle album like:', e);
    }
  };

  useEffect(() => {
    const fetchAlbum = async () => {
      if (!id) return;
      setIsLoading(true);
      try {
        const data = await getAlbumDetails(id);
        setAlbumData(data);
        
        if (data.songs) {
          const dlSet = new Set<string>();
          data.songs.forEach((s: Song) => {
            if (isOfflineTrack(s.id)) dlSet.add(s.id);
          });
          setDownloadedSongIds(dlSet);
        }
      } catch (error) {
        console.error("Error loading album:", error);
      } finally {
        setIsLoading(false);
      }
    };
    fetchAlbum();
  }, [id]);

  useEffect(() => {
    const fetchRecs = async () => {
      if (albumData?.songs?.[0]?.id) {
        try {
          const recs = await getRecommendations(albumData.songs[0].id);
          setRecommendations(recs);
        } catch (e) {
          console.error("Error loading recs:", e);
        }
      }
    };
    fetchRecs();
  }, [albumData]);

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

  const handleDownloadEntireAlbum = async () => {
    if (!albumData?.songs?.length || isDownloadingAlbum) return;
    setIsDownloadingAlbum(true);
    try {
      for (const song of albumData.songs) {
        if (!downloadedSongIds.has(song.id)) {
          await downloadSongFile(song);
          setDownloadedSongIds(prev => new Set(prev).add(song.id));
        }
      }
    } catch (err) {
      console.error('Album download failed:', err);
    } finally {
      setIsDownloadingAlbum(false);
    }
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-brand"></div>
      </div>
    );
  }

  if (!albumData) {
    return (
      <div className="p-8 text-center min-h-[50vh] flex flex-col items-center justify-center">
        <Disc3 size={64} className="text-neutral-600 mb-4" />
        <h2 className="text-2xl font-bold text-white">Album not found</h2>
        <p className="text-neutral-400 mt-2">The album you're looking for is unavailable.</p>
        <button
          onClick={() => navigate(-1)}
          className="mt-6 px-6 py-2 bg-neutral-800 text-white rounded-full hover:bg-neutral-700 transition"
        >
          Go Back
        </button>
      </div>
    );
  }

  const isCurrentAlbumPlaying = isPlaying && albumData.songs?.some((s: Song) => s.id === currentTrack?.id);

  return (
    <div className="flex flex-col min-h-full bg-black text-white">
      {/* Back Button */}
      <button 
        onClick={() => navigate(-1)}
        className="fixed top-6 left-6 z-50 p-2.5 bg-black/50 backdrop-blur-md rounded-full text-white hover:bg-black/80 transition-all border border-white/10 active:scale-90 shadow-lg"
        title="Go Back"
      >
        <ArrowLeft size={22} strokeWidth={2.5} />
      </button>

      {/* Hero Header */}
      <div 
        className="relative pt-16 pb-8 px-6 flex flex-col md:flex-row items-center md:items-end gap-6 md:gap-8 transition-all duration-700 overflow-hidden"
        style={{ 
          background: `linear-gradient(to bottom, ${albumData.color || '#1e3a29'} 0%, rgba(18, 18, 18, 0.9) 70%, #000000 100%)`,
        }}
      >
        {/* Big Album Cover */}
        <div className="w-52 h-52 sm:w-60 sm:h-60 aspect-square flex-shrink-0 shadow-[0_20px_50px_rgba(0,0,0,0.85)] rounded-xl overflow-hidden transform hover:scale-[1.02] transition-all duration-500 border border-white/10 bg-neutral-900">
          <img 
            src={albumData.image || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&h=500&fit=crop'} 
            alt={albumData.title}
            className="w-full h-full object-cover"
            onError={(e) => {
              e.currentTarget.onerror = null;
              e.currentTarget.src = 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&h=500&fit=crop';
            }}
          />
        </div>

        {/* Album Details */}
        <div className="flex flex-col items-center md:items-start text-center md:text-left flex-1 min-w-0">
          <span className="text-xs uppercase font-bold tracking-widest text-neutral-400 mb-2">Album</span>
          <h1 className="text-3xl sm:text-5xl font-black text-white mb-3 leading-tight tracking-tight break-words">
            {albumData.title}
          </h1>

          <div 
            onClick={() => {
              if (albumData.artist) {
                navigate(`/artist/${encodeURIComponent(albumData.artist)}`);
              }
            }}
            className="flex items-center gap-2 mb-3 group cursor-pointer"
            title="View Artist"
          >
            <div className="w-7 h-7 rounded-full overflow-hidden bg-neutral-800 border border-white/10">
              <img src={albumData.image || '/logo.png'} className="w-full h-full object-cover" alt="" />
            </div>
            <p className="text-sm text-neutral-200 font-bold group-hover:text-brand group-hover:underline transition-colors">
              {albumData.artist}
            </p>
          </div>
          
          <div className="flex items-center gap-2 text-xs font-bold text-neutral-400 uppercase tracking-wider">
            <span>{albumData.songs?.length || 0} Songs</span>
            <span className="text-neutral-600">•</span>
            <span>HD Audio (320kbps)</span>
          </div>
        </div>
      </div>

      {/* Action Row & Content Area */}
      <div className="flex-1 bg-black px-6 pb-12">
        {/* Action Row (Play, Heart, More/Share, Download Album) */}
        <div className="flex items-center justify-between py-6 border-b border-white/5">
          <div className="flex items-center gap-5">
            {/* Main Play / Pause */}
            <button 
              onClick={() => {
                if (isCurrentAlbumPlaying) {
                  togglePlay();
                } else if (albumData.songs?.[0]) {
                  playContext(albumData.songs[0], albumData.songs);
                  saveCollectionPlay({
                    id: albumData.id || id || '',
                    title: albumData.title,
                    coverUrl: albumData.image,
                    type: 'album'
                  });
                }
              }}
              className="w-14 h-14 bg-brand rounded-full text-black flex items-center justify-center hover:scale-105 active:scale-95 transition-all shadow-xl"
              title={isCurrentAlbumPlaying ? "Pause Album" : "Play Album"}
            >
              {isCurrentAlbumPlaying ? (
                <Pause size={24} fill="black" />
              ) : (
                <Play size={24} fill="black" className="ml-1" />
              )}
            </button>
            
            {/* Heart / Like Album */}
            <button 
              onClick={toggleAlbumLike}
              className={`p-3 rounded-full transition-all transform active:scale-90 ${
                isAlbumLiked 
                  ? 'text-brand bg-brand/10' 
                  : 'text-neutral-400 hover:text-white hover:bg-white/5'
              }`}
              title={isAlbumLiked ? "Remove from Liked Albums" : "Save Album to Favorites"}
            >
              <Heart size={26} fill={isAlbumLiked ? "currentColor" : "none"} />
            </button>
            
            {/* Share / Copy Link */}
            <button 
              onClick={handleShare}
              className="p-3 text-neutral-400 hover:text-white hover:bg-white/5 rounded-full transition-all transform active:scale-90"
              title="Share Album Link"
            >
              {copiedLink ? <Check size={24} className="text-brand" /> : <Share2 size={24} />}
            </button>
            {copiedLink && (
              <span className="text-xs text-brand font-semibold animate-in fade-in">
                Link copied!
              </span>
            )}
          </div>
          
          {/* Download Entire Album */}
          <button 
            onClick={handleDownloadEntireAlbum}
            className={`flex items-center gap-2 px-4 py-2 rounded-full text-xs font-bold transition-all border ${
              isDownloadingAlbum
                ? 'bg-neutral-800 text-brand border-brand/30'
                : 'text-neutral-300 hover:text-white bg-neutral-900 border-white/10 hover:border-white/20'
            }`}
            title="Download all tracks in this album"
          >
            {isDownloadingAlbum ? (
              <>
                <Loader2 size={16} className="animate-spin text-brand" />
                <span>Downloading Album...</span>
              </>
            ) : (
              <>
                <Download size={16} />
                <span>Download Album</span>
              </>
            )}
          </button>
        </div>

        {/* Tracklist Table */}
        <div className="mt-4 max-w-7xl">
          <div className="grid grid-cols-[36px_1fr_120px] md:grid-cols-[36px_1fr_140px] gap-4 px-4 py-3 border-b border-white/5 text-neutral-500 text-[11px] uppercase font-bold tracking-[0.2em] mb-2">
            <div className="text-center">#</div>
            <div>Title</div>
            <div className="flex justify-end pr-2">Actions</div>
          </div>

          <div className="flex flex-col space-y-1">
            {albumData.songs?.map((track: Song, index: number) => {
              const isCurrent = currentTrack?.id === track.id;
              const isTrackPlaying = isCurrent && isPlaying;
              const isSongLiked = likedSongIds.has(track.id);
              const isSongDownloaded = downloadedSongIds.has(track.id);
              const isSongDownloading = downloadingSongId === track.id;

              return (
                <div 
                  key={track.id || index}
                  onClick={() => {
                    playContext(track, albumData.songs);
                    saveCollectionPlay({
                      id: albumData.id || id || '',
                      title: albumData.title,
                      coverUrl: albumData.image,
                      type: 'album'
                    });
                  }}
                  className={`grid grid-cols-[36px_1fr_120px] md:grid-cols-[36px_1fr_140px] gap-4 px-4 py-3 rounded-xl group transition-all cursor-pointer items-center border ${
                    isCurrent ? 'bg-white/10 border-brand/30' : 'border-transparent hover:bg-neutral-800/40 hover:border-white/5'
                  }`}
                >
                  {/* Track # / Play indicator */}
                  <div className="flex items-center justify-center w-8 h-8 text-neutral-400 font-mono text-sm">
                    {isTrackPlaying ? (
                      <div className="flex items-end gap-0.5 h-3.5">
                        <span className="w-0.5 bg-brand animate-pulse h-full" />
                        <span className="w-0.5 bg-brand animate-pulse h-2" />
                        <span className="w-0.5 bg-brand animate-pulse h-3" />
                      </div>
                    ) : (
                      <>
                        <span className={`group-hover:hidden ${isCurrent ? 'text-brand font-bold' : ''}`}>
                          {index + 1}
                        </span>
                        <Play size={14} fill="currentColor" className="hidden group-hover:block text-white" />
                      </>
                    )}
                  </div>

                  {/* Title & Artist */}
                  <div className="flex flex-col min-w-0 pr-2">
                    <span className={`font-bold truncate text-sm md:text-base ${
                      isCurrent ? 'text-brand' : 'text-white group-hover:text-brand transition-colors'
                    }`}>
                      {track.title}
                    </span>
                    <span className="text-xs font-medium text-neutral-400 group-hover:text-neutral-300 transition-colors truncate mt-0.5">
                      {track.artist}
                    </span>
                  </div>

                  {/* Actions & Duration */}
                  <div className="flex items-center justify-end gap-2 pr-2" onClick={(e) => e.stopPropagation()}>
                    {/* Like Song */}
                    <button
                      onClick={(e) => handleLikeSong(track, e)}
                      className={`p-1.5 rounded-full transition-all ${
                        isSongLiked 
                          ? 'text-brand' 
                          : 'text-neutral-400 hover:text-white opacity-0 group-hover:opacity-100'
                      }`}
                      title={isSongLiked ? "Unlike" : "Like"}
                    >
                      <Heart size={16} fill={isSongLiked ? "currentColor" : "none"} />
                    </button>

                    {/* Add to Playlist */}
                    <button
                      onClick={() => openModal(track)}
                      className="p-1.5 text-neutral-400 hover:text-white opacity-0 group-hover:opacity-100 rounded-full transition"
                      title="Add to Playlist"
                    >
                      <Plus size={16} />
                    </button>

                    {/* Download Song */}
                    <button
                      onClick={(e) => handleDownloadSong(track, e)}
                      className={`p-1.5 rounded-full transition ${
                        isSongDownloaded 
                          ? 'text-brand' 
                          : 'text-neutral-400 hover:text-white opacity-0 group-hover:opacity-100'
                      }`}
                      title={isSongDownloaded ? "Downloaded Offline" : "Download (320kbps MP3)"}
                    >
                      {isSongDownloading ? (
                        <Loader2 size={16} className="animate-spin text-brand" />
                      ) : isSongDownloaded ? (
                        <Check size={16} className="text-brand" />
                      ) : (
                        <Download size={16} />
                      )}
                    </button>

                    {/* Duration */}
                    <span className="text-xs text-neutral-400 font-mono w-10 text-right">
                      {formatDuration(track.duration)}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Recommendations Section */}
        {recommendations.length > 0 && (
          <div className="mt-16 mb-10 max-w-7xl">
            <h2 className="text-2xl font-bold text-white mb-6 tracking-tight">You Might Also Like</h2>
            <div className="flex overflow-x-auto gap-6 pb-6 scrollbar-hide -mx-2 px-2">
              {recommendations.map((rec) => (
                <div 
                  key={rec.id}
                  onClick={() => playContext(rec, recommendations)}
                  className="flex-shrink-0 w-40 md:w-48 bg-neutral-900/60 p-4 rounded-xl hover:bg-neutral-800 transition-all cursor-pointer group shadow-lg border border-white/5 active:scale-95"
                >
                  <div className="relative aspect-square mb-4 shadow-lg rounded-lg overflow-hidden">
                    <img 
                      src={rec.coverUrl} 
                      alt={rec.title}
                      className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500"
                    />
                    <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                      <div className="w-12 h-12 bg-brand rounded-full flex items-center justify-center shadow-xl transform translate-y-4 group-hover:translate-y-0 transition-transform duration-300">
                        <Play size={20} fill="black" className="ml-1" />
                      </div>
                    </div>
                  </div>
                  <div className="flex flex-col gap-1">
                    <h3 className="text-white font-bold truncate text-sm tracking-tight group-hover:text-brand transition-colors">{rec.title}</h3>
                    <p className="text-neutral-400 text-xs font-semibold truncate group-hover:text-neutral-300 transition-colors">{rec.artist}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default AlbumView;
