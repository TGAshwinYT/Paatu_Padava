import { useRef, useEffect } from 'react';
import YouTube from 'react-youtube';
import type { YouTubeProps, YouTubeEvent } from 'react-youtube';

interface AudioPlayerProps {
    currentVideoId: string | null;
    isPlaying: boolean;
    volume: number;
    seekToTime: number | null;
    onReady: (player: any) => void;
    onEnd: () => void;
    onStateChange?: (state: number) => void;
    onTimeUpdate: (time: number) => void;
    onDurationChange: (duration: number) => void;
    setIsPlaying: (playing: boolean) => void;
    setIsBuffering: (buffering: boolean) => void;
}

export default function AudioPlayer({ 
    currentVideoId, 
    isPlaying, 
    volume, 
    seekToTime,
    onReady, 
    onEnd,
    onStateChange,
    onTimeUpdate,
    onDurationChange,
    setIsPlaying,
    setIsBuffering
}: AudioPlayerProps) {
    const playerRef = useRef<any>(null);

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
        }
        // 2 = Paused, 0 = Ended
        if (playerState === 2 || playerState === 0) {
            setIsBuffering(false);
            setIsPlaying(false);
        }

        if (onStateChange) {
            onStateChange(event.data);
        }
    };

    // --- 3. PRE-WARMING CONFIGURATION ---
    const opts: YouTubeProps['opts'] = {
        height: '0', 
        width: '0',  
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
        },
    };

    return (
        <div className="custom-audio-player">
            {/* The pre-warmed invisible YouTube Engine: ALWAYS rendered, never conditionally hidden */}
            <div style={{ display: 'none', position: 'absolute', pointerEvents: 'none' }}>
                <YouTube 
                    videoId={currentVideoId || ''} 
                    opts={opts} 
                    onReady={handleReady}
                    onEnd={onEnd}
                    onStateChange={handleStateChange}
                />
            </div>
        </div>
    );
}
