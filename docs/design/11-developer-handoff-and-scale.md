# 11 — Developer Handoff & Scalability

## 11.1 Handoff package contents

| Artifact | Status | Location |
|---|---|---|
| Design tokens (`tokens.json`, DTCG format) | to author from doc 6 | `docs/design/tokens.json` (next step) |
| Token → Flutter generator | recommend `theme_tailor` or custom build script | `mobile-app/lib/theme/` |
| Component specs (states, motion, a11y) | done | doc 06, 07 |
| Screen specs + state matrices | done | doc 07 |
| Flows | done | doc 04 |
| API contracts | derived | doc 10 |
| A11y acceptance criteria | done | doc 08 |

## 11.2 Definition of Done (per screen)

A screen is shippable only when **all** are true:
1. All five states implemented: loading (skeleton) · empty · error+retry · offline · success.
2. Every interactive target ≥ 48dp, in thumb zone if primary.
3. `Semantics` labels on all controls; screen-reader walkthrough passes.
4. Reduced-motion variant verified.
5. Contrast checked against tokens (no `content/faint` as text).
6. Realtime updates mutate state in place (no refetch, no spinner on live data).
7. Offline action queues + reconciles.
8. 60fps verified on a mid-tier Android (Pixel 6a class) with 30+ active cards.
9. Single brand accent rule honored (one `brand/500` fill per screen).
10. Strings externalized (`.arb`).

## 11.3 Build order (dependency-correct)

1. **Foundation:** tokens → ThemeData, DS components (`VPrimaryButton`, `VTransactionCard`, `VStatusRail`, `VMissionCard`, `VBottomSheet`, states), auth + go_router guard.
2. **Driver (The Run)** — smallest surface, highest gesture value, validates the swipe-to-advance + Socket + offline patterns end-to-end.
3. **Operator (The Floor + Check-In)** — the core. Reuses everything proven by the driver build.
4. **Company (The Org)** — overview, locations, people, reports.
5. **Admin (Console)** — pulse, companies, global search, logs.
6. **Polish pass** — celebrations, haptics, empty-state warmth, onboarding.

## 11.4 Scale-to-millions plan

The current architecture has three hard ceilings; here's how the redesign clears each.

### Realtime (today: refetch-on-event + 30s poll, `OperatorDashboard.jsx:138`)
- **Delta events over JWT-scoped rooms** (doc 10.5). A floor with 50 cars receives ~1 small event per change, not 3 full-table fetches.
- **Redis Socket.IO adapter** → horizontal realtime-gateway scaling; rooms shard by `location`/`company`.
- Bandwidth per active operator drops ~95%.

### Search (today: none; admin browses nested tables, `Users.jsx`)
- **search-service** backed by Postgres trigram/`pg_trgm` (or Elasticsearch/OpenSearch at the high end) indexing plate, name, phone, company, location.
- Global search is the admin's *primary* navigation, not a feature — required when companies/users hit millions.
- Typeahead debounced 200ms, results paginated, tenant-scoped.

### Notifications (today: poll 20 rows + localStorage read-state)
- **notification-service** with push (FCM/APNs) + an in-app feed paginated server-side; read-state server-stored (not `localStorage`, which doesn't survive reinstall/multi-device).
- Fan-out via the realtime gateway; badge counts from a Redis counter.

### Data volume
- Partition `valet_transactions` by month; hot partition stays small → fast floor/feed queries.
- Archive `delivered`/`cancelled` older than N days to cold storage; the floor only ever touches active rows (the status whitelist in `getActiveTransactions:62` already defines "hot").
- Read replicas for analytics/reports; writes to primary only.

### Dashboards
- Pre-aggregate stats in **analytics-service** (materialized views / scheduled rollups) instead of the current "fetch all rows and count in JS" (`getTransactionStats:217` loads every row). Live counters come from Redis, historical from rollups.

## 11.5 Risks & mitigations

| Risk | Mitigation |
|---|---|
| Swipe-to-advance accidental triggers (gloves/rain) | 75% drag threshold + haptic confirm + undo snackbar (5s) on every state advance |
| Offline conflict (two operators act on same car) | server is source of truth; idempotency keys; conflict → reconcile + toast "updated by someone else" |
| Plate OCR misreads | OCR pre-fills, operator confirms; manual edit always one tap |
| Brand-accent overuse creeping back | lint/DS rule: one `FilledButton` with primary color per screen; review gate |
| Reduced-motion forgotten | DS wraps all transitions; CI a11y check |

## 11.6 Future scalability recommendations

- **Guest app / web link:** the QR/WhatsApp request flow (`OperatorDashboard.jsx:178`) becomes a lightweight guest PWA ("request my car" + live ETA) — same transaction-service public route.
- **Driver presence → smart dispatch:** use presence + location to auto-suggest the nearest idle driver (data already captured via GPS).
- **Multi-language rollout** (i18n-ready from day one, doc 8.7).
- **Tablet podium mode** (Expanded layout, doc 8.5) for high-volume venues — two-pane floor + check-in.
- **SLA/anomaly alerting** (admin Pulse anomaly feed) → proactive incident detection at scale.

---

## 11.7 Memory note

Design conventions discovered and decided here (brand magenta `#A60445` is the single preserved accent; status must be a 1-ramp not 9 hues; thumb-zone primary actions; state machine = UX spine; realtime = deltas not refetch) are recorded to Nova's agent memory for future sessions on this product.
