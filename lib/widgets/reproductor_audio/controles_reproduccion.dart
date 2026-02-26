import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audio_service/audio_service.dart';
import '../../servicios/audio_handler.dart';

/// Widget compacto con los controles de reproducción de audio
/// Muestra: velocidad, anterior, play/pause, siguiente, reiniciar
class ControlesReproduccion extends StatelessWidget {
  final double velocidad;
  final VoidCallback onCambiarVelocidad;
  final VoidCallback onPlayPause;
  final VoidCallback onReiniciar;

  const ControlesReproduccion({
    super.key,
    required this.velocidad,
    required this.onCambiarVelocidad,
    required this.onPlayPause,
    required this.onReiniciar,
  });

  String _getTextoVelocidad() {
    if (velocidad == 0.5) return "1x";
    if (velocidad > 0.5) return "1.5x";
    return "0.7x";
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: audioHandler?.playbackState,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            children: [
              // Barra de progreso
              StreamBuilder<MediaItem?>(
                stream: audioHandler?.mediaItem,
                builder: (context, snapshot) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: null,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.black,
                      ),
                      minHeight: 4,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Controles
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Botón de velocidad
                  TextButton(
                    onPressed: onCambiarVelocidad,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(40, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _getTextoVelocidad(),
                      style: GoogleFonts.inter(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),

                  // Botones de reproducción
                  Row(
                    children: [
                      IconButton(
                        onPressed: audioHandler?.skipToPrevious,
                        icon: const Icon(Icons.skip_previous),
                        color: Colors.black,
                        iconSize: 28,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 24),
                      GestureDetector(
                        onTap: onPlayPause,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            playing ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        onPressed: audioHandler?.skipToNext,
                        icon: const Icon(Icons.skip_next),
                        color: Colors.black,
                        iconSize: 28,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),

                  // Botón reiniciar
                  IconButton(
                    onPressed: onReiniciar,
                    icon: const Icon(Icons.refresh, size: 20),
                    color: Colors.grey.shade600,
                    tooltip: "Reiniciar",
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
