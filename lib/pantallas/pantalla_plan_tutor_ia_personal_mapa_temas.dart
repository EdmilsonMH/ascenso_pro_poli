part of 'pantalla_plan_tutor_ia_personal.dart';

class _MateriaSemaforoItem {
  final String nombre;
  final double porcentaje;
  final _SemaforoTema semaforo;
  final String descripcion;
  final Map<String, dynamic> materia;

  const _MateriaSemaforoItem({
    required this.nombre,
    required this.porcentaje,
    required this.semaforo,
    required this.descripcion,
    required this.materia,
  });
}

class _PantallaMapaTemasSemaforo extends StatelessWidget {
  final List<_MateriaSemaforoItem> items;
  final String resumen;
  final Future<void> Function(Map<String, dynamic> materia) onMateriaTap;

  const _PantallaMapaTemasSemaforo({
    required this.items,
    required this.resumen,
    required this.onMateriaTap,
  });

  Color _colorSemaforo(_SemaforoTema semaforo) {
    switch (semaforo) {
      case _SemaforoTema.verde:
        return const Color(0xFF237D57);
      case _SemaforoTema.ambar:
        return const Color(0xFF8B661E);
      case _SemaforoTema.rojo:
        return const Color(0xFFAD3636);
    }
  }

  String _tituloSemaforo(_SemaforoTema semaforo) {
    switch (semaforo) {
      case _SemaforoTema.verde:
        return 'Verde - Dominadas (>80%)';
      case _SemaforoTema.ambar:
        return 'Ambar - Dudas o ritmo lento';
      case _SemaforoTema.rojo:
        return 'Rojo - Puntos ciegos (<50% o sin iniciar)';
    }
  }

  List<_MateriaSemaforoItem> _itemsPor(
    _SemaforoTema semaforo, {
    _SemaforoTema? filtroActivo,
  }) {
    final base = items.where((e) => e.semaforo == semaforo).toList();
    if (filtroActivo == null) return base;
    if (filtroActivo != semaforo) return const <_MateriaSemaforoItem>[];
    return base;
  }

  Widget _buildFiltroChip({
    required bool selected,
    required VoidCallback onTap,
    required Color color,
    required String titulo,
    required int total,
  }) {
    return ChoiceChip(
      label: Text(
        '$titulo ($total)',
        style: GoogleFonts.inter(
          color: selected ? Colors.white : color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.25)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  Widget _buildSeccion(
    BuildContext context, {
    required _SemaforoTema semaforo,
    _SemaforoTema? filtroActivo,
  }) {
    final lista = _itemsPor(semaforo, filtroActivo: filtroActivo);
    if (lista.isEmpty) return const SizedBox.shrink();
    final color = _colorSemaforo(semaforo);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tituloSemaforo(semaforo),
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 10),
          ...lista.map(
            (item) => InkWell(
              onTap: () async {
                await onMateriaTap(item.materia);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.18)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.nombre,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.descripcion,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF4B5D67),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Dominio ${item.porcentaje.toStringAsFixed(1)}%',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalVerdes = _itemsPor(_SemaforoTema.verde).length;
    final totalAmbar = _itemsPor(_SemaforoTema.ambar).length;
    final totalRojos = _itemsPor(_SemaforoTema.rojo).length;
    _SemaforoTema? filtroActivo;

    return Scaffold(
      backgroundColor: const Color(0xFFECEFF3),
      appBar: AppBar(
        title: Text(
          'Radar de riesgo por materia',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF0B6B57),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StatefulBuilder(
        builder: (context, setLocalState) {
          final visibles = filtroActivo == null
              ? items
              : items.where((e) => e.semaforo == filtroActivo).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDEE6EA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF5EC7A7)),
                  ),
                  child: Text(
                    resumen.trim().isEmpty
                        ? 'Aqui tienes el estado de tus materias segun tu banco actual. Toca una para ver su diagnostico y plan de refuerzo.'
                        : resumen.trim(),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.35,
                      color: const Color(0xFF084434),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFiltroChip(
                      selected: filtroActivo == _SemaforoTema.verde,
                      onTap: () {
                        setLocalState(() {
                          filtroActivo = filtroActivo == _SemaforoTema.verde
                              ? null
                              : _SemaforoTema.verde;
                        });
                      },
                      color: _colorSemaforo(_SemaforoTema.verde),
                      titulo: 'Verde',
                      total: totalVerdes,
                    ),
                    _buildFiltroChip(
                      selected: filtroActivo == _SemaforoTema.ambar,
                      onTap: () {
                        setLocalState(() {
                          filtroActivo = filtroActivo == _SemaforoTema.ambar
                              ? null
                              : _SemaforoTema.ambar;
                        });
                      },
                      color: _colorSemaforo(_SemaforoTema.ambar),
                      titulo: 'Ambar',
                      total: totalAmbar,
                    ),
                    _buildFiltroChip(
                      selected: filtroActivo == _SemaforoTema.rojo,
                      onTap: () {
                        setLocalState(() {
                          filtroActivo = filtroActivo == _SemaforoTema.rojo
                              ? null
                              : _SemaforoTema.rojo;
                        });
                      },
                      color: _colorSemaforo(_SemaforoTema.rojo),
                      titulo: 'Rojo',
                      total: totalRojos,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (filtroActivo == null) ...[
                  _buildSeccion(
                    context,
                    semaforo: _SemaforoTema.rojo,
                    filtroActivo: filtroActivo,
                  ),
                  _buildSeccion(
                    context,
                    semaforo: _SemaforoTema.ambar,
                    filtroActivo: filtroActivo,
                  ),
                  _buildSeccion(
                    context,
                    semaforo: _SemaforoTema.verde,
                    filtroActivo: filtroActivo,
                  ),
                ] else
                  _buildSeccion(
                    context,
                    semaforo: filtroActivo!,
                    filtroActivo: filtroActivo,
                  ),
                if (visibles.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      filtroActivo == null
                          ? 'Aun no hay materias para mostrar. Realiza una practica para activar este panel.'
                          : 'No hay materias en este semaforo con el filtro actual.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
