# 10 — Backend Integration (off Supabase → Spring Boot + Postgres + MinIO + Socket.IO + Docker)

The existing service layer (`src/services/*.js`) is the **bounded-context map already drawn**. Each service file ≈ one microservice. This is a gift — we re-platform contracts, not invent them.

## 10.1 Microservice decomposition (derived from real services)

| Microservice | Owns | Derived from | Key endpoints |
|---|---|---|---|
| **auth-service** | Login, JWT issue/refresh, biometric token, password change | `AuthContext`, `Settings.jsx` re-auth flow | `POST /auth/login`, `POST /auth/refresh`, `POST /auth/password` (re-auth required) |
| **user-service** | Users, roles, staff creation | `userService.js` (`createStaff`, `updateUserRole`) | `POST /users`, `POST /staff`, `GET /users?companyId` |
| **company-service** | Companies + composed owner creation | `companyService.js` (`createCompanyWithOwner` w/ rollback) | `POST /companies` (transactional create+owner) |
| **location-service** | Locations, key capacity | `locationService.js` | CRUD `/locations` |
| **keyslot-service** | Custom/numeric slot allocation | `slotService.js` + `getNextAvailableKeySlot` | `GET /locations/{id}/next-slot`, `/slots` CRUD, `bulk-generate` |
| **transaction-service** | The lifecycle + legal transitions | `transactionService.js` (`STATUS_FLOW`, `LEGAL_TRANSITIONS`) | `POST /transactions`, `PATCH /transactions/{id}/status` |
| **driver-service** | Drivers, user link, performance | `driverService.js`, `getDriverPerformanceStats` | `/drivers`, `GET /drivers/me` (by user_id→email→name fallback) |
| **notification-service** | WhatsApp/push senders + delivery log | `webhookService.js`, `whatsappService.js`, edge fns | `POST /notify/*`, `GET /logs` |
| **media-service** | MinIO uploads, thumbnails | `storageService.js` | `POST /media/presign`, `POST /media/complete` |
| **search-service** | Global plate/name/phone/company search | (new — admin need) | `GET /search?q=` |
| **analytics-service** | Stats, trends, reports | `getTransactionStats`, `getDriverPerformanceStats` | `GET /analytics/*` |
| **realtime-gateway** | Socket.IO fan-out | `subscribeToTransactions`, NotificationsBell sub | WS rooms |

**API gateway** in front (Spring Cloud Gateway): JWT validation, rate-limit, tenant header injection.

## 10.2 The critical server-side rules (port from the JS, harden)

1. **State machine moves to a DB constraint + service guard.** The client `LEGAL_TRANSITIONS` (`transactionService.js:16`) was self-described as "client-side only... should also run as a Postgres trigger." **Do it.** A `transaction-service` domain method + a Postgres `BEFORE UPDATE` trigger enforce legal transitions server-side. Illegal transition → 409.
2. **Tenant scoping is mandatory, server-enforced.** `getActiveTransactions` refusing unscoped calls (`L51`) becomes a gateway rule: every transaction/driver/location query is filtered by the JWT's `companyId` claim. RLS-equivalent at the service layer + row filters. No client can request another tenant's data.
3. **Insert/update field whitelists** (`TRANSACTION_INSERT_FIELDS:74`, `TRANSACTION_UPDATE_FIELDS:108`) become **DTO classes** — Spring only binds whitelisted fields; status is server-forced to `waiting_for_driver` on create (`L96`).
4. **Timestamp stamping** (`requested_at`/`ready_at`/`delivered_at`, `L136`) moves into the service on transition. Always store **UTC with `timestamptz`** — fixing the timezone-marker pitfall noted in CLAUDE.md/`parseUTC` at the source so the client never has to guess.
5. **Guest-request token** (`guest_request_token`) preserved for the public car-request endpoint (anti plate-enumeration) — now a `transaction-service` public route with rate-limiting.

## 10.3 PostgreSQL data-relationship recommendations

Core tables (from observed columns): `users`, `valet_companies`, `locations`, `key_slots`, `drivers`, `visitors`, `cars`, `valet_transactions`, `notifications_log`.

**Recommendations:**
- **Drivers↔users:** keep `drivers.user_id` FK unique-when-set (from migration `20260520`); resolve "me" by `user_id` first. Make name-fallback a server concern only.
- **Transactions FKs** `parked_by_driver_id`/`retrieved_by_driver_id` → `ON DELETE SET NULL` (already in `20260520`). Keep — never orphan history.
- **Visitor model fix (audit C3):** today identity is faked as `CAR-{plate}` phone. Introduce a real `cars (plate UNIQUE per company)` ↔ `visitors` link; a transaction references `car_id` + optional `visitor_id`. Plate is the natural key, not a fake phone.
- **Hot-path indexes:** preserve/extend `20260522` composite indexes (`status × company × created_at`, driver partial indexes, `key_code` lookup, visitor phone, plate). These map exactly to: floor feed, driver "my tasks", slot allocation, search.
- **Status as enum** (`valet_status` Postgres enum) + transition trigger.
- **Partial unique index `(role='admin')`** — CLAUDE.md flags the TOCTOU in `autoCreateProfile`; apply the index server-side to make first-admin creation race-safe.
- **`timestamptz` everywhere.** Partition `valet_transactions` by month at scale (doc 11).

