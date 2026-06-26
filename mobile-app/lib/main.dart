import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router.dart';
import 'state/providers.dart';
import 'theme/v_colors.dart';
import 'theme/v_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge, dark-luxe system chrome (doc §9.8).
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: VColors.surface950,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: ValetDriverApp()));
}

class ValetDriverApp extends ConsumerWidget {
  const ValetDriverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Drives the realtime socket connect/disconnect off auth state.
    ref.watch(realtimeConnectorProvider);
    return MaterialApp.router(
      title: 'Vālet Driver',
      debugShowCheckedModeBanner: false,
      theme: buildValetDarkTheme(),
      // Dark-luxe is primary; dark mode is enforced for this operational app.
      darkTheme: buildValetDarkTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
