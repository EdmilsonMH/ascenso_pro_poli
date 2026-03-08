import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'supabase_service.dart';

class RankingUsuario {
  final String id;
  final String nombreCompleto;
  final String categoria;
  final double puntosTotales;
  final double puntajeMaximo;
  final double porcentajeAciertos;
  final int posicion;
  final int practicasParaRanking;

  RankingUsuario({
    required this.id,
    required this.nombreCompleto,
    required this.categoria,
    required this.puntosTotales,
    required this.puntajeMaximo,
    required this.porcentajeAciertos,
    required this.posicion,
    this.practicasParaRanking = 0,
  });

  factory RankingUsuario.fromJson(Map<String, dynamic> json) {
    return RankingUsuario(
      id: json['id']?.toString() ??'',
      nombreCompleto: (json['nombre_completo'] ??'Usuario').toString(),
      categoria: (json['categoria'] ??'').toString(),
      puntosTotales:
          _toDouble(json['puntos_promedio'] ??json['puntos_totales']) ??0.0,
      puntajeMaximo:
          _toDouble(
            json['puntaje_maximo'] ??
                json['puntos_promedio'] ??
                json['puntos_totales'],
          ) ??
          0.0,
      porcentajeAciertos:
          _toDouble(json['porcentaje_aciertos'] ??json['efectividad']) ??0.0,
      posicion: _toInt(json['posicion']) ??0,
      practicasParaRanking:
          _toInt(
            json['practicas_para_ranking'] ??json['simulacros_100_completados'],
          ) ??
          0,
    );
  }

  static int?_toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double?_toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

enum PeriodoRanking {
  ultimaPractica,
  semana,
  mes,
  diasPersonalizados,
  mejorPuntaje,
}

extension PeriodoRankingExt on PeriodoRanking {
  String get rpcMode {
    switch (this) {
      case PeriodoRanking.ultimaPractica:
        return 'ultima_practica';
      case PeriodoRanking.semana:
        return 'semana';
      case PeriodoRanking.mes:
        return 'mes';
      case PeriodoRanking.diasPersonalizados:
        return 'dias';
      case PeriodoRanking.mejorPuntaje:
        return 'todas';
    }
  }

  String get etiqueta {
    switch (this) {
      case PeriodoRanking.ultimaPractica:
        return 'Ultima practica';
      case PeriodoRanking.semana:
        return 'Ultima semana';
      case PeriodoRanking.mes:
        return 'Ultimo mes';
      case PeriodoRanking.diasPersonalizados:
        return 'Ultimos N dias';
      case PeriodoRanking.mejorPuntaje:
        return 'Mejor puntaje';
    }
  }
}

enum CriterioRanking {
  promedio,
  puntuacionMasAlta,
}

extension CriterioRankingExt on CriterioRanking {
  String get rpcValue {
    switch (this) {
      case CriterioRanking.promedio:
        return 'promedio';
      case CriterioRanking.puntuacionMasAlta:
        return 'puntaje_maximo';
    }
  }

  String get etiqueta {
    switch (this) {
      case CriterioRanking.promedio:
        return 'Promedio por practica';
      case CriterioRanking.puntuacionMasAlta:
        return 'Puntuacion mas alta';
    }
  }
}

class ResultadoRankingPeriodo {
  final List<RankingUsuario> rankingCompleto;
  final List<RankingUsuario> topRanking;
  final RankingUsuario?miPosicion;
  final int misPracticas;

  const ResultadoRankingPeriodo({
    required this.rankingCompleto,
    required this.topRanking,
    required this.miPosicion,
    required this.misPracticas,
  });
}

class ServicioRanking {
  static const int _limiteTopRanking = 100;

  bool get _useSupabase => SupabaseService.isInitialized;
  bool get _tieneUsuarioAutenticado => AuthService.currentUser != null;

  String?get _usuarioId => AuthService.currentUser?.id;

