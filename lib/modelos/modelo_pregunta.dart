/// Modelo de Pregunta compatible con Supabase
class Pregunta {
  final String id;
  final int numero;
  final String texto;
  final List<String> opciones;
  final int indiceRespuestaCorrecta;
  final String explicacion;
  final String?materiaId;
  final String materia;
  final String categoria;
  final String dificultad;

  const Pregunta({
    required this.id,
    required this.numero,
    required this.texto,
    required this.opciones,
    required this.indiceRespuestaCorrecta,
    required this.explicacion,
    this.materiaId,
    required this.materia,
    required this.categoria,
    this.dificultad = 'Media',
  });

  /// Crea una Pregunta desde un mapa de Supabase
  factory Pregunta.fromSupabase(Map<String, dynamic> json) {
    // Convertir respuesta_correcta (A, B, C, D) a índice (0, 1, 2, 3)
    final respuestaLetra = json['respuesta_correcta'] as String;
    final indice = respuestaLetra.codeUnitAt(0) - 'A'.codeUnitAt(0);

    return Pregunta(
      id: json['id'] as String,
      numero: json['numero'] as int,
      texto: json['texto'] as String,
      opciones: [
        json['opcion_a'] as String,
        json['opcion_b'] as String,
        json['opcion_c'] as String,
        json['opcion_d'] as String,
      ],
      indiceRespuestaCorrecta: indice,
      explicacion: json['explicacion'] as String? ?? '',
      materiaId: json['materia_id'] as String?,
      materia:
          json['materia_nombre'] as String? ?? 
          (json['materias'] != null
              ? json['materias']['nombre']
              : 'Sin materia'),
      categoria: json['categoria'] as String,
      dificultad: json['dificultad'] as String? ?? 'Media',
    );
  }

  /// Convierte a mapa para enviar a Supabase
  Map<String, dynamic> toSupabase() {
    String opcionSegura(int index) => index < opciones.length ?opciones[index] : '';
    return {
      'id': id,
      'numero': numero,
      'texto': texto,
      'opcion_a': opcionSegura(0),
      'opcion_b': opcionSegura(1),
      'opcion_c': opcionSegura(2),
      'opcion_d': opcionSegura(3),
      'respuesta_correcta': String.fromCharCode(65 + indiceRespuestaCorrecta),
      'explicacion': explicacion,
      'materia_id': materiaId,
      'categoria': categoria,
      'dificultad': dificultad,
    };
  }

  /// Obtiene la respuesta correcta como letra (A, B, C, D)
  String get respuestaCorrectaLetra => String.fromCharCode(65 + indiceRespuestaCorrecta);

  /// Obtiene el texto de la respuesta correcta
  String get textoRespuestaCorrecta => opciones[indiceRespuestaCorrecta];

  @override
  String toString() => 'Pregunta($numero: $texto)';
}

/// Modelo para un intento fallido
class IntentoFallido {
  final Pregunta pregunta;
  final int indiceIncorrectoSeleccionado;
  final DateTime?fechaIntento;

  IntentoFallido({
    required this.pregunta,
    required this.indiceIncorrectoSeleccionado,
    this.fechaIntento,
  });

