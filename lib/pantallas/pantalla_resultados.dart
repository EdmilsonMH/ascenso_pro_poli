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
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
  }

  @override
  Widget build(BuildContext context) {
    final porcentaje = (puntaje / totalPreguntas) * 100;
    final aprobado = porcentaje >= 70;
    final incorrectas = totalPreguntas - puntaje;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compacto = constraints.maxHeight < 760;
              final muyCompacto = constraints.maxHeight < 700;

              final iconSize = muyCompacto ? 44.0 : 52.0;
              final tituloSize = muyCompacto ? 18.0 : 20.0;
              final scoreSize = muyCompacto ? 58.0 : 62.0;
              final gapXs = muyCompacto ? 3.0 : 4.0;
              final gapSm = compacto ? 6.0 : 8.0;
              final gapMd = compacto ? 8.0 : 10.0;
              final gapLg = compacto ? 10.0 : 12.0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        Icon(
                          Icons.emoji_events_outlined,
                          size: iconSize,
                          color: const Color(0xFF9CA3AF),
                        ),
                        SizedBox(height: gapSm),
                        Text(
                          '\u00A1Practica Completada!',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: tituloSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: gapXs),
                        Text(
                          'Has finalizado tu examen de practica',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (cuentaParaRanking) ...[
                          SizedBox(height: gapSm),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: compacto ? 8 : 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEFCE8),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFFDE047),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.emoji_events_outlined,
                                  color: Color(0xFFA16207),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Esta practica cuenta para el ranking porque completaste 100 preguntas con todas las materias.',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: const Color(0xFFA16207),
                                      fontWeight: FontWeight.w600,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        SizedBox(height: gapLg),
                        Text(
                          '${porcentaje.toStringAsFixed(1)}%',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: scoreSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            height: 0.95,
                          ),
                        ),
                        SizedBox(height: gapXs),
                        Text(
                          '$puntaje de $totalPreguntas respuestas correctas',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        SizedBox(height: gapLg),
                        if (!esPracticaGuiada) ...[
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                              vertical: compacto ? 9 : 10,
                              horizontal: 12,
                            ),
                            decoration: BoxDecoration(
                              color: aprobado
                                  ? const Color(0xFFD9EEE5)
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
                                  ? 'Excelente trabajo. Has aprobado.'
                                  : 'Necesitas mas practica. Se requiere 70% para aprobar.',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: aprobado
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFFC2410C),
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          SizedBox(height: gapMd),
                          InkWell(
                            onTap: preguntasCorrectas.isNotEmpty
                                ? () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            PantallaRevisionPractica(
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
                              color: const Color(0xFF237D57),
                              bgColor: const Color(0xFFD9EEE5),
                              borderColor: const Color(0xFFBBF7D0),
                              compacto: compacto,
                            ),
                          ),
                          SizedBox(height: gapMd),
                          InkWell(
                            onTap: preguntasIncorrectas.isNotEmpty
                                ? () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            PantallaRevisionPractica(
                                              titulo: 'Preguntas Incorrectas',
                                              intentosFallidos:
                                                  preguntasIncorrectas,
                                              esCorrectas: false,
                                            ),
                                      ),
                                    );
                                  }
                                : null,
                            child: _StatCard(
                              label: 'Incorrectas',
                              value: incorrectas.toString(),
                              color: const Color(0xFFAD3636),
                              bgColor: const Color(0xFFF6E0E0),
                              borderColor: const Color(0xFFB85B5B),
                              compacto: compacto,
                            ),
                          ),
                          SizedBox(height: gapMd),
                        ],
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            width: muyCompacto ? 98 : 108,
                            padding: EdgeInsets.symmetric(
                              vertical: compacto ? 8 : 10,
                              horizontal: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDEE6EA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF5A8F8A),
                              ),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  color: Color(0xFF1E6B63),
                                  size: 22,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  esPracticaGuiada
                                      ? 'Tiempo transcurrido'
                                      : 'Tiempo',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF1E6B63),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatearTiempo(tiempoTranscurrido),
                                  style: GoogleFonts.inter(
                                    fontSize: muyCompacto ? 16 : 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onNuevaPractica,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.refresh, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Nueva Practica',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onVolverInicio,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black,
                            side: BorderSide(color: Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Volver al inicio',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
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
  final bool compacto;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    required this.borderColor,
    required this.compacto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: compacto ? 10 : 12,
        horizontal: 14,
      ),
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
                  fontSize: compacto ? 34 : 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  height: 0.95,
                ),
              ),
            ],
          ),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  children: [
                    Text(
                      'Ver $label',
                      style: GoogleFonts.inter(
                        fontSize: compacto ? 13 : 14,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios, size: 14, color: color),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
