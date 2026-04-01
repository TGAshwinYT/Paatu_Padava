import React from 'react';
import { useAudio } from '../context/AudioContext';
import { X, Menu, Trash2, Shuffle } from 'lucide-react';
import { DragDropContext, Droppable, Draggable } from '@hello-pangea/dnd';
import { getValidImage } from '../utils/imageUtils';

interface QueuePanelProps {
  isOpen: boolean;
  onClose: () => void;
}

const QueuePanel: React.FC<QueuePanelProps> = ({ isOpen, onClose }) => {
  const { queue, removeFromQueue, handleOnDragEnd, currentTrack } = useAudio();

  if (!isOpen) return null;

  const manualQueue = queue.filter(song => song.isManual);
  const autoQueue = queue.filter(song => !song.isManual);

  const renderSongRow = (song: any, index: number) => (
    <Draggable 
      key={`queue-${song.id}-${index}`} 
      draggableId={`queue-${song.id}-${index}`} 
      index={index}
    >
      {(provided, snapshot) => (
        <div
          ref={provided.innerRef}
          {...provided.draggableProps}
          className={`group flex items-center gap-3 p-2 rounded-md transition-all ${
            snapshot.isDragging ? 'bg-[#282828] shadow-2xl scale-[1.02]' : 'hover:bg-white/10'
          }`}
        >
          <img 
            src={getValidImage(song)} 
            alt="" 
            className="w-12 h-12 rounded shadow-lg object-cover flex-shrink-0" 
            onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
          />
          
          <div className="flex-1 min-w-0">
            <p className="text-sm font-bold truncate text-white">
              {song.title}
            </p>
            <p className="text-xs text-[#b3b3b3] truncate font-medium">
              {song.artist}
            </p>
          </div>
          
          <div className="flex items-center gap-2">
            <button 
              onClick={() => removeFromQueue(song.id)}
              className="opacity-0 group-hover:opacity-100 p-2 hover:bg-red-500/10 hover:text-red-500 rounded-full transition-all text-neutral-500"
              title="Remove from queue"
            >
              <Trash2 size={16} />
            </button>
            <div 
              {...provided.dragHandleProps}
              className="text-neutral-500 hover:text-white p-2 cursor-grab active:cursor-grabbing"
            >
              <Menu size={20} />
            </div>
          </div>
        </div>
      )}
    </Draggable>
  );

  return (
    <div className="fixed right-0 top-0 h-full w-full md:w-[400px] bg-[#121212] text-white shadow-2xl z-[100] flex flex-col border-l border-white/5 animate-in slide-in-from-right duration-300">
      <div className="p-6 border-b border-white/5 flex items-center justify-between">
        <h2 className="text-2xl font-black tracking-tight">Queue</h2>
        <button 
          onClick={onClose} 
          className="p-2 hover:bg-white/10 rounded-full transition-colors text-neutral-400 hover:text-white"
        >
          <X size={24} />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto p-4 custom-scrollbar space-y-8">
        {queue.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20 px-4 text-center">
            <p className="text-neutral-400 font-medium">Your queue is empty</p>
            <p className="text-xs text-neutral-500 mt-2">Add songs to play them next!</p>
          </div>
        ) : (
          <DragDropContext onDragEnd={handleOnDragEnd}>
            <Droppable droppableId="queue-list">
              {(provided) => (
                <div 
                  {...provided.droppableProps} 
                  ref={provided.innerRef}
                  className="space-y-6"
                >
                  {/* User Added Section */}
                  {manualQueue.length > 0 && (
                    <section>
                      <h3 className="text-xs font-bold text-[#b3b3b3] mb-4 uppercase tracking-[0.1em] px-2">
                        Next In Queue
                      </h3>
                      <div className="space-y-1">
                        {manualQueue.map((song, i) => renderSongRow(song, i))}
                      </div>
                    </section>
                  )}

                  {/* Auto/Radio Section */}
                  {autoQueue.length > 0 && (
                    <section>
                      <h3 className="text-xs font-bold text-[#b3b3b3] mb-4 flex items-center gap-2 uppercase tracking-[0.1em] px-2">
                        <Shuffle className="w-3.5 h-3.5 text-green-500" />
                        Next From: Radio Mix
                      </h3>
                      <div className="space-y-1">
                        {autoQueue.map((song, i) => renderSongRow(song, manualQueue.length + i))}
                      </div>
                    </section>
                  )}
                  {provided.placeholder}
                </div>
              )}
            </Droppable>
          </DragDropContext>
        )}
      </div>

      {currentTrack && (
        <div className="p-6 bg-neutral-900/80 backdrop-blur-md border-t border-white/5 mt-auto">
          <p className="text-[10px] uppercase font-bold text-green-500 mb-4 tracking-widest">Now Playing</p>
          <div className="flex items-center gap-4 group">
             <div className="relative w-12 h-12 flex-shrink-0">
                <img 
                  src={getValidImage(currentTrack)} 
                  alt="" 
                  className="w-full h-full rounded shadow-2xl object-cover" 
                  onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                />
                <div className="absolute inset-0 bg-green-500/20 animate-pulse rounded"></div>
             </div>
             <div className="min-w-0 flex-1">
               <p className="text-sm font-bold text-white truncate">{currentTrack.title}</p>
               <p className="text-xs text-[#b3b3b3] truncate">{currentTrack.artist}</p>
             </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default QueuePanel;
