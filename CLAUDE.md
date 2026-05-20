# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `npm run dev` — Vite dev server.
- `npm run build` — production build to `dist/` (sourcemaps disabled in [vite.config.js](vite.config.js)).
- `npm run lint` — ESLint over `**/*.{js,jsx}`. Flat config enforces `no-unused-vars` but ignores identifiers starting with an uppercase letter or `_` ([eslint.config.js](eslint.config.js)). There's no JSX-aware `react/jsx-uses-vars` rule wired in — destructure-renamed components used only in JSX (e.g. `{ icon: Icon }` → `<Icon />`) will be flagged. Either don't rename, or stash the prop into a non-`Icon`-named local first.
- `npm run preview` — serve the production build locally.

There is no test runner configured.

Required env vars are in [.env.example](.env.example): `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, optional `VITE_ENABLE_WHATSAPP`, `VITE_N8N_WEBHOOK_URL`, `VITE_API_TIMEOUT_MS`. If the Supabase URL/key are missing or still the placeholder value, [src/lib/supabase.js](src/lib/supabase.js) swaps in a mock client so the app boots in "demo mode" — sign-in will reject with an explanatory error.

The Flutter driver companion app lives in [mobile-app/](mobile-app/) and is independent of the web build.

## Database migrations

SQL migrations live in [supabase/migrations/](supabase/migrations/) and are **not** auto-applied — the Supabase CLI isn't logged in. Run new ones manually via Supabase Dashboard → SQL Editor → paste & run. Existing migrations and what they install:

- `20260520_link_drivers_to_users.sql` — adds `drivers.user_id` (FK to `users.id`, unique when set) and `drivers.email`; backfills the link by matching `name + company`; rewrites the `valet_transactions` FKs to `parked_by_driver_id` / `retrieved_by_driver_id` to `ON DELETE SET NULL` so drivers can be removed without orphaning historical rows.
- `20260521_request_car_token.sql` — adds `valet_transactions.guest_request_token`. The `request-car` edge function requires this token alongside the plate to block plate-enumeration attacks; operators must mint one when creating each transaction.
- `20260522_hot_path_indexes.sql` — composite/partial indexes for the operator + driver query patterns (status×company×created_at, driver-id partial indexes, key_code lookup, visitor phone, car plate).

When adding new service queries, check that an index from `20260522` already covers the new access pattern before writing a new one.

## Architecture

### Single-page React app with Supabase backend
React 19 + Vite + Tailwind v4 SPA. The entire backend is Supabase: Postgres (RLS-protected), Auth, Realtime channels, Storage, and Edge Functions. There is no Node/Express server. Auth session is intentionally kept in `sessionStorage` rather than `localStorage` ([src/lib/supabase.js](src/lib/supabase.js#L11)).

### Role model — code names differ from DB names
[src/App.jsx](src/App.jsx) carries the comment, but in practice the database `users.role` column stores one of `admin`, `manager`, `valet`, `driver`, and the frontend everywhere treats them as `admin` / `company` / `valet` / `driver`. `company` in the UI corresponds to `manager` in the DB. When wiring new routes or queries, match whichever side you're touching — don't normalise without checking the other end.

Routing is gated by `<ProtectedRoute allowedRoles={[...]}>` and a top-level `<AuthGate>` that redirects to `/admin`, `/company`, `/driver`, or `/operator` based on role. The `ProtectedRoute` catch-all also handles drivers explicitly (`if (role === 'driver') return <Navigate to="/driver" />`) — without this drivers fall through to `/operator` and get bounced. If you add a new role, update both the catch-all and `AuthGate`.

### AuthContext — load order is load-bearing
[src/contexts/AuthContext.jsx](src/contexts/AuthContext.jsx) flips `loading` back to `true` at the start of the `SIGNED_IN` handler and only flips it back to `false` after `fetchProfile` resolves. **Do not remove this.** Without it, `user` is set before `profile`, the `role` getter falls back to `'valet'` (the default in the value object), and `AuthGate` routes drivers/companies to `/operator` during the gap — leading to silent blank-screen redirects.

`autoCreateProfile` runs when a logged-in auth user has no `public.users` row. It defaults the role to `'valet'` unless **zero admin rows exist anywhere in the table** — only then does it create an admin. The check is TOCTOU-prone (two concurrent first-signups could both win); the comment in the file calls this out and recommends a partial unique index on `(role='admin')` for true safety, which is not yet applied.

There's also a fallback fetch in `fetchProfile` that drops the `location_id` join — kept so the app still boots against older schemas. Don't refactor it away.

### Service layer wraps every Supabase call
All DB access goes through [src/services/](src/services/) (`transactionService`, `locationService`, `driverService`, `slotService`, `userService`, `companyService`, etc.). UI components should not call `supabase.from(...)` directly. Recurring conventions:

1. **camelCase → snake_case mapping.** Service inputs accept camelCase (`companyId`, `locationId`, `keyCode`); the service maps to snake_case before insert/update. See `createTransaction` in [src/services/transactionService.js:50-71](src/services/transactionService.js#L50-L71) and `createSlot` in [src/services/slotService.js:14-28](src/services/slotService.js#L14-L28).
2. **Realtime subscriptions** are exposed as `subscribeTo*` helpers that return a Supabase channel — callers must `unsubscribe()` in their effect cleanup.
3. **Composed services.** [companyService.createCompanyWithOwner](src/services/companyService.js) chains `createCompany` then `createStaff` (auth user + `users` row with `role='company'`) and **deletes the company row if the staff creation fails**, so the admin can retry the same email/name without unique-constraint conflicts. Mirror this rollback pattern for other multi-step creates.
4. **Pre-migration tolerance.** [driverService.deleteDriver](src/services/driverService.js) and `getDriverForUser` swallow "column does not exist" errors so the app keeps working before `20260520_link_drivers_to_users.sql` is applied. `deleteDriver` also nulls out `valet_transactions.parked_by_driver_id` / `retrieved_by_driver_id` references before the delete — keep doing this until the FK rewrite migration is universally applied.

### Errors and logging — use the helpers
- [src/lib/logger.js](src/lib/logger.js) — `debug`/`info`/`warn` become no-ops in `import.meta.env.PROD`; `error` always logs. Use `logger` instead of bare `console.log` so production consoles stay clean. `console.error` is still acceptable for hard failures.
- [src/lib/errors.js](src/lib/errors.js) — `ServiceError` carries a `userMessage` (toast-safe) plus the original `cause`. `wrapError(err, "Failed to load drivers")` maps common Postgres codes (`23505`, `23503`, `42501`, `PGRST116`) to friendly strings. Catchers should do `toast.error(err.userMessage || err.message)` so the user sees a real reason instead of a generic "Failed to ...".

### Transaction state machine
The canonical lifecycle is `STATUS_FLOW` in [src/services/transactionService.js:8-11](src/services/transactionService.js#L8-L11):
`waiting_for_driver → parked → key_in → requested → driver_assigned → en_route → arrived → delivered` (or `cancelled`). `updateTransactionStatus` automatically stamps the matching timestamp column when transitioning to `requested`, `arrived`, or `delivered`. Helpers (`confirmKeyIn`, `assignDriverForRetrieval`, `markEnRoute`, `markArrived`) exist so UI never builds raw status strings — use them instead of calling `updateTransactionStatus` directly.

`getTransactionStats` collapses these statuses into operator-friendly buckets (`waiting`, `parked`, `requested`, `ready`, `delivered`). When adding a new status, update both `STATUS_FLOW` and that aggregation.

### Key slots — two-mode allocation
`getNextAvailableKeySlot` in [src/services/transactionService.js:160-199](src/services/transactionService.js#L160-L199) first looks for custom slots in `key_slots` for the location; if none exist, it falls back to numeric slots `1..locations.key_capacity`. Active-transaction occupancy is checked against the same status whitelist as `getActiveTransactions`. The mode (custom vs numeric) is determined per location.

### Drivers ↔ auth users link
Drivers are a hybrid: a `drivers` row (operational record) optionally linked to a `users`+auth account (login credentials). [driverService.getDriverForUser](src/services/driverService.js) resolves a logged-in driver to their `drivers` row in this order: `user_id`, `email`, then `name + company` (legacy fallback). When adding drivers from the Company portal or admin Company Detail page, the "Create login for driver panel" checkbox runs `createStaff` (auth + `users` row) and passes the new auth `user.id` into `createDriver`. Without that link the driver panel falls back to fuzzy name matching, which fails for multi-driver companies.

### Timestamp parsing pitfall
Supabase sometimes returns timestamps without a timezone marker, which JS then misinterprets as local time. Always format timestamps through `parseUTC` / `formatTime` / `formatDate` / `formatDateTime` in [src/lib/utils.js](src/lib/utils.js) rather than `new Date(string)` directly.

### Validation helpers
`isValidEmail`, `isValidPhone`, `isValidPassword` (8+ chars, ≥1 letter and ≥1 digit), `normalizePhone` all live in [src/lib/utils.js](src/lib/utils.js). Apply them in every form that creates a user account (`Add Company`, `Add Operator`, `Add Driver`, `Staff`) — the forms already do, and new forms should match.

### WhatsApp / Yeti notifications go through an Edge Function
[src/services/webhookService.js](src/services/webhookService.js) does **not** call Yeti directly — it `POST`s to the `send-whatsapp` Edge Function in [supabase/functions/send-whatsapp/index.ts](supabase/functions/send-whatsapp/index.ts), which performs the API-key → JWT exchange against Yeti and caches the JWT in module-level memory. The browser never sees Yeti credentials. When adding a new notification, define a sender in `webhookService.js` and a matching template name; do not bypass the edge function.

Other edge functions:
- `create-staff` — service-role insert of new users (admin/company creating staff accounts). Verifies the caller's `role` is `'admin'` or `'company'` and (for company callers) refuses to create users for another company.
- `request-car` — guest-facing car retrieval endpoint. Validates the plate against `/^[A-Z0-9]{4,12}$/` and (post-migration) requires a per-transaction `guest_request_token` to block plate enumeration. The `REQUEST_CAR_REQUIRE_TOKEN` env var on the edge function can disable the requirement, but the default is on.
- `whatsapp-webhook` — inbound webhook receiver.

### Admin hierarchical drilldown
Super admin has a parallel "manage any company" experience that reuses the same services as the company portal:

- `/admin/companies` ([Companies.jsx](src/pages/admin/Companies.jsx)) — list. Each card is clickable, deep-linking to:
- `/admin/companies/:id` ([CompanyDetail.jsx](src/pages/admin/CompanyDetail.jsx)) — tabbed view (Overview / Locations / Operators / Drivers). The Operators and Drivers tabs both create auth logins via `createStaff` and link them properly. Use this page as the template when extending admin's per-company management.
- `/admin/locations` ([AdminLocations.jsx](src/pages/admin/AdminLocations.jsx)) — every location across every company, grouped by company, with search and company filter.
- `/admin/users` ([Users.jsx](src/pages/admin/Users.jsx)) — hierarchical: Super Admins section at top, then one collapsible card per company with users bucketed into Company Owners / Operators / Drivers.

The "Add Company" flow on `/admin/companies` requires the admin to set an initial password — `companyService.createCompanyWithOwner` provisions both the `valet_companies` row and the `users`+auth account in one shot.

### Notifications bell
[src/components/layout/NotificationsBell.jsx](src/components/layout/NotificationsBell.jsx) is rendered in [Header.jsx](src/components/layout/Header.jsx). It pulls the 20 most recent `valet_transactions` rows scoped to the role (`admin` = all, `company` = own company, `valet` = own location, `driver` = skipped — drivers see notifications in the driver panel itself), subscribes to `postgres_changes` on the same scope, and tracks read state per-user in `localStorage` (`notif_seen_<userId>` → ISO timestamp). The fetch + subscribe live in a single `useEffect` with a cancel flag to avoid the `react-hooks/set-state-in-effect` rule; if you change it, keep both pieces inside one effect.

### Settings & change-password
`/settings` ([src/pages/Settings.jsx](src/pages/Settings.jsx)) is available to every role and is the only built-in way for a user to change their own password. The page re-authenticates via `supabase.auth.signInWithPassword` to verify the current password before calling `supabase.auth.updateUser({ password })` — don't skip the re-auth.

### Sidebar active state
[Sidebar.jsx](src/components/layout/Sidebar.jsx) distinguishes "section root" routes (`/admin`, `/company`, `/operator`, `/driver` — one path segment) from deeper routes. Section roots use exact-match for active highlighting; nested routes use prefix match. Without this split the Dashboard link stayed highlighted on every sub-page.

The sidebar's nav items come from one of four hardcoded arrays in [Sidebar.jsx](src/components/layout/Sidebar.jsx) (`operatorNav` / `driverNav` / `companyNav` / `adminNav`) selected by `role` — add new routes there as well as in `App.jsx`.

### Styling
Tailwind v4 via PostCSS. Custom palettes `brand-*` (pink/magenta) and `dark-*` plus a few keyframes live in [tailwind.config.js](tailwind.config.js). Dark mode is class-based and toggled through [src/contexts/ThemeContext.jsx](src/contexts/ThemeContext.jsx). Compose conditional class strings with `cn(...)` from [src/lib/utils.js](src/lib/utils.js) (clsx + tailwind-merge), not manual string concatenation.

### Page layout
[src/components/layout/Layout.jsx](src/components/layout/Layout.jsx) wraps every protected route with `<Sidebar>` + `<Header>`. The driver panel was originally designed as a standalone mobile screen; on desktop it now renders inside the same Layout as everyone else (max-w-md centered), which is the intentional UX.
