import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import '../modelos/modelo_pregunta.dart';
import '../modelos/tutor_dashboard_inicio.dart';
import '../servicios/auth_service.dart';
import '../servicios/tutor_ia_personal_service.dart';
import '../servicios/servicio_preguntas.dart';
import '../servicios/servicio_progreso.dart';
import '../tema/tema_aplicacion.dart';
import '../widgets/tarjeta_pregunta.dart';
import 'pantalla_practica.dart';
import 'pantalla_preguntas_acertadas.dart';
import 'pantalla_preguntas_incorrectas.dart';

part 'pantalla_plan_tutor_ia_personal_mapa_temas.dart';
part 'pantalla_plan_tutor_ia_personal_proyeccion_tiempo.dart';
part 'pantalla_plan_tutor_ia_personal_prediccion_olvido.dart';
part 'pantalla_plan_tutor_ia_personal_coach_velocidad.dart';
// En este paso, usaremos un Map dinamico para el resultado del servicio,
// pero podriamos adaptar DiagnosticoIA mas adelante.

class PantallaPlanTutorIAPersonal extends StatefulWidget {
  final TutorIAPersonalService? iaService;
  final ServicioPreguntas? servicioPreguntas;
  final bool esInvitado;

  const PantallaPlanTutorIAPersonal({
    super.key,
    this.iaService,
    this.servicioPreguntas,
    this.esInvitado = false,
  });

  @override
  State<PantallaPlanTutorIAPersonal> createState() =>
      _PantallaPlanTutorIAPersonalState();
}

