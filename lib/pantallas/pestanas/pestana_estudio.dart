import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audio_service/audio_service.dart';
import 'package:ascenso_pro_poli/tema/tema_aplicacion.dart';
import 'package:ascenso_pro_poli/modelos/modelo_pregunta.dart';
import 'package:ascenso_pro_poli/widgets/widgets.dart';
import 'package:ascenso_pro_poli/servicios/audio_handler.dart';
import 'package:ascenso_pro_poli/servicios/servicio_preguntas.dart';
import 'package:ascenso_pro_poli/servicios/servicio_progreso.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../widgets/barra_superior.dart';

enum ModoPestanaEstudio { bancoCompleto, estudiarSimple }

class PestanaEstudio extends StatefulWidget {
  final String categoriaUsuario;
  final ModoPestanaEstudio modo;
  final bool permitirCerrarRutaEnVistaMaterias;

  const PestanaEstudio({
    super.key,
    required this.categoriaUsuario,
    this.modo = ModoPestanaEstudio.bancoCompleto,
    this.permitirCerrarRutaEnVistaMaterias = false,
  });

  @override
  State<PestanaEstudio> createState() => _PestanaEstudioState();
}

class _PestanaEstudioState extends State<PestanaEstudio> {
  static const int _tamanoPaginaMateria = 40;
  static final Map<String, _CacheMateriasEstudio> _cacheVistaMaterias = {};
  static final Map<String, _CachePreguntasMateriaEstudio>
  _cachePreguntasMateria = {};

  final ServicioPreguntas _servicioPreguntas = ServicioPreguntas();
  final ServicioProgreso _servicioProgreso = ServicioProgreso();
  final TextEditingController _controladorBusqueda = TextEditingController();
  final TextEditingController _controladorBusquedaMaterias =
      TextEditingController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  List<Pregunta> _preguntasTotales = [];
  List<Pregunta> _preguntasFiltradas = [];
  List<String> _todasLasMaterias = [];
  List<String> _materiasSeleccionadas = [];
  Map<String, int> _conteoPreguntasPorMateria = {};
  String? _materiaActiva;
  bool _mostrarReproductor = false;
  bool _cargando = true;
  bool _cargandoMateria = false;
  bool _cargandoMasPreguntas = false;
  bool _hayMasPreguntasMateria = false;
  bool _actualizandoMateriasEnSegundoPlano = false;
  List<String> _idsMateriaActiva = [];
  int _offsetMateriaActiva = 0;
  int _tokenCargaMateria = 0;
  final Set<String> _idsEstadisticasPendientes = <String>{};

  // Estado para detectar cambios en reproducción
  bool _estabaReproduciendo = false;
  int _ultimaPreguntaReproducida = 0;

  // Control de rango de audio
  String _rangoAudio = 'todo';
  int _preguntaDesde = 1;
  int _preguntaHasta = 1;
  Map<String, EstadisticaPregunta> _estadisticasPorPregunta = {};

  bool get _esModoSimple => widget.modo == ModoPestanaEstudio.estudiarSimple;
  String get _cacheKeyCategoria => widget.categoriaUsuario.trim().toLowerCase();
  String _cacheKeyMateria(String materia) =>
      '$_cacheKeyCategoria|${materia.trim().toLowerCase()}';

  @override
  void initState() {
    super.initState();
    _cargarVistaMateriasInicial();
  }

  Future<void> _cargarVistaMateriasInicial() async {
    final cache = _cacheVistaMaterias[_cacheKeyCategoria];
    if (cache != null && cache.conteoPorMateria.isNotEmpty) {
      if (mounted) {
        setState(() {
          _aplicarConteoMaterias(cache.conteoPorMateria);
          _cargando = false;
        });
      }
      unawaited(_refrescarVistaMaterias(enSegundoPlano: true));
      return;
    }

    await _refrescarVistaMaterias(enSegundoPlano: false);
  }

