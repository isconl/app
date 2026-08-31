import 'package:flutter/material.dart';

/// Design tokens ported 1:1 from dashboard/style.css (:root).
/// The web dashboard is the source of truth for this palette.
class C {
  // Surfaces
  static const bg = Color(0xFF0D1117);
  static const bgRaised = Color(0xFF0F1318);
  static const panel = Color(0xFF161B22);
  static const panelHover = Color(0xFF1B271E); // green-tinted hover surface
  static const surface = Color(0xFF21262D);
  static const border = Color(0xFF30363D);
  static const borderMid = Color(0xFF3D4450);

  // Text
  static const text = Color(0xFFE6EDF3);
  static const text2 = Color(0xFFB1BAC4);
  static const text3 = Color(0xFF7D8590);
  static const textInverse = Color(0xFF0D1117);

  // Accent - green is the brand
  static const green = Color(0xFF3FB950);
  static const greenBright = Color(0xFF56D364);
  static const greenDim = Color(0xFF238636);
  static const greenHover = Color(0xFF2EA043);
  static const greenBg = Color(0x1A3FB950); // rgba(63,185,80,.10)
  static const greenBg2 = Color(0x0F3FB950); // rgba(63,185,80,.06)
  static const greenGlow = Color(0x593FB950); // rgba(63,185,80,.35)

  // Semantic
  static const amber = Color(0xFFD29922);
  static const amberBg = Color(0x1FD29922);
  static const red = Color(0xFFF85149);
  static const redBg = Color(0x1FF85149);
  static const cyan = Color(0xFF58A6FF);
  static const cyanBg = Color(0x1A58A6FF);
  static const violet = Color(0xFFBC8CFF);
  static const violetBg = Color(0x1ABC8CFF);

  // The five lesson callouts, one colour each. Ported 1:1 from
  // dashboard/style.css (--call-*), because a module has to look the same on
  // the phone as it does in the console - his instruction, 7 Aug 2026.
  static const callLearn = green;
  static const callLearnBg = Color(0x1A3FB950);
  static const callJargon = cyan;
  static const callJargonBg = Color(0x1A58A6FF);
  static const callWatch = amber;
  static const callWatchBg = Color(0x1AD29922);
  static const callBook = violet;
  static const callBookBg = Color(0x1ABC8CFF);
  static const callQuote = Color(0xFFF0883E);
  static const callQuoteBg = Color(0x1AF0883E);
  static const callResearch = Color(0xFF6EA6D9);
  static const callResearchBg = Color(0x1A6EA6D9);

  static Color forPriority(String p) => switch (p.toLowerCase()) {
        'high' => red,
        'low' => text3,
        _ => amber,
      };

  static Color forSeverity(String s) => switch (s.toLowerCase()) {
        'high' || 'critical' => red,
        'medium' || 'warn' => amber,
        _ => cyan,
      };
}

/// Type scale. UI font is Inter; identifiers/hashes/timestamps use JetBrains Mono.
class T {
  static const _ui = 'Inter';
  static const _mono = 'JetBrains Mono';

  static const body = TextStyle(
      fontFamily: _ui, fontSize: 14, height: 1.5, color: C.text);
  static const body2 = TextStyle(
      fontFamily: _ui, fontSize: 13, height: 1.45, color: C.text2);
  static const small = TextStyle(
      fontFamily: _ui, fontSize: 12, height: 1.4, color: C.text2);
  static const tiny = TextStyle(
      fontFamily: _ui, fontSize: 11, height: 1.3, color: C.text3);
  static const label = TextStyle(
      fontFamily: _ui,
      fontSize: 10.5,
      height: 1.2,
      color: C.text3,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2);
  static const title = TextStyle(
      fontFamily: _ui,
      fontSize: 16,
      height: 1.3,
      color: C.text,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2);
  static const headline = TextStyle(
      fontFamily: _ui,
      fontSize: 19,
      height: 1.25,
      color: C.text,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4);
  static const mono = TextStyle(
      fontFamily: _mono, fontSize: 11.5, height: 1.45, color: C.text2);
  static const monoSmall = TextStyle(
      fontFamily: _mono, fontSize: 10, height: 1.35, color: C.text3);

  static TextStyle w500(TextStyle s) => s.copyWith(fontWeight: FontWeight.w500);
  static TextStyle w600(TextStyle s) => s.copyWith(fontWeight: FontWeight.w600);
  static TextStyle c(TextStyle s, Color color) => s.copyWith(color: color);
}

/// Shape and spacing.
class Sz {
  static const rSm = 5.0;
  static const rMd = 8.0;
  static const rLg = 12.0;
  static const rXl = 16.0;
  static const pad = 14.0; // card padding
  static const gap = 10.0; // grid gap

  /// Below this width, the web build gets the phone-shaped [Shell] instead
  /// of [DesktopShell] - see ui/adaptive_shell.dart.
  static const desktopMinWidth = 900.0;
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: C.green,
      onPrimary: C.textInverse,
      secondary: C.cyan,
      surface: C.panel,
      onSurface: C.text,
      error: C.red,
      outline: C.border,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'Inter',
      bodyColor: C.text,
      displayColor: C.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: C.panel,
      foregroundColor: C.text,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(color: C.border, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.surface,
      contentTextStyle: T.body2.copyWith(color: C.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sz.rMd),
        side: const BorderSide(color: C.border),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.panel,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: C.panel,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sz.rLg),
        side: const BorderSide(color: C.border),
      ),
      titleTextStyle: T.title,
      contentTextStyle: T.body2,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.bg,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      hintStyle: T.body2.copyWith(color: C.text3),
      labelStyle: T.small.copyWith(color: C.text3),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: C.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: C.green),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: C.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: C.red),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.greenDim,
        foregroundColor: Colors.white,
        textStyle: T.w600(T.body2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0x1AF0F6FC)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text2,
        textStyle: T.w500(T.body2),
        side: const BorderSide(color: C.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: C.green,
        textStyle: T.w500(T.body2),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? C.greenBright : C.text3),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? C.greenDim : C.surface),
      trackOutlineColor: const WidgetStatePropertyAll(C.border),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: C.green,
      inactiveTrackColor: C.surface,
      thumbColor: C.greenBright,
      overlayColor: C.greenBg,
      valueIndicatorColor: C.surface,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: C.green,
      linearTrackColor: C.surface,
      circularTrackColor: C.surface,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: C.greenBright,
      unselectedLabelColor: C.text3,
      indicatorColor: C.green,
      dividerColor: C.border,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: C.surface,
      side: const BorderSide(color: C.border),
      labelStyle: T.small,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: C.text3,
      textColor: C.text,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: C.surface,
      surfaceTintColor: Colors.transparent,
      textStyle: T.body2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sz.rMd),
        side: const BorderSide(color: C.border),
      ),
    ),
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.compact,
  );
}
