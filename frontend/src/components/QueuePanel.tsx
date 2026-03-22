import React from 'react';
import { useAudio } from '../context/AudioContext';
import { X, GripVertical, Trash2 } from 'lucide-react';

interface QueuePanelProps {
  isOpen: boolean;
  onClose: () => void;
}

const QueuePanel: React.FC<QueuePanelProps> = ({ isOpen, onClose }) => {
  const { userQueue, removeFromQueue, reorderQueue, currentTrack } = useAudio();

  const handleDragStart = (e: React.DragEvent, index: number) => {
    e.dataTransfer.setData('text/plain', index.toString());
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
  };

  const handleDrop = (e: React.DragEvent, dropIndex: number) => {
    e.preventDefault();
    const dragIndex = parseInt(e.dataTransfer.getData('text/plain'), 10);
    if (dragIndex === dropIndex) return;
    reorderQueue(dragIndex, dropIndex);
  };

  if (!isOpen) return null;

  return (
    <div className="fixed bottom-24 right-4 w-80 max-h-[70vh] bg-[#181818] border border-white/10 rounded-xl shadow-2xl z-[60] flex flex-col overflow-hidden animate-in slide-in-from-bottom-4 duration-300">
      <div className="p-4 border-b border-white/5 flex items-center justify-between bg-[#282828]/50">
        <h3 className="font-bold text-white flex items-center gap-2">
          Queue
          <span className="text-xs text-neutral-400 font-normal">({userQueue.length} tracks)</span>
        </h3>
        <button onClick={onClose} className="p-1 hover:bg-neutral-700 rounded-full transition-colors text-neutral-400 hover:text-white">
          <X size={20} />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto p-2 custom-scrollbar space-y-1">
        {userQueue.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-10 px-4 text-center">
            <p className="text-neutral-400 text-sm">Your queue is empty</p>
            <p className="text-[10px] text-neutral-500 mt-1">Add songs to play them next!</p>
          </div>
        ) : (
          userQueue.map((song, index) => (
            <div
              key={`${song.id}-${index}`}
              draggable
              onDragStart={(e) => handleDragStart(e, index)}
              onDragOver={handleDragOver}
              onDrop={(e) => handleDrop(e, index)}
              className="group flex items-center gap-2 p-2 rounded-lg hover:bg-white/5 transition-colors cursor-default"
            >
              <div className="text-neutral-600 group-hover:text-neutral-400 cursor-grab active:cursor-grabbing transition-colors">
                <GripVertical size={16} />
              </div>
              <img src={song.coverUrl} alt="" className="w-10 h-10 rounded shadow-md" />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-bold text-white truncate">{song.title}</p>
                <p className="text-[10px] text-neutral-400 truncate">{song.artist}</p>
              </div>
              <button 
                onClick={() => removeFromQueue(song.id)}
                className="opacity-0 group-hover:opacity-100 p-1.5 hover:bg-red-500/20 hover:text-red-500 rounded-md transition-all text-neutral-500"
              >
                <Trash2 size={14} />
              </button>
            </div>
          ))
        )}
      </div>

      {currentTrack && (
        <div className="p-3 bg-[#1db954]/10 border-t border-white/5">
          <p className="text-[10px] uppercase font-bold text-[#1db954] mb-2 tracking-wider">Now Playing</p>
          <div className="flex items-center gap-3">
             <img src={currentTrack.coverUrl} alt="" className="w-10 h-10 rounded animate-pulse shadow-lg" />
             <div className="min-w-0">
               <p className="text-sm font-bold text-white truncate">{currentTrack.title}</p>
               <p className="text-[10px] text-neutral-400 truncate">{currentTrack.artist}</p>
             </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default QueuePanel;
