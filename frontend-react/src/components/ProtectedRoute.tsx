import React from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { LogIn, UserPlus, Music2, Heart, Clock, ListMusic } from 'lucide-react';

interface ProtectedRouteProps {
  children: React.ReactNode;
}

/**
 * Instead of redirecting to /login, shows an inline auth prompt card.
 * Users can browse the app freely; auth-required features show this prompt.
 */
const ProtectedRoute: React.FC<ProtectedRouteProps> = ({ children }) => {
  const { user, isLoading, token } = useAuth();
  const navigate = useNavigate();

  if (isLoading) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[50vh] gap-4">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-brand"></div>
        <p className="text-neutral-400">Verifying session...</p>
      </div>
    );
  }

  if (!user && !token) {
    return (
      <div className="flex items-center justify-center min-h-[60vh] p-6">
        <div className="relative w-full max-w-md">
          {/* Glow effect */}
          <div className="absolute -inset-1 bg-gradient-to-r from-purple-600/20 via-pink-500/20 to-purple-600/20 rounded-2xl blur-xl" />
          
          <div className="relative bg-[#1a1a2e] border border-white/10 rounded-2xl p-8 text-center shadow-2xl backdrop-blur-sm">
            {/* Decorative icons */}
            <div className="flex items-center justify-center gap-3 mb-6">
              <div className="p-2.5 bg-purple-500/10 rounded-xl border border-purple-500/20">
                <Heart size={20} className="text-purple-400" />
              </div>
              <div className="p-2.5 bg-pink-500/10 rounded-xl border border-pink-500/20">
                <ListMusic size={20} className="text-pink-400" />
              </div>
              <div className="p-2.5 bg-indigo-500/10 rounded-xl border border-indigo-500/20">
                <Clock size={20} className="text-indigo-400" />
              </div>
            </div>

            {/* Heading */}
            <div className="mb-2">
              <Music2 size={36} className="text-purple-400 mx-auto mb-3" />
            </div>
            <h2 className="text-2xl font-bold text-white mb-2">
              Sign in to unlock this
            </h2>
            <p className="text-neutral-400 text-sm leading-relaxed mb-8 max-w-xs mx-auto">
              Create an account or log in to access your liked songs, playlists, listening history, and more.
            </p>

            {/* Feature list */}
            <div className="flex flex-col gap-2.5 mb-8 text-left">
              {[
                { icon: Heart, text: 'Save your liked songs', color: 'text-pink-400' },
                { icon: ListMusic, text: 'Create & manage playlists', color: 'text-purple-400' },
                { icon: Clock, text: 'Track your listening history', color: 'text-indigo-400' },
              ].map((item, idx) => (
                <div key={idx} className="flex items-center gap-3 p-2.5 rounded-lg bg-white/[0.03] border border-white/5">
                  <item.icon size={16} className={item.color} />
                  <span className="text-sm text-neutral-300">{item.text}</span>
                </div>
              ))}
            </div>

            {/* Action buttons */}
            <div className="flex flex-col gap-3">
              <button
                onClick={() => navigate('/login')}
                className="w-full flex items-center justify-center gap-2 bg-white text-black font-bold py-3 px-6 rounded-full hover:scale-[1.02] active:scale-[0.98] transition-all duration-200 shadow-lg"
              >
                <LogIn size={18} />
                Log in
              </button>
              <button
                onClick={() => navigate('/signup')}
                className="w-full flex items-center justify-center gap-2 bg-white/[0.08] text-white font-bold py-3 px-6 rounded-full hover:bg-white/[0.12] transition-all duration-200 border border-white/10"
              >
                <UserPlus size={18} />
                Sign up free
              </button>
            </div>

            {/* Subtle note */}
            <p className="text-neutral-600 text-[11px] mt-5">
              You can still browse & play music without signing in
            </p>
          </div>
        </div>
      </div>
    );
  }

  return <>{children}</>;
};

export default ProtectedRoute;
