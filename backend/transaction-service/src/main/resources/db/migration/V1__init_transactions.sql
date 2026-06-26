-- Vālet transaction-service initial schema (database: valet_core).
-- Owns the valet lifecycle: the valet_transactions table, the valet_status enum,
-- the hot-path indexes, and the legal-transition trigger that enforces the
-- canonical state machine at the database (defence-in-depth behind the service).

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_uuid()

-- The canonical lifecycle states, preserved exactly from the legacy
-- transactionService.js STATUS_FLOW.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'valet_status') THEN
        CREATE TYPE valet_status AS ENUM (
            'waiting_for_driver',
            'parked',
            'key_in',
            'requested',
            'driver_assigned',
            'en_route',
            'arrived',
            'delivered',
            'cancelled'
        );
    END IF;
END$$;

CREATE TABLE valet_transactions (
    id                     uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id             uuid         NOT NULL,
    location_id            uuid,
    car_plate              text,
    car_make               text,
    car_model              text,
    car_color              text,
    key_code               text,
    status                 valet_status NOT NULL DEFAULT 'waiting_for_driver',
    parked_by_driver_id    uuid,        -- ON DELETE SET NULL semantics owned by driver-service FK (cross-db)
    retrieved_by_driver_id uuid,
    guest_name             text,
    guest_phone            text,
    requested_at           timestamptz,
    arrived_at             timestamptz,
    delivered_at           timestamptz,
    created_at             timestamptz  NOT NULL DEFAULT now(),
    updated_at             timestamptz  NOT NULL DEFAULT now()
);

-- Hot paths (mirrors legacy 20260522 intent):
--  - driver "my missions": (retrieved_by_driver_id, status)
--  - operator floor feed:  (company_id, status, created_at)
CREATE INDEX ix_tx_retriever_status ON valet_transactions (retrieved_by_driver_id, status)
    WHERE retrieved_by_driver_id IS NOT NULL;
CREATE INDEX ix_tx_company_status_created ON valet_transactions (company_id, status, created_at);

-- ---------------------------------------------------------------------------
-- Legal-transition trigger: the same adjacency map the service enforces, made
-- airtight at the DB so no path (bad migration, manual SQL, future service) can
-- write an illegal transition. Mirrors ValetStatus.LEGAL_TRANSITIONS exactly.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION valet_enforce_transition()
RETURNS trigger AS $$
BEGIN
    -- No-op if status is unchanged (other column updates are always allowed).
    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    -- Every non-terminal status may move to cancelled.
    IF NEW.status = 'cancelled'
       AND OLD.status NOT IN ('delivered', 'cancelled') THEN
        RETURN NEW;
    END IF;

    IF (OLD.status = 'waiting_for_driver' AND NEW.status = 'parked')
       OR (OLD.status = 'parked'          AND NEW.status IN ('key_in', 'requested'))
       OR (OLD.status = 'key_in'          AND NEW.status = 'requested')
       OR (OLD.status = 'requested'       AND NEW.status = 'driver_assigned')
       OR (OLD.status = 'driver_assigned' AND NEW.status = 'en_route')
       OR (OLD.status = 'en_route'        AND NEW.status = 'arrived')
       OR (OLD.status = 'arrived'         AND NEW.status = 'delivered')
    THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Illegal valet status transition: % -> %', OLD.status, NEW.status
        USING ERRCODE = 'check_violation';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_valet_enforce_transition
    BEFORE UPDATE OF status ON valet_transactions
    FOR EACH ROW
    EXECUTE FUNCTION valet_enforce_transition();
