# ValetPro3 Backend — Security Reference

This document covers the threat model, hardening decisions, verified control outcomes,
rotation procedures, and remaining risks for the re-platform backend
(auth-service, transaction-service, realtime-gateway).

---

## 1. CORS Configuration

### What changed

All three services previously used a wildcard CORS origin (`*` or `setAllowedOriginPatterns("*")`).
They now read a shared `CORS_ALLOWED_ORIGINS` environment variable — a comma-separated list of
exact origins or wildcard-port patterns — so the same `.env` line controls the entire stack.

| Service | Source of truth |
|---------|----------------|
| auth-service | `SecurityConfig.corsAllowedOriginsRaw` from `${CORS_ALLOWED_ORIGINS}` |
| transaction-service | same |
| realtime-gateway | `corsOriginValidator()` function in `server.js` |

**Dev default** (when `CORS_ALLOWED_ORIGINS` is unset):
`http://localhost:*,http://127.0.0.1:*`

This permits Flutter hot-reload and any local web dev server without further config.

**Production requirement:** set `CORS_ALLOWED_ORIGINS` to the exact origin(s) of your
Flutter web build and admin panel, e.g.:
```
CORS_ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com
```

Do NOT use a bare `*` in production. The wildcard-port suffix (`:*`) is supported for
local dev only via the pattern-match logic in `SecurityConfig.parseOrigins()` and
`corsOriginValidator()` in the gateway.

### Verified outcomes (post-rebuild probes)

| Probe | Origin | Service | HTTP | Result |
|-------|--------|---------|------|--------|
| Preflight | http://localhost:3000 | auth-service | 200 + ACAO header | PASS |
| Preflight | http://evil.com | auth-service | 403, no ACAO header | PASS |
| Preflight | http://localhost:8080 | transaction-service | 200 + ACAO header | PASS |
| Preflight | http://evil.com | transaction-service | 403, no ACAO header | PASS |
| Preflight | http://localhost:3000 | realtime-gateway | 204 + ACAO header | PASS |
| GET w/ origin | http://evil.com | realtime-gateway | 400 Bad Request | PASS |

---

## 2. JWT Secret — Hygiene and Rotation

### Current state

The shared HS256 secret is controlled by the `JWT_SECRET` environment variable. **Every
service that mints or validates these tokens must run with the byte-identical secret** —
because HS256 is symmetric, the same key both signs (auth-service) and verifies
(transaction-service, realtime-gateway). If the values diverge by a single byte, every
auth-issued token fails verification downstream and all callers get 401.

All three services enforce a minimum of 32 bytes (the HS256 floor) at startup and refuse
to start if the constraint is violated:

- **auth-service** — `JwtService` throws `IllegalStateException` if `< 32` bytes at bean
  construction, AND a dedicated `SecretValidator` (`InitializingBean`) runs eagerly at
  context init and aborts boot with a clear, remediation-oriented message if the secret is
  null/blank/`< 32` bytes. The validator makes the failure loud and first, independent of
  the active Spring profile.
- **transaction-service** — `JwtService`: same `< 32`-byte check, same abort.
- **realtime-gateway** — `config.js`: `Buffer.byteLength(JWT_SECRET, 'utf8') < 32` check
  throws at `require()` time.

The compose default `dev-only-secret-change-me-32bytes-min!!` (40 bytes) satisfies the
constraint for local dev but **must not be used in any other environment**.

### Production profile — no insecure fallback (fail-fast)

The base `application.yml` keeps the dev defaults (empty-string fallback for `JWT_SECRET`,
`valet`/`valet` for the DB) so local `docker compose` boots without extra config. The
**`prod` Spring profile** (`application-prod.yml`) deliberately removes every fallback:

```yaml
spring:
  datasource:
    url: ${DB_URL}        # no localhost fallback
    username: ${DB_USER}  # no "valet" fallback
    password: ${DB_PASSWORD}
auth:
  jwt:
    secret: ${JWT_SECRET} # no empty fallback
```

