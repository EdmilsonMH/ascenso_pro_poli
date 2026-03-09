import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../modelos/modelo_pregunta.dart';
import '../modelos/tutor_dashboard_inicio.dart';
import '../servicios/auth_service.dart';
import '../servicios/tutor_ia_personal_service.dart';
import '../servicios/servicio_preguntas.dart';
import '../servicios/servicio_progreso.dart';
import '../tema/tema_aplicacion.dart';
import 'pantalla_practica.dart';
// En este paso, usaremos un Map dinámico para el resultado del servicio,
// pero podríamos adaptar DiagnosticoIA más adelante.

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
          diagnostico: diagnostico,
          resumenMaterias: resumenMaterias,
          materiasAnalisis: materiasAnalisis,
          fortalezas: fortalezas,
          debilidades: debilidades,
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

  List<Map<String, dynamic>> _obtenerOrdenesTutorParaHoyCards() {
    final dashboard = _dashboardInicio;
    final mision = _dashboardInicio?.misionDiaria;
    final cantidadBase = _intValue(mision?.cantidadPractica, 30).clamp(15, 120);
    final tiempoBase = _intValue(mision?.tiempoPractica, 40).clamp(15, 120);

    final planHoy = _insightPorId('plan_hoy');
    final materiaPrioritaria = _insightPorId('materia_prioritaria');
    final coach = _insightPorId('coach_velocidad');
    final riesgo = _insightPorId('radar_riesgo');

    List<String> idsUnicos(Iterable<String> ids) {
      final salida = <String>[];
      final vistos = <String>{};
      for (final raw in ids) {
        final id = raw.trim();
        if (id.isEmpty) continue;
        if (vistos.add(id)) salida.add(id);
      }
      return salida;
    }

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
      final materia = (insight?.materia ?? fallbackMateria ?? '').trim();
      final preguntaIds = idsUnicos([
        if (!excluirIdsInsight) ...?insight?.preguntaIds,
        ...fallbackPreguntaIds,
      ]);
      if (preguntaIds.isNotEmpty && cantidad < preguntaIds.length) {
        cantidad = preguntaIds.length;
      }
      final materias = <String>{
        if (materia.isNotEmpty) materia,
        ...fallbackMaterias.map((m) => m.trim()).where((m) => m.isNotEmpty),
      }.toList();

      return {
        'type': 'practice',
        'title': title,
        'message':
            (insight?.resumen ?? fallbackMessage ?? 'Sin recomendacion IA.')
                .toString()
                .trim(),
        'cta': 'Entrar',
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

    final materiaRiesgo = (riesgo != null && riesgo.riesgos.isNotEmpty)
        ? riesgo.riesgos.first.materia
        : null;
    final materiasRiesgo = (riesgo?.riesgos ?? const <TutorRiskItem>[])
        .map((e) => e.materia.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final cards = <Map<String, dynamic>>[
      {
        'type': 'guided',
        'title': 'Practica guiada',
        'message':
            'La IA organiza tu sesion completa por materias, dificultad y enfoque de mejora.',
        'cta': 'Entrar',
        'payload': {'cantidad': 100, 'tiempo': 120},
      },
      cardPracticaDesdeInsight(
        title: 'Practicar ahora',
        insight: planHoy,
        fallbackMessage:
            'Sesion recomendada para hoy segun tu rendimiento y objetivo diario.',
        fallbackMaterias: materiasRiesgo,
      ),
      cardPracticaDesdeInsight(
        title: 'Materia prioritaria',
        insight: materiaPrioritaria,
        fallbackMessage:
            'Revisa primero la materia mas prioritaria para subir tu nivel hoy.',
        fallbackMateria: materiaPrioritaria?.materia,
        fallbackMaterias: materiasRiesgo,
      ),
      cardPracticaDesdeInsight(
        title: 'Mejora de velocidad',
        insight: coach,
        fallbackMessage: 'Refuerza tu precision y ritmo con practica dirigida.',
        fallbackMaterias: materiasRiesgo,
      ),
      cardPracticaDesdeInsight(
        title: 'Foco de riesgo',
        insight: riesgo,
        fallbackMessage:
            'Atiende primero tus materias con mayor riesgo para no perder avance.',
        fallbackMateria: materiaRiesgo ?? materiaPrioritaria?.materia,
        fallbackMaterias: materiasRiesgo,
      ),
      {
        'type': 'failed',
        'title': 'Preguntas falladas',
        'message':
            'Practica guiada para corregir tus errores recurrentes en preguntas que ya fallaste.',
        'cta': 'Entrar',
        'payload': {'cantidad': 20, 'tiempo': tiempoBase},
      },
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
          fallbackMaterias: materiasRiesgo,
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
          fallbackMaterias: materiasRiesgo,
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

    return cards;
  }

  Future<void> _abrirOrdenesTutorParaHoy() async {
    final cards = _obtenerOrdenesTutorParaHoyCards();
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
      return '$cantidad preguntas con IA guiada';
    }
    if (type == 'plan') {
      return 'Tu meta de hoy: $tiempo min';
    }
    if (type == 'practice') {
      if (materia != null && materia.isNotEmpty) {
        return '$cantidad preguntas - $materia';
      }
      return '$cantidad preguntas aleatorias';
    }
    if (type == 'failed') {
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
      await _iniciarPracticaGuiadaDesdeIA();
      return;
    }
    if (isFailed) {
      await _iniciarPracticaFalladasDesdeIA(cantidad: cantidad);
      return;
    }
    if (canPractice) {
      await _iniciarPractica(
        cantidad: cantidad,
        tiempoLimite: tiempo,
        materia: materia,
        materiasObjetivo: materiasObjetivo,
        preguntaIdsPrioritarias: preguntaIds,
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

  Future<void> _iniciarPracticaGuiadaDesdeIA() async {
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
      final mision = _dashboardInicio?.misionDiaria;
      final planHoy = _insightPorId('plan_hoy');
      var cantidad = _intValue(planHoy?.cantidadPractica, 0);
      if (cantidad <= 0) {
        cantidad = _intValue(mision?.cantidadPractica, 20);
      }
      cantidad = cantidad.clamp(10, 120);

      final materiasObjetivo = <String>{};
      final materiaPrioritaria =
          (_insightPorId('materia_prioritaria')?.materia ?? '').trim();
      if (materiaPrioritaria.isNotEmpty) {
        materiasObjetivo.add(materiaPrioritaria);
      }
      final radar = _insightPorId('radar_riesgo');
      for (final riesgo in (radar?.riesgos ?? const <TutorRiskItem>[])) {
        final materia = riesgo.materia.trim();
        if (materia.isNotEmpty) {
          materiasObjetivo.add(materia);
        }
      }

      final idsDisponibles = await _servicioPreguntas.obtenerIdsDisponibles(
        categoria: _categoriaUsuario,
        materias: materiasObjetivo.toList(),
      );
      if (idsDisponibles.isEmpty) {
        throw Exception('No hay preguntas disponibles en tu banco.');
      }

      final estadisticas = await _servicioProgreso
          .obtenerEstadisticasPreguntas();
      int prioridadFallo(EstadisticaPregunta? estadistica) {
        if (estadistica == null) return 0;
        if (estadistica.rachaAciertos >= 3) return 0;
        return estadistica.fallosVisibles;
      }

      final posicionOriginal = <String, int>{};
      for (var i = 0; i < idsDisponibles.length; i++) {
        posicionOriginal[idsDisponibles[i]] = i;
      }

      final idsOrdenados = List<String>.from(idsDisponibles);
      idsOrdenados.sort((a, b) {
        final prioridadA = prioridadFallo(estadisticas[a]);
        final prioridadB = prioridadFallo(estadisticas[b]);
        final byFallos = prioridadB.compareTo(prioridadA);
        if (byFallos != 0) return byFallos;
        final aciertosA = estadisticas[a]?.aciertosVisibles ?? 0;
        final aciertosB = estadisticas[b]?.aciertosVisibles ?? 0;
        final byAciertos = aciertosA.compareTo(aciertosB);
        if (byAciertos != 0) return byAciertos;
        final idxA = posicionOriginal[a] ?? 999999;
        final idxB = posicionOriginal[b] ?? 999999;
        return idxA.compareTo(idxB);
      });

      final n = cantidad > idsOrdenados.length ? idsOrdenados.length : cantidad;
      final idsSeleccionados = idsOrdenados.take(n).toList();
      seleccionadas = await _servicioPreguntas.obtenerPreguntasPorIds(
        ids: idsSeleccionados,
        categoria: _categoriaUsuario,
      );
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
                  'Entrar',
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
          tiempoLimiteSegundos: tiempoLimite * 60,
          preguntas: preguntas,
          esModoPractica: true,
          revisarRespuestaInmediata: esPracticaGuiada,
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

    final estadisticas = await _servicioProgreso.obtenerEstadisticasPreguntas();
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
      'ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡': 'a',
      'ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©': 'e',
      'ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­': 'i',
      'ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³': 'o',
      'ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âº': 'u',
      'ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¼': 'u',
      'ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â±': 'n',
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
        ),
      ),
    );

    if (!mounted) return;
    if (req == null) return;

    await _iniciarPractica(
      cantidad: req.cantidad,
      tiempoLimite: req.tiempoMinutos,
      materia: req.materia,
      esPracticaGuiada: true,
    );
  }

  Future<void> _ejecutarInsightCard(TutorInsightCard card) async {
    final id = card.id.toLowerCase().trim();
    if (id == 'analisis_perfil') {
      await _abrirMapaTemasSemaforo();
      return;
    }

    if (id == 'coach_velocidad') {
      await _abrirCoachVelocidad();
      return;
    }

    if (id == 'plan_hoy' || id == 'ordenes_tutor_hoy') {
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
              card.titulo.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 14,
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
                Text(
                  'Entrar',
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

  Widget _buildInsightsGridV2(TutorDashboardInicio dashboard) {
    final cards = dashboard.insights.where((card) {
      final id = card.id.toLowerCase().trim();
      return id != 'debrief_sesion' &&
          id != 'mensaje_personal' &&
          id != 'materia_prioritaria';
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
            childAspectRatio: 0.95,
          ),
          itemBuilder: (_, index) => _buildInsightTileV2(cards[index]),
        ),
      ],
    );
  }

  Widget _buildDashboardV2({required Map<String, dynamic> analisis}) {
    final dashboard = _dashboardInicio ?? TutorDashboardInicio.fallback();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroV2(dashboard),
          const SizedBox(height: 14),
          _buildInsightsGridV2(dashboard),
          const SizedBox(height: 24),
          Text(
            'PROGRESO',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 12),
          _ProgresoDetalladoCard(analisis: analisis),
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
              color: Colors.black87,
            ),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black87),
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
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
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
          ? _buildDashboardV2(analisis: analisis)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Tarjeta de Diagnóstico Principal (Nivel Global)
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

                  // 3. SECCIÓN DE PROGRESO (Mockup Requerido)
                  Text(
                    "📈 PROGRESO",
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ProgresoDetalladoCard(analisis: analisis),

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
            'Soy Tutor IA Personal. Pideme plan diario, que estudiar hoy, analisis de sesion, velocidad, horario, patrones de error, materias en riesgo o prediccion de olvido.',
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

class _ProgresoDetalladoCard extends StatelessWidget {
  final Map<String, dynamic> analisis;

  const _ProgresoDetalladoCard({required this.analisis});

  String _formatTiempo(int minutos) {
    if (minutos < 60) return "${minutos}min";
    int h = minutos ~/ 60;
    int m = minutos % 60;
    return "${h}h ${m}min";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          _RowProgreso(
            label: "Preguntas Dominadas",
            value: "${analisis['preguntas_dominadas']}/3000",
            icon: Icons.check_circle_rounded,
            color: Colors.green,
          ),
          const Divider(height: 24),
          _RowProgreso(
            label: "Tasa de Acierto",
            value: "${(analisis['tasa_acierto'] as num).toStringAsFixed(1)}%",
            icon: Icons.analytics_rounded,
            color: TemaAplicacion.colorSecundario,
          ),
          const Divider(height: 24),
          _RowProgreso(
            label: "Tiempo Estudiado",
            value: _formatTiempo(analisis['tiempo_total_estudio'] ?? 0),
            icon: Icons.timer_rounded,
            color: Colors.orange,
          ),
        ],
      ),
    );
  }
}

