import { useState, useEffect } from 'react';
import axios from 'axios';
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
import PlaylistDetail from './pages/PlaylistDetail';
import ArtistView from './pages/ArtistView';
import Profile from './pages/Profile';
import AlbumView from './pages/AlbumView';
import LocalArtists from './pages/LocalArtists';
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

const AppContent = () => {
  const [isAuthModalOpen, setIsAuthModalOpen] = useState(false);
  const { isOpen: isPlaylistModalOpen, song, closeModal } = usePlaylistModal();
  const isMobile = useMobile();
  const { 
    user, 
    logout, 
    isLibraryAuthModalOpen, 
    closeLibraryAuthModal 
  } = useAuth();
  const navigate = useNavigate();

  if (isMobile) {
    return (
      <>
        <MobileLayout />
        <AuthModal isOpen={isAuthModalOpen} onClose={() => setIsAuthModalOpen(false)} />
        <AddToPlaylistModal isOpen={isPlaylistModalOpen} song={song} onClose={closeModal} />
      </>
    );
  }

  return (
    <div className="flex h-screen bg-black text-white overflow-hidden p-2 gap-2 font-display">
      <Sidebar />
      
      <main className="flex-1 overflow-y-auto bg-neutral-900 rounded-xl relative pb-24 md:pb-32">
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
            <Route path="/profile" element={
              <ProtectedRoute>
                <Profile />
              </ProtectedRoute>
            } />
            <Route path="/album/:id" element={<AlbumView />} />
            <Route path="/local-artists" element={<LocalArtists />} />
            <Route path="/login" element={<Login />} />
            <Route path="/signup" element={<Signup />} />
            <Route path="/forgot-password" element={<ForgotPassword />} />
          </Routes>
        </div>
      </main>
      
      <PlayerBar />
      
      <AuthModal isOpen={isAuthModalOpen} onClose={() => setIsAuthModalOpen(false)} />
      <AddToPlaylistModal isOpen={isPlaylistModalOpen} song={song} onClose={closeModal} />
    </div>
  );
};

const SplashLoader = () => (
  <div className="h-screen w-screen bg-[#121212] flex flex-col items-center justify-center font-display p-6 text-center select-none">
    <div className="relative mb-12 group">
      {/* Icon Logo Container */}
      <div className="w-24 h-24 bg-neutral-800 rounded-[2rem] flex items-center justify-center border border-neutral-700 shadow-2xl relative z-10 transition-transform duration-700 group-hover:scale-110 overflow-hidden">
        <img src="/logo.png" className="w-full h-full object-cover" alt="Logo" />
      </div>
      
      {/* Outer Decorative Rings */}
      <div className="absolute -inset-4 border border-neutral-800 rounded-full animate-pulse opacity-50" />
      <div className="absolute -inset-8 border border-neutral-800/50 rounded-full animate-pulse opacity-25 [animation-delay:0.5s]" />
      
      {/* Spinning Loader Indicator */}
      <div className="absolute -inset-2 border-2 border-transparent border-t-neutral-500 rounded-full animate-spin z-20" />
    </div>
    
    <div className="space-y-2 mb-8">
      <h1 className="text-white text-4xl font-black tracking-tighter uppercase italic">Paatu Paaduva</h1>
      <div className="flex items-center justify-center gap-2">
        <span className="h-[1px] w-8 bg-neutral-800" />
        <p className="text-neutral-500 text-[10px] font-bold tracking-[0.3em] uppercase">Hyper Local Music</p>
        <span className="h-[1px] w-8 bg-neutral-800" />
      </div>
    </div>

    <div className="max-w-[280px] w-full space-y-6">
      <div className="relative">
        <p className="text-neutral-400 text-sm font-medium animate-pulse mb-3">
          Waking up our servers...
        </p>
        
        {/* Progress Bar Container */}
        <div className="h-1.5 w-full bg-neutral-900 rounded-full overflow-hidden border border-neutral-800/50">
          <div className="h-full bg-gradient-to-r from-neutral-700 via-white/40 to-neutral-700 rounded-full w-1/3 animate-loading" />
        </div>
      </div>
      
      <p className="text-neutral-600 text-[11px] leading-relaxed">
        This usually takes 10-15 seconds on the first load due to backend cold starts. <br />
        Thanks for your patience!
      </p>
    </div>
  </div>
);

const App = () => {
  const [isServerReady, setIsServerReady] = useState(false);
  const API_URL = import.meta.env.VITE_DATA_API_URL || 'http://localhost:8000';

  useEffect(() => {
    const checkHealth = async () => {
      try {
        const response = await axios.get(`${API_URL}/api/health`);
        if (response.status === 200) {
          setIsServerReady(true);
        }
      } catch (err) {
        console.log("Backend cold starting... retrying in 2s");
        setTimeout(checkHealth, 2000);
      }
    };
    checkHealth();
  }, [API_URL]);

  if (!isServerReady) {
    return <SplashLoader />;
  }

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