With an unset env var, `${VAR}` (no `:default`) resolves to empty, and `SecretValidator`
(JWT) plus the datasource pool (DB) reject it at boot. **Run production with
`--spring.profiles.active=prod` (or `SPRING_PROFILES_ACTIVE=prod`)** so a missing secret or
DB credential is a hard, immediate startup failure rather than a silent fall-back to a known
weak value. Verified: starting auth-service under the `prod` profile with `JWT_SECRET=""`
aborts boot with `FATAL: JWT signing secret is missing or blank...` and a non-zero exit.

### Generating a production secret

```bash
openssl rand -base64 48
```

This produces a 48-byte-encoded string (64 printable characters), well above the 32-byte minimum.

### Rotation procedure

Because all three services share one symmetric secret (HS256), rotation requires a
coordinated rolling restart. Access tokens have a 15-minute TTL by default.

1. **Generate** the new secret: `openssl rand -base64 48`
2. **Update** the secret in your secret manager (AWS Secrets Manager, GCP Secret Manager,
   Vault, etc.). Do not update `.env` files in the repository.
3. **Rolling restart** all three services within one `AUTH_JWT_ACCESS_TTL` window (default 900s):
   - Restart `auth-service` first — it will begin minting tokens with the new secret.
   - Restart `transaction-service` and `realtime-gateway` — they will now only accept
     tokens signed by the new secret. Any in-flight 15-minute token from the old secret
     will be rejected after this point.
   - To avoid a brief outage during the TTL window: implement dual-key validation
     (accept both old and new secret for one TTL window), or accept a brief re-auth
     cycle for active sessions.
4. **Verify** the stack is healthy: poll `/actuator/health/readiness` on both Java services
   and `/healthz` on the gateway.
5. **Archive/delete** the old secret value from your secret manager.

> **HS256 single-key caveat.** Because the contract uses one symmetric key with no
> key-rotation/`kid` support, there is an unavoidable **brief 401 window** during a rotation:
> once a validating service has been restarted onto the new secret, any still-live access
> token signed with the OLD secret is rejected until the client re-authenticates (access
> TTL is 15 min by default, so the blast radius is at most one TTL). To eliminate the window
> entirely you would need dual-key validation (accept old+new for one TTL) — not yet
> implemented. For a pilot, accept the short re-auth blip and rotate during a low-traffic
> window.

### DB credential rotation

The database user/password are supplied via `DB_USER` / `DB_PASSWORD` (and `DB_URL`).
Under the `prod` profile there is no `valet`/`valet` fallback, so these must be set.

1. Create the new role/password in PostgreSQL (or `ALTER ROLE ... PASSWORD ...`), keeping
   the old credential valid during the cutover.
2. Update `DB_USER` / `DB_PASSWORD` in the secret manager.
3. Rolling-restart `auth-service` and `transaction-service` (each owns its own database —
   `valet_auth` and `valet_core`). HikariCP opens fresh connections with the new credential
   on restart.
4. Verify readiness, then revoke the old credential in PostgreSQL.

Unlike the JWT secret, DB credentials are per-service (not a shared byte-identical contract),
so each service can be rotated independently.

### Issuer validation note

The transaction-service deliberately does NOT enforce the `iss` claim (see comment in
`JwtService.java`). This is an intentional decoupling decision: signature + typ + role are
the binding contract. If you ever run multiple auth-service instances with different issuers
(multi-tenant future work), you will need to add issuer validation here.

---

## 3. Operator Authorization — Defence in Depth

`/api/operator/**` is now protected by three independent layers:

| Layer | Where | What it checks | Failure response |
|-------|-------|----------------|-----------------|
| 1 — Security chain URL rule | `transaction-service/SecurityConfig` | `ROLE_VALET`, `ROLE_MANAGER`, or `ROLE_ADMIN` (Spring authority produced by `JwtAuthenticationFilter`) | 403 FORBIDDEN (generic, before controller is reached) |
| 2 — `@PreAuthorize` on `OperatorController` | AOP, after filter chain | Same role set via Spring method security | 403 FORBIDDEN (via `AccessDeniedHandler`) |
| 3 — `operatorPrincipal()` in-controller | Controller method body | role ∈ {valet, manager, admin} **AND** `companyId != null` | 403 NOT_AN_OPERATOR / NO_TENANT (precise userMessage) |

`@EnableMethodSecurity` was added to `SecurityConfig` to activate layer 2.

Authority naming: `JwtAuthenticationFilter` in both services maps the JWT `role` claim to
`ROLE_<ROLE_UPPERCASE>` (e.g. `role=valet` → authority `ROLE_VALET`). This is why the
security chain uses `hasAnyRole("VALET","MANAGER","ADMIN")` (Spring prepends `ROLE_`), and
`@PreAuthorize` uses the same form.

### Verified outcomes (post-rebuild probes)

| Probe | Token role | Expected HTTP | Actual | Result |
|-------|-----------|--------------|--------|--------|
| GET /api/operator/transactions | no token | 401 | 401 | PASS |
| GET /api/operator/transactions | driver | 403 | 403 | PASS |
| GET /api/operator/transactions | valet (operator) | 200 | 200 | PASS |
| GET /api/operator/transactions | admin (no companyId) | 403 NO_TENANT | 403 | PASS |
| GET /api/driver/assignments | driver | 200 | 200 | PASS |
| GET /api/driver/assignments | valet (operator) | 403 | 403 | PASS |
| POST /api/operator/transactions/{id}/park | driver | 403 FORBIDDEN | 403 | PASS |

Note on the admin 403: the admin demo account has no `companyId` in its JWT, so it passes
layers 1 and 2 (role=ADMIN is permitted), then fails layer 3 with `NO_TENANT`. This is
correct behaviour — an admin must be linked to a company to use the operator floor.

---

## 4. JWT Verification — Adversarial Probe Results

| Probe | Token type | Expected | Actual | Result |
|-------|-----------|----------|--------|--------|
| No `Authorization` header | — | 401 | 401 | PASS |
| Valid format, wrong secret | access (forged HS256) | 401 | 401 | PASS |
| Valid signature, `typ=refresh` (crafted with dev secret) | access-shaped but wrong typ | 401 | 401 | PASS |
| Opaque refresh token used as Bearer | — | 401 | 401 | PASS |

The refresh token is opaque (stored in `refresh_tokens` table, not a JWT). Any attempt to
use it as a Bearer access token fails JJWT parsing immediately (not a valid JWT structure)
and results in 401.

---

## 5. Input Validation

| Probe | Input | Expected | Actual | Result |
|-------|-------|----------|--------|--------|
| Oversized `carPlate` (5000 chars) | POST /api/operator/transactions | 400 VALIDATION_ERROR | 400 | PASS |
| Empty body `{}` | POST /api/operator/transactions | 400 VALIDATION_ERROR | 400 | PASS |
| Malformed JSON | POST /api/operator/transactions | 400 MALFORMED_REQUEST | 400 | PASS |
| SQL injection in `carMake` | POST /api/operator/transactions | 201 (stored as literal string) | 201 | PASS |

SQL injection is not a risk: Spring Data JPA uses parameterized queries for all operations.
The injected string was stored verbatim in the database without execution.

Error responses never leak: stack traces, SQL, class names, or internal error messages.
The `GlobalExceptionHandler` in both services maps all unexpected exceptions to a generic
`INTERNAL_ERROR` 500 with no detail. `server.error.include-stacktrace=never` is set in
both `application.yml` files as a belt-and-suspenders measure.

---

## 6. Tenant Isolation

**Verified:** An operator cannot read or mutate a transaction belonging to another company.

A second-company transaction was inserted directly via psql:
```sql
INSERT INTO valet_transactions (id, company_id, ...) VALUES ('deadbeef-...', 'aaaa...', ...);
```