  Future<ResultadoRankingPeriodo> obtenerRankingPeriodo({
    required PeriodoRanking periodo,
    CriterioRanking criterio = CriterioRanking.promedio,
    int?diasPersonalizados,
    int limiteTop = 50,
  }) async {
    if (!_useSupabase) {
      final top = _topMock();
      final mi = _miPosicionMock();
      return ResultadoRankingPeriodo(
        rankingCompleto: top,
        topRanking: top.take(limiteTop).toList(),
        miPosicion: mi,
        misPracticas: mi.practicasParaRanking,
      );
    }

    try {
      final categoriaUsuario = await _obtenerCategoriaUsuario();
      final limiteConsulta = limiteTop > _limiteTopRanking
          ? limiteTop
          : _limiteTopRanking;
      final rows = await _obtenerFilasRankingPeriodoConFallback(
        categoriaUsuario: categoriaUsuario,
        periodo: periodo,
        criterio: criterio,
        diasPersonalizados: diasPersonalizados,
        limite: limiteConsulta,
      );

      final rankingTop = _parseRows(rows);
      final top = rankingTop.take(limiteConsulta).toList();
      final miPosicionTop = _tieneUsuarioAutenticado
          ? _buscarMiPosicion(rankingTop)
          : null;
      final miPosicion = miPosicionTop ??
          (_tieneUsuarioAutenticado
              ? await _obtenerMiPosicionPeriodo(
                  categoriaUsuario: categoriaUsuario,
                  periodo: periodo,
                  criterio: criterio,
                  diasPersonalizados: diasPersonalizados,
                )
              : null);

      return ResultadoRankingPeriodo(
        rankingCompleto: rankingTop,
        topRanking: top,
        miPosicion: miPosicion,
        misPracticas: miPosicion?.practicasParaRanking ??0,
      );
    } catch (e) {
      debugPrint(
        'ServicioRanking.obtenerRankingPeriodo fallback legacy. Error: $e',
      );
      final top = await _obtenerTopRankingLegacy();
      RankingUsuario?mi;
      var practicas = 0;
      if (_tieneUsuarioAutenticado) {
        mi = await _obtenerMiPosicionLegacy();
        practicas = await _obtenerConteoPracticasRankingLegacy();
      }
      return ResultadoRankingPeriodo(
        rankingCompleto: top,
        topRanking: top.take(limiteTop).toList(),
        miPosicion: mi,
        misPracticas: practicas,
      );
    }
  }

  // Wrappers de compatibilidad.
  Future<List<RankingUsuario>> obtenerTopRanking() async {
    final resultado = await obtenerRankingPeriodo(
      periodo: PeriodoRanking.semana,
    );
    return resultado.topRanking;
  }

  Future<RankingUsuario?> obtenerMiPosicion() async {
    final resultado = await obtenerRankingPeriodo(
      periodo: PeriodoRanking.semana,
    );
    return resultado.miPosicion;
  }

  Future<int> obtenerConteoPracticasRanking() async {
    final resultado = await obtenerRankingPeriodo(
      periodo: PeriodoRanking.semana,
    );
    return resultado.misPracticas;
  }

  Future<List<Map<String, dynamic>>> _obtenerFilasRankingPeriodoConFallback({
    required String?categoriaUsuario,
    required PeriodoRanking periodo,
    required CriterioRanking criterio,
    required int limite,
    int?diasPersonalizados,
  }) async {
    final rows = await _obtenerFilasRankingPeriodo(
      categoriaUsuario: categoriaUsuario,
      periodo: periodo,
      criterio: criterio,
      diasPersonalizados: diasPersonalizados,
      limite: limite,
    );
    if (rows.isNotEmpty) return rows;

    if (!_debeIntentarFallbackCategorias(categoriaUsuario)) {
      return rows;
    }

    final acumuladas = <Map<String, dynamic>>[];
    for (final categoriaFallback in const ['Oficiales PNP', 'Suboficiales PNP']) {
      final parciales = await _obtenerFilasRankingPeriodo(
        categoriaUsuario: categoriaFallback,
        periodo: periodo,
        criterio: criterio,
        diasPersonalizados: diasPersonalizados,
        limite: limite,
      );
      if (parciales.isNotEmpty) {
        acumuladas.addAll(parciales);
      }
    }

    if (acumuladas.isEmpty) return rows;
    return _combinarYOrdenarFilasRanking(
      rows: acumuladas,
      criterio: criterio,
      limite: limite,
    );
  }