class _PantallaPlanTutorIAPersonalState
    extends State<PantallaPlanTutorIAPersonal> {
  late final TutorIAPersonalService _iaService;
  late final ServicioPreguntas _servicioPreguntas;
  late final ServicioProgreso _servicioProgreso;
  static const bool _tutorDashboardV2Enabled = true;
  static const Duration _cacheAnalisisFreshWindow = Duration(minutes: 10);
  static final Map<String, Map<String, dynamic>> _cacheAnalisisPorUsuario = {};
  static final Map<String, DateTime> _cacheAnalisisAtPorUsuario = {};
  static final Map<String, Map<String, dynamic>> _cacheDashboardPorUsuario = {};
  static final Map<String, DateTime> _cacheDashboardAtPorUsuario = {};
  Map<String, dynamic>? _analisisPerfil;
  TutorDashboardInicio? _dashboardInicio;
  String _categoriaUsuario = 'Oficiales de Armas';
  String _userId = 'user_test_id';
  DateTime? _fechaRegistroUsuario;
  bool _cargando = true;
  bool _accesoRestringidoInvitado = false;
  bool _actualizandoTutor = false;

  Map<String, dynamic> _analisisPerfilInicial() {
    return {
      'nivel_global': 'INICIAL',
      'tasa_acierto': 0.0,
      'velocidad_promedio': 0.0,
      'racha_dias': 0,
      'fortalezas': <String>[],
      'debilidades': <String>[],
      'analisis_materias': <Map<String, dynamic>>[],
      'resumen_materias':
          'Aun no hay suficiente informacion. Completa una practica para generar recomendaciones.',
      'diagnostico': 'No se pudo cargar el analisis del tutor en este momento.',
      'panel_ia': {'cards': <Map<String, dynamic>>[]},
    };
  }

  void _limpiarCacheAnalisis() {
    final now = DateTime.now();
    const expiracion = Duration(hours: 1);
    final expiradas = _cacheAnalisisAtPorUsuario.entries
        .where((entry) => now.difference(entry.value) > expiracion)
        .map((entry) => entry.key)
        .toList();

    for (final key in expiradas) {
      _cacheAnalisisAtPorUsuario.remove(key);
      _cacheAnalisisPorUsuario.remove(key);
      _cacheDashboardAtPorUsuario.remove(key);
      _cacheDashboardPorUsuario.remove(key);
    }

    const maxEntradas = 20;
    if (_cacheAnalisisAtPorUsuario.length <= maxEntradas) return;

    final ordenadas = _cacheAnalisisAtPorUsuario.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final exceso = _cacheAnalisisAtPorUsuario.length - maxEntradas;
    for (var i = 0; i < exceso; i++) {
      final key = ordenadas[i].key;
      _cacheAnalisisAtPorUsuario.remove(key);
      _cacheAnalisisPorUsuario.remove(key);
      _cacheDashboardAtPorUsuario.remove(key);
      _cacheDashboardPorUsuario.remove(key);
    }
  }

  @override
  void initState() {
    super.initState();
    _iaService = widget.iaService ?? TutorIAPersonalService();
    _servicioPreguntas = widget.servicioPreguntas ?? ServicioPreguntas();
    _servicioProgreso = ServicioProgreso();
    _accesoRestringidoInvitado = widget.esInvitado || !AuthService.isLoggedIn;
    if (_accesoRestringidoInvitado) {
      _cargando = false;
      return;
    }
    _cargarDatos();
  }

  Future<void> _cargarDatos({bool forzarRecarga = false}) async {
    _limpiarCacheAnalisis();
    try {
      final perfilUsuario = await AuthService.getCurrentUserProfile();
      final categoria = perfilUsuario?['categoria'] as String?;
      final fechaRegistro = _parseFechaLocal(perfilUsuario?['fecha_registro']);

      // Usamos el ID real si existe, sino uno de prueba para evitar crashes en dev
      final userId =
          perfilUsuario?['id'] ??
          AuthService.currentUser?.id ??
          perfilUsuario?['usuario_id'] ??
          'user_test_id';

      final cacheAt = _cacheAnalisisAtPorUsuario[userId];
      final cacheData = _cacheAnalisisPorUsuario[userId];
      final dashboardAt = _cacheDashboardAtPorUsuario[userId];
      final dashboardData = _cacheDashboardPorUsuario[userId];
      final cachePareceFallback =
          (cacheData?['nivel_global']?.toString().toUpperCase().contains(
                'CALCULANDO',
              ) ??
              false) ||
          (cacheData?['diagnostico']?.toString().toLowerCase().contains(
                'recopilando',
              ) ??
              false) ||
          ((dashboardData?['estado'] ?? '').toString().toLowerCase() ==
              'fallback');

      // Modo instantaneo: si hay cache, se pinta de inmediato.
      if (!forzarRecarga && cacheData != null && mounted) {
        setState(() {
          _analisisPerfil = Map<String, dynamic>.from(cacheData);
          if (dashboardData != null) {
            _dashboardInicio = TutorDashboardInicio.fromMap(dashboardData);
          }
          _userId = userId;
          _fechaRegistroUsuario = fechaRegistro;
          if (categoria != null && categoria.isNotEmpty) {
            _categoriaUsuario = categoria;
          }
          _cargando = false;
        });

        // Si el cache aun es muy reciente, evitamos pedir de nuevo.
        if (cacheAt != null &&
            dashboardAt != null &&
            DateTime.now().difference(cacheAt) < _cacheAnalisisFreshWindow &&
            DateTime.now().difference(dashboardAt) <
                _cacheAnalisisFreshWindow &&
            !cachePareceFallback) {
          return;
        }
      }

      // Si ya hay vista en pantalla, actualizamos en segundo plano.
      if (mounted && _analisisPerfil != null) {
        setState(() {
          _actualizandoTutor = true;
        });
      }

      final resultado = await _iaService.analizarPerfilCompleto(
        userId,
        perfilUsuario: perfilUsuario,
      );
      final dashboard = await _iaService.obtenerDashboardTutorInicio(
        userId: userId,
        perfilUsuario: Map<String, dynamic>.from(
          perfilUsuario ?? const <String, dynamic>{},
        ),
      );
      _cacheAnalisisPorUsuario[userId] = Map<String, dynamic>.from(resultado);
      _cacheAnalisisAtPorUsuario[userId] = DateTime.now();
      _cacheDashboardPorUsuario[userId] = Map<String, dynamic>.from(dashboard);
      _cacheDashboardAtPorUsuario[userId] = DateTime.now();

      if (mounted) {
        setState(() {
          _analisisPerfil = resultado;
          _dashboardInicio = TutorDashboardInicio.fromMap(dashboard);
          _userId = userId;
          _fechaRegistroUsuario = fechaRegistro;
          if (categoria != null && categoria.isNotEmpty) {
            _categoriaUsuario = categoria;
          }
          _cargando = false;
          _actualizandoTutor = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _analisisPerfil ??= _analisisPerfilInicial();
          _dashboardInicio ??= TutorDashboardInicio.fallback();
          _cargando = false;
          _actualizandoTutor = false;
        });
      }
    }
  }

  int _intValue(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  List<Map<String, dynamic>> _obtenerAnalisisMaterias() {
    final raw =
        (_analisisPerfil ?? _analisisPerfilInicial())['analisis_materias'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  List<String> _toSafeStringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<String> _idsUnicos(Iterable<String> ids) {
    final salida = <String>[];
    final vistos = <String>{};
    for (final raw in ids) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      if (vistos.add(id)) salida.add(id);
    }
    return salida;
  }

  DateTime? _parseFechaLocal(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final fecha = DateTime.tryParse(raw);
    if (fecha == null) return null;
    return fecha.toLocal();
  }

  Future<void> _abrirAnalisisCompletoPerfil() async {
    double toSafeDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    final analisis = _analisisPerfil ?? _analisisPerfilInicial();
    final diagnostico = (analisis['diagnostico'] ?? '').toString();
    final resumenMaterias = (analisis['resumen_materias'] ?? '').toString();
    final materiasAnalisis = _obtenerAnalisisMaterias();
    final velocidadPromedio = toSafeDouble(analisis['velocidad_promedio']);
    final rachaDias = _intValue(analisis['racha_dias'], 0);
    final tasaAcierto = toSafeDouble(analisis['tasa_acierto']);
    final fortalezas = <String>[
      ..._toSafeStringList(analisis['fortalezas']),
      if (velocidadPromedio > 0 && velocidadPromedio < 15)
        "Buena velocidad (${velocidadPromedio.toStringAsFixed(1)} seg/preg)",
      if (rachaDias >= 3) "Racha de $rachaDias dias",
    ];
    final debilidades = <String>[
      ..._toSafeStringList(analisis['debilidades']),
      if (tasaAcierto > 0 && tasaAcierto < 50)
        "Tendencia a impulsividad (Necesitas mas analisis)",
    ];

    await _abrirPanelMaterias(
      diagnostico: diagnostico,
      resumenMaterias: resumenMaterias,
      materiasAnalisis: materiasAnalisis,
      fortalezas: fortalezas,
      debilidades: debilidades,
    );
  }

  Future<void> _abrirDetalleMateria(Map<String, dynamic> materia) async {
    final debilidadesGlobales = List<String>.from(
      _analisisPerfil?['debilidades'] ?? [],
    );
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetalleMateriaSheet(
        userId: _userId,
        materia: materia,
        categoriaUsuario: _categoriaUsuario,
        debilidadesGlobales: debilidadesGlobales,
        iaService: _iaService,
        servicioPreguntas: _servicioPreguntas,
        onPracticar:
            (
              cantidad,
              tiempoMinutos,
              materiaNombre,
              idsCriticas, {
              bool esPracticaGuiada = false,
            }) async {
              await _iniciarPractica(
                cantidad: cantidad,
                tiempoLimite: tiempoMinutos,
                materia: materiaNombre,
                preguntaIdsPrioritarias: idsCriticas,
                esPracticaGuiada: esPracticaGuiada,
              );
            },
      ),
    );
  }

  Future<void> _abrirPanelMaterias({
    required String diagnostico,
    required String resumenMaterias,
    required List<Map<String, dynamic>> materiasAnalisis,
    required List<String> fortalezas,
    required List<String> debilidades,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PantallaAnalisisMaterias(
          userId: _userId,
          categoriaUsuario: _categoriaUsuario,
          iaService: _iaService,
          diagnostico: diagnostico,
          resumenMaterias: resumenMaterias,
          materiasAnalisis: materiasAnalisis,
          fortalezas: fortalezas,
          debilidades: debilidades,
          analisisBase: _analisisPerfil ?? _analisisPerfilInicial(),
          onMateriaTap: _abrirDetalleMateria,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _obtenerCardsIA() {
    final panel = (_analisisPerfil ?? _analisisPerfilInicial())['panel_ia'];
    if (panel is Map && panel['cards'] is List) {
      return (panel['cards'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  TutorInsightCard? _insightPorId(String id) {
    final dashboard = _dashboardInicio;
    if (dashboard == null) return null;
    final objetivo = id.toLowerCase().trim();
    for (final card in dashboard.insights) {
      if (card.id.toLowerCase().trim() == objetivo) return card;
    }
    return null;
  }

  int _sugerirCantidadPracticaGuiadaTutor({
    required int cantidadPrioritarias,
    required int cantidadMateriasObjetivo,
    required int cantidadCoachMemoria,
    required int cantidadRepasoMemoria,
    required int cantidadCoachVelocidad,
  }) {
    final basePrioritaria = cantidadPrioritarias.clamp(0, 80);
    final refuerzoMaterias = math.min(15, cantidadMateriasObjetivo * 5);
    final memoriaObjetivo = math.max(
      cantidadCoachMemoria.clamp(0, 25),
      cantidadRepasoMemoria.clamp(0, 15) + 10,
    );
    final velocidadObjetivo = cantidadCoachVelocidad <= 0
        ? 0
        : math.min(20, cantidadCoachVelocidad + 10);

    var cantidad = math.max(basePrioritaria, 0);
    cantidad = math.max(cantidad, memoriaObjetivo);
    cantidad = math.max(cantidad, velocidadObjetivo);

    if (cantidad < 20) {
      cantidad = 20 + refuerzoMaterias;
    } else if (basePrioritaria < 20) {
      cantidad = math.max(cantidad, 20 + refuerzoMaterias);
    }

    if (cantidad <= 0) {
      cantidad = 35;
    }

    return cantidad.clamp(20, 50).toInt();
  }

  int _sugerirTiempoPracticaGuiadaTutor(int cantidad) {
    final total = cantidad.clamp(1, 120);
    if (total <= 20) return 25;
    if (total <= 30) return 35;
    if (total <= 40) return 45;
    return 60;
  }

  Map<String, dynamic> _resolverConfiguracionPracticaGuiadaTutor() {
    final planHoy = _insightPorId('plan_hoy');
    final materiaPrioritaria = _insightPorId('materia_prioritaria');
    final coachVelocidad = _insightPorId('coach_velocidad');
    final coachMemoria = _insightPorId('coach_memoria');

    final materiasObjetivo = <String>{};
    void agregarMateria(String? raw) {
      final materia = (raw ?? '').trim();
      if (materia.isNotEmpty) {
        materiasObjetivo.add(materia);
      }
    }

    void agregarMaterias(Iterable<String> materias) {
      for (final materia in materias) {
        agregarMateria(materia);
      }
    }

    agregarMateria(materiaPrioritaria?.materia);
    agregarMateria(coachVelocidad?.materia);
    agregarMaterias(coachVelocidad?.materiasPrioritarias ?? const <String>[]);
    agregarMaterias(coachMemoria?.materiasPrioritarias ?? const <String>[]);
    for (final riesgo in (coachMemoria?.riesgos ?? const <TutorRiskItem>[])) {
      agregarMateria(riesgo.materia);
    }

    final preguntaIdsPrioritarias = _idsUnicos([
      ...?planHoy?.preguntaIds,
      ...?planHoy?.preguntasRepasoIds,
      ...?planHoy?.preguntasNuevasIds,
      ...?coachVelocidad?.preguntaIds,
      ...?coachMemoria?.preguntaIds,
      ...?coachMemoria?.preguntasRepasoIds,
    ]);

    final materiasLista = materiasObjetivo.toList();
    final cantidad = _sugerirCantidadPracticaGuiadaTutor(
      cantidadPrioritarias: preguntaIdsPrioritarias.length,
      cantidadMateriasObjetivo: materiasLista.length,
      cantidadCoachMemoria: coachMemoria?.preguntaIds.length ?? 0,
      cantidadRepasoMemoria: coachMemoria?.preguntasRepasoIds.length ?? 0,
      cantidadCoachVelocidad: coachVelocidad?.preguntaIds.length ?? 0,
    );
    final tiempo = _sugerirTiempoPracticaGuiadaTutor(cantidad);
    final focoMaterias = materiasLista.take(3).toList();
    final focoTexto = focoMaterias.isEmpty
        ? ''
        : ' Foco: ${focoMaterias.join(', ')}.';
    final mensaje = preguntaIdsPrioritarias.isNotEmpty
        ? 'El tutor organizo una sesion guiada de $cantidad preguntas usando prioridades reales detectadas.$focoTexto'
        : 'El tutor organizo una sesion guiada de $cantidad preguntas segun tus focos tacticos.$focoTexto';

    return {
      'cantidad': cantidad,
      'tiempo': tiempo,
      'materias': materiasLista,
      'pregunta_ids': preguntaIdsPrioritarias,
      'message': mensaje.trim(),
    };
  }

  Map<String, dynamic> _resolverPracticarAhoraDesdeRegistro() {
    final hoy = DateTime.now().toLocal();
    final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);
    final fechaRegistro = _fechaRegistroUsuario;
    var cantidad = 20;
    var tiempo = 25;
    var esCicloGeneral100 = false;

    if (fechaRegistro != null) {
      final registroSolo = DateTime(
        fechaRegistro.year,
        fechaRegistro.month,
        fechaRegistro.day,
      );
      final diasDesdeRegistro = hoySolo.difference(registroSolo).inDays;
      if (diasDesdeRegistro >= 2 && ((diasDesdeRegistro - 2) % 4 == 0)) {
        cantidad = 100;
        tiempo = 120;
        esCicloGeneral100 = true;
      }
    }

    return {
      'type': 'practice',
      'title': 'Practicar ahora',
      'message': esCicloGeneral100
          ? 'Hoy toca la practica general del ciclo: 100 preguntas aleatorias de todas las materias.'
          : 'Practica general rapida: 20 preguntas aleatorias de todas las materias.',
      'cta': 'Completar',
      'payload': {'cantidad': cantidad, 'tiempo': tiempo, 'aleatorio': true},
    };
  }

  Future<Map<String, dynamic>> _construirCardPreguntasFalladasInteligente({
    required int tiempoBase,
  }) async {
    try {
      final intentos = await _servicioProgreso.obtenerPreguntasIncorrectas();
      final totalFalladas = intentos.length;

      if (totalFalladas <= 0) {
        return {
          'type': 'failed',
          'title': 'Preguntas falladas',
          'message':
              'No se detectan preguntas falladas activas por ahora. Mantiene el ritmo de estudio.',
          'cta': 'Sin pendientes',
          'payload': {
            'cantidad': 0,
            'tiempo': tiempoBase,
            'habilitada': false,
            'total_falladas': 0,
          },
        };
      }

      final conteoMateria = <String, int>{};
      for (final intento in intentos) {
        final materia = intento.pregunta.materia.trim();
        if (materia.isEmpty) continue;
        conteoMateria[materia] = (conteoMateria[materia] ?? 0) + 1;
      }

      String materiaTop = '';
      if (conteoMateria.isNotEmpty) {
        final ordenadas = conteoMateria.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        materiaTop = ordenadas.first.key;
      }

      final cantidadPractica = math.min(20, totalFalladas);
      final focoTexto = materiaTop.isEmpty
          ? ''
          : ' Foco principal: $materiaTop.';

      return {
        'type': 'failed',
        'title': 'Preguntas falladas',
        'message':
            'Se detectaron $totalFalladas preguntas falladas activas.$focoTexto',
        'cta': 'Completar',
        'payload': {
          'cantidad': cantidadPractica,
          'tiempo': tiempoBase,
          'habilitada': true,
          'total_falladas': totalFalladas,
          if (materiaTop.isNotEmpty) 'materia': materiaTop,
        },
      };
    } catch (_) {
      return {
        'type': 'failed',
        'title': 'Preguntas falladas',
        'message':
            'No se pudo calcular tus falladas ahora. Intenta de nuevo en unos segundos.',
        'cta': 'Reintentar',
        'payload': {'cantidad': 20, 'tiempo': tiempoBase, 'habilitada': false},
      };
    }
  }

  bool _coincideMateriaConObjetivos(
    Pregunta pregunta,
    Set<String> objetivosMateriaNorm,
  ) {
    if (objetivosMateriaNorm.isEmpty) return true;
    final actual = _normalizarTextoSimple(pregunta.materia);
    if (actual.isEmpty) return false;
    for (final objetivo in objetivosMateriaNorm) {
      if (actual == objetivo ||
          actual.contains(objetivo) ||
          objetivo.contains(actual)) {
        return true;
      }
    }
    return false;
  }

  Future<int> _contarDisponiblesParaPractica({
    String? materia,
    List<String> materiasObjetivo = const <String>[],
    List<String> preguntaIdsPrioritarias = const <String>[],
  }) async {
    final objetivosMateria = <String>{
      if (materia != null && materia.trim().isNotEmpty) materia.trim(),
      ...materiasObjetivo.map((e) => e.trim()).where((e) => e.isNotEmpty),
    };
    final objetivosMateriaNorm = objetivosMateria
        .map(_normalizarTextoSimple)
        .where((e) => e.isNotEmpty)
        .toSet();

    final idsDisponibles = <String>{};

    if (preguntaIdsPrioritarias.isNotEmpty) {
      var priorizadas = await _servicioPreguntas.obtenerPreguntasPorIds(
        ids: preguntaIdsPrioritarias,
        categoria: _categoriaUsuario,
        materia: materia,
      );
      if (priorizadas.isEmpty) {
        priorizadas = await _servicioPreguntas.obtenerPreguntasPorIds(
          ids: preguntaIdsPrioritarias,
          categoria: _categoriaUsuario,
        );
      }
      if (objetivosMateriaNorm.isNotEmpty) {
        final filtradas = priorizadas
            .where((p) => _coincideMateriaConObjetivos(p, objetivosMateriaNorm))
            .toList();
        if (filtradas.isNotEmpty) {
          priorizadas = filtradas;
        }
      }
      for (final p in priorizadas) {
        idsDisponibles.add(p.id);
      }
    }

    final idsPorFiltro = await _servicioPreguntas.obtenerIdsDisponibles(
      categoria: _categoriaUsuario,
      materia: materia,
      materias: objetivosMateria.toList(),
    );
    idsDisponibles.addAll(idsPorFiltro);

    return idsDisponibles.length;
  }

  String _mensajeSinDisponiblesPorTipo(String type) {
    switch (type) {
      case 'guided':
        return 'No hay preguntas disponibles para tu practica guiada en este momento.';
      case 'plan':
        return 'No hay preguntas disponibles para esta orden del plan en este momento.';
      case 'practice':
      default:
        return 'No hay preguntas disponibles para este enfoque ahora.';
    }
  }

  Future<Map<String, dynamic>> _ajustarCardSegunDisponibilidadReal(
    Map<String, dynamic> card,
  ) async {
    final type = (card['type'] ?? 'message').toString().trim().toLowerCase();
    if (type != 'guided' && type != 'plan' && type != 'practice') {
      return card;
    }

    final payload = card['payload'] is Map
        ? Map<String, dynamic>.from(card['payload'])
        : <String, dynamic>{};
    if (payload.isEmpty) return card;

    final cantidadSolicitada = _intValue(payload['cantidad'], 20).clamp(1, 120);
    final materia = payload['materia'] is String
        ? payload['materia'].toString().trim()
        : null;
    final materiasObjetivo = payload['materias'] is List
        ? (payload['materias'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[];
    final preguntaIds = payload['pregunta_ids'] is List
        ? (payload['pregunta_ids'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[];

    final disponibles = await _contarDisponiblesParaPractica(
      materia: materia,
      materiasObjetivo: materiasObjetivo,
      preguntaIdsPrioritarias: preguntaIds,
    );

    final ajustada = Map<String, dynamic>.from(card);
    if (disponibles <= 0) {
      payload['cantidad'] = 0;
      payload['habilitada'] = false;
      payload['disponibles'] = 0;
      ajustada['payload'] = payload;
      ajustada['cta'] = 'Sin disponibles';
      ajustada['message'] = _mensajeSinDisponiblesPorTipo(type);
      return ajustada;
    }

    final cantidadReal = math.min(cantidadSolicitada, disponibles);
    payload['cantidad'] = cantidadReal;
    payload['habilitada'] = true;
    payload['disponibles'] = disponibles;
    ajustada['payload'] = payload;

    if (cantidadReal < cantidadSolicitada) {
      final mensajeBase = (ajustada['message'] ?? '').toString().trim();
      final ajuste = 'Disponibles ahora: $cantidadReal.';
      ajustada['message'] = mensajeBase.isEmpty
          ? ajuste
          : '$mensajeBase $ajuste';
    }

    return ajustada;
  }

  Future<List<Map<String, dynamic>>> _obtenerOrdenesTutorParaHoyCards() async {
    final dashboard = _dashboardInicio;
    final mision = _dashboardInicio?.misionDiaria;
    final cantidadBase = _intValue(mision?.cantidadPractica, 30).clamp(15, 120);
    final tiempoBase = _intValue(mision?.tiempoPractica, 40).clamp(15, 120);

    final planHoy = _insightPorId('plan_hoy');
    final materiaPrioritaria = _insightPorId('materia_prioritaria');
    final coach = _insightPorId('coach_velocidad');
    final coachMemoria = _insightPorId('coach_memoria');
    final practicaGuiada = _resolverConfiguracionPracticaGuiadaTutor();
    final practicarAhora = _resolverPracticarAhoraDesdeRegistro();
    final cardFalladas = await _construirCardPreguntasFalladasInteligente(
      tiempoBase: tiempoBase,
    );

    Map<String, dynamic> cardPracticaDesdeInsight({
      required String title,
      required TutorInsightCard? insight,
      String? fallbackMessage,
      String? fallbackMateria,
      List<String> fallbackMaterias = const <String>[],
      List<String> fallbackPreguntaIds = const <String>[],
      bool excluirIdsInsight = false,
    }) {
      var cantidad = _intValue(
        insight?.cantidadPractica,
        cantidadBase,
      ).clamp(10, 120);
      final tiempo = _intValue(
        insight?.tiempoPractica,
        tiempoBase,
      ).clamp(10, 120);
      final preguntaIds = _idsUnicos([
        if (!excluirIdsInsight) ...?insight?.preguntaIds,
        ...fallbackPreguntaIds,
      ]);
      final materiaInsight = (insight?.materia ?? '').trim();
      final materia = materiaInsight.isNotEmpty
          ? materiaInsight
          : (preguntaIds.isNotEmpty ? '' : (fallbackMateria ?? '').trim());
      if (preguntaIds.isNotEmpty && cantidad < preguntaIds.length) {
        cantidad = preguntaIds.length;
      }
      final materias = <String>{
        if (materia.isNotEmpty) materia,
        ...?insight?.materiasPrioritarias,
        ...fallbackMaterias.map((m) => m.trim()).where((m) => m.isNotEmpty),
      }.toList();

      return {
        'type': 'practice',
        'title': title,
        'message':
            (insight?.resumen ?? fallbackMessage ?? 'Sin recomendacion IA.')
                .toString()
                .trim(),
        'cta': 'Completar',
        if (insight != null) 'insight_id': insight.id,
        'payload': {
          'cantidad': cantidad,
          'tiempo': tiempo,
          if (materia.isNotEmpty) 'materia': materia,
          if (materias.isNotEmpty) 'materias': materias,
          if (preguntaIds.isNotEmpty) 'pregunta_ids': preguntaIds,
        },
      };
    }

    final materiaMemoria =
        (coachMemoria != null && coachMemoria.riesgos.isNotEmpty)
        ? coachMemoria.riesgos.first.materia
        : null;
    final materiasMemoria = _idsUnicos([
      ...?coachMemoria?.materiasPrioritarias,
      ...(coachMemoria?.riesgos ?? const <TutorRiskItem>[]).map(
        (e) => e.materia.trim(),
      ),
    ]);
    final materiasVelocidad = _idsUnicos([
      ...?coach?.materiasPrioritarias,
      if ((coach?.materia ?? '').trim().isNotEmpty) coach!.materia!.trim(),
    ]);

    final cards = <Map<String, dynamic>>[
      {
        'type': 'guided',
        'title': 'Practica guiada',
        'message': (practicaGuiada['message'] ?? '').toString().trim().isEmpty
            ? 'La IA organiza tu sesion completa por materias, dificultad y enfoque de mejora.'
            : (practicaGuiada['message'] ?? '').toString().trim(),
        'cta': 'Completar',
        'payload': {
          'cantidad': _intValue(practicaGuiada['cantidad'], 50),
          'tiempo': _intValue(practicaGuiada['tiempo'], 60),
          if (practicaGuiada['materias'] is List &&
              (practicaGuiada['materias'] as List).isNotEmpty)
            'materias': List<String>.from(practicaGuiada['materias'] as List),
          if (practicaGuiada['pregunta_ids'] is List &&
              (practicaGuiada['pregunta_ids'] as List).isNotEmpty)
            'pregunta_ids': List<String>.from(
              practicaGuiada['pregunta_ids'] as List,
            ),
        },
      },
      practicarAhora,
      cardPracticaDesdeInsight(
        title: 'Materia prioritaria',
        insight: materiaPrioritaria,
        fallbackMessage:
            'Revisa primero la materia mas prioritaria para subir tu nivel hoy.',
        fallbackMateria: materiaPrioritaria?.materia,
        fallbackMaterias: materiasMemoria,
      ),
      cardPracticaDesdeInsight(
        title: 'Mejora de velocidad',
        insight: coach,
        fallbackMessage: 'Refuerza tu precision y ritmo con practica dirigida.',
        fallbackMaterias: materiasVelocidad,
      ),
      cardPracticaDesdeInsight(
        title: 'Coach de memoria',
        insight: coachMemoria,
        fallbackMessage:
            'Refuerza primero tus materias mas sensibles para consolidar memoria.',
        fallbackMateria: materiaMemoria ?? materiaPrioritaria?.materia,
        fallbackMaterias: materiasMemoria,
      ),
      cardFalladas,
    ];

    if (planHoy != null && planHoy.preguntasRepasoIds.isNotEmpty) {
      cards.insert(
        2,
        cardPracticaDesdeInsight(
          title: 'Repaso urgente IA',
          insight: planHoy,
          fallbackMessage:
              'Repasa ahora las preguntas con mayor riesgo de olvido.',
          fallbackMateria: materiaPrioritaria?.materia,
          fallbackMaterias: materiasMemoria,
          fallbackPreguntaIds: planHoy.preguntasRepasoIds,
          excluirIdsInsight: true,
        ),
      );
    }

    if (planHoy != null && planHoy.preguntasNuevasIds.isNotEmpty) {
      cards.insert(
        3,
        cardPracticaDesdeInsight(
          title: 'Nuevas prioritarias IA',
          insight: planHoy,
          fallbackMessage:
              'Avanza en preguntas nuevas de alta importancia para tu meta.',
          fallbackMateria: materiaPrioritaria?.materia,
          fallbackMaterias: materiasMemoria,
          fallbackPreguntaIds: planHoy.preguntasNuevasIds,
          excluirIdsInsight: true,
        ),
      );
    }

    if (dashboard?.sesionValida != true) {
      return cards.map((c) {
        if (c['type'] == 'guided') return c;
        final copy = Map<String, dynamic>.from(c);
        copy['type'] = 'message';
        copy.remove('payload');
        return copy;
      }).toList();
    }

    final cardsAjustadas = <Map<String, dynamic>>[];
    for (final card in cards) {
      cardsAjustadas.add(await _ajustarCardSegunDisponibilidadReal(card));
    }
    return cardsAjustadas;
  }

  Future<void> _abrirOrdenesTutorParaHoy() async {
    final cards = await _obtenerOrdenesTutorParaHoyCards();
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFFECEFF3),
          appBar: AppBar(
            title: Text(
              'ORDENES DEL TUTOR PARA HOY',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: 0.4,
              ),
            ),
          ),
          body: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: cards.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.92,
            ),
            itemBuilder: (_, index) {
              final card = cards[index];
              return _buildTarjetaAccionIACompacta(
                card,
                onTap: () async {
                  if (!mounted) return;
                  await _ejecutarAccionTarjetaIA(card);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackGrid() {
    final cards = <Map<String, dynamic>>[
      {
        'type': 'plan',
        'title': 'Rutina Diaria',
        'message':
            'Completa tu sesion diaria de estudio con una practica guiada por tiempo.',
        'cta': 'Iniciar Rutina Diaria (25 preguntas)',
        'payload': {'cantidad': 25, 'tiempo': 30},
      },
      {
        'type': 'practice',
        'title': 'Realizar Practica',
        'message':
            'Personaliza tu practica y fortalece tus materias con mas impacto.',
        'cta': 'Comenzar Practica',
        'payload': {'cantidad': 100, 'tiempo': 120},
      },
      {
        'type': 'streak',
        'title': 'Racha Activa',
        'message':
            'Mantener la constancia diaria aumenta tu probabilidad de ascenso.',
        'cta': 'Ver estrategia',
      },
    ];

    return Column(children: cards.map(_buildTarjetaAccionIA).toList());
  }

  Color _colorPorTipo(String type) {
    switch (type) {
      case 'study':
        return const Color(0xFF5EC7A7);
      case 'guided':
        return const Color(0xFF0B5A45);
      case 'plan':
        return const Color(0xFFB68B2E);
      case 'practice':
        return const Color(0xFF1E6B63);
      case 'streak':
        return const Color(0xFF237D57);
      case 'recommendation':
        return const Color(0xFF5EC7A7);
      case 'alert':
        return const Color(0xFFAD3636);
      case 'failed':
        return const Color(0xFFAD3636);
      case 'message':
      default:
        return const Color(0xFF111827);
    }
  }

  IconData _iconoPorTipo(String type) {
    switch (type) {
      case 'study':
        return Icons.menu_book_rounded;
      case 'guided':
        return Icons.auto_awesome_rounded;
      case 'plan':
        return Icons.access_time_filled;
      case 'practice':
        return Icons.psychology;
      case 'streak':
        return Icons.local_fire_department;
      case 'recommendation':
        return Icons.tips_and_updates_rounded;
      case 'alert':
        return Icons.warning_amber_rounded;
      case 'failed':
        return Icons.cancel_outlined;
      case 'message':
      default:
        return Icons.psychology_alt;
    }
  }

  String _subtituloPorTipo(
    String type,
    int cantidad,
    int tiempo,
    String? materia,
  ) {
    if (type == 'study') {
      if (materia != null && materia.isNotEmpty) {
        return 'Foco IA: $materia';
      }
      return 'Foco tactico por materia';
    }
    if (type == 'guided') {
      if (cantidad <= 0) return 'Sin preguntas disponibles';
      return '$cantidad preguntas con IA guiada';
    }
    if (type == 'plan') {
      return 'Tu meta de hoy: $tiempo min';
    }
    if (type == 'practice') {
      if (cantidad <= 0) return 'Sin preguntas disponibles';
      if (materia != null && materia.isNotEmpty) {
        return '$cantidad preguntas - $materia';
      }
      return '$cantidad preguntas aleatorias';
    }
    if (type == 'failed') {
      if (cantidad <= 0) return 'Sin falladas activas';
      if (materia != null && materia.isNotEmpty) {
        return '$cantidad preguntas - $materia';
      }
      return '$cantidad preguntas mas falladas';
    }
    if (type == 'streak') {
      final racha = _intValue(_analisisPerfil?['racha_dias'], 0);
      return racha > 0 ? 'Racha actual: $racha dias' : 'Disciplina diaria';
    }
    if (type == 'recommendation') return 'Sugerencia tactica personalizada';
    if (type == 'alert') return 'Atencion prioritaria';
    return 'Mensaje de Tutor IA Personal';
  }

  String _ctaPorDefecto(String type, int cantidad) {
    switch (type) {
      case 'study':
        return 'Ver que estudiar';
      case 'guided':
        return 'Abrir practica guiada';
      case 'plan':
        return 'Iniciar Rutina Diaria ($cantidad preguntas)';
      case 'practice':
        return 'Comenzar Practica';
      case 'streak':
        return 'Ver estrategia';
      case 'recommendation':
        return 'Aplicar consejo';
      case 'alert':
        return 'Revisar alerta';
      case 'failed':
        return 'Practicar falladas';
      case 'message':
      default:
        return 'Ver detalle';
    }
  }

  void _mostrarDetalleOrden({
    required String title,
    required String message,
    required List<String> items,
  }) {
    final detail = <String>[
      if (message.trim().isNotEmpty) message.trim(),
      ...items.where((e) => e.trim().isNotEmpty).map((e) => '- ${e.trim()}'),
    ].join('\n');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(detail.isEmpty ? 'Sin detalles adicionales.' : detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirChatTutor({
    String? promptInicial,
    bool enviarAutomatico = false,
  }) async {
    final analisis = _analisisPerfil ?? _analisisPerfilInicial();
    final contexto = <String, dynamic>{
      'user_id': _userId,
      'categoria_usuario': _categoriaUsuario,
      'nivel_global': analisis['nivel_global'],
      'tasa_acierto': analisis['tasa_acierto'],
      'fortalezas': analisis['fortalezas'],
      'debilidades': analisis['debilidades'],
      'resumen_materias': analisis['resumen_materias'],
    };

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChatTutorSheet(
        iaService: _iaService,
        contexto: contexto,
        promptInicial: promptInicial,
        enviarAutomatico: enviarAutomatico,
      ),
    );
  }

  Future<void> _ejecutarAccionTarjetaIA(Map<String, dynamic> card) async {
    final type = (card['type'] ?? 'message').toString().trim().toLowerCase();
    final title = (card['title'] ?? 'Recomendacion IA').toString().trim();
    final message = (card['message'] ?? '').toString();
    final items = (card['items'] is List)
        ? (card['items'] as List)
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    final payload = card['payload'] is Map
        ? Map<String, dynamic>.from(card['payload'])
        : <String, dynamic>{};
    final cantidad = _intValue(payload['cantidad'], 20);
    final tiempo = _intValue(payload['tiempo'], 25);
    final materia = payload['materia'] is String
        ? payload['materia'] as String
        : null;
    final materiasObjetivo = payload['materias'] is List
        ? (payload['materias'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    final preguntaIds = payload['pregunta_ids'] is List
        ? (payload['pregunta_ids'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    final seleccionarAleatorio = payload['aleatorio'] == true;
    final insightId = (card['insight_id'] ?? '').toString().trim();
    final isStudy = type == 'study';
    final isGuided = type == 'guided';
    final isFailed = type == 'failed';
    final canPractice =
        !isStudy &&
        !isGuided &&
        !isFailed &&
        (type == 'plan' ||
            type == 'practice' ||
            payload.containsKey('cantidad'));

    if (isStudy) {
      await _abrirMapaTemasSemaforo();
      return;
    }
    if (isGuided) {
      if (payload['habilitada'] == false) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No hay preguntas disponibles para esta practica guiada ahora.',
            ),
          ),
        );
        return;
      }
      final disponibles = await _contarDisponiblesParaPractica(
        materia: materia,
        materiasObjetivo: materiasObjetivo,
        preguntaIdsPrioritarias: preguntaIds,
      );
      if (disponibles <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No hay preguntas disponibles para esta practica guiada ahora.',
            ),
          ),
        );
        return;
      }
      final cantidadReal = math.min(cantidad, disponibles);
      await _iniciarPracticaGuiadaDesdeIA(
        cantidad: cantidadReal,
        materia: materia,
        materiasObjetivo: materiasObjetivo,
        preguntaIdsPrioritarias: preguntaIds,
        seleccionarAleatorio: seleccionarAleatorio,
      );
      return;
    }
    if (isFailed) {
      if (payload['habilitada'] == false) {
        if (!mounted) return;
        final texto = message.trim().isEmpty
            ? 'No hay preguntas falladas activas por ahora.'
            : message.trim();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(texto)));
        return;
      }
      await _iniciarPracticaFalladasDesdeIA(cantidad: cantidad);
      return;
    }
    if (canPractice) {
      if (payload['habilitada'] == false) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay preguntas disponibles para esta orden.'),
          ),
        );
        return;
      }
      final disponibles = await _contarDisponiblesParaPractica(
        materia: materia,
        materiasObjetivo: materiasObjetivo,
        preguntaIdsPrioritarias: preguntaIds,
      );
      if (disponibles <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay preguntas disponibles para esta orden.'),
          ),
        );
        return;
      }
      final cantidadReal = math.min(cantidad, disponibles);
      await _iniciarPractica(
        cantidad: cantidadReal,
        tiempoLimite: tiempo,
        materia: materia,
        materiasObjetivo: materiasObjetivo,
        preguntaIdsPrioritarias: preguntaIds,
        seleccionarAleatorio: seleccionarAleatorio,
      );
      return;
    }

    if (insightId.isNotEmpty) {
      final insight = _insightPorId(insightId);
      if (insight != null) {
        await _ejecutarInsightCard(insight);
        return;
      }
    }

    _mostrarDetalleOrden(
      title: title.isEmpty ? 'Recomendacion IA' : title,
      message: message,
      items: items,
    );
  }

  Future<void> _iniciarPracticaGuiadaDesdeIA({
    int? cantidad,
    String? materia,
    List<String> materiasObjetivo = const <String>[],
    List<String> preguntaIdsPrioritarias = const <String>[],
    bool seleccionarAleatorio = false,
  }) async {
    if (!mounted) return;
    if (_dashboardInicio?.sesionValida != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Necesitas una sesion valida para generar practica guiada IA.',
          ),
        ),
      );
      return;
    }

    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return const Center(child: CircularProgressIndicator());
      },
    );

    List<Pregunta> seleccionadas = const [];
    try {
      final practicaGuiada = _resolverConfiguracionPracticaGuiadaTutor();
      final cantidadObjetivo =
          cantidad ?? _intValue(practicaGuiada['cantidad'], 50);
      final materiasObjetivoFinal = materiasObjetivo.isNotEmpty
          ? materiasObjetivo
          : practicaGuiada['materias'] is List
          ? List<String>.from(practicaGuiada['materias'] as List)
          : const <String>[];
      final preguntaIdsFinal = preguntaIdsPrioritarias.isNotEmpty
          ? preguntaIdsPrioritarias
          : practicaGuiada['pregunta_ids'] is List
          ? List<String>.from(practicaGuiada['pregunta_ids'] as List)
          : const <String>[];

      seleccionadas = await _seleccionarPreguntasDeterministicas(
        cantidad: cantidadObjetivo,
        materia: materia,
        materiasObjetivo: materiasObjetivoFinal,
        preguntaIdsPrioritarias: preguntaIdsFinal,
        aleatorio: seleccionarAleatorio,
      );
      if (seleccionadas.isEmpty) {
        throw Exception('No hay preguntas disponibles en tu banco.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar practica guiada IA: $e')),
        );
      }
      return;
    } finally {
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }
    }

    if (!mounted || seleccionadas.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaPractica(
          preguntas: seleccionadas,
          tiempoLimiteSegundos: null,
          esModoPractica: true,
          esRanking: false,
          revisarRespuestaInmediata: true,
        ),
      ),
    );

    if (!mounted) return;
    _cargarDatos(forzarRecarga: true);
  }

  Future<void> _iniciarPracticaFalladasDesdeIA({int cantidad = 20}) async {
    if (!mounted) return;

    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return const Center(child: CircularProgressIndicator());
      },
    );

    List<IntentoFallido> intentos = const <IntentoFallido>[];
    try {
      intentos = await _servicioProgreso.obtenerPreguntasIncorrectas();
    } finally {
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }
    }

    if (!mounted) return;
    if (intentos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aun no tienes preguntas falladas.')),
      );
      return;
    }

    final limite = cantidad <= 0 ? 20 : cantidad;
    final preguntas = intentos.map((e) => e.pregunta).take(limite).toList();
    if (preguntas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay preguntas disponibles para practicar.'),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaPractica(
          preguntas: preguntas,
          tiempoLimiteSegundos: null,
          esModoPractica: true,
          esRanking: false,
          revisarRespuestaInmediata: true,
        ),
      ),
    );

    if (!mounted) return;
    _cargarDatos(forzarRecarga: true);
  }

  Widget _buildTarjetaAccionIACompacta(
    Map<String, dynamic> card, {
    required Future<void> Function() onTap,
  }) {
    final type = (card['type'] ?? 'message').toString().trim().toLowerCase();
    final title = (card['title'] ?? 'Recomendacion IA').toString().trim();
    final message = (card['message'] ?? '').toString().trim();
    final cta = (card['cta'] ?? '').toString().trim();
    final payload = card['payload'] is Map
        ? Map<String, dynamic>.from(card['payload'])
        : <String, dynamic>{};
    final cantidad = _intValue(payload['cantidad'], 20);
    final tiempo = _intValue(payload['tiempo'], 25);
    final materia = payload['materia'] is String
        ? payload['materia'] as String
        : null;
    final color = _colorPorTipo(type);
    final subtitulo = _subtituloPorTipo(type, cantidad, tiempo, materia);
    final ctaFinal = cta.isEmpty ? 'Completar' : cta;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onTap(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.30)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconoPorTipo(type), color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              title.isEmpty ? 'Recomendacion IA' : title.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                message.isEmpty ? 'Sin detalle tactico.' : message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  ctaFinal,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Icon(Icons.arrow_forward_ios_rounded, size: 13, color: color),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTarjetaAccionIA(Map<String, dynamic> card) {
    final type = (card['type'] ?? 'message').toString().trim().toLowerCase();
    final title = (card['title'] ?? 'Recomendacion IA').toString().trim();
    final message = (card['message'] ?? '').toString();
    final cta = (card['cta'] ?? '').toString().trim();
    final items = (card['items'] is List)
        ? (card['items'] as List)
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];

    final payload = card['payload'] is Map
        ? Map<String, dynamic>.from(card['payload'])
        : <String, dynamic>{};
    final cantidad = _intValue(payload['cantidad'], 20);
    final tiempo = _intValue(payload['tiempo'], 25);
    final materia = payload['materia'] is String
        ? payload['materia'] as String
        : null;
    final color = _colorPorTipo(type);
    final subtitulo = _subtituloPorTipo(type, cantidad, tiempo, materia);
    final ctaFinal = cta.isNotEmpty ? cta : _ctaPorDefecto(type, cantidad);

    final description = <String>[
      if (message.trim().isNotEmpty) message.trim(),
      ...items.where((e) => e.trim().isNotEmpty).map((e) => '- ${e.trim()}'),
    ].join('\n');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_iconoPorTipo(type), color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? 'Recomendacion IA' : title,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      subtitulo,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description.isEmpty ? 'Sin descripcion tactica.' : description,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _ejecutarAccionTarjetaIA(card),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Text(
                ctaFinal,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _iniciarPractica({
    required int cantidad,
    required int tiempoLimite,
    String? materia,
    List<String> materiasObjetivo = const <String>[],
    List<String> preguntaIdsPrioritarias = const [],
    bool esPracticaGuiada = false,
    bool seleccionarAleatorio = false,
    bool registrarSesionEnHistorial = true,
    int? tiempoLimiteSegundosPersonalizado,
  }) async {
    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return const Center(child: CircularProgressIndicator());
      },
    );

    final preguntas = <Pregunta>[];
    String? errorMessage;
    try {
      final seleccionadas = await _seleccionarPreguntasDeterministicas(
        cantidad: cantidad,
        materia: materia,
        materiasObjetivo: materiasObjetivo,
        preguntaIdsPrioritarias: preguntaIdsPrioritarias,
        aleatorio: seleccionarAleatorio,
      );
      preguntas.addAll(seleccionadas);
    } catch (e) {
      errorMessage = 'Error al iniciar practica: $e';
    } finally {
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }
    }

    if (!mounted) return;
    if (errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
      return;
    }

    if (preguntas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay preguntas disponibles')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PantallaPractica(
          tiempoLimiteSegundos:
              tiempoLimiteSegundosPersonalizado ?? tiempoLimite * 60,
          preguntas: preguntas,
          esModoPractica: true,
          revisarRespuestaInmediata: esPracticaGuiada,
          registrarSesionEnHistorial: registrarSesionEnHistorial,
        ),
      ),
    );

    if (!mounted) return;
    _cargarDatos(forzarRecarga: true);
  }

  Future<List<Pregunta>> _seleccionarPreguntasDeterministicas({
    required int cantidad,
    String? materia,
    List<String> materiasObjetivo = const <String>[],
    List<String> preguntaIdsPrioritarias = const <String>[],
    bool aleatorio = false,
  }) async {
    final objetivoCantidad = cantidad <= 0 ? 1 : cantidad;
    final seleccion = <Pregunta>[];
    final usados = <String>{};

    final objetivosMateria = <String>{
      if (materia != null && materia.trim().isNotEmpty) materia.trim(),
      ...materiasObjetivo.map((e) => e.trim()).where((e) => e.isNotEmpty),
    };
    final objetivosMateriaNorm = objetivosMateria
        .map(_normalizarTextoSimple)
        .where((e) => e.isNotEmpty)
        .toSet();

    bool coincideMateria(Pregunta pregunta) {
      if (objetivosMateriaNorm.isEmpty) return true;
      final actual = _normalizarTextoSimple(pregunta.materia);
      if (actual.isEmpty) return false;
      for (final objetivo in objetivosMateriaNorm) {
        if (actual == objetivo ||
            actual.contains(objetivo) ||
            objetivo.contains(actual)) {
          return true;
        }
      }
      return false;
    }

    if (preguntaIdsPrioritarias.isNotEmpty) {
      var priorizadas = await _servicioPreguntas.obtenerPreguntasPorIds(
        ids: preguntaIdsPrioritarias,
        categoria: _categoriaUsuario,
        materia: materia,
      );
      if (priorizadas.isEmpty) {
        priorizadas = await _servicioPreguntas.obtenerPreguntasPorIds(
          ids: preguntaIdsPrioritarias,
          categoria: _categoriaUsuario,
        );
      }
      if (objetivosMateriaNorm.isNotEmpty) {
        final filtradas = priorizadas.where(coincideMateria).toList();
        if (filtradas.isNotEmpty) {
          priorizadas = filtradas;
        }
      }
      for (final p in priorizadas) {
        if (seleccion.length >= objetivoCantidad) break;
        if (usados.add(p.id)) {
          seleccion.add(p);
        }
      }
    }

    if (seleccion.length >= objetivoCantidad) {
      return seleccion;
    }

    final idsDisponibles = await _servicioPreguntas.obtenerIdsDisponibles(
      categoria: _categoriaUsuario,
      materia: materia,
      materias: objetivosMateria.toList(),
    );
    final candidatasIds = idsDisponibles
        .where((id) => !usados.contains(id))
        .toList();
    if (candidatasIds.isEmpty) {
      return seleccion;
    }

    if (aleatorio) {
      candidatasIds.shuffle();
    } else {
      final estadisticas = await _servicioProgreso
          .obtenerEstadisticasPreguntas();
      final posicionOriginal = <String, int>{};
      for (var i = 0; i < candidatasIds.length; i++) {
        posicionOriginal[candidatasIds[i]] = i;
      }

      candidatasIds.sort((a, b) {
        final sa = estadisticas[a];
        final sb = estadisticas[b];
        final fallosA = sa?.fallosVisibles ?? 0;
        final fallosB = sb?.fallosVisibles ?? 0;
        if (fallosA != fallosB) return fallosB.compareTo(fallosA);

        final rachaFallosA = sa?.rachaFallos ?? 0;
        final rachaFallosB = sb?.rachaFallos ?? 0;
        if (rachaFallosA != rachaFallosB) {
          return rachaFallosB.compareTo(rachaFallosA);
        }

        final aciertosA = sa?.aciertosVisibles ?? 0;
        final aciertosB = sb?.aciertosVisibles ?? 0;
        if (aciertosA != aciertosB) return aciertosA.compareTo(aciertosB);

        final idxA = posicionOriginal[a] ?? 999999;
        final idxB = posicionOriginal[b] ?? 999999;
        return idxA.compareTo(idxB);
      });
    }

    final faltantes = objetivoCantidad - seleccion.length;
    final idsSeleccionados = candidatasIds.take(faltantes).toList();
    if (idsSeleccionados.isEmpty) {
      return seleccion;
    }

    var adicionales = await _servicioPreguntas.obtenerPreguntasPorIds(
      ids: idsSeleccionados,
      categoria: _categoriaUsuario,
      materia: materia,
    );
    if (adicionales.isEmpty && materia != null && materia.trim().isNotEmpty) {
      adicionales = await _servicioPreguntas.obtenerPreguntasPorIds(
        ids: idsSeleccionados,
        categoria: _categoriaUsuario,
      );
    }

    if (objetivosMateriaNorm.isNotEmpty) {
      final filtradas = adicionales.where(coincideMateria).toList();
      if (filtradas.isNotEmpty) {
        adicionales = filtradas;
      }
    }

    for (final p in adicionales) {
      if (seleccion.length >= objetivoCantidad) break;
      if (usados.add(p.id)) {
        seleccion.add(p);
      }
    }

    return seleccion;
  }

  Color _colorFromHex(String hex, {Color fallback = const Color(0xFFCBD5E1)}) {
    final raw = hex.trim().replaceAll('#', '');
    if (raw.length != 6 && raw.length != 8) return fallback;
    final value = int.tryParse(raw, radix: 16);
    if (value == null) return fallback;
    if (raw.length == 6) {
      return Color(0xFF000000 | value);
    }
    return Color(value);
  }

  IconData _iconByName(String iconName) {
    switch (iconName) {
      case 'calendar_month':
        return Icons.calendar_month_rounded;
      case 'school':
      case 'menu_book':
        return Icons.menu_book_rounded;
      case 'bolt':
        return Icons.bolt_rounded;
      case 'assignment_turned_in':
        return Icons.assignment_turned_in_rounded;
      case 'history':
        return Icons.history_rounded;
      case 'favorite':
        return Icons.favorite_rounded;
      case 'memory':
        return Icons.psychology_alt_rounded;
      case 'radar':
        return Icons.radar_rounded;
      case 'schedule':
        return Icons.schedule_rounded;
      case 'insights':
      default:
        return Icons.auto_awesome_rounded;
    }
  }

  Widget _buildHeroV2(TutorDashboardInicio dashboard) {
    final resumenCorto = _mensajeHeroCorto(dashboard);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5EC7A7), Color(0xFF0B5A45)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.psychology_alt, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'IA Tutor Personal',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Analisis tactico en tiempo real para tu ascenso.',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    resumenCorto,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
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

  String _mensajeHeroCorto(TutorDashboardInicio dashboard) {
    String raw = '';
    for (final card in dashboard.insights) {
      final id = card.id.toLowerCase();
      final titulo = card.titulo.toLowerCase();
      if (id.contains('mensaje') || titulo.contains('mensaje personal')) {
        raw = card.resumen.trim();
        break;
      }
    }
    if (raw.isEmpty) {
      raw =
          'Hoy toca avanzar con foco. Una sesion corta bien hecha vale mas que postergarlo.';
    }
    if (raw.length > 120) {
      return '${raw.substring(0, 117).trim()}...';
    }
    return raw;
  }

  double _doubleValue(dynamic value, [double fallback = 0.0]) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  String _normalizarTextoSimple(String value) {
    var text = value.toLowerCase().trim();
    const reemplazos = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
      'ÃƒÂ¡': 'a',
      'ÃƒÂ©': 'e',
      'ÃƒÂ­': 'i',
      'ÃƒÂ³': 'o',
      'ÃƒÂº': 'u',
      'ÃƒÂ¼': 'u',
      'ÃƒÂ±': 'n',
      'ÃƒÆ’Ã‚Â¡': 'a',
      'ÃƒÆ’Ã‚Â©': 'e',
      'ÃƒÆ’Ã‚Â­': 'i',
      'ÃƒÆ’Ã‚Â³': 'o',
      'ÃƒÆ’Ã‚Âº': 'u',
      'ÃƒÆ’Ã‚Â±': 'n',
    };
    reemplazos.forEach((k, v) {
      text = text.replaceAll(k, v);
    });
    text = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    return text.trim();
  }

  String _nombreMateriaDesdeMap(Map<String, dynamic> materia) {
    final raw = materia['materia'] ?? materia['nombre'];
    if (raw is Map) {
      return (raw['nombre'] ?? 'Materia').toString().trim();
    }
    return (raw ?? 'Materia').toString().trim();
  }

  String _nivelDesdePorcentaje(double porcentaje) {
    if (porcentaje < 40) return 'CRITICO';
    if (porcentaje < 60) return 'BASICO';
    if (porcentaje < 80) return 'INTERMEDIO';
    if (porcentaje < 90) return 'AVANZADO';
    return 'EXPERTO';
  }

  _SemaforoTema _clasificarSemaforo({
    required double porcentaje,
    required double tiempoRecomendadoMin,
    required bool sinRegistro,
  }) {
    if (sinRegistro || porcentaje <= 0 || porcentaje < 50) {
      return _SemaforoTema.rojo;
    }
    final esLenta = tiempoRecomendadoMin >= 35;
    if (porcentaje >= 80 && !esLenta) {
      return _SemaforoTema.verde;
    }
    return _SemaforoTema.ambar;
  }

  List<_MateriaSemaforoItem> _construirMapaSemaforoMaterias({
    required List<Map<String, dynamic>> materiasAnalisis,
    required List<Materia> materiasCatalogo,
  }) {
    final analisisByKey = <String, Map<String, dynamic>>{};
    for (final materia in materiasAnalisis) {
      final nombre = _nombreMateriaDesdeMap(materia);
      final key = _normalizarTextoSimple(nombre);
      if (key.isEmpty) continue;
      analisisByKey[key] = {...materia, 'materia': nombre};
    }

    final items = <_MateriaSemaforoItem>[];
    final keysAgregadas = <String>{};

    for (final materia in materiasCatalogo) {
      final nombre = materia.nombre.trim();
      final key = _normalizarTextoSimple(nombre);
      if (key.isEmpty || !keysAgregadas.add(key)) continue;
      final analisis = analisisByKey.remove(key);
      final porcentaje = _doubleValue(analisis?['porcentaje']);
      final tiempoRecomendado = _doubleValue(
        analisis?['tiempo_recomendado_minutos'],
      );
      final semaforo = _clasificarSemaforo(
        porcentaje: porcentaje,
        tiempoRecomendadoMin: tiempoRecomendado,
        sinRegistro: analisis == null,
      );
      final descripcion = switch (semaforo) {
        _SemaforoTema.verde =>
          'Dominio solido: ${porcentaje.toStringAsFixed(1)}%.',
        _SemaforoTema.ambar =>
          tiempoRecomendado >= 35
              ? 'Conoces este tema, pero tu ritmo aun es lento.'
              : 'Conoces el tema, pero aun hay dudas por consolidar.',
        _SemaforoTema.rojo =>
          (analisis == null || porcentaje <= 0)
              ? 'Punto ciego: aun no has empezado este tema.'
              : 'Punto ciego prioritario para hoy.',
      };

      items.add(
        _MateriaSemaforoItem(
          nombre: nombre,
          porcentaje: porcentaje,
          semaforo: semaforo,
          descripcion: descripcion,
          materia: {
            ...?analisis,
            'materia': nombre,
            'porcentaje': porcentaje,
            'nivel': (analisis?['nivel'] ?? _nivelDesdePorcentaje(porcentaje))
                .toString(),
          },
        ),
      );
    }

    for (final analisis in analisisByKey.values) {
      final nombre = _nombreMateriaDesdeMap(analisis);
      final key = _normalizarTextoSimple(nombre);
      if (key.isEmpty || !keysAgregadas.add(key)) continue;
      final porcentaje = _doubleValue(analisis['porcentaje']);
      final tiempoRecomendado = _doubleValue(
        analisis['tiempo_recomendado_minutos'],
      );
      final semaforo = _clasificarSemaforo(
        porcentaje: porcentaje,
        tiempoRecomendadoMin: tiempoRecomendado,
        sinRegistro: false,
      );
      final descripcion = switch (semaforo) {
        _SemaforoTema.verde =>
          'Dominio solido: ${porcentaje.toStringAsFixed(1)}%.',
        _SemaforoTema.ambar =>
          tiempoRecomendado >= 35
              ? 'Conoces este tema, pero tu ritmo aun es lento.'
              : 'Conoces el tema, pero aun hay dudas por consolidar.',
        _SemaforoTema.rojo => 'Punto ciego prioritario para hoy.',
      };

      items.add(
        _MateriaSemaforoItem(
          nombre: nombre,
          porcentaje: porcentaje,
          semaforo: semaforo,
          descripcion: descripcion,
          materia: {
            ...analisis,
            'materia': nombre,
            'porcentaje': porcentaje,
            'nivel': (analisis['nivel'] ?? _nivelDesdePorcentaje(porcentaje))
                .toString(),
          },
        ),
      );
    }

    int ordenSemaforo(_SemaforoTema s) {
      switch (s) {
        case _SemaforoTema.rojo:
          return 0;
        case _SemaforoTema.ambar:
          return 1;
        case _SemaforoTema.verde:
          return 2;
      }
    }

    items.sort((a, b) {
      final bySemaforo = ordenSemaforo(a.semaforo) - ordenSemaforo(b.semaforo);
      if (bySemaforo != 0) return bySemaforo;
      final byPorcentaje = a.porcentaje.compareTo(b.porcentaje);
      if (byPorcentaje != 0) return byPorcentaje;
      return a.nombre.compareTo(b.nombre);
    });

    return items;
  }

  String _construirResumenMapaTemas({
    required List<_MateriaSemaforoItem> items,
    required String resumenBase,
  }) {
    if (items.isEmpty) {
      return 'Aun no hay datos por materia. Los porcentajes mostrados representan tu porcentaje de dominio por materia.';
    }

    final totalVerde = items
        .where((e) => e.semaforo == _SemaforoTema.verde)
        .length;
    final totalAmbar = items
        .where((e) => e.semaforo == _SemaforoTema.ambar)
        .length;
    final totalRojo = items
        .where((e) => e.semaforo == _SemaforoTema.rojo)
        .length;

    final ordenadas = [...items]
      ..sort((a, b) => b.porcentaje.compareTo(a.porcentaje));
    final top = ordenadas.first;

    final topMsg = top.porcentaje > 0
        ? 'La materia ${top.nombre} es la que mas dominas (${top.porcentaje.toStringAsFixed(1)}%).'
        : 'Aun no tienes dominio registrado por materia.';

    final semaforoMsg =
        'Semaforo actual: Verde $totalVerde, Ambar $totalAmbar y Rojo $totalRojo.';
    const aclaracion =
        'Los porcentajes que se muestran son porcentaje de dominio por materia.';

    if (resumenBase.trim().isEmpty) {
      return '$topMsg $aclaracion $semaforoMsg';
    }

    return '$topMsg $aclaracion $semaforoMsg';
  }

  Future<void> _abrirMapaTemasSemaforo() async {
    final materiasAnalisis = _obtenerAnalisisMaterias();
    List<Materia> materiasCatalogo = const <Materia>[];
    try {
      materiasCatalogo = await _servicioPreguntas.obtenerMateriasPorCategoria(
        categoria: _categoriaUsuario,
      );
    } catch (_) {
      materiasCatalogo = const <Materia>[];
    }

    final items = _construirMapaSemaforoMaterias(
      materiasAnalisis: materiasAnalisis,
      materiasCatalogo: materiasCatalogo,
    );
    final resumenMapa = _construirResumenMapaTemas(
      items: items,
      resumenBase: (_analisisPerfil?['resumen_materias'] ?? '').toString(),
    );

    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _PantallaMapaTemasSemaforo(
          items: items,
          resumen: resumenMapa,
          onMateriaTap: (materia) async {
            await _abrirDetalleMateria(materia);
          },
        ),
      ),
    );
  }

  Future<void> _abrirCoachVelocidad() async {
    if (!mounted) return;
    final req = await Navigator.push<_CoachVelocidadPracticaRequest>(
      context,
      MaterialPageRoute(
        builder: (_) => _PantallaCoachVelocidad(
          userId: _userId,
          iaService: _iaService,
          onIniciarPractica: _iniciarPracticaDesdeCoach,
        ),
      ),
    );

    if (!mounted) return;
    if (req == null) return;

    await _iniciarPracticaDesdeCoach(req);
  }

  Future<void> _abrirPanelPrediccionOlvido(TutorInsightCard card) async {
    if (!mounted) return;
    final req = await Navigator.push<_CoachVelocidadPracticaRequest>(
      context,
      MaterialPageRoute(
        builder: (_) => _PantallaPrediccionOlvido(
          userId: _userId,
          iaService: _iaService,
          card: card,
          onIniciarPractica: _iniciarPracticaDesdeCoach,
        ),
      ),
    );

    if (!mounted || req == null) return;
    await _iniciarPracticaDesdeCoach(req);
  }

  Future<void> _iniciarPracticaDesdeCoach(
    _CoachVelocidadPracticaRequest req,
  ) async {
    await _iniciarPractica(
      cantidad: req.cantidad,
      tiempoLimite: req.tiempoMinutos,
      materia: req.materia,
      preguntaIdsPrioritarias: req.preguntaIdsPrioritarias,
      esPracticaGuiada: req.esPracticaGuiada,
      registrarSesionEnHistorial: req.registrarSesionEnHistorial,
      seleccionarAleatorio: req.seleccionarAleatorio,
      tiempoLimiteSegundosPersonalizado: req.tiempoLimiteSegundosPersonalizado,
    );
  }

  Future<void> _abrirPanelProyeccionTiempo(TutorInsightCard card) async {
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _PantallaProyeccionTiempo(
          userId: _userId,
          categoriaUsuario: _categoriaUsuario,
          iaService: _iaService,
          card: card,
        ),
      ),
    );
  }

  Future<void> _ejecutarInsightCard(TutorInsightCard card) async {
    final id = card.id.toLowerCase().trim();
    if (id == 'analisis_perfil') {
      await _abrirAnalisisCompletoPerfil();
      return;
    }

    if (id == 'radar_riesgo_materia' ||
        id == 'radar_riesgo_por_materia' ||
        id == 'radar_riesgo_por_materias' ||
        id == 'radar_materias' ||
        id == 'radar') {
      await _abrirMapaTemasSemaforo();
      return;
    }

    if (id == 'coach_velocidad') {
      await _abrirCoachVelocidad();
      return;
    }

    if (id == 'coach_memoria') {
      await _abrirPanelPrediccionOlvido(card);
      return;
    }

    if (id == 'prediccion_olvido') {
      // Compatibilidad con dashboards en cache antiguos.
      await _abrirPanelPrediccionOlvido(card);
      return;
    }

    if (id == 'proyeccion_tiempo') {
      await _abrirPanelProyeccionTiempo(card);
      return;
    }

    if (id == 'plan_hoy' ||
        id == 'ordenes_tutor_hoy' ||
        id == 'ordenes_tutor_para_hoy') {
      await _abrirOrdenesTutorParaHoy();
      return;
    }

    if (card.promptAccion.trim().isNotEmpty) {
      await _abrirChatTutor(
        promptInicial: card.promptAccion.trim(),
        enviarAutomatico: true,
      );
      return;
    }

    if (card.cantidadPractica != null && card.tiempoPractica != null) {
      await _iniciarPractica(
        cantidad: card.cantidadPractica!,
        tiempoLimite: card.tiempoPractica!,
        materia: card.materia,
      );
    }
  }

  Widget _buildInsightTileV2(TutorInsightCard card) {
    final color = _colorFromHex(card.colorHex);
    final ctaText = card.cta.trim().isEmpty ? 'Entrar' : card.cta.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _ejecutarInsightCard(card),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconByName(card.iconName), color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              card.titulo,
              maxLines: 4,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                card.resumen,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    ctaText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 13, color: color),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightsGridV2(TutorDashboardInicio dashboard) {
    final cards = dashboard.insights.where((card) {
      final id = card.id.toLowerCase().trim();
      return id != 'debrief_sesion' &&
          id != 'mensaje_personal' &&
          id != 'materia_prioritaria' &&
          id != 'prediccion_olvido';
    }).toList();
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FUNCIONES IA',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: cards.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.86,
          ),
          itemBuilder: (_, index) => _buildInsightTileV2(cards[index]),
        ),
      ],
    );
  }

  Widget _buildDashboardV2() {
    final dashboard = _dashboardInicio ?? TutorDashboardInicio.fallback();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroV2(dashboard),
          const SizedBox(height: 14),
          _buildInsightsGridV2(dashboard),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_accesoRestringidoInvitado) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: Text(
            'Tutor IA Personal',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF0B6B57),
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 44,
                  color: Color(0xFF0B5A45),
                ),
                const SizedBox(height: 12),
                Text(
                  'El Tutor IA Personal es solo para usuarios registrados.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Inicia sesion o registrate para activar recomendaciones personalizadas.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Volver'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final analisis = _analisisPerfil ?? _analisisPerfilInicial();
    final cardsIa = _obtenerCardsIA();
    final diagnostico = (analisis['diagnostico'] ?? '').toString();
    final resumenMaterias = (analisis['resumen_materias'] ?? '').toString();
    final materiasAnalisis = _obtenerAnalisisMaterias();
    final fortalezasAnalisis = [
      ...List<String>.from(analisis['fortalezas'] ?? []),
      if ((analisis['velocidad_promedio'] as num?) != null &&
          (analisis['velocidad_promedio'] as num) < 15)
        "Buena velocidad (${analisis['velocidad_promedio']} seg/preg)",
      if ((analisis['racha_dias'] as int? ?? 0) >= 3)
        "Racha de ${analisis['racha_dias']} dias",
    ];
    final debilidadesAnalisis = [
      ...List<String>.from(analisis['debilidades'] ?? []),
      if ((analisis['tasa_acierto'] as num? ?? 0) < 50)
        "Tendencia a impulsividad (Necesitas mas analisis)",
    ];

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'Tutor IA Personal',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF0B6B57),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Chat con Tutor IA Personal',
            onPressed: _abrirChatTutor,
          ),
          if (_actualizandoTutor)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _cargarDatos(forzarRecarga: true),
            ),
        ],
      ),
      body: _cargando
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    "Analizando tu perfil policial...",
                    style: GoogleFonts.inter(color: Colors.grey),
                  ),
                ],
              ),
            )
          : _tutorDashboardV2Enabled
          ? _buildDashboardV2()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Tarjeta de Diagnostico Principal (Nivel Global)
                  _SeccionNivelGlobal(
                    nivel: analisis['nivel_global'] ?? 'INICIAL',
                    tasaAcierto: analisis['tasa_acierto'] ?? 0,
                  ),

                  const SizedBox(height: 24),

                  _BloqueAnalisisTactico(
                    diagnostico: diagnostico,
                    resumenMaterias: resumenMaterias,
                    materiasAnalisis: materiasAnalisis,
                    fortalezas: fortalezasAnalisis,
                    debilidades: debilidadesAnalisis,
                    onMateriaTap: _abrirDetalleMateria,
                    onAbrirPanelMaterias: () {
                      _abrirPanelMaterias(
                        diagnostico: diagnostico,
                        resumenMaterias: resumenMaterias,
                        materiasAnalisis: materiasAnalisis,
                        fortalezas: fortalezasAnalisis,
                        debilidades: debilidadesAnalisis,
                      );
                    },
                  ),

                  const SizedBox(height: 30),

                  // 5. Ordenes del Tutor (Gemini controla estas tarjetas)
                  Text(
                    "ORDENES DEL TUTOR",
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (cardsIa.isEmpty)
                    _buildFallbackGrid()
                  else
                    Column(
                      children: cardsIa.map(_buildTarjetaAccionIA).toList(),
                    ),

                  const SizedBox(height: 50),
                ],
              ),
            ),
    );
  }
}

