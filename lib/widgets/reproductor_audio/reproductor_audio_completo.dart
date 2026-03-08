import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audio_service/audio_service.dart';
import '../../servicios/audio_handler.dart';
import '../../modelos/modelo_pregunta.dart';

/// Widget completo del reproductor de audio con diseño colapsable/expandible
class ReproductorAudioCompleto extends StatefulWidget {
  final List<Pregunta> preguntas;
  final VoidCallback?onConfiguracion;

  const ReproductorAudioCompleto({
    super.key,
    required this.preguntas,
    this.onConfiguracion,
  });

  @override
  State<ReproductorAudioCompleto> createState() =>
      _ReproductorAudioCompletoState();
}

class _ReproductorAudioCompletoState extends State<ReproductorAudioCompleto> {
  double _velocidad = 0.5;
  bool _expandido = false; // Estado local

  void _cambiarVelocidad() {
    if (audioHandler == null) return;
    setState(() {
      if (_velocidad == 0.5) {
        _velocidad = 0.75;
      } else if (_velocidad == 0.75) {
        _velocidad = 0.35;
      } else {
        _velocidad = 0.5;
      }
    });
    (audioHandler as AudioPlayerHandler).setSpeed(_velocidad);
  }

  String _getTextoVelocidad() {
    if (_velocidad == 0.5) return "1x";
    if (_velocidad > 0.5) return "1.5x";
    return "0.7x";
  }

  Future<void> _continuarReproduccion() async {
    if (audioHandler == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Servicio de audio no disponible. Reinicie la app.'),
          ),
        );
      }
      return;
    }

    final state = audioHandler!.playbackState.value;

    if (state.playing) {
      await audioHandler!.pause();
      if (mounted) setState(() {});
      return;
    }

    if (state.processingState == AudioProcessingState.ready) {
      // Si está en pausa (ready pero no playing), continuar
      await audioHandler!.play();
      if (mounted) setState(() {});
      return;
    }

    if (widget.preguntas.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cargando ${widget.preguntas.length} preguntas...'),
            backgroundColor: const Color(0xFF1E6B63),
            duration: const Duration(milliseconds: 1000),
          ),
        );
      }
      // Al iniciar, expandimos automáticamente
      setState(() {
        _expandido = true;
      });
      await (audioHandler as AudioPlayerHandler).cargarCola(widget.preguntas);
      if (mounted) setState(() {});
    }
  }

  Future<void> _detenerReproduccion() async {
    if (audioHandler != null) {
      await audioHandler!.stop();
      if (mounted) {
        setState(() {
          _expandido = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (audioHandler == null) {
      return _buildErrorWidget();
    }

    return StreamBuilder<PlaybackState>(
      stream: audioHandler!.playbackState,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ??false;
        final processingState =
            snapshot.data?.processingState ??AudioProcessingState.idle;
        final isActive = processingState != AudioProcessingState.idle;

        // Si está activo, forzamos que esté expandido
        final mostrarExpandido = _expandido || isActive;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFAE8FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE9D5FF)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Encabezado clickeable (Sin botón configuración)
              _buildEncabezadoColapsable(isActive: isActive),

              // Contenido expandido
              if (mostrarExpandido) ...[
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  height: 1,
                  color: const Color(0xFFE9D5FF),
                ),
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        'Escucha las preguntas, alternativas y respuestas correctas',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF1A5F59),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (isActive || playing) ...[
                      _buildTarjetaPreguntaActual(),
                      _buildControles(playing),
                    ] else ...[
                      _buildBotonIniciar(),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildEncabezadoColapsable({required bool isActive}) {
    return InkWell(
      onTap: () {
        setState(() {
          _expandido = !_expandido;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF1E6B63),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.volume_up, color: Colors.white, size: 18),
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
            // Se eliminó el botón de configuración de aquí
            const SizedBox(width: 8),
            Icon(
              (_expandido || isActive)
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              color: const Color(0xFF164A55),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonIniciar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          // Info de preguntas CONVERTIDO en botón de configuración
          Expanded(
            child: InkWell(
              onTap: widget.onConfiguracion, // Acciona la configuración
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    // Icono de engranaje (Configuración) reemplaza audífonos
                    Icon(
                      Icons.settings_outlined,
                      size: 20,
                      color: const Color(0xFF1E6B63).withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.preguntas.length} preguntas disponibles',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF164A55),
                          decoration: TextDecoration.underline, // Visual cue
                          decorationColor: const Color(
                            0xFF164A55,
                          ).withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _continuarReproduccion,
            icon: const Icon(Icons.play_arrow, size: 20),
            label: const Text('Reproducir'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E6B63),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTarjetaPreguntaActual() {
    return StreamBuilder<MediaItem?>(
      stream: audioHandler!.mediaItem,
      builder: (context, snapshot) {
        final mediaItem = snapshot.data;
        final queueIndex = audioHandler!.playbackState.value.queueIndex ??0;
        final totalPreguntas = widget.preguntas.length;

        Pregunta?preguntaActual;
        if (queueIndex < widget.preguntas.length) {
          preguntaActual = widget.preguntas[queueIndex];
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pregunta ${queueIndex + 1} - ${preguntaActual?.materia ??mediaItem?.artist ??"Cargando..."}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF164A55),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAE8FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${queueIndex + 1} de $totalPreguntas',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A5F59),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                preguntaActual?.texto ??'Preparando pregunta...',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.black87,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControles(bool playing) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildBotonControl(
                icon: Icons.skip_previous,
                onTap: () => audioHandler?.skipToPrevious(),
                tooltip: 'Anterior',
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: _continuarReproduccion,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E6B63),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x40A855F7),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    playing ?Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _buildBotonControl(
                icon: Icons.skip_next,
                onTap: () => audioHandler?.skipToNext(),
                tooltip: 'Siguiente',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildBotonVelocidad(),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _continuarReproduccion,
                  icon: Icon(
                    playing ?Icons.pause : Icons.play_arrow,
                    size: 18,
                  ),
                  label: Text(playing ?'Pausar' : 'Continuar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E6B63),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _detenerReproduccion,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('Detener'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF164A55),
                    side: const BorderSide(color: Color(0xFF1E6B63)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBotonControl({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9D5FF)),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon),
        color: const Color(0xFF164A55),
        iconSize: 24,
        tooltip: tooltip,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
      ),
    );
  }

  Widget _buildBotonVelocidad() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9D5FF)),
      ),
      child: TextButton(
        onPressed: _cambiarVelocidad,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: Size.zero,
        ),
        child: Text(
          _getTextoVelocidad(),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF164A55),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Servicio de audio no disponible",
              style: TextStyle(color: Colors.red.shade900, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

