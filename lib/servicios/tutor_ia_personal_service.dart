import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class TutorIAPersonalService {
  // Ya no inicializamos el cliente estÃ¡ticamente aquÃ­ para evitar el crash al cargar la clase
  SupabaseClient get _supabase => SupabaseService.client;

  /// 1.1 ðŸ“Š AnÃ¡lisis Completo del Perfil
  /// Analiza el perfil completo del usuario y genera un diagnÃ³stico detallado.
  Future<Map<String, dynamic>> analizarPerfilCompleto(
    String userId, {
    Map<String, dynamic>? perfilUsuario,
  }) async {
    if (!SupabaseService.isInitialized) {
      print(
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
      final List<dynamic> dominiosResponse = await _supabase
          .from('dominio_materia')
          .select('tasa_dominio, materia!inner(nombre)')
          .eq('usuario_id', userId);
      final dominios = dominiosResponse.cast<Map<String, dynamic>>();

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
      final respuestas = respuestasResponse.cast<Map<String, dynamic>>();
      final respuestasValidas = respuestas.where((r) {
        final omitida = r['fue_omitida'] == true;
        final esCorrecta = r['es_correcta'];
        return !omitida && esCorrecta is bool;
      }).toList();

      final totalRespuestas = respuestasValidas.length;
      final totalCorrectas =
          respuestasValidas.where((r) => r['es_correcta'] == true).length;
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

      final tiempoTotalMinutos =
          _toInt(estadistica['tiempo_total_estudio_minutos']);
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
      print('Error en analizarPerfilCompleto: $e');
      return _generarDatosMockEmergencia();
    }
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
      final userIdRaw = (contextoBase['user_id'] ??
              contextoBase['usuario_id'] ??
              '')
          .toString()
          .trim();
      final userId = userIdRaw.isEmpty ? null : userIdRaw;

      final sqlDirecta = _extraerConsultaSqlSegura(mensajeLimpio);
      if (sqlDirecta != null) {
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
        for (final key in const ['respuesta', 'mensaje', 'text', 'diagnostico']) {
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
        params: {
          'p_usuario_id': userId,
          'p_sql': sql,
          'p_max_rows': 25,
        },
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

    final mencionaRobot = t.contains('robot') ||
        t.contains('amigable') ||
        t.contains('frio') ||
        t.contains('muy tecnico');
    if (mencionaRobot) {
      return '${saludo}tienes razon, ajusto el tono desde ahora. Te respondere mas claro y natural. Si quieres, empezamos con un plan rapido para hoy segun tus materias mas debiles.';
    }

    final preguntaIdentidad = t.contains('eres gemini') ||
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
    final limpio = nombreCompleto
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (limpio.isEmpty) return nombreCompleto.trim();
    return limpio.split(' ').first;
  }

  Future<String?> _resolverConsultaDeterministica({
    required String mensaje,
    required String? userId,
    required Map<String, dynamic> contexto,
  }) async {
    if (_esConsultaPreparacionExamen(mensaje)) {
      return await _resolverConsultaPreparacionExamen(userId: userId);
    }

    if (!_esConsultaRanking(mensaje)) return null;
    if (userId == null || userId.isEmpty || userId == 'user_test_id') {
      return 'No puedo leer tu ranking porque no detecto una sesion valida. Cierra sesion, vuelve a ingresar y consulta de nuevo.';
    }

    final categoria = await _resolverCategoriaUsuario(
      userId: userId,
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

  bool _esConsultaPreparacionExamen(String mensaje) {
    final normalizado = _normalizarTexto(mensaje)
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalizado.isEmpty) return false;

    const patronesFuertes = <String>[
      'para cuando estare listo',
      'cuando estare listo para mi examen',
      'cuando estare preparado para mi examen',
      'llego a tiempo al examen',
      'cuanto falta para mi examen',
      'cuando aprobare el examen',
    ];
    for (final p in patronesFuertes) {
      if (normalizado.contains(p)) return true;
    }

    final mencionaExamen = normalizado.contains('examen') ||
        normalizado.contains('ascenso') ||
        normalizado.contains('aprobar') ||
        normalizado.contains('aprobare');
    final mencionaTiempo = normalizado.contains('cuando') ||
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
    final recomendacionPreguntasDia =
        _toInt(progreso?['recomendacion_preguntas_dia']);

    final probAprobacion = _toDouble(probabilidad?['probabilidad_aprobacion']);
    final puntajeEstimado = _toDouble(probabilidad?['puntaje_estimado']);
    final nivelConfianza = (probabilidad?['nivel_confianza'] ?? '')
        .toString()
        .trim()
        .replaceAll('_', ' ');

    final fechaExamen = _parseFechaFlexible(
          progreso?['fecha_examen'],
        ) ??
        _parseFechaFlexible(dias?['fecha_examen']);

    DateTime? fechaEstimadaListo;
    if (faltantes <= 0) {
      fechaEstimadaListo = DateTime.now();
    } else if (ritmoActual > 0) {
      final diasParaCompletar = (faltantes / ritmoActual).ceil();
      fechaEstimadaListo = DateTime.now().add(Duration(days: diasParaCompletar));
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
      final probTxt =
          probAprobacion == null ? null : '${probAprobacion.toStringAsFixed(1)}%';
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
    final resultados = await Future.wait<Map<String, dynamic>?>(
      [
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
      ],
    );
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
          params: {
            'p_categoria': categoriaUsuario,
            'p_limite': 5000,
          },
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
              'practicas_para_ranking':
                  _toInt(rowFast['practicas_para_ranking']),
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

  Future<Map<String, dynamic>> _contextoUsuarioChatDesdeBD(String? userId) async {
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

      final analisis = dominios
          .map((d) {
            final materiaMap =
                d['materia'] is Map ? Map<String, dynamic>.from(d['materia']) : {};
            final nombre = (materiaMap['nombre'] ?? 'Materia').toString();
            final tasa = _toDouble(d['tasa_dominio']) ?? 0.0;
            return {'materia': nombre, 'tasa': tasa};
          })
          .toList();

      analisis.sort((a, b) {
        final aa = _toDouble(a['tasa']) ?? 0.0;
        final bb = _toDouble(b['tasa']) ?? 0.0;
        return bb.compareTo(aa);
      });

      final fortalezas = analisis
          .where((m) => (_toDouble(m['tasa']) ?? 0) >= 75)
          .take(3)
          .toList();
      final debilidades = [...analisis.reversed]
          .where((m) => (_toDouble(m['tasa']) ?? 100) < 65)
          .take(3)
          .toList();

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
      final incorrectas = validas.where((r) => r['es_correcta'] == false).length;
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
          'tasa_acierto_global': _toDouble(perfil['tasa_acierto_global']) ?? 0.0,
          'velocidad_promedio_segundos':
              _toDouble(perfil['velocidad_promedio_segundos']) ?? 0.0,
          'racha_dias': _toInt(perfil['dias_consecutivos_estudio']),
          'tiempo_total_estudio_minutos':
              _toInt(estadistica['tiempo_total_estudio_minutos']),
        },
        'rendimiento_reciente': {
          'total_preguntas': total,
          'correctas': correctas,
          'incorrectas': incorrectas,
          'efectividad_pct': double.parse(efectividadReciente.toStringAsFixed(2)),
        },
        if (ranking != null) 'ranking_usuario': ranking,
        'fortalezas_materia': fortalezas,
        'debilidades_materia': debilidades,
      };
    } catch (e) {
      return {
        'contexto_bd_error': _resumirTextoError(e.toString(), max: 140),
      };
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
      return await _supabase.functions.invoke(
        'ia_diagnostico',
        body: body,
      );
    } on FunctionException catch (e) {
      if (e.status != 401) rethrow;

      // Si la sesion expiro, intentamos refrescar y reintentamos 1 vez.
      try {
        await _supabase.auth.refreshSession();
        return await _supabase.functions.invoke(
          'ia_diagnostico',
          body: body,
        );
      } on FunctionException catch (e2) {
        if (e2.status != 401) rethrow;
        // Si el JWT del usuario sigue invalido, forzamos fallback anon.
        return _invocarTutorConAnon(
          prompt: prompt,
          userId: userId,
          mode: mode,
          usarContextoBd: usarContextoBd,
        );
      } catch (_) {
        // Si no se pudo refrescar sesion, intentamos con anon.
        return _invocarTutorConAnon(
          prompt: prompt,
          userId: userId,
          mode: mode,
          usarContextoBd: usarContextoBd,
        );
      }
    }
  }

  Future<FunctionResponse> _invocarTutorConAnon({
    required String prompt,
    String? userId,
    String mode = 'chat',
    bool usarContextoBd = true,
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
      'usar_contexto_bd': usarContextoBd,
      if (userId != null && userId.isNotEmpty) 'user_id': userId,
    };

    return await _supabase.functions.invoke(
      'ia_diagnostico',
      body: body,
      headers: {
        'Authorization': 'Bearer $anonKey',
        'apikey': anonKey,
      },
    );
  }

  Future<List<Map<String, dynamic>>> obtenerPreguntasQueBajanMateria({
    required String userId,
    required String materia,
    int limit = 5,
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
          .eq('fue_omitida', false)
          .order('respondida_at', ascending: false)
          .limit(500);

      final objetivo = _normalizarTexto(materia);
      final Map<String, Map<String, dynamic>> agg = {};

      for (final raw in rows) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        final esCorrecta = row['es_correcta'];
        if (esCorrecta is! bool) continue;

        final pregunta = row['pregunta'];
        if (pregunta is! Map) continue;
        final preguntaMap = Map<String, dynamic>.from(pregunta);

        final materiaMap = preguntaMap['materia'];
        final nombreMateria = (materiaMap is Map && materiaMap['nombre'] != null)
            ? materiaMap['nombre'].toString()
            : '';

        if (!_materiaCoincide(nombreMateria, objetivo)) continue;

        final preguntaId = (row['pregunta_id'] ?? preguntaMap['id'])?.toString();
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

      final lista = agg.values.map((m) {
        final intentos = _toInt(m['intentos']);
        final fallos = _toInt(m['fallos']);
        final tasaError = intentos > 0 ? (fallos * 100.0) / intentos : 0.0;
        return {
          ...m,
          'tasa_error': tasaError,
        };
      }).where((m) {
        final intentos = _toInt(m['intentos']);
        final fallos = _toInt(m['fallos']);
        return intentos >= 2 && fallos > 0;
      }).toList();

      lista.sort((a, b) {
        final tasaA = _toDouble(a['tasa_error']) ?? 0;
        final tasaB = _toDouble(b['tasa_error']) ?? 0;
        final byRate = tasaB.compareTo(tasaA);
        if (byRate != 0) return byRate;

        final fallosA = _toInt(a['fallos']);
        final fallosB = _toInt(b['fallos']);
        return fallosB.compareTo(fallosA);
      });

      return lista.take(limit).toList();
    } catch (e) {
      print('Error obteniendo preguntas criticas por materia: $e');
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
      final tasaDominio = _toDouble(dominioMateria?['tasa_dominio']) ??
          porcentajeActual ??
          0.0;
      final nivelDominio = (dominioMateria?['nivel_dominio'] ??
              nivelActual ??
              _nivelMateria(tasaDominio))
          .toString();
      final codigoMateria = (materiaMap['codigo'] ?? 'SIN-COD').toString();
      final areaMateria = (materiaMap['categoria'] ?? 'Area general').toString();
      final dificultad = (materiaMap['nivel_dificultad_promedio'] ??
              (tasaDominio < 50
                  ? 'alta'
                  : (tasaDominio < 75 ? 'media' : 'baja')))
          .toString();

      final List<dynamic> respuestasRaw = await _supabase
          .from('respuesta_usuario')
          .select(
            'pregunta_id, es_correcta, fue_omitida, tiempo_total_respuesta, respondida_at, '
            'pregunta:pregunta_id(id, tema_especifico, materia:materia_id(nombre))',
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

      final correctas = respuestasMateria.where((r) {
        return r['es_correcta'] == true && r['fue_omitida'] != true;
      }).length;
      final incorrectas = respuestasMateria.where((r) {
        return r['es_correcta'] == false && r['fue_omitida'] != true;
      }).length;
      final omitidas = respuestasMateria.where((r) => r['fue_omitida'] == true).length;
      final intentos = respuestasMateria.length;

      final preguntasVistasUnicas = respuestasMateria
          .map((r) => (r['pregunta_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .length;
      final noRespondidas = totalPreguntasBanco > 0
          ? (totalPreguntasBanco - preguntasVistasUnicas).clamp(0, totalPreguntasBanco)
          : 0;
      final porcentajeAvance = totalPreguntasBanco > 0
          ? (preguntasVistasUnicas * 100.0) / totalPreguntasBanco
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
        final t = DateTime.tryParse((r['respondida_at'] ?? '').toString())?.toUtc();
        return t != null && t.isAfter(limite7);
      }).toList();
      final anteriores = respuestasMateria.where((r) {
        final t = DateTime.tryParse((r['respondida_at'] ?? '').toString())?.toUtc();
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
          fallosPorPregunta[preguntaId] = (fallosPorPregunta[preguntaId] ?? 0) + 1;
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

      final rankingTiempo = tiemposPorMateria.entries.map((e) {
        return {
          'materia': e.key,
          'promedio': _promedio(e.value),
        };
      }).toList()
        ..sort((a, b) {
          final av = _toDouble(a['promedio']) ?? 0;
          final bv = _toDouble(b['promedio']) ?? 0;
          return bv.compareTo(av);
        });

      final materiasLentas = rankingTiempo
          .take(3)
          .map((m) => '${m['materia']} (${(_toDouble(m['promedio']) ?? 0).toStringAsFixed(1)} seg)')
          .toList();

      final probabilidadActual =
          (tasaDominio * 0.75 + porcentajeAvance * 0.25 + (deltaTendencia * 0.8))
              .clamp(5.0, 99.0);
      var gananciaDiaria = tasaDominio < 50 ? 0.9 : (tasaDominio < 75 ? 0.65 : 0.45);
      if (tendencia == 'empeorando') gananciaDiaria -= 0.2;
      if (gananciaDiaria < 0.2) gananciaDiaria = 0.2;

      final prob7 = (probabilidadActual + gananciaDiaria * 7).clamp(5.0, 99.0);
      final prob14 = (probabilidadActual + gananciaDiaria * 14).clamp(5.0, 99.0);
      final prob30 = (probabilidadActual + gananciaDiaria * 30).clamp(5.0, 99.0);

      final tiempoSugerido = _toInt(dominioMateria?['tiempo_recomendado_minutos']) > 0
          ? _toInt(dominioMateria?['tiempo_recomendado_minutos'])
          : (tasaDominio < 50 ? 35 : (tasaDominio < 70 ? 25 : 18));
      final objetivoPorcentaje = (tasaDominio + 12).clamp(75.0, 92.0).round();

      return {
        'info_basica': {
          'nombre': materia,
          'codigo': codigoMateria,
          'area': areaMateria,
          'total_preguntas': totalPreguntasBanco,
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
          'practicar_cantidad': totalFallidas > 0 ? totalFallidas.clamp(10, 30) : 0,
          'simulacro_cantidad': totalFallidas > 0 ? totalFallidas.clamp(20, 60) : 0,
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
      print('Error obteniendo detalle por materia: $e');
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

      final prompt = '''
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
      print('Error llamando a DeepSeek: $e');
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
    final diagnostico =
        panel['diagnostico'] is String ? panel['diagnostico'] as String : '';

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
      'diagnostico':
          diagnostico.isNotEmpty
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
      return "Â¡Bienvenido! Empieza tus prÃ¡cticas para que pueda analizar tu rendimiento.";
    }
    return "Nivel $nivel detectado. Debemos reforzar ${debilidades.first.split('(').first}. Â¡Sigue asÃ­!";
  }

  // --- Funciones Auxiliares de LÃ³gica de Negocio ---

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
        for (final key in const ['text', 'mensaje', 'respuesta', 'diagnostico']) {
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
      final extra = detalle.isEmpty ? 'Error interno en Edge Function.' : detalle;
      return 'Error $status: $extra';
    }

    if (status == 502 || status == 503 || status == 504) {
      final extra = detalle.isEmpty
          ? 'Fallo al consultar DeepSeek.'
          : detalle;
      return 'Error $status (DeepSeek): $extra';
    }

    final extra = detalle.isEmpty
        ? (e.reasonPhrase ?? 'Sin detalle')
        : detalle;
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

  String _normalizarTexto(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
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
      return {
        if (d['materia_id'] != null) 'materia_id': d['materia_id'],
        if (materia is Map && materia['id'] != null) 'materia_id': materia['id'],
        if (materia is Map && materia['codigo'] != null) 'codigo': materia['codigo'],
        if (materia is Map && materia['categoria'] != null)
          'area': materia['categoria'],
        'materia': nombre,
        'porcentaje': score,
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
        'dificultad':
            porcentaje < 50 ? 'alta' : (porcentaje < 75 ? 'media' : 'baja'),
      },
      'progreso_usuario': {
        'correctas': 0,
        'incorrectas': 0,
        'no_respondidas': 0,
        'omitidas': 0,
        'porcentaje_avance': 0.0,
        'preguntas_vistas': 0,
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


