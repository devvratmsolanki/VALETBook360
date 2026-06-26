-- MANDATORY SEED (shared-contract linchpin for the parallel slice).
--
-- The other services + the Flutter app are built in parallel against these
-- EXACT fixed identifiers/credentials. Do not change the UUIDs, emails, roles,
-- or tenancy below without coordinating the whole slice.
--
--   Demo driver : driver@valet.demo / Driver123  (role=driver, tenant-bound)
--   Demo admin  : admin@valet.demo  / Admin123    (role=admin, tenant-less)
--
-- Password hashes are BCrypt (cost 12), generated out-of-band so the seed is
-- deterministic and the migration stays pure SQL. They verify against Spring's
-- BCryptPasswordEncoder(12). Flyway placeholder replacement only triggers on
-- "${" — the "$2b$12$" BCrypt prefix is therefore safe and untouched.
--
-- Idempotent: ON CONFLICT DO NOTHING so re-running (or a baseline replay) is a
-- no-op and never clobbers a rotated password.

INSERT INTO users (id, email, password_hash, role, company_id, location_id, name, is_active)
VALUES
    (
        '11111111-1111-1111-1111-111111111111',
        'driver@valet.demo',
        '$2b$12$ZeaTahDl73HPa4GYE7P6q.AHs8vaIrzug4QKl8hM3q6RNLymEBwSq',
        'driver',
        '22222222-2222-2222-2222-222222222222',
        '33333333-3333-3333-3333-333333333333',
        'Demo Driver',
        true
    ),
    (
        '44444444-4444-4444-4444-444444444444',
        'admin@valet.demo',
        '$2b$12$zUF4VzPbtv5Q1uohW/T7j.V1HV7PH1dWLwt16YurXMSS4b8OlhHu6',
        'admin',
        NULL,
        NULL,
        'Demo Admin',
        true
    )
ON CONFLICT (id) DO NOTHING;
