import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/recommendations': { target: 'http://localhost:8080', changeOrigin: true },
      '/places': { target: 'http://localhost:8080', changeOrigin: true },
      '/cuisines': { target: 'http://localhost:8080', changeOrigin: true },
      '/health': { target: 'http://localhost:8080', changeOrigin: true },
    },
  },
})
