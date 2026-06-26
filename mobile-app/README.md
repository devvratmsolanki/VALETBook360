# Vālet — Driver app (Flutter)

The first Flutter slice of the **Vālet Design System**: the **driver mission flow**.
Dark-luxe, magenta-brand, thumb-first. Built faithfully to `docs/design/`
(`06-design-system.md`, `07-screen-specs.md`, `09-flutter-implementation.md`,
`tokens.json`).

## What's in this slice

- **Login** (`/login`) — email + password, idle / loading / error states.
  `POST {AUTH}/auth/login`; stores `accessToken` + `refreshToken` (secure
  storage) and the user; routes to the mission stack. 401 → inline error banner.
- **Driver Mission Stack** (`/driver`) — full-bleed swipe-to-advance missions.
  `GET {CORE}/api/driver/assignments` (Bearer). Slide-to-advance drives:
  `driver_assigned → en-route → arrived → delivered` via the three POST
  endpoints, with the live status rail, haptics, optimistic updates + rollback,
  and a delivered success burst.
- **Universal states** — loading skeleton, empty, error + retry, success
  micro-interaction. Reduced-motion honored throughout.

## Run it

```sh
flutter pub get

# Android emulator (defaults target 10.0.2.2 → host loopback)
flutter run

# iOS simulator / desktop / web → host loopback is 127.0.0.1
flutter run \
  --dart-define=AUTH_BASE_URL=http://127.0.0.1:8081 \
  --dart-define=CORE_BASE_URL=http://127.0.0.1:8082

# Remote / staging
flutter run \
  --dart-define=AUTH_BASE_URL=https://auth.staging.valet.app \
  --dart-define=CORE_BASE_URL=https://core.staging.valet.app
```

Base URLs live in `lib/config/api_config.dart` (const, `--dart-define`
overridable). Cleartext HTTP to `10.0.2.2` / `127.0.0.1` / `localhost` is
permitted for dev via the Android network-security-config and iOS ATS
exception — tighten for production.

## Demo login

`driver@valet.demo` / `Driver123` (pre-filled on the login screen).

## Architecture

Riverpod (state) + go_router (routing + auth redirect) + dio (Bearer inject,
401 → bounce to login, RFC7807 / `userMessage` parsing). Tokens in
`flutter_secure_storage`. Theme is generated from `tokens.json` → Material 3
`ThemeData` + a `VStatusColors` theme extension.

```
lib/
  config/api_config.dart        base URLs (dart-define overridable)
  theme/                        v_colors · v_tokens · v_theme · motion
  models/                       auth_user · assignment · lifecycle_status
  api/                          api_client · api_exception · token_store
  state/                        providers · auth_controller · missions_controller · clock
  widgets/                      v_primary_button · v_status_rail · slide_to_advance ·
                                mission_card · v_chips · v_states · success_burst
  screens/                      login_screen · mission_stack_screen
  router.dart · main.dart
test/contract_mapping_test.dart JSON↔contract mapping
```
