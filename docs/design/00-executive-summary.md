# 00 — Executive Summary

**Product:** ValetBook360 → re-christened **VALET** (codename `Vālet`)
**Author:** Nova, Design Director
**Scope:** Total ground-up reinvention. Mobile-first Flutter (Material 3). Backend re-platformed off Supabase onto Java Spring Boot microservices + PostgreSQL + MinIO + Socket.IO + Docker.
**Preserved:** Brand color (magenta/pink `#A60445` family) + brand personality (premium, confident, dark-luxe). **Everything else is new.**

---

## The one-sentence thesis

> The current product is a **desktop dashboard squeezed onto phones**. The valet business is a **physical, on-your-feet, one-hand, gloves-on, outdoors-at-night** business. We are rebuilding it as a **gesture-first operational instrument** where the dominant verb is *"do the next thing"* — not *"read the table."*

---

## Why a reinvention, not a reskin

Three structural problems make a reskin pointless. Each is sourced from the real code:

1. **The operator dashboard is a two-column desktop grid** (`grid-cols-1 lg:grid-cols-2` in `src/pages/operator/OperatorDashboard.jsx:525`) with a 16-import lucide header, `text-[10px]` labels, and seven simultaneously-rendered status sections inside a `max-h-[calc(100vh-320px)] overflow-y-auto` scroll well. This is unusable as a phone-primary surface. On a phone the operator needs **one decision at a time**, thumb-reachable, not a scrollable wall of 10px chips.

2. **The state machine is excellent but invisible.** `STATUS_FLOW` (`transactionService.js:9`) is an 8-state lifecycle with legal-transition guarding (`LEGAL_TRANSITIONS:16`) — genuinely good domain modeling. But the UI scatters it across color chips with emoji (`🟠 Waiting`, `🅿️ Parked`) and per-status action buttons buried in a card's top-right corner. The lifecycle should be the **spine of the entire UX**, rendered as a live progress rail, not decoded from chip colors.

3. **Realtime is brute-force refetch.** Every Supabase `postgres_changes` event triggers a full `fetchAll()` (`OperatorDashboard.jsx:138`) plus a 30s polling heartbeat. This will not survive "millions of users." The Socket.IO rebuild must push **deltas**, not trigger refetches.

A reskin would carry all three forward. We will not.

---

## What we are building (the five-pillar redesign)

| Pillar | Old | New |
|---|---|---|
| **1. The Floor** (operator) | Two-column scroll grid of 10px chips | A single vertical **Live Floor** feed of large, swipeable transaction cards, each showing its position on a **status rail**. One thumb, one action. |
| **2. The Run** (driver) | Tab switcher + tall scrolling cards with inline camera/GPS forms | A **stack of full-bleed "mission" cards** advanced by **swipe-to-progress** gestures (En route → Arrived → Delivered), GPS/photo captured as a single fluid bottom-sheet step. |
| **3. Check-In** (operator) | 2-step form with auto-slot + QR modal | A **3-tap capture**: plate → guest → confirm. Camera-first, returning-guest auto-fill kept and elevated. |
| **4. The Org** (company/admin) | Lazy-loaded desktop tables + tabbed drilldowns | A **search-first command surface** + drill cards. Admin's hierarchy becomes a navigable tree, not nested tables. |
| **5. The System** (design system) | Ad-hoc Tailwind, `text-[10px]`, emoji status, inline hex (`#1e1e2d`, `#8e8e93`) | A tokenized Material 3 design system: `Vālet` type scale, 4pt spacing, semantic status tokens, motion specs in ms, full state coverage. |

---

## Headline metrics we are designing to move

- **Time-to-park** (guest hands keys → car parked & key-slotted): target a **40% reduction** by collapsing the operator's 2-step + driver's separate flow into one continuous handoff.
- **Taps-to-deliver** (guest requests → car delivered): from ~7 operator taps across modals to **3 swipes** end-to-end.
- **Glance comprehension:** an operator should read the floor state in **< 2 seconds** at arm's length, at night. (Today's 10px multi-color chips fail this.)
- **Driver one-handedness:** 100% of driver actions reachable in the bottom 1/3 thumb zone.

---

## Document map

| # | File | What it covers |
|---|---|---|
| 00 | `00-executive-summary.md` | This file |
| 01 | `01-ux-audit.md` | Full audit, code-cited, per surface |
| 02 | `02-strategy-and-positioning.md` | Product strategy, positioning, principles |
| 03 | `03-information-architecture.md` | IA + screen hierarchy per role |
| 04 | `04-user-flows.md` | Flow diagrams per role + transaction lifecycle |
| 05 | `05-navigation.md` | Mobile navigation redesign per role |
| 06 | `06-design-system.md` | Tokens: type, spacing, color, elevation, motion, icons, components |
| 07 | `07-screen-specs.md` | Concrete screen-by-screen layouts + states |
| 08 | `08-accessibility-responsive.md` | WCAG review + adaptive behavior |
| 09 | `09-flutter-implementation.md` | Material 3 widget map, navigation, animation timings |
| 10 | `10-backend-integration.md` | Microservices, Postgres, MinIO, Socket.IO, Docker |
| 11 | `11-developer-handoff-and-scale.md` | Handoff checklist + scale-to-millions plan |

---

## The non-negotiables (design constraints I am committing to)

1. **Thumb-first.** Primary actions live in the bottom 33% of the screen, always. No primary action in a card's top-right corner (the current `OperatorDashboard` anti-pattern).
2. **One brand accent, used scarcely.** `brand-500 #A60445` is for *the single most important action on screen*. We end the rainbow (today: orange, blue, indigo, red, amber, yellow, emerald, purple, gray all simultaneously). Status gets **one** semantic ramp, not nine hues.
3. **Motion explains state.** Every status transition animates along the rail (200–280ms). Nothing decorative; nothing under `prefers-reduced-motion`.
4. **No emoji as UI.** Emoji (`🅿️`, `🔑`, `💰`) are replaced by a real icon system. Emoji don't scale, don't theme, and fail screen readers.
5. **Offline-truthful.** The floor never lies about state (the existing optimistic-rollback instinct at `OperatorDashboard.jsx:344` is right — we systematize it with a queue).
