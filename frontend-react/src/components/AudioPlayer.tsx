import { useRef, useEffect } from 'react';
import YouTube from 'react-youtube';
import type { YouTubeProps, YouTubeEvent } from 'react-youtube';
import type { Song } from '../types';
import { getValidImage } from '../utils/imageUtils';

interface AudioPlayerProps {
    currentVideoId: string | null;
    currentTrack: Song | null;
    isPlaying: boolean;
    volume: number;
    seekToTime: number | null;
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

export default function AudioPlayer({ 
    currentVideoId, 
    currentTrack,
    isPlaying, 
    volume, 
    seekToTime,
    onReady, 
    onEnd,
    onStateChange,
    onTimeUpdate,
    onDurationChange,
    playNext,
    playPrevious,
    setIsPlaying,
    setIsBuffering
}: AudioPlayerProps) {
    const playerRef = useRef<any>(null);
    const silentAudioRef = useRef<HTMLAudioElement>(null);

    // A mathematically silent, 1-second WAV file base64
    const SILENT_WAV = "data:audio/wav;base64,UklGRigAAABXQVZFZm10IBIAAAABAAEARKwAAIhYAQACABAAAABkYXRhAgAAAAEA";

    // --- 0. MEDIA SESSION SYNC (THE FIX FOR BACKGROUND PLAYBACK) ---
    useEffect(() => {
        if (!('mediaSession' in navigator) || !currentTrack) return;

        // 1. Sync Metadata to OS Lock Screen
        navigator.mediaSession.metadata = new MediaMetadata({
            title: currentTrack.title || 'Unknown Title',
            artist: currentTrack.artist || 'Unknown Artist',
            album: currentTrack.album || '',
            artwork: [
                { src: getValidImage(currentTrack), sizes: '512x512', type: 'image/png' }
            ]
        });

        // 2. Register Global Media Handlers
        navigator.mediaSession.setActionHandler('play', () => {
            if (playerRef.current) {
                playerRef.current.playVideo();
                setIsPlaying(true);
            }
        });
        
        navigator.mediaSession.setActionHandler('pause', () => {
            if (playerRef.current) {
                playerRef.current.pauseVideo();
                setIsPlaying(false);
            }
        });

        navigator.mediaSession.setActionHandler('nexttrack', () => {
            playNext();
        });

        navigator.mediaSession.setActionHandler('previoustrack', () => {
            playPrevious();
        });

        // Sync Playback State back to OS
        navigator.mediaSession.playbackState = isPlaying ? 'playing' : 'paused';

        return () => {
            // Cleanup handlers on unmount
            navigator.mediaSession.setActionHandler('play', null);
            navigator.mediaSession.setActionHandler('pause', null);
            navigator.mediaSession.setActionHandler('nexttrack', null);
            navigator.mediaSession.setActionHandler('previoustrack', null);
        };
    }, [currentTrack, isPlaying, playNext, playPrevious, setIsPlaying]);

    // --- 1. SYNC ENGINE (POLLING) ---
    useEffect(() => {
        let interval: any;
        if (isPlaying && playerRef.current) {
            interval = setInterval(async () => {
                try {
                    // Force a check that the player and its internal bridge are actually alive
                    if (!playerRef.current || typeof playerRef.current.getIframe !== 'function') return;
                    
                    const iframe = playerRef.current.getIframe();
                    if (!iframe) return; // This prevents the 'reading src of null' crash

                    const time = await playerRef.current.getCurrentTime();
                    onTimeUpdate(time);
                    
                    const songDuration = await playerRef.current.getDuration();
                    if (songDuration > 0) {
                        onDurationChange(songDuration);
                    }
                } catch (e) {
                    // Silently skip if the player is being re-initialized
                }
            }, 1000);
        }
        return () => clearInterval(interval);
    }, [isPlaying, currentVideoId, onTimeUpdate, onDurationChange]);

    // --- 2. INTERACTION HANDLERS ---
    

    // Sync play/pause state
    useEffect(() => {
        if (!playerRef.current || typeof playerRef.current.playVideo !== 'function') return;
        try {
            const iframe = typeof playerRef.current.getIframe === 'function' ? playerRef.current.getIframe() : null;
            if (!iframe) return;

            if (isPlaying) {
                playerRef.current.playVideo();
            } else {
                playerRef.current.pauseVideo();
            }
        } catch (e) {
            // Silently recover if player is mid-transition
        }
    }, [isPlaying]); 

    // Sync volume (YouTube is 0-100, our context is 0-1)
    useEffect(() => {
        if (!playerRef.current || typeof playerRef.current.setVolume !== 'function') return;
        try {
            playerRef.current.setVolume(volume * 100);
        } catch (e) {}
    }, [volume]);

    // Handle manual seeks from Context
    useEffect(() => {
        if (!playerRef.current || seekToTime === null || typeof playerRef.current.seekTo !== 'function') return;
        try {
            playerRef.current.seekTo(seekToTime, true);
        } catch (e) {}
    }, [seekToTime]);

    const handleReady = (event: YouTubeEvent) => {
        playerRef.current = event.target;
        playerRef.current.setVolume(volume * 100);
        onReady(event.target);
    };

    const handleStateChange = (event: YouTubeEvent) => {
        const playerState = event.data;

        // THE FIX: State 5 = Video Cued. 
        // The library automatically cues new songs. Once cued, we force it to play instantly.
        if (playerState === 5) {
            playerRef.current?.playVideo();
        }

        // 3 = Buffering, -1 = Unstarted
        if (playerState === 3 || playerState === -1) {
            setIsBuffering(true);
        }
        // 1 = Playing
        if (playerState === 1) {
            setIsBuffering(false);
            setIsPlaying(true);
            // Engage the Wake-Lock
            if (silentAudioRef.current) {
                silentAudioRef.current.play().catch(() => console.log("Wake-lock initialized"));
            }
        }
        // 2 = Paused, 0 = Ended
        if (playerState === 2) {
            setIsBuffering(false);
            setIsPlaying(false);
            // Release the Wake-Lock
            if (silentAudioRef.current) {
                silentAudioRef.current.pause();
            }
        }

        if (playerState === 0) {
            setIsBuffering(false);
            setIsPlaying(false);
            // Release the Wake-Lock
            if (silentAudioRef.current) {
                silentAudioRef.current.pause();
            }
            // THE FIX: Immediately trigger the next song state to bypass background throttling
            onEnd(); 
        }

        if (onStateChange) {
            onStateChange(event.data);
        }
    };

    // --- 3. PRE-WARMING CONFIGURATION ---
    const opts: YouTubeProps['opts'] = {
        height: '1', 
        width: '1',  
        playerVars: {
            autoplay: 0, 
            controls: 0,
            disablekb: 1,
            fs: 0,
            playsinline: 1,
            modestbranding: 1,
            rel: 0,
            // THE CORS FIX: Explicitly declare origin
            origin: typeof window !== 'undefined' ? window.location.origin : 'https://paatupadava.vercel.app',
            enablejsapi: 1,
            // Suggested lowest possible quality (144p) to save user bandwidth
            vq: 'tiny',
        },
    };

    return (
        <div className="custom-audio-player">
            {/* THE FIX: Visually hidden, but fully active in the browser's rendering engine to bypass throttling */}
            <div style={{ 
                position: 'absolute', 
                opacity: 0, 
                pointerEvents: 'none', 
                zIndex: -100,
                top: 0,
                left: 0,
                width: '1px',
                height: '1px',
                overflow: 'hidden'
            }}>
                <YouTube 
                    videoId={currentVideoId || ''} 
                    opts={opts} 
                    onReady={handleReady} 
                    onEnd={onEnd}
                    onStateChange={handleStateChange}
                />
            </div>

            {/* THE FIX: The Silent Wake-Lock. Loops infinitely in the background */}
            <audio 
                ref={silentAudioRef} 
                src={SILENT_WAV} 
                loop 
                playsInline 
                style={{ display: 'none' }} 
            />
        </div>
    );
}
