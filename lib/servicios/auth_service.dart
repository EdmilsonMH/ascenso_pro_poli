import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'supabase_service.dart';

// ==========================================
// CLASES MOCK (Para fallback sin Supabase)
// ==========================================

/// Clase User simulada para reemplazar supabase_flutter User
class User {
  final String id;
  final String? email;
  final Map<String, dynamic>? userMetadata;

  User({required this.id, this.email, this.userMetadata});
}

/// Resultado de operaciones de autenticacion
class AuthResult {
  final bool success;
  final String? error;
  final User? user;
  final bool requiresCompletion;

  AuthResult({
    required this.success,
    this.error,
    this.user,
    this.requiresCompletion = false,
  });
}

// ==========================================
// SERVICIO DE AUTENTICACION
// ==========================================

class AuthService {
  // Estado local del usuario (solo para modo mock)
  static User? _currentUser;

  static const String _defaultCategoria = 'Oficiales PNP';
  static const int _defaultMetaDiaria = 30;
  static const List<String> _defaultDiasEstudio = ['L', 'M', 'X', 'J', 'V'];
  static const List<String> _defaultHorariosSesiones = ['20:00'];
  static const String _defaultGrado = 'No definido';
  static const String _oauthRedirectTo = 'io.supabase.flutter://callback';
  static const String _googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '905708593086-kocj5mflpi17h2g9u7ovndnrpdqhr26m.apps.googleusercontent.com',
  );

  static bool get _useSupabase => SupabaseService.isInitialized;
  static sb.SupabaseClient get _client => SupabaseService.client;

  // Getter publico
  static User? get currentUser {
    if (!_useSupabase) return _currentUser;
    final sb.User? user = _client.auth.currentUser;
    if (user == null) return null;
    return User(id: user.id, email: user.email, userMetadata: user.userMetadata);
  }

  // Stream de cambios de autenticacion
  static final StreamController<void> _authStateController =
      StreamController<void>.broadcast();
  static Stream<void> get authStateChanges {
    if (!_useSupabase) return _authStateController.stream;
    return _client.auth.onAuthStateChange.map((_) => null);
  }

  static bool get isLoggedIn {
    if (!_useSupabase) return _currentUser != null;
    return _client.auth.currentSession?.user != null;
  }

  static bool get _isMobilePlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  // Stream para cambios en el perfil
  static final _profileUpdateController = StreamController<void>.broadcast();
  static Stream<void> get onProfileUpdated => _profileUpdateController.stream;

  static void notifyProfileUpdated() {
    _profileUpdateController.add(null);
  }

  // Almacenamiento temporal del perfil (se reinicia al reiniciar la app)
  static final Map<String, dynamic> _mockProfile = {
    'id': 'mock-user-123',
    'email': 'demo@ascensopoli.pe',
    'nombre_completo': 'Oficial Demo',
    'categoria': _defaultCategoria,
    'codigo_referido': 'DEMO1234',
    'referido_por_usuario_id': null,
    'creditos': 0,
    'premium': false,
    'fecha_registro': '2026-01-01T00:00:00Z',
    'meta_diaria_minutos': 45,
    'dias_estudio': _defaultDiasEstudio,
    'notificar_meta': true,
    'notificar_sesiones': true,
    'puntos_totales': 2500,
    'preguntas_respondidas': 120,
    'preguntas_correctas': 98,
    'racha_dias': 12,
    'num_sesiones': 1,
    'horarios_sesiones': _defaultHorariosSesiones,
  };

  /// Obtiene el perfil del usuario actual
  static Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    if (!_useSupabase) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (_currentUser == null) return null;
      return _mockProfile;
    }

    final sb.User? user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      Map<String, dynamic>? usuario;
      try {
        usuario =
            await _client
                .from('usuario')
                .select(
                  'id, nombre_completo, email, grado_actual, codigo_referido, referido_por_usuario_id, creditos, premium, fecha_registro, metadata',
                )
                .eq('id', user.id)
                .maybeSingle();
      } catch (_) {
        // Compatibilidad con esquemas antiguos donde aun no existen columnas nuevas.
        usuario =
            await _client
                .from('usuario')
                .select(
                  'id, nombre_completo, email, grado_actual, codigo_referido, referido_por_usuario_id, creditos, metadata',
                )
                .eq('id', user.id)
                .maybeSingle();
      }

      final perfil =
          await _client
              .from('perfil_usuario')
              .select(
                'total_preguntas_respondidas, total_correctas, dias_consecutivos_estudio',
              )
              .eq('usuario_id', user.id)
              .maybeSingle();

      final ranking =
          await _client
              .from('ranking')
              .select('puntos_totales')
              .eq('usuario_id', user.id)
              .maybeSingle();

      final metadata = _metadataMap(usuario?['metadata']);

      final diasEstudio = _stringList(
        metadata['dias_estudio'],
        _defaultDiasEstudio,
      );
      final horariosSesiones = _stringList(
        metadata['horarios_sesiones'],
        _defaultHorariosSesiones,
      );

      return {
        'id': user.id,
        'usuario_id': user.id,
        'email': user.email ?? usuario?['email'],
        'nombre_completo':
            usuario?['nombre_completo'] ?? _nombreDesdeAuth(user),
        'categoria': metadata['categoria'] ?? _defaultCategoria,
        'grado_actual': usuario?['grado_actual'] ?? _defaultGrado,
        'codigo_referido': usuario?['codigo_referido'],
        'referido_por_usuario_id': usuario?['referido_por_usuario_id'],
        'creditos': _intValue(usuario?['creditos'], 0),
        'premium': _boolValue(usuario?['premium'], false),
        'fecha_registro': usuario?['fecha_registro'],
        'especialidad': metadata['especialidad'],
        'meta_diaria_minutos': _intValue(
          metadata['meta_diaria_minutos'],
          _defaultMetaDiaria,
        ),
        'dias_estudio': diasEstudio,
        'notificar_meta': _boolValue(metadata['notificar_meta'], true),
        'notificar_sesiones': _boolValue(metadata['notificar_sesiones'], true),
        'horarios_sesiones': horariosSesiones,
        'puntos_totales': _intValue(ranking?['puntos_totales'], 0),
        'preguntas_respondidas': _intValue(
          perfil?['total_preguntas_respondidas'],
          0,
        ),
        'preguntas_correctas': _intValue(perfil?['total_correctas'], 0),
        'racha_dias': _intValue(perfil?['dias_consecutivos_estudio'], 0),
      };
    } catch (e) {
      print('Error getCurrentUserProfile: $e');
      return null;
    }
  }

  /// Registrar nuevo usuario
  static Future<AuthResult> register({
    required String email,
    required String password,
    required String nombreCompleto,
    required String categoria,
    required String gradoActual,
    required String especialidad,
    required int metaDiaria,
  }) async {
    if (!_useSupabase) {
      await Future.delayed(const Duration(seconds: 1));
      _currentUser = User(
        id: 'mock-user-123',
        email: email,
        userMetadata: {
          'nombre_completo': nombreCompleto,
          'categoria': categoria,
          'grado_actual': gradoActual,
          'especialidad': especialidad,
        },
      );

      _mockProfile['email'] = email;
      _mockProfile['nombre_completo'] = nombreCompleto;
      _mockProfile['categoria'] = categoria;
      _mockProfile['grado_actual'] = gradoActual;
      _mockProfile['especialidad'] = especialidad;
      _mockProfile['meta_diaria_minutos'] = metaDiaria;
      _mockProfile['puntos_totales'] = 0;
      _mockProfile['preguntas_respondidas'] = 0;
      _mockProfile['preguntas_correctas'] = 0;
      _mockProfile['racha_dias'] = 0;
      _mockProfile['creditos'] = 0;
      _mockProfile['premium'] = false;
      _mockProfile['fecha_registro'] = DateTime.now().toIso8601String();
      _mockProfile['codigo_referido'] =
          'DEMO${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';

      return AuthResult(success: true, user: _currentUser);
    }

    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': nombreCompleto},
      );

      final sb.User? user = response.user;
      if (user == null) {
        return AuthResult(
          success: false,
          error: 'No se pudo crear el usuario.',
        );
      }

      if (response.session == null) {
        return AuthResult(
          success: false,
          error:
              'Debes confirmar tu correo antes de continuar. '
              'Si estas en pruebas, desactiva la confirmacion de email en Supabase.',
        );
      }

      await _client.from('usuario').insert({
        'id': user.id,
        'user_id': user.id,
        'nombre_completo': nombreCompleto,
        'email': email,
        'grado_actual': gradoActual,
        'auth_provider': 'supabase',
        'metadata': {
          'categoria': categoria,
          'especialidad': especialidad,
          'meta_diaria_minutos': metaDiaria,
          'dias_estudio': _defaultDiasEstudio,
          'notificar_meta': true,
          'notificar_sesiones': true,
          'horarios_sesiones': _defaultHorariosSesiones,
        },
      });

      return AuthResult(success: true, user: _wrapUser(user));
    } catch (e) {
      return AuthResult(
        success: false,
        error: _friendlyAuthError(e, 'registro'),
      );
    }
  }

  /// Iniciar sesion
  static Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    if (!_useSupabase) {
      await Future.delayed(const Duration(seconds: 1));
      if (password == 'error') {
        return AuthResult(
          success: false,
          error: 'Credenciales invalidas (Simulado)',
        );
      }

      _currentUser = User(
        id: 'mock-user-123',
        email: email,
        userMetadata: {'nombre_completo': _mockProfile['nombre_completo']},
      );

      return AuthResult(success: true, user: _currentUser);
    }

    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final sb.User? user = response.user;
      if (user == null) {
        return AuthResult(
          success: false,
          error: 'Credenciales invalidas.',
        );
      }

      bool requiresCompletion = true;
      try {
        final existing =
            await _client
                .from('usuario')
                .select('id, grado_actual, metadata')
                .eq('id', user.id)
                .maybeSingle();
        requiresCompletion = _needsCompletion(existing);
      } catch (_) {
        // Si no se puede leer el perfil, forzamos completar perfil
        // para evitar entrar con datos incompletos.
        requiresCompletion = true;
      }

      return AuthResult(
        success: true,
        user: _wrapUser(user),
        requiresCompletion: requiresCompletion,
      );
    } catch (e) {
      return AuthResult(success: false, error: _friendlyAuthError(e, 'login'));
    }
  }

  /// Actualizar perfil del usuario
  static Future<bool> updateProfile(Map<String, dynamic> updates) async {
    if (!_useSupabase) {
      await Future.delayed(const Duration(milliseconds: 500));
      _mockProfile.addAll(updates);
      _profileUpdateController.add(null);
      return true;
    }

    final sb.User? user = _client.auth.currentUser;
    if (user == null) return false;

    try {
      final existing =
          await _client
              .from('usuario')
              .select('id, nombre_completo, grado_actual, email, metadata')
              .eq('id', user.id)
              .maybeSingle();

      final metadata = _metadataMap(existing?['metadata']);

      final columnUpdates = <String, dynamic>{};
      if (updates.containsKey('nombre_completo')) {
        columnUpdates['nombre_completo'] = updates['nombre_completo'];
      }
      if (updates.containsKey('email')) {
        columnUpdates['email'] = updates['email'];
      }
      if (updates.containsKey('grado_actual')) {
        columnUpdates['grado_actual'] = updates['grado_actual'];
      }

      updates.forEach((key, value) {
        if (!columnUpdates.containsKey(key)) {
          metadata[key] = value;
        }
      });

      if (existing == null) {
        await _client.from('usuario').insert({
          'id': user.id,
          'user_id': user.id,
          'nombre_completo':
              columnUpdates['nombre_completo'] ?? _nombreDesdeAuth(user),
          'email': columnUpdates['email'] ?? user.email,
          'grado_actual': columnUpdates['grado_actual'] ?? _defaultGrado,
          'auth_provider': _authProvider(user),
          'metadata': metadata,
        });
      } else {
        final updateMap = <String, dynamic>{
          ...columnUpdates,
          'metadata': metadata,
        };
        await _client.from('usuario').update(updateMap).eq('id', user.id);
      }

      _profileUpdateController.add(null);
      return true;
    } catch (e) {
      print('Error updateProfile: $e');
      return false;
    }
  }

  /// Cambiar contrasena
  static Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (!_useSupabase) {
      await Future.delayed(const Duration(seconds: 1));
      return AuthResult(success: true);
    }

    final sb.User? user = _client.auth.currentUser;
    if (user == null || user.email == null) {
      return AuthResult(success: false, error: 'No hay sesion activa.');
    }

    try {
      // Validar password actual
      await _client.auth.signInWithPassword(
        email: user.email!,
        password: currentPassword,
      );

      await _client.auth.updateUser(
        sb.UserAttributes(password: newPassword),
      );
      return AuthResult(success: true);
    } catch (e) {
      return AuthResult(success: false, error: 'Error al cambiar: $e');
    }
  }

  /// Iniciar sesion con Google
  static Future<AuthResult> loginWithGoogle() async {
    if (!_useSupabase) {
      await Future.delayed(const Duration(seconds: 1));
      _currentUser = User(
        id: 'mock-google-user',
        email: 'google@demo.com',
        userMetadata: {'nombre_completo': 'Usuario Google'},
      );
      return AuthResult(success: true, user: _currentUser);
    }

    try {
      if (_isMobilePlatform) {
        final hasClientId = _googleWebClientId.trim().isNotEmpty;
        final googleSignIn = GoogleSignIn(
          scopes: const ['email', 'profile', 'openid'],
          serverClientId: hasClientId ? _googleWebClientId : null,
        );

        // Forzar selector de cuentas en cada intento para permitir cambiar de correo.
        try {
          if (await googleSignIn.isSignedIn()) {
            await googleSignIn.disconnect();
          } else {
            await googleSignIn.signOut();
          }
        } catch (_) {
          // Si no hay sesion previa en GoogleSignIn, continuamos.
        }

        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          return AuthResult(success: false, error: 'Cancelado');
        }

        final googleAuth = await googleUser.authentication;
        final idToken = googleAuth.idToken;
        if (idToken == null || idToken.isEmpty) {
          return AuthResult(
            success: false,
            error:
                'No se pudo obtener idToken de Google. '
                'Configura GOOGLE_WEB_CLIENT_ID con --dart-define.',
          );
        }

        final response = await _client.auth.signInWithIdToken(
          provider: sb.OAuthProvider.google,
          idToken: idToken,
          accessToken: googleAuth.accessToken,
        );

        final sb.User? user = response.user;
        if (user == null) {
          return AuthResult(
            success: false,
            error: 'No se pudo autenticar con Google.',
          );
        }

        final existing =
            await _client
                .from('usuario')
                .select('id, grado_actual, metadata')
                .eq('id', user.id)
                .maybeSingle();

        final requiresCompletion = _needsCompletion(existing);

        return AuthResult(
          success: true,
          user: _wrapUser(user),
          requiresCompletion: requiresCompletion,
        );
      }

      await _client.auth.signInWithOAuth(
        sb.OAuthProvider.google,
        redirectTo: kIsWeb ? null : _oauthRedirectTo,
      );

      final session =
          await _client.auth.onAuthStateChange
              .where((event) => event.session != null)
              .map((event) => event.session!)
              .first
              .timeout(const Duration(minutes: 2));

      final sb.User user = session.user;
      final existing =
          await _client
              .from('usuario')
              .select('id, grado_actual, metadata')
              .eq('id', user.id)
              .maybeSingle();

      final requiresCompletion = _needsCompletion(existing);

      return AuthResult(
        success: true,
        user: _wrapUser(user),
        requiresCompletion: requiresCompletion,
      );
    } catch (e) {
      return AuthResult(success: false, error: 'Error con Google: $e');
    }
  }

  /// Aplica un código referido para el usuario autenticado (solo una vez)
  static Future<AuthResult> applyReferralCode(String code) async {
    final codigo = code.trim().toUpperCase();
    if (codigo.isEmpty) {
      return AuthResult(success: false, error: 'Código referido vacío.');
    }

    if (!_useSupabase) {
      await Future.delayed(const Duration(milliseconds: 300));
      return AuthResult(success: true);
    }

    final sb.User? user = _client.auth.currentUser;
    if (user == null) {
      return AuthResult(success: false, error: 'No hay sesión activa.');
    }

    try {
      final response = await _client.rpc(
        'aplicar_codigo_referido',
        params: {'p_codigo': codigo},
      );

      if (response is Map) {
        final data = Map<String, dynamic>.from(response);
        final success = data['success'] == true;
        if (success) {
          return AuthResult(success: true);
        }
        return AuthResult(
          success: false,
          error: (data['error'] ?? 'No se pudo aplicar el referido.').toString(),
        );
      }

      return AuthResult(
        success: false,
        error: 'Respuesta inesperada al aplicar referido.',
      );
    } catch (e) {
      return AuthResult(
        success: false,
        error: 'Error aplicando referido: $e',
      );
    }
  }

  /// Verifica si el perfil esta completo
  static Future<bool> isProfileComplete() async {
    if (!_useSupabase) return true;
    final sb.User? user = _client.auth.currentUser;
    if (user == null) return false;

    try {
      final existing =
          await _client
              .from('usuario')
              .select('id, grado_actual, metadata')
              .eq('id', user.id)
              .maybeSingle();
      return !_needsCompletion(existing);
    } catch (_) {
      return false;
    }
  }

  /// Cerrar sesion
  static Future<void> logout() async {
    if (!_useSupabase) {
      _currentUser = null;
      return;
    }

    await _client.auth.signOut();

    if (_isMobilePlatform) {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {
        // Si GoogleSignIn no esta activo, no bloqueamos el logout principal.
      }
    }
  }

  // =====================
  // Helpers
  // =====================

  static User _wrapUser(sb.User user) {
    return User(id: user.id, email: user.email, userMetadata: user.userMetadata);
  }

  static String _authProvider(sb.User user) {
    final provider = user.appMetadata['provider'];
    if (provider is String && provider.trim().isNotEmpty) return provider;
    return 'supabase';
  }

  static String _nombreDesdeAuth(sb.User user) {
    final meta = user.userMetadata ?? {};
    final dynamic fullName = meta['full_name'] ?? meta['name'] ?? meta['nombre'];
    if (fullName is String && fullName.trim().isNotEmpty) {
      return fullName.trim();
    }
    return 'Usuario';
  }

  static bool _needsCompletion(Map<String, dynamic>? usuarioRow) {
    if (usuarioRow == null) return true;
    final metadata = _metadataMap(usuarioRow['metadata']);

    final categoria = metadata['categoria'];
    final metaDiaria = metadata['meta_diaria_minutos'];
    final especialidad = metadata['especialidad'];
    final gradoActualRaw = usuarioRow['grado_actual'] ?? metadata['grado_actual'];

    final categoriaCompleta =
        categoria is String ? categoria.trim().isNotEmpty : categoria != null;
    final especialidadCompleta =
        especialidad is String
            ? especialidad.trim().isNotEmpty
            : especialidad != null;
    final metaCompleta =
        metaDiaria is num
            ? metaDiaria > 0
            : (int.tryParse(metaDiaria?.toString() ?? '') ?? 0) > 0;
    final gradoActual = gradoActualRaw?.toString().trim() ?? '';
    final gradoCompleto = gradoActual.isNotEmpty;

    return !categoriaCompleta ||
        !metaCompleta ||
        !especialidadCompleta ||
        !gradoCompleto;
  }

  static int _intValue(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  static bool _boolValue(dynamic value, bool fallback) {
    if (value is bool) return value;
    return fallback;
  }

  static List<String> _stringList(dynamic value, List<String> fallback) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return fallback;
  }

  static Map<String, dynamic> _metadataMap(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }

    if (raw is String) {
      final source = raw.trim();
      if (source.isEmpty) return <String, dynamic>{};
      try {
        final decoded = jsonDecode(source);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return <String, dynamic>{};
      }
    }

    return <String, dynamic>{};
  }

  static String _friendlyAuthError(Object error, String operation) {
    if (error is sb.AuthException) {
      final raw = error.message.trim();
      final lower = raw.toLowerCase();

      if (lower.contains('invalid login credentials')) {
        return 'Correo o contrasena incorrectos.';
      }
      if (lower.contains('email not confirmed')) {
        return 'Confirma tu correo antes de iniciar sesion.';
      }
      if (lower.contains('user already registered')) {
        return 'Ese correo ya esta registrado.';
      }
      if (lower.contains('password should be at least')) {
        return 'La contrasena debe tener al menos 6 caracteres.';
      }
      if (raw.isNotEmpty) {
        return raw;
      }
    }

    if (error is sb.PostgrestException) {
      final msg = error.message.trim();
      if (msg.isNotEmpty) return msg;
    }

    return 'Error de $operation: $error';
  }
}
