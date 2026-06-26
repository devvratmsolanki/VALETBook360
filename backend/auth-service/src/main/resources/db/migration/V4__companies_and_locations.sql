-- Companies + locations land IN the auth DB (valet_auth), next to users.
-- (Orchestrator decision: no separate company microservice — admin manages
-- tenants from here, sharing the same users table the auth flow owns.)
--
-- Append-only on top of V1/V2/V3. Existing demo users (V2 driver, V3 operator)
-- already reference company 22222222-... and location 33333333-... by id. Those
-- ids did NOT exist as rows in any table before this migration — they were bare
-- tenancy claims on the users row. To add real FKs from users.company_id /
-- users.location_id WITHOUT breaking the seeded rows, we FIRST materialise the
-- demo company + demo location with those exact ids, THEN add the FKs. So the
-- order below is load-bearing: tables -> demo tenant rows -> FKs.

-- valet_companies: the tenant root (legacy valet_companies table).
CREATE TABLE valet_companies (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name text        NOT NULL,
    owner_name   text,
    phone        text,
    email        citext,
    created_at   timestamptz NOT NULL DEFAULT now()
);

-- locations: a company's physical valet sites (legacy locations table).
CREATE TABLE locations (
    id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    valet_company_id uuid        NOT NULL REFERENCES valet_companies (id) ON DELETE CASCADE,
    name             text        NOT NULL,
    address          text,
    city             text,
    state            text,
    country          text,
    key_capacity     int         NOT NULL DEFAULT 0,
    created_at       timestamptz NOT NULL DEFAULT now()
);

-- Hot path: "all locations for a company" (admin drilldown + company portal).
CREATE INDEX ix_locations_company ON locations (valet_company_id);

-- ---------------------------------------------------------------------------
-- Materialise the demo tenant the V2/V3 seed users already point at, so the
-- FKs we add next validate against existing data instead of failing. Idempotent.
-- ---------------------------------------------------------------------------
INSERT INTO valet_companies (id, company_name, owner_name, phone, email)
VALUES (
    '22222222-2222-2222-2222-222222222222',
    'Demo Valet Co',
    'Demo Owner',
    NULL,
    'owner@valet.demo'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO locations (id, valet_company_id, name, address, city, state, country, key_capacity)
VALUES (
    '33333333-3333-3333-3333-333333333333',
    '22222222-2222-2222-2222-222222222222',
    'Demo Garage',
    NULL, NULL, NULL, NULL,
    50
)
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Now the FKs are safe: every users.company_id / users.location_id that is set
-- (demo driver + demo operator) resolves to a row that exists above.
--   - company FK: SET NULL on delete would violate users_tenant_chk for non-admin
--     rows, so we use RESTRICT (a company with users cannot be hard-deleted from
--     under them; the app deactivates instead). Matches the legacy intent.
--   - location FK: SET NULL on delete — a location can be removed while its staff
--     keep their accounts (location_id is nullable + not part of the tenant check).
-- ---------------------------------------------------------------------------
ALTER TABLE users
    ADD CONSTRAINT fk_users_company
        FOREIGN KEY (company_id) REFERENCES valet_companies (id) ON DELETE RESTRICT;

ALTER TABLE users
    ADD CONSTRAINT fk_users_location
        FOREIGN KEY (location_id) REFERENCES locations (id) ON DELETE SET NULL;

-- users_tenant_chk (role='admin' OR company_id NOT NULL) is unaffected: we only
-- added referential integrity; the demo admin (V2) still has company_id NULL and
-- passes, while every tenant-bound row now points at a real valet_companies row.
