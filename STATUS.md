# Vālet Re-Platform — Build Status

Migrating from **React + Vite + Supabase (web SPA)** → **Flutter + Java Spring Boot microservices + PostgreSQL + MinIO + Socket.IO + Docker**, mobile-first, built one **vertical slice** at a time.

Design blueprint lives in [`docs/design/`](docs/design/). This file tracks the **build**.

---

## ✅ Done — Slice 1: Driver mission flow (login → see assignments → swipe to deliver)

The first end-to-end slice across every layer. Built in parallel by 3 agents against a fixed contract, then integrated.

| Layer | What | Where | Verified |
|---|---|---|---|
| Auth microservice | Spring Boot 3.3 / Java 21, JWT (HS256) issue+refresh+rotation, BCrypt, RFC7807, Flyway, role/tenancy claims | `backend/auth-service/` | Compiles; 6/6 JWT unit tests; booted live vs real Postgres 16, all endpoints exercised |
| Transaction/Driver microservice | Valet state machine (legal-transition enforced in service **and** a DB trigger), driver assignment + en-route/arrived/delivered API, JWT resource server | `backend/transaction-service/` | Compiles; 44 unit tests pass; booted live vs Postgres, full happy + illegal-path matrix |
| Flutter app | Login + signature swipe-to-advance mission stack, theme from `tokens.json`, dio client, secure token storage, all states | `mobile-app/` | `flutter analyze` clean; `flutter test` 4/4; `flutter build web` OK |
| Integration | `docker compose` (postgres + both services), 2nd DB init, shared `JWT_SECRET` | `infra/` | ✅ **Booted & verified live — full flow below** |

### ✅ Live end-to-end verification (combined `docker compose up`, this session)
All three containers came up healthy and the full driver flow passed against the running stack:
- `POST /auth/login` (driver@valet.demo) → 200, correct user + JWT.
- `GET /auth/me` → 200, claims match.
- `GET /api/driver/assignments` → **3 seeded missions** (the transaction-service validated the **auth-issued** JWT — cross-service shared-secret confirmed working).
- Advance mission `driver_assigned → en_route → arrived → delivered` → each 200, `deliveredAt` stamped; assignment list dropped 3 → 2.
- Guards: illegal re-advance → **409**, no token → **401**, bad creds → **401**. All as designed.

> Port note: host `8081` was occupied by an unrelated local `node` process and `5432` by a local Postgres, so the stack was verified with `AUTH_PORT=8091 DB_PORT=5433 docker compose ... up`. In a clean environment the contract defaults (8081/8082/5432) work as-is.

### Contract that ties the slice together
- **JWT:** HS256, shared env `JWT_SECRET` (byte-identical across services). Claims: `sub`(userId), `email`, `role` (lowercase `admin|manager|valet|driver`), `companyId`, `locationId`, `typ=access`, `iss=valet-auth`.
- **Ports:** postgres `5432`, auth `8081`, transaction `8082`.
- **Databases:** `valet_auth` (auth), `valet_core` (transaction) on one Postgres cluster.
- **Demo accounts (seeded by Flyway):** `driver@valet.demo / Driver123` (has 3 seeded assignments), `admin@valet.demo / Admin123`.
- **Demo driver UUID:** `11111111-1111-1111-1111-111111111111` — auth seeds the user, transaction seeds that user's assignments. This is what lets the services align with zero runtime coupling.

### Run it
```bash
cp infra/.env.example infra/.env          # optional; tweak JWT_SECRET for non-dev
docker compose -f infra/docker-compose.yml up --build
```
Then verify the backend:
```bash
# 1) login as the demo driver
TOKEN=$(curl -s localhost:8081/auth/login -H 'content-type: application/json' \
  -d '{"email":"driver@valet.demo","password":"Driver123"}' | jq -r .accessToken)
# 2) see the seeded assignments
curl -s localhost:8082/api/driver/assignments -H "authorization: Bearer $TOKEN" | jq
# 3) advance one mission
ID=... ; curl -s -X POST localhost:8082/api/driver/transactions/$ID/en-route -H "authorization: Bearer $TOKEN"
```
Run the Flutter app against it:
```bash
cd mobile-app && flutter pub get
flutter run --dart-define=AUTH_BASE_URL=http://127.0.0.1:8081 --dart-define=CORE_BASE_URL=http://127.0.0.1:8082
# (defaults target the Android emulator at 10.0.2.2; override as above for iOS sim / desktop / web)
```
Login is pre-filled with the demo driver. Slide each mission card to advance it through en-route → arrived → delivered.

