import React from 'react';
import { X, RotateCcw } from 'lucide-react';
import type { EqBand, EqPreset } from '../hooks/useEqualizer';
import { EQ_PRESETS } from '../hooks/useEqualizer';

interface EqualizerPanelProps {
  isOpen: boolean;
  onClose: () => void;
  bands: EqBand[];
  activePreset: EqPreset;
  isEqAvailable: boolean;
  onBandChange: (bandIndex: number, gain: number) => void;
  onPresetChange: (preset: EqPreset) => void;
}

const PRESET_KEYS = Object.keys(EQ_PRESETS) as EqPreset[];

const EqualizerPanel: React.FC<EqualizerPanelProps> = ({
  isOpen,
  onClose,
  bands,
  activePreset,
  isEqAvailable,
  onBandChange,
  onPresetChange,
}) => {
  if (!isOpen) return null;

  return (
    <div className="absolute bottom-full right-0 mb-3 w-[380px] bg-neutral-900/98 border border-white/10 rounded-2xl shadow-2xl z-[90] animate-in fade-in zoom-in-95 duration-200 origin-bottom-right backdrop-blur-xl overflow-hidden select-none">
      {/* Header */}
      <div className="flex items-center justify-between px-5 pt-5 pb-3">
        <div className="flex items-center gap-2.5">
          <div className="w-8 h-8 rounded-lg bg-brand/10 border border-brand/20 flex items-center justify-center">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-brand">
              <line x1="4" y1="21" x2="4" y2="14" /><line x1="4" y1="10" x2="4" y2="3" />
              <line x1="12" y1="21" x2="12" y2="12" /><line x1="12" y1="8" x2="12" y2="3" />
              <line x1="20" y1="21" x2="20" y2="16" /><line x1="20" y1="12" x2="20" y2="3" />
              <line x1="1" y1="14" x2="7" y2="14" /><line x1="9" y1="8" x2="15" y2="8" />
              <line x1="17" y1="16" x2="23" y2="16" />
            </svg>
          </div>
          <div>
            <h3 className="text-sm font-bold text-white tracking-tight">Equalizer</h3>
            <p className="text-[10px] text-neutral-500">
              {isEqAvailable ? '5-band audio processing' : 'Unavailable for YouTube playback'}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-1">
          <button
            onClick={() => onPresetChange('flat')}
            className="p-1.5 text-neutral-500 hover:text-white hover:bg-white/5 rounded-lg transition-colors"
            title="Reset to Flat"
          >
            <RotateCcw size={14} />
          </button>
          <button
            onClick={onClose}
            className="p-1.5 text-neutral-500 hover:text-white hover:bg-white/5 rounded-lg transition-colors"
            title="Close"
          >
            <X size={16} />
          </button>
        </div>
      </div>

      {/* Disabled overlay for YouTube */}
      {!isEqAvailable && (
        <div className="absolute inset-0 z-10 bg-black/60 backdrop-blur-sm flex flex-col items-center justify-center rounded-2xl">
          <div className="w-12 h-12 rounded-full bg-neutral-800 border border-white/10 flex items-center justify-center mb-3">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="text-neutral-400">
              <circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
            </svg>
          </div>
          <p className="text-xs text-neutral-400 font-medium text-center px-6">
            Equalizer is only available for<br />
            <span className="text-white font-bold">native audio streams</span>
          </p>
          <p className="text-[10px] text-neutral-600 mt-1">YouTube playback doesn't support EQ</p>
        </div>
      )}

      {/* Presets */}
      <div className="px-5 pb-3">
        <div className="flex flex-wrap gap-1.5">
          {PRESET_KEYS.map(key => (
            <button
              key={key}
              onClick={() => onPresetChange(key)}
              disabled={!isEqAvailable}
              className={`px-3 py-1.5 rounded-full text-[11px] font-bold transition-all duration-200 border ${
                activePreset === key
                  ? 'bg-brand text-black border-brand/40 shadow-[0_0_12px_rgba(30,215,96,0.2)]'
                  : 'bg-neutral-800/60 text-neutral-400 border-white/5 hover:border-white/15 hover:text-white'
              } disabled:opacity-40 disabled:cursor-not-allowed`}
            >
              {EQ_PRESETS[key].label}
            </button>
          ))}
        </div>
      </div>

      {/* Band Sliders */}
      <div className="px-5 pb-5 pt-1">
        <div className="flex items-end justify-between gap-2">
          {bands.map((band, idx) => (
            <div key={idx} className="flex flex-col items-center gap-1.5 flex-1">
              {/* dB readout */}
              <span className={`text-[10px] font-mono font-bold tabular-nums min-w-[32px] text-center ${
                band.gain > 0 ? 'text-brand' : band.gain < 0 ? 'text-blue-400' : 'text-neutral-500'
              }`}>
                {band.gain > 0 ? '+' : ''}{band.gain.toFixed(0)}
              </span>

              {/* Vertical slider */}
              <div className="relative h-28 w-6 flex items-center justify-center">
                <input
                  type="range"
                  min={-12}
                  max={12}
                  step={1}
                  value={band.gain}
                  onChange={(e) => onBandChange(idx, Number(e.target.value))}
                  disabled={!isEqAvailable}
                  className="eq-slider absolute"
                  style={{
                    writingMode: 'vertical-lr' as any,
                    direction: 'rtl',
                    width: '112px',
                    height: '24px',
                    appearance: 'none',
                    WebkitAppearance: 'none',
                    background: 'transparent',
                    cursor: isEqAvailable ? 'pointer' : 'not-allowed',
                    opacity: isEqAvailable ? 1 : 0.3,
                  }}
                />
                {/* Track visual */}
                <div className="absolute inset-x-0 top-0 bottom-0 flex items-center justify-center pointer-events-none">
                  <div className="w-[3px] h-full bg-neutral-700 rounded-full relative overflow-hidden">
                    <div
                      className="absolute left-0 right-0 bg-gradient-to-t from-brand/80 to-brand rounded-full transition-all duration-150"
                      style={{
                        bottom: '50%',
                        height: band.gain > 0 ? `${(band.gain / 12) * 50}%` : '0%',
                      }}
                    />
                    <div
                      className="absolute left-0 right-0 bg-gradient-to-b from-blue-400/80 to-blue-500 rounded-full transition-all duration-150"
                      style={{
                        top: '50%',
                        height: band.gain < 0 ? `${(Math.abs(band.gain) / 12) * 50}%` : '0%',
                      }}
                    />
                    {/* Center line */}
                    <div className="absolute left-0 right-0 top-1/2 -translate-y-[0.5px] h-[1px] bg-neutral-500" />
                  </div>
                </div>
              </div>

              {/* Frequency label */}
              <span className="text-[9px] text-neutral-500 font-semibold tracking-tight">
                {band.label}
              </span>
            </div>
          ))}
        </div>

        {/* dB scale labels */}
        <div className="flex justify-between px-1 mt-2">
          <span className="text-[9px] text-neutral-600">-12 dB</span>
          <span className="text-[9px] text-neutral-600">0 dB</span>
          <span className="text-[9px] text-neutral-600">+12 dB</span>
        </div>
      </div>

      {/* Footer info */}
      <div className="px-5 pb-4 pt-1 border-t border-white/5">
        <p className="text-[10px] text-neutral-600">
          Press <kbd className="px-1.5 py-0.5 bg-neutral-800 border border-white/10 rounded text-[9px] font-mono">E</kbd> to toggle • Settings persist across sessions
        </p>
      </div>
    </div>
  );
};

export default EqualizerPanel;
