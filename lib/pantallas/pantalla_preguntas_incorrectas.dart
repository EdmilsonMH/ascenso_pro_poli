import 'package:audio_service/audio_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../modelos/modelo_pregunta.dart';
import '../servicios/audio_handler.dart';
import '../servicios/servicio_progreso.dart';
import '../widgets/reproductor_audio/reproductor_audio_completo.dart';
import '../widgets/reproductor_audio/configuracion_audio_sheet.dart';
import '../widgets/barra_superior.dart';
import '../widgets/widgets.dart';
import 'pantalla_practica.dart';

class PantallaPreguntasIncorrectas extends StatefulWidget {
  const PantallaPreguntasIncorrectas({super.key});

  @override
  State<PantallaPreguntasIncorrectas> createState() =>
      _PantallaPreguntasIncorrectasState();
}

class _PantallaPreguntasIncorrectasState
    extends State<PantallaPreguntasIncorrectas> {
  final ServicioProgreso _servicioProgreso = ServicioProgreso();
  List<IntentoFallido> intentos = [];
  Map<String, EstadisticaPregunta> _estadisticasPorPregunta = {};
  bool _cargando = true;
  double _cantidadPreguntas = 5;
  List<String> _todasLasMaterias = [];
  List<String> _materiasSeleccionadas = [];
  final TextEditingController _controladorBusqueda = TextEditingController();

  // Control de Audio y Scroll
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  bool _mostrarReproductor = false;
  bool _estabaReproduciendo = false;
  int _ultimaPreguntaReproducida = 0;

  @override
  void initState() {
    super.initState();
    _actualizarDatos();
  }

  @override
  void dispose() {
    _controladorBusqueda.dispose();
    super.dispose();
  }

  Future<void> _actualizarDatos() async {
    setState(() {
      _cargando = true;
    });

    final resultados = await _servicioProgreso.obtenerPreguntasIncorrectas();
    final estadisticas = await _servicioProgreso.obtenerEstadisticasPreguntas(
      preguntaIds: resultados.map((i) => i.pregunta.id).toList(),
    );

    if (mounted) {
      setState(() {
        intentos = resultados;
        _estadisticasPorPregunta = estadisticas;
        _todasLasMaterias = intentos
            .map((e) => e.pregunta.materia)
            .toSet()
            .toList();

        if (_materiasSeleccionadas.isEmpty) {
          _materiasSeleccionadas = List.from(_todasLasMaterias);
        } else {
          _materiasSeleccionadas.retainWhere(
            (m) => _todasLasMaterias.contains(m),
          );
        }
        _actualizarCantidadMaxima();
        _cargando = false;
      });
    }
  }

  void _actualizarCantidadMaxima() {
    final filtered = _intentosFiltrados;
    if (_cantidadPreguntas > filtered.length) {
      _cantidadPreguntas = filtered.isEmpty ? 0 : filtered.length.toDouble();
    } else if (_cantidadPreguntas == 0 && filtered.isNotEmpty) {
      _cantidadPreguntas = filtered.length.toDouble();
    }
    // setState not needed here directly if called inside setState
  }

  List<IntentoFallido> get _intentosFiltrados {
    var lista = intentos
        .where((i) => _materiasSeleccionadas.contains(i.pregunta.materia))
        .toList();

    final query = _controladorBusqueda.text.toLowerCase();
    if (query.isNotEmpty) {
      lista = lista
          .where(
            (i) =>
                i.pregunta.texto.toLowerCase().contains(query) ||
                i.pregunta.materia.toLowerCase().contains(query),
          )
          .toList();
    }
    return lista;
  }

  void _detenerReproduccion() {
    audioHandler?.stop();
    setState(() {
      _estabaReproduciendo = false;
    });
  }

  void _scrollAPregunta(int indice) {
    if (indice < 0 || indice >= _intentosFiltrados.length) return;

    if (_itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: indice,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
        alignment: 0.0,
      );
    } else {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _itemScrollController.isAttached) {
          _scrollAPregunta(indice);
        }
      });
    }
  }

  void _mostrarConfiguracionAudio(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ConfiguracionAudioSheet(
        totalPreguntas: _intentosFiltrados.length,
        themeColor: const Color(0xFFEF4444),
        onAplicar: _aplicarConfiguracionAudio,
      ),
    );
  }

  void _aplicarConfiguracionAudio(int start, int end) {
    // start y end son 1-based indices (human readable)
    if (_intentosFiltrados.isEmpty) return;

    final startIdx = start - 1;
    final count = end - start + 1;

    // Validar rangos
    if (startIdx < 0 || startIdx >= _intentosFiltrados.length) return;

    final subset = _intentosFiltrados.skip(startIdx).take(count).toList();
    final preguntasSubset = subset.map((i) => i.pregunta).toList();

    _mostrarReproductor = true;
    setState(() {});

    // Cargar en audio handler
    if (audioHandler is AudioPlayerHandler) {
      (audioHandler as AudioPlayerHandler).cargarCola(preguntasSubset);
    }
  }

  // Update build method to scroll by ID instead of queueIndex
  @override
  Widget build(BuildContext context) {
    // Show loading indicator
    if (_cargando) {
      return const Scaffold(
        backgroundColor: Color(0xFFFEF2F2),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFEF4444)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFEF2F2),
      appBar: BarraSuperior(
        mostrarBotonAudio: true,
        audioVisible: _mostrarReproductor,
        onToggleAudio: () {
          setState(() {
            _mostrarReproductor = !_mostrarReproductor;
            if (!_mostrarReproductor) {
              _detenerReproduccion();
            }
          });
        },
      ),
      body: StreamBuilder<PlaybackState>(
        stream: audioHandler?.playbackState ?? Stream.empty(),
        builder: (context, snapshot) {
          final playing = snapshot.data?.playing ?? false;
          final processingState =
              snapshot.data?.processingState ?? AudioProcessingState.idle;
          final isAudioActive =
              playing || processingState == AudioProcessingState.ready;

          // Logic to find visual index from current audio item
          if (isAudioActive) {
            final mediaItem = audioHandler?.mediaItem.value;
            if (mediaItem != null) {
              final idStr = mediaItem.id; // String id
              // Find index in _intentosFiltrados
              // Fix: Direct string comparison for UUIDs
              final index = _intentosFiltrados.indexWhere(
                (i) => i.pregunta.id == idStr,
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
              // Only scroll if valid
              if (_ultimaPreguntaReproducida >= 0 &&
                  _ultimaPreguntaReproducida < _intentosFiltrados.length) {
                _scrollAPregunta(_ultimaPreguntaReproducida);
              }
            });
          }

          _estabaReproduciendo = isAudioActive;

          return Column(
            children: [
              // ... (Panel de filtros code same as before)
              Visibility(
                visible: !isAudioActive,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: false,
                child: Container(
                  color: const Color(0xFFFEF2F2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: Column(
                    children: [
                      EncabezadoPantalla(
                        icono: Icons.cancel_outlined,
                        colorIcono: const Color(0xFFEF4444),
                        titulo: 'Preguntas No Acertadas',
                        subtitulo:
                            'Tienes ${intentos.length} preguntas por corregir',
                      ),
                      const SizedBox(height: 12),
                      _buildBarraBusquedaYFiltros(),
                      if (_materiasSeleccionadas.length !=
                          _todasLasMaterias.length)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _buildIndicadorFiltros(),
                        ),
                    ],
                  ),
                ),
              ),

              // Reproductor
              _buildSeccionReproductor(),

              // Lista
              Expanded(
                child: Visibility(
                  visible: !isAudioActive,
                  maintainState: true,
                  child: ScrollablePositionedList.builder(
                    itemScrollController: _itemScrollController,
                    itemPositionsListener: _itemPositionsListener,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _intentosFiltrados.length,
                    itemBuilder: (context, index) {
                      final intento = _intentosFiltrados[index];
                      final estadistica =
                          _estadisticasPorPregunta[intento.pregunta.id];
                      return TarjetaPregunta(
                        pregunta: intento.pregunta,
                        numeroOrden: index + 1, // Dynamic numbering
                        colorBordeIzquierdo: const Color(0xFFEF4444),
                        colorEtiquetaId: const Color(0xFFFEE2E2),
                        colorTextoEtiquetaId: const Color(0xFF991B1B),
                        indiceSeleccionadoIncorrecto:
                            intento.indiceIncorrectoSeleccionado,
                        aciertosCount: estadistica?.aciertosVisibles ?? 0,
                        fallosCount: estadistica?.fallosVisibles ?? 0,
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _mostrarConfiguracionPractica(context),
        label: Text(
          'Practicar Fallos',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        icon: const Icon(Icons.play_arrow),
        backgroundColor: const Color(0xFFEF4444),
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildSeccionReproductor() {
    return Visibility(
      visible: _mostrarReproductor,
      maintainState: true,
      child: _mostrarReproductor
          ? Padding(
              padding: const EdgeInsets.all(16.0),
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
                  key: const ValueKey('reproductor_incorrectas'),
                  preguntas: _intentosFiltrados.map((i) => i.pregunta).toList(),
                  onConfiguracion: () => _mostrarConfiguracionAudio(context),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildBarraBusquedaYFiltros() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: TextField(
              controller: _controladorBusqueda,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar en fallos...',
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
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        InkWell(
          onTap: () => _mostrarFiltrosVisualizacion(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Icon(
              Icons.filter_list,
              color: Colors.black87,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIndicadorFiltros() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.filter_alt_outlined,
          size: 16,
          color: Color(0xFFEF4444),
        ),
        const SizedBox(width: 8),
        Text(
          'Filtros activos: ${_materiasSeleccionadas.length} materias',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: const Color(0xFFEF4444),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  void _mostrarFiltrosVisualizacion(BuildContext context) {
    List<String> tempMateriasSeleccionadas = List.from(_materiasSeleccionadas);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bc) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              height: MediaQuery.of(context).size.height * 0.65,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
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
                    'Filtrar Vista',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value:
                        _todasLasMaterias.isNotEmpty &&
                        tempMateriasSeleccionadas.length ==
                            _todasLasMaterias.length,
                    onChanged: (value) {
                      setModalState(() {
                        if (value == true) {
                          tempMateriasSeleccionadas = List.from(
                            _todasLasMaterias,
                          );
                        } else {
                          tempMateriasSeleccionadas.clear();
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
                          ? const Color(0xFFEF4444)
                          : null,
                    ),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  Expanded(
                    child: ListView(
                      shrinkWrap: true,
                      children: _todasLasMaterias.map((materia) {
                        final isSelected = tempMateriasSeleccionadas.contains(
                          materia,
                        );
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (value) {
                            setModalState(() {
                              if (value == true) {
                                tempMateriasSeleccionadas.add(materia);
                              } else {
                                tempMateriasSeleccionadas.remove(materia);
                              }
                            });
                          },
                          title: Text(
                            materia,
                            style: GoogleFonts.inter(fontSize: 14),
                          ),
                          fillColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? const Color(0xFFEF4444)
                                : null,
                          ),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      }).toList(),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _materiasSeleccionadas = tempMateriasSeleccionadas;
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444), // Red theme
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Aplicar Filtros',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
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

  void _mostrarConfiguracionPractica(BuildContext context) {
    // Inicializar con TODAS las materias por defecto para la práctica,
    // o con las seleccionadas visualmente si se prefiere.
    // Dado que son independientes, iniciar con todas o las actuales parece razonable.
    // Usaremos las visuales como base pero permitiremos cambiar sin afectar visual.
    double tempCantidadPreguntas = _cantidadPreguntas;
    List<String> tempMateriasSeleccionadas = List.from(_materiasSeleccionadas);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext bc) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            List<IntentoFallido> filteredForModal = intentos
                .where(
                  (i) => tempMateriasSeleccionadas.contains(i.pregunta.materia),
                )
                .toList();

            if (tempCantidadPreguntas > filteredForModal.length) {
              tempCantidadPreguntas = filteredForModal.isEmpty
                  ? 0
                  : filteredForModal.length.toDouble();
            } else if (tempCantidadPreguntas == 0 &&
                filteredForModal.isNotEmpty) {
              tempCantidadPreguntas = filteredForModal.length.toDouble();
            }

            String calcularTiempoEstimado() {
              int segundos = tempCantidadPreguntas.toInt() * 72;
              final minutes = segundos ~/ 60;
              if (minutes < 60) {
                return '$minutes min';
              } else {
                final hours = minutes ~/ 60;
                final min = minutes % 60;
                return '${hours}h ${min}m';
              }
            }

            return _buildContenidoBottomSheet(
              context: context,
              setModalState: setModalState,
              tempCantidadPreguntas: tempCantidadPreguntas,
              tempMateriasSeleccionadas: tempMateriasSeleccionadas,
              filteredForModal: filteredForModal,
              calcularTiempo: calcularTiempoEstimado,
              onCantidadChanged: (value) {
                setModalState(() {
                  tempCantidadPreguntas = value;
                });
              },
              onMateriaToggle: (materia, value) {
                setModalState(() {
                  if (value == true) {
                    tempMateriasSeleccionadas.add(materia);
                  } else {
                    if (tempMateriasSeleccionadas.isNotEmpty) {
                      tempMateriasSeleccionadas.remove(materia);
                    }
                  }
                });
              },
              onTodasToggle: (value) {
                setModalState(() {
                  if (value == true) {
                    tempMateriasSeleccionadas = List.from(_todasLasMaterias);
                  } else {
                    tempMateriasSeleccionadas.clear();
                  }
                });
              },
              onPracticar: () => _iniciarPractica(
                context,
                tempCantidadPreguntas,
                tempMateriasSeleccionadas,
              ),
            );
          },
        );
      },
    ); // No .then() updating state
  }

  Widget _buildContenidoBottomSheet({
    required BuildContext context,
    required StateSetter setModalState,
    required double tempCantidadPreguntas,
    required List<String> tempMateriasSeleccionadas,
    required List<IntentoFallido> filteredForModal,
    required String Function() calcularTiempo,
    required ValueChanged<double> onCantidadChanged,
    required Function(String, bool?) onMateriaToggle,
    required ValueChanged<bool?> onTodasToggle,
    required VoidCallback onPracticar,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      height: MediaQuery.of(context).size.height * 0.75, // Altura fija
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
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
            'Configurar Práctica',
            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          if (filteredForModal.isNotEmpty) ...[
            Text(
              'Cantidad a practicar: ${tempCantidadPreguntas.toInt()}',
              style: GoogleFonts.inter(fontSize: 14),
            ),
            Slider(
              value: tempCantidadPreguntas,
              min: 1,
              max: filteredForModal.length.toDouble(),
              divisions: filteredForModal.length > 1
                  ? filteredForModal.length - 1
                  : 1,
              label: tempCantidadPreguntas.round().toString(),
              activeColor: const Color(0xFFEF4444),
              onChanged: onCantidadChanged,
            ),
            Text(
              'Tiempo estimado: ${calcularTiempo()}',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
            const Divider(height: 24),
          ],
          CheckboxListTile(
            value:
                _todasLasMaterias.isNotEmpty &&
                tempMateriasSeleccionadas.length == _todasLasMaterias.length,
            onChanged: onTodasToggle,
            title: Text(
              'Todas las materias',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            fillColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? const Color(0xFFEF4444)
                  : null,
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          Expanded(
            child: ListView(
              shrinkWrap: true,
              children: _todasLasMaterias.map((materia) {
                final isSelected = tempMateriasSeleccionadas.contains(materia);
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (value) => onMateriaToggle(materia, value),
                  title: Text(materia, style: GoogleFonts.inter(fontSize: 14)),
                  fillColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? const Color(0xFFEF4444)
                        : null,
                  ),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }).toList(),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onPracticar,
              icon: const Icon(Icons.play_circle_outline, size: 20),
              label: const Text('Practicar Fallos Filtrados'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14, // Ligeramente más alto
                ),
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
          // Espacio extra para evitar la barra de navegación del sistema
          SizedBox(height: 24 + MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  void _iniciarPractica(
    BuildContext context,
    double cantidadPreguntas,
    List<String> materiasSeleccionadas,
  ) {
    if (materiasSeleccionadas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos una materia')),
      );
      return;
    }
    if (cantidadPreguntas == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay preguntas disponibles para practicar con los filtros actuales.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _cantidadPreguntas = cantidadPreguntas;
      _materiasSeleccionadas = materiasSeleccionadas;
      _actualizarCantidadMaxima();
    });

    var filteredIntentos = intentos
        .where((i) => _materiasSeleccionadas.contains(i.pregunta.materia))
        .toList();

    filteredIntentos.shuffle();
    var selectedIntentos = filteredIntentos
        .take(_cantidadPreguntas.toInt())
        .toList();

    var selectedPreguntas = selectedIntentos.map((i) => i.pregunta).toList();

    int timeSeconds = selectedPreguntas.length * 72;

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        // context of Navigator.push uses parent context (OK)
        builder: (context) => PantallaPractica(
          preguntas: selectedPreguntas,
          esModoPractica: true,
          avanzarSoloConBotonEnPractica: true,
          tiempoLimiteSegundos: timeSeconds,
          onRespuestaIncorrecta: (preguntaFallada, indiceFallido) {
            // Si falla de nuevo, no hacemos nada especial
          },
        ),
      ),
    ).then((_) {
      setState(() {
        _actualizarDatos();
      });
    });
  }
}
