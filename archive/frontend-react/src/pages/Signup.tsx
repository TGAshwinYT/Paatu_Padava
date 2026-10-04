import React, { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { Eye, EyeOff, Lock, Mail, User, AlertCircle, ArrowRight } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { useGoogleLogin } from '@react-oauth/google';

const GoogleIcon = () => (
  <svg className="w-5 h-5" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
    <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
    <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
    <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
    <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
  </svg>
);

const Signup: React.FC = () => {
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(false);

  const { register, googleLogin } = useAuth();
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    if (!username.trim() || !email.trim() || !password) {
      setError('Please fill in all fields.');
      return;
    }

    if (password.length < 8) {
      setError('Password must be at least 8 characters long.');
      return;
    }

    setIsLoading(true);
    try {
      await register(email.trim(), password, username.trim());
      // Brand new accounts go straight to Onboarding (Languages & Artists)
      navigate('/onboarding');
    } catch (err: any) {
      setError(err.response?.data?.detail || 'Registration failed. That username or email may already be in use.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleGoogleAuth = useGoogleLogin({
    onSuccess: async (tokenResponse) => {
      setIsLoading(true);
      setError('');
      try {
        await googleLogin(tokenResponse.access_token);
        // Newly authorized accounts go to Onboarding
        navigate('/onboarding');
      } catch (err: any) {
        setError(err.response?.data?.detail || 'Google sign-up failed');
      } finally {
        setIsLoading(false);
      }
    },
    onError: () => {
      setError('Google sign-up was cancelled or failed.');
    }
  });

  return (
    <div className="min-h-screen w-full bg-surface-base flex flex-col items-center justify-center p-4 selection:bg-brand selection:text-black">
      {/* Background radial glow */}
      <div className="fixed inset-0 pointer-events-none overflow-hidden">
        <div className="absolute top-1/4 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] bg-brand/5 rounded-full blur-[140px]" />
      </div>

      <div className="w-full max-w-[420px] relative z-10">
        {/* Brand Header */}
        <div className="flex flex-col items-center mb-8">
          <Link to="/" className="flex items-center gap-3 group mb-3">
            <div className="w-12 h-12 rounded-2xl bg-surface-card border border-white/10 p-2 flex items-center justify-center shadow-xl group-hover:scale-105 transition-transform duration-300">
              <img src="/logo.png" alt="Paatu Padava Logo" className="w-full h-full object-cover rounded-xl" />
            </div>
            <span className="text-2xl font-black tracking-tight text-white group-hover:text-brand transition-colors">
              Paatu Paaduva
            </span>
          </Link>
          <h1 className="text-3xl font-black tracking-tight text-white text-center mt-2">
            Create your free account
          </h1>
          <p className="text-sm text-neutral-400 mt-1">
            Sign up to personalize your music taste and mixes.
          </p>
        </div>

        {/* Card Container */}
        <div className="bg-surface-card rounded-2xl border border-white/5 p-8 shadow-2xl backdrop-blur-md">
          {error && (
            <div className="mb-6 p-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 text-sm flex items-center gap-3 animate-in fade-in duration-200">
              <AlertCircle size={18} className="flex-shrink-0" />
              <span>{error}</span>
            </div>
          )}

          {/* Google Signup Button */}
          <button
            type="button"
            onClick={() => handleGoogleAuth()}
            disabled={isLoading}
            className="w-full flex items-center justify-center gap-3 bg-surface hover:bg-surface-hover active:bg-surface-active text-white border border-white/10 py-3.5 px-4 rounded-xl font-semibold text-sm transition-all duration-200 hover:scale-[1.01] active:scale-[0.99] disabled:opacity-50"
          >
            <GoogleIcon />
            <span>Sign up with Google</span>
          </button>

          {/* Divider */}
          <div className="flex items-center my-6 gap-3">
            <div className="flex-1 h-px bg-white/10" />
            <span className="text-xs uppercase tracking-wider font-semibold text-neutral-500">or</span>
            <div className="flex-1 h-px bg-white/10" />
          </div>

          {/* Registration Form */}
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-xs uppercase font-bold tracking-wider text-neutral-400 mb-1.5">
                Username
              </label>
              <div className="relative">
                <User className="absolute left-3.5 top-1/2 -translate-y-1/2 text-neutral-500" size={18} />
                <input
                  type="text"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder="Choose a username"
                  autoComplete="username"
                  required
                  className="w-full bg-surface text-white placeholder-neutral-500 border border-white/10 rounded-xl py-3 pl-11 pr-4 text-sm focus:outline-none focus:border-brand transition-colors"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs uppercase font-bold tracking-wider text-neutral-400 mb-1.5">
                Email Address
              </label>
              <div className="relative">
                <Mail className="absolute left-3.5 top-1/2 -translate-y-1/2 text-neutral-500" size={18} />
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="name@example.com"
                  autoComplete="email"
                  required
                  className="w-full bg-surface text-white placeholder-neutral-500 border border-white/10 rounded-xl py-3 pl-11 pr-4 text-sm focus:outline-none focus:border-brand transition-colors"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs uppercase font-bold tracking-wider text-neutral-400 mb-1.5">
                Password
              </label>
              <div className="relative">
                <Lock className="absolute left-3.5 top-1/2 -translate-y-1/2 text-neutral-500" size={18} />
                <input
                  type={showPassword ? 'text' : 'password'}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="At least 8 characters"
                  autoComplete="new-password"
                  required
                  className="w-full bg-surface text-white placeholder-neutral-500 border border-white/10 rounded-xl py-3 pl-11 pr-11 text-sm focus:outline-none focus:border-brand transition-colors"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3.5 top-1/2 -translate-y-1/2 text-neutral-500 hover:text-white transition-colors"
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                >
                  {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                </button>
              </div>
            </div>

            <button
              type="submit"
              disabled={isLoading}
              className="w-full bg-brand hover:bg-brand-hover active:bg-brand-active text-black font-bold py-3.5 px-6 rounded-full text-sm transition-all duration-200 hover:scale-[1.02] active:scale-[0.98] shadow-lg shadow-brand/20 disabled:opacity-50 flex items-center justify-center gap-2 mt-6"
            >
              {isLoading ? (
                <span className="w-5 h-5 border-2 border-black/30 border-t-black rounded-full animate-spin" />
              ) : (
                <>
                  <span>Create Account</span>
                  <ArrowRight size={16} />
                </>
              )}
            </button>
          </form>
        </div>

        {/* Footer Link to Login */}
        <p className="text-center text-sm text-neutral-400 mt-8">
          Already have an account?{' '}
          <Link to="/login" className="text-white hover:text-brand font-bold transition-colors underline-offset-4 hover:underline">
            Log in here
          </Link>
        </p>
      </div>
    </div>
  );
};

export default Signup;
