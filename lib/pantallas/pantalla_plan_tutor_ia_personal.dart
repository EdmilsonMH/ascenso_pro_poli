import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../modelos/modelo_pregunta.dart';
import '../servicios/auth_service.dart';
import '../servicios/tutor_ia_personal_service.dart';
import '../servicios/servicio_preguntas.dart';
import 'pantalla_practica.dart';
// En este paso, usaremos un Map dinÃ¡mico para el resultado del servicio,
// pero podrÃ­amos adaptar DiagnosticoIA mÃ¡s adelante.

class PantallaPlanTutorIAPersonal extends StatefulWidget {
  const PantallaPlanTutorIAPersonal({super.key});

  @override
  State<PantallaPlanTutorIAPersonal> createState() =>
      _PantallaPlanTutorIAPersonalState();
}

class _PantallaPlanTutorIAPersonalState
    extends State<PantallaPlanTutorIAPersonal> {
  final TutorIAPersonalService _iaService = TutorIAPersonalService();
  final ServicioPreguntas _servicioPreguntas = ServicioPreguntas();
  static const Duration _cacheAnalisisFreshWindow = Duration(minutes: 10);
  static final Map<String, Map<String, dynamic>> _cacheAnalisisPorUsuario = {};
  static final Map<String, DateTime> _cacheAnalisisAtPorUsuario = {};
  Map<String, dynamic>? _analisisPerfil;
  String _categoriaUsuario = 'Oficiales de Armas';
  String _userId = 'user_test_id';
  bool _cargando = true;
  bool _actualizandoTutor = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos({bool forzarRecarga = false}) async {
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

      // Modo instantaneo: si hay cache, se pinta de inmediato.
      if (!forzarRecarga && cacheData != null && mounted) {
        setState(() {
          _analisisPerfil = Map<String, dynamic>.from(cacheData);
          _userId = userId;
          if (categoria != null && categoria.isNotEmpty) {
            _categoriaUsuario = categoria;
          }
          _cargando = false;
        });

        // Si el cache aun es muy reciente, evitamos pedir de nuevo.
        if (cacheAt != null &&
            DateTime.now().difference(cacheAt) < _cacheAnalisisFreshWindow) {
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
      _cacheAnalisisPorUsuario[userId] = Map<String, dynamic>.from(resultado);
      _cacheAnalisisAtPorUsuario[userId] = DateTime.now();

      if (mounted) {
        setState(() {
          _analisisPerfil = resultado;
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
    final raw = _analisisPerfil?['analisis_materias'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  Future<void> _abrirDetalleMateria(Map<String, dynamic> materia) async {
    final debilidadesGlobales =
        List<String>.from(_analisisPerfil?['debilidades'] ?? []);
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
        onPracticar: (cantidad, tiempoMinutos, materiaNombre, idsCriticas) async {
          await _iniciarPractica(
            cantidad: cantidad,
            tiempoLimite: tiempoMinutos,
            materia: materiaNombre,
            preguntaIdsPrioritarias: idsCriticas,
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
    final panel = _analisisPerfil?['panel_ia'];
    if (panel is Map && panel['cards'] is List) {
      return (panel['cards'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
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
      case 'plan':
        return const Color(0xFFF97316);
      case 'practice':
        return const Color(0xFF3B82F6);
      case 'streak':
        return const Color(0xFF10B981);
      case 'recommendation':
        return const Color(0xFF8B5CF6);
      case 'alert':
        return const Color(0xFFEF4444);
      case 'message':
      default:
        return const Color(0xFF111827);
    }
  }

  IconData _iconoPorTipo(String type) {
    switch (type) {
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
    if (type == 'plan') {
      return 'Tu meta de hoy: $tiempo min';
    }
    if (type == 'practice') {
      if (materia != null && materia.isNotEmpty) {
        return '$cantidad preguntas - $materia';
      }
      return '$cantidad preguntas aleatorias';
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

  Future<void> _abrirChatTutor() async {
    final contexto = <String, dynamic>{
      'user_id': _userId,
      'categoria_usuario': _categoriaUsuario,
      'nivel_global': _analisisPerfil?['nivel_global'],
      'tasa_acierto': _analisisPerfil?['tasa_acierto'],
      'fortalezas': _analisisPerfil?['fortalezas'],
      'debilidades': _analisisPerfil?['debilidades'],
      'resumen_materias': _analisisPerfil?['resumen_materias'],
    };

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChatTutorSheet(
        iaService: _iaService,
        contexto: contexto,
      ),
    );
  }

  Widget _buildTarjetaAccionIA(Map<String, dynamic> card) {
    final type = (card['type'] ?? 'message').toString().trim();
    final title = (card['title'] ?? 'Recomendacion IA').toString().trim();
    final message = (card['message'] ?? '').toString();
    final cta = (card['cta'] ?? '').toString().trim();
    final items =
        (card['items'] is List)
            ? (card['items'] as List)
                .whereType<String>()
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList()
            : <String>[];

    final payload =
        card['payload'] is Map
            ? Map<String, dynamic>.from(card['payload'])
            : <String, dynamic>{};
    final cantidad = _intValue(payload['cantidad'], 20);
    final tiempo = _intValue(payload['tiempo'], 25);
    final materia =
        payload['materia'] is String ? payload['materia'] as String : null;
    final color = _colorPorTipo(type);
    final subtitulo = _subtituloPorTipo(type, cantidad, tiempo, materia);
    final ctaFinal = cta.isNotEmpty ? cta : _ctaPorDefecto(type, cantidad);
    final canPractice =
        type == 'plan' || type == 'practice' || payload.containsKey('cantidad');

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
              onPressed: () {
                if (canPractice) {
                  _iniciarPractica(
                    cantidad: cantidad,
                    tiempoLimite: tiempo,
                    materia: materia,
                  );
                  return;
                }
                _mostrarDetalleOrden(
                  title: title.isEmpty ? 'Recomendacion IA' : title,
                  message: message,
                  items: items,
                );
              },
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
    List<String> preguntaIdsPrioritarias = const [],
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final priorizadas = await _servicioPreguntas.obtenerPreguntasPorIds(
        ids: preguntaIdsPrioritarias,
        categoria: _categoriaUsuario,
        materia: materia,
      );

      final faltantes = (cantidad - priorizadas.length).clamp(0, cantidad);
      final aleatorias = await _servicioPreguntas.obtenerPreguntasAleatorias(
        cantidad: faltantes,
        categoria: _categoriaUsuario,
        materia: materia,
      );

      final preguntas = <Pregunta>[];
      final usados = <String>{};
      for (final p in priorizadas) {
        if (preguntas.length >= cantidad) break;
        if (usados.add(p.id)) preguntas.add(p);
      }
      for (final p in aleatorias) {
        if (preguntas.length >= cantidad) break;
        if (usados.add(p.id)) preguntas.add(p);
      }

      if (!mounted) return;
      Navigator.pop(context);

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
            esModoPractica: false,
          ),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al iniciar practica: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardsIa = _obtenerCardsIA();
    final diagnostico = (_analisisPerfil?['diagnostico'] ?? '').toString();
    final resumenMaterias =
        (_analisisPerfil?['resumen_materias'] ?? '').toString();
    final materiasAnalisis = _obtenerAnalisisMaterias();
    final fortalezasAnalisis = [
      ...List<String>.from(_analisisPerfil?['fortalezas'] ?? []),
      if ((_analisisPerfil?['velocidad_promedio'] as num?) != null &&
          (_analisisPerfil?['velocidad_promedio'] as num) < 15)
        "Buena velocidad (${_analisisPerfil?['velocidad_promedio']} seg/preg)",
      if ((_analisisPerfil?['racha_dias'] as int? ?? 0) >= 3)
        "Racha de ${_analisisPerfil?['racha_dias']} dias",
    ];
    final debilidadesAnalisis = [
      ...List<String>.from(_analisisPerfil?['debilidades'] ?? []),
      if ((_analisisPerfil?['tasa_acierto'] as num? ?? 0) < 50)
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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Tarjeta de DiagnÃ³stico Principal (Nivel Global)
                  _SeccionNivelGlobal(
                    nivel: _analisisPerfil!['nivel_global'],
                    tasaAcierto: _analisisPerfil!['tasa_acierto'],
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

                  // 3. SECCIÃ“N DE PROGRESO (Mockup Requerido)
                  Text(
                    "ðŸ“ˆ PROGRESO",
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ProgresoDetalladoCard(analisis: _analisisPerfil!),

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
                      children:
                          cardsIa.map(_buildTarjetaAccionIA).toList(),
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

  const _ChatTutorSheet({
    required this.iaService,
    required this.contexto,
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
            'Soy Tutor IA Personal. Preguntame por materias debiles, plan diario, estrategia o simulacros.',
        esUsuario: false,
      ),
    );
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

  Future<void> _enviarMensaje() async {
    final mensaje = _controller.text.trim();
    if (mensaje.isEmpty || _enviando) return;

    _controller.clear();
    setState(() {
      _mensajes.add(_MensajeChatTutor(texto: mensaje, esUsuario: true));
      _enviando = true;
    });
    _scrollAlFinal();

    final contextoChat = <String, dynamic>{
      ...widget.contexto,
      'historial_chat': _historialParaIA(),
    };

    final respuesta = await widget.iaService.enviarMensajeTutor(
      mensaje: mensaje,
      contexto: contextoChat,
    );

    if (!mounted) return;
    setState(() {
      _mensajes.add(_MensajeChatTutor(texto: respuesta, esUsuario: false));
      _enviando = false;
    });
    _scrollAlFinal();
  }

  List<Map<String, String>> _historialParaIA() {
    if (_mensajes.isEmpty) return const [];
    final start = _mensajes.length > 10 ? _mensajes.length - 10 : 0;
    return _mensajes
        .sublist(start)
        .map(
          (m) => {
            'rol': m.esUsuario ? 'usuario' : 'tutor',
            'texto': m.texto,
          },
        )
        .toList();
  }

  Widget _burbuja(_MensajeChatTutor mensaje) {
    final esUsuario = mensaje.esUsuario;
    final bg = esUsuario ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9);
    final fg = esUsuario ? Colors.white : const Color(0xFF0F172A);
    final align =
        esUsuario ? CrossAxisAlignment.end : CrossAxisAlignment.start;
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
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
          ),
          child: Text(
            mensaje.texto,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: fg,
              height: 1.4,
            ),
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
                          color: const Color(0xFF0F172A),
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
                                color: const Color(0xFF334155),
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
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.shade300,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.shade300,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF2563EB),
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
                          backgroundColor: const Color(0xFF2563EB),
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
        color: const Color(0xFF1E293B), // Azul pizarra oscuro policial
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
                      colors: [Colors.blue, Colors.cyan],
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10),
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
            color: Colors.blue,
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
    return items.map((raw) {
      final texto = raw.trim();
      final match = regex.firstMatch(texto);
      final nombre = match != null ? match.group(1)!.trim() : texto;
      final score =
          match != null ? double.tryParse(match.group(2) ?? '') : null;
      final porcentaje = score ?? (tipo == 'fortaleza' ? 75.0 : 45.0);
      return {
        'materia': nombre,
        'porcentaje': porcentaje,
        'nivel': _nivelDesdePorcentaje(porcentaje),
        'tipo': tipo,
      };
    }).where((e) => (e['materia'] as String).isNotEmpty).toList();
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
            colors: [Color(0xFF0B1220), Color(0xFF1D4ED8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF1E40AF)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1D4ED8).withValues(alpha: 0.25),
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
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white70,
                ),
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
    final nivel =
        (materia['nivel'] ?? _nivelDesdePorcentaje(porcentaje)).toString();

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
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: color,
                ),
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
            color: const Color(0xFF16A34A),
            icono: Icons.check_circle_outline,
            tipo: 'fortaleza',
          ),
          const SizedBox(height: 12),
          _buildGrupo(
            titulo: 'Areas de mejora por materia',
            color: const Color(0xFFF59E0B),
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
              colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E3A8A).withValues(alpha: 0.24),
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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Analisis por Materia',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0F172A),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
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
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Text(
                resumenMaterias.trim().isNotEmpty
                    ? resumenMaterias.trim()
                    : diagnostico,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.45,
                  color: const Color(0xFF1E3A8A),
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
    List<String> preguntaIdsPrioritarias,
  ) onPracticar;

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
  List<Pregunta> _preguntas = const [];

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
    final rec = await widget.iaService.recomendarPorMateria(
      materia: _materia,
      porcentaje: _porcentaje,
      nivel: _nivel,
      debilidadesGlobales: widget.debilidadesGlobales,
    );

    final detalle = await widget.iaService.obtenerDetalleMateria(
      userId: widget.userId,
      materia: _materia,
      porcentajeActual: _porcentaje,
      nivelActual: _nivel,
    );

    final criticas = await widget.iaService.obtenerPreguntasQueBajanMateria(
      userId: widget.userId,
      materia: _materia,
      limit: 6,
    );

    final sugeridas = await widget.servicioPreguntas.obtenerPreguntasAleatorias(
      cantidad: 5,
      materia: _materia,
      categoria: widget.categoriaUsuario,
    );

    if (!mounted) return;
    setState(() {
      _recomendacion = rec;
      _detalleMateria = detalle;
      _preguntasCriticas = criticas;
      _preguntas = sugeridas;
      _cargando = false;
    });
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
            color: const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
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
          ],
        ),
      ),
    );
  }

  Widget _buildFieldChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _iniciarSoloFallidas({
    required int cantidad,
    required int tiempo,
    required List<String> idsFallidas,
  }) async {
    if (idsFallidas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay preguntas fallidas suficientes en esta materia'),
        ),
      );
      return;
    }

    Navigator.pop(context);
    await widget.onPracticar(cantidad, tiempo, _materia, idsFallidas);
  }

  @override
  Widget build(BuildContext context) {
    final info = (_detalleMateria['info_basica'] is Map)
        ? Map<String, dynamic>.from(_detalleMateria['info_basica'])
        : <String, dynamic>{};
    final progreso = (_detalleMateria['progreso_usuario'] is Map)
        ? Map<String, dynamic>.from(_detalleMateria['progreso_usuario'])
        : <String, dynamic>{};
    final stats = (_detalleMateria['estadisticas_clave'] is Map)
        ? Map<String, dynamic>.from(_detalleMateria['estadisticas_clave'])
        : <String, dynamic>{};
    final pred = (_detalleMateria['prediccion'] is Map)
        ? Map<String, dynamic>.from(_detalleMateria['prediccion'])
        : <String, dynamic>{};
    final fallidas = (_detalleMateria['fallidas'] is Map)
        ? Map<String, dynamic>.from(_detalleMateria['fallidas'])
        : <String, dynamic>{};
    final tutorIaRaw = _detalleMateria['tutor_ia_personal'];
    final tutorIa = (tutorIaRaw is Map)
        ? Map<String, dynamic>.from(tutorIaRaw)
        : <String, dynamic>{};
    final recomendaciones = (_detalleMateria['recomendaciones'] is Map)
        ? Map<String, dynamic>.from(_detalleMateria['recomendaciones'])
        : <String, dynamic>{};

    final focos = (_recomendacion['focos'] is List)
        ? (_recomendacion['focos'] as List)
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];

    final cantidad = (_recomendacion['cantidad_preguntas'] is num)
        ? (_recomendacion['cantidad_preguntas'] as num).toInt()
        : 15;
    final tiempo = (_recomendacion['tiempo_minutos'] is num)
        ? (_recomendacion['tiempo_minutos'] as num).toInt()
        : 20;

    final totalPreguntas = _intValue(info['total_preguntas'], 0);
    final codigoMateria = (info['codigo'] ?? 'SIN-COD').toString();
    final areaMateria = (info['area'] ?? 'Area general').toString();
    final dificultad = (info['dificultad'] ?? 'media').toString().toUpperCase();

    final correctas = _intValue(progreso['correctas'], 0);
    final incorrectas = _intValue(progreso['incorrectas'], 0);
    final noRespondidas = _intValue(progreso['no_respondidas'], 0);
    final porcentajeAvance = _doubleValue(progreso['porcentaje_avance'], 0);
    final preguntasVistas = _intValue(progreso['preguntas_vistas'], 0);

    final tiempoPromMateria = _doubleValue(stats['tiempo_promedio_pregunta'], 0);
    final tiempoPromGlobal = _doubleValue(stats['promedio_general'], 0);
    final comparacionTexto =
        (stats['comparacion_texto'] ?? 'Sin datos de comparacion').toString();
    final intentosRealizados = _intValue(stats['intentos_realizados'], 0);
    final tendencia = (stats['tendencia'] ?? 'estable').toString();
    final deltaTendencia = _doubleValue(stats['delta_tendencia'], 0);

    final probActual = _doubleValue(pred['probabilidad_actual'], _porcentaje);
    final prob7 = _doubleValue(pred['proyeccion_7_dias'], _porcentaje);
    final prob14 = _doubleValue(pred['proyeccion_14_dias'], _porcentaje);
    final prob30 = _doubleValue(pred['proyeccion_30_dias'], _porcentaje);

    final totalFallidas = _intValue(fallidas['total'], _preguntasCriticas.length);
    final idsFallidas = (fallidas['ids'] is List)
        ? (fallidas['ids'] as List)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];
    final practicarFallidasCantidad = _intValue(
      fallidas['practicar_cantidad'],
      idsFallidas.isEmpty ? 0 : idsFallidas.length.clamp(10, 30),
    );
    final simulacroFallidasCantidad = _intValue(
      fallidas['simulacro_cantidad'],
      idsFallidas.isEmpty ? 0 : idsFallidas.length.clamp(20, 60),
    );

    final temaRiesgoso = (tutorIa['tema_riesgoso'] ?? 'Sin datos suficientes')
        .toString();
    final temaImpacto = (tutorIa['tema_impacto'] ?? 'Sin datos suficientes')
        .toString();
    final nivelUsuario = (tutorIa['nivel_usuario'] ?? _nivel).toString();
    final materiasTiempo = (tutorIa['materias_tiempo_perdido'] is List)
        ? (tutorIa['materias_tiempo_perdido'] as List)
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList()
        : <String>[];

    final tiempoDiario = _intValue(recomendaciones['tiempo_diario_sugerido'], tiempo);
    final temaPrioritario =
        (recomendaciones['tema_prioritario'] ?? temaRiesgoso).toString();
    final objetivo = (recomendaciones['objetivo'] ?? 'Alcanzar 80% en 10 dias')
        .toString();

    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
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
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              _nivel,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1D4ED8),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${probActual.toStringAsFixed(0)}%',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
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
                              Color(0xFF2563EB),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Avance de materia: ${porcentajeAvance.toStringAsFixed(1)}%',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _buildSectionTitle(
                          '1) Informacion basica',
                          Icons.badge_outlined,
                          const Color(0xFF1D4ED8),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildFieldChip('Codigo', codigoMateria),
                            _buildFieldChip('Area', areaMateria),
                            _buildFieldChip('Preguntas', '$totalPreguntas'),
                            _buildFieldChip('Dificultad', dificultad),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSectionTitle(
                          '2) Progreso del usuario',
                          Icons.assessment_rounded,
                          const Color(0xFF059669),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _buildMiniStat(
                              label: 'Correctas',
                              value: '$correctas',
                              color: const Color(0xFF16A34A),
                            ),
                            const SizedBox(width: 8),
                            _buildMiniStat(
                              label: 'Incorrectas',
                              value: '$incorrectas',
                              color: const Color(0xFFDC2626),
                            ),
                            const SizedBox(width: 8),
                            _buildMiniStat(
                              label: 'No respondidas',
                              value: '$noRespondidas',
                              color: const Color(0xFFD97706),
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
                          '4) Estadisticas clave',
                          Icons.stacked_line_chart_rounded,
                          const Color(0xFF7C3AED),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tiempo promedio: ${tiempoPromMateria.toStringAsFixed(1)} seg/preg',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Promedio general: ${tiempoPromGlobal.toStringAsFixed(1)} seg/preg',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                comparacionTexto,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Intentos realizados: $intentosRealizados',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tendencia: ${tendencia.toUpperCase()} (${deltaTendencia >= 0 ? '+' : ''}${deltaTendencia.toStringAsFixed(1)}%)',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: tendencia == 'empeorando'
                                      ? const Color(0xFFB91C1C)
                                      : const Color(0xFF0F766E),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionTitle(
                          '5) Prediccion',
                          Icons.auto_awesome_rounded,
                          const Color(0xFF1D4ED8),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF4FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Probabilidad actual: ${probActual.toStringAsFixed(0)}%',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1E3A8A),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '7 dias: ${prob7.toStringAsFixed(0)}%   |   14 dias: ${prob14.toStringAsFixed(0)}%   |   30 dias: ${prob30.toStringAsFixed(0)}%',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF1E3A8A),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionTitle(
                          '6) Preguntas fallidas',
                          Icons.error_outline_rounded,
                          const Color(0xFFDC2626),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total fallidas: $totalFallidas',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF7F1D1D),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: idsFallidas.isEmpty
                                          ? null
                                          : () async {
                                              await _iniciarSoloFallidas(
                                                cantidad: practicarFallidasCantidad,
                                                tiempo: tiempo,
                                                idsFallidas: idsFallidas,
                                              );
                                            },
                                      child: const Text('Practicar solo fallidas'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: idsFallidas.isEmpty
                                          ? null
                                          : () async {
                                              await _iniciarSoloFallidas(
                                                cantidad: simulacroFallidasCantidad,
                                                tiempo: tiempo < 40 ? 40 : tiempo,
                                                idsFallidas: idsFallidas,
                                              );
                                            },
                                      child: const Text('Simulacro fallidas'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionTitle(
                          '7) Tutor IA Personal (lectura)',
                          Icons.psychology_alt_rounded,
                          const Color(0xFF7C3AED),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F3FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFDDD6FE),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tema mas riesgoso: $temaRiesgoso',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: const Color(0xFF4C1D95),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tema que mas impacta en puntaje: $temaImpacto',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF4C1D95),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                materiasTiempo.isEmpty
                                    ? 'Materias que te hacen perder tiempo: Sin datos suficientes'
                                    : 'Materias que te hacen perder tiempo: ${materiasTiempo.join(', ')}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF4C1D95),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Nivel actual: $nivelUsuario',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF4C1D95),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionTitle(
                          '8) Recomendaciones automaticas',
                          Icons.tips_and_updates_outlined,
                          const Color(0xFF0F766E),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tiempo diario sugerido: $tiempoDiario min',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF065F46),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tema prioritario: $temaPrioritario',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF065F46),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Objetivo sugerido: $objetivo',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF065F46),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Focos tacticos de refuerzo',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (focos.isEmpty)
                          Text(
                            'Aun no hay focos generados.',
                            style: GoogleFonts.inter(color: Colors.grey.shade600),
                          )
                        else
                          ...focos.map(
                            (f) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      f,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: const Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          'Preguntas que bajan tu porcentaje',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_preguntasCriticas.isEmpty)
                          Text(
                            'Aun no hay suficientes intentos para detectar preguntas criticas en esta materia.',
                            style: GoogleFonts.inter(color: Colors.grey.shade600),
                          )
                        else
                          ..._preguntasCriticas.map(
                            (q) => Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFFDE68A)),
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
                          ),
                        const SizedBox(height: 16),
                        Text(
                          'Preguntas sugeridas',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_preguntas.isEmpty)
                          Text(
                            'No hay preguntas disponibles para esta materia por ahora.',
                            style: GoogleFonts.inter(color: Colors.grey.shade600),
                          )
                        else
                          ..._preguntas.map(
                            (p) => Container(
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
                    onPressed: () async {
                      final idsCriticas = _preguntasCriticas
                          .map((q) => (q['pregunta_id'] ?? '').toString().trim())
                          .where((id) => id.isNotEmpty)
                          .toList();
                      Navigator.pop(context);
                      await widget.onPracticar(
                        cantidad,
                        tiempo,
                        _materia,
                        idsCriticas,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Practicar $cantidad preguntas de $_materia',
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


