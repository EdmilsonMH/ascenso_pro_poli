import '../modelos/modelo_pregunta.dart';

/// Servicio para todas las operaciones de base de datos (MOCK - Frontend Only)
class DatabaseService {
  // ============================================
  // PREGUNTAS
  // ============================================

  /// Obtener todas las preguntas
  static Future<List<Pregunta>> obtenerPreguntas({
    String? categoria,
    String? materia,
    int? limite,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    // Usamos los datos de prueba existentes
    List<Pregunta> resultados = List.from(DatosPrueba.preguntas);

    if (materia != null) {
      resultados = resultados.where((p) => p.materia == materia).toList();
    }

    if (limite != null && resultados.length > limite) {
      return resultados.take(limite).toList();
    }

    return resultados;
  }

  /// Obtener preguntas aleatorias
  static Future<List<Pregunta>> obtenerPreguntasAleatorias({
    required int cantidad,
    String? categoria,
    List<String>? materias,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    List<Pregunta> pool = List.from(DatosPrueba.preguntas);

    if (materias != null && materias.isNotEmpty) {
      pool = pool.where((p) => materias.contains(p.materia)).toList();
    }

    pool.shuffle();
    return pool.take(cantidad).toList();
  }

  /// Obtener lista de materias únicas
  static Future<List<String>> obtenerMaterias() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return DatosPrueba.obtenerMateriasUnicas();
  }

  // ============================================
  // SESIONES DE PRÁCTICA (Historial)
  // ============================================

  /// Crear una nueva sesión de práctica
  static Future<String?> crearSesion({
    required int totalPreguntas,
    List<String>? materias,
    bool cuentaParaRanking = false,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return 'sesion-mock-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Finalizar una sesión de práctica
  static Future<bool> finalizarSesion({
    required String sesionId,
    required int correctas,
    required int incorrectas,
    required int tiempoSegundos,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Aquí podríamos guardar en una lista local en memoria si quisiéramos persistencia durante la sesión
    return true;
  }

  /// Obtener historial de sesiones
  static Future<List<SesionPractica>> obtenerHistorial({int? limite}) async {
    await Future.delayed(const Duration(milliseconds: 500));

    // Mock historial
    final historial = List.generate(5, (index) {
      return SesionPractica(
        id: 'historial-$index',
        totalPreguntas: 20,
        preguntasCorrectas: 15 + index, // Mock variable
        preguntasIncorrectas: 5 - index,
        tiempoTotalSegundos: 300,
        completada: true,
        fechaCreacion: DateTime.now().subtract(Duration(days: index)),
        fechaFinalizacion: DateTime.now().subtract(Duration(days: index)),
      );
    });

    return historial;
  }

  /// Obtener estadísticas de historial
  static Future<Map<String, dynamic>> obtenerEstadisticasHistorial() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return {
      'total_sesiones': 12,
      'promedio_aciertos': 85,
      'tiempo_total': 3600,
    };
  }

  // ============================================
  // RANKING
  // ============================================

  /// Obtener ranking de usuarios
  static Future<List<RankingUsuario>> obtenerRanking({int limite = 50}) async {
    await Future.delayed(const Duration(milliseconds: 1000));

    return List.generate(10, (index) {
      return RankingUsuario(
        id: 'user-$index',
        nombreCompleto: 'Usuario ${index + 1}',
        categoria: 'Oficiales',
        puntosTotales: 5000 - (index * 100),
        preguntasRespondidas: 200,
        preguntasCorrectas: 180,
        porcentajeAciertos: 90.0,
        rachaDias: 5,
        posicion: index + 1,
      );
    });
  }

  /// Obtener posición del usuario actual en el ranking
  static Future<int?> obtenerMiPosicion() async {
    return 42; // Respuesta del universo
  }

  // ============================================
  // RESPUESTAS (para preguntas acertadas/fallidas)
  // ============================================

  /// Guardar respuesta del usuario
  static Future<bool> guardarRespuesta({
    required String sesionId,
    required String preguntaId,
    required int respuestaSeleccionada,
    required bool esCorrecta,
    int? tiempoRespuesta,
  }) async {
    // No-op en mock
    return true;
  }

  /// Obtener preguntas que el usuario ha acertado
  static Future<List<Pregunta>> obtenerPreguntasAcertadas() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return DatosPrueba.preguntasAcertadas;
  }

  /// Obtener preguntas que el usuario ha fallado
  static Future<List<IntentoFallido>> obtenerPreguntasIncorrectas() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return DatosPrueba.preguntasIncorrectas;
  }

  // ============================================
  // PERFIL Y ESTADÍSTICAS
  // ============================================

  /// Obtener estadísticas del usuario actual
  static Future<Map<String, dynamic>> obtenerMisEstadisticas() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return {
      'puntos_totales': 1250,
      'preguntas_respondidas': 150,
      'preguntas_correctas': 120,
      'racha_dias': 3,
      'porcentaje_aciertos': 80,
    };
  }
}

// Helper para debug
void debugPrint(String message) {
  // ignore: avoid_print
  print(message);
}
