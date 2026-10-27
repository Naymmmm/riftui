import { defineConfig } from 'vite'
import { riftHttpProxy } from './scripts/http-proxy.mjs'

export default defineConfig({
  plugins: [riftHttpProxy()],
  build: { target: 'es2022', rollupOptions: { input: { docs: 'index.html', simulator: 'simulator/index.html', preview: 'docs/preview.html' } } },
  esbuild: { target: 'es2022' },
  optimizeDeps: { exclude: ['luau-web'], esbuildOptions: { target: 'es2022' } },
  server: { port: 5199 },
})
