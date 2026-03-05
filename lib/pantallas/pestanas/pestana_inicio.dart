import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../servicios/auth_service.dart';
import '../../servicios/servicio_preguntas.dart';
import '../../servicios/servicio_progreso.dart';
import '../../widgets/barra_superior.dart';
import '../pantalla_login.dart';
import '../pantalla_perfil.dart';
import '../pantalla_plan_tutor_ia_personal.dart';
import '../pantalla_practica.dart';
import '../pantalla_practica_guiada_config.dart';
import '../pantalla_preguntas_acertadas.dart';
import '../pantalla_preguntas_incorrectas.dart';
import '../pantalla_registro.dart';

class PestanaInicio extends StatefulWidget {
  final String categoriaUsuario;
  final bool esInvitado;
  final Function(int)? onTabChange;

  const PestanaInicio({
    super.key,
    required this.categoriaUsuario,
    this.esInvitado = false,
    this.onTabChange,
  });

  @override
  State<PestanaInicio> createState() => _PestanaInicioState();
}

class _PestanaInicioState extends State<PestanaInicio>
    with WidgetsBindingObserver {
  static const int _limitePracticasRankingNoActivo = 3;

  final ServicioPreguntas _servicioPreguntas = ServicioPreguntas();
  final ServicioProgreso _servicioProgreso = ServicioProgreso();

  StreamSubscription? _profileSubscription;

  String _codigoReferido = '';
  int _metaDiariaMinutos = 30;
  bool _perfilCargado = false;
  bool _premiumActivo = false;
  int _rankingPracticasUsadas = 0;
  int _preguntasDisponiblesActuales = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargarDatosUsuario();
    unawaited(
      _servicioPreguntas.precalentarPreguntas(
        categoria: widget.categoriaUsuario,
      ),
    );
    if (!widget.esInvitado) {
      _profileSubscription = AuthService.onProfileUpdated.listen((_) {
        _cargarDatosUsuario();
      });
    }
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.esInvitado && state == AppLifecycleState.resumed) {
      _cargarDatosUsuario();
    }
  }

  bool get _esRegistradoNoActivo =>
      !widget.esInvitado && _perfilCargado && !_premiumActivo;

  int get _rankingPracticasRestantesNoActivo {
    final restantes = _limitePracticasRankingNoActivo - _rankingPracticasUsadas;
    return restantes < 0 ? 0 : restantes;
  }

  String get _mensajeEstadoCorto {
    if (widget.esInvitado) {
      return 'Registra tu cuenta para ranking y tutor IA.';
    }
    if (!_esRegistradoNoActivo) {
      return 'Cuenta activa: modo completo habilitado.';
    }

    final detalle = _preguntasDisponiblesActuales > 0
        ? ' $_preguntasDisponiblesActuales preguntas habilitadas.'
        : '';

    if (_rankingPracticasRestantesNoActivo > 0) {
      return 'No activa: quedan $_rankingPracticasRestantesNoActivo/3 ranking.$detalle';
    }

    return 'No activa: ranking agotado.$detalle';
  }

  Future<void> _cargarDatosUsuario() async {
    if (widget.esInvitado) {
      await _servicioProgreso.obtenerEstadisticasPreguntas();

      if (!mounted) return;
      setState(() {
        _codigoReferido = '';
        _metaDiariaMinutos = 30;
        _perfilCargado = true;
        _premiumActivo = false;
        _rankingPracticasUsadas = 0;
        _preguntasDisponiblesActuales = 0;
      });
      return;
    }

    final perfilFuture = AuthService.getCurrentUserProfile();
    final rankingUsadasFuture = _servicioProgreso
        .obtenerCantidadPracticasRanking();

    final perfil = await perfilFuture;
    final premiumActivo = perfil?['premium'] == true;
    final rankingUsadas = await rankingUsadasFuture;
    final preguntasDisponibles = premiumActivo
        ? 0
        : await _servicioPreguntas.contarPreguntasDisponibles(
            categoria: widget.categoriaUsuario,
          );

    if (!mounted) return;

    setState(() {
      _codigoReferido = (perfil?['codigo_referido'] as String? ?? '')
          .trim()
          .toUpperCase();
      _metaDiariaMinutos = perfil?['meta_diaria_minutos'] as int? ?? 30;
      _premiumActivo = premiumActivo;
      _rankingPracticasUsadas = rankingUsadas;
      _preguntasDisponiblesActuales = preguntasDisponibles;
      _perfilCargado = true;
    });
  }

  void _abrirLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PantallaLogin()),
    );
  }

  void _abrirRegistro() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PantallaRegistro()),
    );
  }

  void _abrirActivacionCuenta() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PantallaPerfil()),
    );
  }

  void _mostrarAvisoTutorInvitado() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tutor IA Personal'),
          content: const Text(
            'Para usar el Tutor IA Personal primero debes iniciar sesion o registrarte.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
                _abrirLogin();
              },
              child: const Text('Iniciar sesion'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _abrirRegistro();
              },
              child: const Text('Registrarse'),
            ),
          ],
        );
      },
    );
  }

  void _irTab(int indice) {
    widget.onTabChange?.call(indice);
  }

  Future<void> _iniciarRutinaDiaria() async {
    final int cantidad = (((_metaDiariaMinutos * 100) / 120).round()).clamp(
      10,
      100,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final preguntas = await _servicioPreguntas.obtenerPreguntasAleatorias(
        cantidad: cantidad,
        categoria: widget.categoriaUsuario,
      );

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
            tiempoLimiteSegundos: _metaDiariaMinutos * 60,
            preguntas: preguntas,
            esModoPractica: false,
          ),
        ),
      );

      _cargarDatosUsuario();
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.pop(context);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al iniciar rutina: $e')));
      }
    }
  }

  Future<void> _abrirPracticaGuiada() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PantallaPracticaGuiadaConfig(
          categoriaUsuario: widget.categoriaUsuario,
        ),
      ),
    );
    _cargarDatosUsuario();
  }

  Future<void> _abrirTutorIA() async {
    if (widget.esInvitado) {
      _mostrarAvisoTutorInvitado();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PantallaPlanTutorIAPersonal(),
      ),
    );
  }

  Future<void> _abrirAcertadas() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PantallaPreguntasAcertadas()),
    );
    _cargarDatosUsuario();
  }

  Future<void> _abrirIncorrectas() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PantallaPreguntasIncorrectas()),
    );
    _cargarDatosUsuario();
  }

  void _copiarCodigoReferido() {
    if (_codigoReferido.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _codigoReferido));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Codigo copiado')));
  }

  List<_TarjetaInicioItem> _tarjetasInicio() {
    return [
      _TarjetaInicioItem(
        titulo: 'Banco de preguntas',
        descripcion: 'Refuerza lo que mas te cuesta.',
        icono: Icons.menu_book_rounded,
        color: const Color(0xFF059669),
        onTap: () async => _irTab(1),
      ),
      _TarjetaInicioItem(
        titulo: 'Simulador de examen',
        descripcion: 'Entrena como en el examen real.',
        icono: Icons.fact_check_rounded,
        color: const Color(0xFF2563EB),
        onTap: () async => _irTab(2),
      ),
      _TarjetaInicioItem(
        titulo: 'Practica guiada',
        descripcion: 'Aprende paso a paso con feedback.',
        icono: Icons.school_outlined,
        color: const Color(0xFF9333EA),
        onTap: _abrirPracticaGuiada,
      ),
      _TarjetaInicioItem(
        titulo: 'Tutor IA personal',
        descripcion: 'Resuelve dudas al instante.',
        icono: Icons.psychology_alt_outlined,
        color: const Color(0xFFEA580C),
        onTap: _abrirTutorIA,
      ),
      _TarjetaInicioItem(
        titulo: 'Rutina diaria',
        descripcion: 'Cumple tu meta y sube nivel.',
        icono: Icons.play_circle_outline_rounded,
        color: const Color(0xFF4F46E5),
        onTap: _iniciarRutinaDiaria,
      ),
      _TarjetaInicioItem(
        titulo: 'Preguntas no acertadas',
        descripcion: 'Corrige fallos y mejora rapido.',
        icono: Icons.cancel_outlined,
        color: const Color(0xFFDC2626),
        onTap: _abrirIncorrectas,
      ),
      _TarjetaInicioItem(
        titulo: 'Preguntas acertadas',
        descripcion: 'Refuerza tus fortalezas clave.',
        icono: Icons.check_circle_outline,
        color: const Color(0xFF16A34A),
        onTap: _abrirAcertadas,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimario = Theme.of(context).colorScheme.primary;
    final colorSecundario = Theme.of(context).colorScheme.secondary;
    final tarjetas = _tarjetasInicio();
    final tituloCabecera = widget.categoriaUsuario.toUpperCase();
    final subtituloCabecera = (!widget.esInvitado && _codigoReferido.isNotEmpty)
        ? 'CÓDIGO DE REFERIDO: $_codigoReferido'
        : 'CÓDIGO DE REFERIDO: SIN CÓDIGO';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: const BarraSuperior(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colorPrimario, colorSecundario],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            tituloCabecera,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                              height: 0.95,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap:
                              (!widget.esInvitado && _codigoReferido.isNotEmpty)
                              ? _copiarCodigoReferido
                              : null,
                          child: Text(
                            subtituloCabecera,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (!widget.esInvitado && _codigoReferido.isNotEmpty) ...[
                        const SizedBox(width: 2),
                        InkWell(
                          onTap: _copiarCodigoReferido,
                          borderRadius: BorderRadius.circular(999),
                          child: const Padding(
                            padding: EdgeInsets.all(1),
                            child: Icon(
                              Icons.content_copy_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: widget.esInvitado
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _abrirLogin,
                                icon: const Icon(Icons.login_rounded, size: 16),
                                label: Text(
                                  'Iniciar sesion',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF1D4ED8),
                                  side: const BorderSide(
                                    color: Color(0xFF93C5FD),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _abrirRegistro,
                                icon: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  'Registrarse',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1D4ED8),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        const Icon(
                          Icons.emoji_events_outlined,
                          size: 16,
                          color: Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _mensajeEstadoCorto,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: const Color(0xFF1E3A8A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_esRegistradoNoActivo)
                          SizedBox(
                            height: 28,
                            child: ElevatedButton(
                              onPressed: _abrirActivacionCuenta,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1D4ED8),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                'Activar',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: tarjetas.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.22,
              ),
              itemBuilder: (context, index) {
                return _TarjetaInicioCuadricula(item: tarjetas[index]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaInicioItem {
  final String titulo;
  final String descripcion;
  final IconData icono;
  final Color color;
  final Future<void> Function() onTap;

  const _TarjetaInicioItem({
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.color,
    required this.onTap,
  });
}

class _TarjetaInicioCuadricula extends StatelessWidget {
  final _TarjetaInicioItem item;

  const _TarjetaInicioCuadricula({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD1D5DB)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.icono, color: item.color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                item.titulo.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: const Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.descripcion,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  color: const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