- `POST /api/operator/transactions/deadbeef-.../park` with the operator token → **403 NOT_YOUR_TRANSACTION** (correct)
- `GET /api/operator/transactions` (active floor feed) → does not include the other company's TX (correct)

Mechanism: `TransactionService.loadOwnedByCompany()` compares `tx.companyId` to
`principal.companyId()` from the JWT. A mismatch is a 403, not a 404, so existence is
not revealed through the error code on *operator* write endpoints.

---

## 7. Actuator Exposure

Only `health` and `info` endpoints are exposed (`management.endpoints.web.exposure.include: health,info`).
Sensitive endpoints (`env`, `beans`, `mappings`, `heapdump`, etc.) return 401 because they
are not in the allow-list and fall through to the security chain's `anyRequest().authenticated()` rule.

---

## 8. Rate Limiting + Account Lockout — IMPLEMENTED (auth-service)

The auth-service enforces two Redis-backed, cluster-safe login abuse controls. They are
deliberately asymmetric in scope: the per-account lockout is the precise primary control;
the per-IP ceiling is a coarse circuit-breaker for genuine floods.

Implementation: Redis fixed-window counters (`INCR` + `EXPIRE` via Lettuce /
`StringRedisTemplate`) behind an injectable `LoginGuardStore` interface — chosen over the
heavier Bucket4j+Redis wiring for a smaller, easy-to-verify footprint. Counter state is in
Redis so the limits hold across all auth-service replicas, not per-JVM.

### Per-IP failure ceiling (coarse circuit-breaker)

`RateLimitFilter` (a `OncePerRequestFilter` placed first in the Spring Security chain,
self-scoped to `POST /auth/login` and `POST /auth/refresh`) performs a **read-only check**
of the per-IP failure counter before the controller runs. The counter itself is incremented
in `AuthService.login` via `LoginGuardService.recordFailure(email, clientIp)` only when a
login attempt actually fails (wrong password, non-existent account).

**Key design decision — why only failures count:**
Behind NAT / a corporate proxy / CGNAT, hundreds of users may share a single egress IP.
Counting all requests (or even just successful logins) against a per-IP bucket would lock
out innocent users the moment one account in the same office runs into brute-force lockout.
By counting only failures, the per-IP ceiling is hit only when a genuine bot is hammering
many credentials from one source — normal mixed traffic from a shared exit node never
approaches the threshold.

- Default: **100 failures per client IP per 60s**, then HTTP **429** with the RFC 7807
  envelope (`code: RATE_LIMITED`, friendly `userMessage`) and a `Retry-After` header.
- A successful login from that IP does NOT decrement or reset the counter. The counter
  decays naturally when the fixed window expires.
- Tunable via `AUTH_RL_IP_MAX` / `AUTH_RL_IP_WINDOW`.

### Per-account lockout (precise primary control)

`LoginGuardService`, enforced inside `AuthService.login`:
- After **5 consecutive failed logins for one email within 900s**, the email is locked for
  **900s**. While locked, even a **correct** password returns **429** `ACCOUNT_LOCKED` with
  `Retry-After`, until the window expires.
- A **successful** login resets the per-account failure counter (and clears any lock).
- Failures are counted against the presented email even when the account does not exist, so
  password-spray over guessed accounts still triggers lockout (without leaking existence —
  the failure response stays the generic `INVALID_CREDENTIALS` 401).
- Tunable via `AUTH_LOCK_MAX_FAILURES` / `AUTH_LOCK_WINDOW` / `AUTH_LOCK_SECONDS`.

### Design intent summary

| Scenario | Per-account | Per-IP |
|----------|-------------|--------|
| Brute-force on one account | Locks after 5 failures (precise control) | Counter increments toward ceiling |
| Different account from same IP (shared NAT) | Independent counter — not affected | Only if that account fails too |
| Genuine flood from one IP (many different accounts) | Per-account locks for targeted addresses | Per-IP ceiling trips after 100 failures total |

