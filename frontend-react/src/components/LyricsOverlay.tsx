import React, { useState, useEffect, useRef } from 'react';
import { X, Sparkles, Activity, Waves, EyeOff } from 'lucide-react';
import { getRelatedSongs, getLyrics } from '../services/api';
import type { Song } from '../types';
import { useAudio } from '../context/AudioContext';
import { parseLRC } from '../utils/LyricsParser';
import type { LyricsLine } from '../utils/LyricsParser';
import AudioVisualizer from './AudioVisualizer';
import type { VisualizerMode } from './AudioVisualizer';

interface LyricItemProps {
  text: string;
  isActive: boolean;
  lineRef: (el: HTMLParagraphElement | null) => void;
  onSeek: () => void;
}

const LyricItem = React.memo<LyricItemProps>(
  ({ text, isActive, lineRef, onSeek }) => (
    <p 
      ref={lineRef}
      onClick={onSeek}
      className={`transition-all duration-300 transform select-none cursor-pointer ${
        isActive 
          ? 'text-3xl md:text-5xl font-bold text-white origin-left drop-shadow-2xl opacity-100 py-3 scale-100' 
          : 'text-2xl md:text-3xl font-semibold text-neutral-500 hover:text-neutral-300 opacity-40 py-3 scale-[0.98]'
      }`}
    >
      {text}
    </p>
  ),
  (prev, next) => prev.text === next.text && prev.isActive === next.isActive
);

interface LyricsOverlayProps {
  song: Song;
  isOpen: boolean;
  onClose: () => void;
}

