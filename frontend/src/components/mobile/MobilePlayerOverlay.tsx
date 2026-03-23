import React, { useState } from 'react';
import { Play, Pause, SkipBack, SkipForward, Shuffle, Repeat, ChevronDown, Share2, MoreHorizontal, Clock, Speaker, ListMusic } from 'lucide-react';
import { useAudio } from '../../context/AudioContext';
import SleepTimerModal from '../SleepTimerModal';
import QueueDrawer from './QueueDrawer';

const MobilePlayerOverlay: React.FC = () => {
  const { currentTrack, isPlaying, togglePlay, playNext, playPrevious, progress, duration, seekTo, isShuffled, isRepeating, toggleShuffle, toggleRepeat, remainingSleepTime } = useAudio();
  const [isExpanded, setIsExpanded] = useState(false);
  const [showSleepTimer, setShowSleepTimer] = useState(false);
  const [isQueueOpen, setIsQueueOpen] = useState(false);

  if (!currentTrack) return null;

  const formatTime = (time: number) => {
    const mins = Math.floor(time / 60);
    const secs = Math.floor(time % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  if (!isExpanded) {
    return (
      <div 
        onClick={() => setIsExpanded(true)}
        className="fixed bottom-[90px] left-2 right-2 bg-neutral-800 rounded-lg p-2 h-14 flex items-center justify-between z-50 animate-in slide-in-from-bottom"
      >
        <div className="flex items-center gap-3 truncate">
          <img src={currentTrack.coverUrl} className="w-10 h-10 rounded object-cover shadow-lg" alt="" />
          <div className="truncate">
            <p className="text-sm font-bold truncate text-white">{currentTrack.title}</p>
            <p className="text-[10px] text-neutral-400 truncate">{currentTrack.artist}</p>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <button onClick={(e) => { e.stopPropagation(); togglePlay(); }} className="p-2">
            {isPlaying ? <Pause size={24} fill="white" /> : <Play size={24} fill="white" />}
          </button>
        </div>
        {/* Progress Bar Mini */}
        <div className="absolute bottom-0 left-0 h-[2px] bg-white transition-all" style={{ width: `${(progress/duration)*100}%` }} />
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-[60] bg-neutral-900 flex flex-col p-6 animate-in slide-in-from-bottom duration-500 overflow-hidden">
      {/* Background Blur */}
      <div 
        className="absolute inset-0 opacity-40 blur-[100px] pointer-events-none scale-150 transition-all duration-1000"
        style={{ background: `url(${currentTrack.coverUrl}) no-repeat center center`, backgroundSize: 'cover' }}
      />

      {/* Header */}
      <div className="flex items-center justify-between mb-8 z-10">
        <button onClick={() => setIsExpanded(false)} className="p-2 -ml-2">
          <ChevronDown size={32} />
        </button>
        <div className="text-center">
          <p className="text-[10px] font-bold uppercase tracking-widest text-neutral-400">Playing from</p>
          <p className="text-sm font-bold"> Paaatu_Padava</p>
        </div>
        <button className="p-2 -mr-2">
          <MoreHorizontal size={24} />
        </button>
      </div>

      {/* Album Art */}
      <div className="flex-1 flex items-center justify-center py-4 z-10">
        <img 
          src={currentTrack.coverUrl} 
          className="w-full aspect-square rounded-lg shadow-2xl object-cover" 
          alt="" 
        />
      </div>

      {/* Title & Controls */}
      <div className="z-10 mt-6">
        <div className="flex items-center justify-between mb-6">
          <div className="truncate max-w-[80%]">
            <h1 className="text-2xl font-black text-white truncate">{currentTrack.title}</h1>
            <p className="text-lg text-neutral-400 font-medium truncate">{currentTrack.artist}</p>
          </div>
          <button className="text-green-500">
             {/* Dynamic Heart Icon could go here */}
          </button>
        </div>

        {/* Seek Bar */}
        <div className="mb-6">
          <input 
            type="range"
            min={0}
            max={duration || 100}
            value={progress}
            onChange={(e) => seekTo(Number(e.target.value))}
            className="w-full h-1 bg-neutral-600 rounded-lg appearance-none accent-white mb-2"
          />
          <div className="flex justify-between text-[10px] font-bold text-neutral-400 uppercase">
            <span>{formatTime(progress)}</span>
            <span>{formatTime(duration)}</span>
          </div>
        </div>

        {/* Main Controls */}
        <div className="flex items-center justify-between mb-8">
          <button onClick={toggleShuffle} className={isShuffled ? 'text-green-500' : 'text-white'}>
            <Shuffle size={24} />
          </button>
          <button onClick={playPrevious} className="text-white">
            <SkipBack size={36} fill="white" />
          </button>
          <button 
            onClick={togglePlay} 
            className="bg-white text-black p-5 rounded-full transform active:scale-95 transition-transform"
          >
            {isPlaying ? <Pause size={36} fill="black" /> : <Play size={36} fill="black" />}
          </button>
          <button onClick={playNext} className="text-white">
            <SkipForward size={36} fill="white" />
          </button>
          <button onClick={toggleRepeat} className={isRepeating ? 'text-green-500' : 'text-white'}>
            <Repeat size={24} />
          </button>
        </div>

        {/* Footer Icons */}
        <div className="flex items-center justify-between px-2 pb-8">
           <Speaker size={20} className="text-neutral-400" />
           <div className="flex gap-8 items-center">
              <Share2 size={20} className="text-neutral-400" />
              <div className="relative group" onClick={() => setShowSleepTimer(true)}>
                 <Clock size={20} className={remainingSleepTime !== null ? 'text-green-500' : 'text-neutral-400'} />
                 {remainingSleepTime !== null && (
                   <span className="absolute -top-1 -right-4 text-[8px] font-bold text-green-500">
                     {Math.ceil(remainingSleepTime / 60)}m
                   </span>
                 )}
              </div>
              <button onClick={() => setIsQueueOpen(true)} className="p-1">
                 <ListMusic size={20} className="text-neutral-400" />
              </button>
           </div>
        </div>
      </div>

      <SleepTimerModal 
        isOpen={showSleepTimer} 
        onClose={() => setShowSleepTimer(false)} 
      />

      <QueueDrawer 
        isOpen={isQueueOpen} 
        onClose={() => setIsQueueOpen(false)} 
      />
    </div>
  );
};

export default MobilePlayerOverlay;
