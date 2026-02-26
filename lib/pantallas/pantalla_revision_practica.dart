import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../modelos/modelo_pregunta.dart';
import '../servicios/servicio_progreso.dart';
import 'pantalla_practica.dart';

class PantallaRevisionPractica extends StatelessWidget {
  final String titulo;
  final List<Pregunta>? preguntas;
  final List<IntentoFallido>? intentosFallidos;
  final bool esCorrectas;
  final bool mostrarBotonPracticarFallos;
  final Map<String, EstadisticaPregunta> estadisticasPorPregunta;

  const PantallaRevisionPractica({
    super.key,
    required this.titulo,
    this.preguntas,
    this.intentosFallidos,
    required this.esCorrectas,
    this.mostrarBotonPracticarFallos = false,
    this.estadisticasPorPregunta = const {},
  });

  List<Pregunta> get _preguntasParaPractica {
    final lista = <Pregunta>[];
    final vistos = <String>{};
    for (final intento in intentosFallidos ?? const <IntentoFallido>[]) {
      final id = intento.pregunta.id;
      if (id.isEmpty) continue;
      if (vistos.add(id)) lista.add(intento.pregunta);
    }
    return lista;
  }

  void _iniciarPracticaFallos(BuildContext context) {
    final preguntasPractica = _preguntasParaPractica;
    if (preguntasPractica.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaPractica(
          preguntas: preguntasPractica,
          esModoPractica: true,
          esRanking: false,
          avanzarSoloConBotonEnPractica: true,
          tiempoLimiteSegundos: preguntasPractica.length * 72,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool mostrarBotonPracticar =
        !esCorrectas &&
        mostrarBotonPracticarFallos &&
        (intentosFallidos?.isNotEmpty ?? false);
    final double paddingInferiorContenido =
        mostrarBotonPracticar
            ? 120 + MediaQuery.of(context).padding.bottom
            : 24;

    final Color colorPrincipal = esCorrectas
        ? const Color(0xFF10B981) // Verde
        : const Color(0xFFEF4444); // Rojo

    final Color colorFondo = esCorrectas
        ? const Color(0xFFF0FDF4) // Verde claro
        : const Color(0xFFFEF2F2); // Rojo claro

    final int totalPreguntas = esCorrectas
        ? (preguntas?.length ?? 0)
        : (intentosFallidos?.length ?? 0);

    return Scaffold(
      backgroundColor: colorFondo,
      appBar: AppBar(
        title: Text(
          titulo,
          style: GoogleFonts.inter(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, paddingInferiorContenido),
          child: Column(
            children: [
              // Header Section
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      esCorrectas
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                      color: colorPrincipal,
                      size: 64,
                    ),
                  ),
                  Text(
                    titulo,
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w400,
                      color: colorPrincipal,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    esCorrectas
                        ? 'Respondiste correctamente $totalPreguntas ${totalPreguntas == 1 ? 'pregunta' : 'preguntas'} en esta práctica'
                        : 'Fallaste $totalPreguntas ${totalPreguntas == 1 ? 'pregunta' : 'preguntas'} en esta práctica',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                ],
              ),

              // Questions List
              if (esCorrectas && preguntas != null)
                ...preguntas!.map(
                  (pregunta) => _PreguntaReviewCard(
                    pregunta: pregunta,
                    esCorrecta: true,
                    estadistica: estadisticasPorPregunta[pregunta.id],
                  ),
                ),

              if (!esCorrectas && intentosFallidos != null)
                ...intentosFallidos!.map(
                  (intento) => _PreguntaErrorCard(
                    intento: intento,
                    estadistica: estadisticasPorPregunta[intento.pregunta.id],
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: mostrarBotonPracticar
          ? FloatingActionButton.extended(
              onPressed: () => _iniciarPracticaFallos(context),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                'Practicar Fallos de esta sesion',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class _PreguntaReviewCard extends StatelessWidget {
  final Pregunta pregunta;
  final bool esCorrecta;
  final EstadisticaPregunta? estadistica;

  const _PreguntaReviewCard({
    required this.pregunta,
    required this.esCorrecta,
    this.estadistica,
  });

  String _idCorto(String id) {
    if (id.isEmpty) return 'SIN-ID';
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(
            color: esCorrecta
                ? const Color(0xFF10B981)
                : const Color(0xFFEF4444),
            width: 4,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tags Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: esCorrecta
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#${_idCorto(pregunta.id)}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: esCorrecta
                        ? const Color(0xFF15803D)
                        : const Color(0xFF991B1B),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    pregunta.materia,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (estadistica != null) ...[
                const SizedBox(width: 8),
                _BadgeContador(
                  valor: estadistica!.aciertosVisibles,
                  icono: Icons.check_circle_outline,
                  colorFondo: const Color(0xFFDCFCE7),
                  colorTexto: const Color(0xFF15803D),
                ),
                const SizedBox(width: 4),
                _BadgeContador(
                  valor: estadistica!.fallosVisibles,
                  icono: Icons.cancel_outlined,
                  colorFondo: const Color(0xFFFEE2E2),
                  colorTexto: const Color(0xFFB91C1C),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            pregunta.texto,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Alternativas:',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          ...List.generate(pregunta.opciones.length, (index) {
            final esRespuestaCorrecta =
                index == pregunta.indiceRespuestaCorrecta;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: esRespuestaCorrecta
                      ? const Color(0xFF10B981)
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '${String.fromCharCode(65 + index)}. ',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      pregunta.opciones[index],
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  if (esRespuestaCorrecta)
                    const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF10B981),
                      size: 20,
                    ),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),

          // Explanation Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Explicacion:',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pregunta.explicacion.trim().isNotEmpty
                      ? pregunta.explicacion
                      : 'No hay explicacion disponible para esta pregunta.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF1E3A8A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreguntaErrorCard extends StatelessWidget {
  final IntentoFallido intento;
  final EstadisticaPregunta? estadistica;

  const _PreguntaErrorCard({required this.intento, this.estadistica});

  String _idCorto(String id) {
    if (id.isEmpty) return 'SIN-ID';
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  @override
  Widget build(BuildContext context) {
    final pregunta = intento.pregunta;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          left: BorderSide(color: Color(0xFFEF4444), width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tags Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#${_idCorto(pregunta.id)}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF991B1B),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    pregunta.materia,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (estadistica != null) ...[
                const SizedBox(width: 8),
                _BadgeContador(
                  valor: estadistica!.aciertosVisibles,
                  icono: Icons.check_circle_outline,
                  colorFondo: const Color(0xFFDCFCE7),
                  colorTexto: const Color(0xFF15803D),
                ),
                const SizedBox(width: 4),
                _BadgeContador(
                  valor: estadistica!.fallosVisibles,
                  icono: Icons.cancel_outlined,
                  colorFondo: const Color(0xFFFEE2E2),
                  colorTexto: const Color(0xFFB91C1C),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            pregunta.texto,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Alternativas:',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          ...List.generate(pregunta.opciones.length, (index) {
            final esCorrecta = index == pregunta.indiceRespuestaCorrecta;
            final fueSeleccionadaIncorrecta =
                index == intento.indiceIncorrectoSeleccionado;

            Color itemBorderColor = Colors.grey.shade300;
            Color itemBgColor = Colors.white;
            IconData? itemIcon;
            Color itemIconColor = Colors.transparent;

            if (esCorrecta) {
              itemBorderColor = const Color(0xFF10B981);
              itemIcon = Icons.check_circle_outline;
              itemIconColor = const Color(0xFF10B981);
            } else if (fueSeleccionadaIncorrecta) {
              itemBorderColor = const Color(0xFFEF4444);
              itemBgColor = const Color(0xFFFEF2F2);
              itemIcon = Icons.cancel_outlined;
              itemIconColor = const Color(0xFFEF4444);
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: itemBgColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: itemBorderColor),
              ),
              child: Row(
                children: [
                  Text(
                    '${String.fromCharCode(65 + index)}. ',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      pregunta.opciones[index],
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  if (itemIcon != null)
                    Icon(itemIcon, color: itemIconColor, size: 20),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),

          // Explanation Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Explicacion:',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pregunta.explicacion.trim().isNotEmpty
                      ? pregunta.explicacion
                      : 'No hay explicacion disponible para esta pregunta.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF1E3A8A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeContador extends StatelessWidget {
  final int valor;
  final IconData icono;
  final Color colorFondo;
  final Color colorTexto;

  const _BadgeContador({
    required this.valor,
    required this.icono,
    required this.colorFondo,
    required this.colorTexto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: colorFondo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: colorTexto),
          const SizedBox(width: 2),
          Text(
            '$valor',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colorTexto,
            ),
          ),
        ],
      ),
    );
  }
}
