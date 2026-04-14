import React from 'react';
import { useNavigate } from 'react-router-dom';
import { Library, X } from 'lucide-react';

interface LibraryAuthModalProps {
  isOpen: boolean;
  onClose: () => void;
}

const LibraryAuthModal: React.FC<LibraryAuthModalProps> = ({ isOpen, onClose }) => {
  const navigate = useNavigate();

  if (!isOpen) return null;

  const handleLogin = () => {
    onClose();
    navigate('/login');
  };

  return (
    <div className="fixed inset-0 bg-black/80 backdrop-blur-sm z-[100] flex items-center justify-center p-4">
      <div 
        className="bg-[#282828] w-full max-w-sm rounded-xl p-8 relative animate-in fade-in zoom-in duration-300 shadow-2xl border border-white/5"
        onClick={(e) => e.stopPropagation()}
      >
        <button 
          onClick={onClose}
          className="absolute right-4 top-4 text-neutral-500 hover:text-white transition-colors"
        >
          <X size={20} />
        </button>

        <div className="flex flex-col items-center text-center">
          <div className="p-4 bg-green-500/10 rounded-full mb-6">
            <Library size={48} className="text-green-500" />
          </div>

          <h2 className="text-2xl font-bold mb-3 text-white">Enjoy your Library</h2>
          <p className="text-neutral-400 mb-8 text-sm leading-relaxed">
            Create a playlist or like a song to save it here. You'll need an account to do that.
          </p>

          <div className="flex flex-col w-full gap-3">
            <button 
              onClick={handleLogin}
              className="w-full bg-white text-black font-bold py-3 px-6 rounded-full hover:scale-105 transition-transform active:scale-95"
            >
              Log in
            </button>
            <button 
              onClick={onClose}
              className="w-full text-neutral-400 hover:text-white transition-colors font-bold py-2 text-sm"
            >
              Not now
            </button>
          </div>
        </div>
      </div>
      
      {/* Click outside to close */}
      <div className="absolute inset-0 -z-10" onClick={onClose} />
    </div>
  );
};

export default LibraryAuthModal;
