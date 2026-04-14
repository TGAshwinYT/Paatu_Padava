import { useState, useEffect, useRef } from 'react';
import { Play, ChevronRight, ChevronLeft, Sparkles } from 'lucide-react';
import SongCard from '../components/SongCard';
import HomeSection from '../components/HomeSection';
import PopularArtists from '../components/PopularArtists';
import PopularAlbums from '../components/PopularAlbums';
import type { Song } from '../types';
import { useNavigate } from 'react-router-dom';
import { getHomeFeed, getListenHistory, getFollowedArtists } from '../services/api';
import { useAudio } from '../context/AudioContext';
import { getRecentCollections } from '../utils/historyUtils';
import 'swiper/css';

interface HomeProps {
  isLoggedIn: boolean;
  user?: any;
}

const Home = ({ isLoggedIn }: HomeProps) => {
  const [recentlyPlayed, setRecentlyPlayed] = useState<Song[]>([]);
  const [topArtists, setTopArtists] = useState<any[]>([]);
  const [recommended, setRecommended] = useState<Song[]>([]);
  const [topAlbums, setTopAlbums] = useState<Song[]>([]);
  const [isPersonalized, setIsPersonalized] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const { playContext } = useAudio();
  const navigate = useNavigate();

  const getGreeting = () => {
    const hour = new Date().getHours();
    if (hour < 12) return "Good morning";
    if (hour < 18) return "Good afternoon";
    return "Good evening";
  };

  // Prepare shortcut items (Prioritize Recently Played Collections + Mixes + Fallback to Top Albums)
  const shortcuts = [
    ...(isLoggedIn ? [{ id: 'liked-songs', title: 'Liked Songs', coverUrl: 'https://misc.scdn.co/liked-songs/liked-songs-640.png', type: 'playlist' }] : []),
    ...getRecentCollections().map(c => ({ id: c.id, title: c.title, coverUrl: c.coverUrl, type: c.type })),
    ...topAlbums.map(a => ({ id: a.id, title: a.title, coverUrl: a.coverUrl, type: 'album' }))
  ].filter(item => item && item.id)
   .reduce((acc: any[], curr) => {
    if (!acc.find(item => item.id === curr.id)) acc.push(curr);
    return acc;
  }, []).slice(0, 8);

  const recommendedRef = useRef<HTMLDivElement>(null);
  const recentlyPlayedRef = useRef<HTMLDivElement>(null);

  const scrollAction = (ref: React.RefObject<HTMLDivElement | null>, direction: 'left' | 'right') => {
    if (ref.current) {
        const scrollAmount = direction === 'left' ? -400 : 400;
        ref.current.scrollBy({ left: scrollAmount, behavior: 'smooth' });
    }
  };

  useEffect(() => {
    const fetchFeed = async () => {
      setIsLoading(true);
      try {
        const [feedData, historyData, artistsData] = await Promise.all([
          getHomeFeed(),
          isLoggedIn ? getListenHistory() : Promise.resolve([]),
          isLoggedIn ? getFollowedArtists() : Promise.resolve([])
        ]);
        
        const data = feedData;
        setIsPersonalized(data.personalized);
        setRecentlyPlayed((historyData || []).slice(0, 12));
        
        let normalizedArtists = (artistsData || []).map((a: any) => ({
          id: a.id || a.artist_id || '',
          name: a.name || a.artist_name || a.artist || 'Unknown Artist',
          image: [{ url: a.image_url || a.image || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200&h=200&fit=crop' }]
        }));

        const backendArtists = data.topArtists || [];
        const finalArtists = normalizedArtists.length > 0 ? normalizedArtists : backendArtists;

        setTopArtists(finalArtists.slice(0, 24));
        setRecommended(data.recommendedForYou || []);
        setTopAlbums(data.topAlbums || []);
      } catch (error) {
        console.error("Error fetching home feed:", error);
      } finally {
        setIsLoading(false);
      }
    };
    fetchFeed();
  }, [isLoggedIn]);


  if (isLoading) {
    return (
      <div className="flex flex-col gap-8 pb-24 items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-white"></div>
        <p className="text-neutral-400 mt-4">Loading your feed...</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-10 pb-24 pt-2">
      
      {/* 🟢 Spotify-Style Greeting & Filters 🟢 */}
      <section className="relative -mx-6 px-6 pt-6 pb-10 bg-gradient-to-b from-green-900/30 to-[#121212]">
        <div className="flex flex-col gap-6 mb-8">
          <div className="flex items-center justify-between">
            <h1 className="text-3xl font-extrabold tracking-tight text-white">{getGreeting()}</h1>
          </div>
        </div>

        {/* Shortcut Grid (4x2 on Desktop, 2x4 on Mobile) */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {shortcuts.map((item, i) => (
            <div 
              key={`${item.id}-${i}`}
              onClick={() => {
                if (!item.id) return;
                
                const id = item.id;
                const isPlaylistID = id.startsWith('PL') || id.startsWith('RDCL') || id.startsWith('RDTK');
                const isAlbumID = id.startsWith('MPREb') || id.startsWith('OLAK5uy_') || id.startsWith('AMGR_') || topAlbums.some(a => a.id === id);

                if (id === 'liked-songs') {
                  navigate('/library');
                } else if (item.type === 'album' || isAlbumID || (!isPlaylistID && id.length > 20)) {
                  navigate(`/album/${id}`);
                } else {
                  navigate(`/playlist/${id}`);
                }
              }}
              className="group relative flex items-center bg-white/5 hover:bg-white/10 rounded-lg overflow-hidden h-[80px] transition-all cursor-pointer border border-transparent hover:border-white/5 shadow-lg"
            >
              <div className="h-full aspect-square w-20 flex-shrink-0 relative">
                <img 
                  src={item.coverUrl || '/logo.png'} 
                  alt={item.title}
                  className="w-full h-full object-cover shadow-[4px_0_10px_rgba(0,0,0,0.3)]"
                  onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                />
              </div>
              <div className="flex-1 px-4 flex items-center justify-between overflow-hidden">
                <span className="text-white font-bold text-sm line-clamp-2 truncate pr-2">
                  {item.title}
                </span>
                <button className="w-12 h-12 bg-[#1ed760] rounded-full shadow-2xl flex items-center justify-center translate-y-2 opacity-0 group-hover:translate-y-0 group-hover:opacity-100 transition-all duration-300 transform scale-0 group-hover:scale-100 flex-shrink-0">
                  <Play size={20} fill="black" className="ml-1" />
                </button>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* 🚀 Personalization Banner 🚀 */}
      {!isLoggedIn && !isPersonalized && (
        <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-indigo-900/60 via-purple-900/40 to-[#121212] border border-white/5 p-8 group">
          <div className="absolute top-0 right-0 w-64 h-64 bg-indigo-500/10 blur-[100px] rounded-full -translate-y-1/2 translate-x-1/2 group-hover:bg-indigo-500/20 transition-all duration-700"></div>
          <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
            <div className="flex items-start gap-4">
              <div className="bg-indigo-500/20 p-3 rounded-xl border border-indigo-500/20 text-indigo-400 group-hover:scale-110 transition-transform duration-500">
                <Sparkles size={24} />
              </div>
              <div className="flex flex-col gap-1">
                <h3 className="text-xl md:text-2xl font-bold text-white tracking-tight">Unlock Your Personalized Mix</h3>
                <p className="text-neutral-400 text-sm md:text-base max-w-xl leading-relaxed">
                  Sign in to sync your YouTube Music history and let our algorithm build unique playlists just for you.
                </p>
              </div>
            </div>
            <button 
              onClick={() => navigate('/login')}
              className="bg-white text-black hover:bg-neutral-200 px-8 py-3 rounded-full font-bold text-sm transition-all hover:scale-105 active:scale-95 shadow-lg whitespace-nowrap"
            >
              Sign In Now
            </button>
          </div>
        </div>
      )}

      {recommended.length > 0 && (
        <HomeSection title="Recommended For You" showAllLink="/recommendations" className="bg-gradient-to-r from-green-500/10 to-transparent p-6 rounded-2xl border border-white/5">
          <div className="relative group/slider">
            <button 
                onClick={() => scrollAction(recommendedRef, 'left')} 
                className="absolute left-[-16px] top-1/2 -translate-y-1/2 z-10 hidden md:flex items-center justify-center w-10 h-10 bg-black/50 hover:bg-black/80 text-white rounded-full opacity-0 group-hover/slider:opacity-100 transition-opacity"
            >
                <ChevronLeft size={24} />
            </button>
            <div ref={recommendedRef} className="flex overflow-x-auto gap-4 pb-4 snap-x snap-mandatory scroll-smooth hide-scrollbar">
              {recommended.map((song, index) => (
                <div key={`${song.id}-${index}`} className="flex-shrink-0 w-36 md:w-44 lg:w-48 snap-start group bg-[#181818] p-4 rounded-lg hover:bg-[#282828] transition-all duration-300 cursor-pointer flex flex-col h-full" onClick={() => playContext(song, recommended)}>
                    <div className="relative mb-4">
                      <img 
                        src={song.coverUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200&h=200&fit=crop'} 
                        className="w-full aspect-square object-cover rounded-md shadow-[0_8px_24px_rgba(0,0,0,0.5)]" 
                        alt={song.title} 
                        loading="lazy"
                      />
                      <button 
                        className="absolute bottom-2 right-2 bg-[#1ed760] w-12 h-12 rounded-full shadow-lg opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0 transition-all duration-300 ease-out flex items-center justify-center hover:scale-105 active:scale-95"
                        onClick={(e) => {
                          e.stopPropagation();
                          playContext(song, recommended);
                        }}
                      >
                        <Play size={20} fill="black" className="text-black ml-1" />
                      </button>
                    </div>
                    <div className="flex flex-col">
                      <p className="text-white font-bold text-base truncate pb-1">{song.title}</p>
                      <p className="text-[#a7a7a7] text-sm font-medium truncate">{song.artist}</p>
                    </div>
                </div>
              ))}
            </div>
            <button 
                onClick={() => scrollAction(recommendedRef, 'right')} 
                className="absolute right-[-16px] top-1/2 -translate-y-1/2 z-10 hidden md:flex items-center justify-center w-10 h-10 bg-black/50 hover:bg-black/80 text-white rounded-full opacity-0 group-hover/slider:opacity-100 transition-opacity"
            >
                <ChevronRight size={24} />
            </button>
          </div>
        </HomeSection>
      )}

      {recentlyPlayed.length > 0 && (
        <HomeSection title="Recently Played" showAllLink="/history">
          <div className="relative group/slider">
            <button 
                onClick={() => scrollAction(recentlyPlayedRef, 'left')} 
                className="absolute left-[-16px] top-1/2 -translate-y-1/2 z-10 hidden md:flex items-center justify-center w-10 h-10 bg-black/50 hover:bg-black/80 text-white rounded-full opacity-0 group-hover/slider:opacity-100 transition-opacity"
            >
                <ChevronLeft size={24} />
            </button>
            <div ref={recentlyPlayedRef} className="flex overflow-x-auto gap-4 pb-4 snap-x snap-mandatory scroll-smooth hide-scrollbar">
              {recentlyPlayed.map((song, index) => (
                <div key={`${song.id}-${index}`} className="flex-shrink-0 w-36 md:w-44 lg:w-48 snap-start">
                  <SongCard song={song} context={recentlyPlayed} />
                </div>
              ))}
            </div>
            <button 
                onClick={() => scrollAction(recentlyPlayedRef, 'right')} 
                className="absolute right-[-16px] top-1/2 -translate-y-1/2 z-10 hidden md:flex items-center justify-center w-10 h-10 bg-black/50 hover:bg-black/80 text-white rounded-full opacity-0 group-hover/slider:opacity-100 transition-opacity"
            >
                <ChevronRight size={24} />
            </button>
          </div>
        </HomeSection>
      )}

      {topArtists?.length > 0 && (
        <PopularArtists artists={topArtists.slice(0, 5)} onArtistClick={(name) => {
          navigate(`/search?q=${encodeURIComponent(name)}`);
        }} />
      )}

      {topAlbums.length > 0 && <PopularAlbums albums={topAlbums} />}

      {isLoggedIn && recentlyPlayed.length === 0 && topArtists.length === 0 && topAlbums.length === 0 && (
        <div className="text-neutral-400 text-center mt-20 flex flex-col items-center">
          <p className="text-xl mb-2 font-semibold">No data available.</p>
          <p className="text-sm">Please ensure your FastAPI backend is running.</p>
        </div>
      )}
    </div>
  );
};

export default Home;