---

## ✅ Done — Slice 1.5: Socket.IO realtime (live deltas replace polling)

The transaction-service's `RealtimeEventPublisher` was previously **dead code** (defined, never called). Now wired into the lifecycle and proven end-to-end live.

| Layer | What | Where | Verified |
|---|---|---|---|
| Transaction-service | `RealtimeEventPublisher` now invoked: `emitCreated` on create, `emitStatus` in the `transition()` chokepoint (covers every move), `emitAssigned` on driver assignment. After-commit, Redis-failure-safe. | `backend/transaction-service/` | Compiles in Docker; 51 unit tests pass; emits captured live on `valet.tx.events` |
| Realtime gateway | Node 24 Socket.IO entrypoint `server.js`: JWT-authed handshake, `@socket.io/redis-adapter` (multi-instance fan-out), dedicated events subscriber, JWT-derived rooms (`driver:{sub}`, `company:{id}`, `location:{id}`), `/healthz`, graceful shutdown. | `backend/realtime-gateway/` + `Dockerfile` | `node --check` clean; booted live; healthz UP |
| Redis | `redis:7-alpine` added to compose; backs the adapter + pub/sub. | `infra/docker-compose.yml` | Healthy in combined stack |
| Flutter | `RealtimeClient` (socket_io_client 2.0.3+1) layered on the driver poll (graceful degradation on disconnect); floor controller subscribes for live deltas. | `mobile-app/` | `flutter analyze` clean; `flutter test` 9/9; `flutter build web` OK |

## ✅ Done — Slice 2: Operator floor (create → park → key-in → request → assign)

The live valet floor. Operator endpoints reuse the `transition()` chokepoint; tenant-scoped by JWT (`companyId`/`locationId`), never from the body.

| Layer | What | Where | Verified |
|---|---|---|---|
| Transaction-service | `OperatorController` `/api/operator/*`: create (status forced `waiting_for_driver`), park, key-in, request, assign(driverId), cancel, GET floor feed. Role guard (valet/manager/admin; driver→403). Cross-tenant guard `loadOwnedByCompany`→403. | `backend/transaction-service/` | Docker build OK; 51 unit tests; full live happy + guard matrix |
| Auth-service | `V3__seed_demo_operator.sql` — `operator@valet.demo / Operator123` (role `valet`, company `2222…`, location `3333…`) so the floor is usable + assignable to the demo driver out of the box. | `backend/auth-service/` | Flyway applied live; login returns valet+company token |
| Flutter | Role-routed (`/operator` vs `/driver`), `floor_controller.dart`, `operator_floor_screen.dart` + create sheet, optimistic actions + live delta cards. | `mobile-app/` | analyze/test/build web all green |

### ✅ Live end-to-end verification (combined `docker compose up`, this session — ports 8091/8092/8090, redis 6380, pg 5433)
All 5 containers healthy (postgres, redis, auth, transaction, realtime-gateway). Verified by hand against the running stack:
- **Operator flow:** create `LIVE9000` → **201** status `waiting_for_driver` (companyId/locationId from JWT, not body) → park **200** → key-in **200** → request **200** → assign(demo driver) **200** status `driver_assigned`, `retrievedByDriverId` stamped.
- **Cross-service:** the operator-created car then appears in **`GET /api/driver/assignments`** (auth-issued token validated by transaction-service).
- **Guards:** admin (no company) create → **403 `NO_TENANT`**; driver → operator endpoint → **403 `NOT_AN_OPERATOR`**; illegal re-park → **409 `ILLEGAL_TRANSITION`**. All RFC7807.
- **Realtime, full chain:** a JWT-authed Socket.IO client auto-joined to its `company:{id}` room received `tx:created` + `tx:status`(parked/key_in/requested) **live** as the operator drove the lifecycle (Redis → gateway → socket, correct tenant room). `tx:assigned` carries `driverId`.

