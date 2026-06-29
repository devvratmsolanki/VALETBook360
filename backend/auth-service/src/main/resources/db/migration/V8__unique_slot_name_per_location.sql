-- Enforce one slot name per location (BUG-05). The company panel's bulk
-- generator + rename could previously create two slots with the same name at a
-- single location, which made the operator key-slot picker ambiguous.
--
-- Step 1: de-duplicate any existing rows so the constraint can be added. For
-- each (location_id, slot_name) group we KEEP the oldest row (earliest
-- created_at, id as a stable tie-break) and DELETE the rest. Deleting (rather
-- than renaming) is safe: key_slots are just labels for the picker, the kept
-- row preserves the original slot, and no transaction row FKs into key_slots.
DELETE FROM key_slots ks
USING (
    SELECT id,
           row_number() OVER (
               PARTITION BY location_id, slot_name
               ORDER BY created_at ASC, id ASC
           ) AS rn
    FROM key_slots
) dup
WHERE ks.id = dup.id
  AND dup.rn > 1;

-- Step 2: the uniqueness guarantee itself.
ALTER TABLE key_slots
    ADD CONSTRAINT ux_slot_name_per_location UNIQUE (location_id, slot_name);
