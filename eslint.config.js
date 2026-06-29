import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import { defineConfig, globalIgnores } from 'eslint/config'

export default defineConfig([
  // The ESLint config targets the React SPA in src/ only. Without ignoring the
  // sibling stacks' build artifacts, `npm run lint` scans minified Flutter web
  // output (mobile-app/build), Dart tooling (.dart_tool) and the Node gateway,
  // producing ~22k spurious errors that drown out real findings and make lint
  // useless in CI. Ignore everything that isn't the SPA source.
  globalIgnores([
    'dist',
    'mobile-app',
    'backend',
    'supabase',
    '**/build/**',
    '**/.dart_tool/**',
  ]),
  {
    files: ['**/*.{js,jsx}'],
    extends: [
      js.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      ecmaVersion: 2020,
      globals: globals.browser,
      parserOptions: {
        ecmaVersion: 'latest',
        ecmaFeatures: { jsx: true },
        sourceType: 'module',
      },
    },
    rules: {
      'no-unused-vars': ['error', { varsIgnorePattern: '^[A-Z_]' }],
    },
  },
])
