import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette shared with web/home.html, kept as a single source of truth.
class RoamColors {
  RoamColors._();

  static const navy = Color(0xff0b1222);
  static const navyTint = Color(0xff131f3a);
  static const emerald = Color(0xff2e8b57);
  static const mint = Color(0xff10b981);
  static const gold = Color(0xffefa331);
  static const coral = Color(0xffff8c69);
  static const offwhite = Color(0xfff9fbfc);
  static const text = Color(0xff1c2635);
}

ThemeData buildRoamTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: RoamColors.emerald,
    scaffoldBackgroundColor: RoamColors.offwhite,
  );
  final headlineFont = GoogleFonts.breeSerifTextTheme(base.textTheme);
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineLarge: headlineFont.headlineLarge?.copyWith(
        color: RoamColors.text,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: headlineFont.headlineMedium?.copyWith(
        color: RoamColors.text,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: headlineFont.headlineSmall?.copyWith(
        color: RoamColors.text,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: headlineFont.titleLarge?.copyWith(
        color: RoamColors.text,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: RoamColors.navy,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );
}
