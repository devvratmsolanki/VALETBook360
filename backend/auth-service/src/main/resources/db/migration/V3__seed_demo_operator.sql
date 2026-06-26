-- MANDATORY SEED (operator slice linchpin) — append-only on top of V2.
--
-- V2 seeds a tenant-bound driver and a tenant-LESS admin. The new operator
-- (valet floor) endpoints in transaction-service require the caller's JWT to
-- carry a companyId; the admin has none, so no V2 account could actually drive
-- the operator flow. This migration adds a seeded OPERATOR so the operator slice
-- is usable + verifiable out of the box.
--
--   Demo operator : operator@valet.demo / Operator123  (role=valet, tenant-bound)
--
-- role=valet is the operator role on the wire. company_id and location_id match
-- the demo driver EXACTLY (company 22222222-..., location 33333333-...) so an
-- operator can create a transaction and assign it to the demo driver — the
-- end-to-end demo works against a single shared tenant.
--
-- Password hash is BCrypt (cost 12), generated out-of-band so the seed is
-- deterministic and the migration stays pure SQL. It verifies against Spring's
-- BCryptPasswordEncoder(12). Flyway placeholder replacement only triggers on
-- "${" — the "$2b$12$" BCrypt prefix is therefore safe and untouched.
--
-- Idempotent: ON CONFLICT DO NOTHING so re-running (or a baseline replay) is a
-- no-op and never clobbers a rotated password.

INSERT INTO users (id, email, password_hash, role, company_id, location_id, name, is_active)
VALUES
    (
        '55555555-5555-5555-5555-555555555555',
        'operator@valet.demo',
        '$2b$12$a08e1pCRwO.MphY3zOaovO6zRbrqVkh.kwJTIJpUK5GbFr4EjwAum',
        'valet',
        '22222222-2222-2222-2222-222222222222',
        '33333333-3333-3333-3333-333333333333',
        'Demo Operator',
        true
    )
ON CONFLICT (id) DO NOTHING;
