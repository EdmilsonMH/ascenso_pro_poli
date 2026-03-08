import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../modelos/modelo_pregunta.dart';

// Variables globales para acceso singleton
AudioHandler?audioHandler;
String?errorDeInicializacion;

class AudioPlayerHandler extends BaseAudioHandler {
  final FlutterTts _flutterTts = FlutterTts();
  List<Pregunta> _cola = [];
  int _indice = 0;
  bool _reproduciendo = false;
  bool _ignoreCompletion = false;
  bool _isPaused = false; // Nuevo flag para saber si está pausado

  AudioPlayerHandler() {
    _inicializarTts();
  }

  Future<void> _inicializarTts() async {
    await _flutterTts.setLanguage("es-ES");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);

    // Configuración para permitir background en iOS/Android
    await _flutterTts
        .setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        ]);

    _flutterTts.setCompletionHandler(() {
      print(
        "[TTS] Completion handler called. _reproduciendo=$_reproduciendo, _ignoreCompletion=$_ignoreCompletion, _isPaused=$_isPaused",
      );
      if (_reproduciendo && !_ignoreCompletion && !_isPaused) {
        skipToNext();
      }
    });

    _flutterTts.setErrorHandler((msg) {
      debugPrint("[TTS] Error: $msg");
    });

    _flutterTts.setCancelHandler(() {
      debugPrint("[TTS] Cancel handler called");
    });
  }

  Future<void> cargarCola(List<Pregunta> preguntas) async {
    debugPrint(
      "[AudioHandler] Cargando cola con ${preguntas.length} preguntas",
    );
    _cola = preguntas;
    _indice = 0;
    _isPaused = false;
    // Iniciamos reproducción automática al cargar nueva cola
    play();
  }

  @override
  Future<void> play() async {
    debugPrint("[AudioHandler] play() llamado. Cola length: ${_cola.length}");
    if (_cola.isEmpty) return;
    _reproduciendo = true;
    _isPaused = false;
    _broadcastState();
    await _leerPregunta();
  }

  @override
  Future<void> pause() async {
    debugPrint("[AudioHandler] pause() llamado");
    _reproduciendo = false;
    _isPaused = true;
    _ignoreCompletion = true; // Flag to prevent skipToNext
    await _flutterTts.stop();
    _ignoreCompletion = false;
    _broadcastState();
  }

  @override
  Future<void> stop() async {
    debugPrint("[AudioHandler] stop() llamado");
    _reproduciendo = false;
    _isPaused = false;
    _ignoreCompletion = true;
    await _flutterTts.stop();
    _ignoreCompletion = false;
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  @override
  Future<void> skipToNext() async {
    debugPrint(
      "[AudioHandler] skipToNext() llamado. Índice actual: $_indice, Total: ${_cola.length}",
    );
    if (_indice < _cola.length - 1) {
      _indice++;
    } else {
      // Fin de la lista
      debugPrint("[AudioHandler] Fin de la lista, deteniendo");
      stop();
      return;
    }
    // Always play when skipping manually
    _reproduciendo = true;
    _isPaused = false;
    await _leerPregunta();
  }

  @override
  Future<void> skipToPrevious() async {
    debugPrint(
      "[AudioHandler] skipToPrevious() llamado. Índice actual: $_indice",
    );
    if (_indice > 0) {
      _indice--;
    } else {
      _indice = 0; // Reiniciar primera
    }
    // Always play when skipping manually
    _reproduciendo = true;
    _isPaused = false;
    await _leerPregunta();
  }

  @override
  Future<void> setSpeed(double speed) async {
    debugPrint("[AudioHandler] setSpeed($speed)");
    await _flutterTts.setSpeechRate(speed);
  }

  Future<void> _leerPregunta() async {
    debugPrint("[AudioHandler] _leerPregunta() - Índice: $_indice");
    _ignoreCompletion = true;
    await _flutterTts.stop();
    // Tiny delay to ensure Android TTS engine clears its buffer and state
    await Future.delayed(const Duration(milliseconds: 200));
    _ignoreCompletion = false;

    if (_indice >= _cola.length) {
      debugPrint("[AudioHandler] Índice fuera de rango, deteniendo");
      return;
    }

    Pregunta p = _cola[_indice];
    _actualizarMediaItem(p);
    _broadcastState(); // Asegurar que UI sabe q estamos tocando esta

    String texto = "Pregunta número ${_indice + 1}. ${p.texto}. ";

    // Alternativas
    if (p.opciones.length >= 4) {
      texto += "Alternativa A: ${p.opciones[0]}. ";
      texto += "Alternativa B: ${p.opciones[1]}. ";
      texto += "Alternativa C: ${p.opciones[2]}. ";
      texto += "Alternativa D: ${p.opciones[3]}. ";
    } else {
      for (int i = 0; i < p.opciones.length; i++) {
        texto +=
            "Alternativa ${String.fromCharCode(65 + i)}: ${p.opciones[i]}. ";
      }
    }

    texto += " ... ";
    texto +=
        "La respuesta correcta es: ${p.opciones[p.indiceRespuestaCorrecta]}. ";

    if (p.explicacion.isNotEmpty) {
      texto += "Explicación: ${p.explicacion}. ";
    }

    debugPrint("[AudioHandler] Hablando pregunta ${_indice + 1}");
    await _flutterTts.speak(texto);
  }

  void _actualizarMediaItem(Pregunta p) {
    mediaItem.add(
      MediaItem(
        id: p.id,
        album: "Examen de Ascenso",
        title: "Pregunta ${_indice + 1}",
        artist: p.materia,
        duration: const Duration(
          seconds: 45,
        ), // Duración dummy para la barra de progreso
      ),
    );
  }

  void _broadcastState() {
    debugPrint(
      "[AudioHandler] _broadcastState() - reproduciendo=$_reproduciendo, isPaused=$_isPaused, indice=$_indice",
    );
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (_reproduciendo) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [
          0,
          1,
          2,
        ], // Mostrar botones prev, play, next en notificación compacta
        processingState: _isPaused
            ? AudioProcessingState.ready
            : (_reproduciendo
                  ? AudioProcessingState.ready
                  : AudioProcessingState.idle),
        playing: _reproduciendo,
        queueIndex: _indice,
      ),
    );
  }
}
