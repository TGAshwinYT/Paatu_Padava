import React from 'react';
import { X, Clock, Check } from 'lucide-react';
import { useAudio } from '../context/AudioContext';

interface SleepTimerModalProps {
  isOpen: boolean;
  onClose: () => void;
}

const SleepTimerModal: React.FC<SleepTimerModalProps> = ({ isOpen, onClose }) => {
  const { setSleepTimer, remainingSleepTime } = useAudio();

  if (!isOpen) return null;

  const options = [
    { label: '5 minutes', value: 5 },
    { label: '15 minutes', value: 15 },
    { label: '30 minutes', value: 30 },
    { label: '45 minutes', value: 45 },
    { label: '1 hour', value: 60 },
    { label: 'End of track', value: 'end' as const },
    { label: 'Off', value: null },
  ];

  const handleSelect = (val: number | 'end' | null) => {
    setSleepTimer(val);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-[100] flex items-end sm:items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-300">
      <div 
        className="bg-neutral-900 w-full max-w-md rounded-t-3xl sm:rounded-3xl overflow-hidden shadow-2xl border border-white/10 animate-in slide-in-from-bottom duration-500"
      >
        <div className="p-6 flex items-center justify-between border-b border-white/5">
          <div className="flex items-center gap-3">
            <Clock className="text-green-500" size={24} />
            <h2 className="text-xl font-bold text-white tracking-tight">Sleep Timer</h2>
          </div>
          <button 
            onClick={onClose}
            className="p-2 hover:bg-white/5 rounded-full transition-colors"
          >
            <X size={24} className="text-neutral-400" />
          </button>
        </div>

        <div className="p-2 max-h-[60vh] overflow-y-auto custom-scrollbar">
          {options.map((opt) => (
            <button
              key={opt.label}
              onClick={() => handleSelect(opt.value)}
              className="w-full flex items-center justify-between p-4 hover:bg-white/5 rounded-xl transition-all group"
            >
              <span className={`text-base font-medium ${
                (opt.value === null && remainingSleepTime === null) || 
                (typeof opt.value === 'number' && remainingSleepTime === opt.value * 60)
                ? 'text-green-500 font-bold' : 'text-neutral-300 group-hover:text-white'
              }`}>
                {opt.label}
              </span>
              {((opt.value === null && remainingSleepTime === null) || 
                (typeof opt.value === 'number' && remainingSleepTime === opt.value * 60)) && (
                <Check size={20} className="text-green-500" />
              )}
            </button>
          ))}
        </div>

        <div className="p-6 bg-neutral-800/50">
           <p className="text-xs text-neutral-500 text-center font-medium">
             Playback will automatically pause when the timer ends.
           </p>
        </div>
      </div>
    </div>
  );
};

export default SleepTimerModal;
