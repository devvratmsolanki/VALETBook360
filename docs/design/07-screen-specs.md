# 07 — Screen Specifications

Concrete layouts, measured. Each screen lists structure, key tokens, and the full state matrix.

---

## 7.1 Auth — Login

**Structure (top→bottom):**
- Safe-area top, then 96px of `surface/950` breathing room.
- Wordmark **VĀLET** (`title-lg`, `content/strong`) + subtag `caption` `content/muted`, `letter-spacing 0.3em`.
- `VTextField` email → `VTextField` password (show/hide eye, 44px).
- `VPrimaryButton` "Sign in" (full width, thumb zone).
- Biometric chip below (Face/Touch ID) if previously enrolled.
- Footer `caption` legal.

**Tokens:** bg `surface/900`; single static `brand/500 @ 6%` radial behind wordmark (no dual blurred blobs — replaces `Login.jsx:40`).
**States:** default · loading (button spinner) · error (`VBanner` `alert/danger`, uses `ServiceError.userMessage` — fixes audit D3) · biometric-prompt · offline (disable + banner).
**Motion:** wordmark fade+rise 280ms on mount; error banner slide-down 200ms.
**A11y:** labels associated, `autofillHints`, error announced via live region, biometric has text fallback.

---

## 7.2 Operator — The Floor (home)

**App bar:** location name (`title`, tap to switch if multi-post operator) · notifications bell w/ live badge · avatar.

**Body (single column, `space/4` gutter):**
1. **Priority hero** — the single most urgent transaction (Requested, else Arrived-unpaid, else oldest Waiting). `VTransactionCard` enlarged, brand left edge if action-needed, swipe-to-act front and center. If nothing urgent → a calm "Floor is clear" `VEmptyState`.
2. **Filter pills** — `All · Waiting · Parked · Requested · Ready` (reuses the 5-bucket collapse from `getTransactionStats`). Active pill `brand/500 @ 15%`.
3. **Live feed** — `VTransactionCard` list, sorted urgency-desc, virtualized. Each: plate · timer · payment dot · guest · slot · driver · compact rail.

**FAB:** center-docked Check-In (`brand/500`).

**Card interactions:**
- Tap → `VBottomSheet` Transaction Detail.
- Swipe right → reveal + commit the legal next action (the only legal successor from `LEGAL_TRANSITIONS`). Threshold haptic.
- Long-press → quick actions (call guest, re-show QR, cancel).

**State matrix:**
| State | Treatment |
|---|---|
| Loading | 3× `VCardSkeleton` + skeleton hero |
| Empty (no active) | `VEmptyState` "Floor is clear" + "Check in a car" CTA |
| Populated | feed |
| Realtime update | card animates to new rail node in place (240ms); new card slides from top |
| Error (load) | inline `VBanner` + retry |
| Offline | top `VBanner` "Offline — actions will sync"; cards still actionable (queued) |

**Payment-gated delivery:** the Deliver swipe on an `arrived` card is **disabled** with a `VPaymentPill` pulsing "Take payment" — prevents the illegal action instead of toasting after (fixes audit A11).

---

## 7.3 Operator — Check-In (3 steps, sheet-stack)

Full-screen modal route, progress rail at top (3 nodes).

**Step 1 — Plate:**
- Big `mono-lg` input, auto-uppercase, strips spaces (preserves `OperatorDashboard.jsx:572` logic).
- Camera/OCR button (`brand/500`) to scan plate.
- On ≥4 chars, debounced 400ms lookup (preserves returning-guest detection L577). If found → "Welcome back" badge + name pre-fills.

**Step 2 — Guest:**
- Name field (pre-filled if returning). `body-lg`.
- Continue is the only thumb-zone action.

**Step 3 — Confirm & dispatch:**
- Summary: plate + guest.
- **Auto key-slot** card (preserves `getNextAvailableKeySlot`; `VKeySlotChip`). Recalc button.
- Driver picker (`VBottomSheet` list, suggested = on-shift drivers).
- Optional vehicle photos (multi, with `VUploadTile` progress — see doc 10 MinIO).
- `VPrimaryButton` "Check in".

**On success:** sheet dismisses with container-transform back to Floor; new card flies into feed; haptic + `VToast` "Checked in · Slot 7"; **QR offered as a non-blocking receipt sheet** (fixes audit C1) — operator can show it or skip.

**States:** per-step validation inline (reuse `isValidPhone` etc.); plate-not-valid disables continue; slot-capacity-full shows `alert/warn` "All slots full" with manual override; offline → queue check-in.

---

## 7.4 Operator — Transaction Detail (sheet)

