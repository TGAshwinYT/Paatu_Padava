import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    host: true, // Listen on all addresses
    strictPort: true,
    hmr: {
      clientPort: 5173,
    },
  },
  build: {
    chunkSizeWarningLimit: 1600,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules')) {
             if (id.includes('lucide-react')) return 'lucide';
             if (id.includes('swiper')) return 'swiper';
             if (id.includes('axios')) return 'axios';
             return 'vendor';
          }
        }
      }
    }
  }
})
