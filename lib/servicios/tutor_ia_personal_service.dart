import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'servicio_preguntas.dart';
import 'supabase_service.dart';

class _TutorCacheEntry<T> {
  final T value;
  final DateTime storedAt;

  const _TutorCacheEntry(this.value, this.storedAt);
}

class TutorIAPersonalService {
  // Ya no inicializamos el cliente est?ticamente aqu?para evitar el crash al cargar la clase
  SupabaseClient get _supabase => SupabaseService.client;
  static const bool _habilitarSqlDirecto = false;
  static const String _rpcCoachVelocidadDashboard =
      'fn_tutor_velocidad_dashboard';
  static const int _ventanaRespuestasVelocidad = 2500;
  static const int _ventanaRespuestasVelocidadDetalle = 1200;
  static const int _ventanaRespuestasCoachMemoria = 6000;
  static const int _diasAlertaSinRepaso = 10;
  static const List<int> _ciclosRepasoMemoriaDias = <int>[1, 3, 7, 15];
  static const int _muestraMinimaVelocidad = 10;
  static const double _halfLifeRecenciaDias = 14.0;
  static const Duration _cacheVelocidadTtl = Duration(minutes: 3);
  static const Duration _cacheVelocidadDetalleMateriaTtl = Duration(minutes: 2);
  static const int _maxEntradasCacheVelocidad = 3000;

  static final Map<String, _TutorCacheEntry<Map<String, dynamic>>>
  _cacheCoachVelocidad = {};
  static final Map<String, Future<Map<String, dynamic>>>
  _inflightCoachVelocidad = {};
  static final Map<String, _TutorCacheEntry<List<Map<String, dynamic>>>>
  _cachePreguntasLentasMateria = {};
  static final Map<String, Future<List<Map<String, dynamic>>>>
  _inflightPreguntasLentasMateria = {};
  static final Map<String, _TutorCacheEntry<List<Map<String, dynamic>>>>
  _cachePreguntasImpulsivasMateria = {};
  static final Map<String, Future<List<Map<String, dynamic>>>>
  _inflightPreguntasImpulsivasMateria = {};

  /// 1.1 ??An?lisis Completo del Perfil
  /// Analiza el perfil completo del usuario y genera un diagn?stico detallado.
  Future<Map<String, dynamic>> analizarPerfilCompleto(
    String userId, {
    Map<String, dynamic>? perfilUsuario,
  }) async {
    if (!SupabaseService.isInitialized) {
      debugPrint(
        'ADVERTENCIA: Supabase no inicializado. Devolviendo estado sin datos verificables del Tutor.',
      );
      return _generarDatosMockEmergencia();
    }

    try {
      // 1) perfil_usuario
      final perfil =
          await _supabase
              .from('perfil_usuario')
              .select('*')
              .eq('usuario_id', userId)
              .maybeSingle() ??
          <String, dynamic>{};

      // 2) dominio_materia + materia
      var dominios = <Map<String, dynamic>>[];
      try {
        final List<dynamic> dominiosResponse = await _supabase
            .from('dominio_materia')
            .select(
              'materia_id, tasa_dominio, dominio_hace_7_dias, tiempo_recomendado_minutos, '
              'materia:materia_id(id, nombre, codigo, categoria, total_preguntas_banco)',
            )
            .eq('usuario_id', userId);
        dominios = dominiosResponse
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (e) {
        debugPrint('TutorIA: error leyendo dominio_materia: $e');
      }

      // 3) exposicion_pregunta (preguntas dominadas verificadas por pregunta)
      final totalDominadas = await _contarPreguntasDominadasUsuario(userId);

      // 4) respuesta_usuario (acierto real + velocidad real)
      final List<dynamic> respuestasResponse = await _supabase
          .from('respuesta_usuario')
          .select('es_correcta, fue_omitida, tiempo_total_respuesta')
          .eq('usuario_id', userId);
      final respuestas = respuestasResponse
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final respuestasValidas = respuestas.where((r) {
        final omitida = r['fue_omitida'] == true;
        final esCorrecta = r['es_correcta'];
        return !omitida && esCorrecta is bool;
      }).toList();

      final inferidos = await _construirDominiosDesdeRespuestas(userId);
      if (inferidos.isNotEmpty) {
        dominios = _fusionarDominios(base: dominios, inferidos: inferidos);
      } else if (dominios.isEmpty ||
          dominios.every((d) => (_obtenerTasaDominio(d) ?? 0) <= 0)) {
        dominios = const <Map<String, dynamic>>[];
      }

      final totalRespuestas = respuestasValidas.length;
      final totalCorrectas = respuestasValidas
          .where((r) => r['es_correcta'] == true)
          .length;
      final tasaAciertoPorRespuestas = totalRespuestas > 0
          ? (totalCorrectas * 100.0) / totalRespuestas
          : 0.0;

      final tiempos = respuestasValidas
          .map((r) => _toDouble(r['tiempo_total_respuesta']))
          .whereType<double>()
          .where((t) => t > 0)
          .toList();
      final velocidadPorRespuestas = tiempos.isNotEmpty
          ? tiempos.reduce((a, b) => a + b) / tiempos.length
          : 0.0;

      // tiempo total estudiado desde estadistica_usuario
      final estadistica =
          await _supabase
              .from('estadistica_usuario')
              .select('tiempo_total_estudio_minutos')
              .eq('usuario_id', userId)
              .maybeSingle() ??
          <String, dynamic>{};

      final tiempoTotalMinutos = _toInt(
        estadistica['tiempo_total_estudio_minutos'],
      );
      final tasaAciertoPerfil = _toDouble(perfil['tasa_acierto_global']) ?? 0.0;
      final velocidadPerfil =
          _toDouble(perfil['velocidad_promedio_segundos']) ?? 0.0;
      final tasaAcierto = tasaAciertoPerfil > 0
          ? tasaAciertoPerfil
          : tasaAciertoPorRespuestas;
      final velocidadPromedio = velocidadPerfil > 0
          ? velocidadPerfil
          : velocidadPorRespuestas;
      final rachaDias = _toInt(perfil['dias_consecutivos_estudio']);

      final nivel = _calcularNivelGlobal({
        ...perfil,
        'tasa_acierto_global': tasaAcierto,
      });
      final fortalezas = _identificarFortalezas(dominios);
      final debilidades = _identificarDebilidades(dominios);
      final analisisMaterias = _construirAnalisisMaterias(dominios);

      final panelIa = await _generarPanelIA(
        nivel: nivel,
        fortalezas: fortalezas,
        debilidades: debilidades,
        tasaAcierto: tasaAcierto,
        rachaDias: rachaDias,
        preguntasDominadas: totalDominadas,
        tiempoTotalMinutos: tiempoTotalMinutos,
        categoria: perfilUsuario?['categoria'],
        gradoActual: perfilUsuario?['grado_actual'] ?? perfilUsuario?['grado'],
        especialidad:
            perfilUsuario?['especialidad'] ?? perfilUsuario?['arma_servicio'],
        metaDiariaMinutos:
            perfilUsuario?['meta_diaria_minutos'] ?? perfilUsuario?['meta'],
      );

      final diagnostico =
          (panelIa['diagnostico'] is String && panelIa['diagnostico'] != '')
          ? panelIa['diagnostico']
          : _generarDiagnosticoBasico(nivel, debilidades);
      final resumenMaterias = await _generarResumenMaterias(
        nivel: nivel,
        analisisMaterias: analisisMaterias,
        fortalezas: fortalezas,
        debilidades: debilidades,
      );

      return {
        'nivel_global': nivel,
        'fortalezas': fortalezas,
        'debilidades': debilidades,
        'analisis_materias': analisisMaterias,
        'resumen_materias': resumenMaterias,
        'materias_criticas': _obtenerMateriasCriticas(dominios),
        'preguntas_dominadas': totalDominadas,
        'tasa_acierto': tasaAcierto,
        'velocidad_promedio': velocidadPromedio,
        'diagnostico': diagnostico,
        'racha_dias': rachaDias,
        'tiempo_total_estudio': tiempoTotalMinutos,
        'panel_ia': panelIa,
      };
    } catch (e) {
      debugPrint('Error en analizarPerfilCompleto: $e');
      try {
        final dominiosInferidos = await _construirDominiosDesdeRespuestas(
          userId,
        );
        if (dominiosInferidos.isNotEmpty) {
          final analisisMaterias = _construirAnalisisMaterias(
            dominiosInferidos,
          );
          final fortalezas = _identificarFortalezas(dominiosInferidos);
          final debilidades = _identificarDebilidades(dominiosInferidos);
          final tasaAciertoPromedio = analisisMaterias.isEmpty
              ? 0.0
              : analisisMaterias
                        .map((m) => _toDouble(m['porcentaje']) ?? 0.0)
                        .reduce((a, b) => a + b) /
                    analisisMaterias.length;
          final nivel = _nivelMateria(tasaAciertoPromedio);
          return {
            'nivel_global': nivel,
            'fortalezas': fortalezas,
            'debilidades': debilidades,
            'analisis_materias': analisisMaterias,
            'resumen_materias': _resumenMateriasFallback(
              analisisMaterias: analisisMaterias,
              fortalezas: fortalezas,
              debilidades: debilidades,
            ),
            'materias_criticas': _obtenerMateriasCriticas(dominiosInferidos),
            'preguntas_dominadas': 0,
            'tasa_acierto': tasaAciertoPromedio,
            'velocidad_promedio': 0.0,
            'diagnostico': _generarDiagnosticoBasico(nivel, debilidades),
            'racha_dias': 0,
            'tiempo_total_estudio': 0,
            'panel_ia': _panelBasico(nivel, debilidades),
          };
        }
      } catch (_) {}
      return _generarDatosMockEmergencia();
    }
  }

  Future<Map<String, dynamic>> obtenerDashboardTutorInicio({
    required String userId,
    required Map<String, dynamic> perfilUsuario,
  }) async {
    final usuario = userId.trim();
    if (!SupabaseService.isInitialized || _sesionInvalida(usuario)) {
      return _dashboardInicioFallback(
        nivel: 'INICIAL',
        racha: 0,
        aprobacion: 0,
        mensaje:
            'Necesito una sesion valida para generar tu tablero inteligente.',
      );
    }

    try {
      final analisis = await analizarPerfilCompleto(
        usuario,
        perfilUsuario: perfilUsuario,
      );
      final params = <String, dynamic>{'p_usuario_id': usuario};
      final plan = await _rpcComoMapa(
        functionName: 'fn_generar_plan_adaptativo',
        params: params,
      );
      final progreso = await _rpcComoMapa(
        functionName: 'fn_calcular_progreso_dinamico',
        params: params,
      );

      final progresoHoy = await _obtenerProgresoHoy(usuario);
      final metaHoy = await _obtenerMetaDiariaHoy(usuario);
      final proyeccionDetalle = await obtenerProyeccionTiempoDetalle(
        userId: usuario,
        categoriaUsuario: (perfilUsuario['categoria'] ?? '').toString(),
        progresoBase: progreso,
        planBase: plan,
      );
      final planHoy = await obtenerResumenPlanDiarioEstructurado(
        userId: usuario,
        planBase: plan,
        progresoBase: progreso,
        proyeccionBase: proyeccionDetalle,
      );
      final queEstudiar = await obtenerResumenQueEstudiarEstructurado(
        userId: usuario,
        perfilUsuario: perfilUsuario,
      );
      final velocidad = await obtenerAnalisisVelocidadEstructurado(
        userId: usuario,
      );
      final coachMemoria = await obtenerCoachMemoriaEstructurado(
        userId: usuario,
      );

      final preguntasObjetivo = _resolverPreguntasObjetivo(
        metaHoy: metaHoy,
        plan: plan,
      );
      final minutosObjetivo = _resolverMinutosObjetivo(
        metaHoy: metaHoy,
        plan: plan,
        perfilUsuario: perfilUsuario,
      );
      final preguntasCompletadas = _toInt(progresoHoy['respondidas']);
      final minutosCompletados = _toInt(progresoHoy['minutos']);
      final dominadasHoy = _toInt(progresoHoy['correctas']);
      final aprobacion =
          _toDouble(proyeccionDetalle['probabilidad_aprobacion']) ??
          _toDouble(analisis['tasa_acierto']) ??
          0.0;
      final racha = _toInt(analisis['racha_dias']);
      final nivel = (analisis['nivel_global'] ?? 'INICIAL').toString();

      final resumenProyeccion = (proyeccionDetalle['resumen'] ?? '')
          .toString()
          .trim();
      final detalleProyeccion = (proyeccionDetalle['detalle'] ?? '')
          .toString()
          .trim();
      final radarRiesgoMateria = _construirCardRadarRiesgoMateria(
        analisis: analisis,
      );
      final proyeccionTiempo = {
        'id': 'proyeccion_tiempo',
        'titulo': 'Proyeccion de Tiempo para Completar',
        'resumen': resumenProyeccion.isEmpty
            ? 'No se pudo calcular la proyeccion en este momento.'
            : resumenProyeccion,
        'detalle': detalleProyeccion,
        'prompt': 'dame mi plan diario',
        'cta': 'Ver proyeccion',
        'color': '#93C5FD',
        'icono': 'schedule',
        'expandable': true,
      };

      final resumenMision =
          'Hoy llevas $preguntasCompletadas/$preguntasObjetivo preguntas y $minutosCompletados/$minutosObjetivo minutos.';

      return {
        'estado': 'ok',
        'sesion_valida': true,
        'hero': {
          'nivel': nivel,
          'aprobacion': aprobacion,
          'dominadas_hoy': dominadasHoy,
          'racha_dias': racha,
        },
        'mision_diaria': {
          'preguntas_objetivo': preguntasObjetivo,
          'minutos_objetivo': minutosObjetivo,
          'preguntas_completadas': preguntasCompletadas,
          'minutos_completados': minutosCompletados,
          'cantidad_practica': _toInt(planHoy['cantidad_practica']) > 0
              ? _toInt(planHoy['cantidad_practica'])
              : preguntasObjetivo.clamp(10, 60),
          'tiempo_practica': _toInt(planHoy['tiempo_practica']) > 0
              ? _toInt(planHoy['tiempo_practica'])
              : minutosObjetivo.clamp(15, 90),
          'resumen': resumenMision,
          'cta_habilitada': true,
        },
        'insights': [
          {
            'id': 'analisis_perfil',
            'titulo': 'Analisis Completo de tu Perfil',
            'resumen': (analisis['diagnostico'] ?? '').toString(),
            'detalle':
                'Nivel: $nivel. Tasa acierto: ${(_toDouble(analisis['tasa_acierto']) ?? 0).toStringAsFixed(1)}%. Debilidades: ${_toStringList(analisis['debilidades']).join(', ')}.',
            'prompt': 'dame mi plan diario',
            'cta': 'Ver estrategia',
            'color': '#FDE68A',
            'icono': 'insights',
            'expandable': true,
          },
          planHoy,
          queEstudiar,
          coachMemoria,
          velocidad,
          radarRiesgoMateria,
          proyeccionTiempo,
        ],
        'atajos_chat': _atajosTutorInicio(),
      };
    } catch (e) {
      debugPrint('Error obtenerDashboardTutorInicio: $e');
      return _dashboardInicioFallback(
        nivel: 'INICIAL',
        racha: 0,
        aprobacion: 0,
        mensaje:
            'No pude cargar tu tablero IA completo. Puedes usar las funciones del chat.',
      );
    }
  }

  Future<Map<String, dynamic>> obtenerAnalisisCompletoPerfilDetallado({
    required String userId,
    String? categoriaUsuario,
    Map<String, dynamic>? analisisBase,
  }) async {
    // Se mantiene por compatibilidad de firma; este analisis se calcula
    // exclusivamente con consultas reales a Supabase.
    final _ = analisisBase;
    final categoriaNormalizada = (categoriaUsuario ?? '').trim();

    if (_sesionInvalida(userId)) {
      return _analisisCompletoPerfilFallbackTecnico(
        estado: 'sin_sesion',
        mensaje: 'Inicia sesion para calcular tu analisis completo de perfil.',
      );
    }

    bool sesionCompletada(Map<String, dynamic> row) =>
        row['completada'] == true || row['estado'] == 'completada';

    int respondidasSesion(Map<String, dynamic> row) {
      final guardado = _toInt(row['preguntas_respondidas']);
      if (guardado > 0) return guardado;
      return _toInt(row['preguntas_correctas']) +
          _toInt(row['preguntas_incorrectas']) +
          _toInt(row['preguntas_omitidas']);
    }

    bool esSimulacro(Map<String, dynamic> row) {
      final tipo = _normalizarTexto((row['tipo_sesion'] ?? '').toString());
      final totalPlaneadas = _toInt(row['total_preguntas_planeadas']);
      return tipo.contains('simulacro') ||
          tipo.contains('ranking') ||
          totalPlaneadas >= 100;
    }

    double promedio(List<double> values) {
      if (values.isEmpty) return 0.0;
      return values.reduce((a, b) => a + b) / values.length;
    }

    double desviacion(List<double> values) {
      if (values.length <= 1) return 0.0;
      final mean = promedio(values);
      final suma = values.fold<double>(
        0.0,
        (acc, v) => acc + (v - mean) * (v - mean),
      );
      return math.sqrt(suma / values.length);
    }

    double pendienteLineal(List<double> values) {
      if (values.length <= 1) return 0.0;
      final n = values.length.toDouble();
      var sumX = 0.0;
      var sumY = 0.0;
      var sumXY = 0.0;
      var sumX2 = 0.0;
      for (var i = 0; i < values.length; i++) {
        final x = i.toDouble();
        final y = values[i];
        sumX += x;
        sumY += y;
        sumXY += x * y;
        sumX2 += x * x;
      }
      final den = (n * sumX2) - (sumX * sumX);
      if (den.abs() < 1e-9) return 0.0;
      return ((n * sumXY) - (sumX * sumY)) / den;
    }

    String nivelVolatilidad(double variacion) {
      if (variacion < 5.0) return 'alta';
      if (variacion <= 10.0) return 'media';
      return 'baja';
    }

    Map<String, dynamic> nivelPostulanteDesdePct(double porcentaje) {
      final pct = porcentaje.clamp(0.0, 100.0);
      if (pct <= 20.0) {
        return {'nombre': 'Muy Bajo', 'rango': '1% - 20%', 'acierto_pct': pct};
      }
      if (pct <= 40.0) {
        return {
          'nombre': 'Principiante',
          'rango': '21% - 40%',
          'acierto_pct': pct,
        };
      }
      if (pct <= 60.0) {
        return {
          'nombre': 'Intermedio',
          'rango': '41% - 60%',
          'acierto_pct': pct,
        };
      }
      if (pct <= 80.0) {
        return {'nombre': 'Avanzado', 'rango': '61% - 80%', 'acierto_pct': pct};
      }
      return {
        'nombre': 'Competitivo / Listo para examen',
        'rango': '81% - 100%',
        'acierto_pct': pct,
      };
    }

    double pctInt(int part, int total) =>
        total > 0 ? (part * 100.0) / total : 0.0;

    String mensajeResumenDesdeMetricas({
      required double tasaAciertoGlobal,
      required int totalNoOmitidas,
      required int totalSub20,
      required double pctErrorSobreSub20,
    }) {
      if (totalNoOmitidas <= 0) {
        return 'Aun no hay respuestas suficientes en Supabase para generar tu analisis.';
      }
      if (totalSub20 >= 10 && pctErrorSobreSub20 >= 35.0) {
        return 'Vas avanzando. Reduce un poco la velocidad y prioriza precision en preguntas clave.';
      }
      if (tasaAciertoGlobal >= 75.0) {
        return 'Buen nivel de rendimiento. Mantiene tu constancia para consolidar resultados.';
      }
      if (tasaAciertoGlobal >= 50.0) {
        return 'Buen progreso. Con practica diaria puedes subir al siguiente nivel.';
      }
      return 'Estas construyendo base. Prioriza sesiones cortas y consistentes para mejorar.';
    }

    try {
      final resultados = await Future.wait<dynamic>([
        _supabase
            .from('perfil_usuario')
            .select(
              'total_preguntas_respondidas, total_correctas, total_incorrectas, tasa_acierto_global',
            )
            .eq('usuario_id', userId)
            .maybeSingle(),
        _supabase
            .from('respuesta_usuario')
            .select(
              'pregunta_id, respondida_at, es_correcta, fue_omitida, '
              'tiempo_total_respuesta, numero_cambios_respuesta, tipo_error',
            )
            .eq('usuario_id', userId)
            .order('respondida_at', ascending: false)
            .limit(6000),
        _supabase
            .from('sesion_practica')
            .select(
              'tipo_sesion, completada, estado, preguntas_correctas, preguntas_incorrectas, '
              'preguntas_omitidas, preguntas_respondidas, puntaje_obtenido, total_preguntas_planeadas, '
              'fecha_inicio, duracion_real_segundos',
            )
            .eq('usuario_id', userId)
            .order('fecha_inicio', ascending: false)
            .limit(1200),
        _supabase
            .from('exposicion_pregunta')
            .select(
              'pregunta_id, total_veces_correcta, total_veces_incorrecta, racha_correctas_consecutivas',
            )
            .eq('usuario_id', userId)
            .limit(4000),
      ]);

      final perfilRaw = resultados[0];
      final perfil = perfilRaw is Map
          ? Map<String, dynamic>.from(perfilRaw)
          : <String, dynamic>{};

      final respuestasRaw = resultados[1];
      final respuestas = respuestasRaw is List
          ? respuestasRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      final sesionesRaw = resultados[2];
      final sesiones = sesionesRaw is List
          ? sesionesRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      final exposicionRaw = resultados[3];
      final exposiciones = exposicionRaw is List
          ? exposicionRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      final sinDatosReales =
          perfil.isEmpty &&
          respuestas.isEmpty &&
          sesiones.isEmpty &&
          exposiciones.isEmpty;
      if (sinDatosReales) {
        return _analisisCompletoPerfilFallbackTecnico(
          estado: 'sin_datos',
          mensaje: categoriaNormalizada.isEmpty
              ? 'Aun no hay datos reales en Supabase para construir tu analisis.'
              : 'Aun no hay datos reales en Supabase para construir tu analisis de $categoriaNormalizada.',
        );
      }

      final now = DateTime.now();

      var totalNoOmitidas = 0;
      var totalCorrectas = 0;
      var totalIncorrectas = 0;
      var totalOmitidas = 0;
      var totalCambiadas = 0;

      var tiempoLt30 = 0;
      var tiempo30a60 = 0;
      var tiempo60a90 = 0;
      var tiempoGt90 = 0;
      var totalConTiempo = 0;
      var sumaTiempoValido = 0.0;

      var totalSub20 = 0;
      var erroresSub20 = 0;

      final weekTotal = List<int>.filled(8, 0);
      final weekCorrect = List<int>.filled(8, 0);
      var segundosRespuestas14d = 0.0;

      final eventosPorPregunta = <String, List<Map<String, dynamic>>>{};
      final eventosCurva = <Map<String, dynamic>>[];

      for (final row in respuestas) {
        final omitida = row['fue_omitida'] == true;
        final esCorrectaRaw = row['es_correcta'];
        final esCorrecta = esCorrectaRaw is bool ? esCorrectaRaw : null;
        final cambios = _toInt(row['numero_cambios_respuesta']);
        final tiempo = _toDouble(row['tiempo_total_respuesta']) ?? 0.0;
        final fecha = _parseFechaFlexible(row['respondida_at']);
        final preguntaId = (row['pregunta_id'] ?? '').toString().trim();

        if (omitida) {
          totalOmitidas++;
        } else if (esCorrecta != null) {
          totalNoOmitidas++;
          if (esCorrecta) {
            totalCorrectas++;
          } else {
            totalIncorrectas++;
          }
          if (cambios > 0) totalCambiadas++;
        }

        if (!omitida && esCorrecta != null && tiempo > 0) {
          totalConTiempo++;
          sumaTiempoValido += tiempo;
          if (tiempo < 30) {
            tiempoLt30++;
          } else if (tiempo <= 60) {
            tiempo30a60++;
          } else if (tiempo <= 90) {
            tiempo60a90++;
          } else {
            tiempoGt90++;
          }

          if (tiempo < 20) {
            totalSub20++;
            if (esCorrecta == false) erroresSub20++;
          }
        }

        if (!omitida && esCorrecta != null && fecha != null) {
          final dias = now.difference(fecha).inDays;
          if (dias >= 0 && dias < 56) {
            final bucket = dias ~/ 7;
            weekTotal[bucket] = weekTotal[bucket] + 1;
            if (esCorrecta) weekCorrect[bucket] = weekCorrect[bucket] + 1;
          }
          if (dias >= 0 && dias < 14 && tiempo > 0) {
            segundosRespuestas14d += tiempo;
          }
        }

        if (preguntaId.isNotEmpty &&
            !omitida &&
            esCorrecta != null &&
            fecha != null) {
          eventosPorPregunta.putIfAbsent(
            preguntaId,
            () => <Map<String, dynamic>>[],
          );
          eventosPorPregunta[preguntaId]!.add({
            'fecha': fecha,
            'correcta': esCorrecta,
          });
        }

        if (!omitida && esCorrecta != null && fecha != null) {
          eventosCurva.add({
            'fecha': fecha,
            'correcta': esCorrecta,
            'tiempo': tiempo > 0 ? tiempo : null,
          });
        }
      }

      final totalEventos = totalNoOmitidas + totalOmitidas;
      final pctCorrectas = pctInt(totalCorrectas, totalEventos);
      final pctIncorrectas = pctInt(totalIncorrectas, totalEventos);
      final pctOmitidas = pctInt(totalOmitidas, totalEventos);
      final pctCambiadas = pctInt(totalCambiadas, totalNoOmitidas);

      final pctLt30 = pctInt(tiempoLt30, totalConTiempo);
      final pct30a60 = pctInt(tiempo30a60, totalConTiempo);
      final pct60a90 = pctInt(tiempo60a90, totalConTiempo);
      final pctGt90 = pctInt(tiempoGt90, totalConTiempo);

      final serieSemanal = <Map<String, dynamic>>[];
      final accSemanal = <double>[];
      final puntosCurva = <Map<String, dynamic>>[
        {
          'x_dias': 0.0,
          'y_nivel': 0.0,
          'acierto_acumulado_pct': 0.0,
          'muestra_acumulada': 0,
        },
      ];
      final puntosCurvaVelocidad = <Map<String, dynamic>>[];
      var acumuladasSemanal = 0;
      var correctasAcumuladasSemanal = 0;
      var bloque5Dias = 0;
      for (var i = 7; i >= 0; i--) {
        final acierto = pctInt(weekCorrect[i], weekTotal[i]);
        serieSemanal.add({
          'etiqueta': 'Semana ${8 - i}',
          'porcentaje': acierto,
          'muestra': weekTotal[i],
        });
        if (weekTotal[i] > 0) {
          acumuladasSemanal += weekTotal[i];
          correctasAcumuladasSemanal += weekCorrect[i];
          final aciertoAcumulado = pctInt(
            correctasAcumuladasSemanal,
            acumuladasSemanal,
          );
          final nivelSemanal = aciertoAcumulado.clamp(0.0, 100.0);
          puntosCurva.add({
            'x_dias': ((bloque5Dias + 1) * 5).toDouble(),
            'y_nivel': nivelSemanal,
            'acierto_acumulado_pct': aciertoAcumulado,
            'muestra_acumulada': acumuladasSemanal,
          });
          bloque5Dias++;
        }
        if (weekTotal[i] > 0) accSemanal.add(acierto);
      }

      if (eventosCurva.isNotEmpty) {
        eventosCurva.sort((a, b) {
          final fa = a['fecha'] as DateTime;
          final fb = b['fecha'] as DateTime;
          return fa.compareTo(fb);
        });

        final inicio = eventosCurva.first['fecha'] as DateTime;
        final totalPorBloque = <int, int>{};
        final correctasPorBloque = <int, int>{};
        final maxDiaPorBloque = <int, int>{};
        final tiempoTotalPorBloque = <int, double>{};
        final tiempoMuestraPorBloque = <int, int>{};
        for (final evento in eventosCurva) {
          final fecha = evento['fecha'] as DateTime;
          final deltaDias = fecha.difference(inicio).inDays;
          if (deltaDias < 0) continue;
          final bloque = deltaDias ~/ 5;
          totalPorBloque[bloque] = (totalPorBloque[bloque] ?? 0) + 1;
          final maxDiaActual = maxDiaPorBloque[bloque];
          if (maxDiaActual == null || deltaDias > maxDiaActual) {
            maxDiaPorBloque[bloque] = deltaDias;
          }
          if (evento['correcta'] == true) {
            correctasPorBloque[bloque] = (correctasPorBloque[bloque] ?? 0) + 1;
          }
          final tiempoEvento = _toDouble(evento['tiempo']) ?? 0.0;
          if (tiempoEvento > 0) {
            tiempoTotalPorBloque[bloque] =
                (tiempoTotalPorBloque[bloque] ?? 0.0) + tiempoEvento;
            tiempoMuestraPorBloque[bloque] =
                (tiempoMuestraPorBloque[bloque] ?? 0) + 1;
          }
        }

        final puntosDetallados = <Map<String, dynamic>>[
          {
            'x_dias': 0.0,
            'y_nivel': 0.0,
            'acierto_acumulado_pct': 0.0,
            'muestra_acumulada': 0,
          },
        ];
        var acumuladas = 0;
        var correctasAcum = 0;
        var nivelPrevio = 0.0;
        final maxBloque = totalPorBloque.keys.fold<int>(
          0,
          (acc, value) => value > acc ? value : acc,
        );
        for (var bloque = 0; bloque <= maxBloque; bloque++) {
          final totalBloque = totalPorBloque[bloque] ?? 0;
          if (totalBloque <= 0) continue;
          final correctasBloque = correctasPorBloque[bloque] ?? 0;
          acumuladas += totalBloque;
          correctasAcum += correctasBloque;
          final aciertoAcumulado = pctInt(correctasAcum, acumuladas);
          var nivel = aciertoAcumulado.clamp(0.0, 100.0);
          if (nivel < nivelPrevio) nivel = nivelPrevio;
          final xRealDias = ((maxDiaPorBloque[bloque] ?? (bloque * 5)) + 1)
              .toDouble();
          puntosDetallados.add({
            'x_dias': xRealDias,
            'y_nivel': nivel,
            'acierto_acumulado_pct': aciertoAcumulado,
            'muestra_acumulada': acumuladas,
          });
          nivelPrevio = nivel;
        }

        if (puntosDetallados.length >= 2) {
          puntosCurva
            ..clear()
            ..addAll(puntosDetallados);
        }

        for (var bloque = 0; bloque <= maxBloque; bloque++) {
          final muestraTiempo = tiempoMuestraPorBloque[bloque] ?? 0;
          if (muestraTiempo <= 0) continue;
          final tiempoPromedio =
              (tiempoTotalPorBloque[bloque] ?? 0.0) / muestraTiempo;
          final xRealDias = ((maxDiaPorBloque[bloque] ?? (bloque * 5)) + 1)
              .toDouble();
          puntosCurvaVelocidad.add({
            'x_dias': xRealDias,
            'segundos_promedio': tiempoPromedio,
            'muestra': muestraTiempo,
          });
        }
      }

      if (puntosCurva.length < 2) {
        puntosCurva.add({
          'x_dias': 5.0,
          'y_nivel': 0.0,
          'acierto_acumulado_pct': 0.0,
          'muestra_acumulada': 0,
        });
      }

      puntosCurvaVelocidad.sort((a, b) {
        final xa = _toDouble(a['x_dias']) ?? 0.0;
        final xb = _toDouble(b['x_dias']) ?? 0.0;
        return xa.compareTo(xb);
      });
      if (puntosCurvaVelocidad.length == 1) {
        final unico = Map<String, dynamic>.from(puntosCurvaVelocidad.first);
        final y = _toDouble(unico['segundos_promedio']) ?? 0.0;
        puntosCurvaVelocidad.insert(0, {
          'x_dias': 0.0,
          'segundos_promedio': y,
          'muestra': 0,
        });
      }
      if (puntosCurvaVelocidad.length < 2) {
        final baseVel = totalConTiempo > 0
            ? (sumaTiempoValido / totalConTiempo)
            : 0.0;
        puntosCurvaVelocidad
          ..clear()
          ..addAll([
            {'x_dias': 0.0, 'segundos_promedio': baseVel, 'muestra': 0},
            {'x_dias': 5.0, 'segundos_promedio': baseVel, 'muestra': 0},
          ]);
      }

      final pendiente = pendienteLineal(accSemanal);
      final variacion = desviacion(accSemanal);
      final mejoraSemanal = accSemanal.length >= 2
          ? (accSemanal.last - accSemanal.first) / (accSemanal.length - 1)
          : 0.0;
      final estabilidadCurva = (100.0 - (variacion * 2.0)).clamp(0.0, 100.0);

      var base24 = 0;
      var ret24 = 0;
      var base7 = 0;
      var ret7 = 0;
      var base30 = 0;
      var ret30 = 0;
      var baseOlvido7 = 0;
      var olvido7 = 0;
      var baseOlvido15 = 0;
      var olvido15 = 0;
      final intentosDominio = <int>[];

      for (final eventos in eventosPorPregunta.values) {
        eventos.sort((a, b) {
          final fa = a['fecha'] as DateTime;
          final fb = b['fecha'] as DateTime;
          return fa.compareTo(fb);
        });

        var streak = 0;
        var intentos = 0;
        var logroDominio = false;
        for (final ev in eventos) {
          intentos++;
          if (ev['correcta'] == true) {
            streak++;
            if (!logroDominio && streak >= 3) {
              intentosDominio.add(intentos);
              logroDominio = true;
            }
          } else {
            streak = 0;
          }
        }

        Map<String, dynamic>? siguienteDespues(
          List<Map<String, dynamic>> lista,
          int desde,
          int dias,
        ) {
          final fechaBase = lista[desde]['fecha'] as DateTime;
          for (var j = desde + 1; j < lista.length; j++) {
            final fecha = lista[j]['fecha'] as DateTime;
            if (fecha.difference(fechaBase).inDays >= dias) {
              return lista[j];
            }
          }
          return null;
        }

        for (var i = 0; i < eventos.length; i++) {
          if (eventos[i]['correcta'] != true) continue;

          final n24 = siguienteDespues(eventos, i, 1);
          if (n24 != null) {
            base24++;
            if (n24['correcta'] == true) ret24++;
          }

          final n7 = siguienteDespues(eventos, i, 7);
          if (n7 != null) {
            base7++;
            if (n7['correcta'] == true) ret7++;
            baseOlvido7++;
            if (n7['correcta'] != true) olvido7++;
          }

          final n15 = siguienteDespues(eventos, i, 15);
          if (n15 != null) {
            baseOlvido15++;
            if (n15['correcta'] != true) olvido15++;
          }

          final n30 = siguienteDespues(eventos, i, 30);
          if (n30 != null) {
            base30++;
            if (n30['correcta'] == true) ret30++;
          }
        }
      }

      var ret24h = pctInt(ret24, base24);
      var ret7d = pctInt(ret7, base7);
      var ret30d = pctInt(ret30, base30);
      final olvido7d = pctInt(olvido7, baseOlvido7);
      final olvido15d = pctInt(olvido15, baseOlvido15);

      var sumaIntentos = 0.0;
      var preguntasConIntentos = 0;
      for (final ex in exposiciones) {
        final total =
            _toInt(ex['total_veces_correcta']) +
            _toInt(ex['total_veces_incorrecta']);
        if (total <= 0) continue;
        sumaIntentos += total.toDouble();
        preguntasConIntentos++;
      }

      final promedioIntentos = intentosDominio.isNotEmpty
          ? promedio(intentosDominio.map((e) => e.toDouble()).toList())
          : (preguntasConIntentos > 0
                ? (sumaIntentos / preguntasConIntentos)
                : 0.0);

      var libreResp = 0;
      var libreCorr = 0;
      var simResp = 0;
      var simCorr = 0;
      var segundosSesion14d = 0.0;

      for (final sesion in sesiones.where(sesionCompletada)) {
        final respondidas = respondidasSesion(sesion);
        if (respondidas <= 0) continue;
        final correctas = _toInt(sesion['preguntas_correctas']);
        if (esSimulacro(sesion)) {
          simResp += respondidas;
          simCorr += correctas;
        } else {
          libreResp += respondidas;
          libreCorr += correctas;
        }

        final fecha = _parseFechaFlexible(sesion['fecha_inicio']);
        if (fecha != null && now.difference(fecha).inDays < 14) {
          final seg = _toDouble(sesion['duracion_real_segundos']) ?? 0.0;
          if (seg > 0) segundosSesion14d += seg;
        }
      }

      final precisionLibre = pctInt(libreCorr, libreResp);
      final precisionSim = pctInt(simCorr, simResp);
      final brecha = precisionLibre - precisionSim;

      final variacionPct = variacion.clamp(0.0, 100.0);
      final estabilidad = nivelVolatilidad(variacionPct);
      final erroresSub20Pct = pctInt(erroresSub20, totalNoOmitidas);
      final pctErrorSobreSub20 = pctInt(erroresSub20, totalSub20);
      final velocidadPromedioGlobal = totalConTiempo > 0
          ? (sumaTiempoValido / totalConTiempo)
          : 0.0;
      final velocidadObjetivoSeg = 72.0;
      final velocidadInicialCurva =
          _toDouble(puntosCurvaVelocidad.first['segundos_promedio']) ??
          velocidadPromedioGlobal;
      final velocidadFinalCurva =
          _toDouble(puntosCurvaVelocidad.last['segundos_promedio']) ??
          velocidadPromedioGlobal;
      final tendenciaVelocidad = (() {
        if (puntosCurvaVelocidad.length < 2) return 'sin_datos';
        final diff = velocidadFinalCurva - velocidadInicialCurva;
        if (diff <= -2.0) return 'mejorando';
        if (diff >= 2.0) return 'empeorando';
        return 'estable';
      })();

      var horasEstudio14d = segundosSesion14d / 3600.0;
      if (horasEstudio14d <= 0) {
        horasEstudio14d = segundosRespuestas14d / 3600.0;
      }
      final mejoraTotal = accSemanal.length >= 2
          ? (accSemanal.last - accSemanal.first)
          : 0.0;
      final indiceEficiencia = horasEstudio14d > 0
          ? (mejoraTotal / horasEstudio14d)
          : 0.0;

      final tasaAciertoGlobal =
          (_toDouble(perfil['tasa_acierto_global']) ??
                  pctInt(totalCorrectas, totalNoOmitidas))
              .clamp(0.0, 100.0);
      final nivelPostulante = nivelPostulanteDesdePct(tasaAciertoGlobal);
      final mensajeResumen = mensajeResumenDesdeMetricas(
        tasaAciertoGlobal: tasaAciertoGlobal,
        totalNoOmitidas: totalNoOmitidas,
        totalSub20: totalSub20,
        pctErrorSobreSub20: pctErrorSobreSub20,
      );

      return {
        'estado': 'ok',
        'origen_datos': 'supabase',
        'mensaje': mensajeResumen,
        'tasa_acierto_global': tasaAciertoGlobal,
        'nivel_postulante': nivelPostulante,
        'distribucion_respuestas': {
          'correctas_total': totalCorrectas,
          'incorrectas_total': totalIncorrectas,
          'omitidas_total': totalOmitidas,
          'cambiadas_total': totalCambiadas,
          'correctas_pct': pctCorrectas,
          'incorrectas_pct': pctIncorrectas,
          'omitidas_pct': pctOmitidas,
          'cambiadas_pct': pctCambiadas,
          'total_eventos': totalEventos,
          'total_no_omitidas': totalNoOmitidas,
        },
        'distribucion_tiempos': {
          'lt_30_pct': pctLt30,
          's30_60_pct': pct30a60,
          's60_90_pct': pct60a90,
          'gt_90_pct': pctGt90,
          'muestra': totalConTiempo,
        },
        'curva_velocidad': {
          'intervalo_dias': 5,
          'velocidad_objetivo_seg': velocidadObjetivoSeg,
          'promedio_global_seg': velocidadPromedioGlobal,
          'tendencia': tendenciaVelocidad,
          'puntos_curva': puntosCurvaVelocidad,
        },
        'curva_aprendizaje': {
          'tasa_mejora_semanal_pct': mejoraSemanal,
          'pendiente_aprendizaje': pendiente,
          'estabilidad_rendimiento_pct': estabilidadCurva,
          'intervalo_dias': 5,
          'serie_semanal': serieSemanal,
          'puntos_curva': puntosCurva,
        },
        'tasa_retencion': {
          'retencion_24h_pct': ret24h,
          'retencion_7d_pct': ret7d,
          'retencion_30d_pct': ret30d,
        },
        'indice_repeticion_efectiva': {
          'promedio_intentos_por_pregunta': promedioIntentos,
          'preguntas_analizadas': preguntasConIntentos,
        },
        'precision_bajo_presion': {
          'practica_libre_pct': precisionLibre,
          'simulacro_cronometrado_pct': precisionSim,
          'brecha_pct': brecha,
        },
        'indice_volatilidad': {
          'variacion_pct': variacionPct,
          'estabilidad': estabilidad,
        },
        'degradacion_memoria': {
          'olvido_7d_pct': olvido7d,
          'olvido_15d_pct': olvido15d,
          'total_base_7d': baseOlvido7,
          'total_base_15d': baseOlvido15,
        },
        'sobreconfianza': {
          'errores_sub20s_pct': erroresSub20Pct,
          'total_respuestas_sub20s': totalSub20,
          'errores_sub20s': erroresSub20,
          'pct_error_sobre_sub20': pctErrorSobreSub20,
        },
        'eficiencia_estudio': {
          'horas_estudio_14d': horasEstudio14d,
          'mejora_pct': mejoraTotal,
          'indice_eficiencia': indiceEficiencia,
          'unidad': 'puntos_por_hora',
        },
      };
    } catch (e) {
      debugPrint('obtenerAnalisisCompletoPerfilDetallado (tecnico) error: $e');
      return _analisisCompletoPerfilFallbackTecnico(
        estado: 'error',
        mensaje:
            'No se pudo calcular el analisis tecnico completo en este momento.',
      );
    }
  }

  Map<String, dynamic> _analisisCompletoPerfilFallbackTecnico({
    required String estado,
    required String mensaje,
  }) {
    return {
      'estado': estado,
      'origen_datos': 'sin_datos',
      'mensaje': mensaje,
      'tasa_acierto_global': 0.0,
      'nivel_postulante': {
        'nombre': 'Muy Bajo',
        'rango': '1% - 20%',
        'acierto_pct': 0.0,
      },
      'distribucion_respuestas': {
        'correctas_total': 0,
        'incorrectas_total': 0,
        'omitidas_total': 0,
        'cambiadas_total': 0,
        'correctas_pct': 0.0,
        'incorrectas_pct': 0.0,
        'omitidas_pct': 0.0,
        'cambiadas_pct': 0.0,
        'total_eventos': 0,
        'total_no_omitidas': 0,
      },
      'distribucion_tiempos': {
        'lt_30_pct': 0.0,
        's30_60_pct': 0.0,
        's60_90_pct': 0.0,
        'gt_90_pct': 0.0,
        'muestra': 0,
      },
      'curva_velocidad': {
        'intervalo_dias': 5,
        'velocidad_objetivo_seg': 0.0,
        'promedio_global_seg': 0.0,
        'tendencia': 'sin_datos',
        'puntos_curva': <Map<String, dynamic>>[
          {'x_dias': 0.0, 'segundos_promedio': 0.0, 'muestra': 0},
          {'x_dias': 5.0, 'segundos_promedio': 0.0, 'muestra': 0},
        ],
      },
      'curva_aprendizaje': {
        'tasa_mejora_semanal_pct': 0.0,
        'pendiente_aprendizaje': 0.0,
        'estabilidad_rendimiento_pct': 0.0,
        'intervalo_dias': 5,
        'serie_semanal': <Map<String, dynamic>>[],
        'puntos_curva': <Map<String, dynamic>>[],
      },
      'tasa_retencion': {
        'retencion_24h_pct': 0.0,
        'retencion_7d_pct': 0.0,
        'retencion_30d_pct': 0.0,
      },
      'indice_repeticion_efectiva': {
        'promedio_intentos_por_pregunta': 0.0,
        'preguntas_analizadas': 0,
      },
      'precision_bajo_presion': {
        'practica_libre_pct': 0.0,
        'simulacro_cronometrado_pct': 0.0,
        'brecha_pct': 0.0,
      },
      'indice_volatilidad': {'variacion_pct': 0.0, 'estabilidad': 'media'},
      'degradacion_memoria': {
        'olvido_7d_pct': 0.0,
        'olvido_15d_pct': 0.0,
        'total_base_7d': 0,
        'total_base_15d': 0,
      },
      'sobreconfianza': {
        'errores_sub20s_pct': 0.0,
        'total_respuestas_sub20s': 0,
        'errores_sub20s': 0,
        'pct_error_sobre_sub20': 0.0,
      },
      'eficiencia_estudio': {
        'horas_estudio_14d': 0.0,
        'mejora_pct': 0.0,
        'indice_eficiencia': 0.0,
        'unidad': 'puntos_por_hora',
      },
    };
  }

  Future<List<Map<String, dynamic>>> obtenerDetalleDistribucionRespuestas({
    required String userId,
    required String tipo,
    int limit = 120,
  }) async {
    if (_sesionInvalida(userId)) return const <Map<String, dynamic>>[];

    final tipoNormalizado = tipo.trim().toLowerCase();
    final limiteFinal = limit.clamp(20, 500);
    const ventanaAnalisis = 6000;

    bool coincideTipo(Map<String, dynamic> row) {
      final omitida = row['fue_omitida'] == true;
      final esCorrecta = row['es_correcta'] == true;
      final cambios = _toInt(row['numero_cambios_respuesta']);

      switch (tipoNormalizado) {
        case 'correctas':
          return !omitida && esCorrecta;
        case 'incorrectas':
          return !omitida && !esCorrecta;
        case 'omitidas':
          return omitida;
        case 'cambiadas':
          return !omitida && cambios > 0;
        default:
          return false;
      }
    }

    String extraerMateria(dynamic pregunta) {
      if (pregunta is! Map) return 'Sin materia';
      final raw = pregunta['materia'];
      if (raw is Map) {
        final nombre = (raw['nombre'] ?? '').toString().trim();
        if (nombre.isNotEmpty) return nombre;
      }
      return 'Sin materia';
    }

    try {
      final response = await _supabase
          .from('respuesta_usuario')
          .select(
            'pregunta_id, respondida_at, es_correcta, fue_omitida, '
            'numero_cambios_respuesta, tiempo_total_respuesta, '
            'pregunta:pregunta_id(codigo_pregunta, enunciado, materia:materia_id(nombre))',
          )
          .eq('usuario_id', userId)
          .order('respondida_at', ascending: false)
          .limit(ventanaAnalisis);

      final rows = (response as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final filtradas = rows.where(coincideTipo).take(limiteFinal).toList();

      return filtradas.map((row) {
        final pregunta = row['pregunta'];
        final codigo =
            (pregunta is Map ? (pregunta['codigo_pregunta'] ?? '') : '')
                .toString()
                .trim();
        final enunciado = (pregunta is Map ? (pregunta['enunciado'] ?? '') : '')
            .toString()
            .trim();

        return <String, dynamic>{
          'pregunta_id': (row['pregunta_id'] ?? '').toString(),
          'codigo_pregunta': codigo,
          'enunciado': enunciado,
          'materia': extraerMateria(pregunta),
          'respondida_at': row['respondida_at'],
          'es_correcta': row['es_correcta'] == true,
          'fue_omitida': row['fue_omitida'] == true,
          'numero_cambios_respuesta': _toInt(row['numero_cambios_respuesta']),
          'tiempo_total_respuesta':
              _toDouble(row['tiempo_total_respuesta']) ?? 0,
        };
      }).toList();
    } catch (e) {
      debugPrint('obtenerDetalleDistribucionRespuestas error: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> obtenerDetalleDistribucionTiempo({
    required String userId,
    required String rango,
    int limit = 120,
  }) async {
    if (_sesionInvalida(userId)) return const <Map<String, dynamic>>[];

    final rangoNormalizado = rango.trim().toLowerCase();
    final limiteFinal = limit.clamp(20, 500);
    const ventanaAnalisis = 6000;

    bool coincideRango(Map<String, dynamic> row) {
      final omitida = row['fue_omitida'] == true;
      final esCorrectaRaw = row['es_correcta'];
      final tieneEstado = esCorrectaRaw is bool;
      final tiempo = _toDouble(row['tiempo_total_respuesta']) ?? 0.0;
      if (omitida || !tieneEstado || tiempo <= 0) return false;

      switch (rangoNormalizado) {
        case 'lt_30':
          return tiempo < 30.0;
        case 's30_60':
          return tiempo >= 30.0 && tiempo <= 60.0;
        case 's60_90':
          return tiempo > 60.0 && tiempo <= 90.0;
        case 'gt_90':
          return tiempo > 90.0;
        default:
          return false;
      }
    }

    String extraerMateria(dynamic pregunta) {
      if (pregunta is! Map) return 'Sin materia';
      final raw = pregunta['materia'];
      if (raw is Map) {
        final nombre = (raw['nombre'] ?? '').toString().trim();
        if (nombre.isNotEmpty) return nombre;
      }
      return 'Sin materia';
    }

    try {
      final response = await _supabase
          .from('respuesta_usuario')
          .select(
            'pregunta_id, respondida_at, es_correcta, fue_omitida, '
            'numero_cambios_respuesta, tiempo_total_respuesta, '
            'pregunta:pregunta_id(codigo_pregunta, enunciado, materia:materia_id(nombre))',
          )
          .eq('usuario_id', userId)
          .order('respondida_at', ascending: false)
          .limit(ventanaAnalisis);

      final rows = (response as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final filtradas = rows.where(coincideRango).take(limiteFinal).toList();

      return filtradas.map((row) {
        final pregunta = row['pregunta'];
        final codigo =
            (pregunta is Map ? (pregunta['codigo_pregunta'] ?? '') : '')
                .toString()
                .trim();
        final enunciado = (pregunta is Map ? (pregunta['enunciado'] ?? '') : '')
            .toString()
            .trim();

        return <String, dynamic>{
          'pregunta_id': (row['pregunta_id'] ?? '').toString(),
          'codigo_pregunta': codigo,
          'enunciado': enunciado,
          'materia': extraerMateria(pregunta),
          'respondida_at': row['respondida_at'],
          'es_correcta': row['es_correcta'] == true,
          'fue_omitida': row['fue_omitida'] == true,
          'numero_cambios_respuesta': _toInt(row['numero_cambios_respuesta']),
          'tiempo_total_respuesta':
              _toDouble(row['tiempo_total_respuesta']) ?? 0,
        };
      }).toList();
    } catch (e) {
      debugPrint('obtenerDetalleDistribucionTiempo error: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  // ignore: unused_element
  Future<Map<String, dynamic>> _obtenerAnalisisCompletoPerfilDetalladoLegacy({
    required String userId,
    String? categoriaUsuario,
    Map<String, dynamic>? analisisBase,
  }) async {
    if (_sesionInvalida(userId)) {
      return _analisisCompletoPerfilFallbackLegacy(
        estado: 'sin_sesion',
        mensaje: 'Inicia sesion para calcular tu analisis completo de perfil.',
      );
    }

    bool sesionCompletada(Map<String, dynamic> row) {
      return row['completada'] == true || row['estado'] == 'completada';
    }

    int respondidasSesion(Map<String, dynamic> row) {
      final respondidasGuardadas = _toInt(row['preguntas_respondidas']);
      if (respondidasGuardadas > 0) return respondidasGuardadas;
      return _toInt(row['preguntas_correctas']) +
          _toInt(row['preguntas_incorrectas']) +
          _toInt(row['preguntas_omitidas']);
    }

    bool esSimulacro(Map<String, dynamic> row) {
      final tipo = _normalizarTexto((row['tipo_sesion'] ?? '').toString());
      final totalPlan = _toInt(row['total_preguntas_planeadas']);
      return tipo.contains('simulacro') || totalPlan >= 100;
    }

    double puntajeSesion(Map<String, dynamic> row) {
      final score = _toDouble(row['puntaje_obtenido']) ?? 0.0;
      if (score > 0) return score.clamp(0.0, 100.0);
      final respondidas = respondidasSesion(row);
      final correctas = _toInt(row['preguntas_correctas']);
      if (respondidas > 0) {
        return ((correctas * 100.0) / respondidas).clamp(0.0, 100.0);
      }
      final totalPlan = _toInt(row['total_preguntas_planeadas']);
      if (totalPlan > 0) {
        return ((correctas * 100.0) / totalPlan).clamp(0.0, 100.0);
      }
      return 0.0;
    }

    String nombreMateria(Map<String, dynamic> materia) {
      final raw = materia['materia'] ?? materia['nombre'];
      if (raw is Map) {
        final nombre = (raw['nombre'] ?? 'Materia').toString().trim();
        return nombre.isEmpty ? 'Materia' : nombre;
      }
      final nombre = (raw ?? 'Materia').toString().trim();
      return nombre.isEmpty ? 'Materia' : nombre;
    }

    double dominioMateria(Map<String, dynamic> materia) {
      return (_toDouble(materia['porcentaje']) ??
              _toDouble(materia['tasa_dominio']) ??
              _toDouble(materia['dominio']) ??
              0.0)
          .clamp(0.0, 100.0);
    }

    String nivelPostulante(double porcentaje) {
      if (porcentaje <= 20) return 'Muy Bajo';
      if (porcentaje <= 40) return 'Principiante';
      if (porcentaje <= 60) return 'Intermedio';
      if (porcentaje <= 80) return 'Avanzado';
      return 'Competitivo / Listo para examen';
    }

    double proyeccion14Dias({
      required double probabilidadActual,
      required double ritmoActual,
      required double ritmoNecesario,
      required double porcentajeAcierto,
      required int materiasCriticas,
    }) {
      final ratio = ritmoNecesario > 0 ? (ritmoActual / ritmoNecesario) : 1.0;
      var gananciaDiaria = 0.35;
      if (ratio >= 1.2) {
        gananciaDiaria = 0.90;
      } else if (ratio >= 1.0) {
        gananciaDiaria = 0.75;
      } else if (ratio >= 0.85) {
        gananciaDiaria = 0.55;
      } else if (ratio >= 0.70) {
        gananciaDiaria = 0.35;
      } else {
        gananciaDiaria = 0.20;
      }

      gananciaDiaria += ((porcentajeAcierto - 60.0) / 100.0).clamp(-0.15, 0.20);
      gananciaDiaria -= (materiasCriticas * 0.015).clamp(0.0, 0.18);
      final proy = probabilidadActual + (gananciaDiaria * 14.0);
      return proy.clamp(0.0, 99.0);
    }

    try {
      final analisis =
          analisisBase ??
          await analizarPerfilCompleto(
            userId,
            perfilUsuario: {'categoria': (categoriaUsuario ?? '').trim()},
          );

      final resultados = await Future.wait<dynamic>([
        _supabase
            .from('perfil_usuario')
            .select(
              'total_preguntas_respondidas, total_correctas, total_incorrectas, '
              'tasa_acierto_global, simulacros_100_completados, mejor_puntaje_simulacro',
            )
            .eq('usuario_id', userId)
            .maybeSingle(),
        _supabase
            .from('respuesta_usuario')
            .select(
              'respondida_at, es_correcta, fue_omitida, tiempo_total_respuesta, '
              'numero_cambios_respuesta, tipo_error',
            )
            .eq('usuario_id', userId)
            .order('respondida_at', ascending: false)
            .limit(6000),
        _supabase
            .from('sesion_practica')
            .select(
              'tipo_sesion, completada, estado, preguntas_correctas, preguntas_incorrectas, '
              'preguntas_omitidas, preguntas_respondidas, puntaje_obtenido, '
              'total_preguntas_planeadas, fecha_inicio',
            )
            .eq('usuario_id', userId)
            .order('fecha_inicio', ascending: false)
            .limit(1200),
        obtenerProyeccionTiempoDetalle(
          userId: userId,
          categoriaUsuario: categoriaUsuario,
        ),
        obtenerAnalisisVelocidadEstructurado(userId: userId),
        obtenerCoachMemoriaDetalle(userId: userId),
        obtenerPrediccionOlvidoDetalle(userId: userId),
      ]);

      final perfilRaw = resultados[0];
      final perfil = perfilRaw is Map
          ? Map<String, dynamic>.from(perfilRaw)
          : <String, dynamic>{};

      final respuestasRaw = resultados[1];
      final respuestas = respuestasRaw is List
          ? respuestasRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      final sesionesRaw = resultados[2];
      final sesiones = sesionesRaw is List
          ? sesionesRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      final proyeccionRaw = resultados[3];
      final proyeccion = proyeccionRaw is Map
          ? Map<String, dynamic>.from(proyeccionRaw)
          : <String, dynamic>{};

      final velocidadRaw = resultados[4];
      final velocidad = velocidadRaw is Map
          ? Map<String, dynamic>.from(velocidadRaw)
          : <String, dynamic>{};

      final coachRaw = resultados[5];
      final coachMemoria = coachRaw is Map
          ? Map<String, dynamic>.from(coachRaw)
          : <String, dynamic>{};

      final olvidoRaw = resultados[6];
      final olvidoDetalle = olvidoRaw is Map
          ? Map<String, dynamic>.from(olvidoRaw)
          : <String, dynamic>{};

      final now = DateTime.now();
      var respondidasHistorial = 0;
      var correctasHistorial = 0;
      var erroresDesconocimiento = 0;
      var erroresDistraccion = 0;
      var erroresTiempo = 0;

      final weekTotal = [0, 0, 0, 0];
      final weekCorrect = [0, 0, 0, 0];
      var mesActualTotal = 0;
      var mesActualCorrect = 0;
      var mesPrevioTotal = 0;
      var mesPrevioCorrect = 0;

      for (final row in respuestas) {
        final omitida = row['fue_omitida'] == true;
        final esCorrectaRaw = row['es_correcta'];
        if (omitida && esCorrectaRaw is! bool) {
          erroresTiempo++;
          continue;
        }
        if (omitida || esCorrectaRaw is! bool) continue;

        final esCorrecta = esCorrectaRaw == true;
        respondidasHistorial++;
        if (esCorrecta) {
          correctasHistorial++;
        } else {
          var tipo = _normalizarTexto((row['tipo_error'] ?? '').toString());
          if (tipo.contains('desconoc')) {
            erroresDesconocimiento++;
          } else if (tipo.contains('distrac') ||
              tipo.contains('lectura') ||
              tipo.contains('confusion') ||
              tipo.contains('impuls')) {
            erroresDistraccion++;
          } else if (tipo.contains('tiempo') || tipo.contains('lento')) {
            erroresTiempo++;
          } else {
            final tiempo = _toDouble(row['tiempo_total_respuesta']) ?? 0.0;
            final cambios = _toInt(row['numero_cambios_respuesta']);
            if (tiempo > 72 || (tiempo > 55 && cambios <= 0)) {
              erroresTiempo++;
            } else if (cambios >= 2 || (tiempo > 0 && tiempo <= 12)) {
              erroresDistraccion++;
            } else {
              erroresDesconocimiento++;
            }
          }
        }

        final fecha = _parseFechaFlexible(row['respondida_at']);
        if (fecha == null) continue;
        final dias = now.difference(fecha).inDays;
        if (dias >= 0 && dias < 28) {
          final bucket = dias ~/ 7;
          weekTotal[bucket] = weekTotal[bucket] + 1;
          if (esCorrecta) weekCorrect[bucket] = weekCorrect[bucket] + 1;
        }
        if (dias >= 0 && dias < 30) {
          mesActualTotal++;
          if (esCorrecta) mesActualCorrect++;
        } else if (dias >= 30 && dias < 60) {
          mesPrevioTotal++;
          if (esCorrecta) mesPrevioCorrect++;
        }
      }

      double pct(int ok, int total) => total > 0 ? (ok * 100.0) / total : 0.0;
      final semanaActualPct = pct(weekCorrect[0], weekTotal[0]);
      final semanaPreviaPct = pct(weekCorrect[1], weekTotal[1]);
      final mensualPct = pct(mesActualCorrect, mesActualTotal);
      final mensualPrevioPct = pct(mesPrevioCorrect, mesPrevioTotal);

      final serieSemanal = <Map<String, dynamic>>[
        {
          'etiqueta': 'Semana 1',
          'porcentaje': pct(weekCorrect[3], weekTotal[3]),
        },
        {
          'etiqueta': 'Semana 2',
          'porcentaje': pct(weekCorrect[2], weekTotal[2]),
        },
        {
          'etiqueta': 'Semana 3',
          'porcentaje': pct(weekCorrect[1], weekTotal[1]),
        },
        {
          'etiqueta': 'Semana 4',
          'porcentaje': pct(weekCorrect[0], weekTotal[0]),
        },
      ];

      final sesionesCompletadas = sesiones.where(sesionCompletada).toList();
      final simulacros = sesionesCompletadas.where(esSimulacro).toList();
      simulacros.sort((a, b) {
        final fa = _parseFechaFlexible(a['fecha_inicio']);
        final fb = _parseFechaFlexible(b['fecha_inicio']);
        if (fa == null && fb == null) return 0;
        if (fa == null) return 1;
        if (fb == null) return -1;
        return fa.compareTo(fb);
      });

      final simulacrosPerfil = _toInt(perfil['simulacros_100_completados']);
      final simulacrosRealizados = simulacrosPerfil > simulacros.length
          ? simulacrosPerfil
          : simulacros.length;

      var mejorSimulacro = _toDouble(perfil['mejor_puntaje_simulacro']) ?? 0.0;
      for (final s in simulacros) {
        final score = puntajeSesion(s);
        if (score > mejorSimulacro) mejorSimulacro = score;
      }

      var mejoraSimulacros = 0.0;
      if (simulacros.length >= 2) {
        final primero = puntajeSesion(simulacros.first);
        final ultimo = puntajeSesion(simulacros.last);
        mejoraSimulacros = ultimo - primero;
      }

      var preguntasRespondidas = _toInt(perfil['total_preguntas_respondidas']);
      if (preguntasRespondidas <= 0) {
        preguntasRespondidas = respondidasHistorial;
      }

      var porcentajeAcierto = _toDouble(perfil['tasa_acierto_global']) ?? 0.0;
      if (porcentajeAcierto <= 0) {
        porcentajeAcierto = _toDouble(analisis['tasa_acierto']) ?? 0.0;
      }
      if (porcentajeAcierto <= 0 && respondidasHistorial > 0) {
        porcentajeAcierto = (correctasHistorial * 100.0) / respondidasHistorial;
      }

      final nivelUsuario = nivelPostulante(porcentajeAcierto);

      final materiasRaw = analisis['analisis_materias'];
      final materias = materiasRaw is List
          ? materiasRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      final riesgoAlto = <Map<String, dynamic>>[];
      final riesgoMedio = <Map<String, dynamic>>[];
      final riesgoBajo = <Map<String, dynamic>>[];
      for (final materia in materias) {
        final nombre = nombreMateria(materia);
        final dominio = dominioMateria(materia);
        final item = <String, dynamic>{'materia': nombre, 'dominio': dominio};
        if (dominio < 60) {
          riesgoAlto.add(item);
        } else if (dominio < 75) {
          riesgoMedio.add(item);
        } else {
          riesgoBajo.add(item);
        }
      }
      riesgoAlto.sort(
        (a, b) => (_toDouble(a['dominio']) ?? 100).compareTo(
          _toDouble(b['dominio']) ?? 100,
        ),
      );
      riesgoMedio.sort(
        (a, b) => (_toDouble(a['dominio']) ?? 100).compareTo(
          _toDouble(b['dominio']) ?? 100,
        ),
      );

      final probActual =
          _toDouble(proyeccion['probabilidad_aprobacion']) ?? porcentajeAcierto;
      final ritmoActual = _toDouble(proyeccion['ritmo_actual_dia']) ?? 0.0;
      final ritmoNecesario =
          _toDouble(proyeccion['ritmo_necesario_dia']) ?? 0.0;
      final prob14 = proyeccion14Dias(
        probabilidadActual: probActual,
        ritmoActual: ritmoActual,
        ritmoNecesario: ritmoNecesario,
        porcentajeAcierto: porcentajeAcierto,
        materiasCriticas: riesgoAlto.length,
      );

      final metricasVelocidadRaw = velocidad['metricas_velocidad'];
      final metricasVelocidad = metricasVelocidadRaw is Map
          ? Map<String, dynamic>.from(metricasVelocidadRaw)
          : <String, dynamic>{};
      final preguntasLentas = velocidad['preguntas_lentas'] is List
          ? (velocidad['preguntas_lentas'] as List).length
          : _toInt(metricasVelocidad['lentas']);
      final promedioVelocidad =
          _toDouble(metricasVelocidad['promedio_segundos']) ??
          _toDouble(analisis['velocidad_promedio']) ??
          0.0;

      final indiceMemoria = _toDouble(coachMemoria['indice_memoria']) ?? 0.0;
      final interpretacionMemoria =
          (coachMemoria['interpretacion_indice'] ?? '').toString().trim();
      final totalCriticas = _toInt(coachMemoria['total_criticas']) > 0
          ? _toInt(coachMemoria['total_criticas'])
          : (coachMemoria['preguntas_criticas'] is List
                ? (coachMemoria['preguntas_criticas'] as List).length
                : 0);
      var dominadas = _toInt(analisis['preguntas_dominadas']);
      if (dominadas <= 0) {
        final metricasMemRaw = coachMemoria['metricas_generales'];
        final metricasMem = metricasMemRaw is Map
            ? Map<String, dynamic>.from(metricasMemRaw)
            : <String, dynamic>{};
        dominadas = _toInt(metricasMem['total_correctas']);
      }
      final enRiesgoOlvido = _toInt(olvidoDetalle['total_preguntas']);

      final totalErroresAnalizados =
          erroresDesconocimiento + erroresDistraccion + erroresTiempo;
      final pctDesconocimiento = totalErroresAnalizados > 0
          ? (erroresDesconocimiento * 100.0) / totalErroresAnalizados
          : 0.0;
      final pctDistraccion = totalErroresAnalizados > 0
          ? (erroresDistraccion * 100.0) / totalErroresAnalizados
          : 0.0;
      final pctTiempo = totalErroresAnalizados > 0
          ? (erroresTiempo * 100.0) / totalErroresAnalizados
          : 0.0;

      final debilidadTop = riesgoAlto.isNotEmpty
          ? (riesgoAlto.first['materia'] ?? '').toString()
          : (riesgoMedio.isNotEmpty
                ? (riesgoMedio.first['materia'] ?? '').toString()
                : '');
      var preguntasHoy = 30;
      if (probActual < 70) preguntasHoy += 10;
      if (riesgoAlto.isNotEmpty) preguntasHoy += 5;
      if (totalCriticas > 20) preguntasHoy += 5;
      if (indiceMemoria > 0 && indiceMemoria < 70) preguntasHoy += 5;
      preguntasHoy = preguntasHoy.clamp(20, 60);
      final mensajeCoach = debilidadTop.trim().isEmpty
          ? 'Tu rendimiento viene en progreso. Se recomienda practicar $preguntasHoy preguntas hoy para consolidar tu avance.'
          : 'Tu mayor debilidad es $debilidadTop. Se recomienda practicar $preguntasHoy preguntas hoy.';

      return {
        'estado': 'ok',
        'nivel_postulante': {
          'nombre': nivelUsuario,
          'porcentaje': porcentajeAcierto,
        },
        'rendimiento_general': {
          'preguntas_respondidas': preguntasRespondidas,
          'porcentaje_acierto': porcentajeAcierto,
          'simulacros_realizados': simulacrosRealizados,
          'mejor_simulacro': mejorSimulacro,
        },
        'probabilidad_aprobar': {
          'actual': probActual,
          'proyeccion_14_dias': prob14,
          'ritmo_actual_dia': ritmoActual,
          'ritmo_necesario_dia': ritmoNecesario,
        },
        'riesgo_por_materia': {
          'alto': riesgoAlto.take(6).toList(),
          'medio': riesgoMedio.take(6).toList(),
          'bajo': riesgoBajo.take(6).toList(),
        },
        'analisis_velocidad': {
          'promedio_segundos': promedioVelocidad,
          'tiempo_objetivo_segundos': 72.0,
          'preguntas_lentas_total': preguntasLentas,
        },
        'indice_memoria': {
          'indice': indiceMemoria,
          'interpretacion': interpretacionMemoria,
          'dominadas': dominadas,
          'en_riesgo_olvido': enRiesgoOlvido,
          'criticas': totalCriticas,
        },
        'patrones_error': {
          'desconocimiento_pct': pctDesconocimiento,
          'distraccion_pct': pctDistraccion,
          'falta_tiempo_pct': pctTiempo,
          'total_errores_analizados': totalErroresAnalizados,
        },
        'evolucion_rendimiento': {
          'semanal_pct': semanaActualPct,
          'semanal_previa_pct': semanaPreviaPct,
          'mensual_pct': mensualPct,
          'mensual_previa_pct': mensualPrevioPct,
          'mejora_simulacros_pct': mejoraSimulacros,
          'serie_semanal': serieSemanal,
        },
        'recomendacion_coach': {
          'mensaje': mensajeCoach,
          'materia_objetivo': debilidadTop,
          'preguntas_hoy': preguntasHoy,
        },
      };
    } catch (e) {
      debugPrint('obtenerAnalisisCompletoPerfilDetallado error: $e');
      return _analisisCompletoPerfilFallbackLegacy(
        estado: 'error',
        mensaje:
            'No se pudo calcular el analisis completo de perfil en este momento.',
      );
    }
  }

  Map<String, dynamic> _analisisCompletoPerfilFallbackLegacy({
    required String estado,
    required String mensaje,
  }) {
    return {
      'estado': estado,
      'mensaje': mensaje,
      'nivel_postulante': {'nombre': 'Muy Bajo', 'porcentaje': 0.0},
      'rendimiento_general': {
        'preguntas_respondidas': 0,
        'porcentaje_acierto': 0.0,
        'simulacros_realizados': 0,
        'mejor_simulacro': 0.0,
      },
      'probabilidad_aprobar': {
        'actual': 0.0,
        'proyeccion_14_dias': 0.0,
        'ritmo_actual_dia': 0.0,
        'ritmo_necesario_dia': 0.0,
      },
      'riesgo_por_materia': {
        'alto': <Map<String, dynamic>>[],
        'medio': <Map<String, dynamic>>[],
        'bajo': <Map<String, dynamic>>[],
      },
      'analisis_velocidad': {
        'promedio_segundos': 0.0,
        'tiempo_objetivo_segundos': 72.0,
        'preguntas_lentas_total': 0,
      },
      'indice_memoria': {
        'indice': 0.0,
        'interpretacion': 'Necesita repaso',
        'dominadas': 0,
        'en_riesgo_olvido': 0,
        'criticas': 0,
      },
      'patrones_error': {
        'desconocimiento_pct': 0.0,
        'distraccion_pct': 0.0,
        'falta_tiempo_pct': 0.0,
        'total_errores_analizados': 0,
      },
      'evolucion_rendimiento': {
        'semanal_pct': 0.0,
        'semanal_previa_pct': 0.0,
        'mensual_pct': 0.0,
        'mensual_previa_pct': 0.0,
        'mejora_simulacros_pct': 0.0,
        'serie_semanal': <Map<String, dynamic>>[],
      },
      'recomendacion_coach': {
        'mensaje':
            'Completa una practica hoy para activar recomendaciones mas precisas.',
        'materia_objetivo': '',
        'preguntas_hoy': 20,
      },
    };
  }

  Future<Map<String, dynamic>> obtenerProyeccionTiempoDetalle({
    required String userId,
    String? categoriaUsuario,
    Map<String, dynamic>? progresoBase,
    Map<String, dynamic>? planBase,
    Map<String, dynamic>? probabilidadBase,
    Map<String, dynamic>? diasBase,
    Map<String, dynamic>? perfilBase,
  }) async {
    int? toOptionalInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    double? toOptionalDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    Map<String, dynamic> fallback({
      required String estado,
      required String resumen,
      String detalle = '',
      bool sesionValida = false,
    }) {
      return {
        'estado': estado,
        'sesion_valida': sesionValida,
        'resumen': resumen,
        'detalle': detalle,
        'total_preguntas_objetivo': null,
        'preguntas_dominadas': 0,
        'preguntas_faltantes': null,
        'porcentaje_completado': null,
        'ritmo_actual_dia': null,
        'ritmo_necesario_dia': null,
        'brecha_dia': null,
        'dias_estimados_completar': null,
        'fecha_estimada_listo': '',
        'fecha_estimada_listo_iso': '',
        'fecha_examen': '',
        'fecha_examen_iso': '',
        'dias_restantes_examen': null,
        'semaforo_avance': 'sin_datos',
        'label_semaforo': 'Sin datos',
        'probabilidad_aprobacion': null,
        'ritmo_suficiente': false,
      };
    }

    final usuario = userId.trim();
    if (!SupabaseService.isInitialized || _sesionInvalida(usuario)) {
      return fallback(
        estado: 'sin_sesion',
        resumen:
            'Inicia sesion para ver tu proyeccion de tiempo con datos reales.',
        detalle:
            'Necesito una sesion valida para calcular ritmo y fecha estimada.',
      );
    }

    try {
      final params = <String, dynamic>{'p_usuario_id': usuario};
      final progreso =
          progresoBase ??
          await _rpcComoMapa(
            functionName: 'fn_calcular_progreso_dinamico',
            params: params,
          );
      final dias =
          diasBase ??
          await _rpcComoMapa(
            functionName: 'fn_calcular_dias_disponibles',
            params: params,
          );

      final perfil = perfilBase ?? await _obtenerPerfilUsuarioBasico(usuario);
      final categoriaResuelta =
          (categoriaUsuario ??
                  perfil['categoria'] ??
                  perfil['categoria_usuario'] ??
                  '')
              .toString()
              .trim();

      final totalObjetivo = await _contarTotalPreguntasObjetivoReal(
        categoriaUsuario: categoriaResuelta.isEmpty ? null : categoriaResuelta,
      );

      final dominadasVerificadas = await _contarPreguntasDominadasUsuario(
        usuario,
      );
      var dominadasFinal = dominadasVerificadas > 0
          ? dominadasVerificadas
          : _toInt(progreso?['preguntas_dominadas']);
      if (dominadasFinal < 0) dominadasFinal = 0;
      if (totalObjetivo != null && totalObjetivo >= 0) {
        dominadasFinal = dominadasFinal.clamp(0, totalObjetivo);
      }

      final faltantes = (totalObjetivo != null && totalObjetivo >= 0)
          ? math.max(totalObjetivo - dominadasFinal, 0)
          : null;

      final porcentajeCompletado = (totalObjetivo != null && totalObjetivo > 0)
          ? ((dominadasFinal * 100.0) / totalObjetivo).clamp(0.0, 100.0)
          : null;

      var ritmoActual = toOptionalDouble(progreso?['ritmo_actual_dia']);
      if (ritmoActual == null) {
        final diasTranscurridos =
            toOptionalInt(progreso?['dias_transcurridos']) ??
            toOptionalInt(dias?['dias_transcurridos']);
        if (diasTranscurridos != null && diasTranscurridos > 0) {
          ritmoActual = dominadasFinal / diasTranscurridos;
        }
      }

      var diasRestantesExamen =
          toOptionalInt(progreso?['dias_restantes']) ??
          toOptionalInt(dias?['dias_restantes']);

      final ritmoNecesario =
          (faltantes != null &&
              diasRestantesExamen != null &&
              diasRestantesExamen > 0)
          ? (faltantes / diasRestantesExamen)
          : null;

      final brechaDia = (ritmoNecesario != null && ritmoActual != null)
          ? math.max(ritmoNecesario - ritmoActual, 0)
          : null;

      int? diasEstimadosCompletar;
      DateTime? fechaEstimadaListo;
      if (faltantes != null && faltantes <= 0) {
        diasEstimadosCompletar = 0;
        fechaEstimadaListo = DateTime.now();
      } else if (faltantes != null &&
          ritmoActual != null &&
          ritmoActual > 0 &&
          faltantes > 0) {
        diasEstimadosCompletar = (faltantes / ritmoActual).ceil();
        fechaEstimadaListo = DateTime.now().add(
          Duration(days: diasEstimadosCompletar),
        );
      }

      final fechaExamen =
          _parseFechaFlexible(progreso?['fecha_examen']) ??
          _parseFechaFlexible(dias?['fecha_examen']);
      if (diasRestantesExamen == null && fechaExamen != null) {
        final hoy = DateTime.now();
        final baseHoy = DateTime(hoy.year, hoy.month, hoy.day);
        final baseExamen = DateTime(
          fechaExamen.year,
          fechaExamen.month,
          fechaExamen.day,
        );
        diasRestantesExamen = baseExamen.difference(baseHoy).inDays;
      }

      final tasaAcierto = _toDouble(perfil['tasa_acierto_global']);
      final rachaDias = _toInt(perfil['dias_consecutivos_estudio']);
      final materiasCriticas = await _contarMateriasCriticasUsuario(usuario);
      final probabilidadAprobacion =
          (totalObjetivo != null && totalObjetivo > 0 && tasaAcierto != null)
          ? _calcularProbabilidadAprobacionReal(
              dominadas: dominadasFinal,
              totalObjetivo: totalObjetivo,
              tasaAcierto: tasaAcierto,
              materiasCriticas: materiasCriticas,
              rachaDias: rachaDias,
              ritmoActual: ritmoActual ?? 0.0,
              ritmoNecesario: ritmoNecesario,
            )
          : null;

      late final String semaforoAvance;
      late final String labelSemaforo;
      if (totalObjetivo == null || totalObjetivo <= 0) {
        semaforoAvance = 'sin_datos';
        labelSemaforo = 'Sin datos';
      } else if (faltantes != null && faltantes <= 0) {
        semaforoAvance = 'completado';
        labelSemaforo = 'Objetivo completado';
      } else if (ritmoActual == null ||
          ritmoActual <= 0 ||
          ritmoNecesario == null) {
        semaforoAvance = 'sin_datos';
        labelSemaforo = 'Sin datos';
      } else if (ritmoActual >= ritmoNecesario) {
        semaforoAvance = 'en_ritmo';
        labelSemaforo = 'En ritmo';
      } else if (ritmoActual >= (ritmoNecesario * 0.85)) {
        semaforoAvance = 'justo';
        labelSemaforo = 'Justo';
      } else {
        semaforoAvance = 'atrasado';
        labelSemaforo = 'Atrasado';
      }

      late final String resumen;
      if (totalObjetivo == null || totalObjetivo <= 0) {
        resumen =
            'No pude verificar tu total real de preguntas objetivo en este momento.';
      } else if (faltantes != null && faltantes <= 0) {
        resumen =
            'Ya completaste tu objetivo real de $totalObjetivo preguntas disponibles.';
      } else if (diasEstimadosCompletar != null) {
        resumen =
            'A este ritmo te tomaria ~$diasEstimadosCompletar dias completar tus faltantes reales.';
      } else {
        resumen = 'Aun no hay ritmo suficiente para proyectar tiempo real.';
      }

      String ritmoEnteroTexto(double? valor, {bool redondearArriba = false}) {
        if (valor == null) return '--';
        final entero = redondearArriba ? valor.ceil() : valor.round();
        return '$entero';
      }

      final detalle = (totalObjetivo == null || totalObjetivo <= 0)
          ? 'Dominadas verificadas: $dominadasFinal. Total objetivo real: no disponible.'
          : 'Dominadas: $dominadasFinal/$totalObjetivo. Faltantes: ${faltantes ?? '--'}. Ritmo actual: ${ritmoEnteroTexto(ritmoActual)}/dia. Ritmo necesario: ${ritmoEnteroTexto(ritmoNecesario, redondearArriba: true)}/dia.';

      return {
        'estado': 'ok',
        'sesion_valida': true,
        'resumen': resumen,
        'detalle': detalle,
        'total_preguntas_objetivo': totalObjetivo,
        'preguntas_dominadas': dominadasFinal,
        'preguntas_faltantes': faltantes,
        'porcentaje_completado': porcentajeCompletado,
        'ritmo_actual_dia': ritmoActual,
        'ritmo_necesario_dia': ritmoNecesario,
        'brecha_dia': brechaDia,
        'dias_estimados_completar': diasEstimadosCompletar,
        'fecha_estimada_listo': fechaEstimadaListo == null
            ? ''
            : _formatearFecha(fechaEstimadaListo),
        'fecha_estimada_listo_iso': fechaEstimadaListo?.toIso8601String() ?? '',
        'fecha_examen': fechaExamen == null ? '' : _formatearFecha(fechaExamen),
        'fecha_examen_iso': fechaExamen?.toIso8601String() ?? '',
        'dias_restantes_examen': diasRestantesExamen,
        'semaforo_avance': semaforoAvance,
        'label_semaforo': labelSemaforo,
        'probabilidad_aprobacion': probabilidadAprobacion,
        'ritmo_suficiente': (ritmoActual ?? 0) > 0,
      };
    } catch (e) {
      debugPrint('obtenerProyeccionTiempoDetalle error: $e');
      return fallback(
        estado: 'error',
        resumen: 'No se pudo cargar la proyeccion de tiempo en este momento.',
        detalle: 'Intenta actualizar en unos segundos.',
        sesionValida: true,
      );
    }
  }

  Future<int?> _contarTotalPreguntasObjetivoReal({
    String? categoriaUsuario,
  }) async {
    try {
      final servicioPreguntas = ServicioPreguntas();
      final categoria = (categoriaUsuario ?? '').trim();
      if (categoria.isEmpty) {
        return null;
      }
      final total = await servicioPreguntas.contarPreguntasDisponibles(
        categoria: categoria,
      );
      return total;
    } catch (e) {
      debugPrint('_contarTotalPreguntasObjetivoReal error: $e');
      return null;
    }
  }

  Future<int> _contarPreguntasDominadasUsuario(String userId) async {
    try {
      final List<dynamic> response = await _supabase
          .from('exposicion_pregunta')
          .select('pregunta_id')
          .eq('usuario_id', userId)
          .eq('estado_dominio', 'dominada');
      final ids = response
          .whereType<Map>()
          .map((row) {
            final map = Map<String, dynamic>.from(row);
            return map['pregunta_id']?.toString() ?? '';
          })
          .where((id) => id.isNotEmpty)
          .toSet();
      return ids.length;
    } catch (e) {
      debugPrint('_contarPreguntasDominadasUsuario error: $e');
      return 0;
    }
  }

  Future<int> _contarMateriasCriticasUsuario(String userId) async {
    try {
      final response = await _supabase
          .from('dominio_materia')
          .select('materia_id')
          .eq('usuario_id', userId)
          .lt('tasa_dominio', 60)
          .count();
      return response.count;
    } catch (e) {
      debugPrint('_contarMateriasCriticasUsuario error: $e');
      return 0;
    }
  }

  Future<Map<String, dynamic>> _obtenerPerfilUsuarioBasico(
    String userId,
  ) async {
    try {
      final row = await _supabase
          .from('perfil_usuario')
          .select('categoria, tasa_acierto_global, dias_consecutivos_estudio')
          .eq('usuario_id', userId)
          .maybeSingle();
      if (row is Map) return Map<String, dynamic>.from(row as Map);
      return const <String, dynamic>{};
    } catch (e) {
      debugPrint('_obtenerPerfilUsuarioBasico error: $e');
      return const <String, dynamic>{};
    }
  }

  double _calcularProbabilidadAprobacionReal({
    required int dominadas,
    required int totalObjetivo,
    required double tasaAcierto,
    required int materiasCriticas,
    required int rachaDias,
    required double ritmoActual,
    required double? ritmoNecesario,
  }) {
    var probabilidad = 50.0;

    // Factor 1: Progreso actual (40%)
    probabilidad += (((dominadas / totalObjetivo) * 100.0 - 50.0) * 0.4);

    // Factor 2: Tasa de acierto (25%)
    probabilidad += ((tasaAcierto - 50.0) * 0.25);

    // Factor 3: Ritmo (20%)
    if (ritmoNecesario == null || ritmoNecesario <= 0) {
      probabilidad += dominadas >= totalObjetivo ? 20.0 : 0.0;
    } else if (ritmoActual >= ritmoNecesario) {
      probabilidad += 20.0;
    } else if (ritmoActual >= (ritmoNecesario * 0.8)) {
      probabilidad += 10.0;
    } else if (ritmoActual >= (ritmoNecesario * 0.6)) {
      probabilidad += 0.0;
    } else {
      probabilidad -= 10.0;
    }

    // Factor 4: Materias críticas (-15% máx aprox)
    probabilidad -= (materiasCriticas * 3.0);

    // Factor 5: Racha de estudio (+15%)
    if (rachaDias >= 30) {
      probabilidad += 15.0;
    } else if (rachaDias >= 14) {
      probabilidad += 10.0;
    } else if (rachaDias >= 7) {
      probabilidad += 5.0;
    }

    return probabilidad.clamp(0.0, 100.0);
  }

  Future<Map<String, dynamic>> obtenerResumenPlanDiarioEstructurado({
    required String userId,
    Map<String, dynamic>? planBase,
    Map<String, dynamic>? progresoBase,
    Map<String, dynamic>? probabilidadBase,
    Map<String, dynamic>? proyeccionBase,
  }) async {
    if (_sesionInvalida(userId)) {
      return _cardFallback(
        id: 'plan_hoy',
        titulo: 'Ordenes del tutor para hoy',
        prompt: 'dame mi plan diario',
        color: '#BFDBFE',
        icono: 'calendar_month',
        resumen: 'Inicia sesion para generar tu plan diario.',
      );
    }

    final params = <String, dynamic>{'p_usuario_id': userId};
    final plan = await _obtenerPlanAdaptativoSeguro(
      userId: userId,
      planBase: planBase,
    );
    final progreso =
        progresoBase ??
        await _rpcComoMapa(
          functionName: 'fn_calcular_progreso_dinamico',
          params: params,
        );
    final proyeccion =
        proyeccionBase ??
        await obtenerProyeccionTiempoDetalle(
          userId: userId,
          progresoBase: progreso,
          planBase: plan,
        );

    if (plan == null) {
      return _cardFallback(
        id: 'plan_hoy',
        titulo: 'Ordenes del tutor para hoy',
        prompt: 'dame mi plan diario',
        color: '#BFDBFE',
        icono: 'calendar_month',
        resumen: 'No se encontro plan adaptativo para hoy.',
      );
    }

    final total = _toInt(plan['total_preguntas_dia']);
    final nuevas = _toInt(plan['cantidad_nuevas']);
    final repaso = _toInt(plan['cantidad_repaso']);
    final nuevasIds = _toStringList(plan['preguntas_nuevas']);
    final repasoIds = _toStringList(plan['preguntas_repaso']);
    final prioritariasRpc = _toStringList(plan['pregunta_ids_prioritarias']);
    final prioritarias = _mergeIdsPreservandoOrden([
      if (prioritariasRpc.isNotEmpty) prioritariasRpc,
      repasoIds,
      nuevasIds,
    ]);
    final materiasPrioritariasIds = _toStringList(
      plan['materias_prioritarias'],
    );
    final diasRestantes = _toInt(
      proyeccion['dias_restantes_examen'] ?? plan['dias_restantes'],
    );
    final faltantes = _toInt(
      proyeccion['preguntas_faltantes'] ?? plan['preguntas_faltantes'],
    );
    final prob = _toDouble(proyeccion['probabilidad_aprobacion']) ?? 0;
    final ritmoActual =
        _toDouble(proyeccion['ritmo_actual_dia']) ??
        _toDouble(progreso?['ritmo_actual_dia']) ??
        0;
    final ritmoNecesario =
        _toDouble(proyeccion['ritmo_necesario_dia']) ??
        _toDouble(progreso?['ritmo_necesario_dia']) ??
        0;

    return {
      'id': 'plan_hoy',
      'titulo': 'Ordenes del tutor para hoy',
      'resumen':
          'Hoy te recomiendo $total preguntas: $nuevas nuevas y $repaso repaso.',
      'detalle':
          'Dias restantes: $diasRestantes. Preguntas faltantes: $faltantes. Ritmo actual: ${ritmoActual.toStringAsFixed(2)}/dia vs ${ritmoNecesario.toStringAsFixed(2)}/dia. Probabilidad estimada: ${prob.toStringAsFixed(1)}%.',
      'prompt': 'dame mi plan diario',
      'cta': 'Ver plan diario',
      'color': '#BFDBFE',
      'icono': 'calendar_month',
      'expandable': true,
      'cantidad_practica': total > 0 ? total : 20,
      'tiempo_practica': _minutosSugeridosDesdePlan(total),
      'pregunta_ids': prioritarias,
      'preguntas_nuevas_ids': nuevasIds,
      'preguntas_repaso_ids': repasoIds,
      'materias_prioritarias_ids': materiasPrioritariasIds,
    };
  }

  Future<Map<String, dynamic>> obtenerResumenQueEstudiarEstructurado({
    required String userId,
    Map<String, dynamic>? perfilUsuario,
  }) async {
    if (_sesionInvalida(userId)) {
      return _cardFallback(
        id: 'materia_prioritaria',
        titulo: 'Materia Prioritaria',
        prompt: 'que estudiar hoy',
        color: '#C7D2FE',
        icono: 'school',
        resumen: 'Inicia sesion para detectar tu materia prioritaria.',
      );
    }

    try {
      final List<dynamic> raw = await _supabase
          .from('dominio_materia')
          .select(
            'tasa_dominio, dominio_hace_7_dias, tiempo_recomendado_minutos, temas_debiles, materia:materia_id(id, nombre, categoria)',
          )
          .eq('usuario_id', userId)
          .order('tasa_dominio', ascending: true);

      final rows = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (rows.isEmpty) {
        return _cardFallback(
          id: 'materia_prioritaria',
          titulo: 'Materia Prioritaria',
          prompt: 'que estudiar hoy',
          color: '#C7D2FE',
          icono: 'school',
          resumen: 'Aun no hay datos por materia para priorizar.',
        );
      }

      final especialidadRaw = (perfilUsuario?['especialidad'] ?? '').toString();
      final especialidad = especialidadRaw.trim();
      final especialidadNormalizada = _normalizarTextoEspecialidad(
        especialidad,
      );
      final keywordsEspecialidad = _palabrasClaveEspecialidad(especialidad);

      List<Map<String, dynamic>> candidatas = rows;
      var filtroEspecialidadAplicado = false;
      if (especialidadNormalizada.isNotEmpty) {
        final filtradas = rows.where((row) {
          return _esMateriaRelacionadaAEspecialidad(
            row: row,
            especialidadNormalizada: especialidadNormalizada,
            keywordsEspecialidad: keywordsEspecialidad,
          );
        }).toList();
        if (filtradas.isNotEmpty) {
          candidatas = filtradas;
          filtroEspecialidadAplicado = true;
        }
      }

      candidatas.sort((a, b) {
        final tasaA = _toDouble(a['tasa_dominio']) ?? 100.0;
        final tasaB = _toDouble(b['tasa_dominio']) ?? 100.0;
        return tasaA.compareTo(tasaB);
      });

      final row = candidatas.first;
      final materia = _asMap(row['materia']);
      final nombre = (materia['nombre'] ?? 'Materia').toString();
      final tasa = _toDouble(row['tasa_dominio']) ?? 0;
      final hace7 = _toDouble(row['dominio_hace_7_dias']);
      final delta = hace7 == null ? 0.0 : (tasa - hace7);
      final tendencia = delta > 1.5
          ? 'mejorando'
          : (delta < -1.5 ? 'empeorando' : 'estable');
      final tiempo = _toInt(row['tiempo_recomendado_minutos']);
      final temas = _toStringList(row['temas_debiles']);
      final resumenCard = filtroEspecialidadAplicado
          ? 'Especialidad $especialidad: $nombre (${tasa.toStringAsFixed(1)}%) es tu foco de hoy.'
          : (especialidad.isNotEmpty
                ? 'Especialidad $especialidad: refuerzo transversal en $nombre (${tasa.toStringAsFixed(1)}%).'
                : '$nombre (${tasa.toStringAsFixed(1)}%) es tu foco de hoy.');
      final prefijoDetalle = filtroEspecialidadAplicado
          ? 'Materias de especialidad detectadas para tu perfil. '
          : (especialidad.isNotEmpty
                ? 'No hubo cruce exacto por nombre; se priorizo la materia con menor dominio dentro de tu banco. '
                : '');

      return {
        'id': 'materia_prioritaria',
        'titulo': 'Materia Prioritaria',
        'resumen': resumenCard,
        'detalle':
            '${prefijoDetalle}Tendencia: $tendencia. Tiempo sugerido: ${tiempo > 0 ? tiempo : 25} minutos. Temas: ${temas.isEmpty ? 'sin detalle' : temas.take(3).join(', ')}.',
        'prompt': 'que estudiar hoy',
        'cta': 'Ver materia prioritaria',
        'color': '#C7D2FE',
        'icono': 'menu_book',
        'expandable': true,
        'materia': nombre,
        'tiempo_practica': tiempo > 0 ? tiempo : 25,
        'cantidad_practica': 20,
      };
    } catch (_) {
      return _cardFallback(
        id: 'materia_prioritaria',
        titulo: 'Materia Prioritaria',
        prompt: 'que estudiar hoy',
        color: '#C7D2FE',
        icono: 'school',
        resumen: 'No pude calcular tu materia prioritaria ahora.',
      );
    }
  }

  Future<Map<String, dynamic>> obtenerResumenUltimaSesionEstructurado({
    required String userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return _cardFallback(
        id: 'debrief_sesion',
        titulo: 'Debrief de Ultima Sesion',
        prompt: 'analiza mi ultima sesion',
        color: '#A7F3D0',
        icono: 'assignment_turned_in',
        resumen: 'Inicia sesion para analizar tu ultima sesion.',
      );
    }

    try {
      final List<dynamic> rawSesiones = await _supabase
          .from('sesion_practica')
          .select(
            'id, nombre_sesion, tipo_sesion, completada, estado, preguntas_correctas, preguntas_incorrectas, preguntas_omitidas, preguntas_respondidas, fecha_inicio',
          )
          .eq('usuario_id', userId)
          .order('fecha_inicio', ascending: false)
          .limit(6);

      final sesiones = rawSesiones
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((s) => s['completada'] == true || s['estado'] == 'completada')
          .toList();

      if (sesiones.isEmpty) {
        return _cardFallback(
          id: 'debrief_sesion',
          titulo: 'Debrief de Ultima Sesion',
          prompt: 'analiza mi ultima sesion',
          color: '#A7F3D0',
          icono: 'assignment_turned_in',
          resumen: 'No hay sesiones completadas para analizar.',
        );
      }

      int respondidasSesion(Map<String, dynamic> s) {
        final guardado = _toInt(s['preguntas_respondidas']);
        if (guardado > 0) return guardado;
        return _toInt(s['preguntas_correctas']) +
            _toInt(s['preguntas_incorrectas']) +
            _toInt(s['preguntas_omitidas']);
      }

      final actual = sesiones.first;
      final respondidas = respondidasSesion(actual);
      final correctas = _toInt(actual['preguntas_correctas']);
      final tasaActual = respondidas > 0
          ? (correctas * 100.0) / respondidas
          : 0;

      final previas = sesiones.skip(1).take(4).toList();
      double promedioPrevio = 0;
      if (previas.isNotEmpty) {
        final tasas = previas.map((s) {
          final r = respondidasSesion(s);
          final c = _toInt(s['preguntas_correctas']);
          return r > 0 ? (c * 100.0) / r : 0.0;
        }).toList();
        promedioPrevio = tasas.reduce((a, b) => a + b) / tasas.length;
      }
      final delta = tasaActual - promedioPrevio;
      final tendencia = previas.isEmpty
          ? 'sin comparativo'
          : (delta >= 0
                ? 'mejoraste ${delta.toStringAsFixed(1)} puntos'
                : 'bajaste ${delta.abs().toStringAsFixed(1)} puntos');

      final nombre =
          (actual['nombre_sesion'] ?? actual['tipo_sesion'] ?? 'Sesion')
              .toString();
      final incorrectas = _toInt(actual['preguntas_incorrectas']);

      return {
        'id': 'debrief_sesion',
        'titulo': 'Debrief de Ultima Sesion',
        'resumen':
            '$nombre: $correctas/$respondidas correctas (${tasaActual.toStringAsFixed(1)}%).',
        'detalle': 'Incorrectas: $incorrectas. Resultado: $tendencia.',
        'prompt': 'analiza mi ultima sesion',
        'cta': 'Analizar sesion',
        'color': '#A7F3D0',
        'icono': 'assignment_turned_in',
        'expandable': true,
      };
    } catch (_) {
      return _cardFallback(
        id: 'debrief_sesion',
        titulo: 'Debrief de Ultima Sesion',
        prompt: 'analiza mi ultima sesion',
        color: '#A7F3D0',
        icono: 'assignment_turned_in',
        resumen: 'No pude analizar tu ultima sesion en este momento.',
      );
    }
  }

  Future<Map<String, dynamic>> obtenerAnalisisVelocidadEstructurado({
    required String userId,
  }) async {
    final usuario = userId.trim();
    if (_sesionInvalida(usuario)) {
      return _cardFallback(
        id: 'coach_velocidad',
        titulo: 'Coach de Velocidad',
        prompt: 'analisis de velocidad',
        color: '#BBF7D0',
        icono: 'bolt',
        resumen: 'Inicia sesion para analizar tu velocidad.',
      );
    }

    final cache = _leerCacheCoachVelocidad(usuario);
    if (cache != null) return cache;

    final enCurso = _inflightCoachVelocidad[usuario];
    if (enCurso != null) {
      final card = await enCurso;
      return _copiarMapa(card);
    }

    final future = _obtenerAnalisisVelocidadEstructuradoCore(userId: usuario);
    _inflightCoachVelocidad[usuario] = future;
    try {
      final card = await future;
      _guardarCacheCoachVelocidad(usuario, card);
      return _copiarMapa(card);
    } finally {
      _inflightCoachVelocidad.remove(usuario);
    }
  }

  Future<Map<String, dynamic>> _obtenerAnalisisVelocidadEstructuradoCore({
    required String userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return _cardFallback(
        id: 'coach_velocidad',
        titulo: 'Coach de Velocidad',
        prompt: 'analisis de velocidad',
        color: '#BBF7D0',
        icono: 'bolt',
        resumen: 'Inicia sesion para analizar tu velocidad.',
      );
    }

    final desdeRpc = await _obtenerAnalisisVelocidadDesdeRpc(userId: userId);
    if (desdeRpc != null) {
      return desdeRpc;
    }

    try {
      final nowUtc = DateTime.now().toUtc();
      final List<dynamic> raw = await _supabase
          .from('respuesta_usuario')
          .select(
            'pregunta_id, tiempo_total_respuesta, fue_omitida, es_correcta, respondida_at, '
            'pregunta:pregunta_id(materia:materia_id(nombre))',
          )
          .eq('usuario_id', userId)
          .order('respondida_at', ascending: false)
          .limit(_ventanaRespuestasVelocidad);

      final rows = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((r) => r['fue_omitida'] != true && (r['es_correcta'] is bool))
          .toList();
      if (rows.isEmpty) {
        return _cardFallback(
          id: 'coach_velocidad',
          titulo: 'Coach de Velocidad',
          prompt: 'analisis de velocidad',
          color: '#BBF7D0',
          icono: 'bolt',
          resumen: 'Aun no hay respuestas validas para evaluar tu velocidad.',
        );
      }

      double globalPeso = 0.0;
      double globalTiempoPonderado = 0.0;
      double globalImpPeso = 0.0;
      double globalOptPeso = 0.0;
      double globalLenPeso = 0.0;
      int globalMuestraTiempo = 0;
      int globalValidasAcierto = 0;
      int globalCorrectasAcierto = 0;

      final Map<String, Map<String, dynamic>> statsPorMateria = {};
      final Map<String, Map<String, dynamic>> tiemposPorPregunta = {};

      for (final row in rows) {
        final esCorrecta = row['es_correcta'] == true;
        final pregunta = _asMap(row['pregunta']);
        final materia = _asMap(pregunta['materia']);
        final nombreMateria = (materia['nombre'] ?? '').toString().trim();
        if (nombreMateria.isEmpty) continue;

        final materiaStats = statsPorMateria.putIfAbsent(
          nombreMateria,
          () => <String, dynamic>{
            'muestra_tiempo': 0,
            'respuestas_validas': 0,
            'correctas_validas': 0,
            'peso_total': 0.0,
            'tiempo_ponderado': 0.0,
            'impulsiva_peso': 0.0,
            'optima_peso': 0.0,
            'lenta_peso': 0.0,
          },
        );

        materiaStats['respuestas_validas'] =
            _toInt(materiaStats['respuestas_validas']) + 1;
        globalValidasAcierto += 1;
        if (esCorrecta) {
          materiaStats['correctas_validas'] =
              _toInt(materiaStats['correctas_validas']) + 1;
          globalCorrectasAcierto += 1;
        }

        final tiempo = _toDouble(row['tiempo_total_respuesta']) ?? 0.0;
        if (tiempo <= 0) continue;

        final respondedAt = DateTime.tryParse(
          (row['respondida_at'] ?? '').toString(),
        )?.toUtc();
        final peso = _pesoRecenciaRespuesta(
          respondedAtUtc: respondedAt,
          referenciaUtc: nowUtc,
        );

        globalPeso += peso;
        globalTiempoPonderado += tiempo * peso;
        globalMuestraTiempo += 1;
        if (tiempo < 8) {
          globalImpPeso += peso;
        } else if (tiempo <= 20) {
          globalOptPeso += peso;
        } else {
          globalLenPeso += peso;
        }

        materiaStats['muestra_tiempo'] =
            _toInt(materiaStats['muestra_tiempo']) + 1;
        materiaStats['peso_total'] =
            (_toDouble(materiaStats['peso_total']) ?? 0) + peso;
        materiaStats['tiempo_ponderado'] =
            (_toDouble(materiaStats['tiempo_ponderado']) ?? 0) +
            (tiempo * peso);
        if (tiempo < 8) {
          materiaStats['impulsiva_peso'] =
              (_toDouble(materiaStats['impulsiva_peso']) ?? 0) + peso;
        } else if (tiempo <= 20) {
          materiaStats['optima_peso'] =
              (_toDouble(materiaStats['optima_peso']) ?? 0) + peso;
        } else {
          materiaStats['lenta_peso'] =
              (_toDouble(materiaStats['lenta_peso']) ?? 0) + peso;
        }

        final preguntaId = (row['pregunta_id'] ?? pregunta['id'])
            .toString()
            .trim();
        if (preguntaId.isEmpty) continue;
        final preguntaBucket = tiemposPorPregunta.putIfAbsent(
          preguntaId,
          () => <String, dynamic>{
            'pregunta_id': preguntaId,
            'materia': nombreMateria,
            'intentos': 0,
            'suma': 0.0,
            'correctas': 0,
            'incorrectas': 0,
          },
        );
        preguntaBucket['intentos'] = _toInt(preguntaBucket['intentos']) + 1;
        preguntaBucket['suma'] =
            (_toDouble(preguntaBucket['suma']) ?? 0.0) + tiempo;
        if (esCorrecta) {
          preguntaBucket['correctas'] = _toInt(preguntaBucket['correctas']) + 1;
        } else {
          preguntaBucket['incorrectas'] =
              _toInt(preguntaBucket['incorrectas']) + 1;
        }
      }

      if (globalMuestraTiempo <= 0 || globalPeso <= 0) {
        return _cardFallback(
          id: 'coach_velocidad',
          titulo: 'Coach de Velocidad',
          prompt: 'analisis de velocidad',
          color: '#BBF7D0',
          icono: 'bolt',
          resumen: 'Aun no hay tiempos validos para evaluar tu velocidad.',
        );
      }

      final promedio = globalTiempoPonderado / globalPeso;
      final pctImpulsiva = (globalImpPeso * 100.0) / globalPeso;
      final pctOptima = (globalOptPeso * 100.0) / globalPeso;
      final pctLenta = (globalLenPeso * 100.0) / globalPeso;
      final clasificacion = promedio < 8
          ? 'Impulsivo'
          : (promedio <= 20 ? 'Optimo' : 'Lento');
      final confianzaGlobal = _etiquetaConfianzaMuestra(globalMuestraTiempo);

      final recomendacion = globalMuestraTiempo < _muestraMinimaVelocidad
          ? 'Aun hay poca muestra para decisiones finas. Continua practicando para mejorar precision del coach.'
          : (promedio < 8
                ? 'Baja un poco la velocidad y relee palabras clave (NO/EXCEPTO).'
                : (promedio <= 20
                      ? 'Tu ritmo es saludable. Mantiene precision con lectura activa.'
                      : 'Acelera descarte de opciones para ganar tiempo por pregunta.'));

      final tasaAciertoGlobal = globalValidasAcierto > 0
          ? (globalCorrectasAcierto * 100.0 / globalValidasAcierto)
          : 0.0;

      final rankingMaterias =
          statsPorMateria.entries
              .map((entry) {
                final stats = entry.value;
                final muestraTiempo = _toInt(stats['muestra_tiempo']);
                final respuestasValidas = _toInt(stats['respuestas_validas']);
                final correctasValidas = _toInt(stats['correctas_validas']);
                final pesoTotal = _toDouble(stats['peso_total']) ?? 0.0;
                final tiempoPonderado =
                    _toDouble(stats['tiempo_ponderado']) ?? 0.0;
                if (muestraTiempo <= 0 ||
                    pesoTotal <= 0 ||
                    respuestasValidas <= 0) {
                  return <String, dynamic>{};
                }

                final prom = tiempoPonderado / pesoTotal;
                final impPeso = _toDouble(stats['impulsiva_peso']) ?? 0.0;
                final optPeso = _toDouble(stats['optima_peso']) ?? 0.0;
                final lenPeso = _toDouble(stats['lenta_peso']) ?? 0.0;
                final pctImp = (impPeso * 100.0) / pesoTotal;
                final pctOpt = (optPeso * 100.0) / pesoTotal;
                final pctLen = (lenPeso * 100.0) / pesoTotal;
                final tasaAcierto =
                    (correctasValidas * 100.0) / respuestasValidas;

                final promAjustado =
                    ((prom * muestraTiempo) + (promedio * 20.0)) /
                    (muestraTiempo + 20.0);
                final confiabilidad = _factorConfiabilidadMuestra(
                  muestraTiempo,
                );
                final scoreRanking = promAjustado * confiabilidad;

                final clase = prom < 8
                    ? 'Impulsivo'
                    : (prom <= 20 ? 'Optimo' : 'Lento');

                return <String, dynamic>{
                  'materia': entry.key,
                  'promedio_segundos': prom,
                  'promedio_ajustado': promAjustado,
                  'score_ranking': scoreRanking,
                  'preguntas': muestraTiempo,
                  'muestra_valida': muestraTiempo,
                  'respuestas_validas': respuestasValidas,
                  'pct_impulsiva': pctImp,
                  'pct_optima': pctOpt,
                  'pct_lenta': pctLen,
                  'tasa_acierto': tasaAcierto,
                  'clasificacion': clase,
                  'confianza_muestra': _etiquetaConfianzaMuestra(muestraTiempo),
                };
              })
              .where((m) => m.isNotEmpty)
              .where(
                (m) => _toInt(m['muestra_valida']) >= _muestraMinimaVelocidad,
              )
              .toList()
            ..sort((a, b) {
              final scoreA = _toDouble(a['score_ranking']) ?? 0.0;
              final scoreB = _toDouble(b['score_ranking']) ?? 0.0;
              final byScore = scoreB.compareTo(scoreA);
              if (byScore != 0) return byScore;
              final muestraA = _toInt(a['muestra_valida']);
              final muestraB = _toInt(b['muestra_valida']);
              return muestraB.compareTo(muestraA);
            });

      final rankingPreguntas =
          tiemposPorPregunta.values
              .map((stats) {
                final intentos = _toInt(stats['intentos']);
                final totalSeg = _toDouble(stats['suma']) ?? 0.0;
                final promedioSeg = intentos > 0 ? totalSeg / intentos : 0.0;
                final correctas = _toInt(stats['correctas']);
                final incorrectas = _toInt(stats['incorrectas']);
                final tasaError = intentos > 0
                    ? (incorrectas * 100.0 / intentos)
                    : 0.0;
                final tasaAcierto = intentos > 0
                    ? (correctas * 100.0 / intentos)
                    : 0.0;
                return <String, dynamic>{
                  'pregunta_id': (stats['pregunta_id'] ?? '').toString(),
                  'materia': (stats['materia'] ?? '').toString(),
                  'intentos': intentos,
                  'total_segundos': totalSeg,
                  'promedio_segundos': promedioSeg,
                  'tasa_error': tasaError,
                  'tasa_acierto': tasaAcierto,
                };
              })
              .where((item) {
                final id = (item['pregunta_id'] ?? '').toString().trim();
                final intentos = _toInt(item['intentos']);
                final promedioPregunta =
                    _toDouble(item['promedio_segundos']) ?? 0.0;
                return id.isNotEmpty && intentos > 0 && promedioPregunta > 0;
              })
              .toList()
            ..sort((a, b) {
              final aProm = _toDouble(a['promedio_segundos']) ?? 0.0;
              final bProm = _toDouble(b['promedio_segundos']) ?? 0.0;
              final byProm = bProm.compareTo(aProm);
              if (byProm != 0) return byProm;
              final aIntentos = _toInt(a['intentos']);
              final bIntentos = _toInt(b['intentos']);
              final byIntentos = bIntentos.compareTo(aIntentos);
              if (byIntentos != 0) return byIntentos;
              final aTotal = _toDouble(a['total_segundos']) ?? 0.0;
              final bTotal = _toDouble(b['total_segundos']) ?? 0.0;
              return bTotal.compareTo(aTotal);
            });

      final topPreguntasBase = rankingPreguntas.take(10).toList();
      final topPreguntaIds = topPreguntasBase
          .map((item) => (item['pregunta_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toList();

      final Map<String, Map<String, dynamic>> detallePreguntaPorId = {};
      if (topPreguntaIds.isNotEmpty) {
        try {
          final List<dynamic> detalleRaw = await _supabase
              .from('pregunta')
              .select(
                'id, numero_oficial, codigo_pregunta, enunciado, '
                'materia:materia_id(nombre)',
              )
              .inFilter('id', topPreguntaIds);
          for (final item in detalleRaw) {
            if (item is! Map) continue;
            final row = Map<String, dynamic>.from(item);
            final id = (row['id'] ?? '').toString().trim();
            if (id.isEmpty) continue;
            detallePreguntaPorId[id] = row;
          }
        } catch (e) {
          debugPrint('TutorIA: no pude cargar detalle de preguntas lentas: $e');
        }
      }

      final topPreguntas = topPreguntasBase.map((item) {
        final preguntaId = (item['pregunta_id'] ?? '').toString().trim();
        final detalle = detallePreguntaPorId[preguntaId];
        final materiaDetalle = _asMap(detalle?['materia']);
        final materiaNombre =
            (item['materia'] ?? materiaDetalle['nombre'] ?? '')
                .toString()
                .trim();
        final numero = _toInt(detalle?['numero_oficial']);
        final codigo = (detalle?['codigo_pregunta'] ?? '').toString().trim();
        final enunciado = (detalle?['enunciado'] ?? '').toString().trim();
        final texto = enunciado.isNotEmpty
            ? _resumirTextoError(enunciado, max: 130)
            : (codigo.isNotEmpty ? codigo : 'Pregunta');

        return <String, dynamic>{
          'pregunta_id': preguntaId,
          'numero': numero,
          'codigo_pregunta': codigo,
          'texto': texto,
          'materia': materiaNombre,
          'intentos': _toInt(item['intentos']),
          'promedio_segundos': _toDouble(item['promedio_segundos']) ?? 0.0,
          'total_segundos': _toDouble(item['total_segundos']) ?? 0.0,
          'tasa_error': _toDouble(item['tasa_error']) ?? 0.0,
          'tasa_acierto': _toDouble(item['tasa_acierto']) ?? 0.0,
        };
      }).toList();

      final metricas = {
        'promedio_segundos': promedio,
        'clasificacion': clasificacion,
        'total_respuestas': globalMuestraTiempo,
        'respuestas_validas_acierto': globalValidasAcierto,
        'tasa_acierto_global': tasaAciertoGlobal,
        'impulsivas': ((pctImpulsiva * globalMuestraTiempo) / 100).round(),
        'optimas': ((pctOptima * globalMuestraTiempo) / 100).round(),
        'lentas': ((pctLenta * globalMuestraTiempo) / 100).round(),
        'pct_impulsiva': pctImpulsiva,
        'pct_optima': pctOptima,
        'pct_lenta': pctLenta,
        'rango_optimo_min': 8,
        'rango_optimo_max': 20,
        'recomendacion': recomendacion,
        'confianza_muestra': confianzaGlobal,
        'muestra_minima_recomendada': _muestraMinimaVelocidad,
        'ventana_respuestas': _ventanaRespuestasVelocidad,
      };

      return _construirCardCoachVelocidadDashboard(
        promedio: promedio,
        clasificacion: clasificacion,
        confianzaGlobal: confianzaGlobal,
        tasaAciertoGlobal: tasaAciertoGlobal,
        recomendacion: recomendacion,
        materias: rankingMaterias,
        preguntas: topPreguntas,
        metricas: metricas,
      );
    } catch (_) {
      return _cardFallback(
        id: 'coach_velocidad',
        titulo: 'Coach de Velocidad',
        prompt: 'analisis de velocidad',
        color: '#BBF7D0',
        icono: 'bolt',
        resumen: 'No pude calcular el coach de velocidad ahora.',
      );
    }
  }

  Future<Map<String, dynamic>?> _obtenerAnalisisVelocidadDesdeRpc({
    required String userId,
  }) async {
    try {
      final dynamic raw = await _supabase.rpc(
        _rpcCoachVelocidadDashboard,
        params: {
          'p_usuario_id': userId,
          'p_ventana': _ventanaRespuestasVelocidad,
          'p_muestra_minima': _muestraMinimaVelocidad,
          'p_half_life_dias': _halfLifeRecenciaDias,
        },
      );

      Map<String, dynamic>? payload;
      if (raw is Map) {
        payload = Map<String, dynamic>.from(raw);
      } else if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          payload = Map<String, dynamic>.from(decoded);
        }
      }
      if (payload == null || payload.isEmpty) return null;

      final metricasRaw = payload['metricas_velocidad'];
      final metricas = metricasRaw is Map
          ? Map<String, dynamic>.from(metricasRaw)
          : <String, dynamic>{};
      if (metricas.isEmpty) return null;

      final materiasRaw = payload['materias_tiempo'];
      final materias = materiasRaw is List
          ? materiasRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      final preguntasRaw = payload['preguntas_lentas'];
      final preguntas = preguntasRaw is List
          ? preguntasRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      final promedio = _toDouble(metricas['promedio_segundos']) ?? 0.0;
      final clasificacion = (metricas['clasificacion'] ?? 'Sin datos')
          .toString()
          .trim();
      final recomendacion = (metricas['recomendacion'] ?? '').toString().trim();
      final confianzaGlobal = (metricas['confianza_muestra'] ?? 'Sin datos')
          .toString()
          .trim();
      final tasaAciertoGlobal = _toDouble(metricas['tasa_acierto_global']) ?? 0;

      return _construirCardCoachVelocidadDashboard(
        promedio: promedio,
        clasificacion: clasificacion,
        confianzaGlobal: confianzaGlobal,
        tasaAciertoGlobal: tasaAciertoGlobal,
        recomendacion: recomendacion,
        materias: materias,
        preguntas: preguntas,
        metricas: metricas,
        preguntasIdsFallback: _toStringList(payload['preguntas_lentas_ids']),
        fuenteDatos: 'rpc',
      );
    } catch (e) {
      debugPrint(
        'TutorIA: RPC coach velocidad no disponible, fallback app: $e',
      );
      return null;
    }
  }

  Future<Map<String, dynamic>> obtenerCoachMemoriaEstructurado({
    required String userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return _cardFallback(
        id: 'coach_memoria',
        titulo: 'Coach de Memoria',
        prompt: 'coach de memoria',
        color: '#FECACA',
        icono: 'memory',
        resumen: 'Inicia sesion para activar tu coach de memoria.',
      );
    }

    final data = await obtenerCoachMemoriaDetalle(userId: userId);
    final estado = (data['estado'] ?? '').toString().trim().toLowerCase();
    if (estado == 'error') {
      return _cardFallback(
        id: 'coach_memoria',
        titulo: 'Coach de Memoria',
        prompt: 'coach de memoria',
        color: '#FECACA',
        icono: 'memory',
        resumen:
            (data['resumen'] ?? 'No pude calcular tu coach de memoria ahora.')
                .toString()
                .trim(),
      );
    }

    return _construirCardCoachMemoriaDesdeDetalle(data);
  }

  Future<Map<String, dynamic>> obtenerCoachMemoriaDetalle({
    required String userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return {
        'estado': 'sin_sesion',
        'resumen':
            'Inicia sesion para calcular tu coach de memoria con datos reales.',
        'indice_memoria': 0.0,
        'interpretacion_indice': 'Necesita repaso',
        'plan_diario': {'nuevas': 0, 'fallidas': 0, 'repaso': 0},
        'pregunta_ids_prioritarias': <String>[],
        'preguntas_criticas': <Map<String, dynamic>>[],
        'preguntas_dificiles': <Map<String, dynamic>>[],
        'riesgos': <Map<String, dynamic>>[],
      };
    }

    List<List<String>> trocearIds(List<String> ids, int tamano) {
      final salida = <List<String>>[];
      for (var i = 0; i < ids.length; i += tamano) {
        final fin = (i + tamano) > ids.length ? ids.length : (i + tamano);
        salida.add(ids.sublist(i, fin));
      }
      return salida;
    }

    try {
      final List<dynamic> raw = await _supabase
          .from('respuesta_usuario')
          .select(
            'pregunta_id, es_correcta, fue_omitida, tiempo_total_respuesta, respondida_at',
          )
          .eq('usuario_id', userId)
          .order('respondida_at', ascending: true)
          .limit(_ventanaRespuestasCoachMemoria);

      final eventos = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((row) {
            final omitida = row['fue_omitida'] == true;
            final esCorrecta = row['es_correcta'];
            final preguntaId = (row['pregunta_id'] ?? '').toString().trim();
            return !omitida && esCorrecta is bool && preguntaId.isNotEmpty;
          })
          .toList();

      if (eventos.isEmpty) {
        return {
          'estado': 'sin_datos',
          'resumen':
              'Aun no hay historial suficiente para activar el coach de memoria.',
          'indice_memoria': 0.0,
          'interpretacion_indice': 'Necesita repaso',
          'plan_diario': {'nuevas': 20, 'fallidas': 10, 'repaso': 10},
          'pregunta_ids_prioritarias': <String>[],
          'preguntas_criticas': <Map<String, dynamic>>[],
          'preguntas_dificiles': <Map<String, dynamic>>[],
          'riesgos': <Map<String, dynamic>>[],
        };
      }

      final preguntaIdsUnicos = eventos
          .map((e) => (e['pregunta_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final preguntaMetaPorId = <String, Map<String, dynamic>>{};
      final materiaIdPorPregunta = <String, String>{};
      for (final chunk in trocearIds(preguntaIdsUnicos, 150)) {
        final List<dynamic> preguntasRaw = await _supabase
            .from('pregunta')
            .select('id, numero_oficial, codigo_pregunta, materia_id')
            .inFilter('id', chunk);
        for (final item in preguntasRaw.whereType<Map>()) {
          final row = Map<String, dynamic>.from(item);
          final id = (row['id'] ?? '').toString().trim();
          if (id.isEmpty) continue;
          final materiaId = (row['materia_id'] ?? '').toString().trim();
          preguntaMetaPorId[id] = row;
          if (materiaId.isNotEmpty) {
            materiaIdPorPregunta[id] = materiaId;
          }
        }
      }

      final materiaIds = materiaIdPorPregunta.values.toSet().toList();
      final materiaNombrePorId = <String, String>{};
      for (final chunk in trocearIds(materiaIds, 150)) {
        final List<dynamic> materiasRaw = await _supabase
            .from('materia')
            .select('id, nombre')
            .inFilter('id', chunk);
        for (final item in materiasRaw.whereType<Map>()) {
          final row = Map<String, dynamic>.from(item);
          final id = (row['id'] ?? '').toString().trim();
          final nombre = (row['nombre'] ?? 'Materia').toString().trim();
          if (id.isNotEmpty) {
            materiaNombrePorId[id] = nombre.isEmpty ? 'Materia' : nombre;
          }
        }
      }

      final now = DateTime.now();
      final porPregunta = <String, Map<String, dynamic>>{};
      var totalCorrectas = 0;
      var totalFallos = 0;
      var reiniciosSpaced = 0;

      for (var index = 0; index < eventos.length; index++) {
        final row = eventos[index];
        final preguntaId = (row['pregunta_id'] ?? '').toString().trim();
        if (preguntaId.isEmpty) continue;
        final esCorrecta = row['es_correcta'] == true;
        final respondidaAt =
            _parseFechaFlexible(row['respondida_at']) ??
            now.subtract(Duration(seconds: eventos.length - index));
        final tiempo = _toDouble(row['tiempo_total_respuesta']) ?? 0.0;
        final meta = _asMap(preguntaMetaPorId[preguntaId]);
        final materiaId = (meta['materia_id'] ?? '').toString().trim();
        final materiaNombre =
            materiaNombrePorId[materiaId] ??
            (meta['materia_nombre'] ?? 'Materia').toString().trim();

        final item = porPregunta.putIfAbsent(
          preguntaId,
          () => <String, dynamic>{
            'pregunta_id': preguntaId,
            'numero_oficial': _toInt(meta['numero_oficial']),
            'codigo_pregunta': (meta['codigo_pregunta'] ?? '')
                .toString()
                .trim(),
            'materia': materiaNombre.isEmpty ? 'Materia' : materiaNombre,
            'intentos': 0,
            'correctas': 0,
            'fallos': 0,
            'tiempo_suma': 0.0,
            'primera_vez': respondidaAt,
            'ultima_vez': respondidaAt,
            'ultima_correcta': false,
            'alguna_correcta': false,
            'eventos_olvido': 0,
            'racha_correctas': 0,
            'racha_fallos': 0,
            'srs_nivel': 0,
            'srs_ciclo_dias': _ciclosRepasoMemoriaDias.first,
            'proxima_revision': respondidaAt.add(
              Duration(days: _ciclosRepasoMemoriaDias.first),
            ),
            'repeticion_intervalo': 0,
            'fallo_index': -1,
          },
        );

        final algunaCorrectaAntes = item['alguna_correcta'] == true;
        item['intentos'] = _toInt(item['intentos']) + 1;
        item['ultima_vez'] = respondidaAt;
        item['tiempo_suma'] = (_toDouble(item['tiempo_suma']) ?? 0.0) + tiempo;

        if (esCorrecta) {
          totalCorrectas++;
          item['correctas'] = _toInt(item['correctas']) + 1;
          item['alguna_correcta'] = true;
          item['ultima_correcta'] = true;
          item['racha_correctas'] = _toInt(item['racha_correctas']) + 1;
          item['racha_fallos'] = 0;
          final racha = _toInt(item['racha_correctas']);
          final nivel = (racha - 1).clamp(
            0,
            _ciclosRepasoMemoriaDias.length - 1,
          );
          final ciclo = _ciclosRepasoMemoriaDias[nivel];
          item['srs_nivel'] = nivel;
          item['srs_ciclo_dias'] = ciclo;
          item['proxima_revision'] = respondidaAt.add(Duration(days: ciclo));
        } else {
          totalFallos++;
          item['fallos'] = _toInt(item['fallos']) + 1;
          if (algunaCorrectaAntes) {
            item['eventos_olvido'] = _toInt(item['eventos_olvido']) + 1;
          }
          if (_toInt(item['srs_nivel']) > 0 || algunaCorrectaAntes) {
            reiniciosSpaced++;
          }
          item['ultima_correcta'] = false;
          item['racha_correctas'] = 0;
          item['racha_fallos'] = _toInt(item['racha_fallos']) + 1;
          item['srs_nivel'] = 0;
          item['srs_ciclo_dias'] = _ciclosRepasoMemoriaDias.first;
          item['proxima_revision'] = respondidaAt.add(
            Duration(days: _ciclosRepasoMemoriaDias.first),
          );
          final intervalo = _intervaloRepeticionInmediata(preguntaId);
          item['repeticion_intervalo'] = intervalo;
          item['fallo_index'] = index;
        }
      }

      if (porPregunta.isEmpty) {
        return {
          'estado': 'sin_datos',
          'resumen':
              'Aun no hay historial suficiente para activar el coach de memoria.',
          'indice_memoria': 0.0,
          'interpretacion_indice': 'Necesita repaso',
          'plan_diario': {'nuevas': 20, 'fallidas': 10, 'repaso': 10},
          'pregunta_ids_prioritarias': <String>[],
          'preguntas_criticas': <Map<String, dynamic>>[],
          'preguntas_dificiles': <Map<String, dynamic>>[],
          'riesgos': <Map<String, dynamic>>[],
        };
      }

      String etiquetaPregunta(Map<String, dynamic> q) {
        final numero = _toInt(q['numero_oficial']);
        if (numero > 0) return numero.toString();
        final codigo = (q['codigo_pregunta'] ?? '').toString().trim();
        if (codigo.isNotEmpty) return codigo;
        final id = (q['pregunta_id'] ?? '').toString().trim();
        return id.length <= 8 ? id : id.substring(0, 8);
      }

      final topPrioridad = <Map<String, dynamic>>[];
      final preguntasCriticas = <Map<String, dynamic>>[];
      final preguntasDificiles = <Map<String, dynamic>>[];
      final preguntasOlvido = <Map<String, dynamic>>[];
      final preguntasRepasoVencido = <Map<String, dynamic>>[];
      final preguntasSinRepaso = <Map<String, dynamic>>[];
      final preguntasRepeticionInmediata = <Map<String, dynamic>>[];
      final porMateria = <String, Map<String, dynamic>>{};

      for (final rawItem in porPregunta.values) {
        final item = Map<String, dynamic>.from(rawItem);
        final intentos = _toInt(item['intentos']);
        if (intentos <= 0) continue;

        final correctas = _toInt(item['correctas']);
        final fallos = _toInt(item['fallos']);
        final tasaAcierto = intentos > 0 ? (correctas * 100.0) / intentos : 0.0;
        final ultimaVez = _parseFechaFlexible(item['ultima_vez']);
        final proximaRevision = _parseFechaFlexible(item['proxima_revision']);
        final diasSinRepaso = ultimaVez == null
            ? _diasAlertaSinRepaso
            : now.difference(ultimaVez).inDays;
        final repasoVencido =
            proximaRevision != null && !proximaRevision.isAfter(now);
        final eventosOlvido = _toInt(item['eventos_olvido']);
        final riesgoOlvido =
            eventosOlvido > 0 ||
            (_toInt(item['correctas']) > 0 && item['ultima_correcta'] != true);
        final rachaFallos = _toInt(item['racha_fallos']);
        final critica =
            intentos >= 3 &&
            (tasaAcierto <= 45 ||
                rachaFallos >= 2 ||
                (fallos >= 3 && correctas <= 1));
        final dificil = intentos >= 3 && tasaAcierto < 60;
        final intervalo = _toInt(item['repeticion_intervalo']);
        final falloIndex = _toInt(item['fallo_index']);
        final distanciaDesdeFallo = falloIndex >= 0
            ? (eventos.length - 1 - falloIndex)
            : 9999;
        final faltanParaReaparecer = (intervalo - distanciaDesdeFallo).clamp(
          0,
          999,
        );
        final repeticionInmediataPendiente =
            falloIndex >= 0 &&
            item['ultima_correcta'] != true &&
            intervalo >= 10 &&
            distanciaDesdeFallo < intervalo;

        final avgTiempo = (_toDouble(item['tiempo_suma']) ?? 0.0) / intentos;
        var prioridad = (100 - tasaAcierto) * 1.2;
        prioridad += critica ? 35 : 0;
        prioridad += riesgoOlvido ? 24 : 0;
        prioridad += repasoVencido ? 20 : 0;
        prioridad += repeticionInmediataPendiente ? 22 : 0;
        prioridad += math.min(diasSinRepaso.toDouble(), 20);
        prioridad += math.min(fallos.toDouble(), 8) * 1.8;

        final resumenPregunta = <String, dynamic>{
          'pregunta_id': (item['pregunta_id'] ?? '').toString().trim(),
          'numero_oficial': _toInt(item['numero_oficial']),
          'codigo_pregunta': (item['codigo_pregunta'] ?? '').toString().trim(),
          'etiqueta': etiquetaPregunta(item),
          'materia': (item['materia'] ?? 'Materia').toString().trim(),
          'intentos': intentos,
          'correctas': correctas,
          'fallos': fallos,
          'tasa_acierto': tasaAcierto,
          'tiempo_promedio_segundos': avgTiempo,
          'dias_sin_repaso': diasSinRepaso < 0 ? 0 : diasSinRepaso,
          'en_riesgo_olvido': riesgoOlvido,
          'eventos_olvido': eventosOlvido,
          'es_critica': critica,
          'es_dificil': dificil,
          'repaso_vencido': repasoVencido,
          'repeticion_inmediata_pendiente': repeticionInmediataPendiente,
          'faltan_para_reaparicion': faltanParaReaparecer,
          'srs_nivel': _toInt(item['srs_nivel']),
          'srs_ciclo_dias': _toInt(item['srs_ciclo_dias']),
          'proxima_revision': proximaRevision?.toIso8601String() ?? '',
          'proxima_revision_legible': proximaRevision == null
              ? ''
              : _formatearFecha(proximaRevision),
          'prioridad_score': prioridad,
        };

        topPrioridad.add(resumenPregunta);
        if (critica) preguntasCriticas.add(resumenPregunta);
        if (dificil) preguntasDificiles.add(resumenPregunta);
        if (riesgoOlvido) preguntasOlvido.add(resumenPregunta);
        if (repasoVencido) preguntasRepasoVencido.add(resumenPregunta);
        if (diasSinRepaso >= _diasAlertaSinRepaso) {
          preguntasSinRepaso.add(resumenPregunta);
        }
        if (repeticionInmediataPendiente) {
          preguntasRepeticionInmediata.add(resumenPregunta);
        }

        final materia = (resumenPregunta['materia'] ?? 'Materia')
            .toString()
            .trim();
        final acc = porMateria.putIfAbsent(
          materia.isEmpty ? 'Materia' : materia,
          () => <String, dynamic>{
            'materia': materia.isEmpty ? 'Materia' : materia,
            'intentos': 0,
            'correctas': 0,
            'criticas': 0,
            'olvido': 0,
          },
        );
        acc['intentos'] = _toInt(acc['intentos']) + intentos;
        acc['correctas'] = _toInt(acc['correctas']) + correctas;
        if (critica) acc['criticas'] = _toInt(acc['criticas']) + 1;
        if (riesgoOlvido) acc['olvido'] = _toInt(acc['olvido']) + 1;
      }

      topPrioridad.sort((a, b) {
        final scoreA = _toDouble(a['prioridad_score']) ?? 0.0;
        final scoreB = _toDouble(b['prioridad_score']) ?? 0.0;
        final byScore = scoreB.compareTo(scoreA);
        if (byScore != 0) return byScore;
        return _toInt(b['fallos']).compareTo(_toInt(a['fallos']));
      });

      preguntasCriticas.sort((a, b) {
        final tasaA = _toDouble(a['tasa_acierto']) ?? 0.0;
        final tasaB = _toDouble(b['tasa_acierto']) ?? 0.0;
        final byTasa = tasaA.compareTo(tasaB);
        if (byTasa != 0) return byTasa;
        return _toInt(b['fallos']).compareTo(_toInt(a['fallos']));
      });

      preguntasDificiles.sort((a, b) {
        final tasaA = _toDouble(a['tasa_acierto']) ?? 0.0;
        final tasaB = _toDouble(b['tasa_acierto']) ?? 0.0;
        final byTasa = tasaA.compareTo(tasaB);
        if (byTasa != 0) return byTasa;
        return _toInt(b['intentos']).compareTo(_toInt(a['intentos']));
      });

      preguntasSinRepaso.sort(
        (a, b) => _toInt(
          b['dias_sin_repaso'],
        ).compareTo(_toInt(a['dias_sin_repaso'])),
      );
      preguntasRepasoVencido.sort((a, b) {
        final scoreA = _toDouble(a['prioridad_score']) ?? 0.0;
        final scoreB = _toDouble(b['prioridad_score']) ?? 0.0;
        return scoreB.compareTo(scoreA);
      });

      final riesgos =
          porMateria.values.map((raw) {
            final item = Map<String, dynamic>.from(raw);
            final intentos = _toInt(item['intentos']);
            final correctas = _toInt(item['correctas']);
            final tasa = intentos > 0 ? (correctas * 100.0) / intentos : 0.0;
            final criticas = _toInt(item['criticas']);
            final olvido = _toInt(item['olvido']);
            final tendencia = (olvido > 0 || criticas > 0)
                ? 'empeorando'
                : (tasa >= 75 ? 'mejorando' : 'estable');
            final scoreRiesgo = (100 - tasa) + (criticas * 8) + (olvido * 5);
            return <String, dynamic>{
              'materia': item['materia'],
              'tasa': tasa,
              'tendencia': tendencia,
              'semaforo': _semaforoPorTasa(tasa),
              'score_riesgo': scoreRiesgo,
            };
          }).toList()..sort((a, b) {
            final scoreA = _toDouble(a['score_riesgo']) ?? 0.0;
            final scoreB = _toDouble(b['score_riesgo']) ?? 0.0;
            return scoreB.compareTo(scoreA);
          });

      final preguntasVistas = porPregunta.length;
      final totalIntentos = totalCorrectas + totalFallos;
      final tasaGlobal = totalIntentos > 0
          ? (totalCorrectas * 100.0) / totalIntentos
          : 0.0;
      final olvidoPorcentaje = preguntasVistas > 0
          ? (preguntasOlvido.length * 100.0) / preguntasVistas
          : 0.0;
      final repasoAlDia = preguntasVistas > 0
          ? (100.0 -
                    ((preguntasRepasoVencido.length * 100.0) / preguntasVistas))
                .clamp(0.0, 100.0)
          : 0.0;

      final indiceBase =
          (tasaGlobal * 0.55) +
          ((100.0 - olvidoPorcentaje) * 0.25) +
          (repasoAlDia * 0.20);
      final penalizacionCriticas = math
          .min(preguntasCriticas.length * 1.5, 18)
          .toDouble();
      final penalizacionSinRepaso = math
          .min(preguntasSinRepaso.length * 0.25, 12)
          .toDouble();
      final indiceMemoria =
          (indiceBase - penalizacionCriticas - penalizacionSinRepaso).clamp(
            0.0,
            100.0,
          );

      final interpretacionIndice = indiceMemoria >= 90
          ? 'Excelente'
          : (indiceMemoria >= 70 ? 'Bueno' : 'Necesita repaso');

      final perfil = await _obtenerPerfilUsuarioBasico(userId);
      final categoriaUsuario = (perfil['categoria'] ?? '').toString().trim();
      final totalObjetivo = await _contarTotalPreguntasObjetivoReal(
        categoriaUsuario: categoriaUsuario,
      );
      final totalBanco = (totalObjetivo != null && totalObjetivo > 0)
          ? totalObjetivo
          : 3000;
      final pendientesNuevas = math.max(totalBanco - preguntasVistas, 0);

      var nuevas = indiceMemoria >= 90 ? 35 : (indiceMemoria >= 70 ? 30 : 20);
      if (pendientesNuevas < nuevas) nuevas = pendientesNuevas;

      var fallidas =
          (preguntasRepeticionInmediata.length + preguntasCriticas.length)
              .clamp(10, 25);
      if (preguntasCriticas.length >= 8 && fallidas < 20) {
        fallidas = 20;
      }

      var repaso = preguntasRepasoVencido.length.clamp(10, 25);
      if (preguntasSinRepaso.length > repaso) {
        repaso = preguntasSinRepaso.length.clamp(10, 25);
      }

      final idsFallidas = topPrioridad
          .where(
            (q) =>
                q['es_critica'] == true ||
                q['es_dificil'] == true ||
                q['repeticion_inmediata_pendiente'] == true,
          )
          .map((q) => (q['pregunta_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toList();

      final idsRepaso = topPrioridad
          .where(
            (q) =>
                q['repaso_vencido'] == true ||
                q['en_riesgo_olvido'] == true ||
                _toInt(q['dias_sin_repaso']) >= _diasAlertaSinRepaso,
          )
          .map((q) => (q['pregunta_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toList();

      final idsPrioritarias = <String>[];
      final vistos = <String>{};
      for (final id in [...idsFallidas, ...idsRepaso]) {
        if (id.isEmpty) continue;
        if (vistos.add(id)) idsPrioritarias.add(id);
      }

      final idsCriticas = preguntasCriticas
          .map((q) => (q['pregunta_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .take(25)
          .toList();

      final maxDiasSinRepaso = preguntasSinRepaso.isEmpty
          ? 0
          : preguntasSinRepaso
                .map((q) => _toInt(q['dias_sin_repaso']))
                .reduce((a, b) => a > b ? a : b);

      final recordatorioRepaso = preguntasSinRepaso.isEmpty
          ? 'No tienes preguntas atrasadas por mas de $_diasAlertaSinRepaso dias.'
          : 'Tienes ${preguntasSinRepaso.length} preguntas que no repasas hace $maxDiasSinRepaso dias.';

      final resumen =
          'Indice de memoria ${indiceMemoria.toStringAsFixed(1)}% ($interpretacionIndice). '
          'Plan de hoy: $nuevas nuevas, $fallidas fallidas y $repaso de repaso. '
          'Criticas: ${preguntasCriticas.length}. Riesgo de olvido: ${preguntasOlvido.length}.';

      return {
        'estado': 'ok',
        'resumen': resumen,
        'indice_memoria': indiceMemoria,
        'interpretacion_indice': interpretacionIndice,
        'plan_diario': {
          'nuevas': nuevas,
          'fallidas': fallidas,
          'repaso': repaso,
        },
        'repeticion_fallidas': {
          'intervalo_min': 10,
          'intervalo_max': 20,
          'pendientes': preguntasRepeticionInmediata.take(30).toList(),
          'total_pendientes': preguntasRepeticionInmediata.length,
        },
        'repeticion_espaciada': {
          'ciclos_dias': _ciclosRepasoMemoriaDias,
          'total_vencidas': preguntasRepasoVencido.length,
          'reinicios_por_fallo': reiniciosSpaced,
        },
        'detector_olvido': {
          'total_en_riesgo': preguntasOlvido.length,
          'preguntas': preguntasOlvido.take(50).toList(),
        },
        'preguntas_dificiles': preguntasDificiles.take(50).toList(),
        'preguntas_criticas': preguntasCriticas.take(50).toList(),
        'preguntas_criticas_ids': idsCriticas,
        'recordatorio_repaso': recordatorioRepaso,
        'total_sin_repaso': preguntasSinRepaso.length,
        'total_criticas': preguntasCriticas.length,
        'total_repaso_vencidas': preguntasRepasoVencido.length,
        'total_preguntas_vistas': preguntasVistas,
        'total_objetivo': totalBanco,
        'total_pendientes_nuevas': pendientesNuevas,
        'riesgos': riesgos.take(6).toList(),
        'top_prioridad': topPrioridad.take(80).toList(),
        'pregunta_ids_prioritarias': idsPrioritarias.take(80).toList(),
        'pregunta_ids_fallidas': idsFallidas.take(80).toList(),
        'pregunta_ids_repaso': idsRepaso.take(80).toList(),
        'datos_base_guardados': const [
          'id_pregunta',
          'acierto_error',
          'numero_intentos',
          'ultima_vez_respondida',
          'tiempo_respuesta_segundos',
        ],
        'metricas_generales': {
          'total_intentos': totalIntentos,
          'total_correctas': totalCorrectas,
          'total_fallos': totalFallos,
          'tasa_acierto_global': tasaGlobal,
          'olvido_porcentaje': olvidoPorcentaje,
          'repaso_al_dia': repasoAlDia,
        },
      };
    } catch (e) {
      debugPrint('obtenerCoachMemoriaDetalle error: $e');
      return {
        'estado': 'error',
        'resumen': 'No se pudo calcular el coach de memoria en este momento.',
        'indice_memoria': 0.0,
        'interpretacion_indice': 'Necesita repaso',
        'plan_diario': {'nuevas': 20, 'fallidas': 10, 'repaso': 10},
        'pregunta_ids_prioritarias': <String>[],
        'preguntas_criticas': <Map<String, dynamic>>[],
        'preguntas_dificiles': <Map<String, dynamic>>[],
        'riesgos': <Map<String, dynamic>>[],
      };
    }
  }

  Future<Map<String, dynamic>> obtenerPrediccionOlvidoEstructurado({
    required String userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return _cardFallback(
        id: 'prediccion_olvido',
        titulo: 'Prediccion de Olvido',
        prompt: 'prediccion de olvido',
        color: '#DDD6FE',
        icono: 'history',
        resumen:
            'Aun no hay datos suficientes para tu prediccion de olvido. Completa una practica para activarla.',
      );
    }

    try {
      final List<dynamic> raw = await _supabase
          .from('prediccion_olvido')
          .select(
            'probabilidad_olvido, urgencia_revision, requiere_revision_inmediata',
          )
          .eq('usuario_id', userId)
          .gte('probabilidad_olvido', 70)
          .order('probabilidad_olvido', ascending: false)
          .limit(30);

      final rows = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (rows.isEmpty) {
        return {
          'id': 'prediccion_olvido',
          'titulo': 'Prediccion de Olvido',
          'resumen': 'No hay alertas de olvido alto (>70%) por ahora.',
          'detalle': 'Tu cola de repaso urgente esta bajo control.',
          'prompt': 'prediccion de olvido',
          'cta': 'Ver plan de repaso',
          'color': '#DDD6FE',
          'icono': 'history',
          'expandable': true,
        };
      }

      final urgentes = rows.where((r) {
        final urg = _normalizarTexto((r['urgencia_revision'] ?? '').toString());
        return r['requiere_revision_inmediata'] == true ||
            urg.contains('alta') ||
            urg.contains('critica');
      }).length;
      final topProb = _toDouble(rows.first['probabilidad_olvido']) ?? 0;

      return {
        'id': 'prediccion_olvido',
        'titulo': 'Prediccion de Olvido',
        'resumen':
            'Tienes ${rows.length} preguntas con olvido alto. Urgentes: $urgentes.',
        'detalle':
            'Mayor probabilidad detectada: ${topProb.toStringAsFixed(1)}%. Conviene repaso en el siguiente bloque.',
        'prompt': 'prediccion de olvido',
        'cta': 'Ver plan de repaso',
        'color': '#DDD6FE',
        'icono': 'history',
        'expandable': true,
      };
    } catch (_) {
      return _cardFallback(
        id: 'prediccion_olvido',
        titulo: 'Prediccion de Olvido',
        prompt: 'prediccion de olvido',
        color: '#DDD6FE',
        icono: 'history',
        resumen:
            'Aun no hay datos suficientes para tu prediccion de olvido. Completa una practica para activarla.',
      );
    }
  }

  Future<Map<String, dynamic>> obtenerPrediccionOlvidoDetalle({
    required String userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return {
        'estado': 'sin_sesion',
        'resumen':
            'Inicia sesion para ver el listado de materias con riesgo de olvido.',
        'materias': <Map<String, dynamic>>[],
        'total_preguntas': 0,
        'total_urgentes': 0,
      };
    }

    Map<String, dynamic> construirResultado({
      required List<Map<String, dynamic>> rows,
      required Map<String, String> materiaNombrePorPregunta,
    }) {
      if (rows.isEmpty) {
        return {
          'estado': 'sin_datos',
          'resumen': 'No hay materias con riesgo de olvido alto por ahora.',
          'materias': <Map<String, dynamic>>[],
          'total_preguntas': 0,
          'total_urgentes': 0,
        };
      }

      final agrupado = <String, Map<String, dynamic>>{};
      var totalUrgentes = 0;

      for (final row in rows) {
        final prob = _toDouble(row['probabilidad_olvido']) ?? 0;
        final urg = _normalizarTexto(
          (row['urgencia_revision'] ?? '').toString(),
        );
        final urgente =
            row['requiere_revision_inmediata'] == true ||
            urg.contains('alta') ||
            urg.contains('critica');
        if (urgente) totalUrgentes++;

        final preguntaId = (row['pregunta_id'] ?? '').toString().trim();
        final key =
            (materiaNombrePorPregunta[preguntaId] ?? 'Materia sin nombre')
                .trim();
        final materiaNombre = key.isEmpty ? 'Materia sin nombre' : key;

        final actual = agrupado.putIfAbsent(
          materiaNombre,
          () => {
            'materia': materiaNombre,
            'total': 0,
            'urgentes': 0,
            'suma_prob': 0.0,
            'max_prob': 0.0,
            'proxima_revision': null,
            'pregunta_ids': <String>[],
          },
        );

        actual['total'] = (actual['total'] as int) + 1;
        actual['suma_prob'] = (actual['suma_prob'] as double) + prob;
        if (prob > (actual['max_prob'] as double)) {
          actual['max_prob'] = prob;
        }
        if (urgente) {
          actual['urgentes'] = (actual['urgentes'] as int) + 1;
        }
        if (preguntaId.isNotEmpty) {
          (actual['pregunta_ids'] as List<String>).add(preguntaId);
        }

        final fecha = _parseFechaFlexible(row['fecha_revision_optima']);
        final fechaActual = actual['proxima_revision'] as DateTime?;
        if (fecha != null &&
            (fechaActual == null || fecha.isBefore(fechaActual))) {
          actual['proxima_revision'] = fecha;
        }
      }

      final materias = agrupado.values.map((m) {
        final total = m['total'] as int;
        final sumaProb = m['suma_prob'] as double;
        final proxima = m['proxima_revision'] as DateTime?;
        final ids = (m['pregunta_ids'] as List<String>).toSet().toList();
        return <String, dynamic>{
          'materia': m['materia'],
          'total': total,
          'urgentes': m['urgentes'],
          'probabilidad_promedio': total > 0 ? (sumaProb / total) : 0.0,
          'probabilidad_maxima': m['max_prob'],
          'proxima_revision': proxima == null ? '' : _formatearFecha(proxima),
          'pregunta_ids': ids,
        };
      }).toList();

      materias.sort((a, b) {
        final urgA = _toInt(a['urgentes']);
        final urgB = _toInt(b['urgentes']);
        final byUrg = urgB.compareTo(urgA);
        if (byUrg != 0) return byUrg;
        final maxA = _toDouble(a['probabilidad_maxima']) ?? 0;
        final maxB = _toDouble(b['probabilidad_maxima']) ?? 0;
        final byMax = maxB.compareTo(maxA);
        if (byMax != 0) return byMax;
        return _toInt(b['total']).compareTo(_toInt(a['total']));
      });

      final top = materias.first;
      return {
        'estado': 'ok',
        'resumen':
            'Se detectaron ${rows.length} preguntas con riesgo de olvido en ${materias.length} materias. Urgentes: $totalUrgentes. Materia mas expuesta: ${top['materia']}.',
        'materias': materias,
        'total_preguntas': rows.length,
        'total_urgentes': totalUrgentes,
      };
    }

    List<List<String>> trocearIds(List<String> ids, int tamano) {
      final salida = <List<String>>[];
      for (var i = 0; i < ids.length; i += tamano) {
        final fin = (i + tamano) > ids.length ? ids.length : (i + tamano);
        salida.add(ids.sublist(i, fin));
      }
      return salida;
    }

    // 1) Camino principal: RPC segura (si existe en tu Supabase).
    final rpc = await _rpcComoMapa(
      functionName: 'fn_tutor_prediccion_olvido_materias',
      params: {'p_usuario_id': userId, 'p_min_prob': 40},
    );
    if (rpc != null && rpc.isNotEmpty) {
      final materiasRaw = rpc['materias'];
      if (materiasRaw is List) {
        final materias = materiasRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        return {
          'estado': (rpc['estado'] ?? (materias.isEmpty ? 'sin_datos' : 'ok'))
              .toString(),
          'resumen': (rpc['resumen'] ?? '').toString(),
          'materias': materias,
          'total_preguntas': _toInt(rpc['total_preguntas']),
          'total_urgentes': _toInt(rpc['total_urgentes']),
        };
      }
    }

    // 2) Fallback robusto: sin joins anidados de PostgREST.
    try {
      final List<dynamic> raw = await _supabase
          .from('prediccion_olvido')
          .select(
            'pregunta_id, probabilidad_olvido, urgencia_revision, fecha_revision_optima, requiere_revision_inmediata',
          )
          .eq('usuario_id', userId)
          .gte('probabilidad_olvido', 40)
          .order('probabilidad_olvido', ascending: false)
          .limit(300);

      final rows = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (rows.isEmpty) {
        return {
          'estado': 'sin_datos',
          'resumen': 'No hay materias con riesgo de olvido alto por ahora.',
          'materias': <Map<String, dynamic>>[],
          'total_preguntas': 0,
          'total_urgentes': 0,
        };
      }

      final preguntaIds = rows
          .map((r) => (r['pregunta_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final preguntaToMateriaId = <String, String>{};
      for (final chunk in trocearIds(preguntaIds, 150)) {
        final List<dynamic> preguntaRaw = await _supabase
            .from('pregunta')
            .select('id, materia_id')
            .inFilter('id', chunk);
        for (final item in preguntaRaw.whereType<Map>()) {
          final map = Map<String, dynamic>.from(item);
          final pid = (map['id'] ?? '').toString().trim();
          final mid = (map['materia_id'] ?? '').toString().trim();
          if (pid.isNotEmpty && mid.isNotEmpty) {
            preguntaToMateriaId[pid] = mid;
          }
        }
      }

      final materiaIds = preguntaToMateriaId.values.toSet().toList();
      final materiaIdToNombre = <String, String>{};
      for (final chunk in trocearIds(materiaIds, 150)) {
        final List<dynamic> materiaRaw = await _supabase
            .from('materia')
            .select('id, nombre')
            .inFilter('id', chunk);
        for (final item in materiaRaw.whereType<Map>()) {
          final map = Map<String, dynamic>.from(item);
          final id = (map['id'] ?? '').toString().trim();
          final nombre = (map['nombre'] ?? 'Materia sin nombre')
              .toString()
              .trim();
          if (id.isNotEmpty) {
            materiaIdToNombre[id] = nombre.isEmpty
                ? 'Materia sin nombre'
                : nombre;
          }
        }
      }

      final materiaPorPregunta = <String, String>{};
      for (final pid in preguntaIds) {
        final mid = preguntaToMateriaId[pid];
        if (mid == null || mid.isEmpty) continue;
        materiaPorPregunta[pid] =
            materiaIdToNombre[mid] ?? 'Materia sin nombre';
      }

      return construirResultado(
        rows: rows,
        materiaNombrePorPregunta: materiaPorPregunta,
      );
    } catch (e) {
      debugPrint('obtenerPrediccionOlvidoDetalle error: $e');
      return {
        'estado': 'error',
        'resumen':
            'No se pudo cargar el listado por materias de prediccion de olvido.',
        'materias': <Map<String, dynamic>>[],
        'total_preguntas': 0,
        'total_urgentes': 0,
      };
    }
  }

  Future<Map<String, dynamic>> obtenerDetallePrediccionOlvidoMateria({
    required String userId,
    required String materiaNombre,
    List<String> preguntaIdsPreferidas = const <String>[],
  }) async {
    Map<String, dynamic> vacio({
      required String estado,
      required String resumen,
      List<String> ids = const <String>[],
    }) {
      return {
        'estado': estado,
        'materia': materiaNombre,
        'resumen': resumen,
        'riesgo_general': 0.0,
        'probabilidad_maxima': 0.0,
        'nivel_riesgo': 'bajo',
        'total_preguntas': 0,
        'total_urgentes': 0,
        'proxima_revision': '',
        'proxima_revision_legible': '',
        'distribucion_urgencia': const {
          'critica': 0,
          'alta': 0,
          'media': 0,
          'baja': 0,
        },
        'ids_por_urgencia': const {
          'critica': <String>[],
          'alta': <String>[],
          'media': <String>[],
          'baja': <String>[],
        },
        'pregunta_ids': ids,
      };
    }

    if (_sesionInvalida(userId)) {
      return vacio(
        estado: 'sin_sesion',
        resumen: 'Inicia sesion para ver el detalle de esta materia.',
      );
    }

    List<List<String>> trocearIds(List<String> ids, int tamano) {
      final salida = <List<String>>[];
      for (var i = 0; i < ids.length; i += tamano) {
        final fin = (i + tamano) > ids.length ? ids.length : (i + tamano);
        salida.add(ids.sublist(i, fin));
      }
      return salida;
    }

    String clasificarUrgencia(Map<String, dynamic> row) {
      final urg = _normalizarTexto((row['urgencia_revision'] ?? '').toString());
      final prob = _toDouble(row['probabilidad_olvido']) ?? 0;
      if (urg.contains('critica') || urg.contains('critico') || prob >= 85) {
        return 'critica';
      }
      if (urg.contains('alta') || prob >= 70) return 'alta';
      if (urg.contains('media') || prob >= 55) return 'media';
      return 'baja';
    }

    String etiquetaRevision(DateTime? fecha) {
      if (fecha == null) return '';
      final ahora = DateTime.now();
      final dias = fecha.difference(ahora).inDays;
      if (dias == 0) return 'Hoy';
      if (dias > 0) return 'En $dias dias';
      return 'Hace ${dias.abs()} dias';
    }

    String nivelRiesgo(double riesgo) {
      if (riesgo >= 85) return 'critico';
      if (riesgo >= 70) return 'alto';
      if (riesgo >= 55) return 'medio';
      return 'bajo';
    }

    Map<String, dynamic> construirDesdeMateriaBase(
      Map<String, dynamic> materia, {
      required String estado,
    }) {
      final total = _toInt(materia['total']);
      final urgentes = _toInt(materia['urgentes']);
      final probProm = _toDouble(materia['probabilidad_promedio']) ?? 0.0;
      final probMax = _toDouble(materia['probabilidad_maxima']) ?? 0.0;
      final riesgo = probProm > 0 ? probProm : probMax;
      final proxima = (materia['proxima_revision'] ?? '').toString().trim();
      final proximaFecha = _parseFechaFlexible(proxima);
      final ids = materia['pregunta_ids'] is List
          ? (materia['pregunta_ids'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList()
          : <String>[];
      final restantes = (total - urgentes).clamp(0, total);
      final urgentesSafe = urgentes.clamp(0, ids.length);
      final criticaIds = ids.take(urgentesSafe).toList();
      final mediaIds = ids.skip(urgentesSafe).toList();
      return {
        'estado': estado,
        'materia': materiaNombre,
        'resumen':
            'Riesgo general ${riesgo.toStringAsFixed(1)}%. Urgentes: $urgentes de $total.',
        'riesgo_general': riesgo,
        'probabilidad_maxima': probMax,
        'nivel_riesgo': nivelRiesgo(riesgo),
        'total_preguntas': total,
        'total_urgentes': urgentes,
        'proxima_revision': proxima,
        'proxima_revision_legible': etiquetaRevision(proximaFecha),
        'distribucion_urgencia': {
          'critica': urgentes,
          'alta': 0,
          'media': restantes,
          'baja': 0,
        },
        'ids_por_urgencia': {
          'critica': criticaIds,
          'alta': <String>[],
          'media': mediaIds,
          'baja': <String>[],
        },
        'pregunta_ids': ids,
      };
    }

    Map<String, dynamic>? baseMateria;
    try {
      final base = await obtenerPrediccionOlvidoDetalle(userId: userId);
      final materiasRaw = base['materias'];
      if (materiasRaw is List) {
        final materias = materiasRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        final objetivo = _normalizarTexto(materiaNombre);

        Map<String, dynamic>? encontrada;
        for (final m in materias) {
          final nombre = _normalizarTexto((m['materia'] ?? '').toString());
          if (nombre == objetivo) {
            encontrada = m;
            break;
          }
        }

        if (encontrada == null && preguntaIdsPreferidas.isNotEmpty) {
          final idsSet = preguntaIdsPreferidas.map((e) => e.trim()).toSet();
          for (final m in materias) {
            final ids = m['pregunta_ids'] is List
                ? (m['pregunta_ids'] as List)
                      .map((e) => e.toString().trim())
                      .where((e) => e.isNotEmpty)
                      .toSet()
                : <String>{};
            if (ids.isNotEmpty && ids.intersection(idsSet).isNotEmpty) {
              encontrada = m;
              break;
            }
          }
        }

        if (encontrada != null) {
          baseMateria = construirDesdeMateriaBase(
            encontrada,
            estado: 'ok_base',
          );
        }
      }
    } catch (_) {
      // Se mantiene fallback sin bloquear el flujo.
    }

    try {
      final List<dynamic> raw = await _supabase
          .from('prediccion_olvido')
          .select(
            'pregunta_id, probabilidad_olvido, urgencia_revision, '
            'fecha_revision_optima, requiere_revision_inmediata',
          )
          .eq('usuario_id', userId)
          .gte('probabilidad_olvido', 40)
          .order('probabilidad_olvido', ascending: false)
          .limit(1200);

      final rows = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (rows.isEmpty) {
        return baseMateria ??
            vacio(
              estado: 'sin_datos',
              resumen: 'No hay preguntas con riesgo para esta materia.',
              ids: preguntaIdsPreferidas,
            );
      }

      var filtradas = <Map<String, dynamic>>[];
      if (preguntaIdsPreferidas.isNotEmpty) {
        final idsSet = preguntaIdsPreferidas.map((e) => e.trim()).toSet();
        filtradas = rows.where((row) {
          final preguntaId = (row['pregunta_id'] ?? '').toString().trim();
          return preguntaId.isNotEmpty && idsSet.contains(preguntaId);
        }).toList();
      }

      if (filtradas.isEmpty) {
        final preguntaIds = rows
            .map((r) => (r['pregunta_id'] ?? '').toString().trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();

        final preguntaToMateriaId = <String, String>{};
        for (final chunk in trocearIds(preguntaIds, 150)) {
          final List<dynamic> preguntaRaw = await _supabase
              .from('pregunta')
              .select('id, materia_id')
              .inFilter('id', chunk);
          for (final item in preguntaRaw.whereType<Map>()) {
            final map = Map<String, dynamic>.from(item);
            final pid = (map['id'] ?? '').toString().trim();
            final mid = (map['materia_id'] ?? '').toString().trim();
            if (pid.isNotEmpty && mid.isNotEmpty) {
              preguntaToMateriaId[pid] = mid;
            }
          }
        }

        final materiaIds = preguntaToMateriaId.values.toSet().toList();
        final materiaIdToNombre = <String, String>{};
        for (final chunk in trocearIds(materiaIds, 150)) {
          final List<dynamic> materiaRaw = await _supabase
              .from('materia')
              .select('id, nombre')
              .inFilter('id', chunk);
          for (final item in materiaRaw.whereType<Map>()) {
            final map = Map<String, dynamic>.from(item);
            final id = (map['id'] ?? '').toString().trim();
            final nombre = (map['nombre'] ?? 'Materia sin nombre')
                .toString()
                .trim();
            if (id.isNotEmpty) {
              materiaIdToNombre[id] = nombre.isEmpty
                  ? 'Materia sin nombre'
                  : nombre;
            }
          }
        }

        final objetivo = _normalizarTexto(materiaNombre);
        filtradas = rows.where((row) {
          final preguntaId = (row['pregunta_id'] ?? '').toString().trim();
          final materiaId = preguntaToMateriaId[preguntaId];
          final materia = materiaId == null
              ? ''
              : (materiaIdToNombre[materiaId] ?? '');
          return _normalizarTexto(materia) == objetivo;
        }).toList();
      }

      if (filtradas.isEmpty) {
        return baseMateria ??
            vacio(
              estado: 'sin_datos',
              resumen:
                  'No se encontraron preguntas con riesgo para esta materia.',
              ids: preguntaIdsPreferidas,
            );
      }

      var suma = 0.0;
      var maxProb = 0.0;
      var urgentes = 0;
      DateTime? proximaRevision;
      final dist = <String, int>{
        'critica': 0,
        'alta': 0,
        'media': 0,
        'baja': 0,
      };
      final idsPorUrg = <String, List<String>>{
        'critica': <String>[],
        'alta': <String>[],
        'media': <String>[],
        'baja': <String>[],
      };

      for (final row in filtradas) {
        final prob = _toDouble(row['probabilidad_olvido']) ?? 0;
        suma += prob;
        if (prob > maxProb) maxProb = prob;

        final urg = _normalizarTexto(
          (row['urgencia_revision'] ?? '').toString(),
        );
        final esUrgente =
            row['requiere_revision_inmediata'] == true ||
            urg.contains('alta') ||
            urg.contains('critica');
        if (esUrgente) urgentes++;

        final bucket = clasificarUrgencia(row);
        dist[bucket] = (dist[bucket] ?? 0) + 1;
        final preguntaId = (row['pregunta_id'] ?? '').toString().trim();
        if (preguntaId.isNotEmpty) {
          idsPorUrg[bucket]!.add(preguntaId);
        }

        final fecha = _parseFechaFlexible(row['fecha_revision_optima']);
        if (fecha != null &&
            (proximaRevision == null || fecha.isBefore(proximaRevision))) {
          proximaRevision = fecha;
        }
      }

      final ordenadas = [...filtradas]
        ..sort((a, b) {
          final pa = _toDouble(a['probabilidad_olvido']) ?? 0;
          final pb = _toDouble(b['probabilidad_olvido']) ?? 0;
          return pb.compareTo(pa);
        });
      final ids = ordenadas
          .map((r) => (r['pregunta_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final riesgoGeneral = filtradas.isEmpty ? 0.0 : (suma / filtradas.length);
      final proximaTxt = proximaRevision == null
          ? ''
          : _formatearFecha(proximaRevision);

      return {
        'estado': 'ok',
        'materia': materiaNombre,
        'resumen':
            'Riesgo general ${riesgoGeneral.toStringAsFixed(1)}%. Urgentes: $urgentes de ${filtradas.length}.',
        'riesgo_general': riesgoGeneral,
        'probabilidad_maxima': maxProb,
        'nivel_riesgo': nivelRiesgo(riesgoGeneral),
        'total_preguntas': filtradas.length,
        'total_urgentes': urgentes,
        'proxima_revision': proximaTxt,
        'proxima_revision_legible': etiquetaRevision(proximaRevision),
        'distribucion_urgencia': dist,
        'ids_por_urgencia': idsPorUrg,
        'pregunta_ids': ids,
      };
    } catch (e) {
      debugPrint('obtenerDetallePrediccionOlvidoMateria error: $e');
      return baseMateria ??
          vacio(
            estado: 'error',
            resumen:
                'No se pudo cargar el detalle de prediccion para esta materia.',
            ids: preguntaIdsPreferidas,
          );
    }
  }

  Map<String, dynamic> construirMensajeMotivacionalEstructurado({
    Map<String, dynamic>? progreso,
    Map<String, dynamic>? probabilidad,
    Map<String, dynamic>? proyeccion,
  }) {
    final dominadas = _toInt(
      proyeccion?['preguntas_dominadas'] ?? progreso?['preguntas_dominadas'],
    );
    final porcentaje =
        _toDouble(proyeccion?['porcentaje_completado']) ??
        _toDouble(progreso?['porcentaje_completado']) ??
        0;
    final ritmoActual =
        _toDouble(proyeccion?['ritmo_actual_dia']) ??
        _toDouble(progreso?['ritmo_actual_dia']) ??
        0;
    final ritmoNecesario =
        _toDouble(proyeccion?['ritmo_necesario_dia']) ??
        _toDouble(progreso?['ritmo_necesario_dia']) ??
        0;
    final probAprobacion =
        _toDouble(proyeccion?['probabilidad_aprobacion']) ??
        _toDouble(probabilidad?['probabilidad_aprobacion']);
    final semaforo = (proyeccion?['semaforo_avance'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    late final String resumen;
    late final String detalle;
    if (semaforo == 'completado' ||
        semaforo == 'en_ritmo' ||
        progreso?['esta_adelantado'] == true) {
      resumen =
          'Excelente ritmo: vas adelantado con ${porcentaje.toStringAsFixed(1)}% completado.';
      detalle =
          'Sigue con la misma constancia para ganar margen de repaso antes del examen.';
    } else if (semaforo == 'atrasado' ||
        progreso?['esta_atrasado'] == true ||
        progreso?['debe_acelerar'] == true) {
      resumen =
          'Es momento de acelerar: ${ritmoActual.toStringAsFixed(1)}/dia vs ${ritmoNecesario.toStringAsFixed(1)}/dia.';
      detalle =
          'Empieza con un bloque corto ahora y cierra el dia cumpliendo la meta.';
    } else {
      resumen =
          'Vas construyendo buen ritmo: $dominadas dominadas (${porcentaje.toStringAsFixed(1)}%).';
      detalle = 'La clave ahora es consistencia diaria sin romper cadena.';
    }

    final cierre = probAprobacion == null
        ? detalle
        : '$detalle Probabilidad estimada actual: ${probAprobacion.toStringAsFixed(1)}%.';

    return {
      'id': 'mensaje_personal',
      'titulo': 'Mensaje Personal del Tutor IA',
      'resumen': resumen,
      'detalle': cierre,
      'prompt': 'dame un mensaje motivacional',
      'cta': 'Recibir motivacion',
      'color': '#E9D5FF',
      'icono': 'favorite',
      'expandable': true,
    };
  }

  Future<Map<String, dynamic>> recomendarPorMateria({
    required String materia,
    required double porcentaje,
    required String nivel,
    List<String> debilidadesGlobales = const [],
  }) async {
    if (!SupabaseService.isInitialized) {
      return _recomendacionMateriaFallback(materia, porcentaje, nivel);
    }

    try {
      final prompt =
          '''
Actua como tutor policial PNP.
Debes recomendar refuerzo para UNA materia.

DATOS:
{
  "materia": "$materia",
  "porcentaje_dominio": $porcentaje,
  "nivel": "$nivel",
  "debilidades_globales": ${jsonEncode(debilidadesGlobales)}
}

Devuelve SOLO JSON valido (sin markdown):
{
  "mensaje": "breve y claro",
  "focos": ["foco 1", "foco 2", "foco 3"],
  "cantidad_preguntas": 15,
  "tiempo_minutos": 20
}
''';

      final currentUserId = _supabase.auth.currentUser?.id;
      final response = await _supabase.functions.invoke(
        'ia_diagnostico',
        body: {
          'prompt': prompt,
          'mode': 'chat',
          if (currentUserId != null && currentUserId.isNotEmpty)
            'user_id': currentUserId,
        },
      );

      final data = response.data;
      String? raw;
      if (data is String && data.trim().isNotEmpty) {
        raw = data.trim();
      } else if (data is Map && data['text'] is String) {
        raw = (data['text'] as String).trim();
      }

      if (raw == null || raw.isEmpty) {
        return _recomendacionMateriaFallback(materia, porcentaje, nivel);
      }

      final parsed = _parsePanelJson(raw);
      if (parsed == null) {
        return _recomendacionMateriaFallback(materia, porcentaje, nivel);
      }

      final focosRaw = parsed['focos'];
      final focos = focosRaw is List
          ? focosRaw
                .whereType<String>()
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .take(4)
                .toList()
          : <String>[];

      return {
        'mensaje': (parsed['mensaje'] ?? '').toString().trim().isEmpty
            ? 'Refuerza $materia con preguntas enfocadas en tus errores frecuentes.'
            : parsed['mensaje'].toString(),
        'focos': focos,
        'cantidad_preguntas': _toInt(parsed['cantidad_preguntas']) > 0
            ? _toInt(parsed['cantidad_preguntas'])
            : 15,
        'tiempo_minutos': _toInt(parsed['tiempo_minutos']) > 0
            ? _toInt(parsed['tiempo_minutos'])
            : 20,
      };
    } catch (_) {
      return _recomendacionMateriaFallback(materia, porcentaje, nivel);
    }
  }

  Future<String> enviarMensajeTutor({
    required String mensaje,
    Map<String, dynamic>? contexto,
  }) async {
    final mensajeLimpio = mensaje.trim();
    if (mensajeLimpio.isEmpty) {
      return 'Escribe una consulta para poder ayudarte.';
    }

    if (!SupabaseService.isInitialized) {
      return 'No puedo conectarme al tutor en este momento. Intenta de nuevo.';
    }

    try {
      final contextoBase = Map<String, dynamic>.from(
        contexto ?? const <String, dynamic>{},
      );
      final userIdRaw =
          (contextoBase['user_id'] ?? contextoBase['usuario_id'] ?? '')
              .toString()
              .trim();
      final userId = userIdRaw.isEmpty ? null : userIdRaw;

      final sqlDirecta = _extraerConsultaSqlSegura(mensajeLimpio);
      if (sqlDirecta != null) {
        if (!_habilitarSqlDirecto) {
          return 'La consulta SQL directa esta deshabilitada por seguridad.';
        }
        return await _resolverConsultaSqlDirecta(
          userId: userId,
          sql: sqlDirecta,
        );
      }

      final respuestaDeterministica = await _resolverConsultaDeterministica(
        mensaje: mensajeLimpio,
        userId: userId,
        contexto: contextoBase,
      );
      if (respuestaDeterministica != null) {
        return respuestaDeterministica;
      }

      final respuestaConversacional = _resolverConsultaConversacionalSimple(
        mensaje: mensajeLimpio,
        contexto: contextoBase,
      );
      if (respuestaConversacional != null) {
        return respuestaConversacional;
      }

      var usarContextoBd = _requiereContextoBdParaChat(
        mensaje: mensajeLimpio,
        contexto: contextoBase,
      );
      if (usarContextoBd &&
          (userId == null || userId.isEmpty || userId == 'user_test_id')) {
        // En modo invitado seguimos como tutor general sin contexto personal.
        usarContextoBd = false;
      }

      // El contexto fuerte se arma en la Edge Function para evitar duplicidad
      // de tokens y mantener una sola estrategia de tutor.
      final prompt = mensajeLimpio;
      await _guardarEstadoTutorUsuario(
        userId: userId,
        contexto: contextoBase,
        ultimoMensaje: mensajeLimpio,
      );

      final response = await _invocarTutorConReintento401(
        prompt: prompt,
        userId: userId,
        mode: 'chat',
        usarContextoBd: usarContextoBd,
      );

      final raw = _extraerTextoDesdeInvoke(response.data);
      if (raw == null || raw.isEmpty) {
        return 'No pude generar respuesta. Intenta nuevamente.';
      }

      final parsed = _parsePanelJson(raw);
      if (parsed != null) {
        final estructurada = _extraerRespuestaEstructurada(parsed);
        if (estructurada != null && estructurada.isNotEmpty) {
          return _normalizarRespuestaTutor(estructurada);
        }
      }

      final texto = _normalizarRespuestaTutor(raw);
      if (texto.isNotEmpty) {
        return texto;
      }

      return 'No pude generar respuesta util. Intenta nuevamente.';
    } on FunctionException catch (e) {
      return _mensajeErrorTutorDesdeFuncion(e);
    } catch (e) {
      final detalle = _resumirTextoError(e.toString(), max: 180);
      return 'Error inesperado del tutor: $detalle';
    }
  }

  String? _extraerConsultaSqlSegura(String mensaje) {
    final txt = mensaje.trim();
    if (txt.isEmpty) return null;

    final lower = txt.toLowerCase();
    if (lower.startsWith('sql:')) {
      final sql = txt.substring(4).trim();
      return sql.isEmpty ? null : sql;
    }

    if (lower.startsWith('consulta sql:')) {
      final sql = txt.substring('consulta sql:'.length).trim();
      return sql.isEmpty ? null : sql;
    }

    return null;
  }

  Future<String> _resolverConsultaSqlDirecta({
    required String? userId,
    required String sql,
  }) async {
    if (userId == null || userId.isEmpty || userId == 'user_test_id') {
      return 'Para ejecutar SQL necesito tu sesion activa. Cierra sesion, vuelve a ingresar y reintenta.';
    }

    try {
      final raw = await _supabase.rpc(
        'fn_ia_ejecutar_sql_lectura',
        params: {'p_usuario_id': userId, 'p_sql': sql, 'p_max_rows': 25},
      );

      final data = _asMap(raw);
      final rowsRaw = data['rows'];
      final rows = rowsRaw is List ? rowsRaw : const <dynamic>[];
      final count = _toInt(data['count']);
      final preview = rows.take(5).toList();

      if (rows.isEmpty) {
        return 'Consulta SQL ejecutada. No se encontraron filas.';
      }

      return 'Consulta SQL ejecutada. Filas: $count. Vista previa: ${jsonEncode(preview)}';
    } catch (e) {
      final detalle = _resumirTextoError(e.toString(), max: 240);
      return 'No pude ejecutar SQL. Verifica que exista fn_ia_ejecutar_sql_lectura y usa solo SELECT con :user_id. Detalle: $detalle';
    }
  }

  // ignore: unused_element
  String _construirPromptTutor({
    required String mensaje,
    required Map<String, dynamic> contextoFinal,
  }) {
    final esEstrategica = _esConsultaEstrategica(mensaje);
    final instrucciones = esEstrategica
        ? '''
REGLAS:
1) Responde en espanol natural, cercano y profesional.
2) Nunca dejes frases incompletas.
3) Da una respuesta util entre 90 y 160 palabras.
4) Incluye:
   - Diagnostico breve
   - Accion concreta para hoy
   - 3 pasos claros
   - Como medir avance esta semana
5) No uses markdown ni bloques de codigo.
6) Evita plantillas rigidas o frases repetitivas.
'''
        : '''
REGLAS:
1) Responde en espanol natural, cercano y directo (tono humano, no robot).
2) Nunca dejes frases incompletas.
3) Responde en 2 a 5 frases completas.
4) Si la pregunta es personal (ej. "eres la IA"), responde directo en la primera frase.
5) Cierra con una sugerencia practica breve.
6) No uses markdown ni bloques de codigo.
''';

    return '''
Actua como tutor academico para examen de ascenso PNP.

CONTEXTO (JSON):
${jsonEncode(contextoFinal)}

MENSAJE DEL ESTUDIANTE:
"$mensaje"

$instrucciones
''';
  }

  bool _esConsultaEstrategica(String mensaje) {
    final t = _normalizarTexto(mensaje);
    const claves = <String>[
      'plan',
      'estrategia',
      'simulacro',
      'materia',
      'debil',
      'estudio',
      'estudiar',
      'practica',
      'mejorar',
      'horario',
      'objetivo',
    ];
    for (final c in claves) {
      if (t.contains(c)) return true;
    }
    return false;
  }

  bool _requiereContextoBdParaChat({
    required String mensaje,
    required Map<String, dynamic> contexto,
  }) {
    if (_esConsultaRanking(mensaje) || _esConsultaPreparacionExamen(mensaje)) {
      return true;
    }

    if (contexto['forzar_contexto_bd'] == true ||
        contexto['usar_contexto_bd'] == true) {
      return true;
    }

    final normalizado = _normalizarTexto(mensaje)
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalizado.isEmpty) return false;

    final t = ' $normalizado ';
    const indicadoresPersonales = <String>[
      ' mi ',
      ' mis ',
      ' conmigo ',
      ' para mi ',
      ' yo ',
      ' me ',
      ' estoy ',
      ' voy ',
      ' conmigo ',
      ' mio ',
      ' mia ',
    ];
    const indicadoresRendimiento = <String>[
      'progreso',
      'avance',
      'rendimiento',
      'acierto',
      'racha',
      'debilidad',
      'fortaleza',
      'promedio',
      'plan',
      'examen',
      'listo',
      'preparado',
      'tasa',
      'puntaje',
      'dominio',
      'materia debil',
    ];

    final tienePersonal = indicadoresPersonales.any(t.contains);
    final pideRendimiento = indicadoresRendimiento.any(normalizado.contains);
    if (tienePersonal && pideRendimiento) return true;

    const frasesDirectas = <String>[
      'como voy',
      'que tal voy',
      'como estoy',
      'como voy en',
      'que debo estudiar hoy',
      'hazme un plan',
      'dame mi plan',
      'mis debilidades',
      'mis fortalezas',
      'mi progreso',
      'mi rendimiento',
      'mi avance',
      'mi promedio',
      'mi puntaje',
      'mi examen',
    ];
    for (final frase in frasesDirectas) {
      if (normalizado.contains(frase)) return true;
    }

    return false;
  }

  String? _resolverConsultaConversacionalSimple({
    required String mensaje,
    required Map<String, dynamic> contexto,
  }) {
    final t = _normalizarTexto(mensaje);
    final nombre = _extraerNombrePreferido(contexto);
    final saludo = nombre == null ? '' : '$nombre, ';

    final mencionaRobot =
        t.contains('robot') ||
        t.contains('amigable') ||
        t.contains('frio') ||
        t.contains('muy tecnico');
    if (mencionaRobot) {
      return '${saludo}tienes razon, ajusto el tono desde ahora. Te respondere mas claro y natural. Si quieres, empezamos con un plan rapido para hoy segun tus materias mas debiles.';
    }

    final preguntaIdentidad =
        t.contains('eres gemini') ||
        (t.contains('eres') && t.contains('ia')) ||
        t.contains('que modelo eres') ||
        t.contains('quien eres');
    if (preguntaIdentidad) {
      return 'Si. Soy tu Tutor IA Personal con Gemini. Si inicias sesion puedo personalizar con tu progreso en Supabase; si no, te guio con un plan general de estudio.';
    }

    return null;
  }

  String? _extraerNombrePreferido(Map<String, dynamic> contexto) {
    final directos = [
      contexto['nombre_completo'],
      contexto['nombre'],
      contexto['display_name'],
    ];
    for (final value in directos) {
      final txt = value?.toString().trim();
      if (txt != null && txt.isNotEmpty) return _nombreCorto(txt);
    }

    final bd = _asMap(contexto['contexto_bd_usuario']);
    final fromBd = bd['nombre_completo']?.toString().trim();
    if (fromBd != null && fromBd.isNotEmpty) return _nombreCorto(fromBd);
    return null;
  }

  String _nombreCorto(String nombreCompleto) {
    final limpio = nombreCompleto.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (limpio.isEmpty) return nombreCompleto.trim();
    return limpio.split(' ').first;
  }

  Future<String?> _resolverConsultaDeterministica({
    required String mensaje,
    required String? userId,
    required Map<String, dynamic> contexto,
  }) async {
    // Sin sesion valida evitamos rutas deterministicas que exigen BD personal
    // y dejamos que el tutor responda en modo general via Edge Function.
    if (_sesionInvalida(userId)) {
      if (_esConsultaRanking(mensaje)) {
        return 'Para decirte tu puesto exacto en el ranking necesito tu sesion activa. Inicia sesion y te digo tu posicion semanal e historica.';
      }
      return null;
    }

    if (_esConsultaPlanDiario(mensaje)) {
      return await _resolverConsultaPlanDiario(userId: userId);
    }

    if (_esConsultaQueEstudiar(mensaje)) {
      return await _resolverConsultaQueEstudiar(userId: userId);
    }

    if (_esConsultaHorarioEstudio(mensaje)) {
      return await _resolverConsultaHorarioEstudio(userId: userId);
    }

    if (_esConsultaAnalisisVelocidad(mensaje)) {
      return await _resolverConsultaAnalisisVelocidad(userId: userId);
    }

    if (_esConsultaAnalisisCognitivo(mensaje)) {
      return await _resolverConsultaAnalisisCognitivo(userId: userId);
    }

    if (_esConsultaAnalisisSesion(mensaje)) {
      return await _resolverConsultaAnalisisSesion(userId: userId);
    }

    if (_esConsultaPatronesError(mensaje)) {
      return await _resolverConsultaPatronesError(userId: userId);
    }

    if (_esConsultaCoachMemoria(mensaje)) {
      return await _resolverConsultaCoachMemoria(userId: userId);
    }

    if (_esConsultaPrediccionOlvido(mensaje)) {
      return await _resolverConsultaPrediccionOlvido(userId: userId);
    }

    if (_esConsultaMotivacion(mensaje)) {
      return await _resolverConsultaMotivacion(userId: userId);
    }

    if (_esConsultaPreparacionExamen(mensaje)) {
      return await _resolverConsultaPreparacionExamen(userId: userId);
    }

    if (_esConsultaRanking(mensaje)) {
      return await _resolverConsultaRanking(userId: userId, contexto: contexto);
    }

    return null;
  }

  String _normalizarConsultaTexto(String mensaje) {
    return _normalizarTexto(mensaje)
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _contieneAlgunaFrase(String texto, List<String> frases) {
    for (final frase in frases) {
      if (texto.contains(frase)) return true;
    }
    return false;
  }

  bool _sesionInvalida(String? userId) {
    return userId == null || userId.isEmpty || userId == 'user_test_id';
  }

  bool _esConsultaPlanDiario(String mensaje) {
    final t = _normalizarConsultaTexto(mensaje);
    if (t.isEmpty) return false;
    return _contieneAlgunaFrase(t, const [
      'plan diario',
      'plan del dia',
      'plan de hoy',
      'que hago hoy',
      'que estudiar hoy',
      'plan adaptativo',
    ]);
  }

  bool _esConsultaQueEstudiar(String mensaje) {
    final t = _normalizarConsultaTexto(mensaje);
    if (t.isEmpty) return false;
    if (t.contains('que estudiar hoy')) return false;
    return _contieneAlgunaFrase(t, const [
      'que estudiar',
      'por donde empiezo',
      'materia prioritaria',
      'prioridad de estudio',
      'recomiendame que estudiar',
      'que materia repaso',
    ]);
  }

  bool _esConsultaHorarioEstudio(String mensaje) {
    final t = _normalizarConsultaTexto(mensaje);
    if (t.isEmpty) return false;
    return _contieneAlgunaFrase(t, const [
      'mejor horario',
      'que hora estudiar',
      'cuando estudiar',
      'estudiar en la manana',
      'estudiar en la tarde',
      'estudiar en la noche',
      'horario de estudio',
    ]);
  }

  bool _esConsultaAnalisisVelocidad(String mensaje) {
    final t = _normalizarConsultaTexto(mensaje);
    if (t.isEmpty) return false;
    return _contieneAlgunaFrase(t, const [
      'analisis de velocidad',
      'mi velocidad',
      'impulsividad',
      'respondo muy rapido',
      'respondo muy lento',
      'velocidad de respuesta',
    ]);
  }

  bool _esConsultaAnalisisCognitivo(String mensaje) {
    final t = _normalizarConsultaTexto(mensaje);
    if (t.isEmpty) return false;
    return _contieneAlgunaFrase(t, const [
      'analisis cognitivo',
      'perfil cognitivo',
      'cambios de respuesta',
      'veces leo enunciado',
      'nivel de confianza',
      'como estoy pensando',
    ]);
  }

  bool _esConsultaAnalisisSesion(String mensaje) {
    final t = _normalizarConsultaTexto(mensaje);
    if (t.isEmpty) return false;
    return _contieneAlgunaFrase(t, const [
      'analisis de sesion',
      'analiza mi sesion',
      'post sesion',
      'ultima sesion',
      'como me fue en la sesion',
      'analisis post sesion',
    ]);
  }

  bool _esConsultaPatronesError(String mensaje) {
    final t = _normalizarConsultaTexto(mensaje);
    if (t.isEmpty) return false;
    return _contieneAlgunaFrase(t, const [
      'patrones de error',
      'errores recurrentes',
      'por que fallo',
      'tipo de error',
      'detectar errores',
      'en que me equivoco',
    ]);
  }

  bool _esConsultaCoachMemoria(String mensaje) {
    final t = _normalizarConsultaTexto(mensaje);
    if (t.isEmpty) return false;
    return _contieneAlgunaFrase(t, const [
      'coach de memoria',
      'coach memoria',
      'activar coach de memoria',
      'indice de memoria',
      'memoria',
      'repeticion espaciada',
      'preguntas criticas',
      'preguntas dificiles',
      'preguntas olvidadas',
      'plan diario de memoria',
      'recordatorio de repaso',
      'focos de memoria',
      'entrenar memoria',
      'materias en riesgo',
      'materias criticas',
      'materias debiles',
      'riesgo de reprobar',
      'que materia estoy mal',
      'alerta de materias',
    ]);
  }

  bool _esConsultaPrediccionOlvido(String mensaje) {
    final t = _normalizarConsultaTexto(mensaje);
    if (t.isEmpty) return false;
    return _contieneAlgunaFrase(t, const [
      'prediccion de olvido',
      'que voy a olvidar',
      'olvido',
      'repaso urgente',
      'curva de olvido',
      'preguntas por olvidar',
    ]);
  }

  bool _esConsultaMotivacion(String mensaje) {
    final t = _normalizarConsultaTexto(mensaje);
    if (t.isEmpty) return false;
    return _contieneAlgunaFrase(t, const [
      'motivacion',
      'motiva',
      'mensaje motivacional',
      'consejo del dia',
      'consejo de mentalidad',
      'animo',
    ]);
  }

  bool _esConsultaPreparacionExamen(String mensaje) {
    final normalizado = _normalizarConsultaTexto(mensaje);
    if (normalizado.isEmpty) return false;

    const patronesFuertes = <String>[
      'para cuando estare listo',
      'cuando estare listo para mi examen',
      'cuando estare preparado para mi examen',
      'llego a tiempo al examen',
      'cuanto falta para mi examen',
      'cuando aprobare el examen',
      'probabilidad de aprobacion',
      'prediccion de aprobacion',
      'puntaje estimado',
      'prediccion del examen',
      'tiempo para dominar',
    ];
    for (final p in patronesFuertes) {
      if (normalizado.contains(p)) return true;
    }

    final mencionaExamen =
        normalizado.contains('examen') ||
        normalizado.contains('ascenso') ||
        normalizado.contains('aprobar') ||
        normalizado.contains('aprobare');
    final mencionaTiempo =
        normalizado.contains('cuando') ||
        normalizado.contains('fecha') ||
        normalizado.contains('dias') ||
        normalizado.contains('tiempo') ||
        normalizado.contains('listo') ||
        normalizado.contains('preparado');

    return mencionaExamen && mencionaTiempo;
  }

  Future<String?> _resolverConsultaPreparacionExamen({
    required String? userId,
  }) async {
    if (userId == null || userId.isEmpty || userId == 'user_test_id') {
      return 'Para calcular cuando estaras listo necesito tu sesion activa. Cierra sesion, vuelve a ingresar y consultame de nuevo.';
    }

    final params = <String, dynamic>{'p_usuario_id': userId};
    final progreso = await _rpcComoMapa(
      functionName: 'fn_calcular_progreso_dinamico',
      params: params,
    );
    final plan = await _rpcComoMapa(
      functionName: 'fn_generar_plan_adaptativo',
      params: params,
    );
    final dias = await _rpcComoMapa(
      functionName: 'fn_calcular_dias_disponibles',
      params: params,
    );

    if (progreso == null) {
      return null;
    }

    final perfilBasico = await _obtenerPerfilUsuarioBasico(userId);
    final categoriaUsuario = (perfilBasico['categoria'] ?? '')
        .toString()
        .trim();
    final proyeccion = await obtenerProyeccionTiempoDetalle(
      userId: userId,
      categoriaUsuario: categoriaUsuario.isEmpty ? null : categoriaUsuario,
      progresoBase: progreso,
      planBase: plan,
      diasBase: dias,
      perfilBase: perfilBasico,
    );
    final totalObjetivoRaw = proyeccion['total_preguntas_objetivo'];
    final totalObjetivoReal = totalObjetivoRaw is num
        ? totalObjetivoRaw.toInt()
        : int.tryParse((totalObjetivoRaw ?? '').toString());

    final preguntasDominadas = _toInt(
      proyeccion['preguntas_dominadas'] ?? progreso['preguntas_dominadas'],
    );
    final faltantes = (totalObjetivoReal != null && totalObjetivoReal >= 0)
        ? math.max(totalObjetivoReal - preguntasDominadas, 0)
        : (proyeccion['preguntas_faltantes'] is num
              ? (proyeccion['preguntas_faltantes'] as num).toInt()
              : int.tryParse(
                  (proyeccion['preguntas_faltantes'] ?? '').toString(),
                ));
    final porcentajeCompletado =
        (totalObjetivoReal != null && totalObjetivoReal > 0)
        ? ((preguntasDominadas * 100.0) / totalObjetivoReal).clamp(0.0, 100.0)
        : (_toDouble(proyeccion['porcentaje_completado']) ?? 0.0);
    final ritmoActual =
        _toDouble(proyeccion['ritmo_actual_dia']) ??
        _toDouble(progreso['ritmo_actual_dia']) ??
        0.0;
    final diasRestantes = _toInt(
      proyeccion['dias_restantes_examen'] ?? progreso['dias_restantes'],
    );
    final ritmoNecesario = (faltantes != null && diasRestantes > 0)
        ? (faltantes / diasRestantes)
        : (_toDouble(proyeccion['ritmo_necesario_dia']) ??
              _toDouble(progreso['ritmo_necesario_dia']) ??
              0.0);
    final recomendacionPreguntasDia = _toInt(
      progreso['recomendacion_preguntas_dia'],
    );

    final probAprobacion = _toDouble(proyeccion['probabilidad_aprobacion']);

    final fechaExamen =
        _parseFechaFlexible(progreso['fecha_examen']) ??
        _parseFechaFlexible(dias?['fecha_examen']);

    DateTime? fechaEstimadaListo;
    if (faltantes != null && faltantes <= 0) {
      fechaEstimadaListo = DateTime.now();
    } else if (faltantes != null && ritmoActual > 0) {
      final diasParaCompletar = (faltantes / ritmoActual).ceil();
      fechaEstimadaListo = DateTime.now().add(
        Duration(days: diasParaCompletar),
      );
    }

    final totalPlan = _toInt(plan?['total_preguntas_dia']);
    final planNuevas = _toInt(plan?['cantidad_nuevas']);
    final planRepaso = _toInt(plan?['cantidad_repaso']);

    final partes = <String>[];
    if (fechaEstimadaListo != null) {
      partes.add(
        'Si mantienes tu ritmo actual, estarias listo alrededor del ${_formatearFecha(fechaEstimadaListo)}.',
      );
    } else {
      partes.add(
        'Aun no puedo estimar una fecha exacta porque falta historial suficiente de avance.',
      );
    }

    if (fechaExamen != null) {
      final fechaExamenTxt = _formatearFecha(fechaExamen);
      if (diasRestantes > 0) {
        partes.add(
          'Tu examen objetivo es el $fechaExamenTxt y te quedan $diasRestantes dias.',
        );
      } else {
        partes.add('Tu fecha de examen registrada es $fechaExamenTxt.');
      }
    } else {
      partes.add(
        'No encuentro fecha de examen registrada en tu perfil; agregala para una proyeccion mas precisa.',
      );
    }

    if (totalObjetivoReal != null && totalObjetivoReal > 0) {
      partes.add(
        'Hoy vas $preguntasDominadas/$totalObjetivoReal (${porcentajeCompletado.toStringAsFixed(1)}%) con ritmo actual de ${ritmoActual.toStringAsFixed(2)} preguntas por dia.',
      );
    } else {
      partes.add(
        'Hoy llevas $preguntasDominadas preguntas dominadas con ritmo actual de ${ritmoActual.toStringAsFixed(2)} preguntas por dia.',
      );
    }

    if (ritmoNecesario > 0) {
      if (ritmoActual >= ritmoNecesario) {
        partes.add(
          'Necesitas ${ritmoNecesario.toStringAsFixed(2)} por dia para llegar y actualmente vas en ritmo.',
        );
      } else {
        final brecha = (ritmoNecesario - ritmoActual).toStringAsFixed(2);
        partes.add(
          'Necesitas ${ritmoNecesario.toStringAsFixed(2)} por dia para llegar; te falta subir aprox $brecha por dia.',
        );
      }
    }

    if (probAprobacion != null) {
      partes.add(
        'Tu probabilidad estimada de aprobacion actual es ${probAprobacion.toStringAsFixed(1)}%.',
      );
    }

    if (totalPlan > 0) {
      partes.add(
        'Plan sugerido para hoy: $totalPlan preguntas ($planNuevas nuevas y $planRepaso de repaso).',
      );
    } else if (recomendacionPreguntasDia > 0) {
      partes.add(
        'Para mejorar tu proyeccion, apunta a $recomendacionPreguntasDia preguntas hoy.',
      );
    }

    return partes.join(' ');
  }

  Future<String?> _resolverConsultaRanking({
    required String? userId,
    required Map<String, dynamic> contexto,
  }) async {
    if (_sesionInvalida(userId)) {
      return 'No puedo leer tu ranking porque no detecto una sesion valida. Cierra sesion, vuelve a ingresar y consulta de nuevo.';
    }

    final categoria = await _resolverCategoriaUsuario(
      userId: userId!,
      contexto: contexto,
    );
    final resumen = await _obtenerResumenRankingUsuario(
      userId: userId,
      categoriaUsuario: categoria,
    );

    if (resumen == null) {
      return 'No pude leer tu ranking ahora. Intenta en unos segundos.';
    }

    final semanal = _asMap(resumen['semanal']);
    final historico = _asMap(resumen['historico']);

    final semanalText = _formatearBloqueRanking(
      etiqueta: 'Semana',
      info: semanal,
      usarMaximoComoPrincipal: false,
    );
    final historicoText = _formatearBloqueRanking(
      etiqueta: 'Historico',
      info: historico,
      usarMaximoComoPrincipal: true,
    );

    return '$semanalText $historicoText';
  }

  Future<String?> _resolverConsultaPlanDiario({required String? userId}) async {
    if (_sesionInvalida(userId)) {
      return 'Para generar tu plan diario necesito tu sesion activa. Cierra sesion, vuelve a ingresar y consultame de nuevo.';
    }

    final params = <String, dynamic>{'p_usuario_id': userId!};
    final plan = await _rpcComoMapa(
      functionName: 'fn_generar_plan_adaptativo',
      params: params,
    );
    final progreso = await _rpcComoMapa(
      functionName: 'fn_calcular_progreso_dinamico',
      params: params,
    );
    final perfilBasico = await _obtenerPerfilUsuarioBasico(userId);
    final categoriaUsuario = (perfilBasico['categoria'] ?? '')
        .toString()
        .trim();
    final proyeccion = await obtenerProyeccionTiempoDetalle(
      userId: userId,
      categoriaUsuario: categoriaUsuario.isEmpty ? null : categoriaUsuario,
      progresoBase: progreso,
      planBase: plan,
    );

    if (plan == null) return null;

    final totalDia = _toInt(plan['total_preguntas_dia']);
    final nuevas = _toInt(plan['cantidad_nuevas']);
    final repaso = _toInt(plan['cantidad_repaso']);
    final diasRestantes = _toInt(
      proyeccion['dias_restantes_examen'] ?? plan['dias_restantes'],
    );
    final faltantes = _toInt(
      proyeccion['preguntas_faltantes'] ?? plan['preguntas_faltantes'],
    );
    final mensajeIa = (plan['mensaje_ia'] ?? '').toString().trim();

    final idsMaterias = _toStringList(plan['materias_prioritarias']);
    final materiasPrioritarias = await _resolverNombresMateriasDesdeIds(
      idsMaterias,
    );
    final materiasTxt = materiasPrioritarias.isEmpty
        ? 'Sin materias criticas detectadas por ahora.'
        : materiasPrioritarias.take(3).join(', ');

    final prob = _toDouble(proyeccion['probabilidad_aprobacion']);
    final ritmoActual =
        _toDouble(proyeccion['ritmo_actual_dia']) ??
        _toDouble(progreso?['ritmo_actual_dia']) ??
        0;
    final ritmoNecesario =
        _toDouble(proyeccion['ritmo_necesario_dia']) ??
        _toDouble(progreso?['ritmo_necesario_dia']) ??
        0;

    final partes = <String>[
      'Plan del dia: $totalDia preguntas ($nuevas nuevas y $repaso de repaso).',
      'Te quedan $diasRestantes dias y $faltantes preguntas por dominar.',
      'Materias prioritarias: $materiasTxt',
    ];

    if (ritmoActual > 0 && ritmoNecesario > 0) {
      if (ritmoActual >= ritmoNecesario) {
        partes.add(
          'Tu ritmo actual (${ritmoActual.toStringAsFixed(2)}/dia) esta en rango para llegar.',
        );
      } else {
        partes.add(
          'Ritmo actual ${ritmoActual.toStringAsFixed(2)}/dia; necesitas ${ritmoNecesario.toStringAsFixed(2)}/dia para cerrar brecha.',
        );
      }
    }

    if (prob != null) {
      partes.add(
        'Probabilidad estimada de aprobacion: ${prob.toStringAsFixed(1)}%.',
      );
    }

    if (mensajeIa.isNotEmpty) {
      partes.add('Mensaje del tutor: $mensajeIa');
    }

    return partes.join(' ');
  }

  Future<String?> _resolverConsultaQueEstudiar({
    required String? userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return 'Para recomendarte que estudiar necesito tu sesion activa. Cierra sesion, vuelve a ingresar y consultame de nuevo.';
    }

    try {
      final List<dynamic> raw = await _supabase
          .from('dominio_materia')
          .select(
            'tasa_dominio, prioridad_estudio, tiempo_recomendado_minutos, '
            'temas_debiles, dominio_hace_7_dias, '
            'materia:materia_id(nombre)',
          )
          .eq('usuario_id', userId!)
          .order('tasa_dominio', ascending: true)
          .limit(20);

      final rows = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (rows.isEmpty) {
        return 'Aun no tengo datos por materia. Haz una practica para construir tus prioridades.';
      }

      rows.sort((a, b) {
        final ta = _toDouble(a['tasa_dominio']) ?? 100;
        final tb = _toDouble(b['tasa_dominio']) ?? 100;
        if (ta != tb) return ta.compareTo(tb);
        final pa = _toInt(a['prioridad_estudio']);
        final pb = _toInt(b['prioridad_estudio']);
        return pb.compareTo(pa);
      });

      final prioritaria = rows.first;
      final materiaMap = _asMap(prioritaria['materia']);
      final materia = (materiaMap['nombre'] ?? 'Materia').toString();
      final tasa = _toDouble(prioritaria['tasa_dominio']) ?? 0;
      final tiempo = _toInt(prioritaria['tiempo_recomendado_minutos']);
      final hace7 = _toDouble(prioritaria['dominio_hace_7_dias']);
      final delta = hace7 == null ? 0.0 : (tasa - hace7);
      final tendencia = delta >= 2
          ? 'mejorando'
          : (delta <= -2 ? 'empeorando' : 'estable');
      final impactoPuntos = ((70 - tasa).clamp(0, 40) / 4).round();

      final temas = _toStringList(prioritaria['temas_debiles']);
      final temasTxt = temas.isEmpty
          ? 'Sin temas debiles especificos en tu historial.'
          : temas.take(3).join(', ');

      final topRiesgo = rows
          .take(3)
          .map((r) {
            final m = _asMap(r['materia']);
            final n = (m['nombre'] ?? 'Materia').toString();
            final t = (_toDouble(r['tasa_dominio']) ?? 0).toStringAsFixed(1);
            return '$n ($t%)';
          })
          .join(', ');

      return 'Prioridad #1: $materia (${tasa.toStringAsFixed(1)}%). Tendencia: $tendencia. Temas a estudiar hoy: $temasTxt. Tiempo sugerido: ${tiempo > 0 ? tiempo : 25} minutos. Impacto estimado si mejoras esta materia: +$impactoPuntos puntos. Otras materias en riesgo: $topRiesgo.';
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolverConsultaHorarioEstudio({
    required String? userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return 'Para recomendar horario necesito tu sesion activa. Cierra sesion, vuelve a ingresar y consultame de nuevo.';
    }

    try {
      final List<dynamic> raw = await _supabase
          .from('respuesta_usuario')
          .select(
            'momento_del_dia, es_correcta, fue_omitida, tiempo_total_respuesta',
          )
          .eq('usuario_id', userId!)
          .order('respondida_at', ascending: false)
          .limit(500);

      final stats = <String, Map<String, double>>{
        'manana': {'total': 0, 'correctas': 0, 'tiempo': 0},
        'tarde': {'total': 0, 'correctas': 0, 'tiempo': 0},
        'noche': {'total': 0, 'correctas': 0, 'tiempo': 0},
      };

      for (final item in raw) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final esCorrecta = row['es_correcta'];
        if (row['fue_omitida'] == true || esCorrecta is! bool) continue;
        final momento = _normalizarMomentoDelDia(row['momento_del_dia']);
        if (!stats.containsKey(momento)) continue;
        final bucket = stats[momento]!;
        bucket['total'] = (bucket['total'] ?? 0) + 1;
        if (esCorrecta) {
          bucket['correctas'] = (bucket['correctas'] ?? 0) + 1;
        }
        final tiempo = _toDouble(row['tiempo_total_respuesta']) ?? 0;
        if (tiempo > 0) bucket['tiempo'] = (bucket['tiempo'] ?? 0) + tiempo;
      }

      final validos = stats.entries.where((e) => (e.value['total'] ?? 0) > 0);
      if (validos.isEmpty) {
        return 'Aun no tengo datos de horario para recomendarte una franja ideal. Completa algunas practicas en distintos momentos del dia.';
      }

      final ordenados = validos.toList()
        ..sort((a, b) {
          final ta = a.value['total'] ?? 0;
          final tb = b.value['total'] ?? 0;
          final aa = ta > 0 ? ((a.value['correctas'] ?? 0) * 100 / ta) : 0;
          final ab = tb > 0 ? ((b.value['correctas'] ?? 0) * 100 / tb) : 0;
          if (aa != ab) return ab.compareTo(aa);
          return tb.compareTo(ta);
        });

      final mejor = ordenados.first;
      final mejorTotal = mejor.value['total'] ?? 0;
      final mejorAcierto = mejorTotal > 0
          ? ((mejor.value['correctas'] ?? 0) * 100 / mejorTotal)
          : 0;
      final mejorTiempo = mejorTotal > 0
          ? (mejor.value['tiempo'] ?? 0) / mejorTotal
          : 0;

      final detalle = <String>[];
      for (final key in const ['manana', 'tarde', 'noche']) {
        final bucket = stats[key]!;
        final total = bucket['total'] ?? 0;
        if (total <= 0) continue;
        final acierto = ((bucket['correctas'] ?? 0) * 100) / total;
        final tiempo = (bucket['tiempo'] ?? 0) / total;
        detalle.add(
          '${_descripcionMomento(key)}: ${acierto.toStringAsFixed(1)}% en ${total.toStringAsFixed(0)} respuestas (${tiempo.toStringAsFixed(1)} seg/preg).',
        );
      }

      return 'Tu mejor horario actual es ${_descripcionMomento(mejor.key)} con ${mejorAcierto.toStringAsFixed(1)}% de acierto y ${mejorTiempo.toStringAsFixed(1)} seg/preg. Resumen por franja: ${detalle.join(' ')}';
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolverConsultaAnalisisVelocidad({
    required String? userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return 'Para analizar tu velocidad necesito tu sesion activa. Cierra sesion, vuelve a ingresar y consultame de nuevo.';
    }

    try {
      final List<dynamic> raw = await _supabase
          .from('respuesta_usuario')
          .select('tiempo_total_respuesta, es_correcta, fue_omitida')
          .eq('usuario_id', userId!)
          .order('respondida_at', ascending: false)
          .limit(300);

      final rows = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((r) => r['fue_omitida'] != true && r['es_correcta'] is bool)
          .toList();
      if (rows.isEmpty) {
        return 'Aun no tengo suficientes respuestas para analizar tu velocidad.';
      }

      final tiempos = rows
          .map((r) => _toDouble(r['tiempo_total_respuesta']) ?? 0.0)
          .where((t) => t > 0)
          .toList();
      if (tiempos.isEmpty) {
        return 'Aun no tengo tiempos validos para evaluar velocidad.';
      }

      final promedio = _promedio(tiempos);
      final impulsivas = rows.where((r) {
        final t = _toDouble(r['tiempo_total_respuesta']) ?? 0.0;
        return t > 0 && t < 5;
      }).toList();
      final lentas = rows.where((r) {
        final t = _toDouble(r['tiempo_total_respuesta']) ?? 0.0;
        return t > 30;
      }).toList();
      final control = rows.where((r) {
        final t = _toDouble(r['tiempo_total_respuesta']) ?? 0.0;
        return t >= 8 && t <= 20;
      }).toList();

      final pctImpulsiva = impulsivas.length * 100.0 / rows.length;
      final pctLenta = lentas.length * 100.0 / rows.length;
      final errorImp = impulsivas.isEmpty
          ? 0.0
          : (impulsivas.where((r) => r['es_correcta'] == false).length *
                    100.0) /
                impulsivas.length;
      final errorControl = control.isEmpty
          ? 0.0
          : (control.where((r) => r['es_correcta'] == false).length * 100.0) /
                control.length;

      String diagnostico;
      String recomendacion;
      if (pctImpulsiva >= 20) {
        diagnostico =
            'Velocidad alta con impulsividad marcada (${pctImpulsiva.toStringAsFixed(1)}% en <5s).';
        recomendacion =
            'Baja el ritmo: apunta a 8-15 segundos por pregunta y relee palabras clave antes de marcar.';
      } else if (promedio > 24) {
        diagnostico =
            'Vas mas lento de lo ideal (${promedio.toStringAsFixed(1)} seg/preg).';
        recomendacion =
            'Entrena bloques cronometrados para acercarte a 12-18 segundos manteniendo precision.';
      } else {
        diagnostico =
            'Tu velocidad esta en rango saludable (${promedio.toStringAsFixed(1)} seg/preg).';
        recomendacion =
            'Mantiene este ritmo y evita respuestas en menos de 5 segundos cuando la pregunta sea larga.';
      }

      return 'Analisis de velocidad: $diagnostico Tasa impulsiva: ${pctImpulsiva.toStringAsFixed(1)}%. Tasa lenta: ${pctLenta.toStringAsFixed(1)}%. Error en respuestas impulsivas: ${errorImp.toStringAsFixed(1)}% vs ${errorControl.toStringAsFixed(1)}% en rango 8-20s. Recomendacion: $recomendacion';
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolverConsultaAnalisisCognitivo({
    required String? userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return 'Para analizar tu perfil cognitivo necesito tu sesion activa. Cierra sesion, vuelve a ingresar y consultame de nuevo.';
    }

    try {
      final List<dynamic> raw = await _supabase
          .from('respuesta_usuario')
          .select(
            'numero_cambios_respuesta, veces_leyo_enunciado, confianza_usuario, '
            'momento_del_dia, es_correcta, fue_omitida, tiempo_total_respuesta',
          )
          .eq('usuario_id', userId!)
          .order('respondida_at', ascending: false)
          .limit(250);

      final rows = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((r) => r['fue_omitida'] != true && r['es_correcta'] is bool)
          .toList();
      if (rows.isEmpty) {
        return 'Aun no tengo datos suficientes para tu analisis cognitivo.';
      }

      final cambios = rows.map((r) => _toInt(r['numero_cambios_respuesta']));
      final relecturas = rows.map((r) => _toInt(r['veces_leyo_enunciado']));
      final confianzas = rows
          .map((r) => _toInt(r['confianza_usuario']))
          .where((v) => v > 0)
          .toList();

      final promedioCambios = cambios.isEmpty
          ? 0.0
          : cambios.reduce((a, b) => a + b) / cambios.length;
      final promedioRelecturas = relecturas.isEmpty
          ? 0.0
          : relecturas.reduce((a, b) => a + b) / relecturas.length;
      final promedioConfianza = confianzas.isEmpty
          ? 0.0
          : confianzas.reduce((a, b) => a + b) / confianzas.length;

      String perfil;
      if (promedioCambios > 2.0) {
        perfil = 'DUBITATIVO';
      } else if (promedioRelecturas > 2.4) {
        perfil = 'REFLEXIVO';
      } else if (promedioCambios < 0.7 && promedioRelecturas <= 1.3) {
        perfil = 'RAPIDO';
      } else {
        perfil = 'EQUILIBRADO';
      }

      final recomendacionHorario = await _resolverConsultaHorarioEstudio(
        userId: userId,
      );

      final consejo = promedioRelecturas > 2.4
          ? 'Confia mas en la primera lectura y evita releer en exceso cuando el enunciado ya esta claro.'
          : (promedioCambios > 2.0
                ? 'Reduce cambios de alternativa: decide una regla de descarte y confirma solo una vez.'
                : 'Tu patron cognitivo esta estable; enfocate en constancia diaria.');

      return 'Perfil cognitivo: $perfil. Cambios promedio: ${promedioCambios.toStringAsFixed(2)}. Relecturas promedio: ${promedioRelecturas.toStringAsFixed(2)}. Confianza promedio: ${promedioConfianza.toStringAsFixed(2)}/5. Consejo: $consejo ${recomendacionHorario ?? ''}';
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolverConsultaAnalisisSesion({
    required String? userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return 'Para analizar tu sesion necesito tu sesion activa. Cierra sesion, vuelve a ingresar y consultame de nuevo.';
    }

    try {
      final List<dynamic> rawSesiones = await _supabase
          .from('sesion_practica')
          .select(
            'id, nombre_sesion, tipo_sesion, completada, estado, '
            'preguntas_correctas, preguntas_incorrectas, preguntas_omitidas, preguntas_respondidas, '
            'fecha_inicio, fecha_fin',
          )
          .eq('usuario_id', userId!)
          .order('fecha_inicio', ascending: false)
          .limit(10);

      final sesiones = rawSesiones
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((s) => s['completada'] == true || s['estado'] == 'completada')
          .toList();
      if (sesiones.isEmpty) {
        return 'No encuentro sesiones completadas para analizar.';
      }

      final actual = sesiones.first;
      final idSesion = (actual['id'] ?? '').toString();
      if (idSesion.isEmpty) return 'No pude identificar la sesion a analizar.';

      int respondidasSesion(Map<String, dynamic> s) {
        final guardado = _toInt(s['preguntas_respondidas']);
        if (guardado > 0) return guardado;
        return _toInt(s['preguntas_correctas']) +
            _toInt(s['preguntas_incorrectas']) +
            _toInt(s['preguntas_omitidas']);
      }

      final respondidasActual = respondidasSesion(actual);
      final correctasActual = _toInt(actual['preguntas_correctas']);
      final tasaActual = respondidasActual > 0
          ? (correctasActual * 100.0) / respondidasActual
          : 0.0;

      final previas = sesiones.skip(1).take(4).toList();
      double promedioPrevio = 0.0;
      if (previas.isNotEmpty) {
        final tasas = previas.map((s) {
          final r = respondidasSesion(s);
          final c = _toInt(s['preguntas_correctas']);
          return r > 0 ? (c * 100.0) / r : 0.0;
        }).toList();
        promedioPrevio = tasas.reduce((a, b) => a + b) / tasas.length;
      }
      final delta = tasaActual - promedioPrevio;

      final List<dynamic> rawRespuestas = await _supabase
          .from('respuesta_usuario')
          .select(
            'es_correcta, fue_omitida, pregunta:pregunta_id(materia:materia_id(nombre))',
          )
          .eq('sesion_id', idSesion)
          .limit(500);

      final fallosPorMateria = <String, int>{};
      for (final item in rawRespuestas) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        if (row['fue_omitida'] == true || row['es_correcta'] != false) continue;
        final pregunta = _asMap(row['pregunta']);
        final materia = _asMap(pregunta['materia']);
        final nombre = (materia['nombre'] ?? 'Materia').toString();
        fallosPorMateria[nombre] = (fallosPorMateria[nombre] ?? 0) + 1;
      }
      final materiaCritica = fallosPorMateria.entries.isEmpty
          ? 'Sin materia critica detectada'
          : (fallosPorMateria.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .first;

      final tendenciaTxt = previas.isEmpty
          ? 'Aun no hay suficiente historial para comparar con sesiones previas.'
          : (delta >= 0
                ? 'Mejoraste ${delta.toStringAsFixed(1)} puntos frente a tus sesiones previas.'
                : 'Bajaste ${delta.abs().toStringAsFixed(1)} puntos frente a tus sesiones previas.');

      final nombreSesion =
          (actual['nombre_sesion'] ?? actual['tipo_sesion'] ?? 'Sesion')
              .toString();
      final incorrectas = _toInt(actual['preguntas_incorrectas']);
      final omitidas = _toInt(actual['preguntas_omitidas']);

      final parteMateria = materiaCritica is MapEntry<String, int>
          ? 'Materia con mayor error: ${materiaCritica.key} (${materiaCritica.value} fallos).'
          : '$materiaCritica.';

      return 'Analisis post-sesion ($nombreSesion): $correctasActual/$respondidasActual correctas (${tasaActual.toStringAsFixed(1)}%). Incorrectas: $incorrectas, omitidas: $omitidas. $tendenciaTxt $parteMateria';
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolverConsultaPatronesError({
    required String? userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return 'Para detectar tus patrones de error necesito tu sesion activa. Cierra sesion, vuelve a ingresar y consultame de nuevo.';
    }

    try {
      final List<dynamic> rawPatrones = await _supabase
          .from('patron_error_detallado')
          .select(
            'tipo_patron, severidad, veces_detectado, '
            'puntos_perdidos_estimados, tendencia, estrategia_correccion, patron_corregido',
          )
          .eq('usuario_id', userId!)
          .eq('patron_corregido', false)
          .limit(8);

      final patrones = rawPatrones
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (patrones.isNotEmpty) {
        int severidadScore(String s) {
          final t = _normalizarTexto(s);
          if (t.contains('grave') || t.contains('critico')) return 3;
          if (t.contains('moderado')) return 2;
          return 1;
        }

        patrones.sort((a, b) {
          final sa = severidadScore((a['severidad'] ?? '').toString());
          final sb = severidadScore((b['severidad'] ?? '').toString());
          if (sa != sb) return sb.compareTo(sa);
          return _toInt(
            b['veces_detectado'],
          ).compareTo(_toInt(a['veces_detectado']));
        });

        final top = patrones
            .take(3)
            .map((p) {
              final tipo = (p['tipo_patron'] ?? 'patron').toString();
              final sev = (p['severidad'] ?? 'sin_severidad').toString();
              final veces = _toInt(p['veces_detectado']);
              final perdida = (_toDouble(p['puntos_perdidos_estimados']) ?? 0)
                  .toStringAsFixed(1);
              return '$tipo (sev $sev, $veces veces, -$perdida pts)';
            })
            .join('; ');

        final estrategia = (patrones.first['estrategia_correccion'] ?? '')
            .toString()
            .trim();
        final estrategiaTxt = estrategia.isEmpty
            ? ''
            : ' Estrategia principal: $estrategia';

        return 'Patrones de error activos: $top.$estrategiaTxt';
      }

      final List<dynamic> rawRespuestas = await _supabase
          .from('respuesta_usuario')
          .select(
            'tiempo_total_respuesta, numero_cambios_respuesta, es_correcta, fue_omitida, tipo_error',
          )
          .eq('usuario_id', userId)
          .order('respondida_at', ascending: false)
          .limit(300);

      final conteo = <String, int>{};
      for (final item in rawRespuestas) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        if (row['fue_omitida'] == true || row['es_correcta'] != false) continue;
        var tipo = (row['tipo_error'] ?? '').toString().trim();
        if (tipo.isEmpty) {
          final tiempo = _toDouble(row['tiempo_total_respuesta']) ?? 0;
          final cambios = _toInt(row['numero_cambios_respuesta']);
          if (tiempo > 0 && tiempo < 5) {
            tipo = 'impulsividad';
          } else if (cambios > 2) {
            tipo = 'confusion_opciones';
          } else if (tiempo > 60 && cambios <= 1) {
            tipo = 'desconocimiento';
          } else {
            tipo = 'error_lectura';
          }
        }
        conteo[tipo] = (conteo[tipo] ?? 0) + 1;
      }

      if (conteo.isEmpty) {
        return 'No detecto patrones de error recurrentes en tu historial reciente.';
      }

      final total = conteo.values.fold<int>(0, (a, b) => a + b);
      final top = conteo.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final resumen = top
          .take(3)
          .map((e) {
            final pct = total > 0 ? (e.value * 100.0 / total) : 0;
            return '${e.key}: ${pct.toStringAsFixed(1)}%';
          })
          .join(', ');

      return 'Patrones detectados en tus errores recientes: $resumen. Recomendacion: baja impulsividad (<5s), limita cambios de alternativa y relee palabras clave como NO/EXCEPTO/SALVO.';
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolverConsultaCoachMemoria({
    required String? userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return 'Para activar tu coach de memoria necesito tu sesion activa. Cierra sesion, vuelve a ingresar y consultame de nuevo.';
    }

    try {
      final data = await obtenerCoachMemoriaDetalle(userId: userId!);
      final estado = (data['estado'] ?? '').toString().trim().toLowerCase();
      if (estado == 'sin_datos') {
        return 'Aun no tengo historial suficiente para tu coach de memoria. Resuelve una practica y vuelvo a calcularlo.';
      }
      if (estado == 'error') {
        return (data['resumen'] ??
                'No pude calcular tu coach de memoria ahora.')
            .toString()
            .trim();
      }

      final indice = _toDouble(data['indice_memoria']) ?? 0.0;
      final interpretacion = (data['interpretacion_indice'] ?? '')
          .toString()
          .trim();
      final plan = _asMap(data['plan_diario']);
      final riesgos = data['riesgos'] is List
          ? (data['riesgos'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];
      final criticas = data['preguntas_criticas'] is List
          ? (data['preguntas_criticas'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];
      final repeticion = _asMap(data['repeticion_fallidas']);
      final espaciada = _asMap(data['repeticion_espaciada']);
      final recordatorio = (data['recordatorio_repaso'] ?? '')
          .toString()
          .trim();

      final topMaterias = riesgos
          .take(3)
          .map((m) {
            final nombre = (m['materia'] ?? 'Materia').toString().trim();
            final tasa = _toDouble(m['tasa']) ?? 0.0;
            return '$nombre ${tasa.toStringAsFixed(1)}%';
          })
          .where((txt) => txt.trim().isNotEmpty)
          .join(', ');

      final criticasTxt = criticas
          .take(4)
          .map((q) => (q['etiqueta'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .join(', ');

      final ciclos = (espaciada['ciclos_dias'] is List)
          ? (espaciada['ciclos_dias'] as List).map((e) => '$e').join('-')
          : '1-3-7-15';

      final totalPendientes = _toInt(repeticion['total_pendientes']);
      final nuevas = _toInt(plan['nuevas']);
      final fallidas = _toInt(plan['fallidas']);
      final repaso = _toInt(plan['repaso']);
      final vencidas = _toInt(espaciada['total_vencidas']);

      return 'Indice de memoria: ${indice.toStringAsFixed(1)}% ($interpretacion). '
          'Plan de hoy: $nuevas nuevas, $fallidas fallidas y $repaso de repaso. '
          'Repeticion inmediata de falladas (10-20 preguntas): pendientes $totalPendientes. '
          'Repeticion espaciada activa ($ciclos dias), vencidas: $vencidas. '
          '${recordatorio.isEmpty ? '' : '$recordatorio '}'
          '${topMaterias.isEmpty ? '' : 'Materias con mas riesgo: $topMaterias. '}'
          '${criticasTxt.isEmpty ? '' : 'Preguntas criticas: $criticasTxt.'}';
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolverConsultaPrediccionOlvido({
    required String? userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return 'Para predecir olvido necesito tu sesion activa. Cierra sesion, vuelve a ingresar y consultame de nuevo.';
    }

    try {
      final List<dynamic> raw = await _supabase
          .from('prediccion_olvido')
          .select(
            'probabilidad_olvido, urgencia_revision, fecha_revision_optima, requiere_revision_inmediata, '
            'pregunta:pregunta_id(codigo_pregunta, materia:materia_id(nombre))',
          )
          .eq('usuario_id', userId!)
          .gte('probabilidad_olvido', 70)
          .order('probabilidad_olvido', ascending: false)
          .limit(30);

      final rows = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (rows.isEmpty) {
        return 'No hay alertas de olvido alto (>70%) en este momento.';
      }

      final urgentes = rows.where((r) {
        final urg = _normalizarTexto((r['urgencia_revision'] ?? '').toString());
        return r['requiere_revision_inmediata'] == true ||
            urg.contains('alta') ||
            urg.contains('critica');
      }).length;

      final porMateria = <String, int>{};
      DateTime? proximaRevision;
      for (final r in rows) {
        final pregunta = _asMap(r['pregunta']);
        final materia = _asMap(pregunta['materia']);
        final nombre = (materia['nombre'] ?? 'Materia').toString();
        porMateria[nombre] = (porMateria[nombre] ?? 0) + 1;

        final fecha = _parseFechaFlexible(r['fecha_revision_optima']);
        if (fecha != null &&
            (proximaRevision == null || fecha.isBefore(proximaRevision))) {
          proximaRevision = fecha;
        }
      }

      final topMaterias = porMateria.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final materiasTxt = topMaterias
          .take(3)
          .map((e) => '${e.key} (${e.value})')
          .join(', ');
      final fechaTxt = proximaRevision == null
          ? 'sin fecha exacta'
          : _formatearFecha(proximaRevision);

      return 'Prediccion de olvido: ${rows.length} preguntas con riesgo alto, de las cuales $urgentes son urgentes. Materias mas expuestas: $materiasTxt. Proxima revision recomendada: $fechaTxt.';
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolverConsultaMotivacion({required String? userId}) async {
    if (_sesionInvalida(userId)) {
      return 'Sigue avanzando. Inicia sesion para recibir un mensaje motivacional personalizado con tus datos reales.';
    }

    final params = <String, dynamic>{'p_usuario_id': userId!};
    final progreso = await _rpcComoMapa(
      functionName: 'fn_calcular_progreso_dinamico',
      params: params,
    );
    if (progreso == null) return null;

    final perfilBasico = await _obtenerPerfilUsuarioBasico(userId);
    final categoriaUsuario = (perfilBasico['categoria'] ?? '')
        .toString()
        .trim();
    final proyeccion = await obtenerProyeccionTiempoDetalle(
      userId: userId,
      categoriaUsuario: categoriaUsuario.isEmpty ? null : categoriaUsuario,
      progresoBase: progreso,
      perfilBase: perfilBasico,
    );

    final dominadas = _toInt(
      proyeccion['preguntas_dominadas'] ?? progreso['preguntas_dominadas'],
    );
    final diasTranscurridos = _toInt(progreso['dias_transcurridos']);
    final ritmoActual =
        _toDouble(proyeccion['ritmo_actual_dia']) ??
        _toDouble(progreso['ritmo_actual_dia']) ??
        0;
    final ritmoNecesario =
        _toDouble(proyeccion['ritmo_necesario_dia']) ??
        _toDouble(progreso['ritmo_necesario_dia']) ??
        0;
    final porcentaje =
        _toDouble(proyeccion['porcentaje_completado']) ??
        _toDouble(progreso['porcentaje_completado']) ??
        0;
    final probAprobacion = _toDouble(proyeccion['probabilidad_aprobacion']);
    final semaforo = (proyeccion['semaforo_avance'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    late final String mensaje;
    if (semaforo == 'completado' || semaforo == 'en_ritmo') {
      mensaje =
          'Excelente trabajo: vas adelantado con $dominadas preguntas dominadas en $diasTranscurridos dias (${porcentaje.toStringAsFixed(1)}%). Manteniendo este ritmo, llegaras con margen para repasar.';
    } else if (semaforo == 'atrasado') {
      final objetivo = ritmoNecesario > 0
          ? ritmoNecesario.toStringAsFixed(1)
          : 'tu objetivo';
      mensaje =
          'Es momento de acelerar: hoy vas en ${ritmoActual.toStringAsFixed(1)}/dia y necesitas $objetivo/dia para llegar comodo. Empieza con un bloque corto ahora y cierra el dia cumpliendo tu meta.';
    } else {
      mensaje =
          'Vas construyendo buen ritmo: $dominadas dominadas (${porcentaje.toStringAsFixed(1)}%). La clave ahora es consistencia diaria sin romper la cadena.';
    }

    final mensajeFinal = probAprobacion == null
        ? mensaje
        : '$mensaje Probabilidad estimada de aprobacion actual: ${probAprobacion.toStringAsFixed(1)}%.';

    try {
      await _supabase.from('mensaje_ia').insert({
        'usuario_id': userId,
        'tipo_mensaje': 'motivacion',
        'categoria': 'coaching',
        'titulo': 'Mensaje del Tutor IA',
        'contenido': mensajeFinal,
        'prioridad': 'normal',
      });
    } catch (_) {
      // La motivacion debe devolverse aunque la insercion falle.
    }

    return mensajeFinal;
  }

  Future<Map<String, dynamic>?> _rpcComoMapa({
    required String functionName,
    required Map<String, dynamic> params,
  }) async {
    try {
      final raw = await _supabase.rpc(functionName, params: params);
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      if (raw is List && raw.isNotEmpty) {
        final first = raw.first;
        if (first is Map<String, dynamic>) return first;
        if (first is Map) return Map<String, dynamic>.from(first);
      }
      return null;
    } catch (e) {
      debugPrint('TutorIA._rpcComoMapa($functionName) error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _obtenerPlanAdaptativoSeguro({
    required String userId,
    Map<String, dynamic>? planBase,
  }) async {
    if (planBase != null && planBase.isNotEmpty) {
      return planBase;
    }

    final paramsBase = <String, dynamic>{'p_usuario_id': userId};

    final planAdaptativo = await _rpcComoMapa(
      functionName: 'fn_generar_plan_adaptativo',
      params: paramsBase,
    );
    if (planAdaptativo != null && planAdaptativo.isNotEmpty) {
      return planAdaptativo;
    }

    // Compatibilidad con instalaciones que aun no tienen la funcion adaptativa.
    final planLegacy = await _rpcComoMapa(
      functionName: 'fn_generar_plan_dia_siguiente',
      params: {'p_usuario_id': userId, 'p_dia_numero': 0},
    );
    if (planLegacy != null && planLegacy.isNotEmpty) {
      return planLegacy;
    }

    final planLegacyDia1 = await _rpcComoMapa(
      functionName: 'fn_generar_plan_dia_siguiente',
      params: {'p_usuario_id': userId, 'p_dia_numero': 1},
    );
    if (planLegacyDia1 != null && planLegacyDia1.isNotEmpty) {
      return planLegacyDia1;
    }

    return null;
  }

  List<String> _mergeIdsPreservandoOrden(List<List<String>> grupos) {
    final salida = <String>[];
    final vistos = <String>{};
    for (final grupo in grupos) {
      for (final raw in grupo) {
        final id = raw.trim();
        if (id.isEmpty) continue;
        if (vistos.add(id)) {
          salida.add(id);
        }
      }
    }
    return salida;
  }

  bool _esConsultaRanking(String mensaje) {
    final normalizado = _normalizarTexto(mensaje)
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalizado.isEmpty) return false;

    const claves = <String>[
      'ranking',
      'puesto',
      'posicion',
      'lugar',
      'clasificacion',
      'tabla',
      'top',
    ];
    for (final clave in claves) {
      if (normalizado.contains(clave)) return true;
    }

    const patrones = <String>[
      'en que puesto',
      'que puesto',
      'mi puesto',
      'mi posicion',
      'que lugar',
      'donde voy',
    ];
    for (final p in patrones) {
      if (normalizado.contains(p)) return true;
    }

    return false;
  }

  Future<String?> _resolverCategoriaUsuario({
    required String userId,
    required Map<String, dynamic> contexto,
  }) async {
    final fromCtx = _extraerCategoriaDesdeMapa(contexto);
    if (fromCtx != null && fromCtx.isNotEmpty) return fromCtx;

    try {
      final usuario =
          await _supabase
              .from('usuario')
              .select('metadata')
              .eq('id', userId)
              .maybeSingle() ??
          <String, dynamic>{};
      final metadata = _asMap(usuario['metadata']);
      return _extraerCategoriaDesdeMapa(metadata);
    } catch (_) {
      return null;
    }
  }

  String? _extraerCategoriaDesdeMapa(Map<String, dynamic> data) {
    final directos = [
      data['categoria_usuario'],
      data['categoria'],
      data['category'],
    ];
    for (final item in directos) {
      final txt = item?.toString().trim();
      if (txt != null && txt.isNotEmpty) return txt;
    }

    final nested = _asMap(data['contexto_bd_usuario']);
    if (nested.isNotEmpty) {
      final txt = nested['categoria_usuario']?.toString().trim();
      if (txt != null && txt.isNotEmpty) return txt;
    }

    return null;
  }

  Future<Map<String, dynamic>?> _obtenerResumenRankingUsuario({
    required String userId,
    required String? categoriaUsuario,
  }) async {
    final resultados = await Future.wait<Map<String, dynamic>?>([
      _obtenerFilaRankingUsuario(
        userId: userId,
        categoriaUsuario: categoriaUsuario,
        modo: 'semana',
        criterio: 'promedio',
      ),
      _obtenerFilaRankingUsuario(
        userId: userId,
        categoriaUsuario: categoriaUsuario,
        modo: 'todas',
        criterio: 'puntaje_maximo',
      ),
    ]);
    final semanal = resultados[0];
    final historico = resultados[1];

    if (semanal == null && historico == null) return null;
    return {
      'semanal': semanal ?? const <String, dynamic>{},
      'historico': historico ?? const <String, dynamic>{},
    };
  }

  Future<Map<String, dynamic>?> _obtenerFilaRankingUsuario({
    required String userId,
    required String? categoriaUsuario,
    required String modo,
    required String criterio,
  }) async {
    if (modo == 'todas' && criterio == 'puntaje_maximo') {
      try {
        final rawFast = await _supabase.rpc(
          'obtener_ranking_mejor_puntaje',
          params: {'p_categoria': categoriaUsuario, 'p_limite': 5000},
        );

        if (rawFast is List) {
          final rowsFast = rawFast
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          final totalFast = rowsFast.length;
          final rowFast = rowsFast.firstWhere(
            (r) => (r['usuario_id'] ?? r['id'])?.toString() == userId,
            orElse: () => const <String, dynamic>{},
          );

          final enRankingFast = rowFast.isNotEmpty;
          return {
            'en_ranking': enRankingFast,
            'total_usuarios': totalFast,
            'modo': modo,
            'criterio': criterio,
            if (enRankingFast) ...{
              'posicion': _toInt(rowFast['posicion']),
              'puntos_promedio': _toDouble(rowFast['puntos_promedio']) ?? 0.0,
              'puntaje_maximo': _toInt(rowFast['puntaje_maximo']),
              'efectividad': _toDouble(rowFast['efectividad']) ?? 0.0,
              'practicas_para_ranking': _toInt(
                rowFast['practicas_para_ranking'],
              ),
            },
          };
        }
      } catch (_) {
        // Si aun no existe la RPC fast, usamos ruta estandar.
      }
    }

    final params = <String, dynamic>{
      'p_categoria': categoriaUsuario,
      'p_modo': modo,
      'p_limite': 5000,
      'p_criterio': criterio,
    };

    try {
      dynamic raw;
      try {
        raw = await _supabase.rpc('obtener_ranking_periodo', params: params);
      } catch (_) {
        final legacy = Map<String, dynamic>.from(params)..remove('p_criterio');
        raw = await _supabase.rpc('obtener_ranking_periodo', params: legacy);
      }

      if (raw is! List) {
        return {
          'en_ranking': false,
          'total_usuarios': 0,
          'modo': modo,
          'criterio': criterio,
        };
      }

      final rows = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final total = rows.length;
      final row = rows.firstWhere(
        (r) => (r['usuario_id'] ?? r['id'])?.toString() == userId,
        orElse: () => const <String, dynamic>{},
      );

      final enRanking = row.isNotEmpty;
      return {
        'en_ranking': enRanking,
        'total_usuarios': total,
        'modo': modo,
        'criterio': criterio,
        if (enRanking) ...{
          'posicion': _toInt(row['posicion']),
          'puntos_promedio': _toDouble(row['puntos_promedio']) ?? 0.0,
          'puntaje_maximo': _toInt(row['puntaje_maximo']),
          'efectividad': _toDouble(row['efectividad']) ?? 0.0,
          'practicas_para_ranking': _toInt(row['practicas_para_ranking']),
        },
      };
    } catch (_) {
      return null;
    }
  }

  String _formatearBloqueRanking({
    required String etiqueta,
    required Map<String, dynamic> info,
    required bool usarMaximoComoPrincipal,
  }) {
    if (info.isEmpty) {
      return '$etiqueta: no disponible ahora.';
    }

    final enRanking = info['en_ranking'] == true;
    final total = _toInt(info['total_usuarios']);
    if (!enRanking) {
      if (total <= 0) {
        return '$etiqueta: aun no hay datos para mostrar ranking.';
      }
      return '$etiqueta: aun no figuras en ranking. Necesitas practicas validas (100 preguntas completadas con todas las materias).';
    }

    final posicion = _toInt(info['posicion']);
    final promedio = _toDouble(info['puntos_promedio']) ?? 0.0;
    final maximo = _toInt(info['puntaje_maximo']);
    final efectividad = _toDouble(info['efectividad']) ?? 0.0;
    final practicas = _toInt(info['practicas_para_ranking']);

    if (usarMaximoComoPrincipal) {
      return '$etiqueta: puesto $posicion de $total. Maximo $maximo, promedio ${promedio.toStringAsFixed(2)} y efectividad ${efectividad.toStringAsFixed(2)}%.';
    }

    return '$etiqueta: puesto $posicion de $total. Promedio ${promedio.toStringAsFixed(2)}, maximo $maximo, efectividad ${efectividad.toStringAsFixed(2)}% y $practicas practicas validas.';
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  // ignore: unused_element
  Future<Map<String, dynamic>> _contextoUsuarioChatDesdeBD(
    String? userId,
  ) async {
    if (userId == null || userId.isEmpty || userId == 'user_test_id') {
      return const <String, dynamic>{};
    }

    try {
      final usuario =
          await _supabase
              .from('usuario')
              .select('nombre_completo, metadata')
              .eq('id', userId)
              .maybeSingle() ??
          <String, dynamic>{};
      final metadata = _asMap(usuario['metadata']);
      final categoriaUsuario = _extraerCategoriaDesdeMapa(metadata);

      final perfil =
          await _supabase
              .from('perfil_usuario')
              .select(
                'tasa_acierto_global, velocidad_promedio_segundos, dias_consecutivos_estudio',
              )
              .eq('usuario_id', userId)
              .maybeSingle() ??
          <String, dynamic>{};

      final estadistica =
          await _supabase
              .from('estadistica_usuario')
              .select('tiempo_total_estudio_minutos')
              .eq('usuario_id', userId)
              .maybeSingle() ??
          <String, dynamic>{};

      final List<dynamic> dominiosRaw = await _supabase
          .from('dominio_materia')
          .select('tasa_dominio, materia:materia_id(nombre)')
          .eq('usuario_id', userId);

      final dominios = dominiosRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final analisis = dominios.map((d) {
        final materiaMap = d['materia'] is Map
            ? Map<String, dynamic>.from(d['materia'])
            : {};
        final nombre = (materiaMap['nombre'] ?? 'Materia').toString();
        final tasa = _toDouble(d['tasa_dominio']) ?? 0.0;
        return {'materia': nombre, 'tasa': tasa};
      }).toList();

      analisis.sort((a, b) {
        final aa = _toDouble(a['tasa']) ?? 0.0;
        final bb = _toDouble(b['tasa']) ?? 0.0;
        return bb.compareTo(aa);
      });

      final fortalezas = analisis
          .where((m) => (_toDouble(m['tasa']) ?? 0) >= 75)
          .take(3)
          .toList();
      final debilidades = [
        ...analisis.reversed,
      ].where((m) => (_toDouble(m['tasa']) ?? 100) < 65).take(3).toList();

      final List<dynamic> respuestasRaw = await _supabase
          .from('respuesta_usuario')
          .select('es_correcta, fue_omitida')
          .eq('usuario_id', userId)
          .order('respondida_at', ascending: false)
          .limit(50);

      final respuestas = respuestasRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final validas = respuestas.where((r) {
        final esCorrecta = r['es_correcta'];
        return r['fue_omitida'] != true && esCorrecta is bool;
      }).toList();

      final correctas = validas.where((r) => r['es_correcta'] == true).length;
      final incorrectas = validas
          .where((r) => r['es_correcta'] == false)
          .length;
      final total = validas.length;
      final efectividadReciente = total > 0 ? (correctas * 100.0) / total : 0.0;
      final ranking = await _obtenerResumenRankingUsuario(
        userId: userId,
        categoriaUsuario: categoriaUsuario,
      );

      return {
        'usuario_id': userId,
        if (categoriaUsuario != null && categoriaUsuario.isNotEmpty)
          'categoria_usuario': categoriaUsuario,
        if ((usuario['nombre_completo'] ?? '').toString().trim().isNotEmpty)
          'nombre_completo': usuario['nombre_completo'].toString().trim(),
        'resumen_global': {
          'tasa_acierto_global':
              _toDouble(perfil['tasa_acierto_global']) ?? 0.0,
          'velocidad_promedio_segundos':
              _toDouble(perfil['velocidad_promedio_segundos']) ?? 0.0,
          'racha_dias': _toInt(perfil['dias_consecutivos_estudio']),
          'tiempo_total_estudio_minutos': _toInt(
            estadistica['tiempo_total_estudio_minutos'],
          ),
        },
        'rendimiento_reciente': {
          'total_preguntas': total,
          'correctas': correctas,
          'incorrectas': incorrectas,
          'efectividad_pct': double.parse(
            efectividadReciente.toStringAsFixed(2),
          ),
        },
        if (ranking != null) 'ranking_usuario': ranking,
        'fortalezas_materia': fortalezas,
        'debilidades_materia': debilidades,
      };
    } catch (e) {
      return {'contexto_bd_error': _resumirTextoError(e.toString(), max: 140)};
    }
  }

  Future<FunctionResponse> _invocarTutorConReintento401({
    required String prompt,
    String? userId,
    String mode = 'chat',
    bool usarContextoBd = true,
  }) async {
    final body = <String, dynamic>{
      'prompt': prompt,
      'mode': mode,
      'usar_contexto_bd': usarContextoBd,
      if (userId != null && userId.isNotEmpty) 'user_id': userId,
    };
    try {
      return await _supabase.functions.invoke('ia_diagnostico', body: body);
    } on FunctionException catch (e) {
      if (e.status != 401) rethrow;

      // Si la sesion expiro, intentamos refrescar y reintentamos 1 vez.
      try {
        await _supabase.auth.refreshSession();
        return await _supabase.functions.invoke('ia_diagnostico', body: body);
      } on FunctionException catch (e2) {
        if (e2.status != 401) rethrow;
        // Si el JWT del usuario sigue invalido, forzamos fallback anon.
        return _invocarTutorConAnon(prompt: prompt, mode: mode);
      } catch (_) {
        // Si no se pudo refrescar sesion, intentamos con anon.
        return _invocarTutorConAnon(prompt: prompt, mode: mode);
      }
    }
  }

  Future<void> _guardarEstadoTutorUsuario({
    required String? userId,
    required Map<String, dynamic> contexto,
    required String ultimoMensaje,
  }) async {
    if (!SupabaseService.isInitialized) return;
    if (userId == null || userId.isEmpty || userId == 'user_test_id') return;

    final estadoParcial = _construirEstadoTutorParcial(
      contexto: contexto,
      ultimoMensaje: ultimoMensaje,
    );
    if (estadoParcial.isEmpty) return;

    try {
      await _supabase.rpc(
        'fn_upsert_ia_tutor_estado_usuario',
        params: {
          'p_estado_parcial': estadoParcial,
          'p_fuente': 'app',
          'p_version': 1,
        },
      );
    } catch (e) {
      debugPrint('TutorIA: no se pudo guardar estado tutor JSON: $e');
    }
  }

  Map<String, dynamic> _construirEstadoTutorParcial({
    required Map<String, dynamic> contexto,
    required String ultimoMensaje,
  }) {
    final contextoBd = _asMap(contexto['contexto_bd_usuario']);

    final plan = _asMap(
      contexto['plan'] ??
          contexto['plan_hoy'] ??
          contexto['plan_diario'] ??
          contextoBd['plan_hoy'] ??
          contextoBd['plan'],
    );
    final progreso = _asMap(
      contexto['progreso'] ??
          contexto['resumen_global'] ??
          contexto['rendimiento_reciente'] ??
          contextoBd['resumen_global'] ??
          contextoBd['rendimiento_reciente'],
    );
    final diagnostico = _asMap(
      contexto['diagnostico'] ??
          contexto['panel_ia'] ??
          contexto['analisis'] ??
          contextoBd['diagnostico'],
    );
    final ranking = _asMap(
      contexto['ranking_usuario'] ??
          contexto['ranking'] ??
          contextoBd['ranking_usuario'],
    );

    final metadata = <String, dynamic>{
      'ultimo_mensaje': ultimoMensaje,
      'origen': 'chat_tutor',
      'updated_at_iso': DateTime.now().toIso8601String(),
    };

    return {
      if (plan.isNotEmpty) 'plan_dia': plan,
      if (progreso.isNotEmpty) 'progreso': progreso,
      if (diagnostico.isNotEmpty) 'diagnostico': diagnostico,
      if (ranking.isNotEmpty) 'ranking': ranking,
      'metadata': metadata,
    };
  }

  Future<FunctionResponse> _invocarTutorConAnon({
    required String prompt,
    String mode = 'chat',
  }) async {
    final anonKey = _supabase.auth.headers['apikey'];
    if (anonKey == null || anonKey.isEmpty) {
      throw FunctionException(
        status: 401,
        details: const {
          'code': '401',
          'message': 'No se pudo obtener ANON KEY para fallback',
        },
      );
    }

    final body = <String, dynamic>{
      'prompt': prompt,
      'mode': mode,
      // En fallback anonimo nunca enviamos user_id ni contexto personal.
      'usar_contexto_bd': false,
    };

    return await _supabase.functions.invoke(
      'ia_diagnostico',
      body: body,
      headers: {'Authorization': 'Bearer $anonKey', 'apikey': anonKey},
    );
  }

  Future<List<Map<String, dynamic>>> obtenerPreguntasQueBajanMateria({
    required String userId,
    required String materia,
    int limit = 10,
  }) async {
    if (!SupabaseService.isInitialized) return [];

    try {
      final List<dynamic> rows = await _supabase
          .from('respuesta_usuario')
          .select(
            'pregunta_id, es_correcta, fue_omitida, '
            'pregunta:pregunta_id(id, numero, texto, materia:materia_id(nombre))',
          )
          .eq('usuario_id', userId)
          .order('respondida_at', ascending: false)
          .limit(_ventanaRespuestasVelocidad);

      final objetivo = _normalizarTexto(materia);
      final Map<String, Map<String, dynamic>> agg = {};

      for (final raw in rows) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        if (row['fue_omitida'] == true) continue;
        final esCorrecta = row['es_correcta'];
        if (esCorrecta is! bool) continue;

        final pregunta = row['pregunta'];
        if (pregunta is! Map) continue;
        final preguntaMap = Map<String, dynamic>.from(pregunta);

        final materiaMap = preguntaMap['materia'];
        final nombreMateria =
            (materiaMap is Map && materiaMap['nombre'] != null)
            ? materiaMap['nombre'].toString()
            : '';

        if (!_materiaCoincide(nombreMateria, objetivo)) continue;

        final preguntaId = (row['pregunta_id'] ?? preguntaMap['id'])
            ?.toString();
        if (preguntaId == null || preguntaId.isEmpty) continue;

        final actual = agg.putIfAbsent(
          preguntaId,
          () => {
            'pregunta_id': preguntaId,
            'numero': _toInt(preguntaMap['numero']),
            'texto': (preguntaMap['texto'] ?? '').toString(),
            'materia': nombreMateria,
            'intentos': 0,
            'fallos': 0,
            'aciertos': 0,
          },
        );

        actual['intentos'] = _toInt(actual['intentos']) + 1;
        if (esCorrecta) {
          actual['aciertos'] = _toInt(actual['aciertos']) + 1;
        } else {
          actual['fallos'] = _toInt(actual['fallos']) + 1;
        }
      }

      final lista = agg.values
          .map((m) {
            final intentos = _toInt(m['intentos']);
            final fallos = _toInt(m['fallos']);
            final tasaError = intentos > 0 ? (fallos * 100.0) / intentos : 0.0;
            return {...m, 'tasa_error': tasaError};
          })
          .where((m) {
            final fallos = _toInt(m['fallos']);
            return fallos > 0;
          })
          .toList();

      lista.sort((a, b) {
        final fallosA = _toInt(a['fallos']);
        final fallosB = _toInt(b['fallos']);
        final byFallos = fallosB.compareTo(fallosA);
        if (byFallos != 0) return byFallos;

        final tasaA = _toDouble(a['tasa_error']) ?? 0;
        final tasaB = _toDouble(b['tasa_error']) ?? 0;
        return tasaB.compareTo(tasaA);
      });

      return lista.take(limit).toList();
    } catch (e) {
      debugPrint('Error obteniendo preguntas criticas por materia: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> obtenerPreguntasLentasPorMateria({
    required String userId,
    required String materia,
    int limit = 10,
  }) async {
    if (!SupabaseService.isInitialized) return [];
    final key = '${_cacheKeyMateria(userId, materia)}::$limit';

    final cache = _leerCacheListaMaterias(_cachePreguntasLentasMateria, key);
    if (cache != null) return cache.take(limit).toList();

    final enCurso = _inflightPreguntasLentasMateria[key];
    if (enCurso != null) {
      final lista = await enCurso;
      return _copiarListaMaps(lista).take(limit).toList();
    }

    final future = _obtenerPreguntasLentasPorMateriaCore(
      userId: userId.trim(),
      materia: materia,
      limit: limit,
    );
    _inflightPreguntasLentasMateria[key] = future;
    try {
      final lista = await future;
      _guardarCacheListaMaterias(_cachePreguntasLentasMateria, key, lista);
      return _copiarListaMaps(lista);
    } finally {
      _inflightPreguntasLentasMateria.remove(key);
    }
  }

  Future<List<Map<String, dynamic>>> _obtenerPreguntasLentasPorMateriaCore({
    required String userId,
    required String materia,
    int limit = 10,
  }) async {
    if (!SupabaseService.isInitialized) return [];

    try {
      final List<dynamic> rows = await _supabase
          .from('respuesta_usuario')
          .select(
            'pregunta_id, tiempo_total_respuesta, es_correcta, fue_omitida, '
            'pregunta:pregunta_id(id, numero_oficial, codigo_pregunta, enunciado, materia:materia_id(nombre))',
          )
          .eq('usuario_id', userId)
          .order('respondida_at', ascending: false)
          .limit(_ventanaRespuestasVelocidadDetalle);

      final objetivo = _normalizarTexto(materia);
      final Map<String, Map<String, dynamic>> agg = {};

      for (final raw in rows) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        if (row['fue_omitida'] == true) continue;

        final tiempo = _toDouble(row['tiempo_total_respuesta']) ?? 0.0;
        if (tiempo <= 0) continue;

        final esCorrecta = row['es_correcta'];
        if (esCorrecta is! bool) continue;

        final pregunta = row['pregunta'];
        if (pregunta is! Map) continue;
        final preguntaMap = Map<String, dynamic>.from(pregunta);
        final materiaMap = _asMap(preguntaMap['materia']);
        final nombreMateria = (materiaMap['nombre'] ?? '').toString().trim();
        if (!_materiaCoincide(nombreMateria, objetivo)) continue;

        final preguntaId = (row['pregunta_id'] ?? preguntaMap['id'])
            .toString()
            .trim();
        if (preguntaId.isEmpty) continue;

        final actual = agg.putIfAbsent(
          preguntaId,
          () => <String, dynamic>{
            'pregunta_id': preguntaId,
            'materia': nombreMateria,
            'numero': _toInt(preguntaMap['numero_oficial']),
            'codigo_pregunta': (preguntaMap['codigo_pregunta'] ?? '')
                .toString()
                .trim(),
            'texto': _resumirTextoError(
              (preguntaMap['enunciado'] ?? '').toString(),
              max: 130,
            ),
            'intentos': 0,
            'suma': 0.0,
            'correctas': 0,
            'incorrectas': 0,
          },
        );

        actual['intentos'] = _toInt(actual['intentos']) + 1;
        actual['suma'] = (_toDouble(actual['suma']) ?? 0.0) + tiempo;
        if (esCorrecta) {
          actual['correctas'] = _toInt(actual['correctas']) + 1;
        } else {
          actual['incorrectas'] = _toInt(actual['incorrectas']) + 1;
        }
      }

      final lista = agg.values
          .map((item) {
            final intentos = _toInt(item['intentos']);
            final suma = _toDouble(item['suma']) ?? 0.0;
            final promedio = intentos > 0 ? suma / intentos : 0.0;
            final incorrectas = _toInt(item['incorrectas']);
            final correctas = _toInt(item['correctas']);
            final tasaError = intentos > 0
                ? (incorrectas * 100.0) / intentos
                : 0.0;
            final tasaAcierto = intentos > 0
                ? (correctas * 100.0) / intentos
                : 0.0;

            return {
              ...item,
              'promedio_segundos': promedio,
              'total_segundos': suma,
              'tasa_error': tasaError,
              'tasa_acierto': tasaAcierto,
            };
          })
          .where((item) {
            final promedio = _toDouble(item['promedio_segundos']) ?? 0.0;
            final intentos = _toInt(item['intentos']);
            return promedio > 0 && intentos > 0;
          })
          .toList();

      lista.sort((a, b) {
        final promA = _toDouble(a['promedio_segundos']) ?? 0.0;
        final promB = _toDouble(b['promedio_segundos']) ?? 0.0;
        final byProm = promB.compareTo(promA);
        if (byProm != 0) return byProm;

        final intentosA = _toInt(a['intentos']);
        final intentosB = _toInt(b['intentos']);
        final byIntentos = intentosB.compareTo(intentosA);
        if (byIntentos != 0) return byIntentos;

        final errorA = _toDouble(a['tasa_error']) ?? 0.0;
        final errorB = _toDouble(b['tasa_error']) ?? 0.0;
        return errorB.compareTo(errorA);
      });

      return lista.take(limit).toList();
    } catch (e) {
      debugPrint('Error obteniendo preguntas lentas por materia: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> obtenerPreguntasImpulsivasPorMateria({
    required String userId,
    required String materia,
    int limit = 25,
  }) async {
    if (!SupabaseService.isInitialized) return [];
    final key = '${_cacheKeyMateria(userId, materia)}::$limit';

    final cache = _leerCacheListaMaterias(
      _cachePreguntasImpulsivasMateria,
      key,
    );
    if (cache != null) return cache.take(limit).toList();

    final enCurso = _inflightPreguntasImpulsivasMateria[key];
    if (enCurso != null) {
      final lista = await enCurso;
      return _copiarListaMaps(lista).take(limit).toList();
    }

    final future = _obtenerPreguntasImpulsivasPorMateriaCore(
      userId: userId.trim(),
      materia: materia,
      limit: limit,
    );
    _inflightPreguntasImpulsivasMateria[key] = future;
    try {
      final lista = await future;
      _guardarCacheListaMaterias(_cachePreguntasImpulsivasMateria, key, lista);
      return _copiarListaMaps(lista);
    } finally {
      _inflightPreguntasImpulsivasMateria.remove(key);
    }
  }

  Future<List<Map<String, dynamic>>> _obtenerPreguntasImpulsivasPorMateriaCore({
    required String userId,
    required String materia,
    int limit = 25,
  }) async {
    if (!SupabaseService.isInitialized) return [];

    try {
      final List<dynamic> rows = await _supabase
          .from('respuesta_usuario')
          .select(
            'pregunta_id, tiempo_total_respuesta, es_correcta, fue_omitida, '
            'pregunta:pregunta_id(id, numero_oficial, codigo_pregunta, enunciado, materia:materia_id(nombre))',
          )
          .eq('usuario_id', userId)
          .order('respondida_at', ascending: false)
          .limit(_ventanaRespuestasVelocidadDetalle);

      final objetivo = _normalizarTexto(materia);
      final Map<String, Map<String, dynamic>> agg = {};

      for (final raw in rows) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        if (row['fue_omitida'] == true) continue;

        final tiempo = _toDouble(row['tiempo_total_respuesta']) ?? 0.0;
        if (tiempo <= 0) continue;

        final esCorrecta = row['es_correcta'];
        if (esCorrecta is! bool) continue;

        final pregunta = row['pregunta'];
        if (pregunta is! Map) continue;
        final preguntaMap = Map<String, dynamic>.from(pregunta);
        final materiaMap = _asMap(preguntaMap['materia']);
        final nombreMateria = (materiaMap['nombre'] ?? '').toString().trim();
        if (!_materiaCoincide(nombreMateria, objetivo)) continue;

        final preguntaId = (row['pregunta_id'] ?? preguntaMap['id'])
            .toString()
            .trim();
        if (preguntaId.isEmpty) continue;

        final actual = agg.putIfAbsent(
          preguntaId,
          () => <String, dynamic>{
            'pregunta_id': preguntaId,
            'materia': nombreMateria,
            'numero': _toInt(preguntaMap['numero_oficial']),
            'codigo_pregunta': (preguntaMap['codigo_pregunta'] ?? '')
                .toString()
                .trim(),
            'texto': _resumirTextoError(
              (preguntaMap['enunciado'] ?? '').toString(),
              max: 130,
            ),
            'intentos': 0,
            'impulsivos': 0,
            'suma_tiempo': 0.0,
            'correctas': 0,
            'incorrectas': 0,
          },
        );

        actual['intentos'] = _toInt(actual['intentos']) + 1;
        actual['suma_tiempo'] =
            (_toDouble(actual['suma_tiempo']) ?? 0.0) + tiempo;
        if (tiempo < 8) {
          actual['impulsivos'] = _toInt(actual['impulsivos']) + 1;
        }
        if (esCorrecta) {
          actual['correctas'] = _toInt(actual['correctas']) + 1;
        } else {
          actual['incorrectas'] = _toInt(actual['incorrectas']) + 1;
        }
      }

      final lista = agg.values
          .map((item) {
            final intentos = _toInt(item['intentos']);
            final impulsivos = _toInt(item['impulsivos']);
            final sumaTiempo = _toDouble(item['suma_tiempo']) ?? 0.0;
            final promedio = intentos > 0 ? sumaTiempo / intentos : 0.0;
            final incorrectas = _toInt(item['incorrectas']);
            final correctas = _toInt(item['correctas']);
            final pctImpulsiva = intentos > 0
                ? (impulsivos * 100.0 / intentos)
                : 0.0;
            final tasaError = intentos > 0
                ? (incorrectas * 100.0 / intentos)
                : 0.0;
            final tasaAcierto = intentos > 0
                ? (correctas * 100.0 / intentos)
                : 0.0;
            return {
              ...item,
              'promedio_segundos': promedio,
              'pct_impulsiva': pctImpulsiva,
              'tasa_error': tasaError,
              'tasa_acierto': tasaAcierto,
            };
          })
          .where((item) => _toInt(item['impulsivos']) > 0)
          .toList();

      lista.sort((a, b) {
        final impA = _toInt(a['impulsivos']);
        final impB = _toInt(b['impulsivos']);
        final byImp = impB.compareTo(impA);
        if (byImp != 0) return byImp;

        final pctA = _toDouble(a['pct_impulsiva']) ?? 0.0;
        final pctB = _toDouble(b['pct_impulsiva']) ?? 0.0;
        final byPct = pctB.compareTo(pctA);
        if (byPct != 0) return byPct;

        final promA = _toDouble(a['promedio_segundos']) ?? 0.0;
        final promB = _toDouble(b['promedio_segundos']) ?? 0.0;
        final byProm = promA.compareTo(promB);
        if (byProm != 0) return byProm;

        final errA = _toDouble(a['tasa_error']) ?? 0.0;
        final errB = _toDouble(b['tasa_error']) ?? 0.0;
        return errB.compareTo(errA);
      });

      return lista.take(limit).toList();
    } catch (e) {
      debugPrint('Error obteniendo preguntas impulsivas por materia: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> obtenerDetalleMateria({
    required String userId,
    required String materia,
    double? porcentajeActual,
    String? nivelActual,
  }) async {
    final fallback = _detalleMateriaFallback(
      materia: materia,
      porcentajeActual: porcentajeActual ?? 0,
      nivelActual: nivelActual ?? 'INTERMEDIO',
    );

    if (!SupabaseService.isInitialized) return fallback;

    try {
      final objetivo = _normalizarTexto(materia);

      final List<dynamic> dominiosRaw = await _supabase
          .from('dominio_materia')
          .select(
            'materia_id, tasa_dominio, dominio_hace_7_dias, tasa_mejora, '
            'nivel_dominio, tiempo_recomendado_minutos, '
            'total_preguntas_vistas, total_correctas, total_incorrectas, total_omitidas, '
            'temas_debiles, errores_comunes, '
            'materia:materia_id(id, nombre, codigo, categoria, total_preguntas_banco, nivel_dificultad_promedio)',
          )
          .eq('usuario_id', userId);

      final dominios = dominiosRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      Map<String, dynamic>? dominioMateria;
      for (final d in dominios) {
        final materiaMap = d['materia'];
        final nombre = (materiaMap is Map)
            ? (materiaMap['nombre'] ?? '').toString()
            : '';
        if (_materiaCoincide(nombre, objetivo)) {
          dominioMateria = d;
          break;
        }
      }

      final materiaMap = (dominioMateria?['materia'] is Map)
          ? Map<String, dynamic>.from(dominioMateria!['materia'])
          : <String, dynamic>{};

      final totalPreguntasBanco = _toInt(materiaMap['total_preguntas_banco']);
      final tasaDominio =
          _toDouble(dominioMateria?['tasa_dominio']) ?? porcentajeActual ?? 0.0;
      final nivelDominio =
          (dominioMateria?['nivel_dominio'] ??
                  nivelActual ??
                  _nivelMateria(tasaDominio))
              .toString();
      final codigoMateria = (materiaMap['codigo'] ?? 'SIN-COD').toString();
      final areaMateria = (materiaMap['categoria'] ?? 'Area general')
          .toString();
      final dificultad =
          (materiaMap['nivel_dificultad_promedio'] ??
                  (tasaDominio < 50
                      ? 'alta'
                      : (tasaDominio < 75 ? 'media' : 'baja')))
              .toString();

      final List<dynamic> respuestasRaw = await _supabase
          .from('respuesta_usuario')
          .select(
            'pregunta_id, es_correcta, fue_omitida, tiempo_total_respuesta, respondida_at, '
            'pregunta:pregunta_id(id, tema_especifico, materia_id, materia:materia_id(nombre))',
          )
          .eq('usuario_id', userId)
          .order('respondida_at', ascending: false)
          .limit(_ventanaRespuestasVelocidad);

      final respuestas = respuestasRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final respuestasMateria = respuestas.where((r) {
        final pregunta = r['pregunta'];
        if (pregunta is! Map) return false;
        final materiaData = pregunta['materia'];
        final nombreMateria = (materiaData is Map)
            ? (materiaData['nombre'] ?? '').toString()
            : '';
        return _materiaCoincide(nombreMateria, objetivo);
      }).toList();

      List<String> idsUnicosDesde(Iterable<dynamic> values) {
        final ids = <String>[];
        final vistos = <String>{};
        for (final value in values) {
          final id = value.toString().trim();
          if (id.isEmpty) continue;
          if (vistos.add(id)) {
            ids.add(id);
          }
        }
        return ids;
      }

      final omitidas = respuestasMateria
          .where((r) => r['fue_omitida'] == true)
          .length;
      final intentos = respuestasMateria.length;

      var materiaId = (materiaMap['id'] ?? '').toString().trim();
      if (materiaId.isEmpty) {
        final preguntaConMateriaId = respuestasMateria.firstWhere((r) {
          final pregunta = r['pregunta'];
          return pregunta is Map &&
              (pregunta['materia_id'] ?? '').toString().trim().isNotEmpty;
        }, orElse: () => <String, dynamic>{});
        final preguntaData = (preguntaConMateriaId['pregunta'] is Map)
            ? Map<String, dynamic>.from(preguntaConMateriaId['pregunta'])
            : const <String, dynamic>{};
        materiaId = (preguntaData['materia_id'] ?? '').toString().trim();
      }

      final respuestasMateriaOrdenadas = [...respuestasMateria]
        ..sort((a, b) {
          final ta = DateTime.tryParse((a['respondida_at'] ?? '').toString());
          final tb = DateTime.tryParse((b['respondida_at'] ?? '').toString());
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });

      final Map<String, Map<String, dynamic>> ultimoIntentoPorPregunta = {};
      for (final r in respuestasMateriaOrdenadas) {
        final id = (r['pregunta_id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        ultimoIntentoPorPregunta.putIfAbsent(id, () => r);
      }

      var totalPreguntasMateria = totalPreguntasBanco;
      var idsBancoMateria = <String>[];
      if (materiaId.isNotEmpty) {
        List<dynamic> bancoRaw;
        try {
          bancoRaw = await _supabase
              .from('pregunta')
              .select('id')
              .eq('materia_id', materiaId)
              .eq('activo', true);
        } catch (_) {
          bancoRaw = await _supabase
              .from('pregunta')
              .select('id')
              .eq('materia_id', materiaId);
        }
        idsBancoMateria = idsUnicosDesde(
          bancoRaw.whereType<Map>().map((row) => row['id']),
        );
        if (idsBancoMateria.isNotEmpty) {
          totalPreguntasMateria = idsBancoMateria.length;
        }
      }

      final correctasIds = <String>[];
      final incorrectasIds = <String>[];
      final noRespondidasIds = <String>[];

      void clasificarPregunta(String idPregunta) {
        final ultimo = ultimoIntentoPorPregunta[idPregunta];
        if (ultimo == null) {
          noRespondidasIds.add(idPregunta);
          return;
        }
        final fueOmitida = ultimo['fue_omitida'] == true;
        final esCorrecta = ultimo['es_correcta'];
        if (fueOmitida || esCorrecta is! bool) {
          noRespondidasIds.add(idPregunta);
          return;
        }
        if (esCorrecta) {
          correctasIds.add(idPregunta);
        } else {
          incorrectasIds.add(idPregunta);
        }
      }

      if (idsBancoMateria.isNotEmpty) {
        for (final id in idsBancoMateria) {
          clasificarPregunta(id);
        }
      } else {
        for (final id in ultimoIntentoPorPregunta.keys) {
          clasificarPregunta(id);
        }
      }

      final correctas = correctasIds.length;
      final incorrectas = incorrectasIds.length;
      var noRespondidas = noRespondidasIds.length;
      if (idsBancoMateria.isEmpty && totalPreguntasMateria > 0) {
        final faltantes =
            totalPreguntasMateria - (correctas + incorrectas + noRespondidas);
        if (faltantes > 0) {
          noRespondidas += faltantes;
        }
      }

      final respondidasIds = [...correctasIds, ...incorrectasIds];
      final preguntasVistasUnicas = respondidasIds.length;
      final porcentajeAvance = totalPreguntasMateria > 0
          ? (preguntasVistasUnicas * 100.0) / totalPreguntasMateria
          : 0.0;

      final tiemposMateria = respuestasMateria
          .where((r) => r['fue_omitida'] != true)
          .map((r) => _toDouble(r['tiempo_total_respuesta']) ?? 0.0)
          .where((t) => t > 0)
          .toList();
      final tiemposGlobal = respuestas
          .where((r) => r['fue_omitida'] != true)
          .map((r) => _toDouble(r['tiempo_total_respuesta']) ?? 0.0)
          .where((t) => t > 0)
          .toList();
      final tiempoPromedioMateria = _promedio(tiemposMateria);
      final tiempoPromedioGlobal = _promedio(tiemposGlobal);
      final comparacionSegundos = tiempoPromedioMateria - tiempoPromedioGlobal;
      final comparacionTexto = comparacionSegundos.abs() < 0.1
          ? 'Igual a tu promedio general'
          : (comparacionSegundos > 0
                ? '${comparacionSegundos.toStringAsFixed(1)} seg mas lento que tu promedio general'
                : '${comparacionSegundos.abs().toStringAsFixed(1)} seg mas rapido que tu promedio general');

      final ahora = DateTime.now().toUtc();
      final limite7 = ahora.subtract(const Duration(days: 7));
      final limite14 = ahora.subtract(const Duration(days: 14));
      final recientes = respuestasMateria.where((r) {
        final t = DateTime.tryParse(
          (r['respondida_at'] ?? '').toString(),
        )?.toUtc();
        return t != null && t.isAfter(limite7);
      }).toList();
      final anteriores = respuestasMateria.where((r) {
        final t = DateTime.tryParse(
          (r['respondida_at'] ?? '').toString(),
        )?.toUtc();
        if (t == null) return false;
        return t.isAfter(limite14) && t.isBefore(limite7);
      }).toList();

      final accReciente = _tasaAcierto(recientes);
      final accAnterior = _tasaAcierto(anteriores);
      double deltaTendencia;
      if (recientes.length >= 5 && anteriores.length >= 5) {
        deltaTendencia = accReciente - accAnterior;
      } else {
        final dominio7 = _toDouble(dominioMateria?['dominio_hace_7_dias']);
        deltaTendencia = dominio7 == null ? 0.0 : (tasaDominio - dominio7);
      }

      final tendencia = deltaTendencia >= 2.0
          ? 'mejorando'
          : (deltaTendencia <= -2.0 ? 'empeorando' : 'estable');

      final Map<String, int> fallosPorPregunta = {};
      final Map<String, int> fallosPorTema = {};

      for (final r in respuestasMateria) {
        if (r['es_correcta'] != false || r['fue_omitida'] == true) continue;
        final preguntaId = (r['pregunta_id'] ?? '').toString();
        if (preguntaId.isNotEmpty) {
          fallosPorPregunta[preguntaId] =
              (fallosPorPregunta[preguntaId] ?? 0) + 1;
        }

        final pregunta = r['pregunta'];
        final tema = (pregunta is Map)
            ? (pregunta['tema_especifico'] ?? '').toString().trim()
            : '';
        final temaFinal = tema.isNotEmpty ? tema : 'Fundamentos de $materia';
        fallosPorTema[temaFinal] = (fallosPorTema[temaFinal] ?? 0) + 1;
      }

      final fallidasOrdenadas = fallosPorPregunta.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final idsFallidas = fallidasOrdenadas.map((e) => e.key).toList();
      final totalFallidas = idsFallidas.length;

      final temasOrdenados = fallosPorTema.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final temaRiesgoso = temasOrdenados.isNotEmpty
          ? temasOrdenados.first.key
          : 'Sin tema critico detectado';
      final temaImpacto = temasOrdenados.length > 1
          ? temasOrdenados[1].key
          : temaRiesgoso;

      final Map<String, List<double>> tiemposPorMateria = {};
      for (final r in respuestas) {
        if (r['fue_omitida'] == true) continue;
        final tiempo = _toDouble(r['tiempo_total_respuesta']) ?? 0;
        if (tiempo <= 0) continue;

        final pregunta = r['pregunta'];
        if (pregunta is! Map) continue;
        final materiaData = pregunta['materia'];
        final nombreMateria = (materiaData is Map)
            ? (materiaData['nombre'] ?? '').toString().trim()
            : '';
        if (nombreMateria.isEmpty) continue;
        tiemposPorMateria.putIfAbsent(nombreMateria, () => []).add(tiempo);
      }

      final rankingTiempo =
          tiemposPorMateria.entries.map((e) {
            return {'materia': e.key, 'promedio': _promedio(e.value)};
          }).toList()..sort((a, b) {
            final av = _toDouble(a['promedio']) ?? 0;
            final bv = _toDouble(b['promedio']) ?? 0;
            return bv.compareTo(av);
          });

      final materiasLentas = rankingTiempo
          .take(3)
          .map(
            (m) =>
                '${m['materia']} (${(_toDouble(m['promedio']) ?? 0).toStringAsFixed(1)} seg)',
          )
          .toList();

      final probabilidadActual =
          (tasaDominio * 0.75 +
                  porcentajeAvance * 0.25 +
                  (deltaTendencia * 0.8))
              .clamp(5.0, 99.0);
      var gananciaDiaria = tasaDominio < 50
          ? 0.9
          : (tasaDominio < 75 ? 0.65 : 0.45);
      if (tendencia == 'empeorando') gananciaDiaria -= 0.2;
      if (gananciaDiaria < 0.2) gananciaDiaria = 0.2;

      final prob7 = (probabilidadActual + gananciaDiaria * 7).clamp(5.0, 99.0);
      final prob14 = (probabilidadActual + gananciaDiaria * 14).clamp(
        5.0,
        99.0,
      );
      final prob30 = (probabilidadActual + gananciaDiaria * 30).clamp(
        5.0,
        99.0,
      );

      final tiempoSugerido =
          _toInt(dominioMateria?['tiempo_recomendado_minutos']) > 0
          ? _toInt(dominioMateria?['tiempo_recomendado_minutos'])
          : (tasaDominio < 50 ? 35 : (tasaDominio < 70 ? 25 : 18));
      final objetivoPorcentaje = (tasaDominio + 12).clamp(75.0, 92.0).round();

      return {
        'info_basica': {
          'nombre': materia,
          'codigo': codigoMateria,
          'area': areaMateria,
          'total_preguntas': totalPreguntasMateria,
          'dificultad': dificultad,
        },
        'progreso_usuario': {
          'correctas': correctas,
          'incorrectas': incorrectas,
          'no_respondidas': noRespondidas,
          'omitidas': omitidas,
          'porcentaje_avance': porcentajeAvance,
          'preguntas_vistas': preguntasVistasUnicas,
        },
        'preguntas_por_estado': {
          'correctas_ids': correctasIds,
          'incorrectas_ids': incorrectasIds,
          'no_respondidas_ids': noRespondidasIds,
          'respondidas_ids': respondidasIds,
        },
        'estadisticas_clave': {
          'tiempo_promedio_pregunta': tiempoPromedioMateria,
          'promedio_general': tiempoPromedioGlobal,
          'comparacion_texto': comparacionTexto,
          'intentos_realizados': intentos,
          'tendencia': tendencia,
          'delta_tendencia': deltaTendencia,
        },
        'prediccion': {
          'probabilidad_actual': probabilidadActual,
          'proyeccion_7_dias': prob7,
          'proyeccion_14_dias': prob14,
          'proyeccion_30_dias': prob30,
        },
        'fallidas': {
          'total': totalFallidas,
          'ids': idsFallidas,
          'practicar_cantidad': totalFallidas > 0
              ? totalFallidas.clamp(10, 30)
              : 0,
          'simulacro_cantidad': totalFallidas > 0
              ? totalFallidas.clamp(20, 60)
              : 0,
        },
        'tutor_ia_personal': {
          'tema_riesgoso': temaRiesgoso,
          'tema_impacto': temaImpacto,
          'materias_tiempo_perdido': materiasLentas,
          'nivel_usuario': nivelDominio.toUpperCase(),
        },
        'recomendaciones': {
          'tiempo_diario_sugerido': tiempoSugerido,
          'tema_prioritario': temaRiesgoso,
          'objetivo': 'Alcanzar $objetivoPorcentaje% en 10 dias',
        },
      };
    } catch (e) {
      debugPrint('Error obteniendo detalle por materia: $e');
      return fallback;
    }
  }

  Future<String> _generarResumenMaterias({
    required String nivel,
    required List<Map<String, dynamic>> analisisMaterias,
    required List<String> fortalezas,
    required List<String> debilidades,
  }) async {
    final fallback = _resumenMateriasFallback(
      analisisMaterias: analisisMaterias,
      fortalezas: fortalezas,
      debilidades: debilidades,
    );

    if (!SupabaseService.isInitialized) return fallback;

    try {
      final top = analisisMaterias
          .take(8)
          .map(
            (m) => {
              'materia': (m['materia'] ?? '').toString(),
              'porcentaje': _toDouble(m['porcentaje']) ?? 0.0,
              'nivel': (m['nivel'] ?? '').toString(),
              'tipo': (m['tipo'] ?? '').toString(),
            },
          )
          .toList();

      final prompt =
          '''
Actua como tutor policial PNP.
Genera SOLO una frase corta en espanol (max 150 caracteres), sin comillas ni markdown.
La frase debe sonar tactica, directa y mas llamativa (no robotica).
Debe resumir estado por materias y cerrar con una accion clara para entrar a Revisar.

DATOS:
{
  "nivel_global": "$nivel",
  "materias": ${jsonEncode(top)},
  "fortalezas": ${jsonEncode(fortalezas)},
  "debilidades": ${jsonEncode(debilidades)}
}
''';

      final currentUserId = _supabase.auth.currentUser?.id;
      final response = await _supabase.functions.invoke(
        'ia_diagnostico',
        body: {
          'prompt': prompt,
          'mode': 'panel',
          if (currentUserId != null && currentUserId.isNotEmpty)
            'user_id': currentUserId,
        },
      );

      final data = response.data;
      String? raw;
      if (data is String && data.trim().isNotEmpty) {
        raw = data.trim();
      } else if (data is Map && data['text'] is String) {
        raw = (data['text'] as String).trim();
      }

      if (raw == null || raw.isEmpty) return fallback;

      final cleaned = raw
          .replaceAll('\n', ' ')
          .replaceAll('"', '')
          .replaceAll('`', '')
          .trim();

      if (cleaned.isEmpty) return fallback;
      return cleaned.length <= 170 ? cleaned : cleaned.substring(0, 170).trim();
    } catch (_) {
      return fallback;
    }
  }

  String _resumenMateriasFallback({
    required List<Map<String, dynamic>> analisisMaterias,
    required List<String> fortalezas,
    required List<String> debilidades,
  }) {
    final fortalezasCount = analisisMaterias
        .where((m) => (m['tipo'] ?? '').toString() == 'fortaleza')
        .length;
    final debilidadesCount = analisisMaterias
        .where((m) => (m['tipo'] ?? '').toString() == 'debilidad')
        .length;

    if (fortalezasCount == 0 &&
        debilidadesCount == 0 &&
        analisisMaterias.isEmpty) {
      return 'Briefing inicial listo: aun no hay datos por materia. Ejecuta una practica y vuelve a Revisar.';
    }

    final f = fortalezasCount > 0 ? fortalezasCount : fortalezas.length;
    final d = debilidadesCount > 0 ? debilidadesCount : debilidades.length;
    return 'Briefing IA: $f materias en control y $d en mejora. Entra a Revisar para ejecutar el plan por materia.';
  }

  // Panel IA (Gemini controla tarjetas y mensajes)
  Future<Map<String, dynamic>> _generarPanelIA({
    required String nivel,
    required List<String> fortalezas,
    required List<String> debilidades,
    required double tasaAcierto,
    required int rachaDias,
    required int preguntasDominadas,
    required int tiempoTotalMinutos,
    String? categoria,
    String? gradoActual,
    String? especialidad,
    int? metaDiariaMinutos,
  }) async {
    if (!SupabaseService.isInitialized) {
      return _panelBasico(nivel, debilidades);
    }

    try {
      final contexto = {
        'nivel_global': nivel,
        'tasa_acierto': tasaAcierto,
        'fortalezas': fortalezas,
        'debilidades': debilidades,
        'racha_dias': rachaDias,
        'preguntas_dominadas': preguntasDominadas,
        'tiempo_total_minutos': tiempoTotalMinutos,
        'categoria': categoria ?? 'No especificado',
        'grado_actual': gradoActual ?? 'No especificado',
        'especialidad': especialidad ?? 'No especificado',
        'meta_diaria_minutos': metaDiariaMinutos ?? 30,
      };

      final prompt =
          '''
Actua como un Tutor Experto de la Policia Nacional del Peru (PNP).
Tu objetivo es dirigir el entrenamiento del estudiante y definir acciones concretas.

DATOS DEL ESTUDIANTE (JSON):
${jsonEncode(contexto)}

TAREA:
Devuelve SOLO un JSON valido (sin markdown) con este formato exacto:
{
  "diagnostico": "texto breve (<= 300 caracteres)",
  "cards": [
    {
      "type": "practice|streak|message|plan|recommendation|alert",
      "title": "titulo corto",
      "message": "descripcion breve",
      "cta": "texto boton opcional",
      "items": ["item opcional 1", "item 2"],
      "payload": {
        "cantidad": 20,
        "tiempo": 25,
        "materia": "Derecho Penal"
      }
    }
  ]
}

REGLAS:
1) Genera entre 3 y 6 cards.
2) Incluye al menos 1 card type "practice" con cantidad y tiempo.
3) Incluye al menos 1 card type "streak" o "message".
4) Si recomiendas materia, usa el campo payload.materia.
5) No agregues texto fuera del JSON.
''';

      final currentUserId = _supabase.auth.currentUser?.id;
      final response = await _supabase.functions.invoke(
        'ia_diagnostico',
        body: {
          'prompt': prompt,
          'mode': 'panel',
          if (currentUserId != null && currentUserId.isNotEmpty)
            'user_id': currentUserId,
        },
      );

      final data = response.data;
      String? raw;
      if (data is String && data.trim().isNotEmpty) {
        raw = data.trim();
      } else if (data is Map && data['text'] is String) {
        raw = (data['text'] as String).trim();
      }

      if (raw == null || raw.isEmpty) {
        return _panelBasico(nivel, debilidades);
      }

      final parsed = _parsePanelJson(raw);
      if (parsed == null) return _panelBasico(nivel, debilidades);

      return _normalizarPanel(parsed, nivel, debilidades);
    } catch (e) {
      debugPrint('Error llamando a Gemini: $e');
      return _panelBasico(nivel, debilidades);
    }
  }

  Map<String, dynamic> _panelBasico(String nivel, List<String> debilidades) {
    return {
      'diagnostico': _generarDiagnosticoBasico(nivel, debilidades),
      'cards': [
        {
          'type': 'practice',
          'title': 'Practica de refuerzo',
          'message': '20 preguntas mixtas para mejorar tu base.',
          'cta': 'Iniciar 20 preguntas',
          'payload': {'cantidad': 20, 'tiempo': 25},
        },
        {
          'type': 'streak',
          'title': 'Racha activa',
          'message': 'Sigue estudiando hoy para mantener tu ritmo.',
        },
        {
          'type': 'recommendation',
          'title': 'Consejo tactico',
          'message': 'Repasa tu debilidad principal antes de dormir.',
        },
      ],
    };
  }

  Map<String, dynamic>? _parsePanelJson(String raw) {
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}

    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    final candidate = raw.substring(start, end + 1);
    try {
      final decoded = json.decode(candidate);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  Map<String, dynamic> _normalizarPanel(
    Map<String, dynamic> panel,
    String nivel,
    List<String> debilidades,
  ) {
    final diagnostico = panel['diagnostico'] is String
        ? panel['diagnostico'] as String
        : '';

    final cardsRaw = panel['cards'];
    final List<Map<String, dynamic>> cards = [];
    if (cardsRaw is List) {
      for (final item in cardsRaw) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final typeRaw = map['type']?.toString().toLowerCase().trim() ?? '';
          final type = _mapType(typeRaw);
          final title = map['title']?.toString().trim();
          final message = map['message']?.toString().trim();
          final cta = map['cta']?.toString().trim();
          final payload = map['payload'] is Map
              ? Map<String, dynamic>.from(map['payload'])
              : <String, dynamic>{};
          final items = map['items'] is List
              ? (map['items'] as List)
                    .whereType<String>()
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList()
              : <String>[];

          if ((title ?? '').isEmpty && (message ?? '').isEmpty) continue;

          cards.add({
            'type': type,
            'title': (title ?? 'Recomendacion IA'),
            'message': message ?? '',
            if (cta != null && cta.isNotEmpty) 'cta': cta,
            if (items.isNotEmpty) 'items': items,
            if (payload.isNotEmpty) 'payload': payload,
          });
        }
      }
    }

    if (cards.isEmpty) {
      return _panelBasico(nivel, debilidades);
    }

    return {
      'diagnostico': diagnostico.isNotEmpty
          ? diagnostico
          : _generarDiagnosticoBasico(nivel, debilidades),
      'cards': cards,
    };
  }

  String _mapType(String raw) {
    switch (raw) {
      case 'practice':
      case 'practica':
        return 'practice';
      case 'streak':
      case 'racha':
        return 'streak';
      case 'plan':
      case 'plan_diario':
        return 'plan';
      case 'recommendation':
      case 'recomendacion':
        return 'recommendation';
      case 'alert':
      case 'alerta':
        return 'alert';
      case 'message':
      case 'mensaje':
      default:
        return 'message';
    }
  }

  // Fallback en caso de que Gemini falle o no haya internet
  String _generarDiagnosticoBasico(String nivel, List<String> debilidades) {
    if (debilidades.isEmpty || debilidades.first.contains('proceso')) {
      return "?Bienvenido! Empieza tus pr?cticas para que pueda analizar tu rendimiento.";
    }
    return "Nivel $nivel detectado. Debemos reforzar ${debilidades.first.split('(').first}. ?Sigue as?!";
  }

  // --- Funciones Auxiliares de L?gica de Negocio ---

  String _calcularNivelGlobal(Map<String, dynamic> perfil) {
    final tasa = (perfil['tasa_acierto_global'] as num?)?.toDouble() ?? 0.0;
    if (tasa < 50) return 'PRINCIPIANTE';
    if (tasa < 75) return 'INTERMEDIO';
    if (tasa < 90) return 'AVANZADO';
    return 'EXPERTO';
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String? _extraerTextoDesdeInvoke(dynamic data) {
    if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }

    if (data is Map) {
      final map = data.map((key, value) => MapEntry(key.toString(), value));
      for (final key in const ['text', 'mensaje', 'respuesta', 'diagnostico']) {
        final value = map[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }

      final nested = map['data'];
      if (nested is Map) {
        final nestedMap = nested.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        for (final key in const [
          'text',
          'mensaje',
          'respuesta',
          'diagnostico',
        ]) {
          final value = nestedMap[key];
          if (value is String && value.trim().isNotEmpty) {
            return value.trim();
          }
        }
      }
    }

    return null;
  }

  String _normalizarRespuestaTutor(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';

    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z0-9_-]*'), '').trim();
      if (text.endsWith('```') && text.length >= 3) {
        text = text.substring(0, text.length - 3).trim();
      }
    }
    text = text.replaceAll('```', '').trim();

    final parsed = _parsePanelJson(text);
    if (parsed != null) {
      final estructurada = _extraerRespuestaEstructurada(parsed);
      if (estructurada != null && estructurada.isNotEmpty) {
        return estructurada.trim();
      }
    }

    return text;
  }

  String? _extraerRespuestaEstructurada(Map<String, dynamic> parsed) {
    for (final key in const ['respuesta', 'mensaje', 'text']) {
      final value = parsed[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    String? campo(String key) {
      final value = parsed[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      return null;
    }

    final diagnostico = campo('diagnostico') ?? campo('Diagnostico');
    final accionHoy =
        campo('accion_hoy') ??
        campo('accionHoy') ??
        campo('Accion_hoy') ??
        campo('AccionHoy');
    final control = campo('control') ?? campo('Control');
    final seguimiento24h =
        campo('seguimiento_24h') ??
        campo('seguimiento24h') ??
        campo('Seguimiento_24h');

    String? pasos;
    final pasosRaw = parsed['pasos'] ?? parsed['Pasos'];
    if (pasosRaw is String && pasosRaw.trim().isNotEmpty) {
      pasos = pasosRaw.trim();
    } else if (pasosRaw is List) {
      final items = pasosRaw
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (items.isNotEmpty) {
        pasos = items
            .asMap()
            .entries
            .map((e) => '${e.key + 1}) ${e.value}')
            .join(' ');
      }
    }

    final partes = <String>[
      if (diagnostico != null) 'Diagnostico: $diagnostico',
      if (accionHoy != null) 'Accion_hoy: $accionHoy',
      if (pasos != null) 'Pasos: $pasos',
      if (control != null) 'Control: $control',
      if (seguimiento24h != null) 'Seguimiento_24h: $seguimiento24h',
    ];

    if (partes.isNotEmpty) {
      return partes.join('\n');
    }

    final diagnosticoSolo = campo('diagnostico') ?? campo('Diagnostico');
    if (diagnosticoSolo != null) return diagnosticoSolo;

    return null;
  }

  String _mensajeErrorTutorDesdeFuncion(FunctionException e) {
    final status = e.status;
    final detalle = _resumirTextoError(_detalleComoTexto(e.details), max: 220);
    final rateLimit = _detallePareceRateLimit(detalle);

    if (status == 429 || rateLimit) {
      return 'El tutor IA esta con alta demanda ahora (limite temporal de Gemini). Intenta nuevamente en 1 o 2 minutos.';
    }

    if (status == 401 || status == 403) {
      final extra = detalle.isEmpty
          ? 'no autorizado. Cierra sesion y vuelve a ingresar.'
          : detalle;
      return 'Error $status: $extra';
    }

    if (status == 400) {
      final extra = detalle.isEmpty ? 'Solicitud invalida.' : detalle;
      return 'Error $status: $extra';
    }

    if (status == 500) {
      final extra = detalle.isEmpty
          ? 'Error interno en Edge Function.'
          : detalle;
      return 'Error $status: $extra';
    }

    if (status == 502 || status == 503 || status == 504) {
      final extra = detalle.isEmpty ? 'Fallo al consultar Gemini.' : detalle;
      return 'Error $status (Gemini): $extra';
    }

    final extra = detalle.isEmpty ? (e.reasonPhrase ?? 'Sin detalle') : detalle;
    return 'Error del tutor ($status): $extra';
  }

  bool _detallePareceRateLimit(String detalle) {
    if (detalle.trim().isEmpty) return false;
    final t = detalle.toLowerCase();
    return t.contains('429') ||
        t.contains('too many requests') ||
        t.contains('quota') ||
        t.contains('rate limit');
  }

  String _detalleComoTexto(dynamic details) {
    if (details == null) return '';
    if (details is String) return details;
    if (details is Map || details is List) {
      try {
        return jsonEncode(details);
      } catch (_) {
        return details.toString();
      }
    }
    return details.toString();
  }

  String _resumirTextoError(String texto, {int max = 200}) {
    var limpio = texto
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (limpio.length <= max) return limpio;
    limpio = limpio.substring(0, max).trimRight();
    return '$limpio...';
  }

  DateTime? _parseFechaFlexible(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final txt = value.toString().trim();
    if (txt.isEmpty) return null;
    return DateTime.tryParse(txt);
  }

  String _formatearFecha(DateTime fecha) {
    final local = fecha.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yy = local.year.toString();
    return '$dd/$mm/$yy';
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  String _normalizarMomentoDelDia(dynamic value) {
    final txt = _normalizarTexto((value ?? '').toString());
    if (txt.contains('manana') || txt.contains('morning') || txt == 'am') {
      return 'manana';
    }
    if (txt.contains('tarde') || txt.contains('afternoon')) {
      return 'tarde';
    }
    if (txt.contains('noche') ||
        txt.contains('night') ||
        txt.contains('evening')) {
      return 'noche';
    }
    return 'otro';
  }

  String _descripcionMomento(String key) {
    switch (key) {
      case 'manana':
        return 'manana (6am-12pm)';
      case 'tarde':
        return 'tarde (12pm-6pm)';
      case 'noche':
        return 'noche (6pm-12am)';
      default:
        return key;
    }
  }

  Future<List<String>> _resolverNombresMateriasDesdeIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const <String>[];
    try {
      final List<dynamic> rows = await _supabase
          .from('materia')
          .select('id, nombre')
          .inFilter('id', ids);
      final nombres = rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map((m) => (m['nombre'] ?? '').toString().trim())
          .where((n) => n.isNotEmpty)
          .toList();
      return nombres;
    } catch (_) {
      return const <String>[];
    }
  }

  String _normalizarTextoEspecialidad(String value) {
    return _normalizarTexto(
      value
          .replaceAll('\u00e1', 'a')
          .replaceAll('\u00e9', 'e')
          .replaceAll('\u00ed', 'i')
          .replaceAll('\u00f3', 'o')
          .replaceAll('\u00fa', 'u')
          .replaceAll('\u00f1', 'n'),
    );
  }

  List<String> _palabrasClaveEspecialidad(String especialidad) {
    final normalizada = _normalizarTextoEspecialidad(especialidad);
    if (normalizada.isEmpty) return const <String>[];

    if (normalizada.contains('investig')) {
      return const <String>[
        'investig',
        'criminal',
        'crimen',
        'penal',
        'procesal',
        'lavado',
        'extorsion',
        'drog',
        'organizado',
      ];
    }
    if (normalizada.contains('intelig')) {
      return const <String>[
        'intelig',
        'informacion',
        'contraintelig',
        'seguridad',
      ];
    }
    if (normalizada.contains('criminalist')) {
      return const <String>[
        'criminalist',
        'forens',
        'perici',
        'evidencia',
        'laboratorio',
      ];
    }
    if (normalizada.contains('administr')) {
      return const <String>[
        'administr',
        'procedimiento',
        'regimen',
        'carrera',
        'disciplina',
        'gestion',
        'ascenso',
      ];
    }
    if (normalizada.contains('orden') || normalizada.contains('seguridad')) {
      return const <String>[
        'orden',
        'seguridad',
        'operativo',
        'fuerza',
        'patrull',
      ];
    }
    if (normalizada.contains('servicio')) {
      return const <String>[
        'servicio',
        'procedimiento',
        'administr',
        'regimen',
      ];
    }

    return normalizada
        .split(RegExp(r'[^a-z0-9]+'))
        .where((e) => e.trim().length >= 4)
        .toList();
  }

  bool _esMateriaRelacionadaAEspecialidad({
    required Map<String, dynamic> row,
    required String especialidadNormalizada,
    required List<String> keywordsEspecialidad,
  }) {
    final materia = _asMap(row['materia']);
    final nombre = _normalizarTextoEspecialidad(
      (materia['nombre'] ?? '').toString(),
    );
    final categoria = _normalizarTextoEspecialidad(
      (materia['categoria'] ?? '').toString(),
    );
    final temas = _toStringList(
      row['temas_debiles'],
    ).map(_normalizarTextoEspecialidad).join(' ');
    final texto = '$nombre $categoria $temas'.trim();
    if (texto.isEmpty) return false;

    if (especialidadNormalizada.isNotEmpty &&
        texto.contains(especialidadNormalizada)) {
      return true;
    }

    for (final keyword in keywordsEspecialidad) {
      if (keyword.trim().isEmpty) continue;
      if (texto.contains(keyword)) return true;
    }
    return false;
  }

  String _normalizarTexto(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('Ã¡', 'a')
        .replaceAll('Ã©', 'e')
        .replaceAll('Ã­', 'i')
        .replaceAll('Ã³', 'o')
        .replaceAll('Ãº', 'u');
  }

  bool _materiaCoincide(String nombreMateria, String objetivoNormalizado) {
    final actual = _normalizarTexto(nombreMateria);
    if (actual.isEmpty || objetivoNormalizado.isEmpty) return false;
    return actual == objetivoNormalizado ||
        actual.contains(objetivoNormalizado) ||
        objetivoNormalizado.contains(actual);
  }

  double? _obtenerTasaDominio(Map<String, dynamic> dominio) {
    return _toDouble(dominio['tasa_dominio']) ??
        _toDouble(dominio['tasa_dominio_actual']);
  }

  String _obtenerNombreMateria(Map<String, dynamic> dominio) {
    final materia = dominio['materia'];
    if (materia is Map && materia['nombre'] != null) {
      return materia['nombre'].toString();
    }
    return 'Materia';
  }

  String _nivelMateria(double tasa) {
    if (tasa < 40) return 'CRITICO';
    if (tasa < 60) return 'BASICO';
    if (tasa < 80) return 'INTERMEDIO';
    if (tasa < 90) return 'AVANZADO';
    return 'EXPERTO';
  }

  List<Map<String, dynamic>> _construirAnalisisMaterias(
    List<Map<String, dynamic>> dominios,
  ) {
    final materias = dominios.map((d) {
      final nombre = _obtenerNombreMateria(d);
      final score = _obtenerTasaDominio(d) ?? 0;
      final materia = d['materia'];
      final tiempoRecomendadoMin = _toInt(d['tiempo_recomendado_minutos']);
      final dominioPrevio = _toDouble(d['dominio_hace_7_dias']);
      final respondidasNoOmitidas = _toInt(d['respondidas_no_omitidas']);
      final coberturaBanco = _toDouble(d['cobertura_banco']);
      final consistencia = _toDouble(d['consistencia']);
      return {
        if (d['materia_id'] != null) 'materia_id': d['materia_id'],
        if (materia is Map && materia['id'] != null)
          'materia_id': materia['id'],
        if (materia is Map && materia['codigo'] != null)
          'codigo': materia['codigo'],
        if (materia is Map && materia['categoria'] != null)
          'area': materia['categoria'],
        'materia': nombre,
        'porcentaje': score,
        if (dominioPrevio != null) 'dominio_hace_7_dias': dominioPrevio,
        'tiempo_recomendado_minutos': tiempoRecomendadoMin,
        if (respondidasNoOmitidas > 0)
          'respondidas_no_omitidas': respondidasNoOmitidas,
        if (coberturaBanco != null) 'cobertura_banco': coberturaBanco,
        if (consistencia != null) 'consistencia': consistencia,
        'nivel': _nivelMateria(score),
        'tipo': score >= 70 ? 'fortaleza' : 'debilidad',
      };
    }).toList();

    materias.sort((a, b) {
      final aa = (a['porcentaje'] as num).toDouble();
      final bb = (b['porcentaje'] as num).toDouble();
      return bb.compareTo(aa);
    });
    return materias;
  }

  List<Map<String, dynamic>> _fusionarDominios({
    required List<Map<String, dynamic>> base,
    required List<Map<String, dynamic>> inferidos,
  }) {
    String keyOf(Map<String, dynamic> item) {
      final materiaId = (item['materia_id'] ?? '').toString().trim();
      if (materiaId.isNotEmpty) return 'id:$materiaId';
      return 'nm:${_normalizarTexto(_obtenerNombreMateria(item))}';
    }

    final merged = <String, Map<String, dynamic>>{};

    for (final d in base) {
      merged[keyOf(d)] = Map<String, dynamic>.from(d);
    }

    for (final inf in inferidos) {
      final key = keyOf(inf);
      final current = merged[key];
      if (current == null) {
        merged[key] = Map<String, dynamic>.from(inf);
        continue;
      }

      final next = Map<String, dynamic>.from(current);
      // El dominio calculado desde respuestas es el valor real m?s reciente.
      next['tasa_dominio'] = _toDouble(inf['tasa_dominio']) ?? 0.0;

      final tiempoInf = _toInt(inf['tiempo_recomendado_minutos']);
      if (tiempoInf > 0) {
        next['tiempo_recomendado_minutos'] = tiempoInf;
      }

      final materiaInf = _asMap(inf['materia']);
      final materiaCur = _asMap(next['materia']);
      next['materia'] = {...materiaCur, ...materiaInf};
      if ((next['materia_id'] ?? '').toString().trim().isEmpty &&
          (inf['materia_id'] ?? '').toString().trim().isNotEmpty) {
        next['materia_id'] = inf['materia_id'];
      }
      merged[key] = next;
    }

    return merged.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> _construirDominiosDesdeRespuestas(
    String userId,
  ) async {
    if (_sesionInvalida(userId) || !SupabaseService.isInitialized) {
      return const <Map<String, dynamic>>[];
    }

    try {
      final List<dynamic> raw = await _supabase
          .from('respuesta_usuario')
          .select(
            'es_correcta, fue_omitida, tiempo_total_respuesta, '
            'pregunta:pregunta_id(materia:materia_id(id, nombre, codigo, categoria, total_preguntas_banco))',
          )
          .eq('usuario_id', userId)
          .limit(6000);

      final acumulado = <String, Map<String, dynamic>>{};

      for (final item in raw) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final pregunta = _asMap(row['pregunta']);
        final materia = _asMap(pregunta['materia']);
        final nombre = (materia['nombre'] ?? '').toString().trim();
        if (nombre.isEmpty) continue;

        final idMateria = (materia['id'] ?? '').toString().trim();
        final key = idMateria.isNotEmpty ? idMateria : _normalizarTexto(nombre);
        if (key.isEmpty) continue;

        final entry = acumulado.putIfAbsent(
          key,
          () => <String, dynamic>{
            'materia': {
              'id': idMateria,
              'nombre': nombre,
              if (materia['codigo'] != null) 'codigo': materia['codigo'],
              if (materia['categoria'] != null)
                'categoria': materia['categoria'],
              if (materia['total_preguntas_banco'] != null)
                'total_preguntas_banco': materia['total_preguntas_banco'],
            },
            'intentos': 0,
            'correctas': 0,
            'tiempos': <double>[],
          },
        );

        final omitida = row['fue_omitida'] == true;
        final esCorrecta = row['es_correcta'];
        if (!omitida && esCorrecta is bool) {
          entry['intentos'] = _toInt(entry['intentos']) + 1;
          if (esCorrecta) {
            entry['correctas'] = _toInt(entry['correctas']) + 1;
          }
        }

        if (!omitida) {
          final tiempo = _toDouble(row['tiempo_total_respuesta']) ?? 0.0;
          if (tiempo > 0) {
            (entry['tiempos'] as List<double>).add(tiempo);
          }
        }
      }

      final dominios = <Map<String, dynamic>>[];
      for (final item in acumulado.values) {
        final intentos = _toInt(item['intentos']);
        if (intentos <= 0) continue;
        final correctas = _toInt(item['correctas']);
        final tasa = (correctas * 100.0) / intentos;
        final tiempos = (item['tiempos'] is List)
            ? List<double>.from(item['tiempos'] as List)
            : <double>[];
        final tiempoProm = _promedio(tiempos);
        var tiempoRecomendado = tasa < 50 ? 35 : (tasa < 70 ? 25 : 18);
        if (tiempoProm > 20) {
          tiempoRecomendado += 5;
        }

        final materia = _asMap(item['materia']);
        dominios.add({
          if ((materia['id'] ?? '').toString().trim().isNotEmpty)
            'materia_id': materia['id'],
          'tasa_dominio': tasa,
          'tiempo_recomendado_minutos': tiempoRecomendado,
          'materia': materia,
        });
      }

      return dominios;
    } catch (e) {
      debugPrint('TutorIA: error infiriendo dominios desde respuestas: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  List<String> _identificarFortalezas(List<Map<String, dynamic>> dominios) {
    if (dominios.isEmpty) return ['Sin datos suficientes'];

    final fortalezas = dominios
        .where((d) => (_obtenerTasaDominio(d) ?? -1) >= 80)
        .map((d) {
          final nombreMateria = _obtenerNombreMateria(d);
          final porcentaje = (_obtenerTasaDominio(d) ?? 0).toStringAsFixed(1);
          return '$nombreMateria ($porcentaje%)';
        })
        .toList();

    if (fortalezas.isEmpty) return ['Constancia (en desarrollo)'];

    return fortalezas.take(3).toList();
  }

  List<String> _identificarDebilidades(List<Map<String, dynamic>> dominios) {
    if (dominios.isEmpty) return ['Necesitas empezar a estudiar'];

    return dominios
        .where((d) => (_obtenerTasaDominio(d) ?? 101) < 60)
        .map((d) {
          final nombreMateria = _obtenerNombreMateria(d);
          final porcentaje = (_obtenerTasaDominio(d) ?? 0).toStringAsFixed(1);
          return '$nombreMateria ($porcentaje%)';
        })
        .take(3)
        .toList();
  }

  List<Map<String, dynamic>> _obtenerMateriasCriticas(
    List<Map<String, dynamic>> dominios,
  ) {
    return dominios
        .where((d) => (_obtenerTasaDominio(d) ?? 101) < 50)
        .map(
          (d) => {
            'nombre': _obtenerNombreMateria(d),
            'porcentaje': _obtenerTasaDominio(d) ?? 0,
            'estado': 'CRITICO',
          },
        )
        .toList();
  }

  double _promedio(List<double> valores) {
    if (valores.isEmpty) return 0.0;
    return valores.reduce((a, b) => a + b) / valores.length;
  }

  double _pesoRecenciaRespuesta({
    required DateTime? respondedAtUtc,
    required DateTime referenciaUtc,
  }) {
    if (respondedAtUtc == null) return 0.4;
    final delta = referenciaUtc.difference(respondedAtUtc).inMinutes;
    final dias = delta <= 0 ? 0.0 : (delta / 1440.0);
    final factor = math.exp(-math.ln2 * dias / _halfLifeRecenciaDias);
    return factor.clamp(0.2, 1.0);
  }

  String _etiquetaConfianzaMuestra(int muestra) {
    if (muestra < _muestraMinimaVelocidad) return 'Baja';
    if (muestra < (_muestraMinimaVelocidad * 3)) return 'Media';
    return 'Alta';
  }

  double _factorConfiabilidadMuestra(int muestra) {
    final factor = math.sqrt((muestra / 30.0).clamp(0.0, 1.0));
    return factor.clamp(0.45, 1.0);
  }

  double _tasaAcierto(List<Map<String, dynamic>> respuestas) {
    final validas = respuestas.where((r) {
      final esCorrecta = r['es_correcta'];
      return r['fue_omitida'] != true && esCorrecta is bool;
    }).toList();
    if (validas.isEmpty) return 0.0;
    final correctas = validas.where((r) => r['es_correcta'] == true).length;
    return (correctas * 100.0) / validas.length;
  }

  Map<String, dynamic> _detalleMateriaFallback({
    required String materia,
    required double porcentajeActual,
    required String nivelActual,
  }) {
    final porcentaje = porcentajeActual.clamp(0, 100);
    return {
      'info_basica': {
        'nombre': materia,
        'codigo': 'SIN-COD',
        'area': 'Area general',
        'total_preguntas': 0,
        'dificultad': porcentaje < 50
            ? 'alta'
            : (porcentaje < 75 ? 'media' : 'baja'),
      },
      'progreso_usuario': {
        'correctas': 0,
        'incorrectas': 0,
        'no_respondidas': 0,
        'omitidas': 0,
        'porcentaje_avance': 0.0,
        'preguntas_vistas': 0,
      },
      'preguntas_por_estado': {
        'correctas_ids': <String>[],
        'incorrectas_ids': <String>[],
        'no_respondidas_ids': <String>[],
        'respondidas_ids': <String>[],
      },
      'estadisticas_clave': {
        'tiempo_promedio_pregunta': 0.0,
        'promedio_general': 0.0,
        'comparacion_texto': 'Sin datos suficientes para comparar',
        'intentos_realizados': 0,
        'tendencia': 'estable',
        'delta_tendencia': 0.0,
      },
      'prediccion': {
        'probabilidad_actual': null,
        'proyeccion_7_dias': null,
        'proyeccion_14_dias': null,
        'proyeccion_30_dias': null,
      },
      'fallidas': {
        'total': 0,
        'ids': <String>[],
        'practicar_cantidad': 0,
        'simulacro_cantidad': 0,
      },
      'tutor_ia_personal': {
        'tema_riesgoso': 'Sin datos suficientes',
        'tema_impacto': 'Sin datos suficientes',
        'materias_tiempo_perdido': <String>[],
        'nivel_usuario': nivelActual.toUpperCase(),
      },
      'recomendaciones': {
        'tiempo_diario_sugerido': null,
        'tema_prioritario': 'Sin datos verificables',
        'objetivo': 'Completa mas sesiones para habilitar recomendaciones.',
      },
    };
  }

  Map<String, dynamic> _generarDatosMockEmergencia() {
    return {
      'nivel_global': 'SIN_DATOS',
      'fortalezas': <String>[],
      'debilidades': <String>[],
      'analisis_materias': <Map<String, dynamic>>[],
      'resumen_materias':
          'No hay datos verificables suficientes para generar un resumen de materias.',
      'materias_criticas': <Map<String, dynamic>>[],
      'preguntas_dominadas': 0,
      'tasa_acierto': 0.0,
      'velocidad_promedio': 0.0,
      'diagnostico': 'No se pudo verificar informacion real en este momento.',
      'panel_ia': _panelBasico('SIN_DATOS', ['Sin datos verificables']),
    };
  }

  List<String> _atajosTutorInicio() {
    return const [
      'dame mi plan diario',
      'que estudiar hoy',
      'analiza mi ultima sesion',
      'analisis de velocidad',
      'activa mi coach de memoria',
      'indice de memoria',
      'dame un mensaje motivacional',
    ];
  }

  Map<String, dynamic> _dashboardInicioFallback({
    required String nivel,
    required int racha,
    required double aprobacion,
    required String mensaje,
  }) {
    return {
      'estado': 'fallback',
      'sesion_valida': false,
      'hero': {
        'nivel': nivel,
        'aprobacion': aprobacion,
        'dominadas_hoy': 0,
        'racha_dias': racha,
      },
      'mision_diaria': {
        'preguntas_objetivo': 0,
        'minutos_objetivo': 0,
        'preguntas_completadas': 0,
        'minutos_completados': 0,
        'cantidad_practica': 0,
        'tiempo_practica': 0,
        'resumen': mensaje,
        'cta_habilitada': false,
      },
      'insights': [
        _cardFallback(
          id: 'plan_hoy',
          titulo: 'Ordenes del tutor para hoy',
          prompt: 'dame mi plan diario',
          color: '#BFDBFE',
          icono: 'calendar_month',
          resumen: mensaje,
        ),
      ],
      'atajos_chat': _atajosTutorInicio(),
    };
  }

  Future<Map<String, dynamic>> _obtenerProgresoHoy(String userId) async {
    final now = DateTime.now();
    final inicio = DateTime(now.year, now.month, now.day);
    final fin = inicio.add(const Duration(days: 1));
    try {
      final List<dynamic> raw = await _supabase
          .from('respuesta_usuario')
          .select('es_correcta, fue_omitida, tiempo_total_respuesta')
          .eq('usuario_id', userId)
          .gte('respondida_at', inicio.toIso8601String())
          .lt('respondida_at', fin.toIso8601String())
          .limit(6000);

      var respondidas = 0;
      var correctas = 0;
      var segundos = 0.0;
      for (final item in raw) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final esCorrecta = row['es_correcta'];
        final omitida = row['fue_omitida'] == true;
        if (!omitida && esCorrecta is bool) {
          respondidas++;
          if (esCorrecta) correctas++;
        }
        final tiempo = _toDouble(row['tiempo_total_respuesta']) ?? 0.0;
        if (tiempo > 0) segundos += tiempo;
      }

      var minutos = (segundos / 60).round();
      if (minutos <= 0) {
        final List<dynamic> sesiones = await _supabase
            .from('sesion_practica')
            .select('duracion_real_segundos')
            .eq('usuario_id', userId)
            .gte('fecha_inicio', inicio.toIso8601String())
            .lt('fecha_inicio', fin.toIso8601String())
            .limit(300);
        final segundosSesion = sesiones
            .whereType<Map>()
            .map((e) => _toInt((e)['duracion_real_segundos']))
            .where((e) => e > 0)
            .fold<int>(0, (a, b) => a + b);
        minutos = (segundosSesion / 60).round();
      }

      return {
        'respondidas': respondidas,
        'correctas': correctas,
        'minutos': minutos,
      };
    } catch (_) {
      return {'respondidas': 0, 'correctas': 0, 'minutos': 0};
    }
  }

  Future<Map<String, dynamic>?> _obtenerMetaDiariaHoy(String userId) async {
    final now = DateTime.now();
    final dd = now.day.toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final yyyy = now.year.toString().padLeft(4, '0');
    final hoy = '$yyyy-$mm-$dd';
    try {
      final row = await _supabase
          .from('meta_diaria')
          .select(
            'preguntas_objetivo, minutos_objetivo, preguntas_completadas, minutos_estudiados, meta_cumplida',
          )
          .eq('usuario_id', userId)
          .eq('fecha', hoy)
          .maybeSingle();
      if (row == null) return null;
      return _asMap(row);
    } catch (_) {
      return null;
    }
  }

  int _resolverPreguntasObjetivo({
    required Map<String, dynamic>? metaHoy,
    required Map<String, dynamic>? plan,
  }) {
    final meta = _toInt(metaHoy?['preguntas_objetivo']);
    if (meta > 0) return meta;
    final total = _toInt(plan?['total_preguntas_dia']);
    if (total > 0) return total;
    return 20;
  }

  int _resolverMinutosObjetivo({
    required Map<String, dynamic>? metaHoy,
    required Map<String, dynamic>? plan,
    required Map<String, dynamic> perfilUsuario,
  }) {
    final meta = _toInt(metaHoy?['minutos_objetivo']);
    if (meta > 0) return meta;
    final perfil = _toInt(perfilUsuario['meta_diaria_minutos']);
    if (perfil > 0) return perfil;
    final totalPlan = _toInt(plan?['total_preguntas_dia']);
    if (totalPlan > 0) {
      return _minutosSugeridosDesdePlan(totalPlan);
    }
    return 30;
  }

  int _minutosSugeridosDesdePlan(int totalPreguntas) {
    if (totalPreguntas <= 0) return 25;
    final estimado = (totalPreguntas * 1.5).round();
    return estimado.clamp(15, 120);
  }

  int _sugerirCantidadCoachVelocidad({
    required int muestraMateria,
    required int cantidadIds,
  }) {
    if (cantidadIds > 0) return cantidadIds.clamp(1, 25).toInt();
    if (muestraMateria >= 80) return 20;
    if (muestraMateria >= 30) return 15;
    return 12;
  }

  int _sugerirTiempoCoachVelocidad(double promedio) {
    if (promedio > 20) return 30;
    if (promedio > 0 && promedio < 8) return 25;
    return 20;
  }

  Map<String, dynamic> _construirCardCoachVelocidadDashboard({
    required double promedio,
    required String clasificacion,
    required String confianzaGlobal,
    required double tasaAciertoGlobal,
    required String recomendacion,
    required List<Map<String, dynamic>> materias,
    required List<Map<String, dynamic>> preguntas,
    required Map<String, dynamic> metricas,
    List<String> preguntasIdsFallback = const <String>[],
    String? fuenteDatos,
  }) {
    final topMaterias = materias.take(3).toList();
    final resumenMaterias = topMaterias
        .map((item) {
          final nombre = (item['materia'] ?? 'Materia').toString().trim();
          final prom = _toDouble(item['promedio_segundos']) ?? 0.0;
          final n = _toInt(item['muestra_valida'] ?? item['preguntas']);
          return '$nombre ${prom.toStringAsFixed(1)}s (n=$n)';
        })
        .where((e) => e.trim().isNotEmpty)
        .join(', ');
    final detalleMaterias = topMaterias
        .map((item) {
          final nombre = (item['materia'] ?? 'Materia').toString().trim();
          final prom = _toDouble(item['promedio_segundos']) ?? 0.0;
          final n = _toInt(item['muestra_valida'] ?? item['preguntas']);
          final conf = (item['confianza_muestra'] ?? '').toString().trim();
          return '$nombre: ${prom.toStringAsFixed(1)} seg/preg, muestra $n${conf.isEmpty ? '' : ' ($conf)'}.';
        })
        .where((e) => e.trim().isNotEmpty)
        .join(' ');

    final materiasPrioritarias = topMaterias
        .map((item) => (item['materia'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final materiaObjetivo = materiasPrioritarias.isNotEmpty
        ? materiasPrioritarias.first
        : '';

    final preguntasIdsGlobal = _mergeIdsPreservandoOrden([
      preguntasIdsFallback,
      preguntas
          .map((item) => (item['pregunta_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toList(),
    ]);
    final objetivoNorm = _normalizarTexto(materiaObjetivo);
    final preguntasIdsMateria = objetivoNorm.isEmpty
        ? const <String>[]
        : _mergeIdsPreservandoOrden([
            preguntas
                .where((item) {
                  final materia = _normalizarTexto(
                    (item['materia'] ?? '').toString(),
                  );
                  return materia == objetivoNorm;
                })
                .map((item) => (item['pregunta_id'] ?? '').toString().trim())
                .where((id) => id.isNotEmpty)
                .toList(),
          ]);
    final preguntasPrioritarias = preguntasIdsMateria.isNotEmpty
        ? preguntasIdsMateria
        : preguntasIdsGlobal;

    final muestraMateria = topMaterias.isNotEmpty
        ? _toInt(
            topMaterias.first['muestra_valida'] ??
                topMaterias.first['preguntas'],
          )
        : 0;
    final promedioObjetivo = topMaterias.isNotEmpty
        ? (_toDouble(topMaterias.first['promedio_segundos']) ?? promedio)
        : promedio;
    final cantidadPractica = _sugerirCantidadCoachVelocidad(
      muestraMateria: muestraMateria,
      cantidadIds: preguntasPrioritarias.length,
    );
    final tiempoPractica = _sugerirTiempoCoachVelocidad(promedioObjetivo);

    final detallePartes = <String>[
      'Promedio general: ${promedio.toStringAsFixed(1)} seg/preg.',
      'Clasificacion: $clasificacion.',
      'Confianza: $confianzaGlobal.',
      'Acierto global: ${tasaAciertoGlobal.toStringAsFixed(1)}%.',
      if (detalleMaterias.isNotEmpty) 'Materias mas lentas: $detalleMaterias',
      if (recomendacion.isNotEmpty) 'Recomendacion: $recomendacion',
    ];

    return {
      'id': 'coach_velocidad',
      'titulo': 'Coach de Velocidad',
      'resumen': resumenMaterias.isNotEmpty
          ? 'Mas tiempo por materia: $resumenMaterias.'
          : 'Promedio ${promedio.toStringAsFixed(1)} seg/preg. Clasificacion: $clasificacion.',
      'detalle': detallePartes.join(' '),
      'prompt': 'analisis de velocidad',
      'cta': 'Ver analisis de velocidad',
      'color': '#BBF7D0',
      'icono': 'bolt',
      'expandable': true,
      'cantidad_practica': cantidadPractica,
      'tiempo_practica': tiempoPractica,
      if (materiaObjetivo.isNotEmpty) 'materia': materiaObjetivo,
      if (preguntasPrioritarias.isNotEmpty)
        'pregunta_ids': preguntasPrioritarias,
      if (materiasPrioritarias.isNotEmpty)
        'materias_prioritarias': materiasPrioritarias,
      'metricas_velocidad': metricas,
      if (materias.isNotEmpty) 'materias_tiempo': materias,
      if (preguntas.isNotEmpty) 'preguntas_lentas': preguntas,
      if (preguntasIdsGlobal.isNotEmpty)
        'preguntas_lentas_ids': preguntasIdsGlobal,
      if (fuenteDatos != null && fuenteDatos.trim().isNotEmpty)
        'fuente_datos': fuenteDatos.trim(),
    };
  }

  Map<String, dynamic> _construirCardCoachMemoriaDesdeDetalle(
    Map<String, dynamic> data,
  ) {
    final resumen = (data['resumen'] ?? '').toString().trim();
    final plan = _asMap(data['plan_diario']);
    final riesgosRaw = data['riesgos'];
    final riesgos = riesgosRaw is List
        ? riesgosRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];
    final materiasPrioritarias = riesgos
        .map((item) => (item['materia'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final idsPrioritarias = _toStringList(data['pregunta_ids_prioritarias']);
    final idsRepaso = _toStringList(data['pregunta_ids_repaso']);
    final idsFallidas = _toStringList(data['pregunta_ids_fallidas']);

    int cantidadPractica =
        _toInt(plan['repaso']) + math.min(_toInt(plan['fallidas']), 10);
    if (cantidadPractica <= 0) {
      cantidadPractica = _toInt(plan['repaso']);
    }
    if (cantidadPractica <= 0) {
      cantidadPractica = _toInt(plan['fallidas']);
    }
    if (cantidadPractica <= 0) {
      cantidadPractica = idsPrioritarias.isNotEmpty
          ? idsPrioritarias.length
          : 20;
    }
    cantidadPractica = cantidadPractica.clamp(10, 25).toInt();
    if (idsPrioritarias.isNotEmpty &&
        cantidadPractica > idsPrioritarias.length) {
      cantidadPractica = idsPrioritarias.length;
    }
    if (idsPrioritarias.isNotEmpty && cantidadPractica <= 0) {
      cantidadPractica = idsPrioritarias.length.clamp(1, 25).toInt();
    }

    final tiempoPractica = _minutosSugeridosDesdePlan(
      cantidadPractica <= 0 ? 20 : cantidadPractica,
    ).clamp(20, 60).toInt();
    final totalCriticas = _toInt(data['total_criticas']);
    final totalRepasoVencidas = _toInt(data['total_repaso_vencidas']);
    final recordatorio = (data['recordatorio_repaso'] ?? '').toString().trim();

    final detallePartes = <String>[
      if (materiasPrioritarias.isNotEmpty)
        'Materias en mayor riesgo: ${materiasPrioritarias.take(3).join(', ')}.',
      if (recordatorio.isNotEmpty) recordatorio,
      if (totalCriticas > 0) 'Preguntas criticas detectadas: $totalCriticas.',
      if (totalRepasoVencidas > 0)
        'Repasos vencidos detectados: $totalRepasoVencidas.',
    ];

    return {
      'id': 'coach_memoria',
      'titulo': 'Coach de Memoria',
      'resumen': resumen.isEmpty
          ? 'Aun no hay historial suficiente para activar tu coach de memoria.'
          : resumen,
      'detalle': detallePartes.join(' '),
      'prompt': 'coach de memoria',
      'cta': 'Ver coach de memoria',
      'color': '#FECACA',
      'icono': 'memory',
      'expandable': true,
      'cantidad_practica': cantidadPractica,
      'tiempo_practica': tiempoPractica,
      if (idsPrioritarias.isNotEmpty) 'pregunta_ids': idsPrioritarias,
      if (idsRepaso.isNotEmpty) 'preguntas_repaso_ids': idsRepaso,
      if (idsFallidas.isNotEmpty) 'pregunta_ids_fallidas': idsFallidas,
      if (materiasPrioritarias.isNotEmpty)
        'materias_prioritarias': materiasPrioritarias,
      if (riesgos.isNotEmpty) 'riesgos': riesgos,
    };
  }

  Map<String, dynamic> _construirCardRadarRiesgoMateria({
    required Map<String, dynamic> analisis,
  }) {
    String nombreMateria(Map<String, dynamic> materia) {
      final raw = materia['materia'] ?? materia['nombre'];
      if (raw is Map) {
        final nombre = (raw['nombre'] ?? 'Materia').toString().trim();
        return nombre.isEmpty ? 'Materia' : nombre;
      }
      final nombre = (raw ?? 'Materia').toString().trim();
      return nombre.isEmpty ? 'Materia' : nombre;
    }

    double porcentajeDominio(Map<String, dynamic> materia) {
      return _toDouble(materia['porcentaje']) ??
          _toDouble(materia['tasa_dominio']) ??
          _toDouble(materia['dominio']) ??
          0.0;
    }

    double scoreRiesgo(Map<String, dynamic> materia) {
      final dominio = porcentajeDominio(materia).clamp(0.0, 100.0);
      final tiempo = _toDouble(materia['tiempo_recomendado_minutos']) ?? 0.0;
      final penalidadTiempo = tiempo >= 35 ? 8.0 : (tiempo >= 25 ? 4.0 : 0.0);
      final score = (100.0 - dominio) + penalidadTiempo;
      return score.clamp(0.0, 100.0);
    }

    final materiasRaw = analisis['analisis_materias'];
    final materias = materiasRaw is List
        ? materiasRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];

    final debilidades = _toStringList(analisis['debilidades']);
    if (materias.isEmpty) {
      final resumenFallback = debilidades.isEmpty
          ? 'Sin datos por materia aun. Activa el radar para detectar focos.'
          : 'Focos sugeridos: ${debilidades.take(2).join(', ')}.';
      return {
        'id': 'radar_riesgo_materia',
        'titulo': 'Radar de riesgo por materia',
        'resumen': resumenFallback,
        'detalle':
            'Abrir el radar muestra tu semaforo de materias (rojo, ambar, verde) para priorizar repaso.',
        'prompt': 'radar de riesgo por materia',
        'cta': 'Ver radar de materias',
        'color': '#FCD34D',
        'icono': 'radar',
        'expandable': true,
      };
    }

    final ordenadas = [...materias]
      ..sort((a, b) => scoreRiesgo(b).compareTo(scoreRiesgo(a)));
    final top = ordenadas.first;
    final topNombre = nombreMateria(top);
    final topScore = scoreRiesgo(top);
    final topEtiquetas = ordenadas
        .take(3)
        .map((e) => nombreMateria(e))
        .where((e) => e.trim().isNotEmpty)
        .toSet()
        .toList();
    final resumen = topEtiquetas.length > 1
        ? 'Materias con mayor riesgo: ${topEtiquetas.join(', ')}.'
        : '$topNombre es la materia con mayor riesgo hoy.';

    return {
      'id': 'radar_riesgo_materia',
      'titulo': 'Radar de riesgo por materia',
      'resumen': resumen,
      'detalle':
          'Riesgo estimado en $topNombre: ${topScore.toStringAsFixed(1)}%. Abre el radar para ver el semaforo y atacar primero las materias rojas.',
      'prompt': 'radar de riesgo por materia',
      'cta': 'Ver radar de materias',
      'color': '#FCD34D',
      'icono': 'radar',
      'expandable': true,
    };
  }

  bool _esCacheVigente(DateTime storedAt, Duration ttl) {
    return DateTime.now().difference(storedAt) <= ttl;
  }

  Map<String, dynamic> _copiarMapa(Map<String, dynamic> map) {
    return Map<String, dynamic>.from(map);
  }

  List<Map<String, dynamic>> _copiarListaMaps(List<Map<String, dynamic>> list) {
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  String _cacheKeyMateria(String userId, String materia) {
    final usuario = userId.trim();
    final materiaNorm = _normalizarTexto(materia);
    return '$usuario::$materiaNorm';
  }

  void _podarCacheSiExcede<T>(Map<String, _TutorCacheEntry<T>> cache) {
    if (cache.length <= _maxEntradasCacheVelocidad) return;
    final masAntigua = cache.entries.reduce(
      (a, b) => a.value.storedAt.isBefore(b.value.storedAt) ? a : b,
    );
    cache.remove(masAntigua.key);
  }

  Map<String, dynamic>? _leerCacheCoachVelocidad(String userId) {
    final key = userId.trim();
    if (key.isEmpty) return null;
    final entry = _cacheCoachVelocidad[key];
    if (entry == null) return null;
    if (!_esCacheVigente(entry.storedAt, _cacheVelocidadTtl)) {
      _cacheCoachVelocidad.remove(key);
      return null;
    }
    return _copiarMapa(entry.value);
  }

  void _guardarCacheCoachVelocidad(String userId, Map<String, dynamic> card) {
    final key = userId.trim();
    if (key.isEmpty) return;
    _cacheCoachVelocidad[key] = _TutorCacheEntry(
      _copiarMapa(card),
      DateTime.now(),
    );
    _podarCacheSiExcede(_cacheCoachVelocidad);
  }

  List<Map<String, dynamic>>? _leerCacheListaMaterias(
    Map<String, _TutorCacheEntry<List<Map<String, dynamic>>>> cache,
    String key,
  ) {
    final entry = cache[key];
    if (entry == null) return null;
    if (!_esCacheVigente(entry.storedAt, _cacheVelocidadDetalleMateriaTtl)) {
      cache.remove(key);
      return null;
    }
    return _copiarListaMaps(entry.value);
  }

  void _guardarCacheListaMaterias(
    Map<String, _TutorCacheEntry<List<Map<String, dynamic>>>> cache,
    String key,
    List<Map<String, dynamic>> value,
  ) {
    cache[key] = _TutorCacheEntry(_copiarListaMaps(value), DateTime.now());
    _podarCacheSiExcede(cache);
  }

  Map<String, dynamic> _cardFallback({
    required String id,
    required String titulo,
    required String prompt,
    required String color,
    required String icono,
    required String resumen,
  }) {
    return {
      'id': id,
      'titulo': titulo,
      'resumen': resumen,
      'detalle': resumen,
      'prompt': prompt,
      'cta': 'Abrir en chat',
      'color': color,
      'icono': icono,
      'expandable': true,
    };
  }

  int _intervaloRepeticionInmediata(String preguntaId) {
    final id = preguntaId.trim();
    if (id.isEmpty) return 10;
    final hash = id.codeUnits.fold<int>(0, (acc, ch) => (acc + ch) % 997);
    return 10 + (hash % 11); // 10..20
  }

  String _semaforoPorTasa(double tasa) {
    if (tasa < 40) return 'rojo';
    if (tasa < 60) return 'amarillo';
    return 'verde';
  }

  Map<String, dynamic> _recomendacionMateriaFallback(
    String materia,
    double porcentaje,
    String nivel,
  ) {
    final cantidad = porcentaje < 50 ? 20 : 12;
    final tiempo = porcentaje < 50 ? 25 : 15;
    return {
      'mensaje':
          '$materia esta en nivel $nivel (${porcentaje.toStringAsFixed(0)}%). Refuerza conceptos base y practica casos aplicados.',
      'focos': [
        'Repasar teoria esencial de la materia.',
        'Resolver preguntas tipo examen en bloques cortos.',
        'Analizar cada error antes de pasar a la siguiente pregunta.',
      ],
      'cantidad_preguntas': cantidad,
      'tiempo_minutos': tiempo,
    };
  }
}