- Drag handle, plate header (`mono-lg`), live timer.
- **Full `VStatusRail`** with timestamps (`requested_at`/`ready_at`/`delivered_at`).
- Guest (call/WhatsApp), car make/model/color, key slot, parked-by + retrieved-by drivers, parking photos (tap → lightbox), parking note + map deep-link, payment.
- Primary action (state-dependent swipe/button).
- Overflow: Reassign · Cancel · Re-show QR.

---

## 7.5 Driver — Mission Stack (home)

**Active `VMissionCard`** (full-bleed `surface/950`):
- Mission type ribbon (Park / Retrieve) top.
- **Plate** `display` mono, centered.
- Context block: slot chip, guest, (retrieve: pickup point + ETA + Navigate button).
- **Thumb-zone swipe track:** "Slide to mark parked" / "Slide — On my way" / "Slide — Arrived". Track fills `status` hue as dragged; commit at 75% + haptic.
- Up-next card peeks behind (scale 0.94, dimmed).

**Park capture** opens a `VBottomSheet`: GPS auto-captures (high→low fallback preserved from `DriverPanel.jsx:148`), photo, note — then the slide-to-confirm lives in the sheet (fixes audit B3, the buried CTA).

**Tasks drawer (swipe-up):** grouped Now · Parked (handed off) · Done today + Me.

**States:**
| State | Treatment |
|---|---|
| Loading | skeleton mission card |
| No missions | calm `VEmptyState` "No tasks — you're all caught up" |
| New assignment | card slides in from top + heavy haptic + sound |
| GPS denied | inline native permission prompt (not the PWA workaround modal, audit B4) |
| Offline | "Saved — will sync" chip on the card; mission advances locally |
| No driver profile | `VEmptyState` with a "Contact my manager" action (fixes dead-end B7) |

---

## 7.6 Company — Overview

- App bar: company name + search.
- **Live pulse** card: cars in motion across all locations (Socket-driven counter, animates).
- **Location health** horizontal cards: name · staffed? (operator on shift) · active cars · avg service time · incident dot.
- Quick actions row: + Driver · + Operator · + Location.
- This week strip: volume sparkline, top driver.

**States:** loading skeletons · empty (no locations → "Add your first location") · error retry.

---

## 7.7 Company — Locations / Location Detail

- **Locations:** searchable list, each card = name, address, live active-car count, capacity bar. FAB + Add.
- **Location Detail:** read-only floor mirror · key-slot config (custom-named vs numeric, preserves the two-mode model from `getNextAvailableKeySlot`/`slotService`) · operators at post · volume.

---

## 7.8 Company — People

- Segmented: Operators · Drivers.
- Searchable rows: avatar, name, phone, active toggle (drivers), "has login" badge.
- Row → detail (performance for drivers). FAB + Add → role-aware form with the **"create login"** toggle that runs `createStaff` + links via `user_id` (preserves CLAUDE.md driver-link flow).

---

## 7.9 Company / Admin — Reports

- Driver performance leaderboard (avg retrieval time, on-time %, volume) — redesign of `DriverPerformance.jsx`/`getDriverPerformanceStats`.
- Volume trends (day/week), per location.
- Export (CSV/PDF via Analytics service).

---

## 7.10 Admin — Pulse

- Global live counter (platform cars in motion).
- Tiles: companies · locations · active drivers · today's volume (redesign `AdminDashboard.jsx`).
- **Anomaly feed:** stuck transactions (in `requested` > N min), unpaid-overdue, error spikes — actionable rows.

---

## 7.11 Admin — Companies / Company Detail / People / Logs

- **Companies:** searchable cards → Company Detail (Overview · Locations · Operators · Drivers) — preserves the real `CompanyDetail` tab structure but as a mobile drill.
- **People:** Super Admins, then per-company collapsible (Owners · Operators · Drivers) — preserves `Users.jsx` hierarchy, made searchable.
- **Logs:** notification delivery log (`WhatsAppLogs`) + transaction audit (`AdminTransactions`), filterable.
- **Global search:** plate / name / phone / company / location → deep-jump.

---

## 7.12 Settings (all roles)

- Profile · **Change password** (preserves the re-auth-then-update flow from `Settings.jsx` — verify current password before update) · theme (system/dark/light) · notifications · biometric toggle · sign out.

---

## 7.13 Universal state components (systematized — fixes audit E5)

Every data surface ships with all five: **Loading (skeleton) · Empty · Error (retry) · Offline (banner + queue) · Success (haptic + state)**. No more per-page hand-rolled `Card p-8 text-center`.
