import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../modelos/modelo_pregunta.dart' show IntentoFallido;
import '../../widgets/barra_superior.dart';
import '../../servicios/servicio_progreso.dart';
import '../pantalla_revision_practica.dart';

class PestanaHistorial extends StatefulWidget {
  final bool esInvitado;

  const PestanaHistorial({super.key, this.esInvitado = false});

  @override
  State<PestanaHistorial> createState() => _PestanaHistorialState();
}

class _PestanaHistorialState extends State<PestanaHistorial> {
  final ServicioProgreso _servicioProgreso = ServicioProgreso();

  int _filtroSeleccionado = 0; // 0: Todas, 1: Ranking, 2: Práctica
  bool _cargandoSeccion = true;

  EstadisticasHistorial _estadisticas = EstadisticasHistorial(
    totalPracticas: 0,
    promedioGeneral: 0.0,
    mejorPuntaje: 0.0,
    aprobadas: 0,
    totalSesiones: 0,
    practicasRanking: 0,
    practicasPersonalizadas: 0,
  );

  EstadisticasHistorial _estadisticasGlobales = EstadisticasHistorial(
    totalPracticas: 0,
    promedioGeneral: 0.0,
    mejorPuntaje: 0.0,
    aprobadas: 0,
    totalSesiones: 0,
    practicasRanking: 0,
    practicasPersonalizadas: 0,
  );

