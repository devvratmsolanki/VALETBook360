-- Tenant-isolation hardening for the RLS policies installed in
-- 20260523_enable_rls.sql. Found during the 2026-06-29 security audit.
--
-- NOTE: Supabase migrations are NOT auto-applied here (the CLI isn't logged in).
-- Run this manually: Supabase Dashboard -> SQL Editor -> paste & run.
--
-- This migration is idempotent (drop policy if exists + create) and only
-- REPLACES two over-permissive policies. It does not touch table data.

-- ============================================================
-- FIX 1 (Critical) — valet_transactions: a driver could rewrite ANY column
-- ------------------------------------------------------------
-- The previous driver branch of tx_update's WITH CHECK was just
--   auth_role() = 'driver'
-- so a driver who satisfied the USING clause could PATCH the row's
-- valet_company_id (re-assigning the transaction to ANOTHER company and
-- exfiltrating it) or set any status, bypassing the (client-side) state machine.
--
-- We pin the post-update valet_company_id to the driver's own company so a
-- driver can no longer move a transaction across tenants. (A true server-side
-- state-machine guard would additionally need a BEFORE UPDATE trigger validating
-- the status edge — see RECOMMENDED block at the bottom.)
drop policy if exists "tx_update" on public.valet_transactions;
create policy "tx_update" on public.valet_transactions
    for update to authenticated
    using (
        is_admin()
        or (is_staff() and valet_company_id = auth_company_id())
        or (auth_role() = 'driver' and (
            parked_by_driver_id = auth_driver_id()
            or retrieved_by_driver_id = auth_driver_id()
            or (valet_company_id = auth_company_id() and status in ('requested', 'driver_assigned'))
        ))
    )
    with check (
        is_admin()
        or (is_staff() and valet_company_id = auth_company_id())
        -- Driver writes can never change the owning company (no cross-tenant move).
        or (auth_role() = 'driver' and valet_company_id = auth_company_id())
    );

-- ============================================================
-- FIX 2 (Critical) — users: a company owner could change any user's role
-- ------------------------------------------------------------
-- users_update_company previously had no role restriction, so a company owner
-- could PATCH a valet/driver (or another owner) to role='company', minting a
-- co-owner. (Escalation to 'admin' was already blocked by the one-admin unique
-- index, but not escalation to 'company'.)
--
-- We restrict company updates to staff rows (valet/driver) on BOTH the rows they
-- may touch (USING) and the resulting row (WITH CHECK) — mirroring the Spring
-- auth-service "PROTECTED_ACCOUNT" + valet|driver-only rule. A company owner
-- editing their OWN profile is still allowed via the separate users_update_self
-- policy (which already pins role = auth_role()).
drop policy if exists "users_update_company" on public.users;
create policy "users_update_company" on public.users
    for update to authenticated
    using (
        is_company()
        and valet_company_id = auth_company_id()
        and role in ('valet', 'driver')
    )
    with check (
        is_company()
        and valet_company_id = auth_company_id()
        and role in ('valet', 'driver')
    );

-- ============================================================
-- RECOMMENDED (NOT applied here — require product/schema decisions)
-- ============================================================
--
-- R1 (Critical) — visitors / cars have NO tenant isolation.
--   vis_select / car_select use is_staff() with no company filter, so any
--   authenticated valet reads every guest's name + phone across ALL companies.
--   These tables have no valet_company_id column (visitors are de-duped across
--   tenants in the current schema), so a real fix needs a schema change:
--     1) alter table public.visitors add column valet_company_id uuid;
--        alter table public.cars     add column valet_company_id uuid;
--     2) backfill from the owning valet_transactions rows;
--     3) replace the policies, e.g.:
--        -- create policy "vis_select" on public.visitors for select to authenticated
--        --   using (is_admin() or valet_company_id = auth_company_id());
--   If a visitor genuinely spans multiple companies, model it as a junction
--   table instead of a single shared row. Decide before applying.
--
-- R2 (Medium) — users_select_admin_bootstrap leaks every admin's full profile
--   row (email, name, ...) to ANY authenticated user. The bootstrap check only
--   needs a boolean, which first_admin_exists() (SECURITY DEFINER) already
--   provides. After confirming the React autoCreateProfile path uses the RPC
--   (not a direct select on role='admin'), drop the policy:
--        -- drop policy if exists "users_select_admin_bootstrap" on public.users;
--
-- R3 (Medium) — no DB-level state-machine on valet_transactions in Supabase
--   (the legal-transition trigger lives only in the Spring valet_core DB). A
--   driver/valet can PATCH status to any value. Add a BEFORE UPDATE trigger that
--   validates OLD.status -> NEW.status against the canonical edge map if the
--   legacy Supabase path remains in production use.
