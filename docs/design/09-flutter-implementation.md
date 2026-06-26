# 09 — Flutter Implementation Considerations

The current `mobile-app/` is a stub (`main.dart` + `pubspec.yaml` are 1-line placeholders) — **greenfield**. This is the recommended build.

## 9.1 Stack

| Concern | Choice | Why |
|---|---|---|
| Framework | Flutter 3.2x, Material 3 (`useMaterial3: true`) | Native 60fps, one codebase, M3 motion built in |
| State | **Riverpod 2** (codegen) | Testable, scales, clean async; mirrors the old service-layer separation |
| Navigation | **go_router** | Declarative, deep-link & role-guard friendly (replaces `ProtectedRoute`/`AuthGate`) |
| Networking | **dio** + interceptors | JWT attach/refresh, retry, timeout (replaces supabase-js) |
| Realtime | **socket_io_client** | Matches the new Socket.IO backend |
| Local store | **flutter_secure_storage** (tokens) + **drift** (offline cache/queue) | Secure JWT + offline-first transaction queue |
| Models | **freezed** + **json_serializable** | Immutable DTOs mirroring Spring Boot responses |
| Media | **image_picker** + **camera** + custom MinIO multipart uploader | Plate OCR, parking photos |
| Maps | platform map deep-links + optional `google_maps_flutter` | Preserve the `maps.google.com/?q=` deep-link from `DriverPanel.jsx:142` |
| Plate OCR | **google_mlkit_text_recognition** | On-device, offline plate scan |

## 9.2 Theme wiring (tokens → ThemeData)

```dart
// color_tokens.dart  — generated from tokens.json (doc 11)
class VColors {
  static const brand500   = Color(0xFFA60445); // PRESERVED
  static const brand400   = Color(0xFFD42862);
  static const brand300   = Color(0xFFE84A7A);
  static const surface950 = Color(0xFF030303);
  static const surface900 = Color(0xFF050505);
  static const surface800 = Color(0xFF0F0F0F);
  static const surface700 = Color(0xFF1A1A1A);
  static const contentStrong = Color(0xFFFFFFFF);
  static const contentMuted  = Color(0xFF9A9A9A);
  // status ramp
  static const statusActive = Color(0xFFC77DAE); // requested
  static const statusReady  = Color(0xFF5BB98C); // arrived
  static const alertWarn    = Color(0xFFE0A93A);
  static const alertDanger  = Color(0xFFE0564E);
}

final valetDarkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: VColors.surface900,
  colorScheme: const ColorScheme.dark(
    primary: VColors.brand500,
    onPrimary: Color(0xFF0A0A0A),
    surface: VColors.surface800,
    error: VColors.alertDanger,
  ),
  textTheme: vTextTheme,            // Inter + JetBrains Mono scale (doc 6.2)
  extensions: const [VStatusColors(), VElevation()], // status ramp + glow tokens
);
```

## 9.3 Widget mapping (DS component → Flutter)

| DS component | Flutter implementation |
|---|---|
| `VPrimaryButton` | `FilledButton` + custom style + `AnimatedScale` press |
| `VSecondaryButton`/`VGhostButton` | `OutlinedButton` / `TextButton` |
| `VTransactionCard` | `Card`(`elev/1`) → `Dismissible`(swipe action) wrapping `InkWell`(tap→sheet) |
| `VStatusRail` | custom `CustomPaint` (8 nodes) with `AnimatedFractionalTranslation` fill |
| `VMissionCard` | full-bleed `Container` + custom `SlideToConfirm` (GestureDetector + spring `AnimationController`) |
| swipe-to-advance | `Dismissible` (operator) / bespoke `SlideAction` (driver, with haptic at threshold) |
| `VBottomSheet` | `showModalBottomSheet`(isScrollControlled, `DraggableScrollableSheet`) |
| `VKeySlotChip`/`VPaymentPill` | `Chip` variants |
| `VEmptyState` | stateless centered column |
| `VCardSkeleton` | `shimmer` over `surface/700` blocks |
| `VNavBar` | `NavigationBar` (compact) / `NavigationRail` (expanded, doc 8.5) |
| `VToast` | `ScaffoldMessenger` snackbar, custom shape, above nav bar |
| `VSearchField` | `SearchAnchor`/`SearchBar` (M3) |
| Check-In stepper | `PageView` + top progress rail (3 nodes) |

## 9.4 Navigation & role guard (replaces ProtectedRoute/AuthGate)

```dart
final router = GoRouter(
  redirect: (ctx, state) {
    final auth = ref.read(authProvider);
    if (!auth.isAuthed) return '/login';
    // mirror App.jsx role routing exactly
    return switch (auth.role) {
      'admin'   => state.matchedLocation.startsWith('/admin')   ? null : '/admin',
      'company' => state.matchedLocation.startsWith('/company') ? null : '/company',
      'driver'  => state.matchedLocation.startsWith('/driver')  ? null : '/driver',
      _         => state.matchedLocation.startsWith('/floor')   ? null : '/floor', // valet
    };
  },
  routes: [...],
);
```
Role→home table is **identical** to the web (`App.jsx:70`): admin→Console, company→Org, driver→Run, valet→Floor.

## 9.5 Animation timings (concrete, from doc 6.7)

| Interaction | Controller | Duration | Curve |
|---|---|---|---|
| State advance on rail | `AnimationController` | 240ms | `Curves.easeOutBack`-like spring |
| Tab switch | `go_router` + `FadeThroughTransition` | 200ms | `Easing.emphasized` |
| Sheet open | `showModalBottomSheet` | 280ms | `Easing.emphasizedDecelerate` |
| New card enter | `AnimatedList.insertItem` | 280ms | decelerate |
| Delivered exit | `AnimatedList.removeItem` | 320ms | accelerate, desaturate |
| Requested pulse | repeating `AnimationController` | 1600ms | sine |
| Swipe threshold | — | — | `HapticFeedback.selectionClick` |
| Delivered celebration | Lottie/`confetti` | 600ms | + success haptic |
| FAB→Check-In | `OpenContainer` (animations pkg) | 300ms | emphasized |

Wrap the app in a reduced-motion check: `MediaQuery.of(context).disableAnimations` → swap all transitions for `FadeTransition` ≤120ms, disable pulse/celebration.

## 9.6 Performance budget (60fps non-negotiable)

- **One ticker for all live timers**, not one per card (fixes audit A8): a single `Stream.periodic(1s)` provider; cards read `elapsed` via `Selector`/`Consumer` scoped to their id. With 30 cards = 1 timer, not 30.
- **Virtualized lists** (`ListView.builder`/`SliverList`) everywhere — never map a full list into a Column (the old `cards.map(renderTile)` materialized everything).
- **const constructors** + `RepaintBoundary` around the status rail and mission card.
- **Image:** `cached_network_image` for MinIO photos; thumbnails requested at display size (doc 10).
- Realtime mutates a single Riverpod `StateNotifier` **in place** (delta) — no full refetch (fixes audit A7).

## 9.7 Offline-first

- `drift` table mirrors `valet_transactions`; reads come from local, writes go to an **outbox** queue with optimistic state (systematizes the `OperatorDashboard.jsx:344` rollback instinct).
- On reconnect: replay outbox; server is source of truth on conflict; `VBanner` shows sync state.

## 9.8 Platform polish

- iOS: Cupertino-style edge-swipe back, `HapticFeedback`, dynamic type, ProMotion-aware.
- Android: predictive back, Material You optional accent override **disabled** (we keep brand magenta), edge-to-edge.
- Both: respect notch/hinge/home-indicator via `SafeArea`.
