import { useRef, useEffect, useCallback } from 'react';
import YouTube from 'react-youtube';
import type { Song, PlaybackEngine } from '../types';
import { getValidImage } from '../utils/imageUtils';

// ─── Props ────────────────────────────────────────────────────────────────────
interface AudioPlayerProps {
    currentTrack: Song | null;
    isPlaying: boolean;
    volume: number;
    seekToTime: number | null;
    // ── Silent Bridge Props ──────────────────────────────────────────────────
    playbackEngine: PlaybackEngine;
    nativeAudioUrl: string | null;
    youtubeVideoId: string | null;
    // ── Crossfade & Equalizer ───────────────────────────────────────────────
    crossfadeDuration: number;
    connectEqualizer: (audioElement: HTMLAudioElement | null) => void;
    // ── Callbacks ────────────────────────────────────────────────────────────
    onReady: (player: any) => void;
    onEnd: () => void;
    playNext: () => void;
    playPrevious: () => void;
    onStateChange?: (state: number) => void;
    onTimeUpdate: (time: number) => void;
    onDurationChange: (duration: number) => void;
    setIsPlaying: (playing: boolean) => void;
    setIsBuffering: (buffering: boolean) => void;
}

// ─────────────────────────────────────────────────────────────────────────────
// AudioPlayer
//
// Dual-mode player with crossfade support:
//   • playbackEngine === 'native'  → Dual HTML5 <audio> with crossfade ramp
//   • playbackEngine === 'youtube' → 1×1 hidden YouTube IFrame (react-youtube)
//
// Crossfade:
//   When crossfadeDuration > 0 and both outgoing + incoming tracks are native,
//   we start fading out the active <audio> element and fading in the standby
//   element `crossfadeDuration` seconds before the current track ends.
// ─────────────────────────────────────────────────────────────────────────────
const SILENT_AUDIO_WAV = 'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=';

