import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'pantalla_balotario_audio_materia_detalle.dart';
import '../servicios/servicio_preguntas.dart';

class PantallaBalotarioAudioMaterias extends StatefulWidget {
  final String categoriaUsuario;

  const PantallaBalotarioAudioMaterias({
    super.key,
    required this.categoriaUsuario,
  });

  @override
  State<PantallaBalotarioAudioMaterias> createState() =>
      _PantallaBalotarioAudioMateriasState();
}

class _PantallaBalotarioAudioMateriasState
    extends State<PantallaBalotarioAudioMaterias> {
  final ServicioPreguntas _servicioPreguntas = ServicioPreguntas();
  final TextEditingController _busquedaController = TextEditingController();

  bool _cargando = true;
  List<String> _materias = const <String>[];
  Map<String, int> _conteoPorMateria = const <String, int>{};

  @override
  void initState() {
    super.initState();
    _cargarMaterias();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _cargarMaterias() async {
    setState(() {
      _cargando = true;
    });

    try {
      final conteo = await _servicioPreguntas.obtenerConteoPreguntasPorMateria(
        categoria: widget.categoriaUsuario,
      );
      final materias = conteo.keys.toList()..sort((a, b) => a.compareTo(b));

      if (!mounted) return;
      setState(() {
        _conteoPorMateria = conteo;
        _materias = materias;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _conteoPorMateria = const <String, int>{};
        _materias = const <String>[];
        _cargando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudieron cargar las materias por ahora.'),
        ),
      );
    }
  }

  List<String> get _materiasFiltradas {
    final query = _busquedaController.text.trim().toLowerCase();
    if (query.isEmpty) return _materias;
    return _materias
        .where((materia) => materia.toLowerCase().contains(query))
        .toList();
  }

  Widget _buildBusqueda() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _busquedaController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Buscar materias...',
            hintStyle: GoogleFonts.inter(
              color: Colors.grey.shade500,
              fontSize: 14,
            ),
            prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
          ),
        ),
      ),
    );
  }

  Widget _buildListaMaterias() {
    final materias = _materiasFiltradas;
    if (_materias.isEmpty) {
      return Center(
        child: Text(
          'No hay materias disponibles por ahora.',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: const Color(0xFF6B7280),
          ),
        ),
      );
    }
    if (materias.isEmpty) {
      return Center(
        child: Text(
          'No se encontraron materias.',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: const Color(0xFF6B7280),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      itemCount: materias.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final materia = materias[index];
        final total = _conteoPorMateria[materia] ?? 0;
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PantallaBalotarioAudioMateriaDetalle(
                    categoriaUsuario: widget.categoriaUsuario,
                    materia: materia,
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD1D5DB)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFEFF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.headphones_rounded,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          materia,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$total preguntas',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Color(0xFF6B7280),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(
          'Balotario en audio',
          style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildBusqueda(),
                Expanded(child: _buildListaMaterias()),
              ],
            ),
    );
  }
}
