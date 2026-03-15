import 'package:ascenso_pro_poli/modelos/tutor_dashboard_inicio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TutorInsightCard.fromMap', () {
    test('reconoce payload enriquecido de coach de velocidad', () {
      final card = TutorInsightCard.fromMap({
        'id': 'coach_velocidad',
        'titulo': 'Coach de Velocidad',
        'preguntas_lentas_ids': ['v1', 'v2', 'v3'],
        'materias_tiempo': const [
          {'materia': 'Codigo Penal', 'promedio_segundos': 24.1},
          {'materia': 'Ley N 31873', 'promedio_segundos': 21.4},
        ],
      });

      expect(card.preguntaIds, ['v1', 'v2', 'v3']);
      expect(card.materia, 'Codigo Penal');
      expect(card.materiasPrioritarias, ['Codigo Penal', 'Ley N 31873']);
    });

    test('reconoce payload enriquecido de coach de memoria', () {
      final card = TutorInsightCard.fromMap({
        'id': 'coach_memoria',
        'titulo': 'Coach de Memoria',
        'pregunta_ids_prioritarias': ['m1', 'm2', 'm3'],
        'pregunta_ids_repaso': ['r1', 'r2'],
        'riesgos': const [
          {
            'materia': 'Derechos Humanos',
            'tasa': 38.0,
            'tendencia': 'empeorando',
            'semaforo': 'rojo',
          },
        ],
      });

      expect(card.preguntaIds, ['m1', 'm2', 'm3']);
      expect(card.preguntasRepasoIds, ['r1', 'r2']);
      expect(card.materia, 'Derechos Humanos');
      expect(card.materiasPrioritarias, ['Derechos Humanos']);
      expect(card.riesgos.single.semaforo, 'rojo');
    });
  });
}
