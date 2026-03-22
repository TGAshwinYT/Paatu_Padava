import React, { useState } from 'react';
import { useAuth } from '../context/AuthContext';
import { Link, useNavigate } from 'react-router-dom';
import { Music, Eye, EyeOff } from 'lucide-react';

const Login = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const { login, isLoading } = useAuth();
  const [error, setError] = useState('');
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    // Frontend Validation
    if (password.length < 8 || password.length > 128) {
        setError('Password must be between 8 and 128 characters');
        return;
    }

    try {
      await login(email, password);
      navigate('/');
    } catch (err: any) {
      setError(err.response?.data?.detail || 'An error occurred. Please try again.');
    }
  };

  return (
    <div className="flex flex-col items-center justify-center min-h-[80vh] bg-neutral-900">
      <div className="bg-[#181818] w-full max-w-md rounded-xl p-8 shadow-2xl">
        <div className="flex items-center gap-2 justify-center mb-8">
          <div className="p-2 bg-green-500 rounded-lg">
            <Music size={32} className="text-black" />
          </div>
          <h1 className="text-3xl font-bold">Paatu Paaduva</h1>
        </div>

        <h2 className="text-2xl font-bold mb-6 text-center">Log in to continue</h2>

        {error && (
          <div className="bg-red-500/10 border border-red-500/20 text-red-500 p-3 rounded-lg mb-6 text-sm text-center">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-400 mb-1">Email address</label>
            <input 
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="name@example.com"
              className="w-full bg-[#282828] border-none rounded-lg p-3 text-white focus:ring-2 focus:ring-green-500 transition-all outline-none"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-400 mb-1">Password</label>
            <div className="relative">
                <input 
                type={showPassword ? "text" : "password"}
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                className="w-full bg-[#282828] border-none rounded-lg p-3 pr-12 text-white focus:ring-2 focus:ring-green-500 transition-all outline-none"
                />
                <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-white transition-colors"
                >
                {showPassword ? <EyeOff size={20} /> : <Eye size={20} />}
                </button>
            </div>
          </div>

          <button 
            type="submit"
            disabled={isLoading}
            className="w-full bg-green-500 text-black font-bold p-3 rounded-full hover:scale-105 transition-transform disabled:opacity-50 mt-4"
          >
            {isLoading ? 'Processing...' : 'Log In'}
          </button>
        </form>

        <p className="text-gray-400 text-center mt-6 text-sm">
          Don't have an account?{' '}
          <Link to="/signup" className="text-white font-bold hover:underline">
            Sign up for free
          </Link>
        </p>
      </div>
    </div>
  );
};

export default Login;
