# 02 — Product Strategy & Positioning

## Positioning statement

> **VALET is the operating system for the valet floor.**
> For valet operators and their drivers, who run a fast, physical, error-prone service in seconds and in the dark — VALET is a mobile-first operations instrument that turns every car's journey into a single, swipeable, always-truthful line of motion. Unlike the spreadsheet-on-a-phone tools they use today, VALET is built for one thumb, one glance, and zero ambiguity.

## Who we serve (personas, derived from the four real roles)

### 1. Marco — the Operator (DB `valet`)
Stands at a podium at a hotel/restaurant entrance. Phone in one hand, keys in the other. Greets guests, triages, assigns drivers, takes payment, hands cars back. **Peak chaos at 8pm Friday.** His job is *triage and dispatch*. He needs: the single most urgent car, the next action, and proof of state. He does **not** need a scrollable table.

> Design implication: Marco gets the **Live Floor** — a prioritized single feed, top card = most urgent, swipe to act.

### 2. Diego — the Driver (DB `driver`)
On his feet, running between the podium and a multi-level garage. Phone in pocket, pulled out between sprints, often one-handed, sometimes with the wrong glove on. **Latency-sensitive:** every second he stares at a screen is a second not running. Needs: *what car, what slot, where, navigate, done.*

> Design implication: Diego gets **The Run** — full-bleed mission cards, swipe-to-advance, GPS/photo as one fluid step, map deep-link.

### 3. Priya — the Company Manager (DB `manager`, UI `company`)
Runs 3 hotels' valet contracts. Mostly off-floor, on her phone between meetings. Cares about: are my locations staffed, are drivers performing, any incidents, this week's volume. Occasionally adds a driver or operator.

> Design implication: Priya gets **The Org** — a search-first overview, location health cards, driver leaderboard, fast "add staff."

### 4. Sam — the Super Admin (DB `admin`)
Platform owner. Onboards companies, audits everything, resolves escalations. Needs a navigable hierarchy (company → location → user) and global search.

> Design implication: Sam gets the **Admin Console** — a drill-down tree + global command search, not nested HTML tables.

## Product principles (the constitution)

1. **The next action is always one gesture away.** If the user has to scroll to find what to do, we failed. The system surfaces the highest-priority pending action.
2. **State is sacred and visible.** The 8-state lifecycle is the product's spine, rendered as a live rail on every transaction. Never decode state from a color chip.
3. **One accent, used like a scalpel.** `brand-500` marks *the* primary action and nothing else. Status uses one neutral→hot semantic ramp.
4. **Built for the worst moment.** Night, rain, gloves, 8pm rush, weak signal. Big targets, high contrast, offline-tolerant, optimistic-but-honest.
5. **Realtime, not refresh.** Socket.IO deltas mutate local state in place. No spinners on live data.
6. **Delight at the peak and the end** (Peak-End Rule): the "car delivered" moment and the daily "floor cleared" moment get a crafted micro-celebration. Everything else gets out of the way.

## Competitive craftsmanship targets (what to borrow in spirit, never in form)

| Reference | What we take | What we will NOT copy |
|---|---|---|
| **Linear** | Keyboard/command speed, status-as-spine, restraint | Its desktop density |
| **Revolut** | Mobile money confidence, swipe primary actions, card stacks | Its consumer-finance chrome |
| **Arc** | Spatial, gesture navigation, playful-but-fast | Its tab-everything model |
| **Stripe** | Trustworthy data viz, precise typography | Its enterprise grayness |
| **Apple (iOS)** | Thumb zones, haptics, motion physics, clarity | Skeuomorphism |
| **Airbnb** | Warmth in empty/onboarding states | Its photography-first IA |

**The unique identity:** *dark-luxe operational instrument.* Near-black surfaces, a single confident magenta, crisp mono for codes/plates/timers, and motion that feels like a precision machine — a Leica, not a toy.

## Business objectives the design serves

- **Reduce service time** → more cars/hour/operator → higher venue throughput → stickier contracts.
- **Reduce errors** (wrong car, lost key, unpaid delivery) → fewer incidents → trust → retention.
- **Make onboarding trivial** → admin/company can stand up a new location in minutes → faster platform growth.
- **Scale to millions** → realtime + search + notifications architected for fan-out from day one (doc 11).
