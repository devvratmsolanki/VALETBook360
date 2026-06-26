# Vālet — transaction-service

The **transaction + driver microservice**. Owns the canonical valet lifecycle
state machine and the driver-facing mission endpoints. It is a JWT **resource
server**: it validates the HS256 access tokens minted by the `auth-service` but
issues none of its own.

- Java 21, Spring Boot 3.3.x, Maven, layered (controller / service / repository
  / domain / dto / security / config).
- PostgreSQL 16, database **`valet_core`**. Flyway owns schema + seed.
- Port **8082**. Base paths `/api/transactions/*` and `/api/driver/*`.
- Errors are RFC 7807 `application/problem+json` with the legacy
  `{ code, userMessage, detail }` envelope.

## The state machine (preserved exactly)

```
waiting_for_driver → parked → key_in → requested
                   → driver_assigned → en_route → arrived → delivered
parked → requested                       (guest requests; key still with driver)
(any non-terminal) → cancelled
delivered, cancelled = terminal
```

Legal transitions are enforced in **two** places:

1. `TransactionService.transition(...)` — the single chokepoint every status
   change flows through (reused by future operator endpoints). Illegal moves →
   **409** `ILLEGAL_TRANSITION`.
2. A Postgres `BEFORE UPDATE` trigger (`valet_enforce_transition`) — the same
   adjacency map at the database, so no path (raw SQL, a bad migration, a future
   service) can persist an illegal transition.

The canonical map lives in `ValetStatus.LEGAL_TRANSITIONS` and is pinned by unit
tests (`ValetStatusTransitionTest`).

## Endpoints

### Driver API — `Bearer` access token, `role=driver`, `driverId = sub`

| Method | Path | Transition | Notes |
|---|---|---|---|
| GET  | `/api/driver/assignments` | — | `retrieved_by_driver_id = driverId` AND status ∈ {driver_assigned, en_route, arrived}, newest first |
| POST | `/api/driver/transactions/{id}/en-route`  | driver_assigned → en_route | must belong to caller |
| POST | `/api/driver/transactions/{id}/arrived`   | en_route → arrived | stamps `arrived_at` |
| POST | `/api/driver/transactions/{id}/delivered` | arrived → delivered | stamps `delivered_at` |

- Not your assignment → **403** `NOT_YOUR_ASSIGNMENT`.
- Illegal transition → **409** `ILLEGAL_TRANSITION`.
- Non-driver role → **403** (enforced in the security chain).
- Missing/invalid/expired/wrong-secret/non-`access` token → **401**.

Assignment item shape:
`{ id, carPlate, carMake, carModel, carColor, keyCode, status, guestName, locationId, requestedAt }`

### Debug — `Bearer` (any authenticated caller)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/transactions/{id}` | full transaction; debugging aid for the parallel slice |

## Environment variables

| Var | Default | Purpose |
|---|---|---|
| `SERVER_PORT` | `8082` | HTTP port |
| `DB_URL` | `jdbc:postgresql://localhost:5432/valet_core?stringtype=unspecified` | JDBC URL (`stringtype=unspecified` lets the string map onto the `valet_status` enum) |
| `DB_USER` | `valet` | DB user |
| `DB_PASSWORD` | `valet` | DB password |
| `DB_POOL_MAX` | `10` | Hikari max pool size |
| `JWT_SECRET` | — (required) | **Shared** HS256 secret — must equal the auth-service's secret. ≥ 32 bytes. Falls back to `AUTH_JWT_SECRET` so one compose `.env` value serves both services. |

No secrets are hardcoded. If `JWT_SECRET` is missing or < 32 bytes the app fails
fast at startup.

## Run

### Docker (build context is this directory)

```bash
# from backend/transaction-service/
docker build -t valet-transaction-service .

# needs a reachable Postgres named `postgres` with db `valet_core`
docker run --rm -p 8082:8082 \
  -e DB_URL="jdbc:postgresql://postgres:5432/valet_core?stringtype=unspecified" \
  -e DB_USER=valet -e DB_PASSWORD=valet \
  -e JWT_SECRET="<same-secret-as-auth-service-min-32-bytes>" \
  valet-transaction-service
```

Flyway runs `V1__init_transactions.sql` (enum + table + indexes + trigger) and
`V2__seed_demo_driver_assignments.sql` (the demo seed) on first boot.

### Local Maven

```bash
JWT_SECRET="<min-32-byte-secret>" mvn spring-boot:run
```

(Requires JDK 21 + Maven locally; otherwise use the Docker path above.)

## Seed (the parallel-slice linchpin)

`V2` seeds **3** retrieval missions assigned to the demo driver the auth-service
seeds — referencing the UUID only, never creating the user:

