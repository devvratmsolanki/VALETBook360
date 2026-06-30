-- Add is_active flag to users table so super admins can enable/disable
-- team members (operators, company owners, drivers) without deleting them.
--
-- is_active = false means the account is disabled from the admin UI.
-- This is a UI-level flag; the auth session itself is not revoked here.
-- To also block login at the auth level, use the Supabase Auth admin API
-- (ban_duration) via an Edge Function.

alter table public.users
    add column if not exists is_active boolean not null default true;

-- Back-fill: all existing users are active
update public.users set is_active = true where is_active is null;

comment on column public.users.is_active is
    'Whether this team member is enabled. Super admins can toggle this flag. '
    'False = disabled in the UI; does not automatically revoke the auth session.';
