import React, { useState, useEffect } from 'react';
import { ArrowDownTrayIcon, ArrowUpOnSquareIcon } from '@heroicons/react/24/outline';

const InstallPWA: React.FC = () => {
    const [isIOS, setIsIOS] = useState(false);
    const [isStandalone, setIsStandalone] = useState(false);
    const [deferredPrompt, setDeferredPrompt] = useState<any>(null);
    const [isInstallable, setIsInstallable] = useState(false);

    useEffect(() => {
        // Detect iOS
        const userAgent = window.navigator.userAgent.toLowerCase();
        const isIosDevice = /iphone|ipad|ipod/.test(userAgent);
        setIsIOS(isIosDevice);

        // Detect if already installed (Standalone mode)
        const isAppInstalled = window.matchMedia('(display-mode: standalone)').matches || ('standalone' in window.navigator && (window.navigator as any).standalone);
        setIsStandalone(isAppInstalled);

        const handleBeforeInstallPrompt = (e: Event) => {
            // Prevent Chrome 67 and earlier from automatically showing the prompt
            e.preventDefault();
            // Stash the event so it can be triggered later.
            setDeferredPrompt(e);
            setIsInstallable(true);
        };

        window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt);

        // Cleanup listener
        return () => {
            window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
        };
    }, []);

    const handleInstallClick = async () => {
        if (!deferredPrompt) return;

        // Show the install prompt
        deferredPrompt.prompt();

        // Wait for the user to respond to the prompt
        const { outcome } = await deferredPrompt.userChoice;
        console.log(`User response to the install prompt: ${outcome}`);

        // We've used the prompt, and can't use it again, so clear it
        setDeferredPrompt(null);
        setIsInstallable(false);
    };

    // Hide completely if already running as an installed native app
    if (isStandalone) return null;

    return (
        <div className="mt-4 w-full">
            {/* Show 1-Click Install for Android/Desktop */}
            {isInstallable && (
                <button 
                    onClick={handleInstallClick}
                    className="flex items-center justify-center gap-2 w-full px-4 py-3 bg-green-500 text-black font-bold rounded-xl hover:bg-green-400 transition shadow-lg active:scale-95"
                >
                    <ArrowDownTrayIcon className="w-5 h-5" strokeWidth={2.5} />
                    Install App
                </button>
            )}

            {/* Show Manual Instructions for iOS */}
            {isIOS && !isInstallable && (
                <div className="bg-[#282828] text-gray-300 text-sm p-4 rounded-xl flex items-center gap-3 border border-white/5 animate-in fade-in slide-in-from-bottom-2 duration-500">
                    <div className="bg-white/10 p-2 rounded-lg">
                        <ArrowUpOnSquareIcon className="w-6 h-6 text-white" />
                    </div>
                    <p className="leading-tight">
                        To install the app, tap the <span className="text-white font-bold">Share</span> icon below and select <span className="text-white font-bold">"Add to Home Screen"</span>.
                    </p>
                </div>
            )}
        </div>
    );
};

export default InstallPWA;
