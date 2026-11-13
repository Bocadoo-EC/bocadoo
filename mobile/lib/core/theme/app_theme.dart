import 'package:material_ui/material_ui.dart';

/// Bocadoo App Theme & Design System tokens.
/// Fuente única de verdad basada en Material Design 3 y los tokens del PMV Web
/// (docs/IDENTIDAD_BOCADOO.md y src/styles.css).
class AppColors {
  AppColors._();

  // Semilla de marca
  static const Color brandSeed = Color(0xFF7B2CBF);

  // Modo Claro
  static const Color lightPrimary = Color(0xFF8234C6);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightPrimaryHover = Color(0xFF680EAC);
  static const Color lightPrimaryContainer = Color(0xFFF1DBFF);
  static const Color lightOnPrimaryContainer = Color(0xFF2D0050);

  static const Color lightSecondaryContainer = Color(0xFFEDDDF6);
  static const Color lightOnSecondaryContainer = Color(0xFF211829);

  static const Color lightBackground = Color(0xFFF5ECFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceNav = Color(0xFFFFFFFF);
  static const Color lightForeground = Color(0xFF2D0050);
  static const Color lightMutedForeground = Color(0xFF635C65);

  static const Color lightBorder = Color(0xFFCDC4CE);
  static const Color lightOutline = Color(0xFF7C757E);
  static const Color lightInputBg = Color(0xFFFFFFFF);

  static const Color lightSuccess = Color(0xFF157A41);
  static const Color lightSuccessForeground = Color(0xFFFFFFFF);
  static const Color lightSuccessContainer = Color(0xFFE6F6EC);
  static const Color lightOnSuccessContainer = Color(0xFF0F3D22);

  static const Color lightDanger = Color(0xFFBA1A1A);
  static const Color lightDangerForeground = Color(0xFFFFFFFF);
  static const Color lightDangerContainer = Color(0xFFFFDAD6);
  static const Color lightOnDangerContainer = Color(0xFF410002);

  static const Color lightFooterBg = Color(0xFF2D0050);
  static const Color lightFooterAccent = Color(0xFFDEB7FF);

  // Modo Oscuro
  static const Color darkBackground = Color(0xFF1C1127);
  static const Color darkSurface = Color(0xFF2A1B3A);
  static const Color darkSurfaceNav = Color(0xFF24172F);
  static const Color darkForeground = Color(0xFFF1DBFF);
  static const Color darkMutedForeground = Color(0xFFCDB8E0);

  static const Color darkPrimary = Color(0xFFDEB7FF);
  static const Color darkOnPrimary = Color(0xFF4A007F);
  static const Color darkPrimaryHover = Color(0xFFF1DBFF);
  static const Color darkPrimaryContainer = Color(0xFF680EAC);
  static const Color darkOnPrimaryContainer = Color(0xFFF1DBFF);

  static const Color darkSecondaryContainer = Color(0xFF4A007F);
  static const Color darkOnSecondaryContainer = Color(0xFFF1DBFF);

  static const Color darkBorder = Color(0xFF4A454D);
  static const Color darkOutline = Color(0xFF968E98);
  static const Color darkInputBg = Color(0xFF2A1B3A);

  static const Color darkSuccess = Color(0xFF7FDC9F);
  static const Color darkSuccessForeground = Color(0xFF0F3D22);
  static const Color darkSuccessContainer = Color(0xFF0F3D22);
  static const Color darkOnSuccessContainer = Color(0xFF7FDC9F);

  static const Color darkDanger = Color(0xFFFFB4AB);
  static const Color darkDangerForeground = Color(0xFF690005);
  static const Color darkDangerContainer = Color(0xFF93000A);
  static const Color darkOnDangerContainer = Color(0xFFFFB4AB);

  static const Color darkFooterBg = Color(0xFF120A1A);
  static const Color darkFooterAccent = Color(0xFFDEB7FF);

  // Tokens de QR (Inmutables en ambos temas para garantizar lectura óptica)
  static const Color qrForeground = Color(0xFF2D0050);
  static const Color qrBackground = Color(0xFFFFFFFF);

  // Hero Gradients
  static const LinearGradient lightHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9C51E1), Color(0xFF8234C6), Color(0xFF680EAC)],
  );

  static const LinearGradient darkHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8234C6), Color(0xFF680EAC), Color(0xFF2D0050)],
  );
}

