import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../modelos/modelo_pregunta.dart';
import 'auth_service.dart';
import 'servicio_notificaciones.dart';
import 'servicio_preguntas.dart';
import 'supabase_service.dart';

class ServicioProgreso {
  final ServicioPreguntas _servicioPreguntas = ServicioPreguntas();
  final List<_IntentoPendiente> _intentosPendientes = [];
  bool _registrandoSesion = false;
  static bool _migrandoInvitadoASupabase = false;
  static const String _prefsGuestStatsKey = 'guest_progress_stats_v1';
  static const String _prefsGuestIncorrectMetaKey =
      'guest_progress_incorrect_meta_v1';
  static const String _prefsGuestSessionsKey = 'guest_progress_sessions_v1';
  static bool _mockDataLoaded = false;
  static Map<String, _MockPreguntaEstado> _mockEstadoPreguntas = {};
  static Map<String, _MockIncorrectMeta> _mockIncorrectasMeta = {};
  static List<SesionPractica> _mockSesiones = [];

  bool get _useSupabase =>
      SupabaseService.isInitialized && AuthService.currentUser != null;

  String?get _usuarioId => AuthService.currentUser?.id;

  /// Migra el progreso local de invitado a Supabase cuando ya existe sesion.
  /// - Sesiones: se copian al historial como practicas migradas.
  /// - Estadisticas por pregunta: se insertan en exposicion_pregunta
  ///   solo cuando no existan previamente para ese usuario.
  Future<bool> migrarProgresoInvitadoASupabase() async {
    if (!_useSupabase) return false;
    final usuarioId = _usuarioId;
    if (usuarioId == null || usuarioId.isEmpty) return false;
    if (_migrandoInvitadoASupabase) return false;

    _migrandoInvitadoASupabase = true;
    try {
      await _asegurarMockPersistidoCargado();
      if (!_tieneDatosMockPersistidos()) return false;

      await _asegurarUsuarioBase();

      final sesionesMigradas = await _migrarSesionesMockASupabase(
        usuarioId: usuarioId,
      );
      final resumen = await _migrarExposicionMockASupabase(
        usuarioId: usuarioId,
      );
      await _actualizarPerfilDesdeResumenMigracion(
        usuarioId: usuarioId,
        resumen: resumen,
      );

      await _limpiarDatosMockPersistidos();

      debugPrint(
        'ServicioProgreso.migrarProgresoInvitadoASupabase: '
        'sesionesMigradas=$sesionesMigradas, '
        'preguntasMigradas=${resumen.preguntasMigradas}',
      );

      return sesionesMigradas > 0 || resumen.preguntasMigradas > 0;
    } catch (e) {
      debugPrint('ServicioProgreso.migrarProgresoInvitadoASupabase error: $e');
      return false;
    } finally {
      _migrandoInvitadoASupabase = false;
    }
  }

  /// Registra el resultado de una respuesta a una pregunta individual.
  /// Se guarda en buffer y se persiste cuando se cierre la sesion.
  Future<void> registrarIntento({
    required String preguntaId,
    required String respuestaSeleccionada,
    required bool esCorrecta,
    int?tiempoSegundos,
    int?numeroCambiosRespuesta,
  }) async {
    final id = preguntaId.trim();
    if (id.isEmpty) return;

    final letra = _normalizarLetra(respuestaSeleccionada);
    if (letra == null) return;

    _intentosPendientes.removeWhere((x) => x.preguntaId == id);
    _intentosPendientes.add(
      _IntentoPendiente(
        preguntaId: id,
        respuestaSeleccionada: letra,
        esCorrecta: esCorrecta,
        tiempoSegundos: tiempoSegundos,
        numeroCambiosRespuesta: numeroCambiosRespuesta,
        fechaIntento: DateTime.now(),
      ),
    );

    debugPrint(
      'ServicioProgreso.registrarIntento: pregunta=$id, '
      'correcta=$esCorrecta, pendientes=${_intentosPendientes.length}, '
      'useSupabase=$_useSupabase, usuarioId=$_usuarioId',
    );
  }

  /// Obtiene la lista de preguntas que el usuario ha fallado.
  Future<List<IntentoFallido>> obtenerPreguntasIncorrectas() async {
    if (!_useSupabase) {
      return _obtenerPreguntasIncorrectasMock();
    }

    try {
      final estadisticas = await obtenerEstadisticasPreguntas();
      if (estadisticas.isEmpty) {
        return _obtenerPreguntasIncorrectasPorUltimoIntento();
      }

      final entradas =
          estadisticas.values.where((s) => s.estaEnIncorrectas).toList()
            ..sort((a, b) => b.totalFallos.compareTo(a.totalFallos));

      if (entradas.isEmpty) return [];

      final ids = entradas.map((s) => s.preguntaId).toList();
      final preguntas = await _servicioPreguntas.obtenerPreguntasPorIds(
        ids: ids,
      );
      if (preguntas.isEmpty) return [];

      final usuarioId = _usuarioId;
      if (usuarioId == null) return [];

      // Recupera el último intento incorrecto por pregunta para mostrar la opción marcada.
      final ultimoIntentoIncorrecto = <String, Map<String, dynamic>>{};
      for (final chunk in _chunkList(ids, 150)) {
        final rows = await SupabaseService.client
            .from('respuesta_usuario')
            .select('pregunta_id, letra_seleccionada, respondida_at')
            .eq('usuario_id', usuarioId)
            .eq('es_correcta', false)
            .inFilter('pregunta_id', chunk)
            .order('respondida_at', ascending: false)
            .limit(10000);

        for (final item in (rows as List<dynamic>)) {
          final row = _toMap(item);
          final preguntaId = row['pregunta_id']?.toString();
          if (preguntaId == null || preguntaId.isEmpty) continue;
          final actual = ultimoIntentoIncorrecto[preguntaId];
          if (actual == null) {
            ultimoIntentoIncorrecto[preguntaId] = row;
            continue;
          }

          final nuevaFecha = _toDateTime(row['respondida_at']);
          final fechaActual = _toDateTime(actual['respondida_at']);
          if (nuevaFecha != null &&
              (fechaActual == null || nuevaFecha.isAfter(fechaActual))) {
            ultimoIntentoIncorrecto[preguntaId] = row;
          }
        }
      }

      final resultado = <IntentoFallido>[];
      for (final pregunta in preguntas) {
        final row = ultimoIntentoIncorrecto[pregunta.id];
        final indice = _indiceDesdeLetra(row?['letra_seleccionada'], pregunta);
        resultado.add(
          IntentoFallido(
            pregunta: pregunta,
            indiceIncorrectoSeleccionado: indice,
            fechaIntento: _toDateTime(row?['respondida_at']),
          ),
        );
      }
      return resultado;
    } catch (e) {
      debugPrint('ServicioProgreso.obtenerPreguntasIncorrectas error: $e');
      return _obtenerPreguntasIncorrectasMock();
    }
  }

  /// Obtiene la lista de preguntas que el usuario ha acertado.
  Future<List<Pregunta>> obtenerPreguntasAcertadas() async {
    if (!_useSupabase) {
      return _obtenerPreguntasAcertadasMock();
    }

    try {
      final estadisticas = await obtenerEstadisticasPreguntas();
      if (estadisticas.isEmpty) {
        return _obtenerPreguntasAcertadasPorUltimoIntento();
      }

      final entradas =
          estadisticas.values.where((s) => s.estaEnAcertadas).toList()
            ..sort((a, b) => b.totalAciertos.compareTo(a.totalAciertos));

      if (entradas.isEmpty) return [];
      final ids = entradas.map((s) => s.preguntaId).toList();
      return _servicioPreguntas.obtenerPreguntasPorIds(ids: ids);
    } catch (e) {
      debugPrint('ServicioProgreso.obtenerPreguntasAcertadas error: $e');
      return _obtenerPreguntasAcertadasMock();
    }
  }

