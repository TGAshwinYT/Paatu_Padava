import React, { useState } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { Play, Plus, Heart, ListMusic, PlusCircle } from 'lucide-react';
import type { Song } from '../types';
import { useAudio } from '../context/AudioContext';
import { usePlaylistModal } from '../context/PlaylistModalContext';
import { useAuth } from '../context/AuthContext';
import { likeSong, unlikeSong } from '../services/api';

interface SongCardProps {
  song: Song;
  isInitiallyLiked?: boolean;
}

const SongCard: React.FC<SongCardProps> = ({ song, isInitiallyLiked = false }) => {
  const navigate = useNavigate();
  const location = useLocation();
  const { playTrack, addToQueue } = useAudio();
  const { openModal } = usePlaylistModal();
  const { user } = useAuth();
  const [isLiked, setIsLiked] = useState(isInitiallyLiked);
  const [showPlusMenu, setShowPlusMenu] = useState(false);

  const handleLikeToggle = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!user) {
      navigate("/login", { state: { from: location } });
      return;
    }
    
    if (isLiked) {
      await unlikeSong(song.id);
      setIsLiked(false);
    } else {
      await likeSong(song);
      setIsLiked(true);
    }
  };

  return (
    <div 
      className="bg-neutral-800/40 p-4 rounded-md hover:bg-neutral-700/50 transition-all duration-300 group cursor-pointer"
      onClick={() => playTrack(song)}
    >
      <div className="relative mb-4">
        <img 
          src={song.coverUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&h=500&fit=crop'} 
          alt={song.title} 
          className="w-full aspect-square object-cover rounded-md shadow-lg"
        />
        <div className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity">
           <button 
             onClick={handleLikeToggle}
             className="p-2 bg-neutral-900/60 backdrop-blur-md rounded-full text-white hover:scale-110 active:scale-95 transition"
           >
             <Heart size={18} fill={isLiked ? "#22c55e" : "transparent"} stroke={isLiked ? "#22c55e" : "currentColor"} />
           </button>
        </div>
        <div className="absolute bottom-2 right-2 flex gap-2 translate-y-2 opacity-0 group-hover:translate-y-0 group-hover:opacity-100 transition-all duration-300">
           <div className="relative">
             <button 
               className="p-3 bg-neutral-900/80 backdrop-blur-md rounded-full text-white hover:scale-105 border border-white/10"
               onClick={(e) => {
                 e.stopPropagation();
                 setShowPlusMenu(!showPlusMenu);
               }}
             >
               <Plus size={20} />
             </button>
             
             {showPlusMenu && (
               <div className="absolute bottom-full right-0 mb-2 w-48 bg-[#282828] rounded-lg shadow-2xl border border-white/10 py-1 overflow-hidden z-20 animate-in slide-in-from-bottom-2 duration-200">
                 <button 
                   onClick={(e) => {
                     e.stopPropagation();
                     addToQueue(song);
                     setShowPlusMenu(false);
                   }}
                   className="w-full flex items-center gap-3 px-4 py-2 text-sm text-neutral-300 hover:bg-neutral-700 hover:text-white transition-colors"
                 >
                   <ListMusic size={16} />
                   Add to Queue
                 </button>
                 <button 
                   onClick={(e) => {
                     e.stopPropagation();
                     openModal(song.id);
                     setShowPlusMenu(false);
                   }}
                   className="w-full flex items-center gap-3 px-4 py-2 text-sm text-neutral-300 hover:bg-neutral-700 hover:text-white transition-colors border-t border-white/5"
                 >
                   <PlusCircle size={16} />
                   Add to Playlist
                 </button>
               </div>
             )}
           </div>
           
           <button 
             className="p-3 bg-green-500 rounded-full text-black shadow-xl hover:scale-105"
             onClick={(e) => {
               e.stopPropagation();
               playTrack(song);
             }}
           >
             <Play fill="currentColor" size={20} />
           </button>
        </div>
      </div>
      <h3 className="font-semibold text-white truncate mb-1">{song.title}</h3>
      <p className="text-sm text-neutral-400 truncate">{song.artist}</p>
    </div>
  );
};

export default SongCard;