  factory IntentoFallido.fromSupabase(Map<String, dynamic> json) {
    final respuestaLetra = json['respuesta_seleccionada'] as String;
    final indice = respuestaLetra.codeUnitAt(0) - 'A'.codeUnitAt(0);

    return IntentoFallido(
      pregunta: Pregunta.fromSupabase(json['preguntas']),
      indiceIncorrectoSeleccionado: indice,
      fechaIntento: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  String get respuestaSeleccionadaLetra =>
      String.fromCharCode(65 + indiceIncorrectoSeleccionado);
}

/// Modelo para una materia
class Materia {
  final String id;
  final String nombre;
  final String?descripcion;
  final String icono;
  final String color;
  final int orden;

  const Materia({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.icono = 'book',
    this.color = '#3B82F6',
    this.orden = 0,
  });

  factory Materia.fromSupabase(Map<String, dynamic> json) {
    return Materia(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      descripcion: json['descripcion'] as String?,
      icono: json['icono'] as String? ?? 'book',
      color: json['color'] as String? ?? '#3B82F6',
      orden: json['orden'] as int? ?? 0,
    );
  }
}

/// Modelo para sesión de práctica
class SesionPractica {
  final String id;
  final int totalPreguntas;
  final int preguntasCorrectas;
  final int preguntasIncorrectas;
  final int?tiempoTotalSegundos;
  final bool completada;
  final DateTime fechaCreacion;
  final DateTime?fechaFinalizacion;

  const SesionPractica({
    required this.id,
    required this.totalPreguntas,
    this.preguntasCorrectas = 0,
    this.preguntasIncorrectas = 0,
    this.tiempoTotalSegundos,
    this.completada = false,
    required this.fechaCreacion,
    this.fechaFinalizacion,
  });

  factory SesionPractica.fromSupabase(Map<String, dynamic> json) {
    return SesionPractica(
      id: json['id'] as String,
      totalPreguntas: json['total_preguntas'] as int,
      preguntasCorrectas: json['preguntas_correctas'] as int? ?? 0,
      preguntasIncorrectas: json['preguntas_incorrectas'] as int? ?? 0,
      tiempoTotalSegundos: json['tiempo_total_segundos'] as int?,
      completada: json['completada'] as bool? ?? false,
      fechaCreacion: DateTime.parse(json['created_at']),
      fechaFinalizacion: json['finished_at'] != null
          ? DateTime.parse(json['finished_at'])
          : null,
    );
  }

  double get porcentajeAciertos {
    if (totalPreguntas == 0) return 0;
    return (preguntasCorrectas / totalPreguntas) * 100;
  }

  Duration get duracion {
    return Duration(seconds: tiempoTotalSegundos ??0);
  }
}

/// Modelo para usuario
class Usuario {
  final String id;
  final String email;
  final String?nombreCompleto;
  final String?categoria;
  final String?codigoReferido;
  final int puntosTotales;
  final int preguntasRespondidas;
  final int preguntasCorrectas;
  final int rachaDias;
  final DateTime?ultimoEstudio;

  const Usuario({
    required this.id,
    required this.email,
    this.nombreCompleto,
    this.categoria,
    this.codigoReferido,
    this.puntosTotales = 0,
    this.preguntasRespondidas = 0,
    this.preguntasCorrectas = 0,
    this.rachaDias = 0,
    this.ultimoEstudio,
  });

  factory Usuario.fromSupabase(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'] as String,
      email: json['email'] as String,
      nombreCompleto: json['nombre_completo'] as String?,
      categoria: json['categoria'] as String?,
      codigoReferido: json['codigo_referido'] as String?,
      puntosTotales: json['puntos_totales'] as int? ?? 0,
      preguntasRespondidas: json['preguntas_respondidas'] as int? ?? 0,
      preguntasCorrectas: json['preguntas_correctas'] as int? ?? 0,
      rachaDias: json['racha_dias'] as int? ?? 0,
      ultimoEstudio: json['ultimo_estudio'] != null
          ? DateTime.parse(json['ultimo_estudio'])
          : null,
    );
  }

  double get porcentajeAciertos {
    if (preguntasRespondidas == 0) return 0;
    return (preguntasCorrectas / preguntasRespondidas) * 100;
  }
}

/// Modelo para el ranking
class RankingUsuario {
  final String id;
  final String?nombreCompleto;
  final String?categoria;
  final int puntosTotales;
  final int preguntasRespondidas;
  final int preguntasCorrectas;
  final double porcentajeAciertos;
  final int rachaDias;
  final int posicion;

  const RankingUsuario({
    required this.id,
    this.nombreCompleto,
    this.categoria,
    this.puntosTotales = 0,
    this.preguntasRespondidas = 0,
    this.preguntasCorrectas = 0,
    this.porcentajeAciertos = 0,
    this.rachaDias = 0,
    required this.posicion,
  });

