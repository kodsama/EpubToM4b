/// The app's visual identity: a warm literary dark theme.
///
/// Design language — "lamplit library": a deep espresso surface, a glowing
/// amber accent (audio + aged paper), a characterful serif (Fraunces) for
/// display text paired with a clean grotesque (Hanken Grotesk) for controls.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized design tokens so every widget pulls from one palette. The colors
/// resolve against [brightness] so the same widgets render in the dark
/// ("lamplit library") or a light ("sunlit paper") variant. Set [brightness]
/// before building the theme/widget tree (the root does this on theme change).
abstract class AppTokens {
  /// Current palette brightness; the getters below switch on it.
  static Brightness brightness = Brightness.dark;
  static bool get _dark => brightness == Brightness.dark;

  /// Deepest background (page).
  static Color get ink =>
      _dark ? const Color(0xFF17130F) : const Color(0xFFF6EFE3);

  /// Raised surface (cards).
  static Color get surface =>
      _dark ? const Color(0xFF211B15) : const Color(0xFFFFFDF8);

  /// Higher surface (inputs, hover).
  static Color get surfaceHigh =>
      _dark ? const Color(0xFF2C241C) : const Color(0xFFEFE6D5);

  /// Hairline borders.
  static Color get line =>
      _dark ? const Color(0xFF3A3026) : const Color(0xFFDCD0BC);

  /// Primary glowing amber accent.
  static Color get amber =>
      _dark ? const Color(0xFFE0A458) : const Color(0xFFB1722A);

  /// Brighter amber for highlights/gradient tops.
  static Color get amberBright =>
      _dark ? const Color(0xFFF2C078) : const Color(0xFFC98F3F);

  /// Primary text.
  static Color get cream =>
      _dark ? const Color(0xFFF3E9DC) : const Color(0xFF2A211A);

  /// Muted secondary text.
  static Color get muted =>
      _dark ? const Color(0xFF9C8E7C) : const Color(0xFF796D5C);

  /// Success / done.
  static Color get sage =>
      _dark ? const Color(0xFF8FB996) : const Color(0xFF4E7A57);

  /// Error.
  static Color get rust =>
      _dark ? const Color(0xFFD08770) : const Color(0xFFB35539);

  /// Standard corner radius.
  static const double radius = 16;

  /// Standard outer padding.
  static const double pad = 20;
}

/// Builds the [ThemeData] for the app in the given [brightness].
ThemeData buildAppTheme([Brightness brightness = Brightness.dark]) {
  AppTokens.brightness = brightness;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final scheme = ColorScheme.fromSeed(
    seedColor: AppTokens.amber,
    brightness: brightness,
  ).copyWith(
    primary: AppTokens.amber,
    onPrimary: AppTokens.ink,
    secondary: AppTokens.amberBright,
    surface: AppTokens.surface,
    onSurface: AppTokens.cream,
    error: AppTokens.rust,
  );

  final display = GoogleFonts.fraunces(
    color: AppTokens.cream,
    fontWeight: FontWeight.w600,
  );
  final body = GoogleFonts.hankenGrotesk(color: AppTokens.cream);

  return base.copyWith(
    scaffoldBackgroundColor: AppTokens.ink,
    colorScheme: scheme,
    textTheme: base.textTheme
        .copyWith(
          displaySmall: display.copyWith(fontSize: 34, letterSpacing: -0.5),
          headlineSmall: display.copyWith(fontSize: 22),
          titleLarge: display.copyWith(fontSize: 18),
          titleMedium: body.copyWith(fontWeight: FontWeight.w600),
          bodyMedium: body.copyWith(color: AppTokens.cream, height: 1.45),
          bodySmall: body.copyWith(color: AppTokens.muted, height: 1.4),
          labelLarge: body.copyWith(fontWeight: FontWeight.w600),
        )
        .apply(bodyColor: AppTokens.cream, displayColor: AppTokens.cream),
    cardTheme: CardThemeData(
      color: AppTokens.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        side: BorderSide(color: AppTokens.line),
      ),
    ),
    dividerColor: AppTokens.line,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppTokens.amber,
        foregroundColor: AppTokens.ink,
        textStyle: body.copyWith(fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppTokens.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTokens.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTokens.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTokens.amber, width: 1.5),
      ),
    ),
  );
}
