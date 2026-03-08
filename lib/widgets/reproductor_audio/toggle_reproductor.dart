import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Widget para el botón toggle que muestra/oculta el reproductor de audio
class ToggleReproductor extends StatelessWidget {
  final bool expandido;
  final VoidCallback onToggle;

  const ToggleReproductor({
    super.key,
    required this.expandido,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAE8FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE9D5FF)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF1E6B63),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.volume_up, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Reproductor de Audio',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF164A55),
                ),
              ),
            ),
            Icon(
              expandido ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: const Color(0xFF164A55),
            ),
          ],
        ),
      ),
    );
  }
}

