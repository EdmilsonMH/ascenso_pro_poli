import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'auth_service.dart';
import 'servicio_preguntas.dart';
import 'navigation_service.dart';
import '../pantallas/pantalla_practica.dart';

/// Servicio para manejar notificaciones programadas y alarmas
class ServicioNotificacionesProgramadas {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Inicializar el servicio de notificaciones
  static Future<void> initialize() async {
    if (_initialized) return;

    // Inicializar zonas horarias
    tz.initializeTimeZones();
    final dynamic currentTimeZone = await FlutterTimezone.getLocalTimezone();

    String tzName = '';
    if (currentTimeZone is String) {
      tzName = currentTimeZone;
    } else {
      // Intentar extraer el nombre si es un objeto (común en algunas versiones)
      // O convertir a string y limpiar si tiene formato "TimezoneInfo(id, ...)"
      final rawStr = currentTimeZone.toString();
      if (rawStr.contains('(') && rawStr.contains(')')) {
        tzName = rawStr.split('(')[1].split(',')[0].trim();
      } else {
        tzName = rawStr;
      }
    }

    try {
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (e) {
      debugPrint("Error al establecer ubicación horaria ($tzName): $e");
      // Fallback a America/Lima si falla
      tz.setLocalLocation(tz.getLocation('America/Lima'));
    }

    // Inicializar Android Alarm Manager
    if (!kIsWeb) {
      try {
        await AndroidAlarmManager.initialize();
      } catch (e) {
        debugPrint("AndroidAlarmManager no disponible: $e");
      }
    }

    // Configuración de Android
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
  }

  /// Manejar tap en notificación
  static void _onNotificationTapped(NotificationResponse response) async {
    if (response.payload == 'practice_reminder' ||
        response.payload == 'practice_alarm' ||
        response.payload == 'session_reminder') {
      final context = navigatorKey.currentContext;
      if (context == null) return;

      // Mostrar loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      try {
        final perfil = await AuthService.getCurrentUserProfile();
        final String categoria = perfil?['categoria'] ?? 'Oficiales PNP';
        final int tiempoMeta = perfil?['meta_diaria_minutos'] ?? 30;
        final int cantidadPreguntas = (tiempoMeta * 100 / 120).round();

        final servicioPreguntas = ServicioPreguntas();
        final preguntas = await servicioPreguntas.obtenerPreguntasAleatorias(
          cantidad: cantidadPreguntas,
          categoria: categoria,
        );

        if (context.mounted) Navigator.pop(context); // Cerrar loading

        if (preguntas.isEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No hay preguntas disponibles para iniciar'),
              ),
            );
          }
          return;
        }

