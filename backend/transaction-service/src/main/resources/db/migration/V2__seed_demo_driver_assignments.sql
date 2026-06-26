-- MANDATORY SEED — the linchpin for the parallel slice.
--
-- Seeds retrieval missions assigned to the demo driver the auth-service seeds:
--   driver userId (= JWT sub)         11111111-1111-1111-1111-111111111111
--   company_id                        22222222-2222-2222-2222-222222222222
--   location_id                       33333333-3333-3333-3333-333333333333
--
-- We do NOT create the user here (that is auth-service's job); we only reference
-- the UUID so GET /api/driver/assignments returns these immediately.
--
-- status = driver_assigned, requested_at set => they appear as active missions.
-- Fixed transaction ids so the seed is idempotent and easy to curl against.

INSERT INTO valet_transactions
    (id, company_id, location_id, car_plate, car_make, car_model, car_color,
     key_code, status, retrieved_by_driver_id, parked_by_driver_id,
     guest_name, guest_phone, requested_at, created_at, updated_at)
VALUES
    ('aaaaaaa1-0000-0000-0000-000000000001',
     '22222222-2222-2222-2222-222222222222',
     '33333333-3333-3333-3333-333333333333',
     'MH01AB1234', 'Toyota', 'Camry', 'Silver',
     'K-07', 'driver_assigned',
     '11111111-1111-1111-1111-111111111111',
     '11111111-1111-1111-1111-111111111111',
     'Aarav Sharma', '+919800000001',
     now() - interval '6 minutes', now() - interval '40 minutes', now()),

    ('aaaaaaa1-0000-0000-0000-000000000002',
     '22222222-2222-2222-2222-222222222222',
     '33333333-3333-3333-3333-333333333333',
     'KA05CD5678', 'Honda', 'City', 'White',
     'K-12', 'driver_assigned',
     '11111111-1111-1111-1111-111111111111',
     NULL,
     'Priya Nair', '+919800000002',
     now() - interval '4 minutes', now() - interval '25 minutes', now()),

    ('aaaaaaa1-0000-0000-0000-000000000003',
     '22222222-2222-2222-2222-222222222222',
     '33333333-3333-3333-3333-333333333333',
     'DL08EF9012', 'BMW', 'X5', 'Black',
     'K-21', 'driver_assigned',
     '11111111-1111-1111-1111-111111111111',
     '11111111-1111-1111-1111-111111111111',
     'Rohan Mehta', '+919800000003',
     now() - interval '2 minutes', now() - interval '15 minutes', now())
ON CONFLICT (id) DO NOTHING;
