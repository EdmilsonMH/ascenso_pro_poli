import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../modelos/modelo_pregunta.dart';
import '../tema/tema_aplicacion.dart';

/// Tarjeta reutilizable para mostrar una pregunta con alternativas.
class TarjetaPregunta extends StatelessWidget {
  final Pregunta pregunta;
  final Color colorBordeIzquierdo;
  final Color colorEtiquetaId;
  final Color colorTextoEtiquetaId;
  final int? indiceSeleccionadoIncorrecto;
  final int? numeroOrden;
  final int? aciertosCount;
  final int? fallosCount;

  const TarjetaPregunta({
    super.key,
    required this.pregunta,
    this.colorBordeIzquierdo = Colors.transparent,
    this.colorEtiquetaId = const Color(0xFFF3F4F6),
    this.colorTextoEtiquetaId = Colors.grey,
    this.indiceSeleccionadoIncorrecto,
    this.numeroOrden,
    this.aciertosCount,
    this.fallosCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: colorBordeIzquierdo != Colors.transparent
            ? Border(left: BorderSide(color: colorBordeIzquierdo, width: 4))
            : Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (colorBordeIzquierdo == Colors.transparent)
            const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              pregunta.texto,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: TemaAplicacion.textoPrimario,
              ),
            ),
          ),
          _buildOpciones(),
          const SizedBox(height: 16),
          _buildCajaRespuestaCorrecta(),
          const SizedBox(height: 12),
          _buildCajaExplicacion(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final idCorto = pregunta.id.length > 8
        ? pregunta.id.substring(0, 8)
        : pregunta.id;
    final etiquetaId = numeroOrden != null ? '#$numeroOrden' : '#$idCorto';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 90),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colorEtiquetaId,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              etiquetaId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colorTextoEtiquetaId,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                pregunta.materia,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (aciertosCount != null || fallosCount != null) ...[
            const SizedBox(width: 8),
            _buildBadgeContador(
              colorFondo: const Color(0xFFD1FAE5),
              colorTexto: const Color(0xFF065F46),
              icono: Icons.check_circle,
              valor: aciertosCount ?? 0,
            ),
            const SizedBox(width: 6),
            _buildBadgeContador(
              colorFondo: const Color(0xFFFEE2E2),
              colorTexto: const Color(0xFF991B1B),
              icono: Icons.cancel,
              valor: fallosCount ?? 0,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadgeContador({
    required Color colorFondo,
    required Color colorTexto,
    required IconData icono,
    required int valor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colorFondo,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: colorTexto),
          const SizedBox(width: 3),
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

  Widget _buildOpciones() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alternativas:',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          ...List.generate(pregunta.opciones.length, (index) {
            final esCorrecta = index == pregunta.indiceRespuestaCorrecta;
            final esSeleccionadaIncorrecta =
                indiceSeleccionadoIncorrecto != null &&
                index == indiceSeleccionadoIncorrecto;

            Color colorBorde = Colors.grey.shade300;
            Color colorFondo = Colors.white;
            IconData? icono;
            Color? colorIcono;

            if (esCorrecta) {
              colorBorde = const Color(0xFF10B981);
              icono = Icons.check_circle_outline;
              colorIcono = const Color(0xFF10B981);
            } else if (esSeleccionadaIncorrecta) {
              colorBorde = const Color(0xFFEF4444);
              colorFondo = const Color(0xFFFEF2F2);
              icono = Icons.cancel_outlined;
              colorIcono = const Color(0xFFEF4444);
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorFondo,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorBorde),
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
                        color: TemaAplicacion.textoPrimario,
                      ),
                    ),
                  ),
                  if (icono != null) Icon(icono, color: colorIcono, size: 20),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCajaRespuestaCorrecta() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: Color(0xFF16A34A),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF15803D),
                ),
                children: [
                  const TextSpan(
                    text: 'Respuesta Correcta: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text:
                        '${String.fromCharCode(65 + pregunta.indiceRespuestaCorrecta)}. ${pregunta.opciones[pregunta.indiceRespuestaCorrecta]}',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCajaExplicacion() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
            pregunta.explicacion,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF1E3A8A),
            ),
          ),
        ],
      ),
    );
  }
}
