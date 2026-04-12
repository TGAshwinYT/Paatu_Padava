import React from 'react';
import { Routes, Route } from 'react-router-dom';
import MobileHome from '../pages/mobile/MobileHome';
import MobileSearch from '../pages/mobile/MobileSearch';
import MobileLibrary from '../pages/mobile/MobileLibrary';
import Onboarding from '../pages/Onboarding';
import Settings from '../pages/Settings';
import Login from '../pages/Login';
import Signup from '../pages/Signup';
import RecentlyListened from '../pages/RecentlyListened';
import ProtectedRoute from '../components/ProtectedRoute';
import AlbumView from '../pages/AlbumView';
import ArtistView from '../pages/ArtistView';
import PlaylistDetail from '../pages/PlaylistDetail';
import Profile from '../pages/Profile';
import LocalArtists from '../pages/LocalArtists';
import ForgotPassword from '../pages/ForgotPassword';
import MobileBottomNavbar from '../components/mobile/MobileBottomNavbar';
import MobilePlayerOverlay from '../components/mobile/MobilePlayerOverlay';

const MobileLayout: React.FC = () => {
  return (
    <div className="flex flex-col h-screen bg-black text-white relative overflow-hidden">
      {/* Scrollable Content Area */}
      <main className="flex-1 overflow-y-auto pb-32">
        <Routes>
          <Route path="/" element={<MobileHome />} />
          <Route path="/search" element={<MobileSearch />} />
          <Route path="/library" element={
            <ProtectedRoute>
              <MobileLibrary />
            </ProtectedRoute>
          } />
          <Route path="/history" element={
            <ProtectedRoute>
              <RecentlyListened />
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
          <Route path="/album/:id" element={<AlbumView />} />
          <Route path="/artist/:artistId" element={
            <ProtectedRoute>
              <ArtistView />
            </ProtectedRoute>
          } />
          <Route path="/playlist/:id" element={
            <ProtectedRoute>
              <PlaylistDetail />
            </ProtectedRoute>
          } />
          <Route path="/profile" element={
            <ProtectedRoute>
              <Profile />
            </ProtectedRoute>
          } />
          <Route path="/local-artists" element={<LocalArtists />} />
          <Route path="/forgot-password" element={<ForgotPassword />} />
          <Route path="/login" element={<Login />} />
          <Route path="/signup" element={<Signup />} />
        </Routes>
      </main>

      {/* Persistent Full-Screen Player / Mini Player */}
      <MobilePlayerOverlay />

      {/* Bottom Tabs */}
      <MobileBottomNavbar />
    </div>
  );
};

export default MobileLayout;
