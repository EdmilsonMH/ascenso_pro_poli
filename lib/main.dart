import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Imports absolutos para evitar conflictos de instancias Singleton
import 'package:ascenso_pro_poli/tema/tema_aplicacion.dart';
import 'package:ascenso_pro_poli/pantallas/pantalla_registro.dart';
import 'package:ascenso_pro_poli/pantallas/pantalla_inicio_sesion.dart';
import 'package:ascenso_pro_poli/pantallas/pantalla_login.dart';
import 'package:ascenso_pro_poli/pantallas/pantalla_principal.dart';
import 'package:ascenso_pro_poli/servicios/auth_service.dart';
import 'package:ascenso_pro_poli/servicios/audio_handler.dart';
import 'package:ascenso_pro_poli/servicios/servicio_notificaciones_programadas.dart';
import 'package:ascenso_pro_poli/servicios/servicio_progreso.dart';
import 'package:ascenso_pro_poli/servicios/navigation_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- CONFIGURACIÓN DE SUPABASE ---
  // Se recomienda pasar las credenciales por --dart-define
  // Ejemplo:
  // flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
  const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://saooclhjmdsrmosikknu.supabase.co',
  );
  const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNhb29jbGhqbWRzcm1vc2lra251Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAxNTg1MjEsImV4cCI6MjA4NTczNDUyMX0.dFuaUfYie1YTYlXhBzaHpaIzHBNZlb3jSVUPH1m63Mg',
  );

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  } else {
    debugPrint(
      "ℹ️ Supabase no configurado. El sistema IA funcionará en modo MOCK. "
      "Configura SUPABASE_URL y SUPABASE_ANON_KEY con --dart-define.",
    );
  }
  // ---------------------------------

  // Inicializar Audio Service
  try {
    debugPrint("Iniciando servicio de audio (AudioService)...");
    audioHandler = await AudioService.init(
      builder: () => AudioPlayerHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.ascensopolicia.audio_channel',
        androidNotificationChannelName: 'Audio Estudio',
        androidNotificationOngoing: true,
      ),
    );
    debugPrint("Servicio de audio iniciado con éxito.");
  } catch (e) {
    debugPrint("ERROR CRÍTICO al iniciar AudioService: $e");
    errorDeInicializacion = e.toString();

    // FALLBACK: Si el servicio nativo falla (común en emuladores o por config),
    // iniciamos el handler localmente para que funcione dentro de la app (sin controles en lockscreen).
    debugPrint("⚠️ Activando modo FALLBACK para audio.");
    try {
      audioHandler = AudioPlayerHandler();
    } catch (e2) {
      debugPrint("ERROR FATAL en fallback: $e2");
      errorDeInicializacion = "$e\n\nFallback Error: $e2";
    }
  }

  // Inicializar servicio de notificaciones programadas
  try {
    debugPrint("Iniciando servicio de notificaciones...");
    await ServicioNotificacionesProgramadas.initialize();
    await ServicioNotificacionesProgramadas.solicitarPermisos();
    debugPrint("Servicio de notificaciones iniciado con éxito.");
  } catch (e) {
    debugPrint("Error al iniciar notificaciones: $e");
  }

  runApp(const MiAplicacion());
}

class MiAplicacion extends StatelessWidget {
  const MiAplicacion({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Ascenso PNP',
      debugShowCheckedModeBanner: false,
      theme: TemaAplicacion.temaClaro,
      // Gate de arranque: decide Login vs Inicio según sesión actual.
      home: const PantallaArranque(),
      routes: {
        '/login': (context) => const PantallaLogin(),
        '/register': (context) => const PantallaRegistro(),
        '/old-login': (context) => const PantallaInicioSesion(),
      },
    );
  }
}

class PantallaArranque extends StatefulWidget {
  const PantallaArranque({super.key});

  @override
  State<PantallaArranque> createState() => _PantallaArranqueState();
}

class _PantallaArranqueState extends State<PantallaArranque> {
  late final Future<Widget> _pantallaInicialFuture;

  @override
  void initState() {
    super.initState();
    _pantallaInicialFuture = _resolverPantallaInicial();
  }

  Future<Widget> _resolverPantallaInicial() async {
    try {
      if (!AuthService.isLoggedIn) {
        return const PantallaPrincipal(
          categoriaUsuario: 'Ambos',
          esInvitado: true,
        );
      }

      final perfilCompleto = await AuthService.isProfileComplete();
      if (!perfilCompleto) {
        return const PantallaRegistro(completarPerfilGoogle: true);
      }

      try {
        await ServicioProgreso().migrarProgresoInvitadoASupabase();
      } catch (e) {
        debugPrint('No se pudo migrar progreso invitado en arranque: $e');
      }

      final profile = await AuthService.getCurrentUserProfile();
      final categoria = profile?['categoria'] ?? 'Oficiales PNP';
      return PantallaPrincipal(categoriaUsuario: categoria);
    } catch (e) {
      debugPrint('Error resolviendo pantalla inicial: $e');
      return const PantallaPrincipal(
        categoriaUsuario: 'Ambos',
        esInvitado: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _pantallaInicialFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        return snapshot.data ??
            const PantallaPrincipal(
              categoriaUsuario: 'Ambos',
              esInvitado: true,
            );
      },
    );
  }
}
