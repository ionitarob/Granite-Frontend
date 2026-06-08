import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api_client.dart';
import '../../services/api_service.dart';
import '../../services/order_input_formatter.dart';
import '../../services/sound_player.dart';
import '../../widgets/main_sidebar.dart';

class SerialVerificationScreen extends StatefulWidget {
  final String? initialOrderNumber;

  const SerialVerificationScreen({super.key, this.initialOrderNumber});

  static const routeName = '/serials/verification';

  @override
  State<SerialVerificationScreen> createState() => _SerialVerificationScreenState();
}

class _SerialVerificationScreenState extends State<SerialVerificationScreen> {
  final TextEditingController _orderCtrl = TextEditingController();
  final TextEditingController _scanCtrl = TextEditingController();
  final FocusNode _scanFocus = FocusNode();
  final GlobalKey _scannerCardKey = GlobalKey();

  Uint8List? _fileBytes;
  String? _fileName;
  String? _selectedSheet;
  String? _selectedColumn;
  List<String> _sheetNames = [];
  List<String> _columns = [];
  List<List<String>> _previewRows = [];
  Map<String, dynamic>? _session;
  final List<Map<String, dynamic>> _pendingScans = [];
  int? _serverFirstScanLength;

  bool _boxModeEnabled = false;
  final TextEditingController _boxCtrl = TextEditingController();
  final TextEditingController _boxCapacityCtrl = TextEditingController();
  final TextEditingController _boxSearchCtrl = TextEditingController();
  int get _boxCapacity => int.tryParse(_boxCapacityCtrl.text) ?? 180;
  final List<String> _currentBoxGoodSerials = [];
  final List<String> _currentBoxBadSerials = [];
  List<Map<String, dynamic>> _pastBoxes = [];
  bool _loadingBoxes = false;
  int _boxCtrlVersion = 0;
  int _boxesCurrentPage = 1;
  final int _boxesPageSize = 5;

  bool _previewLoading = false;
  bool _starting = false;
  bool _scanning = false;
  bool _stopping = false;
  bool _exporting = false;
  bool _resuming = false;

  String _statusLabel(String raw) {
    switch (raw) {
      case 'verified':
        return 'Verificado';
      case 'pending':
        return 'Pendiente';
      case 'duplicate_upload':
        return 'Duplicado en carga';
      case 'duplicate_bad':
        return 'Duplicado malo';
      case 'duplicate_scan_session':
        return 'Duplicado por re-scan';
      case 'duplicate_scan_upload':
        return 'Duplicado por carga';
      case 'duplicate_scan_not_in_upload':
        return 'No pertenece a carga';
      case 'active':
        return 'Activa';
      case 'completed':
        return 'Completada';
      case 'verifying':
        return 'Verificando...';
      default:
        return raw;
    }
  }

  Color _statusColor(BuildContext context, String raw) {
    final lower = raw.toLowerCase();
    if (lower == 'verifying') return Colors.blueAccent;
    if (lower.contains('verified')) return Colors.greenAccent;
    if (lower.contains('pending')) return Colors.amberAccent;
    if (lower.contains('duplicate') || lower.contains('not_in_upload')) {
      return Colors.orangeAccent;
    }
    if (lower == 'completed') return Colors.lightBlueAccent;
    return Theme.of(context).colorScheme.primary;
  }