- driver `sub` = `11111111-1111-1111-1111-111111111111`
- company = `22222222-2222-2222-2222-222222222222`
- location = `33333333-3333-3333-3333-333333333333`
- status `driver_assigned`, `requested_at` set, varied cars/plates/guests
- fixed tx ids `aaaaaaa1-0000-0000-0000-00000000000{1,2,3}`

So `GET /api/driver/assignments` returns them immediately with a valid driver
token.

## Example: get a token from auth-service, then call the driver API

```bash
# 1) Log in to the auth-service (port 8081) as the demo driver to get an access token.
ACCESS=$(curl -s -X POST http://localhost:8081/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"driver@valet.test","password":"<demo-driver-password>"}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["accessToken"])')

# 2) List the driver's missions.
curl -s http://localhost:8082/api/driver/assignments \
  -H "Authorization: Bearer $ACCESS" | python3 -m json.tool

# 3) Progress the first mission through the lifecycle.
TX=aaaaaaa1-0000-0000-0000-000000000001
curl -s -X POST http://localhost:8082/api/driver/transactions/$TX/en-route  -H "Authorization: Bearer $ACCESS"
curl -s -X POST http://localhost:8082/api/driver/transactions/$TX/arrived   -H "Authorization: Bearer $ACCESS"
curl -s -X POST http://localhost:8082/api/driver/transactions/$TX/delivered -H "Authorization: Bearer $ACCESS"

# Illegal jump (skips en_route) → 409 problem+json:
curl -i -X POST http://localhost:8082/api/driver/transactions/aaaaaaa1-0000-0000-0000-000000000002/arrived \
  -H "Authorization: Bearer $ACCESS"
```

> The token must be signed with the **same** `JWT_SECRET` both services share. In
> tests we forge such a token directly (see `support/TestTokens`) so the resource
> server can be exercised without standing up the auth-service.

## Tests

| Test | Type | Covers |
|---|---|---|
| `ValetStatusTransitionTest` | pure unit | every legal edge + many illegal edges + immutability + terminal states |
| `TransactionServiceTest` | unit (Mockito) | service guard: 409 illegal, 403 ownership, 404 unknown, timestamp stamping |
| `JwtServiceTest` | unit | HS256 validation: claims, `typ=access`, wrong-secret, expired, garbage, short-secret |
| `DriverApiIntegrationTest` | Testcontainers (Postgres 16) | Flyway enum + trigger + seed, `GET /assignments`, full transition happy path, 409/403/401 paths — using a forged-but-correctly-signed token |

```bash
mvn test
```

The integration test uses **Testcontainers**; if Docker is unavailable it fails
fast at container start and the three pure unit suites still run. See the build
report below for how this was verified in a Docker-Desktop-only environment.

## Build & test results (honest, in this environment)

The dev host had only JDK 8 + Docker (no JDK 21, no Maven). Everything was built
and run inside the `maven:3.9-eclipse-temurin-21` image:

- **Compile + 3 unit suites: PASS** — `Tests run: 44, Failures: 0, Errors: 0`
  (`ValetStatusTransitionTest` 32, `JwtServiceTest` 6, `TransactionServiceTest` 6).
- **Testcontainers integration test:** could **not** run from inside the nested
  Maven build container — Testcontainers' Docker-Desktop socket discovery NPEs
  when nested under Docker Desktop (a host/DinD limitation, not a code problem).
  It will run normally on any host with a reachable Docker daemon / in CI.
- **End-to-end verified instead** by booting the real jar against a real
  Postgres 16 container and curling every path. All passed:
  - Flyway migrated `V1` (enum + trigger) and `V2` (seed); Hibernate
    `ddl-auto: validate` passed against the Flyway schema.
  - `GET /api/driver/assignments` → 3 seeded rows, newest-first, exact shape.
  - Happy path `en-route → arrived → delivered` stamped `arrived_at` /
    `delivered_at`.
  - Illegal jump `driver_assigned → arrived` → **409** `ILLEGAL_TRANSITION`.
  - Re-deliver terminal row → **409**.
  - Foreign driver → **403** `NOT_YOUR_ASSIGNMENT`; `role=valet` → **403**;
    no token → **401**; `typ=refresh` → **401**; wrong-secret signature → **401**.
  - **DB trigger defense:** a raw `UPDATE ... SET status='delivered'` on a
    `driver_assigned` row was rejected by Postgres:
    `ERROR: Illegal valet status transition: driver_assigned -> delivered`.
- **Docker image:** `docker build .` from this directory succeeds (multi-stage,
  slim JRE 21, non-root).
```
```
