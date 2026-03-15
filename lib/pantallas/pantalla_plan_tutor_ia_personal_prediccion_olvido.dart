part of 'pantalla_plan_tutor_ia_personal.dart';

class _PantallaPrediccionOlvido extends StatefulWidget {
  final String userId;
  final TutorIAPersonalService iaService;
  final TutorInsightCard card;
  final Future<void> Function(_CoachVelocidadPracticaRequest req)?
  onIniciarPractica;

  const _PantallaPrediccionOlvido({
    required this.userId,
    required this.iaService,
    required this.card,
    this.onIniciarPractica,
  });

  @override
  State<_PantallaPrediccionOlvido> createState() =>
      _PantallaPrediccionOlvidoState();
}

class _PantallaPrediccionOlvidoState extends State<_PantallaPrediccionOlvido> {
  bool _cargando = true;
  String? _error;
  String _resumen = '';
  int _totalPreguntas = 0;
  int _totalUrgentes = 0;
  List<Map<String, dynamic>> _materias = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _resumen = widget.card.resumen.trim();
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

  Future<void> _emitirSolicitudPractica(
    _CoachVelocidadPracticaRequest req,
  ) async {
    final onIniciar = widget.onIniciarPractica;
    if (onIniciar != null) {
      await onIniciar(req);
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, req);
  }

  Color _colorRiesgo(double maxProb) {
    // Misma paleta y orden semantico que la leyenda:
    // Critica (rojo), Alta (naranja), Media (amarillo), Baja (verde).
    if (maxProb >= 85) return const Color(0xFFC63D4D);
    if (maxProb >= 70) return const Color(0xFFE86C32);
    if (maxProb >= 55) return const Color(0xFFCA9A36);
    return const Color(0xFF26A269);
  }

  String _estadoRiesgo(double maxProb) {
    if (maxProb >= 85) return 'Critica';
    if (maxProb >= 70) return 'Alta';
    if (maxProb >= 55) return 'Media';
    return 'Baja';
  }

  int _sugerirCantidad(int total) {
    if (total >= 40) return 25;
    if (total >= 20) return 20;
    return 12;
  }

  int _sugerirTiempo(double maxProb) {
    if (maxProb >= 90) return 35;
    if (maxProb >= 80) return 30;
    return 25;
  }

  DateTime? _parseFechaRevision(String value) {
    final txt = value.trim();
    if (txt.isEmpty) return null;
    try {
      return DateTime.parse(txt);
    } catch (_) {
      return null;
    }
  }

  int? _diasHastaRevision(String value) {
    final fecha = _parseFechaRevision(value);
    if (fecha == null) return null;
    final hoy = DateTime.now();
    final baseHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final baseFecha = DateTime(fecha.year, fecha.month, fecha.day);
    return baseFecha.difference(baseHoy).inDays;
  }

  Future<void> _iniciarRepasoMateria({
    required String nombreMateria,
    required List<String> preguntaIds,
    required int cantidad,
    required int tiempoMinutos,
  }) async {
    await _emitirSolicitudPractica(
      _CoachVelocidadPracticaRequest(
        cantidad: cantidad,
        tiempoMinutos: tiempoMinutos,
        materia: nombreMateria.isEmpty ? null : nombreMateria,
        preguntaIdsPrioritarias: preguntaIds,
      ),
    );
  }

