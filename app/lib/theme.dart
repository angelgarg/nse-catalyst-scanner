import 'package:flutter/material.dart';

// Brand tokens (design review 2026-10-29). Up/down/spike have light and dark
// variants so every text use meets WCAG AA contrast.
const kBrand = Color(0xFF1D4ED8);
const kBrandDark = Color(0xFF4F8CFF);
const kSpike = Color(0xFFF5B700);
const kOnSpike = Color(0xFF0F1419);

bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color upColor(BuildContext c) =>
    _dark(c) ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
Color downColor(BuildContext c) =>
    _dark(c) ? const Color(0xFFF87171) : const Color(0xFFB91C1C);
Color spikeText(BuildContext c) => _dark(c) ? kSpike : const Color(0xFFB45309);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrand,
    brightness: b,
    primary: dark ? kBrandDark : kBrand,
    onPrimary: dark ? const Color(0xFF0B1220) : Colors.white,
    surface: dark ? const Color(0xFF0B1220) : const Color(0xFFF7F8FB),
    onSurface: dark ? const Color(0xFFE7ECF6) : const Color(0xFF0F172A),
    onSurfaceVariant: dark ? const Color(0xFF93A1BD) : const Color(0xFF5B6476),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardTheme(
      elevation: 0,
      color: dark ? const Color(0xFF121A2C) : Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: dark ? const Color(0xFF243049) : const Color(0xFFE3E7EF)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
  );
}