/// Extensión de tema para colores semánticos propios de Bocadoo
class BocadooColors extends ThemeExtension<BocadooColors> {
  final Color success;
  final Color successForeground;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color danger;
  final Color dangerForeground;
  final Color dangerContainer;
  final Color onDangerContainer;
  final Color surfaceNav;
  final Color footerBg;
  final Color footerAccent;
  final Color inputBg;
  final Color qrForeground;
  final Color qrBackground;
  final LinearGradient heroGradient;

  const BocadooColors({
    required this.success,
    required this.successForeground,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.danger,
    required this.dangerForeground,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.surfaceNav,
    required this.footerBg,
    required this.footerAccent,
    required this.inputBg,
    required this.qrForeground,
    required this.qrBackground,
    required this.heroGradient,
  });

  static const BocadooColors light = BocadooColors(
    success: AppColors.lightSuccess,
    successForeground: AppColors.lightSuccessForeground,
    successContainer: AppColors.lightSuccessContainer,
    onSuccessContainer: AppColors.lightOnSuccessContainer,
    danger: AppColors.lightDanger,
    dangerForeground: AppColors.lightDangerForeground,
    dangerContainer: AppColors.lightDangerContainer,
    onDangerContainer: AppColors.lightOnDangerContainer,
    surfaceNav: AppColors.lightSurfaceNav,
    footerBg: AppColors.lightFooterBg,
    footerAccent: AppColors.lightFooterAccent,
    inputBg: AppColors.lightInputBg,
    qrForeground: AppColors.qrForeground,
    qrBackground: AppColors.qrBackground,
    heroGradient: AppColors.lightHeroGradient,
  );

  static const BocadooColors dark = BocadooColors(
    success: AppColors.darkSuccess,
    successForeground: AppColors.darkSuccessForeground,
    successContainer: AppColors.darkSuccessContainer,
    onSuccessContainer: AppColors.darkOnSuccessContainer,
    danger: AppColors.darkDanger,
    dangerForeground: AppColors.darkDangerForeground,
    dangerContainer: AppColors.darkDangerContainer,
    onDangerContainer: AppColors.darkOnDangerContainer,
    surfaceNav: AppColors.darkSurfaceNav,
    footerBg: AppColors.darkFooterBg,
    footerAccent: AppColors.darkFooterAccent,
    inputBg: AppColors.darkInputBg,
    qrForeground: AppColors.qrForeground,
    qrBackground: AppColors.qrBackground,
    heroGradient: AppColors.darkHeroGradient,
  );

  @override
  ThemeExtension<BocadooColors> copyWith({
    Color? success,
    Color? successForeground,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? danger,
    Color? dangerForeground,
    Color? dangerContainer,
    Color? onDangerContainer,
    Color? surfaceNav,
    Color? footerBg,
    Color? footerAccent,
    Color? inputBg,
    Color? qrForeground,
    Color? qrBackground,
    LinearGradient? heroGradient,
  }) {
    return BocadooColors(
      success: success ?? this.success,
      successForeground: successForeground ?? this.successForeground,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      danger: danger ?? this.danger,
      dangerForeground: dangerForeground ?? this.dangerForeground,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
      surfaceNav: surfaceNav ?? this.surfaceNav,
      footerBg: footerBg ?? this.footerBg,
      footerAccent: footerAccent ?? this.footerAccent,
      inputBg: inputBg ?? this.inputBg,
      qrForeground: qrForeground ?? this.qrForeground,
      qrBackground: qrBackground ?? this.qrBackground,
      heroGradient: heroGradient ?? this.heroGradient,
    );
  }

  @override
  ThemeExtension<BocadooColors> lerp(
    covariant ThemeExtension<BocadooColors>? other,
    double t,
  ) {
    if (other is! BocadooColors) return this;
    return BocadooColors(
      success: Color.lerp(success, other.success, t)!,
      successForeground: Color.lerp(
        successForeground,
        other.successForeground,
        t,
      )!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerForeground: Color.lerp(
        dangerForeground,
        other.dangerForeground,
        t,
      )!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      onDangerContainer: Color.lerp(
        onDangerContainer,
        other.onDangerContainer,
        t,
      )!,
      surfaceNav: Color.lerp(surfaceNav, other.surfaceNav, t)!,
      footerBg: Color.lerp(footerBg, other.footerBg, t)!,
      footerAccent: Color.lerp(footerAccent, other.footerAccent, t)!,
      inputBg: Color.lerp(inputBg, other.inputBg, t)!,
      qrForeground: qrForeground,
      qrBackground: qrBackground,
      heroGradient: heroGradient,
    );
  }
}

