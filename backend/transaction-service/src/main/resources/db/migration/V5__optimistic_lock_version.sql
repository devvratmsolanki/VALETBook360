-- Optimistic-locking version column (E-03). The valet_transactions row is now
-- guarded by a JPA @Version field: every UPDATE bumps `version` and a write
-- whose expected version no longer matches fails with an
-- OptimisticLockingFailureException, which the service maps to a 409
-- CONCURRENT_UPDATE. This prevents double-deliver / double-assign last-write-wins
-- when two callers act on the same car concurrently.
--
-- DEFAULT 0 backfills every existing row; NOT NULL because @Version is a
-- primitive int on the entity.
ALTER TABLE valet_transactions
    ADD COLUMN IF NOT EXISTS version int NOT NULL DEFAULT 0;
