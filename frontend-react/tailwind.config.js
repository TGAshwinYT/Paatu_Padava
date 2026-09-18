/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: 'var(--color-brand)',
          hover: 'var(--color-brand-hover)',
          active: 'var(--color-brand-active)',
        },
        surface: {
          DEFAULT: 'var(--color-surface)',
          base: 'var(--color-bg-base)',
          card: 'var(--color-surface-card)',
          hover: 'var(--color-surface-hover)',
          active: 'var(--color-surface-active)',
        },
        muted: {
          DEFAULT: 'var(--color-text-secondary)',
          subtle: 'var(--color-text-muted)',
        },
        border: {
          subtle: 'var(--color-border-subtle)',
          DEFAULT: 'var(--color-border-default)',
        },
      },
    },
  },
  plugins: [],
}
