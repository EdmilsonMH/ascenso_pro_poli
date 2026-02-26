import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../servicios/servicio_ranking.dart';
import '../../servicios/supabase_service.dart';
import '../../widgets/barra_superior.dart';
import '../pantalla_login.dart';
import '../pantalla_registro.dart';

class PestanaRanking extends StatefulWidget {
  final int refreshToken;
  final bool esInvitado;

  const PestanaRanking({
    super.key,
    this.refreshToken = 0,
    this.esInvitado = false,
  });

  @override
  State<PestanaRanking> createState() => _PestanaRankingState();
}

class _PestanaRankingState extends State<PestanaRanking> {
  final ServicioRanking _servicioRanking = ServicioRanking();
  final TextEditingController _diasController = TextEditingController(text: '7');
  RealtimeChannel? _rankingRealtimeChannel;
  Timer? _realtimeRefreshDebounce;
  bool _cargandoRanking = false;

  List<RankingUsuario> _topRanking = [];
  RankingUsuario? _miPosicion;
  int _misPracticas = 0;
  bool _cargando = true;

  PeriodoRanking _periodoSeleccionado = PeriodoRanking.ultimaPractica;
  CriterioRanking _criterioSeleccionado = CriterioRanking.promedio;
  int _diasPersonalizados = 7;

  @override
  void initState() {
    super.initState();
    _cargarRanking();
    if (!widget.esInvitado) {
      _suscribirseCambiosRanking();
    }
  }

  @override
  void didUpdateWidget(covariant PestanaRanking oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.esInvitado && oldWidget.esInvitado) {
      _suscribirseCambiosRanking();
    } else if (widget.esInvitado && !oldWidget.esInvitado) {
      _desuscribirseCambiosRanking();
    }

