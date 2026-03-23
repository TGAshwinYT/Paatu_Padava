import { useState, useEffect, useRef } from 'react';
import { BrowserRouter as Router, Routes, Route, useNavigate } from 'react-router-dom';
import Home from './pages/Home';
import Search from './pages/Search';
import LikedSongs from './pages/LikedSongs';
import RecentlyListened from './pages/RecentlyListened';
import Login from './pages/Login';
import Signup from './pages/Signup';
import Onboarding from './pages/Onboarding';
import Settings from './pages/Settings';
import ForgotPassword from './pages/ForgotPassword';
import ResetPassword from './pages/ResetPassword';
import PlaylistDetail from './pages/PlaylistDetail';
import ArtistView from './pages/ArtistView';
import ProtectedRoute from './components/ProtectedRoute';
import Sidebar from './components/Sidebar';
import PlayerBar from './components/PlayerBar';
import AuthModal from './components/AuthModal';
import AddToPlaylistModal from './components/AddToPlaylistModal';
import { AudioProvider } from './context/AudioContext';
import { PlaylistModalProvider, usePlaylistModal } from './context/PlaylistModalContext';
import { useAuth } from './context/AuthContext';

import { useMobile } from './hooks/useMobile';
import MobileLayout from './layouts/MobileLayout';

const AppContent = () => {
  const [isAuthModalOpen, setIsAuthModalOpen] = useState(false);
  const { isOpen: isPlaylistModalOpen, songId, closeModal } = usePlaylistModal();
  const isMobile = useMobile();
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  // Profile Dropdown State
  const [isProfileMenuOpen, setIsProfileMenuOpen] = useState(false);
  const profileMenuRef = useRef<HTMLDivElement>(null);

  // Close menu when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (profileMenuRef.current && !profileMenuRef.current.contains(event.target as Node)) {
        setIsProfileMenuOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  if (isMobile) {
    return (
      <>
        <MobileLayout />
        <AuthModal isOpen={isAuthModalOpen} onClose={() => setIsAuthModalOpen(false)} />
        <AddToPlaylistModal isOpen={isPlaylistModalOpen} songId={songId} onClose={closeModal} />
      </>
    );
  }

  return (
    <div className="flex h-screen bg-black text-white overflow-hidden p-2 gap-2 font-display">
      <Sidebar onLogin={() => setIsAuthModalOpen(true)} />
      
      <main className="flex-1 overflow-y-auto bg-neutral-900 rounded-xl relative pb-24 md:pb-32">
        {/* Top-Right Profile Menu */}
        <div className="absolute top-6 right-6 z-50" ref={profileMenuRef}>
          <div className="relative">
            <button 
              onClick={() => setIsProfileMenuOpen(!isProfileMenuOpen)} 
              className="w-8 h-8 rounded-full bg-pink-500 text-white font-black text-sm flex items-center justify-center shadow-lg hover:scale-105 active:scale-95 transition-all duration-200 border border-white/10"
            >
              {user?.username?.[0]?.toUpperCase() || 'A'}
            </button>
            
            {isProfileMenuOpen && (
              <div className="absolute top-10 right-0 z-[60] w-48 bg-[#282828] p-1 rounded-md shadow-[0_16px_24px_rgba(0,0,0,0.3)] border border-white/10 animate-in fade-in zoom-in-95 duration-100 origin-top-right">
                <div 
                  onClick={() => { navigate('/settings'); setIsProfileMenuOpen(false); }}
                  className="text-sm text-neutral-200 p-3 hover:bg-neutral-700/60 rounded-sm cursor-pointer transition-colors font-medium flex items-center justify-between"
                >
                  Profile
                </div>
                <hr className="border-white/10 my-1" />
                <div 
                  onClick={() => { logout(); setIsProfileMenuOpen(false); }}
                  className="text-sm text-neutral-200 p-3 hover:bg-neutral-700/60 rounded-sm cursor-pointer transition-colors font-medium"
                >
                  Sign out
                </div>
              </div>
            )}
          </div>
        </div>

        <div className="absolute inset-0 bg-gradient-to-b from-neutral-800/50 to-transparent pointer-events-none h-64" />
        <div className="relative z-10 p-6">
          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/search" element={<Search />} />
            <Route path="/library" element={
              <ProtectedRoute>
                <LikedSongs />
              </ProtectedRoute>
            } />
            <Route path="/playlist/:id" element={
              <ProtectedRoute>
                <PlaylistDetail />
              </ProtectedRoute>
            } />
            <Route path="/history" element={
              <ProtectedRoute>
                <RecentlyListened />
              </ProtectedRoute>
            } />
            <Route path="/artist/:artistId" element={
              <ProtectedRoute>
                <ArtistView />
              </ProtectedRoute>
            } />
            <Route path="/onboarding" element={
              <ProtectedRoute>
                <Onboarding />
              </ProtectedRoute>
            } />
            <Route path="/settings" element={
              <ProtectedRoute>
                <Settings />
              </ProtectedRoute>
            } />
            <Route path="/login" element={<Login />} />
            <Route path="/signup" element={<Signup />} />
            <Route path="/forgot-password" element={<ForgotPassword />} />
            <Route path="/reset-password" element={<ResetPassword />} />
          </Routes>
        </div>
      </main>
      
      <PlayerBar />
      
      <AuthModal isOpen={isAuthModalOpen} onClose={() => setIsAuthModalOpen(false)} />
      <AddToPlaylistModal isOpen={isPlaylistModalOpen} songId={songId} onClose={closeModal} />
    </div>
  );
};

const App = () => {
  return (
    <Router>
      <PlaylistModalProvider>
        <AudioProvider>
          <AppContent />
        </AudioProvider>
      </PlaylistModalProvider>
    </Router>
  );
};

export default App;
