import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constantes/constantes_pnp.dart';
import '../servicios/auth_service.dart';
import '../servicios/servicio_notificaciones_programadas.dart';
import '../servicios/servicio_progreso.dart';
import '../servicios/servicio_preguntas.dart';
import '../tema/tema_aplicacion.dart';

import 'pantalla_login.dart';
import 'pantalla_notificaciones.dart';

class PantallaPerfil extends StatefulWidget {
  final bool soloConfiguracion;

  const PantallaPerfil({super.key, this.soloConfiguracion = false});

  @override
  State<PantallaPerfil> createState() => _PantallaPerfilState();
}

class _PantallaPerfilState extends State<PantallaPerfil> {
  String _nombreUsuario = 'Cargando...';
  String _gradoActualUsuario = 'Cargando...';
  String _telefonoUsuario = '';
  bool _isLoading = true;

  // EstadÃ­sticas del usuario
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
        final grado = ConstantesPNP.normalizarGradoCompleto(
          (profile?['grado_actual'] ?? '').toString(),
        );
        _gradoActualUsuario = grado.isEmpty ? 'Sin grado actual' : grado;
        _telefonoUsuario = (profile?['telefono'] ?? '').toString();

        // Mismo criterio que Historial: promedio general por sesiÃ³n.
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

  // --- DIÃLOGOS Y FUNCIONES ---

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

  Map<String, String> _separarNombreCompleto(String nombreCompleto) {
    final limpio = nombreCompleto.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (limpio.isEmpty) {
      return {'nombres': '', 'apellido_paterno': '', 'apellido_materno': ''};
    }
    final partes = limpio.split(' ').where((p) => p.isNotEmpty).toList();
    if (partes.length >= 3) {
      return {
        'apellido_paterno': partes[0],
        'apellido_materno': partes[1],
        'nombres': partes.sublist(2).join(' '),
      };
    }
    if (partes.length == 2) {
      return {
        'apellido_paterno': partes[0],
        'apellido_materno': '',
        'nombres': partes[1],
      };
    }
    return {
      'apellido_paterno': '',
      'apellido_materno': '',
      'nombres': partes.first,
    };
  }

