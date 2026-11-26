import React, { useEffect, useCallback } from 'react';
import type { Song, PlaybackEngine } from '../../types';
import AudioPlayer from '../../components/AudioPlayer';
import { usePlaybackProgress } from '../PlaybackProgressContext';

export interface AudioPlayerBridgeProps {
  currentTrack: Song | null;
  isPlaying: boolean;
  volume: number;
  playbackEngine: PlaybackEngine;
  nativeAudioUrl: string | null;
  youtubeVideoId: string | null;
  crossfadeDuration: number;
  connectEqualizer: (audioElement: HTMLAudioElement | null) => void;
  onReady: (player: any) => void;
  onEnd: () => void;
  playNext: () => void;
  playPrevious: () => void;
  setIsPlaying: (playing: boolean) => void;
  setIsBuffering: (buffering: boolean) => void;
  currentTimeRef: React.MutableRefObject<number>;
}

export const AudioPlayerBridge: React.FC<AudioPlayerBridgeProps> = ({
  currentTimeRef,
  ...props
}) => {
  const { setCurrentTime, setDuration, seekToTime, resetProgress, seekTo } = usePlaybackProgress();

  useEffect(() => {
    const handleExternalSeek = (e: Event) => {
      const customEvent = e as CustomEvent<number>;
      if (typeof customEvent.detail === 'number') {
        seekTo(customEvent.detail);
      }
    };
    window.addEventListener('paatu:seek-to', handleExternalSeek);
    return () => window.removeEventListener('paatu:seek-to', handleExternalSeek);
  }, [seekTo]);

  useEffect(() => {
    if (props.currentTrack) {
      const dur = typeof props.currentTrack.duration === 'number'
        ? props.currentTrack.duration
        : Number(props.currentTrack.duration);
      resetProgress(dur && isFinite(dur) && dur > 0 ? dur : 0);
      currentTimeRef.current = 0;
    } else {
      resetProgress(0);
      currentTimeRef.current = 0;
    }
  }, [props.currentTrack?.id, resetProgress, currentTimeRef]);

  const handleTimeUpdate = useCallback((time: number) => {
    currentTimeRef.current = time;
    setCurrentTime(time);
  }, [setCurrentTime, currentTimeRef]);

  return (
    <AudioPlayer
      {...props}
      seekToTime={seekToTime}
      onTimeUpdate={handleTimeUpdate}
      onDurationChange={setDuration}
    />
  );
};
