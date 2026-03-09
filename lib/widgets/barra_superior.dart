import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ascenso_pro_poli/pantallas/pantalla_notificaciones.dart';
import 'package:ascenso_pro_poli/pantallas/pantalla_perfil.dart';

class BarraSuperior extends StatelessWidget implements PreferredSizeWidget {
  final bool mostrarBotonAtras;
  final VoidCallback? onAtrasPressed;
  final bool mostrarBotonAudio;
  final bool audioVisible;
  final VoidCallback? onToggleAudio;

  const BarraSuperior({
    super.key,
    this.mostrarBotonAtras = false,
    this.onAtrasPressed,
    this.mostrarBotonAudio = false,
    this.audioVisible = false,
    this.onToggleAudio,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppBar(
      automaticallyImplyLeading: false,
      leading: mostrarBotonAtras && onAtrasPressed != null
          ? IconButton(
              icon: Icon(Icons.arrow_back, color: scheme.onPrimary),
              onPressed: onAtrasPressed,
              tooltip: 'Volver',
            )
          : null,
      backgroundColor: scheme.primary,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.secondary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.psychology, color: scheme.onSecondary, size: 20),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Examen',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.inter(
                    color: scheme.onPrimary,
                    fontSize: 13,
                    height: 1.1,
                  ),
                ),
                Text(
                  'de Ascenso',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.inter(
                    color: scheme.onPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (mostrarBotonAudio && onToggleAudio != null)
          IconButton(
            icon: Icon(
              audioVisible ? Icons.volume_up : Icons.volume_off,
              color: audioVisible ? scheme.secondary : scheme.onPrimary,
            ),
            onPressed: onToggleAudio,
            tooltip: audioVisible
                ? 'Ocultar reproductor'
                : 'Mostrar reproductor',
          ),
        IconButton(
          icon: Icon(Icons.settings_outlined, color: scheme.onPrimary),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    const PantallaPerfil(soloConfiguracion: true),
              ),
            );
          },
          tooltip: 'Configuracion',
        ),
        IconButton(
          icon: Icon(Icons.person_outline, color: scheme.onPrimary),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PantallaPerfil()),
            );
          },
          tooltip: 'Perfil',
        ),
        IconButton(
          icon: Icon(Icons.notifications_none, color: scheme.onPrimary),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PantallaNotificaciones(),
              ),
            );
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
