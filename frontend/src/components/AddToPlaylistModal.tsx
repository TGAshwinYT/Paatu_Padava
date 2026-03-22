import React, { useState, useEffect } from 'react';
import { X, Music } from 'lucide-react';
import api from '../services/api';
import { useAuth } from '../context/AuthContext';

interface Playlist {
  id: string;
  title: string;
}

interface AddToPlaylistModalProps {
  songId: string;
  isOpen: boolean;
  onClose: () => void;
}

const AddToPlaylistModal: React.FC<AddToPlaylistModalProps> = ({ songId, isOpen, onClose }) => {
  const { user } = useAuth();
  const [playlists, setPlaylists] = useState<Playlist[]>([]);
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle');

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
    setStatus('loading');
    try {
      await api.post(`/api/playlists/${playlistId}/songs`, {
        jiosaavn_song_id: songId
      });
      setStatus('success');
      setTimeout(() => {
        onClose();
        setStatus('idle');
      }, 1500);
    } catch (error) {
      console.error("Error adding to playlist:", error);
      setStatus('error');
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div className="bg-[#181818] w-full max-w-sm rounded-2xl shadow-2xl border border-white/10 overflow-hidden">
        <div className="p-6">
          <div className="flex justify-between items-center mb-6">
            <h2 className="text-xl font-bold text-white">Add to Playlist</h2>
            <button onClick={onClose} className="p-1 hover:bg-neutral-800 rounded-full transition-colors">
              <X size={24} className="text-neutral-400 hover:text-white" />
            </button>
          </div>

          <div className="space-y-4 max-h-[300px] overflow-y-auto pr-2 custom-scrollbar">
            {playlists.length === 0 ? (
              <p className="text-neutral-400 text-sm text-center py-4">No playlists found. Create one in the sidebar!</p>
            ) : (
              playlists.map((playlist: any) => (
                <button
                  key={playlist.id}
                  onClick={() => handleAddToPlaylist(playlist.id)}
                  disabled={status === 'loading'}
                  className="w-full flex items-center gap-4 p-3 rounded-lg hover:bg-neutral-800 transition-colors group"
                >
                  <div className="bg-neutral-800 p-2 rounded group-hover:bg-neutral-700">
                    <Music size={20} className="text-neutral-400 group-hover:text-green-500" />
                  </div>
                  <span className="font-semibold text-white text-left truncate">{playlist.title}</span>
                </button>
              ))
            )}
          </div>

          {status === 'success' && (
             <div className="mt-4 p-3 bg-green-500/20 text-green-500 rounded-lg text-center font-bold text-sm">
                Added successfully!
             </div>
          )}
          {status === 'error' && (
             <div className="mt-4 p-3 bg-red-500/20 text-red-500 rounded-lg text-center font-bold text-sm">
                Error adding track.
             </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default AddToPlaylistModal;
