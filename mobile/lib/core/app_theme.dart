import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Design tokens — every colour / spacing value in the app comes from here.
class AppColors {
  const AppColors._();

  static const Color primary = Color(0xFF1565C0);
  static const Color primaryDark = Color(0xFF64B5F6);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFEF6C00);
  static const Color danger = Color(0xFFC62828);
  static const Color remnant = Color(0xFF6A1B9A);

  static const Color background = Color(0xFFF6F7F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE3E6EA);
  static const Color text = Color(0xFF1A1A1A);
  /// 说明性文字。原 #5F6368 在白底上只有 5.9:1，12.5px 的小字还是发虚，
  /// 加深到 #4A4E54（约 8.6:1），工地上逆光看也清楚。
  static const Color textSecondary = Color(0xFF4A4E54);
  /// 输入框的占位示例（"例如 阳台 / 储物间"）。必须**明显浅于**真实输入，
  /// 否则用户分不清"这是示例"还是"我已经输了"——之前它和正文一样深。
  static const Color textHint = Color(0xFFA3A9B0);
  static const Color disabled = Color(0xFF9E9E9E);

  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color dividerDark = Color(0xFF2C2C2C);
  static const Color textDark = Color(0xFFEDEDED);
  static const Color textSecondaryDark = Color(0xFFB0B6BC);

  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  static Color card(BuildContext context) => isDark(context) ? surfaceDark : surface;
  static Color page(BuildContext context) => isDark(context) ? backgroundDark : background;
  static Color line(BuildContext context) => isDark(context) ? dividerDark : divider;
  static Color label(BuildContext context) => isDark(context) ? textDark : text;
  static Color sub(BuildContext context) => isDark(context) ? textSecondaryDark : textSecondary;
  static Color accent(BuildContext context) => isDark(context) ? primaryDark : primary;
}

class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppRadius {
  const AppRadius._();

  static const double control = 12;
  static const double card = 16;
  static const double sheet = 24;
}

class AppSizes {
  const AppSizes._();

  /// Minimum touch target (gloves, one hand).
  static const double minTouch = 48;
  static const double primaryButton = 56;
  static const double input = 56;
  static const double icon = 24;
}

TextStyle _digits(TextStyle base) =>
    base.copyWith(fontFeatures: const <ui.FontFeature>[ui.FontFeature.tabularFigures()]);

ThemeData buildAppTheme(Brightness brightness) {
  final bool dark = brightness == Brightness.dark;
  final Color primary = dark ? AppColors.primaryDark : AppColors.primary;
  final Color onPrimary = dark ? Colors.black : Colors.white;

  final ColorScheme scheme = ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
    primary: primary,
    onPrimary: onPrimary,
    surface: dark ? AppColors.surfaceDark : AppColors.surface,
    onSurface: dark ? AppColors.textDark : AppColors.text,
    error: AppColors.danger,
    outline: dark ? AppColors.dividerDark : AppColors.divider,
  );

  final TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.4,
    color: dark ? AppColors.textDark : AppColors.text,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? AppColors.backgroundDark : AppColors.background,
    dividerColor: dark ? AppColors.dividerDark : AppColors.divider,
    splashFactory: InkSparkle.splashFactory,
    textTheme: TextTheme(
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: body.color, height: 1.3),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: body.color),
      bodyLarge: body,
      bodyMedium: body.copyWith(fontSize: 15),
      bodySmall: body.copyWith(fontSize: 13, color: dark ? AppColors.textSecondaryDark : AppColors.textSecondary),
      labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: body.color),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? AppColors.surfaceDark : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: TextStyle(color: dark ? AppColors.textSecondaryDark : AppColors.textSecondary, fontSize: 14),
      // 占位示例单独一档：明显浅于真实输入，一眼能分出"还没填"
      hintStyle: TextStyle(color: dark ? const Color(0xFF6E767E) : AppColors.textHint, fontSize: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: dark ? AppColors.dividerDark : AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: dark ? AppColors.dividerDark : AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSizes.primaryButton),
        backgroundColor: primary,
        foregroundColor: onPrimary,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSizes.minTouch),
        side: BorderSide(color: primary),
        foregroundColor: primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary, minimumSize: const Size(64, AppSizes.minTouch)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF303030) : const Color(0xFF323232),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide(color: dark ? AppColors.dividerDark : AppColors.divider),
      backgroundColor: dark ? AppColors.surfaceDark : Colors.white,
      labelStyle: TextStyle(fontSize: 14, color: dark ? AppColors.textDark : AppColors.text),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size(64, AppSizes.minTouch)),
        textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: dark ? AppColors.surfaceDark : Colors.white,
      selectedItemColor: primary,
      unselectedItemColor: dark ? AppColors.textSecondaryDark : AppColors.textSecondary,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 12),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? AppColors.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      showDragHandle: true,
    ),
  );
}

/// Shared AppBar so we do not depend on version specific theme classes.
AppBar buildAppBar(BuildContext context, String title, {List<Widget>? actions, Widget? leading}) {
  final Color fg = AppColors.label(context);
  return AppBar(
    title: Text(title),
    actions: actions,
    leading: leading,
    backgroundColor: AppColors.page(context),
    foregroundColor: fg,
    elevation: 0,
    scrolledUnderElevation: 1,
    centerTitle: false,
    titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: fg),
  );
}

/// Numbers (sizes, piece counts) use tabular figures so columns line up.
TextStyle numberStyle(BuildContext context, {double size = 18, FontWeight weight = FontWeight.w700, Color? color}) {
  return _digits(
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.label(context),
      height: 1.2,
    ),
  );
}