  bool _debeIntentarFallbackCategorias(String?categoriaUsuario) {
    final normalizada = _normalizar(categoriaUsuario);
    return normalizada.isEmpty ||
        normalizada == 'ambos' ||
        normalizada == 'general' ||
        normalizada.contains('ambos');
  }

  List<Map<String, dynamic>> _combinarYOrdenarFilasRanking({
    required List<Map<String, dynamic>> rows,
    required CriterioRanking criterio,
    required int limite,
  }) {
    final porUsuario = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final userId = row['usuario_id']?.toString() ??row['id']?.toString() ??'';
      if (userId.isEmpty) continue;

      final actual = porUsuario[userId];
      if (actual == null) {
        porUsuario[userId] = Map<String, dynamic>.from(row);
        continue;
      }

      // Mantiene la mejor fila de cada usuario segun el criterio elegido.
      if (_compararRowsRanking(row, actual, criterio) < 0) {
        porUsuario[userId] = Map<String, dynamic>.from(row);
      }
    }

    final lista = porUsuario.values.toList()
      ..sort((a, b) => _compararRowsRanking(a, b, criterio));

    final top = lista.take(limite).toList();
    for (var i = 0; i < top.length; i++) {
      top[i]['posicion'] = i + 1;
    }
    return top;
  }

  int _compararRowsRanking(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    CriterioRanking criterio,
  ) {
    final aProm = _toDouble(a['puntos_promedio'] ??a['puntos_totales']) ??0.0;
    final bProm = _toDouble(b['puntos_promedio'] ??b['puntos_totales']) ??0.0;
    final aMax =
        _toDouble(
          a['puntaje_maximo'] ??a['puntos_promedio'] ??a['puntos_totales'],
        ) ??
        0.0;
    final bMax =
        _toDouble(
          b['puntaje_maximo'] ??b['puntos_promedio'] ??b['puntos_totales'],
        ) ??
        0.0;
    final aEf = _toDouble(a['efectividad'] ??a['porcentaje_aciertos']) ??0.0;
    final bEf = _toDouble(b['efectividad'] ??b['porcentaje_aciertos']) ??0.0;
    final aTotal = _toDouble(a['puntos_totales'] ??a['puntos_promedio']) ??0.0;
    final bTotal = _toDouble(b['puntos_totales'] ??b['puntos_promedio']) ??0.0;
    final aFecha = _toDateTime(a['ultima_practica']);
    final bFecha = _toDateTime(b['ultima_practica']);
    final aId = a['usuario_id']?.toString() ??a['id']?.toString() ??'';
    final bId = b['usuario_id']?.toString() ??b['id']?.toString() ??'';

    if (criterio == CriterioRanking.puntuacionMasAlta) {
      final cMax = bMax.compareTo(aMax);
      if (cMax != 0) return cMax;
      final cProm = bProm.compareTo(aProm);
      if (cProm != 0) return cProm;
      final cEf = bEf.compareTo(aEf);
      if (cEf != 0) return cEf;
    } else {
      final cProm = bProm.compareTo(aProm);
      if (cProm != 0) return cProm;
      final cEf = bEf.compareTo(aEf);
      if (cEf != 0) return cEf;
      final cTotal = bTotal.compareTo(aTotal);
      if (cTotal != 0) return cTotal;
    }

    if (aFecha != null && bFecha != null) {
      final cFecha = bFecha.compareTo(aFecha);
      if (cFecha != 0) return cFecha;
    } else if (aFecha != null) {
      return -1;
    } else if (bFecha != null) {
      return 1;
    }

    return aId.compareTo(bId);
  }

