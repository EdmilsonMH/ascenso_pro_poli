part of 'pantalla_plan_tutor_ia_personal.dart';

class _PantallaProyeccionTiempo extends StatefulWidget {
  final String userId;
  final String? categoriaUsuario;
  final TutorIAPersonalService iaService;
  final TutorInsightCard card;

  const _PantallaProyeccionTiempo({
    required this.userId,
    this.categoriaUsuario,
    required this.iaService,
    required this.card,
  });

  @override
  State<_PantallaProyeccionTiempo> createState() =>
      _PantallaProyeccionTiempoState();
}

class _PantallaProyeccionTiempoState extends State<_PantallaProyeccionTiempo> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _data = const <String, dynamic>{};

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

  int? _toOptionalInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double? _toOptionalDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _formatearRitmoEntero(double? valor, {bool redondearArriba = false}) {
    if (valor == null) return '--';
    final entero = redondearArriba ? valor.ceil() : valor.round();
    return '$entero/dia';
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final data = await widget.iaService.obtenerProyeccionTiempoDetalle(
        userId: widget.userId,
        categoriaUsuario: widget.categoriaUsuario,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
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

  Color _colorSemaforo(String estado) {
    switch (estado) {
      case 'completado':
        return const Color(0xFF0B5A45);
      case 'en_ritmo':
        return const Color(0xFF237D57);
      case 'justo':
        return const Color(0xFFB54708);
      case 'atrasado':
        return const Color(0xFFC63D4D);
      case 'sin_datos':
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _iconSemaforo(String estado) {
    switch (estado) {
      case 'completado':
        return Icons.task_alt_rounded;
      case 'en_ritmo':
        return Icons.trending_up_rounded;
      case 'justo':
        return Icons.timelapse_rounded;
      case 'atrasado':
        return Icons.warning_amber_rounded;
      case 'sin_datos':
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _descripcionSemaforo(String estado) {
    switch (estado) {
      case 'completado':
        return 'Ya alcanzaste el objetivo global de preguntas dominadas.';
      case 'en_ritmo':
        return 'Tu ritmo actual alcanza o supera el ritmo necesario.';
      case 'justo':
        return 'Vas cerca del ritmo objetivo, pero con poco margen.';
      case 'atrasado':
        return 'Tu ritmo actual esta por debajo de lo requerido.';
      case 'sin_datos':
      default:
        return 'Aun no hay ritmo calculable para una proyeccion confiable.';
    }
  }

  Widget _buildMetrica({
    required String titulo,
    required String valor,
    Color? colorValor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: colorValor ?? const Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resumen = (_data['resumen'] ?? widget.card.resumen).toString().trim();
    final detalle = (_data['detalle'] ?? widget.card.detalle).toString().trim();
    final totalObjetivo = _toOptionalInt(_data['total_preguntas_objetivo']);
    final dominadas = _toInt(_data['preguntas_dominadas']);
    final faltantes = _toOptionalInt(_data['preguntas_faltantes']);
    final porcentaje = _toOptionalDouble(_data['porcentaje_completado']);
    final ritmoActual = _toOptionalDouble(_data['ritmo_actual_dia']);
    final ritmoNecesario = _toOptionalDouble(_data['ritmo_necesario_dia']);
    final brecha = _toOptionalDouble(_data['brecha_dia']);
    final diasEstimados = _toOptionalInt(_data['dias_estimados_completar']);
    final fechaEstimada = (_data['fecha_estimada_listo'] ?? '')
        .toString()
        .trim();
    final fechaExamen = (_data['fecha_examen'] ?? '').toString().trim();
    final diasRestantesExamen = _toOptionalInt(_data['dias_restantes_examen']);
    final probAprob = _toOptionalDouble(_data['probabilidad_aprobacion']);
    final ritmoSuficiente = _data['ritmo_suficiente'] == true;
    final semaforo = (_data['semaforo_avance'] ?? 'sin_datos')
        .toString()
        .trim()
        .toLowerCase();
    final labelSemaforo = (_data['label_semaforo'] ?? 'Sin datos')
        .toString()
        .trim();
    final colorSemaforo = _colorSemaforo(semaforo);
    final progreso = ((porcentaje ?? 0.0) / 100).clamp(0.0, 1.0);
    final colorHeader =
        Theme.of(context).appBarTheme.backgroundColor ??
        Theme.of(context).colorScheme.primary;
    final colorResumenInicio =
        Color.lerp(colorHeader, Colors.white, 0.32) ?? colorHeader;
    final colorResumenFin =
        Color.lerp(colorHeader, Colors.black, 0.04) ?? colorHeader;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Proyeccion de Tiempo',
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 30,
                      color: Colors.red.shade300,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No se pudo cargar la proyeccion de tiempo.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colorResumenInicio, colorResumenFin],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: colorHeader.withValues(alpha: 0.22),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Proyeccion de tiempo para completar',
                          style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          resumen.isEmpty
                              ? 'Aun no hay datos suficientes para proyectar.'
                              : resumen,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            height: 1.35,
                            color: Colors.white.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: colorSemaforo.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _iconSemaforo(semaforo),
                                size: 16,
                                color: colorSemaforo,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                'Semaforo: $labelSemaforo',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: colorSemaforo,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (detalle.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      detalle,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Avance total',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                            ),
                            Text(
                              porcentaje == null
                                  ? '--'
                                  : '${porcentaje.toStringAsFixed(1)}%',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0B5A45),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progreso,
                            minHeight: 8,
                            backgroundColor: const Color(0xFFE5E7EB),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF0B5A45),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!ritmoSuficiente && (faltantes ?? 0) > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Text(
                        'Aun no hay ritmo suficiente para calcular una fecha estimada confiable.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: const Color(0xFF92400E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    'Metricas clave',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const spacing = 10.0;
                      final width = (constraints.maxWidth - spacing) / 2;
                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: [
                          SizedBox(
                            width: width,
                            child: _buildMetrica(
                              titulo: 'Fecha estimada',
                              valor: fechaEstimada.isEmpty
                                  ? '--'
                                  : fechaEstimada,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetrica(
                              titulo: 'Dias estimados',
                              valor: diasEstimados == null
                                  ? '--'
                                  : '$diasEstimados dias',
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetrica(
                              titulo: 'Dominadas',
                              valor:
                                  (totalObjetivo != null && totalObjetivo > 0)
                                  ? '$dominadas/$totalObjetivo'
                                  : '$dominadas',
                              colorValor: const Color(0xFF237D57),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetrica(
                              titulo: 'Faltantes',
                              valor: faltantes == null ? '--' : '$faltantes',
                              colorValor: const Color(0xFFB54708),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetrica(
                              titulo: 'Ritmo actual',
                              valor: _formatearRitmoEntero(ritmoActual),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetrica(
                              titulo: 'Ritmo necesario',
                              valor: _formatearRitmoEntero(
                                ritmoNecesario,
                                redondearArriba: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetrica(
                              titulo: 'Brecha diaria',
                              valor: _formatearRitmoEntero(brecha),
                              colorValor: (brecha ?? 0) > 0
                                  ? const Color(0xFFC63D4D)
                                  : const Color(0xFF237D57),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetrica(
                              titulo: 'Probabilidad',
                              valor: probAprob == null
                                  ? '--'
                                  : '${probAprob.toStringAsFixed(1)}%',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  if (fechaExamen.isNotEmpty ||
                      diasRestantesExamen != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Examen objetivo',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            fechaExamen.isEmpty
                                ? 'Fecha no registrada'
                                : 'Fecha: $fechaExamen',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          Text(
                            diasRestantesExamen == null
                                ? 'Dias restantes: --'
                                : 'Dias restantes: $diasRestantesExamen',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorSemaforo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorSemaforo.withValues(alpha: 0.38),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _iconSemaforo(semaforo),
                          color: colorSemaforo,
                          size: 20,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Estado: $labelSemaforo',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: colorSemaforo,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _descripcionSemaforo(semaforo),
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: Colors.grey.shade800,
                                  height: 1.3,
                                ),
                              ),
                            ],
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



