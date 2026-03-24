import React, { useState, useEffect } from 'react';
import { Home, Search, Library, Music, Plus, Heart, Clock } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import api, { getFollowedArtists } from '../services/api';
import { User as UserIcon } from 'lucide-react';

interface Playlist {
  id: string; // Updated to string for UUID
  title: string;
}

interface SidebarProps {
}

const Sidebar: React.FC<SidebarProps> = () => {
  const { user, logout, openLibraryAuthModal } = useAuth();
  const navigate = useNavigate();
  const [playlists, setPlaylists] = useState<Playlist[]>([]);
  const [followedArtists, setFollowedArtists] = useState<any[]>([]);
  const [favoriteArtists, setFavoriteArtists] = useState<{id: string, name: string, image: string}[]>([]);

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

          {user && (
            <div className="bg-[#1c1c1c] rounded-lg p-4 flex flex-col gap-4">
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
            </div>
          )}
          
          <div className="flex flex-col gap-2 mt-2 overflow-y-auto max-h-[60vh] scrollbar-hide">
            {/* Core Actions (Visible to All) */}
            <div 
              onClick={handleCreatePlaylist}
              className="flex items-center gap-4 text-neutral-400 hover:text-white transition-colors font-semibold p-2 rounded-lg hover:bg-[#282828] cursor-pointer"
            >
              <div className="bg-gradient-to-br from-indigo-700 to-indigo-300 p-1.5 rounded-sm flex-shrink-0">
                <Plus size={16} className="text-white" />
              </div>
              <span>Create Playlist</span>
            </div>

            <div 
              onClick={() => user ? navigate('/library') : openLibraryAuthModal()}
              className="flex items-center gap-4 text-neutral-400 hover:text-white transition-colors font-semibold p-2 rounded-lg hover:bg-[#282828] cursor-pointer"
            >
              <div className="bg-gradient-to-br from-purple-800 to-pink-300 p-1.5 rounded-sm flex-shrink-0">
                <Heart size={16} className="text-white fill-current" />
              </div>
              <span>Liked Songs</span>
            </div>

            <div 
              onClick={() => user ? navigate('/history') : openLibraryAuthModal()}
              className="flex items-center gap-4 text-neutral-400 hover:text-white transition-colors font-semibold p-2 rounded-lg hover:bg-[#282828] cursor-pointer"
            >
              <div className="bg-gradient-to-br from-purple-900 to-black p-1.5 rounded-sm flex-shrink-0">
                <Clock size={16} className="text-white" />
              </div>
              <span>Recently Listened</span>
            </div>

            {/* User-Specific Content (Restricted) */}
            {user && (
              <>
                {/* Favorite Artists */}
                {followedArtists.length > 0 && (
                  <div className="mt-4 mb-2">
                    <div className="text-[10px] uppercase font-bold text-neutral-500 px-3 mb-2 tracking-widest">Favorite Artists</div>
                    <div className="flex flex-col gap-1">
                      {followedArtists.map((artist) => (
                        <Link 
                          key={artist.id}
                          to={`/artist/${artist.id}`}
                          className="flex items-center gap-3 text-neutral-400 hover:text-green-500 hover:bg-neutral-800 transition-all font-semibold p-2 rounded-lg cursor-pointer group"
                        >
                          <div className="w-8 h-8 rounded-full bg-neutral-800 flex items-center justify-center flex-shrink-0 overflow-hidden ring-1 ring-white/10 group-hover:ring-green-500/50 transition-all">
                            {artist.imageUrl ? (
                              <img src={artist.imageUrl} className="w-full h-full object-cover" alt={artist.name} />
                            ) : (
                              <UserIcon size={14} />
                            )}
                          </div>
                          <span className="truncate text-sm">{artist.name}</span>
                        </Link>
                      ))}
                    </div>
                  </div>
                )}

                {/* Playlists List */}
                {playlists.map((playlist) => (
                  <Link 
                    key={playlist.id}
                    to={`/playlist/${playlist.id}`}
                    className="flex items-center gap-4 text-neutral-400 hover:text-white transition-colors font-semibold p-2 rounded-lg hover:bg-[#282828] cursor-pointer truncate"
                  >
                    <div className="bg-neutral-800 p-2 rounded-md flex-shrink-0">
                      <Music size={20} />
                    </div>
                    <span className="truncate">{playlist.title}</span>
                  </Link>
                ))}

                {/* YOUR ARTISTS Section */}
                {favoriteArtists.length > 0 && (
                  <>
                    <p className="text-xs font-semibold text-neutral-400 tracking-wider mt-6 mb-4 px-2">YOUR ARTISTS</p>
                    <div className="flex flex-col gap-1">
                      {favoriteArtists.map((artist, index) => (
                        <Link 
                          key={artist.id || index}
                          to={`/artist/${artist.id || artist.name}`}
                          className="flex items-center gap-3 py-2 text-neutral-400 hover:text-white transition-colors cursor-pointer group px-2"
                        >
                          <img 
                            src={artist.image || 'https://via.placeholder.com/150'} 
                            alt={artist.name} 
                            className="w-8 h-8 rounded-full object-cover shadow-md group-hover:shadow-lg transition-shadow" 
                          />
                          <span className="text-sm font-medium truncate">{artist.name}</span>
                        </Link>
                      ))}
                    </div>
                  </>
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
