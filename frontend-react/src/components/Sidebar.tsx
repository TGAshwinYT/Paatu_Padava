import React, { useState, useEffect } from 'react';
import { Home, Search, Library, Music, Plus, Heart, PanelLeftClose, ArrowDownCircle } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { useAudio } from '../context/AudioContext';
import api from '../services/api';
import ImportSpotifyModal from './ImportSpotifyModal';

interface Playlist {
  id: string; 
  title: string;
  cover_url?: string;
}

interface SidebarProps {
}

const Sidebar: React.FC<SidebarProps> = () => {
  const { user, openLibraryAuthModal } = useAuth();
  const { userPlaylists, refreshPlaylists } = useAudio();
  const navigate = useNavigate();
  const [playlists, setPlaylists] = useState<Playlist[]>([]);
  const [isCollapsed, setIsCollapsed] = useState(false);
  const [showSpotifyModal, setShowSpotifyModal] = useState(false);

  useEffect(() => {
    if (user) {
      refreshPlaylists();
      fetchPlaylists();
    } else {
      setPlaylists([]);
    }
  }, [user]);

  useEffect(() => {
    const handleSync = () => {
      if (user) {
        refreshPlaylists();
        fetchPlaylists();
      }
    };
    window.addEventListener('playlists-updated', handleSync);
    return () => window.removeEventListener('playlists-updated', handleSync);
  }, [user]);

  const fetchPlaylists = async () => {
    try {
      const response = await api.get('/api/playlists/');
      setPlaylists(response.data || []);
    } catch (error) {
      console.error("Error fetching playlists:", error);
    }
  };

  const handleCreatePlaylist = async () => {
    if (!user) {
      openLibraryAuthModal();
      return;
    }

    const currentCount = (userPlaylists && userPlaylists.length > 0 ? userPlaylists.length : playlists.length);
    const title = window.prompt("Enter Playlist Name", `My Playlist #${currentCount + 1}`);
    if (!title) return; 

    try {
      await api.post('/api/playlists/', {
        title,
        is_public: false
      });
      await refreshPlaylists();
      fetchPlaylists();
      window.dispatchEvent(new Event('playlists-updated'));
    } catch (error) {
      console.error("Error creating playlist:", error);
    }
  };

  const toggleCollapse = () => setIsCollapsed(!isCollapsed);

  return (
    <>
    <aside className={`hidden md:flex flex-col gap-2 h-full min-h-0 transition-all duration-300 ease-in-out ${isCollapsed ? 'w-20' : 'w-64'}`}>
      <div className="bg-surface-base rounded-xl p-5 flex flex-col gap-6 flex-shrink-0">
        <div className={`flex items-center gap-2 text-white px-2 overflow-hidden transition-all duration-300 ${isCollapsed ? 'justify-center' : ''}`}>
          <div className="w-8 h-8 rounded-lg flex-shrink-0 overflow-hidden shadow-lg border border-white/10 group-hover:scale-110 transition-transform duration-300">
            <img src="/logo.png" className="w-full h-full object-cover" alt="Logo" />
          </div>
          {!isCollapsed && <span className="font-bold text-xl truncate animate-in fade-in duration-500">Paaatu_Padava</span>}
        </div>

        <nav className="flex flex-col gap-4">
          <Link 
            to="/" 
            title={isCollapsed ? "Home" : ""}
            className={`flex items-center gap-4 text-muted hover:text-white transition-all font-semibold px-2 ${isCollapsed ? 'justify-center' : ''}`}
          >
            <Home size={28} className="flex-shrink-0" />
            {!isCollapsed && <span className="animate-in fade-in slide-in-from-left-2 duration-300">Home</span>}
          </Link>
          <Link 
            to="/search" 
            title={isCollapsed ? "Search" : ""}
            className={`flex items-center gap-4 text-muted hover:text-white transition-all font-semibold px-2 ${isCollapsed ? 'justify-center' : ''}`}
          >
            <Search size={28} className="flex-shrink-0" />
            {!isCollapsed && <span className="animate-in fade-in slide-in-from-left-2 duration-300">Search</span>}
          </Link>
        </nav>
      </div>

      <div className="bg-surface-base rounded-xl flex-1 min-h-0 flex flex-col p-4 gap-4 overflow-hidden">
        <div className={`flex items-center justify-between text-muted px-2 flex-shrink-0 ${isCollapsed ? 'flex-col gap-4 items-center' : ''}`}>
            <div 
                onClick={toggleCollapse}
                title={isCollapsed ? "Expand Library" : "Collapse Library"}
                className={`flex items-center gap-4 font-semibold hover:text-white transition-colors cursor-pointer ${isCollapsed ? 'justify-center w-full' : ''}`}
            >
              <Library size={28} className="flex-shrink-0" />
              {!isCollapsed && <span className="animate-in fade-in slide-in-from-left-2 duration-300">Your Library</span>}
            </div>
            <div className={`flex items-center gap-2 ${isCollapsed ? 'flex-col' : ''}`}>
                <div title="Create Playlist">
                    <Plus 
                        size={20} 
                        className="hover:text-white cursor-pointer transition-colors" 
                        onClick={handleCreatePlaylist}
                    />
                </div>
                {!isCollapsed && (
                    <button onClick={toggleCollapse} className="hover:text-white transition-colors" title="Collapse">
                        <PanelLeftClose size={20} />
                    </button>
                )}
            </div>
          </div>

          <div className="flex-1 min-h-0 flex flex-col gap-1.5 overflow-y-auto overflow-x-hidden pr-1 pb-8 custom-scrollbar">
            <div 
              onClick={() => {
                if (!user) { openLibraryAuthModal(); return; }
                setShowSpotifyModal(true);
              }}
              title={isCollapsed ? "Import from Spotify" : ""}
              className={`flex items-center gap-4 text-muted hover:text-white transition-all font-semibold p-2 rounded-lg hover:bg-surface cursor-pointer ${isCollapsed ? 'justify-center' : ''}`}
            >
              <div className="bg-[#1DB954]/20 p-2 rounded-md flex-shrink-0">
                <svg className="w-5 h-5 text-[#1DB954] fill-current" viewBox="0 0 24 24">
                  <path d="M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm5.502 17.31c-.22.36-.68.472-1.04.252-2.85-1.742-6.438-2.137-10.665-1.17-.412.094-.816-.168-.91-.58-.094-.412.168-.816.58-.91 4.63-1.057 8.59-.61 11.783 1.34.36.22.472.68.252 1.068zm1.47-3.268c-.276.45-.86.59-1.31.314-3.264-2.007-8.24-2.59-12.1-1.417-.506.154-1.043-.136-1.197-.642-.154-.506.136-1.043.642-1.197 4.414-1.34 9.897-.69 13.65 1.62.45.276.59.86.315 1.322zm.126-3.41c-3.916-2.325-10.37-2.54-14.1-1.398-.6.183-1.237-.16-1.42-.76-.183-.6.16-1.237.76-1.42 4.29-1.302 11.41-1.05 15.89 1.61.54.32.72 1.02.4 1.56-.32.54-1.02.72-1.53.408z"/>
                </svg>
              </div>
              {!isCollapsed && <span className="truncate text-sm animate-in fade-in slide-in-from-left-2 duration-300">Import from Spotify</span>}
            </div>

            <div 
              onClick={() => user ? navigate('/library') : openLibraryAuthModal()}
              title={isCollapsed ? "Liked Songs" : ""}
              className={`flex items-center gap-4 text-muted hover:text-white transition-all font-semibold p-2 rounded-lg hover:bg-surface cursor-pointer ${isCollapsed ? 'justify-center' : ''}`}
            >
              <div className="bg-gradient-to-br from-purple-800 to-pink-300 p-2 rounded-md flex-shrink-0">
                <Heart size={20} className="text-white fill-current" />
              </div>
              {!isCollapsed && <span className="truncate text-sm animate-in fade-in slide-in-from-left-2 duration-300">Liked Songs</span>}
            </div>

            <Link 
              to="/downloaded"
              title={isCollapsed ? "Downloaded Songs" : ""}
              className={`flex items-center gap-4 text-muted hover:text-white transition-all font-semibold p-2 rounded-lg hover:bg-surface cursor-pointer ${isCollapsed ? 'justify-center' : ''}`}
            >
              <div className="bg-gradient-to-br from-emerald-600 to-teal-800 p-2 rounded-md flex-shrink-0">
                <ArrowDownCircle size={20} className="text-white" />
              </div>
              {!isCollapsed && <span className="truncate text-sm animate-in fade-in slide-in-from-left-2 duration-300">Downloaded Songs</span>}
            </Link>

            {user && (
              <>
                {((userPlaylists && userPlaylists.length > 0) ? userPlaylists : playlists).map((playlist) => (
                  <Link 
                    key={playlist.id}
                    to={`/playlist/${playlist.id}`}
                    title={playlist.title}
                    className={`flex items-center gap-3 text-muted hover:text-white transition-all font-semibold p-2 rounded-lg hover:bg-surface cursor-pointer truncate ${isCollapsed ? 'justify-center' : ''}`}
                  >
                    <div className="w-9 h-9 bg-neutral-800 rounded-md flex-shrink-0 flex items-center justify-center overflow-hidden border border-white/5 shadow-sm">
                      {playlist.cover_url ? (
                        <img 
                          src={playlist.cover_url} 
                          alt={playlist.title} 
                          className="w-full h-full object-cover" 
                          onError={(e) => { e.currentTarget.style.display = 'none'; }} 
                        />
                      ) : (
                        <Music size={18} className="text-neutral-400" />
                      )}
                    </div>
                    {!isCollapsed && <span className="truncate text-sm animate-in fade-in duration-300">{playlist.title}</span>}
                  </Link>
                ))}
              </>
            )}
          </div>
        </div>
      </aside>
    <ImportSpotifyModal isOpen={showSpotifyModal} onClose={() => setShowSpotifyModal(false)} />
    </>
  );
};

export default Sidebar;
