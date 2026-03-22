import React from 'react';
import LikedSongs from '../LikedSongs';

const MobileLibrary: React.FC = () => {
  return (
    <div className="p-4 pt-12">
      <h1 className="text-3xl font-bold mb-6">Your Library</h1>
      <LikedSongs />
    </div>
  );
};

export default MobileLibrary;