class _MensajeChatTutor {
  final String texto;
  final bool esUsuario;

  const _MensajeChatTutor({required this.texto, required this.esUsuario});
}

class _ChatTutorSheet extends StatefulWidget {
  final TutorIAPersonalService iaService;
  final Map<String, dynamic> contexto;
  final String? promptInicial;
  final bool enviarAutomatico;

  const _ChatTutorSheet({
    required this.iaService,
    required this.contexto,
    this.promptInicial,
    this.enviarAutomatico = false,
  });

  @override
  State<_ChatTutorSheet> createState() => _ChatTutorSheetState();
}

class _ChatTutorSheetState extends State<_ChatTutorSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_MensajeChatTutor> _mensajes = [];
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _mensajes.add(
      const _MensajeChatTutor(
        texto:
            'Soy Tutor IA Personal. Pideme plan diario, que estudiar hoy, analisis de sesion, velocidad, horario, patrones de error, coach de memoria o indice de memoria.',
        esUsuario: false,
      ),
    );
    if (widget.enviarAutomatico &&
        widget.promptInicial != null &&
        widget.promptInicial!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _enviarMensaje(widget.promptInicial);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _enviarMensaje([String? mensajeForzado]) async {
    final mensaje = (mensajeForzado ?? _controller.text).trim();
    if (mensaje.isEmpty || _enviando) return;

    if (mensajeForzado == null) {
      _controller.clear();
    }
    setState(() {
      _mensajes.add(_MensajeChatTutor(texto: mensaje, esUsuario: true));
      _enviando = true;
    });
    _scrollAlFinal();

    final contextoChat = <String, dynamic>{
      ...widget.contexto,
      'historial_chat': _historialParaIA(),
    };

    try {
      final respuesta = await widget.iaService.enviarMensajeTutor(
        mensaje: mensaje,
        contexto: contextoChat,
      );

      if (!mounted) return;
      setState(() {
        _mensajes.add(_MensajeChatTutor(texto: respuesta, esUsuario: false));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mensajes.add(
          const _MensajeChatTutor(
            texto: 'No pude responder en este momento. Intenta nuevamente.',
            esUsuario: false,
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _enviando = false;
        });
        _scrollAlFinal();
      }
    }
  }

  List<Map<String, String>> _historialParaIA() {
    if (_mensajes.isEmpty) return const [];
    final start = _mensajes.length > 10 ? _mensajes.length - 10 : 0;
    return _mensajes
        .sublist(start)
        .map(
          (m) => {'rol': m.esUsuario ? 'usuario' : 'tutor', 'texto': m.texto},
        )
        .toList();
  }

  Widget _burbuja(_MensajeChatTutor mensaje) {
    final esUsuario = mensaje.esUsuario;
    final bg = esUsuario ? const Color(0xFF0B5A45) : const Color(0xFFF1F5F9);
    final fg = esUsuario ? Colors.white : const Color(0xFF111827);
    final align = esUsuario ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(esUsuario ? 14 : 4),
      bottomRight: Radius.circular(esUsuario ? 4 : 14),
    );

    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 320),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: bg, borderRadius: radius),
          child: Text(
            mensaje.texto,
            style: GoogleFonts.inter(fontSize: 13, color: fg, height: 1.4),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.82;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          height: maxHeight,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Chat con Tutor IA Personal',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  itemCount: _mensajes.length + (_enviando ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_enviando && index == _mensajes.length) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              'Tutor escribiendo...',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFF445744),
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    final item = _mensajes[index];
                    return Align(
                      alignment: item.esUsuario
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: _burbuja(item),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _enviarMensaje(),
                        decoration: InputDecoration(
                          hintText: 'Escribe tu consulta...',
                          hintStyle: GoogleFonts.inter(fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFFECEFF3),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF0B5A45),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 46,
                      width: 46,
                      child: ElevatedButton(
                        onPressed: _enviando ? null : _enviarMensaje,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B5A45),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Icon(Icons.send_rounded, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeccionNivelGlobal extends StatelessWidget {
  final String nivel;
  final double tasaAcierto;

  const _SeccionNivelGlobal({required this.nivel, required this.tasaAcierto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF243223), // Azul pizarra oscuro policial
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Nivel Global: $nivel",
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Stack(
            children: [
              Container(
                height: 10,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              FractionallySizedBox(
                widthFactor: (tasaAcierto / 100).clamp(0.0, 1.0),
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        TemaAplicacion.colorSecundario,
                        TemaAplicacion.colorPrimario,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "${tasaAcierto.toStringAsFixed(0)}% Dominio Total",
            style: GoogleFonts.inter(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _BloqueAnalisisTactico extends StatelessWidget {
  final String diagnostico;
  final String resumenMaterias;
  final List<String> fortalezas;
  final List<String> debilidades;
  final List<Map<String, dynamic>> materiasAnalisis;
  final ValueChanged<Map<String, dynamic>> onMateriaTap;
  final VoidCallback onAbrirPanelMaterias;

  const _BloqueAnalisisTactico({
    required this.diagnostico,
    required this.resumenMaterias,
    required this.fortalezas,
    required this.debilidades,
    required this.materiasAnalisis,
    required this.onMateriaTap,
    required this.onAbrirPanelMaterias,
  });

  List<Map<String, dynamic>> _normalizarDesdeTexto(
    List<String> items,
    String tipo,
  ) {
    final regex = RegExp(r'^(.*)\(([\d.]+)%\)$');
    return items
        .map((raw) {
          final texto = raw.trim();
          final match = regex.firstMatch(texto);
          final nombre = match != null ? match.group(1)!.trim() : texto;
          final score = match != null
              ? double.tryParse(match.group(2) ?? '')
              : null;
          final porcentaje = score ?? (tipo == 'fortaleza' ? 75.0 : 45.0);
          return {
            'materia': nombre,
            'porcentaje': porcentaje,
            'nivel': _nivelDesdePorcentaje(porcentaje),
            'tipo': tipo,
          };
        })
        .where((e) => (e['materia'] as String).isNotEmpty)
        .toList();
  }

  String _nivelDesdePorcentaje(double value) {
    if (value < 40) return 'CRITICO';
    if (value < 60) return 'BASICO';
    if (value < 80) return 'INTERMEDIO';
    if (value < 90) return 'AVANZADO';
    return 'EXPERTO';
  }

  List<Map<String, dynamic>> _materiasPorTipo(String tipo) {
    if (materiasAnalisis.isNotEmpty) {
      return materiasAnalisis
          .where((m) => (m['tipo'] ?? '').toString() == tipo)
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return tipo == 'fortaleza'
        ? _normalizarDesdeTexto(fortalezas, 'fortaleza')
        : _normalizarDesdeTexto(debilidades, 'debilidad');
  }

  String _resumenMostrar() {
    if (resumenMaterias.trim().isNotEmpty) return resumenMaterias.trim();

    final fortalezasCount = _materiasPorTipo('fortaleza').length;
    final debilidadesCount = _materiasPorTipo('debilidad').length;
    final total = materiasAnalisis.isNotEmpty
        ? materiasAnalisis.length
        : (fortalezasCount + debilidadesCount);

    if (total == 0) {
      return 'Aun no hay datos por materia. Inicia practicas para generar analisis.';
    }

    return 'Tienes $fortalezasCount materias fuertes y $debilidadesCount materias en mejora. Pulsa Revisar para ver el detalle por materia.';
  }

  Widget _buildResumenAccionCard() {
    return InkWell(
      onTap: onAbrirPanelMaterias,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0B1220), Color(0xFF084434)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF084434)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF084434).withValues(alpha: 0.25),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_graph_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BRIEFING TACTICO IA',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        'Estado por materias',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white70),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _resumenMostrar(),
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.45,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: Row(
                children: [
                  Text(
                    'Entrar a revisar',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTarjetaMateria({
    required Map<String, dynamic> materia,
    required Color color,
  }) {
    final nombreRaw = materia['materia'] ?? materia['nombre'];
    final nombre = (nombreRaw is Map)
        ? (nombreRaw['nombre'] ?? 'Materia').toString()
        : (nombreRaw ?? 'Materia').toString();
    final porcentaje = (materia['porcentaje'] is num)
        ? (materia['porcentaje'] as num).toDouble()
        : double.tryParse(materia['porcentaje']?.toString() ?? '0') ?? 0.0;
    final nivel = (materia['nivel'] ?? _nivelDesdePorcentaje(porcentaje))
        .toString();

    return InkWell(
      onTap: () => onMateriaTap({
        ...materia,
        'materia': nombre,
        'porcentaje': porcentaje,
        'nivel': nivel,
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$nombre: $nivel',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Text(
                  '${porcentaje.toStringAsFixed(0)}%',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, size: 18, color: color),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (porcentaje / 100).clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: Colors.white,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildGrupo({
    required String titulo,
    required Color color,
    required IconData icono,
    required String tipo,
  }) {
    final data = _materiasPorTipo(tipo);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (data.isEmpty)
            Text(
              tipo == 'fortaleza'
                  ? 'Aun no tienes materias fuertes identificadas.'
                  : 'Aun no hay materias en mejora identificadas.',
              style: GoogleFonts.inter(
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            ...data.map((m) => _buildTarjetaMateria(materia: m, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'INTELIGENCIA TACTICA IA',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF111827), Color(0xFF084434)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF084434).withValues(alpha: 0.24),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Frase de Gemini',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                diagnostico.isEmpty
                    ? 'Sin diagnostico IA por ahora.'
                    : '"$diagnostico"',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildResumenAccionCard(),
      ],
    );
  }
}

class _PantallaAnalisisMaterias extends StatefulWidget {
  final String userId;
  final String categoriaUsuario;
  final TutorIAPersonalService iaService;
  final String diagnostico;
  final String resumenMaterias;
  final List<String> fortalezas;
  final List<String> debilidades;
  final List<Map<String, dynamic>> materiasAnalisis;
  final Map<String, dynamic> analisisBase;
  final ValueChanged<Map<String, dynamic>> onMateriaTap;

  const _PantallaAnalisisMaterias({
    required this.userId,
    required this.categoriaUsuario,
    required this.iaService,
    required this.diagnostico,
    required this.resumenMaterias,
    required this.fortalezas,
    required this.debilidades,
    required this.materiasAnalisis,
    required this.analisisBase,
    required this.onMateriaTap,
  });

  @override
  State<_PantallaAnalisisMaterias> createState() =>
      _PantallaAnalisisMateriasState();
}

class _PantallaAnalisisMateriasState extends State<_PantallaAnalisisMaterias> {
  final ServicioPreguntas _servicioPreguntas = ServicioPreguntas();
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _detalle = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _cargarDetalle();
  }

  Future<void> _cargarDetalle() async {
    try {
      final data = await widget.iaService
          .obtenerAnalisisCompletoPerfilDetallado(
            userId: widget.userId,
            categoriaUsuario: widget.categoriaUsuario,
            analisisBase: widget.analisisBase,
          );
      if (!mounted) return;
      setState(() {
        _detalle = data;
        _cargando = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _toMapList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  String _nivelPostulanteDesdePct(double porcentaje) {
    final pct = porcentaje.clamp(0.0, 100.0);
    if (pct <= 20.0) return 'Muy Bajo';
    if (pct <= 40.0) return 'Principiante';
    if (pct <= 60.0) return 'Intermedio';
    if (pct <= 80.0) return 'Avanzado';
    return 'Competitivo / Listo para examen';
  }

  String _construirMensajeMotivadorInteligente({
    required double tasaAciertoGlobal,
    required String nivelPostulante,
    required int totalEventos,
    required String respaldo,
  }) {
    if (totalEventos <= 0) {
      return respaldo.trim().isNotEmpty
          ? respaldo.trim()
          : 'Vas bien. Inicia una sesion corta para activar tu analisis personal.';
    }

    if (tasaAciertoGlobal >= 75) {
      return 'Excelente ritmo, $nivelPostulante. Mantiene la constancia y sigue asi.';
    }
    if (tasaAciertoGlobal >= 50) {
      return 'Buen avance, $nivelPostulante. Un poco mas de constancia y vas a despegar.';
    }
    if (tasaAciertoGlobal >= 30) {
      return 'Vas progresando, $nivelPostulante. Enfocate en calma y precision.';
    }
    return 'Estas en etapa de construccion, $nivelPostulante. Con practica diaria vas a mejorar.';
  }

  List<_CurvaPunto> _construirPuntosCurva(
    Map<String, dynamic> curva,
    List<Map<String, dynamic>> serieSemanal,
  ) {
    final intervaloDiasRaw = _toInt(curva['intervalo_dias']);
    final intervaloDias = intervaloDiasRaw > 0 ? intervaloDiasRaw : 5;
    final parsed = <_CurvaPunto>[];
    final raw = curva['puntos_curva'];
    if (raw is List) {
      for (final item in raw.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        var x = _toDouble(map['x_dias']);
        if (x <= 0 && map.containsKey('x_horas')) {
          x = _toDouble(map['x_horas']) / 24.0;
        }
        final y = _toDouble(map['y_nivel']);
        final muestra = _toInt(map['muestra_acumulada']);
        if (x.isFinite && y.isFinite && x >= 0) {
          parsed.add(
            _CurvaPunto(x: x, y: y.clamp(0.0, 100.0), muestra: muestra),
          );
        }
      }
    }
    parsed.sort((a, b) => a.x.compareTo(b.x));
    if (parsed.isNotEmpty && parsed.first.x > 0.001) {
      parsed.insert(0, const _CurvaPunto(x: 0.0, y: 0.0, muestra: 0));
    }
    if (parsed.length >= 2) return parsed;

    final fallback = <_CurvaPunto>[
      const _CurvaPunto(x: 0.0, y: 0.0, muestra: 0),
    ];
    var dias = 0.0;
    for (final punto in serieSemanal) {
      final muestra = _toInt(punto['muestra']);
      if (muestra <= 0) continue;
      dias += intervaloDias.toDouble();
      final pct = _toDouble(punto['porcentaje']).clamp(0.0, 100.0);
      final nivel = pct;
      fallback.add(_CurvaPunto(x: dias, y: nivel, muestra: muestra));
    }

    if (fallback.length >= 2) return fallback;
    return <_CurvaPunto>[
      _CurvaPunto(x: 0.0, y: 0.0, muestra: 0),
      _CurvaPunto(x: intervaloDias.toDouble(), y: 0.0, muestra: 0),
    ];
  }

  Widget _kpi({
    required String label,
    required String valor,
    required Color color,
    VoidCallback? onTap,
  }) {
    final content = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: content,
      ),
    );
  }

  Widget _kpiGrid({required List<Widget> items, double spacing = 8}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .map((item) => SizedBox(width: cardWidth, child: item))
              .toList(),
        );
      },
    );
  }

  String _formatearFechaCorta(dynamic value) {
    if (value == null) return '-';
    final raw = value.toString().trim();
    if (raw.isEmpty) return '-';
    final fecha = DateTime.tryParse(raw);
    if (fecha == null) return raw;
    final local = fecha.toLocal();
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${dos(local.day)}/${dos(local.month)} ${dos(local.hour)}:${dos(local.minute)}';
  }

  Future<void> _practicarDesdeDetalleDistribucion({
    required List<Map<String, dynamic>> rows,
  }) async {
    const maxPreguntasPractica = 20;
    final seleccionadas = <Map<String, dynamic>>[];
    final idsUnicos = <String>{};
    final ids = <String>[];
    for (final row in rows) {
      final id = (row['pregunta_id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      if (!idsUnicos.add(id)) continue;
      ids.add(id);
      seleccionadas.add(row);
      if (ids.length >= maxPreguntasPractica) break;
    }

    if (ids.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay preguntas validas para practicar.'),
        ),
      );
      return;
    }

    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return const Center(child: CircularProgressIndicator());
      },
    );

    List<Pregunta> preguntas = const <Pregunta>[];
    String? error;
    try {
      preguntas = await _servicioPreguntas.obtenerPreguntasPorIds(
        ids: ids,
        categoria: widget.categoriaUsuario,
      );
      if (preguntas.isEmpty) {
        preguntas = await _servicioPreguntas.obtenerPreguntasPorIds(ids: ids);
      }
    } catch (e) {
      error = 'Error al cargar preguntas para practicar: $e';
    } finally {
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }
    }

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (preguntas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay preguntas disponibles para practicar.'),
        ),
      );
      return;
    }

    var tiempoTotalSegundos = 0;
    for (final row in seleccionadas) {
      final tiempo = _toDouble(row['tiempo_total_respuesta']);
      if (tiempo.isFinite && tiempo > 0) {
        tiempoTotalSegundos += tiempo.ceil();
      }
    }
    final tiempoLimiteSegundos = tiempoTotalSegundos > 0
        ? tiempoTotalSegundos
        : null;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaPractica(
          preguntas: preguntas,
          esModoPractica: true,
          revisarRespuestaInmediata: false,
          registrarSesionEnHistorial: true,
          tiempoLimiteSegundos: tiempoLimiteSegundos,
        ),
      ),
    );

    if (!mounted) return;
    _cargarDetalle();
  }

  Future<void> _abrirDetalleDistribucion({
    required String tipo,
    required String titulo,
    required Color color,
    bool esTiempo = false,
  }) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.94,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: esTiempo
                    ? widget.iaService.obtenerDetalleDistribucionTiempo(
                        userId: widget.userId,
                        rango: tipo,
                      )
                    : widget.iaService.obtenerDetalleDistribucionRespuestas(
                        userId: widget.userId,
                        tipo: tipo,
                      ),
                builder: (context, snapshot) {
                  final cargando =
                      snapshot.connectionState == ConnectionState.waiting;
                  final rows = snapshot.data ?? const <Map<String, dynamic>>[];
                  final totalPracticar = rows
                      .map(
                        (row) => (row['pregunta_id'] ?? '').toString().trim(),
                      )
                      .where((id) => id.isNotEmpty)
                      .toSet()
                      .length;
                  final totalPracticarBoton = math.min(totalPracticar, 20);

                  return Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                titulo,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.28),
                                ),
                              ),
                              child: Text(
                                '${rows.length} registros',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      if (!cargando && rows.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: totalPracticar == 0
                                  ? null
                                  : () async {
                                      Navigator.of(context).pop();
                                      await _practicarDesdeDetalleDistribucion(
                                        rows: rows,
                                      );
                                    },
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 18,
                              ),
                              label: Text(
                                'Practicar ($totalPracticarBoton)',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: color,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (cargando)
                        const Expanded(
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (rows.isEmpty)
                        Expanded(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Text(
                                'No hay datos para este filtro en Supabase.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: const Color(0xFF6B7280),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.separated(
                            controller: scrollController,
                            itemCount: rows.length,
                            separatorBuilder: (_, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final row = rows[index];
                              final codigo = (row['codigo_pregunta'] ?? '')
                                  .toString()
                                  .trim();
                              final materia = (row['materia'] ?? 'Sin materia')
                                  .toString()
                                  .trim();
                              final enunciado = (row['enunciado'] ?? '')
                                  .toString()
                                  .trim();
                              final cambios = _toInt(
                                row['numero_cambios_respuesta'],
                              );
                              final tiempo = _toDouble(
                                row['tiempo_total_respuesta'],
                              );
                              final fecha = _formatearFechaCorta(
                                row['respondida_at'],
                              );

                              return ListTile(
                                dense: false,
                                title: Text(
                                  codigo.isEmpty ? 'Pregunta' : codigo,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${materia.isEmpty ? 'Sin materia' : materia}\n'
                                  '${enunciado.isEmpty ? '' : enunciado}\n'
                                  '$fecha  ·  ${tiempo.toStringAsFixed(1)}s  ·  cambios: $cambios',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    color: const Color(0xFF6B7280),
                                    height: 1.35,
                                  ),
                                ),
                                isThreeLine: true,
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _abrirPreguntasAcertadas() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PantallaPreguntasAcertadas()),
    );
    if (!mounted) return;
    _cargarDetalle();
  }

  Future<void> _abrirPreguntasNoAcertadas() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PantallaPreguntasIncorrectas()),
    );
    if (!mounted) return;
    _cargarDetalle();
  }

  Widget _filaNivelColor({required String texto, required Color color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.circle, size: 7.5, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccion({
    required String titulo,
    required IconData icono,
    required Color color,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        backgroundColor: const Color(0xFFECEFF3),
        appBar: AppBar(
          title: Text(
            'Analisis completo de perfil',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFECEFF3),
        appBar: AppBar(
          title: Text(
            'Analisis completo de perfil',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No se pudo cargar el analisis completo.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _cargarDetalle,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final tasaAciertoGlobal = _toDouble(_detalle['tasa_acierto_global']);
    final nivelPostulanteMap = _toMap(_detalle['nivel_postulante']);
    final nivelPostulante =
        (nivelPostulanteMap['nombre'] ?? '').toString().trim().isNotEmpty
        ? (nivelPostulanteMap['nombre'] ?? '').toString()
        : _nivelPostulanteDesdePct(tasaAciertoGlobal);
    final distResp = _toMap(_detalle['distribucion_respuestas']);
    final distTiempo = _toMap(_detalle['distribucion_tiempos']);
    final curva = _toMap(_detalle['curva_aprendizaje']);
    final presion = _toMap(_detalle['precision_bajo_presion']);
    final sobreconfianza = _toMap(_detalle['sobreconfianza']);
    final totalEventos = _toInt(distResp['total_eventos']);
    final correctasTotal = _toInt(distResp['correctas_total']);
    final incorrectasTotal = _toInt(distResp['incorrectas_total']);
    final omitidasTotal = _toInt(distResp['omitidas_total']);
    final pctErrorSub20 = _toDouble(sobreconfianza['errores_sub20s_pct']);
    final serieSemanal = _toMapList(curva['serie_semanal']);
    final estadoDetalle = (_detalle['estado'] ?? '').toString().trim();
    final intervaloDias = (() {
      final raw = _toInt(curva['intervalo_dias']);
      return raw > 0 ? raw : 5;
    })();
    final puntosCurva = _construirPuntosCurva(curva, serieSemanal);
    final mensajeRespaldo =
        (_detalle['mensaje'] ?? '').toString().trim().isNotEmpty
        ? (_detalle['mensaje'] ?? '').toString().trim()
        : (estadoDetalle == 'ok'
              ? 'Analisis calculado con tus datos reales de Supabase.'
              : 'Aun no hay datos suficientes en Supabase para este analisis.');
    final mensajeMotivador = _construirMensajeMotivadorInteligente(
      tasaAciertoGlobal: tasaAciertoGlobal,
      nivelPostulante: nivelPostulante,
      totalEventos: totalEventos,
      respaldo: mensajeRespaldo,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFECEFF3),
      appBar: AppBar(
        title: Text(
          'Analisis completo de perfil',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF0B6B57),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0B6B57),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF0B6B57)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          mensajeMotivador,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            height: 1.45,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          'Acierto global ${tasaAciertoGlobal.toStringAsFixed(1)}%',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          'Eventos analizados $totalEventos',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          'Nivel: $nivelPostulante',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _seccion(
              titulo: '1. Distribucion de respuestas',
              icono: Icons.pie_chart_outline_rounded,
              color: const Color(0xFF0B5A45),
              child: _kpiGrid(
                items: [
                  _kpi(
                    label: 'Correctas',
                    valor: '$correctasTotal',
                    color: const Color(0xFF0B5A45),
                    onTap: _abrirPreguntasAcertadas,
                  ),
                  _kpi(
                    label: 'Incorrectas',
                    valor: '$incorrectasTotal',
                    color: const Color(0xFFB91C1C),
                    onTap: _abrirPreguntasNoAcertadas,
                  ),
                  _kpi(
                    label: 'Omitidas',
                    valor: '$omitidasTotal',
                    color: const Color(0xFF92400E),
                    onTap: () => _abrirDetalleDistribucion(
                      tipo: 'omitidas',
                      titulo: 'Detalle de respuestas omitidas',
                      color: const Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
            ),
            _seccion(
              titulo: '2. Curva de aprendizaje',
              icono: Icons.trending_up_rounded,
              color: const Color(0xFF166534),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nivel del postulante: $nivelPostulante.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _filaNivelColor(
                    texto: 'Nivel Muy Bajo',
                    color: const Color(0xFFF31225),
                  ),
                  _filaNivelColor(
                    texto: 'Nivel Principiante',
                    color: const Color(0xFFF56A22),
                  ),
                  _filaNivelColor(
                    texto: 'Nivel Intermedio',
                    color: const Color(0xFFF4D40A),
                  ),
                  _filaNivelColor(
                    texto: 'Nivel Avanzado',
                    color: const Color(0xFF8CC63E),
                  ),
                  _filaNivelColor(
                    texto: 'Nivel Competitivo / Listo para examen',
                    color: const Color(0xFF0B9A43),
                  ),
                  const SizedBox(height: 10),
                  _GraficoCurvaAprendizaje(
                    puntos: puntosCurva,
                    intervaloDias: intervaloDias,
                    color: const Color(0xFF0F766E),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Puntos usados: ${puntosCurva.length} (cada punto = $intervaloDias dias, muestra base: ${_toInt(distResp['total_no_omitidas'])} respuestas).',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            _seccion(
              titulo: '3. Distribucion de tiempo de respuesta',
              icono: Icons.timer_outlined,
              color: const Color(0xFF0F766E),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kpiGrid(
                    items: [
                      _kpi(
                        label: '< 30 s',
                        valor:
                            '${_toDouble(distTiempo['lt_30_pct']).toStringAsFixed(1)}%',
                        color: const Color(0xFF0F766E),
                        onTap: () => _abrirDetalleDistribucion(
                          tipo: 'lt_30',
                          titulo: 'Detalle de respuestas < 30 s',
                          color: const Color(0xFF0F766E),
                          esTiempo: true,
                        ),
                      ),
                      _kpi(
                        label: '30-60 s',
                        valor:
                            '${_toDouble(distTiempo['s30_60_pct']).toStringAsFixed(1)}%',
                        color: const Color(0xFF1D4ED8),
                        onTap: () => _abrirDetalleDistribucion(
                          tipo: 's30_60',
                          titulo: 'Detalle de respuestas 30-60 s',
                          color: const Color(0xFF1D4ED8),
                          esTiempo: true,
                        ),
                      ),
                      _kpi(
                        label: '60-90 s',
                        valor:
                            '${_toDouble(distTiempo['s60_90_pct']).toStringAsFixed(1)}%',
                        color: const Color(0xFFB45309),
                        onTap: () => _abrirDetalleDistribucion(
                          tipo: 's60_90',
                          titulo: 'Detalle de respuestas 60-90 s',
                          color: const Color(0xFFB45309),
                          esTiempo: true,
                        ),
                      ),
                      _kpi(
                        label: '> 90 s',
                        valor:
                            '${_toDouble(distTiempo['gt_90_pct']).toStringAsFixed(1)}%',
                        color: const Color(0xFFB91C1C),
                        onTap: () => _abrirDetalleDistribucion(
                          tipo: 'gt_90',
                          titulo: 'Detalle de respuestas > 90 s',
                          color: const Color(0xFFB91C1C),
                          esTiempo: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Muestra de tiempo: ${_toInt(distTiempo['muestra'])} respuestas.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            _seccion(
              titulo: '4. Precision bajo presion',
              icono: Icons.speed_rounded,
              color: const Color(0xFF065F46),
              child: _kpiGrid(
                items: [
                  _kpi(
                    label: 'Practica libre',
                    valor:
                        '${_toDouble(presion['practica_libre_pct']).toStringAsFixed(1)}%',
                    color: const Color(0xFF065F46),
                  ),
                  _kpi(
                    label: 'Simulacro',
                    valor:
                        '${_toDouble(presion['simulacro_cronometrado_pct']).toStringAsFixed(1)}%',
                    color: const Color(0xFFB45309),
                  ),
                ],
              ),
            ),
            _seccion(
              titulo: '5. Deteccion de sobreconfianza',
              icono: Icons.psychology_alt_rounded,
              color: const Color(0xFF7E22CE),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Patron detectado: cuando respondes en menos de 20 segundos, fallas el ${pctErrorSub20.toStringAsFixed(1)}% de las preguntas.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Recomendacion: baja ligeramente la velocidad en preguntas clave y verifica opciones antes de confirmar.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurvaPunto {
  final double x;
  final double y;
  final int muestra;

  const _CurvaPunto({required this.x, required this.y, required this.muestra});
}

class _GraficoCurvaAprendizaje extends StatefulWidget {
  final List<_CurvaPunto> puntos;
  final int intervaloDias;
  final Color color;

  const _GraficoCurvaAprendizaje({
    required this.puntos,
    required this.intervaloDias,
    required this.color,
  });

  @override
  State<_GraficoCurvaAprendizaje> createState() =>
      _GraficoCurvaAprendizajeState();
}

class _GraficoCurvaAprendizajeState extends State<_GraficoCurvaAprendizaje> {
  final ScrollController _scrollController = ScrollController();
  String _lastAutoScrollKey = '';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Color _colorNivelPorPorcentaje(double pct) {
    if (pct <= 20) return const Color(0xFFF31225); // Muy Bajo
    if (pct <= 40) return const Color(0xFFF56A22); // Principiante
    if (pct <= 60) return const Color(0xFFF4D40A); // Intermedio
    if (pct <= 80) return const Color(0xFF8CC63E); // Avanzado
    return const Color(0xFF0B9A43); // Competitivo
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.puntos.length >= 2
        ? List<_CurvaPunto>.from(widget.puntos)
        : const <_CurvaPunto>[
            _CurvaPunto(x: 0.0, y: 0.0, muestra: 0),
            _CurvaPunto(x: 1.0, y: 0.0, muestra: 0),
          ];
    data.sort((a, b) => a.x.compareTo(b.x));
    final ultimo = data.last;
    final colorFinal = _colorNivelPorPorcentaje(ultimo.y);
    final intervalo = widget.intervaloDias > 0 ? widget.intervaloDias : 5;
    final maxXVisual = (() {
      var maxValue = 0.0;
      for (final punto in data) {
        if (punto.x > maxValue) maxValue = punto.x;
      }
      if (maxValue < 20.0) maxValue = 20.0; // Vista base del eje X: 0..20.
      final bloques = (maxValue / intervalo).ceil().clamp(1, 240);
      return (bloques * intervalo).toDouble();
    })();

    void programarAutoScroll({
      required double anchoViewport,
      required double anchoGrafico,
    }) {
      final key =
          '${maxXVisual.toStringAsFixed(2)}|${ultimo.x.toStringAsFixed(2)}|'
          '${anchoViewport.toStringAsFixed(1)}|${anchoGrafico.toStringAsFixed(1)}';
      if (_lastAutoScrollKey == key) return;
      _lastAutoScrollKey = key;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (maxScroll <= 0) return;

        const left = 42.0;
        const right = 14.0;
        final plotWidth = math.max(0.0, anchoGrafico - left - right);
        final ratio = maxXVisual > 0
            ? (ultimo.x / maxXVisual).clamp(0.0, 1.0)
            : 0.0;
        final puntoX = left + (ratio * plotWidth);
        final target = (puntoX - (anchoViewport * 0.70)).clamp(0.0, maxScroll);

        if ((_scrollController.offset - target).abs() > 1.0) {
          _scrollController.jumpTo(target);
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Nivel alcanzado',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF374151),
              ),
            ),
            const Spacer(),
            Text(
              'Final ${ultimo.y.toStringAsFixed(1)}%',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: colorFinal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 220,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final anchoDisponible = constraints.maxWidth;
              final bloques = (maxXVisual / intervalo).ceil().clamp(1, 240);
              final anchoObjetivo = 80.0 + (bloques * 34.0);
              final anchoGrafico = anchoObjetivo > anchoDisponible
                  ? anchoObjetivo
                  : anchoDisponible;

              programarAutoScroll(
                anchoViewport: anchoDisponible,
                anchoGrafico: anchoGrafico,
              );

              return SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: anchoGrafico,
                  height: 220,
                  child: CustomPaint(
                    painter: _CurvaAprendizajePainter(
                      puntos: data,
                      color: widget.color,
                      intervaloDias: widget.intervaloDias,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Tiempo de estudio (dias) - bloques de $intervalo dias - total ${ultimo.x.toStringAsFixed(0)} dias',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: const Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _CurvaAprendizajePainter extends CustomPainter {
  final List<_CurvaPunto> puntos;
  final Color color;
  final int intervaloDias;

  const _CurvaAprendizajePainter({
    required this.puntos,
    required this.color,
    required this.intervaloDias,
  });

  double _maxXValue(List<_CurvaPunto> data) {
    var maxValue = 0.0;
    for (final punto in data) {
      if (punto.x > maxValue) maxValue = punto.x;
    }
    final intervalo = intervaloDias > 0 ? intervaloDias.toDouble() : 5.0;
    if (maxValue <= 0) maxValue = intervalo;
    if (maxValue < 20.0) maxValue = 20.0; // Vista base del eje X: 0..20.
    final bloques = (maxValue / intervalo).ceil().clamp(1, 240);
    return (bloques * intervalo).toDouble();
  }

  double _maxYValue(List<_CurvaPunto> data) {
    var maxValue = 0.0;
    for (final punto in data) {
      if (punto.y > maxValue) maxValue = punto.y;
    }
    if (maxValue < 100.0) maxValue = 100.0;
    final escalado = (maxValue / 10.0).ceil() * 10.0;
    return escalado.toDouble();
  }

  String _formatX(double value) {
    return value.toStringAsFixed(0);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    required Color color,
    double fontSize = 10,
    FontWeight fontWeight = FontWeight.w600,
    TextAlign align = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: GoogleFonts.inter(
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final data = List<_CurvaPunto>.from(puntos)
      ..sort((a, b) => a.x.compareTo(b.x));
    if (data.length < 2) return;

    const left = 42.0;
    const right = 14.0;
    const top = 12.0;
    const bottom = 28.0;
    final plot = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );
    if (plot.width <= 4 || plot.height <= 4) return;

    final maxX = _maxXValue(data);
    final maxY = _maxYValue(data);

    double yByPctRange(double pct) {
      final clamped = pct.clamp(0.0, maxY);
      return plot.bottom - ((clamped / maxY) * plot.height);
    }

    void drawNivelFranja({
      required double desdePct,
      required double hastaPct,
      required Color colorFondo,
    }) {
      final topY = yByPctRange(hastaPct);
      final bottomY = yByPctRange(desdePct);
      final rect = Rect.fromLTRB(plot.left, topY, plot.right, bottomY);
      canvas.drawRect(
        rect,
        Paint()..color = colorFondo.withValues(alpha: 0.16),
      );
    }

    // Fondo tenue del cuadro de estadistica por rangos de nivel.
    drawNivelFranja(
      desdePct: 81,
      hastaPct: 100,
      colorFondo: const Color(0xFF0B9A43), // verde fuerte
    );
    drawNivelFranja(
      desdePct: 61,
      hastaPct: 80,
      colorFondo: const Color(0xFF8CC63E), // verde claro
    );
    drawNivelFranja(
      desdePct: 41,
      hastaPct: 60,
      colorFondo: const Color(0xFFF4D40A), // amarillo
    );
    drawNivelFranja(
      desdePct: 21,
      hastaPct: 40,
      colorFondo: const Color(0xFFF56A22), // naranja
    );
    drawNivelFranja(
      desdePct: 0,
      hastaPct: 20,
      colorFondo: const Color(0xFFF31225), // rojo
    );

    final gridPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1;
    final intervalo = intervaloDias > 0 ? intervaloDias : 5;
    final xTicks = (maxX / intervalo).round().clamp(1, 240);
    final xLabelStep = (xTicks / 6).ceil().clamp(1, 240);
    const yTicks = 5;

    for (var i = 0; i <= xTicks; i++) {
      final x = plot.left + ((plot.width * i) / xTicks);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      final mostrarLabel = i == 0 || i == xTicks || (i % xLabelStep == 0);
      if (mostrarLabel) {
        final xValue = i * intervalo;
        final label = _formatX(xValue.toDouble());
        final labelPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: const Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        labelPainter.paint(
          canvas,
          Offset(x - (labelPainter.width / 2), plot.bottom + 6),
        );
      }
    }

    for (var i = 0; i <= yTicks; i++) {
      final y = plot.bottom - ((plot.height * i) / yTicks);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }

    double yByPct(double pct) {
      final clamped = pct.clamp(0.0, maxY);
      return plot.bottom - ((clamped / maxY) * plot.height);
    }

    void drawNivelPunto(double pct, Color colorDot) {
      canvas.drawCircle(
        Offset(plot.left - 13, yByPct(pct)),
        4.0,
        Paint()..color = colorDot,
      );
    }

    // Referencia visual de 5 niveles en curva de aprendizaje.
    drawNivelPunto(10.5, const Color(0xFFF31225)); // Muy Bajo (1-20)
    drawNivelPunto(30.5, const Color(0xFFF56A22)); // Principiante (21-40)
    drawNivelPunto(50.5, const Color(0xFFF4D40A)); // Intermedio (41-60)
    drawNivelPunto(70.5, const Color(0xFF8CC63E)); // Avanzado (61-80)
    drawNivelPunto(90.5, const Color(0xFF0B9A43)); // Competitivo (81-100)

    final axisPaint = Paint()
      ..color = const Color(0xFF9CA3AF)
      ..strokeWidth = 1.4;
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.left, plot.top),
      axisPaint,
    );

    Offset mapPoint(_CurvaPunto punto) {
      final xNorm = maxX > 0 ? (punto.x / maxX) : 0.0;
      final yNorm = maxY > 0 ? (punto.y / maxY) : 0.0;
      final x = plot.left + (xNorm.clamp(0.0, 1.0) * plot.width);
      final y = plot.bottom - (yNorm.clamp(0.0, 1.0) * plot.height);
      return Offset(x, y);
    }

    final linePath = Path();
    final first = mapPoint(data.first);
    linePath.moveTo(first.dx, first.dy);
    for (var i = 1; i < data.length; i++) {
      final p = mapPoint(data[i]);
      linePath.lineTo(p.dx, p.dy);
    }

    final areaPath = Path.from(linePath)
      ..lineTo(mapPoint(data.last).dx, plot.bottom)
      ..lineTo(first.dx, plot.bottom)
      ..close();
    canvas.drawPath(areaPath, Paint()..color = color.withValues(alpha: 0.10));

    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final puntoPaint = Paint()..color = color;
    final bordePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (final punto in data) {
      final p = mapPoint(punto);
      canvas.drawCircle(p, 3.8, puntoPaint);
      canvas.drawCircle(p, 3.8, bordePaint);
    }

    _drawText(
      canvas,
      'NIVEL',
      Offset(plot.left - 38, plot.top - 2),
      color: const Color(0xFF4B5563),
      fontSize: 10,
      fontWeight: FontWeight.w700,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvaAprendizajePainter oldDelegate) {
    if (oldDelegate.color != color) return true;
    if (oldDelegate.intervaloDias != intervaloDias) return true;
    if (oldDelegate.puntos.length != puntos.length) return true;
    for (var i = 0; i < puntos.length; i++) {
      final a = puntos[i];
      final b = oldDelegate.puntos[i];
      if (a.x != b.x || a.y != b.y || a.muestra != b.muestra) return true;
    }
    return false;
  }
}

enum _SemaforoTema { verde, ambar, rojo }

class _DetalleMateriaSheet extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> materia;
  final String categoriaUsuario;
  final List<String> debilidadesGlobales;
  final TutorIAPersonalService iaService;
  final ServicioPreguntas servicioPreguntas;
  final Future<void> Function(
    int cantidad,
    int tiempoMinutos,
    String materia,
    List<String> preguntaIdsPrioritarias, {
    bool esPracticaGuiada,
  })
  onPracticar;

  const _DetalleMateriaSheet({
    required this.userId,
    required this.materia,
    required this.categoriaUsuario,
    required this.debilidadesGlobales,
    required this.iaService,
    required this.servicioPreguntas,
    required this.onPracticar,
  });

  @override
  State<_DetalleMateriaSheet> createState() => _DetalleMateriaSheetState();
}

class _DetalleMateriaSheetState extends State<_DetalleMateriaSheet> {
  bool _cargando = true;
  Map<String, dynamic> _recomendacion = const {};
  Map<String, dynamic> _detalleMateria = const {};
  List<Map<String, dynamic>> _preguntasCriticas = const [];

  String get _materia =>
      (widget.materia['materia'] ?? widget.materia['nombre'] ?? 'Materia')
          .toString();

  double get _porcentaje {
    final raw = widget.materia['porcentaje'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '0') ?? 0.0;
  }

  String get _nivel =>
      (widget.materia['nivel'] ?? 'INTERMEDIO').toString().toUpperCase();

  @override
  void initState() {
    super.initState();
    _cargarDetalle();
  }

  Future<void> _cargarDetalle() async {
    try {
      final recFuture = widget.iaService.recomendarPorMateria(
        materia: _materia,
        porcentaje: _porcentaje,
        nivel: _nivel,
        debilidadesGlobales: widget.debilidadesGlobales,
      );
      final detalleFuture = widget.iaService.obtenerDetalleMateria(
        userId: widget.userId,
        materia: _materia,
        porcentajeActual: _porcentaje,
        nivelActual: _nivel,
      );
      final criticasFuture = widget.iaService.obtenerPreguntasQueBajanMateria(
        userId: widget.userId,
        materia: _materia,
        limit: 10,
      );

      final rec = await recFuture;
      final detalle = await detalleFuture;
      final criticas = await criticasFuture;
      var criticasFinales = criticas;
      if (criticasFinales.isEmpty) {
        final fallidas = (detalle['fallidas'] is Map)
            ? Map<String, dynamic>.from(detalle['fallidas'])
            : <String, dynamic>{};
        final preguntasEstado = (detalle['preguntas_por_estado'] is Map)
            ? Map<String, dynamic>.from(detalle['preguntas_por_estado'])
            : <String, dynamic>{};
        final idsFallidas = (fallidas['ids'] is List)
            ? (fallidas['ids'] as List)
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList()
            : <String>[];
        final idsIncorrectas = (preguntasEstado['incorrectas_ids'] is List)
            ? (preguntasEstado['incorrectas_ids'] as List)
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList()
            : <String>[];
        final idsFallback = <String>{
          ...idsFallidas,
          ...idsIncorrectas,
        }.take(10).toList();
        if (idsFallback.isNotEmpty) {
          var preguntasFallback = await widget.servicioPreguntas
              .obtenerPreguntasPorIds(
                ids: idsFallback,
                categoria: widget.categoriaUsuario,
                materia: _materia,
              );
          if (preguntasFallback.isEmpty) {
            preguntasFallback = await widget.servicioPreguntas
                .obtenerPreguntasPorIds(ids: idsFallback);
          }
          if (preguntasFallback.isNotEmpty) {
            criticasFinales = preguntasFallback
                .map(
                  (p) => <String, dynamic>{
                    'pregunta_id': p.id,
                    'numero': p.numero,
                    'texto': p.texto,
                    'fallos': null,
                    'intentos': null,
                    'tasa_error': null,
                  },
                )
                .toList();
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _recomendacion = rec;
        _detalleMateria = detalle;
        _preguntasCriticas = criticasFinales;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo cargar el detalle de la materia.'),
        ),
      );
    }
  }

  int _intValue(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  double _doubleValue(dynamic value, double fallback) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111827),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat({
    required String label,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    final tarjeta = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(height: 4),
            Text(
              'Ver',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return Expanded(child: tarjeta);
    }

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: tarjeta,
      ),
    );
  }

  List<String> _toIdList(dynamic value) {
    if (value is! List) return <String>[];
    final ids = <String>[];
    final vistos = <String>{};
    for (final raw in value) {
      final id = raw.toString().trim();
      if (id.isEmpty) continue;
      if (vistos.add(id)) {
        ids.add(id);
      }
    }
    return ids;
  }

  Future<void> _abrirListadoPreguntasEstado({
    required String titulo,
    required List<String> ids,
    required Color color,
  }) async {
    final idsLimpios = _toIdList(ids);
    if (idsLimpios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay preguntas disponibles en este grupo.'),
        ),
      );
      return;
    }

    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return const Center(child: CircularProgressIndicator());
      },
    );

    List<Pregunta> preguntas = const [];
    String? error;
    try {
      preguntas = await widget.servicioPreguntas.obtenerPreguntasPorIds(
        ids: idsLimpios,
        categoria: widget.categoriaUsuario,
        materia: _materia,
      );
      if (preguntas.isEmpty) {
        preguntas = await widget.servicioPreguntas.obtenerPreguntasPorIds(
          ids: idsLimpios,
        );
      }
    } catch (e) {
      error = 'No se pudieron cargar las preguntas: $e';
    } finally {
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }
    }

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (preguntas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontraron preguntas para este grupo.'),
        ),
      );
      return;
    }

    final idsPractica = preguntas.map((p) => p.id).toList();
    final cantidadPractica = idsPractica.length;
    final tiempoPractica = _intValue(_recomendacion['tiempo_minutos'], 20);
    final textoBoton = 'Practicar ${idsPractica.length} preguntas';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFECEFF3),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            titulo,
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF111827),
                            ),
                          ),
                        ),
                        Text(
                          '${preguntas.length}',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: preguntas.length,
                      itemBuilder: (_, index) {
                        final p = preguntas[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(
                            '#${p.numero} ${p.texto}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: const Color(0xFF1F2937),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final onPracticar = widget.onPracticar;
                          final materiaActual = _materia;
                          Navigator.of(sheetContext).pop();
                          await onPracticar(
                            cantidadPractica,
                            tiempoPractica,
                            materiaActual,
                            idsPractica,
                            esPracticaGuiada: true,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B5A45),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          textoBoton,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = (_detalleMateria['info_basica'] is Map)
        ? Map<String, dynamic>.from(_detalleMateria['info_basica'])
        : <String, dynamic>{};
    final progreso = (_detalleMateria['progreso_usuario'] is Map)
        ? Map<String, dynamic>.from(_detalleMateria['progreso_usuario'])
        : <String, dynamic>{};
    final pred = (_detalleMateria['prediccion'] is Map)
        ? Map<String, dynamic>.from(_detalleMateria['prediccion'])
        : <String, dynamic>{};
    final preguntasPorEstado = (_detalleMateria['preguntas_por_estado'] is Map)
        ? Map<String, dynamic>.from(_detalleMateria['preguntas_por_estado'])
        : <String, dynamic>{};
    final tiempo = (_recomendacion['tiempo_minutos'] is num)
        ? (_recomendacion['tiempo_minutos'] as num).toInt()
        : 20;

    final totalPreguntas = _intValue(info['total_preguntas'], 0);

    final correctas = _intValue(progreso['correctas'], 0);
    final incorrectas = _intValue(progreso['incorrectas'], 0);
    final noRespondidas = _intValue(progreso['no_respondidas'], 0);
    final porcentajeAvance = _doubleValue(progreso['porcentaje_avance'], 0);
    final preguntasVistas = _intValue(progreso['preguntas_vistas'], 0);

    final probActual = _doubleValue(pred['probabilidad_actual'], _porcentaje);
    final prob7 = _doubleValue(pred['proyeccion_7_dias'], _porcentaje);
    final prob30 = _doubleValue(pred['proyeccion_30_dias'], _porcentaje);
    final idsCorrectas = _toIdList(preguntasPorEstado['correctas_ids']);
    var idsIncorrectas = _toIdList(preguntasPorEstado['incorrectas_ids']);
    final idsNoRespondidas = _toIdList(
      preguntasPorEstado['no_respondidas_ids'],
    );
    if (idsIncorrectas.isEmpty && _preguntasCriticas.isNotEmpty) {
      idsIncorrectas = _preguntasCriticas
          .map((q) => (q['pregunta_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toList();
    }
    final preguntasCriticasTop = _preguntasCriticas.take(10).toList();
    final idsPrioritariasDetalle = <String>{
      ...preguntasCriticasTop
          .map((q) => (q['pregunta_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty),
    }.toList();
    final cantidadPracticarCriticas = idsPrioritariasDetalle.length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: const BoxDecoration(
        color: Color(0xFFECEFF3),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      children: [
                        Text(
                          _materia,
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'PROBABILIDAD DE APROBAR ESTA MATERIA',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF084434),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${probActual.toStringAsFixed(0)}%',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF111827),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: (porcentajeAvance / 100).clamp(0.0, 1.0),
                            minHeight: 9,
                            backgroundColor: Colors.white,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF0B5A45),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionTitle(
                          '1) Progreso del usuario',
                          Icons.assessment_rounded,
                          const Color(0xFF237D57),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _buildMiniStat(
                              label: 'Correctas',
                              value: '$correctas',
                              color: const Color(0xFF237D57),
                              onTap: () => _abrirListadoPreguntasEstado(
                                titulo: 'Preguntas correctas',
                                ids: idsCorrectas,
                                color: const Color(0xFF237D57),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildMiniStat(
                              label: 'Incorrectas',
                              value: '$incorrectas',
                              color: const Color(0xFFAD3636),
                              onTap: () => _abrirListadoPreguntasEstado(
                                titulo: 'Preguntas incorrectas',
                                ids: idsIncorrectas,
                                color: const Color(0xFFAD3636),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildMiniStat(
                              label: 'No respondidas',
                              value: '$noRespondidas',
                              color: const Color(0xFF8B661E),
                              onTap: () => _abrirListadoPreguntasEstado(
                                titulo: 'Preguntas no respondidas',
                                ids: idsNoRespondidas,
                                color: const Color(0xFF8B661E),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Preguntas vistas: $preguntasVistas de $totalPreguntas',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionTitle(
                          '2) Prediccion',
                          Icons.auto_awesome_rounded,
                          const Color(0xFF084434),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF6F1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF5EC7A7)),
                          ),
                          child: Text(
                            'Tu esfuerzo da frutos. Aunque hoy tu probabilidad es del ${probActual.toStringAsFixed(0)}%, si cumples con tus tareas diarias, en solo una semana habras subido al ${prob7.toStringAsFixed(0)}%. Sigue asi para llegar al ${prob30.toStringAsFixed(0)}% en un mes.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              height: 1.45,
                              color: const Color(0xFF084434),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionTitle(
                          '3) Preguntas que bajan tu porcentaje',
                          Icons.warning_amber_rounded,
                          const Color(0xFF8B661E),
                        ),
                        const SizedBox(height: 10),
                        if (preguntasCriticasTop.isNotEmpty)
                          ...preguntasCriticasTop.map(
                            (q) => Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFFDE68A),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '#${q['numero']} ${q['texto']}',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: const Color(0xFF1F2937),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (q['fallos'] is num &&
                                      q['intentos'] is num &&
                                      q['tasa_error'] is num)
                                    Text(
                                      'Fallos: ${q['fallos']}/${q['intentos']}  |  Error: ${(q['tasa_error'] as num).toStringAsFixed(0)}%',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: const Color(0xFF92400E),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          )
                        else
                          Text(
                            'Aun no hay preguntas falladas en esta materia.',
                            style: GoogleFonts.inter(
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
            ),
            if (!_cargando)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: cantidadPracticarCriticas == 0
                        ? null
                        : () async {
                            final tiempoPractica = tiempo > 0 ? tiempo : 20;
                            await widget.onPracticar(
                              cantidadPracticarCriticas,
                              tiempoPractica,
                              _materia,
                              idsPrioritariasDetalle,
                              esPracticaGuiada: true,
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0B5A45),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Practicar preguntas',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
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
