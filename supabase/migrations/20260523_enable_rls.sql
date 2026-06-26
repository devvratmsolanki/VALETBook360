-- Enable Row Level Security across every public table and install per-role
-- policies. Without this, the anon API key reads every row in the database.
--
-- Role model (DB values): 'admin', 'company', 'valet', 'driver'.
-- (Some legacy code/comments refer to 'manager' as the DB name for 'company',
-- but autoCreateProfile and the existing rows use 'company'. Both are accepted
-- in the policies below for safety.)
--
-- Service-role calls from edge functions (create-staff, send-whatsapp,
-- request-car) automatically bypass RLS — no policy needed for them.

-- ============================================================
-- 1. Helper functions (SECURITY DEFINER to bypass RLS recursion)
-- ============================================================

create or replace function public.auth_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
    select role from public.users where id = auth.uid()
$$;

create or replace function public.auth_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
    select valet_company_id from public.users where id = auth.uid()
$$;

create or replace function public.auth_location_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
    select location_id from public.users where id = auth.uid()
$$;

create or replace function public.auth_driver_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
    select id from public.drivers where user_id = auth.uid() limit 1
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select auth_role() = 'admin'
$$;

create or replace function public.is_company()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select auth_role() in ('company', 'manager')
$$;

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select auth_role() in ('admin', 'company', 'manager', 'valet')
$$;

create or replace function public.first_admin_exists()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists(select 1 from public.users where role = 'admin')
$$;

grant execute on function public.auth_role()        to authenticated;
grant execute on function public.auth_company_id()  to authenticated;
grant execute on function public.auth_location_id() to authenticated;
grant execute on function public.auth_driver_id()   to authenticated;
grant execute on function public.is_admin()         to authenticated;
grant execute on function public.is_company()       to authenticated;
grant execute on function public.is_staff()         to authenticated;
grant execute on function public.first_admin_exists() to authenticated, anon;

-- ============================================================
-- 2. valet_companies
-- ============================================================
alter table public.valet_companies enable row level security;

drop policy if exists "vc_select" on public.valet_companies;
create policy "vc_select" on public.valet_companies
    for select to authenticated
    using (
        is_admin()
        or id = auth_company_id()
    );

drop policy if exists "vc_insert" on public.valet_companies;
create policy "vc_insert" on public.valet_companies
    for insert to authenticated
    with check (is_admin());

drop policy if exists "vc_update" on public.valet_companies;
create policy "vc_update" on public.valet_companies
    for update to authenticated
    using (is_admin() or (is_company() and id = auth_company_id()))
    with check (is_admin() or (is_company() and id = auth_company_id()));

drop policy if exists "vc_delete" on public.valet_companies;
create policy "vc_delete" on public.valet_companies
    for delete to authenticated
    using (is_admin());

-- ============================================================
-- 3. users
-- ============================================================
alter table public.users enable row level security;

-- Atomic first-admin guard. Combined with the WITH CHECK below, this prevents
-- two concurrent first-signups from both becoming admin.
create unique index if not exists users_one_admin_idx on public.users(role) where role = 'admin';

drop policy if exists "users_select_self" on public.users;
create policy "users_select_self" on public.users
    for select to authenticated
    using (id = auth.uid());

drop policy if exists "users_select_admin" on public.users;
create policy "users_select_admin" on public.users
    for select to authenticated
    using (is_admin());

drop policy if exists "users_select_company" on public.users;
create policy "users_select_company" on public.users
    for select to authenticated
    using (is_company() and valet_company_id = auth_company_id());

-- Allow authenticated users to detect whether ANY admin exists (for the
-- autoCreateProfile bootstrap path). Only exposes admin rows; non-admin
-- profiles remain hidden across companies.
drop policy if exists "users_select_admin_bootstrap" on public.users;
create policy "users_select_admin_bootstrap" on public.users
    for select to authenticated
    using (role = 'admin');

-- Self-signup bootstrap: a freshly-authenticated user can insert their own
-- public.users row. They MAY claim 'admin' only when no admin exists yet —
-- the unique index above is the atomic guard against races.
drop policy if exists "users_insert_self" on public.users;
create policy "users_insert_self" on public.users
    for insert to authenticated
    with check (
        id = auth.uid()
        and (
            role = 'valet'
            or (role = 'admin' and not first_admin_exists())
        )
    );

drop policy if exists "users_insert_admin" on public.users;
create policy "users_insert_admin" on public.users
    for insert to authenticated
    with check (is_admin());

drop policy if exists "users_insert_company" on public.users;
create policy "users_insert_company" on public.users
    for insert to authenticated
    with check (
        is_company()
        and valet_company_id = auth_company_id()
        and role in ('valet', 'driver')
    );

drop policy if exists "users_update_self" on public.users;
create policy "users_update_self" on public.users
    for update to authenticated
    using (id = auth.uid())
    with check (id = auth.uid() and role = auth_role());

drop policy if exists "users_update_admin" on public.users;
create policy "users_update_admin" on public.users
    for update to authenticated
    using (is_admin())
    with check (is_admin());

drop policy if exists "users_update_company" on public.users;
create policy "users_update_company" on public.users
    for update to authenticated
    using (is_company() and valet_company_id = auth_company_id())
    with check (is_company() and valet_company_id = auth_company_id());

drop policy if exists "users_delete_admin" on public.users;
create policy "users_delete_admin" on public.users
    for delete to authenticated
    using (is_admin());

