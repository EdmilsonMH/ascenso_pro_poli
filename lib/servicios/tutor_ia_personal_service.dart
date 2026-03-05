import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class TutorIAPersonalService {
  // Ya no inicializamos el cliente estÃƒÂ¡ticamente aquÃƒÂ­ para evitar el crash al cargar la clase
  SupabaseClient get _supabase => SupabaseService.client;
  static const bool _habilitarSqlDirecto = false;

  /// 1.1 Ã°Å¸â€œÅ  AnÃƒÂ¡lisis Completo del Perfil
  /// Analiza el perfil completo del usuario y genera un diagnÃƒÂ³stico detallado.
  Future<Map<String, dynamic>> analizarPerfilCompleto(
    String userId, {
    Map<String, dynamic>? perfilUsuario,
  }) async {
    if (!SupabaseService.isInitialized) {
      debugPrint(
        'ADVERTENCIA: Supabase no inicializado. Usando datos Mock para el Tutor.',
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

      // 3) exposicion_pregunta (preguntas dominadas)
      final totalDominadasResponse = await _supabase
          .from('exposicion_pregunta')
          .select('id')
          .eq('usuario_id', userId)
          .eq('estado_dominio', 'dominada')
          .count();
      final totalDominadas = totalDominadasResponse.count;

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
      final probabilidad = await _rpcComoMapa(
        functionName: 'fn_calcular_probabilidad_aprobacion_dinamica',
        params: params,
      );

      final progresoHoy = await _obtenerProgresoHoy(usuario);
      final metaHoy = await _obtenerMetaDiariaHoy(usuario);
      final planHoy = await obtenerResumenPlanDiarioEstructurado(
        userId: usuario,
        planBase: plan,
        progresoBase: progreso,
        probabilidadBase: probabilidad,
      );
      final queEstudiar = await obtenerResumenQueEstudiarEstructurado(
        userId: usuario,
      );
      final ultimaSesion = await obtenerResumenUltimaSesionEstructurado(
        userId: usuario,
      );
      final velocidad = await obtenerAnalisisVelocidadEstructurado(
        userId: usuario,
      );
      final riesgos = await obtenerMateriasRiesgoEstructurado(userId: usuario);
      final olvido = await obtenerPrediccionOlvidoEstructurado(userId: usuario);
      final motivacion = construirMensajeMotivacionalEstructurado(
        progreso: progreso,
        probabilidad: probabilidad,
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
          _toDouble(probabilidad?['probabilidad_aprobacion']) ??
          _toDouble(analisis['tasa_acierto']) ??
          0.0;
      final racha = _toInt(analisis['racha_dias']);
      final nivel = (analisis['nivel_global'] ?? 'INICIAL').toString();

      final totalDominadas = _toInt(progreso?['preguntas_dominadas']);
      final faltantes = (3000 - totalDominadas).clamp(0, 3000);
      final ritmoActual = _toDouble(progreso?['ritmo_actual_dia']) ?? 0;
      final diasEstimados = ritmoActual > 0
          ? (faltantes / ritmoActual).ceil()
          : 0;
      final proyeccionTiempo = {
        'id': 'proyeccion_tiempo',
        'titulo': 'Proyeccion de Tiempo para Completar',
        'resumen': diasEstimados > 0
            ? 'A este ritmo te tomaria ~$diasEstimados dias completar tus faltantes.'
            : 'Aun no hay ritmo suficiente para proyectar tiempo real.',
        'detalle':
            'Dominadas: $totalDominadas/3000. Faltantes: $faltantes. Ritmo actual: ${ritmoActual.toStringAsFixed(2)} preguntas/dia.',
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
          riesgos,
          velocidad,
          proyeccionTiempo,
          ultimaSesion,
          olvido,
          motivacion,
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

  Future<Map<String, dynamic>> obtenerResumenPlanDiarioEstructurado({
    required String userId,
    Map<String, dynamic>? planBase,
    Map<String, dynamic>? progresoBase,
    Map<String, dynamic>? probabilidadBase,
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
    final plan =
        planBase ??
        await _rpcComoMapa(
          functionName: 'fn_generar_plan_adaptativo',
          params: params,
        );
    final progreso =
        progresoBase ??
        await _rpcComoMapa(
          functionName: 'fn_calcular_progreso_dinamico',
          params: params,
        );
    final probabilidad =
        probabilidadBase ??
        await _rpcComoMapa(
          functionName: 'fn_calcular_probabilidad_aprobacion_dinamica',
          params: params,
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
    final diasRestantes = _toInt(plan['dias_restantes']);
    final faltantes = _toInt(plan['preguntas_faltantes']);
    final prob = _toDouble(probabilidad?['probabilidad_aprobacion']) ?? 0;
    final ritmoActual = _toDouble(progreso?['ritmo_actual_dia']) ?? 0;
    final ritmoNecesario = _toDouble(progreso?['ritmo_necesario_dia']) ?? 0;

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
    };
  }

  Future<Map<String, dynamic>> obtenerResumenQueEstudiarEstructurado({
    required String userId,
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
            'tasa_dominio, dominio_hace_7_dias, tiempo_recomendado_minutos, temas_debiles, materia:materia_id(nombre)',
          )
          .eq('usuario_id', userId)
          .order('tasa_dominio', ascending: true)
          .limit(1);

      if (raw.isEmpty || raw.first is! Map) {
        return _cardFallback(
          id: 'materia_prioritaria',
          titulo: 'Materia Prioritaria',
          prompt: 'que estudiar hoy',
          color: '#C7D2FE',
          icono: 'school',
          resumen: 'Aun no hay datos por materia para priorizar.',
        );
      }

      final row = Map<String, dynamic>.from(raw.first as Map);
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

      return {
        'id': 'materia_prioritaria',
        'titulo': 'Materia Prioritaria',
        'resumen': '$nombre (${tasa.toStringAsFixed(1)}%) es tu foco de hoy.',
        'detalle':
            'Tendencia: $tendencia. Tiempo sugerido: ${tiempo > 0 ? tiempo : 25} minutos. Temas: ${temas.isEmpty ? 'sin detalle' : temas.take(3).join(', ')}.',
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

    try {
      final List<dynamic> raw = await _supabase
          .from('respuesta_usuario')
          .select(
            'tiempo_total_respuesta, fue_omitida, es_correcta, pregunta:pregunta_id(materia:materia_id(nombre))',
          )
          .eq('usuario_id', userId)
          .order('respondida_at', ascending: false)
          .limit(400);

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
          resumen: 'Aun no hay tiempos validos para evaluar tu velocidad.',
        );
      }

      final tiempos = rows
          .map((r) => _toDouble(r['tiempo_total_respuesta']) ?? 0)
          .where((t) => t > 0)
          .toList();
      if (tiempos.isEmpty) {
        return _cardFallback(
          id: 'coach_velocidad',
          titulo: 'Coach de Velocidad',
          prompt: 'analisis de velocidad',
          color: '#BBF7D0',
          icono: 'bolt',
          resumen: 'Aun no hay tiempos validos para evaluar tu velocidad.',
        );
      }

      final promedio = _promedio(tiempos);
      final impulsiva = tiempos.where((t) => t < 8).length;
      final pctImpulsiva = tiempos.isEmpty
          ? 0
          : (impulsiva * 100.0 / tiempos.length);
      final clasificacion = promedio < 8
          ? 'Impulsivo'
          : (promedio <= 20 ? 'Optimo' : 'Lento');
      final recomendacion = promedio < 8
          ? 'Baja un poco la velocidad y relee palabras clave (NO/EXCEPTO).'
          : (promedio <= 20
                ? 'Tu ritmo es saludable. Mantiene precision con lectura activa.'
                : 'Acelera descarte de opciones para ganar tiempo por pregunta.');

      final Map<String, List<double>> tiemposPorMateria = {};
      for (final row in rows) {
        final tiempo = _toDouble(row['tiempo_total_respuesta']) ?? 0;
        if (tiempo <= 0) continue;

        final pregunta = _asMap(row['pregunta']);
        final materia = _asMap(pregunta['materia']);
        final nombre = (materia['nombre'] ?? '').toString().trim();
        if (nombre.isEmpty) continue;
        tiemposPorMateria.putIfAbsent(nombre, () => <double>[]).add(tiempo);
      }

      final rankingMaterias =
          tiemposPorMateria.entries.map((entry) {
            final lista = entry.value;
            final total = lista.fold<double>(0.0, (a, b) => a + b);
            return <String, dynamic>{
              'materia': entry.key,
              'promedio_segundos': _promedio(lista),
              'total_segundos': total,
              'preguntas': lista.length,
            };
          }).toList()..sort((a, b) {
            final aProm = _toDouble(a['promedio_segundos']) ?? 0;
            final bProm = _toDouble(b['promedio_segundos']) ?? 0;
            if (bProm != aProm) return bProm.compareTo(aProm);
            final aTotal = _toDouble(a['total_segundos']) ?? 0;
            final bTotal = _toDouble(b['total_segundos']) ?? 0;
            return bTotal.compareTo(aTotal);
          });

      final topMaterias = rankingMaterias.take(3).toList();
      final resumenMaterias = topMaterias
          .map((item) {
            final nombre = (item['materia'] ?? 'Materia').toString();
            final prom = _toDouble(item['promedio_segundos']) ?? 0;
            return '$nombre ${prom.toStringAsFixed(1)}s';
          })
          .join(', ');

      final detalleMaterias = topMaterias
          .map((item) {
            final nombre = (item['materia'] ?? 'Materia').toString();
            final prom = _toDouble(item['promedio_segundos']) ?? 0;
            final totalSeg = _toDouble(item['total_segundos']) ?? 0;
            final preguntas = _toInt(item['preguntas']);
            final totalMin = totalSeg / 60.0;
            return '$nombre: ${prom.toStringAsFixed(1)} seg/preg en $preguntas preg (${totalMin.toStringAsFixed(1)} min).';
          })
          .join(' ');

      return {
        'id': 'coach_velocidad',
        'titulo': 'Coach de Velocidad',
        'resumen': resumenMaterias.isNotEmpty
            ? 'Mas tiempo por materia: $resumenMaterias.'
            : 'Promedio ${promedio.toStringAsFixed(1)} seg/preg. Clasificacion: $clasificacion.',
        'detalle':
            'Promedio general: ${promedio.toStringAsFixed(1)} seg/preg. Clasificacion: $clasificacion. Impulsividad (<8s): ${pctImpulsiva.toStringAsFixed(1)}%. ${detalleMaterias.isNotEmpty ? 'Materias mas lentas: $detalleMaterias ' : ''}Recomendacion: $recomendacion',
        'prompt': 'analisis de velocidad',
        'cta': 'Ver analisis de velocidad',
        'color': '#BBF7D0',
        'icono': 'bolt',
        'expandable': true,
        if (rankingMaterias.isNotEmpty) 'materias_tiempo': rankingMaterias,
      };
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

  Future<Map<String, dynamic>> obtenerMateriasRiesgoEstructurado({
    required String userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return _cardFallback(
        id: 'radar_riesgo',
        titulo: 'Radar de Riesgo por Materias',
        prompt: 'cuales son mis materias en riesgo',
        color: '#FECACA',
        icono: 'radar',
        resumen: 'Inicia sesion para detectar materias en riesgo.',
      );
    }

    try {
      final List<dynamic> raw = await _supabase
          .from('dominio_materia')
          .select(
            'tasa_dominio, dominio_hace_7_dias, materia:materia_id(nombre)',
          )
          .eq('usuario_id', userId)
          .lt('tasa_dominio', 60)
          .order('tasa_dominio', ascending: true)
          .limit(5);

      final rows = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (rows.isEmpty) {
        return {
          'id': 'radar_riesgo',
          'titulo': 'Radar de Riesgo por Materias',
          'resumen': 'No detecto materias criticas (<60%) en este momento.',
          'detalle':
              'Mantienes un control aceptable. Revisa periodicamente para evitar retrocesos.',
          'prompt': 'cuales son mis materias en riesgo',
          'cta': 'Ver materias en riesgo',
          'color': '#FECACA',
          'icono': 'radar',
          'expandable': true,
          'riesgos': <Map<String, dynamic>>[],
        };
      }

      final riesgos = rows.map((r) {
        final materia = _asMap(r['materia']);
        final nombre = (materia['nombre'] ?? 'Materia').toString();
        final tasa = _toDouble(r['tasa_dominio']) ?? 0;
        final hace7 = _toDouble(r['dominio_hace_7_dias']);
        final delta = hace7 == null ? 0.0 : (tasa - hace7);
        final tendencia = delta >= 1.5
            ? 'mejorando'
            : (delta <= -1.5 ? 'empeorando' : 'estable');
        return {
          'materia': nombre,
          'tasa': tasa,
          'tendencia': tendencia,
          'semaforo': _semaforoPorTasa(tasa),
        };
      }).toList();

      final topTxt = riesgos
          .take(3)
          .map(
            (e) =>
                '${e['materia']} ${(_toDouble(e['tasa']) ?? 0).toStringAsFixed(1)}%',
          )
          .join(', ');

      return {
        'id': 'radar_riesgo',
        'titulo': 'Radar de Riesgo por Materias',
        'resumen': 'Materias en riesgo detectadas: $topTxt.',
        'detalle':
            'Umbral de riesgo aplicado: dominio < 60%. Prioriza la primera materia hoy.',
        'prompt': 'cuales son mis materias en riesgo',
        'cta': 'Ver materias en riesgo',
        'color': '#FECACA',
        'icono': 'radar',
        'expandable': true,
        'riesgos': riesgos,
      };
    } catch (_) {
      return _cardFallback(
        id: 'radar_riesgo',
        titulo: 'Radar de Riesgo por Materias',
        prompt: 'cuales son mis materias en riesgo',
        color: '#FECACA',
        icono: 'radar',
        resumen: 'No pude cargar tu radar de riesgo ahora.',
      );
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
        resumen: 'Inicia sesion para calcular riesgo de olvido.',
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
          'cta': 'Ver olvido',
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
        'cta': 'Ver prediccion de olvido',
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
        resumen: 'No pude cargar prediccion de olvido ahora.',
      );
    }
  }

  Map<String, dynamic> construirMensajeMotivacionalEstructurado({
    Map<String, dynamic>? progreso,
    Map<String, dynamic>? probabilidad,
  }) {
    final dominadas = _toInt(progreso?['preguntas_dominadas']);
    final porcentaje = _toDouble(progreso?['porcentaje_completado']) ?? 0;
    final ritmoActual = _toDouble(progreso?['ritmo_actual_dia']) ?? 0;
    final ritmoNecesario = _toDouble(progreso?['ritmo_necesario_dia']) ?? 0;
    final probAprobacion = _toDouble(probabilidad?['probabilidad_aprobacion']);

    late final String resumen;
    late final String detalle;
    if (progreso?['esta_adelantado'] == true) {
      resumen =
          'Excelente ritmo: vas adelantado con ${porcentaje.toStringAsFixed(1)}% completado.';
      detalle =
          'Sigue con la misma constancia para ganar margen de repaso antes del examen.';
    } else if (progreso?['esta_atrasado'] == true ||
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

      final usarContextoBd = _requiereContextoBdParaChat(
        mensaje: mensajeLimpio,
        contexto: contextoBase,
      );
      if (usarContextoBd &&
          (userId == null || userId.isEmpty || userId == 'user_test_id')) {
        return 'Para responder eso con precision necesito tu sesion activa. Cierra sesion, vuelve a ingresar y consultame de nuevo.';
      }

      final contextoBd = usarContextoBd
          ? await _contextoUsuarioChatDesdeBD(userId)
          : const <String, dynamic>{};
      final contextoFinal = <String, dynamic>{
        ...contextoBase,
        if (usarContextoBd && contextoBd.isNotEmpty)
          'contexto_bd_usuario': contextoBd,
      };

      final prompt = _construirPromptTutor(
        mensaje: mensajeLimpio,
        contextoFinal: contextoFinal,
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
        for (final key in const [
          'respuesta',
          'mensaje',
          'text',
          'diagnostico',
        ]) {
          final value = parsed[key];
          if (value is String && value.trim().isNotEmpty) {
            return _normalizarRespuestaTutor(value);
          }
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
      return 'Si. Este tutor usa DeepSeek y se conecta a tu progreso en Supabase para personalizar las recomendaciones. Si quieres, ahora mismo te propongo tu plan de hoy.';
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

    if (_esConsultaMateriasRiesgo(mensaje)) {
      return await _resolverConsultaMateriasRiesgo(userId: userId);
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

  bool _esConsultaMateriasRiesgo(String mensaje) {
    final t = _normalizarConsultaTexto(mensaje);
    if (t.isEmpty) return false;
    return _contieneAlgunaFrase(t, const [
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
    final probabilidad = await _rpcComoMapa(
      functionName: 'fn_calcular_probabilidad_aprobacion_dinamica',
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

    if (progreso == null && probabilidad == null) {
      return null;
    }

    final preguntasDominadas = _toInt(progreso?['preguntas_dominadas']);
    final faltantes = (3000 - preguntasDominadas).clamp(0, 3000).toInt();
    final porcentajeCompletado =
        _toDouble(progreso?['porcentaje_completado']) ?? 0.0;
    final ritmoActual = _toDouble(progreso?['ritmo_actual_dia']) ?? 0.0;
    final ritmoNecesario = _toDouble(progreso?['ritmo_necesario_dia']) ?? 0.0;
    final diasRestantes = _toInt(progreso?['dias_restantes']);
    final recomendacionPreguntasDia = _toInt(
      progreso?['recomendacion_preguntas_dia'],
    );

    final probAprobacion = _toDouble(probabilidad?['probabilidad_aprobacion']);
    final puntajeEstimado = _toDouble(probabilidad?['puntaje_estimado']);
    final nivelConfianza = (probabilidad?['nivel_confianza'] ?? '')
        .toString()
        .trim()
        .replaceAll('_', ' ');

    final fechaExamen =
        _parseFechaFlexible(progreso?['fecha_examen']) ??
        _parseFechaFlexible(dias?['fecha_examen']);

    DateTime? fechaEstimadaListo;
    if (faltantes <= 0) {
      fechaEstimadaListo = DateTime.now();
    } else if (ritmoActual > 0) {
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

    partes.add(
      'Hoy vas $preguntasDominadas/3000 (${porcentajeCompletado.toStringAsFixed(1)}%) con ritmo actual de ${ritmoActual.toStringAsFixed(2)} preguntas por dia.',
    );

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

    if (probAprobacion != null || puntajeEstimado != null) {
      final probTxt = probAprobacion == null
          ? null
          : '${probAprobacion.toStringAsFixed(1)}%';
      final puntajeTxt = puntajeEstimado?.toStringAsFixed(1);
      if (probTxt != null && puntajeTxt != null) {
        partes.add(
          'Tu probabilidad estimada de aprobacion es $probTxt (confianza $nivelConfianza) con puntaje proyectado de $puntajeTxt.',
        );
      } else if (probTxt != null) {
        partes.add(
          'Tu probabilidad estimada de aprobacion es $probTxt (confianza $nivelConfianza).',
        );
      }
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
    final probabilidad = await _rpcComoMapa(
      functionName: 'fn_calcular_probabilidad_aprobacion_dinamica',
      params: params,
    );

    if (plan == null) return null;

    final totalDia = _toInt(plan['total_preguntas_dia']);
    final nuevas = _toInt(plan['cantidad_nuevas']);
    final repaso = _toInt(plan['cantidad_repaso']);
    final diasRestantes = _toInt(plan['dias_restantes']);
    final faltantes = _toInt(plan['preguntas_faltantes']);
    final mensajeIa = (plan['mensaje_ia'] ?? '').toString().trim();

    final idsMaterias = _toStringList(plan['materias_prioritarias']);
    final materiasPrioritarias = await _resolverNombresMateriasDesdeIds(
      idsMaterias,
    );
    final materiasTxt = materiasPrioritarias.isEmpty
        ? 'Sin materias criticas detectadas por ahora.'
        : materiasPrioritarias.take(3).join(', ');

    final prob = _toDouble(probabilidad?['probabilidad_aprobacion']);
    final ritmoActual = _toDouble(progreso?['ritmo_actual_dia']) ?? 0;
    final ritmoNecesario = _toDouble(progreso?['ritmo_necesario_dia']) ?? 0;

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

  Future<String?> _resolverConsultaMateriasRiesgo({
    required String? userId,
  }) async {
    if (_sesionInvalida(userId)) {
      return 'Para detectar materias en riesgo necesito tu sesion activa. Cierra sesion, vuelve a ingresar y consultame de nuevo.';
    }

    try {
      final List<dynamic> raw = await _supabase
          .from('dominio_materia')
          .select(
            'tasa_dominio, dominio_hace_7_dias, tiempo_recomendado_minutos, '
            'total_preguntas_vistas, total_incorrectas, '
            'materia:materia_id(nombre, total_preguntas_banco)',
          )
          .eq('usuario_id', userId!)
          .lt('tasa_dominio', 60)
          .order('tasa_dominio', ascending: true)
          .limit(10);

      final rows = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (rows.isEmpty) {
        return 'No detecto materias en riesgo critico (<60%) en este momento.';
      }

      final resumen = rows
          .take(3)
          .map((r) {
            final materia = _asMap(r['materia']);
            final nombre = (materia['nombre'] ?? 'Materia').toString();
            final tasa = _toDouble(r['tasa_dominio']) ?? 0;
            final hace7 = _toDouble(r['dominio_hace_7_dias']);
            final delta = hace7 == null ? 0.0 : (tasa - hace7);
            final tendencia = delta >= 1.5
                ? 'mejorando'
                : (delta <= -1.5 ? 'empeorando' : 'estable');
            final totalBanco = _toInt(materia['total_preguntas_banco']);
            final vistas = _toInt(r['total_preguntas_vistas']);
            final pendientes = totalBanco > 0
                ? (totalBanco - vistas).clamp(0, totalBanco)
                : 0;
            final tiempo = _toInt(r['tiempo_recomendado_minutos']);
            return '$nombre ${tasa.toStringAsFixed(1)}% (tendencia $tendencia, pendientes $pendientes, sugerido ${tiempo > 0 ? tiempo : 25} min/dia)';
          })
          .join('; ');

      return 'Materias en riesgo detectadas: $resumen.';
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
    final probabilidad = await _rpcComoMapa(
      functionName: 'fn_calcular_probabilidad_aprobacion_dinamica',
      params: params,
    );
    if (progreso == null) return null;

    final dominadas = _toInt(progreso['preguntas_dominadas']);
    final diasTranscurridos = _toInt(progreso['dias_transcurridos']);
    final ritmoActual = _toDouble(progreso['ritmo_actual_dia']) ?? 0;
    final ritmoNecesario = _toDouble(progreso['ritmo_necesario_dia']) ?? 0;
    final porcentaje = _toDouble(progreso['porcentaje_completado']) ?? 0;
    final probAprobacion = _toDouble(probabilidad?['probabilidad_aprobacion']);

    late final String mensaje;
    if (progreso['esta_adelantado'] == true) {
      mensaje =
          'Excelente trabajo: vas adelantado con $dominadas preguntas dominadas en $diasTranscurridos dias (${porcentaje.toStringAsFixed(1)}%). Manteniendo este ritmo, llegaras con margen para repasar.';
    } else if (progreso['esta_atrasado'] == true ||
        progreso['debe_acelerar'] == true) {
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
    } catch (_) {
      return null;
    }
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
          .limit(2000);

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
          .limit(2000);

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

  // Panel IA (DeepSeek controla tarjetas y mensajes)
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
      debugPrint('Error llamando a DeepSeek: $e');
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

  // Fallback en caso de que DeepSeek falle o no haya internet
  String _generarDiagnosticoBasico(String nivel, List<String> debilidades) {
    if (debilidades.isEmpty || debilidades.first.contains('proceso')) {
      return "Ã‚Â¡Bienvenido! Empieza tus prÃƒÂ¡cticas para que pueda analizar tu rendimiento.";
    }
    return "Nivel $nivel detectado. Debemos reforzar ${debilidades.first.split('(').first}. Ã‚Â¡Sigue asÃƒÂ­!";
  }

  // --- Funciones Auxiliares de LÃƒÂ³gica de Negocio ---

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
      for (final key in const ['respuesta', 'mensaje', 'text', 'diagnostico']) {
        final value = parsed[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }

    return text;
  }

  String _mensajeErrorTutorDesdeFuncion(FunctionException e) {
    final status = e.status;
    final detalle = _resumirTextoError(_detalleComoTexto(e.details), max: 220);
    final rateLimit = _detallePareceRateLimit(detalle);

    if (status == 429 || rateLimit) {
      return 'El tutor IA esta con alta demanda ahora (limite temporal de DeepSeek). Intenta nuevamente en 1 o 2 minutos.';
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
      final extra = detalle.isEmpty ? 'Fallo al consultar DeepSeek.' : detalle;
      return 'Error $status (DeepSeek): $extra';
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

  String _normalizarTexto(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
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
      // El dominio calculado desde respuestas es el valor real mÃ¡s reciente.
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
    final probActual = (porcentaje * 0.9).clamp(5, 95);
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
        'probabilidad_actual': probActual,
        'proyeccion_7_dias': (probActual + 5).clamp(5, 99),
        'proyeccion_14_dias': (probActual + 9).clamp(5, 99),
        'proyeccion_30_dias': (probActual + 14).clamp(5, 99),
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
        'tiempo_diario_sugerido': porcentaje < 50 ? 30 : 20,
        'tema_prioritario': 'Fundamentos de $materia',
        'objetivo': 'Alcanzar 80% en 10 dias',
      },
    };
  }

  Map<String, dynamic> _generarDatosMockEmergencia() {
    return {
      'nivel_global': 'CALCULANDO...',
      'fortalezas': ['Analisis en proceso...'],
      'debilidades': ['Analisis en proceso...'],
      'analisis_materias': [
        {
          'materia': 'Derechos Humanos',
          'porcentaje': 60.0,
          'nivel': 'INTERMEDIO',
          'tipo': 'debilidad',
        },
      ],
      'resumen_materias':
          'Tienes 0 materias fuertes y 1 en mejora. Pulsa Revisar para ver el detalle por materia.',
      'materias_criticas': [],
      'preguntas_dominadas': 0,
      'tasa_acierto': 0.0,
      'velocidad_promedio': 0.0,
      'diagnostico':
          'El sistema esta recopilando tus primeros datos. Vuelve pronto.',
      'panel_ia': _panelBasico('CALCULANDO...', ['Analisis en proceso...']),
    };
  }

  List<String> _atajosTutorInicio() {
    return const [
      'dame mi plan diario',
      'que estudiar hoy',
      'analiza mi ultima sesion',
      'analisis de velocidad',
      'cuales son mis materias en riesgo',
      'prediccion de olvido',
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
        'preguntas_objetivo': 20,
        'minutos_objetivo': 30,
        'preguntas_completadas': 0,
        'minutos_completados': 0,
        'cantidad_practica': 20,
        'tiempo_practica': 30,
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


