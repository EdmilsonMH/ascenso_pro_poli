import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../servicios/servicio_notificaciones.dart';
import '../tema/tema_aplicacion.dart';

class PantallaNotificaciones extends StatefulWidget {
  const PantallaNotificaciones({super.key});

  @override
  State<PantallaNotificaciones> createState() => _PantallaNotificacionesState();
}

class _PantallaNotificacionesState extends State<PantallaNotificaciones> {
  final ServicioNotificaciones _servicioNotificaciones =
      ServicioNotificaciones();

  List<Notificacion> _notificaciones = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarNotificaciones();
  }

  Future<void> _cargarNotificaciones() async {
    setState(() => _cargando = true);

    final notificaciones = await _servicioNotificaciones
        .obtenerNotificaciones();

    if (mounted) {
      setState(() {
        _notificaciones = notificaciones;
        _cargando = false;
      });
    }
  }

  Future<void> _marcarTodasComoLeidas() async {
    final exito = await _servicioNotificaciones.marcarTodasComoLeidas();

    if (exito && mounted) {
      final paleta = TemaAplicacion.paleta(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Todas las notificaciones marcadas como leidas'),
          backgroundColor: paleta.success,
        ),
      );
      _cargarNotificaciones();
    }
  }

  Future<void> _marcarComoLeida(String id) async {
    await _servicioNotificaciones.marcarComoLeida(id);
    _cargarNotificaciones();
  }

  String _formatearTiempo(DateTime fecha) {
    final ahora = DateTime.now();
    final diferencia = ahora.difference(fecha);

    if (diferencia.inMinutes < 60) {
      return 'Hace ${diferencia.inMinutes} min';
    } else if (diferencia.inHours < 24) {
      return 'Hace ${diferencia.inHours} horas';
    } else if (diferencia.inDays < 7) {
      return 'Hace ${diferencia.inDays} dias';
    } else {
      return DateFormat('dd MMM yyyy').format(fecha);
    }
  }

  IconData _obtenerIcono(String icono) {
    switch (icono) {
      case 'local_fire_department':
        return Icons.local_fire_department;
      case 'emoji_events':
        return Icons.emoji_events;
      case 'celebration':
        return Icons.celebration;
      case 'assignment':
        return Icons.assignment;
      case 'system_update':
        return Icons.system_update;
      case 'check_circle':
        return Icons.check_circle;
      default:
        return Icons.notifications;
    }
  }

  Color _obtenerColor(String colorHex) {
    try {
      final hex = colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return TemaAplicacion.colorSecundario;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Notificaciones',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: TemaAplicacion.colorPrimario,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_notificaciones.any((n) => !n.leida))
            TextButton(
              onPressed: _marcarTodasComoLeidas,
              child: Text(
                'Marcar todo leido',
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: _cargando
          ?const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarNotificaciones,
              child: _notificaciones.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _notificaciones.length,
                      itemBuilder: (context, index) {
                        final notif = _notificaciones[index];
                        return _buildNotificationItem(notif);
                      },
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 80,
            color: scheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No tienes notificaciones',
            style: GoogleFonts.inter(
              fontSize: 18,
              color: scheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Aqui apareceran tus logros y recordatorios',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(Notificacion notif) {
    final scheme = Theme.of(context).colorScheme;
    final paleta = TemaAplicacion.paleta(context);
    final color = _obtenerColor(notif.color);
    final icono = _obtenerIcono(notif.icono);

    return GestureDetector(
      onTap: () {
        if (!notif.leida) {
          _marcarComoLeida(notif.id);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: notif.leida
              ? scheme.surface
              : paleta.actionCyan.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          notif.titulo,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      if (!notif.leida)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: scheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notif.mensaje,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatearTiempo(notif.createdAt),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
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
