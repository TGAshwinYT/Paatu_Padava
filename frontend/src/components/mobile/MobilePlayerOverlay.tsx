import React, { useState } from 'react';
import { Play, Pause, SkipBack, SkipForward, Shuffle, Repeat, ChevronDown, Share2, MoreHorizontal, Clock, Speaker, ListMusic, Heart, PlusCircle, Mic2 } from 'lucide-react';
import { useAudio } from '../../context/AudioContext';
import SleepTimerModal from '../SleepTimerModal';
import QueueDrawer from './QueueDrawer';
import LyricsOverlay from '../LyricsOverlay';
import { usePlaylistModal } from '../../context/PlaylistModalContext';
import { getValidImage } from '../../utils/imageUtils';

const MobilePlayerOverlay: React.FC = () => {
  const { 
    currentTrack, 
    isPlaying, 
    togglePlay, 
    playNext, 
    playPrevious, 
    currentTime, 
    setCurrentTime,
    duration, 
    setIsSeeking,
    isShuffle, 
    repeatMode, 
    toggleShuffle, 
    toggleRepeat, 
    remainingSleepTime,
    audioRef
  } = useAudio();
  const [isExpanded, setIsExpanded] = useState(false);
  const [showSleepTimer, setShowSleepTimer] = useState(false);
  const [isQueueOpen, setIsQueueOpen] = useState(false);
  const [isLyricsOpen, setIsLyricsOpen] = useState(false);
  const [isLiked, setIsLiked] = useState(false);
  const { openModal } = usePlaylistModal();
  
  const handleSeekChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setIsSeeking(true);
    setCurrentTime(Number(e.target.value));
  };

  const handleSeekRelease = (e: React.ChangeEvent<HTMLInputElement> | React.MouseEvent | React.TouchEvent | React.KeyboardEvent) => {
    setIsSeeking(false);
    const target = e.target as HTMLInputElement;
    if (audioRef.current) {
      audioRef.current.currentTime = Number(target.value);
    }
  };

  const formatTime = (time: number) => {
    const mins = Math.floor(time / 60);
    const secs = Math.floor(time % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  if (!currentTrack) return null;

  if (!isExpanded) {
    return (
      <div 
        onClick={() => setIsExpanded(true)}
        className="fixed bottom-[90px] left-2 right-2 bg-neutral-800 rounded-lg p-2 h-14 flex items-center justify-between z-50 animate-in slide-in-from-bottom"
      >
        <div className="flex items-center gap-3 truncate">
          <img 
            src={getValidImage(currentTrack)} 
            className="w-10 h-10 rounded object-cover shadow-lg" 
            alt="" 
            onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
          />
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
        <div className="absolute bottom-0 left-0 h-[2px] bg-white transition-all" style={{ width: `${(currentTime/duration)*100}%` }} />
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-[60] bg-neutral-900 flex flex-col p-6 animate-in slide-in-from-bottom duration-500 overflow-hidden">
      {/* Background Blur */}
      <div 
        className="absolute inset-0 opacity-40 blur-[100px] pointer-events-none scale-150 transition-all duration-1000"
        style={{ background: `url(${getValidImage(currentTrack)}) no-repeat center center`, backgroundSize: 'cover' }}
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
          src={getValidImage(currentTrack)} 
          className="w-full aspect-square rounded-lg shadow-2xl object-cover" 
          alt="" 
          onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
        />
      </div>

      {/* Title & Controls */}
      <div className="z-10 mt-6">
        <div className="flex items-center justify-between mb-4">
          <div className="truncate w-full pr-4">
            <h1 className="text-2xl font-black text-white truncate">{currentTrack.title}</h1>
            <p className="text-lg text-neutral-400 font-medium truncate">{currentTrack.artist}</p>
          </div>
        </div>

        {/* Secondary Actions Row */}
        <div className="flex justify-between items-center w-full px-2 mb-6 text-gray-400">
            {/* Like Button */}
            <button onClick={() => setIsLiked(!isLiked)} className="hover:text-white transition-colors p-2">
                {isLiked ? <Heart className="w-6 h-6 text-green-500" fill="currentColor" /> : <Heart className="w-6 h-6 text-white" />}
            </button>

            {/* Add to Playlist */}
            <button onClick={() => openModal(currentTrack)} className="hover:text-white transition-colors p-2">
                <PlusCircle className="w-6 h-6" />
            </button>

            {/* Lyrics Button */}
            <button onClick={() => setIsLyricsOpen(!isLyricsOpen)} className="hover:text-white transition-colors p-2">
                <Mic2 className={`w-6 h-6 ${isLyricsOpen ? 'text-green-500' : ''}`} />
            </button>

            {/* Queue & Timer Button */}
            <button onClick={() => setIsQueueOpen(!isQueueOpen)} className="hover:text-white transition-colors p-2">
                <ListMusic className={`w-6 h-6 ${isQueueOpen ? 'text-green-500' : ''}`} />
            </button>
        </div>

        {/* Seek Bar */}
        <div className="mb-6">
          <input 
            type="range"
            min={0}
            max={duration || 100}
            value={currentTime}
            onChange={handleSeekChange}
            onMouseUp={handleSeekRelease}
            onTouchEnd={handleSeekRelease}
            onKeyUp={handleSeekRelease}
            className="w-full h-1 bg-neutral-600 rounded-lg appearance-none accent-white mb-2"
          />
          <div className="flex justify-between text-[10px] font-bold text-neutral-400 uppercase">
            <span>{formatTime(currentTime)}</span>
            <span>{formatTime(duration)}</span>
          </div>
        </div>

        {/* Main Controls */}
        <div className="flex items-center justify-between mb-8">
          <button onClick={toggleShuffle} className={isShuffle ? 'text-green-500' : 'text-white'}>
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
          <button onClick={toggleRepeat} className={repeatMode !== 'none' ? 'text-green-500' : 'text-white'}>
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

      <LyricsOverlay 
        song={currentTrack} 
        isOpen={isLyricsOpen} 
        onClose={() => setIsLyricsOpen(false)} 
      />

    </div>
  );
};

export default MobilePlayerOverlay;