  /// Estadísticas por pregunta (aciertos/fallos + rachas).
  ///
  /// Regla de UI solicitada:
  /// si una pregunta llega a 3 aciertos consecutivos, el contador visible
  /// vuelve a 0 (`aciertosVisibles` en [EstadisticaPregunta]).
  Future<Map<String, EstadisticaPregunta>> obtenerEstadisticasPreguntas({
    List<String>?preguntaIds,
  }) async {
    final idsNormalizados = preguntaIds
        ?.map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    if (!_useSupabase) {
      await _asegurarMockPersistidoCargado();
      return _obtenerEstadisticasMock(preguntaIds: idsNormalizados);
    }

    try {
      final usuarioId = _usuarioId;
      if (usuarioId == null) return {};

      final rows = <Map<String, dynamic>>[];

      if (idsNormalizados != null && idsNormalizados.isNotEmpty) {
        for (final chunk in _chunkList(idsNormalizados, 150)) {
          final pageRaw = await SupabaseService.client
              .from('exposicion_pregunta')
              .select(
                'pregunta_id, total_veces_correcta, total_veces_incorrecta, '
                'racha_correctas_consecutivas, racha_incorrectas_consecutivas',
              )
              .eq('usuario_id', usuarioId)
              .inFilter('pregunta_id', chunk);
          rows.addAll((pageRaw as List<dynamic>).map(_toMap));
        }
      } else {
        const pageSize = 1000;
        var offset = 0;
        while (true) {
          final pageRaw = await SupabaseService.client
              .from('exposicion_pregunta')
              .select(
                'pregunta_id, total_veces_correcta, total_veces_incorrecta, '
                'racha_correctas_consecutivas, racha_incorrectas_consecutivas',
              )
              .eq('usuario_id', usuarioId)
              .order('actualizado_at', ascending: false)
              .range(offset, offset + pageSize - 1);

          final page = (pageRaw as List<dynamic>).map(_toMap).toList();
          if (page.isEmpty) break;
          rows.addAll(page);
          if (page.length < pageSize) break;
          offset += pageSize;
        }
      }

      final resultado = <String, EstadisticaPregunta>{};
      for (final row in rows) {
        final preguntaId = row['pregunta_id']?.toString();
        if (preguntaId == null || preguntaId.isEmpty) continue;
        final totalAciertos = _toInt(row['total_veces_correcta']) ??0;
        final totalFallos = _toInt(row['total_veces_incorrecta']) ??0;
        final rachaAciertos = _toInt(row['racha_correctas_consecutivas']) ??0;
        final rachaFallos = _toInt(row['racha_incorrectas_consecutivas']) ??0;
        bool?ultimoResultado;
        if (rachaAciertos > 0) {
          ultimoResultado = true;
        } else if (rachaFallos > 0) {
          ultimoResultado = false;
        } else if (totalAciertos > 0 && totalFallos == 0) {
          // Primer acierto en la pregunta (racha puede venir en 0).
          ultimoResultado = true;
        } else if (totalFallos > 0 && totalAciertos == 0) {
          // Primer fallo en la pregunta (racha puede venir en 0).
          ultimoResultado = false;
        }

        resultado[preguntaId] = EstadisticaPregunta(
          preguntaId: preguntaId,
          totalAciertos: totalAciertos,
          totalFallos: totalFallos,
          rachaAciertos: rachaAciertos,
          rachaFallos: rachaFallos,
          ultimoResultadoCorrecto: ultimoResultado,
        );
      }

      // Para casos ambiguos (rachas en 0 con aciertos/fallos mixtos), tomamos
      // explícitamente el último resultado desde respuesta_usuario.
      final idsAmbiguos = resultado.values
          .where(
            (s) =>
                s.ultimoResultadoCorrecto == null &&
                (s.totalAciertos > 0 || s.totalFallos > 0),
          )
          .map((s) => s.preguntaId)
          .toList();
      if (idsAmbiguos.isNotEmpty) {
        final ultimoResultadoMap = await _obtenerUltimoResultadoPorPregunta(
          usuarioId: usuarioId,
          preguntaIds: idsAmbiguos,
        );
        for (final id in idsAmbiguos) {
          final actual = resultado[id];
          if (actual == null) continue;
          resultado[id] = EstadisticaPregunta(
            preguntaId: actual.preguntaId,
            totalAciertos: actual.totalAciertos,
            totalFallos: actual.totalFallos,
            rachaAciertos: actual.rachaAciertos,
            rachaFallos: actual.rachaFallos,
            ultimoResultadoCorrecto: ultimoResultadoMap[id],
          );
        }
      }

      // Compatibilidad: si no hay tabla/trigger de exposición cargado
      // pero sí hay respuestas históricas, reconstruimos desde respuesta_usuario.
      if (resultado.isEmpty) {
        final desdeRespuestas = await _obtenerEstadisticasDesdeRespuestas(
          preguntaIds: idsNormalizados,
        );
        if (desdeRespuestas.isNotEmpty) {
          return desdeRespuestas;
        }
      }

      if (idsNormalizados != null && idsNormalizados.isNotEmpty) {
        for (final id in idsNormalizados) {
          resultado.putIfAbsent(
            id,
            () => EstadisticaPregunta(
              preguntaId: id,
              totalAciertos: 0,
              totalFallos: 0,
              rachaAciertos: 0,
              rachaFallos: 0,
              ultimoResultadoCorrecto: null,
            ),
          );
        }
      }

      return resultado;
    } catch (e) {
      debugPrint('ServicioProgreso.obtenerEstadisticasPreguntas error: $e');
      final desdeRespuestas = await _obtenerEstadisticasDesdeRespuestas(
        preguntaIds: idsNormalizados,
      );
      if (desdeRespuestas.isNotEmpty) return desdeRespuestas;
      return _obtenerEstadisticasMock(preguntaIds: idsNormalizados);
    }
  }

  /// Registra una sesion de practica completada.
  Future<void> registrarSesion({
    required int totalPreguntas,
    required int correctas,
    required int incorrectas,
    required int tiempoSegundos,
    required List<String> materiasIncluidas,
    required bool cuentaParaRanking,
    bool registrarHistorial = true,
  }) async {
    if (_registrandoSesion) {
      debugPrint(
        'ServicioProgreso.registrarSesion: llamada duplicada ignorada.',
      );
      return;
    }
    _registrandoSesion = true;

    final porcentaje = totalPreguntas > 0
        ? (correctas / totalPreguntas) * 100
        : 0.0;

    debugPrint(
      'ServicioProgreso.registrarSesion: useSupabase=$_useSupabase, '
      'usuarioId=$_usuarioId, intentosPendientes=${_intentosPendientes.length}, '
      'total=$totalPreguntas, correctas=$correctas, incorrectas=$incorrectas',
    );

    try {
      if (_useSupabase) {
        try {
          final usuarioId = _usuarioId;
          if (usuarioId != null) {
            await _asegurarUsuarioBase();
            String?sesionId;
            if (registrarHistorial) {
              final materiaIds = await _resolverMateriaIds(materiasIncluidas);
              final ahora = DateTime.now();
              final inicio = ahora.subtract(Duration(seconds: tiempoSegundos));
              try {
                final sesionInsert = await SupabaseService.client
                    .from('sesion_practica')
                    .insert({
                      'usuario_id': usuarioId,
                      'tipo_sesion': cuentaParaRanking ?'ranking' : 'practica',
                      'nombre_sesion': cuentaParaRanking
                          ? 'Practica Ranking'
                          : 'Practica Personalizada',
                      'total_preguntas_planeadas': totalPreguntas,
                      'preguntas_respondidas': correctas + incorrectas,
                      'preguntas_correctas': correctas,
                      'preguntas_incorrectas': incorrectas,
                      'fecha_inicio': inicio.toIso8601String(),
                      'fecha_fin': ahora.toIso8601String(),
                      'duracion_real_segundos': tiempoSegundos,
                      'puntaje_obtenido': porcentaje,
                      'aprobado': porcentaje >= 70,
                      'estado': 'finalizada',
                      'completada': true,
                      'materias_incluidas': materiaIds,
                      'metadata': {'cuenta_para_ranking': cuentaParaRanking},
                      'actualizado_at': ahora.toIso8601String(),
                    })
                    .select('id')
                    .single();
                sesionId = _toMap(sesionInsert)['id']?.toString();
              } catch (e) {
                debugPrint(
                  'ServicioProgreso.registrarSesion aviso: no se pudo crear sesion_practica, '
                  'se guardaran intentos sin sesion_id. Error: $e',
                );
              }
            }

            await _persistirIntentosPendientes(
              usuarioId: usuarioId,
              sesionId: sesionId,
            );

            if (registrarHistorial && sesionId != null) {
              await _actualizarRankingUsuario(
                usuarioId: usuarioId,
                totalPreguntas: totalPreguntas,
                correctas: correctas,
                porcentaje: porcentaje,
                cuentaParaRanking: cuentaParaRanking,
              );
            }
          }
        } catch (e) {
          debugPrint('ServicioProgreso.registrarSesion error: $e');
        }
      } else {
        debugPrint(
          'ServicioProgreso.registrarSesion: ejecutando modo mock. '
          'SupabaseInitialized=${SupabaseService.isInitialized}, '
          'AuthCurrentUser=${AuthService.currentUser?.id}',
        );
        await _asegurarMockPersistidoCargado();
        _aplicarIntentosPendientesEnMocks();
        if (registrarHistorial) {
          _mockSesiones.insert(
            0,
            SesionPractica(
              id: 'guest-${DateTime.now().microsecondsSinceEpoch}',
              totalPreguntas: totalPreguntas,
              preguntasCorrectas: correctas,
              preguntasIncorrectas: incorrectas,
              tiempoSegundos: tiempoSegundos,
              cuentaParaRanking: cuentaParaRanking,
              fechaCreacion: DateTime.now(),
            ),
          );
          if (_mockSesiones.length > 500) {
            _mockSesiones = _mockSesiones.sublist(0, 500);
          }
        }
        await _guardarMockPersistido();
        _intentosPendientes.clear();
      }

      if (porcentaje >= 90) {
        final servicioNotif = ServicioNotificaciones();
        await servicioNotif.notificarLogro(
          'Excelente resultado',
          'Has obtenido ${porcentaje.toStringAsFixed(0)}% de aciertos.',
        );
      }
    } finally {
      _registrandoSesion = false;
    }
  }

