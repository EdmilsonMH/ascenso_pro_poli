import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../modelos/modelo_pregunta.dart';
import 'pantalla_revision_practica.dart';

class PantallaResultados extends StatelessWidget {
  final int puntaje;
  final int totalPreguntas;
  final Duration tiempoTranscurrido;
  final List<Pregunta> preguntasCorrectas;
  final List<IntentoFallido> preguntasIncorrectas;
  final bool cuentaParaRanking;
  final bool esPracticaGuiada;
  final VoidCallback onNuevaPractica;
  final VoidCallback onVolverInicio;

  const PantallaResultados({
    super.key,
    required this.puntaje,
    required this.totalPreguntas,
    required this.tiempoTranscurrido,
    required this.preguntasCorrectas,
    required this.preguntasIncorrectas,
    this.cuentaParaRanking = false,
    this.esPracticaGuiada = false,
    required this.onNuevaPractica,
    required this.onVolverInicio,
  });

  String _formatearTiempo(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final double porcentaje = (puntaje / totalPreguntas) * 100;
    final bool aprobado = porcentaje >= 70;
    final int incorrectas = totalPreguntas - puntaje;
    final bool esRanking = cuentaParaRanking;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // Trophy Icon
              const Icon(
                Icons.emoji_events_outlined,
                size: 64,
                color: Color(0xFF9CA3AF),
              ),
              const SizedBox(height: 16),
              // Title
              Text(
                '¡Práctica Completada!',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Has finalizado tu examen de práctica',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),

              // Ranking Banner (Conditional)
              if (esRanking)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEFCE8), // Light yellow
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE047)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.emoji_events_outlined,
                        color: Color(0xFFA16207),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFFA16207),
                              height: 1.4,
                            ),
                              children: const [
                                TextSpan(
                                text: 'Esta práctica cuenta para el ranking ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              TextSpan(
                                text:
                                    'porque completaste 100 preguntas con todas las materias',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 48),

              // Score Percentage
              Text(
                '${porcentaje.toStringAsFixed(1)}%',
                style: GoogleFonts.inter(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$puntaje de $totalPreguntas respuestas correctas',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              if (!esPracticaGuiada) ...[
                // Feedback Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: aprobado
                        ? const Color(0xFFF0FDF4)
                        : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: aprobado
                          ? const Color(0xFFBBF7D0)
                          : const Color(0xFFFFEDD5),
                    ),
                  ),
                  child: Text(
                    aprobado
                        ? '¡Excelente trabajo! Has aprobado.'
                        : 'Necesitas más práctica. Se requiere 70% para aprobar.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: aprobado
                          ? const Color(0xFF15803D)
                          : const Color(0xFFC2410C),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 32),

                // Stats Cards
                InkWell(
                  onTap: preguntasCorrectas.isNotEmpty
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PantallaRevisionPractica(
                                titulo: 'Preguntas Correctas',
                                preguntas: preguntasCorrectas,
                                esCorrectas: true,
                              ),
                            ),
                          );
                        }
                      : null,
                  child: _StatCard(
                    label: 'Correctas',
                    value: puntaje.toString(),
                    color: const Color(0xFF10B981),
                    bgColor: const Color(0xFFF0FDF4),
                    borderColor: const Color(0xFFBBF7D0),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: preguntasIncorrectas.isNotEmpty
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PantallaRevisionPractica(
                                titulo: 'Preguntas Incorrectas',
                                intentosFallidos: preguntasIncorrectas,
                                esCorrectas: false,
                              ),
                            ),
                          );
                        }
                      : null,
                  child: _StatCard(
                    label: 'Incorrectas',
                    value: incorrectas.toString(),
                    color: const Color(0xFFEF4444),
                    bgColor: const Color(0xFFFEF2F2),
                    borderColor: const Color(0xFFFECACA),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF), // Blue bg
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.access_time,
                      color: Color(0xFF3B82F6),
                      size: 24,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      esPracticaGuiada ? 'Tiempo transcurrido' : 'Tiempo',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: const Color(0xFF3B82F6),
                      ),
                    ),
                    Text(
                      _formatearTiempo(tiempoTranscurrido),
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onNuevaPractica,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.refresh, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Nueva Práctica',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onVolverInicio,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Volver al Inicio',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color bgColor;
  final Color borderColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                'Ver $label',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_ios, size: 14, color: color),
            ],
          ),
        ],
      ),
    );
  }
}

