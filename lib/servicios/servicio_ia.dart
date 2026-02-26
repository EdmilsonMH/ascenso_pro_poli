import 'dart:async';
import '../modelos/modelo_ia.dart';
import 'servicio_preguntas.dart';

class ServicioIA {
  final ServicioPreguntas _servicioPreguntas = ServicioPreguntas();

  // Simula una llamada a la API de Gemini para obtener el diagnóstico del día
  Future<DiagnosticoIA> obtenerDiagnosticoDiario() async {
    // Simulamos delay de red (como si Gemini estuviera "pensando")
    await Future.delayed(const Duration(milliseconds: 1500));

    // Obtenemos algunas preguntas reales para incluirlas en el plan
    final preguntasLegis = await _servicioPreguntas.obtenerPreguntasAleatorias(
      cantidad: 5,
      categoria: 'Legislación Policial',
    );

    return DiagnosticoIA(
      mensajeDelMentor:
          "¡Buenos días, Suboficial! He analizado tu rendimiento de ayer. Veo que tienes un dominio sólido en Derechos Humanos, pero tu tiempo de respuesta en Código Penal está por encima del promedio. Hoy nos enfocaremos en velocidad y precisión normativa.",
      nivelPreparacionGeneral: 68, // Ejemplo: 68% listo para el examen
      fortalezas: ['Derechos Humanos', 'Constitución Política', 'Ética'],
      debilidades: [
        'Régimen Disciplinario',
        'Código Penal Militar',
        'Técnicas de Intervención',
      ],
      planDeHoy: [
        RecomendacionIA(
          id: 'rec_001',
          titulo: 'Ataque Relámpago: Régimen Disciplinario',
          descripcion:
              '5 preguntas clave que suelen fallar la mayoría. Tienes 3 minutos.',
          tipo: TipoRecomendacion.repasoUrgente,
          materiaRelacionada: 'Régimen Disciplinario',
          duracionEstimadaMinutos: 3,
          preguntasSugeridas: preguntasLegis, // Usamos preguntas mock reales
        ),
        RecomendacionIA(
          id: 'rec_002',
          titulo: 'Lectura Estratégica: Art. 4 DL 1267',
          descripcion:
              'Repasa las funciones de la PNP. Es un tema recurrente en los exámenes.',
          tipo: TipoRecomendacion.lectura,
          duracionEstimadaMinutos: 10,
        ),
        RecomendacionIA(
          id: 'rec_003',
          titulo: 'Simulacro Parcial de Control',
          descripcion:
              'Evaluación rápida de 20 preguntas mixtas para medir tu retención.',
          tipo: TipoRecomendacion.simulacro,
          duracionEstimadaMinutos: 25,
        ),
      ],
    );
  }

  // Simula pedirle a Gemini un consejo específico sobre un tema
  Future<String> pedirConsejoRapido(String tema) async {
    await Future.delayed(const Duration(seconds: 1));
    return "Para dominar $tema, te sugiero crear mapas mentales de los artículos principales. Los estudiantes que visualizan la jerarquía de normas en $tema suelen mejorar su puntaje en un 30%.";
  }
}