  /// Obtiene el historial completo de sesiones de practica del usuario.
  Future<List<SesionPractica>> obtenerHistorialSesiones({
    bool?soloRanking,
  }) async {
    if (!_useSupabase) {
      await _asegurarMockPersistidoCargado();
      return _historialMock(soloRanking: soloRanking);
    }

    try {
      final usuarioId = _usuarioId;
      if (usuarioId == null) return [];

      final rows = await SupabaseService.client
          .from('sesion_practica')
          .select(
            'id, tipo_sesion, total_preguntas_planeadas, preguntas_respondidas, '
            'preguntas_correctas, preguntas_incorrectas, duracion_real_segundos, '
            'fecha_inicio, fecha_fin, creado_at, metadata',
          )
          .eq('usuario_id', usuarioId)
          .order('creado_at', ascending: false)
          .limit(1000);

      final sesiones = <SesionPractica>[];
      for (final item in (rows as List<dynamic>)) {
        final row = _toMap(item);

        final totalPreguntas =
            _toInt(row['total_preguntas_planeadas']) ??
            _toInt(row['preguntas_respondidas']) ??
            ((_toInt(row['preguntas_correctas']) ??0) +
                (_toInt(row['preguntas_incorrectas']) ??0));

        final metadata = _toMap(row['metadata']);
        final tipoSesion = _normalizar(row['tipo_sesion']);
        final esRanking =
            metadata['cuenta_para_ranking'] == true ||
            tipoSesion == 'ranking' ||
            totalPreguntas >= 100;

        if (soloRanking == true && !esRanking) continue;
        if (soloRanking == false && esRanking) continue;

        sesiones.add(
          SesionPractica(
            id: row['id']?.toString() ??'',
            totalPreguntas: totalPreguntas,
            preguntasCorrectas: _toInt(row['preguntas_correctas']) ??0,
            preguntasIncorrectas: _toInt(row['preguntas_incorrectas']) ??0,
            tiempoSegundos: _toInt(row['duracion_real_segundos']) ??0,
            cuentaParaRanking: esRanking,
            fechaCreacion:
                _toDateTime(row['fecha_fin']) ??
                _toDateTime(row['creado_at']) ??
                _toDateTime(row['fecha_inicio']) ??
                DateTime.now(),
          ),
        );
      }

      return sesiones;
    } catch (e) {
      debugPrint('ServicioProgreso.obtenerHistorialSesiones error: $e');
      return _historialMock(soloRanking: soloRanking);
    }
  }

  /// Obtiene las preguntas incorrectas de una sesion especifica.
  Future<List<IntentoFallido>> obtenerPreguntasIncorrectasDeSesion({
    required String sesionId,
  }) async {
    final idSesion = sesionId.trim();
    if (idSesion.isEmpty) return [];

    if (!_useSupabase) {
      return [];
    }

    try {
      final usuarioId = _usuarioId;
      if (usuarioId == null) return [];

      final rows = await SupabaseService.client
          .from('respuesta_usuario')
          .select('pregunta_id, letra_seleccionada, respondida_at')
          .eq('usuario_id', usuarioId)
          .eq('sesion_id', idSesion)
          .eq('es_correcta', false)
          .order('respondida_at', ascending: false)
          .limit(300);

      final listaRows = (rows as List<dynamic>).map(_toMap).toList();
      if (listaRows.isEmpty) return [];

      // Conserva solo el intento mas reciente por pregunta dentro de la sesion.
      final intentoPorPregunta = <String, Map<String, dynamic>>{};
      for (final row in listaRows) {
        final preguntaId = row['pregunta_id']?.toString();
        if (preguntaId == null || preguntaId.isEmpty) continue;
        intentoPorPregunta.putIfAbsent(preguntaId, () => row);
      }

      final preguntaIds = intentoPorPregunta.keys.toList();
      if (preguntaIds.isEmpty) return [];

      final preguntas = await _servicioPreguntas.obtenerPreguntasPorIds(
        ids: preguntaIds,
      );
      if (preguntas.isEmpty) return [];

      final preguntaById = {for (final p in preguntas) p.id: p};
      final resultado = <IntentoFallido>[];

      for (final preguntaId in preguntaIds) {
        final row = intentoPorPregunta[preguntaId];
        if (row == null) continue;
        final pregunta = preguntaById[preguntaId];
        if (pregunta == null) continue;

        resultado.add(
          IntentoFallido(
            pregunta: pregunta,
            indiceIncorrectoSeleccionado: _indiceDesdeLetra(
              row['letra_seleccionada'],
              pregunta,
            ),
            fechaIntento: _toDateTime(row['respondida_at']),
          ),
        );
      }

      return resultado;
    } catch (e) {
      debugPrint(
        'ServicioProgreso.obtenerPreguntasIncorrectasDeSesion error: $e',
      );
      return [];
    }
  }

  /// Obtiene estadisticas resumen del historial.
  Future<EstadisticasHistorial> obtenerEstadisticasHistorial() async {
    final sesiones = await obtenerHistorialSesiones();
    if (sesiones.isEmpty) {
      return EstadisticasHistorial(
        totalPracticas: 0,
        promedioGeneral: 0,
        mejorPuntaje: 0,
        aprobadas: 0,
        totalSesiones: 0,
        practicasRanking: 0,
        practicasPersonalizadas: 0,
      );
    }

    double suma = 0;
    double mejor = 0;
    int aprobadas = 0;
    int ranking = 0;

    for (final s in sesiones) {
      final p = s.porcentaje;
      suma += p;
      if (p > mejor) mejor = p;
      if (p >= 70) aprobadas++;
      if (s.cuentaParaRanking) ranking++;
    }

    return EstadisticasHistorial(
      totalPracticas: sesiones.length,
      promedioGeneral: suma / sesiones.length,
      mejorPuntaje: mejor,
      aprobadas: aprobadas,
      totalSesiones: sesiones.length,
      practicasRanking: ranking,
      practicasPersonalizadas: sesiones.length - ranking,
    );
  }

  /// Cantidad total de practicas que cuentan para ranking del usuario actual.
  Future<int> obtenerCantidadPracticasRanking() async {
    try {
      final sesionesRanking = await obtenerHistorialSesiones(soloRanking: true);
      return sesionesRanking.length;
    } catch (e) {
      debugPrint('ServicioProgreso.obtenerCantidadPracticasRanking error: $e');
      return 0;
    }
  }

