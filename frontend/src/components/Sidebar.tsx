import React, { useState, useEffect } from 'react';
import { Home, Search, Library, Music, Plus, Heart, Sparkles, Clock } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import api from '../services/api';

interface Playlist {
  id: string; // Updated to string for UUID
  title: string;
}

interface SidebarProps {
  onLogin?: () => void;
}

const Sidebar: React.FC<SidebarProps> = ({ onLogin }) => {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const [playlists, setPlaylists] = useState<Playlist[]>([]);

  useEffect(() => {
    if (user) {
      fetchPlaylists();
    } else {
      setPlaylists([]);
    }
  }, [user]);

  const fetchPlaylists = async () => {
    try {
      const response = await api.get('/api/playlists/');
      setPlaylists(response.data);
    } catch (error) {
      console.error("Error fetching playlists:", error);
    }
  };

  const handleCreatePlaylist = async () => {
    if (!user) {
      if (onLogin) onLogin();
      return;
    }

    const title = window.prompt("Enter Playlist Name", `My Playlist #${playlists.length + 1}`);
    if (!title) return; // Cancelled

    try {
      await api.post('/api/playlists/', {
        title,
        is_public: false
      });
      fetchPlaylists();
    } catch (error) {
      console.error("Error creating playlist:", error);
    }
  };

  return (
    <aside className="hidden md:flex flex-col w-64 gap-2 h-full">
      <div className="bg-[#121212] rounded-xl p-5 flex flex-col gap-6">
        <div className="flex items-center gap-2 text-white px-2">
          <div className="bg-white p-1 rounded-full text-black">
            <Music size={24} />
          </div>
          <span className="font-bold text-xl">Paaatu_Padava</span>
        </div>

        <nav className="flex flex-col gap-4">
          <Link to="/" className="flex items-center gap-4 text-neutral-400 hover:text-white transition-colors font-semibold px-2">
            <Home size={28} />
            <span>Home</span>
          </Link>
          <Link to="/search" className="flex items-center gap-4 text-neutral-400 hover:text-white transition-colors font-semibold px-2">
            <Search size={28} />
            <span>Search</span>
          </Link>
        </nav>
      </div>

      <div className="bg-[#121212] rounded-xl flex-1 flex flex-col gap-2 overflow-hidden">
        <div className="p-5 flex flex-col gap-6 h-full">
          <div className="flex items-center justify-between text-neutral-400 px-2">
            <div className="flex items-center gap-4 font-semibold hover:text-white transition-colors">
              <Library size={28} />
              <span>Your Library</span>
            </div>
            <Plus 
              size={20} 
              className="hover:text-white cursor-pointer" 
              onClick={handleCreatePlaylist}
            />
          </div>

          <div className="bg-[#1c1c1c] rounded-lg p-4 flex flex-col gap-4">
            {user ? (
              <div className="space-y-4">
                <div className="text-xs text-gray-400 font-bold uppercase tracking-wider">Account</div>
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-full bg-green-500 flex items-center justify-center text-black font-bold text-xs ring-2 ring-white/10">
                    {user.username[0].toUpperCase()}
                  </div>
                  <div className="text-sm truncate font-bold text-white tracking-tight">{user.username}</div>
                </div>
                <div className="flex flex-col gap-2">
                  <button 
                    onClick={() => navigate('/onboarding')}
                    className="bg-neutral-800 text-white text-xs font-bold py-2 px-4 rounded-full hover:bg-neutral-700 transition-colors flex items-center justify-center gap-2"
                  >
                    <Sparkles size={12} className="text-green-500" />
                    Update Preferences
                  </button>
                  <button 
                    onClick={() => navigate('/settings')}
                    className="bg-neutral-800 text-white text-xs font-bold py-2 px-4 rounded-full hover:bg-neutral-700 transition-colors flex items-center justify-center gap-2"
                  >
                    Settings
                  </button>
                  <button 
                    onClick={logout}
                    className="bg-neutral-800 text-white text-xs font-bold py-2 px-4 rounded-full hover:bg-neutral-700 transition-colors"
                  >
                    Sign Out
                  </button>
                </div>
              </div>
            ) : (
              <div className="space-y-4">
                <p className="text-sm font-bold">Sign in to save songs</p>
                <p className="text-xs text-gray-400 leading-relaxed">It's free and always will be.</p>
                <button 
                  onClick={onLogin}
                  className="bg-white text-black text-sm font-bold py-2 px-4 rounded-full hover:scale-105 transition-transform"
                >
                  Log In
                </button>
              </div>
            )}
          </div>
          
          <div className="flex flex-col gap-2 mt-2 overflow-y-auto max-h-[40vh] scrollbar-hide">
             <div 
               onClick={handleCreatePlaylist}
               className="flex items-center gap-4 text-neutral-400 hover:text-white transition-colors font-semibold p-2 rounded-lg hover:bg-[#282828] cursor-pointer"
             >
               <div className="bg-gradient-to-br from-indigo-700 to-indigo-300 p-1.5 rounded-sm">
                 <Plus size={16} className="text-white" />
               </div>
               <span>Create Playlist</span>
             </div>
             <Link 
               to="/library"
               className="flex items-center gap-4 text-neutral-400 hover:text-white transition-colors font-semibold p-2 rounded-lg hover:bg-[#282828] cursor-pointer"
             >
               <div className="bg-gradient-to-br from-purple-800 to-pink-300 p-1.5 rounded-sm">
                 <Heart size={16} className="text-white fill-current" />
               </div>
               <span>Liked Songs</span>
             </Link>

             <Link 
               to="/history"
               className="flex items-center gap-4 text-neutral-400 hover:text-white transition-colors font-semibold p-2 rounded-lg hover:bg-[#282828] cursor-pointer"
             >
               <div className="bg-gradient-to-br from-purple-900 to-black p-1.5 rounded-sm">
                 <Clock size={16} className="text-white" />
               </div>
               <span>Recently Listened</span>
             </Link>

             {/* Playlists List */}
             {playlists.map((playlist) => (
               <Link 
                 key={playlist.id}
                 to={`/playlist/${playlist.id}`}
                 className="flex items-center gap-4 text-neutral-400 hover:text-white transition-colors font-semibold p-2 rounded-lg hover:bg-[#282828] cursor-pointer truncate"
               >
                 <div className="bg-neutral-800 p-2 rounded-md">
                   <Music size={20} />
                 </div>
                 <span className="truncate">{playlist.title}</span>
               </Link>
             ))}
          </div>
        </div>
      </div>
    </aside>
  );
};

export default Sidebar;
