import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { Music, ArrowLeft, CheckCircle } from 'lucide-react';
import api from '../services/api';

const ForgotPassword = () => {
  const [email, setEmail] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    setError('');
    setMessage('');

    try {
      await api.post('/api/auth/forgot-password', { email });
      setMessage('If an account exists with this email, a reset link has been sent to the server terminal.');
    } catch (err: any) {
      setError(err.response?.data?.detail || 'An error occurred. Please try again.');
    } finally {
      setIsLoading(false);
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

        <h2 className="text-2xl font-bold mb-2 text-center">Reset your password</h2>
        <p className="text-gray-400 text-center mb-8 text-sm px-4">
          Enter your email address and we'll send you a link to reset your password.
        </p>

        {message ? (
          <div className="text-center py-6">
            <div className="flex justify-center mb-4">
                <CheckCircle size={48} className="text-green-500" />
            </div>
            <p className="text-white font-medium mb-6">{message}</p>
            <Link to="/login" className="inline-flex items-center gap-2 text-green-500 font-bold hover:underline">
                <ArrowLeft size={16} />
                Back to Login
            </Link>
          </div>
        ) : (
          <>
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

              <button 
                type="submit"
                disabled={isLoading}
                className="w-full bg-green-500 text-black font-bold p-3 rounded-full hover:scale-105 transition-transform disabled:opacity-50 mt-4"
              >
                {isLoading ? 'Sending...' : 'Send Reset Link'}
              </button>
            </form>

            <div className="mt-8 pt-6 border-t border-white/5 text-center">
                <Link to="/login" className="inline-flex items-center gap-2 text-gray-400 hover:text-white transition-colors text-sm font-medium">
                    <ArrowLeft size={16} />
                    Back to Login
                </Link>
            </div>
          </>
        )}
      </div>
    </div>
  );
};

export default ForgotPassword;
