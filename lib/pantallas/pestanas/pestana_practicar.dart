import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../modelos/modelo_pregunta.dart';
import '../../servicios/auth_service.dart';
import '../../servicios/servicio_preguntas.dart';
import '../../servicios/servicio_progreso.dart';
import '../pantalla_practica.dart';
import '../../widgets/barra_superior.dart';

class PestanaPracticar extends StatefulWidget {
  final String categoriaUsuario;
  final bool esInvitado;

  const PestanaPracticar({
    super.key,
    required this.categoriaUsuario,
    this.esInvitado = false,
  });

  @override
  State<PestanaPracticar> createState() => _PestanaPracticarState();
}

class _PestanaPracticarState extends State<PestanaPracticar> {
  static const int _limitePracticasRankingNoActivo = 3;
  final ServicioPreguntas _servicioPreguntas = ServicioPreguntas();
  final ServicioProgreso _servicioProgreso = ServicioProgreso();
  final TextEditingController _cantidadController = TextEditingController(
    text: '100',
  );
  int _cantidadPreguntas = 100;
  List<String> _todasLasMateriasDisponibles = [];
  List<String> _materiasSeleccionadas = [];
  int _preguntasDisponibles = 0;
  List<Pregunta> _preguntasTotalesCache = [];
  bool _premiumActivo = false;
  int _rankingPracticasUsadas = 0;
  bool _cargando = true;
  bool _mostrarInstruccionesCompletas = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    try {
      final preguntasFuture = _servicioPreguntas
          .obtenerTodas(categoria: widget.categoriaUsuario)
          .timeout(const Duration(seconds: 20));
      final perfilFuture = widget.esInvitado
          ? Future<Map<String, dynamic>?>.value(null)
          : AuthService.getCurrentUserProfile();
      final rankingUsadasFuture = widget.esInvitado
          ? Future<int>.value(0)
          : _servicioProgreso.obtenerCantidadPracticasRanking();

      final preguntas = await preguntasFuture;
      final perfil = await perfilFuture;
      final rankingUsadas = await rankingUsadasFuture;

      if (mounted) {
        setState(() {
          _preguntasTotalesCache = preguntas;
          _todasLasMateriasDisponibles = preguntas
              .map((p) => p.materia)
              .toSet()
              .toList();
          _materiasSeleccionadas = List.from(_todasLasMateriasDisponibles);
          _premiumActivo = perfil?['premium'] == true;
          _rankingPracticasUsadas = rankingUsadas;
          _cargando = false;
          _actualizarPreguntasDisponibles();
        });
      }
    } catch (e) {
      debugPrint('PestanaPracticar._cargarDatos error: $e');
      if (!mounted) return;
      setState(() {
        _preguntasTotalesCache = const [];
        _todasLasMateriasDisponibles = const [];
        _materiasSeleccionadas = const [];
        _preguntasDisponibles = 0;
        _cargando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudieron cargar las preguntas por ahora.'),
        ),
      );
    }
  }

  void _actualizarPreguntasDisponibles() {
    // Ya viene filtrado por categorÃ­a, aquÃ­ solo filtramos por materia.
    final todas = _preguntasTotalesCache;

    // Filtrar preguntas que pertenezcan a las materias seleccionadas
    final disponibles = todas
        .where((p) => _materiasSeleccionadas.contains(p.materia))
        .length;

    setState(() {
      _preguntasDisponibles = disponibles;
      // Validar si la cantidad actual excede las disponibles
      if (_cantidadPreguntas > _preguntasDisponibles) {
        // Solo ajustar si hay disponibilidad (evitar poner 0 si no se seleccionÃ³ nada)
        _cantidadPreguntas = _preguntasDisponibles > 0
            ? _preguntasDisponibles
            : 0;
        _cantidadController.text = _cantidadPreguntas.toString();
      }
    });
  }

  int get _tiempoEstimadoMinutos => (_cantidadPreguntas * 1.2).ceil();

  int get _cantidadPreguntasEfectiva {
    if (_cantidadPreguntas <= 0) return 0;
    if (_preguntasDisponibles <= 0) return 0;
    return _cantidadPreguntas > _preguntasDisponibles
        ? _preguntasDisponibles
        : _cantidadPreguntas;
  }

  // Es ranking solo si selecciona TODAS las materias y 100 preguntas.
  bool get _cumpleConfiguracionRanking =>
      _todasLasMateriasDisponibles.isNotEmpty &&
      _materiasSeleccionadas.length == _todasLasMateriasDisponibles.length &&
      _cantidadPreguntasEfectiva == 100;

  bool get _esEligibleParaRanking =>
      !widget.esInvitado &&
      _cumpleConfiguracionRanking &&
      (!_esRegistradoNoActivo || _rankingPracticasRestantesNoActivo > 0);

  bool get _intentaRankingComoInvitado =>
      widget.esInvitado && _cumpleConfiguracionRanking;

  bool get _intentaRankingSinIntentosNoActivo =>
      !widget.esInvitado &&
      _esRegistradoNoActivo &&
      _cumpleConfiguracionRanking &&
      _rankingPracticasRestantesNoActivo == 0;

  bool get _esRegistradoNoActivo => !widget.esInvitado && !_premiumActivo;

  int get _rankingPracticasRestantesNoActivo {
    final restantes = _limitePracticasRankingNoActivo - _rankingPracticasUsadas;
    return restantes < 0 ? 0 : restantes;
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    super.dispose();
  }

  void _mostrarDialogoSeleccionMaterias() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // TÃ­tulo
                  Text(
                    'Filtrar por Materias',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // OpciÃ³n Todas las materias
                  CheckboxListTile(
                    title: Text(
                      'Todas las materias',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                    value:
                        _materiasSeleccionadas.length ==
                        _todasLasMateriasDisponibles.length,
                    fillColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? const Color(0xFF2563EB)
                          : null,
                    ),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (bool? value) {
                      setStateModal(() {
                        if (value == true) {
                          _materiasSeleccionadas = List.from(
                            _todasLasMateriasDisponibles,
                          );
                        } else {
                          // Debe haber al menos una seleccionada o permitimos 0?
                          // El original permitÃ­a 0 y luego ponÃ­a 0 preguntas disponibles.
                          _materiasSeleccionadas.clear();
                        }
                      });
                    },
                  ),
                  const Divider(height: 24),

                  // Lista de materias
                  Expanded(
                    child: ListView(
                      shrinkWrap: true,
                      children: _todasLasMateriasDisponibles.map((materia) {
                        return CheckboxListTile(
                          title: Text(
                            materia,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: const Color(0xFF4B5563),
                            ),
                          ),
                          value: _materiasSeleccionadas.contains(materia),
                          fillColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? const Color(0xFF2563EB)
                                : null,
                          ),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (bool? value) {
                            setStateModal(() {
                              if (value == true) {
                                _materiasSeleccionadas.add(materia);
                              } else {
                                _materiasSeleccionadas.remove(materia);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // BotÃ³n Aplicar
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        // Aplicar cambios en el padre
                        setState(() {
                          _actualizarPreguntasDisponibles();
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Aplicar Filtros',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 12 + MediaQuery.of(context).padding.bottom),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _obtenerTextoSeleccionMaterias() {
    if (_materiasSeleccionadas.isEmpty) {
      return 'Ninguna seleccionada';
    }
    if (_materiasSeleccionadas.length == _todasLasMateriasDisponibles.length) {
      return 'Todas las materias';
    }
    if (_materiasSeleccionadas.length == 1) {
      return _materiasSeleccionadas.first;
    }
    return '${_materiasSeleccionadas.length} materias seleccionadas';
  }

  List<String> _obtenerInstruccionesPractica() {
    return [
      _materiasSeleccionadas.length == _todasLasMateriasDisponibles.length
          ? 'Se te presentaran $_cantidadPreguntas preguntas de todas las materias'
          : 'Se te presentaran $_cantidadPreguntas preguntas de ${_materiasSeleccionadas.length} materias seleccionadas',
      'Cada pregunta tiene 4 opciones de respuesta, solo una es correcta',
      'Podras ver la respuesta correcta y una explicacion despues de responder',
      'Tiempo estimado: $_tiempoEstimadoMinutos minutos (se registrara automaticamente)',
      'Se requiere un 70% de aciertos para aprobar',
      'Tus respuestas se guardaran para seguimiento de progreso',
    ];
  }

  // ... (skip until build)
  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const BarraSuperior(),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          12,
          10,
          12,
          12 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Configuration Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDBEAFE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.settings_outlined,
                        color: Color(0xFF2563EB),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Configuraci\u00F3n de Pr\u00E1ctica',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E3A8A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Inputs Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Quantity Input
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Preguntas',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 44,
                              child: TextField(
                                controller: _cantidadController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                                onChanged: (value) {
                                  final n = int.tryParse(value);
                                  if (n != null) {
                                    setState(() {
                                      _cantidadPreguntas = n;
                                    });
                                  }
                                },
                              ),
                            ),
                            if (_cantidadPreguntas > _preguntasDisponibles)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'M\u00E1ximo $_preguntasDisponibles',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'M\u00E1ximo: $_preguntasDisponibles disponibles',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Subject Selector (Multi-select)
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Materia',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: _mostrarDialogoSeleccionMaterias,
                              child: Container(
                                height: 44,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _obtenerTextoSeleccionMaterias(),
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_drop_down,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Aviso de ranking solo cuando la configuracion equivale
                  // a una practica ranking (100 preguntas, todas las materias).
                  if (_esEligibleParaRanking ||
                      _intentaRankingComoInvitado ||
                      _intentaRankingSinIntentosNoActivo)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _esEligibleParaRanking
                            ? const Color(0xFFFEFCE8)
                            : const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _esEligibleParaRanking
                              ? const Color(0xFFFEF08A)
                              : const Color(0xFFC7D2FE),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _esEligibleParaRanking
                                ? Icons.emoji_events
                                : Icons.lock_outline,
                            color: _esEligibleParaRanking
                                ? const Color(0xFFCA8A04)
                                : const Color(0xFF4338CA),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: _esEligibleParaRanking
                                      ? const Color(0xFF854D0E)
                                      : const Color(0xFF3730A3),
                                ),
                                children: _esEligibleParaRanking
                                    ? (_esRegistradoNoActivo
                                          ? [
                                              const TextSpan(
                                                text:
                                                    'Esta práctica contará para el ranking ',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              TextSpan(
                                                text:
                                                    'y te quedarán ${_rankingPracticasRestantesNoActivo - 1} de 3 prácticas ranking al finalizar. Activa tu cuenta para ranking ilimitado.',
                                              ),
                                            ]
                                          : const [
                                              TextSpan(
                                                text:
                                                    'Esta práctica contará para el ranking ',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              TextSpan(
                                                text:
                                                    'porque estás practicando 100 preguntas con todas las materias.',
                                              ),
                                            ])
                                    : _intentaRankingSinIntentosNoActivo
                                    ? const [
                                        TextSpan(
                                          text:
                                              'Ya usaste tus 3 prácticas ranking. ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        TextSpan(
                                          text:
                                              'Activa tu cuenta para seguir compitiendo en el ranking.',
                                        ),
                                      ]
                                    : const [
                                        TextSpan(
                                          text: 'No aparecerás en el ranking ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        TextSpan(
                                          text:
                                              'porque estás en modo invitado. Regístrate o inicia sesión para que tu práctica cuente.',
                                        ),
                                      ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Instructions Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDBEAFE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Instrucciones:',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1E3A8A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...(() {
                    final instrucciones = _obtenerInstruccionesPractica();
                    final visibles = _mostrarInstruccionesCompletas
                        ? instrucciones
                        : instrucciones.take(2).toList();
                    return visibles.map(_buildInstructionItem);
                  })(),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _mostrarInstruccionesCompletas =
                            !_mostrarInstruccionesCompletas;
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: const Size(0, 0),
                    ),
                    icon: Icon(
                      _mostrarInstruccionesCompletas
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: const Color(0xFF2563EB),
                    ),
                    label: Text(
                      _mostrarInstruccionesCompletas
                          ? 'Leer menos'
                          : 'Leer mas',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Stats Row
            Row(
              children: [
                Expanded(
                  child: _ResumenCard(
                    titulo: 'Preguntas',
                    valor: '$_cantidadPreguntas',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ResumenCard(
                    titulo: 'Tiempo Estimado',
                    valor: '$_tiempoEstimadoMinutos min',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ResumenCard(titulo: 'Para Aprobar', valor: '70%'),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Start Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);

                  if (_cantidadPreguntas < 1) return;

                  if (_materiasSeleccionadas.isEmpty) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Debes seleccionar al menos una materia'),
                      ),
                    );
                    return;
                  }

                  // Ajustar si la cantidad pedida es mayor a la disponible
                  int cantidadFinal = _cantidadPreguntas;
                  if (cantidadFinal > _preguntasDisponibles) {
                    cantidadFinal = _preguntasDisponibles;
                    if (cantidadFinal > 0) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Se ajust\u00F3 a $cantidadFinal preguntas disponibles',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }

                  if (cantidadFinal == 0) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'No hay preguntas disponibles para las materias seleccionadas',
                        ),
                      ),
                    );
                    return;
                  }

                  final incluyeTodasMaterias =
                      _todasLasMateriasDisponibles.isNotEmpty &&
                      _materiasSeleccionadas.length ==
                          _todasLasMateriasDisponibles.length;
                  final intentaRanking =
                      !widget.esInvitado &&
                      incluyeTodasMaterias &&
                      cantidadFinal == 100;
                  final esRankingFinal =
                      intentaRanking &&
                      (!_esRegistradoNoActivo ||
                          _rankingPracticasRestantesNoActivo > 0);

                  if (intentaRanking &&
                      _esRegistradoNoActivo &&
                      _rankingPracticasRestantesNoActivo == 0) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Ya usaste tus 3 prácticas ranking. Activa tu cuenta para continuar.',
                        ),
                      ),
                    );
                    return;
                  }

                  List<Pregunta> seleccionadas;
                  var n = cantidadFinal;

                  if (esRankingFinal && _esRegistradoNoActivo) {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          const Center(child: CircularProgressIndicator()),
                    );
                    try {
                      final rankingBancoCompleto = await _servicioPreguntas
                          .obtenerPreguntasRankingBancoCompleto(
                            categoria: widget.categoriaUsuario,
                            cantidad: 100,
                          )
                          .timeout(const Duration(seconds: 20));

                      if (!mounted) return;
                      navigator.pop();

                      if (rankingBancoCompleto.length < 100) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'No hay suficientes preguntas para una práctica ranking.',
                            ),
                          ),
                        );
                        return;
                      }

                      seleccionadas = rankingBancoCompleto;
                      n = 100;
                    } catch (_) {
                      if (mounted) {
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'No se pudieron cargar las preguntas de ranking.',
                            ),
                          ),
                        );
                      }
                      return;
                    }
                  } else {
                    // Filtro normal por materias dentro del acceso permitido.
                    final todas = _preguntasTotalesCache;
                    final seleccionadasCandidatas = todas
                        .where(
                          (p) => _materiasSeleccionadas.contains(p.materia),
                        )
                        .toList();

                    seleccionadasCandidatas.shuffle();
                    if (n > seleccionadasCandidatas.length) {
                      n = seleccionadasCandidatas.length;
                    }
                    seleccionadas = seleccionadasCandidatas.take(n).toList();
                  }

                  if (seleccionadas.isEmpty) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('No hay preguntas disponibles.'),
                      ),
                    );
                    return;
                  }

                  final materiasParaRegistroRanking = esRankingFinal
                      ? _preguntasTotalesCache
                            .map((p) => p.materiaId?.trim() ?? '')
                            .where((id) => id.isNotEmpty)
                            .toSet()
                            .toList()
                      : <String>[];

                  if (!mounted) return;
                  await navigator.push(
                    MaterialPageRoute(
                      builder: (context) => PantallaPractica(
                        preguntas: seleccionadas,
                        tiempoLimiteSegundos: n * 72,
                        esModoPractica: !esRankingFinal,
                        esRanking: esRankingFinal,
                        avanzarSoloConBotonEnPractica: !esRankingFinal,
                        materiasIncluidasParaRegistro:
                            materiasParaRegistroRanking.isEmpty
                            ? null
                            : materiasParaRegistroRanking,
                      ),
                    ),
                  );
                  if (mounted) {
                    await _cargarDatos();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Comenzar Pr\u00E1ctica',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: Color(0xFF4B5563),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF4B5563),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumenCard extends StatelessWidget {
  final String titulo;
  final String valor;

  const _ResumenCard({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Text(
            titulo,
            style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
