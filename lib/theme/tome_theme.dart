import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The three looks you can pick in Settings → Appearance.
enum TomeStyle { arcane, parchment, fel }

extension TomeStyleName on TomeStyle {
  String get label => switch (this) {
        TomeStyle.arcane => 'Arcane Library',
        TomeStyle.parchment => 'Old Parchment',
        TomeStyle.fel => 'Fel & Shadow',
      };

  String get description => switch (this) {
        TomeStyle.arcane => 'Midnight indigo, gold trim, arcane blue glow',
        TomeStyle.parchment => 'Aged paper, dark ink, wax-seal red',
        TomeStyle.fel => 'Near-black, dark iron, fel green glow',
      };
}

/// Colors for one look. Read it anywhere with `context.tome`.
@immutable
class TomePalette extends ThemeExtension<TomePalette> {
  final bool dark;
  final Color bgTop; // background gradient
  final Color bgBottom;
  final Color surface; // cards, sheets, dialogs
  final Color trim; // gold / iron borders and ornaments
  final Color trimDark;
  final Color glow; // accent: progress, highlights, active things
  final Color text;
  final Color textMuted;
  final Color shelf; // bookshelf planks
  final Color shelfEdge;

  const TomePalette({
    required this.dark,
    required this.bgTop,
    required this.bgBottom,
    required this.surface,
    required this.trim,
    required this.trimDark,
    required this.glow,
    required this.text,
    required this.textMuted,
    required this.shelf,
    required this.shelfEdge,
  });

  static const arcane = TomePalette(
    dark: true,
    bgTop: Color(0xFF1D1442),
    bgBottom: Color(0xFF07060F),
    surface: Color(0xFF17112E),
    trim: Color(0xFFD4A640),
    trimDark: Color(0xFF6E4E1C),
    glow: Color(0xFF7FDCFF),
    text: Color(0xFFF1E2BD),
    textMuted: Color(0xFFB4A68A),
    shelf: Color(0xFF3A2414),
    shelfEdge: Color(0xFF1E120A),
  );

  static const parchment = TomePalette(
    dark: false,
    bgTop: Color(0xFFF6EBCB),
    bgBottom: Color(0xFFE2CB96),
    surface: Color(0xFFF8EDD2),
    trim: Color(0xFF8A6420),
    trimDark: Color(0xFFB79A62),
    glow: Color(0xFF8E1B1B),
    text: Color(0xFF3B2414),
    textMuted: Color(0xFF6E5434),
    shelf: Color(0xFF8A6A43),
    shelfEdge: Color(0xFF5E4528),
  );

  static const fel = TomePalette(
    dark: true,
    bgTop: Color(0xFF13201A),
    bgBottom: Color(0xFF030504),
    surface: Color(0xFF111713),
    trim: Color(0xFF7D868F),
    trimDark: Color(0xFF353B40),
    glow: Color(0xFF7CFF4F),
    text: Color(0xFFDFE8D6),
    textMuted: Color(0xFF98A392),
    shelf: Color(0xFF2B3035),
    shelfEdge: Color(0xFF15181B),
  );

  static TomePalette of(TomeStyle style) => switch (style) {
        TomeStyle.arcane => arcane,
        TomeStyle.parchment => parchment,
        TomeStyle.fel => fel,
      };

  /// Background color behind highlighted read-along text.
  Color get highlight => glow.withValues(alpha: dark ? 0.28 : 0.18);

  @override
  TomePalette copyWith() => this;

  @override
  TomePalette lerp(TomePalette? other, double t) =>
      (other == null || t < 0.5) ? this : other;
}

extension TomeContext on BuildContext {
  TomePalette get tome => Theme.of(this).extension<TomePalette>()!;
}

/// Fantasy title font (Cinzel) for headings, book titles, buttons.
TextStyle titleFont(TextStyle? base) => GoogleFonts.cinzel(textStyle: base);

