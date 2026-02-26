import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Widget de encabezado reutilizable para pantallas de revisión
class EncabezadoPantalla extends StatelessWidget {
  final IconData icono;
  final Color colorIcono;
  final String titulo;
  final String subtitulo;

  const EncabezadoPantalla({
    super.key,
    required this.icono,
    required this.colorIcono,
    required this.titulo,
    required this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, color: colorIcono, size: 28),
            const SizedBox(width: 8),
            Text(
              titulo,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1E3A8A),
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitulo,
          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
