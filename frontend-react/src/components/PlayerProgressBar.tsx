import React from 'react';
import { usePlaybackProgress } from '../context/PlaybackProgressContext';

const formatTime = (seconds: number) => {
  if (isNaN(seconds)) return '0:00';
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, '0')}`;
};

interface PlayerProgressBarProps {
  compact?: boolean;
}

const PlayerProgressBar: React.FC<PlayerProgressBarProps> = ({ compact = false }) => {
  const {
    currentTime,
    setCurrentTime,
    duration,
    setIsSeeking,
    seekTo,
  } = usePlaybackProgress();

  const handleSeekChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setIsSeeking(true);
    setCurrentTime(Number(e.target.value));
  };

  const handleSeekRelease = (e: React.ChangeEvent<HTMLInputElement> | React.MouseEvent | React.TouchEvent | React.KeyboardEvent) => {
    setIsSeeking(false);
    const target = e.target as HTMLInputElement;
    seekTo(Number(target.value));
  };

  const progressPercent = duration > 0 ? (currentTime / duration) * 100 : 0;

  if (compact) {
    return (
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
            style={{ width: `${progressPercent.toFixed(1)}%` }}
          />
        </div>
        <span>{formatTime(duration)}</span>
      </div>
    );
  }

  return (
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
          backgroundImage: `linear-gradient(to right, var(--color-brand) ${progressPercent}%, #4d4d4d 0%)`
        }}
      />
      <span>{formatTime(duration)}</span>
    </div>
  );
};

export default React.memo(PlayerProgressBar);
