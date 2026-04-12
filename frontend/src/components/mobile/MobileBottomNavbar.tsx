import React from 'react';
import { NavLink } from 'react-router-dom';
import { Home, Search, Library } from 'lucide-react';

const MobileBottomNavbar: React.FC = () => {
  return (
    <nav className="fixed bottom-0 left-0 right-0 h-[calc(64px+env(safe-area-inset-bottom))] bg-black/80 backdrop-blur-lg flex justify-around items-center border-t border-white/10 px-6 z-50 pb-[env(safe-area-inset-bottom)]">
      <NavLink 
        to="/" 
        className={({ isActive }) => `flex flex-col items-center gap-1 transition-colors ${isActive ? 'text-white' : 'text-neutral-500'}`}
      >
        {({ isActive }) => (
          <>
            <Home size={24} strokeWidth={isActive ? 2.5 : 2} />
            <span className="text-[10px] font-bold">Home</span>
          </>
        )}
      </NavLink>

      <NavLink 
        to="/search" 
        className={({ isActive }) => `flex flex-col items-center gap-1 transition-colors ${isActive ? 'text-white' : 'text-neutral-500'}`}
      >
        {({ isActive }) => (
          <>
            <Search size={24} strokeWidth={isActive ? 2.5 : 2} />
            <span className="text-[10px] font-medium">Search</span>
          </>
        )}
      </NavLink>

      <NavLink 
        to="/library" 
        className={({ isActive }) => `flex flex-col items-center gap-1 transition-colors ${isActive ? 'text-white' : 'text-neutral-500'}`}
      >
        {({ isActive }) => (
          <>
            <Library size={24} strokeWidth={isActive ? 2.5 : 2} />
            <span className="text-[10px] font-medium">Library</span>
          </>
        )}
      </NavLink>
    </nav>
  );
};

export default MobileBottomNavbar;