  Future<List<Map<String, dynamic>>> _obtenerFilasRankingPeriodo({
    required String?categoriaUsuario,
    required PeriodoRanking periodo,
    required CriterioRanking criterio,
    required int limite,
    int?diasPersonalizados,
  }) async {
    if (periodo == PeriodoRanking.mejorPuntaje &&
        criterio == CriterioRanking.puntuacionMasAlta) {
      try {
        final fastRaw = await SupabaseService.client.rpc(
          'obtener_ranking_mejor_puntaje',
          params: {
            'p_categoria': categoriaUsuario,
            'p_limite': limite,
          },
        );
        if (fastRaw is List) {
          return fastRaw.map(_toMap).toList();
        }
      } catch (_) {
        // Si la RPC aun no existe en BD, continuamos con la ruta estandar.
      }
    }

    final params = <String, dynamic>{
      'p_categoria': categoriaUsuario,
      'p_modo': periodo.rpcMode,
      'p_limite': limite,
      'p_criterio': criterio.rpcValue,
    };

    if (periodo == PeriodoRanking.diasPersonalizados) {
      params['p_dias'] = (diasPersonalizados ??1).clamp(1, 3650);
    }

    dynamic raw;
    try {
      raw = await SupabaseService.client.rpc(
        'obtener_ranking_periodo',
        params: params,
      );
    } catch (_) {
      // Compatibilidad: si la BD aun no tiene el parametro p_criterio.
      final paramsLegacy = Map<String, dynamic>.from(params)
        ..remove('p_criterio');
      raw = await SupabaseService.client.rpc(
        'obtener_ranking_periodo',
        params: paramsLegacy,
      );
    }

    if (raw is! List) return const [];
    return raw.map(_toMap).toList();
  }

  Future<RankingUsuario?> _obtenerMiPosicionPeriodo({
    required String?categoriaUsuario,
    required PeriodoRanking periodo,
    required CriterioRanking criterio,
    int?diasPersonalizados,
  }) async {
    final userId = _usuarioId;
    if (userId == null || userId.isEmpty) return null;

    dynamic raw;
    try {
      if (periodo == PeriodoRanking.mejorPuntaje &&
          criterio == CriterioRanking.puntuacionMasAlta) {
        raw = await SupabaseService.client.rpc(
          'obtener_posicion_usuario_mejor_puntaje',
          params: {
            'p_categoria': categoriaUsuario,
            'p_usuario_id': userId,
          },
        );
      } else {
        final params = <String, dynamic>{
          'p_categoria': categoriaUsuario,
          'p_modo': periodo.rpcMode,
          'p_criterio': criterio.rpcValue,
          'p_usuario_id': userId,
          if (periodo == PeriodoRanking.diasPersonalizados)
            'p_dias': (diasPersonalizados ??1).clamp(1, 3650),
        };
        raw = await SupabaseService.client.rpc(
          'obtener_posicion_usuario_ranking_periodo',
          params: params,
        );
      }
    } catch (_) {
      return null;
    }

    final map = _extraerPrimeraFila(raw);
    if (map == null || map.isEmpty) return null;
    final parsed = _parseRows([map]);
    if (parsed.isEmpty) return null;
    return parsed.first;
  }

  Map<String, dynamic>?_extraerPrimeraFila(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  List<RankingUsuario> _parseRows(List<Map<String, dynamic>> rows) {
    final resultado = <RankingUsuario>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final userId =
          row['usuario_id']?.toString() ??row['id']?.toString() ??'';
      if (userId.isEmpty) continue;

      resultado.add(
        RankingUsuario(
          id: userId,
          nombreCompleto:
              row['nombre_completo']?.toString().trim().isNotEmpty == true
              ? row['nombre_completo'].toString().trim()
              : _aliasUsuario(userId),
          categoria: row['categoria']?.toString().trim().isNotEmpty == true
              ? row['categoria'].toString().trim()
              : 'General',
          puntosTotales:
              _toDouble(row['puntos_promedio'] ??row['puntos_totales']) ??0.0,
          puntajeMaximo:
              _toDouble(
                row['puntaje_maximo'] ??
                    row['puntos_promedio'] ??
                    row['puntos_totales'],
              ) ??
              0.0,
          porcentajeAciertos:
              _toDouble(row['efectividad'] ??row['promedio_simulacros']) ??0.0,
          posicion: _toInt(row['posicion']) ??(i + 1),
          practicasParaRanking:
              _toInt(
                row['practicas_para_ranking'] ??
                    row['simulacros_100_completados'],
              ) ??
              0,
        ),
      );
    }
    return resultado;
  }

  RankingUsuario?_buscarMiPosicion(List<RankingUsuario> ranking) {
    final usuarioId = _usuarioId;
    if (usuarioId == null) return null;
    for (final r in ranking) {
      if (r.id == usuarioId) return r;
    }
    return null;
  }