  Widget _metricPill({
    required BuildContext context,
    required String label,
    required dynamic value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 18, color: color),
              Text(
                '${value ?? 0}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color.withOpacity(0.85),
                  fontSize: 10,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _duplicateKindMessage(String duplicateKind) {
    switch (duplicateKind) {
      case 'already_scanned':
        return 'ya fue escaneado en esta sesión y no está en la carga original';
      case 'uploaded_duplicate':
        return 'ya fue verificado en esta sesión';
      case 'pending_upload':
        return 'está en el archivo cargado pero quieres marcarlo como malo directamente';
      default:
        return 'no pertenece al archivo cargado';
    }
  }

  @override
  void initState() {
    super.initState();
    _boxCtrl.addListener(_onBoxIdChanged);
    if (widget.initialOrderNumber != null) {
      _orderCtrl.text = widget.initialOrderNumber!.trim();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if ((_orderCtrl.text.trim().isNotEmpty)) {
        _resumeSession();
      }
    });
  }

  @override
  void dispose() {
    _boxCtrl.removeListener(_onBoxIdChanged);
    _orderCtrl.dispose();
    _scanCtrl.dispose();
    _boxCtrl.dispose();
    _boxCapacityCtrl.dispose();
    _boxSearchCtrl.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  ApiClient? _clientOrNull() {
    final svc = ApiService.instance;
    if (svc != null) return svc.client;
    try {
      return Provider.of<ApiService>(context, listen: false).client;
    } catch (_) {
      return null;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _promoteScannerFocus() async {
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    _scanFocus.requestFocus();
    final contextForScanner = _scannerCardKey.currentContext;
    if (contextForScanner != null) {
      await Scrollable.ensureVisible(
        contextForScanner,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        alignment: 0.05,
      );
    }
  }

  List<String> _extractColumns(excel.Sheet sheet) {
    final rows = sheet.rows;
    if (rows.isEmpty) return const [];
    final firstRow = rows.first;
    final headers = <String>[];
    for (var i = 0; i < firstRow.length; i++) {
      final raw = firstRow[i]?.value?.toString().trim() ?? '';
      headers.add(raw.isNotEmpty ? raw : 'Col ${i + 1}');
    }
    return headers;
  }

  List<List<String>> _extractPreviewRows(excel.Sheet sheet, {int limit = 5}) {
    final rows = sheet.rows;
    if (rows.length <= 1) return const [];
    final preview = <List<String>>[];
    for (final row in rows.skip(1).take(limit)) {
      preview.add(List<String>.from(row.map((cell) => cell?.value?.toString().trim() ?? '').toList()));
    }
    return preview;
  }

  void _loadWorkbookPreview(Uint8List bytes, String fileName) {
    final workbook = excel.Excel.decodeBytes(bytes);
    final sheets = workbook.sheets;
    if (sheets.isEmpty) {
      throw Exception('El archivo no contiene hojas legibles');
    }

    final sheetNames = sheets.keys.map((k) => k.toString()).toList();
    final preferredSheet = _selectedSheet != null && sheets.containsKey(_selectedSheet)
        ? _selectedSheet!
        : sheetNames.first;
    final sheet = sheets[preferredSheet];
    if (sheet == null) {
      throw Exception('No se pudo leer la hoja seleccionada');
    }

    final columns = _extractColumns(sheet);
    final previewRows = _extractPreviewRows(sheet);

    setState(() {
      _fileBytes = bytes;
      _fileName = fileName;
      _sheetNames = sheetNames;
      _selectedSheet = preferredSheet;
      _columns = columns;
      _selectedColumn = columns.isNotEmpty ? columns.first : null;
      _previewRows = previewRows;
      _session = null;
    });
  }

  Future<void> _pickFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xls'],
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null || bytes.isEmpty) {
        _showSnack('No se pudo leer el archivo seleccionado');
        return;
      }
      setState(() => _previewLoading = true);
      try {
          final fileNameSafe = file.name.isNotEmpty ? file.name : 'serials.xlsx';
          _loadWorkbookPreview(bytes, fileNameSafe);
      } finally {
        if (mounted) setState(() => _previewLoading = false);
      }
      _showSnack('Archivo cargado. Selecciona la columna de seriales.');
    } catch (e) {
      _showSnack('Error cargando archivo: $e');
    }
  }

  Future<void> _loadSheet(String sheetName) async {
    if (_fileBytes == null || _fileName == null) {
      _showSnack('No hay archivo cargado');
      return;
    }
    setState(() {
      _selectedSheet = sheetName;
      _selectedColumn = null;
      _previewLoading = true;
    });
    try {
      final workbook = excel.Excel.decodeBytes(_fileBytes!);
      final sheet = workbook.sheets[sheetName];
      if (sheet == null) throw Exception('No se pudo abrir la hoja');
      final columns = _extractColumns(sheet);
      setState(() {
        _columns = columns;
        _selectedColumn = columns.isNotEmpty ? columns.first : null;
        _previewRows = _extractPreviewRows(sheet);
      });
    } catch (e) {
      _showSnack('Error cambiando de hoja: $e');
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  Future<void> _loadActiveBoxState() async {
    final client = _clientOrNull();
    final session = _sessionMap();
    final boxId = _boxCtrl.text.trim();
    debugPrint('[BoxResumer] _loadActiveBoxState for Box: "$boxId", Session: ${session?['id']}');
    if (client == null || session == null || boxId.isEmpty) return;
    
    try {
      final res = await client.get('/serials/verification/items?session_id=${session['id']}&box_id=$boxId&page_size=1000');
      debugPrint('[BoxResumer] API Status: ${res.statusCode}, Body: ${res.body}');
      if (res.ok && res.body is Map) {
        final body = Map<String, dynamic>.from(res.body as Map);
        final list = body['items'] as List? ?? [];
        final items = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        debugPrint('[BoxResumer] Found ${items.length} items for Box "$boxId"');
        
        final goods = <String>[];
        final bads = <String>[];
        int? loadedCapacity;
        for (final item in items) {
          if (item['source_type'] != 'scan') continue; // Only count scans
          final status = item['status']?.toString() ?? '';
          final serial = item['serial']?.toString() ?? '';
          final cap = item['box_capacity'];
          if (cap != null && loadedCapacity == null) {
            loadedCapacity = int.tryParse(cap.toString());
          }
          if (serial.isNotEmpty) {
            if (status == 'verified') {
              goods.add(serial);
            } else {
              bads.add(serial);
            }
          }
        }
        setState(() {
          _currentBoxGoodSerials.clear();
          _currentBoxGoodSerials.addAll(goods);
          _currentBoxBadSerials.clear();
          _currentBoxBadSerials.addAll(bads);
          if (loadedCapacity != null) {
            _boxCapacityCtrl.text = loadedCapacity.toString();
          }
        });
        debugPrint('[BoxResumer] State updated. Good: ${goods.length}, Bad: ${bads.length}, Capacity: $loadedCapacity');
      }
    } catch (e) {
      debugPrint('[BoxResumer] Error loading box state: $e');
    }
  }

  void _onBoxIdChanged() {
    final currentVersion = ++_boxCtrlVersion;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (currentVersion == _boxCtrlVersion && mounted) {
        _loadActiveBoxState();
      }
    });
  }

  Future<void> _fetchPastBoxes() async {
    final client = _clientOrNull();
    final session = _sessionMap();
    if (client == null || session == null) return;
    setState(() => _loadingBoxes = true);
    try {
      final res = await client.get('/serials/verification/boxes?session_id=${session['id']}');
      List? boxesList;
      if (res.body is Map) {
        boxesList = (res.body as Map)['boxes'] as List?;
      } else if (res.body is List) {
        boxesList = res.body as List?;
      }
      if (res.ok && boxesList != null) {
        setState(() {
          _pastBoxes = boxesList!.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _loadingBoxes = false);
    }
  }

  Future<void> _finishBox() async {
    final boxId = _boxCtrl.text.trim();
    final total = _currentBoxGoodSerials.length + _currentBoxBadSerials.length;
    final badCount = _currentBoxBadSerials.length;
    final goodList = List<String>.from(_currentBoxGoodSerials);

    if (total == 0) {
      _showSnack('No hay seriales escaneados en esta caja.');
      return;
    }

    setState(() {
      _currentBoxGoodSerials.clear();
      _currentBoxBadSerials.clear();
      
      final match = RegExp(r'^(.*?)(\d+)$').firstMatch(boxId);
      if (match != null) {
        final prefix = match.group(1) ?? '';
        final numStr = match.group(2) ?? '1';
        final nextNum = int.parse(numStr) + 1;
        _boxCtrl.text = '$prefix$nextNum';
      } else {
        _boxCtrl.text = '$boxId 2';
      }
    });

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.inventory_2_rounded, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Text('Resumen de Caja: $boxId'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tienes $badCount duplicados/malos de un total de $total escaneados.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('Listado de Seriales Buenos:'),
              const SizedBox(height: 8),
              if (goodList.isEmpty)
                const Text('No hay seriales buenos en esta caja.')
              else
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    itemCount: goodList.length,
                    itemBuilder: (context, idx) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                      title: Text(goodList[idx]),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );

    await _fetchPastBoxes();
  }

  Future<void> _showBoxDetailsDialog(String boxId) async {
    final client = _clientOrNull();
    final session = _sessionMap();
    if (client == null || session == null) return;

    bool loading = true;
    List<Map<String, dynamic>> items = [];

    Future<void> loadItems() async {
      final res = await client.get('/serials/verification/items?session_id=${session['id']}&box_id=$boxId&page_size=1000');
      if (res.ok && res.body is Map) {
        final body = Map<String, dynamic>.from(res.body as Map);
        final list = body['items'] as List? ?? [];
        items = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      loading = false;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          if (loading) {
            loadItems().then((_) => setState(() {}));
          }
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Detalle de Caja: $boxId'),
            content: SizedBox(
              width: 600,
              height: 400,
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? const Center(child: Text('No hay seriales en esta caja'))
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, idx) {
                            final item = items[idx];
                            final status = item['status']?.toString() ?? '';
                            final isGood = status == 'verified';
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                isGood ? Icons.check_circle_outline : Icons.error_outline,
                                color: isGood ? Colors.green : Colors.red,
                              ),
                              title: Text(item['serial']?.toString() ?? ''),
                              subtitle: Text('Estado: ${_statusLabel(status)}'),
                            );
                          },
                        ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          );
        });
      },
    );
  }

  Map<String, dynamic>? _sessionMap() {
    final session = _session;
    if (session == null) return null;
    return Map<String, dynamic>.from(session);
  }

  Map<String, dynamic> _counts() {
    final session = _sessionMap();
    final counts = session?['counts'];
    if (counts is Map) return Map<String, dynamic>.from(counts);
    return const {};
  }

  Future<void> _startSession() async {
    final client = _clientOrNull();
    if (client == null) {
      _showSnack('Servicio API no disponible');
      return;
    }
    final order = _orderCtrl.text.trim();
    if (order.isEmpty) {
      _showSnack('Ingresa el número de orden');
      return;
    }
    if (_fileBytes == null || _fileName == null) {
      _showSnack('Primero carga el archivo Excel');
      return;
    }
    if (_selectedColumn == null || _selectedColumn!.trim().isEmpty) {
      _showSnack('Selecciona la columna de serials');
      return;
    }

    setState(() => _starting = true);
    try {
      final res = await client.postMultipart(
        '/serials/verification/start',
        fields: {
          'order_nbr': order,
          'serial_column': _selectedColumn!,
          if (_selectedSheet != null) 'sheet_name': _selectedSheet!,
        },
        fileFieldName: 'file',
        fileName: _fileName!,
        fileBytes: _fileBytes,
      );
      if (!mounted) return;
      if (!res.ok) {
        var msg = 'No se pudo iniciar (${res.statusCode})';
        try {
          if (res.body != null) {
            if (res.body is Map && (res.body as Map).containsKey('error')) {
              msg = '${(res.body as Map)['error'] ?? msg}';
            } else if (res.body is Map && (res.body as Map).containsKey('details')) {
              msg = '${(res.body as Map)['details'] ?? msg}';
            } else if (res.body is String) {
              msg = res.body as String;
            }
          }
        } catch (_) {}
        _showSnack(msg);
        return;
      }
      final body = Map<String, dynamic>.from(res.body as Map);
      final session = body['session'];
      if (session is Map) {
        setState(() => _session = Map<String, dynamic>.from(session));
      }
      await _fetchFirstScanLength();
      final dup = body['duplicate_upload_rows'] ?? 0;
      final imported = body['imported_rows'] ?? 0;
      _showSnack('Verificación iniciada. Cargados: $imported, duplicados en archivo: $dup');
      await _promoteScannerFocus();
      await _fetchPastBoxes();
      await _loadActiveBoxState();
    } catch (e) {
      _showSnack('Error iniciando verificación: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _resumeSession() async {
    final client = _clientOrNull();
    if (client == null) return;
    final order = _orderCtrl.text.trim();
    if (order.isEmpty) return;

    setState(() => _resuming = true);
    try {
      final res = await client.post(
        '/serials/verification/resume',
        jsonBody: {'order_nbr': order},
      );
      if (!mounted) return;
      if (!res.ok || res.body is! Map) return;
      final body = Map<String, dynamic>.from(res.body as Map);
      final session = body['session'];
      if (session is Map) {
        setState(() => _session = Map<String, dynamic>.from(session));
        _showSnack('Sesión reabierta');
        await _fetchFirstScanLength();
        await _promoteScannerFocus();
        await _fetchPastBoxes();
        await _loadActiveBoxState();
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _resuming = false);
    }
  }

  Future<bool> _confirmDuplicate(String serial, String duplicateKind) async {
    if (duplicateKind == 'already_scanned') {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
              SizedBox(width: 8),
              Text('Serial ya escaneado'),
            ],
          ),
          content: Text('El serial "$serial" ya fue escaneado y verificado en esta sesión.\n\nNo pertenece a un nuevo registro del archivo original.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return false;
    }

    final kindMessage = _duplicateKindMessage(duplicateKind);
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.warning_rounded, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('Marcar como Duplicado Malo'),
              ],
            ),
            content: Text('El serial "$serial" $kindMessage.\n\n¿Quieres marcarlo como duplicado malo (incorrecto) en la base de datos?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                child: const Text('Sí, marcar malo'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _syncSessionFromResponse(Map<String, dynamic> body) {
    final session = body['session'];
    if (session is Map) {
      setState(() => _session = Map<String, dynamic>.from(session));
    }
  }

  int? _getReferenceLength() {
    return _serverFirstScanLength;
  }

  Future<void> _fetchFirstScanLength() async {
    final client = _clientOrNull();
    final session = _sessionMap();
    if (client == null || session == null) return;
    try {
      final res = await client.get('/serials/verification/items?session_id=${session['id']}&page_size=1000');
      if (res.ok && res.body is Map) {
        final body = Map<String, dynamic>.from(res.body as Map);
        final list = body['items'] as List? ?? [];
        final items = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        
        final scans = items.where((i) => i['source_type'] == 'scan').toList();
        if (scans.isNotEmpty) {
          scans.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
          final firstSerial = scans.first['serial']?.toString() ?? '';
          if (firstSerial.isNotEmpty) {
            setState(() {
              _serverFirstScanLength = firstSerial.length;
            });
            debugPrint('[_fetchFirstScanLength] Found first scan: $firstSerial (length: ${firstSerial.length})');
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[_fetchFirstScanLength] Error fetching items: $e');
    }
    setState(() {
      _serverFirstScanLength = null;
    });
  }

  Future<void> _scanSerial() async {
    final client = _clientOrNull();
    final session = _sessionMap();
    final serial = _scanCtrl.text.trim();
    if (client == null) {
      _showSnack('Servicio API no disponible');
      return;
    }
    if (session == null) {
      _showSnack('Primero inicia o reanuda una sesión');
      return;
    }
    if (_boxModeEnabled) {
      if (_boxCtrl.text.trim().isEmpty) {
        _showSnack('Por favor ingresa un identificador de caja');
        return;
      }
      if (_boxCapacityCtrl.text.trim().isEmpty) {
        _showSnack('Por favor ingresa la capacidad de la caja');
        return;
      }
    }
    if (serial.isEmpty) return;

    final refLen = _getReferenceLength();
    if (refLen != null && serial.length != refLen) {
      SoundPlayer.playError();
      _showSnack('Serial ignorado: longitud incorrecta (${serial.length} vs esperado $refLen)');
      _scanCtrl.clear();
      _scanFocus.requestFocus();
      return;
    }

    if (_serverFirstScanLength == null) {
      setState(() {
        _serverFirstScanLength = serial.length;
      });
    }


    if (_boxModeEnabled) {
      if (_currentBoxGoodSerials.contains(serial) || _currentBoxBadSerials.contains(serial)) {
        SoundPlayer.playError();
        _showSnack('Serial "$serial" ya escaneado en esta caja. Ignorado.');
        _scanCtrl.clear();
        _scanFocus.requestFocus();
        return;
      }
    }

    // Instant reset & refocus (Optimistic UI)
    _scanCtrl.clear();
    _scanFocus.requestFocus();

    final pendingItem = {
      'serial': serial,
      'source_type': 'scan',
      'status': 'verifying',
      'created_at': DateTime.now().toIso8601String(),
    };

    setState(() {
      _pendingScans.insert(0, pendingItem);
    });

    try {
      final res = await client.post(
        '/serials/verification/scan',
        jsonBody: {
          'session_id': session['id'],
          'serial': serial,
          'confirm_duplicate': false,
          if (_boxModeEnabled) ...{
            'box_id': _boxCtrl.text.trim(),
            'box_capacity': _boxCapacity,
          },
        },
      );

      if (!mounted) return;

      if (res.ok && res.body is Map) {
        final body = Map<String, dynamic>.from(res.body as Map);
        _syncSessionFromResponse(body);
        final resName = body['result']?.toString() ?? 'verified';
        
        if (resName == 'ignored_duplicate') {
          SoundPlayer.playError();
          _showSnack('Serial "$serial" ya fue escaneado en esta sesión. Ignorado.');
          return;
        }
        
        if (_boxModeEnabled) {
          if (resName == 'verified') {
            SoundPlayer.playSuccess();
            _showSnack('Serial verificado en caja');
            setState(() {
              _currentBoxGoodSerials.add(serial);
            });
          } else {
            SoundPlayer.playError();
            _showSnack('Serial incorrecto/duplicado registrado en caja');
            setState(() {
              _currentBoxBadSerials.add(serial);
            });
          }
          
          if (_currentBoxGoodSerials.length + _currentBoxBadSerials.length >= _boxCapacity) {
            await _finishBox();
          }
        } else {
          if (resName == 'verified') {
            SoundPlayer.playSuccess();
            _showSnack('Serial verificado');
          } else if (resName == 'duplicate_bad') {
            SoundPlayer.playError();
            await showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 28),
                    SizedBox(width: 8),
                    Text('Duplicado Malo Detectado'),
                  ],
                ),
                content: Text(
                  'El serial "$serial" ya existe en el archivo original cargado.\n\n'
                  'Se ha registrado automáticamente en la base de datos como un DUPLICADO MALO.\n\n'
                  'Por favor, verifique el serial físico antes de continuar.'
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                    child: const Text('Entendido'),
                  ),
                ],
              ),
            );
          } else {
            SoundPlayer.playError();
            _showSnack('Serial marcado como duplicado malo');
          }
        }
      } else if (res.statusCode == 409 && res.body is Map) {
        final body = Map<String, dynamic>.from(res.body as Map);
        final duplicateKind = body['duplicate_kind']?.toString() ?? 'already_scanned';
        SoundPlayer.playError();
        if (_boxModeEnabled) {
          _showSnack('Serial incorrecto/duplicado registrado en caja');
          setState(() {
            _currentBoxBadSerials.add(serial);
          });
          if (_currentBoxGoodSerials.length + _currentBoxBadSerials.length >= _boxCapacity) {
            await _finishBox();
          }
        } else {
          await _confirmDuplicate(serial, duplicateKind);
        }
      } else {
        SoundPlayer.playError();
        final errorMsg = res.body is Map ? (res.body['error'] ?? res.error) : res.error;
        if (_boxModeEnabled) {
          _showSnack('Error escaneando serial: ${errorMsg ?? "registrado como malo en caja"}');
          setState(() {
            _currentBoxBadSerials.add(serial);
          });
          if (_currentBoxGoodSerials.length + _currentBoxBadSerials.length >= _boxCapacity) {
            await _finishBox();
          }
        } else {
          _showSnack(errorMsg ?? 'No se pudo escanear (${res.statusCode})');
        }
      }
    } catch (e) {
      SoundPlayer.playError();
      if (_boxModeEnabled) {
        _showSnack('Error de conexión: registrado como malo en caja');
        setState(() {
          _currentBoxBadSerials.add(serial);
        });
        if (_currentBoxGoodSerials.length + _currentBoxBadSerials.length >= _boxCapacity) {
          await _finishBox();
        }
      } else {
        _showSnack('Error escaneando: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _pendingScans.remove(pendingItem);
        });
        _scanFocus.requestFocus();
      }
    }
  }

  Future<void> _stopSession() async {
    final client = _clientOrNull();
    final session = _sessionMap();
    if (client == null || session == null) return;

    setState(() => _stopping = true);
    try {
      final res = await client.post(
        '/serials/verification/stop',
        jsonBody: {'session_id': session['id']},
      );
      if (!mounted) return;
      if (res.ok && res.body is Map) {
        _syncSessionFromResponse(Map<String, dynamic>.from(res.body as Map));
        _showSnack('Sesión cerrada');
      } else {
        _showSnack('No se pudo cerrar la sesión');
      }
    } catch (e) {
      _showSnack('Error cerrando sesión: $e');
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  Future<void> _exportReport() async {
    final client = _clientOrNull();
    final session = _sessionMap();
    if (client == null || session == null) {
      _showSnack('No hay sesión activa para exportar');
      return;
    }

    setState(() => _exporting = true);
    try {
      final res = await client.getBytes('/serials/verification/export?session_id=${session['id']}');
      if (!mounted) return;
      if (!res.ok || res.body is! List<int>) {
        _showSnack('No se pudo exportar (${res.statusCode})');
        return;
      }
      final suggested = 'verification_${_orderCtrl.text.trim().replaceAll('-', '')}.xlsx';
      final path = await FilePicker.platform.saveFile(
        fileName: suggested,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        dialogTitle: 'Guardar reporte de verificación',
      );
      if (path == null) {
        _showSnack('Exportación cancelada');
        return;
      }
      await File(path).writeAsBytes(res.body as List<int>, flush: true);
      _showSnack('Reporte guardado en $path');
    } catch (e) {
      _showSnack('Error exportando: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<Map<String, dynamic>?> _fetchMovementPage(int sessionId, int page, int pageSize) async {
    final client = _clientOrNull();
    if (client == null) return null;
    final res = await client.get('/serials/verification/items?session_id=$sessionId&page=$page&page_size=$pageSize');
    if (!res.ok || res.body is! Map) return null;
    return Map<String, dynamic>.from(res.body as Map);
  }

  Future<void> _showMovementsDialog(int sessionId, {int initialPage = 1, int pageSize = 50}) async {
    final client = _clientOrNull();
    if (client == null) return;
    int page = initialPage;
    int total = 0;
    List<Map<String, dynamic>> pageItems = [];
    bool loading = true;

    Future<void> loadPage() async {
      loading = true;
      final result = await _fetchMovementPage(sessionId, page, pageSize);
      if (result != null) {
        total = (result['total'] ?? 0) as int;
        final itemsRaw = result['items'] as List? ?? [];
        pageItems = itemsRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        pageItems = [];
        total = 0;
      }
      loading = false;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          if (loading) {
            loadPage().then((_) => setState(() {}));
          }
          final totalPages = (total / pageSize).ceil();
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Movimientos - Página $page/${totalPages == 0 ? 1 : totalPages}'),
            content: SizedBox(
              width: 760,
              height: 480,
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            itemCount: pageItems.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, idx) {
                               final item = pageItems[idx];
                               return ListTile(
                                 dense: true,
                                 leading: Icon(item['source_type'] == 'scan' ? Icons.qr_code_scanner : Icons.upload_file),
                                 title: Text(item['serial']?.toString() ?? ''),
                                 subtitle: Text('${item['source_type'] ?? ''} · ${_statusLabel(item['status']?.toString() ?? '')}'),
                               );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total: $total'),
                            Row(
                              children: [
                                OutlinedButton(
                                  onPressed: page > 1
                                      ? () async {
                                          page -= 1;
                                          setState(() => loading = true);
                                          await loadPage();
                                          setState(() {});
                                        }
                                      : null,
                                  child: const Text('Anterior'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: page < totalPages
                                      ? () async {
                                          page += 1;
                                          setState(() => loading = true);
                                          await loadPage();
                                          setState(() {});
                                        }
                                      : null,
                                  child: const Text('Siguiente'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    
    final counts = _counts();
    final session = _sessionMap();
    final items = (session?['recent_items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final displayItems = [
      ..._pendingScans,
      ...items.where((i) => !_pendingScans.any((p) => p['serial'] == i['serial'])),
    ];

    final cardBgColor = isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02);
    final borderColor = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isMobile ? 'VERIFICAR' : 'VERIFICACIÓN DE SERIALS',
          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        actions: [
          TextButton.icon(
            onPressed: _resuming ? null : _resumeSession,
            icon: _resuming
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow_rounded),
            label: Text(isMobile ? 'Reanudar' : 'Reanudar Sesión'),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: (_exporting || session == null) ? null : _exportReport,
            icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_download_outlined),
            label: Text(isMobile ? 'Reporte' : 'Exportar Reporte'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.all(isMobile ? 12 : 24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Premium gradient banner header
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isMobile ? 16 : 24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark 
                          ? [theme.colorScheme.primary.withOpacity(0.24), theme.colorScheme.secondary.withOpacity(0.08)]
                          : [theme.colorScheme.primary.withOpacity(0.12), theme.colorScheme.secondary.withOpacity(0.04)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        )
                      ]
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.fact_check_rounded, color: theme.colorScheme.primary, size: isMobile ? 24 : 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Verificación de seriales',
                                style: (isMobile 
                                  ? theme.textTheme.titleMedium 
                                  : theme.textTheme.headlineSmall)?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.2,
                                  ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Carga un archivo Excel de tu orden, elige la columna de seriales y utiliza el escáner maestro para validar, marcar duplicados malos e inventariar con seguridad.',
                          style: (isMobile ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)?.copyWith(
                            height: 1.5,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 1040;
                      
                      if (session == null) {
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(color: borderColor),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(isMobile ? 16 : 24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.settings_system_daydream, size: 24, color: Colors.blueAccent),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'Configuración y Carga',
                                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    TextField(
                                      controller: _orderCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'Número de orden',
                                        prefixIcon: const Icon(Icons.numbers_rounded),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      inputFormatters: [OrderInputFormatter()],
                                      onSubmitted: (_) {
                                        _resumeSession();
                                      },
                                    ),
                                    const SizedBox(height: 20),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      children: [
                                        FilledButton.icon(
                                          onPressed: _previewLoading ? null : _pickFile,
                                          icon: _previewLoading
                                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                              : const Icon(Icons.upload_file_rounded),
                                          label: const Text('Cargar Excel'),
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _starting ? null : _startSession,
                                          icon: _starting
                                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                              : const Icon(Icons.playlist_add_check_rounded),
                                          label: const Text('Iniciar verificación'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('Nombre de archivo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      subtitle: Text(_fileName ?? 'Ninguno cargado', style: const TextStyle(fontSize: 13)),
                                      leading: const Icon(Icons.description_rounded, color: Colors.blueAccent, size: 28),
                                    ),
                                    if (_sheetNames.isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      DropdownButtonFormField<String>(
                                        value: _selectedSheet,
                                        decoration: InputDecoration(
                                          labelText: 'Hoja seleccionada',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        items: _sheetNames
                                            .map((sheet) => DropdownMenuItem(value: sheet, child: Text(sheet)))
                                            .toList(),
                                        onChanged: (value) {
                                          if (value != null) _loadSheet(value);
                                        },
                                      ),
                                    ],
                                    if (_columns.isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      DropdownButtonFormField<String>(
                                        value: _selectedColumn,
                                        decoration: InputDecoration(
                                          labelText: 'Columna de seriales',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        items: _columns
                                            .map((col) => DropdownMenuItem(value: col, child: Text(col)))
                                            .toList(),
                                        onChanged: (value) => setState(() => _selectedColumn = value),
                                      ),
                                    ],
                                    if (_previewRows.isNotEmpty) ...[
                                      const SizedBox(height: 24),
                                      Text('Vista previa de carga', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 12),
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: borderColor),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: DataTable(
                                            headingRowColor: WidgetStateProperty.all(cardBgColor),
                                            columns: List.generate(
                                              _columns.length,
                                              (index) => DataColumn(label: Text(_columns[index], style: const TextStyle(fontWeight: FontWeight.bold))),
                                            ),
                                            rows: _previewRows
                                                .map(
                                                  (row) => DataRow(
                                                    cells: List.generate(
                                                      _columns.length,
                                                      (index) => DataCell(Text(index < row.length ? row[index] : '')),
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      } else {
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 860),
                            child: Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.24)),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(isMobile ? 12 : 24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    isMobile
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.qr_code_scanner_rounded, size: 28, color: theme.colorScheme.primary),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  'Escáner Maestro',
                                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.primary.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              'Orden: ${session['order_nbr']}',
                                              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.qr_code_scanner_rounded, size: 28, color: theme.colorScheme.primary),
                                              const SizedBox(width: 12),
                                              Text('Escáner Maestro', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 18)),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.primary.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              'Orden: ${session['order_nbr']}',
                                              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                                            ),
                                          ),
                                        ],
                                      ),
                                    const SizedBox(height: 20),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withOpacity(0.04),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(Icons.inventory_2_rounded, color: theme.colorScheme.primary, size: 20),
                                                  const SizedBox(width: 8),
                                                  const Text(
                                                    'Modo Cajas',
                                                    style: TextStyle(fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                              Switch.adaptive(
                                                value: _boxModeEnabled,
                                                onChanged: (val) {
                                                  setState(() => _boxModeEnabled = val);
                                                },
                                              ),
                                            ],
                                          ),
                                          if (_boxModeEnabled) ...[
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                Expanded(
                                                  flex: 3,
                                                  child: TextField(
                                                    controller: _boxCtrl,
                                                    decoration: InputDecoration(
                                                      labelText: 'Identificador de Caja',
                                                      prefixIcon: const Icon(Icons.label_outline_rounded),
                                                      isDense: true,
                                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  flex: 2,
                                                  child: TextField(
                                                    controller: _boxCapacityCtrl,
                                                    keyboardType: TextInputType.number,
                                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                                    decoration: InputDecoration(
                                                      labelText: 'Capacidad',
                                                      prefixIcon: const Icon(Icons.tag_rounded),
                                                      isDense: true,
                                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                    ),
                                                    onChanged: (_) {
                                                      setState(() {});
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Builder(
                                              builder: (context) {
                                                final currentTotal = _currentBoxGoodSerials.length + _currentBoxBadSerials.length;
                                                final percent = currentTotal / _boxCapacity;
                                                return Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Text(
                                                          'Progreso Caja: $currentTotal / $_boxCapacity',
                                                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                                                        ),
                                                        Text(
                                                          'Correctos: ${_currentBoxGoodSerials.length} · Malos: ${_currentBoxBadSerials.length}',
                                                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 6),
                                                    ClipRRect(
                                                      borderRadius: BorderRadius.circular(4),
                                                      child: LinearProgressIndicator(
                                                        value: percent.clamp(0.0, 1.0),
                                                        minHeight: 8,
                                                        backgroundColor: theme.dividerColor.withOpacity(0.5),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Align(
                                                      alignment: Alignment.centerRight,
                                                      child: TextButton.icon(
                                                        onPressed: currentTotal > 0 ? _finishBox : null,
                                                        icon: const Icon(Icons.check_box_outlined, size: 18),
                                                        label: const Text('Cerrar Caja Manual'),
                                                        style: TextButton.styleFrom(
                                                          visualDensity: VisualDensity.compact,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    TextField(
                                      controller: _scanCtrl,
                                      focusNode: _scanFocus,
                                      decoration: InputDecoration(
                                        labelText: 'Escanear / Ingresar Serial',
                                        prefixIcon: const Icon(Icons.barcode_reader),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                                        ),
                                      ),
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) {
                                        if (!_scanning) {
                                          _scanSerial();
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: _scanning ? null : _scanSerial,
                                            icon: _scanning
                                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                                : const Icon(Icons.check_circle_outline_rounded),
                                            label: Text(isMobile ? 'Validar' : 'Validar serial'),
                                            style: FilledButton.styleFrom(
                                              padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 16),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        OutlinedButton.icon(
                                          onPressed: _stopping ? null : _stopSession,
                                          icon: _stopping
                                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                              : const Icon(Icons.stop_circle_outlined),
                                          label: const Text('Finalizar'),
                                          style: OutlinedButton.styleFrom(
                                            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: isMobile ? 12 : 16),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            foregroundColor: Colors.redAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    Text('Estadísticas y Métricas', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 12),
                                    GridView.count(
                                      crossAxisCount: isNarrow ? 2 : 3,
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: isMobile ? 2.1 : (isNarrow ? 2.5 : 3.0),
                                      children: [
                                        _metricPill(
                                          context: context,
                                          label: 'Cargados',
                                          value: counts['uploaded_rows'],
                                          icon: Icons.upload_file_rounded,
                                          color: Colors.blue,
                                        ),
                                        _metricPill(
                                          context: context,
                                          label: 'Pendientes',
                                          value: counts['pending_rows'],
                                          icon: Icons.pending_actions_rounded,
                                          color: Colors.amber,
                                        ),
                                        _metricPill(
                                          context: context,
                                          label: 'Válidos',
                                          value: counts['verified_rows'],
                                          icon: Icons.verified_rounded,
                                          color: Colors.green,
                                        ),
                                        _metricPill(
                                          context: context,
                                          label: 'Dup. archivo',
                                          value: counts['duplicate_upload_rows'],
                                          icon: Icons.content_copy_rounded,
                                          color: Colors.orange,
                                        ),
                                        _metricPill(
                                          context: context,
                                          label: 'Dup. malos',
                                          value: counts['duplicate_bad_rows'],
                                          icon: Icons.warning_rounded,
                                          color: Colors.red,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Últimos movimientos', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            final sid = session['id'] as int;
                                            _showMovementsDialog(sid);
                                          },
                                          icon: const Icon(Icons.list, size: 16),
                                          label: const Text('Ver todos'),
                                          style: OutlinedButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    if (displayItems.isEmpty)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(20),
                                        alignment: Alignment.center,
                                        child: Text('Todavía no hay movimientos en esta sesión.', style: theme.textTheme.bodySmall),
                                      )
                                    else
                                      ListView.separated(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: displayItems.length > 5 ? 5 : displayItems.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                                        itemBuilder: (_, index) {
                                          final item = displayItems[index];
                                          final status = item['status']?.toString() ?? '';
                                          final color = _statusColor(context, status);
                                          return Container(
                                            decoration: BoxDecoration(
                                              color: color.withOpacity(0.04),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: color.withOpacity(0.15)),
                                            ),
                                            child: ListTile(
                                              dense: true,
                                              leading: Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: color.withOpacity(0.12),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  item['source_type'] == 'scan' ? Icons.qr_code_scanner_rounded : Icons.file_present_rounded,
                                                  color: color,
                                                  size: 16,
                                                ),
                                              ),
                                              title: Text(
                                                item['serial']?.toString() ?? '',
                                                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                              ),
                                              subtitle: Text(
                                                '${item['source_type'] == 'scan' ? 'Escaneado' : 'Archivo'} · ${_statusLabel(status)}'
                                                '${(item['duplicate_reason']?.toString().isNotEmpty == true) ? ' · ${item['duplicate_reason']}' : ''}',
                                                style: TextStyle(color: color, fontSize: 11),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    if (_boxModeEnabled || _pastBoxes.isNotEmpty) ...[
                                      const SizedBox(height: 24),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Historial de Cajas', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                                          if (_loadingBoxes)
                                            const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: _boxSearchCtrl,
                                        decoration: InputDecoration(
                                          labelText: 'Buscar caja...',
                                          prefixIcon: const Icon(Icons.search_rounded),
                                          isDense: true,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onChanged: (_) {
                                          setState(() {
                                            _boxesCurrentPage = 1;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      Builder(
                                        builder: (context) {
                                          final query = _boxSearchCtrl.text.trim().toLowerCase();
                                          final filteredBoxes = _pastBoxes.where((box) {
                                            final bid = box['box_id']?.toString().toLowerCase() ?? '';
                                            return bid.contains(query);
                                          }).toList();

                                          if (filteredBoxes.isEmpty) {
                                            return Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(20),
                                              alignment: Alignment.center,
                                              child: Text(
                                                _pastBoxes.isEmpty 
                                                    ? 'No hay cajas cerradas en esta sesión.' 
                                                    : 'No se encontraron cajas con ese nombre.', 
                                                style: theme.textTheme.bodySmall,
                                              ),
                                            );
                                          }

                                          final totalPages = (filteredBoxes.length / _boxesPageSize).ceil();
                                          if (_boxesCurrentPage > totalPages) {
                                            _boxesCurrentPage = totalPages;
                                          }
                                          if (_boxesCurrentPage < 1) {
                                            _boxesCurrentPage = 1;
                                          }

                                          final displayBoxes = filteredBoxes
                                              .skip((_boxesCurrentPage - 1) * _boxesPageSize)
                                              .take(_boxesPageSize)
                                              .toList();

                                        return Column(
                                          children: [
                                            ListView.separated(
                                              shrinkWrap: true,
                                              physics: const NeverScrollableScrollPhysics(),
                                              itemCount: displayBoxes.length,
                                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                                              itemBuilder: (_, index) {
                                                final box = displayBoxes[index];
                                                final boxId = box['box_id']?.toString() ?? '';
                                                final total = box['total_items'] ?? box['total'] ?? 0;
                                                final good = box['good_items'] ?? box['good'] ?? 0;
                                                final bad = box['bad_items'] ?? box['bad'] ?? 0;
                                                return Container(
                                                  decoration: BoxDecoration(
                                                    color: theme.colorScheme.primary.withOpacity(0.03),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
                                                  ),
                                                  child: ListTile(
                                                    dense: true,
                                                    leading: Container(
                                                      padding: const EdgeInsets.all(8),
                                                      decoration: BoxDecoration(
                                                        color: theme.colorScheme.primary.withOpacity(0.1),
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Icon(
                                                        Icons.inventory_2_rounded,
                                                        color: theme.colorScheme.primary,
                                                        size: 16,
                                                      ),
                                                    ),
                                                    title: Text(
                                                      boxId,
                                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                                    ),
                                                    subtitle: Text(
                                                      'Total: $total · Buenos: $good · Malos: $bad',
                                                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                                                    ),
                                                    trailing: const Icon(Icons.chevron_right_rounded),
                                                    onTap: () => _showBoxDetailsDialog(boxId),
                                                  ),
                                                );
                                              },
                                            ),
                                            if (totalPages > 1) ...[
                                              const SizedBox(height: 12),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.chevron_left_rounded),
                                                    onPressed: _boxesCurrentPage > 1
                                                        ? () {
                                                            setState(() {
                                                              _boxesCurrentPage--;
                                                            });
                                                          }
                                                        : null,
                                                  ),
                                                  Text(
                                                    'Página $_boxesCurrentPage de $totalPages',
                                                    style: theme.textTheme.bodyMedium,
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.chevron_right_rounded),
                                                    onPressed: _boxesCurrentPage < totalPages
                                                        ? () {
                                                            setState(() {
                                                              _boxesCurrentPage++;
                                                            });
                                                          }
                                                        : null,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerLeft,
              child: EdgeNavHandle(),
            ),
          ),
        ],
      ),
    );
  }
}