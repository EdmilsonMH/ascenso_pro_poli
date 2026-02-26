import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Panel de configuración para seleccionar rango de preguntas a reproducir
class PanelConfiguracionAudio extends StatelessWidget {
  final String rangoAudio; // 'todo' o 'rango'
  final int preguntaDesde;
  final int preguntaHasta;
  final int totalPreguntas;
  final ValueChanged<String> onRangoChanged;
  final ValueChanged<int> onDesdeChanged;
  final ValueChanged<int> onHastaChanged;
  final VoidCallback onReproducir;

  const PanelConfiguracionAudio({
    super.key,
    required this.rangoAudio,
    required this.preguntaDesde,
    required this.preguntaHasta,
    required this.totalPreguntas,
    required this.onRangoChanged,
    required this.onDesdeChanged,
    required this.onHastaChanged,
    required this.onReproducir,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAE8FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9D5FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Escucha las preguntas, alternativas y respuestas correctas',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF7E22CE),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Título de opciones
          Text(
            'Rango de reproducción:',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF6B21A8),
            ),
          ),
          const SizedBox(height: 8),

          // Opción: Todas las preguntas
          RadioListTile<String>(
            value: 'todo',
            groupValue: rangoAudio,
            onChanged: (value) {
              if (value != null) onRangoChanged(value);
            },
            title: Text(
              'Todas las preguntas ($totalPreguntas)',
              style: GoogleFonts.inter(fontSize: 13),
            ),
            fillColor: WidgetStateProperty.all(const Color(0xFFA855F7)),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),

          // Opción: Rango personalizado
          RadioListTile<String>(
            value: 'rango',
            groupValue: rangoAudio,
            onChanged: (value) {
              if (value != null) onRangoChanged(value);
            },
            title: Text(
              'Rango personalizado',
              style: GoogleFonts.inter(fontSize: 13),
            ),
            fillColor: WidgetStateProperty.all(const Color(0xFFA855F7)),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),

          // Campos de rango (solo si está seleccionado 'rango')
          if (rangoAudio == 'rango') ...[
            const SizedBox(height: 12),
            _buildCamposRango(context),
            const SizedBox(height: 8),
            _buildInfoRango(),
          ],

          const SizedBox(height: 16),

          // Botón reproducir
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onReproducir,
              icon: const Icon(Icons.play_circle_fill),
              label: Text(
                rangoAudio == 'todo' ? 'Reproducir Todas' : 'Reproducir Rango',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA855F7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCamposRango(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9D5FF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildCampoNumero(
              etiqueta: 'Desde:',
              hint: '1',
              onChanged: (value) {
                final num = int.tryParse(value);
                if (num != null && num >= 1 && num <= totalPreguntas) {
                  onDesdeChanged(num);
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildCampoNumero(
              etiqueta: 'Hasta:',
              hint: '$totalPreguntas',
              onChanged: (value) {
                final num = int.tryParse(value);
                if (num != null &&
                    num >= preguntaDesde &&
                    num <= totalPreguntas) {
                  onHastaChanged(num);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampoNumero({
    required String etiqueta,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: const Color(0xFF6B21A8),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            isDense: true,
          ),
          style: GoogleFonts.inter(fontSize: 13),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildInfoRango() {
    final cantidadPreguntas = preguntaHasta - preguntaDesde + 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Se reproducirán $cantidadPreguntas preguntas',
          style: GoogleFonts.inter(
            fontSize: 11,
            color: const Color(0xFF7E22CE),
            fontStyle: FontStyle.italic,
          ),
        ),
        Text(
          'Total: $totalPreguntas',
          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