    if (widget.refreshToken != oldWidget.refreshToken ||
        widget.esInvitado != oldWidget.esInvitado) {
      _cargarRanking(silencioso: true);
    }
  }

  @override
  void dispose() {
    _realtimeRefreshDebounce?.cancel();
    _desuscribirseCambiosRanking();
    _diasController.dispose();
    super.dispose();
  }

  Future<void> _cargarRanking({bool silencioso = false}) async {
    if (_cargandoRanking) return;
    _cargandoRanking = true;

    if (mounted) {
      if (!silencioso || _topRanking.isEmpty) {
        setState(() {
          _cargando = true;
        });
      }
    }
    try {
      final resultado = await _servicioRanking.obtenerRankingPeriodo(
        periodo: _periodoSeleccionado,
        criterio: _criterioSeleccionado,
        diasPersonalizados: _diasPersonalizados,
        limiteTop: 100,
      );

      if (!mounted) return;
      setState(() {
        _topRanking = resultado.topRanking;
        _miPosicion = resultado.miPosicion;
        _misPracticas = resultado.misPracticas;
        _cargando = false;
      });
    } catch (e) {
      debugPrint('PestanaRanking._cargarRanking error: $e');
      if (!mounted) return;
      setState(() {
        _topRanking = [];
        _miPosicion = null;
        _misPracticas = 0;
        _cargando = false;
      });
    } finally {
      _cargandoRanking = false;
    }
  }

  void _suscribirseCambiosRanking() {
    if (!SupabaseService.isInitialized) return;
    _desuscribirseCambiosRanking();

    _rankingRealtimeChannel = SupabaseService.client
        .channel('ranking-sesion-practica-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sesion_practica',
          callback: (_) {
            _programarRefreshRealtime();
          },
        )
        .subscribe();
  }

  void _desuscribirseCambiosRanking() {
    final channel = _rankingRealtimeChannel;
    _rankingRealtimeChannel = null;
    if (channel != null && SupabaseService.isInitialized) {
      SupabaseService.client.removeChannel(channel);
    }
  }

  void _programarRefreshRealtime() {
    _realtimeRefreshDebounce?.cancel();
    _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      _cargarRanking(silencioso: true);
    });
  }

  void _seleccionarPeriodo(PeriodoRanking periodo) {
    setState(() {
      _periodoSeleccionado = periodo;
      _criterioSeleccionado = periodo == PeriodoRanking.mejorPuntaje
          ? CriterioRanking.puntuacionMasAlta
          : CriterioRanking.promedio;
    });

    if (periodo != PeriodoRanking.diasPersonalizados) {
      _cargarRanking(silencioso: true);
    }
  }

  void _aplicarDiasPersonalizados() {
    final parsed = int.tryParse(_diasController.text.trim());
    if (parsed == null || parsed < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un número de días válido.')),
      );
      return;
    }

    setState(() {
      _diasPersonalizados = parsed;
    });
    _cargarRanking(silencioso: true);
  }

  String _periodoActualLabel() {
    if (_periodoSeleccionado == PeriodoRanking.diasPersonalizados) {
      return 'Últimos $_diasPersonalizados días';
    }
    return _periodoSeleccionado.etiqueta;
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: const BarraSuperior(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final top3 = _topRanking.take(3).toList();
    final resto = _topRanking.skip(3).toList();
    final periodoLabel = _periodoActualLabel();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: const BarraSuperior(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Center(
              child: Column(
                children: [
                  Text(
                    'Ranking de Usuarios',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w400,
                      color: Colors.black87,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            if (_cargandoRanking) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Color(0xFFE5E7EB),
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _buildFiltroPeriodoCard(),
            const SizedBox(height: 24),
            if (widget.esInvitado) _buildAvisoInvitadoCard(),
            if (!widget.esInvitado && _miPosicion != null)
              _buildMiPosicionCard(periodoLabel),
            if (!widget.esInvitado && _miPosicion == null)
              _buildSinMiPosicionCard(),
            const SizedBox(height: 32),
            if (top3.isEmpty && resto.isEmpty) ...[
              _buildSinDatosCard(),
              const SizedBox(height: 24),
            ],
            if (top3.isNotEmpty)
              ...top3.map(
                (u) => Column(
                  children: [
                    _TarjetaTopUser(
                      usuario: u,
                      criterio: _criterioSeleccionado,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            if (resto.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ranking Completo',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      _descripcionOrdenActual(),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...resto.map(
                (u) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ItemRanking(
                    usuario: u,
                    criterio: _criterioSeleccionado,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvisoInvitadoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline, color: Color(0xFF2563EB), size: 30),
          const SizedBox(height: 12),
          Text(
            'Estás en modo invitado',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Puedes ver el ranking de otros usuarios, pero no aparecerás en el ranking '
            'hasta iniciar sesión o registrarte.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PantallaLogin()),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1D4ED8),
                    side: const BorderSide(color: Color(0xFF1D4ED8)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Iniciar sesión'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PantallaRegistro()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D4ED8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Registrarse'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroPeriodoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6E7FF)),
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
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _buildPeriodoTile(
                      periodo: PeriodoRanking.ultimaPractica,
                      titulo: 'Última práctica',
                      icono: Icons.flag_outlined,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildPeriodoTile(
                      periodo: PeriodoRanking.semana,
                      titulo: 'Última semana',
                      icono: Icons.date_range_outlined,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildPeriodoTile(
                      periodo: PeriodoRanking.mes,
                      titulo: 'Último mes',
                      icono: Icons.calendar_month_outlined,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildPeriodoTile(
                      periodo: PeriodoRanking.diasPersonalizados,
                      titulo: 'Últimos N días',
                      icono: Icons.tune,
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth,
                    child: _buildPeriodoTile(
                      periodo: PeriodoRanking.mejorPuntaje,
                      titulo: 'Mejor puntaje',
                      icono: Icons.emoji_events_outlined,
                    ),
                  ),
                ],
              );
            },
          ),
          if (_periodoSeleccionado == PeriodoRanking.diasPersonalizados) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _diasController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Días',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _aplicarDiasPersonalizados,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Aplicar'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Ejemplo: 2 = se comparan los últimos 2 días de todos los usuarios.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _buildDetallePeriodos(),
          const SizedBox(height: 8),
          Text(
            'Todos los usuarios se comparan con el mismo período seleccionado.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodoTile({
    required PeriodoRanking periodo,
    required String titulo,
    required IconData icono,
  }) {
    final selected = _periodoSeleccionado == periodo;
    return Material(
      color: selected ? const Color(0xFFEEF5FF) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _seleccionarPeriodo(periodo),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF93C5FD) : Colors.grey.shade300,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icono,
                    size: 16,
                    color: selected ? const Color(0xFF1D4ED8) : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      titulo,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? const Color(0xFF1D4ED8)
                            : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetallePeriodos() {
    final detalle = _detallePeriodoSeleccionado();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Detalle',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '- $detalle',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  String _detallePeriodoSeleccionado() {
    switch (_periodoSeleccionado) {
      case PeriodoRanking.ultimaPractica:
        return 'Última práctica: compara la última práctica válida de cada usuario.';
      case PeriodoRanking.semana:
        return 'Última semana: suma prácticas válidas de los últimos 7 días.';
      case PeriodoRanking.mes:
        return 'Último mes: suma prácticas válidas de los últimos 30 días.';
      case PeriodoRanking.diasPersonalizados:
        return 'Últimos N días: suma prácticas válidas de los últimos $_diasPersonalizados días.';
      case PeriodoRanking.mejorPuntaje:
        return 'Mejor puntaje: toma el mejor resultado de todas las prácticas válidas de ranking de cada usuario.';
    }
  }

  String _descripcionOrdenActual() {
    if (_criterioSeleccionado == CriterioRanking.puntuacionMasAlta) {
      return 'Ordenado por puntaje más alto (histórico), efectividad y última práctica válida';
    }
    return 'Ordenado por promedio por práctica, efectividad y última práctica válida';
  }

  Widget _buildMiPosicionCard(String periodoLabel) {
    final usarPuntajeMasAlto =
        _criterioSeleccionado == CriterioRanking.puntuacionMasAlta;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3B82F6)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.verified_outlined,
                      color: Color(0xFF2563EB),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Tu posición actual',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: const Color(0xFF1E40AF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    periodoLabel,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '#${_miPosicion!.posicion}',
                  style: GoogleFonts.inter(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            usarPuntajeMasAlto
                                ? 'Puntaje más alto'
                                : 'Promedio',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            usarPuntajeMasAlto
                                ? _miPosicion!.puntajeMaximo.toStringAsFixed(0)
                                : _miPosicion!.puntosTotales.toStringAsFixed(2),
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Efectividad',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_miPosicion!.porcentajeAciertos.toStringAsFixed(1)}%',
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Prácticas',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_misPracticas',
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_misPracticas == 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF9C3),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(15),
                ),
                border: Border(
                  top: BorderSide(color: Colors.yellow.shade200),
                ),
              ),
              child: Text(
                'Aún no tienes prácticas válidas en este período.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF854D0E),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSinDatosCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        'No hay resultados para este periodo con las reglas de ranking.',
        style: GoogleFonts.inter(
          fontSize: 13,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildSinMiPosicionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        'Aún no apareces en ranking para este período. '
        'Necesitas prácticas válidas de ranking para figurar.',
        style: GoogleFonts.inter(
          fontSize: 13,
          color: const Color(0xFF1E40AF),
        ),
      ),
    );
  }
}

class _TarjetaTopUser extends StatelessWidget {
  final RankingUsuario usuario;
  final CriterioRanking criterio;

  const _TarjetaTopUser({required this.usuario, required this.criterio});

  Color get _colorTema {
    switch (usuario.posicion) {
      case 1:
        return const Color(0xFFEAB308);
      case 2:
        return const Color(0xFF94A3B8);
      case 3:
        return const Color(0xFFF97316);
      default:
        return Colors.grey;
    }
  }

  String get _iniciales {
    if (usuario.nombreCompleto.isEmpty) return 'U';
    final parts = usuario.nombreCompleto.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0].substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final usarPuntajeMasAlto = criterio == CriterioRanking.puntuacionMasAlta;
    final valorPrincipal = usarPuntajeMasAlto
        ? usuario.puntajeMaximo.toStringAsFixed(0)
        : usuario.puntosTotales.toStringAsFixed(2);
    final etiquetaPrincipal = usarPuntajeMasAlto
        ? 'Puntaje más alto'
        : 'Promedio por practica';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(top: BorderSide(color: _colorTema, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Icon(Icons.emoji_events_outlined, color: _colorTema, size: 24),
          const SizedBox(height: 12),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _colorTema,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _iniciales,
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            usuario.nombreCompleto,
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          Text(
            'Puesto #${usuario.posicion}',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Text(
                      valorPrincipal,
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      etiquetaPrincipal,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ItemRanking extends StatelessWidget {
  final RankingUsuario usuario;
  final CriterioRanking criterio;

  const _ItemRanking({required this.usuario, required this.criterio});

  String get _iniciales {
    if (usuario.nombreCompleto.isEmpty) return 'U';
    final parts = usuario.nombreCompleto.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0].substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final usarPuntajeMasAlto = criterio == CriterioRanking.puntuacionMasAlta;
    final valorPrincipal = usarPuntajeMasAlto
        ? usuario.puntajeMaximo.toStringAsFixed(0)
        : usuario.puntosTotales.toStringAsFixed(2);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '#${usuario.posicion}',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _iniciales,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  usuario.nombreCompleto,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  usuario.categoria,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                valorPrincipal,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              Text(
                '${usuario.porcentajeAciertos.toStringAsFixed(1)}%',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