/// Definición completa de temas Material 3 para Bocadoo
class AppTheme {
  AppTheme._();

  // Color primario alias para compatibilidad rápida con prompts
  static const Color primaryPurple = AppColors.lightPrimary;
  static const Color qrFg = AppColors.qrForeground;
  static const Color qrBg = AppColors.qrBackground;

  // Radios oficiales
  static const double buttonRadius = 999.0;
  static const double cardRadius = 28.0;
  static const double inputRadius = 16.0;

  static ThemeData get lightTheme {
    final colorScheme = const ColorScheme.light(
      primary: AppColors.lightPrimary,
      onPrimary: AppColors.lightOnPrimary,
      primaryContainer: AppColors.lightPrimaryContainer,
      onPrimaryContainer: AppColors.lightOnPrimaryContainer,
      secondary: AppColors.lightSecondaryContainer,
      onSecondary: AppColors.lightOnSecondaryContainer,
      secondaryContainer: AppColors.lightSecondaryContainer,
      onSecondaryContainer: AppColors.lightOnSecondaryContainer,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightForeground,
      onSurfaceVariant: AppColors.lightMutedForeground,
      outline: AppColors.lightOutline,
      outlineVariant: AppColors.lightBorder,
      error: AppColors.lightDanger,
      onError: AppColors.lightDangerForeground,
      errorContainer: AppColors.lightDangerContainer,
      onErrorContainer: AppColors.lightOnDangerContainer,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.lightBackground,
      fontFamily: 'Plus Jakarta Sans',
      extensions: const [BocadooColors.light],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppColors.lightForeground),
        titleTextStyle: TextStyle(
          color: AppColors.lightForeground,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          fontFamily: 'Plus Jakarta Sans',
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: AppColors.lightBorder, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.lightPrimary,
          foregroundColor: AppColors.lightOnPrimary,
          elevation: 0,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.lightPrimary,
          side: const BorderSide(color: AppColors.lightBorder, width: 1.5),
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightInputBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: AppColors.lightOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: AppColors.lightPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: AppColors.lightDanger),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = const ColorScheme.dark(
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.darkOnPrimary,
      primaryContainer: AppColors.darkPrimaryContainer,
      onPrimaryContainer: AppColors.darkOnPrimaryContainer,
      secondary: AppColors.darkSecondaryContainer,
      onSecondary: AppColors.darkOnSecondaryContainer,
      secondaryContainer: AppColors.darkSecondaryContainer,
      onSecondaryContainer: AppColors.darkOnSecondaryContainer,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkForeground,
      onSurfaceVariant: AppColors.darkMutedForeground,
      outline: AppColors.darkOutline,
      outlineVariant: AppColors.darkBorder,
      error: AppColors.darkDanger,
      onError: AppColors.darkDangerForeground,
      errorContainer: AppColors.darkDangerContainer,
      onErrorContainer: AppColors.darkOnDangerContainer,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.darkBackground,
      fontFamily: 'Plus Jakarta Sans',
      extensions: const [BocadooColors.dark],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppColors.darkForeground),
        titleTextStyle: TextStyle(
          color: AppColors.darkForeground,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          fontFamily: 'Plus Jakarta Sans',
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: AppColors.darkBorder, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkPrimary,
          foregroundColor: AppColors.darkOnPrimary,
          elevation: 0,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkPrimary,
          side: const BorderSide(color: AppColors.darkBorder, width: 1.5),
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkInputBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: AppColors.darkOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: AppColors.darkPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: AppColors.darkDanger),
        ),
      ),
    );
  }
}

/// Acceso de conveniencia a los tokens de Bocadoo desde BuildContext
extension BocadooThemeX on BuildContext {
  BocadooColors get bocadooColors =>
      Theme.of(this).extension<BocadooColors>() ?? BocadooColors.light;
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
}
