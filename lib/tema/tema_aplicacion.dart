import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

@immutable
class PaletaPNP extends ThemeExtension<PaletaPNP> {
  final Color actionCyan;
  final Color actionGold;
  final Color success;
  final Color warning;
  final Color info;
  final Color surfaceSoft;
  final Color feedbackCorrectBg;
  final Color feedbackCorrectBorder;
  final Color feedbackIncorrectBg;
  final Color feedbackIncorrectBorder;
  final Color feedbackPendingBg;
  final Color feedbackPendingBorder;

  const PaletaPNP({
    required this.actionCyan,
    required this.actionGold,
    required this.success,
    required this.warning,
    required this.info,
    required this.surfaceSoft,
    required this.feedbackCorrectBg,
    required this.feedbackCorrectBorder,
    required this.feedbackIncorrectBg,
    required this.feedbackIncorrectBorder,
    required this.feedbackPendingBg,
    required this.feedbackPendingBorder,
  });

  @override
  PaletaPNP copyWith({
    Color? actionCyan,
    Color? actionGold,
    Color? success,
    Color? warning,
    Color? info,
    Color? surfaceSoft,
    Color? feedbackCorrectBg,
    Color? feedbackCorrectBorder,
    Color? feedbackIncorrectBg,
    Color? feedbackIncorrectBorder,
    Color? feedbackPendingBg,
    Color? feedbackPendingBorder,
  }) {
    return PaletaPNP(
      actionCyan: actionCyan ?? this.actionCyan,
      actionGold: actionGold ?? this.actionGold,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      feedbackCorrectBg: feedbackCorrectBg ?? this.feedbackCorrectBg,
      feedbackCorrectBorder:
          feedbackCorrectBorder ?? this.feedbackCorrectBorder,
      feedbackIncorrectBg: feedbackIncorrectBg ?? this.feedbackIncorrectBg,
      feedbackIncorrectBorder:
          feedbackIncorrectBorder ?? this.feedbackIncorrectBorder,
      feedbackPendingBg: feedbackPendingBg ?? this.feedbackPendingBg,
      feedbackPendingBorder:
          feedbackPendingBorder ?? this.feedbackPendingBorder,
    );
  }

  @override
  PaletaPNP lerp(ThemeExtension<PaletaPNP>? other, double t) {
    if (other is! PaletaPNP) return this;
    return PaletaPNP(
      actionCyan: Color.lerp(actionCyan, other.actionCyan, t)!,
      actionGold: Color.lerp(actionGold, other.actionGold, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      surfaceSoft: Color.lerp(surfaceSoft, other.surfaceSoft, t)!,
      feedbackCorrectBg: Color.lerp(
        feedbackCorrectBg,
        other.feedbackCorrectBg,
        t,
      )!,
      feedbackCorrectBorder: Color.lerp(
        feedbackCorrectBorder,
        other.feedbackCorrectBorder,
        t,
      )!,
      feedbackIncorrectBg: Color.lerp(
        feedbackIncorrectBg,
        other.feedbackIncorrectBg,
        t,
      )!,
      feedbackIncorrectBorder: Color.lerp(
        feedbackIncorrectBorder,
        other.feedbackIncorrectBorder,
        t,
      )!,
      feedbackPendingBg: Color.lerp(
        feedbackPendingBg,
        other.feedbackPendingBg,
        t,
      )!,
      feedbackPendingBorder: Color.lerp(
        feedbackPendingBorder,
        other.feedbackPendingBorder,
        t,
      )!,
    );
  }
}

class TemaAplicacion {
  // Paleta PNP Competitiva (verde oscuro + lima)
  static const Color colorPrimario = Color(0xFF0B5A45);
  static const Color colorPrimarioOscuro = Color(0xFF084434);
  static const Color colorSecundario = Color(0xFF5EC7A7);
  static const Color colorDorado = Color(0xFFC8A84A);
  static const Color colorFondo = Color(0xFFECEFF3);
  static const Color colorTarjeta = Color(0xFFFFFFFF);
  static const Color colorExito = Color(0xFF34A37E);
  static const Color colorAdvertencia = Color(0xFFC8A84A);
  static const Color colorError = Color(0xFFD35B5B);
  static const Color textoPrimario = Color(0xFF111827);
  static const Color textoSecundario = Color(0xFF4B5563);
  static const Color colorBorde = Color(0xFFD3D9E0);

