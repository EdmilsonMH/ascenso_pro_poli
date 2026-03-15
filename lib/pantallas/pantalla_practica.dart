import 'package:flutter/material.dart';
import 'dart:async';
import 'pantalla_resultados.dart';
import 'package:google_fonts/google_fonts.dart';
import '../tema/tema_aplicacion.dart';
import '../modelos/modelo_pregunta.dart';
import '../servicios/servicio_progreso.dart';
import '../servicios/auth_service.dart';
import '../servicios/servicio_notificaciones_programadas.dart';

class PantallaPractica extends StatefulWidget {
  final List<Pregunta> preguntas;
  final bool esModoPractica; // True para práctica, False para examen
  final bool esRanking;
  final bool avanzarSoloConBotonEnPractica;
  final bool revisarRespuestaInmediata;
  final bool registrarSesionEnHistorial;
  final Function(Pregunta, int)? onRespuestaIncorrecta;
  final int? tiempoLimiteSegundos;
  final List<String>? materiasIncluidasParaRegistro;

  const PantallaPractica({
    super.key,
    required this.preguntas,
    this.esModoPractica = true,
    this.esRanking = false,
    this.avanzarSoloConBotonEnPractica = false,
    this.revisarRespuestaInmediata = false,
    this.registrarSesionEnHistorial = true,
    this.onRespuestaIncorrecta,
    this.tiempoLimiteSegundos,
    this.materiasIncluidasParaRegistro,
  });

  @override
  State<PantallaPractica> createState() => _PantallaPracticaState();
}

class _PantallaPracticaState extends State<PantallaPractica> {
  final ServicioProgreso _servicioProgreso = ServicioProgreso();
  bool _finalizacionEnCurso = false;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _feedbackRevisionKey = GlobalKey();

  // Estado de navegación
  int _indiceActual = 0;

  // Estado para Modo Examen/Ranking (Respuestas guardadas temporalmente)
  final Map<String, int> _respuestasRanking =
      {}; // Map<PreguntaID, IndiceOpcion>
  final Map<String, int> _tiempoPorPreguntaSegundos = {};
  final Map<String, int> _cambiosAlternativaPorPregunta = {};
  String? _preguntaVisibleId;
  DateTime? _preguntaVisibleInicio;
  bool _modoRevision =
      false; // Si es true, muestra la lista completa para revisar

  // Permite navegar pregunta por pregunta y enviar al final
  bool get _usaNavegacionManual => widget.esRanking || !widget.esModoPractica;
  bool get _practicaConAvanceManual =>
      widget.esModoPractica &&
      !widget.esRanking &&
      widget.avanzarSoloConBotonEnPractica;
  bool get _practicaConRevisarInmediato =>
      widget.esModoPractica &&
      !widget.esRanking &&
      widget.revisarRespuestaInmediata;
  bool get _sinLimiteTiempo => _practicaConRevisarInmediato;

  // Estado para Modo Práctica Rápida (Feedback inmediato)
  int? _indiceOpcionSeleccionadaPractica;
  bool _respuestaRevisadaEnPregunta = false;

  // Estado general
  int _puntaje = 0;
  late Timer _timer;
  int _segundosRestantes = 120 * 60; // Default 2 horas
  int _segundosTranscurridos = 0;

  // Rastrear resultados para estadísticas
  final List<Pregunta> _preguntasCorrectas = [];
  final List<IntentoFallido> _preguntasIncorrectas = [];

  @override
  void initState() {
    super.initState();
    if (_sinLimiteTiempo) {
      _segundosTranscurridos = 0;
    } else {
      _segundosRestantes = widget.tiempoLimiteSegundos ?? 120 * 60;
    }
    _iniciarTemporizador();
    _iniciarTrackingPreguntaActual();
    ServicioNotificacionesProgramadas.marcarPracticaIniciada();
  }

  @override
  void dispose() {
    _acumularTiempoPreguntaActual();
    _timer.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _iniciarTemporizador() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sinLimiteTiempo) {
        setState(() {
          _segundosTranscurridos++;
        });
        return;
      }

