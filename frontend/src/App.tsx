import { useState } from 'react';
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
import Album from './pages/Album';
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
        {/* Top-Right Area: Profile Menu or Login/Signup */}
        <div className="absolute top-6 right-6 z-50 flex items-center gap-4">
          {user ? (
            <UserDropdown user={user} onLogout={logout} />
          ) : (
            <div className="flex items-center gap-6">
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

        <div className="absolute inset-0 bg-gradient-to-b from-neutral-800/50 to-transparent pointer-events-none h-64" />
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
            <Route path="/album/:id" element={<Album />} />
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
