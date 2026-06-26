# VALETBook360 — Tech Stack & Project Workflow

> Last updated: June 2026

---

## 1. Tech Stack at a Glance

| Layer | Technology | Notes |
|---|---|---|
| Frontend framework | **React 19** | SPA, functional components + hooks only |
| Build tool | **Vite 7** | Dev server + production bundler, manual chunk splitting, sourcemaps disabled in prod |
| Routing | **React Router DOM 7** | Role-gated routes via `ProtectedRoute` + `AuthGate` |
| Styling | **Tailwind CSS v4** (via PostCSS) | Custom `brand-*` (pink/magenta) and `dark-*` palettes; class-based dark mode |
| Icons | **lucide-react** | |
| Fonts | Inter + Playfair Display | Self-hosted via `@fontsource` |
| Utility libs | `clsx` + `tailwind-merge` (via `cn()`), `qrcode` | QR codes for guest car-retrieval links |
| Backend | **Supabase** (full BaaS — no custom server) | Postgres, Auth, Realtime, Storage, Edge Functions |
| Database | **PostgreSQL** (Supabase-hosted) | RLS-protected, migrations in `supabase/migrations/` |
| Auth | **Supabase Auth** (email + password) | Session stored in `sessionStorage` (intentional — not `localStorage`) |
| Realtime | **Supabase Realtime** (`postgres_changes`) | Live dashboard updates, notifications bell |
| Serverless | **Supabase Edge Functions** (Deno/TypeScript) | 4 functions: `create-staff`, `request-car`, `send-whatsapp`, `whatsapp-webhook` |
| Notifications | **WhatsApp via Yeti API** | Proxied through `send-whatsapp` edge function; browser never sees Yeti credentials |
| Automation (optional) | **n8n webhook** | `VITE_N8N_WEBHOOK_URL` |
| Linting | **ESLint 9** (flat config) | `react-hooks`, `react-refresh` plugins |
| Mobile companion | **Flutter** (`mobile-app/`) | Driver app — skeleton stage, independent of web build |
| Testing | — | No test runner configured (known gap) |

**There is no Node/Express backend.** The browser talks directly to Supabase (Postgres via PostgREST, Auth, Realtime) and to Edge Functions for anything requiring secrets or service-role privileges.

---

## 2. Environment & Commands

```bash
npm run dev       # Vite dev server → http://localhost:5173
npm run build     # production build → dist/
npm run preview   # serve the production build locally
npm run lint      # ESLint over **/*.{js,jsx}
```

Required env vars (`.env`, template in `.env.example`):

| Var | Purpose |
|---|---|
| `VITE_SUPABASE_URL` | Supabase project URL |
| `VITE_SUPABASE_ANON_KEY` | Public anon key (RLS enforces access) |
| `VITE_ENABLE_WHATSAPP` | Optional — toggles WhatsApp notifications |
| `VITE_N8N_WEBHOOK_URL` | Optional — n8n automation hook |
| `VITE_API_TIMEOUT_MS` | Optional — request timeout |

If the Supabase URL/key are missing, `src/lib/supabase.js` swaps in a **mock client** ("demo mode") so the app still boots; sign-in rejects with an explanatory error and a banner renders.

Database migrations are **not auto-applied** — run them manually in Supabase Dashboard → SQL Editor, in filename order:

1. `20260520_link_drivers_to_users.sql` — links `drivers` rows to auth accounts
2. `20260521_request_car_token.sql` — per-transaction guest token (anti plate-enumeration)
3. `20260522_hot_path_indexes.sql` — composite/partial indexes for hot queries
4. `20260523_enable_rls.sql` — Row-Level Security on all 10 tables + per-role policies + first-admin unique index

---

## 3. Roles & Portals

Four roles, four portals, one login page:

| Role (DB `users.role`) | Portal route | Who they are | What they do |
|---|---|---|---|
| `admin` | `/admin` | Platform super admin | Manage all companies, locations, users; hierarchical drilldown (`/admin/companies/:id`) |
| `company` | `/company` | Valet company owner | Manage own locations, operators, drivers; view stats |
| `valet` | `/operator` | On-site operator | Check-in cars, manage key slots, assign drivers, run the live dashboard |
| `driver` | `/driver` | Valet driver | Mobile-style panel: park cars, retrieve cars, update status |

Routing is enforced twice:
- `<AuthGate>` redirects a logged-in user to their portal based on `role`.
- `<ProtectedRoute allowedRoles={[...]}>` guards each route subtree.

**On the backend**, the same role model is enforced by Postgres RLS (migration `20260523`): admin sees everything, company/valet see their own company, drivers see their own assignments. Edge functions use the service role and do their own caller-role verification.

---

## 4. Frontend Architecture

