/**
 * Parses raw LRC formatted text into a timed array of objects.
 * [00:12.50] Hello world -> { time: 12.5, text: "Hello world" }
 */
export interface LyricsLine {
  time: number;
  text: string;
}

export const parseLRC = (lrcString: string): LyricsLine[] => {
  if (!lrcString) return [];

  const lines = lrcString.split('\n');
  const result: LyricsLine[] = [];
  const timeRegex = /\[(\d{2}):(\d{2}\.\d{2,3})\](.*)/;

  lines.forEach(line => {
    const match = line.match(timeRegex);
    if (match) {
      const minutes = parseInt(match[1]);
      const seconds = parseFloat(match[2]);
      const text = match[3].trim();
      
      const time = minutes * 60 + seconds;
      
      // Skip lines with empty text or instrumental markers
      if (text && !text.includes('♪')) {
        result.push({ time, text });
      }
    } else if (line.trim() && !line.startsWith('[')) {
        // Fallback for lines without timestamps (treat as time 0 or sequential)
        // But for fully synced UI, we usually only care about the matched ones.
    }
  });

  return result.sort((a, b) => a.time - b.time);
};
