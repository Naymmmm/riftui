import { defineConfig } from 'vite'
import { revision } from './scripts/revision.mjs'
import { riftHttpProxy } from './scripts/http-proxy.mjs'

export default defineConfig({
  appType: 'mpa',
  define: { __RIFT_REVISION__: JSON.stringify(revision()) },
  plugins: [{
    name: 'rift-simulator-route',
    configureServer(server) {
      // Resolve the directory entry before Vite's SPA fallback serves the docs.
      server.middlewares.use((req, _res, next) => {
        const [path, query] = (req.url || '').split('?')
        if (['/simulator', '/simulator/', '/simuilator', '/simuilator/'].includes(path)) {
          req.url = '/simulator/index.html' + (query ? '?' + query : '')
        }
        next()
      })
    },
    configurePreviewServer(server) {
      server.middlewares.use((req, _res, next) => {
        const [path, query] = (req.url || '').split('?')
        if (['/simulator', '/simulator/', '/simuilator', '/simuilator/'].includes(path)) {
          req.url = '/simulator/index.html' + (query ? '?' + query : '')
        }
        next()
      })
    },
  }, riftHttpProxy()],
  build: { target: 'es2022', rollupOptions: { input: { docs: 'index.html', simulator: 'simulator/index.html', preview: 'docs/preview.html', banner: 'docs/banner.html' } } },
  esbuild: { target: 'es2022' },
  optimizeDeps: { exclude: ['luau-web'], esbuildOptions: { target: 'es2022' } },
  server: { port: 5199 },
})
