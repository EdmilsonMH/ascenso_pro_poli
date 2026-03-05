import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../modelos/modelo_pregunta.dart';
import '../servicios/servicio_progreso.dart';
import '../servicios/servicio_preguntas.dart';
import '../widgets/barra_superior.dart';
import 'pantalla_practica.dart';

class PantallaPracticaGuiadaConfig extends StatefulWidget {
  final String categoriaUsuario;

  const PantallaPracticaGuiadaConfig({
    super.key,
    required this.categoriaUsuario,
  });

  @override
  State<PantallaPracticaGuiadaConfig> createState() =>
      _PantallaPracticaGuiadaConfigState();
}

class _PantallaPracticaGuiadaConfigState
    extends State<PantallaPracticaGuiadaConfig> {
  static const String _opcionTodasMaterias = 'Todas las materias';
  final ServicioPreguntas _servicioPreguntas = ServicioPreguntas();
  final ServicioProgreso _servicioProgreso = ServicioProgreso();
  final TextEditingController _cantidadController = TextEditingController(
    text: '100',
  );

  int _cantidadPreguntas = 100;
  int _preguntasDisponibles = 0;
  bool _cargando = true;
  List<String> _todasLasMateriasDisponibles = [];
  List<String> _materiasSeleccionadas = [];
  String? _materiaActiva;
  List<Pregunta> _preguntasTotalesCache = [];
  List<_PreguntaConFallos> _preguntasFalladasOrdenadas = [];
  bool _bancoFalladasCargado = false;
  bool _cargandoBancoFalladas = false;

  bool get _enVistaMaterias => _materiaActiva == null;
  String get _textoSeleccionActual => _materiaActiva ?? '';
  bool get _puedeIniciar =>
      !_enVistaMaterias &&
      _cantidadPreguntas > 0 &&
      _preguntasDisponibles > 0 &&
      _materiasSeleccionadas.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    final preguntas = await _servicioPreguntas.obtenerTodas(
      categoria: widget.categoriaUsuario,
    );

    if (!mounted) return;

    setState(() {
      _preguntasTotalesCache = preguntas;
      _todasLasMateriasDisponibles =
          preguntas.map((p) => p.materia).toSet().toList()
            ..sort((a, b) => a.compareTo(b));
      _materiasSeleccionadas = List.from(_todasLasMateriasDisponibles);
      _materiaActiva = null;
      _cargando = false;
    });

    _actualizarPreguntasDisponibles();
  }

  void _actualizarPreguntasDisponibles() {
    final disponibles = _preguntasTotalesCache
        .where((p) => _materiasSeleccionadas.contains(p.materia))
        .length;

    var cantidadAjustada = _cantidadPreguntas;
    if (cantidadAjustada > disponibles) {
      cantidadAjustada = disponibles > 0 ? disponibles : 0;
      _cantidadController.text = cantidadAjustada.toString();
    }

    if (!mounted) return;
    setState(() {
      _preguntasDisponibles = disponibles;
      _cantidadPreguntas = cantidadAjustada;
    });
  }

  void _abrirMateria(String materia) {
    setState(() {
      _materiaActiva = materia;
      _materiasSeleccionadas = [materia];
    });
    _actualizarPreguntasDisponibles();
  }

  void _abrirTodasLasMaterias() {
    setState(() {
      _materiaActiva = _opcionTodasMaterias;
      _materiasSeleccionadas = List.from(_todasLasMateriasDisponibles);
    });
    _actualizarPreguntasDisponibles();
  }

  void _volverAMaterias() {
    setState(() {
      _materiaActiva = null;
      _materiasSeleccionadas = List.from(_todasLasMateriasDisponibles);
    });
    _actualizarPreguntasDisponibles();
  }

  int _obtenerPrioridadFallo(EstadisticaPregunta? estadistica) {
    if (estadistica == null) return 0;
    // Regla: al completar 3 aciertos seguidos, contadores visibles vuelven a 0.
    if (estadistica.rachaAciertos >= 3) return 0;
    return estadistica.fallosVisibles;
  }

  Future<List<Pregunta>> _ordenarPorFallasActuales(
    List<Pregunta> preguntas,
  ) async {
    if (preguntas.length <= 1) return List<Pregunta>.from(preguntas);

    try {
      final estadisticas = await _servicioProgreso.obtenerEstadisticasPreguntas(
        preguntaIds: preguntas.map((p) => p.id).toList(),
      );

      final ordenadas = List<Pregunta>.from(preguntas);
      ordenadas.sort((a, b) {
        final prioridadA = _obtenerPrioridadFallo(estadisticas[a.id]);
        final prioridadB = _obtenerPrioridadFallo(estadisticas[b.id]);
        final porPrioridad = prioridadB.compareTo(prioridadA);
        if (porPrioridad != 0) return porPrioridad;
        return a.numero.compareTo(b.numero);
      });
      return ordenadas;
    } catch (_) {
      final fallback = List<Pregunta>.from(preguntas);
      fallback.sort((a, b) => a.numero.compareTo(b.numero));
      return fallback;
    }
  }

  Future<void> _iniciarPracticaGuiada() async {
    if (!_puedeIniciar) return;

    if (_materiaActiva == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes seleccionar una materia.')),
      );
      return;
    }

    var cantidadFinal = _cantidadPreguntas;
    if (cantidadFinal > _preguntasDisponibles) {
      cantidadFinal = _preguntasDisponibles;
      if (cantidadFinal > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Se ajustó a $cantidadFinal preguntas disponibles.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    if (cantidadFinal == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay preguntas disponibles para la selección actual.',
          ),
        ),
      );
      return;
    }

    final candidatas = _preguntasTotalesCache
        .where((p) => _materiasSeleccionadas.contains(p.materia))
        .toList();

    final ordenadas = await _ordenarPorFallasActuales(candidatas);
    var n = cantidadFinal;
    if (n > ordenadas.length) n = ordenadas.length;

    final seleccionadas = ordenadas.take(n).toList();
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PantallaPractica(
          preguntas: seleccionadas,
          tiempoLimiteSegundos: null,
          esModoPractica: true,
          esRanking: false,
          revisarRespuestaInmediata: true,
          registrarSesionEnHistorial: false,
        ),
      ),
    );
  }

  Future<void> _cargarBancoFalladas() async {
    if (_bancoFalladasCargado || _cargandoBancoFalladas) return;

    setState(() {
      _cargandoBancoFalladas = true;
    });

    try {
      final estadisticas = await _servicioProgreso
          .obtenerEstadisticasPreguntas();
      final conFallos =
          estadisticas.values
              .where((s) => s.estaEnIncorrectas && s.fallosVisibles > 0)
              .toList()
            ..sort((a, b) {
              final porFallos = b.fallosVisibles.compareTo(a.fallosVisibles);
              if (porFallos != 0) return porFallos;
              return a.preguntaId.compareTo(b.preguntaId);
            });

      if (conFallos.isEmpty) {
        if (!mounted) return;
        setState(() {
          _preguntasFalladasOrdenadas = [];
          _bancoFalladasCargado = true;
        });
        return;
      }

      final ids = conFallos.map((s) => s.preguntaId).toList();
      final fallosPorId = <String, int>{
        for (final s in conFallos) s.preguntaId: s.fallosVisibles,
      };
      final preguntas = await _servicioPreguntas.obtenerPreguntasPorIds(
        ids: ids,
      );

      if (!mounted) return;
      final preguntasConFallo =
          preguntas
              .map(
                (pregunta) => _PreguntaConFallos(
                  pregunta: pregunta,
                  fallosActuales: fallosPorId[pregunta.id] ?? 0,
                ),
              )
              .toList()
            ..sort((a, b) {
              final porFallos = b.fallosActuales.compareTo(a.fallosActuales);
              if (porFallos != 0) return porFallos;
              return a.pregunta.numero.compareTo(b.pregunta.numero);
            });

      setState(() {
        _preguntasFalladasOrdenadas = preguntasConFallo;
        _bancoFalladasCargado = true;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo cargar las preguntas falladas.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _cargandoBancoFalladas = false;
        });
      }
    }
  }

  void _iniciarPracticaGuiadaConPreguntas(List<Pregunta> preguntas) {
    if (preguntas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay preguntas disponibles para iniciar la práctica.',
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PantallaPractica(
          preguntas: preguntas,
          tiempoLimiteSegundos: null,
          esModoPractica: true,
          esRanking: false,
          revisarRespuestaInmediata: true,
          registrarSesionEnHistorial: false,
        ),
      ),
    );
  }

  Future<void> _mostrarModalPracticaFalladas() async {
    await _cargarBancoFalladas();
    if (!mounted) return;

    if (_preguntasFalladasOrdenadas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tienes preguntas falladas para practicar.'),
        ),
      );
      return;
    }

    final materiasDisponibles =
        _preguntasFalladasOrdenadas
            .map((item) => item.pregunta.materia)
            .toSet()
            .toList()
          ..sort();

    int tempCantidad = _preguntasFalladasOrdenadas.length < 30
        ? _preguntasFalladasOrdenadas.length
        : 30;
    List<String> tempMateriasSeleccionadas = List.from(materiasDisponibles);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            final preguntasFiltradas = _preguntasFalladasOrdenadas
                .where(
                  (item) =>
                      tempMateriasSeleccionadas.contains(item.pregunta.materia),
                )
                .toList();
            final disponibles = preguntasFiltradas.length;

            if (disponibles == 0) {
              tempCantidad = 0;
            } else if (tempCantidad <= 0) {
              tempCantidad = 1;
            } else if (tempCantidad > disponibles) {
              tempCantidad = disponibles;
            }

            final todasSeleccionadas =
                materiasDisponibles.isNotEmpty &&
                tempMateriasSeleccionadas.length == materiasDisponibles.length;

            Future<void> ingresarCantidadManual() async {
              if (disponibles <= 0) return;

              final controladorCantidad = TextEditingController(
                text: tempCantidad.toString(),
              );
              String? errorTexto;

              final cantidadNueva = await showDialog<int>(
                context: context,
                builder: (dialogContext) {
                  return StatefulBuilder(
                    builder: (dialogContext, setDialogState) {
                      return AlertDialog(
                        title: Text(
                          'Cantidad de preguntas',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827),
                          ),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: controladorCantidad,
                              keyboardType: TextInputType.number,
                              autofocus: true,
                              decoration: InputDecoration(
                                labelText: 'Ingresa una cantidad',
                                hintText: 'Ejemplo: 100',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                errorText: errorTexto,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Disponible: $disponibles',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Cancelar'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              final valor = int.tryParse(
                                controladorCantidad.text.trim(),
                              );
                              if (valor == null) {
                                setDialogState(() {
                                  errorTexto = 'Ingresa un número válido.';
                                });
                                return;
                              }
                              if (valor < 1) {
                                setDialogState(() {
                                  errorTexto = 'La cantidad mínima es 1.';
                                });
                                return;
                              }
                              if (valor > disponibles) {
                                setDialogState(() {
                                  errorTexto =
                                      'Máximo permitido con filtros: $disponibles.';
                                });
                                return;
                              }

                              Navigator.pop(dialogContext, valor);
                            },
                            child: const Text('Aplicar'),
                          ),
                        ],
                      );
                    },
                  );
                },
              );

              controladorCantidad.dispose();
              if (cantidadNueva == null) return;
              setStateModal(() {
                tempCantidad = cantidadNueva;
              });
            }

            return SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.86,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFB91C1C),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Practicar preguntas falladas',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Text(
                        'Se priorizan las preguntas donde actualmente fallas mas. '
                        'Si completas 3 aciertos seguidos, sus contadores vuelven a 0.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF9A3412),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Cantidad',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD1D9E6)),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: disponibles <= 0 || tempCantidad <= 1
                                ? null
                                : () {
                                    setStateModal(() {
                                      tempCantidad--;
                                    });
                                  },
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: ingresarCantidadManual,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$tempCantidad',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF111827),
                                      ),
                                    ),
                                    Text(
                                      'Toca para escribir',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: const Color(0xFF64748B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed:
                                disponibles <= 0 || tempCantidad >= disponibles
                                ? null
                                : () {
                                    setStateModal(() {
                                      tempCantidad++;
                                    });
                                  },
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Disponibles con tus filtros: $disponibles',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF475569),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: todasSeleccionadas,
                      activeColor: const Color(0xFF1D4ED8),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Todas las materias',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      onChanged: (value) {
                        setStateModal(() {
                          if (value == true) {
                            tempMateriasSeleccionadas = List.from(
                              materiasDisponibles,
                            );
                          } else {
                            tempMateriasSeleccionadas.clear();
                          }
                        });
                      },
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: materiasDisponibles.length,
                        itemBuilder: (context, index) {
                          final materia = materiasDisponibles[index];
                          return CheckboxListTile(
                            value: tempMateriasSeleccionadas.contains(materia),
                            activeColor: const Color(0xFF1D4ED8),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              materia,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: const Color(0xFF334155),
                              ),
                            ),
                            onChanged: (value) {
                              setStateModal(() {
                                if (value == true) {
                                  tempMateriasSeleccionadas.add(materia);
                                } else {
                                  tempMateriasSeleccionadas.remove(materia);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: disponibles == 0 || tempCantidad == 0
                            ? null
                            : () {
                                final seleccionadas = preguntasFiltradas
                                    .take(tempCantidad)
                                    .map((item) => item.pregunta)
                                    .toList();
                                Navigator.pop(context);
                                _iniciarPracticaGuiadaConPreguntas(
                                  seleccionadas,
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFB91C1C),
                          disabledBackgroundColor: const Color(0xFFCBD5E1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Iniciar práctica guiada',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      appBar: const BarraSuperior(),
      body: _enVistaMaterias
          ? _buildVistaMaterias()
          : _buildVistaConfiguracionMateria(),
    );
  }

  Map<String, int> _contarPreguntasPorMateria() {
    final conteo = <String, int>{};
    for (final pregunta in _preguntasTotalesCache) {
      conteo[pregunta.materia] = (conteo[pregunta.materia] ?? 0) + 1;
    }
    return conteo;
  }

  Widget _buildVistaMaterias() {
    final conteoPorMateria = _contarPreguntasPorMateria();
    final totalGeneral = _preguntasTotalesCache.length;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        24 + MediaQuery.of(context).padding.bottom + 84,
      ),
      children: [
        _buildTarjetaPreguntasFalladas(),
        const SizedBox(height: 16),
        Text(
          'Elige una materia para practica guiada',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Selecciona una materia o todas, luego define cuantas preguntas practicar.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: const Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 14),
        if (_todasLasMateriasDisponibles.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              'No hay materias disponibles por ahora.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _abrirTodasLasMaterias,
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
                          color: const Color(0xFFE0E7FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.apps_rounded,
                          color: Color(0xFF4338CA),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _opcionTodasMaterias,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$totalGeneral preguntas',
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
            ),
          ),
          ..._todasLasMateriasDisponibles.map((materia) {
            final total = conteoPorMateria[materia] ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
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
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildVistaConfiguracionMateria() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        24 + MediaQuery.of(context).padding.bottom + 84,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEncabezadoMateriaActiva(),
          const SizedBox(height: 14),
          _buildTarjetaConfiguracion(),
          const SizedBox(height: 24),
          _buildBotonPrincipal(),
        ],
      ),
    );
  }

  Widget _buildEncabezadoMateriaActiva() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
      child: Row(
        children: [
          IconButton(
            onPressed: _volverAMaterias,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Volver a materias',
          ),
          Expanded(
            child: Text(
              _textoSeleccionActual,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$_preguntasDisponibles preg.',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildTarjetaPreguntasFalladas() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFECACA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFB91C1C),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Preguntas falladas',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Practica con guía las preguntas que fallaste para reforzar exactamente donde te equivocas.',
            style: GoogleFonts.inter(
              fontSize: 13.2,
              height: 1.35,
              color: const Color(0xFF4B5563),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _cargandoBancoFalladas
                  ? null
                  : _mostrarModalPracticaFalladas,
              icon: _cargandoBancoFalladas
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFB91C1C),
                      ),
                    )
                  : const Icon(Icons.play_circle_outline_rounded, size: 18),
              label: Text(
                'Practicar preguntas falladas',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB91C1C),
                side: const BorderSide(color: Color(0xFFFCA5A5)),
                backgroundColor: const Color(0xFFFFF1F2),
                padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _buildTarjetaConfiguracion() {
    final excedeDisponibles =
        _cantidadPreguntas > _preguntasDisponibles && _preguntasDisponibles > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: Color(0xFF1E40AF),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Configuración de práctica guiada',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildLabelCampo('Materia seleccionada'),
          const SizedBox(height: 6),
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD1D9E6)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.menu_book_rounded,
                  color: Color(0xFF64748B),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _textoSeleccionActual,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _volverAMaterias,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text(
                'Cambiar seleccion',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1D4ED8),
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _buildLabelCampo('Preguntas'),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD1D9E6)),
            ),
            child: TextField(
              controller: _cantidadController,
              keyboardType: TextInputType.number,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827),
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                prefixIcon: const Icon(
                  Icons.help_outline_rounded,
                  size: 19,
                  color: Color(0xFF64748B),
                ),
                hintText: '0',
                hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              onChanged: (value) {
                final n = int.tryParse(value);
                if (n != null) {
                  setState(() {
                    _cantidadPreguntas = n;
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Disponibles: $_preguntasDisponibles',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF475569),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (excedeDisponibles)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Se ajustará automáticamente al máximo disponible.',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFFB91C1C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFFEA580C),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF9A3412),
                        height: 1.4,
                      ),
                      children: const [
                        TextSpan(
                          text:
                              'Esta práctica guiada no contará para el ranking. ',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text:
                              'Tampoco se guardará en el historial, porque es un modo de estudio.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotonPrincipal() {
    final fondoGradiente = _puedeIniciar
        ? const [Color(0xFF0F172A), Color(0xFF1E293B)]
        : const [Color(0xFF94A3B8), Color(0xFF94A3B8)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: fondoGradiente,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: _puedeIniciar
                ? const [
                    BoxShadow(
                      color: Color(0x260F172A),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          child: ElevatedButton(
            onPressed: _puedeIniciar ? _iniciarPracticaGuiada : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white70,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.play_arrow_rounded, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Comenzar práctica guiada',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!_puedeIniciar)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _preguntasDisponibles == 0
                  ? 'No hay preguntas disponibles con la selección actual.'
                  : 'Ingresa una cantidad válida para comenzar.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLabelCampo(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1E293B),
      ),
    );
  }
}

class _PreguntaConFallos {
  final Pregunta pregunta;
  final int fallosActuales;

  const _PreguntaConFallos({
    required this.pregunta,
    required this.fallosActuales,
  });
}
