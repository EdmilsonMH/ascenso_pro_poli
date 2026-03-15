import 'package:ascenso_pro_poli/modelos/modelo_pregunta.dart';
import 'package:ascenso_pro_poli/pantallas/pantalla_plan_tutor_ia_personal.dart';
import 'package:ascenso_pro_poli/servicios/auth_service.dart';
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
      'analisis_materias': <Map<String, dynamic>>[
        {
          'materia': 'Constitucion Politica del Peru',
          'porcentaje': 82.0,
          'nivel': 'AVANZADO',
          'tiempo_recomendado_minutos': 20,
          'tipo': 'fortaleza',
        },
        {
          'materia': 'Codigo Penal',
          'porcentaje': 42.0,
          'nivel': 'CRITICO',
          'tiempo_recomendado_minutos': 35,
          'tipo': 'debilidad',
        },
      ],
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
        'cantidad_practica': 0,
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
          'cantidad_practica': 0,
          'tiempo_practica': 0,
          'pregunta_ids': List<String>.generate(
            36,
            (index) => 'plan_${index + 1}',
          ),
          'expandable': true,
        },
        {
          'id': 'radar_riesgo_materia',
          'titulo': 'Radar de riesgo por materia',
          'resumen': 'Detecta tus materias en rojo, ambar y verde.',
          'detalle': 'Detalle radar',
          'prompt': 'radar de riesgo por materia',
          'cta': 'Ver radar de materias',
          'color': '#FCD34D',
          'icono': 'radar',
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

  @override
  Future<Map<String, dynamic>> obtenerAnalisisCompletoPerfilDetallado({
    required String userId,
    String? categoriaUsuario,
    Map<String, dynamic>? analisisBase,
  }) async {
    return {
      'estado': 'ok',
      'mensaje': 'Analisis calculado con datos fake.',
      'tasa_acierto_global': 64.4,
      'nivel_postulante': {'nombre': 'Intermedio'},
      'distribucion_respuestas': {
        'total_eventos': 10,
        'correctas_total': 6,
        'incorrectas_total': 3,
        'omitidas_total': 1,
      },
      'distribucion_tiempos': {
        'sub20_total': 4,
        'entre20y40_total': 4,
        'mas40_total': 2,
      },
      'curva_aprendizaje': {
        'intervalo_dias': 5,
        'serie_semanal': const [
          {'porcentaje': 40.0, 'muestra': 4},
          {'porcentaje': 52.0, 'muestra': 6},
          {'porcentaje': 64.4, 'muestra': 10},
        ],
      },
      'precision_bajo_presion': {
        'accuracy_sub_20s': 58.0,
        'accuracy_general': 64.4,
      },
      'sobreconfianza': {'errores_sub20s_pct': 18.0, 'indice': 22.0},
    };
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
  Future<void> fijarFechaRegistroHace(int dias) async {
    await AuthService.updateProfile({
      'fecha_registro': DateTime.now()
          .subtract(Duration(days: dias))
          .toIso8601String(),
    });
  }

  setUp(() async {
    await AuthService.login(email: 'tester@ascensopoli.pe', password: '123456');
    await fijarFechaRegistroHace(2);
  });

  tearDown(() async {
    await AuthService.logout();
  });

  testWidgets('renderiza dashboard V2 y abre ordenes del tutor', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PantallaPlanTutorIAPersonal(iaService: _FakeTutorService()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('IA Tutor Personal'), findsOneWidget);
    expect(find.textContaining('Hoy toca avanzar con foco'), findsOneWidget);
    expect(find.text('Ordenes del tutor para hoy'), findsOneWidget);

    await tester.tap(find.text('Ordenes del tutor para hoy').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('ORDENES DEL TUTOR PARA HOY'), findsOneWidget);
    expect(find.text('PRACTICA GUIADA'), findsOneWidget);
    expect(find.text('36 preguntas con IA guiada'), findsOneWidget);
    expect(find.text('PRACTICAR AHORA'), findsOneWidget);
    expect(find.text('100 preguntas aleatorias'), findsOneWidget);
    expect(find.text('Completar'), findsAtLeastNWidgets(1));
  });

  testWidgets('practicar ahora usa 20 preguntas fuera del ciclo de 4 dias', (
    WidgetTester tester,
  ) async {
    await fijarFechaRegistroHace(3);

    await tester.pumpWidget(
      MaterialApp(
        home: PantallaPlanTutorIAPersonal(iaService: _FakeTutorService()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Ordenes del tutor para hoy'), findsOneWidget);

    await tester.tap(find.text('Ordenes del tutor para hoy').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('PRACTICAR AHORA'), findsOneWidget);
    expect(find.text('20 preguntas aleatorias'), findsOneWidget);
  });

  testWidgets('analisis completo abre panel tecnico del perfil', (
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

    await tester.tap(find.textContaining('Analisis Completo de tu Perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Analisis completo de perfil'), findsOneWidget);
    expect(find.text('1. Distribucion de respuestas'), findsOneWidget);
    expect(find.text('2. Curva de aprendizaje'), findsOneWidget);
    expect(find.textContaining('Acierto global 64.4%'), findsOneWidget);
  });

  testWidgets('radar de riesgo abre mapa semaforo de materias', (
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

    await tester.scrollUntilVisible(
      find.text('Radar de riesgo por materia'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.text('Radar de riesgo por materia'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Radar de riesgo por materia'), findsOneWidget);
    expect(
      find.text('Rojo - Puntos ciegos (<50% o sin iniciar)'),
      findsOneWidget,
    );
    expect(find.text('Constitucion Politica del Peru'), findsOneWidget);

    await tester.tap(find.text('Ambar (0)'));
    await tester.pumpAndSettle();

    expect(
      find.text('No hay materias en este semaforo con el filtro actual.'),
      findsOneWidget,
    );
  });
}
