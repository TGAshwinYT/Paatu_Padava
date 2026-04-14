import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Music, ArrowLeft, CheckCircle } from 'lucide-react';
import api from '../services/api';

const ForgotPassword = () => {
  const [step, setStep] = useState(1);
  const [email, setEmail] = useState('');
  const [otp, setOtp] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const navigate = useNavigate();

  const handleRequestOTP = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    setError('');
    setMessage('');

    try {
      await api.post('/api/auth/forgot-password', { email });
      setMessage('OTP sent to your email (check server terminal).');
      setStep(2);
    } catch (err: any) {
      setError(err.response?.data?.detail || 'An error occurred. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleResetPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    setError('');

    try {
      await api.post('/api/auth/reset-password', { 
        email, 
        otp, 
        new_password: newPassword 
      });
      setMessage('Password updated successfully! You can now log in.');
      setStep(3); // Success step
    } catch (err: any) {
      setError(err.response?.data?.detail || 'Invalid or expired OTP. Please try again.');
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

        {step === 1 && (
          <>
            <h2 className="text-2xl font-bold mb-2 text-center">Reset your password</h2>
            <p className="text-gray-400 text-center mb-8 text-sm px-4">
              Enter your email address and we'll send you a 6-digit OTP to reset your password.
            </p>

            {error && (
              <div className="bg-red-500/10 border border-red-500/20 text-red-500 p-3 rounded-lg mb-6 text-sm text-center">
                {error}
              </div>
            )}

            <form onSubmit={handleRequestOTP} className="space-y-4">
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
                {isLoading ? 'Sending...' : 'Send OTP'}
              </button>
            </form>
          </>
        )}

        {step === 2 && (
          <>
            <h2 className="text-2xl font-bold mb-2 text-center">Verify OTP</h2>
            <p className="text-gray-400 text-center mb-8 text-sm px-4">
              We've sent a code to <span className="text-white font-medium">{email}</span>. Please enter it below along with your new password.
            </p>

            {error && (
              <div className="bg-red-500/10 border border-red-500/20 text-red-500 p-3 rounded-lg mb-6 text-sm text-center">
                {error}
              </div>
            )}

            <form onSubmit={handleResetPassword} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-400 mb-1">6-Digit OTP</label>
                <input 
                  type="text"
                  required
                  maxLength={6}
                  value={otp}
                  onChange={(e) => setOtp(e.target.value)}
                  placeholder="123456"
                  className="w-full bg-[#282828] border-none rounded-lg p-3 text-white tracking-[0.5em] text-center font-bold text-lg focus:ring-2 focus:ring-green-500 transition-all outline-none"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-400 mb-1">New Password</label>
                <input 
                  type="password"
                  required
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  placeholder="••••••••"
                  className="w-full bg-[#282828] border-none rounded-lg p-3 text-white focus:ring-2 focus:ring-green-500 transition-all outline-none"
                />
              </div>

              <button 
                type="submit"
                disabled={isLoading}
                className="w-full bg-green-500 text-black font-bold p-3 rounded-full hover:scale-105 transition-transform disabled:opacity-50 mt-4"
              >
                {isLoading ? 'Processing...' : 'Reset Password'}
              </button>
              
              <button 
                type="button"
                onClick={() => setStep(1)}
                className="w-full text-gray-400 hover:text-white transition-colors text-sm font-medium mt-2"
              >
                Change email
              </button>
            </form>
          </>
        )}

        {step === 3 && (
          <div className="text-center py-6">
            <div className="flex justify-center mb-4">
                <CheckCircle size={48} className="text-green-500" />
            </div>
            <p className="text-white font-medium mb-8">{message}</p>
            <button 
              onClick={() => navigate('/login')}
              className="w-full bg-green-500 text-black font-bold p-3 rounded-full hover:scale-105 transition-transform"
            >
              Go to Login
            </button>
          </div>
        )}

        {step !== 3 && (
          <div className="mt-8 pt-6 border-t border-white/5 text-center">
            <Link to="/login" className="inline-flex items-center gap-2 text-gray-400 hover:text-white transition-colors text-sm font-medium">
              <ArrowLeft size={16} />
              Back to Login
            </Link>
          </div>
        )}
      </div>
    </div>
  );
};

export default ForgotPassword;
