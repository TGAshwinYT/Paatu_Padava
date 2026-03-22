import React, { useState, useEffect } from 'react';
import { Search as SearchIcon, Clock, X } from 'lucide-react';
import { getListenHistory, deleteHistoryItem } from '../../services/api';
import { useAudio } from '../../context/AudioContext';
import type { Song } from '../../types';

const MobileSearch: React.FC = () => {
  const [query, setQuery] = useState('');
  const [recentlyPlayed, setRecentlyPlayed] = useState<(Song & { historyId: string })[]>([]);
  const { playTrack } = useAudio();

  useEffect(() => {
    const fetchRecent = async () => {
      const history = await getListenHistory();
      setRecentlyPlayed(history);
    };
    fetchRecent();
  }, []);

  const handleDeleteHistory = async (e: React.MouseEvent, historyId: string) => {
    e.stopPropagation();
    await deleteHistoryItem(historyId);
    setRecentlyPlayed(prev => prev.filter(item => item.historyId !== historyId));
  };

  return (
    <div className="p-4 pt-12 animate-in fade-in duration-500">
      <h1 className="text-3xl font-bold mb-6">Search</h1>
      
      {/* Search Input */}
      <div className="relative mb-8">
        <div className="absolute inset-y-0 left-3 flex items-center pointer-events-none">
          <SearchIcon size={20} className="text-black" />
        </div>
        <input
          type="text"
          placeholder="Artists, songs, or podcasts"
          className="w-full bg-white text-black py-3 pl-11 pr-4 rounded font-bold placeholder-neutral-600 focus:outline-none"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
      </div>

      {recentlyPlayed.length > 0 && (
        <>
          <h2 className="text-lg font-bold mb-4">Recently played</h2>
          <div className="flex flex-col gap-4">
            {recentlyPlayed.map((song) => (
              <div 
                key={song.id} 
                onClick={() => playTrack(song)}
                className="flex items-center gap-4 group"
              >
                <img src={song.coverUrl} className="w-12 h-12 rounded object-cover shadow-lg" alt="" />
                <div className="flex-1 truncate">
                  <p className="font-bold truncate">{song.title}</p>
                  <p className="text-xs text-neutral-400 truncate">{song.artist}</p>
                </div>
                <button onClick={(e) => handleDeleteHistory(e, song.historyId)} className="p-2">
                   <X size={18} className="text-neutral-500" />
                </button>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
};

export default MobileSearch;
