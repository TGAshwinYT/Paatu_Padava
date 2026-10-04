import React, { useRef, useEffect } from 'react';

export type VisualizerMode = 'bars' | 'wave' | 'off';

interface AudioVisualizerProps {
  isPlaying: boolean;
  mode: VisualizerMode;
  className?: string;
  accentColor?: string;
}

const AudioVisualizer: React.FC<AudioVisualizerProps> = ({
  isPlaying,
  mode,
  className = '',
  accentColor = '#22c55e'
}) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const animationFrameRef = useRef<number | null>(null);
  const phaseRef = useRef<number>(0);
  const energyRef = useRef<number>(isPlaying ? 1 : 0);
  const barsDataRef = useRef<number[]>([]);

  useEffect(() => {
    if (mode === 'off') return;

    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Set canvas dimensions respecting DPR for sharp rendering
    const updateCanvasSize = () => {
      const rect = canvas.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.max(rect.width * dpr, 300);
      canvas.height = Math.max(rect.height * dpr, 150);
    };

    updateCanvasSize();
    const resizeObserver = new ResizeObserver(() => updateCanvasSize());
    resizeObserver.observe(canvas);

    const BAR_COUNT = 48;
    if (barsDataRef.current.length !== BAR_COUNT) {
      barsDataRef.current = Array.from({ length: BAR_COUNT }, () => 0.1);
    }

    const render = () => {
      const width = canvas.width;
      const height = canvas.height;

      ctx.clearRect(0, 0, width, height);

      // Smooth energy transition on play/pause
      const targetEnergy = isPlaying ? 1.0 : 0.08;
      energyRef.current += (targetEnergy - energyRef.current) * 0.08;
      phaseRef.current += isPlaying ? 0.04 : 0.01;

      const energy = energyRef.current;
      const phase = phaseRef.current;

      if (mode === 'bars') {
        // ── Spectrum Bars Mode ──────────────────────────────────────
        const barWidth = width / (BAR_COUNT * 1.5);
        const gap = barWidth * 0.5;
        const totalWidth = BAR_COUNT * (barWidth + gap) - gap;
        const startX = (width - totalWidth) / 2;

        const gradient = ctx.createLinearGradient(0, height, 0, 0);
        gradient.addColorStop(0, 'rgba(16, 185, 129, 0.2)');
        gradient.addColorStop(0.5, accentColor);
        gradient.addColorStop(1, 'rgba(52, 211, 153, 0.9)');

        ctx.fillStyle = gradient;

        for (let i = 0; i < BAR_COUNT; i++) {
          // Compute organic multi-frequency harmonic response
          const normalizedI = i / BAR_COUNT;
          const bellCurve = Math.sin(normalizedI * Math.PI);
          
          const wave1 = Math.sin(phase * 2.5 + i * 0.35);
          const wave2 = Math.cos(phase * 1.8 - i * 0.2);
          const wave3 = Math.sin(phase * 3.7 + i * 0.5);

          const rawHeight = (0.2 + (wave1 * 0.35 + wave2 * 0.25 + wave3 * 0.15)) * bellCurve;
          const targetH = Math.max(0.04, Math.min(1.0, rawHeight * energy));

          // Interpolate current bar height for silky smooth 60fps movement
          barsDataRef.current[i] += (targetH - barsDataRef.current[i]) * 0.18;
          const h = barsDataRef.current[i] * (height * 0.75);

          const x = startX + i * (barWidth + gap);
          const y = height - h;

          // Draw rounded bar
          ctx.beginPath();
          const r = Math.min(barWidth / 2, 4);
          ctx.roundRect(x, y, barWidth, h, [r, r, 0, 0]);
          ctx.fill();

          // Subtle glowing mirror reflection
          ctx.fillStyle = 'rgba(34, 197, 94, 0.08)';
          ctx.beginPath();
          ctx.roundRect(x, height, barWidth, h * 0.2, [0, 0, r, r]);
          ctx.fill();
          ctx.fillStyle = gradient;
        }
      } else if (mode === 'wave') {
        // ── Liquid Wave / Aurora Mode ──────────────────────────────
        const layers = [
          { speed: 1.0, amp: 0.25, freq: 0.008, alpha: 0.35, color: 'rgba(16, 185, 129, ' },
          { speed: 1.4, amp: 0.20, freq: 0.012, alpha: 0.25, color: 'rgba(59, 130, 246, ' },
          { speed: 0.7, amp: 0.30, freq: 0.006, alpha: 0.45, color: 'rgba(34, 197, 94, ' }
        ];

        layers.forEach((layer) => {
          ctx.beginPath();
          ctx.moveTo(0, height);

          for (let x = 0; x <= width; x += 12) {
            const baseY = height * 0.75;
            const w1 = Math.sin(x * layer.freq + phase * layer.speed) * (height * layer.amp * energy);
            const w2 = Math.cos(x * layer.freq * 0.6 - phase * layer.speed * 0.8) * (height * 0.08 * energy);
            const y = baseY + w1 + w2;
            ctx.lineTo(x, y);
          }

          ctx.lineTo(width, height);
          ctx.closePath();

          const waveGrad = ctx.createLinearGradient(0, height * 0.4, 0, height);
          waveGrad.addColorStop(0, `${layer.color}${layer.alpha})`);
          waveGrad.addColorStop(1, `${layer.color}0.02)`);

          ctx.fillStyle = waveGrad;
          ctx.fill();
        });
      }

      animationFrameRef.current = requestAnimationFrame(render);
    };

    animationFrameRef.current = requestAnimationFrame(render);

    return () => {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
      }
      resizeObserver.disconnect();
    };
  }, [isPlaying, mode, accentColor]);

  if (mode === 'off') return null;

  return (
    <canvas 
      ref={canvasRef} 
      className={`w-full h-full pointer-events-none ${className}`}
    />
  );
};

export default AudioVisualizer;
