import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../tema/tema_aplicacion.dart';
import '../pantalla_preguntas_acertadas.dart';
import '../pantalla_preguntas_incorrectas.dart';
import '../pantalla_login.dart';
import '../pantalla_perfil.dart';

import '../pantalla_practica.dart';
import '../pantalla_practica_guiada_config.dart';
import '../pantalla_registro.dart';
import '../../widgets/barra_superior.dart';
import '../../servicios/auth_service.dart';
import '../../servicios/servicio_preguntas.dart';
import '../../servicios/servicio_progreso.dart';
import '../pantalla_plan_tutor_ia_personal.dart';

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
  String _nombreUsuario = '';

  String _codigoReferido = '';
  int _metaDiariaMinutos = 30; // Valor por defecto
  int _preguntasCorrectasCount = 0;
  int _preguntasIncorrectasCount = 0;
  int _preguntasTotalesCount = 0;
  bool _cargandoStats = true;
  bool _perfilCargado = false;
  bool _premiumActivo = false;
  int _rankingPracticasUsadas = 0;
  int _preguntasDisponiblesActuales = 0;

  final ServicioPreguntas _servicioPreguntas = ServicioPreguntas();
  final ServicioProgreso _servicioProgreso = ServicioProgreso();

  StreamSubscription? _profileSubscription;

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
    // Recargar datos cuando la app vuelve a primer plano
    if (!widget.esInvitado && state == AppLifecycleState.resumed) {
      _cargarDatosUsuario();
    }
  }

  bool get _esRegistradoNoActivo =>
      !widget.esInvitado && _perfilCargado && !_premiumActivo;

  int get _rankingPracticasRestantesNoActivo {
    final restantes =
        _limitePracticasRankingNoActivo - _rankingPracticasUsadas;
    return restantes < 0 ? 0 : restantes;
  }

  String get _mensajeBannerRanking {
    if (widget.esInvitado) {
      return '¿Quieres un mentor a tu lado? Regístrate y desbloquea tu IA Tutor Personal para resolver dudas al instante, dominar cada tema a tu ritmo y acceder a muchas otras funciones diseñadas para asegurar tu ascenso. ¡Hay mucho más esperándote al crear tu cuenta!';
    }

    if (!_perfilCargado) {
      return 'Sistema de Ranking: Para que tu práctica cuente para el ranking, debes completar 100 preguntas con todas las materias. Las prácticas personalizadas (menos preguntas o materias específicas) no cuentan para el ranking pero sí mejoran tu progreso.';
    }

    if (!_esRegistradoNoActivo) {
      return 'Sistema de Ranking: Para que tu práctica cuente para el ranking, debes completar 100 preguntas con todas las materias. Las prácticas personalizadas (menos preguntas o materias específicas) no cuentan para el ranking pero sí mejoran tu progreso.';
    }

    final detalleAcceso = _preguntasDisponiblesActuales > 0
        ? ' Actualmente tienes acceso a $_preguntasDisponiblesActuales preguntas.'
        : '';

    if (_rankingPracticasRestantesNoActivo > 0) {
      return 'Cuenta no activa: accedes a 50 preguntas por materia.$detalleAcceso Te quedan $_rankingPracticasRestantesNoActivo de 3 prácticas ranking (100 preguntas con todas las materias). Activa tu cuenta para desbloquear todas las preguntas y ranking ilimitado.';
    }

    return 'Cuenta no activa: accedes a 50 preguntas por materia.$detalleAcceso Ya usaste tus 3 prácticas ranking. Activa tu cuenta para desbloquear todas las preguntas y volver a competir en el ranking.';
  }

  Future<void> _cargarDatosUsuario() async {
    if (widget.esInvitado) {
      final estadisticas = await _servicioProgreso.obtenerEstadisticasPreguntas();
      final total = estadisticas.length;

      if (!mounted) return;
      setState(() {
        _nombreUsuario = 'Invitado';
        _codigoReferido = '';
        _metaDiariaMinutos = 30;
        _preguntasIncorrectasCount = estadisticas.values
            .where((s) => s.estaEnIncorrectas)
            .length;
        _preguntasCorrectasCount = estadisticas.values
            .where((s) => s.estaEnAcertadas)
            .length;
        _preguntasTotalesCount = total;
        _cargandoStats = false;
        _perfilCargado = true;
        _premiumActivo = false;
        _rankingPracticasUsadas = 0;
        _preguntasDisponiblesActuales = 0;
      });
      return;
    }

    final perfilFuture = AuthService.getCurrentUserProfile();
    final estadisticasFuture = _servicioProgreso.obtenerEstadisticasPreguntas();
    final rankingUsadasFuture = _servicioProgreso.obtenerCantidadPracticasRanking();

    final perfil = await perfilFuture;
    final estadisticas = await estadisticasFuture;
    final premiumActivo = perfil?['premium'] == true;
    final rankingUsadas = await rankingUsadasFuture;
    final preguntasDisponibles = premiumActivo
        ? 0
        : await _servicioPreguntas.contarPreguntasDisponibles(
            categoria: widget.categoriaUsuario,
          );

    // Para totales, podriamos sumar ambas listas, o consultar DB.
    // Por simplicidad, sumamos lo que tenemos + preguntas 'mixtas' si hubiera,
    // pero lo mejor es contar intentos totales.
    // Vamos a mostrar lo que tenemos en cache:
    final total = estadisticas.length;

    if (mounted) {
      setState(() {
        final nombreCompleto = perfil?['nombre_completo'] as String? ?? '';
        _nombreUsuario = nombreCompleto.isNotEmpty
            ? nombreCompleto.split(' ').first
            : '';

        _codigoReferido =
            (perfil?['codigo_referido'] as String? ?? '').trim().toUpperCase();

        _metaDiariaMinutos = perfil?['meta_diaria_minutos'] as int? ?? 30;
        _premiumActivo = premiumActivo;
        _rankingPracticasUsadas = rankingUsadas;
        _preguntasDisponiblesActuales = preguntasDisponibles;
        _perfilCargado = true;

        _preguntasIncorrectasCount = estadisticas.values
            .where((s) => s.estaEnIncorrectas)
            .length;
        _preguntasCorrectasCount = estadisticas.values
            .where((s) => s.estaEnAcertadas)
            .length;
        _preguntasTotalesCount = total;
        _cargandoStats = false;
      });
    }
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

  Future<void> _iniciarPractica({
    required int cantidad,
    required String categoria,
    required int tiempoLimite,
    bool esModoPractica = false,
    bool avanzarSoloConBotonEnPractica = false,
    bool revisarRespuestaInmediata = false,
    bool registrarSesionEnHistorial = true,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final preguntas = await _servicioPreguntas.obtenerPreguntasAleatorias(
        cantidad: cantidad,
        categoria: categoria,
      );

      if (!mounted) return;
      Navigator.pop(context); // Cerrar loading

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
            esModoPractica: esModoPractica,
            avanzarSoloConBotonEnPractica: avanzarSoloConBotonEnPractica,
            revisarRespuestaInmediata: revisarRespuestaInmediata,
            registrarSesionEnHistorial: registrarSesionEnHistorial,
          ),
        ),
      );

      // Al volver, recargar stats
      _cargarDatosUsuario();
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
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6), // Light grey/blue background
      appBar: const BarraSuperior(),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Welcome Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              color: const Color(0xFFEBF5FF), // Light blue header bg
              child: Column(
                children: [
                  const Icon(
                    Icons.local_police_outlined,
                    size: 64,
                    color: Color(0xFF1E3A8A), // Dark blue
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.esInvitado
                        ? 'Bienvenido'
                        : 'Bienvenido, ${_nombreUsuario.isNotEmpty ? _nombreUsuario : "Usuario"}',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w400,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (widget.esInvitado)
                    Text(
                      'Explora la app y empieza a practicar en minutos.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  if (!widget.esInvitado)
                    RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                      children: [
                        const TextSpan(
                          text: 'Preparándote para el Examen de\nAscenso - ',
                        ),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E3A8A),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.categoriaUsuario,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (widget.esInvitado)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Crea tu cuenta para guardar progreso, ranking y alertas.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _abrirLogin,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF1D4ED8),
                                    side: const BorderSide(
                                      color: Color(0xFF1D4ED8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                  child: const Text('Iniciar sesión'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _abrirRegistro,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1D4ED8),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                  child: const Text('Registrarse'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (!widget.esInvitado)
                    Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Codigo de referido: ${_codigoReferido.isNotEmpty ? _codigoReferido : "Generando..."}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            if (_codigoReferido.isNotEmpty) {
                              Clipboard.setData(
                                ClipboardData(text: _codigoReferido),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Codigo de referido copiado al portapapeles',
                                  ),
                                ),
                              );
                            }
                          },
                          child: const Icon(
                            Icons.copy,
                            size: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Ranking Banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF), // Very light blue
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.emoji_events_outlined,
                              color: Color(0xFF3B82F6),
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _mensajeBannerRanking,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: const Color(0xFF1E3A8A),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_esRegistradoNoActivo) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              height: 36,
                              child: ElevatedButton(
                                onPressed: _abrirActivacionCuenta,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1D4ED8),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  'Activar',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Rutina Diaria Card
                  Builder(
                    builder: (context) {
                      // Usar la meta del usuario desde Supabase
                      final int tiempoMeta = _metaDiariaMinutos;
                      // Relacion: 100 preguntas en 120 minutos
                      // x preguntas = (tiempo * 100) / 120
                      final int cantidadPreguntas = (tiempoMeta * 100 / 120)
                          .round();

                      return _TarjetaInicioDetallada(
                        titulo: 'Rutina Diaria',
                        subtitulo: 'Tu meta de hoy: $tiempoMeta min',
                        descripcion:
                            'Completa tu sesión diaria de estudio. Para $tiempoMeta minutos, te recomendamos practicar $cantidadPreguntas preguntas variadas (según el estándar de 120 min por 100 preguntas).',
                        icono: Icons.access_time_filled,
                        colorIcono: Colors.white,
                        fondoIcono: const Color(0xFFF97316), // Orange
                        colorBoton: const Color(0xFFF97316),
                        textoBoton:
                            'Iniciar Rutina Diaria ($cantidadPreguntas preguntas)',
                        alPresionar: () => _iniciarPractica(
                          cantidad: cantidadPreguntas,
                          categoria: widget.categoriaUsuario,
                          tiempoLimite: tiempoMeta,
                          esModoPractica: false,
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Practica guiada (sin historial/ranking)
                  _TarjetaInicioDetallada(
                    titulo: 'Practica guiada',
                    subtitulo: 'Retroalimentacion inmediata por pregunta',
                    descripcion:
                        'Configura preguntas y materias. Al revisar cada respuesta veras la correcta y su explicacion al instante. No cuenta para ranking ni historial.',
                    icono: Icons.school_outlined,
                    colorIcono: Colors.white,
                    fondoIcono: const Color(0xFF16A34A),
                    colorBoton: const Color(0xFF16A34A),
                    textoBoton: 'Abrir practica guiada',
                    alPresionar: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PantallaPracticaGuiadaConfig(
                            categoriaUsuario: widget.categoriaUsuario,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Realizar Practica Card
                  _TarjetaInicioDetallada(
                    titulo: 'Realizar Practica',
                    subtitulo: '100 preguntas aleatorias',
                    descripcion:
                        'Personaliza tu practica: elige la cantidad de preguntas y materias especificas. Las practicas completas (100 preguntas, todas las materias) cuentan para el ranking.',
                    icono: Icons.psychology,
                    colorIcono: Colors.white,
                    fondoIcono: const Color(0xFF3B82F6), // Blue
                    colorBoton: Colors.black, // From screenshot
                    textoBoton: 'Comenzar Practica',
                    alPresionar: () => _iniciarPractica(
                      cantidad: 100,
                      categoria: widget.categoriaUsuario,
                      tiempoLimite: 120, // 2 horas
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Tutor IA Personal Card
                  _TarjetaInicioDetallada(
                    titulo: 'Tutor IA Personal',
                    subtitulo: 'Inteligencia Artificial Policial',
                    descripcion:
                        'Accede a tu centro de comando IA: Diagnosticos, predicciones de ascenso y planes de estudio adaptativos.',
                    icono: Icons.psychology_alt,
                    colorIcono: Colors.white,
                    fondoIcono: const Color(0xFF7C3AED), // Violet
                    colorBoton: const Color(0xFF7C3AED),
                    textoBoton: 'Abrir Tutor IA Personal',
                    alPresionar: () {
                      if (widget.esInvitado) {
                        _mostrarAvisoTutorInvitado();
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => const PantallaPlanTutorIAPersonal(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Preguntas Acertadas
                  _TarjetaInicioDetallada(
                    titulo: 'Preguntas Acertadas',
                    subtitulo: '$_preguntasCorrectasCount preguntas dominadas',
                    descripcion:
                        'Revisa las preguntas que has respondido correctamente para reforzar tu conocimiento.',
                    icono: Icons.check_circle_outline,
                    colorIcono: Colors.white,
                    fondoIcono: const Color(0xFF10B981), // Green
                    colorBoton: const Color(0xFF10B981),
                    textoBoton: 'Ver Acertadas ($_preguntasCorrectasCount)',
                    fondoTarjeta: const Color(0xFFF0FDF4), // Light green bg
                    bordeTarjeta: const Color(0xFFBBF7D0),
                    alPresionar: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const PantallaPreguntasAcertadas(),
                        ),
                      );
                      _cargarDatosUsuario();
                    },
                  ),

                  const SizedBox(height: 16),

                  // Preguntas No Acertadas
                  _TarjetaInicioDetallada(
                    titulo: 'Preguntas No Acertadas',
                    subtitulo:
                        '$_preguntasIncorrectasCount preguntas por mejorar',
                    descripcion:
                        'Practica las preguntas donde has fallado para convertirlas en fortalezas.',
                    icono: Icons.cancel_outlined,
                    colorIcono: Colors.white,
                    fondoIcono: const Color(0xFFEF4444), // Red
                    colorBoton: const Color(0xFFEF4444),
                    textoBoton: 'Corregir Fallos ($_preguntasIncorrectasCount)',
                    fondoTarjeta: const Color(0xFFFEF2F2), // Light red bg
                    bordeTarjeta: const Color(0xFFFECACA),
                    alPresionar: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const PantallaPreguntasIncorrectas(),
                        ),
                      );
                      _cargarDatosUsuario(); // Refresh stats on return
                    },
                  ),

                  const SizedBox(height: 24),

                  // Progress Banner - Tu Progreso General
                  Container(
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
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
                        // Header
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF3B82F6), Color(0xFFA855F7)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.track_changes,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Tu Progreso General',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Stats Cards Container
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _ItemProgreso(
                                titulo: 'Preguntas Acertadas',
                                valor: _cargandoStats
                                    ? '...'
                                    : _preguntasCorrectasCount.toString(),
                                color: const Color(0xFF10B981), // Green
                                icono: Icons.check_circle_outline,
                                bordeColor: const Color(0xFF86EFAC),
                              ),
                              const SizedBox(height: 12),
                              _ItemProgreso(
                                titulo: 'Preguntas No Acertadas',
                                valor: _cargandoStats
                                    ? '...'
                                    : _preguntasIncorrectasCount.toString(),
                                color: const Color(0xFFEF4444), // Red
                                icono: Icons.cancel_outlined,
                                bordeColor: const Color(0xFFFECACA),
                              ),
                              const SizedBox(height: 12),
                              _ItemProgreso(
                                titulo: 'Total Respondidas',
                                valor: _cargandoStats
                                    ? '...'
                                    : _preguntasTotalesCount.toString(),
                                color: const Color(0xFF3B82F6), // Blue
                                icono: Icons.track_changes,
                                bordeColor: const Color(0xFFBFDBFE),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaInicioDetallada extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final String descripcion;
  final IconData icono;
  final Color colorIcono;
  final Color fondoIcono;
  final Color colorBoton;
  final String textoBoton;
  final VoidCallback alPresionar;
  final Color? fondoTarjeta;
  final Color? bordeTarjeta;

  const _TarjetaInicioDetallada({
    required this.titulo,
    required this.subtitulo,
    required this.descripcion,
    required this.icono,
    required this.colorIcono,
    required this.fondoIcono,
    required this.colorBoton,
    required this.textoBoton,
    required this.alPresionar,
    this.fondoTarjeta,
    this.bordeTarjeta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: fondoTarjeta ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bordeTarjeta ?? Colors.grey.shade200),
        boxShadow: [
          if (fondoTarjeta == null)
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
                  color: fondoIcono,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icono, color: colorIcono, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
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
                        color: fondoTarjeta != null
                            ? Colors.black54
                            : TemaAplicacion.colorExito,
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
            descripcion,
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
              onPressed: alPresionar,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorBoton,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Text(
                textoBoton,
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
}

class _ItemProgreso extends StatelessWidget {
  final String titulo;
  final String valor;
  final Color color;
  final IconData icono;
  final Color bordeColor;

  const _ItemProgreso({
    required this.titulo,
    required this.valor,
    required this.color,
    required this.icono,
    required this.bordeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bordeColor),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icono, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            titulo,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}