```
src/
├── App.jsx                  # Routes, AuthGate, ProtectedRoute, error boundary
├── contexts/
│   ├── AuthContext.jsx      # Session + profile + role (load order is load-bearing!)
│   └── ThemeContext.jsx     # Dark mode (class-based)
├── lib/
│   ├── supabase.js          # Client init (or mock client in demo mode)
│   ├── logger.js            # debug/info/warn no-op in prod; error always logs
│   ├── errors.js            # ServiceError + wrapError → toast-safe userMessage
│   └── utils.js             # cn(), parseUTC/formatTime, validators, normalizePhone
├── services/                # ALL Supabase access goes through here
│   ├── transactionService.js  # State machine + CRUD + realtime + stats
│   ├── driverService.js     # Driver CRUD + user→driver resolution
│   ├── companyService.js    # createCompanyWithOwner (with rollback)
│   ├── locationService.js / slotService.js / userService.js / visitorService.js
│   └── webhookService.js    # WhatsApp senders → send-whatsapp edge function
├── components/
│   ├── layout/              # Layout, Sidebar (role-based nav), Header, NotificationsBell
│   └── ui/                  # Shared UI primitives, Toast
└── pages/
    ├── Login.jsx, Settings.jsx
    ├── admin/               # Dashboard, Companies, CompanyDetail, AdminLocations, Users
    ├── company/             # Dashboard, Locations, LocationDetail, Staff, Drivers
    ├── operator/            # OperatorDashboard, CheckIn, ActiveCars, KeySlots
    └── driver/              # DriverPanel (mobile-first, max-w-md centered on desktop)
```

### Key conventions

1. **Service layer only** — UI components never call `supabase.from(...)` directly (known exceptions: `NotificationsBell`, `DriverPanel` — documented in CLAUDE.md).
2. **camelCase in, snake_case out** — services accept camelCase inputs and map to snake_case columns before insert/update.
3. **Realtime helpers** — `subscribeTo*` functions return a channel; callers must `unsubscribe()` in effect cleanup.
4. **Errors** — catch blocks use `toast.error(err.userMessage || err.message)`; `wrapError()` maps Postgres error codes to friendly strings.
5. **Timestamps** — always `parseUTC`/`formatTime`/`formatDate` from `lib/utils.js`, never `new Date(string)` (Supabase timestamps can be missing the TZ marker).
6. **Insert/update whitelists** — `transactionService` filters writable columns through `TRANSACTION_INSERT_FIELDS` / `TRANSACTION_UPDATE_FIELDS` so callers can't inject privileged fields.

---

## 5. Backend Architecture (Supabase)

### Database tables

| Table | Purpose |
|---|---|
| `valet_companies` | Tenant root — one row per valet company |
| `users` | Profiles keyed by auth user id; `role`, `valet_company_id`, `location_id` |
| `locations` | Venues operated by a company; `key_capacity` for numeric slot mode |
| `drivers` | Operational driver record; optional `user_id` link to a login |
| `key_slots` | Custom key slots per location (fallback: numeric `1..key_capacity`) |
| `visitors` | Guests (name + phone) |
| `cars` | Vehicles (plate, make, model, color) |
| `valet_transactions` | The core entity — one row per park/retrieve cycle |
| `whatsapp_logs` | Notification audit trail |
| `contracts` | Driver↔location assignment contracts |

### Security model

- **RLS everywhere** (`20260523_enable_rls.sql`): policies built on `SECURITY DEFINER` helper functions (`auth_role()`, `auth_company_id()`, `auth_driver_id()`) to avoid recursive policy lookups.
- **First-admin bootstrap**: a partial unique index `users_one_admin_idx` makes "only one self-claimed admin" atomic — fixes the signup race.
- **Edge functions** run with service role (bypass RLS) and verify the caller's JWT + role themselves.
- **Anon key in the browser is safe by design** — it can only do what RLS policies allow.

### Edge Functions (Deno/TypeScript, `supabase/functions/`)

| Function | Trigger | What it does |
|---|---|---|
| `create-staff` | Admin/Company UI | Service-role creation of auth user + `users` row. Verifies caller is `admin` or `company`; company callers can't create users outside their own company. |
| `request-car` | Guest QR link (unauthenticated) | Guest requests their car by plate + `guest_request_token`. Plate validated against `/^[A-Z0-9]{4,12}$/`; token blocks plate enumeration. |
| `send-whatsapp` | `webhookService.js` | Exchanges API key for a Yeti JWT (cached in module memory), sends template messages. Browser never sees Yeti credentials. |
| `whatsapp-webhook` | Yeti/Meta inbound | Receives delivery callbacks / inbound messages. |

---

## 6. The Core Workflow — Life of a Valet Transaction