drop policy if exists "users_delete_company" on public.users;
create policy "users_delete_company" on public.users
    for delete to authenticated
    using (is_company() and valet_company_id = auth_company_id() and role <> 'admin');

-- ============================================================
-- 4. locations
-- ============================================================
alter table public.locations enable row level security;

drop policy if exists "loc_select" on public.locations;
create policy "loc_select" on public.locations
    for select to authenticated
    using (is_admin() or valet_company_id = auth_company_id());

drop policy if exists "loc_write" on public.locations;
create policy "loc_write" on public.locations
    for all to authenticated
    using (is_admin() or (is_company() and valet_company_id = auth_company_id()))
    with check (is_admin() or (is_company() and valet_company_id = auth_company_id()));

-- ============================================================
-- 5. drivers
-- ============================================================
alter table public.drivers enable row level security;

drop policy if exists "drv_select" on public.drivers;
create policy "drv_select" on public.drivers
    for select to authenticated
    using (
        is_admin()
        or valet_company_id = auth_company_id()
        or user_id = auth.uid()
    );

drop policy if exists "drv_write" on public.drivers;
create policy "drv_write" on public.drivers
    for all to authenticated
    using (is_admin() or (is_company() and valet_company_id = auth_company_id()))
    with check (is_admin() or (is_company() and valet_company_id = auth_company_id()));

drop policy if exists "drv_update_self" on public.drivers;
create policy "drv_update_self" on public.drivers
    for update to authenticated
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

-- ============================================================
-- 6. key_slots
-- ============================================================
alter table public.key_slots enable row level security;

drop policy if exists "ks_select" on public.key_slots;
create policy "ks_select" on public.key_slots
    for select to authenticated
    using (
        is_admin()
        or exists (
            select 1 from public.locations l
            where l.id = key_slots.location_id
              and l.valet_company_id = auth_company_id()
        )
    );

drop policy if exists "ks_write" on public.key_slots;
create policy "ks_write" on public.key_slots
    for all to authenticated
    using (
        is_admin()
        or (
            is_staff() and exists (
                select 1 from public.locations l
                where l.id = key_slots.location_id
                  and l.valet_company_id = auth_company_id()
            )
        )
    )
    with check (
        is_admin()
        or (
            is_staff() and exists (
                select 1 from public.locations l
                where l.id = key_slots.location_id
                  and l.valet_company_id = auth_company_id()
            )
        )
    );

-- ============================================================
-- 7. visitors
-- ============================================================
-- Visitors are deduped across tenants in the current schema (no
-- valet_company_id column). Restrict to authenticated staff; cross-tenant
-- isolation would require a schema change (add valet_company_id).
alter table public.visitors enable row level security;

drop policy if exists "vis_select" on public.visitors;
create policy "vis_select" on public.visitors
    for select to authenticated
    using (is_staff() or auth_driver_id() is not null);

drop policy if exists "vis_write" on public.visitors;
create policy "vis_write" on public.visitors
    for all to authenticated
    using (is_staff())
    with check (is_staff());

-- ============================================================
-- 8. cars
-- ============================================================
alter table public.cars enable row level security;

drop policy if exists "car_select" on public.cars;
create policy "car_select" on public.cars
    for select to authenticated
    using (is_staff() or auth_driver_id() is not null);

drop policy if exists "car_write" on public.cars;
create policy "car_write" on public.cars
    for all to authenticated
    using (is_staff())
    with check (is_staff());

-- ============================================================
-- 9. valet_transactions
-- ============================================================
alter table public.valet_transactions enable row level security;

drop policy if exists "tx_select" on public.valet_transactions;
create policy "tx_select" on public.valet_transactions
    for select to authenticated
    using (
        is_admin()
        or (is_company() and valet_company_id = auth_company_id())
        or (auth_role() = 'valet' and valet_company_id = auth_company_id())
        or (auth_role() = 'driver' and (
            valet_company_id = auth_company_id()
            or parked_by_driver_id = auth_driver_id()
            or retrieved_by_driver_id = auth_driver_id()
        ))
    );

drop policy if exists "tx_insert" on public.valet_transactions;
create policy "tx_insert" on public.valet_transactions
    for insert to authenticated
    with check (
        is_admin()
        or (is_staff() and valet_company_id = auth_company_id())
    );

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
        or auth_role() = 'driver'
    );

drop policy if exists "tx_delete" on public.valet_transactions;
create policy "tx_delete" on public.valet_transactions
    for delete to authenticated
    using (is_admin() or (is_company() and valet_company_id = auth_company_id()));

-- ============================================================
-- 10. whatsapp_logs
-- ============================================================
alter table public.whatsapp_logs enable row level security;

drop policy if exists "wa_select" on public.whatsapp_logs;
create policy "wa_select" on public.whatsapp_logs
    for select to authenticated
    using (is_admin() or is_company());

drop policy if exists "wa_insert" on public.whatsapp_logs;
create policy "wa_insert" on public.whatsapp_logs
    for insert to authenticated
    with check (is_staff());

-- ============================================================
-- 11. contracts
-- ============================================================
alter table public.contracts enable row level security;

drop policy if exists "ctr_select" on public.contracts;
create policy "ctr_select" on public.contracts
    for select to authenticated
    using (is_admin() or valet_company_id = auth_company_id());

drop policy if exists "ctr_write" on public.contracts;
create policy "ctr_write" on public.contracts
    for all to authenticated
    using (is_admin() or (is_company() and valet_company_id = auth_company_id()))
    with check (is_admin() or (is_company() and valet_company_id = auth_company_id()));
