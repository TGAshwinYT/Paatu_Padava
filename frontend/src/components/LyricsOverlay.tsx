import React, { useState, useEffect, useRef } from 'react';
import { X, Sparkles } from 'lucide-react';
import { getRelatedSongs, getLyrics } from '../services/api';
import type { Song } from '../types';
import { useAudio } from '../context/AudioContext';
import { parseLRC } from '../utils/LyricsParser';
import type { LyricsLine } from '../utils/LyricsParser';

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
  
  const { playTrack, progress } = useAudio();
  const activeLineRef = useRef<HTMLDivElement>(null);
  const scrollContainerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (isOpen && song.id) {
      if (activeTab === 'lyrics') fetchLyrics();
      else fetchRecs();
    }
  }, [isOpen, song.id, activeTab]);

  // Handle active index based on progress
  useEffect(() => {
    if (lyricsLines.length > 0) {
      const index = lyricsLines.findIndex((line, i) => {
        const nextLine = lyricsLines[i + 1];
        return progress >= line.time && (!nextLine || progress < nextLine.time);
      });
      if (index !== activeIndex) {
        setActiveIndex(index);
      }
    }
  }, [progress, lyricsLines, activeIndex]);

  // Handle auto-scroll
  useEffect(() => {
    if (activeLineRef.current && activeIndex !== -1) {
      activeLineRef.current.scrollIntoView({
        behavior: 'smooth',
        block: 'center'
      });
    }
  }, [activeIndex]);

  const fetchLyrics = async () => {
    setLoading(true);
    setLyricsLines([]);
    setPlainLyrics('');
    try {
      const data = await getLyrics(song);
      if (!data) throw new Error("No data");
      
      if (data.syncedLyrics) {
        const parsed = parseLRC(data.syncedLyrics);
        setLyricsLines(parsed);
      } else if (data.plainLyrics) {
        setPlainLyrics(data.plainLyrics);
      } else {
        setPlainLyrics("Lyrics not available for this track.");
      }
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
    <div className="fixed inset-0 z-[60] bg-black/95 backdrop-blur-xl animate-in fade-in slide-in-from-bottom-10 duration-500 overflow-hidden">
      <div className="h-full flex flex-col p-8 md:p-16 relative">
        <button 
          onClick={onClose}
          className="absolute top-8 right-8 p-3 hover:bg-neutral-800 rounded-full transition-colors text-neutral-400 hover:text-white z-[70]"
        >
          <X size={32} />
        </button>

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
          {/* Left Side: Big Album Art */}
          <div className="w-64 md:w-80 flex-shrink-0 animate-in zoom-in-95 duration-700 hidden md:block">
            <div className="sticky top-0">
                <img 
                src={song.coverUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745'} 
                alt={song.title} 
                className="w-full aspect-square object-cover rounded-2xl shadow-[0_20px_50px_rgba(0,0,0,0.5)] border border-white/10"
                />
                <div className="mt-8">
                <h2 className="text-3xl font-black text-white mb-2">{song.title}</h2>
                <p className="text-xl text-neutral-400 font-medium">{song.artist}</p>
                </div>
            </div>
          </div>

          {/* Right Side: Content */}
          <div ref={scrollContainerRef} className="flex-1 w-full overflow-y-auto custom-scrollbar pr-4 py-32 md:py-[30vh]">
            {loading ? (
              <div className="h-full flex flex-col items-center justify-center text-neutral-400 gap-4">
                <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-green-500"></div>
                <p className="animate-pulse">Taking a moment to find similar vibes...</p>
              </div>
            ) : activeTab === 'lyrics' ? (
              <div className="flex flex-col gap-6 md:gap-8 max-w-3xl">
                {lyricsLines.length > 0 ? (
                  lyricsLines.map((line, i) => (
                    <div 
                      key={i} 
                      ref={i === activeIndex ? activeLineRef : null}
                      className={`transition-all duration-300 transform ${
                        i === activeIndex 
                          ? 'text-4xl md:text-5xl font-bold text-white scale-105 origin-left drop-shadow-2xl' 
                          : 'text-2xl md:text-3xl font-semibold text-neutral-500 hover:text-neutral-300 cursor-pointer'
                      }`}
                      onClick={() => {
                          // Optional: seek to time if clicked
                      }}
                    >
                      {line.text}
                    </div>
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
                            onClick={() => playTrack(track)}
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
