-- Indexes for the queries that run on every operator/driver refresh and
-- realtime tick. Without these, table scans will start hurting once the
-- valet_transactions table grows past a few thousand rows.
--
-- Composite index on (valet_company_id, status, created_at desc) matches
-- getActiveTransactions and the operator notification list — both filter on
-- company + status and order by created_at desc.
create index if not exists valet_transactions_company_status_created_idx
    on public.valet_transactions(valet_company_id, status, created_at desc);

-- Driver task lookups: DriverPanel does an OR across these two columns plus
-- a status IN filter. Two single-column partial indexes outperform a
-- composite for the OR pattern because Postgres can BitmapOr them.
create index if not exists valet_transactions_parked_driver_idx
    on public.valet_transactions(parked_by_driver_id)
    where parked_by_driver_id is not null;

create index if not exists valet_transactions_retrieved_driver_idx
    on public.valet_transactions(retrieved_by_driver_id)
    where retrieved_by_driver_id is not null;

-- key_code lookup feeds getNextAvailableKeySlot's occupancy check, which
-- runs every time the operator opens the check-in form.
create index if not exists valet_transactions_location_status_idx
    on public.valet_transactions(location_id, status);

-- Visitor lookup by phone is the entry point for returning-guest detection.
-- A simple btree on phone is enough — ILIKE prefix searches won't use this,
-- but exact-match getVisitorByPhone will.
create index if not exists visitors_phone_idx
    on public.visitors(phone);

-- Car lookup by plate number runs on every check-in and every returning-
-- guest auto-fill. Unique constraint would be safer but the existing data
-- may already have duplicates; ship as a plain index for now.
create index if not exists cars_car_number_idx
    on public.cars(car_number);