  Future<void> _persistirIntentosPendientes({
    required String usuarioId,
    String?sesionId,
  }) async {
    if (_intentosPendientes.isEmpty) return;

    final payload = <Map<String, dynamic>>[];
    for (final intento in _intentosPendientes) {
      final row = _buildRespuestaPayload(
        usuarioId: usuarioId,
        intento: intento,
        sesionId: sesionId,
      );
      payload.add(row);
    }

    try {
      await SupabaseService.client.from('respuesta_usuario').insert(payload);
      _intentosPendientes.clear();
      return;
    } catch (e) {
      debugPrint(
        'ServicioProgreso._persistirIntentosPendientes aviso: fallo insercion en lote, '
        'se intentara por filas. Error: $e',
      );
    }

    final pendientes = List<_IntentoPendiente>.from(_intentosPendientes);
    for (final intento in pendientes) {
      final row = _buildRespuestaPayload(
        usuarioId: usuarioId,
        intento: intento,
        sesionId: sesionId,
      );
      try {
        await SupabaseService.client.from('respuesta_usuario').insert(row);
        _intentosPendientes.removeWhere(
          (x) => x.preguntaId == intento.preguntaId,
        );
      } catch (e) {
        debugPrint(
          'ServicioProgreso._persistirIntentosPendientes error en pregunta '
          '${intento.preguntaId}: $e',
        );
      }
    }
  }

  Map<String, dynamic> _buildRespuestaPayload({
    required String usuarioId,
    required _IntentoPendiente intento,
    String?sesionId,
  }) {
    final row = <String, dynamic>{
      'usuario_id': usuarioId,
      'pregunta_id': intento.preguntaId,
      'letra_seleccionada': intento.respuestaSeleccionada,
      'es_correcta': intento.esCorrecta,
      'fue_omitida': false,
      'tiempo_total_respuesta': intento.tiempoSegundos ??0,
      'numero_cambios_respuesta': intento.numeroCambiosRespuesta ??0,
      'respondida_at': intento.fechaIntento.toIso8601String(),
    };
    if (sesionId != null && sesionId.isNotEmpty) {
      row['sesion_id'] = sesionId;
    }
    return row;
  }

  Future<void> _asegurarUsuarioBase() async {
    final user = AuthService.currentUser;
    if (!SupabaseService.isInitialized || user == null) return;

    final existente = await SupabaseService.client
        .from('usuario')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();
    if (existente != null) return;

    final metadata = Map<String, dynamic>.from(user.userMetadata ??{});
    final nombre = _resolverNombreUsuario(metadata, user.email);
    final grado = _resolverGradoUsuario(metadata);

    await SupabaseService.client.from('usuario').insert({
      'id': user.id,
      'user_id': user.id,
      'nombre_completo': nombre,
      'email': user.email,
      'grado_actual': grado,
      'auth_provider': 'supabase',
      'metadata': metadata,
    });
  }

  String _resolverNombreUsuario(Map<String, dynamic> metadata, String?email) {
    final candidatos = [
      metadata['nombre_completo'],
      metadata['full_name'],
      metadata['name'],
      metadata['nombre'],
    ];
    for (final c in candidatos) {
      if (c is String && c.trim().isNotEmpty) return c.trim();
    }
    if (email != null && email.trim().isNotEmpty) {
      return email.split('@').first;
    }
    return 'Usuario';
  }

  String _resolverGradoUsuario(Map<String, dynamic> metadata) {
    final candidatos = [metadata['grado_actual'], metadata['grado']];
    for (final c in candidatos) {
      if (c is String && c.trim().isNotEmpty) return c.trim();
    }
    return 'No definido';
  }

  Future<List<String>> _resolverMateriaIds(List<String> materias) async {
    if (materias.isEmpty) return const [];

    final directos = <String>{};
    final porNombre = <String>{};
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );

    for (final materia in materias) {
      final valor = materia.trim();
      if (valor.isEmpty) continue;
      if (uuidRegex.hasMatch(valor)) {
        directos.add(valor);
      } else {
        porNombre.add(valor);
      }
    }

    if (porNombre.isEmpty) return directos.toList();

