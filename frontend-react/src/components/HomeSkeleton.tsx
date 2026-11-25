import React from 'react';

const HomeSkeleton: React.FC = () => (
  <div className="flex flex-col gap-10 pb-24 pt-2 animate-pulse" aria-label="Loading home feed">
    <section className="relative -mx-6 px-6 pt-6 pb-10 bg-gradient-to-b from-brand/10 to-surface-base">
      <div className="h-8 w-48 bg-neutral-800 rounded-lg mb-8" />
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {Array.from({ length: 8 }).map((_, i) => (
          <div key={i} className="h-16 bg-neutral-800/80 rounded-lg flex items-center gap-3 p-2">
            <div className="w-12 h-12 bg-neutral-700 rounded" />
            <div className="h-4 w-24 bg-neutral-700 rounded" />
          </div>
        ))}
      </div>
    </section>
    {Array.from({ length: 2 }).map((_, sIdx) => (
      <section key={sIdx} className="flex flex-col gap-4">
        <div className="h-6 w-40 bg-neutral-800 rounded" />
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4">
          {Array.from({ length: 5 }).map((__, cIdx) => (
            <div key={cIdx} className="p-3 rounded-xl bg-neutral-900/70 border border-white/5 flex flex-col gap-3">
              <div className="aspect-square w-full bg-neutral-800 rounded-lg" />
              <div className="h-4 w-3/4 bg-neutral-800 rounded" />
              <div className="h-3 w-1/2 bg-neutral-800/70 rounded" />
            </div>
          ))}
        </div>
      </section>
    ))}
  </div>
);

export default HomeSkeleton;