const LyricsOverlay: React.FC<LyricsOverlayProps> = ({ song, isOpen, onClose }) => {
  const [activeTab, setActiveTab] = useState<'lyrics' | 'related'>('lyrics');
  const [lyricsLines, setLyricsLines] = useState<LyricsLine[]>([]);
  const [plainLyrics, setPlainLyrics] = useState<string>('');
  const [recommendations, setRecommendations] = useState<Song[]>([]);
  const [loading, setLoading] = useState<boolean>(false);
  const [activeIndex, setActiveIndex] = useState<number>(-1);
  const [visualizerMode, setVisualizerMode] = useState<VisualizerMode>(() => {
    try {
      const saved = localStorage.getItem('paatu_lyrics_visualizer');
      return (saved as VisualizerMode) || 'bars';
    } catch {
      return 'bars';
    }
  });
  
  const { playContext, currentTime, seekTo, isPlaying } = useAudio();
  const lineRefs = useRef<(HTMLParagraphElement | null)[]>([]);
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const cachedLyricsRef = useRef<{ id: string; synced: LyricsLine[]; plain: string } | null>(null);

  const cycleVisualizerMode = () => {
    setVisualizerMode(prev => {
      const next: VisualizerMode = prev === 'bars' ? 'wave' : prev === 'wave' ? 'off' : 'bars';
      try { localStorage.setItem('paatu_lyrics_visualizer', next); } catch {}
      return next;
    });
  };

  // Reset state when song changes
  useEffect(() => {
    setActiveIndex(-1);
    lineRefs.current = [];
  }, [song.id]);

  useEffect(() => {
    if (isOpen && song.id) {
      if (activeTab === 'lyrics') fetchLyrics();
      else fetchRecs();
    }
  }, [isOpen, song.id, activeTab]);

  // Handle active index based on currentTime
  useEffect(() => {
    if (!lyricsLines.length) return;
    
    // Efficiently find current index
    const index = lyricsLines.findIndex((line, i) => {
      const nextLine = lyricsLines[i + 1];
      return currentTime >= line.time && (!nextLine || currentTime < nextLine.time);
    });

    // Only update if index actually changed to prevent re-renders
    if (index !== -1 && index !== activeIndex) {
      setActiveIndex(index);
    }
  }, [currentTime, lyricsLines.length, activeIndex]);

  // Handle auto-scroll based on activeIndex
  useEffect(() => {
    if (activeIndex !== -1 && activeTab === 'lyrics') {
      const scrollIt = () => {
        lineRefs.current[activeIndex]?.scrollIntoView({
          behavior: 'smooth',
          block: 'center'
        });
      };
      scrollIt();
      const timer = setTimeout(scrollIt, 80);
      return () => clearTimeout(timer);
    }
  }, [activeIndex, activeTab, lyricsLines]);

  const fetchLyrics = async () => {
    // If lyrics already cached for this exact song, display instantly with zero lag
    if (cachedLyricsRef.current && cachedLyricsRef.current.id === song.id) {
      setLyricsLines(cachedLyricsRef.current.synced);
      setPlainLyrics(cachedLyricsRef.current.plain);
      return;
    }

    setLoading(true);
    setLyricsLines([]);
    setPlainLyrics('');
    try {
      const data = await getLyrics(song);
      if (!data) throw new Error("No data");
      
      let parsedSynced: LyricsLine[] = [];
      let parsedPlain = '';

      if (data.syncedLyrics) {
        parsedSynced = parseLRC(data.syncedLyrics);
        setLyricsLines(parsedSynced);
      } else if (data.plainLyrics) {
        parsedPlain = data.plainLyrics;
        setPlainLyrics(parsedPlain);
      } else {
        parsedPlain = "Lyrics not available for this track.";
        setPlainLyrics(parsedPlain);
      }

      cachedLyricsRef.current = {
        id: song.id,
        synced: parsedSynced,
        plain: parsedPlain
      };
    } catch (error) {
      setPlainLyrics("Lyrics not available for this track.");
    } finally {
      setLoading(false);
    }
  };

  const fetchRecs = async () => {
    setLoading(true);
    setRecommendations([]); // Clear old recommendations immediately (Task 1)
    try {
      const data = await getRelatedSongs(song.id, song.artist);
      setRecommendations(data);
    } catch (error) {
      console.error("Error fetching related songs:", error);
    } finally {
      setLoading(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div 
      className="fixed inset-0 z-[60] bg-black text-white animate-in fade-in slide-in-from-bottom-10 duration-300 overflow-hidden select-none"
      style={{ backgroundColor: '#000000' }}
    >
      {/* Ambient Audio Visualizer Layer */}
      <div className="absolute inset-0 pointer-events-none z-0 overflow-hidden opacity-35">
        <AudioVisualizer isPlaying={isPlaying} mode={visualizerMode} />
      </div>

      <div className="h-full flex flex-col p-8 md:p-16 relative z-10">
        {/* Top Right Actions: Visualizer Mode Toggle + Close */}
        <div className="absolute top-8 right-8 flex items-center gap-3 z-[70]">
          <button
            onClick={cycleVisualizerMode}
            className="flex items-center gap-2 px-3.5 py-1.5 bg-white/10 hover:bg-white/20 text-white rounded-full text-xs font-semibold backdrop-blur-md border border-white/10 transition-all hover:scale-105 active:scale-95 shadow-lg"
            title={`Visualizer: ${visualizerMode.toUpperCase()} (Click to toggle: Bars -> Wave -> Off)`}
          >
            {visualizerMode === 'bars' && <Activity size={15} className="text-brand animate-pulse" />}
            {visualizerMode === 'wave' && <Waves size={15} className="text-blue-400 animate-pulse" />}
            {visualizerMode === 'off' && <EyeOff size={15} className="text-neutral-400" />}
            <span className="capitalize font-mono text-[11px]">{visualizerMode}</span>
          </button>

          <button 
            onClick={onClose}
            className="p-2 hover:bg-white/10 rounded-full transition-colors text-neutral-400 hover:text-white"
            title="Close lyrics (Esc or L)"
          >
            <X size={28} />
          </button>
        </div>

        {/* Tab Switcher */}
        <div className="flex gap-8 mb-12">
            <button 
                onClick={() => setActiveTab('lyrics')}
                className={`text-2xl font-bold transition-all ${activeTab === 'lyrics' ? 'text-white border-b-4 border-green-500 pb-2' : 'text-neutral-500 hover:text-neutral-300'}`}
            >
                Lyrics
            </button>
            <button 
                onClick={() => setActiveTab('related')}
                className={`text-2xl font-bold transition-all ${activeTab === 'related' ? 'text-white border-b-4 border-green-500 pb-2' : 'text-neutral-500 hover:text-neutral-300'}`}
            >
                Related
            </button>
        </div>

        <div className="flex flex-col md:flex-row gap-12 h-full items-center md:items-start overflow-hidden">
          {/* Left Side: Big Album Art (Responsive Wrapper) */}
          <div className="w-64 md:w-80 flex-shrink-0 animate-in zoom-in-95 duration-700 hidden md:block">
            <div className="sticky top-0">
                <div style={{
                    width: '100%',           
                    maxWidth: '400px',       // Prevents it from getting absurdly huge on 4K monitors
                    margin: '0 auto',        
                    aspectRatio: '1 / 1',    // THE FIX: Forces a perfect square at all times
                    borderRadius: '16px',    
                    overflow: 'hidden',      
                    boxShadow: '0 8px 24px rgba(0,0,0,0.5)',
                    border: '1px solid rgba(255,255,255,0.1)'
                }}>
                    <img 
                        src={song.coverUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745'} 
                        alt={song.title} 
                        style={{
                            width: '100%',
                            height: '100%',
                            objectFit: 'cover', // THE FIX: Fills the square without distorting
                            display: 'block'
                        }}
                    />
                </div>
                <div className="mt-8">
                <h2 className="text-3xl font-black text-white mb-2">{song.title}</h2>
                <p className="text-xl text-neutral-400 font-medium">{song.artist}</p>
                </div>
            </div>
          </div>

          {/* Right Side: Content */}
          <div 
            ref={scrollContainerRef} 
            className="flex-1 w-full overflow-y-auto custom-scrollbar pr-4 py-32 md:py-[30vh]"
          >
            {loading ? (
              <div className="h-full flex flex-col items-center justify-center text-neutral-400 gap-4">
                <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-green-500"></div>
                <p className="animate-pulse">Taking a moment to find similar vibes...</p>
              </div>
            ) : activeTab === 'lyrics' ? (
              <div className="flex flex-col gap-6 md:gap-8 max-w-3xl">
                {lyricsLines.length > 0 ? (
                  lyricsLines.map((line, i) => (
                    <LyricItem
                      key={`${line.time}-${i}`}
                      text={line.text}
                      isActive={i === activeIndex}
                      lineRef={(el) => {
                        lineRefs.current[i] = el;
                      }}
                      onSeek={() => seekTo(line.time)}
                    />
                  ))
                ) : (
                  <div className="text-2xl md:text-4xl font-bold text-neutral-400 leading-relaxed">
                    {plainLyrics.split('\n').map((line, i) => (
                      <p key={i} className="mb-4">{line || '\u00A0'}</p>
                    ))}
                  </div>
                )}
              </div>
            ) : (
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6 animate-in fade-in slide-in-from-right-10 duration-500">
                    {recommendations.length > 0 ? recommendations.map(track => (
                        <div 
                            key={track.id}
                            onClick={() => playContext(track, recommendations)}
                            className="bg-white/5 p-4 rounded-xl hover:bg-white/10 transition-all group flex items-center gap-4 cursor-pointer"
                        >
                            <img src={track.coverUrl} className="w-16 h-16 rounded-lg object-cover" alt="" />
                            <div className="truncate">
                                <p className="font-bold text-lg text-white truncate group-hover:text-green-500 transition-colors">{track.title}</p>
                                <p className="text-sm text-neutral-400 truncate">{track.artist}</p>
                            </div>
                        </div>
                    )) : (
                        <div className="col-span-full flex flex-col items-center justify-center text-neutral-400 py-20 bg-neutral-900/20 rounded-2xl border border-white/5 animate-in fade-in duration-500">
                            <Sparkles size={48} className="mb-4 opacity-20" />
                            <p className="text-xl font-medium">No related songs found for this track.</p>
                            <p className="text-sm mt-2">Try playing another song to see more vibes!</p>
                        </div>
                    )}
                </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default LyricsOverlay;
