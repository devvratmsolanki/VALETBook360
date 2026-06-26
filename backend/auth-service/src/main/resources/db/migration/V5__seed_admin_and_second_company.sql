-- Demo data for the ADMIN panel: a SECOND company with its own owner + location,
-- plus a login for the EXISTING demo company's owner. After this migration the
-- admin panel shows >=2 companies, each with real children (owner, location).
--
-- Super admin: admin@valet.demo / Admin123 already exists from V2 (role=admin,
-- tenant-less). We keep it as the panel's super-admin — no change needed here.
--
-- New logins seeded (role 'manager' == UI 'company'):
--   owner@valet.demo  / Owner123  -> Demo Valet Co     (company 22222222-...)
--   owner2@valet.demo / Owner123  -> Skyline Parking   (company 66666666-...)
--
-- BCrypt hashes are cost 12, prefix $2b$, generated out-of-band in a
-- python:3.12-alpine container (bcrypt.hashpw(b'Owner123', bcrypt.gensalt(12,
-- prefix=b'2b'))) and round-trip-verified with bcrypt.checkpw. They validate
-- against Spring's BCryptPasswordEncoder(12). Flyway placeholder replacement is
-- disabled (placeholder-replacement: false) so the $2b$12$ prefix is safe.
--
-- Idempotent: ON CONFLICT DO NOTHING everywhere so a replay never clobbers a
-- rotated password or duplicates a company.

-- 1) Second company.
INSERT INTO valet_companies (id, company_name, owner_name, phone, email)
VALUES (
    '66666666-6666-6666-6666-666666666666',
    'Skyline Parking',
    'Skyline Owner',
    NULL,
    'owner2@valet.demo'
)
ON CONFLICT (id) DO NOTHING;

-- 2) A location for the second company so its drilldown isn't empty.
INSERT INTO locations (id, valet_company_id, name, address, city, state, country, key_capacity)
VALUES (
    '77777777-7777-7777-7777-777777777777',
    '66666666-6666-6666-6666-666666666666',
    'Skyline Downtown',
    '100 Market St', 'Metropolis', 'CA', 'USA',
    120
)
ON CONFLICT (id) DO NOTHING;

-- 3) Owner login for the EXISTING demo company (Demo Valet Co).
--    role 'manager' (UI 'company'); pinned to the company, not a single location.
INSERT INTO users (id, email, password_hash, role, company_id, location_id, name, is_active)
VALUES (
    '88888888-8888-8888-8888-888888888888',
    'owner@valet.demo',
    '$2b$12$5eJD4WLpafibQNvQ4/4cqOMjyz5St197ZaXX6Q65wSa9ZtakTGvt.',
    'manager',
    '22222222-2222-2222-2222-222222222222',
    NULL,
    'Demo Owner',
    true
)
ON CONFLICT (id) DO NOTHING;

-- 4) Owner login for the second company (Skyline Parking).
INSERT INTO users (id, email, password_hash, role, company_id, location_id, name, is_active)
VALUES (
    '99999999-9999-9999-9999-999999999999',
    'owner2@valet.demo',
    '$2b$12$j10ISjcB25q9m0/73mRY4e4LIk5na.CYvAhHBbVomWM5gy62X7OmO',
    'manager',
    '66666666-6666-6666-6666-666666666666',
    NULL,
    'Skyline Owner',
    true
)
ON CONFLICT (id) DO NOTHING;
