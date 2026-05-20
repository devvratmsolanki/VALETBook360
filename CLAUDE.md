# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `npm run dev` — Vite dev server.
- `npm run build` — production build to `dist/` (sourcemaps disabled in [vite.config.js](vite.config.js)).
- `npm run lint` — ESLint over `**/*.{js,jsx}`. The flat config enforces `no-unused-vars` but ignores identifiers that start with an uppercase letter or `_` ([eslint.config.js](eslint.config.js)).
- `npm run preview` — serve the production build locally.

There is no test runner configured.

Required env vars are in [.env.example](.env.example): `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, optional `VITE_ENABLE_WHATSAPP`, `VITE_N8N_WEBHOOK_URL`, `VITE_API_TIMEOUT_MS`. If the Supabase URL/key are missing or still the placeholder value, [src/lib/supabase.js](src/lib/supabase.js) swaps in a mock client so the app boots in "demo mode" — sign-in will reject with an explanatory error.

The Flutter driver companion app lives in [mobile-app/](mobile-app/) and is independent of the web build.

## Architecture

### Single-page React app with Supabase backend
React 19 + Vite + Tailwind v4 SPA. The entire backend is Supabase: Postgres (RLS-protected), Auth, Realtime channels, Storage, and Edge Functions. There is no Node/Express server. Auth session is intentionally kept in `sessionStorage` rather than `localStorage` ([src/lib/supabase.js](src/lib/supabase.js#L11)).

### Role model — code names differ from DB names
[src/App.jsx](src/App.jsx) carries an authoritative comment: the database `users.role` column stores `admin`, `manager`, `valet` (plus `driver`), but the frontend everywhere treats them as `admin` / `company` / `valet` / `driver`. `company` in the UI corresponds to `manager` in the DB. When wiring new routes or queries, match whichever side you are touching — don't normalise without checking the other end.

Routing is gated by `<ProtectedRoute allowedRoles={[...]}>` and a top-level `<AuthGate>` that redirects to `/admin`, `/company`, `/driver`, or `/operator` based on role. Admin can reach everything; `company` can reach operator/driver routes; `valet` is mostly confined to `/operator` and `/driver`.

### AuthContext auto-provisions profiles
[src/contexts/AuthContext.jsx](src/contexts/AuthContext.jsx) fetches `users` joined with `valet_companies` and `location`. If no row exists for the authenticated user it auto-creates one in `users`; the **first user ever created becomes `admin`**, everyone after becomes `valet`. There is also a fallback fetch that drops the `location_id` join — this exists so the app keeps working against older schemas missing that column. Keep that fallback in mind before refactoring the join.

### Service layer wraps every Supabase call
All DB access goes through [src/services/](src/services/) (`transactionService`, `locationService`, `driverService`, `slotService`, `userService`, etc.). UI components should not call `supabase.from(...)` directly. Two recurring conventions inside services:

1. **camelCase → snake_case mapping.** Service inputs accept camelCase (`companyId`, `locationId`, `keyCode`), and the service builds the snake_case payload before insert/update. See `createTransaction` in [src/services/transactionService.js:50-71](src/services/transactionService.js#L50-L71) and `createSlot` in [src/services/slotService.js:14-28](src/services/slotService.js#L14-L28).
2. **Realtime subscriptions** are exposed as `subscribeTo*` helpers that return a Supabase channel — callers are responsible for `unsubscribe()` in their effect cleanup.

### Transaction state machine
The canonical lifecycle is `STATUS_FLOW` in [src/services/transactionService.js:8-11](src/services/transactionService.js#L8-L11):
`waiting_for_driver → parked → key_in → requested → driver_assigned → en_route → arrived → delivered` (or `cancelled`). `updateTransactionStatus` automatically stamps the matching timestamp column when transitioning to `requested`, `arrived`, or `delivered`. Helpers (`confirmKeyIn`, `assignDriverForRetrieval`, `markEnRoute`, `markArrived`) exist so UI never builds raw status strings — use them instead of calling `updateTransactionStatus` directly.

`getTransactionStats` collapses these statuses into operator-friendly buckets (`waiting`, `parked`, `requested`, `ready`, `delivered`). When adding a new status, update both `STATUS_FLOW` and that aggregation.

### Key slots — two-mode allocation
`getNextAvailableKeySlot` in [src/services/transactionService.js:160-199](src/services/transactionService.js#L160-L199) first looks for custom slots in `key_slots` for the location; if none exist, it falls back to numeric slots `1..locations.key_capacity`. Active-transaction occupancy is checked against the same status whitelist as `getActiveTransactions`. The mode (custom vs numeric) is determined per location, not globally.

### Timestamp parsing pitfall
Supabase sometimes returns timestamps without a timezone marker, which JS then misinterprets as local time. Always format timestamps through `parseUTC` / `formatTime` / `formatDate` / `formatDateTime` in [src/lib/utils.js](src/lib/utils.js) rather than `new Date(string)` directly.

### WhatsApp / Yeti notifications go through an Edge Function
[src/services/webhookService.js](src/services/webhookService.js) does **not** call Yeti directly — it `POST`s to the `send-whatsapp` Edge Function in [supabase/functions/send-whatsapp/index.ts](supabase/functions/send-whatsapp/index.ts), which performs the API-key → JWT exchange against Yeti and caches the JWT in module-level memory. The browser never sees Yeti credentials. When adding a new notification, define a sender in `webhookService.js` and a matching template name; do not bypass the edge function.

Other edge functions:
- `create-staff` — service-role insert of new users (admin/company creating staff accounts).
- `request-car` — guest-facing car retrieval endpoint.
- `whatsapp-webhook` — inbound webhook receiver.

### Styling
Tailwind v4 via PostCSS. Custom palettes `brand-*` (pink/magenta) and `dark-*` plus a few keyframes live in [tailwind.config.js](tailwind.config.js). Dark mode is class-based and toggled through [src/contexts/ThemeContext.jsx](src/contexts/ThemeContext.jsx). Compose conditional class strings with `cn(...)` from [src/lib/utils.js](src/lib/utils.js) (clsx + tailwind-merge), not manual string concatenation.

### Page layout
[src/components/layout/Layout.jsx](src/components/layout/Layout.jsx) wraps every protected route with `<Sidebar>` + `<Header>`. The sidebar's nav items come from one of three hardcoded arrays in [src/components/layout/Sidebar.jsx](src/components/layout/Sidebar.jsx) (`operatorNav` / `companyNav` / `adminNav`) selected by `role` — add new routes there as well as in `App.jsx`.
