import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pestanas/pestana_inicio.dart';
import 'pestanas/pestana_estudio.dart';
import 'pestanas/pestana_practicar.dart';
import 'pestanas/pestana_historial.dart';
import 'pestanas/pestana_ranking.dart';
import '../servicios/servicio_notificaciones_programadas.dart';

class PantallaPrincipal extends StatefulWidget {
  final String categoriaUsuario; // 'Oficiales PNP' or 'Suboficiales PNP'
  final bool esInvitado;

  const PantallaPrincipal({
    super.key,
    required this.categoriaUsuario,
    this.esInvitado = false,
  });

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  int _indiceActual = 0;
  int _rankingRefreshToken = 0;
  final GlobalKey _pestanaEstudioKey = GlobalKey();

  void _restablecerEstudioSiSaleDeTab(int nuevoIndice) {
    if (_indiceActual != 1 || nuevoIndice == 1) return;
    final dynamic estadoEstudio = _pestanaEstudioKey.currentState;
    if (estadoEstudio == null) return;
    try {
      estadoEstudio.restablecerVistaMaterias();
    } catch (_) {
      // Si el estado no expone el método, continuamos sin bloquear navegación.
    }
  }

  @override
  void initState() {
    super.initState();
    if (!widget.esInvitado) {
      _sincronizarNotificaciones();
    } else {
      _limpiarNotificacionesInvitado();
    }
  }

  Future<void> _sincronizarNotificaciones() async {
    try {
      await ServicioNotificacionesProgramadas.programarNotificacionesDiarias();
    } catch (e) {
      debugPrint('No se pudo sincronizar notificaciones: $e');
    }
  }

  Future<void> _limpiarNotificacionesInvitado() async {
    try {
      await ServicioNotificacionesProgramadas.cancelarTodasLasNotificaciones();
    } catch (e) {
      debugPrint('No se pudieron limpiar notificaciones en modo invitado: $e');
    }
  }

  @override
  void didUpdateWidget(covariant PantallaPrincipal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.esInvitado == oldWidget.esInvitado) return;
    if (widget.esInvitado) {
      _limpiarNotificacionesInvitado();
    } else {
      _sincronizarNotificaciones();
    }
  }

  List<Widget> _buildPantallas() {
    return [
      PestanaInicio(
        categoriaUsuario: widget.categoriaUsuario,
        esInvitado: widget.esInvitado,
        onTabChange: (indice) {
          _restablecerEstudioSiSaleDeTab(indice);
          setState(() {
            _indiceActual = indice;
            if (indice == 4) {
              _rankingRefreshToken++;
            }
          });
        },
      ),
      PestanaEstudio(
        key: _pestanaEstudioKey,
        categoriaUsuario: widget.categoriaUsuario,
      ),
      PestanaPracticar(
        categoriaUsuario: widget.categoriaUsuario,
        esInvitado: widget.esInvitado,
      ),
      PestanaHistorial(esInvitado: widget.esInvitado),
      PestanaRanking(
        refreshToken: _rankingRefreshToken,
        esInvitado: widget.esInvitado,
      ),
    ];
  }

  Future<bool> _manejarBotonAtras() async {
    if (_indiceActual == 1) {
      final dynamic estadoEstudio = _pestanaEstudioKey.currentState;
      if (estadoEstudio != null) {
        try {
          final bool consumido = estadoEstudio.manejarBackInterno() == true;
          if (consumido) return false;
        } catch (_) {
          // Si falla el acceso al estado interno, seguimos con fallback de tabs.
        }
      }
    }

    if (_indiceActual != 0) {
      setState(() {
        _indiceActual = 0;
      });
      return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final permitirSalida = await _manejarBotonAtras();
        if (permitirSalida) {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _indiceActual, children: _buildPantallas()),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _indiceActual,
          onDestinationSelected: (indice) {
            _restablecerEstudioSiSaleDeTab(indice);
            setState(() {
              _indiceActual = indice;
              if (indice == 4) {
                _rankingRefreshToken++;
              }
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Inicio',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Estudiar',
            ),
            NavigationDestination(
              icon: Icon(Icons.psychology_outlined),
              selectedIcon: Icon(Icons.psychology),
              label: 'Practicar',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'Historial',
            ),
            NavigationDestination(
              icon: Icon(Icons.emoji_events_outlined),
              selectedIcon: Icon(Icons.emoji_events),
              label: 'Ranking',
            ),
          ],
        ),
      ),
    );
  }
}
