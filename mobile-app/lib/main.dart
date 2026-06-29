import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router.dart';
import 'state/providers.dart';
import 'theme/v_colors.dart';
import 'theme/v_theme.dart';
import 'widgets/help_chatbot.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: ValetDriverApp()));
}

class ValetDriverApp extends ConsumerWidget {
  const ValetDriverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Drives the realtime socket connect/disconnect off auth state.
    ref.watch(realtimeConnectorProvider);

    // Resolve the active brightness from the persisted theme mode + platform.
    final mode = ref.watch(themeControllerProvider);
    // Show the help assistant only once the user is authenticated.
    final authed = ref.watch(authControllerProvider).isAuthed;
    final platform = MediaQuery.platformBrightnessOf(context);
    final brightness = ref
        .read(themeControllerProvider.notifier)
        .resolve(platform);

    // CRITICAL: flip the VColors getters BEFORE building the themes/tree so the
    // ~400 static `VColors.*` references resolve to the active variant. Watching
    // `themeControllerProvider` above guarantees this rebuild on every toggle.
    VColors.setBrightness(brightness);

    // Edge-to-edge system chrome, brightness-aware: dark icons on light paper,
    // light icons on dark charcoal; nav bar tinted to the active scaffold.
    final isDark = brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light, // iOS
        systemNavigationBarColor: VColors.surface900,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return MaterialApp.router(
      title: 'Vālet',
      debugShowCheckedModeBanner: false,
      theme: buildValetLightTheme(),
      darkTheme: buildValetDarkTheme(),
      themeMode: mode,
      routerConfig: router,
      // The ~400 `VColors.*` reads are plain statics, and most screens are wired
      // up with `const` widgets — so a theme toggle alone won't repaint those
      // const subtrees (Flutter reuses the cached const elements). Re-keying the
      // route content by brightness forces the whole subtree below the router to
      // rebuild from scratch on toggle, re-reading the active palette. The router
      // (and thus the current location) lives ABOVE this builder, so navigation
      // is preserved; only ephemeral view state (e.g. the selected tab) resets.
      builder: (context, child) => KeyedSubtree(
        key: ValueKey(brightness),
        child: Stack(
          children: [
            child ?? const SizedBox.shrink(),
            // The assistant lives above the router, so it needs its OWN Overlay
            // ancestor — without it the chat TextField throws "No Overlay widget
            // found" on focus. A lightweight Overlay here provides one; empty
            // areas don't absorb taps, so the app underneath stays interactive.
            if (authed)
              Positioned.fill(
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(builder: (_) => const HelpChatbot()),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
