import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audio_service/audio_service.dart';
import 'package:ascenso_pro_poli/tema/tema_aplicacion.dart';
import 'package:ascenso_pro_poli/modelos/modelo_pregunta.dart';
import 'package:ascenso_pro_poli/widgets/widgets.dart';
import 'package:ascenso_pro_poli/servicios/audio_handler.dart';
import 'package:ascenso_pro_poli/servicios/servicio_preguntas.dart';
import 'package:ascenso_pro_poli/servicios/servicio_progreso.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../widgets/barra_superior.dart';

class PestanaEstudio extends StatefulWidget {
  final String categoriaUsuario;

  const PestanaEstudio({super.key, required this.categoriaUsuario});

  @override
  State<PestanaEstudio> createState() => _PestanaEstudioState();
}

class _PestanaEstudioState extends State<PestanaEstudio> {
  final ServicioPreguntas _servicioPreguntas = ServicioPreguntas();
  final ServicioProgreso _servicioProgreso = ServicioProgreso();
  final TextEditingController _controladorBusqueda = TextEditingController();
  final TextEditingController _controladorBusquedaMaterias =
      TextEditingController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  List<Pregunta> _preguntasTotales = []; // Cache all
  List<Pregunta> _preguntasFiltradas = [];
  List<String> _todasLasMaterias = [];
  List<String> _materiasSeleccionadas = [];
  String? _materiaActiva;
  bool _mostrarReproductor = false;
  bool _cargando = true;

  // Estado para detectar cambios en reproducción
  bool _estabaReproduciendo = false;
  int _ultimaPreguntaReproducida = 0;

  // Control de rango de audio
  String _rangoAudio = 'todo';
  int _preguntaDesde = 1;
  int _preguntaHasta = 1;
  Map<String, EstadisticaPregunta> _estadisticasPorPregunta = {};

  @override
  void initState() {
    super.initState();
    _cargarPreguntas();
  }