  List<SesionPractica> _sesionesTodas = [];
  List<SesionPractica> _sesiones = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargandoSeccion = true);

    final sesionesTodas = await _servicioProgreso.obtenerHistorialSesiones();
    final estadisticasGlobales = _calcularEstadisticas(sesionesTodas);
    final sesionesFiltradas = _filtrarSesiones(
      sesionesTodas,
      _filtroSeleccionado,
    );
    final estadisticasFiltradas = _calcularEstadisticas(sesionesFiltradas);

    if (mounted) {
      setState(() {
        _sesionesTodas = sesionesTodas;
        _estadisticasGlobales = estadisticasGlobales;
        _sesiones = sesionesFiltradas;
        _estadisticas = estadisticasFiltradas;
        _cargandoSeccion = false;
      });
    }
  }

  List<SesionPractica> _filtrarSesiones(
    List<SesionPractica> sesiones,
    int filtro,
  ) {
    switch (filtro) {
      case 1:
        return sesiones.where((s) => s.cuentaParaRanking).toList();
      case 2:
        return sesiones.where((s) => !s.cuentaParaRanking).toList();
      default:
        return sesiones;
    }
  }

  EstadisticasHistorial _calcularEstadisticas(List<SesionPractica> sesiones) {
    if (sesiones.isEmpty) {
      return EstadisticasHistorial(
        totalPracticas: 0,
        promedioGeneral: 0.0,
        mejorPuntaje: 0.0,
        aprobadas: 0,
        totalSesiones: 0,
        practicasRanking: 0,
        practicasPersonalizadas: 0,
      );
    }

    double suma = 0;
    double mejor = 0;
    int aprobadas = 0;
    int ranking = 0;

    for (final s in sesiones) {
      final p = s.porcentaje;
      suma += p;
      if (p > mejor) mejor = p;
      if (p >= 70) aprobadas++;
      if (s.cuentaParaRanking) ranking++;
    }

    return EstadisticasHistorial(
      totalPracticas: sesiones.length,
      promedioGeneral: suma / sesiones.length,
      mejorPuntaje: mejor,
      aprobadas: aprobadas,
      totalSesiones: sesiones.length,
      practicasRanking: ranking,
      practicasPersonalizadas: sesiones.length - ranking,
    );
  }

  void _cambiarFiltro(int filtro) {
    setState(() {
      _filtroSeleccionado = filtro;
      _sesiones = _filtrarSesiones(_sesionesTodas, filtro);
      _estadisticas = _calcularEstadisticas(_sesiones);
    });
  }

  Future<void> _abrirRevisionFallosSesion(SesionPractica sesion) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    List<IntentoFallido> intentos = const [];
    try {
      intentos = await _servicioProgreso.obtenerPreguntasIncorrectasDeSesion(
        sesionId: sesion.id,
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) return;

    if (intentos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se encontraron preguntas falladas guardadas para esta práctica.',
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaRevisionPractica(
          titulo: 'Preguntas Falladas',
          intentosFallidos: intentos,
          esCorrectas: false,
          mostrarBotonPracticarFallos: true,
        ),
      ),
    );
  }

  String get _tituloSeccion {
    switch (_filtroSeleccionado) {
      case 1:
        return 'Prácticas de Ranking';
      case 2:
        return 'Prácticas Personalizadas';
      default:
        return 'Historial Completo';
    }
  }

  String get _descripcionSeccion {
    switch (_filtroSeleccionado) {
      case 1:
        return 'Prácticas oficiales que cuentan para tu puntaje global (100 preguntas)';
      case 2:
        return 'Prácticas con configuración personalizada (menos preguntas o materias específicas)';
      default:
        return 'Todas las prácticas realizadas hasta el momento';
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: const BarraSuperior(),
      body: RefreshIndicator(
        onRefresh: _cargarDatos,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
                    // Title Header
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Historial de Prácticas',
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.w400,
                              color: Colors.black87,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Revisa tu progreso y evolución',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Info Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Color(0xFF3B82F6),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: widget.esInvitado
                                ? Text(
                                    'Las prácticas se dividen en Para Ranking y De Práctica. ¿Quieres ver tu historial completo y comparar tu posición en el Ranking? Regístrate ahora para desbloquear.',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: const Color(0xFF1E3A8A),
                                      height: 1.4,
                                    ),
                                  )
                                : RichText(
                                    text: TextSpan(
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: const Color(0xFF1E3A8A),
                                        height: 1.4,
                                      ),
                                      children: const [
                                        TextSpan(
                                          text:
                                              'Las prácticas se dividen en dos tipos: ',
                                        ),
                                        TextSpan(
                                          text: 'Para Ranking',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        TextSpan(
                                          text:
                                              ' (100 preguntas con todas las materias) y ',
                                        ),
                                        TextSpan(
                                          text: 'De Práctica',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        TextSpan(
                                          text:
                                              ' (prácticas personalizadas). Ambas ayudan a tu aprendizaje, pero solo las primeras cuentan para el ranking.',
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Filter Tabs
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _cambiarFiltro(0),
                              child: _TabFiltro(
                                texto:
                                    'Todas (${_estadisticasGlobales.totalPracticas})',
                                activo: _filtroSeleccionado == 0,
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _cambiarFiltro(1),
                              child: _TabFiltro(
                                texto:
                                    'Ranking (${_estadisticasGlobales.practicasRanking})',
                                activo: _filtroSeleccionado == 1,
                                icono: Icons.emoji_events_outlined,
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _cambiarFiltro(2),
                              child: _TabFiltro(
                                texto:
                                    'Práctica (${_estadisticasGlobales.practicasPersonalizadas})',
                                activo: _filtroSeleccionado == 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Stats Cards (orden 1)
                    _TarjetaEstadistica(
                      titulo: 'Total de Prácticas',
                      valor: '${_estadisticas.totalPracticas}',
                    ),
                    const SizedBox(height: 16),
                    _TarjetaEstadistica(
                      titulo: 'Promedio General',
                      valor:
                          '${_estadisticas.promedioGeneral.toStringAsFixed(1)}%',
                    ),
                    const SizedBox(height: 16),
                    _TarjetaEstadistica(
                      titulo: 'Mejor Puntaje',
                      valor:
                          '${_estadisticas.mejorPuntaje.toStringAsFixed(1)}%',
                      colorValor: const Color(0xFF10B981),
                    ),
                    const SizedBox(height: 16),
                    _TarjetaEstadistica(
                      titulo: 'Aprobadas',
                      valor:
                          '${_estadisticas.aprobadas}/${_estadisticas.totalSesiones}',
                      colorValor: const Color(0xFF3B82F6),
                    ),

                    const SizedBox(height: 24),


                    // Dynamic Content (List or Empty Message)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _tituloSeccion,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _descripcionSeccion,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_cargandoSeccion)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          else if (_sesiones.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                child: Text(
                                  'No hay prácticas registradas',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ),
                            )
                          else
                            ..._sesiones.map(
                              (s) => _ItemSesion(
                                sesion: s,
                                onTap: widget.esInvitado
                                    ? null
                                    : () => _abrirRevisionFallosSesion(s),
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

class _ItemSesion extends StatelessWidget {
  final SesionPractica sesion;
  final VoidCallback? onTap;

  const _ItemSesion({required this.sesion, this.onTap});

  @override
  Widget build(BuildContext context) {
    final fechaFormato = DateFormat(
      'dd MMM yyyy, HH:mm',
    ).format(sesion.fechaCreacion);
    final porcentaje = sesion.porcentaje;
    final aprobado = porcentaje >= 70;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: aprobado
                      ? const Color(0xFFD1FAE5)
                      : const Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  aprobado ? Icons.check : Icons.close,
                  color: aprobado
                      ? const Color(0xFF059669)
                      : const Color(0xFFDC2626),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${porcentaje.toStringAsFixed(1)}%',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: aprobado
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (sesion.cuentaParaRanking)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.emoji_events,
                                  size: 12,
                                  color: Color(0xFFD97706),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'Ranking',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFD97706),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${sesion.preguntasCorrectas}/${sesion.totalPreguntas} correctas',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      fechaFormato,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey.shade500,
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

class _TarjetaEstadistica extends StatelessWidget {
  final String titulo;
  final String valor;
  final Color? colorValor;

  const _TarjetaEstadistica({
    required this.titulo,
    required this.valor,
    this.colorValor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            titulo,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w400,
              color: colorValor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabFiltro extends StatelessWidget {
  final String texto;
  final bool activo;
  final IconData? icono;

  const _TabFiltro({required this.texto, required this.activo, this.icono});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: activo ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        boxShadow: activo
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(
              icono,
              size: 14,
              color: activo ? Colors.black87 : Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              texto,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: activo ? FontWeight.w600 : FontWeight.w500,
                color: activo ? Colors.black87 : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

