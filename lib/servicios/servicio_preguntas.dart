import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../modelos/modelo_pregunta.dart';
import 'auth_service.dart';
import 'supabase_service.dart';

class ServicioPreguntas {
  static const Duration _cacheMateriasTtl = Duration(minutes: 10);
  static const Duration _cachePremiumTtl = Duration(minutes: 2);
  static const int _limiteInvitadoPorMateria = 10;
  static const int _limiteRegistradoNoActivoPorMateria = 50;
  static const String _prefsGuestSnapshotPrefix =
      'guest_fixed_question_ids_v1_';
  static List<Map<String, dynamic>>? _materiasActivasCache;
  static DateTime? _materiasActivasCacheAt;
  static String? _premiumCacheUserId;
  static bool? _premiumCacheValue;
  static DateTime? _premiumCacheAt;
  static final Map<String, List<String>> _idsCachePorFiltro = {};
  static final Map<String, Map<String, List<String>>> _guestSnapshotCache = {};
  static final Map<String, Map<String, List<String>>>
      _registradoNoActivoSnapshotCache = {};
  bool get _esInvitadoConSupabase =>
      SupabaseService.isInitialized && !AuthService.isLoggedIn;

  String _claveSnapshotInvitado(String categoria) {
    final prefijoCategoria = _prefijoCodigoPorCategoria(categoria);
    if (prefijoCategoria == 'SUB-') return 'suboficial';
    if (prefijoCategoria == 'OFI-') return 'oficial';
    return 'ambos';
  }

  Map<String, List<String>> _snapshotDesdeJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, List<String>>{};

