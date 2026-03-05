import 'package:flutter_test/flutter_test.dart';
import 'package:ascenso_pro_poli/servicios/tutor_ia_personal_service.dart';

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
  });
}
