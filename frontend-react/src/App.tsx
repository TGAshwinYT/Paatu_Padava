import { useState, useEffect, lazy, Suspense } from 'react';
import axios from 'axios';
import { BrowserRouter as Router, Routes, Route, useNavigate, useLocation } from 'react-router-dom';
import Home from './pages/Home';

const Search = lazy(() => import('./pages/Search'));
const LikedSongs = lazy(() => import('./pages/LikedSongs'));
const RecentlyListened = lazy(() => import('./pages/RecentlyListened'));
const Login = lazy(() => import('./pages/Login'));
const Signup = lazy(() => import('./pages/Signup'));
const Onboarding = lazy(() => import('./pages/Onboarding'));
const Settings = lazy(() => import('./pages/Settings'));
const ForgotPassword = lazy(() => import('./pages/ForgotPassword'));
const PlaylistDetail = lazy(() => import('./pages/PlaylistDetail'));
const ArtistView = lazy(() => import('./pages/ArtistView'));
const Profile = lazy(() => import('./pages/Profile'));
const AlbumView = lazy(() => import('./pages/AlbumView'));
const LocalArtists = lazy(() => import('./pages/LocalArtists'));
const DownloadedSongs = lazy(() => import('./pages/DownloadedSongs'));

const PageLoadingFallback = () => (
  <div className="flex-1 flex items-center justify-center min-h-[50vh]">
    <div className="w-8 h-8 border-2 border-indigo-500 border-t-transparent rounded-full animate-spin" />
  </div>
);

import LibraryAuthModal from './components/modals/LibraryAuthModal';
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
import UserDropdown from './components/UserDropdown';
import TopSearchBar from './components/TopSearchBar';
import useKeyboardShortcuts from './hooks/useKeyboardShortcuts';
import KeyboardShortcutsModal from './components/KeyboardShortcutsModal';

