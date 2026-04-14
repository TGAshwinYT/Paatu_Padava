import React, { useState, useEffect } from 'react';
import LikedSongs from '../LikedSongs';
import api, { getFollowedArtists } from '../../services/api';
import { useAuth } from '../../context/AuthContext';
import { Music, Plus, Heart, User as UserIcon, PlusCircle } from 'lucide-react';
import { Link } from 'react-router-dom';

const MobileLibrary: React.FC = () => {
  const { user, openLibraryAuthModal } = useAuth();
  const [activeTab, setActiveTab] = useState<'all' | 'liked'>('all');
  const [playlists, setPlaylists] = useState<any[]>([]);
  const [followedArtists, setFollowedArtists] = useState<any[]>([]);
  const [favoriteArtists, setFavoriteArtists] = useState<any[]>([]);
  const [filter, setFilter] = useState<'all' | 'playlists' | 'artists'>('all');

  useEffect(() => {
    if (user) {
      fetchPlaylists();
      fetchFollowedArtists();
      fetchFavoriteArtists();
    }
  }, [user]);

  const fetchFavoriteArtists = async () => {
    try {
      const response = await api.get('/api/auth/me/artists-details');
      setFavoriteArtists(response.data);
    } catch (error) {
      console.error(error);
    }
  };

  const fetchFollowedArtists = async () => {
    try {
      const data = await getFollowedArtists();
      setFollowedArtists(data);
    } catch (error) {
      console.error(error);
    }
  };

  const fetchPlaylists = async () => {
    try {
      const response = await api.get('/api/playlists/');
      setPlaylists(response.data);
    } catch (error) {
      console.error(error);
    }
  };

  const handleCreatePlaylist = async () => {
    if (!user) {
      openLibraryAuthModal();
      return;
    }
    const title = window.prompt("Enter Playlist Name", `My Playlist ${playlists.length + 1}`);
    if (!title) return; 
    try {
      await api.post('/api/playlists/', { title, is_public: false });
      fetchPlaylists();
    } catch (error) {
      console.error(error);
    }
  };

  if (activeTab === 'liked') {
    return (
      <div className="pb-32 h-full flex flex-col p-4 animate-in fade-in zoom-in-95 duration-300">
        <div className="pt-8 mb-4">
           <button onClick={() => setActiveTab('all')} className="text-sm font-bold text-neutral-400 hover:text-white transition-colors flex items-center gap-2">
             &larr; Back to Library
           </button>
        </div>
        <LikedSongs />
      </div>
    );
  }

  const allArtists = [...followedArtists, ...favoriteArtists].filter((v,i,a)=>a.findIndex(t=>(t.id === v.id))===i);

  return (
    <div className="p-6 pt-12 pb-32 text-white min-h-screen animate-in fade-in duration-500">
      <h1 className="text-3xl font-black mb-6 tracking-tight">Your Library</h1>

      {/* Filter Chips */}
      <div className="flex gap-3 mb-8 overflow-x-auto no-scrollbar pb-2">
        <button 
          onClick={() => setFilter('all')}
          className={`px-5 py-2 rounded-full text-sm font-bold whitespace-nowrap transition-colors border border-white/10 ${filter === 'all' ? 'bg-white text-black' : 'bg-neutral-800 text-white hover:bg-neutral-700'}`}
        >
          All
        </button>
        <button 
          onClick={() => setFilter('playlists')}
          className={`px-5 py-2 rounded-full text-sm font-bold whitespace-nowrap transition-colors border border-white/10 ${filter === 'playlists' ? 'bg-white text-black' : 'bg-neutral-800 text-white hover:bg-neutral-700'}`}
        >
          Playlists
        </button>
        <button 
          onClick={() => setFilter('artists')}
          className={`px-5 py-2 rounded-full text-sm font-bold whitespace-nowrap transition-colors border border-white/10 ${filter === 'artists' ? 'bg-white text-black' : 'bg-neutral-800 text-white hover:bg-neutral-700'}`}
        >
          Artists
        </button>
      </div>

      <div className="flex flex-col gap-8">
          
        {/* Liked & Create Playlist Buttons */}
        {(filter === 'all' || filter === 'playlists') && (
            <div className="grid grid-cols-2 gap-4 animate-in slide-in-from-bottom flex-shrink-0">
               <div 
                 onClick={() => {
                   if(user) setActiveTab('liked');
                   else openLibraryAuthModal();
                 }}
                 className="bg-gradient-to-br from-purple-800 to-pink-300 p-4 rounded-xl flex flex-col gap-3 cursor-pointer hover:scale-[1.02] active:scale-95 transition-transform shadow-lg"
               >
                 <Heart size={28} className="text-white fill-current" />
                 <span className="font-bold text-sm">Liked Songs</span>
               </div>
               
               <div 
                 onClick={handleCreatePlaylist}
                 className="bg-neutral-800 p-4 rounded-xl flex flex-col gap-3 cursor-pointer hover:scale-[1.02] active:scale-95 transition-transform shadow-lg border border-white/5"
               >
                 <Plus size={28} className="text-green-500" />
                 <span className="font-bold text-sm">New Playlist</span>
               </div>
            </div>
        )}

        {/* Playlists List */}
        {(filter === 'all' || filter === 'playlists') && playlists.length > 0 && (
            <div className="flex flex-col gap-3">
              <h2 className="text-lg font-bold">Your Playlists</h2>
              {playlists.map((playlist: any) => (
                <Link 
                  key={playlist.id}
                  to={`/playlist/${playlist.id}`}
                  className="flex items-center gap-4 p-3 rounded-xl bg-neutral-900/50 hover:bg-neutral-800 active:scale-95 transition-all border border-white/5 cursor-pointer"
                >
                  <div className="w-14 h-14 bg-neutral-800 rounded-lg flex items-center justify-center shadow-md flex-shrink-0">
                    <Music size={24} className="text-neutral-500" />
                  </div>
                  <div className="flex flex-col min-w-0">
                     <span className="font-bold text-white truncate text-sm">{playlist.title}</span>
                     <span className="text-xs text-neutral-400">Playlist</span>
                  </div>
                </Link>
              ))}
            </div>
        )}

        {/* Artists List */}
        {(filter === 'all' || filter === 'artists') && (
            <div className="flex flex-col gap-4">
              <div className="flex items-center justify-between">
                 <h2 className="text-lg font-bold">Following</h2>
                 {filter === 'artists' && (
                     <Link to="/local-artists" className="text-xs font-bold text-green-500 uppercase tracking-wider flex items-center gap-1">
                        <PlusCircle size={14} /> Add
                     </Link>
                 )}
              </div>
              
              <div className="flex flex-col gap-2">
                 {allArtists.map((artist) => (
                    <Link 
                       key={artist.id}
                       to={`/artist/${artist.id || artist.name}`}
                       className="flex items-center gap-4 p-3 rounded-xl hover:bg-neutral-800 active:scale-95 transition-all cursor-pointer"
                    >
                       <img 
                          src={artist.image?.[0]?.url || artist.image || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=100&h=100&fit=crop'} 
                          alt={artist.name} 
                          className="w-14 h-14 rounded-full object-cover shadow-md flex-shrink-0" 
                       />
                       <div className="flex flex-col min-w-0">
                          <span className="text-sm font-bold text-white truncate">{artist.name}</span>
                          <span className="text-xs text-neutral-400 uppercase tracking-widest font-semibold mt-0.5">Artist</span>
                       </div>
                    </Link>
                 ))}

                 {allArtists.length === 0 && (
                     <div className="py-12 flex flex-col items-center justify-center text-neutral-500 bg-neutral-900/50 rounded-xl border border-white/5">
                         <UserIcon size={40} className="mb-4 opacity-20" />
                         <p className="font-medium text-sm">You aren't following anyone yet.</p>
                         <Link to="/local-artists" className="mt-5 px-6 py-2 bg-white text-black font-bold rounded-full text-sm">
                             Find Artists
                         </Link>
                     </div>
                 )}
              </div>
            </div>
        )}
      </div>
    </div>
  );
};

export default MobileLibrary;
