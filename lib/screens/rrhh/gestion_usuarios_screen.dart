import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../config.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';

const String baseUrl = kBackendBaseUrl;

class GestionEmpleadosScreen extends StatefulWidget {
  const GestionEmpleadosScreen({super.key});

  @override
  State<GestionEmpleadosScreen> createState() => _GestionEmpleadosScreenState();
}

class _GestionEmpleadosScreenState extends State<GestionEmpleadosScreen> {
  final TextEditingController _buscadorCtrl = TextEditingController();

  List<Map<String, dynamic>> _empleados = [];
  List<Map<String, dynamic>> _filtrados = [];
  List<Map<String, dynamic>> _empresas = [];
  List<Map<String, dynamic>> _roles = [];

  bool _cargando = true;
  String? _error;
  bool _mostrarSoloActivos = false;

  @override
  void initState() {
    super.initState();
    _buscadorCtrl.addListener(_aplicarFiltro);
    _cargarInicial();
  }

  @override
  void dispose() {
    _buscadorCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarInicial() async {
    await Future.wait([
      _cargarEmpresas(),
      _cargarRoles(),
    ]);
    await _cargarEmpleados();
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
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final List<dynamic> body = jsonDecode(res.body) as List<dynamic>;
        return body
            .map<Map<String, dynamic>>(
              (item) => Map<String, dynamic>.from(item as Map),
            )
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _cargarEmpleados({bool soloActivos = false}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    final uri = soloActivos
        ? Uri.parse('$baseUrl/fichajes').replace(
            queryParameters: {
              'activos': '1',
              'fecha': DateTime.now().toIso8601String().substring(0, 10),
            },
          )
        : Uri.parse('$baseUrl/empleado');

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final datos =
            (jsonDecode(res.body) as List).cast<Map<String, dynamic>>()..sort(
              (a, b) => '${a['nombre']} ${a['apellido']}'
                  .toLowerCase()
                  .compareTo('${b['nombre']} ${b['apellido']}'.toLowerCase()),
            );

        if (!mounted) return;
        setState(() {
          _empleados = datos;
          _filtrados = _filtrarLista(_buscadorCtrl.text);
          _cargando = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _error = 'Error ${res.statusCode}: ${res.reasonPhrase ?? ''}';
          _cargando = false;
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Tiempo de espera agotado';
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Sin conexión con el servidor';
        _cargando = false;
      });
    }
  }

  void _aplicarFiltro() {
    final query = _buscadorCtrl.text;
    setState(() => _filtrados = _filtrarLista(query));
  }

  List<Map<String, dynamic>> _filtrarLista(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return List<Map<String, dynamic>>.from(_empleados);
    }
    return _empleados.where((emp) {
      final nombreCompleto =
          '${emp['nombre']} ${emp['apellido']}'.toLowerCase();
      return nombreCompleto.contains(normalized);
    }).toList();
  }

  Future<bool> _eliminarEmpleado(int id) async {
    try {
      final res = await http
          .delete(Uri.parse('$baseUrl/empleado/$id'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) return true;
      _mostrarSnack('Error al eliminar (${res.statusCode})');
    } catch (_) {
      _mostrarSnack('No se pudo conectar al servidor');
    }
    return false;
  }

  Future<bool> _actualizarEmpleado({
    required int id,
    required String nombre,
    required String apellido,
    required String turno,
    required int empresaId,
    required int rolId,
    String? contrasena,
  }) async {
    final body = {
      'nombre': nombre,
      'apellido': apellido,
      'turno': turno,
      'empresa_id': empresaId,
      'rol_id': rolId,
    };
    if (contrasena != null && contrasena.trim().isNotEmpty) {
      body['contrasena'] = contrasena.trim();
    }

    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/empleado/$id'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) return true;
      _mostrarSnack('Error al actualizar (${res.statusCode})');
    } catch (_) {
      _mostrarSnack('No se pudo conectar al servidor');
    }
    return false;
  }

