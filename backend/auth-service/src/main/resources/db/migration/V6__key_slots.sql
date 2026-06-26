-- Custom key-storage slots per location (the legacy `key_slots` table). A
-- location either uses these custom labels (e.g. VIP-1, Box A) or falls back to
-- generic numeric slots 1..key_capacity when none exist. Managed from the
-- company panel's Location Detail → Key Slots tab (bulk generator + rename +
-- delete). Tenant scoping is enforced in the service via the owning location's
-- company.
CREATE TABLE key_slots (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id uuid        NOT NULL REFERENCES locations (id) ON DELETE CASCADE,
    slot_name   text        NOT NULL,
    sort_order  int         NOT NULL DEFAULT 0,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- Hot path: "all slots for a location", ordered for display.
CREATE INDEX ix_key_slots_location ON key_slots (location_id, sort_order, slot_name);
