import 'package:ascenso_pro_poli/modelos/modelo_pregunta.dart';
import 'package:ascenso_pro_poli/pantallas/pantalla_plan_tutor_ia_personal.dart';
import 'package:ascenso_pro_poli/servicios/servicio_preguntas.dart';
import 'package:ascenso_pro_poli/servicios/tutor_ia_personal_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTutorService extends TutorIAPersonalService {
  @override
  Future<Map<String, dynamic>> analizarPerfilCompleto(
    String userId, {
    Map<String, dynamic>? perfilUsuario,
  }) async {
    return {
      'nivel_global': 'INTERMEDIO',
      'tasa_acierto': 64.4,
      'velocidad_promedio': 14.2,
      'racha_dias': 3,
      'fortalezas': <String>['Constitucion (82%)'],
      'debilidades': <String>['Codigo Penal (48%)'],
      'analisis_materias': <Map<String, dynamic>>[],
      'resumen_materias': 'Resumen de prueba',
      'diagnostico': 'Diagnostico de prueba',
      'preguntas_dominadas': 120,
      'tiempo_total_estudio': 45,
      'panel_ia': {'cards': <Map<String, dynamic>>[]},
    };
  }

  @override
  Future<Map<String, dynamic>> obtenerDashboardTutorInicio({
    required String userId,
    required Map<String, dynamic> perfilUsuario,
  }) async {
    return {
      'estado': 'ok',
      'sesion_valida': true,
      'hero': {
        'nivel': 'INTERMEDIO',
        'aprobacion': 58.2,
        'dominadas_hoy': 6,
        'racha_dias': 3,
      },
      'mision_diaria': {
        'preguntas_objetivo': 30,
        'minutos_objetivo': 40,
        'preguntas_completadas': 10,
        'minutos_completados': 15,
        'cantidad_practica': 20,
        'tiempo_practica': 25,
        'resumen': 'Vas 10/30 hoy.',
        'cta_habilitada': true,
      },
      'insights': [
        {
          'id': 'analisis_perfil',
          'titulo': 'Analisis Completo de tu Perfil',
          'resumen': 'Resumen perfil',
          'detalle': 'Detalle perfil',
          'prompt': 'dame mi plan diario',
          'cta': 'Abrir en chat',
          'color': '#FDE68A',
          'icono': 'insights',
          'expandable': true,
        },
        {
          'id': 'plan_hoy',
          'titulo': 'Ordenes del tutor para hoy',
          'resumen': 'Resumen plan',
          'detalle': 'Detalle plan',
          'prompt': 'dame mi plan diario',
          'cta': 'Abrir plan en chat',
          'color': '#BFDBFE',
          'icono': 'calendar_month',
          'expandable': true,
        },
      ],
      'atajos_chat': const ['dame mi plan diario', 'que estudiar hoy'],
    };
  }

  @override
  Future<String> enviarMensajeTutor({
    required String mensaje,
    Map<String, dynamic>? contexto,
  }) async {
    return 'respuesta fake';
  }
}

class _FakePreguntasService extends ServicioPreguntas {
  @override
  Future<List<Materia>> obtenerMaterias() async {
    return const [
      Materia(id: 'm1', nombre: 'Constitucion Politica del Peru'),
      Materia(id: 'm2', nombre: 'Codigo Penal'),
      Materia(id: 'm3', nombre: 'Ley N 31873'),
    ];
  }

  @override
  Future<List<Materia>> obtenerMateriasPorCategoria({
    required String categoria,
  }) {
    return obtenerMaterias();
  }
}

void main() {
  testWidgets('renderiza dashboard V2 y abre ordenes del tutor', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PantallaPlanTutorIAPersonal(iaService: _FakeTutorService()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('IA Tutor Personal'), findsOneWidget);
    expect(find.textContaining('Hoy toca avanzar con foco'), findsOneWidget);
    expect(find.text('ORDENES DEL TUTOR PARA HOY'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('ORDENES DEL TUTOR PARA HOY'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.text('ORDENES DEL TUTOR PARA HOY'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Practica guiada'), findsOneWidget);
    expect(find.text('Iniciar practica'), findsOneWidget);
  });

  testWidgets('analisis completo abre mapa semaforo de materias', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PantallaPlanTutorIAPersonal(
          iaService: _FakeTutorService(),
          servicioPreguntas: _FakePreguntasService(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('ANALISIS COMPLETO DE TU'));
    await tester.pumpAndSettle();

    expect(find.text('Mapa de temas del prospecto'), findsOneWidget);
    expect(find.textContaining('Rojo'), findsAtLeastNWidgets(1));
    expect(
      find.textContaining('Constitucion Politica del Peru'),
      findsOneWidget,
    );

    await tester.tap(find.textContaining('Verde ('));
    await tester.pumpAndSettle();

    expect(
      find.text('No hay materias en este semaforo con el filtro actual.'),
      findsOneWidget,
    );
  });
}
