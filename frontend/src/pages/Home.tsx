import { useState, useEffect } from 'react';
import { Music } from 'lucide-react';
import SongCard from '../components/SongCard';
import type { Song } from '../types';
import { getHomeFeed } from '../services/api';

const Home = () => {
  const [recentlyPlayed, setRecentlyPlayed] = useState<Song[]>([]);
  const [topArtists, setTopArtists] = useState<Song[]>([]);
  const [recommended, setRecommended] = useState<Song[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const fetchFeed = async () => {
      setIsLoading(true);
      const data = await getHomeFeed();
      setRecentlyPlayed(data.recentlyPlayed || []);
      setTopArtists(data.topArtists || []);
      // @ts-ignore - response might have dynamic field from backend
      setRecommended(data.recommendedForYou || []);
      setIsLoading(false);
    };
    fetchFeed();
  }, []);

  if (isLoading) {
    return (
      <div className="flex flex-col gap-8 pb-24 items-center justify-center min-h-[50vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-white"></div>
        <p className="text-neutral-400 mt-4">Loading your feed...</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-8 pb-24">
      {recommended.length > 0 && (
        <section className="bg-gradient-to-r from-green-500/10 to-transparent p-6 rounded-2xl border border-white/5">
          <div className="flex items-center gap-2 mb-6">
            <div className="p-1.5 bg-green-500 rounded-lg">
                <Music size={20} className="text-black" />
            </div>
            <h2 className="text-2xl font-black">Recommended For You</h2>
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
            {recommended.map(song => (
              <SongCard key={song.id} song={song} />
            ))}
          </div>
        </section>
      )}

      {recentlyPlayed.length > 0 && (
        <section>
          <h2 className="text-2xl font-bold mb-4">Recently Played</h2>
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4 border-b border-white/5 pb-8">
            {recentlyPlayed.map(song => (
              <SongCard key={song.id} song={song} />
            ))}
          </div>
        </section>
      )}

      {topArtists.length > 0 && (
        <section>
          <h2 className="text-2xl font-bold mb-4">Top Artists For You</h2>
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
            {topArtists.map(song => (
              <SongCard key={song.id} song={song} />
            ))}
          </div>
        </section>
      )}

      {recentlyPlayed.length === 0 && topArtists.length === 0 && (
        <div className="text-neutral-400 text-center mt-20 flex flex-col items-center">
          <p className="text-xl mb-2 font-semibold">No data available.</p>
          <p className="text-sm">Please ensure your FastAPI backend is running on port 8000.</p>
        </div>
      )}
    </div>
  );
};

export default Home;