### State machine (`transactionService.js`)

```
waiting_for_driver → parked → key_in → requested → driver_assigned → en_route → arrived → delivered
                                  └──────────── (cancelled reachable from any active state) ───────┘
```

Transitions are validated client-side against `LEGAL_TRANSITIONS` — illegal jumps throw (e.g. `delivered → parked`). Status changes auto-stamp timestamp columns (`requested_at`, `ready_at`, `delivered_at`). UI never builds raw status strings; it calls helpers: `confirmKeyIn`, `assignDriverForRetrieval` (auto-steps through `requested` when assigning from `parked`/`key_in`), `markEnRoute`, `markArrived`.

### End-to-end flow

```
┌──────────┐   1. Guest arrives, operator checks car in
│  GUEST   │      (plate, visitor name/phone, photos)
└────┬─────┘
     │
┌────▼─────┐   2. createTransaction()
│ OPERATOR │      • status = waiting_for_driver (forced)
│ /operator│      • key slot auto-allocated (custom slots, else numeric 1..capacity)
└────┬─────┘      • QR code + WhatsApp "car parked" sent to guest
     │
┌────▼─────┐   3. Driver parks the car → status: parked
│  DRIVER  │   4. Hands key to operator → confirmKeyIn() → status: key_in
│ /driver  │
└────┬─────┘
     │         5. Guest wants the car back — two paths:
     │            a) Guest scans QR → request-car edge function
     │               (plate + guest_request_token) → status: requested
     │            b) Operator assigns directly from the dashboard
     │
┌────▼─────┐   6. assignDriverForRetrieval(driverId, etaMinutes)
│ OPERATOR │      → status: driver_assigned
└────┬─────┘      → WhatsApp "driver assigned, ETA X min" to guest
     │
┌────▼─────┐   7. Driver picks up key → markEnRoute() → en_route
│  DRIVER  │   8. Reaches pickup point → markArrived() → arrived
└────┬─────┘      → WhatsApp "your car is ready"
     │
┌────▼─────┐   9. Guest takes the car → delivered
│  GUEST   │      (key slot frees up automatically — occupancy is derived
└──────────┘       from active-transaction statuses, no separate slot table write)
```

### Realtime propagation

Every dashboard subscribes to `postgres_changes` on `valet_transactions`:
- **Operator dashboard** — live card board grouped by status.
- **Driver panel** — new assignments appear instantly.
- **Notifications bell** — last 20 transactions scoped by role (admin = all, company = own company, valet = own location).
- **Company/Admin dashboards** — stats recompute on change.

---

## 7. Supporting Workflows

### Onboarding a new company (admin)
1. `/admin/companies` → "Add Company" — admin sets company name + owner email + initial password.
2. `companyService.createCompanyWithOwner` chains: create `valet_companies` row → `create-staff` edge function (auth user + `users` row, `role='company'`). **If staff creation fails, the company row is deleted** (rollback) so the admin can retry without unique-constraint conflicts.
3. Company owner logs in → `/company` → adds locations, operators (role `valet`), drivers.

### Adding a driver with a login
1. Company portal or admin Company Detail → "Add Driver" with "Create login for driver panel" checked.
2. `create-staff` provisions auth + `users` row (`role='driver'`), then `createDriver` stores the `drivers` row with `user_id` linked.
3. Driver logs in → `getDriverForUser` resolves their `drivers` row by `user_id` (fallback: email). The legacy name-match fallback was removed (impersonation risk).

### First-run bootstrap
First-ever signup auto-creates a profile with `role='admin'` **only if no admin exists** — enforced atomically by the partial unique index. Every later orphan signup defaults to `valet`.

### Password change
`/settings` (all roles) — re-authenticates with the current password via `signInWithPassword` before calling `updateUser({ password })`.

### WhatsApp notification flow
```
UI event → webhookService.sendX() → POST /functions/v1/send-whatsapp
  → edge fn verifies caller JWT + role
  → Yeti API-key → JWT exchange (cached)
  → template message sent → logged to whatsapp_logs
```

---

## 8. Known Gaps / Roadmap

| Item | Status |
|---|---|
| RLS policies | Written (`20260523`) — **must be applied in Supabase Dashboard** |
| `guest_request_token` minting in frontend | **Open** — `createTransaction` doesn't generate the token yet; QR retrieval flow 401s once `request-car` enforcement is on |
| Auth-account deletion | **Open** — `deleteUser` only removes the profile row; needs a `delete-user` edge function so removed users can't sign back in |
| State machine server-side enforcement | Client-side only; a Postgres trigger would make it tamper-proof |
| `send-whatsapp` caller scope | Any logged-in non-driver can send templates; should be tightened |
| Tests | None configured |
| Flutter driver app | Skeleton only |
