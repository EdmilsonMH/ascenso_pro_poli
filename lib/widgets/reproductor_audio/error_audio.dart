import 'package:flutter/material.dart';
import '../../servicios/audio_handler.dart';

/// Widget que muestra un mensaje de error cuando el servicio de audio falla
class ErrorAudio extends StatelessWidget {
  const ErrorAudio({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 32),
          const SizedBox(height: 8),
          const Text(
            "Error de inicialización de Audio:",
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SelectableText(
            errorDeInicializacion ??
                "Servicio no disponible.\nIntente reiniciar la app.",
            style: TextStyle(
              color: Colors.red.shade900,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
