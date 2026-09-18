import React, { useState, useRef, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import { useAudio } from '../context/AudioContext';
import { useNavigate } from 'react-router-dom';
import { LogOut, Trash2, ShieldAlert, User as UserIcon, Download, Upload, CheckCircle2, AlertCircle, Sparkles, Globe, Music, HardDrive, Radio } from 'lucide-react';
import api, { updatePreferredLanguages } from '../services/api';
import { getOfflineStorageStats, clearAllOfflineTracks } from '../utils/offlineStorage';
import InstallPWA from '../components/InstallPWA';

const AVAILABLE_LANGUAGES = [
  { id: 'tamil', label: 'தமிழ் (Tamil)' },
  { id: 'english', label: 'English' },
  { id: 'hindi', label: 'हिन्दी (Hindi)' },
  { id: 'telugu', label: 'తెలుగు (Telugu)' },
  { id: 'malayalam', label: 'മലയാളം (Malayalam)' },
  { id: 'kannada', label: 'ಕನ್ನಡ (Kannada)' },
  { id: 'punjabi', label: 'ਪੰਜਾਬੀ (Punjabi)' },
  { id: 'marathi', label: 'मराठी (Marathi)' },
  { id: 'bengali', label: 'বাংলা (Bengali)' },
];

const Settings = () => {
  const { user, logout } = useAuth();
  const { crossfadeDuration, setCrossfadeDuration, isAutoplay, toggleAutoplay } = useAudio();
  const navigate = useNavigate();
  const fileInputRef = useRef<HTMLInputElement>(null);
  
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [isExporting, setIsExporting] = useState(false);
  const [isImporting, setIsImporting] = useState(false);
  const [statusMessage, setStatusMessage] = useState<{type: 'success' | 'error', text: string} | null>(null);
  const [error, setError] = useState('');
  const [offlineStats, setOfflineStats] = useState<{ count: number; formattedSize: string }>({ count: 0, formattedSize: '0 MB' });
  const [isClearingOffline, setIsClearingOffline] = useState(false);

  useEffect(() => {
    getOfflineStorageStats().then(stats => setOfflineStats({ count: stats.count, formattedSize: stats.formattedSize }));
    const handleUpdate = () => {
      getOfflineStorageStats().then(stats => setOfflineStats({ count: stats.count, formattedSize: stats.formattedSize }));
    };
    window.addEventListener('paatu:offline-storage-updated', handleUpdate);
    return () => window.removeEventListener('paatu:offline-storage-updated', handleUpdate);
  }, []);

  const [selectedLanguages, setSelectedLanguages] = useState<string[]>(() => {
    if (user?.preferredLanguages && Array.isArray(user.preferredLanguages) && user.preferredLanguages.length > 0) {
      return user.preferredLanguages.map((l: string) => l.toLowerCase());
    }
    return ['tamil', 'english', 'hindi'];
  });
  const [isSavingLanguages, setIsSavingLanguages] = useState(false);
  const [langSavedMessage, setLangSavedMessage] = useState('');

  const handleToggleLanguage = async (langId: string) => {
    let updated: string[];
    if (selectedLanguages.includes(langId)) {
      if (selectedLanguages.length === 1) {
        return; // Keep at least one language
      }
      updated = selectedLanguages.filter(l => l !== langId);
    } else {
      updated = [...selectedLanguages, langId];
    }
    setSelectedLanguages(updated);
    setIsSavingLanguages(true);
    try {
      const ok = await updatePreferredLanguages(updated);
      if (ok) {
        setLangSavedMessage('Preferences saved!');
        setTimeout(() => setLangSavedMessage(''), 3000);
      }
    } finally {
      setIsSavingLanguages(false);
    }
  };

  const handleLogout = async () => {
    await logout();
    navigate('/login');
  };

  const handleDeleteAccount = async () => {
    setIsDeleting(true);
    setError('');
    try {
      await api.delete('/api/users/me'); 
      logout();
      navigate('/signup');
    } catch (err: any) {
      setError(err.response?.data?.detail || 'Failed to delete account. Please try again.');
      setIsDeleting(false);
      setShowDeleteModal(false);
    }
  };

  const handleExportData = async () => {
    setIsExporting(true);
    setStatusMessage(null);
    try {
      const response = await api.get('/api/users/export');
      const dataStr = JSON.stringify(response.data, null, 2);
      const dataUri = 'data:application/json;charset=utf-8,' + encodeURIComponent(dataStr);
      
      const exportFileDefaultName = `paaatu_padava_data_${user?.username}.json`;
      
      const linkElement = document.createElement('a');
      linkElement.setAttribute('href', dataUri);
      linkElement.setAttribute('download', exportFileDefaultName);
      linkElement.click();
      
      setStatusMessage({type: 'success', text: 'Data exported successfully!'});
    } catch (err: any) {
      setStatusMessage({type: 'error', text: 'Failed to export data.'});
    } finally {
      setIsExporting(false);
    }
  };

  const handleImportClick = () => {
    fileInputRef.current?.click();
  };

  const handleFileChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    setIsImporting(true);
    setStatusMessage(null);
    const formData = new FormData();
    formData.append('file', file);

    try {
      const response = await api.post('/api/users/import', formData, {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      });
      setStatusMessage({type: 'success', text: response.data.message});
    } catch (err: any) {
      setStatusMessage({type: 'error', text: err.response?.data?.detail || 'Failed to import data.'});
    } finally {
      setIsImporting(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  if (!user) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[60vh] text-center">
        <h2 className="text-2xl font-bold mb-4 text-white">Please sign in to view settings</h2>
        <button 
          onClick={() => navigate('/login')}
          className="bg-brand hover:bg-brand-hover text-black font-bold px-8 py-3 rounded-full hover:scale-105 active:scale-95 transition-all shadow-lg"
        >
          Go to Login
        </button>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto py-8 px-4">
      <h1 className="text-3xl font-bold mb-8 text-white">Account Settings</h1>

      {statusMessage && (
        <div className={`mb-6 p-4 rounded-xl flex items-center gap-3 border ${
          statusMessage.type === 'success' ? 'bg-green-500/10 border-green-500/20 text-green-500' : 'bg-red-500/10 border-red-500/20 text-red-500'
        }`}>
          {statusMessage.type === 'success' ? <CheckCircle2 size={20} /> : <AlertCircle size={20} />}
          <span className="text-sm font-medium">{statusMessage.text}</span>
        </div>
      )}

      <input 
        type="file" 
        ref={fileInputRef} 
        onChange={handleFileChange} 
        accept=".json" 
        className="hidden" 
      />

      <div className="space-y-6">
        {/* Profile Section */}
        <section className="bg-surface-card p-6 rounded-xl border border-white/5">
          <h2 className="text-xl font-semibold mb-4 flex items-center gap-2 text-white">
            <UserIcon size={20} className="text-brand" />
            Profile Information
          </h2>
          <div className="space-y-4">
            <div className="flex flex-col">
              <label className="text-xs text-muted uppercase font-bold mb-1">Username</label>
              <div className="text-neutral-200 bg-surface p-3 rounded-lg border border-white/5">
                {user.username}
              </div>
            </div>
            
            <button 
              onClick={() => navigate('/onboarding')}
              className="w-full flex items-center justify-center gap-2 bg-surface hover:bg-surface-hover text-white p-3 rounded-lg font-bold transition-all border border-white/10 mt-4 group"
            >
              <Sparkles size={18} className="text-brand group-hover:scale-110 transition-transform" />
              Update Music Preferences
            </button>
          </div>
        </section>

        {/* Music Languages Section */}
        <section className="bg-surface-card p-6 rounded-xl border border-white/5">
          <div className="flex items-center justify-between mb-2">
            <h2 className="text-xl font-semibold flex items-center gap-2 text-white">
              <Globe size={20} className="text-brand" />
              Preferred Music Languages
            </h2>
            {langSavedMessage && (
              <span className="text-xs text-brand font-semibold flex items-center gap-1 bg-brand/10 px-2.5 py-1 rounded-full border border-brand/20">
                <CheckCircle2 size={14} /> {langSavedMessage}
              </span>
            )}
          </div>
          <p className="text-sm text-muted mb-5 leading-relaxed">
            Select the languages you listen to. We use this to rank your personalized mixes and search results (defaults to Tamil-first).
          </p>

          <div className="flex flex-wrap gap-2.5">
            {AVAILABLE_LANGUAGES.map((lang) => {
              const isSelected = selectedLanguages.includes(lang.id);
              return (
                <button
                  key={lang.id}
                  onClick={() => handleToggleLanguage(lang.id)}
                  disabled={isSavingLanguages}
                  className={`px-4 py-2 rounded-full text-sm font-semibold transition-all duration-200 border ${
                    isSelected
                      ? 'bg-brand text-black border-brand/40 shadow-[0_0_15px_rgba(30,215,96,0.25)] scale-[1.02]'
                      : 'bg-surface text-neutral-300 border-white/5 hover:border-white/20 hover:text-white'
                  }`}
                >
                  {lang.label}
                </button>
              );
            })}
          </div>
        </section>

        {/* Playback Section */}
        <section className="bg-surface-card p-6 rounded-xl border border-white/5">
          <h2 className="text-xl font-semibold mb-2 flex items-center gap-2 text-white">
            <Music size={20} className="text-brand" />
            Playback
          </h2>
          <p className="text-sm text-muted mb-5 leading-relaxed">
            Adjust how tracks transition and sound.
          </p>

          <div className="space-y-4">
            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="text-sm font-semibold text-white">Crossfade Duration</label>
                <span className="text-sm font-mono font-bold text-brand bg-brand/10 px-2.5 py-0.5 rounded-full border border-brand/20">
                  {crossfadeDuration === 0 ? 'Off' : `${crossfadeDuration}s`}
                </span>
              </div>
              <p className="text-xs text-muted mb-3">
                Smoothly blend the end of one song into the beginning of the next. Only applies to native audio streams.
              </p>
              <input
                type="range"
                min={0}
                max={12}
                step={1}
                value={crossfadeDuration}
                onChange={(e) => setCrossfadeDuration(Number(e.target.value))}
                className="w-full h-1.5 bg-neutral-700 rounded-full appearance-none cursor-pointer accent-brand"
                style={{
                  backgroundImage: `linear-gradient(to right, var(--color-brand) ${(crossfadeDuration / 12) * 100}%, #404040 0%)`
                }}
              />
              <div className="flex justify-between mt-1">
                <span className="text-[10px] text-neutral-600">Off</span>
                <span className="text-[10px] text-neutral-600">6s</span>
                <span className="text-[10px] text-neutral-600">12s</span>
              </div>
            </div>

            {/* Infinite Autoplay */}
            <div className="pt-4 border-t border-white/5 flex items-center justify-between">
              <div className="max-w-[80%]">
                <label className="text-sm font-semibold text-white flex items-center gap-2">
                  <Radio size={16} className="text-brand" />
                  Infinite Autoplay (Song Radio)
                </label>
                <p className="text-xs text-muted mt-1 leading-relaxed">
                  Keep listening to similar songs automatically when your current queue or album reaches the end.
                </p>
              </div>
              <button
                type="button"
                onClick={toggleAutoplay}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors duration-200 focus:outline-none flex-shrink-0 ${
                  isAutoplay ? 'bg-brand' : 'bg-neutral-700'
                }`}
                title={isAutoplay ? 'Autoplay is ON' : 'Autoplay is OFF'}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition duration-200 ease-in-out ${
                    isAutoplay ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>
          </div>
        </section>

        {/* Offline Storage & Downloads Section */}
        <section className="bg-surface-card p-6 rounded-xl border border-white/5 text-white">
          <h2 className="text-xl font-semibold mb-2 flex items-center gap-2">
            <HardDrive size={20} className="text-blue-400" />
            Downloads & Offline Storage
          </h2>
          <p className="text-sm text-muted mb-6">
            Cached 320kbps MP3 tracks stored in your browser for instant playback without internet.
          </p>

          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-4 rounded-lg bg-neutral-900/60 border border-white/5">
            <div className="flex items-center gap-4">
              <div className="w-12 h-12 rounded-lg bg-blue-500/10 flex items-center justify-center text-blue-400 border border-blue-500/20">
                <Download size={22} />
              </div>
              <div>
                <p className="font-semibold text-white">
                  {offlineStats.count} {offlineStats.count === 1 ? 'Track' : 'Tracks'} Saved Offline
                </p>
                <p className="text-xs text-muted mt-0.5">
                  Storage used: <span className="font-mono text-brand font-bold">{offlineStats.formattedSize}</span> (High Fidelity 320kbps)
                </p>
              </div>
            </div>

            {offlineStats.count > 0 && (
              <button
                type="button"
                onClick={async () => {
                  if (window.confirm('Clear all downloaded offline audio files from your browser cache?')) {
                    setIsClearingOffline(true);
                    await clearAllOfflineTracks();
                    setIsClearingOffline(false);
                  }
                }}
                disabled={isClearingOffline}
                className="px-4 py-2 bg-red-500/10 hover:bg-red-500/20 text-red-400 rounded-lg text-xs font-semibold border border-red-500/20 transition-colors flex items-center gap-2 self-start sm:self-center"
              >
                <Trash2 size={14} />
                {isClearingOffline ? 'Clearing...' : 'Clear Offline Cache'}
              </button>
            )}
          </div>
        </section>

        {/* Data Portability Section */}
        <section className="bg-surface-card p-6 rounded-xl border border-white/5 text-white">
          <h2 className="text-xl font-semibold mb-2 flex items-center gap-2">
            <Download size={20} className="text-purple-400" />
            Data Portability
          </h2>
          <p className="text-sm text-muted mb-6">Download a copy of your personal data or import it from another account.</p>
          
          <div className="flex flex-wrap gap-4">
            <button 
              onClick={handleExportData}
              disabled={isExporting}
              className="flex items-center gap-2 bg-surface hover:bg-surface-hover text-white px-6 py-3 rounded-lg font-bold transition-colors disabled:opacity-50 border border-white/5"
            >
              {isExporting ? <span className="animate-spin border-2 border-white/20 border-t-white rounded-full w-4 h-4" /> : <Download size={18} />}
              Download My Data
            </button>

            <button 
              onClick={handleImportClick}
              disabled={isImporting}
              className="flex items-center gap-2 bg-surface hover:bg-surface-hover text-white px-6 py-3 rounded-lg font-bold transition-colors disabled:opacity-50 border border-white/5"
            >
              {isImporting ? <span className="animate-spin border-2 border-white/20 border-t-white rounded-full w-4 h-4" /> : <Upload size={18} />}
              Import Data from File
            </button>
          </div>
        </section>

        {/* PWA Install Section */}
        <section className="bg-surface-card p-6 rounded-xl border border-white/5">
          <h2 className="text-xl font-semibold mb-2 flex items-center gap-2 text-white">
            <Download size={20} className="text-brand" />
            Get the App
          </h2>
          <p className="text-sm text-muted mb-4">Install Paatu Padava on your device for the best experience, offline support, and quick access.</p>
          <InstallPWA />
        </section>

        {/* Security Section */}
        <section className="bg-surface-card p-6 rounded-xl border border-white/5">
          <h2 className="text-xl font-semibold mb-4 flex items-center gap-2 text-white">
            <ShieldAlert size={20} className="text-blue-400" />
            Account Actions
          </h2>
          
          <div className="flex flex-wrap gap-4">
            <button 
              onClick={handleLogout}
              className="flex items-center gap-2 bg-surface hover:bg-surface-hover text-white px-6 py-3 rounded-lg font-bold transition-colors border border-white/5"
            >
              <LogOut size={18} />
              Sign Out
            </button>

            <button 
              onClick={() => setShowDeleteModal(true)}
              className="flex items-center gap-2 bg-red-500/10 hover:bg-red-500/20 text-red-500 border border-red-500/30 px-6 py-3 rounded-lg font-bold transition-colors"
            >
              <Trash2 size={18} />
              Delete Account
            </button>
          </div>
        </section>
      </div>

      {/* Delete Confirmation Modal */}
      {showDeleteModal && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/80 backdrop-blur-sm p-4">
          <div className="bg-surface w-full max-w-md rounded-2xl p-8 shadow-2xl border border-white/10">
            <h2 className="text-2xl font-bold mb-4 text-white">Are you absolutely sure?</h2>
            <p className="text-muted mb-8 leading-relaxed">
              This action cannot be undone. This will permanently delete your account and remove all your data, including your playlists and liked songs.
            </p>
            
            {error && <p className="text-red-500 text-sm mb-4">{error}</p>}

            <div className="flex flex-col gap-3">
              <button 
                onClick={handleDeleteAccount}
                disabled={isDeleting}
                className="w-full bg-red-500 text-white font-bold py-3 rounded-full hover:bg-red-600 transition-colors disabled:opacity-50"
              >
                {isDeleting ? 'Deleting...' : 'Yes, Delete My Account'}
              </button>
              <button 
                onClick={() => setShowDeleteModal(false)}
                disabled={isDeleting}
                className="w-full bg-transparent text-white font-bold py-3 rounded-full hover:bg-surface-hover transition-colors border border-white/10"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

    </div>
  );
};

export default Settings;
