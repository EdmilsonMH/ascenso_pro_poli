import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../servicios/auth_service.dart';
import '../servicios/servicio_notificaciones_programadas.dart';
import '../servicios/servicio_progreso.dart';
import '../servicios/servicio_preguntas.dart';

import 'pantalla_login.dart';
import 'pantalla_notificaciones.dart';

class PantallaPerfil extends StatefulWidget {
  const PantallaPerfil({super.key});

  @override
  State<PantallaPerfil> createState() => _PantallaPerfilState();
}

class _PantallaPerfilState extends State<PantallaPerfil> {
  String _nombreUsuario = 'Cargando...';
  String _categoriaUsuario = 'Cargando...';
  bool _isLoading = true;

  // Estadísticas del usuario
  int _preguntasDisponibles = 0;
  double _porcentajeAciertos = 0.0;
  int _rachaDias = 0;
  int _creditosReferidos = 0;
  int _diasEnApp = 0;
  bool _premiumActivo = false;

  final ServicioProgreso _servicioProgreso = ServicioProgreso();
  final ServicioPreguntas _servicioPreguntas = ServicioPreguntas();

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
  }

  Future<void> _cargarDatosUsuario() async {
    final profile = await AuthService.getCurrentUserProfile();
    final sesiones = await _servicioProgreso.obtenerHistorialSesiones();
    final categoriaPerfil = (profile?['categoria'] as String?) ?? 'Ambos';
    final preguntasDisponibles = await _servicioPreguntas
        .contarPreguntasDisponibles(categoria: categoriaPerfil);
    if (mounted) {
      setState(() {
        _nombreUsuario = profile?['nombre_completo'] ?? 'Usuario';
        _categoriaUsuario = profile?['categoria'] ?? 'Oficiales';

        // Mismo criterio que Historial: promedio general por sesión.
        _porcentajeAciertos = _calcularPromedioGeneralDesdeSesiones(sesiones);
        final rachaDesdePerfil = _intValue(profile?['racha_dias']);
        final rachaDesdeHistorial = _calcularRachaDesdeSesiones(sesiones);
        _rachaDias = rachaDesdeHistorial > rachaDesdePerfil
            ? rachaDesdeHistorial
            : rachaDesdePerfil;
        _preguntasDisponibles = preguntasDisponibles;
        _creditosReferidos = _intValue(profile?['creditos']);
        _diasEnApp = _calcularDiasEnApp(profile?['fecha_registro'], sesiones);
        _premiumActivo = _boolValue(profile?['premium']);

        _isLoading = false;
      });
    }
  }

  // --- DIÁLOGOS Y FUNCIONES ---

  int _intValue(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  bool _boolValue(dynamic value, [bool fallback = false]) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalizado = value.toLowerCase();
      if (normalizado == 'true' || normalizado == '1') return true;
      if (normalizado == 'false' || normalizado == '0') return false;
    }
    return fallback;
  }

  DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return value.toLocal();
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  DateTime _inicioDelDia(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _esMismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int _calcularDiasEnApp(dynamic fechaRegistro, List<SesionPractica> sesiones) {
    DateTime? inicio = _parseDate(fechaRegistro);
    if (inicio == null && sesiones.isNotEmpty) {
      inicio = sesiones
          .map((s) => s.fechaCreacion)
          .reduce((a, b) => a.isBefore(b) ? a : b);
    }
    if (inicio == null) return 0;

    final inicioDia = _inicioDelDia(inicio);
    final hoyDia = _inicioDelDia(DateTime.now());
    final dias = hoyDia.difference(inicioDia).inDays + 1;
    return dias < 1 ? 1 : dias;
  }

  int _calcularRachaDesdeSesiones(List<SesionPractica> sesiones) {
    if (sesiones.isEmpty) return 0;

    final diasEstudio = <DateTime>{};
    for (final sesion in sesiones) {
      diasEstudio.add(_inicioDelDia(sesion.fechaCreacion));
    }
    if (diasEstudio.isEmpty) return 0;

    final hoy = _inicioDelDia(DateTime.now());
    final estudioHoy = diasEstudio.any((d) => _esMismoDia(d, hoy));
    var cursor = estudioHoy ? hoy : hoy.subtract(const Duration(days: 1));
    var racha = 0;

    while (diasEstudio.any((d) => _esMismoDia(d, cursor))) {
      racha++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return racha;
  }

  double _calcularPromedioGeneralDesdeSesiones(List<SesionPractica> sesiones) {
    if (sesiones.isEmpty) return 0.0;
    var suma = 0.0;
    for (final sesion in sesiones) {
      suma += sesion.porcentaje;
    }
    return suma / sesiones.length;
  }

  void _mostrarEditarPerfil() {
    final nombreController = TextEditingController(text: _nombreUsuario);
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.zero,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(
              'Editar Perfil',
              style: GoogleFonts.inter(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    if (newPasswordController.text.isNotEmpty &&
                        currentPasswordController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Debes ingresar tu contraseña actual para cambiarla',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    if (nombreController.text.isNotEmpty) {
                      // Guardar en Supabase
                      final success = await AuthService.updateProfile({
                        'nombre_completo': nombreController.text,
                      });

                      if (success) {
                        setState(() {
                          _nombreUsuario = nombreController.text;
                        });
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Perfil actualizado correctamente'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Error al guardar el perfil'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }

                    // Cambiar contraseña si se proporcionó
                    if (newPasswordController.text.isNotEmpty &&
                        currentPasswordController.text.isNotEmpty) {
                      final result = await AuthService.changePassword(
                        currentPassword: currentPasswordController.text,
                        newPassword: newPasswordController.text,
                      );

                      if (context.mounted) {
                        if (result.success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Contraseña actualizada correctamente',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                result.error ?? 'Error al cambiar contraseña',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return; // No cerrar el diálogo si hay error
                        }
                      }
                    }

                    Navigator.pop(context);
                  }
                },
                child: const Text(
                  'Guardar',
                  style: TextStyle(
                    color: Color(0xFF6B21A8),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          body: SizedBox(
            width: double.maxFinite,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Información Personal',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nombreController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre Completo',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? 'Ingresa tu nombre' : null,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Cambiar Contraseña',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: currentPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña Actual',
                        prefixIcon: Icon(Icons.lock_open),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Nueva Contraseña',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val != null && val.isNotEmpty && val.length < 6) {
                          return 'Mínimo 6 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirmar Nueva Contraseña',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (newPasswordController.text.isNotEmpty &&
                            val != newPasswordController.text) {
                          return 'Las contraseñas no coinciden';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarPreferencias() async {
    final perfil = await AuthService.getCurrentUserProfile();

    int tiempoEstudio = _intValue(perfil?['meta_diaria_minutos'], 30);
    bool notificarMetaDiaria = _boolValue(perfil?['notificar_meta'], true);
    final List<String> diasSeleccionados = List<String>.from(
      perfil?['dias_estudio'] ?? ['L', 'M', 'X', 'J', 'V'],
    );

    final String horaRaw =
        (perfil?['hora_recordatorio_meta'] as String?) ?? '08:00:00';
    TimeOfDay horaMetaDiaria = const TimeOfDay(hour: 8, minute: 0);
    final partesHora = horaRaw.split(':');
    if (partesHora.length >= 2) {
      final h = (int.tryParse(partesHora[0]) ?? 8).clamp(0, 23).toInt();
      final m = (int.tryParse(partesHora[1]) ?? 0).clamp(0, 59).toInt();
      horaMetaDiaria = TimeOfDay(hour: h, minute: m);
    }

    final tiempoController = TextEditingController(
      text: tiempoEstudio.toString(),
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            insetPadding: EdgeInsets.zero,
            child: Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                title: Text(
                  'Preferencias de Estudio',
                  style: GoogleFonts.inter(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.black),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      final nuevoTiempo =
                          int.tryParse(tiempoController.text.trim()) ?? 30;
                      final horaTexto =
                          '${horaMetaDiaria.hour.toString().padLeft(2, '0')}:${horaMetaDiaria.minute.toString().padLeft(2, '0')}:00';

                      final success = await AuthService.updateProfile({
                        'meta_diaria_minutos': nuevoTiempo,
                        'notificar_meta': notificarMetaDiaria,
                        'hora_recordatorio_meta': horaTexto,
                        'dias_estudio': diasSeleccionados,
                        'notificar_sesiones': false,
                      });

                      if (success) {
                        try {
                          await ServicioNotificacionesProgramadas.programarNotificacionesDiarias();
                        } catch (e, st) {
                          debugPrint(
                            'Error programando notificaciones: $e\n$st',
                          );
                        }
                      }

                      if (!context.mounted) return;
                      Navigator.pop(context);

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            success
                                ? 'Preferencias guardadas correctamente'
                                : 'Error al guardar preferencias',
                          ),
                          backgroundColor: success ? Colors.green : Colors.red,
                        ),
                      );
                    },
                    child: const Text(
                      'Guardar',
                      style: TextStyle(
                        color: Color(0xFF6B21A8),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              body: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.timer, color: Color(0xFF6B21A8)),
                          const SizedBox(width: 8),
                          Text(
                            'Meta Diaria',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: tiempoController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Minutos por día',
                          suffixText: 'min',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: Text(
                          'Notificarme para cumplir esta meta',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          notificarMetaDiaria
                              ? 'Recibirás un recordatorio diario general.'
                              : 'No recibirás recordatorios de meta.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        value: notificarMetaDiaria,
                        activeThumbColor: const Color(0xFFA855F7),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) =>
                            setState(() => notificarMetaDiaria = val),
                      ),
                      if (notificarMetaDiaria)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFD8B4FE)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    color: Color(0xFF6B21A8),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'A la hora programada recibirás una notificación. Si no inicias práctica en 10 min, sonará una alarma.',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: const Color(0xFF6B21A8),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Hora de recordatorio:',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    horaMetaDiaria.format(context),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF6B21A8),
                                    ),
                                  ),
                                ),
                                onTap: () async {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: horaMetaDiaria,
                                  );
                                  if (time != null) {
                                    setState(() => horaMetaDiaria = time);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _irNotificaciones() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PantallaNotificaciones()),
    );
  }

  void _mostrarAyuda() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.zero,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(
              'Ayuda y Soporte',
              style: GoogleFonts.inter(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¿Tienes problemas con la app?',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ListTile(
                    leading: const Icon(
                      Icons.email_outlined,
                      color: Color(0xFF6B21A8),
                      size: 28,
                    ),
                    title: const Text('Contáctanos por correo'),
                    subtitle: const Text('mallquihuamanedmilson@gmail.com'),
                    contentPadding: EdgeInsets.zero,
                    onTap: () async {
                      final Uri emailLaunchUri = Uri(
                        scheme: 'mailto',
                        path: 'mallquihuamanedmilson@gmail.com',
                        queryParameters: {
                          'subject': 'Soporte Ascenso Pro Poli',
                        },
                      );
                      if (await canLaunchUrl(emailLaunchUri)) {
                        await launchUrl(emailLaunchUri);
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'No se pudo abrir la aplicación de correo',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  const Divider(height: 32),
                  ListTile(
                    leading: const Icon(
                      Icons.chat,
                      color: Colors.green,
                      size: 28,
                    ),
                    title: const Text('Chat de Soporte'),
                    subtitle: const Text('942172070'),
                    contentPadding: EdgeInsets.zero,
                    onTap: () async {
                      final Uri whatsappUri = Uri.parse(
                        'https://wa.me/51942172070?text=Hola,%20necesito%20ayuda%20con%20la%20app%20Ascenso%20Pro%20Poli',
                      );

                      if (await canLaunchUrl(whatsappUri)) {
                        await launchUrl(
                          whatsappUri,
                          mode: LaunchMode.externalApplication,
                        );
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No se pudo abrir WhatsApp'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarTerminos() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.zero,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(
              'Términos y Condiciones',
              style: GoogleFonts.inter(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Text('''
1. Aceptación de los Términos
Al acceder y utilizar la aplicación Ascenso Pro Poli, aceptas cumplir los siguientes términos y condiciones.

2. Uso de la Aplicación
La aplicación está diseñada para fines educativos y de preparación para exámenes de ascenso. El contenido proporcionado es referencial.

3. Propiedad Intelectual
Todo el contenido, marcas y logos son propiedad de sus respectivos dueños.

4. Privacidad
Respetamos tu privacidad. Tus datos personales serán tratados de acuerdo con nuestra Política de Privacidad.

5. Responsabilidad
No nos hacemos responsables por el mal uso de la aplicación o por resultados en exámenes reales.

(Texto completo simulado...)
              ''', style: GoogleFonts.inter(fontSize: 14, height: 1.5)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cerrarSesion() async {
    await AuthService.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const PantallaLogin()),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Mi Perfil',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  // Header con Avatar y Nombres
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.blue.shade200,
                              width: 2,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.blue.shade100,
                            child: Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _nombreUsuario,
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _categoriaUsuario,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Tarjeta de creditos de referidos
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6B21A8), Color(0xFFA855F7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFA855F7,
                          ).withValues(alpha: 0.28),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.developer_board_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'REFERIDOS',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'CR: $_creditosReferidos | DIAS: $_diasEnApp',
                                style: GoogleFonts.robotoMono(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _premiumActivo ? 'ON' : 'OFF',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF6B21A8),
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Estadísticas Resumen
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Disponibles',
                            _preguntasDisponibles.toString(),
                            Icons.question_answer_outlined,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            'Acierto Prom.',
                            '${_porcentajeAciertos.toStringAsFixed(0)}%',
                            Icons.check_circle_outline,
                            Colors.green,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            'Racha',
                            '$_rachaDias días',
                            Icons.local_fire_department_outlined,
                            Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Opciones
                  _buildSectionTitle('Configuración de Cuenta'),
                  _buildOptionTile(
                    context,
                    'Editar Perfil',
                    Icons.edit_outlined,
                    _mostrarEditarPerfil,
                  ),
                  _buildOptionTile(
                    context,
                    'Preferencias de Estudio',
                    Icons.tune_outlined,
                    _mostrarPreferencias,
                  ),
                  _buildOptionTile(
                    context,
                    'Notificaciones',
                    Icons.notifications_outlined,
                    _irNotificaciones,
                  ),

                  const SizedBox(height: 16),
                  _buildSectionTitle('Soporte'),
                  _buildOptionTile(
                    context,
                    'Ayuda y Soporte',
                    Icons.help_outline,
                    _mostrarAyuda,
                  ),
                  _buildOptionTile(
                    context,
                    'Términos y Condiciones',
                    Icons.description_outlined,
                    _mostrarTerminos,
                  ),

                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _cerrarSesion,
                        icon: const Icon(Icons.logout, color: Colors.red),
                        label: Text(
                          'Cerrar Sesión',
                          style: GoogleFonts.inter(color: Colors.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey[500],
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon, color: Colors.grey[700]),
        title: Text(title, style: GoogleFonts.inter(fontSize: 16)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      ),
    );
  }
}
