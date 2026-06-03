import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';
import 'package:provider/provider.dart';
import '../../api_client.dart';
import '../../services/api_service.dart';

const String baseUrl = kBackendBaseUrl;

// ─────────── Dark Glassmorphism palette ───────────
const Color kGlassStroke = Color(0x1AFFFFFF);
const Color kGlassFill = Color(0x0EFFFFFF);
const Color kPrimary = Color(0xFF90CAF9); // sleek light blue accent
const Color kPrimaryDark = Color(0xFF42A5F5);
const Color kTextOnGlass = Color(0xFFF5F5F7);
const Color kTextSecondary = Color(0xFF8E8E93);
const Color kActivo = Color(0xFF34C759); // vibrant iOS-style green
const Color kAusente = Color(0xFFFF9500); // vibrant iOS-style amber

class JobSelectorScreen extends StatefulWidget {
  const JobSelectorScreen({super.key});

  @override
  State<JobSelectorScreen> createState() => _JobSelectorScreenState();
}

class _JobSelectorScreenState extends State<JobSelectorScreen> {
  DateTime _fecha = DateTime.now();
  int? _empresaId;
  bool _cargando = false;
  final ScrollController _hScrollCtrl = ScrollController();
  final ValueNotifier<bool> _dragging = ValueNotifier<bool>(false);
  SharedPreferences? _prefs;
  int? _pendingEmpresaId;
  // Auto-scroll while dragging
  Timer? _autoScrollTimer;
  Offset? _lastPointerLocal; // position inside board viewport
  double _boardWidth = 0; // viewport width from LayoutBuilder
  static const double _edgeSize = 80; // px near borders to trigger autoscroll
  static const double _maxAutoScrollPxPerTick = 28; // per tick ~16ms

  // datos del board
  List<Map<String, dynamic>> _jobs =
      []; // cada job: {id, nombre, empleados: [...]}
  List<Map<String, dynamic>> _unassigned = [];
  List<Map<String, dynamic>> _empresas = [];

  static const _prefsKeyFecha = 'job_selector_fecha';
  static const _prefsKeyEmpresa = 'job_selector_empresa';

  @override
  void initState() {
    super.initState();
    _initializeState();
    // Stop autoscroll when drag ends
    _dragging.addListener(() {
      if (!_dragging.value) {
        _stopAutoScroll();
      }
    });
  }

  @override
  void dispose() {
    _hScrollCtrl.dispose();
    _dragging.dispose();
    _stopAutoScroll();
    super.dispose();
  }

