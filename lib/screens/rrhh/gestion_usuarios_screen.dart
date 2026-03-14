import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/api_service.dart';
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

  OverlayEntry? _edgeOverlay;

  @override
  void initState() {
    super.initState();
    _buscadorCtrl.addListener(_aplicarFiltro);
    _cargarInicial();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final isMobile = MediaQuery.of(context).size.width < 980;
      if (isMobile) return;
      final overlay = Overlay.of(context, rootOverlay: true);
      _edgeOverlay = OverlayEntry(
        builder: (ctx) {
          return Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: EdgeNavHandle(
                  width: 32,
                  currentRoute: '/hr/gestion_empleado',
                  showIndicator: true,
                ),
              ),
            ),
          );
        },
      );
      overlay.insert(_edgeOverlay!);
    });
  }

  @override
  void dispose() {
    _edgeOverlay?.remove();
    _buscadorCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarInicial() async {
    await Future.wait([_cargarEmpresas(), _cargarRoles()]);
    await _cargarEmpleados();
  }

  Future<void> _cargarEmpresas() async {
    final data = await _fetchCatalog('/empresas');
    if (!mounted) return;
    setState(() => _empresas = data);
  }

  Future<void> _cargarRoles() async {
    final data = await _fetchCatalog('/roles');
    if (!mounted) return;
    setState(() => _roles = data);
  }

  Future<List<Map<String, dynamic>>> _fetchCatalog(String endpoint) async {
    try {
      final service = ApiService.instance;
      if (service == null) return [];

      if (!service.client.hasAccessToken) {
        await service.refreshAccessToken();
      }

      final result = await service.client.get(endpoint);
      dynamic data = result.body;

      if (result.ok && data is Map && data.containsKey('results')) {
        data = data['results'];
      }

      if (result.ok && data is List) {
        return data
            .map<Map<String, dynamic>>(
              (item) => Map<String, dynamic>.from(item as Map),
            )
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _cargarEmpleados() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    const path = '/empleados/';

    try {
      final service = ApiService.instance;
      if (service == null) throw Exception('ApiService not initialized');

      if (!service.client.hasAccessToken) {
        await service.refreshAccessToken();
      }

      final res = await service.client.get(path);

      if (res.ok) {
        dynamic data = res.body;
        // Handle paginated or wrapped responses
        if (data is Map && data.containsKey('results')) {
          data = data['results'];
        }

        if (data is! List) throw Exception('Formato inesperado');

        final datos = data.cast<Map<String, dynamic>>()
          ..sort(
            (a, b) => '${a['nombre']} ${a['apellido']}'.toLowerCase().compareTo(
              '${b['nombre']} ${b['apellido']}'.toLowerCase(),
            ),
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
          _error = 'Error ${res.statusCode}: ${res.error ?? ''}';
          _cargando = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error de conexión: $e';
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
      final nombreCompleto = '${emp['nombre']} ${emp['apellido']}'
          .toLowerCase();
      return nombreCompleto.contains(normalized);
    }).toList();
  }

  Future<bool> _eliminarEmpleado(int id) async {
    try {
      final service = ApiService.instance;
      if (service == null) return false;

      final res = await service.client.delete('/empleados/$id/');
      if (res.ok) return true;
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
      final service = ApiService.instance;
      if (service == null) return false;

      final res = await service.client.put(
        '/empleados/$id/', // Corrected from /empleado/$id
        jsonBody: body,
      );
      if (res.ok) return true;
      _mostrarSnack('Error al actualizar (${res.statusCode})');
    } catch (_) {
      _mostrarSnack('No se pudo conectar al servidor');
    }
    return false;
  }

  Future<void> _descargarExcel() async {
    try {
      final service = ApiService.instance;
      if (service == null) return;

      final res = await service.client.getBytes('/empleados_excel');
      if (res.ok) {
        final dir = await _defaultDownloadDir();
        final file = File(
          '${dir.path}/empleados_${DateTime.now().millisecondsSinceEpoch}.xlsx',
        );
        await file.writeAsBytes(res.body as List<int>);
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
        final downloads = Directory(
          '${extDir.path.split('Android').first}Download',
        );
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
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
        await _cargarEmpleados();
      }
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontWeight: FontWeight.w500),
      prefixIcon: Icon(icon, color: Theme.of(context).primaryColor),
      filled: true,
      fillColor: Theme.of(
        context,
      ).scaffoldBackgroundColor.withValues(alpha: .5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: .1)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );
  }

  Future<void> _dialogoEditar(Map<String, dynamic> emp) async {
    final nombreCtrl = TextEditingController(
      text: emp['nombre']?.toString() ?? '',
    );
    final apellidoCtrl = TextEditingController(
      text: emp['apellido']?.toString() ?? '',
    );
    final usuarioCtrl = TextEditingController(
      text: emp['usuario']?.toString() ?? '',
    );
    final contrasenaCtrl = TextEditingController();

    String turnoSel = emp['turno']?.toString() ?? '';
    int? empresaSel = (emp['empresa_id'] as num?)?.toInt();
    int? rolSel = (emp['rol_id'] as num?)?.toInt();

    // Ensure initial selection exists in lists to avoid dropdown crashes
    if (turnoSel.isNotEmpty &&
        !['Mañana', 'Tarde', 'Central', 'Noche'].contains(turnoSel)) {
      turnoSel = '';
    }
    if (empresaSel != null && !_empresas.any((e) => e['id'] == empresaSel)) {
      empresaSel = null;
    }
    if (rolSel != null && !_roles.any((r) => r['id'] == rolSel)) {
      rolSel = null;
    }

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final modalIsMobile = MediaQuery.of(ctx).size.width < 560;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(
            horizontal: modalIsMobile ? 12 : 40,
            vertical: 24,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(modalIsMobile ? 18 : 24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                constraints: BoxConstraints(maxWidth: modalIsMobile ? 520 : 400),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withValues(alpha: .9),
                  border: Border.all(color: Colors.white.withValues(alpha: .2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: EdgeInsets.all(modalIsMobile ? 16 : 24),
                child: StatefulBuilder(
                  builder: (context, setModalState) {
                    return SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.edit_note, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Editar empleado',
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: .1),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.fingerprint, size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  'ID: ${emp['id']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: nombreCtrl,
                            decoration: _inputDecoration('Nombre', Icons.person),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: apellidoCtrl,
                            decoration: _inputDecoration(
                              'Apellido',
                              Icons.person_outline,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: usuarioCtrl,
                            enabled: false,
                            decoration:
                                _inputDecoration(
                                  'Usuario',
                                  Icons.account_circle,
                                ).copyWith(
                                  fillColor: Colors.grey.withValues(alpha: .2),
                                ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: contrasenaCtrl,
                            obscureText: true,
                            decoration: _inputDecoration(
                              'Contraseña',
                              Icons.lock,
                            ),
                          ),
                          const SizedBox(height: 20),
                          DropdownButtonFormField<String>(
                            value: turnoSel.isEmpty ? null : turnoSel,
                            decoration: _inputDecoration(
                              'Turno',
                              Icons.schedule,
                            ).copyWith(contentPadding: EdgeInsets.zero),
                            items: ['Mañana', 'Tarde', 'Central', 'Noche']
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Text(t),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setModalState(() => turnoSel = v ?? ''),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: empresaSel,
                            decoration: _inputDecoration(
                              'Empresa',
                              Icons.business,
                            ).copyWith(contentPadding: EdgeInsets.zero),
                            items: _empresas
                                .map(
                                  (e) => DropdownMenuItem<int>(
                                    value: (e['id'] as num).toInt(),
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Text(
                                        e['nombre']?.toString() ?? 'Sin nombre',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setModalState(() => empresaSel = v),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: rolSel,
                            decoration: _inputDecoration(
                              'Rol',
                              Icons.badge,
                            ).copyWith(contentPadding: EdgeInsets.zero),
                            items: _roles
                                .map(
                                  (r) => DropdownMenuItem<int>(
                                    value: (r['id'] as num).toInt(),
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Text(
                                        r['nombre']?.toString() ?? 'Sin nombre',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setModalState(() => rolSel = v),
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton.icon(
                                icon: const Icon(Icons.save),
                                label: const Text('Guardar'),
                                onPressed: () {
                                  if (nombreCtrl.text.trim().isEmpty ||
                                      apellidoCtrl.text.trim().isEmpty ||
                                      (turnoSel.isEmpty) ||
                                      empresaSel == null ||
                                      rolSel == null) {
                                    _mostrarSnack('Revisa los campos requeridos');
                                    return;
                                  }
                                  Navigator.of(ctx).pop(true);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    if (guardado == true) {
      final ok = await _actualizarEmpleado(
        id: emp['id'] as int,
        nombre: nombreCtrl.text.trim(),
        apellido: apellidoCtrl.text.trim(),
        turno: turnoSel,
        empresaId: empresaSel!,
        rolId: rolSel!,
        contrasena: contrasenaCtrl.text.trim().isEmpty
            ? null
            : contrasenaCtrl.text.trim(),
      );
      if (ok) {
        _mostrarSnack('Empleado actualizado');
        await _cargarEmpleados();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 980;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

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

          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 10 : 16,
                isMobile ? 10 : 16,
                isMobile ? 10 : 16,
                (isMobile ? 92 : 16) + bottomInset,
              ),
              child: Column(
                children: [
                  _buildControlsCard(theme, isMobile: isMobile),
                  SizedBox(height: isMobile ? 10 : 16),
                  Expanded(child: _buildEmployeeList(theme, isMobile: isMobile)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsCard(ThemeData theme, {required bool isMobile}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(isMobile ? 20 : 26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.all(isMobile ? 14 : 20),
          decoration: BoxDecoration(
            color: theme.cardColor.withValues(alpha: .65),
            borderRadius: BorderRadius.circular(isMobile ? 20 : 30),
            border: Border.all(color: Colors.white.withValues(alpha: .2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .1),
                blurRadius: 30,
                offset: const Offset(0, 15),
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
                  fillColor: theme.scaffoldBackgroundColor.withValues(
                    alpha: .5,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (isMobile)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                    onPressed: _cargarEmpleados,
                  ),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualizar'),
                      onPressed: _cargarEmpleados,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeList(ThemeData theme, {required bool isMobile}) {
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
                onPressed: _cargarEmpleados,
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
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text('No se encontraron empleados'),
            ],
          ),
        ),
      );
    }

    return _glassCard(
      theme,
      child: RefreshIndicator(
        onRefresh: _cargarEmpleados,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _filtrados.length,

          itemBuilder: (context, index) {
            final emp = _filtrados[index];
            final nombre = emp['nombre']?.toString() ?? '';
            final apellido = emp['apellido']?.toString() ?? '';
            final initials =
                (nombre.isNotEmpty ? nombre[0] : '') +
                (apellido.isNotEmpty ? apellido[0] : '');
            final trailingActions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(
                    Icons.edit_rounded,
                    color: Colors.blueAccent,
                  ),
                  onPressed: () => _dialogoEditar(emp),
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  icon: Icon(
                    Icons.delete_rounded,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: () => _dialogoEliminar(emp),
                ),
              ],
            );

            return Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: .3)),
              ),
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 12 : 20,
                  vertical: isMobile ? 8 : 12,
                ),
                leading: CircleAvatar(
                  radius: isMobile ? 20 : 24,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    initials.toUpperCase(),
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$nombre $apellido',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: .05),
                              ),
                            ),
                            child: Text(
                              '#${emp['id']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: .6,
                                ),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Flexible(
                            child: Text(
                              '$nombre $apellido',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: .05),
                              ),
                            ),
                            child: Text(
                              '#${emp['id']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: .6,
                                ),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _Badge(
                            text: emp['turno'] ?? '-',
                            color: Colors.blue.withValues(alpha: .1),
                            textColor: Colors.blue.shade800,
                          ),
                          _Badge(
                            text:
                                emp['empresa'] ??
                                emp['empresa_nombre'] ??
                                'Sin empresa',
                            color: Colors.purple.withValues(alpha: .1),
                            textColor: Colors.purple.shade800,
                          ),
                          Text(
                            emp['rol'] ?? emp['rol_nombre'] ?? '-',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: .6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isMobile)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: trailingActions,
                          ),
                        ),
                    ],
                  ),
                ),
                trailing: isMobile ? null : trailingActions,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _glassCard(ThemeData theme, {required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardColor.withValues(alpha: .6),
            border: Border.all(color: Colors.white.withValues(alpha: .2)),
            borderRadius: BorderRadius.circular(30),
          ),
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.color,
    required this.textColor,
  });

  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