  Future<String?> _obtenerCategoriaUsuario() async {
    final user = AuthService.currentUser;
    if (user == null) return null;

    final fromAuth = _extraerCategoriaDesdeMetadata(
      Map<String, dynamic>.from(user.userMetadata ??{}),
    );
    if (fromAuth != null) return fromAuth;

    try {
      final perfil = await AuthService.getCurrentUserProfile();
      final categoriaPerfil = perfil?['categoria']?.toString().trim();
      if (categoriaPerfil != null && categoriaPerfil.isNotEmpty) {
        return categoriaPerfil;
      }
    } catch (_) {
      // Ignorado: intentamos siguiente fuente.
    }

    try {
      final row = await SupabaseService.client
          .from('usuario')
          .select('metadata')
          .eq('id', user.id)
          .maybeSingle();
      final metadata = _toMap(row?['metadata']);
      return _extraerCategoriaDesdeMetadata(metadata) ??'Oficiales PNP';
    } catch (_) {
      return 'Oficiales PNP';
    }
  }

  String?_extraerCategoriaDesdeMetadata(Map<String, dynamic> metadata) {
    final candidatos = [
      metadata['categoria'],
      metadata['categoria_usuario'],
      metadata['category'],
    ];
    for (final c in candidatos) {
      final txt = c?.toString().trim();
      if (txt != null && txt.isNotEmpty) return txt;
    }
    return null;
  }

  String _aliasUsuario(String id) {
    final shortId = id.length >= 4 ?id.substring(id.length - 4) : id;
    return 'Usuario $shortId';
  }

