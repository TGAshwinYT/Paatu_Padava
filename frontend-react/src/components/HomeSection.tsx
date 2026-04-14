import React from 'react';
import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';

interface HomeSectionProps {
  title: string;
  showAllLink?: string;
  rightElement?: ReactNode;
  children: ReactNode;
  className?: string;
}

const HomeSection: React.FC<HomeSectionProps> = ({ title, showAllLink, rightElement, children, className = "" }) => {
  return (
    <section className={`w-full ${className}`}>
      <div className="flex items-center justify-between mb-4 pr-4">
        <h2 className="text-2xl font-bold text-white hover:underline cursor-pointer">
          {showAllLink ? <Link to={showAllLink}>{title}</Link> : title}
        </h2>
        {rightElement ? (
          rightElement
        ) : (
          showAllLink && (
            <Link 
              to={showAllLink} 
              className="text-sm font-bold text-[#a7a7a7] hover:text-white transition-colors duration-200"
            >
              Show all
            </Link>
          )
        )}
      </div>
      {children}
    </section>
  );
};

export default HomeSection;
