import React, { useEffect } from 'react';
import { X, Keyboard, Play, Volume2, Mic2 } from 'lucide-react';

interface KeyboardShortcutsModalProps {
  isOpen: boolean;
  onClose: () => void;
}

interface ShortcutItem {
  keys: string[];
  description: string;
}

interface ShortcutSection {
  title: string;
  icon: React.ReactNode;
  items: ShortcutItem[];
}

const KeyboardShortcutsModal: React.FC<KeyboardShortcutsModalProps> = ({ isOpen, onClose }) => {
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  const sections: ShortcutSection[] = [
    {
      title: 'Playback Controls',
      icon: <Play size={18} className="text-brand" />,
      items: [
        { keys: ['Space'], description: 'Play or pause current track' },
        { keys: ['Shift', 'N'], description: 'Skip to next track' },
        { keys: ['Shift', 'P'], description: 'Return to previous track' },
        { keys: ['→'], description: 'Seek forward 5 seconds' },
        { keys: ['←'], description: 'Seek backward 5 seconds' },
      ]
    },
    {
      title: 'Volume & Playback Modes',
      icon: <Volume2 size={18} className="text-blue-400" />,
      items: [
        { keys: ['↑'], description: 'Increase volume by 5%' },
        { keys: ['↓'], description: 'Decrease volume by 5%' },
        { keys: ['M'], description: 'Mute or unmute audio' },
        { keys: ['S'], description: 'Toggle shuffle mode' },
        { keys: ['R'], description: 'Cycle repeat (Off → All → One)' },
      ]
    },
    {
      title: 'Visuals & Navigation',
      icon: <Mic2 size={18} className="text-purple-400" />,
      items: [
        { keys: ['L'], description: 'Toggle fullscreen lyrics & visualizer' },
        { keys: ['E'], description: 'Toggle equalizer panel' },
        { keys: ['D'], description: 'Download current song (320kbps MP3)' },
        { keys: ['C'], description: 'Collapse / expand desktop player bar' },
        { keys: ['/'], description: 'Quick focus search bar' },
        { keys: ['?'], description: 'Toggle this keyboard shortcuts menu' },
        { keys: ['Esc'], description: 'Close modals or overlays' },
      ]
    }
  ];

  return (
    <div 
      className="fixed inset-0 z-[120] flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-in fade-in duration-200"
      onClick={onClose}
    >
      <div 
        className="relative w-full max-w-2xl bg-neutral-900 border border-white/10 rounded-2xl p-6 md:p-8 shadow-2xl animate-in zoom-in-95 duration-200"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between pb-5 border-b border-white/10">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-brand/10 border border-brand/20 flex items-center justify-center">
              <Keyboard size={22} className="text-brand" />
            </div>
            <div>
              <h2 className="text-xl font-bold text-white tracking-tight">Desktop Keyboard Shortcuts</h2>
              <p className="text-xs text-neutral-400">Navigate and control Paatu Padava with hands-free hotkeys</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 text-neutral-400 hover:text-white hover:bg-white/10 rounded-full transition-colors"
            title="Close (Esc)"
          >
            <X size={20} />
          </button>
        </div>

        {/* Shortcuts Grid */}
        <div className="mt-6 space-y-6 max-h-[60vh] overflow-y-auto pr-2 custom-scrollbar">
          {sections.map((section, idx) => (
            <div key={idx} className="space-y-3">
              <div className="flex items-center gap-2 text-xs uppercase font-bold tracking-wider text-neutral-400">
                {section.icon}
                <span>{section.title}</span>
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-2.5">
                {section.items.map((item, itemIdx) => (
                  <div 
                    key={itemIdx} 
                    className="flex items-center justify-between p-2.5 bg-neutral-800/60 hover:bg-neutral-800 rounded-xl border border-white/5 transition-colors"
                  >
                    <span className="text-xs text-neutral-300 font-medium">{item.description}</span>
                    <div className="flex items-center gap-1 flex-shrink-0 ml-2">
                      {item.keys.map((k, kIdx) => (
                        <kbd
                          key={kIdx}
                          className="min-w-[24px] px-2 py-1 text-[11px] font-mono font-bold text-white bg-neutral-700/80 border border-white/15 rounded-md shadow-sm text-center"
                        >
                          {k}
                        </kbd>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>

        {/* Footer tip */}
        <div className="mt-6 pt-4 border-t border-white/10 flex items-center justify-between text-[11px] text-neutral-500">
          <span>Tip: Shortcuts are automatically paused when typing in search or inputs.</span>
          <button
            onClick={onClose}
            className="px-4 py-1.5 bg-white text-black font-bold text-xs rounded-full hover:scale-105 active:scale-95 transition-all shadow"
          >
            Got it
          </button>
        </div>
      </div>
    </div>
  );
};

export default KeyboardShortcutsModal;
