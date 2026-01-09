import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';

const String baseUrl = kBackendBaseUrl;

class AltaEmpleadoScreen extends StatefulWidget {
  const AltaEmpleadoScreen({super.key});

  @override
  State<AltaEmpleadoScreen> createState() => _AltaEmpleadoScreenState();
}

class _AltaEmpleadoScreenState extends State<AltaEmpleadoScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _apellidoController = TextEditingController();
  final TextEditingController _usuarioController = TextEditingController();
  final TextEditingController _contrasenaController = TextEditingController();

  List<Map<String, dynamic>> _empresas = [];
  List<Map<String, dynamic>> _roles = [];
  final List<String> _turnos = ['Mañana', 'Tarde', 'Central', 'Noche'];

  int? _empresaSeleccionadaId;
  int? _rolSeleccionadoId;
  String? _turnoSeleccionado;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _cargarEmpresas();
    _cargarRoles();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _usuarioController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }

  Future<void> _cargarEmpresas() async {
    final data = await _fetchCatalog('$baseUrl/empresas');
    if (!mounted) return;
    setState(() => _empresas = data);
  }

  Future<void> _cargarRoles() async {
    final data = await _fetchCatalog('$baseUrl/roles');
    if (!mounted) return;
    setState(() => _roles = data);
  }

  Future<List<Map<String, dynamic>>> _fetchCatalog(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as List<dynamic>;
        return decoded
            .map<Map<String, dynamic>>(
              (item) => Map<String, dynamic>.from(item as Map),
            )
            .toList();
      }
      debugPrint('[$runtimeType] GET $url failed (${response.statusCode})');
    } catch (e, s) {
      debugPrint('[$runtimeType] Error fetching $url -> $e');
      debugPrint('$s');
    }
    return [];
  }

  Future<void> _registrarEmpleado() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final payload = {
      'nombre': _nombreController.text.trim(),
      'apellido': _apellidoController.text.trim(),
      'empresa_id': _empresaSeleccionadaId,
      'turno': _turnoSeleccionado,
      'usuario': _usuarioController.text.trim(),
      'contrasena': _contrasenaController.text.trim(),
      'rol_id': _rolSeleccionadoId,
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/empleado'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        _showSnack('Empleado registrado correctamente');
        _resetForm();
      } else {
        _showSnack(
          'Error al registrar: ${response.body.isEmpty ? response.statusCode : response.body}',
          isError: true,
        );
      }
    } catch (_) {
      if (!mounted) return;
      _showSnack('No se pudo registrar al empleado', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _nombreController.clear();
    _apellidoController.clear();
    _usuarioController.clear();
    _contrasenaController.clear();
    setState(() {
      _empresaSeleccionadaId = null;
      _rolSeleccionadoId = null;
      _turnoSeleccionado = null;
    });
  }

  void _showSnack(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: colorScheme.primary),
      filled: true,
      fillColor: Colors.white.withValues(alpha: .9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .25)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
      ),
    );
  }

  List<DropdownMenuEntry<int>> get _empresaEntries => _empresas
      .map(
        (empresa) => DropdownMenuEntry<int>(
          value: (empresa['id'] as num).toInt(),
          label: empresa['nombre']?.toString() ?? '',
        ),
      )
      .toList();

  List<DropdownMenuEntry<int>> get _rolEntries => _roles
      .map(
        (rol) => DropdownMenuEntry<int>(
          value: (rol['id'] as num).toInt(),
          label: rol['nombre']?.toString() ?? '',
        ),
      )
      .toList();

  List<DropdownMenuEntry<String>> get _turnoEntries => _turnos
      .map(
        (turno) => DropdownMenuEntry<String>(
          value: turno,
          label: turno,
        ),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Alta de empleado'),
        backgroundColor: Colors.black.withValues(alpha: .15),
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 1.1),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: EdgeNavHandle(width: 28),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _buildGlassCard(theme),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard(ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: theme.cardColor.withValues(alpha: .85),
            border: Border.all(color: Colors.white.withValues(alpha: .2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .12),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double fieldWidth = constraints.maxWidth > 640
                  ? (constraints.maxWidth - 32) / 2
                  : constraints.maxWidth;

              return Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registra a un nuevo colaborador',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Completa los datos y asigna empresa, turno y rol antes de guardar.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: .7),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: fieldWidth,
                          child: TextFormField(
                            controller: _nombreController,
                            decoration: _inputDecoration('Nombre', Icons.badge_outlined),
                            validator: (value) =>
                                value == null || value.trim().isEmpty ? 'Introduce el nombre' : null,
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: TextFormField(
                            controller: _apellidoController,
                            decoration: _inputDecoration('Apellido', Icons.perm_identity),
                            validator: (value) =>
                                value == null || value.trim().isEmpty ? 'Introduce el apellido' : null,
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: TextFormField(
                            controller: _usuarioController,
                            decoration: _inputDecoration('Usuario', Icons.account_circle_outlined),
                            validator: (value) =>
                                value == null || value.trim().isEmpty ? 'Introduce el usuario' : null,
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: TextFormField(
                            controller: _contrasenaController,
                            obscureText: true,
                            decoration: _inputDecoration('Contraseña', Icons.lock_outline),
                            validator: (value) =>
                                value == null || value.trim().isEmpty ? 'Introduce la contraseña' : null,
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: _DropdownField<int>(
                            label: 'Empresa',
                            icon: Icons.apartment_outlined,
                            entries: _empresaEntries,
                            value: _empresaSeleccionadaId,
                            onSelected: (value) =>
                                setState(() => _empresaSeleccionadaId = value),
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: _DropdownField<String>(
                            label: 'Turno',
                            icon: Icons.schedule_outlined,
                            entries: _turnoEntries,
                            value: _turnoSeleccionado,
                            onSelected: (value) =>
                                setState(() => _turnoSeleccionado = value),
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: _DropdownField<int>(
                            label: 'Rol',
                            icon: Icons.workspace_premium_outlined,
                            entries: _rolEntries,
                            value: _rolSeleccionadoId,
                            onSelected: (value) =>
                                setState(() => _rolSeleccionadoId = value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2.2),
                              )
                            : const Icon(Icons.save_alt_outlined),
                        label: Text(_isLoading ? 'Guardando...' : 'Registrar empleado'),
                        onPressed: _isLoading ? null : _registrarEmpleado,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                          textStyle: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.icon,
    required this.entries,
    required this.value,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final List<DropdownMenuEntry<T>> entries;
  final T? value;
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;

    return FormField<T>(
      validator: (current) => current == null ? 'Selecciona $label' : null,
      initialValue: value,
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                return DropdownMenu<T>(
                  width: constraints.maxWidth,
                  initialSelection: value,
                  label: Text(label),
                  leadingIcon: Icon(icon),
                  trailingIcon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onSelected: (selection) {
                    field.didChange(selection);
                    onSelected(selection);
                  },
                  dropdownMenuEntries: entries,
                );
              },
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: Text(
                  field.errorText!,
                  style: TextStyle(color: errorColor, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }
}
