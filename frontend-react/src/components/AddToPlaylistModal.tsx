import React, { useState, useEffect } from 'react';
import { X, Music, Plus, CheckCircle2, AlertCircle, Loader2 } from 'lucide-react';
import api from '../services/api';
import { useAuth } from '../context/AuthContext';
import type { Song } from '../types';

interface Playlist {
  id: string;
  title: string;
}

interface AddToPlaylistModalProps {
  song: Song | null;
  isOpen: boolean;
  onClose: () => void;
}

const AddToPlaylistModal: React.FC<AddToPlaylistModalProps> = ({ song, isOpen, onClose }) => {
  const { user } = useAuth();
  const [playlists, setPlaylists] = useState<Playlist[]>([]);
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle');
  const [errorMsg, setErrorMsg] = useState('');

  useEffect(() => {
    if (isOpen && user) {
      fetchPlaylists();
    }
  }, [isOpen, user]);

  const fetchPlaylists = async () => {
    try {
      const response = await api.get('/api/playlists/');
      setPlaylists(response.data);
    } catch (error) {
      console.error("Error fetching playlists:", error);
    }
  };

  const handleAddToPlaylist = async (playlistId: string) => {
    if (!song) return;
    setStatus('loading');
    try {
      await api.post(`/api/playlists/${playlistId}/songs`, {
        jiosaavn_song_id: song.id
      });
      setStatus('success');
      setTimeout(() => {
        onClose();
        setStatus('idle');
      }, 1500);
    } catch (error) {
      console.error("Error adding to playlist:", error);
      setStatus('error');
      setErrorMsg("Failed to add song.");
      setTimeout(() => setStatus('idle'), 3000);
    }
  };

  const handleCreateAndAdd = async () => {
    if (!song) return;
    const title = window.prompt("Enter new playlist name:");
    if (!title) return;

    setStatus('loading');
    try {
      const response = await api.post('/api/playlists/', {
        title,
        is_public: false
      });
      const newPlaylistId = response.data.id;
      
      // Now add the song to the newly created playlist
      await api.post(`/api/playlists/${newPlaylistId}/songs`, {
        jiosaavn_song_id: song.id
      });
      
      setStatus('success');
      fetchPlaylists(); // Refresh list for next time
      setTimeout(() => {
        onClose();
        setStatus('idle');
      }, 1500);
    } catch (error) {
      setStatus('error');
      setErrorMsg("Creation failed.");
      setTimeout(() => setStatus('idle'), 3000);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-in fade-in duration-300">
      <div className="bg-[#181818] w-full max-w-sm rounded-2xl shadow-2xl border border-white/5 overflow-hidden animate-in zoom-in-95 duration-300">
        <div className="p-6">
          <div className="flex justify-between items-center mb-6">
            <div>
                <h2 className="text-xl font-bold text-white">Add to Playlist</h2>
                {song && <p className="text-xs text-neutral-400 mt-1 truncate max-w-[200px]">{song.title}</p>}
            </div>
            <button onClick={onClose} className="p-2 hover:bg-neutral-800 rounded-full transition-colors">
              <X size={20} className="text-neutral-400 hover:text-white" />
            </button>
          </div>

          <div className="space-y-2 max-h-[300px] overflow-y-auto pr-1 custom-scrollbar">
            {playlists.length > 0 ? (
              playlists.map((playlist) => (
                <button
                  key={playlist.id}
                  onClick={() => handleAddToPlaylist(playlist.id)}
                  disabled={status === 'loading'}
                  className="w-full flex items-center gap-4 p-3 rounded-xl hover:bg-neutral-800/80 transition-all group border border-transparent hover:border-white/5"
                >
                  <div className="bg-neutral-800 p-2.5 rounded-lg group-hover:bg-neutral-700 transition-colors">
                    <Music size={18} className="text-neutral-500 group-hover:text-green-500" />
                  </div>
                  <span className="font-medium text-neutral-200 text-left truncate flex-1">{playlist.title}</span>
                </button>
              ))
            ) : status !== 'loading' && (
              <div className="text-center py-8">
                <Music size={40} className="mx-auto text-neutral-700 mb-3" />
                <p className="text-neutral-500 text-sm">No playlists yet.</p>
              </div>
            )}
          </div>

          <div className="mt-6 pt-6 border-t border-white/5">
            <button 
                onClick={handleCreateAndAdd}
                disabled={status === 'loading'}
                className="w-full flex items-center justify-center gap-2 py-3 px-4 bg-white text-black rounded-full font-bold text-sm hover:scale-[1.02] active:scale-95 transition-all disabled:opacity-50 disabled:scale-100"
            >
                <Plus size={18} />
                Create New Playlist
            </button>
          </div>

          {/* Feedback Overlays */}
          {status !== 'idle' && (
              <div className="mt-4 animate-in slide-in-from-top-2 duration-300">
                {status === 'loading' && (
                    <div className="flex items-center justify-center gap-2 text-neutral-400 py-2">
                        <Loader2 size={16} className="animate-spin text-green-500" />
                        <span className="text-xs font-semibold">Processing...</span>
                    </div>
                )}
                {status === 'success' && (
                    <div className="flex items-center justify-center gap-2 text-green-500 py-2 bg-green-500/10 rounded-lg">
                        <CheckCircle2 size={16} />
                        <span className="text-xs font-bold">Successfully added!</span>
                    </div>
                )}
                {status === 'error' && (
                    <div className="flex items-center justify-center gap-2 text-red-500 py-2 bg-red-500/10 rounded-lg">
                        <AlertCircle size={16} />
                        <span className="text-xs font-bold">{errorMsg}</span>
                    </div>
                )}
              </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default AddToPlaylistModal;
