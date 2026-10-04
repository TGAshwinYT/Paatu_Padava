import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import type { Song } from '../types';
import { getPlaylistDetail, removeSongFromPlaylist, renamePlaylist, deletePlaylist } from '../services/api';
import { saveCollectionPlay } from '../utils/historyUtils';
import { getValidImage } from '../utils/imageUtils';
import { useAuth } from '../context/AuthContext';
import { Music, Trash2, Play, MoreVertical, Edit2, ArrowLeft, Clock } from 'lucide-react';
import { useAudio } from '../context/AudioContext';

const formatDuration = (secs?: number) => {
  if (!secs || isNaN(secs) || secs <= 0) return '3:45';
  const mins = Math.floor(secs / 60);
  const remaining = Math.floor(secs % 60);
  return `${mins}:${remaining.toString().padStart(2, '0')}`;
};

const PlaylistDetail: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [songs, setSongs] = useState<Song[]>([]);
  const [playlistTitle, setPlaylistTitle] = useState('Playlist');
  const [playlistCover, setPlaylistCover] = useState<string | null>(null);
  const [playlistDescription, setPlaylistDescription] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const { user } = useAuth();
  const { playContext, currentTrack, isPlaying, togglePlay, refreshPlaylists } = useAudio();
  const [showMenu, setShowMenu] = useState(false);
  const [showRenameModal, setShowRenameModal] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [editTitle, setEditTitle] = useState('');

  useEffect(() => {
    const fetchDetail = async () => {
      if (!id || !user) {
        setIsLoading(false);
        return;
      }
      setIsLoading(true);
      try {
        const { title, description, coverUrl, songs: playlistSongs } = await getPlaylistDetail(id);
        setPlaylistTitle(title);
        setPlaylistDescription(description || null);
        setPlaylistCover(coverUrl || null);
        setSongs(playlistSongs);
      } catch (err) {
        console.error("Error loading playlist detail:", err);
      } finally {
        setIsLoading(false);
      }
    };
    fetchDetail();
  }, [id, user]);

  const handleRemove = async (songId: string) => {
    if (!id) return;
    try {
      await removeSongFromPlaylist(id, songId);
      setSongs(prev => prev.filter(s => s.id !== songId));
    } catch (err) {
      console.error("Error removing song:", err);
    }
  };

  const handlePlayAll = () => {
    if (songs.length > 0) {
      playContext(songs[0], songs);
      if (id) {
        saveCollectionPlay({
          id: id,
          title: playlistTitle,
          coverUrl: displayCover || '',
          type: 'playlist'
        });
      }
    }
  };

  const handleRename = async () => {
    if (!id || !editTitle.trim()) return;
    try {
      await renamePlaylist(id, editTitle);
      setPlaylistTitle(editTitle);
      setShowRenameModal(false);
      await refreshPlaylists();
      window.dispatchEvent(new Event('playlists-updated'));
    } catch (error) {
      alert("Failed to rename playlist");
    }
  };

  const handleDelete = async () => {
    if (!id) return;
    try {
      await deletePlaylist(id);
      await refreshPlaylists();
      window.dispatchEvent(new Event('playlists-updated'));
      navigate('/');
    } catch (error) {
      alert("Failed to delete playlist");
    }
  };

  if (isLoading) {
    return (
      <div className="flex flex-col gap-8 pb-24 items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-brand"></div>
      </div>
    );
  }

  if (!user) {
    navigate('/login');
    return null;
  }

  const displayCover = playlistCover || (songs.length > 0 ? songs[0].coverUrl : null);

  return (
    <div className="flex flex-col min-h-full bg-black text-white">
      {/* Back Button */}
      <button 
        onClick={() => navigate(-1)}
        className="fixed top-6 left-6 z-50 p-2.5 bg-black/60 backdrop-blur-md rounded-full text-white hover:bg-neutral-800 transition-all border border-white/10 active:scale-90 shadow-lg"
        title="Go Back"
      >
        <ArrowLeft size={22} strokeWidth={2.5} />
      </button>

      {/* Hero Header */}
      <div 
        className="relative pt-16 pb-8 px-6 md:px-10 flex flex-col md:flex-row items-center md:items-end gap-6 md:gap-8 transition-all duration-700 overflow-hidden"
        style={{ 
          background: `linear-gradient(to bottom, rgba(30, 215, 96, 0.28) 0%, rgba(18, 18, 18, 0.85) 65%, #000000 100%)`,
        }}
      >
        {/* Playlist Cover Art */}
        <div className="w-48 h-48 sm:w-56 sm:h-56 md:w-60 md:h-60 aspect-square flex-shrink-0 shadow-[0_20px_50px_rgba(0,0,0,0.85)] rounded-xl overflow-hidden transform hover:scale-[1.02] transition-all duration-500 border border-white/10 bg-neutral-900 flex items-center justify-center">
          {displayCover ? (
            <img 
              src={displayCover} 
              className="w-full h-full object-cover" 
              alt={playlistTitle}
              onError={(e) => {
                e.currentTarget.onerror = null;
                e.currentTarget.src = '/logo.png';
              }} 
            />
          ) : (
            <div className="flex flex-col items-center justify-center text-neutral-600">
              <Music size={72} />
            </div>
          )}
        </div>

        {/* Playlist Metadata */}
        <div className="flex flex-col items-center md:items-start text-center md:text-left flex-1 min-w-0">
          <span className="text-xs uppercase font-bold tracking-widest text-neutral-400 mb-2">Playlist</span>
          <h1 className="text-2xl sm:text-4xl md:text-5xl font-black text-white mb-3 leading-tight tracking-tight break-words">
            {playlistTitle}
          </h1>
          {playlistDescription && (
            <p className="text-sm text-neutral-400 mb-3 line-clamp-2 max-w-2xl">{playlistDescription}</p>
          )}
          <div className="flex flex-wrap items-center justify-center md:justify-start gap-2 text-sm text-neutral-300 font-medium">
            <span className="font-bold text-white">{user.username}</span>
            <span className="text-neutral-600">•</span>
            <span>{songs.length} {songs.length === 1 ? 'song' : 'songs'}</span>
          </div>
        </div>
      </div>

      {/* Main Tracklist Section */}
      <div className="flex-1 bg-black px-4 sm:px-8 md:px-10 pb-20">
        {/* Action Controls Bar */}
        <div className="flex items-center justify-between py-6">
          <div className="flex items-center gap-5">
            <button 
              onClick={handlePlayAll}
              disabled={songs.length === 0}
              className="w-14 h-14 bg-brand rounded-full text-black flex items-center justify-center hover:scale-105 active:scale-95 transition-all shadow-xl shadow-brand/20 disabled:opacity-50 disabled:hover:scale-100"
              title="Play All"
            >
              <Play size={24} fill="black" className="ml-1" />
            </button>
            
            <div className="relative">
              <button 
                onClick={() => setShowMenu(!showMenu)}
                className="text-neutral-400 hover:text-white p-2 rounded-full hover:bg-neutral-800 transition-all transform active:scale-90"
                title="More options"
              >
                <MoreVertical size={24} />
              </button>

              {showMenu && (
                <div className="absolute top-full left-0 mt-2 w-48 bg-neutral-900 rounded-xl shadow-2xl border border-white/10 py-1.5 z-50 animate-in fade-in slide-in-from-top-2 duration-200">
                  <button 
                    onClick={() => {
                      setEditTitle(playlistTitle);
                      setShowRenameModal(true);
                      setShowMenu(false);
                    }}
                    className="w-full flex items-center gap-3 px-4 py-2.5 text-sm text-neutral-300 hover:bg-neutral-800 hover:text-white transition-colors"
                  >
                    <Edit2 size={16} />
                    Rename Playlist
                  </button>
                  <button 
                    onClick={() => {
                      setShowDeleteConfirm(true);
                      setShowMenu(false);
                    }}
                    className="w-full flex items-center gap-3 px-4 py-2.5 text-sm text-red-400 hover:bg-red-500/10 hover:text-red-300 transition-colors border-t border-white/5"
                  >
                    <Trash2 size={16} />
                    Delete Playlist
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Rename Modal */}
        {showRenameModal && (
          <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200">
            <div className="bg-neutral-900 w-full max-w-sm rounded-2xl p-6 shadow-2xl border border-white/10">
              <h2 className="text-xl font-bold mb-4">Rename Playlist</h2>
              <input 
                type="text"
                value={editTitle}
                onChange={(e) => setEditTitle(e.target.value)}
                className="w-full bg-neutral-800 text-white p-3.5 rounded-xl mb-6 focus:outline-none focus:ring-2 focus:ring-brand border border-white/5 text-sm"
                placeholder="New playlist name"
                autoFocus
              />
              <div className="flex justify-end gap-3">
                <button onClick={() => setShowRenameModal(false)} className="px-4 py-2 text-neutral-400 font-semibold hover:text-white transition">Cancel</button>
                <button onClick={handleRename} className="px-5 py-2 bg-brand text-black rounded-full font-bold hover:scale-105 transition">Save</button>
              </div>
            </div>
          </div>
        )}

        {/* Delete Confirmation */}
        {showDeleteConfirm && (
          <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200">
            <div className="bg-neutral-900 w-full max-w-sm rounded-2xl p-6 shadow-2xl border border-white/10 text-center">
              <div className="w-14 h-14 bg-red-500/20 text-red-500 rounded-full flex items-center justify-center mx-auto mb-4">
                <Trash2 size={28} />
              </div>
              <h2 className="text-xl font-bold mb-2">Delete Playlist?</h2>
              <p className="text-neutral-400 text-sm mb-6">This will remove "{playlistTitle}" forever. You can't undo this action.</p>
              <div className="flex flex-col gap-2.5">
                <button onClick={handleDelete} className="w-full py-3 bg-red-500 text-white rounded-full font-bold hover:bg-red-600 transition">Delete</button>
                <button onClick={() => setShowDeleteConfirm(false)} className="w-full py-3 text-neutral-400 font-bold hover:text-white transition">Cancel</button>
              </div>
            </div>
          </div>
        )}

        {/* Compact Spotify-Style Tracklist Table */}
        {songs.length > 0 ? (
          <div className="w-full">
            {/* Table Header */}
            <div className="grid grid-cols-[36px_1fr_40px] md:grid-cols-[36px_1fr_100px_48px] gap-4 px-4 py-2.5 border-b border-white/10 text-neutral-400 text-[11px] uppercase font-bold tracking-wider mb-2">
              <div className="text-center">#</div>
              <div>Title</div>
              <div className="hidden md:flex justify-end pr-4 items-center gap-1">
                <Clock size={14} />
              </div>
              <div className="text-center"></div>
            </div>

            {/* Song Rows */}
            <div className="flex flex-col space-y-1">
              {songs.map((song, index) => {
                const isCurrent = currentTrack?.id === song.id;
                const isTrackPlaying = isCurrent && isPlaying;

                return (
                  <div 
                    key={song.id || index}
                    onClick={() => {
                      if (isCurrent) {
                        togglePlay();
                      } else {
                        playContext(song, songs);
                        if (id) {
                          saveCollectionPlay({
                            id: id,
                            title: playlistTitle,
                            coverUrl: displayCover || '',
                            type: 'playlist'
                          });
                        }
                      }
                    }}
                    className={`grid grid-cols-[36px_1fr_40px] md:grid-cols-[36px_1fr_100px_48px] gap-4 px-4 py-2.5 rounded-lg group transition-all items-center cursor-pointer ${
                      isCurrent ? 'bg-white/10' : 'hover:bg-white/5'
                    }`}
                  >
                    {/* Index / Play / Pause / Equalizer */}
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
                          <Play size={14} fill="white" className="hidden group-hover:block text-white" />
                        </>
                      )}
                    </div>

                    {/* Thumbnail + Title + Artist */}
                    <div className="flex items-center gap-3.5 min-w-0">
                      <img 
                        src={getValidImage(song)} 
                        alt={song.title} 
                        className="w-11 h-11 rounded-md object-cover flex-shrink-0 shadow-md bg-neutral-900 border border-white/5"
                        loading="lazy"
                        onError={(e) => { 
                          e.currentTarget.onerror = null; 
                          e.currentTarget.src = '/logo.png'; 
                        }}
                      />
                      <div className="flex flex-col min-w-0">
                        <span className={`font-semibold truncate text-sm sm:text-base ${
                          isCurrent ? 'text-brand' : 'text-white group-hover:text-brand transition-colors'
                        }`}>
                          {song.title}
                        </span>
                        <span className="text-xs text-neutral-400 group-hover:text-neutral-300 truncate mt-0.5">
                          {song.artist}
                        </span>
                      </div>
                    </div>

                    {/* Duration */}
                    <div className="hidden md:flex justify-end text-sm text-neutral-400 font-mono pr-4">
                      {formatDuration(song.duration)}
                    </div>

                    {/* Remove Action */}
                    <div className="flex items-center justify-center" onClick={(e) => e.stopPropagation()}>
                      <button 
                        onClick={() => handleRemove(song.id)}
                        className="opacity-0 group-hover:opacity-100 p-2 text-neutral-400 hover:text-red-400 hover:bg-red-500/10 rounded-full transition-all"
                        title="Remove from playlist"
                      >
                        <Trash2 size={16} />
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        ) : (
          <div className="text-neutral-400 text-center py-20 flex flex-col items-center">
            <Music size={48} className="text-neutral-600 mb-3" />
            <p className="text-xl mb-1 font-semibold text-white">This playlist is empty</p>
            <p className="text-sm text-neutral-400">Add songs using search or import from Spotify.</p>
          </div>
        )}
      </div>
    </div>
  );
};

export default PlaylistDetail;
