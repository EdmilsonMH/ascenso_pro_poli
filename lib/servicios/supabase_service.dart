import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio centralizado para el cliente de Supabase.
/// Facilita el acceso a la instancia del cliente desde cualquier lugar.
class SupabaseService {
  // Verificamos si Supabase ha sido inicializado antes de acceder al cliente
  static SupabaseClient get client {
    try {
      // Si accedemos a Supabase.instance y no está inicializado,
      // lanzará una excepción controlada por la librería.
      return Supabase.instance.client;
    } catch (e) {
      // Si falla, lanzamos un error más descriptivo o manejamos el caso
      throw Exception(
        'Supabase no ha sido inicializado. '
        'Asegúrate de configurar Supabase.initialize() en tu main.dart '
        'con tu URL y Anon Key.',
      );
    }
  }

  // Método opcional para verificar si está listo
  static bool get isInitialized {
    try {
      Supabase.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  // Constructor privado para evitar instancias
  SupabaseService._();
}
