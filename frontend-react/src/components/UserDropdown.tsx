import React, { useState, useRef, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ExternalLink } from 'lucide-react';

interface UserDropdownProps {
  user: any;
  onLogout: () => void;
}

const UserDropdown: React.FC<UserDropdownProps> = ({ user, onLogout }) => {
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const navigate = useNavigate();

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    if (isOpen) {
      document.addEventListener('mousedown', handleClickOutside);
    }

    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [isOpen]);

  const menuItems = [
    { 
      label: 'Profile', 
      icon: null, 
      onClick: () => { navigate('/profile'); setIsOpen(false); },
      separator: true 
    },
    { 
      label: 'Settings', 
      icon: null, 
      onClick: () => { navigate('/settings'); setIsOpen(false); },
      separator: false 
    },
    { 
      label: 'Log out', 
      icon: null, 
      onClick: () => { onLogout(); setIsOpen(false); },
      separator: false 
    },
  ];

  return (
    <div className="relative" ref={dropdownRef}>
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="w-8 h-8 rounded-full bg-pink-500 text-white font-bold text-sm flex items-center justify-center shadow-lg hover:scale-105 active:scale-95 transition-all duration-200 border border-white/10"
      >
        {user?.username?.[0]?.toUpperCase() || 'A'}
      </button>

      {isOpen && (
        <div className="absolute top-10 right-0 z-[100] w-48 bg-[#282828] p-1 rounded-md shadow-[0_16px_24px_rgba(0,0,0,0.5)] border border-white/5 animate-in fade-in zoom-in-95 duration-100 origin-top-right">
          {menuItems.map((item, index) => (
            <React.Fragment key={index}>
              <button
                onClick={item.onClick}
                className="w-full text-left px-3 py-3 text-sm font-medium text-white hover:bg-[#3e3e3e] flex items-center justify-between transition-colors rounded-sm"
              >
                <span>{item.label}</span>
                {item.icon}
              </button>
              {item.separator && <hr className="border-white/5 my-1 mx-2" />}
            </React.Fragment>
          ))}
        </div>
      )}
    </div>
  );
};

export default UserDropdown;