        // Navegar a la pantalla de práctica
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (context) => PantallaPractica(
                tiempoLimiteSegundos: tiempoMeta * 60,
                preguntas: preguntas,
                esModoPractica: false,
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) Navigator.pop(context);
        debugPrint('Error al iniciar práctica desde notificación: $e');
      }
    }
  }

  /// Programar notificaciones diarias según preferencias del usuario
  static Future<void> programarNotificacionesDiarias() async {
    await initialize();

    final perfil = await AuthService.getCurrentUserProfile();
    if (perfil == null) return;

    final bool notificarMeta = perfil['notificar_meta'] ?? false;
    if (!notificarMeta) {
      await cancelarTodasLasNotificaciones();
      // No retornamos aquí porque igual queremos procesar las sesiones extras si existen
    }

    final String horaRecordatorio =
        perfil['hora_recordatorio_meta'] ?? '08:00:00';
    final List<dynamic> diasEstudio =
        perfil['dias_estudio'] ?? ['L', 'M', 'X', 'J', 'V'];

    // Convertir hora string a Time
    final parts = horaRecordatorio.split(':');
    final hora = (int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 8)
        .clamp(0, 23)
        .toInt();
    final minuto = (int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0)
        .clamp(0, 59)
        .toInt();

    // Programar para cada día de la semana
    for (int i = 1; i <= 7; i++) {
      final diaSemana = _obtenerLetraDia(i);
      if (diasEstudio.contains(diaSemana)) {
        if (notificarMeta) {
          await _programarNotificacionSemanal(
            id: i,
            diaSemana: i,
            hora: hora,
            minuto: minuto,
          );
        } else {
          await _notificationsPlugin.cancel(i);
          await _notificationsPlugin.cancel(i + 100);
        }

        // Programar sesiones adicionales si están activas
        final bool notificarSesiones = perfil['notificar_sesiones'] ?? false;
        if (notificarSesiones) {
          final List<dynamic>? savedHorarios = perfil['horarios_sesiones'];
          if (savedHorarios != null) {
            for (int j = 0; j < savedHorarios.length; j++) {
              final hParts = savedHorarios[j].toString().split(':');
              final horaSesion = (int.tryParse(hParts.isNotEmpty ? hParts[0] : '') ?? hora)
                  .clamp(0, 23)
                  .toInt();
              final minutoSesion = (int.tryParse(hParts.length > 1 ? hParts[1] : '') ?? minuto)
                  .clamp(0, 59)
                  .toInt();
              await _programarSesionExtraSemanal(
                id: i * 10 + j + 500, // ID único por día y sesión
                diaSemana: i,
                hora: horaSesion,
                minuto: minutoSesion,
                numeroSesion: j + 1,
              );
            }
          }
        } else {
          // Cancelar sesiones extras para este día
          for (int j = 0; j < 5; j++) {
            await _notificationsPlugin.cancel(i * 10 + j + 500);
            await _notificationsPlugin.cancel(i * 10 + j + 600);
          }
        }
      } else {
        // Cancelar todas las notificaciones de este día si no está seleccionado
        await _notificationsPlugin.cancel(i);
        await _notificationsPlugin.cancel(i + 100);
        for (int j = 0; j < 5; j++) {
          await _notificationsPlugin.cancel(i * 10 + j + 500);
          await _notificationsPlugin.cancel(i * 10 + j + 600);
        }
      }
    }
  }

  /// Programar notificación semanal para un día específico
  static Future<void> _programarNotificacionSemanal({
    required int id,
    required int diaSemana,
    required int hora,
    required int minuto,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hora,
      minuto,
    );

    while (scheduledDate.weekday != diaSemana) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    }

    await _safeZonedSchedule(
      id,
      '⏰ Hora de estudiar',
      'Es momento de realizar tu práctica diaria. ¡Vamos!',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder',
          'Recordatorios Diarios',
          channelDescription: 'Notificaciones para recordar tu meta diaria',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: 'practice_reminder',
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );

    // Alarma de seguimiento (10 minutos después)
    await _programarAlarmaSeguimiento(
      id: id + 100,
      scheduledDate: scheduledDate.add(const Duration(minutes: 10)),
    );
  }

  /// Programar sesión extra semanal
  static Future<void> _programarSesionExtraSemanal({
    required int id,
    required int diaSemana,
    required int hora,
    required int minuto,
    required int numeroSesion,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hora,
      minuto,
    );

    while (scheduledDate.weekday != diaSemana) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    }

    await _safeZonedSchedule(
      id,
      '📚 Sesión $numeroSesion de estudio',
      'Es hora de realizar tu sesión programada. ¡Sigue así!',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'session_reminder',
          'Sesiones Programadas',
          channelDescription: 'Recordatorios de tus sesiones de estudio extras',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: 'session_reminder',
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );

    // Alarma de seguimiento (10 minutos después)
    await _programarAlarmaSeguimiento(
      id: id + 100,
      scheduledDate: scheduledDate.add(const Duration(minutes: 10)),
    );
  }

  /// Programar alarma de seguimiento si no ha iniciado práctica
  static Future<void> _programarAlarmaSeguimiento({
    required int id,
    required tz.TZDateTime scheduledDate,
  }) async {
    await _safeZonedSchedule(
      id,
      '🔔 ¡No olvides tu práctica!',
      'Hora de realizar la práctica. ¡Haz clic aquí para empezar!',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'practice_alarm',
          'Alarmas de Práctica',
          channelDescription: 'Alarmas cuando no has iniciado tu práctica',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
        ),
      ),
      payload: 'practice_alarm',
    );
  }

  static Future<void> _safeZonedSchedule(
    int id,
    String? title,
    String? body,
    tz.TZDateTime scheduledDate,
    NotificationDetails notificationDetails, {
    required String payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      );
    } catch (e) {
      debugPrint(
        'Exact alarm no disponible para notificación $id, '
        'se programa modo inexacto: $e',
      );
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      );
    }
  }

  /// Cancelar todas las notificaciones programadas
  static Future<void> cancelarTodasLasNotificaciones() async {
    await initialize();
    await _notificationsPlugin.cancelAll();
  }

  /// Marcar que el usuario inició práctica (cancelar alarma pendiente)
  static Future<void> marcarPracticaIniciada() async {
    await initialize();

    // Solo cancelar alarmas de seguimiento del día actual para no perder
    // recordatorios de los demás días de estudio.
    final int diaActual = DateTime.now().weekday; // 1=Lunes ... 7=Domingo
    await _notificationsPlugin.cancel(diaActual + 100);
    for (int j = 0; j < 5; j++) {
      await _notificationsPlugin.cancel(diaActual * 10 + j + 600);
    }
  }

  /// Obtener letra del día de la semana (1=L, 7=D, compatible con ISO)
  static String _obtenerLetraDia(int dia) {
    switch (dia) {
      case 1:
        return 'L';
      case 2:
        return 'M';
      case 3:
        return 'X';
      case 4:
        return 'J';
      case 5:
        return 'V';
      case 6:
        return 'S';
      case 7:
        return 'D';
      default:
        return '';
    }
  }

  /// Solicitar permisos de notificación (Android 13+)
  static Future<bool> solicitarPermisos() async {
    try {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidImplementation != null) {
        final granted = await androidImplementation
            .requestNotificationsPermission();
        return granted ?? false;
      }
      return true;
    } catch (e) {
      debugPrint('No se pudo solicitar permisos de notificación: $e');
      return false;
    }
  }
}
