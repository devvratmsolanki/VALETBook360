-- Link drivers table to auth/users so the driver panel can resolve
-- the logged-in user to their driver record.
--
-- Run this in the Supabase SQL editor (or via `supabase db push`).

alter table public.drivers
    add column if not exists user_id uuid references public.users(id) on delete set null,
    add column if not exists email text;

create unique index if not exists drivers_user_id_unique
    on public.drivers(user_id)
    where user_id is not null;

create index if not exists drivers_email_idx
    on public.drivers(lower(email))
    where email is not null;

-- Best-effort backfill for existing drivers by matching on name + company.
-- (Safe to re-run; only fills rows where user_id is still null.)
update public.drivers d
set user_id = u.id,
    email   = coalesce(d.email, u.email)
from public.users u
where d.user_id is null
  and u.role = 'driver'
  and u.valet_company_id = d.valet_company_id
  and lower(trim(u.name)) = lower(trim(d.name));

-- Allow deleting a driver without first manually nulling their references.
-- Historical transactions keep the row, just lose the driver name link.
alter table public.valet_transactions
    drop constraint if exists valet_transactions_parked_by_driver_id_fkey,
    drop constraint if exists valet_transactions_retrieved_by_driver_id_fkey;

alter table public.valet_transactions
    add constraint valet_transactions_parked_by_driver_id_fkey
        foreign key (parked_by_driver_id) references public.drivers(id) on delete set null,
    add constraint valet_transactions_retrieved_by_driver_id_fkey
        foreign key (retrieved_by_driver_id) references public.drivers(id) on delete set null;