  Future<void> _cargarPreguntas() async {
    try {
      final preguntas = await _servicioPreguntas
          .obtenerTodas(categoria: widget.categoriaUsuario)
          .timeout(const Duration(seconds: 20));
      final materias = preguntas.map((p) => p.materia).toSet().toList()
        ..sort((a, b) => a.compareTo(b));
      final estadisticas = await _servicioProgreso
          .obtenerEstadisticasPreguntas(
            preguntaIds: preguntas.map((p) => p.id).toList(),
          )
          .timeout(const Duration(seconds: 20));

      if (mounted) {
        setState(() {
          _preguntasTotales = preguntas;
          _preguntasFiltradas = preguntas;
          _todasLasMaterias = materias;
          _materiasSeleccionadas = List.from(materias);
          _materiaActiva = null;
          _preguntaHasta = preguntas.isNotEmpty ? preguntas.length : 1;
          _estadisticasPorPregunta = estadisticas;
          _cargando = false;
        });
      }
    } catch (e) {
      debugPrint('PestanaEstudio._cargarPreguntas error: $e');
      if (!mounted) return;
      setState(() {
        _preguntasTotales = const [];
        _preguntasFiltradas = const [];
        _todasLasMaterias = const [];
        _materiasSeleccionadas = const [];
        _materiaActiva = null;
        _preguntaHasta = 1;
        _estadisticasPorPregunta = const {};
        _cargando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudieron cargar las preguntas por ahora.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controladorBusqueda.dispose();
    _controladorBusquedaMaterias.dispose();
    // _scrollController.dispose();
    super.dispose();
  }

  List<Pregunta> _obtenerPreguntasParaReproduccion() {
    if (_rangoAudio == 'todo') return _preguntasFiltradas;

    int inicio = _preguntaDesde - 1;
    int fin = _preguntaHasta;

    if (inicio < 0) inicio = 0;
    if (inicio >= _preguntasFiltradas.length) {
      inicio = _preguntasFiltradas.isNotEmpty
          ? _preguntasFiltradas.length - 1
          : 0;
    }

    if (fin > _preguntasFiltradas.length) fin = _preguntasFiltradas.length;
    if (fin < inicio) fin = inicio;

    if (inicio >= fin) return [];

    return _preguntasFiltradas.sublist(inicio, fin);
  }

  void _filtrarPreguntas(String consulta) {
    setState(() {
      var preguntas = _preguntasTotales;

      preguntas = preguntas
          .where((p) => _materiasSeleccionadas.contains(p.materia))
          .toList();

      if (consulta.isNotEmpty) {
        preguntas = preguntas
            .where(
              (p) =>
                  p.texto.toLowerCase().contains(consulta.toLowerCase()) ||
                  p.materia.toLowerCase().contains(consulta.toLowerCase()),
            )
            .toList();
      }

      _preguntasFiltradas = preguntas;
      if (_preguntasFiltradas.isEmpty) {
        _preguntaDesde = 1;
        _preguntaHasta = 1;
      } else {
        _preguntaDesde = _preguntaDesde.clamp(1, _preguntasFiltradas.length);
        _preguntaHasta = _preguntaHasta.clamp(
          _preguntaDesde,
          _preguntasFiltradas.length,
        );
      }
    });
  }

  void _aplicarFiltros() {
    _filtrarPreguntas(_controladorBusqueda.text);
  }

  void _detenerReproduccion() {
    audioHandler?.stop();
    _estabaReproduciendo = false;
  }

  bool get _enVistaMaterias => _materiaActiva == null;

  bool manejarBackInterno() {
    if (_enVistaMaterias) return false;
    _volverAMaterias();
    return true;
  }

  void restablecerVistaMaterias() {
    if (_enVistaMaterias) return;
    _volverAMaterias();
  }

  void _abrirMateria(String materia) {
    _detenerReproduccion();
    _controladorBusqueda.clear();
    setState(() {
      _materiaActiva = materia;
      _materiasSeleccionadas = [materia];
      _mostrarReproductor = false;
    });
    _filtrarPreguntas('');
  }

  void _volverAMaterias() {
    _detenerReproduccion();
    _controladorBusqueda.clear();
    setState(() {
      _materiaActiva = null;
      _materiasSeleccionadas = List.from(_todasLasMaterias);
      _mostrarReproductor = false;
    });
    _filtrarPreguntas('');
  }

  Map<String, int> _contarPreguntasPorMateria() {
    final conteo = <String, int>{};
    for (final pregunta in _preguntasTotales) {
      conteo[pregunta.materia] = (conteo[pregunta.materia] ?? 0) + 1;
    }
    return conteo;
  }

  List<String> get _materiasFiltradasPorBusqueda {
    final query = _controladorBusquedaMaterias.text.trim().toLowerCase();
    if (query.isEmpty) return _todasLasMaterias;
    return _todasLasMaterias
        .where((materia) => materia.toLowerCase().contains(query))
        .toList();
  }

  Widget _buildBarraBusquedaMaterias() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      color: Colors.white,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _controladorBusquedaMaterias,
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

  Widget _buildVistaMaterias() {
    final conteoPorMateria = _contarPreguntasPorMateria();
    final materiasFiltradas = _materiasFiltradasPorBusqueda;

    if (_todasLasMaterias.isEmpty) {
      return const Center(
        child: Text('No hay materias disponibles por ahora.'),
      );
    }

    return Column(
      children: [
        _buildBarraBusquedaMaterias(),
        Expanded(
          child: materiasFiltradas.isEmpty
              ? Center(
                  child: Text(
                    'No se encontraron materias.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                  itemCount: materiasFiltradas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final materia = materiasFiltradas[index];
                    final total = conteoPorMateria[materia] ?? 0;

                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _abrirMateria(materia),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
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
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.menu_book_rounded,
                                  color: Color(0xFF1D4ED8),
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
                ),
        ),
      ],
    );
  }

  // Hacer scroll usando la nueva librería
  void _scrollAPregunta(int indice) {
    if (indice < 0 || indice >= _preguntasFiltradas.length) return;

    // Solo intentamos si el controlador está adjunto (la lista está visible)
    if (_itemScrollController.isAttached) {
      debugPrint('DEBUG: Scroll directo a indice $indice');
      _itemScrollController.scrollTo(
        index: indice,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
        alignment:
            0.0, // 0.0 significa alinear el elemento al inicio (arriba) de la lista
      );
    } else {
      debugPrint('DEBUG: Controlador no adjunto, reintentando...');
      // Reintentar brevemente por si se está construyendo
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _itemScrollController.isAttached) {
          _scrollAPregunta(indice);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        backgroundColor: TemaAplicacion.colorFondo,
        body: Center(
          child: CircularProgressIndicator(color: TemaAplicacion.colorPrimario),
        ),
      );
    }
    return Scaffold(
      backgroundColor: TemaAplicacion.colorFondo,
      appBar: BarraSuperior(
        mostrarBotonAtras: !_enVistaMaterias,
        onAtrasPressed: !_enVistaMaterias ? _volverAMaterias : null,
        mostrarBotonAudio: !_enVistaMaterias,
        audioVisible: _mostrarReproductor,
        onToggleAudio: !_enVistaMaterias
            ? () {
                setState(() {
                  _mostrarReproductor = !_mostrarReproductor;
                  if (!_mostrarReproductor) {
                    _detenerReproduccion();
                  }
                });
              }
            : null,
      ),
      body: _enVistaMaterias
          ? _buildVistaMaterias()
          : StreamBuilder<PlaybackState>(
              stream: audioHandler?.playbackState ?? Stream.empty(),
              builder: (context, snapshot) {
                final playing = snapshot.data?.playing ?? false;
                final processingState =
                    snapshot.data?.processingState ?? AudioProcessingState.idle;
                final isAudioActive =
                    playing || processingState == AudioProcessingState.ready;
                final queueIndex = snapshot.data?.queueIndex ?? 0;

                // Guardar última pregunta si está reproduciendo
                if (isAudioActive) {
                  int offset = 0;
                  if (_rangoAudio == 'rango') {
                    offset = (_preguntaDesde - 1).clamp(
                      0,
                      _preguntasFiltradas.length,
                    );
                  }
                  _ultimaPreguntaReproducida = queueIndex + offset;
                  // debugPrint('DEBUG: Reproduciendo idx: $queueIndex | Offset: $offset | Ultima: $_ultimaPreguntaReproducida');
                }

                // DETECCIÓN DE DETENCIÓN:
                // Si estaba reproduciendo y ahora NO, y el estado es IDLE (detenido)
                if (_estabaReproduciendo &&
                    !isAudioActive &&
                    processingState == AudioProcessingState.idle) {
                  debugPrint(
                    'DEBUG: STOP detectado. Scroll a $_ultimaPreguntaReproducida',
                  );

                  // Usamos postFrameCallback para dar tiempo a que el Visibility cambie y la lista se monte
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollAPregunta(_ultimaPreguntaReproducida);
                  });
                }

                // Actualizar estado previo
                _estabaReproduciendo = isAudioActive;

                return Column(
                  children: [
                    // Barra de búsqueda: Usamos Visibility para mantenerla en el árbol
                    // y evitar que el reproductor pierda su estado al cambiar la estructura del Column.
                    Visibility(
                      visible: !isAudioActive,
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: false, // Permitimos que colapse su espacio
                      child: BarraBusqueda(
                        controller: _controladorBusqueda,
                        onChanged: _filtrarPreguntas,
                        hintText: 'Buscar en ${_materiaActiva ?? ''}...',
                        mostrarFiltroActivo:
                            _materiasSeleccionadas.length !=
                            _todasLasMaterias.length,
                        onFiltroPressed: () => _mostrarFiltroMaterias(context),
                      ),
                    ),

                    // Reproductor de audio
                    _buildSeccionReproductor(),

                    // Lista de preguntas: Usamos Expanded + Visibility
                    Expanded(
                      child: Visibility(
                        visible: !isAudioActive,
                        maintainState:
                            true, // Mantener estado permite recuperar posición scroll si fuera visible
                        child: _preguntasFiltradas.isEmpty
                            ? Center(
                                child: Text(
                                  'No hay preguntas en esta materia.',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: const Color(0xFF6B7280),
                                  ),
                                ),
                              )
                            : ScrollablePositionedList.builder(
                                itemScrollController: _itemScrollController,
                                itemPositionsListener: _itemPositionsListener,
                                padding: const EdgeInsets.all(16),
                                itemCount: _preguntasFiltradas.length,
                                itemBuilder: (context, index) {
                                  final pregunta = _preguntasFiltradas[index];
                                  final estadistica =
                                      _estadisticasPorPregunta[pregunta.id];
                                  // Marcar visualmente la pregunta que se estaba escuchando? (Opcional)
                                  return TarjetaPregunta(
                                    key: ValueKey('estudio_${pregunta.id}'),
                                    pregunta: pregunta,
                                    numeroOrden: index + 1,
                                    mostrarRespuestaAlInicio: false,
                                    aciertosCount:
                                        estadistica?.aciertosVisibles ?? 0,
                                    fallosCount:
                                        estadistica?.fallosVisibles ?? 0,
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildSeccionReproductor() {
    // Usamos Visibility en lugar de devolver SizedBox.shrink() para la misma razón:
    // Mantener la clave y estado del widget.
    return Visibility(
      visible: _mostrarReproductor,
      maintainState: true,
      child: _mostrarReproductor
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: ReproductorAudioCompleto(
                // Usar ValueKey asegura que Flutter reconozca este widget como único
                key: const ValueKey('reproductor_principal'),
                preguntas: _obtenerPreguntasParaReproduccion(),
                onConfiguracion: () => _mostrarConfiguracionAudio(context),
              ),
            )
          : const SizedBox.shrink(), // Aquí sí colapsamos si el usuario lo oculta explícitamente
    );
  }

  void _mostrarConfiguracionAudio(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Colors.transparent, // Transparente para ver bordes redondeados
      builder: (BuildContext bc) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SafeArea(
                  // Protege contra barras de navegación gestual
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        24,
                        24,
                        24,
                        40,
                      ), // 40px extra abajo
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
                          const SizedBox(height: 16),
                          Text(
                            'Configuración de Audio',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF6B21A8),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Rango de reproducción:',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF6B21A8),
                            ),
                          ),
                          const SizedBox(height: 12),
                          RadioListTile<String>(
                            value: 'todo',
                            groupValue: _rangoAudio,
                            onChanged: (value) {
                              setModalState(() {
                                _rangoAudio = value!;
                              });
                              setState(() {
                                _rangoAudio = value!;
                              });
                            },
                            title: Text(
                              'Todas las preguntas (${_preguntasFiltradas.length})',
                              style: GoogleFonts.inter(fontSize: 14),
                            ),
                            fillColor: WidgetStateProperty.all(
                              const Color(0xFFA855F7),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          RadioListTile<String>(
                            value: 'rango',
                            groupValue: _rangoAudio,
                            onChanged: (value) {
                              setModalState(() {
                                _rangoAudio = value!;
                              });
                              setState(() {
                                _rangoAudio = value!;
                              });
                            },
                            title: Text(
                              'Rango personalizado',
                              style: GoogleFonts.inter(fontSize: 14),
                            ),
                            fillColor: WidgetStateProperty.all(
                              const Color(0xFFA855F7),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          if (_rangoAudio == 'rango') ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Desde:',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: const Color(0xFF6B21A8),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      TextField(
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          hintText: '1',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                        ),
                                        onChanged: (value) {
                                          final num = int.tryParse(value);
                                          if (num != null &&
                                              num >= 1 &&
                                              num <=
                                                  _preguntasFiltradas.length) {
                                            setState(() {
                                              _preguntaDesde = num;
                                              if (_preguntaDesde >
                                                  _preguntaHasta) {
                                                _preguntaHasta = _preguntaDesde;
                                              }
                                            });
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Hasta:',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: const Color(0xFF6B21A8),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      TextField(
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          hintText:
                                              '${_preguntasFiltradas.length}',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                        ),
                                        onChanged: (value) {
                                          final num = int.tryParse(value);
                                          if (num != null &&
                                              num >= _preguntaDesde &&
                                              num <=
                                                  _preguntasFiltradas.length) {
                                            setState(() {
                                              _preguntaHasta = num;
                                            });
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Se reproducirán ${_preguntaHasta - _preguntaDesde + 1} preguntas',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF7E22CE),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFA855F7),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Aplicar Configuración'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _mostrarFiltroMaterias(BuildContext context) {
    mostrarBottomSheetFiltros(
      context: context,
      todasLasMaterias: _todasLasMaterias,
      materiasSeleccionadas: _materiasSeleccionadas,
      colorPrimario: const Color(0xFF3B82F6),
      onAplicar: (nuevasMaterias) {
        if (nuevasMaterias.length != 1) {
          _detenerReproduccion();
        }
        setState(() {
          _materiasSeleccionadas = nuevasMaterias;
          _materiaActiva = nuevasMaterias.length == 1
              ? nuevasMaterias.first
              : null;
          if (_materiaActiva == null) {
            _mostrarReproductor = false;
          }
        });
        _aplicarFiltros();
      },
    );
  }
}