If a reverse proxy in front cannot supply a per-real-client signal (e.g. because the
network is large CGNAT with no per-subscriber header), the primary protection is the
per-account lockout. Raise `AUTH_RL_IP_MAX` further or rely on a WAF / CDN rate-limiter
at the perimeter for finer per-client control.

### Client IP extraction

Behind a reverse proxy (prod), the first hop of `X-Forwarded-For` is used
(`AUTH_RL_TRUST_XFF=true`, the default). **Trust assumption:** a single trusted proxy
sets/overwrites the XFF header. If the service is ever exposed directly to the internet,
set `AUTH_RL_TRUST_XFF=false`, otherwise a client could spoof XFF to rotate its apparent
IP and evade the per-IP ceiling. See residual-risk note in Section 10.

### Health endpoints are never rate limited

The filter only matches the two auth POSTs; `/actuator/health/**` is excluded.

### Fail-open

`RedisLoginGuardStore` wraps every Redis call: on a Redis outage it logs WARN and returns
a non-blocking value, so an infra blip degrades to "no rate limiting" rather than "nobody
can log in". (Redis is healthchecked in compose, so this path is exceptional.)

### Still outstanding (other services)

- `POST /api/operator/transactions` (transaction-service) — not yet rate limited.
- realtime-gateway Socket.IO handshake — not yet rate limited.

These should be added at the API gateway / reverse proxy layer (nginx, ALB, Cloudflare) or
mirror the auth-service approach. A perimeter rate limit is still recommended in front of
all services for defence in depth.

---

## 9. Cross-Tenant Read Leak — IDENTIFIED RISK

**`GET /api/transactions/{id}` has no tenant or ownership check.** Any authenticated user
(including drivers) can retrieve the full transaction record for any UUID, including:
- `guestName`, `guestPhone` (PII)
- `carPlate`, `carMake`, `carModel`, `carColor`
- `companyId`, `locationId`
- All lifecycle timestamps

This endpoint is documented as a "Bearer-protected debugging aid for the parallel slice"
in `TransactionController.java` and is not currently linked from any role-specific UI,
but it is reachable with any valid JWT.

### Must-fix before production

Add a tenant/ownership guard in `TransactionController.getById()` that either:
(a) Restricts to the caller's own company (for operator/manager/admin), or
(b) Restricts to the assigned driver (for driver role), or
(c) Removes the endpoint entirely if it is not needed in production.

The `TransactionService` already provides `loadOwnedByCompany()` and `loadOwnedByDriver()`
for exactly this purpose.

---

## 10. Remaining Security Risks — Ranked

### Must-Fix Before Production

| # | Risk | Severity | Fix |
|---|------|----------|-----|
| 1 | ~~No rate limiting on `/auth/login`, `/auth/refresh`~~ | ~~Critical~~ **RESOLVED (auth-service)** | Redis failure-only per-IP ceiling (100/60s) + per-account lockout; see Section 8. Transaction-service / gateway still need a perimeter limit. |
| 2 | `GET /api/transactions/{id}` has no tenant isolation — any authenticated user reads any transaction | **Critical** | Add ownership guard in `TransactionController`; see Section 9 |
| 3 | Default JWT secret (`dev-only-secret-change-me-32bytes-min!!`) committed in `.env` and `.env.example` | **Critical** (dev default) | Rotate before any non-local deployment; move to secret manager. The `prod` profile now removes the fallback so a missing secret fails-fast at boot (Section 2). |
| 4 | DB credentials (`DB_USER=valet / DB_PASSWORD=valet`) are trivially guessable | **High** | Strong random password; PostgreSQL TLS in production. The `prod` profile removes the `valet`/`valet` fallback (fail-fast). |
| 5 | ~~No brute-force lockout on login~~ | ~~High~~ **RESOLVED (auth-service)** | Per-account lockout after 5 failures / 15 min, correct password blocked while locked; see Section 8. |

