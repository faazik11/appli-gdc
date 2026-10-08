import 'package:flutter/material.dart';

/// Identité visuelle de l'Appli GDC : aubergine profond, or, fond ivoire.
class AppColors {
  static const aubergine = Color(0xFF2E1A47);
  static const aubergineLight = Color(0xFF4B2E6F);
  static const gold = Color(0xFFC9A227);
  static const goldLight = Color(0xFFE8CF7A);
  static const ivory = Color(0xFFF7F3EE);
  static const night = Color(0xFF15111C);
  static const nightSurface = Color(0xFF211B2C);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [aubergine, aubergineLight, Color(0xFF6B3F7A)],
  );
}

const _fallback = ['Amiri'];

TextTheme _textTheme(TextTheme base, Color body) {
  final t = base.apply(fontFamily: 'Poppins', fontFamilyFallback: _fallback, bodyColor: body, displayColor: body);
  TextStyle? serif(TextStyle? s) =>
      s?.copyWith(fontFamily: 'DMSerifDisplay', fontWeight: FontWeight.w400, fontFamilyFallback: _fallback);
  return t.copyWith(
    displayLarge: serif(t.displayLarge),
    displayMedium: serif(t.displayMedium),
    displaySmall: serif(t.displaySmall),
    headlineLarge: serif(t.headlineLarge),
    headlineMedium: serif(t.headlineMedium),
    headlineSmall: serif(t.headlineSmall),
    titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
  );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.aubergine,
    brightness: brightness,
  ).copyWith(
    primary: dark ? const Color(0xFFCDB4F0) : AppColors.aubergine,
    onPrimary: dark ? AppColors.night : Colors.white,
    secondary: AppColors.gold,
    onSecondary: AppColors.night,
    tertiary: dark ? AppColors.goldLight : const Color(0xFF8A6D12),
    surface: dark ? AppColors.night : AppColors.ivory,
    surfaceContainerLowest: dark ? const Color(0xFF110D17) : Colors.white,
    surfaceContainerLow: dark ? AppColors.nightSurface : Colors.white,
    surfaceContainer: dark ? const Color(0xFF292235) : const Color(0xFFF1EBE3),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final radius = BorderRadius.circular(18);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: _textTheme(base.textTheme, scheme.onSurface),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'DMSerifDisplay',
        fontFamilyFallback: _fallback,
        fontSize: 24,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: dark ? 0.25 : 0.5)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      labelStyle: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, color: scheme.onSurface),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.gold,
      foregroundColor: AppColors.night,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: AppColors.gold.withValues(alpha: 0.28),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurface),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: AppColors.gold.withValues(alpha: 0.28),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.4)),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
  );
}

/// Couleur et icône propres à chaque catégorie.
class CategoryStyle {
  final IconData icon;
  final List<Color> colors;
  final String subtitle;

  const CategoryStyle(this.icon, this.colors, this.subtitle);

  LinearGradient get gradient =>
      LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors);

  static CategoryStyle of(String name) => switch (name) {
        'Chants Français' => const CategoryStyle(
            Icons.music_note_rounded, [Color(0xFF2F4C8F), Color(0xFF5E86D1)], 'Répertoire francophone'),
        'Chants Arabe' => const CategoryStyle(
            Icons.nights_stay_rounded, [Color(0xFF0E6B58), Color(0xFF2DAA8A)], 'Répertoire arabe'),
        'Chants Mariage' => const CategoryStyle(
            Icons.favorite_rounded, [Color(0xFFA2304F), Color(0xFFE07795)], 'Pour les cérémonies'),
        'Chants International' => const CategoryStyle(
            Icons.public_rounded, [Color(0xFFB45A12), Color(0xFFE9A04B)], 'Du monde entier'),
        'Livrets' => const CategoryStyle(
            Icons.menu_book_rounded, [AppColors.aubergine, Color(0xFF9C7A2B)], 'Programmes des prestations'),
        _ => const CategoryStyle(
            Icons.queue_music_rounded, [AppColors.aubergineLight, Color(0xFF8E6BB8)], 'Chants'),
      };
}
