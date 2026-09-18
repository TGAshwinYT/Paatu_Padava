import { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import type { Song } from '../types';
import { useAudio } from '../context/AudioContext';
import { 
  getOfflineTracks, 
  removeOfflineTrack, 
  clearAllOfflineTracks, 
  type OfflineTrackMetadata 
} from '../utils/offlineStorage';
import { 
  ArrowDownCircle, 
  Play, 
  Pause, 
  Shuffle, 
  Trash2, 
  WifiOff, 
  HardDrive, 
  CheckCircle2, 
  Music,
  Compass
} from 'lucide-react';

const DownloadedSongs = () => {
  const [offlineTracks, setOfflineTracks] = useState<OfflineTrackMetadata[]>([]);
  const { playContext, currentTrack, isPlaying, togglePlay } = useAudio();
  const navigate = useNavigate();

  const loadTracks = () => {
    const list = getOfflineTracks();
    setOfflineTracks(list);
  };

  useEffect(() => {
    loadTracks();

    const handleStorageUpdate = () => {
      loadTracks();
    };

    window.addEventListener('paatu:offline-storage-updated', handleStorageUpdate);
    return () => {
      window.removeEventListener('paatu:offline-storage-updated', handleStorageUpdate);
    };
  }, []);

  const totalBytes = useMemo(() => {
    return offlineTracks.reduce((acc, t) => acc + (t.sizeBytes || 0), 0);
  }, [offlineTracks]);

  const totalSizeFormatted = useMemo(() => {
    if (totalBytes > 0) {
      const mb = totalBytes / (1024 * 1024);
      return mb >= 1000 ? `${(mb / 1024).toFixed(2)} GB` : `${mb.toFixed(1)} MB`;
    }
    return offlineTracks.length > 0 ? `${(offlineTracks.length * 5).toFixed(1)} MB` : '0 MB';
  }, [totalBytes, offlineTracks]);

  // Convert offline metadata to playback-compatible Song format
  const songs: Song[] = useMemo(() => {
    return offlineTracks.map(t => ({
      id: t.id,
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: t.duration,
      cover_url: t.coverUrl || '/logo.png',
      coverUrl: t.coverUrl || '/logo.png',
      audioUrl: '',
      is_studio: true,
      source: 'offline'
    }));
  }, [offlineTracks]);

  const isDownloadedPlaying = isPlaying && songs.some(s => s.id === currentTrack?.id);

  const handlePlaySong = (song: Song) => {
    if (currentTrack?.id === song.id) {
      togglePlay();
    } else {
      playContext(song, songs);
    }
  };

  const handlePlayAll = () => {
    if (songs.length === 0) return;
    if (isDownloadedPlaying) {
      togglePlay();
    } else {
      playContext(songs[0], songs);
    }
  };

  const handleShufflePlay = () => {
    if (songs.length === 0) return;
    const shuffled = [...songs].sort(() => Math.random() - 0.5);
    playContext(shuffled[0], shuffled);
  };

  const handleDeleteTrack = async (songId: string, e: React.MouseEvent) => {
    e.stopPropagation();
    await removeOfflineTrack(songId);
    loadTracks();
  };

  const handleClearAll = async () => {
    if (offlineTracks.length === 0) return;
    const confirmed = window.confirm("Are you sure you want to remove all downloaded songs from offline storage?");
    if (confirmed) {
      await clearAllOfflineTracks();
      loadTracks();
    }
  };

  const formatDuration = (seconds?: number) => {
    if (!seconds || seconds <= 0) return '--:--';
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  };

  const formatDate = (timestamp?: number) => {
    if (!timestamp) return 'Recently';
    return new Date(timestamp).toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric'
    });
  };

  return (
    <div className="flex flex-col gap-8 pb-24 animate-in fade-in duration-500">
      {/* Hero Header */}
      <div className="flex flex-col md:flex-row items-center md:items-end gap-6 p-6 sm:p-8 rounded-2xl bg-gradient-to-br from-emerald-900/60 via-teal-900/40 to-neutral-900 border border-white/5 shadow-2xl relative overflow-hidden">
        <div className="absolute top-0 right-0 p-8 opacity-10 pointer-events-none">
          <ArrowDownCircle size={220} className="text-emerald-400" />
        </div>

        <div className="w-44 h-44 sm:w-52 sm:h-52 bg-gradient-to-br from-emerald-600 via-teal-600 to-emerald-800 rounded-2xl shadow-2xl flex items-center justify-center flex-shrink-0 border border-white/10 ring-2 ring-emerald-500/20">
          <ArrowDownCircle size={80} className="text-white drop-shadow-lg" />
        </div>

        <div className="flex flex-col gap-3 text-center md:text-left flex-1 min-w-0 z-10">
          <div className="flex items-center justify-center md:justify-start gap-2">
            <span className="text-xs uppercase font-extrabold tracking-widest text-emerald-300">
              Offline Storage
            </span>
            <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 flex items-center gap-1">
              <CheckCircle2 size={11} /> 320kbps MP3
            </span>
          </div>

          <h1 className="text-4xl sm:text-6xl md:text-7xl font-black text-white tracking-tight">
            Downloaded Songs
          </h1>

          <div className="flex flex-wrap items-center justify-center md:justify-start gap-2 text-sm font-semibold text-neutral-300">
            <span>{offlineTracks.length} {offlineTracks.length === 1 ? 'track' : 'tracks'}</span>
            <span className="text-neutral-500">•</span>
            <span className="flex items-center gap-1 text-emerald-400">
              <HardDrive size={14} />
              {totalSizeFormatted} cached
            </span>
            <span className="text-neutral-500">•</span>
            <span className="text-neutral-400">Zero data playback</span>
          </div>

          {/* Action Row */}
          {songs.length > 0 && (
            <div className="flex flex-wrap items-center justify-center md:justify-start gap-4 mt-2">
              <button
                onClick={handlePlayAll}
                className="w-14 h-14 bg-brand text-black rounded-full flex items-center justify-center hover:scale-105 active:scale-95 transition-all shadow-xl"
                title={isDownloadedPlaying ? "Pause Offline Playback" : "Play All Downloaded Songs"}
              >
                {isDownloadedPlaying ? (
                  <Pause size={24} fill="currentColor" />
                ) : (
                  <Play size={24} fill="currentColor" className="ml-1" />
                )}
              </button>

              <button
                onClick={handleShufflePlay}
                className="w-12 h-12 bg-neutral-800 hover:bg-neutral-700 text-neutral-200 hover:text-white rounded-full flex items-center justify-center hover:scale-105 active:scale-95 transition-all shadow-lg border border-white/5"
                title="Shuffle Downloaded Songs"
              >
                <Shuffle size={20} />
              </button>

              <button
                onClick={handleClearAll}
                className="text-xs font-semibold text-neutral-400 hover:text-red-400 transition-colors px-3 py-2 rounded-lg hover:bg-red-500/10 border border-transparent hover:border-red-500/20 ml-auto"
                title="Clear all downloaded songs from offline storage"
              >
                Clear All Downloads
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Offline Status Notice Banner */}
      <div className="p-4 rounded-xl bg-emerald-500/10 border border-emerald-500/20 flex items-center gap-3">
        <div className="p-2 rounded-lg bg-emerald-500/20 text-emerald-400 flex-shrink-0">
          <WifiOff size={20} />
        </div>
        <div className="flex-1 text-sm">
          <span className="font-bold text-emerald-300">Offline Listening Ready: </span>
          <span className="text-neutral-300">
            All songs listed below are saved in your browser's persistent cache. You can play them anytime without an active internet connection.
          </span>
        </div>
      </div>

      {/* Track List */}
      {songs.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 px-4 text-center rounded-2xl border border-white/5 bg-neutral-900/40">
          <div className="w-20 h-20 rounded-full bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center mb-6 text-emerald-400">
            <ArrowDownCircle size={40} />
          </div>
          <h3 className="text-2xl font-black text-white mb-2">No downloaded songs yet</h3>
          <p className="text-neutral-400 text-sm max-w-md mb-8">
            Click the download icon on any song, album, or current playing bar to store high quality 320kbps MP3 tracks for offline playback.
          </p>
          <button
            onClick={() => navigate('/')}
            className="flex items-center gap-2 px-8 py-3 bg-brand text-black font-bold rounded-full hover:scale-105 active:scale-95 transition-all shadow-lg"
          >
            <Compass size={18} />
            Explore Music
          </button>
        </div>
      ) : (
        <div className="flex flex-col divide-y divide-white/5">
          {/* Table Header */}
          <div className="grid grid-cols-[auto_1fr_auto] md:grid-cols-[auto_2fr_1fr_1fr_auto] gap-4 px-4 py-3 text-xs font-bold uppercase tracking-wider text-neutral-400 border-b border-white/10">
            <span className="w-8 text-center">#</span>
            <span>Title</span>
            <span className="hidden md:block">Album</span>
            <span className="hidden md:block">Downloaded</span>
            <span className="text-right pr-2">Actions</span>
          </div>

          {/* Table Rows */}
          {offlineTracks.map((track, idx) => {
            const isThisPlaying = currentTrack?.id === track.id && isPlaying;
            const songItem = songs[idx];
            const sizeMb = track.sizeBytes 
              ? `${(track.sizeBytes / (1024 * 1024)).toFixed(1)} MB` 
              : '320kbps';

            return (
              <div
                key={track.id}
                onClick={() => handlePlaySong(songItem)}
                className={`group grid grid-cols-[auto_1fr_auto] md:grid-cols-[auto_2fr_1fr_1fr_auto] gap-4 px-4 py-3 items-center rounded-lg transition-all cursor-pointer ${
                  isThisPlaying 
                    ? 'bg-emerald-500/10 text-emerald-400' 
                    : 'hover:bg-white/5 text-neutral-300 hover:text-white'
                }`}
              >
                {/* Number or Play/Pause Icon */}
                <div className="w-8 flex items-center justify-center font-bold text-sm text-neutral-500">
                  {isThisPlaying ? (
                    <Pause size={16} className="text-emerald-400 fill-current animate-pulse" />
                  ) : (
                    <>
                      <span className="group-hover:hidden">{idx + 1}</span>
                      <Play size={16} className="hidden group-hover:block text-white fill-current ml-0.5" />
                    </>
                  )}
                </div>

                {/* Cover, Title & Artist */}
                <div className="flex items-center gap-3 min-w-0">
                  <div className="w-11 h-11 rounded-lg overflow-hidden bg-neutral-800 flex-shrink-0 shadow-md border border-white/5 relative">
                    {track.coverUrl ? (
                      <img 
                        src={track.coverUrl} 
                        alt={track.title} 
                        className="w-full h-full object-cover" 
                        onError={(e) => { e.currentTarget.style.display = 'none'; }}
                      />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center bg-neutral-800 text-neutral-500">
                        <Music size={20} />
                      </div>
                    )}
                    <span className="absolute bottom-0 right-0 bg-emerald-500 text-black text-[9px] font-black px-1 rounded-tl">
                      OFF
                    </span>
                  </div>
                  <div className="flex flex-col min-w-0">
                    <p className={`text-sm font-bold truncate ${isThisPlaying ? 'text-emerald-400' : 'text-white'}`}>
                      {track.title}
                    </p>
                    <p className="text-xs text-neutral-400 truncate">
                      {track.artist}
                    </p>
                  </div>
                </div>

                {/* Album */}
                <div className="hidden md:flex items-center text-xs text-neutral-400 truncate">
                  {track.album || '—'}
                </div>

                {/* Download Date & Size */}
                <div className="hidden md:flex flex-col text-xs text-neutral-400">
                  <span>{formatDate(track.downloadedAt)}</span>
                  <span className="text-[10px] text-emerald-400 font-semibold">{sizeMb}</span>
                </div>

                {/* Actions */}
                <div className="flex items-center justify-end gap-3 text-xs">
                  <span className="hidden sm:inline-block font-mono text-neutral-400">
                    {formatDuration(track.duration)}
                  </span>
                  <button
                    onClick={(e) => handleDeleteTrack(track.id, e)}
                    className="p-2 rounded-full text-neutral-500 hover:text-red-400 hover:bg-red-500/10 transition-colors opacity-0 group-hover:opacity-100 focus:opacity-100"
                    title="Delete downloaded song"
                  >
                    <Trash2 size={16} />
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default DownloadedSongs;