### Updated contract additions (Slice 1.5 / 2)
- **Realtime channel:** transaction-service publishes camelCase JSON to Redis `valet.tx.events`: `tx:created` / `tx:status` / `tx:assigned`, each `{event,id,status,locationId,companyId,driverId,ts}`. Gateway fans to rooms by id presence.
- **Gateway:** host port **8090** (`GATEWAY_PORT`), `/healthz`. Same shared `JWT_SECRET` + issuer as the Java services. Socket connect: `auth:{token:<accessToken>}`.
- **Operator API:** base `/api/operator` on transaction-service (8082). Roles `valet|manager|admin`.
- **Demo operator:** `operator@valet.demo / Operator123` (role `valet`, company `2222…`).
- **Ports note:** host 5432/6379 are occupied by local Postgres/Redis on the dev machine; `infra/.env` overrides to 5433/6380 (+ 8091/8092). Clean envs use the defaults.

---

## 🚢 What's left to ship the client MVP

The **ship-MVP = live valet floor + driver missions + realtime** is now functionally complete across all layers and verified live. Remaining before a client pilot:

**Must-do (small):**
1. **Flutter manual run vs live stack** — only automated gates (analyze/test/build) have run; do one manual emulator pass of the operator + driver screens against the running stack (`--dart-define=REALTIME_URL=http://10.0.2.2:8090 AUTH_BASE_URL=… CORE_BASE_URL=…`).
2. **Assign-driver UX** — operator assign currently takes a free-text driverId (no driver-service yet). For a usable pilot, add a minimal driver list (seed-backed or a thin endpoint) so operators pick from a dropdown.
3. **Run the Testcontainers integration tests on CI/host** (`*IntegrationTest`) — they were excluded from the in-container unit runs; they pass on a normal Docker host and should gate the pipeline.

**Nice-to-have (explicitly deferred from ship-MVP):** MinIO/media uploads, notification-service (WhatsApp), search, analytics, admin company-management, KeySlot custom allocation, company/location CRUD services.

---

## ✅ Done — Production-hardening wave (2026-06-25, verified live)

A parallel hardening + completion wave run across 5 specialist streams (qa-stress-tester, root-cause-debugger, fullstack-migration-architect, system-architect, + a remediation pass). All changes rebuilt into the combined stack and re-verified live by the orchestrator.

