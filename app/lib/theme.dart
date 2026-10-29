import 'package:flutter/material.dart';

const kUp = Color(0xFF16A34A);
const kDown = Color(0xFFDC2626);
const kBrand = Color(0xFF4F8CFF);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrand,
    brightness: b,
    surface: dark ? const Color(0xFF0B1220) : const Color(0xFFF7F8FB),
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
        side: BorderSide(color: dark ? const Color(0xFF243049) : const Color(0xFFE3E7EF)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
  );
}
