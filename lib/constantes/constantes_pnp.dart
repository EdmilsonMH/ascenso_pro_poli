/// Constantes oficiales para la jerarquía de la Policía Nacional del Perú
/// basadas en el Decreto Legislativo N° 1149.
class ConstantesPNP {
  static const List<String> categorias = [
    'Oficiales de Armas',
    'Oficiales de Servicios',
    'Suboficiales de Armas',
    'Suboficiales de Servicios',
  ];

  static const Map<String, List<String>> jerarquiasPorCategoria = {
    'Oficiales de Armas': [
      'Oficiales Subalternos',
      'Oficiales Superiores',
      'Oficiales Generales',
    ],
    'Oficiales de Servicios': [
      'Oficiales Subalternos',
      'Oficiales Superiores',
      'Oficiales Generales',
    ],
    'Suboficiales de Armas': [
      'Suboficiales',
      'Suboficiales Técnicos',
      'Suboficiales Superiores',
    ],
    'Suboficiales de Servicios': [
      'Suboficiales',
      'Suboficiales Técnicos',
      'Suboficiales Superiores',
    ],
  };

  static const Map<String, List<String>> gradosPorJerarquia = {
    'Oficiales Subalternos': ['Alférez', 'Teniente', 'Capitán'],
    'Oficiales Superiores': ['Mayor', 'Comandante', 'Coronel'],
    'Oficiales Generales': ['General', 'Teniente General'],
    'Suboficiales': ['SO3', 'SO2', 'SO1'],
    'Suboficiales Técnicos': ['SOT3', 'SOT2', 'SOT1'],
    'Suboficiales Superiores': ['SOB', 'SOS'],
  };

  static const List<String> especialidades = [
    'Orden y Seguridad',
    'Investigación Criminal',
    'Inteligencia',
    'Criminalística',
    'Administración',
    'Otras (Servicios)',
  ];

  /// Obtiene los grados válidos para una categoría específica
  static List<String> obtenerGradosParaCategoria(String categoria) {
    List<String> jerarquias = jerarquiasPorCategoria[categoria] ?? [];
    List<String> todosLosGrados = [];
    for (var jerarquia in jerarquias) {
      todosLosGrados.addAll(gradosPorJerarquia[jerarquia] ?? []);
    }
    return todosLosGrados;
  }
}
