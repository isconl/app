import 'package:flutter/material.dart';

import 'theme_tokens.dart';

/// The app's colour, type and size names. The values come from theme_tokens.dart, which is generated
/// from limelight's tokens.json (BL26100903); change a value there, not here. The names stay the same
/// so no call site changes. Lesson callouts follow the web values (decision 9 Oct 2026).
class C {
  static const bg = TokenColors.bg;
  static const bgRaised = TokenColors.bgRaised;
  static const panel = TokenColors.panel;
  static const panelHover = TokenColors.panelHover;
  static const surface = TokenColors.surface;
  static const border = TokenColors.border;
  static const borderMid = TokenColors.borderMid;
  static const text = TokenColors.text;
  static const text2 = TokenColors.text2;
  static const text3 = TokenColors.text3;
  static const textInverse = TokenColors.textInverse;
  static const green = TokenColors.green;
  static const greenBright = TokenColors.greenBright;
  static const greenDim = TokenColors.greenDim;
  static const greenHover = TokenColors.greenHover;
  static const greenBg = TokenColors.greenBg;
  static const greenBg2 = TokenColors.greenBg2;
  static const greenGlow = TokenColors.greenGlow;
  static const amber = TokenColors.amber;
  static const amberBg = TokenColors.amberBg;
  static const red = TokenColors.red;
  static const redBg = TokenColors.redBg;
  static const cyan = TokenColors.cyan;
  static const cyanBg = TokenColors.cyanBg;
  static const blue = TokenColors.blue;
  static const violet = TokenColors.violet;
  static const violetBg = TokenColors.violetBg;
  static const callLearn = TokenColors.callLearn;
  static const callLearnBg = TokenColors.callLearnBg;
  static const callJargon = TokenColors.callJargon;
  static const callJargonBg = TokenColors.callJargonBg;
  static const callWatch = TokenColors.callWatch;
  static const callWatchBg = TokenColors.callWatchBg;
  static const callBook = TokenColors.callBook;
  static const callBookBg = TokenColors.callBookBg;
  static const callQuote = TokenColors.callQuote;
  static const callQuoteBg = TokenColors.callQuoteBg;
  static const callResearch = TokenColors.callResearch;
  static const callResearchBg = TokenColors.callResearchBg;
  static const callFact = TokenColors.callFact;
  static const callFactBg = TokenColors.callFactBg;
  static const callQuiz = TokenColors.callQuiz;
  static const callQuizBg = TokenColors.callQuizBg;

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

/// Type scale. UI font is Inter; identifiers, hashes and timestamps use JetBrains Mono.
class T {
  static const body = TokenType.body;
  static const body2 = TokenType.body2;
  static const small = TokenType.small;
  static const tiny = TokenType.tiny;
  static const label = TokenType.label;
  static const title = TokenType.title;
  static const headline = TokenType.headline;
  static const mono = TokenType.mono;
  static const monoSmall = TokenType.monoSmall;
  static const idBadge = TokenType.idBadge;

  /// The small monospace status line: the app-bar status chip and the checkpoint card share it.
  static final statusMono = monoSmall.copyWith(fontSize: 11, color: C.text3);

  static TextStyle w500(TextStyle s) => s.copyWith(fontWeight: FontWeight.w500);
  static TextStyle w600(TextStyle s) => s.copyWith(fontWeight: FontWeight.w600);
  static TextStyle c(TextStyle s, Color color) => s.copyWith(color: color);
}

/// Shape and spacing. rMd is 10 in the app (BG26091015) and 8 on the web; see tokens.json.
class Sz {
  static const rSm = TokenSize.rSm;
  static const rMd = TokenSize.rMd;
  static const rLg = TokenSize.rLg;
  static const rXl = TokenSize.rXl;
  static const pad = TokenSize.pad; // card padding
  static const gap = TokenSize.gap; // grid gap

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
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      shape: CircleBorder(),
      backgroundColor: C.green,
      foregroundColor: C.textInverse,
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