**Security hardening (verified live):**
- **CORS allowlist replaces `*`** on all three surfaces (auth, transaction, gateway) via env `CORS_ALLOWED_ORIGINS` (gateway: `CORS_ALLOWED_ORIGINS`). Live: `evil.com` preflight → 403, `localhost:*` → 200/204. Prod sets real origins.
- **Operator authz is now defense-in-depth**: security-chain URL rule `/api/operator/**` → `hasAnyRole(VALET,MANAGER,ADMIN)` + `@EnableMethodSecurity` + class `@PreAuthorize` + the in-controller check. Driver → operator endpoint → 403 at the chain.
- **CRITICAL cross-tenant PII leak CLOSED**: `GET /api/transactions/{id}` was returning full PII (guestPhone/name/plate/companyId) to ANY authenticated user. Now `getByIdScoped` enforces tenant+role: only the assigned driver OR an operator-role caller in the same company can read it; others → 403 `NOT_YOUR_TRANSACTION` (doesn't reveal existence). Verified live.
- **JWT secret hygiene**: services + gateway already fail-fast on <32-byte secret; rotation runbook documented in `docs/SECURITY.md`.
- Full adversarial audit (forged/expired/refresh-as-access tokens → 401; SQLi stored as literal; oversized/malformed input → 400) all PASS — see `docs/SECURITY.md`.

**Reliability / ops hardening (verified live):**
- **Graceful shutdown** on both Java services (`server.shutdown: graceful`, 30s drain) + compose `stop_grace_period: 35s`. Confirmed active in logs.
- **Gateway `/healthz` no longer lies**: returns 503 `DOWN` if any of the 3 Redis clients isn't `ready`, 200 `UP` otherwise. Verified: redis down → 503, redis up → 200.
- **Flyway multi-DB init made idempotent** (`\gexec` guard) so adding a service DB survives a non-empty volume — the prior first-init-only gotcha is fixed. Runbook in the init script header.

**Completion to pilot-ready (verified live):**
- **Driver picker** replaces free-text driverId: new tenant-scoped `GET /drivers` on auth-service (operator-roles only, returns `{id,name,email}` for caller's company — no PII beyond name/email, inactive excluded). Flutter operator assign now uses a picker sheet (loading/empty/error states). Live: operator → 200 list, driver → 403, admin(no company) → 403.

**Tests now GREEN on host (Testcontainers):**
- Root-cause fixes let the deferred `*IntegrationTest` suites RUN on this host (OrbStack): pinned docker-java `api.version=1.41`; fixed shared-container test ordering; switched auth tests off JDK `HttpURLConnection` (intercepts 401 bodies) to Apache HttpClient5.
- **transaction-service: 14/14 integration GREEN** (Operator 7/7 + Driver 7/7); **auth-service: 9/9 integration GREEN**; plus 51 Java + 13 Flutter unit tests.

### ✅ Live re-verification after hardening (combined stack, all 5 containers healthy)
- PII leak: driver reads other's tx → **403**; operator reads own → **200**; assigned driver reads own → **200**.
- Operator happy path create→park→key-in→request→assign → all **2xx**; assigned car appears in driver feed; realtime fired `tx:created` + 3×`tx:status` + `tx:assigned`.
- Driver→operator endpoint → **403**; CORS evil→**403**/localhost→**200**; gateway healthz **UP** (redis up).

### Production-readiness verdict
- **Genuinely production-ready now:** auth/JWT model, state-machine chokepoint (service + DB trigger), tenant isolation (operator + the fixed `/transactions/{id}` read), CORS allowlist, operator authz depth, graceful shutdown, idempotent DB init, realtime fan-out (horizontally scalable via redis-adapter), integration test suite.
- **Pilot-ready (acceptable for a supervised single-location pilot, hardening tracked):** realtime delivery is best-effort (Redis-failure-safe) with full-list refetch on reconnect — fine at pilot scale; observability is gateway-JSON-logs only.

## ✅ Done — Final production-hardening wave (2026-06-25, all 5 MUST-fixes landed + verified live by the orchestrator)

The five MUST-fix items previously blocking production are now implemented AND independently re-verified live against the rebuilt stack. Tests stayed green (no regression).

1. **Rate limiting + account lockout** — auth-service: Redis-backed sliding-window per-IP **failure** ceiling (coarse, default 100 fails/60s) + precise **per-account lockout** (5 fails/15min, resets on success, blocks even a correct password while locked). 429 RFC7807 + `Retry-After`. Live: 5 bad logins for an account → 429 lockout; a DIFFERENT account from the SAME host IP still logs in **200** (the shared-egress-IP trap the orchestrator caught and had fixed — per-IP now counts failures only); locked account stays 429.
2. **Secret fail-fast + prod profile** — `application-prod.yml` removes all insecure fallbacks; eager `SecretValidator` aborts boot if `JWT_SECRET` is missing/<32 bytes. Live: empty secret under prod profile → container **exits 1** with `IllegalStateException: auth.jwt.secret ... must be at least 32 bytes`; healthy stack boots clean with a valid secret. Rotation runbook in `docs/SECURITY.md`.
3. **CORS to real origins** — env `CORS_ALLOWED_ORIGINS` allowlist on all three surfaces. Live: `evil.com` preflight → auth 403 / transaction 403 / gateway 400; `localhost:3000` → 200 / 200 / 204.
4. **X-Request-Id correlation** — `RequestIdFilter` (both Java services, runs before security) generates/propagates the id; `logback-spring.xml` includes it; it's added to RFC7807 bodies AND the realtime event envelope. Live: response echoes the id; the **same id appears in the RFC7807 error body AND propagates into the realtime envelope AND the gateway's fanout log** (end-to-end correlation proven).
5. **Refresh rotation/revocation + security headers + socket room-ownership** —
   - Refresh tokens are opaque + SHA-256-hashed, rotate on use, and reuse-detection **revokes the whole family**. Live: reuse old token → 401; the rotated token is then **also** 401 (family killed).
   - Security headers (`X-Content-Type-Options`, `X-Frame-Options: DENY`, `Referrer-Policy`, `CSP: default-src 'none'`, HSTS) present on Java + gateway responses (verified).
   - `subscribe:tx` room join is now **authorized via transaction-service's own `getByIdScoped` guard** (gateway forwards the socket's token, 200=join, else fail-closed). Live: entitled tx → ack ok+join; unentitled/foreign/random id → ack `{ok:false}`, not joined.

**Bonus fix this wave:** wrong HTTP method on a route returned **500**; now returns **405** with an `Allow` header (RFC7807) in both services — verified live (was the one real bug the orchestrator's own verification caught).

### ✅ Final live gate (combined stack, all 5 containers healthy, verified by orchestrator)
- Builds: all services compile (Docker). **Tests GREEN, no regression: transaction-service 66/66, auth-service 28/28** (run on host via Testcontainers).
- All 5 MUST-fixes verified live (evidence above).
- **No regressions:** PII cross-tenant read still **403**; operator happy path create→park→key-in→request→assign all **2xx**; assigned car appears in driver feed; realtime fan-out fires; driver picker `GET /drivers` **200**; method-mismatch **405**.

## 🚨 Remaining before OPEN PRODUCTION TRAFFIC (honest)
The 5 MUST-fixes are done. What still stands between this and *unsupervised, open* production:
**Operational MUST (config/deploy, not code — do at deploy time):**
1. **Actually set prod secrets**: generate `JWT_SECRET` (`openssl rand -base64 48`), strong DB creds (replace `valet/valet`), and the real `CORS_ALLOWED_ORIGINS`, injected via a secret manager and run with `--spring.profiles.active=prod`. The *mechanism* is built + fail-fast-verified; the *values* are deploy-time config.
2. **Rate-limit the transaction-service + the Socket.IO handshake** at the edge (nginx/gateway) — auth-service login/refresh are limited, but operator writes and the WS handshake rely on the perimeter proxy. Documented in `docs/SECURITY.md §8`.
3. **TLS termination** (HSTS only bites over HTTPS) + reverse proxy that overwrites `X-Forwarded-For` (the per-IP limiter trusts its first hop).

**SHOULD before scale:** Micrometer/Prometheus metrics, structured JSON logs in the prod logback profile (wired, enable it), Lettuce/Hikari pool tuning + container mem limits, gateway `ulimit nofile`, `sync:since(ts)` delta reconciliation on reconnect, Redis Sentinel + Postgres read replica.

**Still pilot-only (not yet built — out of ship-MVP scope):** MinIO/media, notifications, search, analytics, admin mgmt, KeySlot custom alloc, company/location CRUD. One **manual Flutter emulator pass** of operator+driver against the live stack is still outstanding (only `analyze`/`test`/`build web` have run).

**Verdict:** the backend slice is **code-complete and security-hardened to production grade** — cleared for production traffic **once the deploy-time operational items above are set** (real secrets, edge rate-limit on the non-auth surfaces, TLS). No code blockers remain; the residual is standard production *deployment configuration*, not unfinished engineering.

## ⚠️ Operational notes
- `valet_core` init is now idempotent (`infra/initdb`); adding a service DB no longer requires `down -v` — re-run the init script against the live volume (header documents it).
- Realtime in Flutter keeps the REST poll as a **fallback** on socket disconnect (graceful degradation) — intentional.
- This is all **additive**; the existing React + Supabase web app is untouched and still runs.
- Security details + adversarial audit results live in `docs/SECURITY.md`.
