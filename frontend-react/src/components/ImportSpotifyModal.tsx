import React, { useState } from 'react';
import { X, CheckCircle2, AlertCircle, Loader2, ArrowRight, Music } from 'lucide-react';
import { previewSpotifyPlaylist, importSpotifyPlaylist, type SpotifyPlaylistPreview } from '../services/api';
import { useAudio } from '../context/AudioContext';
import { useNavigate } from 'react-router-dom';

interface ImportSpotifyModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const ImportSpotifyModal: React.FC<ImportSpotifyModalProps> = ({ isOpen, onClose }) => {
  const navigate = useNavigate();
  const { refreshPlaylists } = useAudio();
  const [spotifyUrl, setSpotifyUrl] = useState('');
  const [customTitle, setCustomTitle] = useState('');
  const [preview, setPreview] = useState<SpotifyPlaylistPreview | null>(null);
  
  const [isLoadingPreview, setIsLoadingPreview] = useState(false);
  const [isImporting, setIsImporting] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [successPlaylistId, setSuccessPlaylistId] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleFetchPreview = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    const trimmed = spotifyUrl.trim();
    if (!trimmed) {
      setErrorMsg('Please paste a valid Spotify playlist link.');
      return;
    }

    setErrorMsg('');
    setIsLoadingPreview(true);
    setPreview(null);
    setSuccessPlaylistId(null);