class _RowProgreso extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _RowProgreso({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade700),
        ),
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
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
  final bool soloDetalleMaterias;

  const _BloqueAnalisisTactico({
    required this.diagnostico,
    required this.resumenMaterias,
    required this.fortalezas,
    required this.debilidades,
    required this.materiasAnalisis,
    required this.onMateriaTap,
    required this.onAbrirPanelMaterias,
    this.soloDetalleMaterias = false,
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
    if (soloDetalleMaterias) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGrupo(
            titulo: 'Fortalezas por materia',
            color: const Color(0xFF237D57),
            icono: Icons.check_circle_outline,
            tipo: 'fortaleza',
          ),
          const SizedBox(height: 12),
          _buildGrupo(
            titulo: 'Areas de mejora por materia',
            color: const Color(0xFFB68B2E),
            icono: Icons.warning_amber_rounded,
            tipo: 'debilidad',
          ),
        ],
      );
    }

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

class _PantallaAnalisisMaterias extends StatelessWidget {
  final String diagnostico;
  final String resumenMaterias;
  final List<String> fortalezas;
  final List<String> debilidades;
  final List<Map<String, dynamic>> materiasAnalisis;
  final ValueChanged<Map<String, dynamic>> onMateriaTap;

  const _PantallaAnalisisMaterias({
    required this.diagnostico,
    required this.resumenMaterias,
    required this.fortalezas,
    required this.debilidades,
    required this.materiasAnalisis,
    required this.onMateriaTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECEFF3),
      appBar: AppBar(
        title: Text(
          'Analisis por Materia',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF5EC7A7)),
              ),
              child: Text(
                resumenMaterias.trim().isNotEmpty
                    ? resumenMaterias.trim()
                    : diagnostico,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.45,
                  color: const Color(0xFF084434),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Toca una materia para abrir su diagnostico detallado.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),
            _BloqueAnalisisTactico(
              diagnostico: diagnostico,
              resumenMaterias: resumenMaterias,
              fortalezas: fortalezas,
              debilidades: debilidades,
              materiasAnalisis: materiasAnalisis,
              onMateriaTap: onMateriaTap,
              onAbrirPanelMaterias: () {},
              soloDetalleMaterias: true,
            ),
          ],
        ),
      ),
    );
  }
}

