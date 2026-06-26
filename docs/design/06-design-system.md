# 06 — Design System: "Vālet DS"

A tokenized system. Values are given as **design tokens** with Flutter `ThemeData`/`ColorScheme` mappings *and* the legacy Tailwind equivalents so web parity is possible. Built on the **preserved brand magenta + dark palette**; everything else is new.

---

## 6.1 Color

### 6.1.1 Brand ramp (PRESERVED — from `tailwind.config.js`)

| Token | Hex | Use |
|---|---|---|
| `brand/300` | `#E84A7A` | Hover/pressed accents, gradient top |
| `brand/400` | `#D42862` | Secondary accent, focus glow |
| `brand/500` | `#A60445` | **THE accent.** Primary action, active nav, key-slot chip |
| `brand/600` | `#8A0339` | Pressed primary |
| `brand/700` | `#6E032E` | Deep accent borders |
| `brand/900` | `#3A0119` | Accent tint backgrounds |

**Rule:** `brand/500` appears at most **once per screen as a filled element** (the primary action). Everywhere else it's a tint (`brand/500 @ 8–15% alpha`). This is the single biggest visual fix vs. the current rainbow.

### 6.1.2 Surface ramp (PRESERVED dark + extended)

| Token | Hex | Use |
|---|---|---|
| `surface/950` | `#030303` | App background (driver full-bleed) |
| `surface/900` | `#050505` | Scaffold background |
| `surface/800` | `#0F0F0F` | Card / sheet base |
| `surface/700` | `#1A1A1A` | Raised card, input field |
| `surface/600` | `#2A2A2A` | Pressed/elevated, dividers |
| `surface/500` | `#3A3A3A` | Hairline borders, disabled |

### 6.1.3 Content (text/icon) tokens (NEW — fixes contrast)

| Token | Value | Contrast on `surface/800` | Use |
|---|---|---|---|
| `content/strong` | `#FFFFFF` | 19:1 | Plates, headings, primary numbers |
| `content/default` | `#E6E6E6` | 15:1 | Body |
| `content/muted` | `#9A9A9A` | 6.1:1 | Secondary labels (replaces all `text-gray-500` at proper size) |
| `content/faint` | `#6B6B6B` | 3.4:1 | **Decorative only** — never load-bearing text (WCAG) |
| `content/onAccent` | `#0A0A0A` | — | Text on `brand/500` fills (matches existing `text-black` on brand) |

### 6.1.4 Status semantic ramp (NEW — replaces the 9-hue chaos, audit A4)

The 8 lifecycle states collapse into **one perceptual progression** + 2 alert colors. State is read by **position on the rail + a single hue temperature shift**, not by memorizing 9 colors.

| Lifecycle state | Token | Hex | Temperature |
|---|---|---|---|
| `waiting_for_driver` | `status/queued` | `#7A8AA0` (cool slate) | coldest = newest/idle |
| `parked` | `status/settled` | `#5A8FB0` (steel blue) | |
| `key_in` | `status/secured` | `#5AA0A0` (teal) | |
| `requested` | `status/active` | `#C77DAE` (brand-tinted, **pulses**) | warming = needs action |
| `driver_assigned` | `status/dispatched` | `#D08A5A` (amber) | |
| `en_route` | `status/moving` | `#D6A94E` (gold) | |
| `arrived` | `status/ready` | `#5BB98C` (green) | "go" |
| `delivered` | `status/done` | `#6B6B6B` (faint, receded) | cooled, archived |

| Alert | Token | Hex |
|---|---|---|
| Payment due / blocking | `alert/warn` | `#E0A93A` |
| Error / cancelled / overdue | `alert/danger` | `#E0564E` |
| Success confirm | `alert/success` | `#4FB97E` |

> The rule: **one** status color per card, applied as the rail node + a 2px left edge. No multi-color chip soup. `requested` (needs operator) and `arrived` (ready) are the only two that "shout."

### 6.1.5 Light mode

