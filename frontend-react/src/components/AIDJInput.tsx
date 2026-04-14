import React, { useState } from 'react';
import { Sparkles, Loader2 } from 'lucide-react';
import api from '../services/api';
import { useAudio } from '../context/AudioContext';
import './AIDJInput.css';

const AIDJInput: React.FC = () => {
    const [prompt, setPrompt] = useState('');
    const [isGenerating, setIsGenerating] = useState(false);
    const { playContext } = useAudio();

    const handleGenerate = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!prompt.trim() || isGenerating) return;

        setIsGenerating(true);
        try {
            const res = await api.post('/api/ai/dj', { prompt });
            const aiQueue = res.data.queue;

            if (aiQueue && aiQueue.length > 0) {
                // Clear current queue and inject AI tracks
                // We set isManual: true to mimic manual user selection behavior
                const playableQueue = aiQueue.map((s: any) => ({ ...s, isManual: true }));
                
                // Use playContext to start the first track and set the rest as the queue
                playContext(playableQueue[0], playableQueue);
                
                setPrompt(''); // Clear input
            }
        } catch (error: any) {
            console.error("AI DJ Error:", error);
            if (error.response?.status === 429) {
                alert("Rate limit exceeded. Please wait a minute.");
            } else {
                alert("Failed to generate AI playlist. Try again later.");
            }
        } finally {
            setIsGenerating(false);
        }
    };

    return (
        <div className="ai-dj-container bg-neutral-900/40 p-6 rounded-2xl border border-white/5 backdrop-blur-md mb-8 relative overflow-hidden">
            {/* Animated Aura Background */}
            <div className="absolute -top-24 -right-24 w-48 h-48 bg-purple-600/20 blur-[100px] pointer-events-none"></div>
            <div className="absolute -bottom-24 -left-24 w-48 h-48 bg-pink-600/20 blur-[100px] pointer-events-none"></div>

            <div className="flex items-center gap-2 mb-4 relative z-10">
                <Sparkles className="text-purple-400 animate-pulse" size={20} />
                <h3 className="text-lg font-bold text-white tracking-tight">AI DJ <span className="text-[10px] uppercase bg-purple-600 px-1.5 py-0.5 rounded ml-1 tracking-widest font-black">Beta</span></h3>
            </div>
            
            <form onSubmit={handleGenerate} className="relative group z-10">
                <div className={`ai-input-wrapper relative rounded-xl transition-all duration-300 ${isGenerating ? 'generating-glow' : ''}`}>
                    <input
                        type="text"
                        value={prompt}
                        onChange={(e) => setPrompt(e.target.value)}
                        disabled={isGenerating}
                        placeholder="Describe your mood... (e.g. 'Chill Tamil lo-fi for a rainy night')"
                        className="w-full bg-neutral-800/60 text-white rounded-xl py-4 pl-4 pr-32 focus:outline-none focus:ring-1 focus:ring-purple-500/30 transition-all font-medium placeholder-neutral-500 border border-white/5 hover:bg-neutral-800/80"
                    />
                    <button
                        type="submit"
                        disabled={isGenerating || !prompt.trim()}
                        className="absolute right-2 top-2 bottom-2 px-6 bg-gradient-to-r from-purple-600 to-pink-600 text-white rounded-lg font-bold text-sm hover:from-purple-500 hover:to-pink-500 disabled:opacity-30 disabled:grayscale transition-all shadow-lg flex items-center gap-2 active:scale-95"
                    >
                        {isGenerating ? (
                            <>
                                <Loader2 className="animate-spin" size={16} />
                                <span className="hidden sm:inline">Thinking...</span>
                            </>
                        ) : (
                            'Generate'
                        )}
                    </button>
                </div>
            </form>
            
            {isGenerating && (
                <div className="flex items-center gap-3 mt-4 animate-in fade-in slide-in-from-top-2">
                    <div className="flex gap-1">
                        <span className="w-1 h-1 bg-purple-400 rounded-full animate-bounce [animation-delay:-0.3s]"></span>
                        <span className="w-1 h-1 bg-purple-400 rounded-full animate-bounce [animation-delay:-0.15s]"></span>
                        <span className="w-1 h-1 bg-purple-400 rounded-full animate-bounce"></span>
                    </div>
                    <p className="text-xs text-purple-400/80 font-semibold tracking-wide uppercase">
                        Curating your vibe via Gemini Flash...
                    </p>
                </div>
            )}
        </div>
    );
};

export default AIDJInput;