enum _SemaforoTema { verde, ambar, rojo }

class _MateriaSemaforoItem {
  final String nombre;
  final double porcentaje;
  final _SemaforoTema semaforo;
  final String descripcion;
  final Map<String, dynamic> materia;

  const _MateriaSemaforoItem({
    required this.nombre,
    required this.porcentaje,
    required this.semaforo,
    required this.descripcion,
    required this.materia,
  });
}

class _PantallaMapaTemasSemaforo extends StatelessWidget {
  final List<_MateriaSemaforoItem> items;
  final String resumen;
  final Future<void> Function(Map<String, dynamic> materia) onMateriaTap;

  const _PantallaMapaTemasSemaforo({
    required this.items,
    required this.resumen,
    required this.onMateriaTap,
  });

  Color _colorSemaforo(_SemaforoTema semaforo) {
    switch (semaforo) {
      case _SemaforoTema.verde:
        return const Color(0xFF237D57);
      case _SemaforoTema.ambar:
        return const Color(0xFF8B661E);
      case _SemaforoTema.rojo:
        return const Color(0xFFAD3636);
    }
  }

  String _tituloSemaforo(_SemaforoTema semaforo) {
    switch (semaforo) {
      case _SemaforoTema.verde:
        return 'Verde · Dominadas (>80%)';
      case _SemaforoTema.ambar:
        return 'Ámbar · Dudas o ritmo lento';
      case _SemaforoTema.rojo:
        return 'Rojo · Puntos ciegos (<50% o sin iniciar)';
    }
  }

