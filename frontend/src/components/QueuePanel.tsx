import React from 'react';
import { useAudio } from '../context/AudioContext';
import { X, GripVertical, Trash2 } from 'lucide-react';
import { DragDropContext, Droppable, Draggable } from '@hello-pangea/dnd';
import type { DropResult } from '@hello-pangea/dnd';

interface QueuePanelProps {
  isOpen: boolean;
  onClose: () => void;
}

const QueuePanel: React.FC<QueuePanelProps> = ({ isOpen, onClose }) => {
  const { userQueue, removeFromQueue, reorderQueue, currentTrack } = useAudio();

  const onDragEnd = (result: DropResult) => {
    if (!result.destination) return;
    reorderQueue(result.source.index, result.destination.index);
  };

  if (!isOpen) return null;

  return (
    <div className="fixed right-0 top-0 h-full w-80 bg-neutral-900 shadow-2xl z-[100] flex flex-col border-l border-white/5 animate-in slide-in-from-right duration-300">
      <div className="p-6 border-b border-white/5 flex items-center justify-between">
        <h3 className="font-bold text-xl text-white">Next Up</h3>
        <button 
          onClick={onClose} 
          className="p-1.5 hover:bg-neutral-800 rounded-full transition-colors text-neutral-400 hover:text-white"
        >
          <X size={24} />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto p-4 custom-scrollbar">
        {userQueue.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20 px-4 text-center">
            <p className="text-neutral-400 font-medium">Your queue is empty</p>
            <p className="text-xs text-neutral-500 mt-2">Add songs to play them next!</p>
          </div>
        ) : (
          <DragDropContext onDragEnd={onDragEnd}>
            <Droppable droppableId="queue-list">
              {(provided) => (
                <div 
                  {...provided.droppableProps} 
                  ref={provided.innerRef}
                  className="space-y-2"
                >
                  {userQueue.map((song, index) => (
                    <Draggable key={song.id} draggableId={song.id} index={index}>
                      {(provided, snapshot) => (
                        <div
                          ref={provided.innerRef}
                          {...provided.draggableProps}
                          className={`group flex items-center gap-3 p-2 rounded-md transition-all ${
                            snapshot.isDragging ? 'bg-neutral-800 shadow-xl' : 'hover:bg-neutral-800/60'
                          }`}
                        >
                          <div 
                            {...provided.dragHandleProps}
                            className="text-neutral-600 hover:text-neutral-400 cursor-grab active:cursor-grabbing"
                          >
                            <GripVertical size={16} />
                          </div>
                          
                          <img 
                            src={song.coverUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=50&h=50&fit=crop'} 
                            alt="" 
                            className="w-10 h-10 rounded shadow-md object-cover" 
                          />
                          
                          <div className="flex-1 min-w-0">
                            <p className="text-sm font-bold text-white truncate group-hover:text-green-500 transition-colors">
                              {song.title}
                            </p>
                            <p className="text-[10px] text-neutral-400 truncate uppercase tracking-tighter font-bold">
                              {song.artist}
                            </p>
                          </div>
                          
                          <button 
                            onClick={() => removeFromQueue(song.id)}
                            className="opacity-0 group-hover:opacity-100 p-2 hover:bg-red-500/10 hover:text-red-500 rounded-full transition-all text-neutral-600"
                          >
                            <Trash2 size={14} />
                          </button>
                        </div>
                      )}
                    </Draggable>
                  ))}
                  {provided.placeholder}
                </div>
              )}
            </Droppable>
          </DragDropContext>
        )}
      </div>

      {currentTrack && (
        <div className="p-6 bg-neutral-950/50 border-t border-white/5 mt-auto">
          <p className="text-[10px] uppercase font-bold text-green-500 mb-4 tracking-widest">Now Playing</p>
          <div className="flex items-center gap-4 group">
             <div className="relative w-12 h-12 flex-shrink-0">
                <img src={currentTrack.coverUrl} alt="" className="w-full h-full rounded shadow-2xl object-cover" />
                <div className="absolute inset-0 bg-green-500/20 animate-pulse rounded"></div>
             </div>
             <div className="min-w-0">
               <p className="text-[15px] font-black text-white truncate">{currentTrack.title}</p>
               <p className="text-xs text-neutral-400 truncate">{currentTrack.artist}</p>
             </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default QueuePanel;