### Post-Pilot / Pre-Scale

| # | Risk | Severity | Fix |
|---|------|----------|-----|
| 6 | TOCTOU on first-admin creation in `autoCreateProfile` | **Medium** | Add a partial unique index on `(role='admin')` per the existing comment in `AuthContext.jsx` |
| 7 | Refresh-token family tracking: no refresh-token rotation or family invalidation on theft | **Medium** | Implement refresh-token rotation (issue new refresh on each use, invalidate old) |
| 8 | No Content-Security-Policy, HSTS, or security headers on HTTP responses | **Medium** | Add via reverse proxy (nginx/Cloudflare) or a Spring `OncePerRequestFilter` |
| 9 | Transaction-service issuer claim not validated (`JwtService.java` comment) | **Low** | Enforce `issuer` claim validation if multiple auth issuers are ever introduced |
| 10 | Socket.IO room subscription (`subscribe:tx`) accepts any string ID — no ownership check | **Low** | Validate the tx ID belongs to the caller's company or driver before `socket.join()` |
| 11 | No mTLS between microservices; inter-service calls go over the compose bridge network | **Low** | Add mTLS or network policy for production K8s; compose bridge is acceptable for dev |
| 12 | Actuator endpoints require auth but are not rate-limited | **Low** | Include in general rate-limit solution |
| 13 | **XFF spoofing residual risk.** The login rate limiter trusts the first hop of `X-Forwarded-For` (`AUTH_RL_TRUST_XFF=true`). Behind a correctly configured single reverse proxy this is safe, but if the proxy does NOT strip/overwrite a client-supplied `X-Forwarded-For`, or auth-service is exposed directly, a client could forge XFF to rotate its apparent IP and dodge the **per-IP** limit. (The **per-account** lockout is unaffected — it keys on email, not IP.) | **Medium** | Ensure the edge proxy overwrites `X-Forwarded-For`; or set `AUTH_RL_TRUST_XFF=false` if there is no trusted proxy. |

---

## 11. Files Changed in This Hardening Pass

| File | Change |
|------|--------|
| `backend/auth-service/src/main/java/com/valet/auth/config/SecurityConfig.java` | Replace wildcard CORS with `CORS_ALLOWED_ORIGINS` env-driven allowlist |
| `backend/transaction-service/src/main/java/com/valet/transaction/config/SecurityConfig.java` | Same CORS change; add `/api/operator/**` URL rule; add `@EnableMethodSecurity` |
| `backend/transaction-service/src/main/java/com/valet/transaction/controller/OperatorController.java` | Add class-level `@PreAuthorize("hasAnyRole('VALET','MANAGER','ADMIN')")` |
| `backend/realtime-gateway/src/server.js` | Replace `origin:'*'` with `corsOriginValidator()` function reading `CORS_ALLOWED_ORIGINS` |
| `infra/docker-compose.yml` | Pass `CORS_ALLOWED_ORIGINS` env var to all three services |
| `infra/.env.example` | Document `CORS_ALLOWED_ORIGINS`; add rotation procedure for `JWT_SECRET` |
| `docs/SECURITY.md` | This file |

### Production-hardening pass (rate limit + lockout + secret fail-fast)

