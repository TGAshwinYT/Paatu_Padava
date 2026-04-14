import { useState, useEffect } from 'react';
import { Clock, Play, Trash2, X, ChevronLeft, ChevronDown } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import api, { getListenHistory, mapHistoryToSong } from '../services/api';
import { useAudio } from '../context/AudioContext';
import { getValidImage } from '../utils/imageUtils';
import { useMobile } from '../hooks/useMobile';

const groupHistoryByDate = (historyArray: any[]) => {
  const groups: { [key: string]: { label: string, rawDate?: string, items: any[] } } = {};
  const orderedGroups: { label: string, rawDate?: string, items: any[] }[] = [];
  
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);
  
  historyArray.forEach(item => {
    let key = 'Earlier';
    let rawDateString = '';
    
    if (item.played_at) {
      const playedDate = new Date(item.played_at);
      rawDateString = playedDate.toISOString().split('T')[0]; // YYYY-MM-DD
      
      playedDate.setHours(0, 0, 0, 0);
      
      if (playedDate.getTime() === today.getTime()) {
        key = 'Today';
      } else if (playedDate.getTime() === yesterday.getTime()) {
        key = 'Yesterday';
      } else {
        key = playedDate.toLocaleDateString('en-US', {
          weekday: 'short',
          month: 'short',
          day: 'numeric',
          year: 'numeric'
        });
      }
    }
    
    if (!groups[key]) {
      groups[key] = { label: key, rawDate: rawDateString, items: [] };
      orderedGroups.push(groups[key]);
    }
    groups[key].items.push(item);
  });
  
  return orderedGroups;
};

