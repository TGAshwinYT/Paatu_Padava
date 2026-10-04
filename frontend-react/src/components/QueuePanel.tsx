import React from 'react';
import { useAudio } from '../context/AudioContext';
import { X, Menu, Trash2, Radio } from 'lucide-react';
import { DragDropContext, Droppable, Draggable } from '@hello-pangea/dnd';

interface QueuePanelProps {
  isOpen: boolean;
  onClose: () => void;
}

const QueuePanel: React.FC<QueuePanelProps> = ({ isOpen, onClose }) => {
  const { queue, removeFromQueue, handleOnDragEnd, currentTrack, isAutoplay, toggleAutoplay } = useAudio();

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
            src={song?.cover_url || song?.coverUrl || song?.image || song?.thumbnail || '/logo.png'} 
            alt={song?.title || "Song Cover"} 
            className="w-12 h-12 rounded shadow-lg object-cover flex-shrink-0" 
            loading="lazy"
            onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
          />
          
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <p className="text-sm font-bold truncate text-white">
                {song.title}
              </p>
              {(song.isRadio || !song.isManual) && (
                <span className="flex-shrink-0 text-[10px] font-semibold text-brand bg-brand/10 border border-brand/20 px-1.5 py-0.2 rounded flex items-center gap-1">
                  <Radio size={9} />
                  Radio
                </span>
              )}
            </div>
            <p className="text-xs text-muted truncate font-medium">
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
    <div className="fixed right-0 top-0 h-full w-full md:w-[400px] bg-surface-base text-white shadow-2xl z-[100] flex flex-col border-l border-white/5 animate-in slide-in-from-right duration-300">
      <div className="p-6 border-b border-white/5 flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-black tracking-tight">Queue</h2>
          <div className="flex items-center gap-2 mt-1">
            <span className="text-xs text-muted">Autoplay</span>
            <button
              type="button"
              onClick={toggleAutoplay}
              className={`relative inline-flex h-4 w-8 items-center rounded-full transition-colors duration-200 focus:outline-none ${
                isAutoplay ? 'bg-brand' : 'bg-neutral-700'
              }`}
              title={isAutoplay ? 'Autoplay is ON: Similar songs keep playing' : 'Autoplay is OFF'}
            >
              <span
                className={`inline-block h-3 w-3 transform rounded-full bg-white transition duration-200 ease-in-out ${
                  isAutoplay ? 'translate-x-4' : 'translate-x-0.5'
                }`}
              />
            </button>
            <span className="text-[10px] text-neutral-400">
              {isAutoplay ? 'Similar songs keep playing' : 'Stops when queue ends'}
            </span>
          </div>
        </div>
        <button 
          onClick={onClose} 
          className="p-2 hover:bg-white/10 rounded-full transition-colors text-muted hover:text-white"
        >
          <X size={24} />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto p-4 custom-scrollbar space-y-8">
        {queue.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20 px-4 text-center">
            <p className="text-muted font-medium">Your queue is empty</p>
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
                      <h3 className="text-xs font-bold text-muted mb-4 uppercase tracking-[0.1em] px-2">
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
                      <div className="flex items-center justify-between mb-4 px-2">
                        <h3 className="text-xs font-bold text-muted flex items-center gap-2 uppercase tracking-[0.1em]">
                          <Radio className="w-3.5 h-3.5 text-brand" />
                          Recommended & Radio
                        </h3>
                        {isAutoplay && (
                          <span className="text-[10px] text-brand/90 bg-brand/10 border border-brand/20 px-2 py-0.5 rounded-full font-medium flex items-center gap-1">
                            <span className="w-1.5 h-1.5 rounded-full bg-brand animate-ping inline-block" />
                            Infinite Radio
                          </span>
                        )}
                      </div>
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
        <div className="p-6 bg-surface-card/90 backdrop-blur-md border-t border-white/5 mt-auto">
          <p className="text-[10px] uppercase font-bold text-brand mb-4 tracking-widest">Now Playing</p>
          <div className="flex items-center gap-4 group">
             <div className="relative w-12 h-12 flex-shrink-0">
                <img 
                  src={currentTrack?.cover_url || currentTrack?.coverUrl || currentTrack?.image || currentTrack?.thumbnail || '/logo.png'} 
                  alt={currentTrack?.title || "Song Cover"} 
                  className="w-full h-full rounded shadow-2xl object-cover" 
                  onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
                />
                <div className="absolute inset-0 bg-brand/20 animate-pulse rounded"></div>
             </div>
             <div className="min-w-0 flex-1">
               <p className="text-sm font-bold text-white truncate">{currentTrack.title}</p>
               <p className="text-xs text-muted truncate">{currentTrack.artist}</p>
             </div>
          </div>
        </div>
      )}

    </div>
  );
};

export default QueuePanel;