  String? _normalizarTelefonoPeru(String raw) {
    final digitos = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.isEmpty) return null;
    if (digitos.length == 9 && digitos.startsWith('9')) {
      return '+51$digitos';
    }
    if (digitos.length == 11 && digitos.startsWith('519')) {
      return '+$digitos';
    }
    return null;
  }

  Future<void> _mostrarEditarPerfil() async {
    final profile = await AuthService.getCurrentUserProfile();
    if (!mounted) return;
    final nombrePerfil = (profile?['nombre_completo'] ?? _nombreUsuario)
        .toString();
    final partes = _separarNombreCompleto(nombrePerfil);

    final nombresController = TextEditingController(
      text: (profile?['nombres'] ?? partes['nombres'] ?? '').toString(),
    );
    final apellidoPaternoController = TextEditingController(
      text: (profile?['apellido_paterno'] ?? partes['apellido_paterno'] ?? '')
          .toString(),
    );
    final apellidoMaternoController = TextEditingController(
      text: (profile?['apellido_materno'] ?? partes['apellido_materno'] ?? '')
          .toString(),
    );
    final telefonoController = TextEditingController(
      text: (profile?['telefono'] ?? _telefonoUsuario).toString(),
    );
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
                            'Debes ingresar tu contraseÃ±a actual para cambiarla',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    final nombres = nombresController.text.trim();
                    final apellidoPaterno = apellidoPaternoController.text
                        .trim();
                    final apellidoMaterno = apellidoMaternoController.text
                        .trim();
                    final nombreCompleto = [
                      apellidoPaterno,
                      apellidoMaterno,
                      nombres,
                    ].where((p) => p.isNotEmpty).join(' ');
                    final telefonoNormalizado = _normalizarTelefonoPeru(
                      telefonoController.text.trim(),
                    );

                    final success = await AuthService.updateProfile({
                      'nombres': nombres,
                      'apellido_paterno': apellidoPaterno,
                      'apellido_materno': apellidoMaterno,
                      'nombre_completo': nombreCompleto,
                      'telefono': telefonoNormalizado,
                    });

                    if (success) {
                      setState(() {
                        _nombreUsuario = nombreCompleto;
                        _telefonoUsuario = telefonoNormalizado ?? '';
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

                    // Cambiar contraseÃ±a si se proporcionÃ³
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
                                'ContraseÃ±a actualizada correctamente',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                result.error ?? 'Error al cambiar contraseÃ±a',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return; // No cerrar el diÃ¡logo si hay error
                        }
                      }
                    }

                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  }
                },
                child: const Text(
                  'Guardar',
                  style: TextStyle(
                    color: Color(0xFF164A55),
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
                      'InformaciÃ³n Personal',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nombresController,
                      decoration: const InputDecoration(
                        labelText: 'Nombres',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v!.isEmpty ? 'Ingresa tus nombres' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: apellidoPaternoController,
                      decoration: const InputDecoration(
                        labelText: 'Apellido paterno',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v!.isEmpty ? 'Ingresa apellido paterno' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: apellidoMaternoController,
                      decoration: const InputDecoration(
                        labelText: 'Apellido materno',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v!.isEmpty ? 'Ingresa apellido materno' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: telefonoController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Agregar numero de celular (Peru)',
                        hintText: 'Ej: 987654321',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final raw = (v ?? '').trim();
                        if (raw.isEmpty) return null;
                        if (_normalizarTelefonoPeru(raw) == null) {
                          return 'Ingresa un celular peruano valido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Cambiar ContraseÃ±a',
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
                        labelText: 'ContraseÃ±a Actual',
                        prefixIcon: Icon(Icons.lock_open),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Nueva ContraseÃ±a',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val != null && val.isNotEmpty && val.length < 6) {
                          return 'MÃ­nimo 6 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirmar Nueva ContraseÃ±a',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (newPasswordController.text.isNotEmpty &&
                            val != newPasswordController.text) {
                          return 'Las contraseÃ±as no coinciden';
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
                        color: Color(0xFF164A55),
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
                          const Icon(Icons.timer, color: Color(0xFF164A55)),
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
                          labelText: 'Minutos por dÃ­a',
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
                              ? 'RecibirÃ¡s un recordatorio diario general.'
                              : 'No recibirÃ¡s recordatorios de meta.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        value: notificarMetaDiaria,
                        activeThumbColor: const Color(0xFF1E6B63),
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
                                    color: Color(0xFF164A55),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'A la hora programada recibirÃ¡s una notificaciÃ³n. Si no inicias prÃ¡ctica en 10 min, sonarÃ¡ una alarma.',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: const Color(0xFF164A55),
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
                                      color: Color(0xFF164A55),
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
                    'Â¿Tienes problemas con la app?',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ListTile(
                    leading: const Icon(
                      Icons.email_outlined,
                      color: Color(0xFF164A55),
                      size: 28,
                    ),
                    title: const Text('ContÃ¡ctanos por correo'),
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
                                'No se pudo abrir la aplicaciÃ³n de correo',
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
              'TÃ©rminos y Condiciones',
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
1. AceptaciÃ³n de los TÃ©rminos
Al acceder y utilizar la aplicaciÃ³n Ascenso Pro Poli, aceptas cumplir los siguientes tÃ©rminos y condiciones.

2. Uso de la AplicaciÃ³n
La aplicaciÃ³n estÃ¡ diseÃ±ada para fines educativos y de preparaciÃ³n para exÃ¡menes de ascenso. El contenido proporcionado es referencial.

3. Propiedad Intelectual
Todo el contenido, marcas y logos son propiedad de sus respectivos dueÃ±os.

4. Privacidad
Respetamos tu privacidad. Tus datos personales serÃ¡n tratados de acuerdo con nuestra PolÃ­tica de Privacidad.

5. Responsabilidad
No nos hacemos responsables por el mal uso de la aplicaciÃ³n o por resultados en exÃ¡menes reales.

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

  void _canjearCreditos() {
    if (_creditosReferidos <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aun no tienes creditos para canjear.')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Canjear creditos'),
          content: Text(
            'Tienes $_creditosReferidos creditos acumulados. '
            'Para continuar con el canje, contacta a soporte.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _mostrarAyuda();
              },
              child: const Text('Ir a soporte'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          widget.soloConfiguracion ? 'Configuracion' : 'Mi Perfil',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: TemaAplicacion.colorPrimario,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : widget.soloConfiguracion
          ? SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  _buildBloqueConfiguracion(context, bottomSpace: 24),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  // Header con Avatar y Nombres
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: TemaAplicacion.colorSecundario
                                    .withValues(alpha: 0.35),
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 50,
                              backgroundColor: TemaAplicacion.colorSecundario
                                  .withValues(alpha: 0.2),
                              child: Icon(
                                Icons.person,
                                size: 60,
                                color: TemaAplicacion.colorSecundario,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 340),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  _nombreUsuario.toUpperCase(),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _gradoActualUsuario.toUpperCase(),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _telefonoUsuario.trim().isEmpty
                                      ? 'Agregar numero de celular'
                                      : _telefonoUsuario,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Tarjeta 1: estado de cuenta + dias en app
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF164A55), Color(0xFF1E6B63)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF1E6B63,
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
                            Icons.verified_user_outlined,
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
                                'ESTADO DE CUENTA',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'DIAS EN APP: $_diasEnApp',
                                style: GoogleFonts.robotoMono(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
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
                            _premiumActivo ? 'ACTIVA' : 'NO ACTIVA',
                            style: GoogleFonts.inter(
                              color: _premiumActivo
                                  ? const Color(0xFF164A55)
                                  : Colors.red.shade700,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Tarjeta 2: creditos acumulados
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: TemaAplicacion.colorSecundario.withValues(
                          alpha: 0.35,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: TemaAplicacion.colorSecundario.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            Icons.account_balance_wallet_outlined,
                            color: TemaAplicacion.colorSecundario,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CREDITOS ACUMULADOS',
                                style: GoogleFonts.inter(
                                  color: Colors.grey[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$_creditosReferidos',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFF164A55),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _canjearCreditos,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF164A55),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          child: Text(
                            'CANJEAR',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // EstadÃ­sticas Resumen
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Disponibles',
                            _preguntasDisponibles.toString(),
                            Icons.question_answer_outlined,
                            TemaAplicacion.colorSecundario,
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
                            '$_rachaDias dÃ­as',
                            Icons.local_fire_department_outlined,
                            TemaAplicacion.colorDorado,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  // Configuracion y soporte se muestran solo en la vista de ajustes.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _cerrarSesion,
                        icon: const Icon(Icons.logout, color: Colors.red),
                        label: Text(
                          'Cerrar Sesion',
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
                  const SizedBox(height: 16),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildBloqueConfiguracion(
    BuildContext context, {
    double bottomSpace = 80,
  }) {
    return Column(
      children: [
        _buildSectionTitle('Configuracion de Cuenta'),
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
          'Terminos y Condiciones',
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
                'Cerrar Sesion',
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
        SizedBox(height: bottomSpace),
      ],
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
