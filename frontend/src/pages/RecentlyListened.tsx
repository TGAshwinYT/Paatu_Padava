import { useState, useEffect } from 'react';
import { Clock, Play } from 'lucide-react';
import { getListenHistory } from '../services/api';
import { useAudio } from '../context/AudioContext';
import type { Song } from '../types';

const History = () => {
  const [history, setHistory] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { playTrack } = useAudio();

  useEffect(() => {
    const fetchHistory = async () => {
      setIsLoading(true);
      const data = await getListenHistory();
      setHistory(data);
      setIsLoading(false);
    };
    fetchHistory();
  }, []);

  // Mapping backend History object to Song type
  const mapHistoryToSong = (h: any): Song => {
    return {
      id: h.jiosaavn_song_id,
      title: h.title,
      artist: h.artist,
      coverUrl: h.cover_url || h.coverUrl || '',
      audioUrl: h.audio_url || h.audioUrl || ''
    };
  };

  return (
    <div className="flex flex-col gap-8 pb-24 animate-in fade-in duration-700">
      <div className="flex items-end gap-6">
        <div className="w-48 h-48 bg-gradient-to-br from-purple-900 to-black rounded-lg shadow-2xl flex items-center justify-center">
          <Clock size={80} className="text-white/20" />
        </div>
        <div>
          <p className="text-sm font-bold uppercase tracking-wider">Playlist</p>
          <h1 className="text-7xl font-black mt-2 mb-6">Recently Listened</h1>
        </div>
      </div>

      {isLoading ? (
        <div className="flex justify-center py-20">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-500"></div>
        </div>
      ) : history.length > 0 ? (
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-6">
          {history.map((h, idx) => {
            const song = mapHistoryToSong(h);
            return (
              <div key={idx} className="relative group">
                 <div className="bg-neutral-800/40 p-4 rounded-md hover:bg-neutral-700/50 transition-all cursor-pointer h-full flex flex-col" onClick={() => playTrack(song)}>
                    <div className="aspect-square bg-neutral-700 rounded-md mb-4 flex items-center justify-center relative overflow-hidden flex-shrink-0">
                       <img 
                         src={song.coverUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&h=500&fit=crop'} 
                         className="w-full h-full object-cover" 
                         alt={song.title} 
                       />
                       <button 
                         onClick={(e) => {
                           e.stopPropagation();
                           playTrack(song);
                         }}
                         className="absolute bottom-2 right-2 p-3 bg-green-500 rounded-full text-black shadow-xl opacity-0 group-hover:opacity-100 translate-y-2 group-hover:translate-y-0 transition-all"
                       >
                         <Play fill="currentColor" size={20} />
                       </button>
                    </div>
                    <h3 className="font-semibold text-white truncate mb-1">{song.title}</h3>
                    <p className="text-xs text-neutral-400 truncate">{song.artist}</p>
                    <p className="text-[10px] text-neutral-500 mt-2 opacity-0 group-hover:opacity-100 transition-opacity">
                      {new Date(h.played_at).toLocaleDateString()}
                    </p>
                 </div>
              </div>
            );
          })}
        </div>
      ) : (
        <div className="flex flex-col items-center justify-center py-20 text-neutral-500 bg-neutral-900/40 rounded-3xl border border-white/5">
          <Clock size={64} className="mb-4 opacity-20" />
          <p className="text-xl font-medium">No listening history yet</p>
          <p className="mt-2">Start playing some tunes!</p>
        </div>
      )}
    </div>
  );
};

export default History;