Dark is primary (operational, night use). A light theme inverts: `surface` ramp → `#FFFFFF → #F4F4F5 → #E8E8EA`, content inverts, brand and status hues stay (they're tuned to pass AA on both). Auto via `ThemeMode.system`.

---

## 6.2 Typography — "Vālet Type Scale"

**Families:** keep **Inter** (UI) from current config; introduce **JetBrains Mono** for plates/codes/timers/slots (mono communicates "machine truth"). Drop orphaned Playfair serif (audit D2) — or reserve it solely for the splash wordmark.

| Token | Size / line / weight | Use |
|---|---|---|
| `display` | 34 / 40 / 700 | Plate hero on driver mission card |
| `title-lg` | 24 / 30 / 700 | Screen titles |
| `title` | 20 / 26 / 600 | Section headers, card plate (operator) |
| `body-lg` | 17 / 24 / 500 | Primary body |
| `body` | 15 / 22 / 400 | Default body |
| `label` | 13 / 18 / 600 | Buttons, nav labels, chips |
| `caption` | 12 / 16 / 500 | Secondary meta (the **floor** for readable UI — no more 10px/9px) |
| `mono-lg` | 22 / 28 / 600 (mono) | Plate / slot hero |
| `mono` | 15 / 20 / 500 (mono) | Timers, key codes, IDs |

**Hard rule:** minimum on-screen text is `caption` (12sp). The current `text-[10px]`/`text-[9px]` (e.g. operator chips, driver stat labels) are eliminated — they fail WCAG and arm's-length legibility.

---

## 6.3 Spacing & layout (NEW — 4pt base)

| Token | px | Use |
|---|---|---|
| `space/0` | 2 | hairline gaps |
| `space/1` | 4 | icon-to-text |
| `space/2` | 8 | tight stack |
| `space/3` | 12 | intra-card |
| `space/4` | 16 | **default gutter / screen padding** |
| `space/5` | 20 | card padding |
| `space/6` | 24 | section gap |
| `space/8` | 32 | major section gap |
| `space/12` | 48 | hero spacing |

- **Screen edge padding:** `space/4` (16) on phones, `space/6` (24) on tablet/foldable.
- **Thumb zone:** all primary actions live within the bottom **88px** safe band (above the bottom bar/home indicator).

## 6.4 Radius

| Token | px | Use |
|---|---|---|
| `radius/sm` | 8 | chips, input |
| `radius/md` | 12 | buttons |
| `radius/lg` | 16 | cards (matches current `rounded-xl`/`2xl` instinct) |
| `radius/xl` | 24 | sheets, mission cards |
| `radius/full` | 999 | pills, avatars, FAB |

## 6.5 Elevation (NEW — dark-aware)

Dark UIs can't rely on drop shadows alone; we combine **surface lift + subtle shadow + optional brand glow**.

| Token | Surface | Shadow | Glow |
|---|---|---|---|
| `elev/0` | `surface/900` | none | — |
| `elev/1` (card) | `surface/800` | `0 1 2 rgba(0,0,0,.4)` | — |
| `elev/2` (raised) | `surface/700` | `0 4 12 rgba(0,0,0,.5)` | — |
| `elev/3` (sheet) | `surface/800` | `0 -8 32 rgba(0,0,0,.6)` | — |
| `elev/accent` (primary CTA) | `brand/500` | `0 4 16 rgba(166,4,69,.35)` | reuses existing `pulse-brand` keyframe |

## 6.6 Iconography

- **Library:** Material Symbols (Rounded, weight 400, optical 24). Replaces lucide-react + **all emoji** (audit A5/B5).
- **Mapping examples:** `directions_car` (car), `vpn_key` (slot), `near_me`/`navigation` (GPS), `payments` (payment), `local_parking` (parked), `bolt`/`notifications_active` (requested), `check_circle` (delivered).
- Icon-only buttons **must** carry a `Semantics(label:)` (a11y, audit E6).
- Status is **never** icon-color-only — always icon + rail position + text label (colorblind safety).

## 6.7 Motion guidelines

| Motion | Duration | Curve | Purpose |
|---|---|---|---|
| State advance on rail | 240ms | spring(320, 28) | the core "machine moved" feeling |
| Card enter (new tx) | 280ms | emphasizedDecelerate | new car arrives, slides + fades from top |
| Card exit (delivered) | 320ms | emphasizedAccelerate | settles, desaturates to `status/done` |
| Requested pulse | 1600ms loop | reuse `pulseBrand` keyframe | draw the eye to action-needed |
| Swipe-to-advance drag | tracks finger | — | direct manipulation |
| Success celebration | 600ms | custom | confetti-lite + haptic on delivered |
| Skeleton shimmer | 1200ms loop | linear | loading |
| Pull-to-refresh | tracks finger | spring | manual refresh |

**Reduced motion:** all of the above degrade to ≤120ms cross-fades; no spring, no pulse, no celebration animation (haptic + static success state instead).

## 6.8 Haptics (native)

| Event | Haptic |
|---|---|
| State advance | `HapticFeedback.mediumImpact` |
| New assignment (driver) | `HapticFeedback.heavyImpact` + sound |
| Delivered / success | success pattern (light-light) |
| Error / illegal action | `HapticFeedback.vibrate` (error pattern) |
| Swipe threshold reached | `HapticFeedback.selectionClick` |

---

## 6.9 Component library (named, with states)

Every component specifies: **default · hover/pressed · focus · loading · disabled · error/empty**.

### `VPrimaryButton`
- Default: `brand/500` fill, `content/onAccent`, `radius/md`, 52px tall, `label` type, `elev/accent`.
- Pressed: `brand/600`, scale 0.98 (matches existing `active:scale-[0.98]`).
- Focus: 2px `brand/300` ring + offset.
- Loading: spinner replaces label, button width locked.
- Disabled: `surface/600` fill, `content/faint`, no glow.
- **One per screen.**

### `VSecondaryButton` / `VGhostButton`
- Outline (`surface/500` 1px) / text-only. Never `brand` filled.

### `VStatusRail`
- Horizontal 8-node rail (one per lifecycle state). Past = filled `status` hue, current = filled + pulse if action-needed, future = `surface/600` outline.
- Compact variant (operator card): 8 tiny dots. Full variant (detail sheet): labeled nodes with timestamps from `requested_at`/`ready_at`/`delivered_at`.

### `VTransactionCard` (operator floor)
- `elev/1`, `radius/lg`, 2px left edge in current `status` hue.
- Row 1: **plate** (`mono-lg`, `content/strong`) · live timer (`mono`, `content/muted`) · payment dot.
- Row 2: guest name (`body`) · key slot chip · driver chip.
- Row 3: compact `VStatusRail`.
- Swipe-right reveals the legal next action (color = brand only if it's the primary verb).
- States: loading→`VCardSkeleton`; empty→`VEmptyState`; error→inline retry.

### `VMissionCard` (driver, full-bleed)
- `surface/950` bg, `radius/xl`, fills viewport minus safe areas.
- Plate in `display` mono, centered top third.
- Mid: slot, pickup point, guest call button (44px+).
- Bottom third (thumb zone): swipe-to-advance track with the next verb + chevrons.

### `VKeySlotChip`
- `brand/500 @ 12%` bg, `brand/400` text, `vpn_key` icon, `mono` slot number. Replaces `🔑` (audit A5).

### `VPaymentPill`
- Paid: `alert/success @ 15%`, check icon. Unpaid: `alert/warn @ 15%`, pulsing when blocking a delivery. 44px tap target (fixes audit A6).

### `VBottomSheet`
- `elev/3`, `radius/xl` top corners, drag handle, scrim `surface/950 @ 60%` + 8px blur. Used for detail, assign, capture.

### `VEmptyState`
- Centered icon (`content/faint`), `body-lg` headline, `caption` hint, optional action. One per empty surface (systematizes audit E5).

### `VCardSkeleton`
- Shimmer placeholders matching card geometry. Replaces the lone `LoadingSpinner` in a `Card` (audit E5).

### `VToast` / `VBanner`
- Toast: bottom, above bottom-bar, auto-dismiss, `alert/*` left edge. Banner: offline/sync state, persistent.

### `VNavBar`
- Material 3 `NavigationBar`, 3–4 destinations, pill indicator `brand/500 @ 15%`.

### `VSearchField`
- App-bar pill, `surface/700`, leading `search` icon, instant results. Admin-critical.

### `VTextField`
- `surface/700` fill, `radius/md`, 52px, `body`, focus ring `brand/500 @ 50%` (matches existing `focus:ring-2 focus:ring-brand-500/50`). Label above, error text below in `alert/danger`.

---

## 6.10 Token export format (for handoff)

Tokens ship as a single `tokens.json` (Design Tokens Community Group format) → generates Flutter `ColorScheme`/`TextTheme` extension + a Tailwind theme for any web parity. See doc 11 for the pipeline.
