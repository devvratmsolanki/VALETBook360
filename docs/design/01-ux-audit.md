# 01 — UX Audit (code-cited)

Every finding below references the real file. Severity: **P0** = blocks the mobile-first goal, **P1** = serious, **P2** = polish.

---

## A. Operator dashboard — `src/pages/operator/OperatorDashboard.jsx`

This is an 855-line file doing seven jobs at once. It is the heart of the product and the most broken surface for mobile.

| # | Sev | Finding | Evidence |
|---|---|---|---|
| A1 | **P0** | **Desktop two-column grid.** Check-in form and car list sit side by side (`grid-cols-1 lg:grid-cols-2`, line 525). On a phone these stack into one endless scroll; neither half is thumb-optimized. | L525 |
| A2 | **P0** | **Seven status sections render simultaneously** inside one scroll container (`renderSection` ×7, L740–746) capped at `max-h-[calc(100vh-320px)]`. The operator must scroll a wall to find the one car that needs action. No prioritization, no "what's next." | L739–747 |
| A3 | **P0** | **Primary actions hidden top-right of each card.** Status action buttons live in a `flex flex-col items-end` column (L448) — the hardest place to reach one-handed, in `text-[10px]` (~10px tap text). | L448–500 |
| A4 | **P1** | **Nine simultaneous status hues.** `tileStyles` defines orange/blue/indigo/red/amber/yellow/emerald/gray + brand (L48–57). At a glance the floor is a rainbow; no hue carries consistent meaning (amber = driver_assigned, yellow = en_route — indistinguishable at night). | L48–57 |
| A5 | **P1** | **Emoji as functional UI.** `📍`, `🔑`, `📌`, `💰`, `💳`, `🅿`, `🚗`, `🗺️` are load-bearing labels (L419–444). Inconsistent across platforms, invisible to screen readers, unthemeable. | L419–444 |
| A6 | **P1** | **Tap-target violations.** Payment toggle, QR button, map link are all `text-[10px] px-1.5 py-0.5` chips (L429, 439) — far under the 44×44px minimum. | L429–445 |
| A7 | **P1** | **Realtime = full refetch + 30s poll.** Each event calls `fetchAll()` (L138) and a `setInterval(fetchAll, 30000)` (L139) runs regardless. Three round-trips per refresh (txs + drivers + locations, L108). Does not scale. | L106–141 |
| A8 | **P2** | **Two LiveTimer intervals per card, 1s tick** (L29–45). With 30 active cars that's 30 timers at 1Hz re-rendering. | L29 |
| A9 | **P2** | **Inline-built file inputs** via `document.createElement('input')` inside onClick (L684, L317) — imperative DOM in React, no preview/progress/retry contract. | L684 |
| A10 | **P1** | **QR modal uses hardcoded hex** (`#111111`, `#1e1e2d`, `#8e8e93`, L798–836) bypassing the token system entirely, and a hardcoded fallback WhatsApp number (`'919106597391'`, L184). | L184, L798 |
| A11 | **P1** | **Payment gating is a toast slap.** Delivering unpaid throws `toast.error('⛔ Payment must be confirmed...')` (L338) — punishment after the tap instead of preventing the illegal action up front. | L335–339 |

**Verdict:** This screen must be rebuilt from zero as a single-column, action-prioritized **Live Floor**, not refactored.

---

## B. Driver panel — `src/pages/driver/DriverPanel.jsx`