  Future<void> _refrescarVistaMaterias({required bool enSegundoPlano}) async {
    if (enSegundoPlano && _actualizandoMateriasEnSegundoPlano) return;
    if (mounted) {
      setState(() {
        if (!enSegundoPlano) {
          _cargando = _todasLasMaterias.isEmpty;
        } else {
          _actualizandoMateriasEnSegundoPlano = true;
        }
      });
    }

    try {
      final conteo = await _servicioPreguntas
          .obtenerConteoPreguntasPorMateria(categoria: widget.categoriaUsuario)
          .timeout(const Duration(seconds: 20));
      final conteoLimpio = Map<String, int>.fromEntries(
        conteo.entries.where((e) => e.key.trim().isNotEmpty && e.value > 0),
      );
      if (conteoLimpio.isNotEmpty) {
        _cacheVistaMaterias[_cacheKeyCategoria] = _CacheMateriasEstudio(
          conteoPorMateria: conteoLimpio,
          actualizadoEn: DateTime.now(),
        );
      }
      if (!mounted) return;
      setState(() {
        _aplicarConteoMaterias(conteoLimpio);
        _cargando = false;
        _actualizandoMateriasEnSegundoPlano = false;
      });
    } catch (e) {
      debugPrint('PestanaEstudio._refrescarVistaMaterias error: $e');
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _actualizandoMateriasEnSegundoPlano = false;
      });
      if (_todasLasMaterias.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudieron cargar las materias por ahora.'),
          ),
        );
      }
    }
  }

  void _aplicarConteoMaterias(Map<String, int> conteo) {
    final materias = conteo.keys.toList()..sort((a, b) => a.compareTo(b));
    _conteoPreguntasPorMateria = {
      for (final materia in materias) materia: conteo[materia] ?? 0,
    };
    _todasLasMaterias = materias;
    if (_materiasSeleccionadas.isEmpty || _enVistaMaterias) {
      _materiasSeleccionadas = List<String>.from(materias);
    } else {
      _materiasSeleccionadas = _materiasSeleccionadas
          .where(_conteoPreguntasPorMateria.containsKey)
          .toList();
      if (_materiasSeleccionadas.isEmpty) {
        _materiasSeleccionadas = List<String>.from(materias);
      }
    }
  }

  Future<void> _cargarMateria(String materia, {required bool revalidar}) async {
    final token = ++_tokenCargaMateria;
    final cache = _cachePreguntasMateria[_cacheKeyMateria(materia)];

    _detenerReproduccion();
    _controladorBusqueda.clear();

    if (mounted) {
      setState(() {
        _materiaActiva = materia;
        _materiasSeleccionadas = [materia];
        _mostrarReproductor = false;
        _rangoAudio = 'todo';
        if (cache != null && cache.preguntas.isNotEmpty) {
          _preguntasTotales = List<Pregunta>.from(cache.preguntas);
          _preguntasFiltradas = List<Pregunta>.from(cache.preguntas);
          _idsMateriaActiva = List<String>.from(cache.idsMateria);
          _offsetMateriaActiva = cache.offsetCargado;
          _hayMasPreguntasMateria = cache.hayMas;
          _cargandoMateria = false;
        } else {
          _preguntasTotales = const [];
          _preguntasFiltradas = const [];
          _idsMateriaActiva = const [];
          _offsetMateriaActiva = 0;
          _hayMasPreguntasMateria = false;
          _cargandoMateria = true;
        }
        _cargandoMasPreguntas = false;
        _preguntaDesde = 1;
        _preguntaHasta = _preguntasFiltradas.isNotEmpty
            ? _preguntasFiltradas.length
            : 1;
      });
    }

    if (cache != null && cache.preguntas.isNotEmpty) {
      _aplicarFiltros();
      if (!_esModoSimple) {
        unawaited(
          _cargarEstadisticasEnSegundoPlano(
            cache.preguntas.map((p) => p.id).toList(),
          ),
        );
      }
      if (revalidar) {
        unawaited(
          _recargarMateriaDesdeServidor(
            materia: materia,
            tokenEsperado: token,
            mostrarCargaVisible: false,
          ),
        );
      }
      return;
    }

    await _recargarMateriaDesdeServidor(
      materia: materia,
      tokenEsperado: token,
      mostrarCargaVisible: true,
    );
  }

  Future<void> _recargarMateriaDesdeServidor({
    required String materia,
    required int tokenEsperado,
    required bool mostrarCargaVisible,
  }) async {
    if (mostrarCargaVisible && mounted) {
      setState(() {
        _cargandoMateria = true;
      });
    }
    try {
      final ids = await _servicioPreguntas
          .obtenerIdsDisponibles(
            categoria: widget.categoriaUsuario,
            materia: materia,
          )
          .timeout(const Duration(seconds: 20));

      if (!mounted ||
          tokenEsperado != _tokenCargaMateria ||
          _materiaActiva != materia) {
        return;
      }

      final limite = ids.length < _tamanoPaginaMateria
          ? ids.length
          : _tamanoPaginaMateria;
      final primeraTanda = ids.take(limite).toList();
      final preguntas = primeraTanda.isEmpty
          ? <Pregunta>[]
          : await _servicioPreguntas
                .obtenerPreguntasPorIds(
                  ids: primeraTanda,
                  materia: materia,
                  categoria: widget.categoriaUsuario,
                )
                .timeout(const Duration(seconds: 20));

      if (!mounted ||
          tokenEsperado != _tokenCargaMateria ||
          _materiaActiva != materia) {
        return;
      }

      final hayMas = ids.length > preguntas.length;
      setState(() {
        _idsMateriaActiva = ids;
        _offsetMateriaActiva = preguntas.length;
        _hayMasPreguntasMateria = hayMas;
        _preguntasTotales = preguntas;
        _cargandoMateria = false;
      });
      _aplicarFiltros();
      _guardarCacheMateria(materia);
      if (!_esModoSimple) {
        unawaited(
          _cargarEstadisticasEnSegundoPlano(
            preguntas.map((p) => p.id).toList(),
          ),
        );
      }
    } catch (e) {
      debugPrint('PestanaEstudio._recargarMateriaDesdeServidor error: $e');
      if (!mounted ||
          tokenEsperado != _tokenCargaMateria ||
          _materiaActiva != materia) {
        return;
      }
      setState(() {
        _cargandoMateria = false;
      });
      if (_preguntasTotales.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudieron cargar las preguntas por ahora.'),
          ),
        );
      }
    }
  }

  Future<void> _cargarMasPreguntasMateria() async {
    final materia = _materiaActiva;
    if (materia == null ||
        _cargandoMateria ||
        _cargandoMasPreguntas ||
        !_hayMasPreguntasMateria) {
      return;
    }

    final tokenEsperado = _tokenCargaMateria;
    final inicio = _offsetMateriaActiva;
    if (inicio >= _idsMateriaActiva.length) {
      if (mounted) {
        setState(() {
          _hayMasPreguntasMateria = false;
        });
      }
      return;
    }

    final fin = (inicio + _tamanoPaginaMateria > _idsMateriaActiva.length)
        ? _idsMateriaActiva.length
        : inicio + _tamanoPaginaMateria;
    final idsPagina = _idsMateriaActiva.sublist(inicio, fin);
    if (idsPagina.isEmpty) return;

    setState(() {
      _cargandoMasPreguntas = true;
    });

    try {
      final nuevas = await _servicioPreguntas
          .obtenerPreguntasPorIds(
            ids: idsPagina,
            materia: materia,
            categoria: widget.categoriaUsuario,
          )
          .timeout(const Duration(seconds: 20));

      if (!mounted ||
          tokenEsperado != _tokenCargaMateria ||
          _materiaActiva != materia) {
        return;
      }

      final porId = <String, Pregunta>{
        for (final p in _preguntasTotales) p.id: p,
      };
      for (final pregunta in nuevas) {
        porId[pregunta.id] = pregunta;
      }
      final combinadas = <Pregunta>[];
      for (final id in _idsMateriaActiva) {
        final pregunta = porId[id];
        if (pregunta != null) {
          combinadas.add(pregunta);
        }
        if (combinadas.length >= fin) break;
      }

      setState(() {
        _preguntasTotales = combinadas;
        _offsetMateriaActiva = combinadas.length;
        _hayMasPreguntasMateria =
            _offsetMateriaActiva < _idsMateriaActiva.length;
        _cargandoMasPreguntas = false;
      });
      _aplicarFiltros();
      _guardarCacheMateria(materia);
      if (!_esModoSimple) {
        unawaited(
          _cargarEstadisticasEnSegundoPlano(nuevas.map((p) => p.id).toList()),
        );
      }
    } catch (e) {
      debugPrint('PestanaEstudio._cargarMasPreguntasMateria error: $e');
      if (!mounted ||
          tokenEsperado != _tokenCargaMateria ||
          _materiaActiva != materia) {
        return;
      }
      setState(() {
        _cargandoMasPreguntas = false;
      });
    }
  }

  void _guardarCacheMateria(String materia) {
    _cachePreguntasMateria[_cacheKeyMateria(
      materia,
    )] = _CachePreguntasMateriaEstudio(
      idsMateria: List<String>.from(_idsMateriaActiva),
      preguntas: List<Pregunta>.from(_preguntasTotales),
      offsetCargado: _offsetMateriaActiva,
      hayMas: _hayMasPreguntasMateria,
      actualizadoEn: DateTime.now(),
    );
  }

  Future<void> _cargarEstadisticasEnSegundoPlano(
    List<String> preguntaIds,
  ) async {
    if (_esModoSimple || preguntaIds.isEmpty) return;
    final idsParaSolicitar = preguntaIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((id) => !_estadisticasPorPregunta.containsKey(id))
        .where((id) => !_idsEstadisticasPendientes.contains(id))
        .toSet()
        .toList();
    if (idsParaSolicitar.isEmpty) return;

    _idsEstadisticasPendientes.addAll(idsParaSolicitar);
    try {
      final estadisticas = await _servicioProgreso
          .obtenerEstadisticasPreguntas(preguntaIds: idsParaSolicitar)
          .timeout(const Duration(seconds: 20));
      if (!mounted || estadisticas.isEmpty) return;
      setState(() {
        _estadisticasPorPregunta = {
          ..._estadisticasPorPregunta,
          ...estadisticas,
        };
      });
    } catch (e) {
      debugPrint('PestanaEstudio._cargarEstadisticasEnSegundoPlano error: $e');
    } finally {
      _idsEstadisticasPendientes.removeAll(idsParaSolicitar);
    }
  }

  @override
  void dispose() {
    _controladorBusqueda.dispose();
    _controladorBusquedaMaterias.dispose();
    // _scrollController.dispose();
    super.dispose();
  }

  List<Pregunta> _obtenerPreguntasParaReproduccion() {
    if (_rangoAudio == 'todo') return _preguntasFiltradas;

    int inicio = _preguntaDesde - 1;
    int fin = _preguntaHasta;

    if (inicio < 0) inicio = 0;
    if (inicio >= _preguntasFiltradas.length) {
      inicio = _preguntasFiltradas.isNotEmpty
          ? _preguntasFiltradas.length - 1
          : 0;
    }

    if (fin > _preguntasFiltradas.length) fin = _preguntasFiltradas.length;
    if (fin < inicio) fin = inicio;

    if (inicio >= fin) return [];

    return _preguntasFiltradas.sublist(inicio, fin);
  }

  void _filtrarPreguntas(String consulta) {
    setState(() {
      var preguntas = _preguntasTotales;

      preguntas = preguntas
          .where((p) => _materiasSeleccionadas.contains(p.materia))
          .toList();

      if (consulta.isNotEmpty) {
        preguntas = preguntas
            .where(
              (p) =>
                  p.texto.toLowerCase().contains(consulta.toLowerCase()) ||
                  p.materia.toLowerCase().contains(consulta.toLowerCase()),
            )
            .toList();
      }

      _preguntasFiltradas = preguntas;
      if (_preguntasFiltradas.isEmpty) {
        _preguntaDesde = 1;
        _preguntaHasta = 1;
      } else {
        _preguntaDesde = _preguntaDesde.clamp(1, _preguntasFiltradas.length);
        _preguntaHasta = _preguntaHasta.clamp(
          _preguntaDesde,
          _preguntasFiltradas.length,
        );
      }
    });
  }

  void _aplicarFiltros() {
    _filtrarPreguntas(_controladorBusqueda.text);
  }

  void _detenerReproduccion() {
    audioHandler?.stop();
    _estabaReproduciendo = false;
  }

  bool get _enVistaMaterias => _materiaActiva == null;

  bool manejarBackInterno() {
    if (_enVistaMaterias) return false;
    _volverAMaterias();
    return true;
  }

  void restablecerVistaMaterias() {
    if (_enVistaMaterias) return;
    _volverAMaterias();
  }

  Future<void> _abrirMateria(String materia) async {
    await _cargarMateria(materia, revalidar: true);
  }

  void _volverAMaterias() {
    _detenerReproduccion();
    _controladorBusqueda.clear();
    setState(() {
      _materiaActiva = null;
      _materiasSeleccionadas = List.from(_todasLasMaterias);
      _mostrarReproductor = false;
      _cargandoMateria = false;
      _cargandoMasPreguntas = false;
    });
  }

  void _manejarAtrasBarraSuperior() {
    if (!_enVistaMaterias) {
      _volverAMaterias();
      return;
    }
    if (widget.permitirCerrarRutaEnVistaMaterias &&
        Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  List<String> get _materiasFiltradasPorBusqueda {
    final query = _controladorBusquedaMaterias.text.trim().toLowerCase();
    if (query.isEmpty) return _todasLasMaterias;
    return _todasLasMaterias
        .where((materia) => materia.toLowerCase().contains(query))
        .toList();
  }

  Widget _buildBarraBusquedaMaterias() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      color: Colors.white,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2F4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _controladorBusquedaMaterias,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Buscar materias...',
            hintStyle: GoogleFonts.inter(
              color: Colors.grey.shade500,
              fontSize: 14,
            ),
            prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
          ),
        ),
      ),
    );
  }

  Widget _buildVistaMaterias() {
    final materiasFiltradas = _materiasFiltradasPorBusqueda;

    if (_todasLasMaterias.isEmpty) {
      return const Center(
        child: Text('No hay materias disponibles por ahora.'),
      );
    }

    return Column(
      children: [
        if (_actualizandoMateriasEnSegundoPlano)
          const LinearProgressIndicator(minHeight: 2),
        _buildBarraBusquedaMaterias(),
        Expanded(
          child: materiasFiltradas.isEmpty
              ? Center(
                  child: Text(
                    'No se encontraron materias.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF4B5D67),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                  itemCount: materiasFiltradas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final materia = materiasFiltradas[index];
                    final total = _conteoPreguntasPorMateria[materia] ?? 0;

                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _abrirMateria(materia),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFD1D5DB)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDEE6EA),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.menu_book_rounded,
                                  color: Color(0xFF0B2933),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      materia,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF1F2A1C),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$total preguntas',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: const Color(0xFF4B5D67),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 16,
                                color: Color(0xFF4B5D67),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Hacer scroll usando la nueva librería
  void _scrollAPregunta(int indice) {
    if (indice < 0 || indice >= _preguntasFiltradas.length) return;

    // Solo intentamos si el controlador está adjunto (la lista está visible)
    if (_itemScrollController.isAttached) {
      debugPrint('DEBUG: Scroll directo a indice $indice');
      _itemScrollController.scrollTo(
        index: indice,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
        alignment:
            0.0, // 0.0 significa alinear el elemento al inicio (arriba) de la lista
      );
    } else {
      debugPrint('DEBUG: Controlador no adjunto, reintentando...');
      // Reintentar brevemente por si se está construyendo
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _itemScrollController.isAttached) {
          _scrollAPregunta(indice);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando && _todasLasMaterias.isEmpty) {
      return Scaffold(
        backgroundColor: TemaAplicacion.colorFondo,
        body: Center(
          child: CircularProgressIndicator(color: TemaAplicacion.colorPrimario),
        ),
      );
    }
    final mostrarBotonAtras =
        !_enVistaMaterias || widget.permitirCerrarRutaEnVistaMaterias;

    return Scaffold(
      backgroundColor: TemaAplicacion.colorFondo,
      appBar: BarraSuperior(
        mostrarBotonAtras: mostrarBotonAtras,
        onAtrasPressed: mostrarBotonAtras ? _manejarAtrasBarraSuperior : null,
        mostrarBotonAudio: !_enVistaMaterias && !_esModoSimple,
        audioVisible: !_esModoSimple && _mostrarReproductor,
        onToggleAudio: (!_enVistaMaterias && !_esModoSimple)
            ? () {
                setState(() {
                  _mostrarReproductor = !_mostrarReproductor;
                  if (!_mostrarReproductor) {
                    _detenerReproduccion();
                  }
                });
              }
            : null,
      ),
      body: _enVistaMaterias
          ? _buildVistaMaterias()
          : _esModoSimple
          ? _buildVistaPreguntasSimple()
          : _buildVistaPreguntasCompleta(),
    );
  }

  Widget _buildVistaPreguntasSimple() {
    if (_cargandoMateria) {
      return Center(
        child: CircularProgressIndicator(color: TemaAplicacion.colorPrimario),
      );
    }

    return Column(
      children: [
        BarraBusqueda(
          controller: _controladorBusqueda,
          onChanged: _filtrarPreguntas,
          hintText: 'Buscar en ${_materiaActiva ?? ''}...',
        ),
        Expanded(
          child: _preguntasFiltradas.isEmpty
              ? Center(
                  child: Text(
                    'No hay preguntas en esta materia.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF4B5D67),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  itemCount: _preguntasFiltradas.length,
                  itemBuilder: (context, index) {
                    final pregunta = _preguntasFiltradas[index];
                    return _TarjetaEstudioSimple(
                      key: ValueKey('estudiar_simple_${pregunta.id}'),
                      pregunta: pregunta,
                      numeroOrden: index + 1,
                    );
                  },
                ),
        ),
        _buildPieCargarMasPreguntas(),
      ],
    );
  }

  Widget _buildVistaPreguntasCompleta() {
    return StreamBuilder<PlaybackState>(
      stream: audioHandler?.playbackState ?? Stream.empty(),
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        final processingState =
            snapshot.data?.processingState ?? AudioProcessingState.idle;
        final isAudioActive =
            playing || processingState == AudioProcessingState.ready;
        final queueIndex = snapshot.data?.queueIndex ?? 0;

        // Guardar última pregunta si está reproduciendo
        if (isAudioActive) {
          int offset = 0;
          if (_rangoAudio == 'rango') {
            offset = (_preguntaDesde - 1).clamp(0, _preguntasFiltradas.length);
          }
          _ultimaPreguntaReproducida = queueIndex + offset;
          // debugPrint('DEBUG: Reproduciendo idx: $queueIndex | Offset: $offset | Ultima: $_ultimaPreguntaReproducida');
        }

        // DETECCIÓN DE DETENCIÓN:
        // Si estaba reproduciendo y ahora NO, y el estado es IDLE (detenido)
        if (_estabaReproduciendo &&
            !isAudioActive &&
            processingState == AudioProcessingState.idle) {
          debugPrint(
            'DEBUG: STOP detectado. Scroll a $_ultimaPreguntaReproducida',
          );

          // Usamos postFrameCallback para dar tiempo a que el Visibility cambie y la lista se monte
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollAPregunta(_ultimaPreguntaReproducida);
          });
        }

        // Actualizar estado previo
        _estabaReproduciendo = isAudioActive;

        if (_cargandoMateria) {
          return Center(
            child: CircularProgressIndicator(
              color: TemaAplicacion.colorPrimario,
            ),
          );
        }

        return Column(
          children: [
            // Barra de búsqueda: Usamos Visibility para mantenerla en el árbol
            // y evitar que el reproductor pierda su estado al cambiar la estructura del Column.
            Visibility(
              visible: !isAudioActive,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: false, // Permitimos que colapse su espacio
              child: BarraBusqueda(
                controller: _controladorBusqueda,
                onChanged: _filtrarPreguntas,
                hintText: 'Buscar en ${_materiaActiva ?? ''}...',
                mostrarFiltroActivo:
                    _materiasSeleccionadas.length != _todasLasMaterias.length,
                onFiltroPressed: () => _mostrarFiltroMaterias(context),
              ),
            ),

            // Reproductor de audio
            _buildSeccionReproductor(),

            // Lista de preguntas: Usamos Expanded + Visibility
            Expanded(
              child: Visibility(
                visible: !isAudioActive,
                maintainState:
                    true, // Mantener estado permite recuperar posición scroll si fuera visible
                child: _preguntasFiltradas.isEmpty
                    ? Center(
                        child: Text(
                          'No hay preguntas en esta materia.',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: const Color(0xFF4B5D67),
                          ),
                        ),
                      )
                    : ScrollablePositionedList.builder(
                        itemScrollController: _itemScrollController,
                        itemPositionsListener: _itemPositionsListener,
                        padding: const EdgeInsets.all(16),
                        itemCount: _preguntasFiltradas.length,
                        itemBuilder: (context, index) {
                          final pregunta = _preguntasFiltradas[index];
                          final estadistica =
                              _estadisticasPorPregunta[pregunta.id];
                          // Marcar visualmente la pregunta que se estaba escuchando?(Opcional)
                          return TarjetaPregunta(
                            key: ValueKey('estudio_${pregunta.id}'),
                            pregunta: pregunta,
                            numeroOrden: index + 1,
                            mostrarRespuestaAlInicio: false,
                            aciertosCount: estadistica?.totalAciertos ?? 0,
                            fallosCount: estadistica?.totalFallos ?? 0,
                          );
                        },
                      ),
              ),
            ),
            if (!isAudioActive) _buildPieCargarMasPreguntas(),
          ],
        );
      },
    );
  }

  Widget _buildPieCargarMasPreguntas() {
    if (!_hayMasPreguntasMateria && !_cargandoMasPreguntas) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _cargandoMasPreguntas
                ? null
                : _cargarMasPreguntasMateria,
            icon: _cargandoMasPreguntas
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more_rounded),
            label: Text(
              _cargandoMasPreguntas ? 'Cargando...' : 'Cargar 40 preguntas mas',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeccionReproductor() {
    // Usamos Visibility en lugar de devolver SizedBox.shrink() para la misma razón:
    // Mantener la clave y estado del widget.
    return Visibility(
      visible: _mostrarReproductor,
      maintainState: true,
      child: _mostrarReproductor
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: ReproductorAudioCompleto(
                // Usar ValueKey asegura que Flutter reconozca este widget como único
                key: const ValueKey('reproductor_principal'),
                preguntas: _obtenerPreguntasParaReproduccion(),
                onConfiguracion: () => _mostrarConfiguracionAudio(context),
              ),
            )
          : const SizedBox.shrink(), // Aquí sí colapsamos si el usuario lo oculta explícitamente
    );
  }

  void _mostrarConfiguracionAudio(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Colors.transparent, // Transparente para ver bordes redondeados
      builder: (BuildContext bc) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SafeArea(
                  // Protege contra barras de navegación gestual
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        24,
                        24,
                        24,
                        40,
                      ), // 40px extra abajo
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Configuración de Audio',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF164A55),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Rango de reproducción:',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF164A55),
                            ),
                          ),
                          const SizedBox(height: 12),
                          RadioListTile<String>(
                            value: 'todo',
                            groupValue: _rangoAudio,
                            onChanged: (value) {
                              setModalState(() {
                                _rangoAudio = value!;
                              });
                              setState(() {
                                _rangoAudio = value!;
                              });
                            },
                            title: Text(
                              'Todas las preguntas (${_preguntasFiltradas.length})',
                              style: GoogleFonts.inter(fontSize: 14),
                            ),
                            fillColor: WidgetStateProperty.all(
                              const Color(0xFF1E6B63),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          RadioListTile<String>(
                            value: 'rango',
                            groupValue: _rangoAudio,
                            onChanged: (value) {
                              setModalState(() {
                                _rangoAudio = value!;
                              });
                              setState(() {
                                _rangoAudio = value!;
                              });
                            },
                            title: Text(
                              'Rango personalizado',
                              style: GoogleFonts.inter(fontSize: 14),
                            ),
                            fillColor: WidgetStateProperty.all(
                              const Color(0xFF1E6B63),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          if (_rangoAudio == 'rango') ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Desde:',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: const Color(0xFF164A55),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      TextField(
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          hintText: '1',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                        ),
                                        onChanged: (value) {
                                          final num = int.tryParse(value);
                                          if (num != null &&
                                              num >= 1 &&
                                              num <=
                                                  _preguntasFiltradas.length) {
                                            setState(() {
                                              _preguntaDesde = num;
                                              if (_preguntaDesde >
                                                  _preguntaHasta) {
                                                _preguntaHasta = _preguntaDesde;
                                              }
                                            });
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Hasta:',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: const Color(0xFF164A55),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      TextField(
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          hintText:
                                              '${_preguntasFiltradas.length}',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                        ),
                                        onChanged: (value) {
                                          final num = int.tryParse(value);
                                          if (num != null &&
                                              num >= _preguntaDesde &&
                                              num <=
                                                  _preguntasFiltradas.length) {
                                            setState(() {
                                              _preguntaHasta = num;
                                            });
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Se reproducirán ${_preguntaHasta - _preguntaDesde + 1} preguntas',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF1A5F59),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E6B63),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Aplicar Configuración'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _mostrarFiltroMaterias(BuildContext context) {
    mostrarBottomSheetFiltros(
      context: context,
      todasLasMaterias: _todasLasMaterias,
      materiasSeleccionadas: _materiasSeleccionadas,
      colorPrimario: const Color(0xFF1E6B63),
      onAplicar: (nuevasMaterias) {
        if (nuevasMaterias.isEmpty) return;
        if (nuevasMaterias.length == 1) {
          final nuevaMateria = nuevasMaterias.first;
          if (nuevaMateria == _materiaActiva) {
            setState(() {
              _materiasSeleccionadas = [nuevaMateria];
            });
            _aplicarFiltros();
            return;
          }
          unawaited(_abrirMateria(nuevaMateria));
          return;
        }
        _volverAMaterias();
      },
    );
  }
}

class _TarjetaEstudioSimple extends StatelessWidget {
  final Pregunta pregunta;
  final int numeroOrden;

  const _TarjetaEstudioSimple({
    super.key,
    required this.pregunta,
    required this.numeroOrden,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final respuestaCorrecta =
        '${String.fromCharCode(65 + pregunta.indiceRespuestaCorrecta)}. '
        '${pregunta.opciones[pregunta.indiceRespuestaCorrecta]}';
    final explicacion = pregunta.explicacion.trim().isNotEmpty
        ? pregunta.explicacion.trim()
        : 'No hay explicacion disponible.';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pregunta #$numeroOrden',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            pregunta.texto,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: TemaAplicacion.textoPrimario,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Respuesta correcta',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0E7A3E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            respuestaCorrecta,
            style: GoogleFonts.inter(fontSize: 14, color: scheme.onSurface),
          ),
          const SizedBox(height: 14),
          Text(
            'Explicacion',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            explicacion,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CacheMateriasEstudio {
  final Map<String, int> conteoPorMateria;
  final DateTime actualizadoEn;

  const _CacheMateriasEstudio({
    required this.conteoPorMateria,
    required this.actualizadoEn,
  });
}

class _CachePreguntasMateriaEstudio {
  final List<String> idsMateria;
  final List<Pregunta> preguntas;
  final int offsetCargado;
  final bool hayMas;
  final DateTime actualizadoEn;

  const _CachePreguntasMateriaEstudio({
    required this.idsMateria,
    required this.preguntas,
    required this.offsetCargado,
    required this.hayMas,
    required this.actualizadoEn,
  });
}
