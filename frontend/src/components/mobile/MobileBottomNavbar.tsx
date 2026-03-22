import React from 'react';
import { NavLink } from 'react-router-dom';
import { Home, Search, Library, User } from 'lucide-react';

const MobileBottomNavbar: React.FC = () => {
  return (
    <div className="fixed bottom-0 left-0 right-0 bg-gradient-to-t from-black via-black/95 to-transparent h-24 flex items-center justify-around px-6 z-40 border-t border-white/5 pb-6">
      <NavLink 
        to="/" 
        className={({ isActive }) => `flex flex-col items-center gap-1 ${isActive ? 'text-white' : 'text-neutral-500'}`}
      >
        <Home size={24} className="transition-all" strokeWidth={2.5} />
        <span className="text-[10px] font-bold">Home</span>
      </NavLink>

      <NavLink 
        to="/search" 
        className={({ isActive }) => `flex flex-col items-center gap-1 ${isActive ? 'text-white' : 'text-neutral-500'}`}
      >
        <Search size={24} />
        <span className="text-[10px] font-medium">Search</span>
      </NavLink>

      <NavLink 
        to="/library" 
        className={({ isActive }) => `flex flex-col items-center gap-1 ${isActive ? 'text-white' : 'text-neutral-500'}`}
      >
        <Library size={24} />
        <span className="text-[10px] font-medium">Library</span>
      </NavLink>

      <NavLink 
        to="/settings" 
        className={({ isActive }) => `flex flex-col items-center gap-1 ${isActive ? 'text-white' : 'text-neutral-500'}`}
      >
        <User size={24} />
        <span className="text-[10px] font-medium">Profile</span>
      </NavLink>
    </div>
  );
};

export default MobileBottomNavbar;
