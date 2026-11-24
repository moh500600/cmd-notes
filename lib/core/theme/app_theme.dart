import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Calm, eye-friendly palette: indigo by default (the user can pick another accent),
/// warm paper-like surfaces in light mode and a soft ink background in dark mode.
class AppColors {
  static const primary = Color(0xFF4F46E5);
  static const accent = Color(0xFF0EA5E9);
  static const success = Color(0xFF16A34A);
  static const danger = Color(0xFFE11D48);
  static const warning = Color(0xFFF59E0B);
  static const info = Color(0xFF0284C7);
  static const purple = Color(0xFF7C3AED);
  static const pink = Color(0xFFDB2777);
  static const teal = Color(0xFF0F766E);
  static const amber = Color(0xFFD97706);
  static const ink = Color(0xFF0F1117);
  static const inkCard = Color(0xFF171A23);

  /// Accents offered in Settings.
  static const accents = [0xFF4F46E5, 0xFF0F766E, 0xFF0EA5E9, 0xFF7C3AED, 0xFFDB2777, 0xFFE11D48, 0xFFD97706, 0xFF16A34A, 0xFF334155];

  /// Colours for notebooks / tags / notes.
  static const swatches = ['#4F46E5', '#0EA5E9', '#0F766E', '#16A34A', '#D97706', '#E11D48', '#DB2777', '#7C3AED', '#64748B', '#A16207'];

  static Color parse(String? hex, [Color fallback = primary]) {
    if (hex == null || hex.length < 7 || !hex.startsWith('#')) return fallback;
    final v = int.tryParse(hex.substring(1, 7), radix: 16);
    return v == null ? fallback : Color(0xFF000000 | v);
  }

  static String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static Color type(String t) => switch (t) {
    'study' => const Color(0xFF0EA5E9),
    'work' => const Color(0xFF334155),
    'meeting' => const Color(0xFF7C3AED),
    'personal' => const Color(0xFFDB2777),
    'journal' => const Color(0xFFD97706),
    'idea' => const Color(0xFFEAB308),
    'shopping' => const Color(0xFF16A34A),
    'todo' => const Color(0xFF0F766E),
    'code' => const Color(0xFF475569),
    'voice' => const Color(0xFFE11D48),
    _ => primary,
  };
}

class AppTheme {
  static ThemeData light({int accent = 0xFF4F46E5, String? font = 'Tajawal'}) => _base(Brightness.light, Color(accent), font);
  static ThemeData dark({int accent = 0xFF4F46E5, String? font = 'Tajawal'}) => _base(Brightness.dark, Color(accent), font);

  static ThemeData _base(Brightness b, Color seed, String? font) {
    final dark = b == Brightness.dark;
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    final scheme = base.copyWith(
      surface: dark ? AppColors.ink : const Color(0xFFF7F6F2),
      surfaceContainerLowest: dark ? AppColors.inkCard : Colors.white,
      surfaceContainerLow: dark ? const Color(0xFF1B1F2A) : Colors.white,
      surfaceContainer: dark ? const Color(0xFF20242F) : const Color(0xFFEDEBE5),
    );
    TextStyle f(TextStyle s) => font == null ? s : s.copyWith(fontFamily: font);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: font,
      scaffoldBackgroundColor: scheme.surface,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: f(TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onSurface)),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: dark ? 0.25 : 0.5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: f(const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primary.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.all(f(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primary.withValues(alpha: 0.15),
        selectedLabelTextStyle: f(TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
        unselectedLabelTextStyle: f(TextStyle(color: scheme.onSurfaceVariant)),
      ),
      chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 14)),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.4), space: 1),
    );
  }
}
