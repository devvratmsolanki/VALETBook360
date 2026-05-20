import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Vendor split keeps the initial JS payload small by isolating libraries
// that the operator/driver pages don't all need on first paint. Admin-only
// chunks like qrcode also get split via React.lazy on the route side.
const VENDOR_CHUNKS = {
  'vendor-react': ['react', 'react-dom', 'react-router-dom'],
  'vendor-supabase': ['@supabase/supabase-js'],
  'vendor-icons': ['lucide-react'],
  'vendor-qrcode': ['qrcode'],
}

export default defineConfig({
  plugins: [react()],
  build: {
    sourcemap: false,
    // Stripping these in production avoids leaking auth/notification noise to
    // end-user devtools while keeping `console.error` for crash diagnostics.
    // The logger in src/lib/logger.js routes structured logs through this same
    // gating, so dev-only diagnostics disappear at build time.
    rollupOptions: {
      output: {
        // Only split well-known heavy packages. Letting the catch-all
        // node_modules bucket exist creates a circular import with the
        // react chunk because shared scheduler/jsx helpers end up in
        // both; Rollup's default bucketing handles the long tail safely.
        manualChunks(id) {
          if (id.includes('node_modules')) {
            for (const [name, pkgs] of Object.entries(VENDOR_CHUNKS)) {
              if (pkgs.some((p) => id.includes(`/node_modules/${p}/`))) return name
            }
          }
        },
      },
    },
  },
  esbuild: {
    // Drop debug-level logs from production but keep warn/error.
    drop: ['debugger'],
    pure: ['console.debug'],
  },
})
