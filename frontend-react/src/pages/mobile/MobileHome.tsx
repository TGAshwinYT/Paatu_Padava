import React, { useState, useEffect } from 'react';
import { useAuth } from '../../context/AuthContext';
import { useAudio } from '../../context/AudioContext';
import { getHomeFeed, getListenHistory } from '../../services/api';
import { Settings, Clock, Sparkles, Play } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import type { Song } from '../../types';

const MobileHome: React.FC = () => {
  const { user } = useAuth();
  const { playContext } = useAudio();
  const navigate = useNavigate();
  const [recentlyPlayed, setRecentlyPlayed] = useState<Song[]>([]);
  const [recommended, setRecommended] = useState<Song[]>([]);
  const [topAlbums, setTopAlbums] = useState<Song[]>([]);
  const [artistMixes, setArtistMixes] = useState<any[]>([]);
  const [isPersonalized, setIsPersonalized] = useState(false);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const fetchData = async () => {
      setIsLoading(true);
      try {
        const [feed, history] = await Promise.all([
          getHomeFeed(),
          user ? getListenHistory() : Promise.resolve([])
        ]);

        setRecentlyPlayed(history.slice(0, 8));
        setRecommended(feed.recommendedForYou || []);
        setTopAlbums(feed.topAlbums || []);
        setIsPersonalized(feed.personalized);

        // Mix Logic
        const favs = user ? JSON.parse(user.favorite_artists || '[]') : [];
        const mockMixes = favs.length > 0 ? favs.map((name: string, i: number) => ({
          id: i,
          name: `${name} Mix`,
          imageUrl: `https://ui-avatars.com/api/?name=${name}&background=random&size=200`
        })) : [
          { id: 1, name: 'Tamil Hits Mix', imageUrl: 'https://images.unsplash.com/photo-1493225255756-d9584f8606e9?w=300&h=300&fit=crop' },
          { id: 2, name: 'Anirudh Mix', imageUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300&h=300&fit=crop' },
          { id: 3, name: 'Illayaraja Mix', imageUrl: 'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?w=300&h=300&fit=crop' }
        ];
        setArtistMixes(mockMixes);
      } catch (err) {
        console.error("Mobile Home Fetch Error:", err);
      } finally {
        setIsLoading(false);
      }
    };
    fetchData();
  }, [user]);

  const greeting = () => {
    const hour = new Date().getHours();
    if (hour < 12) return "Good morning";
    if (hour < 18) return "Good afternoon";
    return "Good evening";
  };

  // Combine Recently Played and Top Albums for the 2x4 grid
  const topEight = [...recentlyPlayed.slice(0, 4), ...topAlbums.slice(0, 4)];

  if (isLoading) {
    return (
      <div className="flex flex-col items-center justify-center h-[100dvh] bg-[#121212]">
        <div className="w-12 h-12 border-4 border-green-500 border-t-transparent rounded-full animate-spin"></div>
      </div>
    );
  }

  return (
    <div className="bg-[#121212] h-[100dvh] overflow-y-auto no-scrollbar pb-32">
      {/* Dynamic Header */}
      <div className="sticky top-0 z-30 bg-gradient-to-b from-neutral-800/80 to-[#121212]/0 backdrop-blur-sm px-4 pt-12 pb-4">
        <div className="flex items-center justify-between mb-4">
          <h1 className="text-2xl font-bold tracking-tighter text-white">{greeting()}</h1>
          <div className="flex items-center gap-5 text-white/90">
             <Sparkles size={22} className="text-indigo-400" />
             <Link to="/history"><Clock size={22} /></Link>
             <Link to="/settings"><Settings size={22} /></Link>
          </div>
        </div>
      </div>

      {/* 2x4 Quick Access Grid */}
      <div className="grid grid-cols-2 gap-2 px-4 mb-8">
        {topEight.map((item, i) => (
          <div 
            key={`${item.id}-${i}`} 
            onClick={() => {
              if (item.id && (item.id.startsWith('MPREb') || (item as any).type === 'album')) {
                navigate(`/album/${item.id}`);
              } else {
                playContext(item, topEight);
              }
            }}
            className="flex items-center bg-white/10 rounded-md overflow-hidden h-14 border border-white/5 active:scale-95 transition-transform"
          >
            <img 
              src={item.coverUrl || '/logo.png'} 
              className="h-full aspect-square object-cover" 
              alt={item.title}
              onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
            />
            <span className="text-white text-[11px] font-bold px-2 line-clamp-2 leading-tight">
              {item.title}
            </span>
          </div>
        ))}
      </div>

      {!isPersonalized && (
        <div className="mx-4 mb-8 p-4 rounded-xl bg-gradient-to-br from-indigo-600/20 to-purple-600/10 border border-white/5 flex items-center justify-between">
          <p className="text-xs text-neutral-300 max-w-[70%] font-medium">Get a mix made just for you by signing in.</p>
          <button onClick={() => navigate('/login')} className="bg-white text-black text-[11px] font-bold px-4 py-2 rounded-full shadow-lg">Log in</button>
        </div>
      )}

      {/* Horizontal Carousels with Snap */}
      <section className="mb-8">
        <h2 className="text-xl font-extrabold px-4 mb-4 text-white">Recommended for you</h2>
        <div className="flex overflow-x-auto snap-x snap-mandatory gap-4 px-4 hide-scrollbar">
          {recommended.map((song) => (
            <div 
              key={song.id} 
              onClick={() => playContext(song, recommended)}
              className="snap-start min-w-[140px] max-w-[140px] flex flex-col gap-2 group"
            >
              <div className="relative aspect-square">
                <img 
                  src={song.coverUrl || '/logo.png'} 
                  className="w-full h-full object-cover rounded-lg shadow-2xl group-active:scale-95 transition-transform" 
                  alt="" 
                />
              </div>
              <div className="flex flex-col">
                <p className="text-white text-xs font-bold truncate">{song.title}</p>
                <p className="text-neutral-400 text-[10px] font-medium truncate">{song.artist}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="mb-8">
        <h2 className="text-xl font-extrabold px-4 mb-4 text-white">Artist Mixes</h2>
        <div className="flex overflow-x-auto snap-x snap-mandatory gap-4 px-4 hide-scrollbar">
          {artistMixes.map((mix) => (
            <div 
              key={mix.id} 
              onClick={() => navigate(`/search?q=${encodeURIComponent(mix.name)}`)}
              className="snap-start min-w-[120px] max-w-[120px] flex flex-col gap-2 active:scale-95 transition-transform cursor-pointer"
            >
              <div className="relative aspect-square">
                <div className="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent z-10 rounded-lg" />
                <img 
                  src={mix.imageUrl || '/logo.png'} 
                  className="w-full h-full object-cover rounded-lg shadow-xl" 
                  alt="" 
                />
              </div>
              <p className="text-white text-[11px] font-bold truncate text-center">{mix.name}</p>
            </div>
          ))}
        </div>
      </section>

      {recentlyPlayed.length > 0 && (
        <section className="mb-4">
          <h2 className="text-xl font-extrabold px-4 mb-4 text-white">Jump back in</h2>
          <div className="px-4">
             {recentlyPlayed.slice(0, 1).map((song) => (
                <div 
                  key={song.id} 
                  onClick={() => playContext(song, recentlyPlayed)}
                  className="relative flex items-center gap-4 bg-white/5 rounded-xl p-3 border border-white/5 active:scale-[0.98] transition-all overflow-hidden"
                >
                   {/* Progress Visualizer Background */}
                   <div className="absolute bottom-0 left-0 h-1 bg-green-500/30 w-[40%]" />
                   
                   <div className="relative w-14 h-14 flex-shrink-0">
                      <img 
                        src={song.coverUrl || '/logo.png'} 
                        className="w-full h-full rounded-lg object-cover shadow-2xl" 
                        alt="" 
                      />
                   </div>
                   
                   <div className="flex-1 min-w-0">
                      <p className="text-white font-bold text-sm truncate">{song.title}</p>
                      <p className="text-neutral-400 text-xs truncate font-medium">{song.artist}</p>
                   </div>

                   <div className="w-10 h-10 flex items-center justify-center rounded-full bg-white/10">
                      <Play size={20} fill="white" className="ml-0.5" />
                   </div>
                </div>
             ))}
          </div>
        </section>
      )}

    </div>
  );
};

export default MobileHome;

