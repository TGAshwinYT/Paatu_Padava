/**
 * Utility functions for formatting audio durations and timestamps.
 */

export const formatDuration = (secs?: number): string => {
  if (secs === undefined || secs === null || isNaN(secs) || secs <= 0) {
    return '3:30';
  }
  const minutes = Math.floor(secs / 60);
  const remainingSeconds = Math.floor(secs % 60);
  return `${minutes}:${remainingSeconds < 10 ? '0' : ''}${remainingSeconds}`;
};

export const formatTime = (secs: number): string => {
  if (isNaN(secs) || secs < 0) return '0:00';
  const minutes = Math.floor(secs / 60);
  const remainingSeconds = Math.floor(secs % 60);
  return `${minutes}:${remainingSeconds < 10 ? '0' : ''}${remainingSeconds}`;
};