  Future<void> _abrirDetalleMateriaPrediccion({
    required String nombre,
    required int total,
    required int urgentes,
    required double probProm,
    required double probMax,
    required String proxima,
    required List<String> ids,
    required int cantidad,
    required int tiempo,
  }) async {
    if (!mounted) return;
    final req = await Navigator.push<_CoachVelocidadPracticaRequest>(
      context,
      MaterialPageRoute(
        builder: (_) => _PantallaDetallePrediccionOlvidoMateria(
          userId: widget.userId,
          iaService: widget.iaService,
          materia: nombre,
          total: total,
          urgentes: urgentes,
          probProm: probProm,
          probMax: probMax,
          proxima: proxima,
          preguntaIds: ids,
          cantidad: cantidad,
          tiempoMinutos: tiempo,
          onIniciarPractica: widget.onIniciarPractica,
        ),
      ),
    );

    if (!mounted || req == null) return;
    await _emitirSolicitudPractica(req);
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final data = await widget.iaService.obtenerPrediccionOlvidoDetalle(
        userId: widget.userId,
      );
      if (!mounted) return;

      final materiasRaw = data['materias'];
      final materias = materiasRaw is List
          ? materiasRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      setState(() {
        _resumen = (data['resumen'] ?? _resumen).toString().trim();
        _totalPreguntas = _toInt(data['total_preguntas']);
        _totalUrgentes = _toInt(data['total_urgentes']);
        _materias = materias;
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

  Widget _chipDato({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumen() {
    final texto = _resumen.trim().isEmpty
        ? 'Coach de memoria no disponible aun. Realiza una practica para activar este panel.'
        : _resumen.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B5A45), Color(0xFF084434)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF084434).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Coach de Memoria por Materias',
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            texto,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.35,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipDato(
                icon: Icons.layers_outlined,
                label: 'Materias',
                value: '${_materias.length}',
              ),
              _chipDato(
                icon: Icons.help_outline_rounded,
                label: 'Preguntas',
                value: '$_totalPreguntas',
              ),
              _chipDato(
                icon: Icons.priority_high_rounded,
                label: 'Urgentes',
                value: '$_totalUrgentes',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMateriaItem(Map<String, dynamic> materia) {
    final nombre = (materia['materia'] ?? 'Materia').toString().trim();
    final total = _toInt(materia['total']);
    final urgentes = _toInt(materia['urgentes']);
    final probProm = _toDouble(materia['probabilidad_promedio']);
    final probMax = _toDouble(materia['probabilidad_maxima']);
    final proxima = (materia['proxima_revision'] ?? '').toString().trim();
    final ids = materia['pregunta_ids'] is List
        ? (materia['pregunta_ids'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
        : <String>[];

    final color = _colorRiesgo(probMax);
    final cantidadIds = ids.length < 10
        ? 10
        : (ids.length > 60 ? 60 : ids.length);
    final cantidad = ids.isNotEmpty ? cantidadIds : _sugerirCantidad(total);
    final tiempo = _sugerirTiempo(probMax);
    final diasRevision = _diasHastaRevision(proxima);
    final revisionVencida = diasRevision != null && diasRevision < 0;
    final revisionHoy = diasRevision != null && diasRevision == 0;
    final textoRevision = proxima.isEmpty
        ? ''
        : revisionVencida
        ? 'Revision vencida hace ${diasRevision.abs()} dias ($proxima)'
        : (revisionHoy
              ? 'Revision sugerida para hoy ($proxima)'
              : (diasRevision == null
                    ? 'Proxima revision sugerida: $proxima'
                    : 'Proxima revision sugerida: $proxima (en $diasRevision dias)'));
    final colorRevision = revisionVencida
        ? const Color(0xFFB42318)
        : (revisionHoy ? const Color(0xFFB54708) : color);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  nombre.isEmpty ? 'Materia' : nombre,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _estadoRiesgo(probMax),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$total preguntas en riesgo - Urgentes $urgentes - Promedio ${probProm.toStringAsFixed(1)}%',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.3,
            ),
          ),
          if (proxima.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              textoRevision,
              style: GoogleFonts.inter(fontSize: 11.5, color: colorRevision),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    _iniciarRepasoMateria(
                      nombreMateria: nombre,
                      preguntaIds: ids,
                      cantidad: cantidad,
                      tiempoMinutos: tiempo,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B5A45),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Repasar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _abrirDetalleMateriaPrediccion(
                    nombre: nombre,
                    total: total,
                    urgentes: urgentes,
                    probProm: probProm,
                    probMax: probMax,
                    proxima: proxima,
                    ids: ids,
                    cantidad: cantidad,
                    tiempo: tiempo,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0B5A45),
                    side: const BorderSide(color: Color(0xFF0B5A45)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Ver detalles'),
                ),
              ),
            ],
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
          'Coach de Memoria',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _cargar,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      backgroundColor: const Color(0xFFECEFF3),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No se pudo cargar el listado por materias.\n$_error',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.grey.shade700),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  _buildResumen(),
                  const SizedBox(height: 12),
                  Text(
                    'Listado de materias',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade700,
                      letterSpacing: 0.8,
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
                        'Aun no hay materias con riesgo alto para mostrar. Continua practicando para alimentar el coach de memoria.',
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

class _PantallaDetallePrediccionOlvidoMateria extends StatefulWidget {
  final String userId;
  final TutorIAPersonalService iaService;
  final String materia;
  final int total;
  final int urgentes;
  final double probProm;
  final double probMax;
  final String proxima;
  final List<String> preguntaIds;
  final int cantidad;
  final int tiempoMinutos;
  final Future<void> Function(_CoachVelocidadPracticaRequest req)?
  onIniciarPractica;

  const _PantallaDetallePrediccionOlvidoMateria({
    required this.userId,
    required this.iaService,
    required this.materia,
    required this.total,
    required this.urgentes,
    required this.probProm,
    required this.probMax,
    required this.proxima,
    required this.preguntaIds,
    required this.cantidad,
    required this.tiempoMinutos,
    this.onIniciarPractica,
  });

  @override
  State<_PantallaDetallePrediccionOlvidoMateria> createState() =>
      _PantallaDetallePrediccionOlvidoMateriaState();
}

class _PantallaDetallePrediccionOlvidoMateriaState
    extends State<_PantallaDetallePrediccionOlvidoMateria> {
  final ServicioPreguntas _servicioPreguntas = ServicioPreguntas();
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _detalle = const <String, dynamic>{};

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

  Future<void> _emitirSolicitudPractica(
    _CoachVelocidadPracticaRequest req,
  ) async {
    final onIniciar = widget.onIniciarPractica;
    if (onIniciar != null) {
      await onIniciar(req);
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, req);
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final data = await widget.iaService.obtenerDetallePrediccionOlvidoMateria(
        userId: widget.userId,
        materiaNombre: widget.materia,
        preguntaIdsPreferidas: widget.preguntaIds,
      );
      if (!mounted) return;
      setState(() {
        _detalle = data;
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

  String _nivelRiesgo(double riesgo) {
    if (riesgo >= 85) return 'Critico';
    if (riesgo >= 70) return 'Alto';
    if (riesgo >= 55) return 'Medio';
    return 'Bajo';
  }

  Color _colorNivel(double riesgo) {
    if (riesgo >= 85) return const Color(0xFFC63D4D);
    if (riesgo >= 70) return const Color(0xFFE86C32);
    if (riesgo >= 55) return const Color(0xFFCA9A36);
    return const Color(0xFF26A269);
  }

  Map<String, int> _distribucionUrgencia() {
    final raw = _detalle['distribucion_urgencia'];
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final dist = <String, int>{
        'critica': _toInt(map['critica']),
        'alta': _toInt(map['alta']),
        'media': _toInt(map['media']),
        'baja': _toInt(map['baja']),
      };
      final total =
          (dist['critica'] ?? 0) +
          (dist['alta'] ?? 0) +
          (dist['media'] ?? 0) +
          (dist['baja'] ?? 0);
      if (total > 0) return dist;
    }

    final totalBase = _toInt(_detalle['total_preguntas'], widget.total);
    final urgBase = _toInt(_detalle['total_urgentes'], widget.urgentes);
    final restantes = (totalBase - urgBase).clamp(0, totalBase);
    return <String, int>{
      'critica': urgBase,
      'alta': 0,
      'media': restantes,
      'baja': 0,
    };
  }

  List<String> _preguntaIds() {
    final raw = _detalle['pregunta_ids'];
    if (raw is List) {
      final ids = raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      if (ids.isNotEmpty) return ids;
    }
    return widget.preguntaIds.toSet().toList();
  }

  List<String> _toIdList(dynamic value) {
    if (value is! List) return <String>[];
    final ids = <String>[];
    final vistos = <String>{};
    for (final raw in value) {
      final id = raw.toString().trim();
      if (id.isEmpty) continue;
      if (vistos.add(id)) ids.add(id);
    }
    return ids;
  }

  Map<String, List<String>> _idsPorUrgencia() {
    final raw = _detalle['ids_por_urgencia'];
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final critica = _toIdList(map['critica']);
      final alta = _toIdList(map['alta']);
      final media = _toIdList(map['media']);
      final baja = _toIdList(map['baja']);
      if (critica.isNotEmpty ||
          alta.isNotEmpty ||
          media.isNotEmpty ||
          baja.isNotEmpty) {
        return <String, List<String>>{
          'critica': critica,
          'alta': alta,
          'media': media,
          'baja': baja,
        };
      }
    }

    final todos = _preguntaIds();
    final dist = _distribucionUrgencia();
    final c = (dist['critica'] ?? 0).clamp(0, todos.length);
    final aRest = (todos.length - c).clamp(0, todos.length);
    final a = (dist['alta'] ?? 0).clamp(0, aRest);
    final mRest = (todos.length - c - a).clamp(0, todos.length);
    final m = (dist['media'] ?? 0).clamp(0, mRest);
    final critica = todos.take(c).toList();
    final alta = todos.skip(c).take(a).toList();
    final media = todos.skip(c + a).take(m).toList();
    final baja = todos.skip(c + a + m).toList();
    return <String, List<String>>{
      'critica': critica,
      'alta': alta,
      'media': media,
      'baja': baja,
    };
  }

  Future<void> _abrirListadoPreguntasUrgencia({
    required String clave,
    required String titulo,
    required Color color,
  }) async {
    final idsPorUrg = _idsPorUrgencia();
    final ids = idsPorUrg[clave] ?? <String>[];
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay preguntas disponibles en este estado.'),
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
      preguntas = await _servicioPreguntas.obtenerPreguntasPorIds(
        ids: ids,
        materia: widget.materia,
      );
      if (preguntas.isEmpty) {
        preguntas = await _servicioPreguntas.obtenerPreguntasPorIds(ids: ids);
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
          content: Text('No se encontraron preguntas para este estado.'),
        ),
      );
      return;
    }

    final idsPractica = preguntas.map((p) => p.id).toList();
    final cantidadPractica = idsPractica.length < 10 ? 10 : idsPractica.length;

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
                        return TarjetaPregunta(
                          pregunta: p,
                          numeroOrden: index + 1,
                          mostrarRespuestaAlInicio: false,
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
                          Navigator.of(sheetContext).pop();
                          await _emitirSolicitudPractica(
                            _CoachVelocidadPracticaRequest(
                              cantidad: cantidadPractica,
                              tiempoMinutos: widget.tiempoMinutos,
                              materia: widget.materia.isEmpty
                                  ? null
                                  : widget.materia,
                              preguntaIdsPrioritarias: idsPractica,
                            ),
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
                          'Repasar este estado (${idsPractica.length})',
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

  Future<void> _repasar() async {
    final ids = _preguntaIds();
    final cantidad = ids.isNotEmpty
        ? (ids.length < 10 ? 10 : (ids.length > 60 ? 60 : ids.length))
        : widget.cantidad;

    await _emitirSolicitudPractica(
      _CoachVelocidadPracticaRequest(
        cantidad: cantidad,
        tiempoMinutos: widget.tiempoMinutos,
        materia: widget.materia.isEmpty ? null : widget.materia,
        preguntaIdsPrioritarias: ids,
      ),
    );
  }

  Widget _heroCard() {
    final riesgo = _toDouble(_detalle['riesgo_general'], widget.probProm);
    final nivel = (_detalle['nivel_riesgo'] ?? '').toString().trim().isEmpty
        ? _nivelRiesgo(riesgo)
        : (_detalle['nivel_riesgo'] ?? '').toString();
    final colorNivel = _colorNivel(riesgo);
    final total = _toInt(_detalle['total_preguntas'], widget.total);
    final urgentes = _toInt(_detalle['total_urgentes'], widget.urgentes);
    final revision = (_detalle['proxima_revision_legible'] ?? '')
        .toString()
        .trim();
    final revisionFecha = (_detalle['proxima_revision'] ?? widget.proxima)
        .toString()
        .trim();
    final resumen = (_detalle['resumen'] ?? '').toString().trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B5A45), Color(0xFF084434)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF084434).withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Riesgo general',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorNivel.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colorNivel,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      nivel.toString().isEmpty
                          ? 'Critico'
                          : nivel.toString().toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${riesgo.toStringAsFixed(1)}%',
            style: GoogleFonts.robotoMono(
              fontSize: 33,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (riesgo / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.24),
              valueColor: AlwaysStoppedAnimation<Color>(colorNivel),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _miniDatoHero(titulo: 'Preguntas', valor: '$total'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniDatoHero(titulo: 'Urgentes', valor: '$urgentes'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _miniDatoHero(
            titulo: 'Proxima revision',
            valor: revision.isEmpty
                ? (revisionFecha.isEmpty ? 'Sin fecha' : revisionFecha)
                : '$revision ($revisionFecha)',
            fullWidth: true,
          ),
          if (resumen.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              resumen,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.92),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniDatoHero({
    required String titulo,
    required String valor,
    bool fullWidth = false,
  }) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaUrgencia({
    required String label,
    required String clave,
    required int value,
    required int maxValue,
    required Color color,
  }) {
    final factor = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: GoogleFonts.robotoMono(
                fontSize: 15,
                color: const Color(0xFF111827),
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: value <= 0
                ? null
                : () => _abrirListadoPreguntasUrgencia(
                    clave: clave,
                    titulo: 'Preguntas en estado $label',
                    color: color,
                  ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Text(
                'Ver',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: value <= 0
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF0B5A45),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(999),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: factor,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 30,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: GoogleFonts.robotoMono(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _graficoUrgencia() {
    final dist = _distribucionUrgencia();
    final critica = dist['critica'] ?? 0;
    final alta = dist['alta'] ?? 0;
    final media = dist['media'] ?? 0;
    final baja = dist['baja'] ?? 0;
    final maxValue = [
      critica,
      alta,
      media,
      baja,
    ].fold<int>(0, (a, b) => a > b ? a : b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Distribucion por urgencia',
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Cuantas preguntas caen en cada nivel:',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 12),
          _filaUrgencia(
            label: 'Critica',
            clave: 'critica',
            value: critica,
            maxValue: maxValue,
            color: const Color(0xFFC63D4D),
          ),
          _filaUrgencia(
            label: 'Alta',
            clave: 'alta',
            value: alta,
            maxValue: maxValue,
            color: const Color(0xFFE86C32),
          ),
          _filaUrgencia(
            label: 'Media',
            clave: 'media',
            value: media,
            maxValue: maxValue,
            color: const Color(0xFFCA9A36),
          ),
          _filaUrgencia(
            label: 'Baja',
            clave: 'baja',
            value: baja,
            maxValue: maxValue,
            color: const Color(0xFF26A269),
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
          'Ver detalles',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _cargar,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF1F5F9),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No se pudo cargar el detalle.\n$_error',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.grey.shade700),
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.materia.isEmpty ? 'Materia' : widget.materia,
                    style: GoogleFonts.inter(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _heroCard(),
                  const SizedBox(height: 14),
                  _graficoUrgencia(),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _repasar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B5A45),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Repasar'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}



