import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Bottom sheet reutilizable para filtrar por materias.
/// Usado en pestana_estudio, pantalla_preguntas_acertadas,
/// pantalla_preguntas_incorrectas.
class BottomSheetFiltros extends StatefulWidget {
  final List<String> todasLasMaterias;
  final List<String> materiasSeleccionadasInicial;
  final Color colorPrimario;
  final String textoBoton;
  final Function(List<String>) onAplicar;

  const BottomSheetFiltros({
    super.key,
    required this.todasLasMaterias,
    required this.materiasSeleccionadasInicial,
    this.colorPrimario = const Color(0xFF3B82F6),
    this.textoBoton = 'Aplicar Filtros',
    required this.onAplicar,
  });

  @override
  State<BottomSheetFiltros> createState() => _BottomSheetFiltrosState();
}

class _BottomSheetFiltrosState extends State<BottomSheetFiltros> {
  late List<String> _materiasSeleccionadas;

  @override
  void initState() {
    super.initState();
    _materiasSeleccionadas = List.from(widget.materiasSeleccionadasInicial);
  }

  @override
  Widget build(BuildContext context) {
    final alturaMaxima = MediaQuery.of(context).size.height * 0.85;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: alturaMaxima,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Indicador de arrastre.
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
              const SizedBox(height: 16),

              Text(
                'Filtrar por Materias',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: ListView(
                  children: [
                    CheckboxListTile(
                      value:
                          widget.todasLasMaterias.isNotEmpty &&
                          _materiasSeleccionadas.length ==
                              widget.todasLasMaterias.length,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            _materiasSeleccionadas = List.from(
                              widget.todasLasMaterias,
                            );
                          } else {
                            _materiasSeleccionadas.clear();
                          }
                        });
                      },
                      title: Text(
                        'Todas las materias',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      fillColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? widget.colorPrimario
                            : null,
                      ),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    ...widget.todasLasMaterias.map((materia) {
                      final isSelected = _materiasSeleccionadas.contains(
                        materia,
                      );
                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              _materiasSeleccionadas.add(materia);
                            } else {
                              _materiasSeleccionadas.remove(materia);
                            }
                          });
                        },
                        title: Text(
                          materia,
                          style: GoogleFonts.inter(fontSize: 14),
                        ),
                        fillColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? widget.colorPrimario
                              : null,
                        ),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_materiasSeleccionadas.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Selecciona al menos una materia'),
                        ),
                      );
                      return;
                    }
                    widget.onAplicar(_materiasSeleccionadas);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.colorPrimario,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    widget.textoBoton,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Funcion helper para mostrar el bottom sheet de filtros.
void mostrarBottomSheetFiltros({
  required BuildContext context,
  required List<String> todasLasMaterias,
  required List<String> materiasSeleccionadas,
  required Function(List<String>) onAplicar,
  Color colorPrimario = const Color(0xFF3B82F6),
  String textoBoton = 'Aplicar Filtros',
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext bc) {
      return BottomSheetFiltros(
        todasLasMaterias: todasLasMaterias,
        materiasSeleccionadasInicial: materiasSeleccionadas,
        colorPrimario: colorPrimario,
        textoBoton: textoBoton,
        onAplicar: onAplicar,
      );
    },
  );
}
