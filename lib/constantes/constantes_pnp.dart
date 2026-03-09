/// Constantes oficiales para la jerarquia de la Policia Nacional del Peru
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
      'Suboficiales Tecnicos',
      'Suboficiales Superiores',
    ],
    'Suboficiales de Servicios': [
      'Suboficiales',
      'Suboficiales Tecnicos',
      'Suboficiales Superiores',
    ],
  };

  static const Map<String, List<String>> gradosPorJerarquia = {
    'Oficiales Subalternos': ['Alferez', 'Teniente', 'Capitan'],
    'Oficiales Superiores': ['Mayor', 'Comandante', 'Coronel'],
    'Oficiales Generales': ['General', 'Teniente General'],
    'Suboficiales': ['SO3', 'SO2', 'SO1'],
    'Suboficiales Tecnicos': ['SOT3', 'SOT2', 'SOT1'],
    'Suboficiales Superiores': ['SOB', 'SOS'],
  };

  static const Map<String, String> gradoCompletoPorCodigo = {
    'SO3': 'Suboficial de Tercera',
    'SO2': 'Suboficial de Segunda',
    'SO1': 'Suboficial de Primera',
    'SOT3': 'Suboficial Tecnico de Tercera',
    'SOT2': 'Suboficial Tecnico de Segunda',
    'SOT1': 'Suboficial Tecnico de Primera',
    'SOB': 'Suboficial Brigadier',
    'SOS': 'Suboficial Superior',
    'ALFEREZ': 'Alferez',
    'TENIENTE': 'Teniente',
    'CAPITAN': 'Capitan',
    'MAYOR': 'Mayor',
    'COMANDANTE': 'Comandante',
    'CORONEL': 'Coronel',
    'GENERAL': 'General',
    'TENIENTE GENERAL': 'Teniente General',
  };

  static const List<String> especialidadesOficialesServicios = [
    'Tecnologo Medico Laboratorista Clinico',
    'Ingeniero de Sistemas',
    'Abogado',
    'Economista',
    'Quimico Farmaceutico',
    'Tecnologo Medico Rehabilitacion y Terapia',
    'Tecnologo Medico en Terapia de Lenguaje',
    'Laboratorista Clinico',
    'Medico',
    'Veterinario',
    'Enfermeria',
    'Obstetra',
    'Ingeniero Mecanico',
    'Contador',
    'Estadistico',
    'Sociologo',
    'Psicologo',
    'Odontologo',
    'Nutricionista',
    'Profesor',
    'Ingeniero Quimico',
    'Asistente Social',
    'Biologo',
    'Administrador',
  ];

  static const List<String> especialidadesGenerales = [
    'Orden y Seguridad',
    'Investigacion Criminal',
    'Inteligencia',
    'Criminalistica',
    'Administracion',
  ];

  static const Map<String, List<String>> especialidadesPorCategoria = {
    'Oficiales de Servicios': especialidadesOficialesServicios,
    'Oficiales de Armas': especialidadesGenerales,
    'Suboficiales de Armas': especialidadesGenerales,
    'Suboficiales de Servicios': especialidadesGenerales,
  };

  static List<String> obtenerEspecialidadesParaCategoria(String categoria) {
    return especialidadesPorCategoria[categoria] ?? especialidadesGenerales;
  }

  static String normalizarGradoCompleto(String grado) {
    final limpio = grado.trim();
    if (limpio.isEmpty) return '';
    final upper = limpio.toUpperCase();
    if (gradoCompletoPorCodigo.containsKey(upper)) {
      return gradoCompletoPorCodigo[upper]!;
    }

    for (final entry in gradoCompletoPorCodigo.entries) {
      if (entry.value.toLowerCase() == limpio.toLowerCase()) {
        return entry.value;
      }
    }
    return limpio;
  }

  /// Obtiene los grados validos para una categoria especifica
  static List<String> obtenerGradosParaCategoria(String categoria) {
    List<String> jerarquias = jerarquiasPorCategoria[categoria] ?? [];
    List<String> todosLosGrados = [];
    for (var jerarquia in jerarquias) {
      final codigos = gradosPorJerarquia[jerarquia] ?? [];
      for (final codigo in codigos) {
        todosLosGrados.add(normalizarGradoCompleto(codigo));
      }
    }
    return todosLosGrados;
  }
}
