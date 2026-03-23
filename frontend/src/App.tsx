import { useState } from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import Home from './pages/Home';
import Search from './pages/Search';
import LikedSongs from './pages/LikedSongs';
import RecentlyListened from './pages/RecentlyListened';
import Login from './pages/Login';
import Signup from './pages/Signup';
import Onboarding from './pages/Onboarding';
import Settings from './pages/Settings';
import PlaylistDetail from './pages/PlaylistDetail';
import ArtistView from './pages/ArtistView';
import ProtectedRoute from './components/ProtectedRoute';
import Sidebar from './components/Sidebar';
import PlayerBar from './components/PlayerBar';
import AuthModal from './components/AuthModal';
import AddToPlaylistModal from './components/AddToPlaylistModal';
import { AudioProvider } from './context/AudioContext';
import { PlaylistModalProvider, usePlaylistModal } from './context/PlaylistModalContext';

import { useMobile } from './hooks/useMobile';
import MobileLayout from './layouts/MobileLayout';

const AppContent = () => {
  const [isAuthModalOpen, setIsAuthModalOpen] = useState(false);
  const { isOpen: isPlaylistModalOpen, songId, closeModal } = usePlaylistModal();
  const isMobile = useMobile();

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
