import React, { useState, useRef } from 'react';
import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';
import { LogOut, Trash2, ShieldAlert, User as UserIcon, Download, Upload, CheckCircle2, AlertCircle, Sparkles } from 'lucide-react';
import api from '../services/api';
import InstallPWA from '../components/InstallPWA';

const Settings = () => {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const fileInputRef = useRef<HTMLInputElement>(null);
  
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [isExporting, setIsExporting] = useState(false);
  const [isImporting, setIsImporting] = useState(false);
  const [statusMessage, setStatusMessage] = useState<{type: 'success' | 'error', text: string} | null>(null);
  const [error, setError] = useState('');

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
          className="bg-green-500 text-black font-bold px-8 py-3 rounded-full hover:scale-105 transition-transform"
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
        <section className="bg-[#181818] p-6 rounded-xl border border-neutral-800">
          <h2 className="text-xl font-semibold mb-4 flex items-center gap-2 text-white">
            <UserIcon size={20} className="text-green-500" />
            Profile Information
          </h2>
          <div className="space-y-4">
            <div className="flex flex-col">
              <label className="text-xs text-neutral-500 uppercase font-bold mb-1">Username</label>
              <div className="text-neutral-200 bg-neutral-900 p-3 rounded-lg border border-neutral-800">
                {user.username}
              </div>
            </div>
            <div className="flex flex-col">
              <label className="text-xs text-neutral-500 uppercase font-bold mb-1">Email Address</label>
              <div className="flex items-center justify-between text-neutral-200 bg-neutral-900 p-3 rounded-lg border border-neutral-800">
                <span>{user.email}</span>
                {user.is_verified ? (
                  <span className="text-xs bg-green-500/10 text-green-500 px-2 py-1 rounded-full border border-green-500/20">Verified</span>
                ) : (
                  <span className="text-xs bg-yellow-500/10 text-yellow-500 px-2 py-1 rounded-full border border-yellow-500/20 text-center">Check terminal for link</span>
                )}
              </div>
            </div>
            
            <button 
              onClick={() => navigate('/onboarding')}
              className="w-full flex items-center justify-center gap-2 bg-neutral-800 hover:bg-neutral-700 text-white p-3 rounded-lg font-bold transition-all border border-neutral-700 mt-4 group"
            >
              <Sparkles size={18} className="text-green-500 group-hover:scale-110 transition-transform" />
              Update Music Preferences
            </button>
          </div>
        </section>

        {/* Data Portability Section */}
        <section className="bg-[#181818] p-6 rounded-xl border border-neutral-800 text-white">
          <h2 className="text-xl font-semibold mb-2 flex items-center gap-2">
            <Download size={20} className="text-purple-500" />
            Data Portability
          </h2>
          <p className="text-sm text-neutral-400 mb-6">Download a copy of your personal data or import it from another account.</p>
          
          <div className="flex flex-wrap gap-4">
            <button 
              onClick={handleExportData}
              disabled={isExporting}
              className="flex items-center gap-2 bg-neutral-800 hover:bg-neutral-700 text-white px-6 py-3 rounded-lg font-bold transition-colors disabled:opacity-50"
            >
              {isExporting ? <span className="animate-spin border-2 border-white/20 border-t-white rounded-full w-4 h-4" /> : <Download size={18} />}
              Download My Data
            </button>

            <button 
              onClick={handleImportClick}
              disabled={isImporting}
              className="flex items-center gap-2 bg-neutral-800 hover:bg-neutral-700 text-white px-6 py-3 rounded-lg font-bold transition-colors disabled:opacity-50"
            >
              {isImporting ? <span className="animate-spin border-2 border-white/20 border-t-white rounded-full w-4 h-4" /> : <Upload size={18} />}
              Import Data from File
            </button>
          </div>
        </section>

        {/* PWA Install Section */}
        <section className="bg-[#181818] p-6 rounded-xl border border-neutral-800">
          <h2 className="text-xl font-semibold mb-2 flex items-center gap-2 text-white">
            <Download size={20} className="text-green-500" />
            Get the App
          </h2>
          <p className="text-sm text-neutral-400 mb-4">Install Paatu Padava on your device for the best experience, offline support, and quick access.</p>
          <InstallPWA />
        </section>

        {/* Security Section */}
        <section className="bg-[#181818] p-6 rounded-xl border border-neutral-800">
          <h2 className="text-xl font-semibold mb-4 flex items-center gap-2 text-white">
            <ShieldAlert size={20} className="text-blue-500" />
            Account Actions
          </h2>
          
          <div className="flex flex-wrap gap-4">
            <button 
              onClick={handleLogout}
              className="flex items-center gap-2 bg-neutral-800 hover:bg-neutral-700 text-white px-6 py-3 rounded-lg font-bold transition-colors"
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
          <div className="bg-[#282828] w-full max-w-md rounded-2xl p-8 shadow-2xl border border-neutral-800">
            <h2 className="text-2xl font-bold mb-4 text-white">Are you absolutely sure?</h2>
            <p className="text-neutral-400 mb-8 leading-relaxed">
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
                className="w-full bg-transparent text-white font-bold py-3 rounded-full hover:bg-neutral-800 transition-colors"
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
