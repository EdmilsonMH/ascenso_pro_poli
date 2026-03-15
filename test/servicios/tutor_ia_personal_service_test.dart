import 'package:flutter_test/flutter_test.dart';
import 'package:ascenso_pro_poli/servicios/tutor_ia_personal_service.dart';

class _FakeCoachMemoriaService extends TutorIAPersonalService {
  @override
  Future<Map<String, dynamic>> obtenerCoachMemoriaDetalle({
    required String userId,
  }) async {
    return {
      'estado': 'ok',
      'resumen': 'Indice de memoria 68.0% (Necesita repaso).',
      'plan_diario': {'nuevas': 20, 'fallidas': 12, 'repaso': 14},
      'pregunta_ids_prioritarias': List<String>.generate(
        15,
        (index) => 'prio_${index + 1}',
      ),
      'pregunta_ids_repaso': List<String>.generate(
        6,
        (index) => 'repaso_${index + 1}',
      ),
      'pregunta_ids_fallidas': List<String>.generate(
        5,
        (index) => 'fallida_${index + 1}',
      ),
      'riesgos': const [
        {
          'materia': 'Codigo Penal',
          'tasa': 42.0,
          'tendencia': 'empeorando',
          'semaforo': 'rojo',
        },
        {
          'materia': 'Ley N 31873',
          'tasa': 55.0,
          'tendencia': 'estable',
          'semaforo': 'amarillo',
        },
      ],
      'recordatorio_repaso': 'Tienes 6 preguntas sin repasar hace 8 dias.',
      'total_criticas': 5,
      'total_repaso_vencidas': 7,
    };
  }
}

void main() {
  group('TutorIAPersonalService dashboard', () {
    test(
      'obtenerDashboardTutorInicio devuelve fallback con sesion invalida',
      () async {
        final service = TutorIAPersonalService();

        final result = await service.obtenerDashboardTutorInicio(
          userId: 'user_test_id',
          perfilUsuario: const <String, dynamic>{},
        );

        expect(result['estado'], isNotNull);
        expect(result['sesion_valida'], isFalse);
        expect(result['hero'], isA<Map<String, dynamic>>());
        expect(result['mision_diaria'], isA<Map<String, dynamic>>());
        expect(result['insights'], isA<List>());
      },
    );

    test(
      'obtenerResumenPlanDiarioEstructurado retorna card fallback en sesion invalida',
      () async {
        final service = TutorIAPersonalService();

        final card = await service.obtenerResumenPlanDiarioEstructurado(
          userId: 'user_test_id',
        );

        expect(card['id'], 'plan_hoy');
        expect(card['prompt'], 'dame mi plan diario');
        expect(card['titulo'], isNotEmpty);
      },
    );

    test(
      'construirMensajeMotivacionalEstructurado entrega card consistente',
      () {
        final service = TutorIAPersonalService();

        final card = service.construirMensajeMotivacionalEstructurado(
          progreso: {
            'preguntas_dominadas': 280,
            'porcentaje_completado': 9.3,
            'ritmo_actual_dia': 14.2,
            'ritmo_necesario_dia': 20.0,
            'esta_atrasado': true,
          },
          probabilidad: {'probabilidad_aprobacion': 62.5},
        );

        expect(card['id'], 'mensaje_personal');
        expect(card['prompt'], 'dame un mensaje motivacional');
        expect((card['resumen'] as String).isNotEmpty, isTrue);
        expect(
          (card['detalle'] as String).contains('Probabilidad estimada'),
          isTrue,
        );
      },
    );

    test(
      'obtenerCoachMemoriaEstructurado construye card accionable con ids tacticos',
      () async {
        final service = _FakeCoachMemoriaService();

        final card = await service.obtenerCoachMemoriaEstructurado(
          userId: 'usuario_real',
        );

        expect(card['id'], 'coach_memoria');
        expect(card['pregunta_ids'], isA<List<String>>());
        expect((card['pregunta_ids'] as List<String>).length, 15);
        expect(card['preguntas_repaso_ids'], isA<List<String>>());
        expect((card['preguntas_repaso_ids'] as List<String>).length, 6);
        expect(card['materias_prioritarias'], contains('Codigo Penal'));
        expect(card['cantidad_practica'], 15);
        expect((card['tiempo_practica'] as int) > 0, isTrue);
      },
    );
  });
}
