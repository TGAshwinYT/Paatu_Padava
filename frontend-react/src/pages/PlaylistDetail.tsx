import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import SongCard from '../components/SongCard';
import type { Song } from '../types';
import { getPlaylistDetail, removeSongFromPlaylist, renamePlaylist, deletePlaylist } from '../services/api';
import { saveCollectionPlay } from '../utils/historyUtils';
import { useAuth } from '../context/AuthContext';
import { Music, Trash2, Play, MoreVertical, Edit2, ArrowLeft } from 'lucide-react';
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
    <div className="flex flex-col min-h-full bg-black">
      {/* Back Button */}
      <button 
        onClick={() => navigate(-1)}
        className="fixed top-6 left-6 z-50 p-2.5 bg-black/40 backdrop-blur-md rounded-full text-white hover:bg-black/60 transition-all border border-white/10 active:scale-90"
      >
        <ArrowLeft size={24} strokeWidth={2.5} />
      </button>

      {/* Hero Header */}
      <div 
        className="relative pt-12 pb-8 px-6 flex flex-col items-center gap-6 transition-all duration-700 overflow-hidden"
        style={{ 
          background: `linear-gradient(to bottom, #1db95433 0%, #000 100%)`,
          minHeight: '55vh'
        }}
      >
        {/* Top Spacer for Fixed Back Button */}
        <div className="h-6 w-full" />

        {/* Big Playlist Cover */}
        <div className="w-[85%] max-w-[300px] aspect-square flex-shrink-0 shadow-[0_20px_50px_rgba(0,0,0,0.8)] rounded-lg overflow-hidden transform hover:scale-[1.02] transition-all duration-500 border border-white/5 bg-neutral-900 flex items-center justify-center">
          {songs.length > 0 ? (
            <img src={songs[0].coverUrl} className="w-full h-full object-cover" alt="" />
          ) : (
            <Music size={120} className="text-neutral-700" />
          )}
        </div>

        {/* Playlist Details Block */}
        <div className="flex flex-col items-start w-full px-2 mt-4">
          <h1 className="text-3xl font-black text-white mb-2 leading-tight tracking-tight">
            {playlistTitle}
          </h1>
          <div className="flex items-center gap-2 mb-4 group cursor-pointer">
             <div className="w-6 h-6 rounded-full overflow-hidden bg-neutral-800 flex items-center justify-center">
                <Music size={12} className="text-neutral-500" />
             </div>
             <p className="text-sm text-neutral-300 font-bold">
               {user.username}
             </p>
          </div>
          
          <div className="flex items-center gap-2 text-[12px] font-bold text-neutral-400 uppercase tracking-wider">
            <span>Playlist</span>
            <span className="text-neutral-600">•</span>
            <span>{songs.length} tracks</span>
          </div>
        </div>
      </div>

      {/* Persistent Content Area */}
      <div className="flex-1 bg-black px-6 pb-12">
        {/* Action Row */}
        <div className="flex items-center justify-between py-6">
           <div className="flex items-center gap-6">
              <button 
                onClick={handlePlayAll}
                className="w-14 h-14 bg-[#1ed760] rounded-full text-black flex items-center justify-center hover:scale-110 active:scale-95 transition-all shadow-xl"
              >
                <Play size={24} fill="black" className="ml-1" />
              </button>
              
              <div className="relative">
                 <button 
                   onClick={() => setShowMenu(!showMenu)}
                   className="text-neutral-400 hover:text-white transition-all transform active:scale-90"
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
                <SongCard 
                   song={song} 
                   context={songs} 
                   onPlay={() => {
                     if (id) {
                       saveCollectionPlay({
                         id: id,
                         title: playlistTitle,
                         coverUrl: songs[0]?.coverUrl || '',
                         type: 'playlist'
                       });
                     }
                   }}
                 />
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
