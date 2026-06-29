import 'package:flutter/material.dart';

/// The LogBook360 brand lockup, used as a persistent mark in every panel's
/// app bar. ONE widget so the asset and sizing are tuned in a single place.
///
/// The asset is blue/red on a TRANSPARENT background — it sits bare on both the
/// light cream paper and the dark charcoal app bar (no plate/chip behind it).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 24});

  /// Rendered logo height in logical px. App bars use ~22–24.
  final double height;

  static const _asset = 'assets/images/logbook360_logo.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _asset,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      // Decode at ~2x the layout height for crisp downscaling of the 1800×499
      // source on high-DPI screens.
      cacheHeight:
          (height * 2 * MediaQuery.devicePixelRatioOf(context)).round(),
      semanticLabel: 'LogBook360',
    );
  }
}
