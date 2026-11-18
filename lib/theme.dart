import 'package:flutter/material.dart';

/// Identité visuelle de l'Appli GDC : anthracite (choisi par Rayan le 18/11/2026 à la place de l'aubergine), or, fond ivoire.
class AppColors {
  static const anthracite = Color(0xFF1F2328);
  static const anthraciteLight = Color(0xFF3A4049);
  static const gold = Color(0xFFC9A227);
  static const goldLight = Color(0xFFE8CF7A);
  static const ivory = Color(0xFFF7F3EE);
  static const night = Color(0xFF121417);
  static const nightSurface = Color(0xFF1C1F24);

  /// Vert foncé choisi par Rayan pour les Chants Arabe ; les autres catégories ont un ton aussi foncé.
  static const categoryGreen = Color(0xFF06402B);

  /// Fond des bandeaux : couleur unie (Rayan préfère sans dégradé).
  static const heroGradient = LinearGradient(colors: [anthracite, anthracite]);
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
    // 12 px minimum pour les petits textes (11 par défaut) : lisible sur téléphone.
    labelSmall: t.labelSmall?.copyWith(fontSize: 12),
  );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.anthracite,
    brightness: brightness,
  ).copyWith(
    primary: dark ? const Color(0xFFDDE1E6) : AppColors.anthracite,
    onPrimary: dark ? AppColors.night : Colors.white,
    secondary: AppColors.gold,
    onSecondary: AppColors.night,
    tertiary: dark ? AppColors.goldLight : const Color(0xFF7D6310),
    surface: dark ? AppColors.night : AppColors.ivory,
    surfaceContainerLowest: dark ? const Color(0xFF0D0F12) : Colors.white,
    surfaceContainerLow: dark ? AppColors.nightSurface : Colors.white,
    surfaceContainer: dark ? const Color(0xFF272B31) : const Color(0xFFF1EBE3),
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
    // Onglet choisi en or clair, comme la barre du bas (sinon Material prend une teinte bleutée).
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.gold.withValues(alpha: 0.28) : null),
        foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
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

  /// Couleur de la catégorie (unie, texte blanc lisible dessus).
  Color get color => colors.first;

  LinearGradient get gradient => LinearGradient(colors: [color, color]);

  static CategoryStyle of(String name) => switch (name) {
        'Chants Français' => const CategoryStyle(
            Icons.music_note_rounded, [Color(0xFF0B2A5B)], 'Répertoire francophone'),
        'Chants Arabe' => const CategoryStyle(
            Icons.nights_stay_rounded, [AppColors.categoryGreen], 'Répertoire arabe'),
        'Chants Mariage' => const CategoryStyle(
            Icons.favorite_rounded, [Color(0xFF5E0B15)], 'Pour les cérémonies'),
        'Chants International' => const CategoryStyle(
            Icons.public_rounded, [Color(0xFF6B3A06)], 'Du monde entier'),
        'Livrets' => const CategoryStyle(
            Icons.menu_book_rounded, [AppColors.anthracite], 'Programmes des prestations'),
        _ => const CategoryStyle(
            Icons.queue_music_rounded, [AppColors.anthraciteLight], 'Chants'),
      };
}
