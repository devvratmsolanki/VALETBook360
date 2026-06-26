# 05 — Navigation Redesign (mobile-first, per role)

The web app's `Sidebar.jsx` (four hardcoded nav arrays) + `Header.jsx` is a desktop paradigm. On mobile it dies. We replace it per role.

## Global rules

- **Bottom navigation bar** for operator/company/admin (Material 3 `NavigationBar`), 3–4 destinations max (Hick's Law). Never 5+.
- **No bottom bar for the driver** — the driver lives in a focused mission stack; a bar would steal thumb space and split focus.
- **Bottom bar height 80px** (Material 3 spec) with 24px icons + 12sp labels; the active destination shows a pill indicator in `brand-500/15` with a `brand-500` icon.
- **One persistent FAB** only where it accelerates the core verb (operator Check-In). Center-docked, `brand-500`.
- **Back = swipe-from-edge** (iOS) / system back (Android), honored on every sheet and pushed route.
- **Sheets over pages** for transient tasks (detail, assign, capture). Pages only for true destinations.

---

## 5.1 Operator — bottom bar (3)

```
┌─────────────────────────────────────────┐
│                                         │
│              [ Floor feed ]             │
│                                         │
├─────────────────────────────────────────┤
│   ◉ Floor      ⊕ Check-In      ◌ Me     │   ← 80px NavigationBar
└─────────────────────────────────────────┘
```
- **Floor** (home, default) — the live feed.
- **Check-In** — center, visually promoted (raised FAB style), the most frequent action.
- **Me** — post, stats, notifications, settings.

Notifications bell does **not** get its own tab; it lives as a badge on the Floor app-bar (top-right) and a row in Me. Real-time count via Socket.

---

## 5.2 Driver — no bar, gesture stack

```
        ┌───────────────────┐
        │  ▒ up-next peek ▒  │
        │ ┌───────────────┐ │
        │ │  ACTIVE       │ │   swipe ← / → to advance state
        │ │  MISSION      │ │   swipe ↑  to open Tasks drawer
        │ │  (full-bleed) │ │   swipe ↓  to refresh (pull)
        │ └───────────────┘ │
        └───────────────────┘
```
- Navigation **is** the gesture. No tabs (kills the Park/Retrieve split, audit B2).
- A small **handle** at the top opens the Tasks drawer (all tasks + Me).
- Mission order is system-decided: retrieval-due > arrived-waiting > park-waiting > parked-handoff.

---

## 5.3 Company — bottom bar (4)

```
◉ Overview     ⌖ Locations     ⊙ People     ◔ Reports
```
- Search lives in the app-bar of Locations and People (not a tab).
- "+ Add" is a contextual FAB on Locations and People.

---

## 5.4 Admin — bottom bar (4) + persistent search

```
◉ Pulse        ⊞ Companies      ⊙ People       ▤ Logs
```
- **Global search** is a persistent pill in the app-bar across all four tabs: tap → full-screen search (plate / name / phone / company / location) → jump. This is the admin's true primary navigation at scale (doc 11 §Search).

---

## 5.5 Navigation transitions (motion)

| Transition | Pattern | Duration / curve |
|---|---|---|
| Bottom-bar tab switch | Shared-axis (horizontal) fade-through | 200ms `emphasized` |
| Open detail/assign sheet | Bottom sheet slide-up + scrim fade | 280ms `emphasizedDecelerate` |
| Dismiss sheet | Slide-down | 220ms `emphasizedAccelerate` |
| Driver state advance (swipe) | Card translate + rail node fill | 240ms spring (stiffness 320, damping 28) |
| Push (e.g. Location Detail) | Shared-axis (z, scale-up) | 260ms `emphasized` |
| FAB → Check-In | Container transform (FAB morphs into sheet) | 300ms `emphasized` |

All respect `MediaQuery.disableAnimations` / reduced-motion → cross-fade only, 120ms.

---

## 5.6 Why this beats the sidebar

- **Thumb-reachable:** bottom bar vs. top-left hamburger.
- **Fewer destinations:** 3–4 vs. the operator's old implicit everything-on-one-screen.
- **Role-true:** the driver gets *no* nav chrome — maximum focus, maximum screen for the mission.
- **Scales:** admin search replaces deep table-tree browsing.