  List<_MateriaSemaforoItem> _itemsPor(
    _SemaforoTema semaforo, {
    _SemaforoTema? filtroActivo,
  }) {
    final base = items.where((e) => e.semaforo == semaforo).toList();
    if (filtroActivo == null) return base;
    if (filtroActivo != semaforo) return const <_MateriaSemaforoItem>[];
    return base;
  }

  Widget _buildFiltroChip({
    required bool selected,
    required VoidCallback onTap,
    required Color color,
    required String titulo,
    required int total,
  }) {
    return ChoiceChip(
      label: Text(
        '$titulo ($total)',
        style: GoogleFonts.inter(
          color: selected ? Colors.white : color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.25)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  Widget _buildSeccion(
    BuildContext context, {
    required _SemaforoTema semaforo,
    _SemaforoTema? filtroActivo,
  }) {
    final lista = _itemsPor(semaforo, filtroActivo: filtroActivo);
    if (lista.isEmpty) return const SizedBox.shrink();
    final color = _colorSemaforo(semaforo);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tituloSemaforo(semaforo),
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 10),
          ...lista.map(
            (item) => InkWell(
              onTap: () async {
                await onMateriaTap(item.materia);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.18)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.nombre,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.descripcion,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF4B5D67),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Dominio ${item.porcentaje.toStringAsFixed(1)}%',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalVerdes = _itemsPor(_SemaforoTema.verde).length;
    final totalAmbar = _itemsPor(_SemaforoTema.ambar).length;
    final totalRojos = _itemsPor(_SemaforoTema.rojo).length;
    _SemaforoTema? filtroActivo;

    return Scaffold(
      backgroundColor: const Color(0xFFECEFF3),
      appBar: AppBar(
        title: Text(
          'Mapa de temas del prospecto',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: StatefulBuilder(
        builder: (context, setLocalState) {
          final visibles = filtroActivo == null
              ? items
              : items.where((e) => e.semaforo == filtroActivo).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDEE6EA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF5EC7A7)),
                  ),
                  child: Text(
                    resumen.trim().isEmpty
                        ? 'Aqui tienes el estado de tus materias segun tu banco actual. Toca una para ver su diagnostico y plan de refuerzo.'
                        : resumen.trim(),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.35,
                      color: const Color(0xFF084434),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFiltroChip(
                      selected: filtroActivo == _SemaforoTema.verde,
                      onTap: () {
                        setLocalState(() {
                          filtroActivo = filtroActivo == _SemaforoTema.verde
                              ? null
                              : _SemaforoTema.verde;
                        });
                      },
                      color: _colorSemaforo(_SemaforoTema.verde),
                      titulo: 'Verde',
                      total: totalVerdes,
                    ),
                    _buildFiltroChip(
                      selected: filtroActivo == _SemaforoTema.ambar,
                      onTap: () {
                        setLocalState(() {
                          filtroActivo = filtroActivo == _SemaforoTema.ambar
                              ? null
                              : _SemaforoTema.ambar;
                        });
                      },
                      color: _colorSemaforo(_SemaforoTema.ambar),
                      titulo: 'Ambar',
                      total: totalAmbar,
                    ),
                    _buildFiltroChip(
                      selected: filtroActivo == _SemaforoTema.rojo,
                      onTap: () {
                        setLocalState(() {
                          filtroActivo = filtroActivo == _SemaforoTema.rojo
                              ? null
                              : _SemaforoTema.rojo;
                        });
                      },
                      color: _colorSemaforo(_SemaforoTema.rojo),
                      titulo: 'Rojo',
                      total: totalRojos,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (filtroActivo == null) ...[
                  _buildSeccion(
                    context,
                    semaforo: _SemaforoTema.rojo,
                    filtroActivo: filtroActivo,
                  ),
                  _buildSeccion(
                    context,
                    semaforo: _SemaforoTema.ambar,
                    filtroActivo: filtroActivo,
                  ),
                  _buildSeccion(
                    context,
                    semaforo: _SemaforoTema.verde,
                    filtroActivo: filtroActivo,
                  ),
                ] else
                  _buildSeccion(
                    context,
                    semaforo: filtroActivo!,
                    filtroActivo: filtroActivo,
                  ),
                if (visibles.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      filtroActivo == null
                          ? 'Aun no hay materias para mostrar. Realiza una practica para activar este panel.'
                          : 'No hay materias en este semaforo con el filtro actual.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CoachVelocidadPracticaRequest {
  final int cantidad;
  final int tiempoMinutos;
  final String? materia;

  const _CoachVelocidadPracticaRequest({
    required this.cantidad,
    required this.tiempoMinutos,
    this.materia,
  });
}

class _PantallaCoachVelocidad extends StatefulWidget {
  final String userId;
  final TutorIAPersonalService iaService;

  const _PantallaCoachVelocidad({
    required this.userId,
    required this.iaService,
  });

  @override
  State<_PantallaCoachVelocidad> createState() => _PantallaCoachVelocidadState();
}

class _PantallaCoachVelocidadState extends State<_PantallaCoachVelocidad> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _card = const <String, dynamic>{};
  Map<String, dynamic> _metricas = const <String, dynamic>{};
  List<Map<String, dynamic>> _materias = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  int _toInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  double _toDouble(dynamic value, [double fallback = 0.0]) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  String _clasificacionPorPromedio(double promedio) {
    if (promedio < 8) return 'Impulsivo';
    if (promedio <= 20) return 'Optimo';
    return 'Lento';
  }

  String _extraerRecomendacion(String detalle) {
    final idx = detalle.toLowerCase().lastIndexOf('recomendacion:');
    if (idx < 0) return '';
    return detalle.substring(idx + 'recomendacion:'.length).trim();
  }

  Map<String, dynamic> _inferirMetricasDesdeMaterias(
    List<Map<String, dynamic>> materias,
    Map<String, dynamic> card,
  ) {
    if (materias.isEmpty) {
      return const <String, dynamic>{};
    }

    var totalPreguntas = 0;
    var totalSegundos = 0.0;
    var impulsivas = 0;
    var lentas = 0;

    for (final m in materias) {
      final preguntas = _toInt(m['preguntas']);
      if (preguntas <= 0) continue;
      final prom = _toDouble(m['promedio_segundos']);
      final impPct = _toDouble(m['pct_impulsiva']);
      final lenPct = _toDouble(m['pct_lenta']);

      totalPreguntas += preguntas;
      totalSegundos += prom * preguntas;
      impulsivas += ((impPct / 100) * preguntas).round();
      lentas += ((lenPct / 100) * preguntas).round();
    }

    if (totalPreguntas <= 0) {
      return const <String, dynamic>{};
    }

    final promedio = totalSegundos / totalPreguntas;
    final optimas = (totalPreguntas - impulsivas - lentas).clamp(0, totalPreguntas);
    final pctImp = impulsivas * 100.0 / totalPreguntas;
    final pctLen = lentas * 100.0 / totalPreguntas;
    final pctOpt = optimas * 100.0 / totalPreguntas;
    final clasificacion = _clasificacionPorPromedio(promedio);
    final recomendacion = _extraerRecomendacion((card['detalle'] ?? '').toString());

    return {
      'promedio_segundos': promedio,
      'clasificacion': clasificacion,
      'total_respuestas': totalPreguntas,
      'impulsivas': impulsivas,
      'optimas': optimas,
      'lentas': lentas,
      'pct_impulsiva': pctImp,
      'pct_optima': pctOpt,
      'pct_lenta': pctLen,
      'rango_optimo_min': 8,
      'rango_optimo_max': 20,
      'recomendacion': recomendacion,
    };
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final card = await widget.iaService.obtenerAnalisisVelocidadEstructurado(
        userId: widget.userId,
      );
      final materiasRaw = card['materias_tiempo'];
      final materias = materiasRaw is List
          ? materiasRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      final metricasRaw = card['metricas_velocidad'];
      final metricas = metricasRaw is Map
          ? Map<String, dynamic>.from(metricasRaw)
          : _inferirMetricasDesdeMaterias(materias, card);

      if (!mounted) return;
      setState(() {
        _card = card;
        _materias = materias;
        _metricas = metricas;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  Color _colorClasificacion(String clasificacion) {
    final c = clasificacion.toLowerCase();
    if (c.contains('impuls')) return const Color(0xFFB45309);
    if (c.contains('lent')) return const Color(0xFFB91C1C);
    return const Color(0xFF166534);
  }

  Color _fondoClasificacion(String clasificacion) {
    final c = clasificacion.toLowerCase();
    if (c.contains('impuls')) return const Color(0xFFFFF7ED);
    if (c.contains('lent')) return const Color(0xFFFEF2F2);
    return const Color(0xFFF0FDF4);
  }

  int _sugerirCantidad(Map<String, dynamic> materia) {
    final preguntas = _toInt(materia['preguntas']);
    if (preguntas >= 80) return 20;
    if (preguntas >= 30) return 15;
    return 12;
  }

  int _sugerirTiempo(double promedio) {
    if (promedio > 20) return 30;
    if (promedio < 8) return 25;
    return 20;
  }

  Widget _chipMetrica(String titulo, double porcentaje, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$titulo ${porcentaje.toStringAsFixed(1)}%',
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildResumen() {
    final promedio = _toDouble(_metricas['promedio_segundos']);
    final total = _toInt(_metricas['total_respuestas']);
    final clasificacion = (_metricas['clasificacion'] ?? 'Sin datos').toString();
    final pctImp = _toDouble(_metricas['pct_impulsiva']);
    final pctOpt = _toDouble(_metricas['pct_optima']);
    final pctLen = _toDouble(_metricas['pct_lenta']);
    final recomendacion = (_metricas['recomendacion'] ?? '').toString().trim();
    final color = _colorClasificacion(clasificacion);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _fondoClasificacion(clasificacion),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Estado actual: ${clasificacion.toUpperCase()}',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Promedio: ${promedio.toStringAsFixed(1)} seg/preg · Muestra: $total respuestas.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF1F2937),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipMetrica('Impulsivo', pctImp, const Color(0xFFB45309)),
              _chipMetrica('Óptimo', pctOpt, const Color(0xFF166534)),
              _chipMetrica('Lento', pctLen, const Color(0xFFB91C1C)),
            ],
          ),
          if (recomendacion.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Recomendación IA: $recomendacion',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF334155),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccionesInteligentes() {
    final ordenPromedio = [..._materias]
      ..sort(
        (a, b) => _toDouble(
          b['promedio_segundos'],
        ).compareTo(_toDouble(a['promedio_segundos'])),
      );
    final ordenImpulsividad = [..._materias]
      ..sort(
        (a, b) => _toDouble(
          b['pct_impulsiva'],
        ).compareTo(_toDouble(a['pct_impulsiva'])),
      );

    final materiaLenta = ordenPromedio.isNotEmpty ? ordenPromedio.first : null;
    final materiaImpulsiva = ordenImpulsividad.isNotEmpty
        ? ordenImpulsividad.first
        : null;

    final lentaValida =
        materiaLenta != null && _toDouble(materiaLenta['promedio_segundos']) > 20;
    final impulsivaValida =
        materiaImpulsiva != null &&
        _toDouble(materiaImpulsiva['pct_impulsiva']) >= 35 &&
        _toInt(materiaImpulsiva['preguntas']) >= 5;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Acciones inteligentes',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 10),
          if (lentaValida)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final materia = (materiaLenta['materia'] ?? '').toString().trim();
                  Navigator.pop(
                    context,
                    _CoachVelocidadPracticaRequest(
                      cantidad: _sugerirCantidad(materiaLenta),
                      tiempoMinutos: _sugerirTiempo(
                        _toDouble(materiaLenta['promedio_segundos']),
                      ),
                      materia: materia.isEmpty ? null : materia,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B5A45),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Practicar materia más lenta'),
              ),
            ),
          if (impulsivaValida)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    final materia = (materiaImpulsiva['materia'] ?? '')
                        .toString()
                        .trim();
                    Navigator.pop(
                      context,
                      _CoachVelocidadPracticaRequest(
                        cantidad: _sugerirCantidad(materiaImpulsiva),
                        tiempoMinutos: 25,
                        materia: materia.isEmpty ? null : materia,
                      ),
                    );
                  },
                  child: const Text('Corregir impulsividad ahora'),
                ),
              ),
            ),
          if (!lentaValida && !impulsivaValida)
            Text(
              'Buen ritmo general. Mantén sesiones cortas y constantes para sostener la precisión.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMateriaItem(Map<String, dynamic> materia) {
    final nombre = (materia['materia'] ?? 'Materia').toString();
    final promedio = _toDouble(materia['promedio_segundos']);
    final preguntas = _toInt(materia['preguntas']);
    final acierto = _toDouble(materia['tasa_acierto']);
    final imp = _toDouble(materia['pct_impulsiva']);
    final len = _toDouble(materia['pct_lenta']);
    final clasificacion = (materia['clasificacion'] ?? _clasificacionPorPromedio(promedio))
        .toString();
    final color = _colorClasificacion(clasificacion);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  nombre,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${promedio.toStringAsFixed(1)} seg/preg',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$preguntas preguntas · Acierto ${acierto.toStringAsFixed(1)}% · Impulsiva ${imp.toStringAsFixed(1)}% · Lenta ${len.toStringAsFixed(1)}%',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                final materiaNombre = nombre.trim();
                Navigator.pop(
                  context,
                  _CoachVelocidadPracticaRequest(
                    cantidad: _sugerirCantidad(materia),
                    tiempoMinutos: _sugerirTiempo(promedio),
                    materia: materiaNombre.isEmpty ? null : materiaNombre,
                  ),
                );
              },
              child: const Text('Practicar esta materia'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Coach de Velocidad',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
      ),
      backgroundColor: const Color(0xFFF8FAFC),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No pude cargar el coach de velocidad.',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827),
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
                      onPressed: _cargar,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildResumen(),
                  const SizedBox(height: 12),
                  _buildAccionesInteligentes(),
                  const SizedBox(height: 14),
                  Text(
                    'Mapa de velocidad por materias',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_materias.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        (_card['resumen'] ?? 'Aun no hay datos de velocidad para mostrar.')
                            .toString(),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    )
                  else
                    ..._materias.map(_buildMateriaItem),
                ],
              ),
            ),
    );
  }
}

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
                          Navigator.of(context).pop();
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
                            Navigator.pop(context);
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