    try {
      final rows = await SupabaseService.client
          .from('materia')
          .select('id, nombre')
          .eq('activo', true);

      final byNombre = <String, String>{};
      for (final item in (rows as List<dynamic>)) {
        final row = _toMap(item);
        final id = row['id']?.toString();
        final nombre = row['nombre']?.toString();
        if (id == null || nombre == null) continue;
        byNombre[_normalizar(nombre)] = id;
      }

      final ids = <String>{...directos};
      for (final materia in porNombre) {
        final id = byNombre[_normalizar(materia)];
        if (id != null) ids.add(id);
      }
      return ids.toList();
    } catch (_) {
      return directos.toList();
    }
  }

  Future<void> _actualizarRankingUsuario({
    required String usuarioId,
    required int totalPreguntas,
    required int correctas,
    required double porcentaje,
    required bool cuentaParaRanking,
  }) async {
    final simulacroValido = cuentaParaRanking && totalPreguntas == 100;
    final simulacroAprobado = simulacroValido && porcentaje >= 70;
    if (!simulacroValido) return;
    final puntosGanados = correctas;

    final nowIso = DateTime.now().toIso8601String();

    final actual = await SupabaseService.client
        .from('ranking')
        .select(
          'puntos_totales, puntos_mes_actual, puntos_semana_actual, '
          'simulacros_100_completados, simulacros_aprobados, '
          'mejor_puntaje_simulacro, promedio_simulacros',
        )
        .eq('usuario_id', usuarioId)
        .maybeSingle();

    Map<String, dynamic>?row;
    if (actual == null) {
      final simulacros = simulacroValido ?1 : 0;
      try {
        await SupabaseService.client.from('ranking').insert({
          'usuario_id': usuarioId,
          'puntos_totales': puntosGanados,
          'puntos_mes_actual': puntosGanados,
          'puntos_semana_actual': puntosGanados,
          'simulacros_100_completados': simulacros,
          'simulacros_aprobados': simulacroAprobado ?1 : 0,
          'mejor_puntaje_simulacro': simulacroValido ?porcentaje.round() : 0,
          'promedio_simulacros': simulacroValido ?porcentaje : 0,
          'actualizado_at': nowIso,
          'calculo_ranking_at': nowIso,
        });
        return;
      } catch (e) {
        if (!_esConflictoUnicoRanking(e)) rethrow;
        debugPrint(
          'ServicioProgreso._actualizarRankingUsuario: conflicto detectado, '
          'se reintentara con UPDATE. Error: $e',
        );
        final existente = await SupabaseService.client
            .from('ranking')
            .select(
              'puntos_totales, puntos_mes_actual, puntos_semana_actual, '
              'simulacros_100_completados, simulacros_aprobados, '
              'mejor_puntaje_simulacro, promedio_simulacros',
            )
            .eq('usuario_id', usuarioId)
            .maybeSingle();
        if (existente == null) return;
        row = _toMap(existente);
      }
    } else {
      row = _toMap(actual);
    }

    final prevSimulacros = _toInt(row['simulacros_100_completados']) ??0;
    final prevPromedio = _toDouble(row['promedio_simulacros']) ??0;
    final nuevoSimulacros = prevSimulacros + (simulacroValido ?1 : 0);
    final nuevoPromedio = simulacroValido
        ? ((prevPromedio * prevSimulacros) + porcentaje) / nuevoSimulacros
        : prevPromedio;

    final mejorPrevio = _toInt(row['mejor_puntaje_simulacro']) ??0;
    final nuevoMejor = simulacroValido
        ?(porcentaje.round() > mejorPrevio ?porcentaje.round() : mejorPrevio)
        : mejorPrevio;

    await SupabaseService.client
        .from('ranking')
        .update({
          'puntos_totales':
              (_toInt(row['puntos_totales']) ??0) + puntosGanados,
          'puntos_mes_actual':
              (_toInt(row['puntos_mes_actual']) ??0) + puntosGanados,
          'puntos_semana_actual':
              (_toInt(row['puntos_semana_actual']) ??0) + puntosGanados,
          'simulacros_100_completados': nuevoSimulacros,
          'simulacros_aprobados':
              (_toInt(row['simulacros_aprobados']) ??0) +
              (simulacroAprobado ?1 : 0),
          'mejor_puntaje_simulacro': nuevoMejor,
          'promedio_simulacros': nuevoPromedio,
          'actualizado_at': nowIso,
          'calculo_ranking_at': nowIso,
        })
        .eq('usuario_id', usuarioId);
  }

  bool _esConflictoUnicoRanking(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('23505') || text.contains('ranking_usuario_id_key');
  }

  Future<void> _asegurarMockPersistidoCargado() async {
    if (_mockDataLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      final rawStats = prefs.getString(_prefsGuestStatsKey);
      if (rawStats != null && rawStats.trim().isNotEmpty) {
        final decoded = jsonDecode(rawStats);
        if (decoded is Map) {
          final parsed = <String, _MockPreguntaEstado>{};
          for (final entry in decoded.entries) {
            final preguntaId = entry.key.toString().trim();
            if (preguntaId.isEmpty) continue;
            if (entry.value is! Map) continue;
            parsed[preguntaId] = _MockPreguntaEstado.fromMap(
              Map<String, dynamic>.from(entry.value as Map),
            );
          }
          _mockEstadoPreguntas = parsed;
        }
      }

      final rawIncorrectMeta = prefs.getString(_prefsGuestIncorrectMetaKey);
      if (rawIncorrectMeta != null && rawIncorrectMeta.trim().isNotEmpty) {
        final decoded = jsonDecode(rawIncorrectMeta);
        if (decoded is Map) {
          final parsed = <String, _MockIncorrectMeta>{};
          for (final entry in decoded.entries) {
            final preguntaId = entry.key.toString().trim();
            if (preguntaId.isEmpty) continue;
            if (entry.value is! Map) continue;
            parsed[preguntaId] = _MockIncorrectMeta.fromMap(
              Map<String, dynamic>.from(entry.value as Map),
            );
          }
          _mockIncorrectasMeta = parsed;
        }
      }

      final rawSesiones = prefs.getString(_prefsGuestSessionsKey);
      if (rawSesiones != null && rawSesiones.trim().isNotEmpty) {
        final decoded = jsonDecode(rawSesiones);
        if (decoded is List) {
          _mockSesiones =
              decoded
                  .whereType<Map>()
                  .map((e) => _sesionFromMap(Map<String, dynamic>.from(e)))
                  .toList()
                ..sort((a, b) => b.fechaCreacion.compareTo(a.fechaCreacion));
        }
      }
    } catch (e) {
      debugPrint('ServicioProgreso._asegurarMockPersistidoCargado error: $e');
    } finally {
      _mockDataLoaded = true;
    }
  }

  Future<void> _guardarMockPersistido() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final statsMap = <String, Map<String, dynamic>>{};
      for (final entry in _mockEstadoPreguntas.entries) {
        statsMap[entry.key] = entry.value.toMap();
      }

      final incorrectMetaMap = <String, Map<String, dynamic>>{};
      for (final entry in _mockIncorrectasMeta.entries) {
        incorrectMetaMap[entry.key] = entry.value.toMap();
      }

      final sesiones = _mockSesiones.map(_sesionToMap).toList();

      await prefs.setString(_prefsGuestStatsKey, jsonEncode(statsMap));
      await prefs.setString(
        _prefsGuestIncorrectMetaKey,
        jsonEncode(incorrectMetaMap),
      );
      await prefs.setString(_prefsGuestSessionsKey, jsonEncode(sesiones));
    } catch (e) {
      debugPrint('ServicioProgreso._guardarMockPersistido error: $e');
    }
  }

  bool _tieneDatosMockPersistidos() {
    return _mockEstadoPreguntas.isNotEmpty ||
        _mockIncorrectasMeta.isNotEmpty ||
        _mockSesiones.isNotEmpty;
  }

  Future<void> _limpiarDatosMockPersistidos({SharedPreferences?prefs}) async {
    final storage = prefs ??await SharedPreferences.getInstance();
    await storage.remove(_prefsGuestStatsKey);
    await storage.remove(_prefsGuestIncorrectMetaKey);
    await storage.remove(_prefsGuestSessionsKey);

    _mockEstadoPreguntas = {};
    _mockIncorrectasMeta = {};
    _mockSesiones = [];
    _mockDataLoaded = true;
  }

  Future<int> _migrarSesionesMockASupabase({required String usuarioId}) async {
    if (_mockSesiones.isEmpty) return 0;

    final yaMigradas = await _obtenerGuestSessionIdsYaMigrados(
      usuarioId: usuarioId,
    );
    final sesionesOrdenadas = List<SesionPractica>.from(_mockSesiones)
      ..sort((a, b) => a.fechaCreacion.compareTo(b.fechaCreacion));

    final payload = <Map<String, dynamic>>[];
    for (final sesion in sesionesOrdenadas) {
      final guestSessionId = sesion.id.trim();
      if (guestSessionId.isNotEmpty && yaMigradas.contains(guestSessionId)) {
        continue;
      }

      final totalPreguntas = sesion.totalPreguntas > 0
          ? sesion.totalPreguntas
          : sesion.preguntasCorrectas + sesion.preguntasIncorrectas;
      if (totalPreguntas <= 0) continue;

      final duracionSeg = sesion.tiempoSegundos < 0 ?0 : sesion.tiempoSegundos;
      final fechaFin = sesion.fechaCreacion;
      final fechaInicio = fechaFin.subtract(Duration(seconds: duracionSeg));
      final puntaje = totalPreguntas > 0
          ? (sesion.preguntasCorrectas / totalPreguntas) * 100
          : 0.0;

      payload.add({
        'usuario_id': usuarioId,
        'tipo_sesion': 'practica',
        'nombre_sesion': 'Practica migrada (invitado)',
        'total_preguntas_planeadas': totalPreguntas,
        'preguntas_respondidas':
            sesion.preguntasCorrectas + sesion.preguntasIncorrectas,
        'preguntas_correctas': sesion.preguntasCorrectas,
        'preguntas_incorrectas': sesion.preguntasIncorrectas,
        'fecha_inicio': fechaInicio.toIso8601String(),
        'fecha_fin': fechaFin.toIso8601String(),
        'duracion_real_segundos': duracionSeg,
        'puntaje_obtenido': puntaje,
        'aprobado': puntaje >= 70,
        'estado': 'finalizada',
        'completada': true,
        'metadata': {
          'migrado_desde_invitado': true,
          'guest_session_id': guestSessionId,
          'cuenta_para_ranking_original': sesion.cuentaParaRanking,
          'cuenta_para_ranking': false,
        },
        'actualizado_at': DateTime.now().toIso8601String(),
      });
    }

    if (payload.isEmpty) return 0;

    var insertadas = 0;
    for (final chunk in _chunkList(payload, 100)) {
      try {
        await SupabaseService.client.from('sesion_practica').insert(chunk);
        insertadas += chunk.length;
      } catch (e) {
        debugPrint(
          'ServicioProgreso._migrarSesionesMockASupabase error en chunk: $e',
        );
      }
    }

    return insertadas;
  }

  Future<Set<String>> _obtenerGuestSessionIdsYaMigrados({
    required String usuarioId,
  }) async {
    try {
      final rows = await SupabaseService.client
          .from('sesion_practica')
          .select('metadata')
          .eq('usuario_id', usuarioId)
          .contains('metadata', {'migrado_desde_invitado': true})
          .limit(2000);

      final ids = <String>{};
      for (final item in (rows as List<dynamic>)) {
        final row = _toMap(item);
        final metadata = _toMap(row['metadata']);
        final guestId = metadata['guest_session_id']?.toString().trim() ??'';
        if (guestId.isNotEmpty) ids.add(guestId);
      }
      return ids;
    } catch (_) {
      return <String>{};
    }
  }

  Future<_ResumenMigracionInvitado> _migrarExposicionMockASupabase({
    required String usuarioId,
  }) async {
    if (_mockEstadoPreguntas.isEmpty) {
      return const _ResumenMigracionInvitado();
    }

    final candidatos = _mockEstadoPreguntas.entries.where((entry) {
      final estado = entry.value;
      return (estado.totalAciertos + estado.totalFallos) > 0;
    }).toList();
    if (candidatos.isEmpty) return const _ResumenMigracionInvitado();

    final preguntaIds = candidatos.map((e) => e.key).toList();
    final yaRegistradas = <String>{};
    for (final chunk in _chunkList(preguntaIds, 150)) {
      try {
        final rows = await SupabaseService.client
            .from('exposicion_pregunta')
            .select('pregunta_id')
            .eq('usuario_id', usuarioId)
            .inFilter('pregunta_id', chunk);
        for (final item in (rows as List<dynamic>)) {
          final id = _toMap(item)['pregunta_id']?.toString().trim() ??'';
          if (id.isNotEmpty) yaRegistradas.add(id);
        }
      } catch (e) {
        debugPrint(
          'ServicioProgreso._migrarExposicionMockASupabase aviso al leer existentes: $e',
        );
      }
    }

    final nowIso = DateTime.now().toIso8601String();
    final payload = <Map<String, dynamic>>[];
    var totalRespondidas = 0;
    var totalCorrectas = 0;
    var totalIncorrectas = 0;

    for (final entry in candidatos) {
      final preguntaId = entry.key;
      if (yaRegistradas.contains(preguntaId)) continue;

      final estado = entry.value;
      final total = estado.totalAciertos + estado.totalFallos;
      if (total <= 0) continue;

      payload.add({
        'usuario_id': usuarioId,
        'pregunta_id': preguntaId,
        'total_veces_vista': total,
        'total_veces_correcta': estado.totalAciertos,
        'total_veces_incorrecta': estado.totalFallos,
        'total_veces_omitida': 0,
        'primera_vez_vista': nowIso,
        'ultima_vez_vista': nowIso,
        'primera_vez_correcta': estado.totalAciertos > 0 ?nowIso : null,
        'ultima_vez_incorrecta': estado.totalFallos > 0 ?nowIso : null,
        'racha_correctas_consecutivas': estado.rachaAciertos,
        'racha_incorrectas_consecutivas': estado.rachaFallos,
        'estado_dominio': _estadoDominioDesdeMock(estado),
        'veces_dominada': estado.rachaAciertos >= 3 ?1 : 0,
        'necesita_atencion_especial':
            estado.ultimoResultadoCorrecto == false && estado.totalFallos >= 2,
        'actualizado_at': nowIso,
      });

      totalRespondidas += total;
      totalCorrectas += estado.totalAciertos;
      totalIncorrectas += estado.totalFallos;
    }

    if (payload.isEmpty) return const _ResumenMigracionInvitado();

    var preguntasMigradas = 0;
    for (final chunk in _chunkList(payload, 200)) {
      try {
        await SupabaseService.client.from('exposicion_pregunta').insert(chunk);
        preguntasMigradas += chunk.length;
      } catch (e) {
        debugPrint(
          'ServicioProgreso._migrarExposicionMockASupabase error en chunk: $e',
        );
      }
    }

    if (preguntasMigradas == 0) {
      return const _ResumenMigracionInvitado();
    }

    return _ResumenMigracionInvitado(
      preguntasMigradas: preguntasMigradas,
      totalRespondidas: totalRespondidas,
      totalCorrectas: totalCorrectas,
      totalIncorrectas: totalIncorrectas,
    );
  }

  String _estadoDominioDesdeMock(_MockPreguntaEstado estado) {
    if (estado.rachaAciertos >= 3) return 'dominada';
    if (estado.rachaAciertos > 0) return 'consolidando';
    return 'aprendiendo';
  }

  Future<void> _actualizarPerfilDesdeResumenMigracion({
    required String usuarioId,
    required _ResumenMigracionInvitado resumen,
  }) async {
    if (resumen.totalRespondidas <= 0) return;

    try {
      final existente = await SupabaseService.client
          .from('perfil_usuario')
          .select(
            'id, total_preguntas_respondidas, total_correctas, total_incorrectas, tasa_acierto_global',
          )
          .eq('usuario_id', usuarioId)
          .maybeSingle();

      if (existente == null) {
        final tasa = resumen.totalRespondidas > 0
            ? (resumen.totalCorrectas / resumen.totalRespondidas) * 100
            : 0.0;
        await SupabaseService.client.from('perfil_usuario').insert({
          'usuario_id': usuarioId,
          'total_preguntas_respondidas': resumen.totalRespondidas,
          'total_correctas': resumen.totalCorrectas,
          'total_incorrectas': resumen.totalIncorrectas,
          'total_omitidas': 0,
          'tasa_acierto_global': tasa,
          'actualizado_at': DateTime.now().toIso8601String(),
        });
        return;
      }

      final row = _toMap(existente);
      final respondidasActual = _toInt(row['total_preguntas_respondidas']) ??0;
      final correctasActual = _toInt(row['total_correctas']) ??0;
      final incorrectasActual = _toInt(row['total_incorrectas']) ??0;

      final respondidasNuevo = respondidasActual + resumen.totalRespondidas;
      final correctasNuevo = correctasActual + resumen.totalCorrectas;
      final incorrectasNuevo = incorrectasActual + resumen.totalIncorrectas;
      final tasaNueva = respondidasNuevo > 0
          ? (correctasNuevo / respondidasNuevo) * 100
          : 0.0;

      await SupabaseService.client
          .from('perfil_usuario')
          .update({
            'total_preguntas_respondidas': respondidasNuevo,
            'total_correctas': correctasNuevo,
            'total_incorrectas': incorrectasNuevo,
            'tasa_acierto_global': tasaNueva,
            'actualizado_at': DateTime.now().toIso8601String(),
          })
          .eq('usuario_id', usuarioId);
    } catch (e) {
      debugPrint(
        'ServicioProgreso._actualizarPerfilDesdeResumenMigracion error: $e',
      );
    }
  }

  void _aplicarIntentoEnMocks(_IntentoPendiente intento) {
    final actual =
        _mockEstadoPreguntas[intento.preguntaId] ??
        const _MockPreguntaEstado(
          totalAciertos: 0,
          totalFallos: 0,
          rachaAciertos: 0,
          rachaFallos: 0,
          ultimoResultadoCorrecto: null,
        );

    if (intento.esCorrecta) {
      _mockEstadoPreguntas[intento.preguntaId] = _MockPreguntaEstado(
        totalAciertos: actual.totalAciertos + 1,
        totalFallos: actual.totalFallos,
        rachaAciertos: actual.rachaAciertos + 1,
        rachaFallos: 0,
        ultimoResultadoCorrecto: true,
      );
      _mockIncorrectasMeta.remove(intento.preguntaId);
      return;
    }

    _mockEstadoPreguntas[intento.preguntaId] = _MockPreguntaEstado(
      totalAciertos: actual.totalAciertos,
      totalFallos: actual.totalFallos + 1,
      rachaAciertos: 0,
      rachaFallos: actual.rachaFallos + 1,
      ultimoResultadoCorrecto: false,
    );

    _mockIncorrectasMeta[intento.preguntaId] = _MockIncorrectMeta(
      indiceIncorrectoSeleccionado: _indiceDesdeLetraSimple(
        intento.respuestaSeleccionada,
      ),
      fechaIntento: intento.fechaIntento,
    );
  }

  void _aplicarIntentosPendientesEnMocks() {
    for (final intento in _intentosPendientes) {
      _aplicarIntentoEnMocks(intento);
    }
  }

  List<SesionPractica> _historialMock({bool?soloRanking}) {
    final todas = List<SesionPractica>.from(_mockSesiones)
      ..sort((a, b) => b.fechaCreacion.compareTo(a.fechaCreacion));

    if (soloRanking == true) {
      return todas.where((s) => s.cuentaParaRanking).toList();
    }
    if (soloRanking == false) {
      return todas.where((s) => !s.cuentaParaRanking).toList();
    }
    return todas;
  }

  SesionPractica _sesionFromMap(Map<String, dynamic> map) {
    return SesionPractica(
      id: map['id']?.toString() ??'',
      totalPreguntas: _toInt(map['total_preguntas']) ??0,
      preguntasCorrectas: _toInt(map['preguntas_correctas']) ??0,
      preguntasIncorrectas: _toInt(map['preguntas_incorrectas']) ??0,
      tiempoSegundos: _toInt(map['tiempo_segundos']) ??0,
      cuentaParaRanking: map['cuenta_para_ranking'] == true,
      fechaCreacion: _toDateTime(map['fecha_creacion']) ??DateTime.now(),
    );
  }

  Map<String, dynamic> _sesionToMap(SesionPractica sesion) {
    return {
      'id': sesion.id,
      'total_preguntas': sesion.totalPreguntas,
      'preguntas_correctas': sesion.preguntasCorrectas,
      'preguntas_incorrectas': sesion.preguntasIncorrectas,
      'tiempo_segundos': sesion.tiempoSegundos,
      'cuenta_para_ranking': sesion.cuentaParaRanking,
      'fecha_creacion': sesion.fechaCreacion.toIso8601String(),
    };
  }

  int _indiceDesdeLetraSimple(String letra) {
    final raw = letra.trim().toUpperCase();
    if (raw.isEmpty) return 0;
    final code = raw.codeUnitAt(0) - 65;
    return code < 0 ?0 : code;
  }

  String?_normalizarLetra(String?value) {
    final raw = (value ??'').trim().toUpperCase();
    if (raw.isEmpty) return null;
    return raw.substring(0, 1);
  }

  int _indiceDesdeLetra(dynamic letraRaw, Pregunta pregunta) {
    final letra = _normalizarLetra(letraRaw?.toString());
    if (letra == null) return 0;
    final index = letra.codeUnitAt(0) - 65;
    if (index < 0) return 0;
    if (pregunta.opciones.isEmpty) return 0;
    if (index >= pregunta.opciones.length) return 0;
    return index;
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  int?_toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  double?_toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  DateTime?_toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  String _normalizar(dynamic value) {
    return (value ??'').toString().trim().toLowerCase();
  }

  Future<List<IntentoFallido>>
  _obtenerPreguntasIncorrectasPorUltimoIntento() async {
    final usuarioId = _usuarioId;
    if (usuarioId == null) return [];

    final rows = await SupabaseService.client
        .from('respuesta_usuario')
        .select('pregunta_id, letra_seleccionada, es_correcta, respondida_at')
        .eq('usuario_id', usuarioId)
        .order('respondida_at', ascending: false)
        .limit(10000);

    final latest = <String, Map<String, dynamic>>{};
    for (final item in (rows as List<dynamic>)) {
      final row = _toMap(item);
      final preguntaId = row['pregunta_id']?.toString();
      if (preguntaId == null || preguntaId.isEmpty) continue;
      latest.putIfAbsent(preguntaId, () => row);
    }

    final incorrectas = latest.values
        .where((row) => row['es_correcta'] == false)
        .toList();
    if (incorrectas.isEmpty) return [];

    final ids = incorrectas
        .map((row) => row['pregunta_id'].toString())
        .toList();
    final preguntas = await _servicioPreguntas.obtenerPreguntasPorIds(ids: ids);
    final preguntaById = {for (final p in preguntas) p.id: p};

    final resultado = <IntentoFallido>[];
    for (final row in incorrectas) {
      final preguntaId = row['pregunta_id']?.toString();
      if (preguntaId == null) continue;
      final pregunta = preguntaById[preguntaId];
      if (pregunta == null) continue;

      resultado.add(
        IntentoFallido(
          pregunta: pregunta,
          indiceIncorrectoSeleccionado: _indiceDesdeLetra(
            row['letra_seleccionada'],
            pregunta,
          ),
          fechaIntento: _toDateTime(row['respondida_at']),
        ),
      );
    }
    return resultado;
  }

  Future<List<Pregunta>> _obtenerPreguntasAcertadasPorUltimoIntento() async {
    final usuarioId = _usuarioId;
    if (usuarioId == null) return [];

    final rows = await SupabaseService.client
        .from('respuesta_usuario')
        .select('pregunta_id, es_correcta, respondida_at')
        .eq('usuario_id', usuarioId)
        .order('respondida_at', ascending: false)
        .limit(10000);

    final latest = <String, Map<String, dynamic>>{};
    for (final item in (rows as List<dynamic>)) {
      final row = _toMap(item);
      final preguntaId = row['pregunta_id']?.toString();
      if (preguntaId == null || preguntaId.isEmpty) continue;
      latest.putIfAbsent(preguntaId, () => row);
    }

    final ids = latest.values
        .where((row) => row['es_correcta'] == true)
        .map((row) => row['pregunta_id'].toString())
        .toList();

    if (ids.isEmpty) return [];
    return _servicioPreguntas.obtenerPreguntasPorIds(ids: ids);
  }

  Future<List<Pregunta>> _obtenerPreguntasAcertadasMock() async {
    await _asegurarMockPersistidoCargado();
    final ids =
        _mockEstadoPreguntas.entries
            .where(
              (e) =>
                  e.value.ultimoResultadoCorrecto == true &&
                  e.value.totalAciertos > 0,
            )
            .toList()
          ..sort(
            (a, b) => b.value.totalAciertos.compareTo(a.value.totalAciertos),
          );

    if (ids.isEmpty) return [];
    return _servicioPreguntas.obtenerPreguntasPorIds(
      ids: ids.map((e) => e.key).toList(),
    );
  }

  Future<List<IntentoFallido>> _obtenerPreguntasIncorrectasMock() async {
    await _asegurarMockPersistidoCargado();
    final entradas =
        _mockEstadoPreguntas.entries
            .where(
              (e) =>
                  e.value.ultimoResultadoCorrecto == false &&
                  e.value.totalFallos > 0,
            )
            .toList()
          ..sort((a, b) => b.value.totalFallos.compareTo(a.value.totalFallos));

    if (entradas.isEmpty) return [];
    final ids = entradas.map((e) => e.key).toList();
    final preguntas = await _servicioPreguntas.obtenerPreguntasPorIds(ids: ids);
    if (preguntas.isEmpty) return [];

    final preguntaById = {for (final p in preguntas) p.id: p};
    final resultado = <IntentoFallido>[];
    for (final id in ids) {
      final pregunta = preguntaById[id];
      if (pregunta == null) continue;

      final meta = _mockIncorrectasMeta[id];
      var indice = meta?.indiceIncorrectoSeleccionado ??0;
      if (indice < 0) indice = 0;
      if (pregunta.opciones.isNotEmpty && indice >= pregunta.opciones.length) {
        indice = pregunta.opciones.length - 1;
      }

      resultado.add(
        IntentoFallido(
          pregunta: pregunta,
          indiceIncorrectoSeleccionado: indice,
          fechaIntento: meta?.fechaIntento,
        ),
      );
    }
    return resultado;
  }

  Map<String, EstadisticaPregunta> _obtenerEstadisticasMock({
    List<String>?preguntaIds,
  }) {
    final resultado = <String, EstadisticaPregunta>{};
    for (final entry in _mockEstadoPreguntas.entries) {
      resultado[entry.key] = EstadisticaPregunta(
        preguntaId: entry.key,
        totalAciertos: entry.value.totalAciertos,
        totalFallos: entry.value.totalFallos,
        rachaAciertos: entry.value.rachaAciertos,
        rachaFallos: entry.value.rachaFallos,
        ultimoResultadoCorrecto: entry.value.ultimoResultadoCorrecto,
      );
    }

    if (preguntaIds == null || preguntaIds.isEmpty) return resultado;

    final filtrado = <String, EstadisticaPregunta>{};
    for (final id in preguntaIds) {
      filtrado[id] =
          resultado[id] ??
          EstadisticaPregunta(
            preguntaId: id,
            totalAciertos: 0,
            totalFallos: 0,
            rachaAciertos: 0,
            rachaFallos: 0,
            ultimoResultadoCorrecto: null,
          );
    }
    return filtrado;
  }

  List<List<T>> _chunkList<T>(List<T> items, int size) {
    if (items.isEmpty) return const [];
    final chunks = <List<T>>[];
    for (var i = 0; i < items.length; i += size) {
      final end = (i + size < items.length) ?i + size : items.length;
      chunks.add(items.sublist(i, end));
    }
    return chunks;
  }

  Future<Map<String, EstadisticaPregunta>> _obtenerEstadisticasDesdeRespuestas({
    List<String>?preguntaIds,
  }) async {
    final usuarioId = _usuarioId;
    if (usuarioId == null) return {};

    final rows = <Map<String, dynamic>>[];

    if (preguntaIds != null && preguntaIds.isNotEmpty) {
      for (final chunk in _chunkList(preguntaIds, 150)) {
        final raw = await SupabaseService.client
            .from('respuesta_usuario')
            .select('pregunta_id, es_correcta, respondida_at')
            .eq('usuario_id', usuarioId)
            .inFilter('pregunta_id', chunk)
            .order('respondida_at', ascending: true)
            .limit(10000);
        rows.addAll((raw as List<dynamic>).map(_toMap));
      }
    } else {
      final raw = await SupabaseService.client
          .from('respuesta_usuario')
          .select('pregunta_id, es_correcta, respondida_at')
          .eq('usuario_id', usuarioId)
          .order('respondida_at', ascending: true)
          .limit(10000);
      rows.addAll((raw as List<dynamic>).map(_toMap));
    }

    if (rows.isEmpty) return {};

    final acumulado = <String, _AcumuladorEstadistica>{};
    for (final row in rows) {
      final preguntaId = row['pregunta_id']?.toString();
      if (preguntaId == null || preguntaId.isEmpty) continue;
      final esCorrecta = row['es_correcta'] == true;

      final item = acumulado.putIfAbsent(
        preguntaId,
        () => _AcumuladorEstadistica(),
      );
      if (esCorrecta) {
        item.totalAciertos += 1;
        item.rachaAciertos += 1;
        item.rachaFallos = 0;
      } else {
        item.totalFallos += 1;
        item.rachaFallos += 1;
        item.rachaAciertos = 0;
      }
      item.ultimoResultadoCorrecto = esCorrecta;
    }

    final resultado = <String, EstadisticaPregunta>{};
    for (final entry in acumulado.entries) {
      resultado[entry.key] = EstadisticaPregunta(
        preguntaId: entry.key,
        totalAciertos: entry.value.totalAciertos,
        totalFallos: entry.value.totalFallos,
        rachaAciertos: entry.value.rachaAciertos,
        rachaFallos: entry.value.rachaFallos,
        ultimoResultadoCorrecto: entry.value.ultimoResultadoCorrecto,
      );
    }

    if (preguntaIds != null && preguntaIds.isNotEmpty) {
      for (final id in preguntaIds) {
        resultado.putIfAbsent(
          id,
          () => EstadisticaPregunta(
            preguntaId: id,
            totalAciertos: 0,
            totalFallos: 0,
            rachaAciertos: 0,
            rachaFallos: 0,
            ultimoResultadoCorrecto: null,
          ),
        );
      }
    }

    return resultado;
  }

  Future<Map<String, bool?>> _obtenerUltimoResultadoPorPregunta({
    required String usuarioId,
    required List<String> preguntaIds,
  }) async {
    if (preguntaIds.isEmpty) return const {};

    final latest = <String, Map<String, dynamic>>{};
    for (final chunk in _chunkList(preguntaIds, 150)) {
      final raw = await SupabaseService.client
          .from('respuesta_usuario')
          .select('pregunta_id, es_correcta, respondida_at')
          .eq('usuario_id', usuarioId)
          .inFilter('pregunta_id', chunk)
          .order('respondida_at', ascending: false)
          .limit(10000);

      for (final item in (raw as List<dynamic>)) {
        final row = _toMap(item);
        final preguntaId = row['pregunta_id']?.toString();
        if (preguntaId == null || preguntaId.isEmpty) continue;
        final actual = latest[preguntaId];
        if (actual == null) {
          latest[preguntaId] = row;
          continue;
        }

        final nuevaFecha = _toDateTime(row['respondida_at']);
        final fechaActual = _toDateTime(actual['respondida_at']);
        if (nuevaFecha != null &&
            (fechaActual == null || nuevaFecha.isAfter(fechaActual))) {
          latest[preguntaId] = row;
        }
      }
    }

    final resultado = <String, bool?>{};
    for (final id in preguntaIds) {
      final row = latest[id];
      resultado[id] = row == null ?null : row['es_correcta'] == true;
    }
    return resultado;
  }
}

