import React, { lazy, Suspense } from 'react';
import { Routes, Route } from 'react-router-dom';
import MobileHome from '../pages/mobile/MobileHome';
import ProtectedRoute from '../components/ProtectedRoute';
import MobileBottomNavbar from '../components/mobile/MobileBottomNavbar';
import MobilePlayerOverlay from '../components/mobile/MobilePlayerOverlay';

const MobileSearch = lazy(() => import('../pages/mobile/MobileSearch'));
const MobileLibrary = lazy(() => import('../pages/mobile/MobileLibrary'));
const Onboarding = lazy(() => import('../pages/Onboarding'));
const Settings = lazy(() => import('../pages/Settings'));
const Login = lazy(() => import('../pages/Login'));
const Signup = lazy(() => import('../pages/Signup'));
const RecentlyListened = lazy(() => import('../pages/RecentlyListened'));
const AlbumView = lazy(() => import('../pages/AlbumView'));
const ArtistView = lazy(() => import('../pages/ArtistView'));
const PlaylistDetail = lazy(() => import('../pages/PlaylistDetail'));
const Profile = lazy(() => import('../pages/Profile'));
const LocalArtists = lazy(() => import('../pages/LocalArtists'));
const DownloadedSongs = lazy(() => import('../pages/DownloadedSongs'));
const ForgotPassword = lazy(() => import('../pages/ForgotPassword'));

const MobileLoadingFallback = () => (
  <div className="flex-1 flex items-center justify-center min-h-[50vh]">
    <div className="w-8 h-8 border-2 border-indigo-500 border-t-transparent rounded-full animate-spin" />
  </div>
);

const MobileLayout: React.FC = () => {
  return (
    <div className="flex flex-col h-screen bg-black text-white relative overflow-hidden">
      {/* Scrollable Content Area */}
      <main className="flex-1 overflow-y-auto pb-32">
        <Suspense fallback={<MobileLoadingFallback />}>
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
            <Route path="/artist/:artistId" element={<ArtistView />} />
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
            <Route path="/downloaded" element={<DownloadedSongs />} />
            <Route path="/forgot-password" element={<ForgotPassword />} />
            <Route path="/login" element={<Login />} />
            <Route path="/signup" element={<Signup />} />
          </Routes>
        </Suspense>
      </main>

      {/* Persistent Full-Screen Player / Mini Player */}
      <MobilePlayerOverlay />

      {/* Bottom Tabs */}
      <MobileBottomNavbar />
    </div>
  );
};

export default MobileLayout;
