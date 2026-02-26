import 'package:flutter/material.dart';

/// Widget de barra de búsqueda reutilizable
class BarraBusqueda extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final bool mostrarFiltroActivo;
  final VoidCallback? onFiltroPressed;

  const BarraBusqueda({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Buscar preguntas...',
    this.mostrarFiltroActivo = false,
    this.onFiltroPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hintText,
                prefixIcon: const Icon(Icons.search),
                fillColor: Colors.grey.shade100,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (onFiltroPressed != null) ...[
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: mostrarFiltroActivo
                    ? const Color(0xFF3B82F6)
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: IconButton(
                icon: Icon(
                  Icons.filter_list,
                  color: mostrarFiltroActivo ? Colors.white : Colors.black,
                ),
                onPressed: onFiltroPressed,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
