import React, { useState, useEffect } from 'react';
import LikedSongs from '../LikedSongs';
import api, { getFollowedArtists } from '../../services/api';
import { useAuth } from '../../context/AuthContext';
import { useAudio } from '../../context/AudioContext';
import { Music, Plus, Heart, User as UserIcon, PlusCircle, ArrowDownCircle } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import ImportSpotifyModal from '../../components/ImportSpotifyModal';

const MobileLibrary: React.FC = () => {
  const navigate = useNavigate();
  const { user, openLibraryAuthModal } = useAuth();
  const { userPlaylists, refreshPlaylists } = useAudio();
  const [activeTab, setActiveTab] = useState<'all' | 'liked'>('all');
  const [playlists, setPlaylists] = useState<any[]>([]);
  const [followedArtists, setFollowedArtists] = useState<any[]>([]);
  const [favoriteArtists, setFavoriteArtists] = useState<any[]>([]);
  const [filter, setFilter] = useState<'all' | 'playlists' | 'artists'>('all');
  const [showSpotifyModal, setShowSpotifyModal] = useState(false);

  useEffect(() => {
    if (user) {
      refreshPlaylists();
      fetchPlaylists();
      fetchFollowedArtists();
      fetchFavoriteArtists();
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
      setPlaylists(response.data || []);
    } catch (error) {
      console.error(error);
    }
  };

  const handleCreatePlaylist = async () => {
    if (!user) {
      openLibraryAuthModal();
      return;
    }
    const currentCount = (userPlaylists && userPlaylists.length > 0 ? userPlaylists.length : playlists.length);
    const title = window.prompt("Enter Playlist Name", `My Playlist ${currentCount + 1}`);
    if (!title) return; 
    try {
      await api.post('/api/playlists/', { title, is_public: false });
      await refreshPlaylists();
      fetchPlaylists();
      window.dispatchEvent(new Event('playlists-updated'));
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
    <>
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
          <>
            <div className="grid grid-cols-2 gap-3 animate-in slide-in-from-bottom flex-shrink-0">
               <div 
                 onClick={() => {
                   if(user) setActiveTab('liked');
                   else openLibraryAuthModal();
                 }}
                 className="bg-gradient-to-br from-purple-800 to-pink-500/80 p-4 rounded-xl flex flex-col gap-3 cursor-pointer hover:scale-[1.02] active:scale-95 transition-transform shadow-lg"
               >
                 <Heart size={26} className="text-white fill-current" />
                 <span className="font-bold text-sm">Liked Songs</span>
               </div>

               <div 
                 onClick={() => navigate('/downloaded')}
                 className="bg-gradient-to-br from-emerald-800 to-teal-600/80 p-4 rounded-xl flex flex-col gap-3 cursor-pointer hover:scale-[1.02] active:scale-95 transition-transform shadow-lg"
               >
                 <ArrowDownCircle size={26} className="text-white" />
                 <span className="font-bold text-sm">Downloaded</span>
               </div>
               
               <div 
                 onClick={handleCreatePlaylist}
                 className="bg-neutral-800 p-4 rounded-xl flex flex-col gap-3 cursor-pointer hover:scale-[1.02] active:scale-95 transition-transform shadow-lg border border-white/5"
               >
                 <Plus size={26} className="text-brand" />
                 <span className="font-bold text-sm">New Playlist</span>
               </div>

               <div 
                 onClick={() => {
                   if (!user) { openLibraryAuthModal(); return; }
                   setShowSpotifyModal(true);
                 }}
                 className="bg-neutral-900/80 border border-[#1DB954]/30 p-4 rounded-xl flex flex-col gap-3 cursor-pointer hover:scale-[1.02] active:scale-95 transition-transform shadow-lg"
               >
                 <div className="w-7 h-7 rounded-md bg-[#1DB954]/20 flex items-center justify-center">
                   <svg className="w-4 h-4 text-[#1DB954] fill-current" viewBox="0 0 24 24">
                     <path d="M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm5.502 17.31c-.22.36-.68.472-1.04.252-2.85-1.742-6.438-2.137-10.665-1.17-.412.094-.816-.168-.91-.58-.094-.412.168-.816.58-.91 4.63-1.057 8.59-.61 11.783 1.34.36.22.472.68.252 1.068zm1.47-3.268c-.276.45-.86.59-1.31.314-3.264-2.007-8.24-2.59-12.1-1.417-.506.154-1.043-.136-1.197-.642-.154-.506.136-1.043.642-1.197 4.414-1.34 9.897-.69 13.65 1.62.45.276.59.86.315 1.322zm.126-3.41c-3.916-2.325-10.37-2.54-14.1-1.398-.6.183-1.237-.16-1.42-.76-.183-.6.16-1.237.76-1.42 4.29-1.302 11.41-1.05 15.89 1.61.54.32.72 1.02.4 1.56-.32.54-1.02.72-1.53.408z"/>
                   </svg>
                 </div>
                 <span className="font-bold text-sm text-white">Import Spotify</span>
               </div>
            </div>
          </>
        )}

        {/* Playlists List */}
        {(filter === 'all' || filter === 'playlists') && ((userPlaylists && userPlaylists.length > 0) ? userPlaylists : playlists).length > 0 && (
            <div className="flex flex-col gap-3">
              <h2 className="text-lg font-bold">Your Playlists</h2>
              {((userPlaylists && userPlaylists.length > 0) ? userPlaylists : playlists).map((playlist: any) => (
                <Link 
                  key={playlist.id}
                  to={`/playlist/${playlist.id}`}
                  className="flex items-center gap-4 p-3 rounded-xl bg-neutral-900/50 hover:bg-neutral-800 active:scale-95 transition-all border border-white/5 cursor-pointer"
                >
                  <div className="w-14 h-14 bg-neutral-800 rounded-lg flex items-center justify-center shadow-md flex-shrink-0 overflow-hidden">
                    {playlist.cover_url ? (
                      <img src={playlist.cover_url} alt={playlist.title} className="w-full h-full object-cover" onError={(e) => { e.currentTarget.style.display = 'none'; }} />
                    ) : (
                      <Music size={24} className="text-neutral-500" />
                    )}
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
    <ImportSpotifyModal isOpen={showSpotifyModal} onClose={() => setShowSpotifyModal(false)} />
    </>
  );
};

export default MobileLibrary;
