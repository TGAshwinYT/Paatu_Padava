import React, { createContext, useContext, useState, useEffect } from 'react';
import api from '../services/api';

interface AuthContextType {
  user: any;
  token: string | null;
  login: (email: string, pass: string) => Promise<void>;
  register: (email: string, pass: string, name: string) => Promise<void>;
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
        } catch (error) {
          console.error("Session restoration failed:", error);
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

  const login = async (email: string, pass: string) => {
    setIsLoading(true);
    try {
      const response = await api.post('/api/auth/login', { email, password: pass });
      const { access_token, user } = response.data;
      setToken(access_token);
      setUser(user);
      localStorage.setItem('token', access_token);
    } finally {
      setIsLoading(false);
    }
  };

  const register = async (email: string, pass: string, username: string) => {
    setIsLoading(true);
    try {
      await api.post('/api/auth/register', { email, password: pass, username });
      // After register, auto-login
      await login(email, pass);
    } finally {
      setIsLoading(false);
    }
  };

  const logout = async () => {
    try {
      await api.post('/api/auth/logout');
    } catch (err) {
      console.error("Logout error:", err);
    } finally {
      setToken(null);
      setUser(null);
      localStorage.removeItem('token');
    }
  };

  return (
    <AuthContext.Provider value={{ 
      user, 
      token, 
      login, 
      register, 
      logout, 
      isLoading,
      isLibraryAuthModalOpen,
      openLibraryAuthModal,
      closeLibraryAuthModal
    }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used within AuthProvider');
  return context;
};
