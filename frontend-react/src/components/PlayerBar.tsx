import { useState } from 'react';
import { 
  Play, 
  Pause, 
  SkipBack, 
  SkipForward, 
  Repeat, 
  Shuffle, 
  Volume2, 
  MonitorSpeaker,
  Mic2,
  Settings,
  Clock,
  ListMusic,
  PlusCircle
} from 'lucide-react';
import { useAudio } from '../context/AudioContext';
import LyricsOverlay from './LyricsOverlay';
import SleepTimerModal from './SleepTimerModal';
import QueuePanel from './QueuePanel';
import { getValidImage } from '../utils/imageUtils';

const PlayerBar = () => {
  const { 
    currentTrack, 
    isPlaying, 
    togglePlay, 
    currentTime, 
    setCurrentTime,
    duration, 
    setIsSeeking,
    volume,
    setVolume,
    repeatMode,
    isShuffle,
    toggleRepeat,
    toggleShuffle,
    playNext,
    playPrevious,
    remainingSleepTime,
    history,
    isBuffering,
    seekTo,
  } = useAudio();

  const [showLyrics, setShowLyrics] = useState(false);
  const [showSleepTimer, setShowSleepTimer] = useState(false);
  const [showDevicePicker, setShowDevicePicker] = useState(false);
  const [showQueue, setShowQueue] = useState(false);
  
  const handleSeekChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setIsSeeking(true);
    setCurrentTime(Number(e.target.value));
  };

  const handleSeekRelease = (e: React.ChangeEvent<HTMLInputElement> | React.MouseEvent | React.TouchEvent | React.KeyboardEvent) => {
    setIsSeeking(false);
    const target = e.target as HTMLInputElement;
    seekTo(Number(target.value));
  };

  const formatTime = (seconds: number) => {
    if (isNaN(seconds)) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  if (!currentTrack) return null;

  return (
    <>
      <footer className="fixed bottom-0 left-0 right-0 h-24 bg-black border-t border-neutral-800 px-4 flex items-center justify-between z-50">
        
        {/* Left: Track Info */}
        <div className="flex items-center gap-4 w-[30%]">
          <img 
            src={getValidImage(currentTrack)} 
            alt={currentTrack.title} 
            className="w-14 h-14 rounded shadow-lg object-cover"
            loading="lazy"
            onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
          />
          <div className="flex flex-col truncate">
            <h4 className="text-sm font-bold text-white hover:underline cursor-pointer truncate">
              {currentTrack.title}
            </h4>
            <p className="text-xs text-neutral-400 hover:text-white cursor-pointer truncate">
              {currentTrack.artist}
            </p>
          </div>
          <PlusCircle 
            size={20} 
            className="text-neutral-400 hover:text-white hover:scale-105 transition-all cursor-pointer flex-shrink-0"
            onClick={() => console.log("Open Playlist Modal")}
          />
        </div>

        {/* Center: Controls & Progress */}
        <div className="flex flex-col items-center max-w-[40%] w-full gap-2">
          <div className="flex items-center gap-6">
            <div className="relative group/shuffle">
              <Shuffle 
                size={18} 
                className={`cursor-pointer transition ${isShuffle ? 'text-green-500 hover:text-green-400' : 'text-neutral-500 hover:text-white'}`} 
                onClick={toggleShuffle}
              />
              <div className="absolute bottom-full mb-2 left-1/2 -translate-x-1/2 bg-neutral-800 text-white text-[10px] px-2 py-1 rounded opacity-0 group-hover/shuffle:opacity-100 transition whitespace-nowrap pointer-events-none border border-white/5">
                {isShuffle ? 'Disable Shuffle' : 'Enable Shuffle'}
              </div>
            </div>
            <SkipBack 
              size={24} 
              className={`transition ${
                history.length === 0 && currentTime < 3 
                ? 'text-neutral-600 cursor-not-allowed opacity-50' 
                : 'text-neutral-400 hover:text-white cursor-pointer hover:scale-105 active:scale-95'
            }`} 
            onClick={() => {
              if (history.length === 0 && currentTime < 3) return;
                playPrevious();
              }}
            />
            
            <div className="relative">
              <button 
                onClick={togglePlay}
                className="w-8 h-8 flex items-center justify-center bg-white rounded-full hover:scale-105 active:scale-95 transition disabled:opacity-50"
                disabled={isBuffering}
              >
                {isBuffering ? (
                  <div className="w-4 h-4 border-2 border-black border-t-transparent rounded-full animate-spin" />
                ) : isPlaying ? (
                  <Pause size={20} className="text-black fill-black" />
                ) : (
                  <Play size={20} className="text-black fill-black ml-1" />
                )}
              </button>
            </div>
            
            <SkipForward 
              size={24} 
              className="text-neutral-400 hover:text-white cursor-pointer transition" 
              onClick={playNext}
            />
            <div className="relative group">
              <Repeat 
                size={18} 
                className={`cursor-pointer transition ${repeatMode !== 'none' ? 'text-green-500' : 'text-neutral-400 hover:text-white'}`} 
                onClick={toggleRepeat}
              />
              {repeatMode === 'one' && (
                <span className="absolute -top-1 -right-1 bg-green-500 text-black text-[8px] font-bold w-3 h-3 flex items-center justify-center rounded-full pointer-events-none">
                  1
                </span>
              )}
              {/* Tooltip for accessibility/clarity */}
              <div className="absolute bottom-full mb-2 left-1/2 -translate-x-1/2 bg-neutral-800 text-white text-[10px] px-2 py-1 rounded opacity-0 group-hover:opacity-100 transition whitespace-nowrap pointer-events-none border border-white/5">
                {repeatMode === 'none' ? 'Enable Repeat' : repeatMode === 'all' ? 'Repeat All' : 'Repeat One'}
              </div>
            </div>
          </div>

          <div className="flex items-center gap-3 w-full">
            <span className="text-[10px] text-neutral-400 min-w-[30px] text-right">
              {formatTime(currentTime)}
            </span>
            <div className="relative group w-full flex items-center">
              <input 
                type="range"
                min={0}
                max={duration || 100}
                value={currentTime}
                onChange={handleSeekChange}
                onMouseUp={handleSeekRelease}
                onTouchEnd={handleSeekRelease}
                onKeyUp={handleSeekRelease}
                className="w-full h-1 bg-neutral-600 rounded-full appearance-none cursor-pointer accent-white group-hover:accent-green-500"
                style={{
                  background: `linear-gradient(to right, #1db954 ${(currentTime / (duration || 100)) * 100}%, #4d4d4d 0%)`
                }}
              />
            </div>
            <span className="text-[10px] text-neutral-400 min-w-[30px]">
              {formatTime(duration)}
            </span>
          </div>
        </div>

        {/* Right: Extra Controls */}
        <div className="flex items-center justify-end gap-3 w-[30%]">
          <div className="w-10" /> 

          <Mic2 
            size={18} 
            className={`cursor-pointer transition ${showLyrics ? 'text-green-500 hover:text-green-400' : 'text-neutral-400 hover:text-white'}`} 
            onClick={() => setShowLyrics(!showLyrics)}
          />

          <ListMusic 
            size={18} 
            className={`cursor-pointer transition ${showQueue ? 'text-green-500 hover:text-green-400' : 'text-neutral-400 hover:text-white'}`} 
            onClick={() => setShowQueue(!showQueue)}
          />
          
          <div className="relative flex items-center gap-1 group">
             <Clock 
               size={18} 
               className={`cursor-pointer transition ${remainingSleepTime !== null ? 'text-green-500' : 'text-neutral-400 group-hover:text-white'}`} 
               onClick={() => setShowSleepTimer(true)}
             />
             {remainingSleepTime !== null && (
               <span className="text-[10px] font-bold text-green-500">
                 {Math.ceil(remainingSleepTime / 60)}m
               </span>
             )}
          </div>
          
          <div className="relative">
            <MonitorSpeaker 
              size={18} 
              className={`cursor-pointer transition ${showDevicePicker ? 'text-green-500' : 'text-neutral-400 hover:text-white'}`} 
              onClick={() => setShowDevicePicker(!showDevicePicker)}
            />
            {showDevicePicker && (
              <div className="absolute bottom-10 right-0 bg-[#282828] rounded-xl shadow-2xl p-4 min-w-[200px] border border-white/10">
                <h5 className="text-xs font-bold text-white mb-3">Connect to a device</h5>
                <div className="space-y-2">
                  <div className="flex items-center gap-3 p-2 rounded-lg bg-green-500/10 border border-green-500/20 cursor-pointer">
                    <MonitorSpeaker size={16} className="text-green-500" />
                    <div>
                      <p className="text-[11px] font-bold text-green-500">This VAIO Laptop</p>
                      <p className="text-[10px] text-neutral-400">Web Player</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-3 p-2 rounded-lg hover:bg-white/5 cursor-not-allowed opacity-50">
                    <Settings size={16} className="text-neutral-400" />
                    <div>
                      <p className="text-[11px] font-bold text-white">Other Devices</p>
                      <p className="text-[10px] text-neutral-400">None detected</p>
                    </div>
                  </div>
                </div>
              </div>
            )}
          </div>

          <div className="flex items-center gap-2 group w-24 ml-2">
            <Volume2 size={18} className="text-neutral-400 group-hover:text-white" />
            <input 
              type="range"
              min={0}
              max={1}
              step={0.01}
              value={volume}
              onChange={(e) => setVolume(Number(e.target.value))}
              className="w-full h-1 bg-neutral-600 rounded-full appearance-none cursor-pointer accent-white group-hover:accent-green-500"
              style={{
                background: `linear-gradient(to right, #1db954 ${volume * 100}%, #4d4d4d 0%)`
              }}
            />
          </div>
        </div>
      </footer>

      {currentTrack && (
        <LyricsOverlay 
          song={currentTrack} 
          isOpen={showLyrics} 
          onClose={() => setShowLyrics(false)} 
        />
      )}

      <SleepTimerModal 
        isOpen={showSleepTimer} 
        onClose={() => setShowSleepTimer(false)} 
      />

      <QueuePanel 
        isOpen={showQueue} 
        onClose={() => setShowQueue(false)} 
      />

    </>
  );
};

export default PlayerBar;
