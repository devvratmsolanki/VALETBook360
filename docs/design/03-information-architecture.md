# 03 — Information Architecture & Screen Hierarchy

Principle: **per-role apps that happen to share a binary.** A driver and a super admin should feel like they opened different products. No shared sidebar. Navigation = a role-specific bottom bar (drivers/operators) or a search-led hub (company/admin).

---

## 3.1 Role → app shell mapping

| Role | Shell | Primary nav | Home screen |
|---|---|---|---|
| `driver` | **The Run** | None — single-stack mission flow + a peek drawer | Task stack |
| `valet` (operator) | **The Floor** | 3-tab bottom bar | Live Floor |
| `company` (manager) | **The Org** | 4-tab bottom bar | Overview |
| `admin` (super) | **Console** | 4-tab bottom bar + global search | Pulse |

---

## 3.2 Operator IA — "The Floor"

```
The Floor (bottom bar: Floor · Check-In · Me)
├── Floor (home)
│   ├── Priority strip (the 1 most-urgent car, hero card)
│   ├── Live feed (single column, status-rail cards, newest-actionable first)
│   ├── Filter pill row (All · Waiting · Parked · Requested · Ready)
│   └── Per-card: tap → Detail sheet; swipe → advance state
├── Check-In (FAB-promoted, also a tab)
│   ├── Step 1: Plate (camera/OCR + manual) → returning-guest auto-fill
│   ├── Step 2: Guest name (prefilled if returning)
│   └── Step 3: Confirm → driver + auto key-slot → done (QR on receipt, not blocking)
├── Transaction Detail (sheet, not page)
│   ├── Status rail (live)
│   ├── Car · Guest · Key slot · Driver(s) · Photos · Payment
│   ├── Primary action (swipe or button, state-dependent)
│   └── Overflow: Cancel · Reassign · Re-show QR · Call guest
└── Me
    ├── My location / post
    ├── Today's stats (cars served, avg time)
    ├── Notifications
    └── Settings · Change password · Sign out
```

**Key IA decision:** the operator no longer scrolls 8 sections. The feed is **one stream, sorted by urgency** (Requested > Arrived-unpaid > Waiting > rest), with a filter pill row for when they want a specific bucket. The buckets reuse the existing 5-bucket collapse (`getTransactionStats`).

---

## 3.3 Driver IA — "The Run"

```
The Run (no bottom bar — single mission stack + peek drawer)
├── Mission Stack (home)
│   ├── Active mission (full-bleed hero card)
│   ├── Up-next preview (peek of card behind)
│   └── Swipe up = drawer of all my tasks
├── Park mission
│   └── Slot · Car · Guest → [capture spot: GPS auto + photo + note] → swipe "Parked"
├── Retrieve mission
│   └── Car · Slot · pickup point · guest call → Navigate → swipe "On my way" → swipe "Arrived"
├── Tasks drawer (swipe-up)
│   └── All assigned, grouped: Now · Parked (handed off) · Done today
└── Me (in drawer)
    └── Shift stats · Notifications · Settings · Sign out
```

**Key IA decision:** kill the Park/Retrieve tab split (`DriverPanel.jsx:544`). One **mission stack**, ordered by what to do next. The system decides the order; the driver just advances.

---

## 3.4 Company IA — "The Org"

```
The Org (bottom bar: Overview · Locations · People · Reports)
├── Overview
│   ├── Live company pulse (cars in motion right now across all locations)
│   ├── Location health cards (staffed? volume? incidents?)
│   └── Quick actions: + Driver · + Operator · + Location
├── Locations
│   ├── List (search) → Location Detail
│   │   ├── Live floor mirror (read-only)
│   │   ├── Key-slot config (custom named OR numeric capacity)
│   │   ├── Operators at this post
│   │   └── Volume + avg service time
├── People
│   ├── Operators (search) → detail → create login
│   ├── Drivers (search, active toggle) → detail → performance → create login
│   └── + Add (sheet: role-aware form)
└── Reports
    ├── Driver performance (the existing perf stats, redesigned)
    ├── Volume trends
    └── Export
```

---

## 3.5 Admin IA — "Console"

```
Console (bottom bar: Pulse · Companies · People · Logs) + global search
├── Pulse (platform home)
│   ├── Global live counter (cars in motion platform-wide)
│   ├── Companies · Locations · Active drivers · Today's volume
│   └── Anomaly feed (errors, stuck transactions, unpaid-overdue)
├── Companies
│   └── List → Company Detail (Overview · Locations · Operators · Drivers)
│       └── reuses Org screens with admin scope (mirrors current CompanyDetail tabs)
├── People (global)
│   └── Super Admins · then per-company collapsible (Owners · Operators · Drivers)
├── Logs
│   └── Notification/WhatsApp delivery log, filterable
└── Global Search (⌘-style, persistent)
    └── Type a plate, name, phone, company, location → jump anywhere
```

**Key IA decision:** Admin's nested-table hierarchy (`Users.jsx`, `CompanyDetail.jsx`) becomes **search-first + drill cards**. At "millions of users" scale, browsing a tree is dead; typing a plate or name and jumping is the only viable model (doc 11 covers the search service).

---

## 3.6 Screen inventory (new) vs. old pages

| New screen | Replaces (old file) |
|---|---|
| Floor (operator home) | `OperatorDashboard.jsx` (right column) |
| Check-In flow | `OperatorDashboard.jsx` (left column), `CheckIn.jsx` |
| Transaction Detail sheet | (none — was inline card) |
| Mission Stack + Park/Retrieve missions | `DriverPanel.jsx` |
| Tasks drawer | `DriverPanel.jsx` tabs |
| Org Overview | `CompanyDashboard.jsx` |
| Locations / Location Detail | `Locations.jsx`, `LocationDetail.jsx` |
| People (Operators/Drivers) | `Drivers.jsx`, `Staff.jsx`, `DriverSelect` |
| Reports | `DriverPerformance.jsx`, `Contracts.jsx`, `CompanyTransactions.jsx` |
| Console Pulse | `AdminDashboard.jsx` |
| Companies / Company Detail | `Companies.jsx`, `CompanyDetail.jsx` |
| Admin People | `Users.jsx`, `AdminLocations.jsx` |
| Logs | `WhatsAppLogs.jsx`, `AdminTransactions.jsx` |
| Global Search | (none — new) |
| Auth / Onboarding | `Login.jsx` |
| Settings | `Settings.jsx` |
