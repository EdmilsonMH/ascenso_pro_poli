import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constantes/constantes_pnp.dart';
import '../servicios/auth_service.dart';
import '../servicios/servicio_notificaciones_programadas.dart';
import '../servicios/servicio_progreso.dart';
import '../tema/tema_aplicacion.dart';
import 'pantalla_principal.dart';

class PantallaRegistro extends StatefulWidget {
  final bool completarPerfilGoogle;
  final String?categoriaInicial;

  const PantallaRegistro({
    super.key,
    this.completarPerfilGoogle = false,
    this.categoriaInicial,
  });

  @override
  State<PantallaRegistro> createState() => _PantallaRegistroState();
}

class _PantallaRegistroState extends State<PantallaRegistro> {
  String _categoriaSeleccionada = ConstantesPNP.categorias.first;
  String _gradoSeleccionado = '';
  String _especialidadSeleccionada =
      ConstantesPNP.obtenerEspecialidadesParaCategoria(
        ConstantesPNP.categorias.first,
      ).first;

  final _claveFormulario = GlobalKey<FormState>();

  // Controladores de Texto
  final _controladorNombres = TextEditingController();
  final _controladorApellidoPaterno = TextEditingController();
  final _controladorApellidoMaterno = TextEditingController();
  final _controladorEmail = TextEditingController();
  final _controladorPassword = TextEditingController();
  final _controladorConfirmPassword = TextEditingController();
  final _controladorMetaDiaria = TextEditingController(text: '30');
  final _controladorCodigoReferido = TextEditingController();
  final _controladorEspecialidad = TextEditingController();

  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    if (widget.categoriaInicial != null &&
        ConstantesPNP.categorias.contains(widget.categoriaInicial)) {
      _categoriaSeleccionada = widget.categoriaInicial!;
    }

    final gradosIniciales = ConstantesPNP.obtenerGradosParaCategoria(
      _categoriaSeleccionada,
    );
    final especialidadesIniciales =
        ConstantesPNP.obtenerEspecialidadesParaCategoria(
          _categoriaSeleccionada,
        );
    _gradoSeleccionado = gradosIniciales.isNotEmpty
        ? gradosIniciales.first
        : '';
    _especialidadSeleccionada = especialidadesIniciales.isNotEmpty
        ? especialidadesIniciales.first
        : '';
    _controladorEspecialidad.text = _especialidadSeleccionada;

