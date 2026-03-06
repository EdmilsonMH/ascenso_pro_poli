import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../modelos/modelo_pregunta.dart';
import '../servicios/audio_handler.dart';
import '../servicios/servicio_progreso.dart';
import '../widgets/barra_superior.dart';
import '../widgets/reproductor_audio/configuracion_audio_sheet.dart';
import '../widgets/widgets.dart';
import 'pantalla_practica.dart';

class PantallaPreguntasAcertadas extends StatefulWidget {
  const PantallaPreguntasAcertadas({super.key});

  @override
  State<PantallaPreguntasAcertadas> createState() =>
      _PantallaPreguntasAcertadasState();
}

class _PantallaPreguntasAcertadasState
    extends State<PantallaPreguntasAcertadas> {
  final ServicioProgreso _servicioProgreso = ServicioProgreso();
  final TextEditingController _controladorBusqueda = TextEditingController();
  final TextEditingController _controladorBusquedaMaterias =
      TextEditingController();

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  List<Pregunta> _preguntas = [];
  Map<String, EstadisticaPregunta> _estadisticasPorPregunta = {};
  List<String> _todasLasMaterias = [];
  String? _materiaActiva;

  bool _cargando = true;
  bool _mostrarReproductor = false;
  bool _estabaReproduciendo = false;
  int _ultimaPreguntaReproducida = 0;
  double _cantidadPreguntas = 5;

  bool get _enVistaMaterias => _materiaActiva == null;

  List<Pregunta> get _preguntasMateriaActiva {
    final materia = _materiaActiva;
    if (materia == null) return const [];
    return _preguntas.where((p) => p.materia == materia).toList();
  }

  List<Pregunta> get _preguntasFiltradas {
    var lista = _preguntasMateriaActiva;
    final query = _controladorBusqueda.text.toLowerCase();
    if (query.isEmpty) return lista;

    return lista
        .where(
          (p) =>
              p.texto.toLowerCase().contains(query) ||
              p.materia.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _actualizarDatos();
  }

  @override
  void dispose() {
    _controladorBusqueda.dispose();
    _controladorBusquedaMaterias.dispose();
    super.dispose();
  }

  Future<void> _actualizarDatos() async {
    setState(() {
      _cargando = true;
    });

    try {
      final resultados = await _servicioProgreso.obtenerPreguntasAcertadas();
      final estadisticas = await _servicioProgreso.obtenerEstadisticasPreguntas(
        preguntaIds: resultados.map((p) => p.id).toList(),
      );
      final materias = resultados.map((e) => e.materia).toSet().toList()
        ..sort((a, b) => a.compareTo(b));

      if (!mounted) return;
      setState(() {
        _preguntas = resultados;
        _estadisticasPorPregunta = estadisticas;
        _todasLasMaterias = materias;

        if (_materiaActiva != null &&
            !_todasLasMaterias.contains(_materiaActiva)) {
          _materiaActiva = null;
        }
        _actualizarCantidadMaxima();
        _cargando = false;
      });
    } catch (e) {
      debugPrint('PantallaPreguntasAcertadas._actualizarDatos error: $e');
      if (!mounted) return;
      setState(() {
        _preguntas = const [];
        _estadisticasPorPregunta = const {};
        _todasLasMaterias = const [];
        _materiaActiva = null;
        _cantidadPreguntas = 0;
        _cargando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar las preguntas.')),
      );
    }
  }

  double _cantidadInicialPara(int total) {
    if (total <= 0) return 0;
    return total >= 5 ? 5 : total.toDouble();
  }

  void _actualizarCantidadMaxima() {
    final totalMateria = _preguntasMateriaActiva.length;
    if (totalMateria <= 0) {
      _cantidadPreguntas = 0;
      return;
    }
    if (_cantidadPreguntas < 1 || _cantidadPreguntas > totalMateria) {
      _cantidadPreguntas = _cantidadInicialPara(totalMateria);
    }
  }

  void _detenerReproduccion() {
    audioHandler?.stop();
    _estabaReproduciendo = false;
  }

  void _abrirMateria(String materia) {
    _detenerReproduccion();
    _controladorBusqueda.clear();
    final total = _preguntas.where((p) => p.materia == materia).length;
    setState(() {
      _materiaActiva = materia;
      _mostrarReproductor = false;
      _cantidadPreguntas = _cantidadInicialPara(total);
    });
  }

  void _volverAMaterias() {
    _detenerReproduccion();
    _controladorBusqueda.clear();
    setState(() {
      _materiaActiva = null;
      _mostrarReproductor = false;
    });
  }

  Map<String, int> _contarPreguntasPorMateria() {
    final conteo = <String, int>{};
    for (final pregunta in _preguntas) {
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

  void _scrollAPregunta(int indice) {
    if (indice < 0 || indice >= _preguntasFiltradas.length) return;

    if (_itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: indice,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
        alignment: 0.0,
      );
      return;
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _itemScrollController.isAttached) {
        _scrollAPregunta(indice);
      }
    });
  }

  void _mostrarConfiguracionAudio(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ConfiguracionAudioSheet(
        totalPreguntas: _preguntasFiltradas.length,
        themeColor: const Color(0xFF10B981),
        onAplicar: _aplicarConfiguracionAudio,
      ),
    );
  }

  void _aplicarConfiguracionAudio(int start, int end) {
    if (_preguntasFiltradas.isEmpty) return;

    final startIdx = start - 1;
    final count = end - start + 1;
    if (startIdx < 0 || startIdx >= _preguntasFiltradas.length) return;

    final subset = _preguntasFiltradas.skip(startIdx).take(count).toList();

    setState(() {
      _mostrarReproductor = true;
    });

    if (audioHandler is AudioPlayerHandler) {
      (audioHandler as AudioPlayerHandler).cargarCola(subset);
    }
  }

  void _mostrarConfiguracionPractica(BuildContext context) {
    final parentContext = context;
    final preguntasMateria = _preguntasMateriaActiva;

    if (preguntasMateria.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay preguntas en esta materia.')),
      );
      return;
    }

    double tempCantidad = _cantidadPreguntas;
    if (tempCantidad < 1 || tempCantidad > preguntasMateria.length) {
      tempCantidad = _cantidadInicialPara(preguntasMateria.length);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            String calcularTiempo() {
              final segundos = tempCantidad.toInt() * 72;
              final minutos = segundos ~/ 60;
              if (minutos < 60) return '$minutos min';
              final horas = minutos ~/ 60;
              final min = minutos % 60;
              return '${horas}h ${min}m';
            }

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
                  const SizedBox(height: 16),
                  Text(
                    'Practicar Acertadas',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _materiaActiva ?? '',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF047857),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Cantidad a practicar: ${tempCantidad.toInt()}',
                    style: GoogleFonts.inter(fontSize: 14),
                  ),
                  Slider(
                    value: tempCantidad,
                    min: 1,
                    max: preguntasMateria.length.toDouble(),
                    divisions: preguntasMateria.length > 1
                        ? preguntasMateria.length - 1
                        : 1,
                    label: tempCantidad.round().toString(),
                    activeColor: const Color(0xFF10B981),
                    onChanged: (value) {
                      setModalState(() {
                        tempCantidad = value;
                      });
                    },
                  ),
                  Text(
                    'Tiempo estimado: ${calcularTiempo()}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(modalContext);
                        _iniciarPractica(parentContext, tempCantidad.toInt());
                      },
                      icon: const Icon(Icons.play_circle_outline, size: 20),
                      label: const Text('Iniciar PrÃ¡ctica'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  SizedBox(height: 16 + MediaQuery.of(context).padding.bottom),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _iniciarPractica(BuildContext context, int cantidadPreguntas) {
    final disponibles = List<Pregunta>.from(_preguntasMateriaActiva);
    if (disponibles.isEmpty || cantidadPreguntas <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay preguntas para practicar.')),
      );
      return;
    }

    setState(() {
      _cantidadPreguntas = cantidadPreguntas.toDouble();
    });

    disponibles.shuffle();
    final seleccionadas = disponibles.take(cantidadPreguntas).toList();
    final tiempoSegundos = seleccionadas.length * 72;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaPractica(
          preguntas: seleccionadas,
          esModoPractica: true,
          avanzarSoloConBotonEnPractica: true,
          tiempoLimiteSegundos: tiempoSegundos,
          onRespuestaIncorrecta: (preguntaFallada, indiceFallido) {
            if (DatosPrueba.preguntasAcertadas.contains(preguntaFallada)) {
              DatosPrueba.preguntasAcertadas.remove(preguntaFallada);
              final existe = DatosPrueba.preguntasIncorrectas.any(
                (i) => i.pregunta.id == preguntaFallada.id,
              );
              if (!existe) {
                DatosPrueba.preguntasIncorrectas.add(
                  IntentoFallido(
                    pregunta: preguntaFallada,
                    indiceIncorrectoSeleccionado: indiceFallido,
                  ),
                );
              }
            }
          },
        ),
      ),
    ).then((_) => _actualizarDatos());
  }

  Widget _buildVistaMaterias() {
    final conteoPorMateria = _contarPreguntasPorMateria();
    final materiasFiltradas = _materiasFiltradasPorBusqueda;

    if (_todasLasMaterias.isEmpty) {
      return const Center(
        child: Text('Aun no tienes preguntas acertadas por materia.'),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          color: const Color(0xFFF0FDF4),
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
                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.grey,
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ),
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
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.menu_book_rounded,
                                  color: Color(0xFF10B981),
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

  Widget _buildBarraBusqueda() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      color: Colors.white,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _controladorBusqueda,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Buscar en ${_materiaActiva ?? ''}...',
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

  Widget _buildSeccionReproductor() {
    return Visibility(
      visible: _mostrarReproductor,
      maintainState: true,
      child: _mostrarReproductor
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: ReproductorAudioCompleto(
                  key: const ValueKey('reproductor_acertadas'),
                  preguntas: _preguntasFiltradas,
                  onConfiguracion: () => _mostrarConfiguracionAudio(context),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        backgroundColor: Color(0xFFF0FDF4),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF10B981)),
        ),
      );
    }

    return PopScope(
      canPop: _enVistaMaterias,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _volverAMaterias();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0FDF4),
        appBar: BarraSuperior(
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
                      snapshot.data?.processingState ??
                      AudioProcessingState.idle;
                  final isAudioActive =
                      playing || processingState == AudioProcessingState.ready;

                  if (isAudioActive) {
                    final mediaItem = audioHandler?.mediaItem.value;
                    if (mediaItem != null) {
                      final index = _preguntasFiltradas.indexWhere(
                        (p) => p.id == mediaItem.id,
                      );
                      if (index != -1) {
                        _ultimaPreguntaReproducida = index;
                      }
                    }
                  }

                  if (_estabaReproduciendo &&
                      !isAudioActive &&
                      processingState == AudioProcessingState.idle) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_ultimaPreguntaReproducida >= 0 &&
                          _ultimaPreguntaReproducida <
                              _preguntasFiltradas.length) {
                        _scrollAPregunta(_ultimaPreguntaReproducida);
                      }
                    });
                  }

                  _estabaReproduciendo = isAudioActive;

                  return Column(
                    children: [
                      if (!isAudioActive) _buildBarraBusqueda(),
                      _buildSeccionReproductor(),
                      Expanded(
                        child: Visibility(
                          visible: !isAudioActive,
                          maintainState: true,
                          child: _preguntasFiltradas.isEmpty
                              ? Center(
                                  child: Text(
                                    'No hay preguntas para mostrar en esta materia.',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: const Color(0xFF6B7280),
                                    ),
                                  ),
                                )
                              : ScrollablePositionedList.builder(
                                  itemScrollController: _itemScrollController,
                                  itemPositionsListener: _itemPositionsListener,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  itemCount: _preguntasFiltradas.length,
                                  itemBuilder: (context, index) {
                                    final pregunta = _preguntasFiltradas[index];
                                    final estadistica =
                                        _estadisticasPorPregunta[pregunta.id];
                                    return TarjetaPregunta(
                                      pregunta: pregunta,
                                      numeroOrden: index + 1,
                                      colorBordeIzquierdo: const Color(
                                        0xFF10B981,
                                      ),
                                      colorEtiquetaId: const Color(0xFFDCFCE7),
                                      colorTextoEtiquetaId: const Color(
                                        0xFF15803D,
                                      ),
                                      aciertosCount:
                                          estadistica?.totalAciertos ?? 0,
                                      fallosCount:
                                          estadistica?.totalFallos ?? 0,
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
        floatingActionButton:
            !_enVistaMaterias && _preguntasMateriaActiva.isNotEmpty
            ? FloatingActionButton.extended(
                onPressed: () => _mostrarConfiguracionPractica(context),
                label: Text(
                  'Practicar Acertadas',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                ),
                icon: const Icon(Icons.play_arrow),
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              )
            : null,
      ),
    );
  }
}