      final resultado = <String, List<String>>{};
      for (final entry in decoded.entries) {
        final materiaId = entry.key.toString().trim();
        if (materiaId.isEmpty) continue;

        final value = entry.value;
        if (value is! List) continue;

        final ids = value
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .take(_limiteInvitadoPorMateria)
            .toList();
        if (ids.isNotEmpty) {
          resultado[materiaId] = ids;
        }
      }
      return resultado;
    } catch (_) {
      return <String, List<String>>{};
    }
  }

  List<String> _aplanarSnapshot(Map<String, List<String>> snapshot) {
    final ids = <String>[];
    final materiaIdsOrdenadas = snapshot.keys.toList()..sort();
    for (final materiaId in materiaIdsOrdenadas) {
      ids.addAll(snapshot[materiaId] ?? const []);
    }
    return ids;
  }

  Future<Map<String, List<String>>> _generarSnapshotInvitadoPorMateria(
    String categoria,
  ) async {
    final prefijoCategoria = _prefijoCodigoPorCategoria(categoria);
    final materiasActivas = await _obtenerMateriasActivasCached();
    final materiasObjetivo = materiasActivas
        .map((m) => m['id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    dynamic query = SupabaseService.client
        .from('pregunta')
        .select('id, materia_id, numero_oficial, codigo_pregunta')
        .eq('activo', true);

    if (prefijoCategoria != null) {
      query = query.like('codigo_pregunta', '$prefijoCategoria%');
    }

    const pageSize = 1000;
    const maxPaginas = 50;
    var offset = 0;
    var paginasLeidas = 0;
    final snapshot = <String, List<String>>{};

    while (true) {
      final pageRaw = await query
          .order('materia_id', ascending: true)
          .order('numero_oficial', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + pageSize - 1);

      final page = (pageRaw as List<dynamic>).map(_toMap).toList();
      if (page.isEmpty) break;

      for (final row in page) {
        final materiaId = row['materia_id']?.toString().trim() ?? '';
        final preguntaId = row['id']?.toString().trim() ?? '';
        if (materiaId.isEmpty || preguntaId.isEmpty) continue;

        final idsMateria = snapshot.putIfAbsent(materiaId, () => <String>[]);
        if (idsMateria.length < _limiteInvitadoPorMateria) {
          idsMateria.add(preguntaId);
        }
      }

      paginasLeidas++;
      if (paginasLeidas >= maxPaginas) break;

      if (_snapshotInvitadoCompleto(
        snapshot: snapshot,
        materiasObjetivo: materiasObjetivo,
      )) {
        break;
      }

      if (page.length < pageSize) break;
      offset += pageSize;
    }

    snapshot.removeWhere((_, ids) => ids.isEmpty);
    return snapshot;
  }

  Future<bool> _esRegistradoNoActivoConSupabase() async {
    if (!SupabaseService.isInitialized || !AuthService.isLoggedIn) return false;

    final userId = AuthService.currentUser?.id;
    if (userId == null || userId.isEmpty) return false;

    final now = DateTime.now();
    if (_premiumCacheUserId == userId &&
        _premiumCacheValue != null &&
        _premiumCacheAt != null &&
        now.difference(_premiumCacheAt!) <= _cachePremiumTtl) {
      return _premiumCacheValue == false;
    }

    var premium = false;
    try {
      final row = await SupabaseService.client
          .from('usuario')
          .select('premium')
          .eq('id', userId)
          .maybeSingle();
      premium = _toMap(row)['premium'] == true;
    } catch (e) {
      // En error de lectura, mantenemos modo limitado por seguridad.
      debugPrint(
        'ServicioPreguntas._esRegistradoNoActivoConSupabase error: $e',
      );
      premium = false;
    }

    _premiumCacheUserId = userId;
    _premiumCacheValue = premium;
    _premiumCacheAt = now;
    return !premium;
  }

  String _claveSnapshotRegistradoNoActivo(String categoria) {
    final userId = AuthService.currentUser?.id ?? 'anon';
    final base = _claveSnapshotInvitado(categoria);
    return '$userId|$base';
  }

  Future<Map<String, List<String>>> _generarSnapshotRegistradoNoActivoPorMateria(
    String categoria,
  ) async {
    final prefijoCategoria = _prefijoCodigoPorCategoria(categoria);
    final materiasActivas = await _obtenerMateriasActivasCached();
    final materiasObjetivo = materiasActivas
        .map((m) => m['id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    dynamic query = SupabaseService.client
        .from('pregunta')
        .select('id, materia_id, numero_oficial, codigo_pregunta')
        .eq('activo', true);

    if (prefijoCategoria != null) {
      query = query.like('codigo_pregunta', '$prefijoCategoria%');
    }

    const pageSize = 1000;
    const maxPaginas = 50;
    var offset = 0;
    var paginasLeidas = 0;
    final snapshot = <String, List<String>>{};

    while (true) {
      final pageRaw = await query
          .order('materia_id', ascending: true)
          .order('numero_oficial', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + pageSize - 1);

      final page = (pageRaw as List<dynamic>).map(_toMap).toList();
      if (page.isEmpty) break;

      for (final row in page) {
        final materiaId = row['materia_id']?.toString().trim() ?? '';
        final preguntaId = row['id']?.toString().trim() ?? '';
        if (materiaId.isEmpty || preguntaId.isEmpty) continue;

        final idsMateria = snapshot.putIfAbsent(materiaId, () => <String>[]);
        if (idsMateria.length < _limiteRegistradoNoActivoPorMateria) {
          idsMateria.add(preguntaId);
        }
      }

      paginasLeidas++;
      if (paginasLeidas >= maxPaginas) break;

      if (_snapshotCompletoPorLimite(
        snapshot: snapshot,
        materiasObjetivo: materiasObjetivo,
        limitePorMateria: _limiteRegistradoNoActivoPorMateria,
      )) {
        break;
      }

      if (page.length < pageSize) break;
      offset += pageSize;
    }

    snapshot.removeWhere((_, ids) => ids.isEmpty);
    return snapshot;
  }

  Future<Map<String, List<String>>> _obtenerSnapshotRegistradoNoActivoPorMateria(
    String categoria,
  ) async {
    try {
      final clave = _claveSnapshotRegistradoNoActivo(categoria);
      final cached = _registradoNoActivoSnapshotCache[clave];
      if (cached != null && cached.isNotEmpty) return cached;

      final generado = await _generarSnapshotRegistradoNoActivoPorMateria(
        categoria,
      );
      if (generado.isNotEmpty) {
        _registradoNoActivoSnapshotCache[clave] = generado;
      }
      return generado;
    } catch (e) {
      debugPrint(
        'ServicioPreguntas._obtenerSnapshotRegistradoNoActivoPorMateria error: $e',
      );
      return <String, List<String>>{};
    }
  }

  Future<List<String>> _obtenerIdsFijosRegistradoNoActivo({
    required String categoria,
    String? materia,
  }) async {
    if (!await _esRegistradoNoActivoConSupabase()) return const [];

    try {
      String? materiaFiltrada = materia;
      final prefijoCategoria = _prefijoCodigoPorCategoria(categoria);
      final categoriaNormalizada = _normalizar(categoria);

      if (materiaFiltrada == null &&
          _debeCategoriaActuarComoFiltroMateria(
            categoriaNormalizada: categoriaNormalizada,
            prefijoCategoria: prefijoCategoria,
          )) {
        materiaFiltrada = categoria;
      }

      final snapshot = await _obtenerSnapshotRegistradoNoActivoPorMateria(
        categoria,
      );
      if (snapshot.isEmpty) return const [];

      if (materiaFiltrada == null || materiaFiltrada == 'Todas') {
        return _aplanarSnapshot(snapshot);
      }

      final materiaIdsPermitidas = await _resolverMateriaIdsPermitidas(
        materiaFiltrada,
      );
      if (materiaIdsPermitidas == null || materiaIdsPermitidas.isEmpty) {
        return const [];
      }

      final ids = <String>[];
      final materiaOrdenadas = materiaIdsPermitidas.toList()..sort();
      for (final materiaId in materiaOrdenadas) {
        ids.addAll(snapshot[materiaId] ?? const []);
      }
      return ids;
    } catch (e) {
      debugPrint(
        'ServicioPreguntas._obtenerIdsFijosRegistradoNoActivo error: $e',
      );
      return const [];
    }
  }

  Future<Map<String, List<String>>> _obtenerSnapshotInvitadoPorMateria(
    String categoria,
  ) async {
    try {
      final clave = _claveSnapshotInvitado(categoria);
      final cached = _guestSnapshotCache[clave];
      if (cached != null && cached.isNotEmpty) return cached;

      final prefs = await SharedPreferences.getInstance();
      final prefsKey = '$_prefsGuestSnapshotPrefix$clave';
      final raw = prefs.getString(prefsKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final snapshot = _snapshotDesdeJson(raw);
        if (snapshot.isNotEmpty) {
          _guestSnapshotCache[clave] = snapshot;
          return snapshot;
        }
      }

      final generado = await _generarSnapshotInvitadoPorMateria(categoria);
      if (generado.isNotEmpty) {
        _guestSnapshotCache[clave] = generado;
        await prefs.setString(prefsKey, jsonEncode(generado));
        return generado;
      }

      return <String, List<String>>{};
    } catch (e) {
      debugPrint(
        'ServicioPreguntas._obtenerSnapshotInvitadoPorMateria error: $e',
      );
      return <String, List<String>>{};
    }
  }

  Future<List<String>> _obtenerIdsFijosInvitado({
    required String categoria,
    String? materia,
  }) async {
    if (!_esInvitadoConSupabase) return const [];
    try {
      String? materiaFiltrada = materia;
      final prefijoCategoria = _prefijoCodigoPorCategoria(categoria);
      final categoriaNormalizada = _normalizar(categoria);

      if (materiaFiltrada == null &&
          _debeCategoriaActuarComoFiltroMateria(
            categoriaNormalizada: categoriaNormalizada,
            prefijoCategoria: prefijoCategoria,
          )) {
        materiaFiltrada = categoria;
      }

      final snapshot = await _obtenerSnapshotInvitadoPorMateria(categoria);
      if (snapshot.isEmpty) return const [];

      if (materiaFiltrada == null || materiaFiltrada == 'Todas') {
        return _aplanarSnapshot(snapshot);
      }

      final materiaIdsPermitidas = await _resolverMateriaIdsPermitidas(
        materiaFiltrada,
      );
      if (materiaIdsPermitidas == null || materiaIdsPermitidas.isEmpty) {
        return const [];
      }

      final ids = <String>[];
      final materiaOrdenadas = materiaIdsPermitidas.toList()..sort();
      for (final materiaId in materiaOrdenadas) {
        ids.addAll(snapshot[materiaId] ?? const []);
      }
      return ids;
    } catch (e) {
      debugPrint('ServicioPreguntas._obtenerIdsFijosInvitado error: $e');
      return const [];
    }
  }

  List<Pregunta> _ordenarPreguntasPorIds({
    required List<String> idsEnOrden,
    required List<Pregunta> preguntas,
  }) {
    final porId = {for (final p in preguntas) p.id: p};
    final ordenadas = <Pregunta>[];
    for (final id in idsEnOrden) {
      final pregunta = porId[id];
      if (pregunta != null) {
        ordenadas.add(pregunta);
      }
    }
    return ordenadas;
  }

  Future<List<Pregunta>> obtenerPreguntasAleatorias({
    int cantidad = 20,
    String? materia,
    String categoria = 'Ambos',
  }) async {
    final cantidadSegura = cantidad <= 0 ? 1 : cantidad;

    if (_esInvitadoConSupabase) {
      try {
        final idsFijos = await _obtenerIdsFijosInvitado(
          categoria: categoria,
          materia: materia,
        );
        if (idsFijos.isEmpty) return [];

        final candidatos = List<String>.from(idsFijos)..shuffle();
        final cantidadObjetivo = cantidadSegura > candidatos.length
            ? candidatos.length
            : cantidadSegura;
        final idsSeleccionados = candidatos.take(cantidadObjetivo).toList();
        return obtenerPreguntasPorIds(
          ids: idsSeleccionados,
          materia: materia,
          categoria: categoria,
        );
      } catch (e) {
        debugPrint(
          'ServicioPreguntas.obtenerPreguntasAleatorias invitado error: $e',
        );
        return [];
      }
    }

    if (await _esRegistradoNoActivoConSupabase()) {
      try {
        final idsPermitidos = await _obtenerIdsFijosRegistradoNoActivo(
          categoria: categoria,
          materia: materia,
        );
        if (idsPermitidos.isEmpty) return [];

        final candidatos = List<String>.from(idsPermitidos)..shuffle();
        final cantidadObjetivo = cantidadSegura > candidatos.length
            ? candidatos.length
            : cantidadSegura;
        final idsSeleccionados = candidatos.take(cantidadObjetivo).toList();
        return obtenerPreguntasPorIds(
          ids: idsSeleccionados,
          materia: materia,
          categoria: categoria,
        );
      } catch (e) {
        debugPrint(
          'ServicioPreguntas.obtenerPreguntasAleatorias no-activo error: $e',
        );
        return [];
      }
    }

    if (SupabaseService.isInitialized) {
      try {
        final idsDisponibles = await _obtenerIdsPreguntasDisponibles(
          materia: materia,
          categoria: categoria,
        );
        if (idsDisponibles.isEmpty) return [];

        final candidatos = List<String>.from(idsDisponibles)..shuffle();
        final idsSeleccionados = candidatos.take(cantidadSegura).toList();
        return obtenerPreguntasPorIds(
          ids: idsSeleccionados,
          materia: materia,
          categoria: categoria,
        );
      } catch (e) {
        debugPrint('ServicioPreguntas.obtenerPreguntasAleatorias error: $e');
      }
    }

    final todas = await _obtenerPreguntasDesdeFuente(
      materia: materia,
      categoria: categoria,
    );
    todas.shuffle();
    return todas.take(cantidadSegura).toList();
  }

  Future<List<Pregunta>> obtenerTodas({String categoria = 'Ambos'}) async {
    if (_esInvitadoConSupabase) {
      try {
        final idsFijos = await _obtenerIdsFijosInvitado(categoria: categoria);
        if (idsFijos.isEmpty) return [];
        return obtenerPreguntasPorIds(ids: idsFijos, categoria: categoria);
      } catch (e) {
        debugPrint('ServicioPreguntas.obtenerTodas invitado error: $e');
        return [];
      }
    }

    if (await _esRegistradoNoActivoConSupabase()) {
      try {
        final idsFijos = await _obtenerIdsFijosRegistradoNoActivo(
          categoria: categoria,
        );
        if (idsFijos.isEmpty) return [];
        return obtenerPreguntasPorIds(ids: idsFijos, categoria: categoria);
      } catch (e) {
        debugPrint('ServicioPreguntas.obtenerTodas no-activo error: $e');
        return [];
      }
    }

    return _obtenerPreguntasDesdeFuente(categoria: categoria);
  }

  /// Obtiene preguntas de ranking desde el banco completo de la categoria,
  /// sin aplicar los limites de invitado/no activo por materia.
  /// Se usa para las practicas ranking limitadas (ej. 3 intentos no activos).
  Future<List<Pregunta>> obtenerPreguntasRankingBancoCompleto({
    required String categoria,
    int cantidad = 100,
  }) async {
    final cantidadSegura = cantidad <= 0 ? 100 : cantidad;

    if (!SupabaseService.isInitialized) {
      final mock = await _obtenerPreguntasDesdeFuente(categoria: categoria);
      if (mock.length < cantidadSegura) return const [];
      mock.shuffle();
      return mock.take(cantidadSegura).toList();
    }

    try {
      final idsDisponibles = await _obtenerIdsPreguntasDisponibles(
        categoria: categoria,
      );
      if (idsDisponibles.length < cantidadSegura) return const [];

      final candidatos = List<String>.from(idsDisponibles)..shuffle();
      final idsSeleccionados = candidatos.take(cantidadSegura).toList();
      final preguntas = await _obtenerPreguntasDesdeFuente(
        ids: idsSeleccionados,
        categoria: categoria,
      );

      final ordenadas = _ordenarPreguntasPorIds(
        idsEnOrden: idsSeleccionados,
        preguntas: preguntas,
      );
      if (ordenadas.length < cantidadSegura) return const [];
      return ordenadas;
    } catch (e) {
      debugPrint(
        'ServicioPreguntas.obtenerPreguntasRankingBancoCompleto error: $e',
      );
      return const [];
    }
  }

  Future<int> contarPreguntasDisponibles({
    String? materia,
    String categoria = 'Ambos',
  }) async {
    if (_esInvitadoConSupabase) {
      try {
        final idsFijos = await _obtenerIdsFijosInvitado(
          materia: materia,
          categoria: categoria,
        );
        return idsFijos.length;
      } catch (e) {
        debugPrint(
          'ServicioPreguntas.contarPreguntasDisponibles invitado error: $e',
        );
        return 0;
      }
    }

    if (await _esRegistradoNoActivoConSupabase()) {
      try {
        final idsFijos = await _obtenerIdsFijosRegistradoNoActivo(
          materia: materia,
          categoria: categoria,
        );
        return idsFijos.length;
      } catch (e) {
        debugPrint(
          'ServicioPreguntas.contarPreguntasDisponibles no-activo error: $e',
        );
        return 0;
      }
    }

    if (SupabaseService.isInitialized) {
      try {
        final ids = await _obtenerIdsPreguntasDisponibles(
          materia: materia,
          categoria: categoria,
        );
        return ids.length;
      } catch (e) {
        debugPrint('ServicioPreguntas.contarPreguntasDisponibles error: $e');
      }
    }

    final todas = await _obtenerPreguntasDesdeFuente(
      materia: materia,
      categoria: categoria,
    );
    return todas.length;
  }

  Future<List<Pregunta>> obtenerPreguntasPorIds({
    required List<String> ids,
    String? materia,
    String categoria = 'Ambos',
  }) async {
    final ordenIds = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (ordenIds.isEmpty) return [];

    if (_esInvitadoConSupabase) {
      try {
        final idsPermitidos = (await _obtenerIdsFijosInvitado(
          categoria: categoria,
          materia: materia,
        )).toSet();
        if (idsPermitidos.isEmpty) return [];

        final idsFiltrados = ordenIds.where(idsPermitidos.contains).toList();
        if (idsFiltrados.isEmpty) return [];

        final preguntasInvitado = await _obtenerPreguntasDesdeFuente(
          ids: idsFiltrados,
          materia: materia,
          categoria: categoria,
        );
        return _ordenarPreguntasPorIds(
          idsEnOrden: idsFiltrados,
          preguntas: preguntasInvitado,
        );
      } catch (e) {
        debugPrint('ServicioPreguntas.obtenerPreguntasPorIds invitado error: $e');
        return [];
      }
    }

    if (await _esRegistradoNoActivoConSupabase()) {
      try {
        final idsPermitidos = (await _obtenerIdsFijosRegistradoNoActivo(
          categoria: categoria,
          materia: materia,
        )).toSet();
        if (idsPermitidos.isEmpty) return [];

        final idsFiltrados = ordenIds.where(idsPermitidos.contains).toList();
        if (idsFiltrados.isEmpty) return [];

        final preguntasNoActivo = await _obtenerPreguntasDesdeFuente(
          ids: idsFiltrados,
          materia: materia,
          categoria: categoria,
        );
        return _ordenarPreguntasPorIds(
          idsEnOrden: idsFiltrados,
          preguntas: preguntasNoActivo,
        );
      } catch (e) {
        debugPrint(
          'ServicioPreguntas.obtenerPreguntasPorIds no-activo error: $e',
        );
        return [];
      }
    }

    final preguntas = await _obtenerPreguntasDesdeFuente(
      ids: ordenIds,
      materia: materia,
      categoria: categoria,
    );
    return _ordenarPreguntasPorIds(idsEnOrden: ordenIds, preguntas: preguntas);
  }

  Future<List<Materia>> obtenerMaterias() async {
    if (!SupabaseService.isInitialized) {
      return _obtenerMateriasMock();
    }

    try {
      final rows = await SupabaseService.client
          .from('materia')
          .select(
            'id, nombre, descripcion, icono, color_hex, orden_visualizacion, activo',
          )
          .eq('activo', true)
          .order('orden_visualizacion', ascending: true);

      final materias = (rows as List<dynamic>)
          .map((e) => _toMap(e))
          .map(
            (m) => Materia(
              id: m['id'].toString(),
              nombre: (m['nombre'] ?? 'Sin nombre').toString(),
              descripcion: m['descripcion']?.toString(),
              icono: (m['icono'] ?? 'book').toString(),
              color: (m['color_hex'] ?? '#3B82F6').toString(),
              orden: _toInt(m['orden_visualizacion']) ?? 0,
            ),
          )
          .toList();

      if (materias.isEmpty) return _obtenerMateriasMock();
      return materias;
    } catch (e) {
      debugPrint('ServicioPreguntas.obtenerMaterias error: $e');
      return _obtenerMateriasMock();
    }
  }

  Future<void> precalentarPreguntas({
    String categoria = 'Ambos',
    String? materia,
  }) async {
    if (!SupabaseService.isInitialized) return;
    if (_esInvitadoConSupabase) {
      try {
        await _obtenerIdsFijosInvitado(categoria: categoria, materia: materia);
      } catch (_) {
        // Ignorado: es solo precalentamiento.
      }
      return;
    }
    try {
      await _obtenerIdsPreguntasDisponibles(
        categoria: categoria,
        materia: materia,
      );
    } catch (_) {
      // Ignorado: es solo precalentamiento.
    }
  }

  Future<List<Map<String, dynamic>>> _obtenerMateriasActivasCached() async {
    if (!SupabaseService.isInitialized) return const [];

    final now = DateTime.now();
    final cache = _materiasActivasCache;
    final cacheAt = _materiasActivasCacheAt;
    if (cache != null &&
        cacheAt != null &&
        now.difference(cacheAt) <= _cacheMateriasTtl) {
      return cache;
    }

    final materiasRaw = await SupabaseService.client
        .from('materia')
        .select('id, nombre, activo')
        .eq('activo', true);
    final materias = (materiasRaw as List<dynamic>).map(_toMap).toList();

    _materiasActivasCache = materias;
    _materiasActivasCacheAt = now;
    return materias;
  }

  Future<Set<String>?> _resolverMateriaIdsPermitidas(String? materia) async {
    if (materia == null || materia == 'Todas') return null;

    final objetivo = _normalizar(materia);
    final materias = await _obtenerMateriasActivasCached();
    final ids = materias
        .where((m) {
          final nombre = _normalizar(m['nombre']);
          return nombre == objetivo ||
              nombre.contains(objetivo) ||
              objetivo.contains(nombre);
        })
        .map((m) => m['id'].toString())
        .toSet();

    return ids;
  }

  Future<List<String>> _obtenerIdsPreguntasDisponibles({
    String? materia,
    String categoria = 'Ambos',
  }) async {
    final prefijoCategoria = _prefijoCodigoPorCategoria(categoria);
    final categoriaNormalizada = _normalizar(categoria);
    String? materiaFiltrada = materia;

    // Compatibilidad: categoria usada como nombre de materia.
    if (materiaFiltrada == null &&
        _debeCategoriaActuarComoFiltroMateria(
          categoriaNormalizada: categoriaNormalizada,
          prefijoCategoria: prefijoCategoria,
        )) {
      materiaFiltrada = categoria;
    }

    final cacheKey =
        '${_normalizar(categoria)}|${_normalizar(materiaFiltrada ?? 'todas')}';
    final cache = _idsCachePorFiltro[cacheKey];
    if (cache != null && cache.isNotEmpty) return cache;

    final materiaIdsPermitidas = await _resolverMateriaIdsPermitidas(
      materiaFiltrada,
    );
    if (materiaFiltrada != null &&
        materiaFiltrada != 'Todas' &&
        (materiaIdsPermitidas == null || materiaIdsPermitidas.isEmpty)) {
      return const [];
    }

    dynamic query = SupabaseService.client
        .from('pregunta')
        .select('id')
        .eq('activo', true);

    if (prefijoCategoria != null) {
      query = query.like('codigo_pregunta', '$prefijoCategoria%');
    }

    if (materiaIdsPermitidas != null) {
      query = query.inFilter('materia_id', materiaIdsPermitidas.toList());
    }

    const pageSize = 1000;
    const maxPaginas = 50;
    var offset = 0;
    var paginasLeidas = 0;
    final ids = <String>[];
    while (true) {
      final pageRaw = await query
          .order('id', ascending: true)
          .range(offset, offset + pageSize - 1);

      final page = (pageRaw as List<dynamic>).map(_toMap).toList();
      if (page.isEmpty) break;

      for (final row in page) {
        final id = row['id']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      }

      paginasLeidas++;
      if (paginasLeidas >= maxPaginas) break;

      if (page.length < pageSize) break;
      offset += pageSize;
    }

    _idsCachePorFiltro[cacheKey] = ids;
    return ids;
  }

  Future<List<Pregunta>> _obtenerPreguntasDesdeFuente({
    List<String>? ids,
    String? materia,
    String categoria = 'Ambos',
  }) async {
    if (!SupabaseService.isInitialized) {
      return _obtenerPreguntasMock(ids: ids, materia: materia, categoria: categoria);
    }

    try {
      final client = SupabaseService.client;

      String? materiaFiltrada = materia;
      final prefijoCategoria = _prefijoCodigoPorCategoria(categoria);
      final categoriaNormalizada = _normalizar(categoria);

      // Compatibilidad: si "categoria" viene como nombre de materia
      // (ej. "Legislacion Policial"), lo aplicamos como filtro de materia.
      if (materiaFiltrada == null &&
          _debeCategoriaActuarComoFiltroMateria(
            categoriaNormalizada: categoriaNormalizada,
            prefijoCategoria: prefijoCategoria,
          )) {
        materiaFiltrada = categoria;
      }

      final materias = await _obtenerMateriasActivasCached();
      final materiaById = {for (final m in materias) m['id'].toString(): m};

      final materiaIdsPermitidas = await _resolverMateriaIdsPermitidas(
        materiaFiltrada,
      );
      if (materiaFiltrada != null &&
          materiaFiltrada != 'Todas' &&
          (materiaIdsPermitidas == null || materiaIdsPermitidas.isEmpty)) {
        return [];
      }

      final preguntasRows = <Map<String, dynamic>>[];

      if (ids != null && ids.isNotEmpty) {
        // Evita URLs excesivas al aplicar filtro IN con cientos/miles de IDs.
        for (final chunk in _chunkList(ids, 150)) {
          dynamic chunkQuery = client
              .from('pregunta')
              .select(
                'id, codigo_pregunta, numero_oficial, enunciado, contexto, '
                'materia_id, dificultad_estimada, activo',
              )
              .eq('activo', true)
              .inFilter('id', chunk);

          if (materiaIdsPermitidas != null) {
            chunkQuery = chunkQuery.inFilter(
              'materia_id',
              materiaIdsPermitidas.toList(),
            );
          }
          if (prefijoCategoria != null) {
            chunkQuery = chunkQuery.like('codigo_pregunta', '$prefijoCategoria%');
          }

          final chunkRaw = await chunkQuery
              .order('numero_oficial', ascending: true)
              .order('id', ascending: true);
          preguntasRows.addAll((chunkRaw as List<dynamic>).map(_toMap));
        }
      } else {
        dynamic baseQuery = client
            .from('pregunta')
            .select(
              'id, codigo_pregunta, numero_oficial, enunciado, contexto, '
              'materia_id, dificultad_estimada, activo',
            )
            .eq('activo', true);

        if (materiaIdsPermitidas != null) {
          baseQuery = baseQuery.inFilter(
            'materia_id',
            materiaIdsPermitidas.toList(),
          );
        }
        if (prefijoCategoria != null) {
          baseQuery = baseQuery.like('codigo_pregunta', '$prefijoCategoria%');
        }

        // Supabase suele tener "API max rows" = 1000.
        // Paginamos para traer TODO el banco (3000/6000+) y no quedarnos en 1000.
        const pageSize = 1000;
        const maxPaginas = 50;
        var offset = 0;
        var paginasLeidas = 0;
        while (true) {
          final pageRaw = await baseQuery
              .order('numero_oficial', ascending: true)
              .order('id', ascending: true)
              .range(offset, offset + pageSize - 1);

          final page = (pageRaw as List<dynamic>).map(_toMap).toList();
          if (page.isEmpty) break;

          preguntasRows.addAll(page);

          paginasLeidas++;
          if (paginasLeidas >= maxPaginas) break;

          if (page.length < pageSize) break;
          offset += pageSize;
        }
      }

      if (preguntasRows.isEmpty) return [];

      final preguntaIds = preguntasRows.map((p) => p['id'].toString()).toList();

      // Evita URLs demasiado largas en PostgREST cuando hay miles de IDs
      // (ejemplo: carga completa de 3000+ preguntas).
      final alternativasRows = <Map<String, dynamic>>[];
      for (final chunk in _chunkList(preguntaIds, 150)) {
        final alternativasRaw = await client
            .from('alternativa')
            .select('pregunta_id, letra, texto, es_correcta, orden')
            .inFilter('pregunta_id', chunk);
        alternativasRows.addAll(
          (alternativasRaw as List<dynamic>).map(_toMap),
        );
      }

      final alternativasPorPregunta = <String, List<Map<String, dynamic>>>{};
      for (final alt in alternativasRows) {
        final preguntaId = alt['pregunta_id'].toString();
        alternativasPorPregunta.putIfAbsent(preguntaId, () => []);
        alternativasPorPregunta[preguntaId]!.add(alt);
      }

      final resultado = <Pregunta>[];
      for (final p in preguntasRows) {
        final preguntaId = p['id'].toString();
        final alternativas = alternativasPorPregunta[preguntaId] ?? const [];
        if (alternativas.isEmpty) continue;

        alternativas.sort((a, b) {
          final ao = _toInt(a['orden']) ?? 0;
          final bo = _toInt(b['orden']) ?? 0;
          if (ao != bo) return ao.compareTo(bo);
          return a['letra'].toString().compareTo(b['letra'].toString());
        });

        final opciones = alternativas
            .map((a) => (a['texto'] ?? '').toString().trim())
            .where((t) => t.isNotEmpty)
            .toList();
        if (opciones.isEmpty) continue;

        while (opciones.length < 4) {
          opciones.add('Opcion no disponible');
        }

        var indiceCorrecta =
            alternativas.indexWhere((a) => a['es_correcta'] == true);
        if (indiceCorrecta < 0 || indiceCorrecta >= opciones.length) {
          indiceCorrecta = 0;
        }

        final materiaId = p['materia_id']?.toString();
        final materiaNombre = materiaId != null
            ? (materiaById[materiaId]?['nombre'] ?? 'Sin materia')
            : 'Sin materia';

        resultado.add(
          Pregunta(
            id: preguntaId,
            numero:
                _toInt(p['numero_oficial']) ??
                _extraerNumero(p['codigo_pregunta']?.toString()) ??
                0,
            texto: (p['enunciado'] ?? '').toString(),
            opciones: opciones,
            indiceRespuestaCorrecta: indiceCorrecta,
            explicacion: (p['contexto'] ?? '').toString(),
            materiaId: materiaId,
            materia: materiaNombre.toString(),
            categoria: 'Ambos',
            dificultad: _normalizarDificultad(p['dificultad_estimada']?.toString()),
          ),
        );
      }

      return resultado;
    } catch (e) {
      debugPrint('ServicioPreguntas._obtenerPreguntasDesdeFuente error: $e');
      if (_esInvitadoConSupabase) {
        return [];
      }
      return _obtenerPreguntasMock(ids: ids, materia: materia, categoria: categoria);
    }
  }

  List<Pregunta> _obtenerPreguntasMock({
    List<String>? ids,
    String? materia,
    String categoria = 'Ambos',
  }) {
    var preguntas = List<Pregunta>.from(DatosPrueba.preguntas);

    String? materiaFiltrada = materia;
    final categoriaNormalizada = _normalizar(categoria);
    final prefijoCategoria = _prefijoCodigoPorCategoria(categoria);
    if (materiaFiltrada == null &&
        _debeCategoriaActuarComoFiltroMateria(
          categoriaNormalizada: categoriaNormalizada,
          prefijoCategoria: prefijoCategoria,
        )) {
      materiaFiltrada = categoria;
    }

    if (ids != null && ids.isNotEmpty) {
      final idsSet = ids.toSet();
      preguntas = preguntas.where((p) => idsSet.contains(p.id)).toList();
    }

    if (materiaFiltrada != null && materiaFiltrada != 'Todas') {
      final objetivo = _normalizar(materiaFiltrada);
      preguntas = preguntas.where((p) {
        final actual = _normalizar(p.materia);
        return actual == objetivo ||
            actual.contains(objetivo) ||
            objetivo.contains(actual);
      }).toList();
    }

    return preguntas;
  }

  List<Materia> _obtenerMateriasMock() {
    return const [
      Materia(
        id: '1',
        nombre: 'Derecho Constitucional',
        color: '#ff5722',
        icono: 'balance',
      ),
      Materia(
        id: '2',
        nombre: 'Derecho Penal',
        color: '#2196f3',
        icono: 'gavel',
      ),
      Materia(
        id: '3',
        nombre: 'Funcion Policial',
        color: '#4caf50',
        icono: 'security',
      ),
    ];
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  String _normalizar(dynamic value) {
    return (value ?? '').toString().toLowerCase().trim();
  }

  bool _debeCategoriaActuarComoFiltroMateria({
    required String categoriaNormalizada,
    required String? prefijoCategoria,
  }) {
    if (prefijoCategoria != null) return false;
    if (categoriaNormalizada.isEmpty || categoriaNormalizada == 'ambos') {
      return false;
    }
    if (categoriaNormalizada == 'invitado' ||
        categoriaNormalizada == 'guest' ||
        categoriaNormalizada.contains('invitad')) {
      return false;
    }
    return true;
  }

  bool _snapshotInvitadoCompleto({
    required Map<String, List<String>> snapshot,
    required Set<String> materiasObjetivo,
  }) {
    return _snapshotCompletoPorLimite(
      snapshot: snapshot,
      materiasObjetivo: materiasObjetivo,
      limitePorMateria: _limiteInvitadoPorMateria,
    );
  }

  bool _snapshotCompletoPorLimite({
    required Map<String, List<String>> snapshot,
    required Set<String> materiasObjetivo,
    required int limitePorMateria,
  }) {
    if (materiasObjetivo.isEmpty) return false;
    for (final materiaId in materiasObjetivo) {
      final ids = snapshot[materiaId];
      if (ids == null || ids.length < limitePorMateria) {
        return false;
      }
    }
    return true;
  }

  int? _extraerNumero(String? codigoPregunta) {
    if (codigoPregunta == null || codigoPregunta.isEmpty) return null;
    final match = RegExp(r'(\d+)$').firstMatch(codigoPregunta);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  String _normalizarDificultad(String? dificultad) {
    final value = _normalizar(dificultad);
    if (value.startsWith('facil')) return 'Facil';
    if (value.startsWith('dificil')) return 'Dificil';
    return 'Media';
  }

  String? _prefijoCodigoPorCategoria(String? categoria) {
    final value = _normalizar(categoria);
    if (value.isEmpty || value == 'ambos') return null;
    if (value.contains('suboficial')) return 'SUB-';
    if (value.contains('oficial')) return 'OFI-';
    return null;
  }

  List<List<T>> _chunkList<T>(List<T> items, int size) {
    if (items.isEmpty) return const [];
    final chunks = <List<T>>[];
    for (var i = 0; i < items.length; i += size) {
      final end = (i + size < items.length) ? i + size : items.length;
      chunks.add(items.sublist(i, end));
    }
    return chunks;
  }
}
