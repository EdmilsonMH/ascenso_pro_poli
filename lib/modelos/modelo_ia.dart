import 'modelo_pregunta.dart';

// Enum para identificar el tipo de recomendación que da la IA
enum TipoRecomendacion { repasoUrgente, nuevoTema, simulacro, lectura }

// Representa una recomendación de estudio generada por Gemini
class RecomendacionIA {
  final String id;
  final String titulo;
  final String descripcion;
  final TipoRecomendacion tipo;
  final String? materiaRelacionada;
  final int duracionEstimadaMinutos;
  final List<Pregunta>?
  preguntasSugeridas; // Si la recomendación incluye preguntas directas

  RecomendacionIA({
    required this.id,
    required this.titulo,
    required this.descripcion,
    required this.tipo,
    this.materiaRelacionada,
    required this.duracionEstimadaMinutos,
    this.preguntasSugeridas,
  });
}

// Representa el análisis diario que hace Gemini sobre el usuario
class DiagnosticoIA {
  final String mensajeDelMentor; // El texto "hablado" por la IA
  final int nivelPreparacionGeneral; // 0-100
  final List<String> fortalezas;
  final List<String> debilidades;
  final List<RecomendacionIA> planDeHoy;

  DiagnosticoIA({
    required this.mensajeDelMentor,
    required this.nivelPreparacionGeneral,
    required this.fortalezas,
    required this.debilidades,
    required this.planDeHoy,
  });
}
