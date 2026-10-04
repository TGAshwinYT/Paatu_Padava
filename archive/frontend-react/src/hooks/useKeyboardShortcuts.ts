import { useEffect, useRef } from 'react';
import { useAudio } from '../context/AudioContext';

interface UseKeyboardShortcutsOptions {
  enabled?: boolean;
  onToggleShortcutsModal?: () => void;
}

export const useKeyboardShortcuts = ({
  enabled = true,
  onToggleShortcutsModal
}: UseKeyboardShortcutsOptions = {}) => {
  const {
    isPlaying,
    togglePlay,
    playNext,
    playPrevious,
    currentTime,
    duration,
    seekTo,
    volume,
    setVolume,
    toggleShuffle,
    toggleRepeat,
    currentTrack,
    queue
  } = useAudio();

  // Keep stable refs to avoid listener churn on audio time updates
  const isPlayingRef = useRef(isPlaying);
  isPlayingRef.current = isPlaying;

  const togglePlayRef = useRef(togglePlay);
  togglePlayRef.current = togglePlay;

  const playNextRef = useRef(playNext);
  playNextRef.current = playNext;

  const playPreviousRef = useRef(playPrevious);
  playPreviousRef.current = playPrevious;

  const currentTimeRef = useRef(currentTime);
  currentTimeRef.current = currentTime;

  const durationRef = useRef(duration);
  durationRef.current = duration;

  const seekToRef = useRef(seekTo);
  seekToRef.current = seekTo;

  const volumeRef = useRef(volume);
  volumeRef.current = volume;

  const setVolumeRef = useRef(setVolume);
  setVolumeRef.current = setVolume;

  const toggleShuffleRef = useRef(toggleShuffle);
  toggleShuffleRef.current = toggleShuffle;

  const toggleRepeatRef = useRef(toggleRepeat);
  toggleRepeatRef.current = toggleRepeat;

  const currentTrackRef = useRef(currentTrack);
  currentTrackRef.current = currentTrack;

  const queueRef = useRef(queue);
  queueRef.current = queue;

  const onToggleShortcutsModalRef = useRef(onToggleShortcutsModal);
  onToggleShortcutsModalRef.current = onToggleShortcutsModal;

  const prevVolumeRef = useRef<number>(volume > 0 ? volume : 0.8);

  useEffect(() => {
    if (!enabled) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      const isInputActive = target && (
        target.tagName === 'INPUT' ||
        target.tagName === 'TEXTAREA' ||
        target.tagName === 'SELECT' ||
        target.isContentEditable
      );

      // Allow Escape to blur any focused input/modal
      if (e.key === 'Escape') {
        if (isInputActive) {
          target.blur();
          return;
        }
        window.dispatchEvent(new CustomEvent('paatu:escape-pressed'));
        return;
      }

      // If user is actively typing in a text field, do not trigger shortcuts
      if (isInputActive) {
        return;
      }

      // Cheatsheet modal: '?' (Shift + '/')
      if (e.key === '?' || (e.shiftKey && e.key === '/')) {
        e.preventDefault();
        // Trigger via callback or global event — only once!
        if (onToggleShortcutsModalRef.current) {
          onToggleShortcutsModalRef.current();
        } else {
          window.dispatchEvent(new CustomEvent('paatu:toggle-shortcuts-modal'));
        }
        return;
      }

      // Focus Search Bar: '/'
      if (e.key === '/' && !e.shiftKey && !e.ctrlKey && !e.metaKey) {
        e.preventDefault();
        const searchInput = document.getElementById('top-search-input') as HTMLInputElement | null;
        if (searchInput) {
          searchInput.focus();
          searchInput.select();
        }
        return;
      }

      // Play / Pause: Space
      if (e.code === 'Space' || e.key === ' ') {
        e.preventDefault();
        if (currentTrackRef.current) {
          togglePlayRef.current();
        } else if (queueRef.current && queueRef.current.length > 0) {
          // If a queue exists but no song currently active, start playing
          togglePlayRef.current();
        }
        return;
      }

      // Next Track: Shift + N or Shift + Right
      if ((e.shiftKey && (e.key === 'N' || e.key === 'n')) || (e.shiftKey && e.key === 'ArrowRight')) {
        e.preventDefault();
        playNextRef.current();
        return;
      }

      // Previous Track: Shift + P or Shift + Left
      if ((e.shiftKey && (e.key === 'P' || e.key === 'p')) || (e.shiftKey && e.key === 'ArrowLeft')) {
        e.preventDefault();
        playPreviousRef.current();
        return;
      }

      // Seek Forward 5s: Right Arrow (without Shift)
      if (e.key === 'ArrowRight' && !e.shiftKey) {
        e.preventDefault();
        const nextTime = Math.min(durationRef.current || 0, currentTimeRef.current + 5);
        seekToRef.current(nextTime);
        return;
      }

      // Seek Backward 5s: Left Arrow (without Shift)
      if (e.key === 'ArrowLeft' && !e.shiftKey) {
        e.preventDefault();
        const prevTime = Math.max(0, currentTimeRef.current - 5);
        seekToRef.current(prevTime);
        return;
      }

      // Volume Up 5%: Arrow Up
      if (e.key === 'ArrowUp') {
        e.preventDefault();
        const newVol = Math.min(1, Math.round((volumeRef.current + 0.05) * 100) / 100);
        setVolumeRef.current(newVol);
        return;
      }

      // Volume Down 5%: Arrow Down
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        const newVol = Math.max(0, Math.round((volumeRef.current - 0.05) * 100) / 100);
        setVolumeRef.current(newVol);
        return;
      }

      // Mute / Unmute: M
      if (e.key === 'm' || e.key === 'M') {
        e.preventDefault();
        if (volumeRef.current > 0) {
          prevVolumeRef.current = volumeRef.current;
          setVolumeRef.current(0);
        } else {
          setVolumeRef.current(prevVolumeRef.current > 0 ? prevVolumeRef.current : 0.8);
        }
        return;
      }

      // Toggle Shuffle: S
      if (e.key === 's' || e.key === 'S') {
        if (!e.ctrlKey && !e.metaKey) {
          e.preventDefault();
          toggleShuffleRef.current();
          return;
        }
      }

      // Toggle Repeat: R
      if (e.key === 'r' || e.key === 'R') {
        if (!e.ctrlKey && !e.metaKey) {
          e.preventDefault();
          toggleRepeatRef.current();
          return;
        }
      }

      // Toggle Lyrics: L
      if (e.key === 'l' || e.key === 'L') {
        if (!e.ctrlKey && !e.metaKey) {
          e.preventDefault();
          window.dispatchEvent(new CustomEvent('paatu:toggle-lyrics'));
          return;
        }
      }

      // Toggle Player Collapse/Expand: C
      if (e.key === 'c' || e.key === 'C') {
        if (!e.ctrlKey && !e.metaKey) {
          e.preventDefault();
          window.dispatchEvent(new CustomEvent('paatu:toggle-player-collapse'));
          return;
        }
      }

      // Toggle Equalizer Panel: E
      if (e.key === 'e' || e.key === 'E') {
        if (!e.ctrlKey && !e.metaKey) {
          e.preventDefault();
          window.dispatchEvent(new CustomEvent('paatu:toggle-equalizer'));
          return;
        }
      }

      // Download Current Song: D
      if (e.key === 'd' || e.key === 'D') {
        if (!e.ctrlKey && !e.metaKey) {
          e.preventDefault();
          window.dispatchEvent(new CustomEvent('paatu:download-current-song'));
          return;
        }
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [enabled]);
};

export default useKeyboardShortcuts;