Closest to mobile-native intent (it's `max-w-md`, has stat tiles, tabs) but still form-heavy and tap-driven where it should be gesture-driven.

| # | Sev | Finding | Evidence |
|---|---|---|---|
| B1 | **P0** | **Direct `supabase.from(...)` in the component** (L83, L111) — violates the project's own service-layer rule (CLAUDE.md). Tight coupling makes the Spring Boot migration painful. | L83, L111 |
| B2 | **P1** | **Tab switcher splits one mental job.** Park / Retrieve tabs (L544) hide half the driver's work. A driver's reality is a single ordered queue of "next task," not two buckets to toggle. | L544–559 |
| B3 | **P1** | **GPS + remarks + multi-photo all crammed into the park card** before the action button (L266–338). The card is tall; the "Mark Parked" CTA is below the fold after photos. | L266–351 |
| B4 | **P1** | **Browser-geolocation permission modal teaches PWA workarounds** ("Tap the Compass icon or Aa in the address bar", L623). Irrelevant once native — but symptomatic: the whole GPS UX is built around browser limitations. | L607–642 |
| B5 | **P1** | **Gradient CTAs everywhere** (`from-emerald-500 to-emerald-600`, `from-blue-500 to-blue-600`, L344, L468). Color-codes actions by hue rather than by hierarchy; clashes with single-accent brand. | L344, L468, L478 |
| B6 | **P2** | **No swipe gestures at all.** Every transition is a button tap. The driver flow (assigned→en route→arrived) is the *textbook* swipe-to-advance pattern and uses none of it. | whole file |
| B7 | **P2** | **"No driver profile found" dead-end** (L496) has no recovery path — just "ask your admin." | L496–506 |

---

## C. Check-in flow — `OperatorDashboard.jsx` (`handleStep1`/`handleStep2`)

| # | Sev | Finding | Evidence |
|---|---|---|---|
| C1 | **P1** | **Two-step with a QR interruption.** Step 1 registers + pops a full-screen QR modal (L243), then Step 2 collects driver/key/photos. The QR modal *blocks* progress mid-flow. | L243, L797 |
| C2 | **P2** | Good: **returning-vehicle auto-fill** debounced at 400ms (L577) is a genuinely nice touch — keep & elevate it. | L577 |
| C3 | **P1** | **Visitor identity is faked via `CAR-${plate}` phone** (L210). The "visitor" model is a workaround. Worth fixing in the data model (see doc 10). | L210 |
| C4 | **P2** | Validation lives inline in handlers (`name.trim().length < 2`, L202) rather than reusing `isValidPhone`/etc. helpers the CLAUDE.md says all forms should use. | L202–205 |

---

## D. Login — `src/pages/Login.jsx`

| # | Sev | Finding | Evidence |
|---|---|---|---|
| D1 | **P2** | **Solid for web, generic for premium mobile.** Blurred blobs + glass card (L40–53) is the 2021 SaaS login. No biometric, no "remember me," no role hint. | L40–53 |
| D2 | **P2** | **`font-serif` Playfair brand wordmark** (L49) — the one place serif appears. Either commit to it as brand voice or drop it; currently orphaned. | L49 |
| D3 | **P1** | **Error is a raw string** (`err.message`, L32) — not the `ServiceError.userMessage` pattern CLAUDE.md mandates. | L32 |

---

## E. Cross-cutting / systemic

| # | Sev | Finding | Evidence |
|---|---|---|---|
| E1 | **P0** | **No design tokens.** `tailwind.config.js` has 6 brand shades + 6 dark shades and three keyframes — no spacing scale, no type scale, no elevation, no semantic status tokens. Everything is ad-hoc utility soup with `text-[10px]`, `text-[9px]`, arbitrary hex. | `tailwind.config.js` |
| E2 | **P0** | **Layout forces desktop chrome on mobile.** `Layout.jsx` wraps every route in Sidebar+Header; the driver panel is explicitly a `max-w-md` island *inside* that desktop frame (CLAUDE.md). Mobile-native has no sidebar. | `Layout.jsx` |
| E3 | **P1** | **Status taxonomy leaks UI inconsistency.** Operator collapses 8 states into 5 buckets (`getTransactionStats`, `transactionService.js:232`) but the dashboard renders all 8; driver renders 5. Three different mental models of the same machine. | `transactionService.js:232` |
| E4 | **P1** | **Notifications are role-scoped polling of 20 rows** with `localStorage` read-state (NotificationsBell, per CLAUDE.md). No grouping, no priority, no push. | CLAUDE.md |
| E5 | **P1** | **No empty/loading/error system.** Each page hand-rolls its own (`Card p-8 text-center`, L737). No skeletons, no consistent error recovery, no offline state. | L732–737 |
| E6 | **P2** | **Accessibility largely absent.** No `aria-*`, no focus-visible system, color-only status encoding (fails colorblind), 10px text fails WCAG 1.4.4, icon-only buttons lack labels. | throughout |

---

## F. What is genuinely good (preserve the intent)

1. **The state machine + legal-transition guard** (`transactionService.js:16`). Domain model is correct; surface it.
2. **Optimistic update with rollback** (`OperatorDashboard.jsx:344`). Right instinct — systematize into an offline queue.
3. **Returning-guest auto-fill** (L577). Delightful; keep.
4. **GPS capture with high→low accuracy fallback** (`DriverPanel.jsx:148`). Robust; carry to native.
5. **Service-layer discipline** (everywhere except DriverPanel). The camelCase→snake_case mapping and whitelist-insert pattern (`transactionService.js:74`) is exactly the contract Spring Boot DTOs should mirror.
6. **Per-tenant scoping refusal** (`getActiveTransactions` returns `[]` without companyId, L51). Security-first instinct — preserve as a hard rule server-side.

---

## Audit scorecard (current product, mobile-first lens)

| Dimension | Score /10 | Note |
|---|---|---|
| Visual hierarchy | 3 | 10px rainbow chips, no focal point |
| One-handed operability | 2 | Primary actions top-right, desktop grid |
| Glance comprehension | 3 | 9 hues, emoji, dense |
| Feedback & states | 4 | Toasts good; no skeletons/empty/offline system |
| Accessibility | 2 | Color-only status, sub-min targets, no ARIA |
| Motion | 3 | 3 keyframes, mostly decorative |
| Scalability of patterns | 3 | Refetch-on-everything, no tokens |
| Domain modeling | 8 | State machine is strong |
| **Composite** | **3.5/10** | Strong backend logic, weak mobile experience |
