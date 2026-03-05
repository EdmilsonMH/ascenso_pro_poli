import 'package:ascenso_pro_poli/modelos/tutor_dashboard_inicio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TutorDashboardInicio fallback tiene estructura valida', () {
    final fallback = TutorDashboardInicio.fallback();
    final map = fallback.toMap();

    expect(map['hero'], isA<Map<String, dynamic>>());
    expect(map['mision_diaria'], isA<Map<String, dynamic>>());
    expect(map['insights'], isA<List>());
    expect(map['atajos_chat'], isA<List>());
  });
}