const History = () => {
  const [history, setHistory] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { playContext } = useAudio();
  const isMobile = useMobile();
  const navigate = useNavigate();

  useEffect(() => {
    const fetchHistory = async () => {
      setIsLoading(true);
      const data = await getListenHistory();
      setHistory(data);
      setIsLoading(false);
    };
    fetchHistory();
  }, []);

  const handleClearAll = async () => {
    if (history.length === 0) return;
    try {
      setHistory([]);
      await api.delete('/api/history/all');
    } catch (error) {
      console.error("Failed to clear history", error);
    }
  };

  const handleClearDay = async (rawDate: string) => {
    if (!rawDate) return;
    try {
      setHistory(prev => prev.filter(h => {
        if (!h.played_at) return true;
        return new Date(h.played_at).toISOString().split('T')[0] !== rawDate;
      }));
      await api.delete(`/api/history/date/${rawDate}`);
    } catch (error) {
      console.error("Failed to clear date", error);
    }
  };

  const handleRemoveSong = async (e: React.MouseEvent, historyId: string) => {
    e.stopPropagation();
    try {
      setHistory(prev => prev.filter(h => h.id !== historyId));
      await api.delete(`/api/history/song/${historyId}`);
    } catch (error) {
      console.error("Failed to remove song", error);
    }
  };

  const groupedHistory = groupHistoryByDate(history);

  if (isLoading) {
    return (
      <div className="flex justify-center py-20 min-h-screen">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-500"></div>
      </div>
    );
  }

  if (isMobile) {
    return (
      <div className="flex flex-col gap-6 pb-32 min-h-screen bg-black animate-in fade-in duration-500">
        {/* Mobile Header */}
        <div className="flex items-center justify-between px-4 py-4 sticky top-0 bg-black z-10">
          <button onClick={() => navigate(-1)} className="p-2 -ml-2 text-white hover:bg-neutral-800 rounded-full transition">
            <ChevronLeft size={28} />
          </button>
          <h1 className="text-lg font-bold text-white">Recents</h1>
          <div className="w-10" /> {/* Spacer for centering */}
        </div>

        {/* Filter Chip */}
        <div className="px-4 -mt-2">
          <div className="inline-flex items-center px-4 py-1.5 bg-[#282828] text-white rounded-full text-xs font-medium border border-transparent">
            Music
          </div>
        </div>

        {groupedHistory.length > 0 ? (
          <div className="flex flex-col gap-8 px-4">
            {groupedHistory.map(({ label: dateCategory, rawDate, items }) => (
              <div key={dateCategory} className="flex flex-col gap-4">
                <div className="flex items-center justify-between">
                  <h2 className="text-2xl font-bold text-white">{dateCategory}</h2>
                  <button 
                    onClick={() => rawDate && handleClearDay(rawDate)}
                    className="text-neutral-500 hover:text-red-400 p-2"
                  >
                    <Trash2 size={18} />
                  </button>
                </div>
                
                <div className="flex flex-col gap-5">
                  {items.map((h, idx) => {
                    const song = mapHistoryToSong(h);
                    return (
                      <div 
                        key={idx} 
                        className="flex items-center gap-4 group active:bg-neutral-900 transition-colors rounded-lg"
                        onClick={() => playContext(song, items.map(h => mapHistoryToSong(h)))}
                      >
                        <div className="w-16 h-16 rounded-md overflow-hidden flex-shrink-0 shadow-lg">
                          <img 
                            src={getValidImage(song)} 
                            className="w-full h-full object-cover" 
                            alt={song.title} 
                            onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                          />
                        </div>
                        <div className="flex-1 min-w-0">
                          <h3 className="font-bold text-white text-md truncate mb-0.5">{song.title}</h3>
                          <div className="flex items-center gap-1.5 text-neutral-400 text-xs font-semibold">
                             <span className="truncate">1 song played</span>
                             <span className="w-1 h-1 rounded-full bg-neutral-600 flex-shrink-0" />
                             <span className="truncate">Album</span>
                             <span className="w-1 h-1 rounded-full bg-neutral-600 flex-shrink-0" />
                             <p className="truncate">{song.artist}</p>
                          </div>
                        </div>
                        <button className="p-2 text-neutral-500">
                          <ChevronDown size={22} className="rotate-270" />
                        </button>
                      </div>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="flex flex-col items-center justify-center pt-32 px-10 text-center">
            <Clock size={64} className="mb-6 opacity-20 text-white" />
            <p className="text-xl font-bold text-white">No listening history</p>
            <p className="text-neutral-500 mt-2 text-sm">Play some music to see your recents appear here.</p>
          </div>
        )}
      </div>
    );
  }

  // Desktop View
  return (
    <div className="flex flex-col gap-8 pb-24 animate-in fade-in duration-700">
      <div className="flex items-end justify-between gap-6">
        <div className="flex items-end gap-6">
          <div className="w-48 h-48 bg-gradient-to-br from-purple-900 to-black rounded-lg shadow-2xl flex items-center justify-center">
            <Clock size={80} className="text-white/20" />
          </div>
          <div>
            <p className="text-sm font-bold uppercase tracking-wider">Playlist</p>
            <h1 className="text-7xl font-black mt-2 mb-6">Recently Listened</h1>
          </div>
        </div>
        
        {history.length > 0 && (
          <button 
            onClick={handleClearAll}
            className="text-red-500 hover:text-red-400 font-semibold mb-6 px-4 py-2 rounded-full hover:bg-red-500/10 transition flex items-center gap-2 border border-transparent hover:border-red-500/20"
          >
            <Trash2 size={18} /> Clear All History
          </button>
        )}
      </div>

      {groupedHistory.length > 0 ? (
        <div className="flex flex-col gap-8">
          {groupedHistory.map(({ label: dateCategory, rawDate, items }) => (
            <div key={dateCategory} className="flex flex-col">
              <div className="flex items-center justify-between sticky top-0 bg-neutral-900/90 py-2 z-10 backdrop-blur-md border-b border-transparent">
                  <h2 className="text-2xl font-bold mt-2 mb-2">
                    {dateCategory}
                  </h2>
                  <button 
                    onClick={() => rawDate && handleClearDay(rawDate)}
                    className="text-neutral-500 hover:text-red-400 p-2 rounded-full hover:bg-white/5 transition mb-2"
                    title="Clear Day"
                  >
                    <Trash2 size={18} />
                  </button>
              </div>
              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-6 pt-4">
                {items.map((h, idx) => {
                  const song = mapHistoryToSong(h);
                  return (
                    <div key={idx} className="relative group">
                       <div className="bg-neutral-800/40 p-4 rounded-md hover:bg-neutral-700/50 transition-all cursor-pointer h-full flex flex-col" onClick={() => playContext(song, items.map(h => mapHistoryToSong(h)))}>
                          <div className="aspect-square bg-neutral-700 rounded-md mb-4 flex items-center justify-center relative overflow-hidden flex-shrink-0">
                             <img 
                               src={getValidImage(song)} 
                               className="w-full h-full object-cover" 
                               alt={song.title} 
                               onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                             />
                             <button 
                               onClick={(e) => {
                                 e.stopPropagation();
                                 playContext(song, items.map(h => mapHistoryToSong(h)));
                               }}
                               className="absolute bottom-2 right-2 p-3 bg-green-500 rounded-full text-black shadow-xl opacity-0 group-hover:opacity-100 translate-y-2 group-hover:translate-y-0 transition-all"
                             >
                               <Play fill="currentColor" size={20} />
                             </button>
                             <button 
                               onClick={(e) => handleRemoveSong(e, h.id)}
                               className="absolute top-2 right-2 p-2 bg-black/60 backdrop-blur-sm rounded-full text-neutral-300 hover:text-white hover:bg-red-500 shadow-xl opacity-0 group-hover:opacity-100 transition-all"
                               title="Remove from history"
                             >
                               <X size={14} />
                             </button>
                          </div>
                          <h3 className="font-semibold text-white truncate mb-1">{song.title}</h3>
                          <p className="text-xs text-neutral-400 truncate">{song.artist}</p>
                          <p className="text-[10px] text-neutral-500 mt-2 opacity-0 group-hover:opacity-100 transition-opacity">
                            {new Date(h.played_at || Date.now()).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}
                          </p>
                       </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
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
