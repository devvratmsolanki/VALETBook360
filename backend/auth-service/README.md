# Vālet — auth-service

Identity, roles and tenancy microservice for the Vālet re-platform (off
React + Supabase → Flutter + Spring Boot microservices + PostgreSQL + Docker).

This is the **first service of the parallel slice**. It owns login, JWT
issue/refresh, profile (`/me`), staff registration and logout. Every other
service validates the access tokens this service mints (see *JWT validation
contract* below).

- **Java 21**, Spring Boot 3.3.x, Maven, layered (controller / service /
  repository / domain / dto / security / config).
- **PostgreSQL 16**, database `valet_auth`. Schema + seed via **Flyway**.
- **Port 8081**, base path `/auth/*`. Permissive CORS for the dev slice.
- Errors are **RFC 7807** `application/problem+json` with extra `code` /
  `userMessage` fields (ported from the legacy `ServiceError` envelope).
- **JWT HS256**, refresh tokens are opaque, persisted (SHA-256 hashed) and
  **rotated** on every refresh, with reuse detection.

---

## Run

### Option A — Docker (no local JDK/Maven needed)

The multi-stage `Dockerfile` builds with Maven inside the image and runs on a
slim JRE 21. It is built from context `backend/auth-service/` and expects a
Postgres reachable at host `postgres`, database `valet_auth`.

```bash
# From repo root — start a Postgres + the service.
docker network create valet-net 2>/dev/null || true

docker run -d --name valet-postgres --network valet-net \
  -e POSTGRES_DB=valet_auth \
  -e POSTGRES_USER=valet \
  -e POSTGRES_PASSWORD=valet \
  -p 5432:5432 postgres:16-alpine

docker build -t valet/auth-service backend/auth-service

docker run -d --name valet-auth --network valet-net -p 8081:8081 \
  -e DB_URL='jdbc:postgresql://postgres:5432/valet_auth?stringtype=unspecified' \
  -e DB_USER=valet \
  -e DB_PASSWORD=valet \
  -e JWT_SECRET='change-me-to-a-32+byte-random-secret-string' \
  valet/auth-service
```

> The container's Postgres host is `postgres`; in the example above we name the
> Postgres container `valet-postgres` but join it to the same network. In the
> root `docker-compose.yml` (written separately) the service name **must be
> `postgres`** so `DB_URL` resolves — see *docker-compose contract* below.

### Option B — local Maven (requires JDK 21 + Maven on host)

```bash
cd backend/auth-service
export JWT_SECRET='a-local-dev-secret-at-least-32-bytes-long!!'
# Point at any Postgres; defaults to localhost:5432/valet_auth valet/valet.
mvn spring-boot:run
```

### Build & test

```bash
cd backend/auth-service
mvn -q -DskipTests=false test     # unit + Testcontainers integration tests
mvn -q clean package -DskipTests  # build the runnable jar (target/auth-service.jar)
```

The integration test uses **Testcontainers** and needs a working Docker daemon
on the machine running the tests. If Docker is unavailable, the integration
test is skipped at the container-start boundary; the JWT unit tests still run.

---

## Environment variables

| Var | Required | Default | Purpose |
|---|---|---|---|
| `JWT_SECRET` | **yes** | — (boot fails if unset/<32 bytes) | HS256 signing secret. **Must be byte-identical across every service** that validates tokens. ≥ 32 bytes. |
| `DB_URL` | no | `jdbc:postgresql://localhost:5432/valet_auth?stringtype=unspecified` | JDBC URL. Keep `stringtype=unspecified` so the `user_role` PG enum binds. |
| `DB_USER` | no | `valet` | DB username. |
| `DB_PASSWORD` | no | `valet` | DB password. |
| `SERVER_PORT` | no | `8081` | HTTP port. |
| `DB_POOL_MAX` | no | `10` | Hikari max pool size. |
| `AUTH_JWT_ISSUER` | no | `valet-auth` | JWT `iss` claim (other services may verify it). |
| `AUTH_JWT_ACCESS_TTL` | no | `900` (15m) | Access-token TTL seconds. |
| `AUTH_JWT_REFRESH_TTL` | no | `2592000` (30d) | Refresh-token TTL seconds. |
| `AUTH_BOOTSTRAP_ADMIN_EMAIL` / `_PASSWORD` / `_NAME` | no | empty (no-op) | Optional one-time first-admin seed if you ever start with an empty DB and skip the demo seed. |

### docker-compose contract (for the root compose file)

The service assumes, and your `docker-compose.yml` must provide:

- a Postgres service named **`postgres`**, database **`valet_auth`**,
  user/password supplied via env (example uses `valet`/`valet`);
- `JWT_SECRET` passed to the auth-service container (and shared with all other
  services);
- this service built from context `backend/auth-service/`, published on `8081`,
  `depends_on` postgres (ideally with a healthcheck).

```yaml
  auth-service:
    build: ./backend/auth-service
    ports: ["8081:8081"]
    environment:
      DB_URL: jdbc:postgresql://postgres:5432/valet_auth?stringtype=unspecified
      DB_USER: ${POSTGRES_USER:-valet}
      DB_PASSWORD: ${POSTGRES_PASSWORD:-valet}
      JWT_SECRET: ${JWT_SECRET}
    depends_on:
      postgres:
        condition: service_healthy
```

---

## Seeded demo accounts (mandatory, fixed contract)

