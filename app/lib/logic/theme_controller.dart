/// Holds and persists the app's light/dark choice.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// A [ValueNotifier] of the chosen [ThemeMode], backed by a tiny file so the
/// preference survives restarts. Defaults to dark.
class ThemeController extends ValueNotifier<ThemeMode> {
  final String _file;

  ThemeController(this._file, [super.initial = ThemeMode.dark]);

  /// Loads the saved preference from `theme.txt` in [dir] (default dark).
  static Future<ThemeController> load(String dir) async {
    final c = ThemeController(p.join(dir, 'theme.txt'));
    try {
      final s = (await File(c._file).readAsString()).trim();
      c.value = s == 'light' ? ThemeMode.light : ThemeMode.dark;
    } on Object {
      // No saved preference yet — keep the default.
    }
    return c;
  }

  /// Whether the dark palette is active.
  bool get isDark => value == ThemeMode.dark;

  /// Flips between light and dark and persists the choice.
  Future<void> toggle() async {
    value = isDark ? ThemeMode.light : ThemeMode.dark;
    try {
      await File(_file).writeAsString(isDark ? 'dark' : 'light');
    } on Object {
      // Persisting is best-effort.
    }
  }
}
