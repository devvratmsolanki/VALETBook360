-- Facility owner: a read-only view into their assigned locations.
-- A facility owner is a User with role 'facility_owner'; locations point back
-- to their user row so we avoid a separate table.

ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'facility_owner';

-- Link each location to its facility owner (nullable; most locations are
-- managed directly by the company and have no facility owner).
ALTER TABLE locations
    ADD COLUMN IF NOT EXISTS facility_owner_id uuid
        REFERENCES users (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS ix_locations_facility_owner
    ON locations (facility_owner_id)
    WHERE facility_owner_id IS NOT NULL;
