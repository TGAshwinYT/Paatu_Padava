import React, { useState, useEffect } from 'react';
import { Home, Search, Library, Music, Plus, Heart, Clock, PanelLeftClose, PanelLeftOpen, User as UserIcon } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import api, { getFollowedArtists } from '../services/api';

interface Playlist {
  id: string; 
  title: string;
}

interface SidebarProps {
}

const Sidebar: React.FC<SidebarProps> = () => {
  const { user, openLibraryAuthModal } = useAuth();
  const navigate = useNavigate();
  const [playlists, setPlaylists] = useState<Playlist[]>([]);
  const [followedArtists, setFollowedArtists] = useState<any[]>([]);
  const [favoriteArtists, setFavoriteArtists] = useState<{id: string, name: string, image: string}[]>([]);
  const [isCollapsed, setIsCollapsed] = useState(false);

  useEffect(() => {
    if (user) {
      fetchPlaylists();
      fetchFollowedArtists();
      fetchFavoriteArtists();
    } else {
      setPlaylists([]);
      setFollowedArtists([]);
      setFavoriteArtists([]);
    }
  }, [user]);

  const fetchFavoriteArtists = async () => {
    try {
      const response = await api.get('/api/auth/me/artists-details');
      setFavoriteArtists(response.data);
    } catch (error) {
      console.error("Error fetching favorite artists details:", error);
    }
  };

  const fetchFollowedArtists = async () => {
    try {
      const data = await getFollowedArtists();
      setFollowedArtists(data);
    } catch (error) {
      console.error("Error fetching followed artists:", error);
    }
  };

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
      openLibraryAuthModal();
      return;
    }

    const title = window.prompt("Enter Playlist Name", `My Playlist #${playlists.length + 1}`);
    if (!title) return; 

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

  const toggleCollapse = () => setIsCollapsed(!isCollapsed);

  return (
    <aside className={`hidden md:flex flex-col gap-2 h-full transition-all duration-300 ease-in-out ${isCollapsed ? 'w-20' : 'w-64'}`}>
      <div className="bg-[#121212] rounded-xl p-5 flex flex-col gap-6">
        <div className={`flex items-center gap-2 text-white px-2 overflow-hidden transition-all duration-300 ${isCollapsed ? 'justify-center' : ''}`}>
          <div className="bg-white p-1 rounded-full text-black flex-shrink-0">
            <Music size={24} />
          </div>
          {!isCollapsed && <span className="font-bold text-xl truncate animate-in fade-in duration-500">Paaatu_Padava</span>}
        </div>

        <nav className="flex flex-col gap-4">
          <Link to="/" className={`flex items-center gap-4 text-neutral-400 hover:text-white transition-all font-semibold px-2 ${isCollapsed ? 'justify-center' : ''}`}>
            <Home size={28} className="flex-shrink-0" />
            {!isCollapsed && <span className="animate-in fade-in slide-in-from-left-2 duration-300">Home</span>}
          </Link>
          <Link to="/search" className={`flex items-center gap-4 text-neutral-400 hover:text-white transition-all font-semibold px-2 ${isCollapsed ? 'justify-center' : ''}`}>
            <Search size={28} className="flex-shrink-0" />
            {!isCollapsed && <span className="animate-in fade-in slide-in-from-left-2 duration-300">Search</span>}
          </Link>
        </nav>
      </div>

      <div className="bg-[#121212] rounded-xl flex-1 flex flex-col gap-2 overflow-hidden">
        <div className="p-5 flex flex-col gap-6 h-full">
          <div className={`flex items-center justify-between text-neutral-400 px-2 ${isCollapsed ? 'flex-col gap-4' : ''}`}>
            <div 
                onClick={toggleCollapse}
                className="flex items-center gap-4 font-semibold hover:text-white transition-colors cursor-pointer"
            >
              {isCollapsed ? <PanelLeftOpen size={28} className="animate-in zoom-in duration-300" /> : <Library size={28} />}
              {!isCollapsed && <span className="animate-in fade-in slide-in-from-left-2 duration-300">Your Library</span>}
            </div>
            <div className="flex items-center gap-2">
                {!isCollapsed && (
                    <>
                        <Plus 
                            size={20} 
                            className="hover:text-white cursor-pointer animate-in fade-in zoom-in duration-300" 
                            onClick={handleCreatePlaylist}
                        />
                        <button onClick={toggleCollapse} className="hover:text-white transition-colors">
                            <PanelLeftClose size={20} />
                        </button>
                    </>
                )}
            </div>
          </div>

          <div className="flex flex-col gap-2 mt-2 overflow-y-auto max-h-[60vh] scrollbar-hide">
            <div 
              onClick={handleCreatePlaylist}
              className={`flex items-center gap-4 text-neutral-400 hover:text-white transition-all font-semibold p-2 rounded-lg hover:bg-[#282828] cursor-pointer ${isCollapsed ? 'justify-center' : ''}`}
            >
              <div className="bg-gradient-to-br from-indigo-700 to-indigo-300 p-1.5 rounded-sm flex-shrink-0">
                <Plus size={16} className="text-white" />
              </div>
              {!isCollapsed && <span className="truncate text-sm animate-in fade-in slide-in-from-left-2 duration-300">Create Playlist</span>}
            </div>

            <div 
              onClick={() => user ? navigate('/library') : openLibraryAuthModal()}
              className={`flex items-center gap-4 text-neutral-400 hover:text-white transition-all font-semibold p-2 rounded-lg hover:bg-[#282828] cursor-pointer ${isCollapsed ? 'justify-center' : ''}`}
            >
              <div className="bg-gradient-to-br from-purple-800 to-pink-300 p-1.5 rounded-sm flex-shrink-0">
                <Heart size={16} className="text-white fill-current" />
              </div>
              {!isCollapsed && <span className="truncate text-sm animate-in fade-in slide-in-from-left-2 duration-300">Liked Songs</span>}
            </div>

            <div 
              onClick={() => user ? navigate('/history') : openLibraryAuthModal()}
              className={`flex items-center gap-4 text-neutral-400 hover:text-white transition-all font-semibold p-2 rounded-lg hover:bg-[#282828] cursor-pointer ${isCollapsed ? 'justify-center' : ''}`}
            >
              <div className="bg-gradient-to-br from-purple-900 to-black p-1.5 rounded-sm flex-shrink-0">
                <Clock size={16} className="text-white" />
              </div>
              {!isCollapsed && <span className="truncate text-sm animate-in fade-in slide-in-from-left-2 duration-300">Recently Listened</span>}
            </div>

            {user && (
              <>
                {followedArtists.length > 0 && (
                  <div className={`mt-4 mb-2 ${isCollapsed ? 'flex flex-col items-center' : ''}`}>
                    {!isCollapsed && <div className="text-[10px] uppercase font-bold text-neutral-500 px-3 mb-2 tracking-widest animate-in fade-in duration-300">Favorite Artists</div>}
                    <div className="flex flex-col gap-1 w-full">
                      {followedArtists.map((artist) => (
                        <Link 
                          key={artist.id}
                          to={`/artist/${artist.id}`}
                          title={isCollapsed ? artist.name : ""}
                          className={`flex items-center gap-3 text-neutral-400 hover:text-green-500 hover:bg-neutral-800 transition-all font-semibold p-2 rounded-lg cursor-pointer group ${isCollapsed ? 'justify-center' : ''}`}
                        >
                          <div className="w-8 h-8 rounded-full bg-neutral-800 flex items-center justify-center flex-shrink-0 overflow-hidden ring-1 ring-white/10 group-hover:ring-green-500/50 transition-all">
                            {artist.imageUrl ? (
                              <img src={artist.imageUrl} className="w-full h-full object-cover" alt={artist.name} loading="lazy" />
                            ) : (
                              <UserIcon size={14} />
                            )}
                          </div>
                          {!isCollapsed && <span className="truncate text-sm animate-in fade-in duration-300">{artist.name}</span>}
                        </Link>
                      ))}
                    </div>
                  </div>
                )}

                {playlists.map((playlist) => (
                  <Link 
                    key={playlist.id}
                    to={`/playlist/${playlist.id}`}
                    title={isCollapsed ? playlist.title : ""}
                    className={`flex items-center gap-4 text-neutral-400 hover:text-white transition-all font-semibold p-2 rounded-lg hover:bg-[#282828] cursor-pointer truncate ${isCollapsed ? 'justify-center' : ''}`}
                  >
                    <div className="bg-neutral-800 p-2 rounded-md flex-shrink-0">
                      <Music size={20} />
                    </div>
                    {!isCollapsed && <span className="truncate text-sm animate-in fade-in duration-300">{playlist.title}</span>}
                  </Link>
                ))}

                {favoriteArtists.length > 0 && (
                  <div className={`${isCollapsed ? 'flex flex-col items-center mt-6' : 'mt-6'}`}>
                    {!isCollapsed && <p className="text-xs font-semibold text-neutral-400 tracking-wider mb-4 px-2 animate-in fade-in duration-300">YOUR ARTISTS</p>}
                    <div className="flex flex-col gap-1 w-full">
                      {favoriteArtists.map((artist, index) => (
                        <Link 
                          key={artist.id || index}
                          to={`/artist/${artist.id || artist.name}`}
                          title={isCollapsed ? artist.name : ""}
                          className={`flex items-center gap-3 py-2 text-neutral-400 hover:text-white transition-all cursor-pointer group px-2 ${isCollapsed ? 'justify-center' : ''}`}
                        >
                          <img 
                            src={artist.image || 'https://via.placeholder.com/150'} 
                            alt={artist.name} 
                            className="w-8 h-8 rounded-full object-cover shadow-md group-hover:shadow-lg transition-shadow" 
                            loading="lazy"
                          />
                          {!isCollapsed && <span className="text-sm font-medium truncate animate-in fade-in duration-300">{artist.name}</span>}
                        </Link>
                      ))}
                    </div>
                  </div>
                )}
              </>
            )}
          </div>
        </div>
      </div>
    </aside>
  );
};

export default Sidebar;