/// Builds the whole Material theme for one look.
ThemeData buildTomeTheme(TomeStyle style) {
  final p = TomePalette.of(style);
  final brightness = p.dark ? Brightness.dark : Brightness.light;
  final onGlow = p.dark ? const Color(0xFF07060F) : Colors.white;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.glow,
    onPrimary: onGlow,
    primaryContainer: p.glow.withValues(alpha: 0.25),
    onPrimaryContainer: p.text,
    secondary: p.trim,
    onSecondary: p.dark ? const Color(0xFF1A1206) : Colors.white,
    error: p.dark ? const Color(0xFFFF6B6B) : const Color(0xFFB00020),
    onError: Colors.white,
    surface: p.surface,
    onSurface: p.text,
    onSurfaceVariant: p.textMuted,
    surfaceContainerHigh: Color.lerp(p.surface, p.trim, 0.08),
    surfaceContainerHighest: Color.lerp(p.surface, p.trim, 0.14),
    outline: p.trim,
    outlineVariant: p.trimDark,
  );

  // Body text: EB Garamond (book-like serif). Headings: Cinzel.
  final base = ThemeData(brightness: brightness).textTheme;
  // Font applied style by style (works with every google_fonts version).
  TextStyle? g(TextStyle? style) =>
      style == null ? null : GoogleFonts.ebGaramond(textStyle: style);
  final body = TextTheme(
    displayLarge: g(base.displayLarge),
    displayMedium: g(base.displayMedium),
    displaySmall: g(base.displaySmall),
    headlineLarge: g(base.headlineLarge),
    headlineMedium: g(base.headlineMedium),
    headlineSmall: g(base.headlineSmall),
    titleLarge: g(base.titleLarge),
    titleMedium: g(base.titleMedium),
    titleSmall: g(base.titleSmall),
    bodyLarge: g(base.bodyLarge),
    bodyMedium: g(base.bodyMedium),
    bodySmall: g(base.bodySmall),
    labelLarge: g(base.labelLarge),
    labelMedium: g(base.labelMedium),
    labelSmall: g(base.labelSmall),
  ).apply(
    bodyColor: p.text,
    displayColor: p.text,
  );
  final text = body.copyWith(
    headlineMedium: titleFont(body.headlineMedium),
    headlineSmall: titleFont(body.headlineSmall),
    titleLarge: titleFont(body.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
    titleMedium: titleFont(body.titleMedium),
    labelLarge: titleFont(body.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
    bodyLarge: body.bodyLarge?.copyWith(fontSize: 17),
    bodyMedium: body.bodyMedium?.copyWith(fontSize: 16),
    bodySmall: body.bodySmall?.copyWith(fontSize: 13.5, color: p.textMuted),
  );

  final trimBorder = BorderSide(color: p.trim.withValues(alpha: 0.6), width: 1);
  final sheetShape = RoundedRectangleBorder(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
    side: trimBorder,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: Color.lerp(p.bgTop, p.bgBottom, 0.7),
    extensions: [p],
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.text,
      titleTextStyle: titleFont(text.titleLarge?.copyWith(color: p.trim, letterSpacing: 1.5)),
      iconTheme: IconThemeData(color: p.trim),
      actionsIconTheme: IconThemeData(color: p.trim),
    ),
    iconTheme: IconThemeData(color: p.text),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: trimBorder,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.trim, width: 1.5),
      ),
      titleTextStyle: text.titleLarge?.copyWith(color: p.trim),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: sheetShape,
      dragHandleColor: p.trim,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: trimBorder,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.surface,
      contentTextStyle: text.bodyMedium?.copyWith(color: p.text),
      actionTextColor: p.glow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: trimBorder,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: p.trim,
      unselectedLabelColor: p.textMuted,
      indicatorColor: p.glow,
      dividerColor: p.trimDark.withValues(alpha: 0.5),
      labelStyle: titleFont(text.labelLarge?.copyWith(letterSpacing: 1.2)),
      unselectedLabelStyle: titleFont(text.labelLarge?.copyWith(letterSpacing: 1.2)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.glow,
      inactiveTrackColor: p.trimDark.withValues(alpha: 0.6),
      thumbColor: p.trim,
      overlayColor: p.glow.withValues(alpha: 0.15),
      trackHeight: 3,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.glow,
      linearTrackColor: p.trimDark.withValues(alpha: 0.45),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.trim,
        foregroundColor: scheme.onSecondary,
        textStyle: titleFont(text.labelLarge),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.trim),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.trim,
      textColor: p.text,
      selectedColor: p.glow,
    ),
    dividerTheme: DividerThemeData(color: p.trimDark.withValues(alpha: 0.6)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.glow : p.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? p.glow.withValues(alpha: 0.35)
          : p.trimDark.withValues(alpha: 0.4)),
      trackOutlineColor: WidgetStatePropertyAll(p.trimDark),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.glow.withValues(alpha: 0.25),
      side: trimBorder,
      labelStyle: text.bodyMedium,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderSide: BorderSide(color: p.trimDark),
        borderRadius: BorderRadius.circular(10),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: p.trimDark),
        borderRadius: BorderRadius.circular(10),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: p.trim, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      labelStyle: TextStyle(color: p.textMuted),
    ),
  );
}