class EstadisticaPregunta {
  final String preguntaId;
  final int totalAciertos;
  final int totalFallos;
  final int rachaAciertos;
  final int rachaFallos;
  final bool?ultimoResultadoCorrecto;

  const EstadisticaPregunta({
    required this.preguntaId,
    required this.totalAciertos,
    required this.totalFallos,
    required this.rachaAciertos,
    required this.rachaFallos,
    required this.ultimoResultadoCorrecto,
  });

  /// Regla solicitada: cada 3 aciertos seguidos la cuenta visual vuelve a 0.
  int get aciertosVisibles => rachaAciertos % 3;

  int get fallosVisibles => rachaFallos;

  bool get tieneAciertos => totalAciertos > 0;

  bool get tieneFallos => totalFallos > 0;

  bool get estaEnAcertadas => ultimoResultadoCorrecto == true;

  bool get estaEnIncorrectas => ultimoResultadoCorrecto == false;
}

class _ResumenMigracionInvitado {
  final int preguntasMigradas;
  final int totalRespondidas;
  final int totalCorrectas;
  final int totalIncorrectas;

  const _ResumenMigracionInvitado({
    this.preguntasMigradas = 0,
    this.totalRespondidas = 0,
    this.totalCorrectas = 0,
    this.totalIncorrectas = 0,
  });
}