export default function AudioPlayer({
    currentTrack,
    isPlaying,
    volume,
    seekToTime,
    playbackEngine,
    nativeAudioUrl,
    youtubeVideoId,
    crossfadeDuration,
    connectEqualizer,
    onReady,
    onEnd,
    onStateChange,
    onTimeUpdate,
    onDurationChange,
    playNext,
    playPrevious,
    setIsPlaying,
    setIsBuffering,
}: AudioPlayerProps) {
    // ── Dual Audio Elements for Crossfade ────────────────────────────────────
    const audioRefA = useRef<HTMLAudioElement>(null);
    const audioRefB = useRef<HTMLAudioElement>(null);
    const activeSlotRef = useRef<'A' | 'B'>('A'); // Which slot is currently the "active" player
    const keepaliveAudioRef = useRef<HTMLAudioElement>(null);
    const ytPlayerRef = useRef<any>(null);
    const loadedUrlRef = useRef<string | null>(null);

    // Crossfade state
    const crossfadeRafRef = useRef<number | null>(null);
    const isCrossfadingRef = useRef(false);
    const crossfadeTriggeredForTrackRef = useRef<string | null>(null);
    const pendingCrossfadeUrlRef = useRef<string | null>(null);

    // EQ connection tracking
    const eqConnectedElementRef = useRef<HTMLAudioElement | null>(null);

    // Helper to get the active audio element
    const getActiveAudio = useCallback((): HTMLAudioElement | null => {
        return activeSlotRef.current === 'A' ? audioRefA.current : audioRefB.current;
    }, []);

    const getStandbyAudio = useCallback((): HTMLAudioElement | null => {
        return activeSlotRef.current === 'A' ? audioRefB.current : audioRefA.current;
    }, []);

    // ── Connect EQ to the active audio element ──────────────────────────────
    const connectEqToActive = useCallback(() => {
        const active = getActiveAudio();
        if (active && active !== eqConnectedElementRef.current) {
            connectEqualizer(active);
            eqConnectedElementRef.current = active;
        }
    }, [getActiveAudio, connectEqualizer]);

    // ── 1. UNIFIED BRIDGE REGISTRATION ────────────────────────────────────────
    useEffect(() => {
        const bridge = {
            playVideo: () => {
                if (playbackEngine === 'native') {
                    try { ytPlayerRef.current?.pauseVideo?.(); } catch (e) {}
                    getActiveAudio()?.play().catch(() => {});
                } else {
                    try { getActiveAudio()?.pause(); } catch (e) {}
                    ytPlayerRef.current?.playVideo?.();
                }
            },
            pauseVideo: () => {
                try { getActiveAudio()?.pause(); } catch (e) {}
                try { getStandbyAudio()?.pause(); } catch (e) {}
                try { ytPlayerRef.current?.pauseVideo?.(); } catch (e) {}
            },
            seekTo: (s: number, allowSeekAhead = true) => {
                if (playbackEngine === 'native') {
                    const active = getActiveAudio();
                    if (active) active.currentTime = s;
                } else {
                    ytPlayerRef.current?.seekTo(s, allowSeekAhead);
                }
            },
            setVolume: (vol: number) => {
                if (playbackEngine === 'native') {
                    const active = getActiveAudio();
                    if (active) active.volume = Math.max(0, Math.min(1, vol / 100));
                } else {
                    ytPlayerRef.current?.setVolume(vol);
                }
            },
            getDuration: () => {
                if (playbackEngine === 'native') return getActiveAudio()?.duration || 0;
                return ytPlayerRef.current?.getDuration?.() || 0;
            },
            getCurrentTime: () => {
                if (playbackEngine === 'native') return getActiveAudio()?.currentTime || 0;
                return ytPlayerRef.current?.getCurrentTime?.() || 0;
            },
            getIframe: () => {
                if (playbackEngine === 'native') return { src: 'native-bridge' };
                return ytPlayerRef.current?.getIframe?.() || {};
            }
        };

        onReady(bridge);
    }, [playbackEngine, nativeAudioUrl, youtubeVideoId, onReady, getActiveAudio, getStandbyAudio]);

    // ── Track Switch & Stale Audio Prevention Guard ─────────────────────────
    const currentTrackIdRef = useRef<string | null>(null);
    useEffect(() => {
        if (currentTrack?.id && currentTrack.id !== currentTrackIdRef.current) {
            currentTrackIdRef.current = currentTrack.id;

            // Cancel any in-flight crossfade
            if (crossfadeRafRef.current) {
                cancelAnimationFrame(crossfadeRafRef.current);
                crossfadeRafRef.current = null;
            }
            isCrossfadingRef.current = false;
            crossfadeTriggeredForTrackRef.current = null;

            // Stop both audio elements unless crossfade is loading them
            if (!pendingCrossfadeUrlRef.current) {
                [audioRefA.current, audioRefB.current].forEach(el => {
                    if (el) {
                        try {
                            el.pause();
                            el.removeAttribute('src');
                            el.load();
                        } catch (e) {}
                    }
                });
                loadedUrlRef.current = null;
            }

            // Stop YouTube
            if (ytPlayerRef.current) {
                try {
                    ytPlayerRef.current.stopVideo?.();
                    ytPlayerRef.current.pauseVideo?.();
                } catch (e) {}
            }

            // Pause keepalive
            if (keepaliveAudioRef.current) {
                try { keepaliveAudioRef.current.pause(); } catch (e) {}
            }
        }
    }, [currentTrack?.id]);

    // ── 2. NATIVE ENGINE: load new URL & state management ──────────────────────
    useEffect(() => {
        const active = getActiveAudio();
        if (playbackEngine !== 'native' || !active) {
            [audioRefA.current, audioRefB.current].forEach(el => {
                if (el) {
                    try {
                        el.pause();
                        el.removeAttribute('src');
                        el.load();
                    } catch (e) {}
                }
            });
            loadedUrlRef.current = null;
            return;
        }

        if (!nativeAudioUrl || nativeAudioUrl.trim() === '') {
            try {
                active.pause();
                active.removeAttribute('src');
                active.load();
            } catch (e) {}
            loadedUrlRef.current = null;
            return;
        }

        // If this URL was loaded via crossfade into the standby, skip double-loading
        if (pendingCrossfadeUrlRef.current === nativeAudioUrl) {
            pendingCrossfadeUrlRef.current = null;
            return;
        }

        if (nativeAudioUrl !== loadedUrlRef.current) {
            loadedUrlRef.current = nativeAudioUrl;
            active.src = nativeAudioUrl;
            active.load();

            // Connect EQ to active
            connectEqToActive();

            if (isPlaying) {
                active.play().catch(e => console.warn('[AudioPlayer] Native play failed:', e));
            }
        }
    }, [nativeAudioUrl, playbackEngine, isPlaying, getActiveAudio, connectEqToActive]);

    // Ensure YouTube player is hard-stopped when engine is not 'youtube'
    useEffect(() => {
        if (playbackEngine !== 'youtube' && ytPlayerRef.current) {
            try {
                ytPlayerRef.current.stopVideo?.();
                ytPlayerRef.current.pauseVideo?.();
            } catch (e) {}
        }
    }, [playbackEngine]);

    // ── 3. NATIVE ENGINE: play/pause sync ────────────────────────────────────
    useEffect(() => {
        const active = getActiveAudio();
        if (playbackEngine !== 'native' || !active || !nativeAudioUrl) return;

        if (isPlaying) {
            active.play().catch(e => console.warn('[AudioPlayer] Native play error:', e));
        } else {
            active.pause();
        }
    }, [isPlaying, nativeAudioUrl, playbackEngine, getActiveAudio]);

    // ── 4. NATIVE ENGINE: volume sync ────────────────────────────────────────
    useEffect(() => {
        const active = getActiveAudio();
        if (active && !isCrossfadingRef.current) {
            active.volume = Math.max(0, Math.min(1, volume));
        }
    }, [volume, getActiveAudio]);

    // ── 5. NATIVE ENGINE: seek sync ───────────────────────────────────────────
    useEffect(() => {
        if (playbackEngine === 'native' && seekToTime !== null) {
            const active = getActiveAudio();
            if (active) active.currentTime = seekToTime;
        }
    }, [seekToTime, playbackEngine, getActiveAudio]);

    // ── 6. CROSSFADE ENGINE ─────────────────────────────────────────────────
    // Detect approaching end-of-track and trigger crossfade
    const handleCrossfadeCheck = useCallback((currentTime: number, duration: number) => {
        if (
            crossfadeDuration <= 0 ||
            playbackEngine !== 'native' ||
            isCrossfadingRef.current ||
            !duration ||
            duration <= crossfadeDuration + 1 // Track too short for crossfade
        ) {
            return;
        }

        const trackId = currentTrackIdRef.current;
        if (crossfadeTriggeredForTrackRef.current === trackId) return; // Already triggered

        const timeLeft = duration - currentTime;
        if (timeLeft <= crossfadeDuration && timeLeft > 0) {
            crossfadeTriggeredForTrackRef.current = trackId;
            // Signal the parent to advance to next track — the crossfade ramp will handle audio
            isCrossfadingRef.current = true;
            startCrossfadeRamp(crossfadeDuration);
            onEnd(); // This triggers playNext in AudioContext
        }
    }, [crossfadeDuration, playbackEngine, onEnd]);

    const startCrossfadeRamp = useCallback((durationSec: number) => {
        const outgoing = getActiveAudio();
        const incoming = getStandbyAudio();
        if (!outgoing || !incoming) {
            isCrossfadingRef.current = false;
            return;
        }

        const startTime = performance.now();
        const totalMs = durationSec * 1000;
        const startVolume = outgoing.volume;
        const targetVolume = Math.max(0, Math.min(1, volume));

        // Start incoming at 0 volume (it will be loaded by the next track's URL update)
        incoming.volume = 0;

        const ramp = (now: number) => {
            const elapsed = now - startTime;
            const progress = Math.min(1, elapsed / totalMs);

            // Ease-in-out curve for smooth transition
            const eased = progress < 0.5
                ? 2 * progress * progress
                : 1 - Math.pow(-2 * progress + 2, 2) / 2;

            outgoing.volume = startVolume * (1 - eased);

            // Incoming may not have loaded yet, set volume anyway
            if (incoming.src && incoming.readyState >= 2) {
                incoming.volume = targetVolume * eased;
            }

            if (progress < 1) {
                crossfadeRafRef.current = requestAnimationFrame(ramp);
            } else {
                // Ramp complete: swap slots
                outgoing.volume = 0;
                try {
                    outgoing.pause();
                    outgoing.removeAttribute('src');
                    outgoing.load();
                } catch {}

                incoming.volume = targetVolume;

                // Swap active slot
                activeSlotRef.current = activeSlotRef.current === 'A' ? 'B' : 'A';

                // Reconnect EQ to new active
                connectEqToActive();

                loadedUrlRef.current = incoming.src || null;
                isCrossfadingRef.current = false;
                crossfadeRafRef.current = null;
            }
        };

        crossfadeRafRef.current = requestAnimationFrame(ramp);
    }, [getActiveAudio, getStandbyAudio, volume, connectEqToActive]);

    // ── 7. YOUTUBE ENGINE: react-youtube opts ────────────────────────────────
    const ytOpts = {
        height: '1',
        width: '1',
        playerVars: {
            autoplay: 0 as const,
            controls: 0 as const,
            disablekb: 1 as const,
            fs: 0 as const,
            rel: 0 as const,
            modestbranding: 1 as const,
            playsinline: 1 as const,
        },
    };

    const handleYTReady = (event: any) => {
        const player = event.target;
        ytPlayerRef.current = player;
        try { player.setVolume(volume * 100); } catch (e) {}

        if (playbackEngine === 'youtube' && isPlaying) {
            player.playVideo?.();
        } else {
            player.pauseVideo?.();
        }
    };

    // YouTube play/pause sync with isPlaying
    useEffect(() => {
        if (playbackEngine === 'youtube' && ytPlayerRef.current) {
            if (isPlaying) {
                ytPlayerRef.current.playVideo?.();
            } else {
                ytPlayerRef.current.pauseVideo?.();
            }
        }
    }, [isPlaying, playbackEngine]);

    const handleYTStateChange = (event: any) => {
        if (playbackEngine !== 'youtube') {
            try { event.target?.pauseVideo?.(); } catch (e) {}
            return;
        }
        const state: number = event.data;
        if (state === 1) {
            setIsBuffering(false);
            setIsPlaying(true);
            const dur = event.target?.getDuration?.() || 0;
            if (dur) onDurationChange(dur);
        } else if (state === 2) {
            if (playbackEngine === 'youtube') {
                setIsPlaying(false);
            }
        } else if (state === 3) {
            setIsBuffering(true);
        } else if (state === 0) {
            setIsPlaying(false);
            onEnd();
        }
        if (onStateChange) onStateChange(state);
    };

    // Poll YouTube currentTime & duration at 250ms
    useEffect(() => {
        if (playbackEngine !== 'youtube') return;
        const interval = setInterval(() => {
            if (isPlaying) {
                const t = ytPlayerRef.current?.getCurrentTime?.();
                if (typeof t === 'number' && isFinite(t)) onTimeUpdate(t);
                const dur = ytPlayerRef.current?.getDuration?.();
                if (typeof dur === 'number' && isFinite(dur) && dur > 0) onDurationChange(dur);
            }
        }, 250);
        return () => clearInterval(interval);
    }, [playbackEngine, isPlaying, onTimeUpdate, onDurationChange]);

    // YouTube seek sync
    useEffect(() => {
        if (playbackEngine === 'youtube' && ytPlayerRef.current && seekToTime !== null) {
            ytPlayerRef.current.seekTo(seekToTime, true);
        }
    }, [seekToTime, playbackEngine]);

    // YouTube volume sync
    useEffect(() => {
        if (playbackEngine === 'youtube' && ytPlayerRef.current) {
            ytPlayerRef.current.setVolume(volume * 100);
        }
    }, [volume, playbackEngine]);

    // ── 8. MEDIA SESSION API ─────────────────────────────────────────────────
    useEffect(() => {
        if (!('mediaSession' in navigator) || !currentTrack) return;

        navigator.mediaSession.metadata = new MediaMetadata({
            title: currentTrack.title || 'Unknown Title',
            artist: currentTrack.artist || 'Unknown Artist',
            album: currentTrack.album || '',
            artwork: [{ src: getValidImage(currentTrack), sizes: '512x512', type: 'image/png' }],
        });

        navigator.mediaSession.setActionHandler('play', () => {
            if (playbackEngine === 'native') getActiveAudio()?.play().catch(() => {});
            else ytPlayerRef.current?.playVideo();
            setIsPlaying(true);
        });
        navigator.mediaSession.setActionHandler('pause', () => {
            if (playbackEngine === 'native') getActiveAudio()?.pause();
            else ytPlayerRef.current?.pauseVideo();
            setIsPlaying(false);
        });
        navigator.mediaSession.setActionHandler('nexttrack', playNext);
        navigator.mediaSession.setActionHandler('previoustrack', playPrevious);
        navigator.mediaSession.playbackState = isPlaying ? 'playing' : 'paused';
    }, [currentTrack, isPlaying, playNext, playPrevious, setIsPlaying, playbackEngine, getActiveAudio]);

    // ── 9. SCREEN-OFF KEEPALIVE ENGINE ──────────────────────────────────────
    useEffect(() => {
        if (!keepaliveAudioRef.current) return;

        if (playbackEngine === 'youtube' && isPlaying) {
            keepaliveAudioRef.current.volume = 0.001;
            keepaliveAudioRef.current.play().catch(e => {
                console.debug('[AudioPlayer] AudioSession keepalive notice:', e);
            });
        } else {
            keepaliveAudioRef.current.pause();
        }
    }, [playbackEngine, isPlaying]);

    // ── 10. WAKE LOCK API ─────────────────────────────────────────────────────
    useEffect(() => {
        let wakeLock: any = null;
        if ('wakeLock' in navigator && isPlaying) {
            (navigator as any).wakeLock?.request('screen')
                .then((lock: any) => { wakeLock = lock; })
                .catch((e: any) => { console.debug('[AudioPlayer] Wake lock notice:', e); });
        }
        return () => {
            if (wakeLock) wakeLock.release().catch(() => {});
        };
    }, [isPlaying]);

    // ── 11. NATIVE ENGINE: event handlers ────────────────────────────────────
    const handleTimeUpdate = (slot: 'A' | 'B') => () => {
        if (playbackEngine !== 'native') return;
        // Only report time from the active slot
        if (slot !== activeSlotRef.current) return;
        const el = slot === 'A' ? audioRefA.current : audioRefB.current;
        if (el) {
            onTimeUpdate(el.currentTime);
            if (typeof el.duration === 'number' && isFinite(el.duration) && !isNaN(el.duration) && el.duration > 0) {
                onDurationChange(el.duration);
            }
            // Check if crossfade should start
            if (el.duration && el.duration > 0) {
                handleCrossfadeCheck(el.currentTime, el.duration);
            }
        }
    };

    const handleLoadedMetadata = (slot: 'A' | 'B') => () => {
        if (playbackEngine !== 'native') return;
        if (slot !== activeSlotRef.current) return;
        const el = slot === 'A' ? audioRefA.current : audioRefB.current;
        if (el) {
            if (typeof el.duration === 'number' && isFinite(el.duration) && !isNaN(el.duration) && el.duration > 0) {
                onDurationChange(el.duration);
            }
            setIsBuffering(false);
        }
    };

    const handleNativeEnd = (slot: 'A' | 'B') => () => {
        if (playbackEngine !== 'native') return;
        if (slot !== activeSlotRef.current) return;
        // If crossfade already triggered onEnd, don't double-trigger
        if (isCrossfadingRef.current) return;
        setIsPlaying(false);
        if (onStateChange) onStateChange(0);
        onEnd();
    };

    return (
        <div
            className="silent-bridge-player"
            aria-hidden="true"
            style={{
                position: 'fixed',
                bottom: 0,
                left: 0,
                width: '1px',
                height: '1px',
                overflow: 'hidden',
                opacity: 0,
                pointerEvents: 'none',
                zIndex: -1
            }}
        >
            {/* NATIVE ENGINE SLOT A */}
            <audio
                ref={audioRefA}
                src={playbackEngine === 'native' && activeSlotRef.current === 'A' ? (nativeAudioUrl || undefined) : undefined}
                onTimeUpdate={handleTimeUpdate('A')}
                onLoadedMetadata={handleLoadedMetadata('A')}
                onDurationChange={handleLoadedMetadata('A')}
                onCanPlay={handleLoadedMetadata('A')}
                onLoadedData={handleLoadedMetadata('A')}
                onWaiting={() => { if (playbackEngine === 'native' && activeSlotRef.current === 'A') setIsBuffering(true); }}
                onPlaying={() => {
                    if (playbackEngine === 'native' && activeSlotRef.current === 'A') {
                        setIsBuffering(false);
                        setIsPlaying(true);
                        if (onStateChange) onStateChange(1);
                    }
                }}
                onPause={() => {
                    if (playbackEngine === 'native' && activeSlotRef.current === 'A' && isPlaying && !isCrossfadingRef.current) {
                        setIsPlaying(false);
                        if (onStateChange) onStateChange(2);
                    }
                }}
                onEnded={handleNativeEnd('A')}
                onError={(e) => {
                    if (playbackEngine === 'native' && activeSlotRef.current === 'A') {
                        console.error('[AudioPlayer] Native audio error (A):', e);
                        setIsBuffering(false);
                    }
                }}
                playsInline
                crossOrigin="anonymous"
            />

            {/* NATIVE ENGINE SLOT B (crossfade standby) */}
            <audio
                ref={audioRefB}
                onTimeUpdate={handleTimeUpdate('B')}
                onLoadedMetadata={handleLoadedMetadata('B')}
                onDurationChange={handleLoadedMetadata('B')}
                onCanPlay={handleLoadedMetadata('B')}
                onLoadedData={handleLoadedMetadata('B')}
                onWaiting={() => { if (playbackEngine === 'native' && activeSlotRef.current === 'B') setIsBuffering(true); }}
                onPlaying={() => {
                    if (playbackEngine === 'native' && activeSlotRef.current === 'B') {
                        setIsBuffering(false);
                        setIsPlaying(true);
                        if (onStateChange) onStateChange(1);
                    }
                }}
                onPause={() => {
                    if (playbackEngine === 'native' && activeSlotRef.current === 'B' && isPlaying && !isCrossfadingRef.current) {
                        setIsPlaying(false);
                        if (onStateChange) onStateChange(2);
                    }
                }}
                onEnded={handleNativeEnd('B')}
                onError={(e) => {
                    if (playbackEngine === 'native' && activeSlotRef.current === 'B') {
                        console.error('[AudioPlayer] Native audio error (B):', e);
                        setIsBuffering(false);
                    }
                }}
                playsInline
                crossOrigin="anonymous"
            />

            {/* AUDIO SESSION KEEPALIVE */}
            <audio
                ref={keepaliveAudioRef}
                src={SILENT_AUDIO_WAV}
                loop
                playsInline
                preload="auto"
            />

            {/* YOUTUBE ENGINE — 1×1 Hidden IFrame */}
            {playbackEngine === 'youtube' && youtubeVideoId && (
                <YouTube
                    key={youtubeVideoId}
                    videoId={youtubeVideoId}
                    opts={ytOpts}
                    onReady={handleYTReady}
                    onStateChange={handleYTStateChange}
                    onError={(e) => {
                        console.error('[AudioPlayer] YouTube IFrame error:', e);
                        setIsBuffering(false);
                    }}
                />
            )}
        </div>
    );
}
