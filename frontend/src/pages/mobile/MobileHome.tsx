import React, { useState, useEffect } from 'react';
import { useAuth } from '../../context/AuthContext';
import { useAudio } from '../../context/AudioContext';
import { getListenHistory } from '../../services/api';
import { Settings, Clock } from 'lucide-react';
import { Link } from 'react-router-dom';
import type { Song } from '../../types';
import InstallPWA from '../../components/InstallPWA';

const MobileHome: React.FC = () => {
  const { user } = useAuth();
  const { playContext } = useAudio();
  const [recentlyPlayed, setRecentlyPlayed] = useState<(Song & { historyId: string })[]>([]);
  const [artistMixes, setArtistMixes] = useState<any[]>([]);

  useEffect(() => {
    const fetchData = async () => {
      if (user) {
        const history = await getListenHistory();
        setRecentlyPlayed(history.slice(0, 4));
      } else {
        setRecentlyPlayed([]);
      }

      // Use user's favorite artists for mixes
      const favs = user ? JSON.parse(user.favorite_artists || '[]') : [];
      const mockMixes = favs.length > 0 ? favs.map((name: string, i: number) => ({
        id: i,
        name: `${name} Mix`,
        imageUrl: `https://ui-avatars.com/api/?name=${name}&background=random&size=200`
      })) : [
        { id: 1, name: 'Tamil Hits Mix', imageUrl: 'https://images.unsplash.com/photo-1493225255756-d9584f8606e9?w=300&h=300&fit=crop' },
        { id: 2, name: 'Anirudh Mix', imageUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300&h=300&fit=crop' }
      ];
      setArtistMixes(mockMixes);
    };
    fetchData();
  }, [user]);

  const greeting = () => {
    const hour = new Date().getHours();
    if (hour < 12) return "Good morning";
    if (hour < 18) return "Good afternoon";
    return "Good evening";
  };

  return (
    <div className="bg-gradient-to-b from-neutral-800 to-black min-h-full p-4 pt-12 animate-in fade-in duration-1000">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold tracking-tight">{greeting()}, {user?.username || 'Guest'}</h1>
        <div className="flex items-center gap-4">
           {user && (
             <Link to="/history">
               <Clock size={24} />
             </Link>
           )}
           <Link to="/settings">
             <Settings size={24} />
           </Link>
           <Link to="/">
             <img src="/logo.png" alt="Home" className="w-8 h-8 rounded-full shadow-lg object-cover" />
           </Link>
        </div>
      </div>

      <div className="mb-8">
        <InstallPWA />
      </div>

      {user && recentlyPlayed.length > 0 && (
        <div className="grid grid-cols-2 gap-2 mb-8 animate-in slide-in-from-bottom-2 duration-500">
          {recentlyPlayed.map((song) => (
            <div 
              key={song.historyId} 
              onClick={() => playContext(song, recentlyPlayed)}
              className="flex items-center bg-white/10 hover:bg-white/20 transition-colors rounded-md overflow-hidden h-14"
            >
              <img 
                src={song.coverUrl || (song as any).cover_url || (song as any).image || (song as any).thumbnail || '/logo.png'} 
                className="w-14 h-14 object-cover" 
                alt="" 
                onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
              />
              <div className="p-2 truncate">
                <p className="text-[11px] font-bold text-white truncate">{song.title}</p>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Artist Mixes Carousels */}
      <section className="mb-8">
        <h2 className="text-2xl font-bold mb-4">Artist Mixes</h2>
        <div className="flex gap-4 overflow-x-auto pb-4 no-scrollbar">
          {artistMixes.map((mix) => (
            <div key={mix.id} className="w-28 shrink-0">
              <div className="relative aspect-square mb-2 group">
                 <img 
                    src={mix.imageUrl || '/logo.png'} 
                    className="w-full h-full object-cover rounded shadow-2xl" 
                    alt="" 
                    onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                 />
                 <div className="absolute inset-0 bg-black/20 group-hover:bg-black/0 transition-all rounded" />
              </div>
              <p className="text-xs font-bold text-neutral-200 line-clamp-2">{mix.name}</p>
            </div>
          ))}
        </div>
      </section>

      {user && recentlyPlayed.length > 0 && (
        <section className="mb-8">
          <h2 className="text-2xl font-bold mb-4">Jump Back In</h2>
          <div className="flex gap-4 overflow-x-auto pb-4 no-scrollbar">
             {recentlyPlayed.map((song) => (
                <div key={song.id} onClick={() => playContext(song, recentlyPlayed)} className="w-36 shrink-0">
                   <img 
                     src={song.coverUrl || (song as any).cover_url || (song as any).image || (song as any).thumbnail || '/logo.png'} 
                     className="w-36 h-36 object-cover rounded-lg shadow-xl mb-2" 
                     alt="" 
                     onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                   />
                   <p className="text-sm font-bold truncate">{song.title}</p>
                   <p className="text-xs text-neutral-400 truncate">{song.artist}</p>
                </div>
             ))}
          </div>
        </section>
      )}
    </div>
  );
};

export default MobileHome;