class _IntentoPendiente {
  final String preguntaId;
  final String respuestaSeleccionada;
  final bool esCorrecta;
  final int?tiempoSegundos;
  final int?numeroCambiosRespuesta;
  final DateTime fechaIntento;

  const _IntentoPendiente({
    required this.preguntaId,
    required this.respuestaSeleccionada,
    required this.esCorrecta,
    required this.tiempoSegundos,
    required this.numeroCambiosRespuesta,
    required this.fechaIntento,
  });
}

class _MockPreguntaEstado {
  final int totalAciertos;
  final int totalFallos;
  final int rachaAciertos;
  final int rachaFallos;
  final bool?ultimoResultadoCorrecto;

  const _MockPreguntaEstado({
    required this.totalAciertos,
    required this.totalFallos,
    required this.rachaAciertos,
    required this.rachaFallos,
    required this.ultimoResultadoCorrecto,
  });

  factory _MockPreguntaEstado.fromMap(Map<String, dynamic> map) {
    return _MockPreguntaEstado(
      totalAciertos: (map['total_aciertos'] as num?)?.toInt() ??0,
      totalFallos: (map['total_fallos'] as num?)?.toInt() ??0,
      rachaAciertos: (map['racha_aciertos'] as num?)?.toInt() ??0,
      rachaFallos: (map['racha_fallos'] as num?)?.toInt() ??0,
      ultimoResultadoCorrecto: map['ultimo_resultado_correcto'] is bool
          ? map['ultimo_resultado_correcto'] as bool
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'total_aciertos': totalAciertos,
      'total_fallos': totalFallos,
      'racha_aciertos': rachaAciertos,
      'racha_fallos': rachaFallos,
      'ultimo_resultado_correcto': ultimoResultadoCorrecto,
    };
  }
}

