import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import SongCard from '../components/SongCard';
import type { Song } from '../types';
import { getPlaylistDetail, removeSongFromPlaylist, renamePlaylist, deletePlaylist } from '../services/api';
import { useAuth } from '../context/AuthContext';
import { Music, Trash2, Play, MoreVertical, Edit2 } from 'lucide-react';
import { useAudio } from '../context/AudioContext';

const PlaylistDetail = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [songs, setSongs] = useState<Song[]>([]);
  const [playlistTitle, setPlaylistTitle] = useState('Playlist');
  const [isLoading, setIsLoading] = useState(true);
  const { user } = useAuth();
  const { playContext } = useAudio();
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
      const { title, songs: playlistSongs } = await getPlaylistDetail(id);
      setPlaylistTitle(title);
      setSongs(playlistSongs);
      setIsLoading(false);
    };
    fetchDetail();
  }, [id, user]);

  const handleRemove = async (songId: string) => {
    if (!id) return;
    await removeSongFromPlaylist(id, songId);
    setSongs(prev => prev.filter(s => s.id !== songId));
  };

  const handlePlayAll = () => {
    if (songs.length > 0) {
      playContext(songs[0], songs);
    }
  };

  const handleRename = async () => {
    if (!id || !editTitle.trim()) return;
    try {
      await renamePlaylist(id, editTitle);
      setPlaylistTitle(editTitle);
      setShowRenameModal(false);
    } catch (error) {
       alert("Failed to rename playlist");
    }
  };

  const handleDelete = async () => {
    if (!id) return;
    try {
      await deletePlaylist(id);
      navigate('/');
    } catch (error) {
       alert("Failed to delete playlist");
    }
  };

  if (isLoading) {
    return (
      <div className="flex flex-col gap-8 pb-24 items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-white"></div>
      </div>
    );
  }

  if (!user) {
    navigate('/login');
    return null;
  }

  return (
    <div className="flex flex-col gap-8 pb-24">
      <div className="flex items-center gap-6 mb-8 flex-wrap md:flex-nowrap">
        <div className="w-52 h-52 bg-neutral-800 rounded-md shadow-2xl flex items-center justify-center">
            <Music size={100} className="text-neutral-600" />
        </div>
        <div className="flex flex-col gap-4 flex-1">
            <span className="text-xs uppercase font-bold tracking-widest text-neutral-400">Playlist</span>
            <h1 className="text-5xl md:text-7xl font-bold text-white">{playlistTitle}</h1>
            <div className="flex items-center gap-2">
                <span className="text-sm font-semibold opacity-80">{user.username} • {songs.length} songs</span>
            </div>
            <div className="flex items-center gap-4 mt-2">
                <button 
                  onClick={handlePlayAll}
                  className="bg-green-500 text-black p-4 rounded-full hover:scale-105 transition shadow-lg flex items-center justify-center"
                >
                  <Play fill="currentColor" size={24} />
                </button>

                <div className="relative">
                   <button 
                     onClick={() => setShowMenu(!showMenu)}
                     className="p-3 text-neutral-400 hover:text-white transition-colors"
                   >
                     <MoreVertical size={28} />
                   </button>

                   {showMenu && (
                      <div className="absolute top-full left-0 mt-2 w-48 bg-[#282828] rounded-lg shadow-2xl border border-white/10 py-1 z-50 animate-in slide-in-from-top-2 duration-200">
                         <button 
                           onClick={() => {
                             setEditTitle(playlistTitle);
                             setShowRenameModal(true);
                             setShowMenu(false);
                           }}
                           className="w-full flex items-center gap-3 px-4 py-3 text-sm text-neutral-300 hover:bg-neutral-700 hover:text-white transition-colors"
                         >
                           <Edit2 size={16} />
                           Rename Playlist
                         </button>
                         <button 
                           onClick={() => {
                             setShowDeleteConfirm(true);
                             setShowMenu(false);
                           }}
                           className="w-full flex items-center gap-3 px-4 py-3 text-sm text-red-400 hover:bg-red-500 hover:text-white transition-colors border-t border-white/5"
                         >
                           <Trash2 size={16} />
                           Delete Playlist
                         </button>
                      </div>
                   )}
                </div>
            </div>
        </div>
      </div>

      {/* Rename Modal */}
      {showRenameModal && (
         <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
            <div className="bg-[#282828] w-full max-w-sm rounded-2xl p-6 shadow-2xl border border-white/10">
               <h2 className="text-xl font-bold mb-6">Rename Playlist</h2>
               <input 
                 type="text"
                 value={editTitle}
                 onChange={(e) => setEditTitle(e.target.value)}
                 className="w-full bg-neutral-800 text-white p-4 rounded-lg mb-6 focus:outline-none focus:ring-2 focus:ring-green-500"
                 placeholder="New playlist name"
                 autoFocus
               />
               <div className="flex justify-end gap-4">
                  <button onClick={() => setShowRenameModal(false)} className="px-6 py-2 text-neutral-400 font-bold hover:text-white transition">Cancel</button>
                  <button onClick={handleRename} className="px-6 py-2 bg-green-500 text-black rounded-full font-bold hover:scale-105 transition">Save</button>
               </div>
            </div>
         </div>
      )}

      {/* Delete Confirmation */}
      {showDeleteConfirm && (
         <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
            <div className="bg-[#282828] w-full max-w-sm rounded-2xl p-6 shadow-2xl border border-white/10 text-center">
               <div className="w-16 h-16 bg-red-500/20 text-red-500 rounded-full flex items-center justify-center mx-auto mb-6">
                  <Trash2 size={32} />
               </div>
               <h2 className="text-xl font-bold mb-2">Delete Playlist?</h2>
               <p className="text-neutral-400 text-sm mb-8">This will remove "{playlistTitle}" forever. You can't undo this action.</p>
               <div className="flex flex-col gap-2">
                  <button onClick={handleDelete} className="w-full py-3 bg-red-500 text-white rounded-full font-bold hover:bg-red-600 transition">Delete</button>
                  <button onClick={() => setShowDeleteConfirm(false)} className="w-full py-3 text-neutral-400 font-bold hover:text-white transition">Cancel</button>
               </div>
            </div>
         </div>
      )}

      <div className="flex flex-col gap-1">
        {songs.length > 0 ? (
          songs.map((song) => (
             <div key={song.id} className="group relative">
                <SongCard song={song} context={songs} />
                <button 
                  onClick={(e) => {
                    e.stopPropagation();
                    handleRemove(song.id);
                  }}
                  className="absolute bottom-4 left-4 opacity-0 group-hover:opacity-100 p-2 bg-red-500/20 text-red-500 rounded-full hover:bg-red-500 hover:text-white transition-all z-10"
                  title="Remove from playlist"
                >
                  <Trash2 size={16} />
                </button>
             </div>
          ))
        ) : (
          <div className="text-neutral-400 text-center mt-20">
            <p className="text-xl mb-2 font-semibold">This playlist is empty.</p>
            <p className="text-sm">Find some great music to add!</p>
          </div>
        )}
      </div>
    </div>
  );
};

export default PlaylistDetail;
