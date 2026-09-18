import { useState, useEffect } from 'react';
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
  PlusCircle,
  Heart,
  ChevronDown,
  ChevronUp,
  SlidersHorizontal,
  Download,
  Radio,
  Loader2,
  Check
} from 'lucide-react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useAudio } from '../context/AudioContext';
import { usePlaylistModal } from '../context/PlaylistModalContext';
import { useAuth } from '../context/AuthContext';
import { likeSong, unlikeSong } from '../services/api';
import LyricsOverlay from './LyricsOverlay';
import SleepTimerModal from './SleepTimerModal';
import QueuePanel from './QueuePanel';
import EqualizerPanel from './EqualizerPanel';
import { getValidImage } from '../utils/imageUtils';
import { isOfflineTrack } from '../utils/offlineStorage';

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
    // Equalizer
    eqBands,
    eqPreset,
    isEqAvailable,
    setEqBandGain,
    applyEqPreset,
    // Autoplay & Download
    startSongRadio,
    downloadCurrentTrack,
  } = useAudio();

  const navigate = useNavigate();
  const location = useLocation();
  const { user } = useAuth();
  const { openModal } = usePlaylistModal();
  const [isLiked, setIsLiked] = useState(false);

  const [showLyrics, setShowLyrics] = useState(false);
  const [showSleepTimer, setShowSleepTimer] = useState(false);
  const [showDevicePicker, setShowDevicePicker] = useState(false);
  const [showQueue, setShowQueue] = useState(false);
  const [showEqualizer, setShowEqualizer] = useState(false);

  // ─── Download & Song Radio States ──────────────────────────────────────────
  const [isDownloading, setIsDownloading] = useState(false);
  const [downloadSuccess, setDownloadSuccess] = useState(false);
  const [isRadioStarting, setIsRadioStarting] = useState(false);
  const [isCurrentlyOffline, setIsCurrentlyOffline] = useState(false);

  useEffect(() => {
    if (currentTrack?.id) {
      setIsCurrentlyOffline(isOfflineTrack(currentTrack.id));
    }
  }, [currentTrack]);

  useEffect(() => {
    const handleStorageUpdate = () => {
      if (currentTrack?.id) {
        setIsCurrentlyOffline(isOfflineTrack(currentTrack.id));
      }
    };
    window.addEventListener('paatu:offline-storage-updated', handleStorageUpdate);
    return () => window.removeEventListener('paatu:offline-storage-updated', handleStorageUpdate);
  }, [currentTrack]);

  const handleDownload = async () => {
    if (!currentTrack || isDownloading) return;
    setIsDownloading(true);
    try {
      await downloadCurrentTrack();
      setDownloadSuccess(true);
      setTimeout(() => setDownloadSuccess(false), 3000);
    } catch (err) {
      console.error('Download failed:', err);
    } finally {
      setIsDownloading(false);
    }
  };

  const handleStartRadio = async () => {
    if (!currentTrack || isRadioStarting) return;
    setIsRadioStarting(true);
    try {
      await startSongRadio(currentTrack);
    } finally {
      setTimeout(() => setIsRadioStarting(false), 1000);
    }
  };

  // Listen for keyboard shortcut D (paatu:download-current-song)
  useEffect(() => {
    const handleDownloadEvent = () => handleDownload();
    window.addEventListener('paatu:download-current-song', handleDownloadEvent);
    return () => window.removeEventListener('paatu:download-current-song', handleDownloadEvent);
  }, [currentTrack, isDownloading]);
  
  const [isCollapsed, setIsCollapsed] = useState<boolean>(() => {
    try {
      return localStorage.getItem('paatu_player_collapsed') === 'true';
    } catch {
      return false;
    }
  });

  const toggleCollapse = () => {
    setIsCollapsed(prev => {
      const next = !prev;
      try {
        localStorage.setItem('paatu_player_collapsed', String(next));
      } catch {}
      return next;
    });
  };

  useEffect(() => {
    const handleToggleLyrics = () => setShowLyrics(prev => !prev);
    const handleToggleCollapse = () => toggleCollapse();
    const handleToggleEq = () => setShowEqualizer(prev => !prev);

    window.addEventListener('paatu:toggle-lyrics', handleToggleLyrics);
    window.addEventListener('paatu:toggle-player-collapse', handleToggleCollapse);
    window.addEventListener('paatu:toggle-equalizer', handleToggleEq);

    return () => {
      window.removeEventListener('paatu:toggle-lyrics', handleToggleLyrics);
      window.removeEventListener('paatu:toggle-player-collapse', handleToggleCollapse);
      window.removeEventListener('paatu:toggle-equalizer', handleToggleEq);
    };
  }, []);

  const handleSeekChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setIsSeeking(true);
    setCurrentTime(Number(e.target.value));
  };

  const handleSeekRelease = (e: React.ChangeEvent<HTMLInputElement> | React.MouseEvent | React.TouchEvent | React.KeyboardEvent) => {
    setIsSeeking(false);
    const target = e.target as HTMLInputElement;
    seekTo(Number(target.value));
  };

  const handleLikeToggle = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!currentTrack) return;
    if (!user) {
      navigate("/login", { state: { from: location } });
      return;
    }
    
    if (isLiked) {
      await unlikeSong(currentTrack.id);
      setIsLiked(false);
    } else {
      await likeSong(currentTrack);
      setIsLiked(true);
    }
  };

  // Reset like state when track changes
  useEffect(() => {
    setIsLiked(false); // We could check library here if we had a central library cache
  }, [currentTrack?.id]);

  const formatTime = (seconds: number) => {
    if (isNaN(seconds)) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  if (!currentTrack) return null;

  if (isCollapsed) {
    return (
      <>
        <footer className="w-full flex-shrink-0 h-11 bg-neutral-950/95 backdrop-blur-md border-t border-white/10 px-4 flex items-center justify-between z-50 transition-all duration-300 select-none shadow-2xl">
          {/* Left: Compact track info */}
          <div 
            onClick={toggleCollapse} 
            className="flex items-center gap-3 min-w-0 max-w-[35%] cursor-pointer group"
            title="Click to expand player"
          >
            <img 
              src={getValidImage(currentTrack)} 
              alt={currentTrack.title} 
              className="w-7 h-7 rounded shadow object-cover flex-shrink-0 border border-white/10"
              loading="lazy"
              onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
            />
            <div className="flex items-center gap-2 min-w-0 truncate">
              <span className="text-xs font-bold text-white truncate group-hover:text-brand transition-colors">
                {currentTrack.title}
              </span>
              <span className="text-[11px] text-neutral-400 truncate hidden sm:inline">
                • {currentTrack.artist}
              </span>
            </div>
          </div>

          {/* Center: Compact controls */}
          <div className="flex items-center gap-4">
            <button 
              onClick={() => {
                if (history.length === 0 && currentTime < 3) return;
                playPrevious();
              }}
              disabled={history.length === 0 && currentTime < 3}
              className="text-neutral-400 hover:text-white disabled:opacity-40 disabled:hover:text-neutral-400 transition-colors p-1"
              title="Previous"
            >
              <SkipBack size={15} />
            </button>
            <button 
              onClick={togglePlay}
              disabled={isBuffering}
              className="w-7 h-7 flex items-center justify-center bg-white hover:bg-neutral-200 text-black rounded-full hover:scale-105 active:scale-95 transition-all shadow"
              title={isPlaying ? "Pause" : "Play"}
            >
              {isBuffering ? (
                <div className="w-3.5 h-3.5 border-2 border-black border-t-transparent rounded-full animate-spin" />
              ) : isPlaying ? (
                <Pause size={14} className="fill-black text-black" />
              ) : (
                <Play size={14} className="fill-black text-black ml-0.5" />
              )}
            </button>
            <button 
              onClick={playNext}
              className="text-neutral-400 hover:text-white transition-colors p-1"
              title="Next"
            >
              <SkipForward size={15} />
            </button>
            
            {/* Scrubber preview on medium screens */}
            <div className="hidden md:flex items-center gap-2 text-[10px] text-neutral-400 font-mono ml-2">
              <span>{formatTime(currentTime)}</span>
              <div 
                className="w-28 h-1 bg-neutral-800 rounded-full overflow-hidden cursor-pointer"
                onClick={(e) => {
                  const rect = e.currentTarget.getBoundingClientRect();
                  const pos = (e.clientX - rect.left) / rect.width;
                  seekTo(pos * (duration || 0));
                }}
              >
                <div 
                  className="h-full bg-brand rounded-full transition-all"
                  style={{ width: `${((currentTime / (duration || 1)) * 100).toFixed(1)}%` }}
                />
              </div>
              <span>{formatTime(duration)}</span>
            </div>
          </div>

          {/* Right: Expand Button */}
          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={handleLikeToggle}
              title={isLiked ? "Unlike" : "Like"}
              className="focus:outline-none flex items-center justify-center"
            >
              <Heart 
                size={17} 
                className={`cursor-pointer transition-all ${isLiked ? 'text-brand fill-brand' : 'text-neutral-400 hover:text-white'}`}
              />
            </button>
            <button
              type="button"
              onClick={handleDownload}
              disabled={isDownloading}
              title={isCurrentlyOffline ? "Downloaded (320kbps)" : "Download MP3 (320kbps) [D]"}
              className={`focus:outline-none flex items-center justify-center ${
                isCurrentlyOffline || downloadSuccess ? 'text-brand' : 'text-neutral-400 hover:text-white'
              }`}
            >
              {isDownloading ? (
                <Loader2 size={16} className="animate-spin text-brand" />
              ) : downloadSuccess || isCurrentlyOffline ? (
                <Check size={16} className="text-brand" />
              ) : (
                <Download size={16} />
              )}
            </button>
            <button
              onClick={toggleCollapse}
              className="flex items-center gap-1.5 px-3 py-1 bg-white/10 hover:bg-white/20 text-white rounded-full text-xs font-semibold border border-white/10 transition-all hover:scale-105 active:scale-95 shadow-sm"
              title="Expand player"
            >
              <span className="hidden sm:inline">Expand</span>
              <ChevronUp size={16} />
            </button>
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
  }

  return (
    <>
      <footer className="w-full flex-shrink-0 h-24 bg-surface-base border-t border-white/5 px-4 flex items-center justify-between z-50 transition-all duration-300 select-none">
        
        {/* Left: Track Info */}
        <div className="flex items-center gap-4 w-[30%]">
          <img 
            src={getValidImage(currentTrack)} 
            alt={currentTrack.title} 
            className="w-14 h-14 rounded shadow-lg object-cover"
            loading="lazy"
            onError={(e) => { e.currentTarget.src = '/logo.png'; e.currentTarget.onerror = null; }}
          />
          <div className="flex flex-col min-w-0">
            <h4 className="text-sm font-semibold text-white hover:underline cursor-pointer truncate">
              {currentTrack.title}
            </h4>
            <p className="text-xs text-muted hover:text-white cursor-pointer truncate">
              {currentTrack.artist}
            </p>
          </div>
          <div className="flex items-center gap-3 ml-2">
            <Heart 
                size={20} 
                className={`transition-all cursor-pointer ${isLiked ? 'text-brand fill-brand' : 'text-muted hover:text-white'}`}
                onClick={handleLikeToggle}
            />
            <PlusCircle 
                size={20} 
                className="text-muted hover:text-white hover:scale-105 transition-all cursor-pointer flex-shrink-0"
                onClick={() => openModal(currentTrack)}
            />

            {/* Download Button */}
            <div className="relative group/dl">
              <button
                type="button"
                onClick={handleDownload}
                disabled={isDownloading}
                className={`transition-all hover:scale-110 active:scale-95 flex items-center justify-center ${
                  isCurrentlyOffline || downloadSuccess
                    ? 'text-brand'
                    : isDownloading
                    ? 'text-brand animate-pulse'
                    : 'text-muted hover:text-white'
                }`}
                title={
                  isCurrentlyOffline
                    ? 'Downloaded (320kbps MP3 available offline)'
                    : isDownloading
                    ? 'Downloading 320kbps MP3...'
                    : 'Download MP3 (320kbps) [D]'
                }
              >
                {isDownloading ? (
                  <Loader2 size={19} className="animate-spin text-brand" />
                ) : downloadSuccess || isCurrentlyOffline ? (
                  <Check size={19} className="text-brand" />
                ) : (
                  <Download size={19} />
                )}
              </button>
              <div className="absolute bottom-full mb-2 left-1/2 -translate-x-1/2 bg-surface text-white text-[10px] px-2 py-1 rounded opacity-0 group-hover/dl:opacity-100 transition whitespace-nowrap pointer-events-none border border-white/5 shadow-xl z-50">
                {isCurrentlyOffline
                  ? 'Downloaded (320kbps MP3)'
                  : isDownloading
                  ? 'Downloading 320kbps...'
                  : 'Download MP3 (320kbps) [D]'}
              </div>
            </div>

            {/* Song Radio Button */}
            <div className="relative group/radio">
              <button
                type="button"
                onClick={handleStartRadio}
                disabled={isRadioStarting}
                className={`transition-all hover:scale-110 active:scale-95 flex items-center justify-center ${
                  isRadioStarting ? 'text-brand animate-pulse' : 'text-muted hover:text-white'
                }`}
                title="Start Song Radio (Similar Tracks)"
              >
                <Radio size={19} className={isRadioStarting ? 'animate-spin' : ''} />
              </button>
              <div className="absolute bottom-full mb-2 left-1/2 -translate-x-1/2 bg-surface text-white text-[10px] px-2 py-1 rounded opacity-0 group-hover/radio:opacity-100 transition whitespace-nowrap pointer-events-none border border-white/5 shadow-xl z-50">
                Start Song Radio
              </div>
            </div>
          </div>
        </div>

        {/* Center: Controls & Progress */}
        <div className="flex flex-col items-center max-w-[40%] w-full gap-2">
          <div className="flex items-center gap-6">
            <div className="relative group/shuffle">
              <Shuffle 
                size={18} 
                className={`cursor-pointer transition ${isShuffle ? 'text-brand hover:text-brand-hover' : 'text-neutral-500 hover:text-white'}`} 
                onClick={toggleShuffle}
              />
              <div className="absolute bottom-full mb-2 left-1/2 -translate-x-1/2 bg-surface text-white text-[10px] px-2 py-1 rounded opacity-0 group-hover/shuffle:opacity-100 transition whitespace-nowrap pointer-events-none border border-white/5">
                {isShuffle ? 'Disable Shuffle' : 'Enable Shuffle'}
              </div>
            </div>
            <SkipBack 
              size={24} 
              className={`transition ${
                history.length === 0 && currentTime < 3 
                ? 'text-neutral-600 cursor-not-allowed opacity-50' 
                : 'text-muted hover:text-white cursor-pointer hover:scale-105 active:scale-95'
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
              className="text-muted hover:text-white cursor-pointer hover:scale-105 active:scale-95 transition" 
              onClick={playNext}
            />
            <div className="relative group/repeat">
              <Repeat 
                size={18} 
                className={`cursor-pointer transition ${repeatMode !== 'none' ? 'text-brand hover:text-brand-hover' : 'text-neutral-500 hover:text-white'}`} 
                onClick={toggleRepeat}
              />
              {repeatMode === 'one' && (
                <span className="absolute -top-1 -right-1 text-[9px] font-black text-brand pointer-events-none">
                  1
                </span>
              )}
              {/* Tooltip for accessibility/clarity */}
              <div className="absolute bottom-full mb-2 left-1/2 -translate-x-1/2 bg-surface text-white text-[10px] px-2 py-1 rounded opacity-0 group-hover/repeat:opacity-100 transition whitespace-nowrap pointer-events-none border border-white/5">
                {repeatMode === 'none' ? 'Enable Repeat' : repeatMode === 'all' ? 'Repeat One' : 'Disable Repeat'}
              </div>
            </div>
          </div>

          {/* Progress Bar & Timestamps */}
          <div className="flex items-center gap-3 w-full text-xs text-muted font-mono">
            <span>{formatTime(currentTime)}</span>
            <input 
              type="range"
              min={0}
              max={duration || 100}
              value={currentTime}
              onChange={handleSeekChange}
              onMouseUp={handleSeekRelease}
              onTouchEnd={handleSeekRelease}
              className="w-full h-1 bg-neutral-600 rounded-full appearance-none cursor-pointer accent-white hover:accent-brand"
              style={{
                backgroundImage: `linear-gradient(to right, var(--color-brand) ${(currentTime / (duration || 1)) * 100}%, #4d4d4d 0%)`
              }}
            />
            <span>{formatTime(duration)}</span>
          </div>
        </div>

        {/* Right: Actions & Volume & Collapse Button */}
        <div className="flex items-center justify-end gap-3 w-[30%]">
          <button
            type="button"
            className="focus:outline-none flex items-center justify-center"
            title="Lyrics"
            onClick={() => setShowLyrics(!showLyrics)}
          >
            <Mic2 
              size={18} 
              className={`cursor-pointer transition ${showLyrics ? 'text-brand' : 'text-muted hover:text-white'}`} 
            />
          </button>

          <button
            type="button"
            className="focus:outline-none flex items-center justify-center"
            title="Queue"
            onClick={() => setShowQueue(!showQueue)}
          >
            <ListMusic 
              size={18} 
              className={`cursor-pointer transition ${showQueue ? 'text-brand' : 'text-muted hover:text-white'}`} 
            />
          </button>

          <div className="relative">
            <button
              type="button"
              className="focus:outline-none flex items-center justify-center"
              title="Equalizer (E)"
              onClick={() => setShowEqualizer(!showEqualizer)}
            >
              <SlidersHorizontal 
                size={18} 
                className={`cursor-pointer transition ${showEqualizer || eqPreset !== 'flat' ? 'text-brand' : 'text-muted hover:text-white'}`} 
              />
            </button>
            <EqualizerPanel
              isOpen={showEqualizer}
              onClose={() => setShowEqualizer(false)}
              bands={eqBands}
              activePreset={eqPreset}
              isEqAvailable={isEqAvailable}
              onBandChange={setEqBandGain}
              onPresetChange={applyEqPreset}
            />
          </div>
          
          <div className="flex items-center gap-1">
             <button
               type="button"
               className="focus:outline-none flex items-center justify-center"
               title="Sleep Timer"
               onClick={() => setShowSleepTimer(true)}
             >
               <Clock 
                 size={18} 
                 className={`cursor-pointer transition ${remainingSleepTime !== null ? 'text-brand' : 'text-muted hover:text-white'}`} 
               />
             </button>
             {remainingSleepTime !== null && (
               <span className="text-[10px] font-bold text-brand">
                 {Math.ceil(remainingSleepTime / 60)}m
               </span>
             )}
          </div>
          
          <div className="relative">
            <MonitorSpeaker 
              size={18} 
              className={`cursor-pointer transition ${showDevicePicker ? 'text-brand' : 'text-muted hover:text-white'}`} 
              onClick={() => setShowDevicePicker(!showDevicePicker)}
            />
            {showDevicePicker && (
              <div className="absolute bottom-10 right-0 bg-surface rounded-xl shadow-2xl p-4 min-w-[200px] border border-white/10">
                <h5 className="text-xs font-bold text-white mb-3">Connect to a device</h5>
                <div className="space-y-2">
                  <div className="flex items-center gap-3 p-2 rounded-lg bg-brand/10 border border-brand/20 cursor-pointer">
                    <MonitorSpeaker size={16} className="text-brand" />
                    <div>
                      <p className="text-[11px] font-bold text-brand">This VAIO Laptop</p>
                      <p className="text-[10px] text-muted">Web Player</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-3 p-2 rounded-lg hover:bg-white/5 cursor-not-allowed opacity-50">
                    <Settings size={16} className="text-muted" />
                    <div>
                      <p className="text-[11px] font-bold text-white">Other Devices</p>
                      <p className="text-[10px] text-muted">None detected</p>
                    </div>
                  </div>
                </div>
              </div>
            )}
          </div>

          <div className="flex items-center gap-2 group w-24 ml-2">
            <Volume2 size={18} className="text-muted group-hover:text-white" />
            <input 
              type="range"
              min={0}
              max={1}
              step={0.01}
              value={volume || 0}
              onChange={(e) => setVolume(Number(e.target.value))}
              className="w-full h-1 bg-neutral-600 rounded-full appearance-none cursor-pointer accent-white group-hover:accent-brand"
              style={{
                backgroundImage: `linear-gradient(to right, var(--color-brand) ${volume * 100}%, #4d4d4d 0%)`
              }}
            />
          </div>

          {/* Desktop Collapse Button */}
          <button
            onClick={toggleCollapse}
            className="p-1.5 text-neutral-400 hover:text-white hover:bg-white/5 rounded-lg transition-colors ml-1"
            title="Collapse player"
          >
            <ChevronDown size={20} />
          </button>
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
