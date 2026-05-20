-- Adds a per-transaction guest token used by the request-car edge function
-- to prevent plate-enumeration attacks. Existing rows have NULL token; the
-- edge function falls back to global REQUIRE_TOKEN behaviour for those.
--
-- New transactions created via the operator UI should populate this column
-- with a random UUID before generating the guest-facing QR/WhatsApp link.

alter table public.valet_transactions
    add column if not exists guest_request_token text;

create index if not exists valet_transactions_guest_token_idx
    on public.valet_transactions(guest_request_token)
    where guest_request_token is not null;
