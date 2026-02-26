/// Modelo de Notificación
class Notificacion {
  final String id;
  final String titulo;
  final String mensaje;
  final String tipo;
  final String icono;
  final String color;
  final bool leida;
  final DateTime createdAt;

  Notificacion({
    required this.id,
    required this.titulo,
    required this.mensaje,
    required this.tipo,
    required this.icono,
    required this.color,
    required this.leida,
    required this.createdAt,
  });

  factory Notificacion.fromJson(Map<String, dynamic> json) {
    return Notificacion(
      id: json['id'] ?? '',
      titulo: json['titulo'] ?? '',
      mensaje: json['mensaje'] ?? '',
      tipo: json['tipo'] ?? 'info',
      icono: json['icono'] ?? 'notifications',
      color: json['color'] ?? '#3B82F6',
      leida: json['leida'] ?? false,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

/// Servicio para manejar notificaciones del usuario (MOCK)
class ServicioNotificaciones {
  // Sin SupabaseClient

  /// Obtener todas las notificaciones del usuario actual
  Future<List<Notificacion>> obtenerNotificaciones() async {
    await Future.delayed(const Duration(milliseconds: 300));

    // Mock notificaciones
    return [
      Notificacion(
        id: '1',
        titulo: '¡Bienvenido!',
        mensaje: 'Gracias por usar Ascenso Pro Poli (Versión Demo).',
        tipo: 'sistema',
        icono: 'celebration',
        color: '#10B981',
        leida: false,
        createdAt: DateTime.now(),
      ),
      Notificacion(
        id: '2',
        titulo: 'Sugerencia de Estudio',
        mensaje: 'Te recomendamos practicar Derecho Penal hoy.',
        tipo: 'info',
        icono: 'school',
        color: '#3B82F6',
        leida: true,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ];
  }

  /// Obtener conteo de notificaciones no leídas
  Future<int> obtenerConteoNoLeidas() async {
    return 1; // Mock
  }

  /// Marcar una notificación como leída
  Future<bool> marcarComoLeida(String notificacionId) async {
    return true;
  }

  /// Marcar todas las notificaciones como leídas
  Future<bool> marcarTodasComoLeidas() async {
    return true;
  }

  /// Crear una notificación para el usuario actual
  Future<bool> crearNotificacion({
    required String titulo,
    required String mensaje,
    String tipo = 'info',
    String icono = 'notifications',
    String color = '#3B82F6',
  }) async {
    print('Notificación creada: $titulo');
    return true;
  }

  /// Crear notificación de bienvenida para nuevos usuarios
  Future<void> crearNotificacionBienvenida() async {
    await crearNotificacion(
      titulo: '¡Bienvenido a Ascenso Pro Poli!',
      mensaje: 'Comienza tu preparación para el examen de ascenso. ¡Éxito!',
      tipo: 'sistema',
      icono: 'celebration',
      color: '#10B981',
    );
  }

  /// Crear notificación de logro
  Future<void> notificarLogro(String titulo, String mensaje) async {
    await crearNotificacion(
      titulo: titulo,
      mensaje: mensaje,
      tipo: 'logro',
      icono: 'emoji_events',
      color: '#F59E0B',
    );
  }

  /// Crear notificación de racha
  Future<void> notificarRacha(int dias) async {
    await crearNotificacion(
      titulo: '¡Racha de $dias días!',
      mensaje: 'Excelente constancia. Sigue así para alcanzar tus metas.',
      tipo: 'racha',
      icono: 'local_fire_department',
      color: '#EF4444',
    );
  }
}