    if (widget.completarPerfilGoogle) {
      _precargarDatosGoogle();
    }
  }

  Future<void> _precargarDatosGoogle() async {
    final profile = await AuthService.getCurrentUserProfile();
    final currentUser = AuthService.currentUser;
    if (!mounted) return;

    final metadata = currentUser?.userMetadata ?? <String, dynamic>{};
    final nombreSugerido =
        (profile?['nombre_completo'] ??
                metadata['full_name'] ??
                metadata['name'] ??
                metadata['nombre'])
            ?.toString()
            .trim();
    final partesNombre = _separarNombreCompleto(nombreSugerido);
    final nombresPerfil = profile?['nombres']?.toString().trim();
    final apellidoPaternoPerfil = profile?['apellido_paterno']
        ?.toString()
        .trim();
    final apellidoMaternoPerfil = profile?['apellido_materno']
        ?.toString()
        .trim();
    final correoSugerido = (profile?['email'] ??currentUser?.email)
        ?.toString()
        .trim();

    setState(() {
      if (nombresPerfil != null && nombresPerfil.isNotEmpty) {
        _controladorNombres.text = nombresPerfil;
      } else if (partesNombre['nombres']!.isNotEmpty) {
        _controladorNombres.text = partesNombre['nombres']!;
      }
      if (apellidoPaternoPerfil != null && apellidoPaternoPerfil.isNotEmpty) {
        _controladorApellidoPaterno.text = apellidoPaternoPerfil;
      } else if (partesNombre['apellido_paterno']!.isNotEmpty) {
        _controladorApellidoPaterno.text = partesNombre['apellido_paterno']!;
      }
      if (apellidoMaternoPerfil != null && apellidoMaternoPerfil.isNotEmpty) {
        _controladorApellidoMaterno.text = apellidoMaternoPerfil;
      } else if (partesNombre['apellido_materno']!.isNotEmpty) {
        _controladorApellidoMaterno.text = partesNombre['apellido_materno']!;
      }
      if (correoSugerido != null && correoSugerido.isNotEmpty) {
        _controladorEmail.text = correoSugerido;
      }

      final categoria = profile?['categoria']?.toString();
      if (categoria != null && ConstantesPNP.categorias.contains(categoria)) {
        _categoriaSeleccionada = categoria;
      }

      final gradosCategoria = ConstantesPNP.obtenerGradosParaCategoria(
        _categoriaSeleccionada,
      );
      final grado = ConstantesPNP.normalizarGradoCompleto(
        profile?['grado_actual']?.toString() ??'',
      );
      if (gradosCategoria.contains(grado)) {
        _gradoSeleccionado = grado;
      } else if (gradosCategoria.isNotEmpty) {
        _gradoSeleccionado = gradosCategoria.first;
      }

      final especialidad = profile?['especialidad']?.toString();
      final especialidadesCategoria =
          ConstantesPNP.obtenerEspecialidadesParaCategoria(
            _categoriaSeleccionada,
          );
      if (especialidad != null &&
          especialidadesCategoria.contains(especialidad)) {
        _especialidadSeleccionada = especialidad;
      } else if (especialidadesCategoria.isNotEmpty) {
        _especialidadSeleccionada = especialidadesCategoria.first;
      }
      _controladorEspecialidad.text = _especialidadSeleccionada;

      final metaDiaria = int.tryParse(
        (profile?['meta_diaria_minutos'] ??'').toString(),
      );
      if (metaDiaria != null && metaDiaria >= 5) {
        _controladorMetaDiaria.text = metaDiaria.toString();
      }
    });
  }

  @override
  void dispose() {
    _controladorNombres.dispose();
    _controladorApellidoPaterno.dispose();
    _controladorApellidoMaterno.dispose();
    _controladorEmail.dispose();
    _controladorPassword.dispose();
    _controladorConfirmPassword.dispose();
    _controladorMetaDiaria.dispose();
    _controladorCodigoReferido.dispose();
    _controladorEspecialidad.dispose();
    super.dispose();
  }

  Future<void> _activarRecordatoriosMeta() async {
    try {
      await ServicioNotificacionesProgramadas.programarNotificacionesDiarias();
    } catch (e) {
      debugPrint('No se pudieron programar notificaciones tras registro: $e');
    }
  }

  Future<void> _migrarProgresoInvitadoSiExiste() async {
    try {
      await ServicioProgreso().migrarProgresoInvitadoASupabase();
    } catch (e) {
      debugPrint('No se pudo migrar progreso invitado tras registro: $e');
    }
  }

  Future<void> _manejarRegistro() async {
    if (_cargando) return;
    _normalizarEspecialidadDesdeTexto();
    if (!_claveFormulario.currentState!.validate()) return;

    setState(() {
      _cargando = true;
    });

    final metaDiaria = int.tryParse(_controladorMetaDiaria.text) ??30;
    final codigoReferido = _controladorCodigoReferido.text.trim().toUpperCase();
    final nombres = _controladorNombres.text.trim();
    final apellidoPaterno = _controladorApellidoPaterno.text.trim();
    final apellidoMaterno = _controladorApellidoMaterno.text.trim();
    final nombreCompleto = [apellidoPaterno, apellidoMaterno, nombres]
        .where((p) => p.isNotEmpty)
        .join(' ');

    if (widget.completarPerfilGoogle) {
      final actualizacion = <String, dynamic>{
        'categoria': _categoriaSeleccionada,
        'grado_actual': _gradoSeleccionado,
        'especialidad': _especialidadSeleccionada,
        'meta_diaria_minutos': metaDiaria,
        'nombres': nombres,
        'apellido_paterno': apellidoPaterno,
        'apellido_materno': apellidoMaterno,
        'nombre_completo': nombreCompleto,
      };

      final email = _controladorEmail.text.trim();
      if (email.isNotEmpty) {
        actualizacion['email'] = email;
      }

      final actualizado = await AuthService.updateProfile(actualizacion);
      if (!mounted) return;

      setState(() {
        _cargando = false;
      });

      if (actualizado) {
        await _migrarProgresoInvitadoSiExiste();
        await _aplicarReferidoSiCorresponde(codigoReferido);
        await _activarRecordatoriosMeta();
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) =>
                PantallaPrincipal(categoriaUsuario: _categoriaSeleccionada),
          ),
          (route) => false,
        );
      } else {
        final detalle = AuthService.lastProfileError?.trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (detalle != null && detalle.isNotEmpty)
                  ? detalle
                  : 'No se pudo completar el perfil.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final resultado = await AuthService.register(
      email: _controladorEmail.text.trim(),
      password: _controladorPassword.text,
      nombreCompleto: nombreCompleto,
      nombres: nombres,
      apellidoPaterno: apellidoPaterno,
      apellidoMaterno: apellidoMaterno,
      categoria: _categoriaSeleccionada,
      gradoActual: _gradoSeleccionado,
      especialidad: _especialidadSeleccionada,
      metaDiaria: metaDiaria,
    );

    if (!mounted) return;

    setState(() {
      _cargando = false;
    });

    if (resultado.success) {
      await _migrarProgresoInvitadoSiExiste();
      await _aplicarReferidoSiCorresponde(codigoReferido);
      await _activarRecordatoriosMeta();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) =>
              PantallaPrincipal(categoriaUsuario: _categoriaSeleccionada),
        ),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resultado.error ??'Error desconocido'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _aplicarReferidoSiCorresponde(String codigoReferido) async {
    if (codigoReferido.isEmpty) return;

    final resultado = await AuthService.applyReferralCode(codigoReferido);
    if (!mounted) return;

    if (!resultado.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resultado.error ??'No se pudo aplicar el código referido.',
          ),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Referido aplicado. El premio se acreditará cuando tu cuenta esté activa/pagada.',
        ),
      ),
    );
  }

  Future<void> _handleGoogleLogin() async {
    if (_cargando) return;
    setState(() {
      _cargando = true;
    });

    final result = await AuthService.loginWithGoogle();

    if (!mounted) return;

    if (result.success) {
      if (result.requiresCompletion) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PantallaRegistro(
              completarPerfilGoogle: true,
              categoriaInicial: _categoriaSeleccionada,
            ),
          ),
        );
      } else {
        await _migrarProgresoInvitadoSiExiste();
        final profile = await AuthService.getCurrentUserProfile();
        final categoria = profile?['categoria'] ??_categoriaSeleccionada;
        await _activarRecordatoriosMeta();

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) =>
                PantallaPrincipal(categoriaUsuario: categoria),
          ),
          (route) => false,
        );
      }
    } else {
      setState(() {
        _cargando = false;
      });
      if (result.error != 'Cancelado') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ??'Error con Google'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  IconData _iconoCategoria(String categoria) {
    final lower = categoria.toLowerCase();
    if (lower.contains('oficiales')) return Icons.military_tech;
    if (lower.contains('servicios')) return Icons.settings;
    return Icons.shield;
  }

  Map<String, String> _separarNombreCompleto(String?nombreCompleto) {
    final limpio = (nombreCompleto ??'').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (limpio.isEmpty) {
      return {
        'nombres': '',
        'apellido_paterno': '',
        'apellido_materno': '',
      };
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
        'nombres': partes[1],
        'apellido_materno': '',
      };
    }

    return {
      'nombres': partes.first,
      'apellido_paterno': '',
      'apellido_materno': '',
    };
  }

  void _normalizarEspecialidadDesdeTexto() {
    final especialidades = ConstantesPNP.obtenerEspecialidadesParaCategoria(
      _categoriaSeleccionada,
    );
    final texto = _controladorEspecialidad.text.trim();
    final exacta = especialidades.where(
      (e) => e.toLowerCase() == texto.toLowerCase(),
    );
    if (exacta.isNotEmpty) {
      _especialidadSeleccionada = exacta.first;
      _controladorEspecialidad.text = _especialidadSeleccionada;
      return;
    }
    if (!especialidades.contains(_especialidadSeleccionada) &&
        especialidades.isNotEmpty) {
      _especialidadSeleccionada = especialidades.first;
      _controladorEspecialidad.text = _especialidadSeleccionada;
    }
  }

  Widget _buildSelectorCategoria() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: ConstantesPNP.categorias.map((categoria) {
            final selected = _categoriaSeleccionada == categoria;
            return SizedBox(
              width: itemWidth,
              child: _TarjetaCategoria(
                titulo: categoria,
                estaSeleccionado: selected,
                icono: _iconoCategoria(categoria),
                alPresionar: () {
                  setState(() {
                    _categoriaSeleccionada = categoria;
                    final grados = ConstantesPNP.obtenerGradosParaCategoria(
                      categoria,
                    );
                    final especialidades = ConstantesPNP
                        .obtenerEspecialidadesParaCategoria(categoria);
                    _gradoSeleccionado = grados.isNotEmpty ?grados.first : '';
                    _especialidadSeleccionada = especialidades.isNotEmpty
                        ? especialidades.first
                        : '';
                    _controladorEspecialidad.text = _especialidadSeleccionada;
                  });
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDropdownGrado() {
    final grados = ConstantesPNP.obtenerGradosParaCategoria(
      _categoriaSeleccionada,
    );
    if (grados.isEmpty) {
      return const Text('Sin grados disponibles');
    }

    if (!grados.contains(_gradoSeleccionado)) {
      _gradoSeleccionado = grados.first;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _gradoSeleccionado,
          isExpanded: true,
          items: grados
              .map((g) => DropdownMenuItem<String>(value: g, child: Text(g)))
              .toList(),
          onChanged: (val) {
            if (val == null) return;
            setState(() => _gradoSeleccionado = val);
          },
        ),
      ),
    );
  }

  Widget _buildDropdownEspecialidad() {
    final especialidades = ConstantesPNP.obtenerEspecialidadesParaCategoria(
      _categoriaSeleccionada,
    );
    if (especialidades.isEmpty) {
      return const Text('Sin especialidades disponibles');
    }
    if (!especialidades.contains(_especialidadSeleccionada)) {
      _especialidadSeleccionada = especialidades.first;
    }
    if (_controladorEspecialidad.text.trim().isEmpty ||
        !especialidades.any(
          (e) =>
              e.toLowerCase() ==
              _controladorEspecialidad.text.trim().toLowerCase(),
        )) {
      _controladorEspecialidad.text = _especialidadSeleccionada;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Autocomplete<String>(
        key: ValueKey('especialidad_${_categoriaSeleccionada}_$_especialidadSeleccionada'),
        initialValue: TextEditingValue(text: _controladorEspecialidad.text),
        optionsBuilder: (TextEditingValue textEditingValue) {
          final query = textEditingValue.text.trim().toLowerCase();
          if (query.isEmpty) return especialidades;
          return especialidades.where(
            (e) => e.toLowerCase().contains(query),
          );
        },
        onSelected: (String seleccion) {
          setState(() {
            _especialidadSeleccionada = seleccion;
            _controladorEspecialidad.text = seleccion;
          });
        },
        fieldViewBuilder:
            (context, textEditingController, focusNode, onFieldSubmitted) {
              return TextFormField(
                controller: textEditingController,
                focusNode: focusNode,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Escribe tu especialidad',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) {
                  _controladorEspecialidad.text = value;
                },
                validator: (value) {
                  final txt = (value ??'').trim().toLowerCase();
                  final existe = especialidades.any(
                    (e) => e.toLowerCase() == txt,
                  );
                  if (!existe) {
                    return 'Selecciona una especialidad de la lista';
                  }
                  return null;
                },
              );
            },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final esFlujoGoogle = widget.completarPerfilGoogle;

    return Scaffold(
      backgroundColor: TemaAplicacion.colorFondo,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(esFlujoGoogle ?20.0 : 24.0),
            child: Form(
              key: _claveFormulario,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.local_police_rounded,
                    size: esFlujoGoogle ?68 : 80,
                    color: TemaAplicacion.colorPrimario,
                  ),
                  SizedBox(height: esFlujoGoogle ?16 : 24),
                  Text(
                    widget.completarPerfilGoogle
                        ? 'Completa tu Perfil'
                        : 'Registro de Oficiales',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: TemaAplicacion.textoPrimario,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.completarPerfilGoogle
                        ? 'Completa tus datos para continuar con Google'
                        : 'Configura tu rango para un entrenamiento preciso',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: TemaAplicacion.textoSecundario,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: esFlujoGoogle ?20 : 32),

                  // PASO 1: CATEGORÍA (Diseño renovado)
                  Text(
                    'PASO 1: CATEGORÍA',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: TemaAplicacion.colorPrimario,
                    ),
                  ),
                  SizedBox(height: esFlujoGoogle ?10 : 12),
                  _buildSelectorCategoria(),

                  SizedBox(height: esFlujoGoogle ?16 : 24),

                  // PASO 2: GRADO ACTUAL
                  Text(
                    'PASO 2: GRADO ACTUAL',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: TemaAplicacion.colorPrimario,
                    ),
                  ),
                  SizedBox(height: esFlujoGoogle ?10 : 12),
                  _buildDropdownGrado(),

                  SizedBox(height: esFlujoGoogle ?16 : 24),

                  // PASO 3: ESPECIALIDAD
                  Text(
                    'PASO 3: ESPECIALIDAD',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: TemaAplicacion.colorPrimario,
                    ),
                  ),
                  SizedBox(height: esFlujoGoogle ?10 : 12),
                  _buildDropdownEspecialidad(),

                  SizedBox(height: esFlujoGoogle ?20 : 32),

                  // Meta Diaria de Estudio
                  TextFormField(
                    controller: _controladorMetaDiaria,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Meta Diaria de Estudio (minutos)',
                      prefixIcon: Icon(Icons.timer_outlined),
                      helperText: 'Recomendado: 30 minutos al día',
                    ),
                    validator: (valor) {
                      if (valor == null || valor.isEmpty) {
                        return 'Ingresa tu meta diaria';
                      }
                      final n = int.tryParse(valor);
                      if (n == null || n < 5) {
                        return 'Mínimo 5 minutos';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: esFlujoGoogle ?12 : 16),

                  // Referido opcional
                  TextFormField(
                    controller: _controladorCodigoReferido,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Código de referido (opcional)',
                      prefixIcon: Icon(Icons.redeem_outlined),
                      helperText: 'Si alguien te invitó, ingresa su código.',
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _controladorNombres,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nombres',
                      prefixIcon: Icon(Icons.person_outline),
                      hintText: 'Ej: Juan Carlos',
                    ),
                    validator: (valor) {
                      if (valor == null || valor.isEmpty) {
                        return 'Por favor ingresa tus nombres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _controladorApellidoPaterno,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Apellido paterno',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (valor) {
                      if (valor == null || valor.isEmpty) {
                        return 'Por favor ingresa tu apellido paterno';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _controladorApellidoMaterno,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Apellido materno',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (valor) {
                      if (valor == null || valor.isEmpty) {
                        return 'Por favor ingresa tu apellido materno';
                      }
                      return null;
                    },
                  ),
                  if (!widget.completarPerfilGoogle) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _controladorEmail,
                      decoration: const InputDecoration(
                        labelText: 'Correo Electrónico',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (valor) {
                        if (valor == null || valor.isEmpty) {
                          return 'Por favor ingresa tu correo';
                        }
                        if (!valor.contains('@')) {
                          return 'Ingresa un correo con @';
                        }
                        return null;
                      },
                    ),
                  ],
                  if (!widget.completarPerfilGoogle) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _controladorPassword,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (valor) {
                        if (valor == null || valor.isEmpty) {
                          return 'Por favor ingresa tu contraseña';
                        }
                        if (valor.length < 6) {
                          return 'La contraseña debe tener al menos 6 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _controladorConfirmPassword,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirmar Contraseña',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (valor) {
                        if (valor == null || valor.isEmpty) {
                          return 'Por favor confirma tu contraseña';
                        }
                        if (valor != _controladorPassword.text) {
                          return 'Las contraseñas no coinciden';
                        }
                        return null;
                      },
                    ),
                  ],
                  SizedBox(height: esFlujoGoogle ?20 : 32),

                  // Botón de Registro
                  ElevatedButton(
                    onPressed: _cargando ?null : _manejarRegistro,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      // Efecto de sombra
                      shadowColor: TemaAplicacion.colorPrimario.withValues(
                        alpha: 0.5,
                      ),
                      elevation: 8,
                    ),
                    child: _cargando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            widget.completarPerfilGoogle
                                ? 'Guardar y Continuar'
                                : 'Registrarse',
                          ),
                  ),

                  if (widget.completarPerfilGoogle) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '¿Ya tienes cuenta?',
                          style: TextStyle(
                            color: TemaAplicacion.textoSecundario,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacementNamed(context, '/login');
                          },
                          child: Text(
                            'Iniciar sesión',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: TemaAplicacion.colorPrimario,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (!widget.completarPerfilGoogle) ...[
                    const SizedBox(height: 24),

                    // Divider
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'o continúa con',
                            style: TextStyle(
                              color: TemaAplicacion.textoSecundario,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Google Button
                    SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _cargando ?null : _handleGoogleLogin,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.network(
                              'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1200px-Google_%22G%22_logo.svg.png',
                              height: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Google',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: TemaAplicacion.textoPrimario,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '¿Ya tienes cuenta?',
                          style: TextStyle(
                            color: TemaAplicacion.textoSecundario,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacementNamed(context, '/login');
                          },
                          child: Text(
                            'Iniciar Sesión',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: TemaAplicacion.colorPrimario,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TarjetaCategoria extends StatelessWidget {
  final String titulo;
  final bool estaSeleccionado;
  final VoidCallback alPresionar;
  final IconData icono;

  const _TarjetaCategoria({
    required this.titulo,
    required this.estaSeleccionado,
    required this.alPresionar,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: alPresionar,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: estaSeleccionado ?TemaAplicacion.colorPrimario : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: estaSeleccionado
                ? TemaAplicacion.colorPrimario
                : Colors.grey.shade200,
            width: 2,
          ),
          boxShadow: estaSeleccionado
              ? [
                  BoxShadow(
                    color: TemaAplicacion.colorPrimario.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          children: [
            Icon(
              icono,
              size: 32,
              color: estaSeleccionado
                  ? Colors.white
                  : TemaAplicacion.textoSecundario,
            ),
            const SizedBox(height: 8),
            Text(
              titulo,
              style: GoogleFonts.inter(
                color: estaSeleccionado
                    ? Colors.white
                    : TemaAplicacion.textoPrimario,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
