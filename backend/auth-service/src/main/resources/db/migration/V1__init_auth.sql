-- Vālet auth-service initial schema.
-- Owns identity, roles and tenancy claims (re-platformed off Supabase Auth).

-- citext gives us case-insensitive, case-preserving emails without a functional
-- index everywhere. pgcrypto provides gen_random_uuid() for DB-side defaults.
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Canonical DB role names, preserved from the legacy Supabase users.role column.
-- (Frontend displayed "manager" as "company"; the DB name is the source of truth.)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('admin', 'manager', 'valet', 'driver');
    END IF;
END$$;

CREATE TABLE users (
    id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    email         citext      NOT NULL,
    password_hash text        NOT NULL,
    role          user_role   NOT NULL,
    company_id    uuid,                       -- legacy: valet_company_id; nullable for super-admins
    location_id   uuid,                       -- nullable; valets/drivers may be pinned to a location
    name          text        NOT NULL,
    is_active     boolean     NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),

    -- A manager/valet/driver must belong to a company; only admin may be tenant-less.
    CONSTRAINT users_tenant_chk CHECK (role = 'admin' OR company_id IS NOT NULL)
);

-- Case-insensitive uniqueness (citext makes the comparison ci).
CREATE UNIQUE INDEX ux_users_email ON users (email);

-- Login path: lookup by email, already covered by ux_users_email.
-- Tenancy lookups (user-service "list staff for company", driver "me" by company).
CREATE INDEX ix_users_company       ON users (company_id) WHERE company_id IS NOT NULL;
CREATE INDEX ix_users_company_role  ON users (company_id, role) WHERE company_id IS NOT NULL;
CREATE INDEX ix_users_location      ON users (location_id) WHERE location_id IS NOT NULL;

-- Fix the legacy autoCreateProfile TOCTOU (CLAUDE.md / doc 10.3): at most one admin
-- can ever be the "bootstrap" admin via this race-prone path. A partial unique index
-- makes concurrent first-admin creation atomic at the DB. We scope it to a sentinel
-- bootstrap marker rather than ALL admins, so the product can still have many admins
-- intentionally. Here we keep it simple and DO allow multiple admins (created
-- deliberately by an existing admin), so we DO NOT globally unique-constrain admins.
-- Instead we guard bootstrap in the service. (Index intentionally omitted; see service.)

CREATE TABLE refresh_tokens (
    id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    token_hash text        NOT NULL,
    expires_at timestamptz NOT NULL,
    revoked    boolean     NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX ux_refresh_token_hash ON refresh_tokens (token_hash);
-- "Revoke all sessions for a user" + reuse-detection family lookups.
CREATE INDEX ix_refresh_user_active ON refresh_tokens (user_id) WHERE revoked = false;
