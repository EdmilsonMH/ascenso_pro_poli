import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../modelos/modelo_pregunta.dart';
import '../servicios/audio_handler.dart';
import '../servicios/servicio_preguntas.dart';
import '../servicios/servicio_progreso.dart';

class PantallaBalotarioAudioMateriaDetalle extends StatefulWidget {
  final String categoriaUsuario;
  final String materia;

  const PantallaBalotarioAudioMateriaDetalle({
    super.key,
    required this.categoriaUsuario,
    required this.materia,
  });

  @override
  State<PantallaBalotarioAudioMateriaDetalle> createState() =>
      _PantallaBalotarioAudioMateriaDetalleState();
}

class _PantallaBalotarioAudioMateriaDetalleState
    extends State<PantallaBalotarioAudioMateriaDetalle> {
  final ServicioPreguntas _servicioPreguntas = ServicioPreguntas();
  final ServicioProgreso _servicioProgreso = ServicioProgreso();

  bool _cargando = true;
  List<Pregunta> _preguntas = const <Pregunta>[];
  Map<String, EstadisticaPregunta> _estadisticas =
      const <String, EstadisticaPregunta>{};

  int _indiceActual = 0;
  bool _soloRespuestas = false;
  bool _conExplicacion = true;
  bool _pilotoAutomatico = true;

  StreamSubscription<PlaybackState>? _playbackSub;
  int _baseIndiceAudio = 0;
  bool _audioActivoPantalla = false;

  double _escalaTextoPregunta() {
    final ancho = MediaQuery.of(context).size.width;
    if (ancho <= 360) return 0.90;
    if (ancho <= 400) return 0.95;
    return 1.0;
  }

  @override
  void initState() {
    super.initState();
    _escucharAudio();
    _cargarPreguntas();
  }

  @override
  void dispose() {
    _playbackSub?.cancel();
    if (_audioActivoPantalla) {
      audioHandler?.stop();
    }
    super.dispose();
  }

  void _escucharAudio() {
    _playbackSub = audioHandler?.playbackState.listen((state) {
      if (!mounted || !_audioActivoPantalla || _preguntas.isEmpty) return;

      final queueIndex = state.queueIndex ?? 0;
      if (_pilotoAutomatico) {
        final indiceGlobal = (_baseIndiceAudio + queueIndex).clamp(
          0,
          _preguntas.length - 1,
        );
        if (indiceGlobal != _indiceActual) {
          setState(() {
            _indiceActual = indiceGlobal;
          });
        }
      }

      if (state.processingState == AudioProcessingState.idle &&
          !state.playing) {
        _audioActivoPantalla = false;
      }
    });
  }

  Future<void> _cargarPreguntas() async {
    setState(() {
      _cargando = true;
    });

    try {
      final ids = await _servicioPreguntas.obtenerIdsDisponibles(
        categoria: widget.categoriaUsuario,
        materia: widget.materia,
      );

      if (ids.isEmpty) {
        if (!mounted) return;
        setState(() {
          _preguntas = const <Pregunta>[];
          _estadisticas = const <String, EstadisticaPregunta>{};
          _indiceActual = 0;
          _cargando = false;
        });
        return;
      }

      final resultados = await Future.wait([
        _servicioPreguntas.obtenerPreguntasPorIds(
          ids: ids,
          categoria: widget.categoriaUsuario,
          materia: widget.materia,
        ),
        _servicioProgreso.obtenerEstadisticasPreguntas(preguntaIds: ids),
      ]);

      final preguntas = (resultados[0] as List<Pregunta>).toList();
      final estadisticas = (resultados[1] as Map<String, EstadisticaPregunta>)
          .map((key, value) => MapEntry(key.toString(), value));

      int prioridadFallo(EstadisticaPregunta? estadistica) {
        if (estadistica == null) return 0;
        if (estadistica.rachaAciertos >= 3) return 0;
        return estadistica.fallosVisibles;
      }

      preguntas.sort((a, b) {
        final sa = estadisticas[a.id];
        final sb = estadisticas[b.id];

        final byPrioridad = prioridadFallo(sb).compareTo(prioridadFallo(sa));
        if (byPrioridad != 0) return byPrioridad;

        final byTotalFallos = (sb?.totalFallos ?? 0).compareTo(
          sa?.totalFallos ?? 0,
        );
        if (byTotalFallos != 0) return byTotalFallos;

        final byAciertos = (sa?.aciertosVisibles ?? 0).compareTo(
          sb?.aciertosVisibles ?? 0,
        );
        if (byAciertos != 0) return byAciertos;

        return a.numero.compareTo(b.numero);
      });

      if (!mounted) return;
      setState(() {
        _preguntas = preguntas;
        _estadisticas = estadisticas;
        _indiceActual = 0;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preguntas = const <Pregunta>[];
        _estadisticas = const <String, EstadisticaPregunta>{};
        _indiceActual = 0;
        _cargando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo cargar esta materia por ahora.'),
        ),
      );
    }
  }

  Future<void> _iniciarAudioDesdeActual() async {
    if (_preguntas.isEmpty) return;
    if (audioHandler == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio no disponible por ahora.')),
      );
      return;
    }

    final handler = audioHandler;
    if (handler is! AudioPlayerHandler) return;

    final cola = _pilotoAutomatico
        ? _preguntas.sublist(_indiceActual)
        : <Pregunta>[_preguntas[_indiceActual]];

    _baseIndiceAudio = _indiceActual;
    _audioActivoPantalla = true;

    await handler.cargarCola(cola);
  }

  Future<void> _togglePlayPause() async {
    final handler = audioHandler;
    if (handler == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio no disponible por ahora.')),
      );
      return;
    }

    final state = handler.playbackState.value;
    if (state.playing) {
      await handler.pause();
      return;
    }

    if (_audioActivoPantalla &&
        state.processingState == AudioProcessingState.ready) {
      await handler.play();
      return;
    }

    await _iniciarAudioDesdeActual();
  }

  Future<void> _irAnterior() async {
    if (_indiceActual <= 0) return;
    setState(() {
      _indiceActual--;
    });

    final state = audioHandler?.playbackState.value;
    final audioEstabaActivo =
        (state?.playing ?? false) ||
        (state?.processingState == AudioProcessingState.ready);

    if (audioEstabaActivo && _audioActivoPantalla) {
      await _iniciarAudioDesdeActual();
    }
  }

  Future<void> _irSiguiente() async {
    if (_indiceActual >= _preguntas.length - 1) return;
    setState(() {
      _indiceActual++;
    });

    final state = audioHandler?.playbackState.value;
    final audioEstabaActivo =
        (state?.playing ?? false) ||
        (state?.processingState == AudioProcessingState.ready);

    if (audioEstabaActivo && _audioActivoPantalla) {
      await _iniciarAudioDesdeActual();
    }
  }

  Widget _buildSwitches() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: _soloRespuestas,
            onChanged: (value) {
              setState(() {
                _soloRespuestas = value;
              });
            },
            title: Text(
              'Solo respuestas',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF111827),
              ),
            ),
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
            activeThumbColor: const Color(0xFF0F766E),
            activeTrackColor: const Color(0xFF99F6E4),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          ),
          SwitchListTile.adaptive(
            value: _conExplicacion,
            onChanged: (value) {
              setState(() {
                _conExplicacion = value;
              });
            },
            title: Text(
              'Con explicación',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF111827),
              ),
            ),
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
            activeThumbColor: const Color(0xFF0F766E),
            activeTrackColor: const Color(0xFF99F6E4),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          ),
          SwitchListTile.adaptive(
            value: _pilotoAutomatico,
            onChanged: (value) {
              setState(() {
                _pilotoAutomatico = value;
              });
              if (_audioActivoPantalla) {
                _iniciarAudioDesdeActual();
              }
            },
            title: Text(
              'Piloto automatico',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF111827),
              ),
            ),
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
            activeThumbColor: const Color(0xFF0F766E),
            activeTrackColor: const Color(0xFF99F6E4),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicador() {
    if (_preguntas.isEmpty) return const SizedBox.shrink();
    final progreso = (_indiceActual + 1) / _preguntas.length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          Text(
            'Pregunta ${_indiceActual + 1} de ${_preguntas.length}',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progreso,
              minHeight: 6,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF0F766E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreguntaActual() {
    if (_preguntas.isEmpty) {
      return Center(
        child: Text(
          'No hay preguntas disponibles en esta materia.',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: const Color(0xFF6B7280),
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final pregunta = _preguntas[_indiceActual];
    final estadistica = _estadisticas[pregunta.id];
    final explicacion = pregunta.explicacion.trim();
    final escalaTexto = _escalaTextoPregunta();
    final tamPregunta = 14.5 * escalaTexto;
    final tamAlternativa = 13.5 * escalaTexto;
    final tamExplicacion = 12 * escalaTexto;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_indiceActual + 1}. ${pregunta.texto}',
                    style: GoogleFonts.inter(
                      fontSize: tamPregunta,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildChipMetrica(
                  etiqueta: 'Fallos',
                  valor: estadistica?.totalFallos ?? 0,
                  color: const Color(0xFFB91C1C),
                  fondo: const Color(0xFFFEE2E2),
                ),
                const SizedBox(width: 8),
                _buildChipMetrica(
                  etiqueta: 'Aciertos',
                  valor: estadistica?.totalAciertos ?? 0,
                  color: const Color(0xFF166534),
                  fondo: const Color(0xFFDCFCE7),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...List.generate(pregunta.opciones.length, (index) {
              final letra = String.fromCharCode(65 + index);
              final esCorrecta = index == pregunta.indiceRespuestaCorrecta;

              if (_soloRespuestas && !esCorrecta) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '$letra) ${pregunta.opciones[index]}',
                  style: GoogleFonts.inter(
                    fontSize: tamAlternativa,
                    fontWeight: esCorrecta ? FontWeight.w700 : FontWeight.w500,
                    height: 1.22,
                    color: esCorrecta
                        ? const Color(0xFF047857)
                        : const Color(0xFF111827),
                  ),
                ),
              );
            }),
            if (_conExplicacion) ...[
              const SizedBox(height: 6),
              Text(
                explicacion.isNotEmpty
                    ? 'Explicación: $explicacion'
                    : 'Explicación: no disponible para esta pregunta.',
                style: GoogleFonts.inter(
                  fontSize: tamExplicacion,
                  height: 1.25,
                  color: const Color(0xFF1D4ED8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChipMetrica({
    required String etiqueta,
    required int valor,
    required Color color,
    required Color fondo,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$etiqueta: $valor',
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildControlesInferiores() {
    final puedeAnterior = _indiceActual > 0;
    final puedeSiguiente = _indiceActual < _preguntas.length - 1;

    return StreamBuilder<PlaybackState>(
      stream: audioHandler?.playbackState ?? Stream.empty(),
      builder: (context, snapshot) {
        final reproduciendo = snapshot.data?.playing ?? false;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD1D5DB)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: puedeAnterior ? _irAnterior : null,
                icon: Icon(
                  Icons.skip_previous_rounded,
                  size: 34,
                  color: puedeAnterior
                      ? const Color(0xFF0F766E)
                      : const Color(0xFF9CA3AF),
                ),
              ),
              IconButton(
                onPressed: _preguntas.isEmpty ? null : _togglePlayPause,
                icon: Icon(
                  reproduciendo
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  size: 54,
                  color: const Color(0xFF0F766E),
                ),
              ),
              IconButton(
                onPressed: puedeSiguiente ? _irSiguiente : null,
                icon: Icon(
                  Icons.skip_next_rounded,
                  size: 34,
                  color: puedeSiguiente
                      ? const Color(0xFF0F766E)
                      : const Color(0xFF9CA3AF),
                ),
              ),
            ],
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
        titleSpacing: 0,
        title: Text(
          widget.materia,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111827),
          ),
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSwitches(),
                _buildIndicador(),
                Expanded(child: _buildPreguntaActual()),
                _buildControlesInferiores(),
              ],
            ),
    );
  }
}
