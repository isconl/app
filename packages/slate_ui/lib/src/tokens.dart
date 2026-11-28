import 'package:flutter/material.dart';

/// Obsidian neutrals (canon 1.4.0 section 2.1 and 2.3) with the silver accent
/// that xkeel's operator engines use (section 2.4). Kept local until the vela
/// kit lands; swap the import then, the names are the kit's.
class SlateTokens {
  const SlateTokens({
    required this.ground,
    required this.surface,
    required this.surface2,
    required this.hairline,
    required this.hairlineStrong,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.onAccent,
    required this.ok,
    required this.warn,
    required this.danger,
  });

  final Color ground;
  final Color surface;
  final Color surface2;
  final Color hairline;
  final Color hairlineStrong;
  final Color text;
  final Color text2;
  final Color text3;
  final Color accent;
  final Color onAccent;
  final Color ok;
  final Color warn;
  final Color danger;

  static const dark = SlateTokens(
    ground: Color(0xFF0B0C0E),
    surface: Color(0xFF111316),
    surface2: Color(0xFF15181C),
    hairline: Color(0xFF23262B),
    hairlineStrong: Color(0xFF343940),
    text: Color(0xFFECEDEE),
    text2: Color(0xFF9096A0),
    text3: Color(0xFF6A7079),
    accent: Color(0xFFBBC5D1),
    onAccent: Color(0xFF0B0C0E),
    ok: Color(0xFF4CC38A),
    warn: Color(0xFFE0A93B),
    danger: Color(0xFFF0736B),
  );

  static const light = SlateTokens(
    ground: Color(0xFFF6F6F4),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF1F1EF),
    hairline: Color(0xFFE2E3E5),
    hairlineStrong: Color(0xFFC9CBCF),
    text: Color(0xFF0B0C0E),
    text2: Color(0xFF5D636B),
    text3: Color(0xFF7A808A),
    accent: Color(0xFF5B646F),
    onAccent: Color(0xFFFFFFFF),
    ok: Color(0xFF1F7A52),
    warn: Color(0xFF8A5F00),
    danger: Color(0xFFB3261E),
  );

  static SlateTokens of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  ThemeData toTheme() {
    final isDark = identical(this, dark);
    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: ground,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: accent,
        onPrimary: onAccent,
        secondary: accent,
        onSecondary: onAccent,
        error: danger,
        onError: onAccent,
        surface: surface,
        onSurface: text,
      ),
      dividerColor: hairline,
      useMaterial3: true,
    );
  }
}
