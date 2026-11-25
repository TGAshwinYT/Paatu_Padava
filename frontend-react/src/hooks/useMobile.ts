import { useState, useEffect } from 'react';

const buildMediaQuery = (breakpoint: number) =>
  `(max-width: ${breakpoint - 1}px) and (pointer: coarse), (max-width: 639px)`;

export const useMobile = (breakpoint: number = 768) => {
  const [isMobile, setIsMobile] = useState<boolean>(() => {
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') {
      return false;
    }
    return window.matchMedia(buildMediaQuery(breakpoint)).matches;
  });

  useEffect(() => {
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') {
      return;
    }
    const mql = window.matchMedia(buildMediaQuery(breakpoint));
    const handleChange = (e: MediaQueryListEvent) => setIsMobile(e.matches);

    mql.addEventListener('change', handleChange);
    return () => mql.removeEventListener('change', handleChange);
  }, [breakpoint]);

  return isMobile;
};