## 10.4 MinIO media UX strategy

Replaces `storageService.uploadMultiplePhotos`. Endpoints: presign → direct PUT to MinIO → complete.

| UX concern | Behavior |
|---|---|
| **Progress** | `VUploadTile` per photo: thumbnail + circular progress (dio `onSendProgress`). Never a blocking full-screen spinner. |
| **Multi-upload** | Parallel (max 3 concurrent), independent tiles; one failing doesn't block others (the old code uploaded as a batch and dropped all on failure). |
| **Retry** | Failed tile shows retry icon; tap re-presigns + re-uploads just that file. |
| **Previews** | Local `URL`/`File` preview instantly (preserves the optimistic preview from `OperatorDashboard.jsx:690`); swap to MinIO URL on complete. |
| **Recovery** | Uploads queued in the offline outbox; resume on reconnect. Check-in/park can complete *without* photos (photos sync later) — never block the operational action. |
| **Thumbnails** | media-service generates 200px thumbs on `complete`; client requests display-size variants (`?w=200`) → fast feeds, low data. |
| **Compression** | client-side downscale to ≤1600px / 80% JPEG before upload (drivers on cellular). |
| **Lightbox** | tap photo → full-screen zoomable viewer with shared-element transition. |

## 10.5 Socket.IO realtime strategy (replaces refetch-on-everything, audit A7)

**Rooms (server-authoritative, JWT-scoped):**
- `company:{id}` — company-wide pulse (managers, admins).
- `location:{id}` — the operator floor for that post.
- `driver:{id}` — that driver's missions.
- `tx:{id}` — granular detail-sheet subscribers.

**Events emit deltas, not "refetch":**
| Event | Payload | Client reaction |
|---|---|---|
| `tx:created` | full tx | insert card (animate from top) |
| `tx:status` | `{id, status, ts}` | mutate that card's state in place, animate rail (240ms) |
| `tx:assigned` | `{id, driverId, eta}` | push mission to `driver:{id}`, heavy haptic |
| `tx:payment` | `{id, paid}` | flip payment pill, enable/disable deliver |
| `presence:driver` | `{driverId, online}` | operator sees who's on shift (NEW — informs suggested driver) |
| `notify` | notification | bell badge increment (replaces 20-row poll) |

**Why:** the old model did `getActiveTransactions + getDrivers + getLocations` on *every* event (`OperatorDashboard.jsx:108–138`) plus a 30s poll. Deltas mutate one `StateNotifier` field → 60fps, near-zero bandwidth, scales to millions (doc 11 fan-out).

**Presence & typing:** presence used for "driver online" dots and smart driver suggestion. (No chat in v1, but the gateway supports typing indicators for a future guest-chat.)

**Reliability:** Socket auto-reconnect with backoff; on reconnect, a single `sync:since(ts)` pull reconciles missed deltas + replays the offline outbox.

## 10.6 Docker / deployment considerations (UX-relevant)

- Each service containerized; `docker-compose` for dev (Postgres, MinIO, Redis, gateway, services, realtime-gateway).
- **Redis** backs Socket.IO adapter (multi-instance fan-out) + rate-limit + presence.
- **MinIO** as S3-compatible object store; CDN/edge cache in front of thumbnails for global photo loads.
- Health/readiness probes so the app shows an honest "service degraded" `VBanner` instead of silent failure (parallels the current demo-mode banner instinct, `App.jsx:82`).
- Config via env (mirrors `.env.example`): API base URL, WS URL, timeouts — the Flutter app reads a single `--dart-define` config per environment.

## 10.7 API contract conventions (carry forward the good parts)

- **camelCase JSON** on the wire (Flutter freezed models) ↔ **snake_case** in Postgres — Spring `@JsonNaming`/MapStruct handles the boundary, exactly mirroring the JS service mapping convention (`createTransaction` camel→snake at `transactionService.js:82`).
- **Error envelope** ports `ServiceError.userMessage`: `{ code, userMessage, detail }`. Postgres `23505/23503/42501` → friendly messages (from `lib/errors.js`). The client always shows `userMessage`.
- **Idempotency keys** on `POST /transactions` and status PATCH (offline replay safety).
