// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:ascenso_pro_poli/main.dart';

void main() {
  testWidgets('Smoke test de inicio', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MiAplicacion());

    // Verify that our registration screen shows up.
    expect(find.text('Crear Cuenta'), findsOneWidget);
    expect(find.text('Iniciar Sesión'), findsOneWidget);
  });
}
