-- Company ↔ venue service agreements (the legacy `contracts` table). Each row
-- ties a company to a location it services, with the on-site manager contact
-- and an active flag. Surfaced in the company panel's Contracts tab.
CREATE TABLE contracts (
    id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    valet_company_id uuid        NOT NULL REFERENCES valet_companies (id) ON DELETE CASCADE,
    location_id      uuid        REFERENCES locations (id) ON DELETE SET NULL,
    name             text        NOT NULL,
    type             text,
    status           text,
    active           boolean     NOT NULL DEFAULT true,
    manager_name     text,
    manager_phone    text,
    manager_email    text,
    created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ix_contracts_company ON contracts (valet_company_id, created_at DESC);

-- Demo contract for Demo Valet Co @ its seeded location so the Contracts tab
-- has something to show on first run.
INSERT INTO contracts (valet_company_id, location_id, name, type, status, active,
                       manager_name, manager_phone, manager_email)
VALUES (
    '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333',
    'Flagship Venue Agreement',
    'venue',
    'signed',
    true,
    'Priya Nair',
    '+91 98250 11223',
    'priya.nair@demo-venue.example'
);