  // Paleta Modern Police - Oscuro
  static const Color colorFondoOscuro = Color(0xFF101823);
  static const Color colorTarjetaOscura = Color(0xFF17212B);
  static const Color colorTarjetaOscuraSecundaria = Color(0xFF1F2C39);
  static const Color colorPrimarioOscuroModo = Color(0xFF1F7A60);
  static const Color colorSecundarioOscuroModo = Color(0xFF66D3B3);
  static const Color colorDoradoOscuroModo = Color(0xFFD3B567);
  static const Color textoPrimarioOscuro = Color(0xFFE7EDF5);
  static const Color textoSecundarioOscuro = Color(0xFFA9B6C5);
  static const Color colorBordeOscuro = Color(0xFF334559);

  static const PaletaPNP paletaClaro = PaletaPNP(
    actionCyan: colorSecundario,
    actionGold: colorDorado,
    success: colorExito,
    warning: colorAdvertencia,
    info: Color(0xFF2B8F79),
    surfaceSoft: Color(0xFFF3F5F8),
    feedbackCorrectBg: Color(0xFFEAF8F2),
    feedbackCorrectBorder: Color(0xFF34A37E),
    feedbackIncorrectBg: Color(0xFFFBECEC),
    feedbackIncorrectBorder: Color(0xFFD35B5B),
    feedbackPendingBg: Color(0xFFFBF4E5),
    feedbackPendingBorder: Color(0xFFC8A84A),
  );

  static const PaletaPNP paletaOscuro = PaletaPNP(
    actionCyan: colorSecundarioOscuroModo,
    actionGold: colorDoradoOscuroModo,
    success: Color(0xFF4EBD97),
    warning: colorDoradoOscuroModo,
    info: Color(0xFF62C5AE),
    surfaceSoft: colorTarjetaOscuraSecundaria,
    feedbackCorrectBg: Color(0xFF133228),
    feedbackCorrectBorder: Color(0xFF4EBD97),
    feedbackIncorrectBg: Color(0xFF3A1E1E),
    feedbackIncorrectBorder: Color(0xFFE38383),
    feedbackPendingBg: Color(0xFF3A2F18),
    feedbackPendingBorder: colorDoradoOscuroModo,
  );

  static PaletaPNP paleta(BuildContext context) =>
      Theme.of(context).extension<PaletaPNP>() ?? paletaClaro;

