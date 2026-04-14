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
    onDurationChange
}: AudioPlayerProps) {
    const playerRef = useRef<any>(null);

    // --- 1. SYNC ENGINE (POLLING) ---
    // YouTube doesn't automatically push time updates to React. 
    // We poll it using a useEffect when the song is playing.
    useEffect(() => {
        let interval: any;
        // Only run the timer if the song is actively playing
        if (isPlaying && playerRef.current) {
            interval = setInterval(async () => {
                try {
                    // Fetch the current time from the hidden YouTube player
                    const time = await playerRef.current.getCurrentTime();
                    onTimeUpdate(time);
                    
                    // Grab the total duration of the song if we haven't yet
                    const songDuration = await playerRef.current.getDuration();
                    if (songDuration > 0) {
                        onDurationChange(songDuration);
                    }
                } catch (e) {
                    // Silently ignore temporary glitches during track changes
                }
            }, 1000); // Update every 1 second
        }
        return () => clearInterval(interval);
    }, [isPlaying, currentVideoId, onTimeUpdate, onDurationChange]);

    // --- 2. INTERACTION HANDLERS ---
    
    // Sync play/pause state
    useEffect(() => {
        if (!playerRef.current) return;
        if (isPlaying) {
            playerRef.current.playVideo();
        } else {
            playerRef.current.pauseVideo();
        }
    }, [isPlaying, currentVideoId]);

    // Sync volume (YouTube is 0-100, our context is 0-1)
    useEffect(() => {
        if (!playerRef.current) return;
        playerRef.current.setVolume(volume * 100);
    }, [volume]);

    // Handle manual seeks from Context
    useEffect(() => {
        if (!playerRef.current || seekToTime === null) return;
        playerRef.current.seekTo(seekToTime, true);
    }, [seekToTime]);

    const handleReady = (event: YouTubeEvent) => {
        playerRef.current = event.target;
        playerRef.current.setVolume(volume * 100);
        onReady(event.target);
    };

    const handleStateChange = (event: YouTubeEvent) => {
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
