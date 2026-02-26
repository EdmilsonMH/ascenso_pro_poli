import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../servicios/auth_service.dart';
import '../tema/tema_aplicacion.dart';
import 'pantalla_principal.dart';

class PantallaCompletarPerfil extends StatefulWidget {
  final String? categoriaInicial;

  const PantallaCompletarPerfil({super.key, this.categoriaInicial});

  @override
  State<PantallaCompletarPerfil> createState() =>
      _PantallaCompletarPerfilState();
}

class _PantallaCompletarPerfilState extends State<PantallaCompletarPerfil> {
  String _categoriaSeleccionada = 'Oficiales PNP';
  int _metaDiaria = 30;
  bool _isSaving = false;
  final _gradoController = TextEditingController();

  final List<String> _categorias = [
    'Oficiales PNP',
    'Suboficiales PNP',
    'ETS PNP',
    'EO PNP',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.categoriaInicial != null &&
        _categorias.contains(widget.categoriaInicial)) {
      _categoriaSeleccionada = widget.categoriaInicial!;
    }
  }

  @override
  void dispose() {
    _gradoController.dispose();
    super.dispose();
  }

  Future<void> _handleFinish() async {
    final gradoActual = _gradoController.text.trim();
    if (gradoActual.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ingresa tu grado actual'),
          ),
        );
      }
      return;
    }

    setState(() => _isSaving = true);

    try {
      final success = await AuthService.updateProfile({
        'categoria': _categoriaSeleccionada,
        'meta_diaria_minutos': _metaDiaria,
        'grado_actual': gradoActual,
      });

      if (success && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PantallaPrincipal(categoriaUsuario: _categoriaSeleccionada),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaAplicacion.colorFondo,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icono
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: TemaAplicacion.colorPrimario.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1,
                      color: TemaAplicacion.colorPrimario,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Título
                  Text(
                    '¡Casi listo!',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: TemaAplicacion.textoPrimario,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Personaliza tu experiencia de estudio para comenzar.',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: TemaAplicacion.textoSecundario,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Selector de Categoría
                  Text(
                    '¿A qué categoría postulas?',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: TemaAplicacion.textoPrimario,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _categoriaSeleccionada,
                        isExpanded: true,
                        items: _categorias.map((cat) {
                          return DropdownMenuItem(value: cat, child: Text(cat));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null)
                            setState(() => _categoriaSeleccionada = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Grado actual
                  Text(
                    'Grado actual',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: TemaAplicacion.textoPrimario,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _gradoController,
                    decoration: InputDecoration(
                      hintText: 'Ej: Teniente, SO2, SOT1',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: TemaAplicacion.colorPrimario,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Meta Diaria
                  Text(
                    'Meta diaria de estudio (minutos)',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: TemaAplicacion.textoPrimario,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _metaDiaria.toDouble(),
                          min: 15,
                          max: 180,
                          divisions: 11,
                          label: '$_metaDiaria min',
                          activeColor: TemaAplicacion.colorPrimario,
                          onChanged: (val) {
                            setState(() => _metaDiaria = val.toInt());
                          },
                        ),
                      ),
                      Text(
                        '$_metaDiaria min',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),

                  // Botón Finalizar
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _handleFinish,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TemaAplicacion.colorPrimario,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              'Comenzar a Estudiar',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