const AppContent = () => {
  const [isAuthModalOpen, setIsAuthModalOpen] = useState(false);
  const [isShortcutsModalOpen, setIsShortcutsModalOpen] = useState(false);
  const { isOpen: isPlaylistModalOpen, song, closeModal } = usePlaylistModal();
  const isMobile = useMobile();
  const { 
    user, 
    logout, 
    isLibraryAuthModalOpen, 
    closeLibraryAuthModal 
  } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  // Auth pages render full-screen without sidebar/playerbar/topbar
  const isAuthPage = ['/login', '/signup', '/forgot-password'].includes(location.pathname);

  // Global event listener to toggle shortcuts modal from anywhere
  useEffect(() => {
    const handleToggleModal = () => setIsShortcutsModalOpen(prev => !prev);
    const handleEscape = () => {
      setIsShortcutsModalOpen(false);
      setIsAuthModalOpen(false);
    };
    window.addEventListener('paatu:toggle-shortcuts-modal', handleToggleModal);
    window.addEventListener('paatu:escape-pressed', handleEscape);
    return () => {
      window.removeEventListener('paatu:toggle-shortcuts-modal', handleToggleModal);
      window.removeEventListener('paatu:escape-pressed', handleEscape);
    };
  }, []);

  // Desktop keyboard shortcuts
  useKeyboardShortcuts({
    enabled: !isMobile && !isAuthPage,
  });

  if (isMobile) {
    return (
      <>
        <MobileLayout />
        <AuthModal isOpen={isAuthModalOpen} onClose={() => setIsAuthModalOpen(false)} />
        <AddToPlaylistModal isOpen={isPlaylistModalOpen} song={song} onClose={closeModal} />
      </>
    );
  }

  // Full-screen auth pages (no sidebar, no player, no top bar)
  if (isAuthPage) {
    return (
      <Suspense fallback={<PageLoadingFallback />}>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/signup" element={<Signup />} />
          <Route path="/forgot-password" element={<ForgotPassword />} />
        </Routes>
      </Suspense>
    );
  }

  return (
    <div className="flex flex-col h-screen bg-black text-white overflow-hidden font-display">
      {/* Top Work Area: Sidebar + Main Content */}
      <div className="flex-1 flex overflow-hidden p-2 pb-1 gap-2 min-h-0">
        <Sidebar />
        
        <main className="flex-1 overflow-y-auto bg-neutral-900 rounded-xl relative pb-12">
          <LibraryAuthModal isOpen={isLibraryAuthModalOpen} onClose={closeLibraryAuthModal} />
          
          {/* Top Header Area */}
          <div className="sticky top-0 z-50 flex items-center justify-between w-full p-4 px-6 bg-neutral-900/80 backdrop-blur-md border-b border-white/5">
            <TopSearchBar />

            {/* Top-Right Area: Profile Menu or Login/Signup */}
            <div className="flex items-center gap-4">
              {user ? (
                <UserDropdown user={user} onLogout={logout} />
              ) : (
              <div className="flex items-center gap-6">
                <div className="w-8 h-8 rounded-lg flex-shrink-0 overflow-hidden shadow-lg border border-white/10 group-hover:scale-110 transition-transform duration-300">
                  <img src="/logo.png" className="w-full h-full object-cover" alt="Logo" />
                </div>
                <button 
                  onClick={() => navigate('/signup')} 
                  className="text-neutral-400 hover:text-white font-bold text-sm transition-colors"
                >
                  Sign up
                </button>
                <button 
                  onClick={() => navigate('/login')} 
                  className="bg-white text-black px-8 py-2.5 rounded-full font-bold text-sm hover:scale-105 active:scale-95 transition-all duration-200 shadow-lg"
                >
                  Log in
                </button>
              </div>
            )}
          </div>
          </div>

          <div className="absolute top-0 inset-x-0 bg-gradient-to-b from-neutral-800/50 to-transparent pointer-events-none h-64" />
          <div className="relative z-10 p-6">
            <Suspense fallback={<PageLoadingFallback />}>
              <Routes>
                <Route path="/" element={<Home isLoggedIn={!!user} />} />
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
                <Route path="/artist/:artistId" element={<ArtistView />} />
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
                <Route path="/profile" element={
                  <ProtectedRoute>
                    <Profile />
                  </ProtectedRoute>
                } />
                <Route path="/album/:id" element={<AlbumView />} />
                <Route path="/local-artists" element={<LocalArtists />} />
                <Route path="/downloaded" element={<DownloadedSongs />} />
              </Routes>
            </Suspense>
          </div>
        </main>
      </div>
      
      {/* Bottom Desktop Player Bar */}
      <PlayerBar />
      
      <AuthModal isOpen={isAuthModalOpen} onClose={() => setIsAuthModalOpen(false)} />
      <AddToPlaylistModal isOpen={isPlaylistModalOpen} song={song} onClose={closeModal} />
      <KeyboardShortcutsModal isOpen={isShortcutsModalOpen} onClose={() => setIsShortcutsModalOpen(false)} />
    </div>
  );
};

const App = () => {
  const [isServerReady, setIsServerReady] = useState(false);
  const API_URL = import.meta.env.VITE_DATA_API_URL || (import.meta.env.PROD ? 'https://tgashwinyt-paatu-padava.hf.space' : 'http://localhost:8000');

  useEffect(() => {
    let isMounted = true;
    const checkHealth = async () => {
      try {
        const response = await axios.get(`${API_URL}/api/health`, { timeout: 8000 });
        if (response.status === 200 && isMounted) {
          setIsServerReady(true);
        }
      } catch {
        console.log("Backend cold starting... retrying in 3s");
        if (isMounted) setTimeout(checkHealth, 3000);
      }
    };
    checkHealth();
    return () => { isMounted = false; };
  }, [API_URL]);

  return (
    <Router>
      <PlaylistModalProvider>
        <AudioProvider>
          {!isServerReady && (
            <div className="bg-indigo-900/60 text-indigo-200 text-xs py-1 px-4 text-center border-b border-indigo-500/20 flex items-center justify-center gap-2 z-50">
              <div className="w-2 h-2 rounded-full bg-amber-400 animate-pulse" />
              <span>Connecting to cloud service... Player and offline library are ready.</span>
            </div>
          )}
          <AppContent />
        </AudioProvider>
      </PlaylistModalProvider>
    </Router>
  );
};

export default App;