  Future<void> _descargarExcel() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/empleados_excel'));
      if (res.statusCode == 200) {
        final dir = await _defaultDownloadDir();
        final file = File(
          '${dir.path}/empleados_${DateTime.now().millisecondsSinceEpoch}.xlsx',
        );
        await file.writeAsBytes(res.bodyBytes);
        _mostrarSnack('Excel descargado en ${file.parent.path}');
        await OpenFilex.open(file.path);
      } else {
        _mostrarSnack('Error al descargar Excel (${res.statusCode})');
      }
    } catch (_) {
      _mostrarSnack('No se pudo descargar el archivo');
    }
  }

  Future<Directory> _defaultDownloadDir() async {
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final downloads = Directory('${extDir.path.split('Android').first}Download');
        if (await downloads.exists()) return downloads;
        await downloads.create(recursive: true);
        return downloads;
      }
    }
    if (Platform.isIOS) {
      return await getApplicationDocumentsDirectory();
    }
    final downloads = await getDownloadsDirectory();
    return downloads ?? await getTemporaryDirectory();
  }

  void _mostrarSnack(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _dialogoEliminar(Map<String, dynamic> emp) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar empleado'),
        content: Text(
          '¿Seguro que quieres eliminar a ${emp['nombre']} ${emp['apellido']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmado == true) {
      final ok = await _eliminarEmpleado(emp['id'] as int);
      if (ok) {
        _mostrarSnack('Empleado eliminado');
        await _cargarEmpleados(soloActivos: _mostrarSoloActivos);
      }
    }
  }

  Future<void> _dialogoEditar(Map<String, dynamic> emp) async {
    final nombreCtrl = TextEditingController(text: emp['nombre']?.toString() ?? '');
    final apellidoCtrl = TextEditingController(text: emp['apellido']?.toString() ?? '');
    final usuarioCtrl = TextEditingController(text: emp['usuario']?.toString() ?? '');
    final contrasenaCtrl = TextEditingController();

    String turnoSel = emp['turno']?.toString() ?? '';
    int? empresaSel = (emp['empresa_id'] as num?)?.toInt();
    int? rolSel = (emp['rol_id'] as num?)?.toInt();

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('Editar empleado'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  TextField(
                    controller: apellidoCtrl,
                    decoration: const InputDecoration(labelText: 'Apellido'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: usuarioCtrl,
                    enabled: false,
                    decoration: const InputDecoration(labelText: 'Usuario'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: contrasenaCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña (opcional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownMenu<String>(
                    initialSelection: turnoSel.isEmpty ? null : turnoSel,
                    label: const Text('Turno'),
                    onSelected: (value) => setModalState(() => turnoSel = value ?? ''),
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: 'Mañana', label: 'Mañana'),
                      DropdownMenuEntry(value: 'Tarde', label: 'Tarde'),
                      DropdownMenuEntry(value: 'Central', label: 'Central'),
                      DropdownMenuEntry(value: 'Noche', label: 'Noche'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownMenu<int>(
                    initialSelection: empresaSel,
                    label: const Text('Empresa'),
                    dropdownMenuEntries: _empresas
                        .map(
                          (e) => DropdownMenuEntry<int>(
                            value: (e['id'] as num).toInt(),
                            label: e['nombre']?.toString() ?? '',
                          ),
                        )
                        .toList(),
                    onSelected: (value) => setModalState(() => empresaSel = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownMenu<int>(
                    initialSelection: rolSel,
                    label: const Text('Rol'),
                    dropdownMenuEntries: _roles
                        .map(
                          (r) => DropdownMenuEntry<int>(
                            value: (r['id'] as num).toInt(),
                            label: r['nombre']?.toString() ?? '',
                          ),
                        )
                        .toList(),
                    onSelected: (value) => setModalState(() => rolSel = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  if (nombreCtrl.text.trim().isEmpty ||
                      apellidoCtrl.text.trim().isEmpty ||
                      (turnoSel.isEmpty) ||
                      empresaSel == null ||
                      rolSel == null) {
                    _mostrarSnack('Completa todos los campos obligatorios');
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                },
                child: const Text('Guardar cambios'),
              ),
            ],
          );
        },
      ),
    );

    if (guardado == true) {
      final ok = await _actualizarEmpleado(
        id: emp['id'] as int,
        nombre: nombreCtrl.text.trim(),
        apellido: apellidoCtrl.text.trim(),
        turno: turnoSel,
        empresaId: empresaSel!,
        rolId: rolSel!,
        contrasena:
            contrasenaCtrl.text.trim().isEmpty ? null : contrasenaCtrl.text.trim(),
      );
      if (ok) {
        _mostrarSnack('Empleado actualizado');
        await _cargarEmpleados(soloActivos: _mostrarSoloActivos);
      }
    }
  }

  Future<void> _toggleSoloActivos(bool value) async {
    setState(() => _mostrarSoloActivos = value);
    await _cargarEmpleados(soloActivos: value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numActivos =
        _empleados.where((e) => (e['activo'] ?? 0) == 1).length;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Gestión de empleados'),
        backgroundColor: Colors.black.withValues(alpha: .15),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Exportar Excel',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _descargarExcel,
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 1.05),
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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildControlsCard(theme, numActivos),
                  const SizedBox(height: 16),
                  Expanded(child: _buildEmployeeList(theme)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsCard(ThemeData theme, int numActivos) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(20),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Busca y filtra tu plantilla',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _buscadorCtrl,
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o apellido',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: .2)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Switch.adaptive(
                    value: _mostrarSoloActivos,
                    onChanged: (value) => _toggleSoloActivos(value),
                  ),
                  const SizedBox(width: 8),
                  const Text('Mostrar solo activos'),
                  const Spacer(),
                  Chip(
                    avatar: const Icon(Icons.people, size: 18),
                    label: Text('Activos: $numActivos'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                    onPressed: () => _cargarEmpleados(soloActivos: _mostrarSoloActivos),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeList(ThemeData theme) {
    if (_cargando) {
      return _glassCard(
        theme,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return _glassCard(
        theme,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _cargarEmpleados(soloActivos: _mostrarSoloActivos),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filtrados.isEmpty) {
      return _glassCard(
        theme,
        child: const Center(child: Text('Sin resultados')), 
      );
    }

    return _glassCard(
      theme,
      child: RefreshIndicator(
        onRefresh: () => _cargarEmpleados(soloActivos: _mostrarSoloActivos),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _filtrados.length,
          separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: .2)),
          itemBuilder: (context, index) {
            final emp = _filtrados[index];
            return ListTile(
              title: Text('${emp['nombre']} ${emp['apellido']}'),
              subtitle: Text(
                'Turno: ${emp['turno'] ?? '-'} • '
                'Empresa: ${emp['empresa'] ?? emp['empresa_nombre'] ?? '-'} • '
                'Rol: ${emp['rol'] ?? emp['rol_nombre'] ?? '-'}',
              ),
              trailing: Wrap(
                spacing: 6,
                children: [
                  IconButton(
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit, color: Colors.lightBlueAccent),
                    onPressed: () => _dialogoEditar(emp),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () => _dialogoEliminar(emp),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _glassCard(ThemeData theme, {required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardColor.withValues(alpha: .85),
            border: Border.all(color: Colors.white.withValues(alpha: .15)),
          ),
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}