| File | Change |
|------|--------|
| `backend/auth-service/pom.xml` | Add `spring-boot-starter-data-redis`; add Testcontainers `testcontainers` (Redis) for tests |
| `backend/auth-service/src/main/resources/application.yml` | Add `spring.data.redis` config; add `auth.login-guard.*` tunables |
| `backend/auth-service/src/main/resources/application-prod.yml` | **New.** Prod profile with NO insecure fallback for `JWT_SECRET` / `DB_URL` / `DB_USER` / `DB_PASSWORD` (fail-fast) |
| `backend/auth-service/.../config/SecretValidator.java` | **New.** Eager `InitializingBean` that aborts boot if the JWT secret is null/blank/`<32` bytes |
| `backend/auth-service/.../config/LoginGuardProperties.java` | **New.** `@ConfigurationProperties` for the rate-limit / lockout tunables |
| `backend/auth-service/.../security/ratelimit/LoginGuardStore.java` | **New.** Injectable counter-store interface (Redis impl + in-memory fake for tests) |
| `backend/auth-service/.../security/ratelimit/RedisLoginGuardStore.java` | **New.** Redis `INCR`+`EXPIRE` store; fails open on Redis errors |
| `backend/auth-service/.../security/ratelimit/LoginGuardService.java` | **New.** Per-IP failure-only rate limit + per-account lockout logic |
| `backend/auth-service/.../security/ratelimit/RateLimitFilter.java` | **New.** `OncePerRequestFilter` gating POST `/auth/login` + `/auth/refresh`; read-only per-IP check; XFF first-hop IP; renders 429 RFC 7807 + `Retry-After` |
| `backend/auth-service/.../config/SecurityConfig.java` | Register `RateLimitFilter` first in the chain; suppress its servlet auto-registration; enable `LoginGuardProperties` |
| `backend/auth-service/.../service/AuthService.java` | `login()` now checks lockout, records failures/successes |
| `backend/auth-service/.../exception/ServiceException.java` | Add 429 (`tooManyRequests`) factory + optional `retryAfterSeconds` |
| `backend/auth-service/.../exception/GlobalExceptionHandler.java` | Emit `Retry-After` header for `ServiceException`s that carry it |
| `backend/auth-service/src/test/.../LoginGuardServiceTest.java` | **New.** Unit tests (in-memory store): IP failure ceiling, cross-account isolation, lockout-after-N, success resets counter |
| `backend/auth-service/src/test/.../AuthIntegrationTest.java` | Add Redis Testcontainer + 5 abuse-control integration tests (including cross-account isolation); flush Redis per test |

### Availability fix: per-IP shared-egress lock-out (FIX 1)

| File | Change |
|------|--------|
| `backend/auth-service/.../config/LoginGuardProperties.java` | `ipMaxAttempts` default raised from 10 → 100; javadoc updated |
| `backend/auth-service/.../security/ratelimit/LoginGuardService.java` | Per-IP counter now tracks `rl:ip:fail:<IP>` (failures only); `recordFailure(email, clientIp)` added; `checkIpRateLimit` → `checkIpFailureLimit` (read-only, no increment) |
| `backend/auth-service/.../security/ratelimit/RateLimitFilter.java` | Calls `checkIpFailureLimit` (read-only); stamps `valet.clientIp` request attribute for AuthService to reuse |
| `backend/auth-service/.../service/AuthService.java` | `recordFailure(email, resolveClientIp())` — increments per-IP failure bucket only on actual auth failures, not on successes |
| `backend/auth-service/src/main/resources/application.yml` | `ip-max-attempts` default → 100; expanded comment |
| `infra/.env.example` | `AUTH_RL_IP_MAX` → 100; expanded two-control explanation |
| `docs/SECURITY.md` | Section 8 rewritten to document failure-only semantics and shared-egress-IP design intent |

### Method-not-allowed 405 fix (FIX 2)

| File | Change |
|------|--------|
| `backend/auth-service/.../exception/GlobalExceptionHandler.java` | Add `@ExceptionHandler(HttpRequestMethodNotSupportedException.class)` → 405 + `Allow` header; add `NoResourceFoundException` → 404 |
| `backend/transaction-service/.../exception/GlobalExceptionHandler.java` | Same two handlers |
| `backend/auth-service/src/test/.../AuthIntegrationTest.java` | Add `getOnPostOnlyRouteReturns405WithAllowHeader` integration test |
| `backend/transaction-service/src/test/.../OperatorApiIntegrationTest.java` | Add `getOnPostOnlyRouteReturns405WithAllowHeader` integration test |
