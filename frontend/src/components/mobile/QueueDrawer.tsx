import React from 'react';
import { X, Music } from 'lucide-react';
import { useAudio } from '../../context/AudioContext';

interface QueueDrawerProps {
  isOpen: boolean;
  onClose: () => void;
}

const QueueDrawer: React.FC<QueueDrawerProps> = ({ isOpen, onClose }) => {
  const { queue, removeFromQueue, currentTrack } = useAudio();

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-[100] flex flex-col justify-end bg-black/60 backdrop-blur-sm animate-in fade-in duration-300">
      {/* Click outside to close */}
      <div className="absolute inset-0" onClick={onClose} />
      
      <div 
        className={`relative w-full max-h-[70vh] bg-neutral-900 rounded-t-[32px] p-6 pb-12 flex flex-col shadow-2xl transition-transform duration-300 transform ${
          isOpen ? 'translate-y-0' : 'translate-y-full'
        } animate-in slide-in-from-bottom duration-500`}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Handle bar */}
        <div className="w-12 h-1.5 bg-neutral-700 rounded-full mx-auto mb-6" />

        <div className="flex items-center justify-between mb-6">
          <h2 className="text-xl font-bold text-white flex items-center gap-2">
            <Music size={20} className="text-green-500" />
            Up Next
          </h2>
          <button 
            onClick={onClose}
            className="p-2 bg-neutral-800 rounded-full text-neutral-400 active:scale-95 transition-transform"
          >
            <X size={20} />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto space-y-4 pr-2">
          {queue.length === 0 ? (
            <div className="text-center py-12">
              <p className="text-neutral-500 italic">Queue is empty</p>
              <p className="text-xs text-neutral-600 mt-2">Add some songs to see them here!</p>
            </div>
          ) : (
            queue.map((track, index) => (
              <div 
                key={`queue-mobile-${track.id}-${index}`} 
                className={`flex items-center gap-4 rounded-xl p-2 transition-colors ${
                  currentTrack?.id === track.id ? 'bg-neutral-800/50' : 'hover:bg-neutral-800/30'
                }`}
              >
                <img 
                  src={track?.cover_url || track?.coverUrl || track?.image || track?.thumbnail || '/logo.png'} 
                  alt={track?.title || "Song Cover"} 
                  className="w-12 h-12 rounded-lg object-cover shadow-md"
                  loading="lazy"
                  onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                />
                <div className="flex-1 min-w-0">
                  <p className={`text-sm font-bold truncate ${
                    currentTrack?.id === track.id ? 'text-green-500' : 'text-white'
                  }`}>
                    {track.title}
                  </p>
                  <p className="text-xs text-neutral-400 truncate">{track.artist}</p>
                </div>
                <button 
                  onClick={() => removeFromQueue(track.id)}
                  className="p-2 text-neutral-500 hover:text-red-400 active:scale-90 transition-all"
                >
                  <X size={18} />
                </button>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
};

export default QueueDrawer;
