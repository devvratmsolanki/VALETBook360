# 04 — User Flows

Mermaid diagrams. The lifecycle preserves the real `STATUS_FLOW` and `LEGAL_TRANSITIONS` (`transactionService.js:9,16`) but redistributes *who* drives each transition to the most natural actor.

---

## 4.1 The canonical valet lifecycle (states preserved, actors clarified)

```mermaid
stateDiagram-v2
    [*] --> waiting_for_driver: Operator checks in car (plate+guest)
    waiting_for_driver --> parked: Driver swipes "Parked" (GPS+photo)
    parked --> key_in: Operator confirms key handover
    key_in --> requested: Guest requests car (QR/WhatsApp/operator)
    parked --> requested: Guest requests (key still with driver)
    requested --> driver_assigned: Operator assigns retrieval driver
    driver_assigned --> en_route: Driver swipes "On my way"
    en_route --> arrived: Driver swipes "Arrived"
    arrived --> delivered: Operator confirms (payment-gated)
    waiting_for_driver --> cancelled
    parked --> cancelled
    key_in --> cancelled
    requested --> cancelled
    driver_assigned --> cancelled
    en_route --> cancelled
    arrived --> cancelled
    delivered --> [*]
    cancelled --> [*]
```

> Note: this matches `LEGAL_TRANSITIONS` exactly. The redesign does **not** change the machine — it makes each edge a deliberate gesture by the right actor. Payment gate on `arrived → delivered` becomes a *pre-condition that disables the swipe*, not a post-tap toast (fixes audit A11).

---

## 4.2 Operator — Check-In flow (3 taps)

```mermaid
flowchart TD
    A[Tap Check-In FAB] --> B[Plate screen: camera OCR or type]
    B -->|>=4 chars| C{Returning car?}
    C -->|yes| D[Auto-fill guest name, badge 'Welcome back']
    C -->|no| E[Empty guest field]
    D --> F[Confirm screen]
    E --> F
    F --> G[Auto key-slot assigned + driver picker]
    G --> H[Tap 'Check in']
    H --> I[Card flies into Floor as 'Waiting'<br/>QR available on receipt sheet, non-blocking]
    I --> J[Haptic + toast 'Checked in · Slot 7']
```

Improvement over old `handleStep1`/`handleStep2`: QR no longer interrupts (audit C1); slot auto-fill kept (`getNextAvailableKeySlot`); returning auto-fill kept (audit C2).

---

## 4.3 Operator — Dispatch / retrieve flow

```mermaid
flowchart TD
    A[Guest requests car] -->|realtime| B[Card jumps to top of Floor, pulses, status=Requested]
    B --> C[Operator taps card or swipes]
    C --> D[Assign sheet: suggested driver pre-selected<br/>same driver who parked it, ETA default 8m]
    D --> E[Swipe 'Assign & notify']
    E --> F[Socket push to driver + WhatsApp to guest<br/>status=driver_assigned]
    F --> G[...driver progresses en_route -> arrived...]
    G --> H{Paid?}
    H -->|no| I[Deliver swipe disabled,<br/>'Take payment' pulses]
    H -->|yes| J[Swipe 'Deliver' -> delivered + celebration]
```

---

## 4.4 Driver — Park mission

```mermaid
flowchart TD
    A[New park mission pushed via Socket] --> B[Hero card: PLATE big, Slot, Guest]
    B --> C[Tap 'Capture spot' -> bottom sheet]
    C --> D[GPS auto-captures lat/lng, map link formed<br/>high->low accuracy fallback]
    D --> E[Optional: photo + note 'Pillar B2']
    E --> F[Swipe-up 'Mark Parked']
    F --> G[Optimistic: card collapses to 'Parked, hand key to operator']
    G --> H[Sync queued if offline]
```

Preserves GPS fallback (`DriverPanel.jsx:148`) and photo/remark capture, but as one sheet step instead of an inline tall form (fixes audit B3).

---

## 4.5 Driver — Retrieve mission

```mermaid
flowchart TD
    A[Retrieval assigned, Socket push + haptic] --> B[Hero card: PLATE, Slot, pickup point]
    B --> C[Tap 'Navigate' -> opens maps to parked GPS]
    C --> D[Swipe 'On my way' -> en_route]
    D --> E[Drive car to pickup]
    E --> F[Swipe 'Arrived' -> arrived]
    F --> G[Card shows 'Operator confirming...' waiting state]
    G --> H[Operator delivers -> card celebrates + clears]
```

---

## 4.6 Company — add a driver with login (preserves the createStaff link)

```mermaid
flowchart TD
    A[People tab -> + Add -> Driver] --> B[Form: name, phone, email]
    B --> C{Create login for driver panel?}
    C -->|yes| D[createStaff: auth user + users row role=driver]
    D --> E[createDriver linked via user_id]
    C -->|no| F[createDriver operational-only]
    E --> G[Driver can log into The Run]
    F --> H[Driver exists for assignment, no app login]
```

Mirrors the real `createStaff` → `createDriver` linkage described in CLAUDE.md so the driver panel resolves by `user_id`, not fuzzy name match.

---

## 4.7 Admin — onboard a company (one shot)

```mermaid
flowchart TD
    A[Companies -> + Company] --> B[Form: company, owner name, phone, email, initial password]
    B --> C[createCompanyWithOwner]
    C --> D{Owner account created?}
    D -->|fail| E[Roll back company row<br/>admin retries same email]
    D -->|ok| F[Company live, owner can log into The Org]
```

Preserves the rollback-on-failure composed-service pattern (`companyService.createCompanyWithOwner`).

---

## 4.8 Auth flow (mobile-native)

```mermaid
flowchart TD
    A[Launch] --> B{Valid token in secure storage?}
    B -->|yes| C{Biometric enabled?}
    C -->|yes| D[Face/Touch ID] --> E[Route by role]
    C -->|no| E
    B -->|no| F[Login: email + password]
    F --> G[POST Auth service -> JWT access+refresh]
    G --> H[Store in flutter_secure_storage] --> E
    E -->|driver| I[The Run]
    E -->|valet| J[The Floor]
    E -->|company| K[The Org]
    E -->|admin| L[Console]
```

Replaces the web `sessionStorage`/`AuthGate` redirect logic (`App.jsx:70`) with native secure storage + biometric, but keeps the role→home routing table identical.