  static ThemeData get temaClaro {
    final base = ThemeData.light(useMaterial3: true);
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: colorPrimario,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFBFE8DA),
      onPrimaryContainer: Color(0xFF0D362A),
      secondary: colorSecundario,
      onSecondary: Color(0xFF10392F),
      secondaryContainer: Color(0xFFD6F2E9),
      onSecondaryContainer: Color(0xFF184A3C),
      tertiary: colorDorado,
      onTertiary: Color(0xFF2E2208),
      tertiaryContainer: Color(0xFFF2E3BE),
      onTertiaryContainer: Color(0xFF4A3A11),
      error: colorError,
      onError: Colors.white,
      errorContainer: Color(0xFFF8D7D7),
      onErrorContainer: Color(0xFF5A1717),
      surface: colorTarjeta,
      onSurface: textoPrimario,
      onSurfaceVariant: textoSecundario,
      outline: colorBorde,
      outlineVariant: Color(0xFFE2E7ED),
      shadow: Color(0x1A000000),
      scrim: Color(0x33000000),
      inverseSurface: Color(0xFF222E3A),
      onInverseSurface: Color(0xFFE8EEF5),
      inversePrimary: Color(0xFF1F7A60),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorFondo,
      textTheme: GoogleFonts.interTextTheme(
        base.textTheme,
      ).apply(bodyColor: textoPrimario, displayColor: textoPrimario),
      cardTheme: CardThemeData(
        color: colorTarjeta,
        elevation: 0.8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E7ED)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: colorPrimario,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      dividerColor: const Color(0xFFE2E7ED),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorTarjeta,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: colorBorde),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: colorBorde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: colorPrimario, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: colorError, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorPrimario,
          foregroundColor: Colors.white,
          elevation: 0,
          disabledBackgroundColor: const Color(0xFFCAD3DC),
          disabledForegroundColor: const Color(0xFF8593A2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorPrimario,
          side: const BorderSide(color: colorPrimario),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorPrimario,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: colorPrimario,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colorPrimario;
          return null;
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1F2937),
        contentTextStyle: GoogleFonts.inter(color: Colors.white),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: colorTarjeta,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorTarjeta,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      extensions: const <ThemeExtension<dynamic>>[paletaClaro],
    );
  }

  static ThemeData get temaOscuro {
    final base = ThemeData.dark(useMaterial3: true);
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: colorPrimarioOscuroModo,
      onPrimary: Color(0xFFE5F6EF),
      primaryContainer: Color(0xFF124D3D),
      onPrimaryContainer: Color(0xFFD7E6EA),
      secondary: colorSecundarioOscuroModo,
      onSecondary: Color(0xFF0C3B2F),
      secondaryContainer: Color(0xFF244A3F),
      onSecondaryContainer: Color(0xFFD0ECE8),
      tertiary: colorDoradoOscuroModo,
      onTertiary: Color(0xFF2E2409),
      tertiaryContainer: Color(0xFF4C3E1F),
      onTertiaryContainer: Color(0xFFFFEFC8),
      error: Color(0xFFE38383),
      onError: Color(0xFF3A1515),
      errorContainer: Color(0xFF5A2424),
      onErrorContainer: Color(0xFFF8DEDE),
      surface: colorTarjetaOscura,
      onSurface: textoPrimarioOscuro,
      onSurfaceVariant: textoSecundarioOscuro,
      outline: colorBordeOscuro,
      outlineVariant: Color(0xFF2C3A49),
      shadow: Color(0x66000000),
      scrim: Color(0x7A000000),
      inverseSurface: Color(0xFFE8EEF5),
      onInverseSurface: Color(0xFF1A2430),
      inversePrimary: colorPrimario,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorFondoOscuro,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: textoPrimarioOscuro,
        displayColor: textoPrimarioOscuro,
      ),
      cardTheme: CardThemeData(
        color: colorTarjetaOscura,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: colorBordeOscuro),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: colorPrimarioOscuro,
        foregroundColor: textoPrimarioOscuro,
        elevation: 0,
      ),
      dividerColor: colorBordeOscuro,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorTarjetaOscuraSecundaria,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: colorBordeOscuro),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: colorBordeOscuro),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: colorPrimarioOscuroModo,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFF07A7A), width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorPrimarioOscuroModo,
          foregroundColor: const Color(0xFFDBF0E1),
          elevation: 0,
          disabledBackgroundColor: const Color(0xFF304050),
          disabledForegroundColor: const Color(0xFF8B99A8),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorPrimarioOscuroModo,
          side: const BorderSide(color: colorPrimarioOscuroModo),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorPrimarioOscuroModo,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: colorPrimarioOscuroModo,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorPrimarioOscuroModo;
          }
          return null;
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1A2430),
        contentTextStyle: GoogleFonts.inter(color: textoPrimarioOscuro),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: colorTarjetaOscura,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorTarjetaOscura,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      extensions: const <ThemeExtension<dynamic>>[paletaOscuro],
    );
  }
}