Flyway `V2__seed_demo_users.sql` seeds exactly these on first migration:

| Role | Email | Password | id | companyId | locationId |
|---|---|---|---|---|---|
| driver | `driver@valet.demo` | `Driver123` | `11111111-1111-1111-1111-111111111111` | `22222222-2222-2222-2222-222222222222` | `33333333-3333-3333-3333-333333333333` |
| admin | `admin@valet.demo` | `Admin123` | `44444444-4444-4444-4444-444444444444` | null | null |

The demo **driver** is the linchpin the parallel services + Flutter app align
to. The **admin** lets you exercise `/auth/register`.

---

## API + example curl

Base URL `http://localhost:8081`.

### `POST /auth/login`
```bash
curl -sS -X POST http://localhost:8081/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"driver@valet.demo","password":"Driver123"}'
```
`200`:
```json
{
  "accessToken": "<jwt>",
  "refreshToken": "<opaque>",
  "tokenType": "Bearer",
  "expiresIn": 900,
  "user": {
    "id": "11111111-1111-1111-1111-111111111111",
    "email": "driver@valet.demo",
    "name": "Demo Driver",
    "role": "driver",
    "companyId": "22222222-2222-2222-2222-222222222222",
    "locationId": "33333333-3333-3333-3333-333333333333",
    "active": true
  }
}
```
`401` on bad credentials (generic `INVALID_CREDENTIALS`, no enumeration).

### `GET /auth/me`  (Bearer access token)
```bash
curl -sS http://localhost:8081/auth/me \
  -H "Authorization: Bearer $ACCESS"
```
Returns the `user` object shape above. Re-reads the live row, so a disabled
account is rejected even while the token is still within its TTL.

### `POST /auth/refresh`  (rotates)
```bash
curl -sS -X POST http://localhost:8081/auth/refresh \
  -H 'Content-Type: application/json' \
  -d "{\"refreshToken\":\"$REFRESH\"}"
```
Returns a **new** `accessToken` + `refreshToken`; the old refresh token is
revoked. Replaying a rotated-out token returns `401` and revokes the whole
token family (theft detection).

### `POST /auth/register`  (Bearer access; caller role admin or manager)
```bash
curl -sS -X POST http://localhost:8081/auth/register \
  -H "Authorization: Bearer $ADMIN_ACCESS" \
  -H 'Content-Type: application/json' \
  -d '{
        "email":"valet1@acme.test",
        "password":"Valet1234",
        "name":"Valet One",
        "role":"valet",
        "companyId":"22222222-2222-2222-2222-222222222222",
        "locationId":null
      }'
```
`201` with the created user. Rules enforced server-side:
- only `admin`/`manager` may create (`403 INSUFFICIENT_PERMISSIONS` otherwise);
- a `manager` may only create within its **own** `companyId`
  (`403 CROSS_TENANT`) and may **not** create an `admin`;
- non-admin roles require a `companyId` (`400 TENANT_REQUIRED`);
- duplicate email → `409 EMAIL_TAKEN`.

Role values on the wire are the DB-canonical names: `admin`, `manager`,
`valet`, `driver` (the legacy frontend's "company" === `manager`).

### `POST /auth/logout`  (Bearer access)
```bash
# Revoke a specific refresh token:
curl -sS -X POST http://localhost:8081/auth/logout \
  -H "Authorization: Bearer $ACCESS" \
  -H 'Content-Type: application/json' \
  -d "{\"refreshToken\":\"$REFRESH\"}"

# Or revoke ALL sessions for the caller:
curl -sS -X POST http://localhost:8081/auth/logout \
  -H "Authorization: Bearer $ACCESS" \
  -H 'Content-Type: application/json' \
  -d '{"allSessions":true}'
```
`204 No Content`.

### Health
`GET /actuator/health` (and `/health/readiness`, `/health/liveness`) — public,
for compose / k8s probes.

---

## JWT validation contract (for every other service)

To validate a Vālet access token, a downstream service needs:

- **Algorithm:** `HS256` (HMAC-SHA256).
- **Secret:** the shared symmetric secret from env **`JWT_SECRET`** — byte-for-byte
  identical to this service's. (UTF-8 bytes of the string, ≥ 32 bytes.)
- **Verify:** signature **and** `exp`; require `iss` = `valet-auth` (override via
  `AUTH_JWT_ISSUER` — keep it identical fleet-wide); require claim `typ` =
  `"access"` (refresh handles are opaque, never JWTs — reject any JWT without
  `typ=access`).
- **Claims:**

  | Claim | Type | Meaning |
  |---|---|---|
  | `sub` | string (UUID) | user id |
  | `email` | string | user email |
  | `role` | string | one of `admin` / `manager` / `valet` / `driver` |
  | `companyId` | string (UUID) — **omitted when null** | tenant; absent for tenant-less admins |
  | `locationId` | string (UUID) — **omitted when null** | location pin; absent if none |
  | `iat` | numeric date | issued at |
  | `exp` | numeric date | expiry (issue + 15m) |
  | `typ` | string | always `"access"` |
  | `iss` | string | `valet-auth` |
  | `name` | string | display name (convenience; not part of the minimal contract) |

  > Note: `companyId` / `locationId` are **absent** (not `null`) in the token
  > when the user has none. Treat a missing claim as `null`.

Tenant scoping (every downstream query filtered by the `companyId` claim, admins
exempt) is enforced by the consuming services / gateway, per design doc 10.2.
