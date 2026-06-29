-- Park-driver mission lookup index.
--
-- getDriverAssignments() runs findByParkedByDriverIdAndStatusInOrderByCreatedAtDesc
-- on every driver mission refresh to surface "go park this car" intake missions.
-- V1 created ix_tx_retriever_status for the retrieval side but never created the
-- matching index for the parker side, so that query was a sequential scan (the
-- repository javadoc claiming a "parked_by_driver_id partial index" was wrong).
--
-- Partial (parked_by_driver_id IS NOT NULL) so it stays small — only assigned
-- intake rows are indexed. Mirrors ix_tx_retriever_status on the retrieval side.
CREATE INDEX IF NOT EXISTS ix_tx_parker_status
    ON valet_transactions (parked_by_driver_id, status)
    WHERE parked_by_driver_id IS NOT NULL;
