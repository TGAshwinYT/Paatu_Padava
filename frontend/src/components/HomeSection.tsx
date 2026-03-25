import React from 'react';
import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';

interface HomeSectionProps {
  title: string;
  showAllLink?: string;
  children: ReactNode;
  className?: string;
}

const HomeSection: React.FC<HomeSectionProps> = ({ title, showAllLink, children, className = "" }) => {
  return (
    <section className={`w-full ${className}`}>
      <div className="flex items-center justify-between mb-4 pr-4">
        <h2 className="text-2xl font-bold text-white hover:underline cursor-pointer">
          {showAllLink ? <Link to={showAllLink}>{title}</Link> : title}
        </h2>
        {showAllLink && (
          <Link 
            to={showAllLink} 
            className="text-sm font-bold text-[#a7a7a7] hover:text-white transition-colors duration-200"
          >
            Show all
          </Link>
        )}
      </div>
      {children}
    </section>
  );
};

export default HomeSection;