  // -------------------------
  // Fallback legacy
  // -------------------------
  Future<List<RankingUsuario>> _obtenerTopRankingLegacy() async {
    if (!_useSupabase) return _topMock();

    try {
      final rankingRows = await SupabaseService.client
          .from('ranking')
          .select(
            'usuario_id, puntos_totales, promedio_simulacros, simulacros_100_completados',
          )
          .order('puntos_totales', ascending: false)
          .order('calculo_ranking_at', ascending: false)
          .limit(50);

      final rows = (rankingRows as List<dynamic>).map(_toMap).toList();
      if (rows.isEmpty) return [];

      final userIds = rows
          .map((r) => r['usuario_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final usuariosById = <String, Map<String, dynamic>>{};
      if (userIds.isNotEmpty) {
        try {
          final usuariosRows = await SupabaseService.client
              .from('usuario')
              .select('id, nombre_completo, metadata')
              .inFilter('id', userIds);

          for (final item in (usuariosRows as List<dynamic>)) {
            final row = _toMap(item);
            final id = row['id']?.toString();
            if (id == null || id.isEmpty) continue;
            usuariosById[id] = row;
          }
        } catch (_) {
          // Ignorado: fallback visual con alias.
        }
      }

      final resultado = <RankingUsuario>[];
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final userId = r['usuario_id']?.toString();
        if (userId == null || userId.isEmpty) continue;

        final usuario = usuariosById[userId];
        final metadata = _toMap(usuario?['metadata']);

        resultado.add(
          RankingUsuario(
            id: userId,
            nombreCompleto: _nombreVisible(id: userId, usuario: usuario),
            categoria: _categoriaVisible(metadata),
            puntosTotales: _toDouble(r['puntos_totales']) ??0.0,
            puntajeMaximo: _toDouble(r['puntos_totales']) ??0.0,
            porcentajeAciertos: _toDouble(r['promedio_simulacros']) ??0.0,
            posicion: i + 1,
            practicasParaRanking:
                _toInt(r['simulacros_100_completados']) ??0,
          ),
        );
      }

      return resultado;
    } catch (e) {
      debugPrint('ServicioRanking._obtenerTopRankingLegacy error: $e');
      return [];
    }
  }

  Future<RankingUsuario?> _obtenerMiPosicionLegacy() async {
    if (!_useSupabase) return _miPosicionMock();

    final usuarioId = _usuarioId;
    if (usuarioId == null) return null;

    try {
      final rankingRows = await SupabaseService.client
          .from('ranking')
          .select(
            'usuario_id, puntos_totales, promedio_simulacros, simulacros_100_completados',
          )
          .order('puntos_totales', ascending: false)
          .order('calculo_ranking_at', ascending: false)
          .limit(5000);

      final rows = (rankingRows as List<dynamic>).map(_toMap).toList();
      final indice = rows.indexWhere(
        (row) => row['usuario_id']?.toString() == usuarioId,
      );
      if (indice < 0) return null;

      Map<String, dynamic>?usuario;
      try {
        final usuarioRow = await SupabaseService.client
            .from('usuario')
            .select('id, nombre_completo, metadata')
            .eq('id', usuarioId)
            .maybeSingle();
        if (usuarioRow != null) usuario = _toMap(usuarioRow);
      } catch (_) {
        // Ignorado.
      }

      final row = rows[indice];
      final metadata = _toMap(usuario?['metadata']);

      return RankingUsuario(
        id: usuarioId,
        nombreCompleto: _nombreVisible(
          id: usuarioId,
          usuario: usuario,
        ),
        categoria: _categoriaVisible(metadata),
        puntosTotales: _toDouble(row['puntos_totales']) ??0.0,
        puntajeMaximo: _toDouble(row['puntos_totales']) ??0.0,
        porcentajeAciertos: _toDouble(row['promedio_simulacros']) ??0.0,
        posicion: indice + 1,
        practicasParaRanking: _toInt(row['simulacros_100_completados']) ??0,
      );
    } catch (e) {
      debugPrint('ServicioRanking._obtenerMiPosicionLegacy error: $e');
      return null;
    }
  }

  Future<int> _obtenerConteoPracticasRankingLegacy() async {
    if (!_useSupabase) return 0;

    final usuarioId = _usuarioId;
    if (usuarioId == null) return 0;

    try {
      final rows = await SupabaseService.client
          .from('sesion_practica')
          .select(
            'tipo_sesion, total_preguntas_planeadas, preguntas_respondidas, metadata, completada',
          )
          .eq('usuario_id', usuarioId)
          .order('creado_at', ascending: false)
          .limit(5000);

      var total = 0;
      for (final item in (rows as List<dynamic>)) {
        final row = _toMap(item);
        if (row['completada'] == false) continue;
        if (_esSesionRankingLegacy(row)) total++;
      }

      return total;
    } catch (e) {
      debugPrint('ServicioRanking._obtenerConteoPracticasRankingLegacy error: $e');
      return 0;
    }
  }

  bool _esSesionRankingLegacy(Map<String, dynamic> row) {
    final metadata = _toMap(row['metadata']);
    final tipo = _normalizar(row['tipo_sesion']);
    final total = _toInt(row['total_preguntas_planeadas']) ??
        _toInt(row['preguntas_respondidas']) ??
        0;

    return total == 100 &&
        (metadata['cuenta_para_ranking'] == true || tipo == 'ranking');
  }

  String _nombreVisible({
    required String id,
    Map<String, dynamic>?usuario,
  }) {
    final nombre = usuario?['nombre_completo']?.toString().trim() ??'';
    if (nombre.isNotEmpty) return nombre;

    final shortId = id.length >= 4 ?id.substring(id.length - 4) : id;
    return 'Usuario $shortId';
  }

  String _categoriaVisible(Map<String, dynamic> metadata) {
    final categoria = metadata['categoria']?.toString().trim() ??'';
    if (categoria.isNotEmpty) return categoria;
    return 'General';
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

  List<RankingUsuario> _topMock() {
    return List.generate(10, (index) {
      return RankingUsuario(
        id: 'mock-$index',
        nombreCompleto: 'Usuario ${index + 1}',
        categoria: 'General',
        puntosTotales: (1000 - (index * 50)).toDouble(),
        puntajeMaximo: (1000 - (index * 50)).toDouble(),
        porcentajeAciertos: 80 - index.toDouble(),
        posicion: index + 1,
      );
    });
  }

  RankingUsuario _miPosicionMock() {
    return RankingUsuario(
      id: 'mock-me',
      nombreCompleto: 'Yo',
      categoria: 'General',
      puntosTotales: 0.0,
      puntajeMaximo: 0.0,
      porcentajeAciertos: 0,
      posicion: 0,
      practicasParaRanking: 0,
    );
  }
}
