part of 'pantalla_plan_tutor_ia_personal.dart';

class _CoachVelocidadPracticaRequest {
  final int cantidad;
  final int tiempoMinutos;
  final String? materia;
  final List<String> preguntaIdsPrioritarias;
  final bool esPracticaGuiada;
  final bool registrarSesionEnHistorial;
  final bool seleccionarAleatorio;
  final int? tiempoLimiteSegundosPersonalizado;

  const _CoachVelocidadPracticaRequest({
    required this.cantidad,
    required this.tiempoMinutos,
    this.materia,
    this.preguntaIdsPrioritarias = const <String>[],
    this.esPracticaGuiada = true,
    this.registrarSesionEnHistorial = true,
    this.seleccionarAleatorio = false,
    this.tiempoLimiteSegundosPersonalizado,
  });
}

class _PantallaCoachVelocidad extends StatefulWidget {
  final String userId;
  final TutorIAPersonalService iaService;
  final Future<void> Function(_CoachVelocidadPracticaRequest req)?
  onIniciarPractica;

  const _PantallaCoachVelocidad({
    required this.userId,
    required this.iaService,
    this.onIniciarPractica,
  });

  @override
  State<_PantallaCoachVelocidad> createState() =>
      _PantallaCoachVelocidadState();
}

class _PantallaCoachVelocidadState extends State<_PantallaCoachVelocidad> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _card = const <String, dynamic>{};
  Map<String, dynamic> _metricas = const <String, dynamic>{};
  List<Map<String, dynamic>> _materias = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _preguntasLentas = const <Map<String, dynamic>>[];

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
    final optimas = (totalPreguntas - impulsivas - lentas).clamp(
      0,
      totalPreguntas,
    );
    final pctImp = impulsivas * 100.0 / totalPreguntas;
    final pctLen = lentas * 100.0 / totalPreguntas;
    final pctOpt = optimas * 100.0 / totalPreguntas;
    final clasificacion = _clasificacionPorPromedio(promedio);
    final recomendacion = _extraerRecomendacion(
      (card['detalle'] ?? '').toString(),
    );

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
      final preguntasRaw = card['preguntas_lentas'];
      final preguntasLentas = preguntasRaw is List
          ? preguntasRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _card = card;
        _materias = materias;
        _metricas = metricas;
        _preguntasLentas = preguntasLentas;
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

  String _mensajeErrorAmigable(String? error) {
    final raw = (error ?? '').toLowerCase();
    if (raw.contains('jwt') ||
        raw.contains('auth') ||
        raw.contains('token') ||
        raw.contains('unauthorized') ||
        raw.contains('no autorizado')) {
      return 'Tu sesion expiro. Vuelve a iniciar sesion e intenta de nuevo.';
    }
    if (raw.contains('network') ||
        raw.contains('socket') ||
        raw.contains('timeout') ||
        raw.contains('timed out') ||
        raw.contains('conexion')) {
      return 'No se pudo conectar con el servidor. Revisa tu internet e intenta nuevamente.';
    }
    return 'No pude cargar el coach de velocidad en este momento. Intenta nuevamente en unos segundos.';
  }

  Widget _chipMetrica(
    String titulo,
    double porcentaje, {
    required Color fondo,
    required Color texto,
    Color? borde,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borde ?? texto.withValues(alpha: 0.45)),
      ),
      child: Text(
        '$titulo ${porcentaje.toStringAsFixed(1)}%',
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: texto,
        ),
      ),
    );
  }

  Widget _buildResumen() {
    final promedio = _toDouble(_metricas['promedio_segundos']);
    final total = _toInt(_metricas['total_respuestas']);
    final clasificacion = (_metricas['clasificacion'] ?? 'Sin datos')
        .toString();
    final pctImp = _toDouble(_metricas['pct_impulsiva']);
    final pctOpt = _toDouble(_metricas['pct_optima']);
    final pctLen = _toDouble(_metricas['pct_lenta']);
    final confianza = (_metricas['confianza_muestra'] ?? 'Sin datos')
        .toString()
        .trim();
    final recomendacion = (_metricas['recomendacion'] ?? '').toString().trim();
    final verdeBase =
        Theme.of(context).appBarTheme.backgroundColor ??
        const Color(0xFF0B5A45);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [verdeBase, const Color(0xFF084434)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Coach inteligente de velocidad',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Estado ${clasificacion.toUpperCase()} - Promedio ${promedio.toStringAsFixed(1)} seg/preg',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Text(
              'Muestra reciente: $total respuestas validas. Confianza: $confianza. Rango optimo: 8 a 20 segundos por pregunta.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipMetrica(
                'Impulsivo',
                pctImp,
                fondo: const Color(0xFFFFEDD5),
                texto: const Color(0xFF9A3412),
                borde: const Color(0xFFFDBA74),
              ),
              _chipMetrica(
                'Optimo',
                pctOpt,
                fondo: const Color(0xFFECFDF5),
                texto: const Color(0xFF065F46),
                borde: const Color(0xFF6EE7B7),
              ),
              _chipMetrica(
                'Lento',
                pctLen,
                fondo: const Color(0xFFFEE2E2),
                texto: const Color(0xFFB91C1C),
                borde: const Color(0xFFFCA5A5),
              ),
            ],
          ),
          if (recomendacion.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Recomendacion IA: $recomendacion',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: Colors.white,
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
        materiaLenta != null &&
        _toDouble(materiaLenta['promedio_segundos']) > 20;
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
                onPressed: () async {
                  final materia = (materiaLenta['materia'] ?? '')
                      .toString()
                      .trim();
                  final idsMateria = _preguntasLentasIdsPorMateria(materia);
                  await _emitirSolicitudPractica(
                    _CoachVelocidadPracticaRequest(
                      cantidad: idsMateria.isNotEmpty
                          ? idsMateria.length
                          : _sugerirCantidad(materiaLenta),
                      tiempoMinutos: _sugerirTiempo(
                        _toDouble(materiaLenta['promedio_segundos']),
                      ),
                      materia: materia.isEmpty ? null : materia,
                      preguntaIdsPrioritarias: idsMateria,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B5A45),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Practicar materia mas lenta'),
              ),
            ),
          if (impulsivaValida)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    final materia = (materiaImpulsiva['materia'] ?? '')
                        .toString()
                        .trim();
                    if (materia.isEmpty) return;
                    final impulsivas = await widget.iaService
                        .obtenerPreguntasImpulsivasPorMateria(
                          userId: widget.userId,
                          materia: materia,
                          limit: 25,
                        );
                    if (!mounted) return;
                    final idsMateria = _idsUnicos(
                      impulsivas.map(
                        (e) => (e['pregunta_id'] ?? '').toString().trim(),
                      ),
                    ).take(25).toList();
                    final cantidadObjetivo = idsMateria.length >= 5
                        ? idsMateria.length
                        : _sugerirCantidad(materiaImpulsiva);
                    await _emitirSolicitudPractica(
                      _CoachVelocidadPracticaRequest(
                        cantidad: cantidadObjetivo,
                        tiempoMinutos: cantidadObjetivo >= 20 ? 25 : 20,
                        materia: materia.isEmpty ? null : materia,
                        preguntaIdsPrioritarias: idsMateria,
                      ),
                    );
                  },
                  child: const Text('Corregir impulsividad ahora'),
                ),
              ),
            ),
          if (!lentaValida && !impulsivaValida)
            Text(
              'Buen ritmo general. Manten sesiones cortas y constantes para sostener la precision.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
        ],
      ),
    );
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

  List<String> _preguntasLentasIdsGlobal() {
    return _idsUnicos(
      _preguntasLentas.map((item) => (item['pregunta_id'] ?? '').toString()),
    );
  }

  List<String> _preguntasLentasIdsPorMateria(String materia) {
    final objetivo = materia.trim().toLowerCase();
    if (objetivo.isEmpty) return const <String>[];
    return _idsUnicos(
      _preguntasLentas
          .where((item) {
            final actual = (item['materia'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            return actual == objetivo;
          })
          .map((item) => (item['pregunta_id'] ?? '').toString()),
    );
  }

  Widget _buildPreguntasLentas() {
    final verdeTema =
        Theme.of(context).appBarTheme.backgroundColor ??
        const Color(0xFF0B5A45);

    if (_preguntasLentas.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: Text(
          'Aun no hay suficientes intentos para detectar preguntas lentas.',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700),
        ),
      );
    }

    final idsGlobal = _preguntasLentasIdsGlobal();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._preguntasLentas.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final numero = _toInt(item['numero']);
            final texto = (item['texto'] ?? 'Pregunta').toString().trim();
            final materia = (item['materia'] ?? 'Materia').toString().trim();
            final promedio = _toDouble(item['promedio_segundos']);
            final intentos = _toInt(item['intentos']);
            final tasaError = _toDouble(item['tasa_error']);

            return Container(
              margin: EdgeInsets.only(
                bottom: index == _preguntasLentas.length - 1 ? 0 : 8,
              ),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: verdeTema.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '#${index + 1}',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: verdeTema,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          numero > 0 ? 'Pregunta $numero' : 'Pregunta',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF334155),
                          ),
                        ),
                      ),
                      Text(
                        '${promedio.toStringAsFixed(1)} seg',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    texto,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F172A),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$materia - $intentos intentos - Error ${tasaError.toStringAsFixed(1)}%',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: const Color(0xFF475569),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: idsGlobal.isEmpty
                  ? null
                  : () async {
                      await _emitirSolicitudPractica(
                        _CoachVelocidadPracticaRequest(
                          cantidad: idsGlobal.length,
                          tiempoMinutos: 30,
                          preguntaIdsPrioritarias: idsGlobal,
                        ),
                      );
                    },
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Practicar preguntas lentas (guiada)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: verdeTema,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirDetalleMateriaVelocidad(
    Map<String, dynamic> materia,
  ) async {
    final materiaNombre = (materia['materia'] ?? '').toString().trim();
    if (materiaNombre.isEmpty) return;

    final lentasIniciales = _preguntasLentas
        .where(
          (item) =>
              (item['materia'] ?? '').toString().trim().toLowerCase() ==
              materiaNombre.toLowerCase(),
        )
        .take(10)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final req = await Navigator.push<_CoachVelocidadPracticaRequest>(
      context,
      MaterialPageRoute(
        builder: (_) => _PantallaDetalleVelocidadMateria(
          userId: widget.userId,
          iaService: widget.iaService,
          materiaNombre: materiaNombre,
          materiaStats: materia,
          promedioGlobalSegundos: _toDouble(_metricas['promedio_segundos']),
          preguntasLentasIniciales: lentasIniciales,
          onIniciarPractica: widget.onIniciarPractica,
        ),
      ),
    );

    if (!mounted || req == null) return;
    await _emitirSolicitudPractica(req);
  }

  Future<void> _entrenarMateriaVelocidad(Map<String, dynamic> materia) async {
    final materiaNombre = (materia['materia'] ?? '').toString().trim();
    if (materiaNombre.isEmpty) return;

    // 20 preguntas x 50 segundos = 1000 segundos.
    await _emitirSolicitudPractica(
      _CoachVelocidadPracticaRequest(
        cantidad: 20,
        tiempoMinutos: 17,
        tiempoLimiteSegundosPersonalizado: 1000,
        materia: materiaNombre,
        esPracticaGuiada: false,
        seleccionarAleatorio: true,
        registrarSesionEnHistorial: false,
      ),
    );
  }

  Widget _buildBotonAccionMateria({
    required String label,
    required VoidCallback onTap,
    required bool primario,
  }) {
    final verde =
        Theme.of(context).appBarTheme.backgroundColor ??
        const Color(0xFF0B5A45);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );

    if (primario) {
      return SizedBox(
        height: 42,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: verde,
            foregroundColor: Colors.white,
            shape: shape,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            textStyle: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      );
    }

    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: verde,
          side: BorderSide(color: verde, width: 1.4),
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
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
    final clasificacion =
        (materia['clasificacion'] ?? _clasificacionPorPromedio(promedio))
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
            '$preguntas preguntas - Acierto ${acierto.toStringAsFixed(1)}% - Impulsiva ${imp.toStringAsFixed(1)}% - Lenta ${len.toStringAsFixed(1)}%',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildBotonAccionMateria(
                  label: 'Entrenar',
                  onTap: () => _entrenarMateriaVelocidad(materia),
                  primario: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildBotonAccionMateria(
                  label: 'Ver detalles',
                  onTap: () => _abrirDetalleMateriaVelocidad(materia),
                  primario: false,
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
                      _mensajeErrorAmigable(_error),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
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
                  Text(
                    'Acciones IA recomendadas',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: const Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 8),
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
                        (_card['resumen'] ??
                                'Aun no hay datos de velocidad para mostrar.')
                            .toString(),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    )
                  else
                    ..._materias.map(_buildMateriaItem),
                  const SizedBox(height: 14),
                  Text(
                    'Preguntas que mas tiempo te quitan',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: const Color(0xFF92400E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildPreguntasLentas(),
                ],
              ),
            ),
    );
  }
}