      if (_segundosRestantes > 0) {
        setState(() {
          _segundosRestantes--;
        });
      } else {
        _timer.cancel();
        // Si se acaba el tiempo en examen, finalizamos automáticamente
        if (widget.esRanking ||
            !widget.esModoPractica ||
            _practicaConAvanceManual) {
          _finalizarExamenRanking();
        } else {
          _mostrarDialogoResultados();
        }
      }
    });
  }

  String _formatearTiempo(int segundos) {
    final int minutos = segundos ~/ 60;
    final int segs = segundos % 60;
    return '${minutos.toString().padLeft(2, '0')}:${segs.toString().padLeft(2, '0')}';
  }

  int _segundosUsados() {
    if (_sinLimiteTiempo) return _segundosTranscurridos;
    final int tiempoTotalSegundos = widget.tiempoLimiteSegundos ?? 120 * 60;
    return tiempoTotalSegundos - _segundosRestantes;
  }

  void _iniciarTrackingPreguntaActual() {
    if (widget.preguntas.isEmpty) return;
    _preguntaVisibleId = widget.preguntas[_indiceActual].id;
    _preguntaVisibleInicio = DateTime.now();
  }

  void _acumularTiempoPreguntaActual() {
    final preguntaId = _preguntaVisibleId;
    final inicio = _preguntaVisibleInicio;
    if (preguntaId == null || inicio == null) return;

    final elapsedMs = DateTime.now().difference(inicio).inMilliseconds;
    if (elapsedMs > 0) {
      final segundos = (elapsedMs / 1000).ceil();
      _tiempoPorPreguntaSegundos[preguntaId] =
          (_tiempoPorPreguntaSegundos[preguntaId] ?? 0) + segundos;
    }

    _preguntaVisibleId = null;
    _preguntaVisibleInicio = null;
  }

  int _tiempoPreguntaSegundos(String preguntaId) {
    return _tiempoPorPreguntaSegundos[preguntaId] ?? 0;
  }

  int _cambiosPregunta(String preguntaId) {
    return _cambiosAlternativaPorPregunta[preguntaId] ?? 0;
  }

  void _registrarCambioAlternativa({
    required String preguntaId,
    required int? indicePrevio,
    required int nuevoIndice,
  }) {
    if (indicePrevio == null || indicePrevio == nuevoIndice) return;
    _cambiosAlternativaPorPregunta[preguntaId] =
        (_cambiosAlternativaPorPregunta[preguntaId] ?? 0) + 1;
  }

  List<String> _resolverMateriasParaRegistro() {
    final override = widget.materiasIncluidasParaRegistro
        ?.map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (override != null && override.isNotEmpty) {
      return override;
    }

    return widget.preguntas
        .map(
          (p) => (p.materiaId != null && p.materiaId!.isNotEmpty)
              ? p.materiaId!
              : p.materia,
        )
        .toSet()
        .toList();
  }

  Future<void> _scrollAExplicacion() async {
    final ctx = _feedbackRevisionKey.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.12,
    );
  }

  // ==========================================
  // LÓGICA MODO RANKING / EXAMEN
  // ==========================================

  void _seleccionarRespuestaManual(int indiceOpcion) {
    final pregunta = widget.preguntas[_indiceActual];
    final indicePrevio = _respuestasRanking[pregunta.id];
    _registrarCambioAlternativa(
      preguntaId: pregunta.id,
      indicePrevio: indicePrevio,
      nuevoIndice: indiceOpcion,
    );
    setState(() {
      _respuestasRanking[pregunta.id] = indiceOpcion;
    });
  }

  void _navegarAtras() {
    if (_indiceActual > 0) {
      _acumularTiempoPreguntaActual();
      setState(() {
        _indiceActual--;
      });
      _iniciarTrackingPreguntaActual();
    }
  }

  void _navegarSiguiente() {
    if (_indiceActual < widget.preguntas.length - 1) {
      _acumularTiempoPreguntaActual();
      setState(() {
        _indiceActual++;
      });
      _iniciarTrackingPreguntaActual();
    } else {
      _acumularTiempoPreguntaActual();
      setState(() {
        _modoRevision = true;
      });
    }
  }

  void _alternarModoRevision() {
    if (_modoRevision) {
      setState(() {
        _modoRevision = false;
      });
      _iniciarTrackingPreguntaActual();
      return;
    }

    _acumularTiempoPreguntaActual();
    setState(() {
      _modoRevision = true;
    });
  }

  void _irAPregunta(int index) {
    _acumularTiempoPreguntaActual();
    setState(() {
      _indiceActual = index;
      _modoRevision = false;
    });
    _iniciarTrackingPreguntaActual();
  }

  Future<void> _finalizarExamenRanking() async {
    if (_finalizacionEnCurso) return;
    _finalizacionEnCurso = true;
    _acumularTiempoPreguntaActual();
    _timer.cancel();

    // Calcular puntaje
    int respuestasCorrectas = 0;
    int respuestasIncorrectas = 0;
    int respuestasOmitidas = 0;
    _preguntasCorrectas.clear();
    _preguntasIncorrectas.clear();

    for (var pregunta in widget.preguntas) {
      final respuestaUsuarioIndex = _respuestasRanking[pregunta.id];
      if (respuestaUsuarioIndex != null) {
        // Analizar si es correcta
        if (respuestaUsuarioIndex == pregunta.indiceRespuestaCorrecta) {
          respuestasCorrectas++;
          _preguntasCorrectas.add(pregunta);
        } else {
          respuestasIncorrectas++;
          _preguntasIncorrectas.add(
            IntentoFallido(
              pregunta: pregunta,
              indiceIncorrectoSeleccionado: respuestaUsuarioIndex,
              fechaIntento: DateTime.now(),
            ),
          );
        }

        // Opcional: Registrar intento individual en backend (si se desea granularidad)
        final letraSeleccionada = String.fromCharCode(
          65 + respuestaUsuarioIndex,
        );
        _servicioProgreso.registrarIntento(
          preguntaId: pregunta.id,
          respuestaSeleccionada: letraSeleccionada,
          esCorrecta: respuestaUsuarioIndex == pregunta.indiceRespuestaCorrecta,
          tiempoSegundos: _tiempoPreguntaSegundos(pregunta.id),
          numeroCambiosRespuesta: _cambiosPregunta(pregunta.id),
        );
      } else {
        respuestasOmitidas++;
        _servicioProgreso.registrarIntentoOmitido(
          preguntaId: pregunta.id,
          tiempoSegundos: _tiempoPreguntaSegundos(pregunta.id),
          numeroCambiosRespuesta: _cambiosPregunta(pregunta.id),
        );
      }
    }

    _puntaje = respuestasCorrectas;
    final int segundosUsados = _segundosUsados();

    // Guardar Sesión
    final materias = _resolverMateriasParaRegistro();
    try {
      await _servicioProgreso.registrarSesion(
        totalPreguntas: widget.preguntas.length,
        correctas: _puntaje,
        incorrectas: respuestasIncorrectas,
        omitidas: respuestasOmitidas,
        tiempoSegundos: segundosUsados,
        materiasIncluidas: materias,
        cuentaParaRanking: widget.esRanking,
        registrarHistorial: widget.registrarSesionEnHistorial,
      );

      AuthService.notifyProfileUpdated();

      if (!mounted) return;
      _irPantallaResultados(secondsUsed: segundosUsados);
    } finally {
      _finalizacionEnCurso = false;
    }
  }

  // ==========================================
  // LÓGICA MODO PRÁCTICA RÁPIDA (Legacy)
  // ==========================================

  void _manejarSeleccionOpcionPractica(int indice) {
    if (_practicaConAvanceManual) {
      final preguntaActual = widget.preguntas[_indiceActual];
      final indicePrevio = _respuestasRanking[preguntaActual.id];
      _registrarCambioAlternativa(
        preguntaId: preguntaActual.id,
        indicePrevio: indicePrevio,
        nuevoIndice: indice,
      );
      setState(() {
        _respuestasRanking[preguntaActual.id] = indice;
      });
      return;
    }

    if (_practicaConRevisarInmediato) {
      if (_respuestaRevisadaEnPregunta) return;
      _registrarCambioAlternativa(
        preguntaId: widget.preguntas[_indiceActual].id,
        indicePrevio: _indiceOpcionSeleccionadaPractica,
        nuevoIndice: indice,
      );
      setState(() {
        _indiceOpcionSeleccionadaPractica = indice;
      });
      return;
    }

    if (_indiceOpcionSeleccionadaPractica != null) return;

    setState(() {
      _indiceOpcionSeleccionadaPractica = indice;
    });

    _registrarRespuestaPractica(indice);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        _siguientePreguntaPractica();
      }
    });
  }

  void _confirmarRespuestaYAvanzarPractica() {
    final indiceSeleccionado = _practicaConAvanceManual
        ? _respuestasRanking[widget.preguntas[_indiceActual].id]
        : _indiceOpcionSeleccionadaPractica;
    if (indiceSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona una alternativa antes de continuar.'),
        ),
      );
      return;
    }

    if (_practicaConAvanceManual) {
      if (_indiceActual < widget.preguntas.length - 1) {
        _acumularTiempoPreguntaActual();
        setState(() {
          _indiceActual++;
        });
        _iniciarTrackingPreguntaActual();
      } else {
        _acumularTiempoPreguntaActual();
        setState(() {
          _modoRevision = true;
        });
      }
      return;
    }

    _registrarRespuestaPractica(indiceSeleccionado);
    _siguientePreguntaPractica();
  }

  void _revisarRespuestaPracticaActual() {
    final indiceSeleccionado = _indiceOpcionSeleccionadaPractica;
    if (indiceSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona una alternativa antes de revisar.'),
        ),
      );
      return;
    }

    if (_respuestaRevisadaEnPregunta) return;

    _registrarRespuestaPractica(indiceSeleccionado);
    setState(() {
      _respuestaRevisadaEnPregunta = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollAExplicacion();
    });
  }

  void _registrarRespuestaPractica(int indiceSeleccionado) {
    final preguntaActual = widget.preguntas[_indiceActual];
    _acumularTiempoPreguntaActual();
    final esCorrecta =
        indiceSeleccionado == preguntaActual.indiceRespuestaCorrecta;
    final letraSeleccionada = String.fromCharCode(65 + indiceSeleccionado);

    _servicioProgreso.registrarIntento(
      preguntaId: preguntaActual.id,
      respuestaSeleccionada: letraSeleccionada,
      esCorrecta: esCorrecta,
      tiempoSegundos: _tiempoPreguntaSegundos(preguntaActual.id),
      numeroCambiosRespuesta: _cambiosPregunta(preguntaActual.id),
    );

    if (esCorrecta) {
      _puntaje++;
      _preguntasCorrectas.add(preguntaActual);
    } else {
      _preguntasIncorrectas.add(
        IntentoFallido(
          pregunta: preguntaActual,
          indiceIncorrectoSeleccionado: indiceSeleccionado,
          fechaIntento: DateTime.now(),
        ),
      );
      widget.onRespuestaIncorrecta?.call(preguntaActual, indiceSeleccionado);
    }
  }

  void _siguientePreguntaPractica() {
    if (_indiceActual < widget.preguntas.length - 1) {
      _acumularTiempoPreguntaActual();
      setState(() {
        _indiceActual++;
        _indiceOpcionSeleccionadaPractica = null;
        _respuestaRevisadaEnPregunta = false;
      });
      _iniciarTrackingPreguntaActual();
    } else {
      _mostrarDialogoResultados();
    }
  }

  Future<void> _mostrarDialogoResultados() async {
    if (_finalizacionEnCurso) return;
    _finalizacionEnCurso = true;
    _acumularTiempoPreguntaActual();
    _timer.cancel();
    final int segundosUsados = _segundosUsados();

    final materias = _resolverMateriasParaRegistro();
    final respuestasIncorrectas = _preguntasIncorrectas.length;
    final respondidasIds = <String>{
      ..._preguntasCorrectas.map((p) => p.id),
      ..._preguntasIncorrectas.map((i) => i.pregunta.id),
    };
    int respuestasOmitidas = 0;
    for (final pregunta in widget.preguntas) {
      if (respondidasIds.contains(pregunta.id)) continue;
      respuestasOmitidas++;
      _servicioProgreso.registrarIntentoOmitido(
        preguntaId: pregunta.id,
        tiempoSegundos: _tiempoPreguntaSegundos(pregunta.id),
        numeroCambiosRespuesta: _cambiosPregunta(pregunta.id),
      );
    }

    try {
      await _servicioProgreso.registrarSesion(
        totalPreguntas: widget.preguntas.length,
        correctas: _puntaje,
        incorrectas: respuestasIncorrectas,
        omitidas: respuestasOmitidas,
        tiempoSegundos: segundosUsados,
        materiasIncluidas: materias,
        cuentaParaRanking: widget.esRanking,
        registrarHistorial: widget.registrarSesionEnHistorial,
      );

      AuthService.notifyProfileUpdated();

      if (!mounted) return;
      _irPantallaResultados(secondsUsed: segundosUsados);
    } finally {
      _finalizacionEnCurso = false;
    }
  }

  void _irPantallaResultados({required int secondsUsed}) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => PantallaResultados(
          puntaje: _puntaje,
          totalPreguntas: widget.preguntas.length,
          tiempoTranscurrido: Duration(seconds: secondsUsed),
          preguntasCorrectas: _preguntasCorrectas,
          preguntasIncorrectas: _preguntasIncorrectas,
          cuentaParaRanking: widget.esRanking,
          esPracticaGuiada: _sinLimiteTiempo,
          onNuevaPractica: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => PantallaPractica(
                  preguntas: widget.preguntas,
                  esModoPractica: widget.esModoPractica,
                  esRanking: widget.esRanking,
                  avanzarSoloConBotonEnPractica:
                      widget.avanzarSoloConBotonEnPractica,
                  revisarRespuestaInmediata: widget.revisarRespuestaInmediata,
                  registrarSesionEnHistorial: widget.registrarSesionEnHistorial,
                  tiempoLimiteSegundos: widget.tiempoLimiteSegundos,
                  materiasIncluidasParaRegistro:
                      widget.materiasIncluidasParaRegistro,
                ),
              ),
            );
          },
          onVolverInicio: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool esManual = _usaNavegacionManual;
    final bool permiteRevision = esManual || _practicaConAvanceManual;
    final scheme = Theme.of(context).colorScheme;
    final paleta = TemaAplicacion.paleta(context);

    // Si estamos en modo manual y revision, mostramos la lista completa
    if (permiteRevision && _modoRevision) {
      return _buildVistaRevision();
    }

    final pregunta = widget.preguntas[_indiceActual];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              'Pregunta ${_indiceActual + 1}/${widget.preguntas.length}',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            Text(
              _sinLimiteTiempo
                  ? 'Tiempo: ${_formatearTiempo(_segundosTranscurridos)}'
                  : _formatearTiempo(_segundosRestantes),
              style: GoogleFonts.inter(
                fontSize: 14,
                color: _sinLimiteTiempo
                    ? scheme.onSurface.withValues(alpha: 0.78)
                    : (_segundosRestantes < 300
                          ? scheme.error
                          : scheme.onSurface.withValues(alpha: 0.78)),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: scheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: scheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: permiteRevision
            ? [
                TextButton(
                  onPressed: _alternarModoRevision,
                  child: const Text(
                    'Revisar',
                    style: TextStyle(color: TemaAplicacion.colorPrimario),
                  ),
                ),
              ]
            : [],
      ),
      bottomNavigationBar: esManual
          ? _buildNavegacionManualBottomBar()
          : (_practicaConAvanceManual
                ? _buildNavegacionPracticaBottomBar()
                : (_practicaConRevisarInmediato
                      ? _buildNavegacionPracticaInmediataBottomBar()
                      : null)),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tarjeta de Pregunta
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: paleta.surfaceSoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Text(
                      pregunta.materia,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: TemaAplicacion.textoSecundario,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    pregunta.texto,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: TemaAplicacion.textoPrimario,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Opciones
            ...List.generate(pregunta.opciones.length, (indice) {
              bool estaSeleccionado = false;
              bool esCorrecta = false;
              bool mostrarFeedback = false;
              final usaSeleccionSimple = esManual || _practicaConAvanceManual;

              if (esManual) {
                // Modo Examen: Solo mostramos la selección, sin colores de cierto/falso
                estaSeleccionado = _respuestasRanking[pregunta.id] == indice;
              } else {
                // En practica general se mantiene feedback inmediato.
                // En practica desde historial, solo seleccion + boton siguiente.
                estaSeleccionado = _practicaConAvanceManual
                    ? _respuestasRanking[pregunta.id] == indice
                    : _indiceOpcionSeleccionadaPractica == indice;
                mostrarFeedback =
                    !_practicaConAvanceManual &&
                    (_practicaConRevisarInmediato
                        ? _respuestaRevisadaEnPregunta
                        : _indiceOpcionSeleccionadaPractica != null);
                if (mostrarFeedback) {
                  esCorrecta = indice == pregunta.indiceRespuestaCorrecta;
                }
              }

              Color colorBorde = scheme.outlineVariant;
              Color colorFondo = scheme.surface;
              Color colorTexto = TemaAplicacion.textoPrimario;

              if (usaSeleccionSimple) {
                if (estaSeleccionado) {
                  colorBorde = TemaAplicacion.colorPrimario;
                  colorFondo = TemaAplicacion.colorPrimario.withValues(
                    alpha: 0.1,
                  );
                  colorTexto = TemaAplicacion.colorPrimario;
                }
              } else {
                if (mostrarFeedback) {
                  if (esCorrecta) {
                    colorBorde = paleta.feedbackCorrectBorder;
                    colorFondo = paleta.feedbackCorrectBg;
                  } else if (estaSeleccionado && !esCorrecta) {
                    colorBorde = paleta.feedbackIncorrectBorder;
                    colorFondo = paleta.feedbackIncorrectBg;
                  } else if (indice == pregunta.indiceRespuestaCorrecta &&
                      !esCorrecta) {
                    // Mostrar la correcta si fallaste.
                    colorBorde = paleta.feedbackCorrectBorder;
                  }
                } else if (estaSeleccionado) {
                  colorBorde = TemaAplicacion.colorPrimario;
                }
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: (!usaSeleccionSimple && mostrarFeedback)
                      ? null
                      : () => esManual
                            ? _seleccionarRespuestaManual(indice)
                            : _manejarSeleccionOpcionPractica(indice),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorFondo,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorBorde,
                        width: usaSeleccionSimple
                            ? (estaSeleccionado ? 2 : 1)
                            : (estaSeleccionado ||
                                      (mostrarFeedback && esCorrecta)
                                  ? 2
                                  : 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: usaSeleccionSimple
                                ? (estaSeleccionado
                                      ? TemaAplicacion.colorPrimario
                                      : paleta.surfaceSoft)
                                : (mostrarFeedback && esCorrecta)
                                ? paleta.feedbackCorrectBorder
                                : (mostrarFeedback && estaSeleccionado)
                                ? paleta.feedbackIncorrectBorder
                                : paleta.surfaceSoft,
                          ),
                          child: Text(
                            String.fromCharCode(65 + indice),
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: usaSeleccionSimple
                                  ? (estaSeleccionado
                                        ? Colors.white
                                        : TemaAplicacion.textoSecundario)
                                  : (estaSeleccionado ||
                                        (mostrarFeedback &&
                                            (esCorrecta || estaSeleccionado)))
                                  ? Colors.white
                                  : TemaAplicacion.textoSecundario,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            pregunta.opciones[indice],
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              color: colorTexto,
                              fontWeight: usaSeleccionSimple
                                  ? (estaSeleccionado
                                        ? FontWeight.w600
                                        : FontWeight.normal)
                                  : (estaSeleccionado ||
                                        (mostrarFeedback && esCorrecta))
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            if (_practicaConRevisarInmediato &&
                _respuestaRevisadaEnPregunta &&
                _indiceOpcionSeleccionadaPractica != null) ...[
              const SizedBox(height: 8),
              _buildFeedbackRevisionInmediata(pregunta),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackRevisionInmediata(Pregunta pregunta) {
    final scheme = Theme.of(context).colorScheme;
    final paleta = TemaAplicacion.paleta(context);
    final indiceSeleccionado = _indiceOpcionSeleccionadaPractica;
    if (indiceSeleccionado == null) return const SizedBox.shrink();

    final esCorrecta = indiceSeleccionado == pregunta.indiceRespuestaCorrecta;
    final letraSeleccionada = String.fromCharCode(65 + indiceSeleccionado);
    final letraCorrecta = String.fromCharCode(
      65 + pregunta.indiceRespuestaCorrecta,
    );
    final textoCorrecto =
        (pregunta.indiceRespuestaCorrecta >= 0 &&
            pregunta.indiceRespuestaCorrecta < pregunta.opciones.length)
        ? pregunta.opciones[pregunta.indiceRespuestaCorrecta]
        : '';
    final explicacion = pregunta.explicacion.trim();

    return Container(
      key: _feedbackRevisionKey,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: esCorrecta
            ? paleta.feedbackCorrectBg
            : paleta.feedbackIncorrectBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: esCorrecta
              ? paleta.feedbackCorrectBorder
              : paleta.feedbackIncorrectBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            esCorrecta ? 'Correcto' : 'Incorrecto',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: esCorrecta ? paleta.success : scheme.error,
            ),
          ),
          const SizedBox(height: 6),
          if (!esCorrecta)
            Text(
              'Tu respuesta: opcion $letraSeleccionada',
              style: GoogleFonts.inter(fontSize: 13, color: scheme.error),
            ),
          RichText(
            text: TextSpan(
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              children: [
                TextSpan(
                  text: 'Respuesta correcta: opcion $letraCorrecta',
                  style: TextStyle(color: paleta.feedbackCorrectBorder),
                ),
                if (textoCorrecto.trim().isNotEmpty)
                  TextSpan(
                    text: ' - $textoCorrecto',
                    style: TextStyle(color: scheme.onSurface),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Explicacion:',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                if (explicacion.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    explicacion,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavegacionPracticaInmediataBottomBar() {
    final scheme = Theme.of(context).colorScheme;
    final esUltimaPregunta = _indiceActual == widget.preguntas.length - 1;
    final tieneSeleccion = _indiceOpcionSeleccionadaPractica != null;

    final String etiquetaPrincipal = !_respuestaRevisadaEnPregunta
        ? 'Revisar'
        : (esUltimaPregunta ? 'Finalizar' : 'Siguiente');

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: !_respuestaRevisadaEnPregunta
                ? (tieneSeleccion ? _revisarRespuestaPracticaActual : null)
                : (esUltimaPregunta
                      ? _mostrarDialogoResultados
                      : _siguientePreguntaPractica),
            style: ElevatedButton.styleFrom(
              backgroundColor: TemaAplicacion.colorPrimario,
              foregroundColor: scheme.onPrimary,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade600,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              etiquetaPrincipal,
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavegacionPracticaBottomBar() {
    final scheme = Theme.of(context).colorScheme;
    final esUltimaPregunta = _indiceActual == widget.preguntas.length - 1;
    final preguntaActual = widget.preguntas[_indiceActual];
    final tieneSeleccion = _respuestasRanking[preguntaActual.id] != null;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            if (_indiceActual > 0)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _indiceActual--;
                  });
                },
                icon: const Icon(Icons.arrow_back_ios, size: 16),
                label: const Text('Anterior'),
                style: TextButton.styleFrom(
                  foregroundColor: TemaAplicacion.textoSecundario,
                ),
              )
            else
              const SizedBox(width: 88),
            const Spacer(),
            if (esUltimaPregunta) ...[
              OutlinedButton(
                onPressed: tieneSeleccion ? _finalizarExamenRanking : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: TemaAplicacion.colorPrimario,
                  side: BorderSide(
                    color: tieneSeleccion
                        ? TemaAplicacion.colorPrimario
                        : Colors.grey.shade300,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Enviar'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: tieneSeleccion
                    ? _confirmarRespuestaYAvanzarPractica
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: TemaAplicacion.colorPrimario,
                  foregroundColor: scheme.onPrimary,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Revisar'),
              ),
            ] else
              ElevatedButton(
                onPressed: tieneSeleccion
                    ? _confirmarRespuestaYAvanzarPractica
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: TemaAplicacion.colorPrimario,
                  foregroundColor: scheme.onPrimary,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Row(
                  children: [
                    Text('Siguiente'),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_ios, size: 16),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavegacionManualBottomBar() {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            if (_indiceActual > 0)
              TextButton.icon(
                onPressed: _navegarAtras,
                icon: const Icon(Icons.arrow_back_ios, size: 16),
                label: const Text('Anterior'),
                style: TextButton.styleFrom(
                  foregroundColor: TemaAplicacion.textoSecundario,
                ),
              )
            else
              const SizedBox(width: 80),
            const Spacer(),
            if (_indiceActual == widget.preguntas.length - 1) ...[
              OutlinedButton(
                onPressed: _alternarModoRevision,
                style: OutlinedButton.styleFrom(
                  foregroundColor: TemaAplicacion.colorPrimario,
                  side: const BorderSide(color: TemaAplicacion.colorPrimario),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Revisar'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _finalizarExamenRanking,
                style: ElevatedButton.styleFrom(
                  backgroundColor: TemaAplicacion.colorPrimario,
                  foregroundColor: scheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Enviar'),
              ),
            ] else
              ElevatedButton(
                onPressed: _navegarSiguiente,
                style: ElevatedButton.styleFrom(
                  backgroundColor: TemaAplicacion.colorPrimario,
                  foregroundColor: scheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Row(
                  children: [
                    const Text('Siguiente'),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: scheme.onPrimary,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Vista de Revision Ajustada
  Widget _buildVistaRevision() {
    final scheme = Theme.of(context).colorScheme;
    final paleta = TemaAplicacion.paleta(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Revision de Practica'),
        backgroundColor: scheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: scheme.onSurface),
          onPressed: _alternarModoRevision,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: paleta.actionCyan.withValues(alpha: 0.12),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    color: paleta.actionCyan,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _sinLimiteTiempo
                          ? 'Tiempo transcurrido: ${_formatearTiempo(_segundosTranscurridos)}'
                          : 'Tiempo restante: ${_formatearTiempo(_segundosRestantes)}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: widget.preguntas.length,
                itemBuilder: (context, index) {
                  final preg = widget.preguntas[index];
                  final respondida = _respuestasRanking.containsKey(preg.id);
                  final opcionIndex = _respuestasRanking[preg.id];

                  String textRespuesta = "Sin responder";
                  Color colorEstado = paleta.feedbackIncorrectBorder;
                  IconData iconoEstado = Icons.warning_amber_rounded;

                  if (respondida && opcionIndex != null) {
                    final letra = String.fromCharCode(65 + opcionIndex);
                    final textoOpcion =
                        (opcionIndex >= 0 && opcionIndex < preg.opciones.length)
                        ? preg.opciones[opcionIndex]
                        : '';
                    textRespuesta = textoOpcion.trim().isEmpty
                        ? "Opcion $letra"
                        : "Opcion $letra: $textoOpcion";
                    colorEstado = paleta.feedbackCorrectBorder;
                    iconoEstado = Icons.check_circle_outline;
                  }

                  return Card(
                    elevation: 0,
                    color: scheme.surface,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: InkWell(
                      onTap: () => _irAPregunta(index),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Pregunta ${index + 1}',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: respondida
                                        ? paleta.feedbackCorrectBg
                                        : paleta.feedbackIncorrectBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        iconoEstado,
                                        size: 14,
                                        color: colorEstado,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        respondida ? 'Respondida' : 'Pendiente',
                                        style: TextStyle(
                                          color: colorEstado,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              preg.texto,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: scheme.onSurface,
                              ),
                            ),
                            if (respondida) ...[
                              const SizedBox(height: 8),
                              RichText(
                                text: TextSpan(
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  children: [
                                    const TextSpan(text: 'Tu seleccion: '),
                                    TextSpan(
                                      text: textRespuesta,
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _finalizarExamenRanking,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _practicaConAvanceManual
                        ? 'FINALIZAR PRACTICA'
                        : 'ENVIAR RESPUESTAS',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
