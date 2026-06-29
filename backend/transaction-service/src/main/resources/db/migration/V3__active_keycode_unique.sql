-- Operator key-slot allocation guard.
--
-- A key slot (key_code) may be held by at most ONE *active* transaction per
-- location at a time. "Active" = anything not yet delivered or cancelled — once
-- a car is delivered/cancelled its slot is free for reuse, which is exactly the
-- "7th car leaves → slot 7 reopens for the 29th car" behaviour the operator
-- panel relies on.
--
-- The operator panel picks the next free slot client-side, but two operators
-- parking at the same instant could pick the same one; this partial unique index
-- makes the database the source of truth — the losing INSERT fails with SQLSTATE
-- 23505 and the client refreshes occupancy and retries with the next free slot.
CREATE UNIQUE INDEX IF NOT EXISTS ux_active_keycode_per_location
    ON valet_transactions (location_id, key_code)
    WHERE key_code IS NOT NULL
      AND key_code <> ''
      AND status NOT IN ('delivered', 'cancelled');
