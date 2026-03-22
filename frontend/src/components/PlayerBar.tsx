import React, { useState } from 'react';
import { 
  Play, 
  Pause, 
  SkipBack, 
  SkipForward, 
  Repeat, 
  Shuffle, 
  Volume2, 
  ListMusic, 
  MonitorSpeaker,
  Mic2,
  ChevronUp,
  Settings,
  Clock
} from 'lucide-react';
import { useAudio } from '../context/AudioContext';
import LyricsOverlay from './LyricsOverlay';
import SleepTimerModal from './SleepTimerModal';

const PlayerBar = () => {
  const { 
    currentTrack, 
    isPlaying, 
    togglePlay, 
    progress, 
    duration, 
    seekTo,
    volume,
    setVolume,
    isRepeating,
    isShuffled,
    toggleRepeat,
    toggleShuffle,
    audioQuality,
    setAudioQuality,
    playNext,
    playPrevious,
    remainingSleepTime
  } = useAudio();

  const [showLyrics, setShowLyrics] = useState(false);
  const [showSleepTimer, setShowSleepTimer] = useState(false);
  const [showQualityMenu, setShowQualityMenu] = useState(false);
  const [showDevicePicker, setShowDevicePicker] = useState(false);

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
            src={currentTrack.coverUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=100&h=100&fit=crop'} 
            alt={currentTrack.title} 
            className="w-14 h-14 rounded shadow-lg object-cover"
          />
          <div className="flex flex-col truncate">
            <h4 className="text-sm font-bold text-white hover:underline cursor-pointer truncate">
              {currentTrack.title}
            </h4>
            <p className="text-xs text-neutral-400 hover:text-white cursor-pointer truncate">
              {currentTrack.artist}
            </p>
          </div>
        </div>

        {/* Center: Controls & Progress */}
        <div className="flex flex-col items-center max-w-[40%] w-full gap-2">
          <div className="flex items-center gap-6">
            <Shuffle 
              size={18} 
              className={`cursor-pointer transition ${isShuffled ? 'text-green-500' : 'text-neutral-500 hover:text-white'}`} 
              onClick={toggleShuffle}
            />
            <SkipBack 
              size={24} 
              className="text-neutral-400 hover:text-white cursor-pointer transition" 
              onClick={playPrevious}
            />
            
            <button 
              onClick={togglePlay}
              className="w-8 h-8 flex items-center justify-center bg-white rounded-full hover:scale-105 active:scale-95 transition"
            >
              {isPlaying ? (
                <Pause size={20} className="text-black fill-black" />
              ) : (
                <Play size={20} className="text-black fill-black ml-1" />
              )}
            </button>
            
            <SkipForward 
              size={24} 
              className="text-neutral-400 hover:text-white cursor-pointer transition" 
              onClick={playNext}
            />
            <Repeat 
              size={18} 
              className={`cursor-pointer transition ${isRepeating ? 'text-green-500' : 'text-neutral-400 hover:text-white'}`} 
              onClick={toggleRepeat}
            />
          </div>

          <div className="flex items-center gap-3 w-full">
            <span className="text-[10px] text-neutral-400 min-w-[30px] text-right">
              {formatTime(progress)}
            </span>
            <div className="relative group w-full flex items-center">
              <input 
                type="range"
                min={0}
                max={duration || 100}
                value={progress}
                onChange={(e) => seekTo(Number(e.target.value))}
                className="w-full h-1 bg-neutral-600 rounded-full appearance-none cursor-pointer accent-white group-hover:accent-green-500"
                style={{
                  background: `linear-gradient(to right, #1db954 ${(progress / (duration || 100)) * 100}%, #4d4d4d 0%)`
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
          <div className="relative">
             <button 
               onClick={() => setShowQualityMenu(!showQualityMenu)}
               className="text-[10px] font-bold text-neutral-400 hover:text-white border border-neutral-700 px-1.5 py-0.5 rounded uppercase flex items-center gap-1"
             >
               {audioQuality === 'high' ? '320' : audioQuality === 'medium' ? '160' : '96'}kbps
               <ChevronUp size={10} className={showQualityMenu ? 'rotate-180 transition' : 'transition'} />
             </button>
             
             {showQualityMenu && (
               <div className="absolute bottom-10 right-0 bg-[#282828] rounded shadow-xl py-1 min-w-[80px] border border-white/5">
                 {(['low', 'medium', 'high'] as const).map((q) => (
                   <button
                     key={q}
                     onClick={() => { setAudioQuality(q); setShowQualityMenu(false); }}
                     className={`w-full text-left px-3 py-1.5 text-[10px] font-bold uppercase hover:bg-white/10 ${audioQuality === q ? 'text-green-500' : 'text-white'}`}
                   >
                     {q === 'high' ? 'High (320)' : q === 'medium' ? 'Med (160)' : 'Low (96)'}
                   </button>
                 ))}
               </div>
             )}
          </div>

          <Mic2 
            size={18} 
            className={`cursor-pointer transition ${showLyrics ? 'text-green-500 hover:text-green-400' : 'text-neutral-400 hover:text-white'}`} 
            onClick={() => setShowLyrics(!showLyrics)}
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
    </>
  );
};

export default PlayerBar;