  Future<void> _initializeState() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }

    if (!mounted) return;

    DateTime? savedDate;
    bool hasSavedEmpresa = false;
    int? savedEmpresa;
    if (prefs != null) {
      final dateStr = prefs.getString(_prefsKeyFecha);
      if (dateStr != null) {
        savedDate = DateTime.tryParse(dateStr);
      }
      if (prefs.containsKey(_prefsKeyEmpresa)) {
        hasSavedEmpresa = true;
        savedEmpresa = prefs.getInt(_prefsKeyEmpresa);
      }
    }

    setState(() {
      _prefs = prefs;
      if (savedDate != null) {
        _fecha = savedDate;
      }
      if (hasSavedEmpresa) {
        _pendingEmpresaId = savedEmpresa;
      }
    });

    if (savedDate == null) {
      if (prefs != null) {
        await prefs.setString(_prefsKeyFecha, _fecha.toIso8601String());
      } else {
        await _saveFecha(_fecha);
      }
    }

    await _cargarEmpresas();

    if (!mounted) return;

    if (_pendingEmpresaId != null) {
      final exists = _empresas.any((e) {
        final id = e['id'];
        if (id is int) return id == _pendingEmpresaId;
        if (id is num) return id.toInt() == _pendingEmpresaId;
        return false;
      });
      if (exists) {
        setState(() => _empresaId = _pendingEmpresaId);
      } else {
        await _saveEmpresa(null);
      }
    }

    _pendingEmpresaId = null;

    await _cargarBoard();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<SharedPreferences?> _getPrefs() async {
    if (_prefs != null) return _prefs;
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      _prefs = null;
    }
    return _prefs;
  }

  Future<void> _saveFecha(DateTime fecha) async {
    final prefs = await _getPrefs();
    if (prefs == null) return;
    await prefs.setString(_prefsKeyFecha, fecha.toIso8601String());
  }

  Future<void> _saveEmpresa(int? empresaId) async {
    final prefs = await _getPrefs();
    if (prefs == null) return;
    if (empresaId == null) {
      await prefs.remove(_prefsKeyEmpresa);
    } else {
      await prefs.setInt(_prefsKeyEmpresa, empresaId);
    }
  }

  Future<void> _applyFechaChange(DateTime newDate) async {
    if (_isSameDay(_fecha, newDate)) return;
    setState(() => _fecha = newDate);
    await _saveFecha(newDate);
    await _cargarBoard();
  }

  Future<void> _updateEmpresaFilter(int? empresaId) async {
    if (_empresaId == empresaId) return;
    setState(() => _empresaId = empresaId);
    await _saveEmpresa(empresaId);
    await _cargarBoard();
  }

  String get _fechaStr => _fecha.toIso8601String().substring(0, 10);

  ApiClient get _api => Provider.of<ApiService>(context, listen: false).client;

  Future<void> _cargarEmpresas() async {
    try {
      final res = await _api.get('/empresas');
      if (res.ok) {
        setState(
          () => _empresas = (res.body as List).cast<Map<String, dynamic>>(),
        );
      }
    } catch (_) {}
  }

  Future<void> _cargarBoard() async {
    setState(() => _cargando = true);
    final params = <String, String>{'fecha': _fechaStr};
    if (_empresaId != null) params['empresa_id'] = _empresaId.toString();

    final query = Uri(queryParameters: params).query;
    try {
      final res = await _api.get('/jobs/board?$query');
      if (res.ok) {
        final data = res.body as Map<String, dynamic>;
        setState(() {
          _jobs = (data['jobs'] as List).cast<Map<String, dynamic>>();
          _unassigned = (data['unassigned'] as List)
              .cast<Map<String, dynamic>>();
        });
      } else {
        _showSnack('Error ${res.statusCode} al cargar tablero');
        setState(() {
          _jobs = [];
          _unassigned = [];
        });
      }
    } catch (e) {
      _showSnack('Error de red');
      setState(() {
        _jobs = [];
        _unassigned = [];
      });
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _crearJobDialog() async {
    final nombreCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nuevo trabajo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final nombre = nombreCtrl.text.trim();
      final descripcion = descCtrl.text.trim();
      if (nombre.isEmpty) {
        _showSnack('El nombre no puede estar vacío');
        return;
      }
      await _crearJob(
        nombre: nombre,
        descripcion: descripcion.isEmpty ? null : descripcion,
      );
    }
  }

  Future<void> _crearJob({required String nombre, String? descripcion}) async {
    try {
      final res = await _api.post(
        '/jobs',
        jsonBody: {
          'nombre': nombre,
          if (descripcion != null) 'descripcion': descripcion,
        },
      );
      if (res.ok) {
        _showSnack('Trabajo creado');
        _cargarBoard();
      } else {
        _showSnack('Error al crear (${res.statusCode})');
      }
    } catch (_) {
      _showSnack('Error de red al crear');
    }
  }

  Future<void> _eliminarJob(int jobId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar trabajo'),
        content: const Text('¿Seguro que deseas eliminar este trabajo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await _api.delete('/jobs/$jobId');
      if (res.ok) {
        _showSnack('Trabajo eliminado');
        _cargarBoard();
      } else {
        _showSnack('Error al eliminar (${res.statusCode})');
      }
    } catch (_) {
      _showSnack('Error de red al eliminar');
    }
  }

  Future<void> _asignarEmpleado({
    required int empleadoId,
    required int jobId,
  }) async {
    try {
      final res = await _api.post(
        '/jobs/assign',
        jsonBody: {
          'fecha': _fechaStr,
          'empleado_id': empleadoId,
          'job_id': jobId,
        },
      );
      if (res.ok) {
        _cargarBoard();
      } else {
        _showSnack('Error al asignar (${res.statusCode})');
      }
    } catch (_) {
      _showSnack('Error de red al asignar');
    }
  }

  Future<void> _desasignarEmpleado({required int empleadoId}) async {
    // Delete with body is non-standard, using http but attaching token manually
    if (!_api.hasAccessToken) {
      _showSnack('No autenticado');
      return;
    }
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/jobs/assign'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_api.accessToken}',
        },
        body: json.encode({'fecha': _fechaStr, 'empleado_id': empleadoId}),
      );
      if (res.statusCode == 200) {
        _cargarBoard();
      } else {
        _showSnack('Error al desasignar (${res.statusCode})');
      }
    } catch (_) {
      _showSnack('Error de red al desasignar');
    }
  }

  Future<void> _renombrarJob(int jobId, String nombre) async {
    try {
      final res = await _api.put('/jobs/$jobId', jsonBody: {'nombre': nombre});
      if (res.ok) {
        _showSnack('Trabajo actualizado');
        _cargarBoard();
      } else {
        _showSnack('Error al actualizar (${res.statusCode})');
      }
    } catch (_) {
      _showSnack('Error de red al actualizar');
    }
  }

  Future<void> _exportarExcel() async {
    // 1) Elegir fecha
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      initialDate: _fecha,
    );
    if (picked == null) return;
    final fechaStr = picked.toIso8601String().substring(0, 10);

    // 2) Llamar endpoint y descargar bytes
    final qp = <String, String>{'fecha': fechaStr};
    if (_empresaId != null) qp['empresa_id'] = _empresaId.toString();
    final query = Uri(queryParameters: qp).query;

    ApiResult res;
    try {
      res = await _api.getBytes('/jobs/export?$query');
    } catch (_) {
      _showSnack('No se pudo contactar con el servidor');
      return;
    }
    if (!res.ok) {
      _showSnack('Error ${res.statusCode} al exportar');
      return;
    }
    final contentType = res.headers?['content-type'] ?? '';
    final bytes = res.body as List<int>;

    // 3) Guardar en carpeta destino estándar
    final suggested =
        'jobs_$fechaStr${_empresaId != null ? '_empresa_$_empresaId' : ''}.xlsx';
    final dir = await _defaultDownloadDir();
    final path = '${dir.path}${Platform.pathSeparator}$suggested';
    try {
      final file = File(path);
      await file.writeAsBytes(bytes);
    } catch (_) {
      _showSnack('No se pudo guardar el archivo en ${dir.path}');
      return;
    }

    // 4) Abrir archivo
    try {
      await OpenFilex.open(path);
    } catch (_) {
      _showSnack('Exportado. Ruta: $path');
    }

    if (contentType.contains('application/json')) {
      _showSnack(
        'El servidor devolvió JSON en lugar de Excel. Verifica dependencias.',
      );
    }
  }

  Future<Directory> _defaultDownloadDir() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        return await getApplicationDocumentsDirectory();
      }
    } catch (_) {}
    final docs = await getApplicationDocumentsDirectory();
    final parent = Directory(docs.path).parent;
    final candidates = <Directory>[
      Directory('${parent.path}${Platform.pathSeparator}Downloads'),
      Directory('${parent.path}${Platform.pathSeparator}Descargas'),
      Directory('${parent.path}${Platform.pathSeparator}Download'),
    ];
    for (final dir in candidates) {
      if (await dir.exists()) return dir;
    }
    return docs;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mq = MediaQuery.maybeOf(context);
    final isDesktop = (mq?.size.width ?? 1000) >= 900;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: !isDesktop,
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 64,
        title: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              color: theme.brightness == Brightness.dark
                  ? Colors.white.withAlpha(28)
                  : Colors.white.withAlpha(200),
              child: Text(
                'Asignación diaria de puestos',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color:
                      theme.textTheme.titleLarge?.color ??
                      colorScheme.onSurface,
                  letterSpacing: .4,
                ),
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Exportar Excel',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _exportarExcel,
          ),
          IconButton(
            tooltip: 'Nuevo trabajo',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: _crearJobDialog,
          ),
          IconButton(
            tooltip: 'Recargar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargarBoard,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            child: _buildFiltersBar(theme, colorScheme),
          ),
        ),
      ),
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 1.0),
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
              padding: const EdgeInsets.all(12),
              child: _cargando
                  ? _buildLoading(theme)
                  : _buildBoardContainer(theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersBar(ThemeData theme, ColorScheme colorScheme) {
    final accent = colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.45),
            border: Border.all(color: kGlassStroke),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Día anterior',
                  icon: Icon(Icons.chevron_left, color: accent),
                  onPressed: () => unawaited(
                    _applyFechaChange(_fecha.subtract(const Duration(days: 1))),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    backgroundColor: Colors.white.withOpacity(0.05),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(Icons.calendar_today, size: 18, color: accent),
                  label: Text(
                    _fechaStr,
                    style: TextStyle(
                      color: kTextOnGlass,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2023, 1, 1),
                      lastDate: DateTime(2030, 12, 31),
                      initialDate: _fecha,
                    );
                    if (picked != null) {
                      await _applyFechaChange(picked);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Día siguiente',
                  icon: Icon(Icons.chevron_right, color: accent),
                  onPressed: () => unawaited(
                    _applyFechaChange(_fecha.add(const Duration(days: 1))),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<int>(
                    initialValue: _empresaId,
                    isExpanded: true,
                    dropdownColor: theme.cardColor,
                    style: const TextStyle(color: kTextOnGlass),
                    items: _empresas
                        .map(
                          (e) => DropdownMenuItem<int>(
                            value: (e['id'] as num).toInt(),
                            child: Text(
                              e['nombre'].toString(),
                              style: const TextStyle(color: kTextOnGlass),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => unawaited(_updateEmpresaFilter(v)),
                    decoration: InputDecoration(
                      labelText: 'Empresa (filtra empleados)',
                      labelStyle: TextStyle(color: kTextSecondary),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.03),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: kGlassStroke,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: kGlassStroke,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: accent, width: 1.3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                _Legend(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoardContainer(ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.35),
            border: Border.all(color: kGlassStroke),
          ),
          child: _buildBoard(),
        ),
      ),
    );
  }

  Widget _buildLoading(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        const CircularProgressIndicator(),
        const SizedBox(height: 18),
        Text(
          'Cargando tablero...',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildBoard() {
    // Construye la lista de columnas: Unassigned + Jobs
    final columns = <Widget>[
      _JobColumn(
        title: 'Sin asignar',
        employees: _unassigned,
        onAccept: (empId) => _desasignarEmpleado(empleadoId: empId),
        allowDelete: false,
        jobId: null,
        onRename: null,
        dragging: _dragging,
      ),
      for (final job in _jobs)
        _JobColumn(
          title: job['nombre'].toString(),
          employees: (job['empleados'] as List).cast<Map<String, dynamic>>(),
          onAccept: (empId) =>
              _asignarEmpleado(empleadoId: empId, jobId: job['id'] as int),
          onDelete: () => _eliminarJob(job['id'] as int),
          jobId: job['id'] as int,
          onRename: (id, newName) => _renombrarJob(id, newName),
          dragging: _dragging,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        _boardWidth = constraints.maxWidth;
        return MouseRegion(
          onHover: (event) {
            _lastPointerLocal = event.localPosition;
            if (_dragging.value) _ensureAutoScroll();
          },
          onExit: (_) {
            _lastPointerLocal = null;
            _stopAutoScroll();
          },
          child: Listener(
            onPointerMove: (event) {
              _lastPointerLocal = event.localPosition;
              if (_dragging.value) _ensureAutoScroll();
            },
            child: Scrollbar(
              controller: _hScrollCtrl,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _hScrollCtrl,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final c in columns)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: c,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─────────── Autoscroll helpers ───────────
  void _ensureAutoScroll() {
    if (_autoScrollTimer != null) return;
    _autoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _autoScrollTick(),
    );
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _autoScrollTick() {
    if (!_dragging.value) {
      _stopAutoScroll();
      return;
    }
    if (_lastPointerLocal == null) return;
    if (!_hScrollCtrl.hasClients) return;

    final pos = _lastPointerLocal!;
    double delta = 0;
    if (pos.dx <= _edgeSize) {
      final t = ((_edgeSize - pos.dx).clamp(0, _edgeSize)) / _edgeSize; // 0..1
      delta = -t * _maxAutoScrollPxPerTick;
    } else if (pos.dx >= _boardWidth - _edgeSize) {
      final t =
          ((pos.dx - (_boardWidth - _edgeSize)).clamp(0, _edgeSize)) /
          _edgeSize; // 0..1
      delta = t * _maxAutoScrollPxPerTick;
    } else {
      // Not near edges → stop scrolling until pointer comes back to edges
      _stopAutoScroll();
      return;
    }

    if (delta == 0) return;
    final position = _hScrollCtrl.position;
    final newOffset = (position.pixels + delta).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if (newOffset != position.pixels) {
      _hScrollCtrl.jumpTo(newOffset);
    }
  }
}

// ─────────── Widgets ───────────

class _JobColumn extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> employees;
  final ValueChanged<int> onAccept; // empleadoId
  final VoidCallback? onDelete;
  final bool allowDelete;
  final int? jobId; // optional for actions like rename/delete
  final Future<void> Function(int jobId, String newName)? onRename;
  final ValueNotifier<bool>? dragging;
  const _JobColumn({
    required this.title,
    required this.employees,
    required this.onAccept,
    this.onDelete,
    this.allowDelete = true,
    this.jobId,
    this.onRename,
    this.dragging,
  });

  @override
  State<_JobColumn> createState() => _JobColumnState();
}

class _JobColumnState extends State<_JobColumn> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: kGlassFill,
                  border: Border.all(color: kGlassStroke),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.title} (${widget.employees.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: kTextOnGlass,
                        ),
                      ),
                    ),
                    if (widget.allowDelete)
                      PopupMenuButton<String>(
                        tooltip: 'Acciones',
                        icon: const Icon(Icons.more_vert, color: kPrimaryDark),
                        onSelected: (value) async {
                          if (value == 'rename' &&
                              widget.jobId != null &&
                              widget.onRename != null) {
                            final ctrl = TextEditingController(
                              text: widget.title,
                            );
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Renombrar trabajo'),
                                content: TextField(
                                  controller: ctrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Nombre',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancelar'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Guardar'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              final newName = ctrl.text.trim();
                              if (newName.isNotEmpty) {
                                await widget.onRename!(widget.jobId!, newName);
                              }
                            }
                          } else if (value == 'delete' &&
                              widget.onDelete != null) {
                            widget.onDelete!();
                          }
                        },
                        itemBuilder: (context) => [
                          if (widget.jobId != null)
                            const PopupMenuItem(
                              value: 'rename',
                              child: Text('Renombrar'),
                            ),
                          if (widget.onDelete != null)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Eliminar'),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Scrollable content with glass card
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kGlassFill,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kGlassStroke),
                      ),
                      child: widget.employees.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                child: Text(
                                  'Arrastra aquí',
                                  style: TextStyle(
                                    color: kTextSecondary.withOpacity(0.55),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.zero,
                              primary: false,
                              itemCount: widget.employees.length,
                              itemBuilder: (context, index) {
                                final e = widget.employees[index];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: _EmployeeTile(
                                    emp: e,
                                    sourceJobId: widget.jobId,
                                    sourceTitle: widget.title,
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ),
                // Full-size DragTarget overlay
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: widget.dragging ?? ValueNotifier(false),
                    builder: (context, isDragging, child) {
                      if (!isDragging) {
                        // When not dragging, don't build an overlay to avoid hit-test conflicts.
                        return const SizedBox.shrink();
                      }
                      return DragTarget<_DragData>(
                        onWillAcceptWithDetails: (_) => true,
                        onLeave: (_) {},
                        onAcceptWithDetails: (details) async {
                          final d = details.data;
                          // Si cae en el mismo grupo, no hacemos nada
                          if (widget.jobId == d.sourceJobId) return;

                          final String empleado = '${d.nombre} ${d.apellido}'
                              .trim();
                          final String destino = widget.title;
                          final String origen = d.sourceTitle ?? 'Sin asignar';
                          String titulo = 'Confirmar cambio';
                          String cuerpo;
                          String accion;
                          if (widget.jobId == null && d.sourceJobId != null) {
                            cuerpo = '¿Quitar a $empleado del grupo "$origen"?';
                            accion = 'Quitar';
                          } else if (widget.jobId != null &&
                              d.sourceJobId == null) {
                            cuerpo =
                                '¿Asignar a $empleado al grupo "$destino"?';
                            accion = 'Asignar';
                          } else if (widget.jobId != null &&
                              d.sourceJobId != null) {
                            cuerpo =
                                '¿Mover a $empleado del grupo "$origen" al grupo "$destino"?';
                            accion = 'Mover';
                          } else {
                            // De sin asignar a sin asignar
                            return;
                          }

                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text(titulo),
                              content: Text(cuerpo),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancelar'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(accion),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            widget.onAccept(d.empleadoId);
                          }
                        },
                        builder: (context, can, rej) {
                          final hovering = can.isNotEmpty;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            decoration: BoxDecoration(
                              color: hovering
                                  ? kPrimary.withOpacity(0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: hovering ? kPrimary : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  final Map<String, dynamic> emp;
  final int? sourceJobId;
  final String sourceTitle;
  const _EmployeeTile({
    required this.emp,
    required this.sourceJobId,
    required this.sourceTitle,
  });

  @override
  Widget build(BuildContext context) {
    final int id = (emp['empleado_id'] as num).toInt();
    final String nombre = emp['nombre']?.toString() ?? '';
    final String apellido = emp['apellido']?.toString() ?? '';
    final bool activo = (emp['activo'] == true || emp['activo'] == 1);
    final Color color = activo ? kActivo : kAusente;
    final int? minutes = emp['minutes_active'] != null ? (emp['minutes_active'] as num).toInt() : null;

    final draggingNotifier = context
        .findAncestorWidgetOfExactType<_JobColumn>()
        ?.dragging;

    return Draggable<_DragData>(
      data: _DragData(
        empleadoId: id,
        nombre: nombre,
        apellido: apellido,
        sourceJobId: sourceJobId,
        sourceTitle: sourceTitle,
      ),
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: _chip(
            nombre,
            apellido,
            color,
            dragging: true,
            feedbackMode: true,
            minutes: minutes,
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _chip(nombre, apellido, color, minutes: minutes),
      ),
      child: _chip(nombre, apellido, color, minutes: minutes),
      onDragStarted: () => draggingNotifier?.value = true,
      onDragEnd: (_) => draggingNotifier?.value = false,
    );
  }

  Widget _chip(
    String nombre,
    String apellido,
    Color color, {
    bool dragging = false,
    bool feedbackMode = false,
    int? minutes,
  }) {
    final inic =
        ((nombre.isNotEmpty ? nombre[0] : '') +
                (apellido.isNotEmpty ? apellido[0] : ''))
            .toUpperCase();
    
    final String minsStr = (minutes != null && minutes > 0) 
        ? "${minutes ~/ 60}h ${minutes % 60}m" 
        : "";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: dragging ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          if (!dragging)
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color.withOpacity(0.85),
            child: Text(
              inic,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$nombre $apellido',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600, 
                    color: kTextOnGlass,
                    fontSize: 13.5,
                  ),
                ),
                if (minsStr.isNotEmpty && !feedbackMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      'Tiempo activo: $minsStr',
                      style: TextStyle(
                        fontSize: 11,
                        color: kTextSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (minsStr.isNotEmpty && feedbackMode) ...[
            const SizedBox(width: 6),
            Text(
              minsStr,
              style: TextStyle(
                fontSize: 11,
                color: kTextSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _LegendDot(color: kActivo, label: 'Activo'),
        SizedBox(width: 10),
        _LegendDot(color: kAusente, label: 'Ausente'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: kTextOnGlass,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DragData {
  final int empleadoId;
  final String? nombre;
  final String? apellido;
  final int? sourceJobId;
  final String? sourceTitle;
  _DragData({
    required this.empleadoId,
    this.nombre,
    this.apellido,
    this.sourceJobId,
    this.sourceTitle,
  });
}
