import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ConfiguracionAudioSheet extends StatefulWidget {
  final int totalPreguntas;
  final Color themeColor;
  final Function(int start, int end) onAplicar;

  const ConfiguracionAudioSheet({
    super.key,
    required this.totalPreguntas,
    required this.themeColor,
    required this.onAplicar,
  });

  @override
  State<ConfiguracionAudioSheet> createState() =>
      _ConfiguracionAudioSheetState();
}

class _ConfiguracionAudioSheetState extends State<ConfiguracionAudioSheet> {
  int _opcionSeleccionada = 0; // 0: Todas, 1: Rango
  late TextEditingController _desdeController;
  late TextEditingController _hastaController;

  @override
  void initState() {
    super.initState();
    _desdeController = TextEditingController(text: '1');
    _hastaController = TextEditingController(
      text: widget.totalPreguntas.toString(),
    );
  }

  @override
  void dispose() {
    _desdeController.dispose();
    _hastaController.dispose();
    super.dispose();
  }

  void _validarYAplicar() {
    if (_opcionSeleccionada == 0) {
      widget.onAplicar(1, widget.totalPreguntas);
      Navigator.pop(context);
    } else {
      int? inicio = int.tryParse(_desdeController.text);
      int? fin = int.tryParse(_hastaController.text);

      if (inicio == null || fin == null) {
        _mostrarError("Ingresa números válidos");
        return;
      }

      if (inicio < 1) inicio = 1;
      if (fin > widget.totalPreguntas) fin = widget.totalPreguntas;

      if (inicio > fin) {
        _mostrarError("El inicio no puede ser mayor que el final");
        return;
      }

      widget.onAplicar(inicio, fin);
      Navigator.pop(context);
    }
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    // Definimos un estilo base para radio buttons
    // Usamos el color del tema pasado por parámetro

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Configuración de Audio',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: const Color(
                0xFF6B21A8,
              ), // Purple for title as in screenshots (or generic)
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Rango de reproducción:',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF6B21A8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),

          // Opcion 1: Todas
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Todas las preguntas (${widget.totalPreguntas})',
              style: GoogleFonts.inter(fontSize: 14),
            ),
            leading: Radio<int>(
              value: 0,
              groupValue: _opcionSeleccionada,
              activeColor: widget.themeColor,
              onChanged: (val) {
                setState(() => _opcionSeleccionada = val!);
              },
            ),
            onTap: () => setState(() => _opcionSeleccionada = 0),
          ),

          // Opcion 2: Rango personalizado
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Rango personalizado',
              style: GoogleFonts.inter(fontSize: 14),
            ),
            leading: Radio<int>(
              value: 1,
              groupValue: _opcionSeleccionada,
              activeColor: widget.themeColor,
              onChanged: (val) {
                setState(() => _opcionSeleccionada = val!);
              },
            ),
            onTap: () => setState(() => _opcionSeleccionada = 1),
          ),

          if (_opcionSeleccionada == 1) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Desde:",
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: widget.themeColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _desdeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Hasta:",
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: widget.themeColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _hastaController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              "Se reproducirán ${_calcularCantidad()} preguntas",
              style: GoogleFonts.inter(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _validarYAplicar,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA855F7), // Primary Purple
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Aplicar Configuración',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          // Extra spacing for keyboard + system navigation area
          SizedBox(
            height:
                16 +
                MediaQuery.of(context).padding.bottom +
                MediaQuery.of(context).viewInsets.bottom,
          ),
        ],
      ),
    );
  }

  int _calcularCantidad() {
    int? inicio = int.tryParse(_desdeController.text) ?? 1;
    int? fin = int.tryParse(_hastaController.text) ?? widget.totalPreguntas;
    if (inicio < 1) inicio = 1;
    if (fin > widget.totalPreguntas) fin = widget.totalPreguntas;
    if (inicio > fin) return 0;
    return fin - inicio + 1;
  }
}
