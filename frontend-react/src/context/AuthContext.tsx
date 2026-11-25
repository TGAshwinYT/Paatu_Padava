import React, { createContext, useContext, useState, useEffect } from 'react';
import api from '../services/api';
import GuestPlaylistImportModal from '../components/GuestPlaylistImportModal';
import {
  clearAccountPlaylists,
  getUnhandledGuestPlaylists,
  markGuestImportHandled,
} from '../utils/offlineStorage';

interface AuthContextType {
  user: any;
  token: string | null;
  login: (email: string, pass: string) => Promise<void>;
  register: (email: string, pass: string, name: string) => Promise<void>;
  googleLogin: (credential: string) => Promise<void>;
  logout: () => Promise<void>;
  isLoading: boolean;
  isLibraryAuthModalOpen: boolean;
  openLibraryAuthModal: () => void;
  closeLibraryAuthModal: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<any>(null);
  const [token, setToken] = useState<string | null>(localStorage.getItem('token'));
  const [isLoading, setIsLoading] = useState(false);
  const [isLibraryAuthModalOpen, setIsLibraryAuthModalOpen] = useState(false);
  const [pendingGuestCount, setPendingGuestCount] = useState(0);
  const [isImportingGuest, setIsImportingGuest] = useState(false);

  const checkGuestImportPrompt = (userId?: string) => {
    if (!userId) {
      setPendingGuestCount(0);
      return;
    }
    const unhandled = getUnhandledGuestPlaylists(userId);
    setPendingGuestCount(unhandled.length);
  };

  const openLibraryAuthModal = () => setIsLibraryAuthModalOpen(true);
  const closeLibraryAuthModal = () => setIsLibraryAuthModalOpen(false);

  useEffect(() => {
    const initAuth = async () => {
      if (token) {
        setIsLoading(true);
        try {
          const response = await api.get('/api/auth/me');
          setUser(response.data);
          localStorage.setItem('token', token);
          checkGuestImportPrompt(response.data?.id);
        } catch (error) {
          console.error("Session restoration failed:", error);
          clearAccountPlaylists(user?.id);
          setToken(null);
          setUser(null);
          localStorage.removeItem('token');
        } finally {
          setIsLoading(false);
        }
      }
    };
    initAuth();
  }, [token]);

  useEffect(() => {
    const handleAuthExpired = () => {
      clearAccountPlaylists(user?.id);
      setToken(null);
      setUser(null);
      setPendingGuestCount(0);
      localStorage.removeItem('token');
      window.dispatchEvent(new Event('playlists-updated'));
    };
    window.addEventListener('auth-expired', handleAuthExpired);
    return () => window.removeEventListener('auth-expired', handleAuthExpired);
  }, [user?.id]);

  const login = async (email: string, pass: string) => {
    setIsLoading(true);
    try {
      const response = await api.post('/api/auth/login', { email, password: pass });
      const { access_token, user } = response.data;
      setToken(access_token);
      setUser(user);
      localStorage.setItem('token', access_token);
      checkGuestImportPrompt(user?.id);
    } finally {
      setIsLoading(false);
    }
  };

  const register = async (email: string, pass: string, username: string) => {
    setIsLoading(true);
    try {
      const regResponse = await api.post('/api/auth/register', { email, password: pass, username });
      // Attempt auto-login if account does not require immediate manual email confirmation
      try {
        await login(email, pass);
      } catch (loginErr: any) {
        if (loginErr?.response?.status === 403) {
          throw new Error(regResponse.data?.message || 'Registration successful. Please verify your email before logging in.');
        }
        throw loginErr;
      }
    } finally {
      setIsLoading(false);
    }
  };

  const googleLogin = async (credential: string) => {
    setIsLoading(true);
    try {
      const response = await api.post('/api/auth/google', { credential });
      const { access_token, user } = response.data;
      setToken(access_token);
      setUser(user);
      localStorage.setItem('token', access_token);
      checkGuestImportPrompt(user?.id);
    } finally {
      setIsLoading(false);
    }
  };

  const logout = async () => {
    const prevUserId = user?.id;
    try {
      await api.post('/api/auth/logout');
    } catch (err) {
      console.error("Logout error:", err);
    } finally {
      clearAccountPlaylists(prevUserId);
      setToken(null);
      setUser(null);
      setPendingGuestCount(0);
      localStorage.removeItem('token');
      window.dispatchEvent(new Event('playlists-updated'));
    }
  };

  const handleDeclineGuestImport = () => {
    if (!user?.id) return;
    const unhandled = getUnhandledGuestPlaylists(user.id);
    markGuestImportHandled(user.id, unhandled.map((p) => p.id));
    setPendingGuestCount(0);
  };

  const handleApproveGuestImport = async () => {
    if (!user?.id) return;
    setIsImportingGuest(true);
    try {
      const unhandled = getUnhandledGuestPlaylists(user.id);
      for (const pl of unhandled) {
        const created = await api.post('/api/playlists/', {
          title: pl.title,
          is_public: false,
        });
        const newId = created.data?.id;
        if (newId && Array.isArray(pl.tracks)) {
          for (const track of pl.tracks) {
            try {
              await api.post(`/api/playlists/${newId}/tracks`, track);
            } catch (trackErr) {
              console.error('Failed to import track into playlist:', trackErr);
            }
          }
        }
      }
      markGuestImportHandled(user.id, unhandled.map((p) => p.id));
      setPendingGuestCount(0);
      window.dispatchEvent(new Event('playlists-updated'));
    } catch (err) {
      console.error('Failed to import guest playlists:', err);
    } finally {
      setIsImportingGuest(false);
    }
  };

  return (
    <AuthContext.Provider value={{ 
      user, 
      token, 
      login, 
      register, 
      googleLogin,
      logout, 
      isLoading,
      isLibraryAuthModalOpen,
      openLibraryAuthModal,
      closeLibraryAuthModal
    }}>
      {children}
      <GuestPlaylistImportModal
        isOpen={Boolean(user && pendingGuestCount > 0)}
        count={pendingGuestCount}
        isBusy={isImportingGuest}
        onApprove={handleApproveGuestImport}
        onDecline={handleDeclineGuestImport}
      />
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used within AuthProvider');
  return context;
};