    try {
      const data = await previewSpotifyPlaylist(trimmed);
      setPreview(data);
      setCustomTitle(data.title);
    } catch (err: any) {
      console.error('Spotify preview error:', err);
      setErrorMsg(err.response?.data?.detail || 'Could not load Spotify playlist. Ensure the playlist is public.');
    } finally {
      setIsLoadingPreview(false);
    }
  };

  const handleImport = async () => {
    if (!spotifyUrl.trim()) return;

    setErrorMsg('');
    setIsImporting(true);

    try {
      const result = await importSpotifyPlaylist(spotifyUrl.trim(), customTitle.trim() || undefined);
      if (result.success) {
        setSuccessPlaylistId(result.playlist_id);
        await refreshPlaylists();
        window.dispatchEvent(new Event('playlists-updated'));
      } else {
        setErrorMsg('Import was completed but no tracks could be matched.');
      }
    } catch (err: any) {
      console.error('Spotify import error:', err);
      setErrorMsg(err.response?.data?.detail || 'Failed to import playlist. Please try again.');
    } finally {
      setIsImporting(false);
    }
  };

  const handleReset = () => {
    setSpotifyUrl('');
    setCustomTitle('');
    setPreview(null);
    setErrorMsg('');
    setSuccessPlaylistId(null);
    onClose();
  };

  const handleViewPlaylist = () => {
    if (successPlaylistId) {
      handleReset();
      navigate(`/playlist/${successPlaylistId}`);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm p-4 animate-in fade-in duration-200">
      <div 
        className="bg-neutral-900 border border-neutral-800 rounded-2xl w-full max-w-lg overflow-hidden shadow-2xl flex flex-col max-h-[90vh]"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-neutral-800/80 bg-neutral-900/50">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-full bg-[#1DB954] flex items-center justify-center shadow-lg shadow-[#1DB954]/20">
              <svg className="w-5 h-5 text-black fill-current" viewBox="0 0 24 24">
                <path d="M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm5.502 17.31c-.22.36-.68.472-1.04.252-2.85-1.742-6.438-2.137-10.665-1.17-.412.094-.816-.168-.91-.58-.094-.412.168-.816.58-.91 4.63-1.057 8.59-.61 11.783 1.34.36.22.472.68.252 1.068zm1.47-3.268c-.276.45-.86.59-1.31.314-3.264-2.007-8.24-2.59-12.1-1.417-.506.154-1.043-.136-1.197-.642-.154-.506.136-1.043.642-1.197 4.414-1.34 9.897-.69 13.65 1.62.45.276.59.86.315 1.322zm.126-3.41c-3.916-2.325-10.37-2.54-14.1-1.398-.6.183-1.237-.16-1.42-.76-.183-.6.16-1.237.76-1.42 4.29-1.302 11.41-1.05 15.89 1.61.54.32.72 1.02.4 1.56-.32.54-1.02.72-1.53.408z"/>
              </svg>
            </div>
            <div>
              <h3 className="font-bold text-lg text-white">Import Spotify Playlist</h3>
              <p className="text-xs text-neutral-400">Transfer any public Spotify playlist to Paatu Padava</p>
            </div>
          </div>
          <button 
            onClick={handleReset} 
            className="text-neutral-400 hover:text-white p-1 rounded-lg hover:bg-neutral-800 transition-colors"
          >
            <X size={20} />
          </button>
        </div>

        {/* Modal Body */}
        <div className="p-6 overflow-y-auto space-y-5">
          {/* Success View */}
          {successPlaylistId ? (
            <div className="flex flex-col items-center justify-center py-6 text-center space-y-4">
              <div className="w-16 h-16 rounded-full bg-emerald-500/20 text-emerald-400 flex items-center justify-center animate-in zoom-in-50 duration-300">
                <CheckCircle2 size={36} />
              </div>
              <div>
                <h4 className="text-xl font-bold text-white">Playlist Successfully Imported!</h4>
                <p className="text-sm text-neutral-400 mt-1 max-w-sm">
                  "{customTitle || preview?.title}" is now ready with direct 320kbps audio in your library.
                </p>
              </div>

              <div className="flex gap-3 pt-4 w-full">
                <button
                  onClick={handleViewPlaylist}
                  className="flex-1 bg-[#1DB954] hover:bg-[#1ed760] text-black font-semibold py-3 px-6 rounded-xl flex items-center justify-center gap-2 transition-all shadow-lg shadow-[#1DB954]/25"
                >
                  <span>Open Playlist</span>
                  <ArrowRight size={18} />
                </button>
                <button
                  onClick={handleReset}
                  className="bg-neutral-800 hover:bg-neutral-700 text-white font-medium py-3 px-5 rounded-xl transition-colors"
                >
                  Done
                </button>
              </div>
            </div>
          ) : (
            <>
              {/* URL Input Form */}
              <form onSubmit={handleFetchPreview} className="space-y-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-neutral-400">
                  Spotify Playlist Link
                </label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    value={spotifyUrl}
                    onChange={(e) => setSpotifyUrl(e.target.value)}
                    placeholder="https://open.spotify.com/playlist/..."
                    disabled={isLoadingPreview || isImporting}
                    className="flex-1 bg-neutral-950 border border-neutral-800 rounded-xl px-4 py-3 text-sm text-white placeholder-neutral-500 focus:outline-none focus:border-[#1DB954] transition-colors"
                  />
                  <button
                    type="submit"
                    disabled={isLoadingPreview || isImporting || !spotifyUrl.trim()}
                    className="bg-neutral-800 hover:bg-neutral-700 disabled:opacity-50 text-white font-medium px-4 py-3 rounded-xl flex items-center gap-2 text-sm transition-colors flex-shrink-0"
                  >
                    {isLoadingPreview ? (
                      <Loader2 size={18} className="animate-spin text-[#1DB954]" />
                    ) : (
                      <span>Fetch</span>
                    )}
                  </button>
                </div>
              </form>

              {/* Error Banner */}
              {errorMsg && (
                <div className="bg-red-500/10 border border-red-500/20 text-red-400 p-3 rounded-xl flex items-start gap-2 text-xs">
                  <AlertCircle size={16} className="flex-shrink-0 mt-0.5" />
                  <span>{errorMsg}</span>
                </div>
              )}

              {/* Preview Card */}
              {preview && (
                <div className="bg-neutral-950/60 border border-neutral-800/80 rounded-xl p-4 space-y-4 animate-in fade-in duration-300">
                  <div className="flex gap-4 items-center">
                    <div className="w-20 h-20 rounded-lg overflow-hidden bg-neutral-800 flex-shrink-0 shadow-md">
                      {preview.cover_url ? (
                        <img 
                          src={preview.cover_url} 
                          alt={preview.title}
                          className="w-full h-full object-cover"
                        />
                      ) : (
                        <div className="w-full h-full flex items-center justify-center text-neutral-600">
                          <Music size={28} />
                        </div>
                      )}
                    </div>

                    <div className="flex-1 min-w-0 space-y-1">
                      <div className="flex items-center gap-2">
                        <span className="text-[10px] uppercase font-bold text-black bg-[#1DB954] px-2 py-0.5 rounded-full">
                          Spotify
                        </span>
                        <span className="text-xs text-neutral-400">
                          {preview.total_tracks} tracks found
                        </span>
                      </div>
                      <input
                        type="text"
                        value={customTitle}
                        onChange={(e) => setCustomTitle(e.target.value)}
                        placeholder="Playlist Title"
                        className="w-full bg-transparent border-b border-neutral-700 focus:border-[#1DB954] text-white font-bold text-base pb-0.5 focus:outline-none"
                      />
                      {preview.description && (
                        <p className="text-xs text-neutral-400 truncate">{preview.description}</p>
                      )}
                    </div>
                  </div>

                  {/* Sample Tracks */}
                  {preview.sample_tracks && preview.sample_tracks.length > 0 && (
                    <div className="space-y-2 pt-2 border-t border-neutral-800/60">
                      <div className="text-xs font-semibold text-neutral-400 uppercase tracking-wider">
                        Sample Preview
                      </div>
                      <div className="space-y-1.5 max-h-36 overflow-y-auto pr-1">
                        {preview.sample_tracks.map((t, idx) => (
                          <div key={idx} className="flex items-center justify-between text-xs py-1 px-2 rounded-md hover:bg-neutral-900/60 text-neutral-300">
                            <div className="truncate flex-1 mr-2">
                              <span className="text-white font-medium">{t.title}</span>
                              <span className="text-neutral-500 ml-1.5">• {t.artist}</span>
                            </div>
                            {t.duration > 0 && (
                              <span className="text-[11px] text-neutral-500 tabular-nums">
                                {Math.floor(t.duration / 60)}:{(t.duration % 60).toString().padStart(2, '0')}
                              </span>
                            )}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Import Button */}
                  <button
                    onClick={handleImport}
                    disabled={isImporting}
                    className="w-full bg-[#1DB954] hover:bg-[#1ed760] disabled:opacity-50 text-black font-bold py-3 px-4 rounded-xl flex items-center justify-center gap-2 transition-all shadow-lg shadow-[#1DB954]/20"
                  >
                    {isImporting ? (
                      <>
                        <Loader2 size={18} className="animate-spin text-black" />
                        <span>Matching & Importing ({preview.total_tracks} tracks)...</span>
                      </>
                    ) : (
                      <>
                        <span>Import {preview.total_tracks} Songs to Library</span>
                        <ArrowRight size={18} />
                      </>
                    )}
                  </button>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export default ImportSpotifyModal;
