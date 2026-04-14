import React, { useRef, useState, useEffect } from 'react';
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
}

export default function AudioPlayer({ 
    currentVideoId, 
    isPlaying, 
    volume, 
    seekToTime,
    onReady, 
    onEnd,
    onStateChange
}: AudioPlayerProps) {
    const playerRef = useRef<any>(null);

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

    const opts: YouTubeProps['opts'] = {
        height: '0',
        width: '0',
        playerVars: {
            autoplay: 1,
            controls: 0,
            disablekb: 1,
            fs: 0,
            playsinline: 1,
            modestbranding: 1,
            rel: 0,
            origin: window.location.origin,
            enablejsapi: 1,
        },
    };

    return (
        <div className="hidden" aria-hidden="true">
            {currentVideoId && (
                <YouTube 
                    videoId={currentVideoId} 
                    opts={opts} 
                    onReady={handleReady}
                    onEnd={onEnd}
                    onStateChange={handleStateChange}
                />
            )}
        </div>
    );
}
