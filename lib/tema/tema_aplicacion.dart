import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TemaAplicacion {
  // Colores extraídos de las capturas
  static const Color colorPrimario = Color(0xFF4F46E5); // Azul/Indigo Vibrante
  static const Color colorSecundario = Color(0xFF818CF8); // Indigo más claro
  static const Color colorFondo = Color(0xFFF3F4F6); // Gris claro/Azul
  static const Color colorTarjeta = Colors.white;
  static const Color colorExito = Color(0xFF10B981); // Verde
  static const Color colorError = Color(0xFFEF4444); // Rojo
  static const Color textoPrimario = Color(0xFF1F2937); // Gris oscuro
  static const Color textoSecundario = Color(0xFF6B7280); // Gris medio

  static ThemeData get temaClaro {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.light(
        primary: colorPrimario,
        secondary: colorSecundario,
        surface: colorFondo,
        error: colorError,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textoPrimario,
      ),
      scaffoldBackgroundColor: colorFondo,
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: textoPrimario,
        displayColor: textoPrimario,
      ),
      /*
      cardTheme: CardTheme(
        color: colorTarjeta,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      */
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: colorPrimario, width: 2),
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
    );
  }
}
