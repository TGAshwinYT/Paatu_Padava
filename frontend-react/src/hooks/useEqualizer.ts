import { useRef, useState, useCallback, useEffect } from 'react';

// ─── EQ Preset Definitions ──────────────────────────────────────────────────
export type EqPreset = 'flat' | 'bass_boost' | 'treble_boost' | 'vocal' | 'rock' | 'electronic';

export interface EqBand {
  frequency: number;
  type: BiquadFilterType;
  label: string;
  gain: number; // -12 to +12 dB
}

const BAND_CONFIGS: { frequency: number; type: BiquadFilterType; label: string }[] = [
  { frequency: 60,    type: 'lowshelf',  label: '60 Hz'  },
  { frequency: 230,   type: 'peaking',   label: '230 Hz' },
  { frequency: 910,   type: 'peaking',   label: '910 Hz' },
  { frequency: 4000,  type: 'peaking',   label: '4 kHz'  },
  { frequency: 14000, type: 'highshelf', label: '14 kHz' },
];

export const EQ_PRESETS: Record<EqPreset, { label: string; gains: number[] }> = {
  flat:          { label: 'Flat',          gains: [0,  0,  0,  0,  0 ] },
  bass_boost:   { label: 'Bass Boost',    gains: [8,  5,  0, -1, -1 ] },
  treble_boost: { label: 'Treble Boost',  gains: [-1, 0,  0,  4,  7 ] },
  vocal:        { label: 'Vocal',         gains: [-2, 0,  4,  3,  1 ] },
  rock:         { label: 'Rock',          gains: [5,  3, -1,  3,  5 ] },
  electronic:   { label: 'Electronic',    gains: [6,  4,  0,  2,  5 ] },
};

const STORAGE_KEY_PRESET = 'paatu_eq_preset';
const STORAGE_KEY_BANDS  = 'paatu_eq_bands';

// ─── Hook ────────────────────────────────────────────────────────────────────
export function useEqualizer() {
  // Web Audio API singletons (lazy-init)
  const audioContextRef = useRef<AudioContext | null>(null);
  const filtersRef = useRef<BiquadFilterNode[]>([]);
  const sourceNodeRef = useRef<MediaElementAudioSourceNode | null>(null);
  const connectedElementRef = useRef<HTMLAudioElement | null>(null);

  // State
  const [bands, setBands] = useState<EqBand[]>(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY_BANDS);
      if (saved) {
        const gains: number[] = JSON.parse(saved);
        return BAND_CONFIGS.map((cfg, i) => ({ ...cfg, gain: gains[i] ?? 0 }));
      }
    } catch {}
    return BAND_CONFIGS.map(cfg => ({ ...cfg, gain: 0 }));
  });

  const [activePreset, setActivePreset] = useState<EqPreset>(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY_PRESET);
      if (saved && saved in EQ_PRESETS) return saved as EqPreset;
    } catch {}
    return 'flat';
  });

  const [isEqAvailable, setIsEqAvailable] = useState(true);

  // Persist to localStorage
  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY_PRESET, activePreset);
      localStorage.setItem(STORAGE_KEY_BANDS, JSON.stringify(bands.map(b => b.gain)));
    } catch {}
  }, [bands, activePreset]);

  // ── Lazy AudioContext + Filter Chain Initialization ────────────────────────
  const ensureAudioContext = useCallback(() => {
    if (audioContextRef.current) return audioContextRef.current;

    const ctx = new (window.AudioContext || (window as any).webkitAudioContext)();
    audioContextRef.current = ctx;

    // Create filter chain
    const filters: BiquadFilterNode[] = BAND_CONFIGS.map((cfg, i) => {
      const filter = ctx.createBiquadFilter();
      filter.type = cfg.type;
      filter.frequency.value = cfg.frequency;
      filter.gain.value = bands[i]?.gain ?? 0;
      if (cfg.type === 'peaking') {
        filter.Q.value = 1.0;
      }
      return filter;
    });

    // Chain filters together: filter[0] → filter[1] → ... → filter[n] → destination
    for (let i = 0; i < filters.length - 1; i++) {
      filters[i].connect(filters[i + 1]);
    }
    filters[filters.length - 1].connect(ctx.destination);

    filtersRef.current = filters;
    return ctx;
  }, []);

  // ── Connect an <audio> element to the EQ chain ────────────────────────────
  const connectSource = useCallback((audioElement: HTMLAudioElement | null) => {
    if (!audioElement) return;

    // Don't reconnect the same element
    if (connectedElementRef.current === audioElement && sourceNodeRef.current) {
      return;
    }

    const ctx = ensureAudioContext();

    // Resume suspended AudioContext (browser autoplay policy)
    if (ctx.state === 'suspended') {
      ctx.resume().catch(() => {});
    }

    // Disconnect previous source if different element
    if (sourceNodeRef.current && connectedElementRef.current !== audioElement) {
      try {
        sourceNodeRef.current.disconnect();
      } catch {}
      sourceNodeRef.current = null;
    }

    try {
      const source = ctx.createMediaElementSource(audioElement);
      source.connect(filtersRef.current[0]);
      sourceNodeRef.current = source;
      connectedElementRef.current = audioElement;
    } catch (e: any) {
      // If the element already has a source node, reconnect
      if (e.name === 'InvalidStateError' && sourceNodeRef.current) {
        try {
          sourceNodeRef.current.disconnect();
          sourceNodeRef.current.connect(filtersRef.current[0]);
          connectedElementRef.current = audioElement;
        } catch {}
      } else {
        console.warn('[useEqualizer] Failed to connect audio source:', e);
      }
    }
  }, [ensureAudioContext]);

  // ── Disconnect current source ─────────────────────────────────────────────
  const disconnectSource = useCallback(() => {
    if (sourceNodeRef.current) {
      try {
        sourceNodeRef.current.disconnect();
      } catch {}
      sourceNodeRef.current = null;
      connectedElementRef.current = null;
    }
  }, []);

  // ── Set a single band's gain ──────────────────────────────────────────────
  const setBandGain = useCallback((bandIndex: number, gainDb: number) => {
    const clamped = Math.max(-12, Math.min(12, gainDb));

    if (filtersRef.current[bandIndex]) {
      filtersRef.current[bandIndex].gain.value = clamped;
    }

    setBands(prev => {
      const next = [...prev];
      next[bandIndex] = { ...next[bandIndex], gain: clamped };
      return next;
    });
  }, []);

  // ── Apply a named preset ──────────────────────────────────────────────────
  const applyPreset = useCallback((preset: EqPreset) => {
    const gains = EQ_PRESETS[preset]?.gains ?? [0, 0, 0, 0, 0];

    filtersRef.current.forEach((filter, i) => {
      filter.gain.value = gains[i] ?? 0;
    });

    setBands(prev => prev.map((band, i) => ({ ...band, gain: gains[i] ?? 0 })));
    setActivePreset(preset);
  }, []);

  // ── Set EQ availability (false for YouTube engine) ────────────────────────
  const setEqEnabled = useCallback((enabled: boolean) => {
    setIsEqAvailable(enabled);
  }, []);

  return {
    bands,
    activePreset,
    isEqAvailable,
    setBandGain,
    applyPreset,
    connectSource,
    disconnectSource,
    setEqEnabled,
  };
}

export default useEqualizer;