class _MockIncorrectMeta {
  final int indiceIncorrectoSeleccionado;
  final DateTime?fechaIntento;

  const _MockIncorrectMeta({
    required this.indiceIncorrectoSeleccionado,
    required this.fechaIntento,
  });

  factory _MockIncorrectMeta.fromMap(Map<String, dynamic> map) {
    return _MockIncorrectMeta(
      indiceIncorrectoSeleccionado:
          (map['indice_incorrecto_seleccionado'] as num?)?.toInt() ??0,
      fechaIntento: DateTime.tryParse((map['fecha_intento'] ??'').toString()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'indice_incorrecto_seleccionado': indiceIncorrectoSeleccionado,
      'fecha_intento': fechaIntento?.toIso8601String(),
    };
  }
}

class _AcumuladorEstadistica {
  int totalAciertos = 0;
  int totalFallos = 0;
  int rachaAciertos = 0;
  int rachaFallos = 0;
  bool?ultimoResultadoCorrecto;
}

class SesionPractica {
  final String id;
  final int totalPreguntas;
  final int preguntasCorrectas;
  final int preguntasIncorrectas;
  final int tiempoSegundos;
  final bool cuentaParaRanking;
  final DateTime fechaCreacion;

  SesionPractica({
    required this.id,
    required this.totalPreguntas,
    required this.preguntasCorrectas,
    required this.preguntasIncorrectas,
    required this.tiempoSegundos,
    required this.cuentaParaRanking,
    required this.fechaCreacion,
  });

  double get porcentaje =>
      totalPreguntas > 0 ?(preguntasCorrectas / totalPreguntas) * 100 : 0.0;
}

class EstadisticasHistorial {
  final int totalPracticas;
  final double promedioGeneral;
  final double mejorPuntaje;
  final int aprobadas;
  final int totalSesiones;
  final int practicasRanking;
  final int practicasPersonalizadas;

  EstadisticasHistorial({
    required this.totalPracticas,
    required this.promedioGeneral,
    required this.mejorPuntaje,
    required this.aprobadas,
    required this.totalSesiones,
    required this.practicasRanking,
    required this.practicasPersonalizadas,
  });
}