  factory RankingUsuario.fromSupabase(Map<String, dynamic> json) {
    return RankingUsuario(
      id: json['id'] as String,
      nombreCompleto: json['nombre_completo'] as String?,
      categoria: json['categoria'] as String?,
      puntosTotales: json['puntos_totales'] as int? ?? 0,
      preguntasRespondidas: json['preguntas_respondidas'] as int? ?? 0,
      preguntasCorrectas: json['preguntas_correctas'] as int? ?? 0,
      porcentajeAciertos:
          (json['porcentaje_aciertos'] as num?)?.toDouble() ??0,
      rachaDias: json['racha_dias'] as int? ?? 0,
      posicion: json['posicion'] as int,
    );
  }
}

// =====================================================
// DATOS DE PRUEBA (Temporales hasta conectar con Supabase)
// =====================================================

class DatosPrueba {
  static const List<Pregunta> preguntas = [
    Pregunta(
      id: '1',
      numero: 1,
      texto:
          '¿Cuál es el artículo de la Constitución que establece que la defensa de la persona humana y el respeto de su dignidad son el fin supremo de la sociedad y del Estado?',
      opciones: ['Artículo 1º', 'Artículo 2º', 'Artículo 3º', 'Artículo 44º'],
      indiceRespuestaCorrecta: 0,
      explicacion:
          'El Artículo 1º de la Constitución Política del Perú establece que la defensa de la persona humana y el respeto de su dignidad son el fin supremo de la sociedad y del Estado.',
      categoria: 'Ambos',
      materia: 'Derecho Constitucional y Derechos Humanos',
    ),
    Pregunta(
      id: '2',
      numero: 2,
      texto:
          '¿Quién es el Jefe Supremo de las Fuerzas Armadas y de la Policía Nacional del Perú?',
      opciones: [
        'El Ministro del Interior',
        'El Comandante General de la PNP',
        'El Presidente de la República',
        'El Presidente del Congreso',
      ],
      indiceRespuestaCorrecta: 2,
      explicacion:
          'Según la Constitución, el Presidente de la República es el Jefe Supremo de las Fuerzas Armadas y de la Policía Nacional.',
      categoria: 'Ambos',
      materia: 'Derecho Constitucional',
    ),
    Pregunta(
      id: '3',
      numero: 3,
      texto:
          '¿Cuál es el plazo máximo de detención policial en caso de flagrante delito?',
      opciones: ['24 horas', '48 horas', '72 horas', '7 días'],
      indiceRespuestaCorrecta: 1,
      explicacion:
          'La Constitución establece que la detención no durará más del tiempo estrictamente necesario para la realización de las investigaciones y, en todo caso, detención policial no puede exceder de 48 horas.',
      categoria: 'Ambos',
      materia: 'Derecho Procesal Penal',
    ),
    Pregunta(
      id: '4',
      numero: 4,
      texto: '¿Qué son los derechos fundamentales?',
      opciones: [
        'Derechos que solo tienen los ciudadanos peruanos',
        'Derechos inherentes a la persona humana reconocidos por la Constitución',
        'Derechos que se obtienen con la mayoría de edad',
        'Derechos exclusivos de funcionarios públicos',
      ],
      indiceRespuestaCorrecta: 1,
      explicacion:
          'Los derechos fundamentales son aquellos inherentes a la persona humana, reconocidos y protegidos por la Constitución.',
      categoria: 'Ambos',
      materia: 'Constitución y Derechos Humanos',
    ),
    Pregunta(
      id: '5',
      numero: 5,
      texto: '¿Qué es la flagrancia delictiva?',
      opciones: [
        'Cuando se sospecha de alguien por sus antecedentes',
        'Cuando el delito es descubierto inmediatamente después de cometido',
        'Cuando existe una orden judicial de detención',
        'Cuando se investiga un delito pasado',
      ],
      indiceRespuestaCorrecta: 1,
      explicacion:
          'La flagrancia ocurre cuando el agente es descubierto realizando el hecho punible o acaba de cometerlo, siendo posible su detención inmediata.',
      categoria: 'Oficiales',
      materia: 'Derecho Penal Aplicado',
    ),
    Pregunta(
      id: '6',
      numero: 6,
      texto: '¿Cuál es la función principal de la Policía Nacional del Perú?',
      opciones: [
        'Hacer leyes para la seguridad ciudadana',
        'Juzgar a los delincuentes',
        'Garantizar, mantener y restablecer el orden interno',
        'Administrar los centros penitenciarios',
      ],
      indiceRespuestaCorrecta: 2,
      explicacion:
          'La finalidad fundamental de la PNP es garantizar, mantener y restablecer el orden interno. Presta protección y ayuda a las personas y a la comunidad.',
      categoria: 'Ambos',
      materia: 'Función Policial',
    ),
  ];

  // Simulamos persistencia en memoria
  static List<Pregunta> preguntasAcertadas = [
    preguntas[3],
    preguntas[4],
    preguntas[0],
    preguntas[1],
    preguntas[2],
    preguntas[5],
  ];

  static List<IntentoFallido> preguntasIncorrectas = [
    IntentoFallido(pregunta: preguntas[2], indiceIncorrectoSeleccionado: 0),
  ];

  static List<String> obtenerMateriasUnicas() {
    return preguntas.map((e) => e.materia).toSet().toList();
  }

  static int tiempoEstudioDiarioMinutos = 30;

  static List<Pregunta> obtenerPreguntasPorCategoria(String categoria) {
    return preguntas;
  }

  static List<Pregunta> obtenerPreguntasAleatorias({
    int cantidad = 20,
    required String categoria,
  }) {
    // 1. Filtrar (si tuviéramos lógica real de filtro por categoría)
    // Por ahora usamos todas las preguntas del mock
    final todas = List<Pregunta>.from(preguntas);

    // 2. Mezclar aleatoriamente
    todas.shuffle();

    // 3. Tomar la cantidad solicitada (o todas si hay menos)
    if (todas.length <= cantidad) {
      return todas;
    }
    return todas.sublist(0, cantidad);
  }
}