class _PantallaDetalleVelocidadMateria extends StatefulWidget {
  final String userId;
  final TutorIAPersonalService iaService;
  final String materiaNombre;
  final Map<String, dynamic> materiaStats;
  final double promedioGlobalSegundos;
  final List<Map<String, dynamic>> preguntasLentasIniciales;
  final Future<void> Function(_CoachVelocidadPracticaRequest req)?
  onIniciarPractica;

  const _PantallaDetalleVelocidadMateria({
    required this.userId,
    required this.iaService,
    required this.materiaNombre,
    required this.materiaStats,
    required this.promedioGlobalSegundos,
    this.preguntasLentasIniciales = const <Map<String, dynamic>>[],
    this.onIniciarPractica,
  });

  @override
  State<_PantallaDetalleVelocidadMateria> createState() =>
      _PantallaDetalleVelocidadMateriaState();
}

class _PantallaDetalleVelocidadMateriaState
    extends State<_PantallaDetalleVelocidadMateria> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _preguntasLentas = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _preguntasLentas = widget.preguntasLentasIniciales;
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

  String _estado() {
    final raw = (widget.materiaStats['clasificacion'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;
    final promedio = _toDouble(widget.materiaStats['promedio_segundos']);
    if (promedio < 8) return 'Impulsivo';
    if (promedio <= 20) return 'Optimo';
    return 'Lento';
  }

  Color _colorEstado(String estado) {
    final n = estado.toLowerCase();
    if (n.contains('impuls')) return const Color(0xFFB45309);
    if (n.contains('lent')) return const Color(0xFFB91C1C);
    return const Color(0xFF166534);
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

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final lentas = await widget.iaService.obtenerPreguntasLentasPorMateria(
        userId: widget.userId,
        materia: widget.materiaNombre,
        limit: 10,
      );

      if (!mounted) return;
      setState(() {
        _preguntasLentas = lentas.isNotEmpty ? lentas : _preguntasLentas;
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

  int _cantidadRecomendadaBase() {
    final muestra = _toInt(widget.materiaStats['preguntas']);
    if (muestra >= 80) return 20;
    if (muestra >= 30) return 15;
    return 12;
  }

  int _tiempoRecomendadoBase() {
    final promedio = _toDouble(widget.materiaStats['promedio_segundos']);
    if (promedio > 20) return 30;
    if (promedio < 8) return 25;
    return 20;
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

  String _mensajeErrorAmigable(String? error) {
    final raw = (error ?? '').toLowerCase();
    if (raw.contains('jwt') ||
        raw.contains('auth') ||
        raw.contains('token') ||
        raw.contains('unauthorized') ||
        raw.contains('no autorizado')) {
      return 'Tu sesion expiro. Vuelve a iniciar sesion e intenta de nuevo.';
    }
    if (raw.contains('network') ||
        raw.contains('socket') ||
        raw.contains('timeout') ||
        raw.contains('timed out') ||
        raw.contains('conexion')) {
      return 'No se pudo conectar con el servidor. Revisa tu internet e intenta nuevamente.';
    }
    return 'No pude cargar el detalle de velocidad de esta materia. Intenta nuevamente en unos segundos.';
  }

  Future<void> _emitirPractica({
    required List<String> preguntaIds,
    required bool soloSeleccion,
  }) async {
    final ids = _idsUnicos(preguntaIds);
    final cantidad = ids.isNotEmpty
        ? ids.length
        : (soloSeleccion ? 0 : _cantidadRecomendadaBase());
    if (cantidad <= 0) return;

    await _emitirSolicitudPractica(
      _CoachVelocidadPracticaRequest(
        cantidad: cantidad,
        tiempoMinutos: _tiempoRecomendadoBase(),
        materia: widget.materiaNombre,
        preguntaIdsPrioritarias: ids,
      ),
    );
  }

  Widget _buildKpi({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaLentas() {
    final verdeTema =
        Theme.of(context).appBarTheme.backgroundColor ??
        const Color(0xFF0B5A45);

    if (_preguntasLentas.isEmpty) {
      return Text(
        'No hay preguntas lentas suficientes en esta materia por ahora.',
        style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey.shade700),
      );
    }

    return Column(
      children: _preguntasLentas.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final numero = _toInt(item['numero']);
        final texto = (item['texto'] ?? 'Pregunta').toString().trim();
        final promedio = _toDouble(item['promedio_segundos']);
        final intentos = _toInt(item['intentos']);
        final tasaError = _toDouble(item['tasa_error']);

        return Container(
          margin: EdgeInsets.only(
            bottom: index == _preguntasLentas.length - 1 ? 0 : 8,
          ),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: verdeTema.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '#${index + 1}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: verdeTema,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      numero > 0 ? 'Pregunta $numero' : 'Pregunta',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF334155),
                      ),
                    ),
                  ),
                  Text(
                    '${promedio.toStringAsFixed(1)} seg',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                texto,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0F172A),
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                '$intentos intentos - Error ${tasaError.toStringAsFixed(1)}%',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: const Color(0xFF475569),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final verdeTema =
        Theme.of(context).appBarTheme.backgroundColor ??
        const Color(0xFF0B5A45);
    final promedioMateria = _toDouble(widget.materiaStats['promedio_segundos']);
    final estado = _estado();
    final colorEstado = _colorEstado(estado);
    final muestra = _toInt(widget.materiaStats['preguntas']);
    final acierto = _toDouble(widget.materiaStats['tasa_acierto']);
    final pctImp = _toDouble(widget.materiaStats['pct_impulsiva']);
    final pctOpt = _toDouble(widget.materiaStats['pct_optima']);
    final pctLen = _toDouble(widget.materiaStats['pct_lenta']);
    final global = widget.promedioGlobalSegundos;
    final delta = promedioMateria - global;
    final comparacion = global > 0
        ? (delta.abs() < 0.1
              ? 'Igual a tu promedio global.'
              : (delta > 0
                    ? '${delta.toStringAsFixed(1)} seg mas lento que tu promedio global.'
                    : '${delta.abs().toStringAsFixed(1)} seg mas rapido que tu promedio global.'))
        : 'Sin comparativo global aun.';

    final idsLentas = _idsUnicos(
      _preguntasLentas.map((item) => (item['pregunta_id'] ?? '').toString()),
    );
    final idsCombinadas = _idsUnicos([...idsLentas]);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Velocidad por materia',
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
                      'No pude cargar el detalle de esta materia.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _mensajeErrorAmigable(_error),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colorEstado.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.materiaNombre,
                          style: GoogleFonts.inter(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colorEstado.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                estado.toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: colorEstado,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${promedioMateria.toStringAsFixed(1)} seg/preg',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          comparacion,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = (constraints.maxWidth - 8) / 2;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: width,
                            child: _buildKpi(
                              icon: Icons.timer_outlined,
                              label: 'Promedio',
                              value:
                                  '${promedioMateria.toStringAsFixed(1)} seg',
                              color: verdeTema,
                              background: verdeTema.withValues(alpha: 0.12),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildKpi(
                              icon: Icons.dataset_outlined,
                              label: 'Muestra analizada',
                              value: '$muestra respuestas',
                              color: const Color(0xFF475569),
                              background: const Color(0xFFF1F5F9),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildKpi(
                              icon: Icons.check_circle_outline,
                              label: 'Acierto',
                              value: '${acierto.toStringAsFixed(1)}%',
                              color: const Color(0xFF166534),
                              background: const Color(0xFFF0FDF4),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildKpi(
                              icon: Icons.bolt_rounded,
                              label: 'Impulsiva / Optima / Lenta',
                              value:
                                  '${pctImp.toStringAsFixed(1)}% / ${pctOpt.toStringAsFixed(1)}% / ${pctLen.toStringAsFixed(1)}%',
                              color: const Color(0xFFB45309),
                              background: const Color(0xFFFFF7ED),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _emitirPractica(
                        preguntaIds: idsCombinadas,
                        soloSeleccion: false,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: verdeTema,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Iniciar practica guiada de esta materia',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: idsLentas.isEmpty
                          ? null
                          : () => _emitirPractica(
                              preguntaIds: idsLentas,
                              soloSeleccion: true,
                            ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: verdeTema,
                        side: BorderSide(
                          color: verdeTema.withValues(alpha: 0.45),
                        ),
                      ),
                      child: const Text('Practicar solo preguntas lentas'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Preguntas que mas tiempo te quitan',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF92400E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildListaLentas(),
                ],
              ),
            ),
    );
  }
}
