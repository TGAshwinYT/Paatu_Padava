import React, { useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Music, Eye, EyeOff, Lock } from 'lucide-react';
import api from '../services/api';

const ResetPassword = () => {
  const [searchParams] = useSearchParams();
  const token = searchParams.get('token');
  const [newPassword, setNewPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState('');
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) {
        setError('Invalid or missing reset token.');
        return;
    }

    if (newPassword.length < 8) {
        setError('Password must be at least 8 characters long.');
        return;
    }

    setIsLoading(true);
    setError('');

    try {
      await api.post('/api/auth/reset-password', { 
        token, 
        new_password: newPassword 
      });
      alert('Password updated successfully! Please log in.');
      navigate('/login');
    } catch (err: any) {
      setError(err.response?.data?.detail || 'An error occurred. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  if (!token) {
      return (
        <div className="flex flex-col items-center justify-center min-h-[80vh] text-center p-6">
            <h1 className="text-2xl font-bold text-red-500 mb-4">Invalid Reset Link</h1>
            <p className="text-neutral-400 mb-8 max-w-md">This password reset link is invalid or has expired. Please request a new one.</p>
            <button 
                onClick={() => navigate('/forgot-password')}
                className="bg-white text-black font-bold px-8 py-3 rounded-full hover:scale-105 transition-transform"
            >
                Request New Link
            </button>
        </div>
      );
  }

  return (
    <div className="flex flex-col items-center justify-center min-h-[80vh] bg-neutral-900">
      <div className="bg-[#181818] w-full max-w-md rounded-xl p-8 shadow-2xl">
        <div className="flex items-center gap-2 justify-center mb-8">
          <div className="p-2 bg-green-500 rounded-lg">
            <Music size={32} className="text-black" />
          </div>
          <h1 className="text-3xl font-bold">Paatu Paaduva</h1>
        </div>

        <h2 className="text-2xl font-bold mb-6 text-center">Set new password</h2>

        {error && (
          <div className="bg-red-500/10 border border-red-500/20 text-red-500 p-3 rounded-lg mb-6 text-sm text-center">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-6">
          <div>
            <label className="block text-sm font-medium text-gray-400 mb-1">New Password</label>
            <div className="relative">
                <input 
                    type={showPassword ? "text" : "password"}
                    required
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    placeholder="Enter new password"
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
            className="w-full bg-green-500 text-black font-bold p-3 rounded-full hover:scale-105 transition-transform disabled:opacity-50 flex items-center justify-center gap-2"
          >
            <Lock size={18} />
            {isLoading ? 'Updating...' : 'Update Password'}
          </button>
        </form>
      </div>
    </div>
  );
};

export default ResetPassword;
