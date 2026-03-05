import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ascenso_pro_poli/pantallas/pantalla_perfil.dart';
import 'package:ascenso_pro_poli/pantallas/pantalla_notificaciones.dart';

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
    return AppBar(
      automaticallyImplyLeading: false,
      leading: mostrarBotonAtras && onAtrasPressed != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: onAtrasPressed,
              tooltip: 'Volver',
            )
          : null,
      backgroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.psychology, color: Colors.white, size: 20),
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
                    color: Colors.black,
                    fontSize: 13, // Reducido ligeramente de 14
                    height: 1.1,
                  ),
                ),
                Text(
                  'de Ascenso',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.inter(
                    color: Colors.black,
                    fontSize: 13, // Reducido ligeramente de 14
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
              color: audioVisible ? const Color(0xFFA855F7) : Colors.grey,
            ),
            onPressed: onToggleAudio,
            tooltip: audioVisible
                ? 'Ocultar reproductor'
                : 'Mostrar reproductor',
          ),
        IconButton(
          icon: const Icon(Icons.person_outline, color: Colors.black),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Abriendo perfil...'),
                duration: Duration(milliseconds: 500),
              ),
            );
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PantallaPerfil()),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.notifications_none, color: Colors.black),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Abriendo notificaciones...'),
                duration: Duration(milliseconds: 500),
              ),
            );
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
