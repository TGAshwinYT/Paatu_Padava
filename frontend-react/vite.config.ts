import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    host: true, 
    strictPort: true,
  },
  optimizeDeps: {
    include: ['react-youtube'],
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
             if (id.includes('react-youtube')) return 'youtube';
             return 'vendor';
          }
        }
      }
    }
  }
})
