# 08 — Accessibility & Responsive/Adaptive Behavior

## 8.1 WCAG 2.2 AA commitments (fixes audit E6)

| Criterion | Current failure | Our rule |
|---|---|---|
| **1.4.3 Contrast (text)** | `text-[10px]`/`text-[9px]` gray chips on dark; `content/faint` used for labels | Min `caption` 12sp; load-bearing text ≥ `content/muted` (6.1:1). `content/faint` decorative only. |
| **1.4.4 Resize text** | Fixed 9–10px | Type respects OS text scaling up to 200%; layouts reflow, no truncation of essential info. |
| **1.4.1 Use of color** | Status is color-only (9 hues) | Status = color **+** rail position **+** text label **+** icon. Colorblind-safe. |
| **1.4.11 Non-text contrast** | Hairline borders on dark | Interactive borders/focus ≥ 3:1. |
| **2.5.5 / 2.5.8 Target size** | `px-1.5 py-0.5` 10px chips | All interactive targets ≥ **48×48dp** (exceeds AA's 24px, meets AAA). |
| **2.4.7 Focus visible** | None | 2px `brand/300` focus ring + offset on every focusable; logical focus order. |
| **4.1.2 Name/Role/Value** | Icon-only buttons, emoji labels | Every control has a `Semantics(label/hint)`; emoji removed. |
| **2.3.3 Animation from interactions** | Pulses/spins always on | All motion respects reduced-motion → cross-fade ≤120ms. |
| **1.3.1 Info & relationships** | Visual-only grouping | Status rail exposes `Semantics` with current state + history to screen readers. |

## 8.2 Screen-reader experience (TalkBack / VoiceOver)

- **Transaction card** announces: *"Car M-H-0-1-A-B-1-2-3-4, status Requested, needs driver, waiting 4 minutes, unpaid. Double-tap to open, swipe right to assign driver."* (Plate read char-by-char via `Semantics` with spelled-out value.)
- **Status rail** is a single semantic node, not 8 unlabeled dots.
- **Live regions:** new assignments and status changes announced politely; errors assertively.
- **Driver swipe-to-advance** has an accessible alternative: the swipe track is also a focusable button ("Mark as parked") — gesture is never the *only* way (WCAG 2.5.1).

## 8.3 Touch & motor

- Primary actions in bottom 88px thumb band.
- 48dp targets, 8dp min spacing between targets.
- Swipe actions always have a tap equivalent (motor-impairment safe).
- Generous hit-slop on small visual elements (payment dot has 48dp hit area despite 16dp visual).

## 8.4 Cognitive

- One primary action per screen (Hick's Law).
- Progressive disclosure: detail lives in sheets, not crammed into cards (fixes the operator card overload, audit A2/A5).
- Recognition over recall: returning-guest auto-fill, suggested driver, auto key-slot.
- Plain language: no emoji codes, no jargon status strings shown raw (`waiting_for_driver` → "Waiting for driver").

## 8.5 Responsive / adaptive (mobile-first, but graceful up)

Flutter `LayoutBuilder` + breakpoints aligned to Material 3 window size classes.

| Class | Width | Layout |
|---|---|---|
| **Compact** | < 600dp (phones) | Single column. Bottom bar. Driver = full-bleed stack. **This is the design target.** |
| **Medium** | 600–839dp (small tablets, folded foldables, landscape phone) | Floor stays single-column but wider cards; Check-In as side sheet; bottom bar persists. |
| **Expanded** | ≥ 840dp (tablets, foldables open, desktop/web build) | **Two-pane:** list (Floor/People/Companies) on left rail, detail in right pane (replaces sheets). Bottom bar → `NavigationRail` on the left. |

- **Foldables:** detail opens on the second pane across the hinge; `TwoPane`/`MediaQuery.displayFeatures` hinge-aware padding.
- **Orientation:** driver mission card locks portrait (one-handed); operator/company adapt.
- **Safe areas:** `SafeArea` + bottom inset honored everywhere; primary actions never under the home indicator.
- **Text scaling:** at 200% scale, cards grow vertically and the rail wraps; no horizontal scroll, no clipped plates.

## 8.6 Environmental (the "worst moment" design)

- **Night/outdoor:** dark theme default, high-contrast plate/timer, large targets.
- **Gloves/rain:** big swipe zones, forgiving thresholds, haptic confirmation (you feel the commit without looking).
- **Weak signal:** offline queue + optimistic UI (doc 10 §Socket/offline); never block on the network.
- **One hand:** thumb-zone actions, swipe-primary; the driver never needs two hands.

## 8.7 Internationalization readiness

- All strings externalized (`.arb`), no concatenated sentences.
- RTL-safe layouts (logical start/end padding, mirror the rail).
- Plate/number formatting locale-aware where applicable; mono digits unaffected.
