import React, { useState, useEffect, useRef } from 'react';
import axios from 'axios';
import { Terminal, RefreshCcw, Trash2, ExternalLink } from 'lucide-react';

const DeveloperLogs: React.FC = () => {
    const [logs, setLogs] = useState<string[]>([]);
    const [isAutoRefresh, setIsAutoRefresh] = useState(true);
    const [lastUpdated, setLastUpdated] = useState<Date>(new Date());
    const [status, setStatus] = useState<'connected' | 'error' | 'connecting'>('connecting');
    const scrollRef = useRef<HTMLDivElement>(null);

    const PROXY_URL = import.meta.env.VITE_STREAM_API_URL || 'http://localhost:8001';

    const fetchLogs = async () => {
        try {
            const response = await axios.get(`${PROXY_URL}/api/logs`);
            setLogs(response.data);
            setLastUpdated(new Date());
            setStatus('connected');
        } catch (err) {
            console.error("Failed to fetch logs:", err);
            setStatus('error');
        }
    };

    useEffect(() => {
        fetchLogs();
        let interval: any;
        if (isAutoRefresh) {
            interval = setInterval(fetchLogs, 3000);
        }
        return () => clearInterval(interval);
    }, [isAutoRefresh]);

    useEffect(() => {
        if (scrollRef.current && isAutoRefresh) {
            scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
        }
    }, [logs]);

    return (
        <div className="flex flex-col h-[calc(100vh-120px)] bg-black/40 rounded-2xl overflow-hidden border border-white/5 backdrop-blur-xl">
            {/* Header */}
            <div className="flex items-center justify-between p-4 bg-white/5 border-b border-white/5">
                <div className="flex items-center gap-3">
                    <div className="p-2 bg-neutral-800 rounded-lg">
                        <Terminal className="w-5 h-5 text-neutral-400" />
                    </div>
                    <div>
                        <h1 className="text-lg font-bold text-white leading-tight">Bouncer Stream Logs</h1>
                        <p className="text-xs text-neutral-500 font-medium tracking-wide flex items-center gap-1.5 uppercase">
                            <span className={`w-1.5 h-1.5 rounded-full ${status === 'connected' ? 'bg-green-500' : 'bg-red-500'} animate-pulse`} />
                            {status} • {PROXY_URL}
                        </p>
                    </div>
                </div>

                <div className="flex items-center gap-2">
                    <button 
                        onClick={() => setIsAutoRefresh(!isAutoRefresh)}
                        className={`flex items-center gap-2 px-3 py-1.5 rounded-full text-xs font-bold transition-all ${isAutoRefresh ? 'bg-white text-black' : 'bg-white/5 text-white hover:bg-white/10'}`}
                    >
                        <RefreshCcw className={`w-3.5 h-3.5 ${isAutoRefresh ? 'animate-spin-slow' : ''}`} />
                        {isAutoRefresh ? 'Auto-Sync ON' : 'Sync Paused'}
                    </button>
                    <button 
                        onClick={() => setLogs([])}
                        className="p-1.5 hover:bg-red-500/10 hover:text-red-500 text-neutral-500 rounded-lg transition-colors"
                        title="Clear local view"
                    >
                        <Trash2 className="w-4 h-4" />
                    </button>
                </div>
            </div>

            {/* Terminal View */}
            <div 
                ref={scrollRef}
                className="flex-1 p-4 font-mono text-sm overflow-y-auto space-y-1 selection:bg-white/20"
            >
                {logs.length === 0 ? (
                    <div className="h-full flex flex-col items-center justify-center opacity-30">
                        <Terminal className="w-12 h-12 mb-4" />
                        <p>No log data received from the bridge.</p>
                    </div>
                ) : (
                    logs.map((log, i) => {
                        const isError = log.includes('ERROR') || log.includes('Failed');
                        const isSuccess = log.includes('Success') || log.includes('✅');
                        
                        return (
                            <div key={i} className={`flex gap-3 leading-relaxed transition-colors border-l-2 pl-3 ${isError ? 'border-red-500/50 text-red-400 bg-red-500/5' : isSuccess ? 'border-green-500/50 text-green-400 bg-green-500/5' : 'border-transparent text-neutral-300 hover:bg-white/5'}`}>
                                <span className="opacity-20 shrink-0 select-none">{(i + 1).toString().padStart(3, '0')}</span>
                                <span className="break-all">{log}</span>
                            </div>
                        );
                    })
                )}
            </div>

            {/* Footer Status */}
            <div className="px-4 py-2 bg-neutral-900 border-t border-white/5 flex items-center justify-between text-[10px] text-neutral-600 font-bold uppercase tracking-widest">
                <div className="flex items-center gap-4">
                    <span>Buffer: {logs.length}/100</span>
                    <span>Last Update: {lastUpdated.toLocaleTimeString()}</span>
                </div>
                <div className="flex items-center gap-4">
                    <a 
                        href={`${PROXY_URL}/api/logs`} 
                        target="_blank" 
                        rel="noreferrer"
                        className="flex items-center gap-1 hover:text-white transition-colors"
                    >
                        Raw JSON <ExternalLink className="w-2.5 h-2.5" />
                    </a>
                </div>
            </div>
        </div>
    );
};

export default DeveloperLogs;
