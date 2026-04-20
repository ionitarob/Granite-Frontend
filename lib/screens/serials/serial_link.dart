import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api_client.dart';
import '../../services/api_service.dart';
import '../../services/order_input_formatter.dart';
import '../../services/orderops_service.dart';
import '../../services/sound_player.dart';
import '../../widgets/main_sidebar.dart';
import '../../widgets/pdf_preview_dialog.dart';
import '../../utils/formatters.dart';

enum _SerialPanel { assign, match, upload, recent }

class SerialLinkScreen extends StatefulWidget {
  final bool isEmbedded;
  final bool matchOnly;
  final int initialTabIndex;
  final String? initialOrderNumber;
  final int? orderId;

  const SerialLinkScreen({
    super.key,
    this.isEmbedded = false,
    this.matchOnly = false,
    this.initialTabIndex = 0,
    this.initialOrderNumber,
    this.orderId,
  });

  @override
  State<SerialLinkScreen> createState() => _SerialLinkScreenState();
}

class _SerialLinkScreenState extends State<SerialLinkScreen>
    with SingleTickerProviderStateMixin {
  static const String _basePath = '/serials';
  static final RegExp _orderFormatRegex = RegExp(
    r'^[A-Z0-9]{2}-[A-Z0-9]{5}-[A-Z0-9]{2}$',
  );

  late final TabController _tabs;
  late final List<_SerialPanel> _activePanels;
  OverlayEntry? _edgeOverlay;

  final TextEditingController _serialCtrl = TextEditingController();
  final FocusNode _serialFocus = FocusNode();
  final TextEditingController _orderCtrl = TextEditingController();
  final FocusNode _orderFocus = FocusNode();
  final TextEditingController _quickScanCtrl = TextEditingController();
  final FocusNode _quickScanFocus = FocusNode();

  String? _nextInventory;
  String? _lastInventory;
  String? _assignError;
  bool _assigning = false;

  bool _loadingRecent = false;
  List<Map<String, String?>> _recent = [];

  Map<String, dynamic>? _orderInfo;
  List<Map<String, String>> _orderSerials = [];
  final List<_MatchRow> _matchRows = [];
  final Set<int> _duplicateRows = <int>{};
  bool _loadingOrder = false;
  bool _savingRows = false;
  int _rowEpoch = 0;

  bool _uploading = false;
  bool _resetting = false;
  bool _exporting = false;
  bool _exportingExcel = false;
  bool _templatesLoading = false;
  bool _templateUploading = false;
  List<Map<String, dynamic>> _templates = [];

  // Sequence Generation
  List<String> _sequenceQueue = [];
  String? _lastPromptedOrder;

  @override
  void initState() {
    super.initState();

    _activePanels = widget.matchOnly
        ? const [_SerialPanel.match]
        : _SerialPanel.values;

    final safeInitialIndex = widget.matchOnly
        ? 0
        : widget.initialTabIndex.clamp(0, _activePanels.length - 1);

    _tabs = TabController(
      length: _activePanels.length,
      vsync: this,
      initialIndex: safeInitialIndex,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshRecent();
      _fetchNextInventory();

      final initialOrder = widget.initialOrderNumber?.trim() ?? '';
      if (initialOrder.isNotEmpty) {
        _orderCtrl.text = _normalizeOrder(initialOrder);
        _fetchOrder();
      }

      if (widget.matchOnly) {
        _orderFocus.requestFocus();
      } else {
        _serialFocus.requestFocus();
      }
    });
    _serialFocus.addListener(() {
      if (_serialFocus.hasFocus) _fetchNextInventory();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isEmbedded || widget.matchOnly) return;
      if (!mounted) return;
      final routeName = ModalRoute.of(context)?.settings.name;
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
                  user: Provider.of<ApiService>(ctx, listen: false).currentUser,
                  width: 32,
                  currentRoute: routeName,
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

  Future<void> _handleQuickScan(String value) async {
    final serial = value.trim();
    if (serial.isEmpty) return;
    _quickScanCtrl.clear();

    // 1. Check for verification (already in order)
    final isDouble = _isManualDouble;
    final existingMatch = _orderSerials.any((s) => s['serial'] == serial);

    if (existingMatch) {
      SoundPlayer.playSuccess();
      _showSnack('VERIFICADO ✅: $serial ya está en la orden');
      _quickScanFocus.requestFocus();
      return;
    }

    // 2. Find first empty slot for rapid matching
    int targetIndex = -1;
    for (int i = 0; i < _matchRows.length; i++) {
      if (_matchRows[i].serial.text.trim().isEmpty) {
        targetIndex = i;
        break;
      }
    }

    if (targetIndex != -1) {
      final row = _matchRows[targetIndex];
      row.serial.text = serial;
      if (isDouble) {
        // Just focus the inventory field of that row
        row.inventoryFocus.requestFocus();
        final currentSaved = _orderSerials.length;
        _showSnack(
          'Serial capturado. Escanea Inventario/IMEI para la Unidad ${currentSaved + targetIndex + 1}',
        );
      } else {
        // Auto-save
        final ok = await _saveRow(targetIndex);
        if (ok) {
          // Success sound is already played in _saveRow
          _quickScanFocus.requestFocus();
        } else {
          // Error sound is already played in _saveRow
          // If save failed, we keep the serial in the row for manual fix
        }
      }
    } else {
      // No slots available
      SoundPlayer.playError();
      _showSnack(
        'ERROR: Todas las unidades están llenas. No se puede añadir "$serial".',
      );
      _quickScanFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _edgeOverlay?.remove();
    _edgeOverlay = null;
    _tabs.dispose();
    _serialCtrl.dispose();
    _serialFocus.dispose();
    _orderCtrl.dispose();
    _orderFocus.dispose();
    _quickScanCtrl.dispose();
    _quickScanFocus.dispose();
    for (final row in _matchRows) {
      row.dispose();
    }
    super.dispose();
  }

  ApiClient? _clientOrNull() {
    final svc = ApiService.instance;
    if (svc != null) return svc.client;
    if (!mounted) return null;
    try {
      return Provider.of<ApiService>(context, listen: false).client;
    } catch (_) {
      return null;
    }
  }

  Map<String, String>? _orderInfoAuthHeaders(ApiClient? client) {
    final token = client?.accessToken;
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token'};
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _normalizeOrder(String raw) =>
      OrderInputFormatter.normalize(raw.trim());

  bool _isValidOrder(String value) => _orderFormatRegex.hasMatch(value);

  int? _tryParseOrderId(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  int? _resolveOrderIdForArchivos() {
    final direct = widget.orderId;
    if (direct != null && direct > 0) return direct;
    final order = _orderInfo;
    if (order == null) return null;
    return _tryParseOrderId(order['idnbr']) ??
        _tryParseOrderId(order['order_id']) ??
        _tryParseOrderId(order['source_idnbr']) ??
        _tryParseOrderId(order['id']);
  }

  Future<void> _autoAttachExcelToArchivos(String numOrden) async {
    final orderId = _resolveOrderIdForArchivos();
    if (orderId == null) {
      _showSnack(
        'Match completado, pero no hay id de orden para adjuntar en Archivos',
      );
      return;
    }
    final client = _clientOrNull();
    if (client == null) {
      _showSnack(
        'Match completado, pero no hay servicio API para adjuntar Excel',
      );
      return;
    }

    setState(() => _exportingExcel = true);
    try {
      final res = await client.getBytes(
        '$_basePath/matches/export?num_orden=${Uri.encodeQueryComponent(numOrden)}',
      );
      if (!mounted) return;
      if (!res.ok || res.body is! List<int>) {
        _showSnack(
          'Match completado, pero no se pudo generar Excel (${res.statusCode})',
        );
        return;
      }

      final headers = res.headers ?? const {};
      final defaultName = 'serial_matches_${numOrden.replaceAll('-', '')}.xlsx';
      final fileName = _filenameFromHeaders(headers) ?? defaultName;

      final uploaded = await OrderOpsService(
        client,
      ).uploadPhoto(orderId, fileName, res.body as List<int>);
      if (!mounted) return;
      _showSnack(
        uploaded
            ? 'Excel de match adjuntado automaticamente en Archivos'
            : 'Match completado, pero no se pudo adjuntar el Excel en Archivos',
      );
    } catch (e) {
      _showSnack('Match completado, pero fallo adjuntar Excel: $e');
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  Future<void> _completeOrderAndAttach(String numOrden) async {
    final removed = _resizeMatchRows(0);
    _orderCtrl.clear();
    setState(() {
      _orderInfo = null;
      _orderSerials = [];
      _duplicateRows.clear();
    });
    _disposeRowsLater(removed);
    if (numOrden.isNotEmpty) {
      await _autoAttachExcelToArchivos(numOrden);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _orderFocus.requestFocus();
      }
    });
  }

  Future<void> _refreshOrderAfterSave(String numOrden) async {
    final client = _clientOrNull();
    if (client == null) return;
    setState(() => _loadingOrder = true);
    try {
      final res = await client.post(
        '$_basePath/order-info',
        jsonBody: {'num_orden': numOrden},
        extraHeaders: _orderInfoAuthHeaders(client),
      );
      if (!mounted) return;

      if (res.statusCode == 404) {
        await _completeOrderAndAttach(numOrden);
        return;
      }

      if (!res.ok || res.body is! Map) {
        _showSnack('No se pudo refrescar la orden (${res.statusCode})');
        return;
      }

      final map = res.body as Map;
      final orderMap = map['order'];
      if (orderMap is! Map || orderMap.isEmpty) {
        _showSnack('La orden no devolvio datos tras guardar');
        return;
      }

      final serials = (map['serials'] as List? ?? const [])
          .whereType<Map>()
          .map<Map<String, String>>(
            (e) => {
              'serial': e['serial']?.toString() ?? '',
              'inventory_code': e['inventory_code']?.toString() ?? '',
            },
          )
          .toList();

      final bool hasInventoryCodes = serials.any(
        (s) => (s['inventory_code'] ?? s['inventory'] ?? '')
            .toString()
            .trim()
            .isNotEmpty,
      );
      _applyOrderData(
        order: Map<String, dynamic>.from(orderMap),
        serials: serials,
        manualDouble: (orderMap['manual_double'] == true) || hasInventoryCodes,
      );
      await _fetchOrderSequence(numOrden);
      _quickScanFocus.requestFocus();
    } catch (e) {
      _showSnack('Error refrescando orden: $e');
    } finally {
      if (mounted) setState(() => _loadingOrder = false);
    }
  }

  Future<({int count, String? sourceOrder})> _getExistingCodesCount(
    String numOrden,
  ) async {
    final client = _clientOrNull();
    if (client == null) return (count: 0, sourceOrder: null);
    try {
      final res = await client.get(
        '$_basePath/get-sequence?order_nbr=${Uri.encodeComponent(numOrden)}&search_orphans=true',
      );
      if (res.ok && res.body is Map) {
        final body = res.body as Map;
        final codes = body['codes'] as List?;
        final source = body['source_order']?.toString();
        return (count: codes?.length ?? 0, sourceOrder: source);
      }
    } catch (_) {}
    return (count: 0, sourceOrder: null);
  }

  Future<void> _fetchOrderSequence(
    String numOrden, {
    bool searchOrphans = false,
  }) async {
    final client = _clientOrNull();
    if (client == null) return;
    try {
      final res = await client.get(
        '$_basePath/get-sequence?order_nbr=${Uri.encodeComponent(numOrden)}&search_orphans=$searchOrphans',
      );
      if (res.ok && res.body is Map) {
        final body = res.body as Map;
        final codes = body['codes'] as List?;
        if (codes != null && mounted) {
          setState(() {
            _sequenceQueue = codes.map((e) => e.toString()).toList();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _showSequenceDialog() async {
    final numOrden = _orderCtrl.text.trim();
    if (numOrden.isEmpty) {
      _showSnack('Por favor ingresa un número de orden primero');
      return;
    }

    // Check for orphans/existing
    final existing = await _getExistingCodesCount(numOrden);

    if (!mounted) return;

    final ctrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gestionar Secuencia'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (existing.count > 0 && existing.sourceOrder != numOrden) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.tealAccent.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Se encontraron ${existing.count} códigos sin usar de la orden ${existing.sourceOrder}.',
                        style: const TextStyle(fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.tealAccent.withOpacity(0.2),
                          foregroundColor: Colors.tealAccent,
                        ),
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await _fetchOrderSequence(
                            numOrden,
                            searchOrphans: true,
                          );
                          _showSnack(
                            'Secuencia recuperada de ${existing.sourceOrder}',
                          );
                        },
                        icon: const Icon(Icons.auto_fix_high_rounded),
                        label: const Text('Reutilizar estos códigos'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              const Text(
                'Nueva Secuencia',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  final units = (_orderInfo?['unidades'] as num?)?.toInt() ?? 0;
                  final List<String>? generated =
                      await showDialog<List<String>>(
                        context: ctx,
                        builder: (c) =>
                            _SequenceSetupDialog(targetCount: units),
                      );
                  if (generated != null && generated.isNotEmpty) {
                    Navigator.of(ctx).pop();
                    await _saveSequenceToBackend(numOrden, generated);
                    await _fetchOrderSequence(numOrden);
                    _showSnack('Se han activado ${generated.length} códigos.');
                  }
                },
                icon: const Icon(Icons.settings_suggest_rounded),
                label: const Text('ABRIR GENERADOR DE SECUENCIAS'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSequenceToBackend(
    String numOrden,
    List<String> codes,
  ) async {
    if (codes.isEmpty) return;
    final client = _clientOrNull();
    if (client == null) return;
    try {
      await client.post(
        '$_basePath/save-sequence',
        jsonBody: {'order_nbr': numOrden, 'codes': codes},
      );
    } catch (_) {}
  }

  Future<void> _fetchNextInventory() async {
    final client = _clientOrNull();
    if (client == null) return;
    try {
      final res = await client.get('$_basePath/next-available');
      if (!mounted) return;
      if (res.ok && res.body is Map) {
        setState(
          () =>
              _nextInventory = (res.body as Map)['inventory_code']?.toString(),
        );
      }
    } catch (_) {}
  }

  Future<void> _refreshRecent() async {
    final client = _clientOrNull();
    if (client == null) return;
    setState(() => _loadingRecent = true);
    try {
      final res = await client.get('$_basePath/mappings?limit=50');
      if (!mounted) return;
      if (res.ok && res.body is List) {
        final rawList = res.body as List;
        setState(() {
          _recent = rawList.map<Map<String, String?>>((item) {
            if (item is Map) {
              return {
                'inventory_code': item['inventory_code']?.toString(),
                'serial': item['serial']?.toString(),
              };
            }
            return {'inventory_code': null, 'serial': null};
          }).toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingRecent = false);
    }
  }

  Future<void> _playAlert() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }

  Future<bool> _confirmSuspicious(String serial, List<dynamic>? matches) async {
    unawaited(_playAlert());
    final sample = (matches ?? const [])
        .cast<Map>()
        .map((m) => m['mask']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .take(3)
        .toList();
    final detail = sample.isEmpty
        ? ''
        : '\nCoincidencias: ${sample.join(', ')}';
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Serial sospechoso'),
        content: Text(
          'El valor escaneado coincide con una máscara conocida.$detail',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<bool> _confirmDuplicate(String serial, String inventoryCode) async {
    unawaited(_playAlert());
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Serial duplicado'),
        content: Text(
          '"$serial" ya está vinculado a "$inventoryCode". ¿Continuar de todos modos?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _assignSerial(String serial) async {
    final client = _clientOrNull();
    if (client == null) {
      _showSnack('Servicio API no disponible');
      return;
    }
    setState(() {
      _assigning = true;
      _assignError = null;
    });
    try {
      final encoded = Uri.encodeQueryComponent(serial);

      // Duplicate pre-check
      try {
        final dup = await client.get(
          '$_basePath/serial-to-inventory?serial=$encoded',
        );
        if (dup.ok && dup.body is Map) {
          final code = (dup.body as Map)['inventory_code']?.toString() ?? '';
          if (code.isNotEmpty) {
            final proceed = await _confirmDuplicate(serial, code);
            if (!proceed) {
              if (mounted) setState(() => _assigning = false);
              return;
            }
          }
        }
      } catch (_) {}

      // Mask check
      try {
        final mask = await client.post(
          '$_basePath/masks/check',
          jsonBody: {'serial': serial},
        );
        if (mask.ok && mask.body is Map) {
          final body = mask.body as Map;
          if (body['suspicious'] == true) {
            final proceed = await _confirmSuspicious(
              serial,
              body['matches'] as List<dynamic>?,
            );
            if (!proceed) {
              if (mounted) setState(() => _assigning = false);
              return;
            }
          }
        }
      } catch (_) {}

      final ensure = await client.post(
        '$_basePath/serial-to-inventory/ensure',
        jsonBody: {'serial': serial},
      );
      if (!mounted) return;
      if (ensure.ok && ensure.body is Map) {
        final map = ensure.body as Map;
        final code = map['inventory_code']?.toString();
        setState(() {
          _lastInventory = code;
          _recent.insert(0, {'inventory_code': code, 'serial': serial});
          if (_recent.length > 50) _recent.removeLast();
        });
        await Future.wait([_fetchNextInventory(), _refreshRecent()]);
        _showSnack('Serial asignado');
      } else {
        SoundPlayer.playError();
        setState(
          () => _assignError =
              ensure.error ?? 'No se pudo asignar (${ensure.statusCode})',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _assignError = e.toString());
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  Future<Map<String, dynamic>?> _maskCheck(String serial) async {
    final client = _clientOrNull();
    if (client == null) return null;
    try {
      final res = await client.post(
        '$_basePath/masks/check',
        jsonBody: {'serial': serial},
      );
      if (res.ok && res.body is Map) return res.body as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  List<_MatchRow> _resizeMatchRows(int target) {
    final removed = <_MatchRow>[];
    final safeTarget = target < 0 ? 0 : (target > 1000 ? 1000 : target);
    _rowEpoch++;
    final reuseUntil = safeTarget < _matchRows.length
        ? safeTarget
        : _matchRows.length;
    for (var i = 0; i < reuseUntil; i++) {
      _matchRows[i].generation = _rowEpoch;
    }
    if (safeTarget < _matchRows.length) {
      removed.addAll(_matchRows.sublist(safeTarget));
      _matchRows.removeRange(safeTarget, _matchRows.length);
    } else if (safeTarget > _matchRows.length) {
      final toCreate = safeTarget - _matchRows.length;
      for (var i = 0; i < toCreate; i++) {
        final row = _MatchRow()..generation = _rowEpoch;
        _matchRows.add(row);
      }
    }
    return removed;
  }

  void _disposeRowsLater(List<_MatchRow> rows) {
    if (rows.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in rows) {
        row.dispose();
      }
    });
  }

  void _applyOrderData({
    required Map<String, dynamic> order,
    required List<Map<String, String>> serials,
    int? unitsOverride,
    bool? manualDouble,
    List<String>? sequence,
  }) {
    final normalized = Map<String, dynamic>.from(order);
    final numOrdenRaw = normalized['num_orden'];
    normalized['num_orden'] =
        (numOrdenRaw == null || numOrdenRaw.toString().trim().isEmpty)
        ? _normalizeOrder(_orderCtrl.text)
        : _normalizeOrder(numOrdenRaw.toString());
    final resolvedUnits =
        unitsOverride ??
        int.tryParse(normalized['unidades']?.toString() ?? '') ??
        serials.length;
    normalized['unidades'] = resolvedUnits;
    normalized['manual'] = normalized['manual'] == true;
    final bool manualDoubleFlag =
        manualDouble ?? (normalized['manual_double'] == true);
    normalized['manual_double'] = manualDoubleFlag;

    final pendingRaw = resolvedUnits - serials.length;
    final removed = _resizeMatchRows(pendingRaw);

    setState(() {
      _orderInfo = normalized;
      _orderSerials = serials;
      _duplicateRows.clear();
      if (sequence != null) {
        _sequenceQueue = sequence;
      }
    });

    _disposeRowsLater(removed);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkCompletionAndPrompt();
    });
  }

  ({int units, bool doubleEntry, List<String>? sequence})?
  _existingManualConfig(String numOrden) {
    if (_orderInfo == null) return null;
    if (_orderInfo!['manual'] != true) return null;
    if (_orderInfo!['num_orden']?.toString() != numOrden) return null;
    final Object? unitsValue = _orderInfo!['unidades'];
    final int? parsedUnits = unitsValue is int
        ? unitsValue
        : int.tryParse(unitsValue?.toString() ?? '');
    if (parsedUnits == null || parsedUnits <= 0) return null;
    final bool doubleEntry = _orderInfo!['manual_double'] == true;
    return (units: parsedUnits, doubleEntry: doubleEntry, sequence: null);
  }

  bool get _isManualDouble => _orderInfo?['manual_double'] == true;

  Future<({int units, bool doubleEntry, List<String>? sequence})?>
  _promptManualUnits(String numOrden) async {
    final result = await showDialog<_ManualOrderPromptResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ManualUnitsDialog(numOrden: numOrden),
    );
    if (result == null) return null;
    final trimmed = result.unitsText.trim();
    if (trimmed.isEmpty) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed <= 0) {
      _showSnack('Introduce un número válido de unidades');
      return null;
    }
    return (
      units: parsed,
      doubleEntry: result.doubleEntry,
      sequence: result.sequence,
    );
  }

  Future<void> _fetchOrder() async {
    final client = _clientOrNull();
    if (client == null) {
      _showSnack('Servicio API no disponible');
      return;
    }
    final numOrden = _normalizeOrder(_orderCtrl.text);
    if (numOrden.isEmpty) return;
    if (!_isValidOrder(numOrden)) {
      _showSnack('Formato inválido. Usa XX-XXXXX-XX');
      return;
    }
    _orderCtrl.value = TextEditingValue(
      text: numOrden,
      selection: TextSelection.collapsed(offset: numOrden.length),
    );
    setState(() {
      _loadingOrder = true;
      _duplicateRows.clear();
    });
    try {
      final res = await client.post(
        '$_basePath/order-info',
        jsonBody: {'num_orden': numOrden},
        extraHeaders: _orderInfoAuthHeaders(client),
      );
      if (!mounted) return;
      if (res.statusCode == 404) {
        final isEmbeddedMatchFlow =
            widget.matchOnly || widget.isEmbedded || _tabs.index == 1;
        setState(() => _loadingOrder = false);
        if (isEmbeddedMatchFlow) {
          final manualConfig = await _promptManualUnits(numOrden);
          if (manualConfig == null) {
            setState(() => _loadingOrder = false);
            return;
          }

          try {
            final regRes = await client.post(
              '$_basePath/order-info',
              jsonBody: {
                'num_orden': numOrden,
                'save': true,
                'unidades': manualConfig.units,
                'manual': true,
                'manual_double': manualConfig.doubleEntry,
              },
              extraHeaders: _orderInfoAuthHeaders(client),
            );
            if (!mounted) return;
            if (!regRes.ok || regRes.body is! Map) {
              _showSnack(
                'No se pudo registrar la orden (${regRes.statusCode})',
              );
              return;
            }
            final map = regRes.body as Map;
            final orderMap = map['order'];
            final serials = (map['serials'] as List? ?? const [])
                .whereType<Map>()
                .map<Map<String, String>>(
                  (e) => {
                    'serial': e['serial']?.toString() ?? '',
                    'inventory_code': e['inventory_code']?.toString() ?? '',
                  },
                )
                .toList();

            if (orderMap is! Map) {
              _showSnack('Orden registrada pero no se devolvieron datos.');
              return;
            }

            _applyOrderData(
              order: Map<String, dynamic>.from(orderMap),
              serials: serials,
              manualDouble:
                  manualConfig.doubleEntry ||
                  (orderMap['manual_double'] == true),
            );
            _quickScanFocus.requestFocus();
            if (manualConfig.sequence != null &&
                manualConfig.sequence!.isNotEmpty) {
              await _saveSequenceToBackend(numOrden, manualConfig.sequence!);
              await _fetchOrderSequence(numOrden);
            }
          } catch (e) {
            _showSnack('Error registrando orden: $e');
          }
          return;
        }
        setState(() => _loadingOrder = false);

        final detection = await _getExistingCodesCount(numOrden);
        final existingCodesCount = detection.count;
        final sourceOrder = detection.sourceOrder;

        bool useExisting = false;
        if (existingCodesCount > 0) {
          final isSameOrder = sourceOrder == numOrden;
          final msg = isSameOrder
              ? 'Se encontraron $existingCodesCount códigos de inventario previos para esta orden.'
              : 'No hay secuencia para esta orden, pero se encontró una sin terminar en la orden "$sourceOrder" ($existingCodesCount códigos).';

          useExisting =
              await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(
                    isSameOrder
                        ? 'Secuencia detectada'
                        : 'Reutilizar secuencia',
                  ),
                  content: Text(
                    '$msg ¿Deseas usar esos códigos o configurar una nueva secuencia?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('NUEVA'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('USAR ESTOS'),
                    ),
                  ],
                ),
              ) ??
              false;
        }

        final existingManual = _existingManualConfig(numOrden);
        final manualConfig =
            existingManual ?? await _promptManualUnits(numOrden);
        if (!mounted) return;
        if (manualConfig != null) {
          final seqToUse = useExisting ? null : manualConfig.sequence;

          _applyOrderData(
            order: {
              'num_orden': numOrden,
              'unidades': manualConfig.units,
              'manual': true,
              'manual_double': useExisting || manualConfig.doubleEntry,
            },
            serials: const <Map<String, String>>[],
            unitsOverride: manualConfig.units,
            manualDouble: useExisting || manualConfig.doubleEntry,
          );
          _quickScanFocus.requestFocus();

          if (useExisting) {
            // Claiming codes from the other order involves saving them for the current order
            await _fetchOrderSequence(numOrden, searchOrphans: true);
            if (_sequenceQueue.isNotEmpty) {
              await _saveSequenceToBackend(numOrden, _sequenceQueue);
            }
          } else if (seqToUse != null && seqToUse.isNotEmpty) {
            await _saveSequenceToBackend(numOrden, seqToUse);
            await _fetchOrderSequence(numOrden);
          }

          if (existingManual == null) {
            final mode = (useExisting || manualConfig.doubleEntry)
                ? 'doble'
                : 'unitario';
            _showSnack(
              'Orden manual ($mode) preparada. Escanea ${manualConfig.units} unidades.',
            );
          }
        }
        return;
      }
      if (!res.ok || res.body is! Map) {
        // TRICK: If the server returns a 500 but it's clearly a missing order
        // (common in dev/staging environments with complex SQL triggers),
        // we still allow the manual registration prompt if we are in one of the match flows.
        final isEmbeddedMatchFlow =
            widget.matchOnly || widget.isEmbedded || _tabs.index == 1;

        if (isEmbeddedMatchFlow) {
          setState(() => _loadingOrder = false);
          final manualConfig = await _promptManualUnits(numOrden);
          if (manualConfig == null) return;

          try {
            final regRes = await client.post(
              '$_basePath/order-info',
              jsonBody: {
                'num_orden': numOrden,
                'save': true,
                'unidades': manualConfig.units,
                'manual': true,
                'manual_double': manualConfig.doubleEntry,
              },
              extraHeaders: _orderInfoAuthHeaders(client),
            );
            if (!mounted) return;
            if (!regRes.ok || regRes.body is! Map) {
              _showSnack(
                'No se pudo registrar la orden (${regRes.statusCode})',
              );
              return;
            }
            final map = regRes.body as Map;
            final orderMap = map['order'];
            final serials = (map['serials'] as List? ?? const [])
                .whereType<Map>()
                .map<Map<String, String>>(
                  (e) => {
                    'serial': e['serial']?.toString() ?? '',
                    'inventory_code': e['inventory_code']?.toString() ?? '',
                  },
                )
                .toList();

            if (orderMap is! Map) {
              _showSnack('Orden registrada pero no se devolvieron datos.');
              return;
            }

            _applyOrderData(
              order: Map<String, dynamic>.from(orderMap),
              serials: serials,
              manualDouble:
                  manualConfig.doubleEntry ||
                  (orderMap['manual_double'] == true) ||
                  serials.any(
                    (s) => (s['inventory_code'] ?? s['inventory'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty,
                  ),
            );
            if (manualConfig.sequence != null &&
                manualConfig.sequence!.isNotEmpty) {
              await _saveSequenceToBackend(numOrden, manualConfig.sequence!);
              await _fetchOrderSequence(numOrden);
            }
          } catch (e) {
            _showSnack('Error registrando orden: $e');
          }
          return;
        }

        if (res.statusCode == 500) {
          _showSnack('Error del servidor al buscar la orden');
        } else {
          _showSnack('Orden no encontrada (${res.statusCode})');
        }
        return;
      }
      final map = res.body as Map;
      final orderMap = map['order'];
      Map<String, dynamic> order;
      if (orderMap is Map && orderMap.isNotEmpty) {
        order = Map<String, dynamic>.from(orderMap);
      } else {
        setState(() => _loadingOrder = false);
        final existingManual = _existingManualConfig(numOrden);
        final manualConfig =
            existingManual ?? await _promptManualUnits(numOrden);
        if (!mounted) return;
        if (manualConfig != null) {
          _applyOrderData(
            order: {
              'num_orden': numOrden,
              'unidades': manualConfig.units,
              'manual': true,
              'manual_double': manualConfig.doubleEntry,
            },
            serials: const <Map<String, String>>[],
            unitsOverride: manualConfig.units,
            manualDouble: manualConfig.doubleEntry,
          );
          if (existingManual == null) {
            final mode = manualConfig.doubleEntry ? 'doble' : 'unitario';
            _showSnack(
              'Orden manual ($mode) preparada. Escanea ${manualConfig.units} unidades.',
            );
          }
          if (manualConfig.sequence != null &&
              manualConfig.sequence!.isNotEmpty) {
            await _saveSequenceToBackend(numOrden, manualConfig.sequence!);
            await _fetchOrderSequence(numOrden);
          }
        }
        return;
      }
      final serials = (map['serials'] as List? ?? const [])
          .whereType<Map>()
          .map<Map<String, String>>(
            (e) => {
              'serial': e['serial']?.toString() ?? '',
              'inventory_code': e['inventory_code']?.toString() ?? '',
            },
          )
          .toList();
      final bool hasInventoryCodes = serials.any(
        (s) => (s['inventory_code'] ?? s['inventory'] ?? '')
            .toString()
            .trim()
            .isNotEmpty,
      );
      _applyOrderData(
        order: order,
        serials: serials,
        manualDouble: (order['manual_double'] == true) || hasInventoryCodes,
      );
      await _fetchOrderSequence(numOrden);
    } catch (e) {
      _showSnack('Error obteniendo orden: $e');
    } finally {
      if (mounted) setState(() => _loadingOrder = false);
    }
  }

  void _validateRows() {
    _duplicateRows.clear();
    final Map<String, List<int>> seen = {};
    for (var i = 0; i < _matchRows.length; i++) {
      final value = _matchRows[i].serial.text.trim().toLowerCase();
      if (value.isEmpty) continue;
      seen.putIfAbsent(value, () => []).add(i);
    }
    for (final entry in seen.entries) {
      if (entry.value.length > 1) _duplicateRows.addAll(entry.value);
    }
    final registered = _orderSerials
        .map((e) => (e['serial'] ?? '').toLowerCase())
        .toSet();
    for (var i = 0; i < _matchRows.length; i++) {
      final value = _matchRows[i].serial.text.trim().toLowerCase();
      if (value.isEmpty) continue;
      if (registered.contains(value)) _duplicateRows.add(i);
    }
    setState(() {});
  }

  Future<bool> _isDuplicateInMatch(int index, String serial) async {
    final value = serial.trim().toLowerCase();
    if (value.isEmpty) return false;

    // Check against history in this order
    final registered = _orderSerials.any(
      (e) => (e['serial'] ?? '').toLowerCase() == value,
    );
    if (registered) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Serial duplicado'),
          content: Text(
            'El serial "$serial" ya está registrado en esta orden.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return true;
    }

    // Check against other current rows
    for (var i = 0; i < _matchRows.length; i++) {
      if (i == index) continue;
      if (_matchRows[i].serial.text.trim().toLowerCase() == value) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Serial duplicado'),
            content: Text('El serial "$serial" ya está en la fila ${i + 1}.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        return true;
      }
    }

    return false;
  }

  Future<void> _lookupInventory(int index) async {
    if (index < 0 || index >= _matchRows.length) return;
    if (_isManualDouble) return;
    final client = _clientOrNull();
    if (client == null) return;
    final row = _matchRows[index];
    final expectedEpoch = row.generation;
    final value = row.serial.text.trim();
    if (value.isEmpty) return;
    final mask = await _maskCheck(value);
    if (mask != null && mask['suspicious'] == true) {
      final proceed = await _confirmSuspicious(
        value,
        mask['matches'] as List<dynamic>?,
      );
      if (!proceed) {
        if (row.disposed ||
            row.generation != expectedEpoch ||
            !_matchRows.contains(row))
          return;
        row.serial.clear();
        _validateRows();
        if (!row.disposed && row.generation == expectedEpoch) {
          row.focus.requestFocus();
        }
        return;
      }
    }
    try {
      final encoded = Uri.encodeQueryComponent(value);
      final res = await client.get(
        '$_basePath/serial-to-inventory?serial=$encoded',
      );
      if (!mounted) return;
      if (row.disposed ||
          row.generation != expectedEpoch ||
          !_matchRows.contains(row))
        return;
      if (res.ok && res.body is Map) {
        final code = (res.body as Map)['inventory_code']?.toString() ?? '';
        row.inventory.text = code;
      } else if (res.statusCode == 404) {
        row.inventory.clear();
      }
      setState(() {});
    } catch (_) {}
  }

  Future<bool> _saveRow(int index, {bool forceConfirm = true}) async {
    final client = _clientOrNull();
    if (client == null || _orderInfo == null) return false;
    if (index < 0 || index >= _matchRows.length) return false;
    final row = _matchRows[index];
    final expectedEpoch = row.generation;
    final serial = row.serial.text.trim();
    if (serial.isEmpty) return false;
    final manualDouble = _isManualDouble;
    final mask = await _maskCheck(serial);
    if (mask != null && mask['suspicious'] == true) {
      final proceed = await _confirmSuspicious(
        serial,
        mask['matches'] as List<dynamic>?,
      );
      if (!proceed) return false;
    }
    if (manualDouble) {
      if (row.inventory.text.trim().isEmpty) {
        SoundPlayer.playError();
        _showSnack('Escanea inventario/IMEI');
        return false;
      }
    } else if (row.inventory.text.trim().isEmpty) {
      await _lookupInventory(index);
      if (row.disposed ||
          row.generation != expectedEpoch ||
          !_matchRows.contains(row))
        return false;
    }

    // Check if already in saved list (Rescan logic)
    final existingMatch = _orderSerials.firstWhere(
      (s) =>
          s['serial'] == serial &&
          (manualDouble
              ? s['inventory_code'] == row.inventory.text.trim()
              : true),
      orElse: () => {},
    );

    if (existingMatch.isNotEmpty) {
      SoundPlayer.playSuccess();
      row.serial.clear();
      row.inventory.clear();
      _showSnack('SERIAL YA REGISTRADO ✅ (En esta orden)');
      if (mounted) {
        setState(() {});
        _validateRows();
      }
      return false; // Keep the placeholder so it can be used for a real new unit
    }

    // If not in saved list, ask for confirmation (New assignment logic)
    bool confirmAdd = !forceConfirm;
    if (forceConfirm) {
      confirmAdd =
          await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Confirmar nueva asignaci\u00f3n'),
              content: Text(
                'El serial "$serial" no est\u00e1 registrado en esta orden. \u00bfDeseas agregarlo como un nuevo registro?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('CANCELAR'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('AGREGAR'),
                ),
              ],
            ),
          ) ??
          false;
    }

    if (!confirmAdd) {
      return false;
    }

    setState(() {
      _savingRows = true;
      row.isSaving = true;
    });

    try {
      final payload = <String, dynamic>{
        'num_orden': _orderInfo!['num_orden'],
        'serial': serial,
      };
      final code = row.inventory.text.trim();
      if (code.isNotEmpty) payload['inventory_code'] = code;
      final res = await client.post('$_basePath/match', jsonBody: payload);
      if (!mounted) return false;
      if (row.disposed ||
          row.generation != expectedEpoch ||
          !_matchRows.contains(row))
        return false;
      if (res.ok) {
        SoundPlayer.playSuccess();
        row.serial.clear();
        row.inventory.clear();
        final completedOrder =
            _orderInfo?['num_orden']?.toString() ?? _orderCtrl.text;
        await _refreshOrderAfterSave(completedOrder);
        return true;
      }

      // Handle Conflict (duplicate serial)
      if (res.statusCode == 400 || res.statusCode == 409) {
        final body = res.body;
        if (body is Map &&
            body['error'] == 'serial already assigned to another order') {
          final existingOrder = body['num_orden'];
          final replace = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Serial ya asignado'),
              content: Text(
                'Este serial está asignado a la orden "$existingOrder". ¿Deseas reemplazarlo y asignarlo a esta orden?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('CANCELAR'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('REEMPLAZAR'),
                ),
              ],
            ),
          );

          if (replace == true) {
            payload['replace'] = true;
            final resRetry = await client.post(
              '$_basePath/match',
              jsonBody: payload,
            );
            if (resRetry.ok) {
              SoundPlayer.playSuccess();
              row.serial.clear();
              row.inventory.clear();
              final completedOrder =
                  _orderInfo?['num_orden']?.toString() ?? _orderCtrl.text;
              await _refreshOrderAfterSave(completedOrder);
              return true;
            }
          }
        }
      }

      SoundPlayer.playError();
      if (res.statusCode == 400 || res.statusCode == 409) {
        String msg = 'Serial ya asignado';
        if (res.body is Map && (res.body as Map)['num_orden'] != null) {
          msg =
              'Serial ya asignado a la orden ${(res.body as Map)['num_orden']}';
        }
        _showSnack(msg);
        return false;
      }
      _showSnack('No se pudo guardar (${res.statusCode})');
      return false;
    } catch (e) {
      SoundPlayer.playError();
      _showSnack('Error guardando: $e');
      return false;
    } finally {
      if (mounted) {
        setState(() {
          row.isSaving = false;
        });
      }
    }
  }

  void _handleInventorySubmit(int index) async {
    if (index < 0 || index >= _matchRows.length) return;
    final saved = await _saveRow(index, forceConfirm: false);
    if (saved) {
      if (index < _matchRows.length) {
        _matchRows[index].focus.requestFocus();
      }
    } else {
      _matchRows[index].inventoryFocus.requestFocus();
    }
  }

  Future<void> _importOrders() async {
    final client = _clientOrNull();
    if (client == null) {
      _showSnack('Servicio API no disponible');
      return;
    }
    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes =
        file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null || bytes.isEmpty) {
      _showSnack('No se pudo leer el archivo seleccionado');
      return;
    }
    setState(() => _uploading = true);
    try {
      final res = await client.postMultipart(
        '$_basePath/import-orders',
        fileFieldName: 'file',
        fileName: file.name.isNotEmpty ? file.name : 'import.dat',
        fileBytes: bytes,
      );
      if (res.ok) {
        if (res.body is Map) {
          final body = res.body as Map;
          final inserted = body['inserted'] ?? 0;
          final skipped = body['skipped'] ?? 0;
          final errors = (body['errors'] as List?)?.length ?? 0;
          _showSnack(
            'Importado: $inserted • saltados: $skipped • errores: $errors',
          );
        } else {
          _showSnack('Importado correctamente');
        }
        await _refreshRecent();
      } else {
        _showSnack('Error importando (${res.statusCode})');
      }
    } catch (e) {
      _showSnack('Error importando: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _checkCompletionAndPrompt() async {
    if (_orderInfo == null) return;
    final total = int.tryParse(_orderInfo!['unidades']?.toString() ?? '0') ?? 0;
    if (total <= 0) return;
    if (_orderSerials.length < total) return;

    // Only for Manipulacion y Etiquetado
    final fam = _orderInfo!['familia']?.toString().toUpperCase() ?? '';
    if (!fam.contains('MANIPULAC') || !fam.contains('ETIQUETADO')) return;

    final orderNbr = _orderInfo!['num_orden']?.toString() ?? '';
    if (_lastPromptedOrder == orderNbr) return;
    _lastPromptedOrder = orderNbr;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('¡Orden Completada!'),
        content: const Text(
          '¿Quieres exportar o imprimir un acta en esta orden?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('AHORA NO'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('EXPORTAR / IMPRIMIR'),
          ),
        ],
      ),
    );

    if (proceed == true && mounted) {
      await _exportActa();
    }
  }

  Future<void> _resetOrders() async {
    final client = _clientOrNull();
    if (client == null) {
      _showSnack('Servicio API no disponible');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resetear registros'),
        content: const Text(
          'Esta acción eliminará todos los registros de órdenes. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _resetting = true);
    try {
      final res = await client.post('$_basePath/truncate-registro-ordenes');
      if (res.ok) {
        if (res.body is Map) {
          final body = res.body as Map;
          _showSnack('Reset completado (${body['deleted_rows'] ?? 0} filas)');
        } else {
          _showSnack('Reset completado');
        }
        await _refreshRecent();
      } else {
        _showSnack('No se pudo resetear (${res.statusCode})');
      }
    } catch (e) {
      _showSnack('Error reset: $e');
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  Future<void> _loadTemplates() async {
    final client = _clientOrNull();
    if (client == null) return;
    setState(() => _templatesLoading = true);
    try {
      final res = await client.get('$_basePath/templates');
      if (!mounted) return;
      if (res.ok && res.body is Map) {
        final list = (res.body as Map)['templates'] as List? ?? const [];
        setState(() {
          _templates = list
              .whereType<Map>()
              .map(
                (e) => {
                  'filename': e['filename']?.toString() ?? '',
                  'size': e['size'],
                  'modified': e['modified'],
                },
              )
              .toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _templatesLoading = false);
    }
  }

  Future<void> _uploadTemplate() async {
    final client = _clientOrNull();
    if (client == null) {
      _showSnack('Servicio API no disponible');
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['docx'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes =
        file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null || bytes.isEmpty) {
      _showSnack('No se pudo leer el archivo seleccionado');
      return;
    }
    setState(() => _templateUploading = true);
    try {
      final res = await client.postMultipart(
        '$_basePath/templates/upload',
        fileFieldName: 'file',
        fileName: file.name.isNotEmpty ? file.name : 'template.docx',
        fileBytes: bytes,
      );
      if (res.ok) {
        _showSnack('Plantilla subida');
        await _loadTemplates();
      } else {
        _showSnack('Error subiendo (${res.statusCode})');
      }
    } catch (e) {
      _showSnack('Error subiendo plantilla: $e');
    } finally {
      if (mounted) setState(() => _templateUploading = false);
    }
  }

  Future<void> _exportActa() async {
    final num = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(
          text: _normalizeOrder(_orderInfo?['num_orden']?.toString() ?? ''),
        );
        return AlertDialog(
          title: const Text('Exportar acta'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Número de orden'),
            inputFormatters: [OrderInputFormatter()],
            autofocus: true,
            onSubmitted: (_) =>
                Navigator.of(ctx).pop(_normalizeOrder(ctrl.text)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_normalizeOrder(ctrl.text)),
              child: const Text('Exportar'),
            ),
          ],
        );
      },
    );
    if (num == null || num.isEmpty) return;
    if (!_isValidOrder(num)) {
      _showSnack('Formato inválido. Usa XX-XXXXX-XX');
      return;
    }
    final client = _clientOrNull();
    if (client == null) {
      _showSnack('Servicio API no disponible');
      return;
    }
    setState(() => _exporting = true);
    try {
      final res = await client.getBytes('/docgen/order/$num/pdf?stream=true');
      if (!mounted) return;
      if (!res.ok || res.body is! List<int>) {
        _showSnack('No se pudo generar el acta (${res.statusCode})');
        return;
      }

      final headers = res.headers ?? const <String, String>{};
      final suggested = _filenameFromHeaders(headers) ?? _defaultActaName(num);
      final pdfBytes = Uint8List.fromList(res.body as List<int>);

      if (mounted) {
        final service = Provider.of<OrderOpsService>(context, listen: false);
        await showDialog(
          context: context,
          builder: (context) => PdfPreviewDialog(
            pdfBytes: pdfBytes,
            fileName: suggested,
            service: service,
          ),
        );
      }
    } catch (e) {
      _showSnack('Error exportando: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportMatchesToExcel() async {
    final num = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(
          text: _normalizeOrder(_orderInfo?['num_orden']?.toString() ?? ''),
        );
        return AlertDialog(
          title: const Text('Exportar Excel'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Número de orden'),
            inputFormatters: [OrderInputFormatter()],
            autofocus: true,
            onSubmitted: (_) =>
                Navigator.of(ctx).pop(_normalizeOrder(ctrl.text)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_normalizeOrder(ctrl.text)),
              child: const Text('Exportar'),
            ),
          ],
        );
      },
    );
    if (num == null || num.isEmpty) return;
    if (!_isValidOrder(num)) {
      _showSnack('Formato inválido. Usa XX-XXXXX-XX');
      return;
    }

    final client = _clientOrNull();
    if (client == null) {
      _showSnack('Servicio API no disponible');
      return;
    }
    setState(() => _exportingExcel = true);
    try {
      final res = await client.getBytes(
        '$_basePath/matches/export?num_orden=${Uri.encodeQueryComponent(num)}',
      );
      if (!mounted) return;
      if (!res.ok || res.body is! List<int>) {
        _showSnack('No se pudo exportar (${res.statusCode})');
        return;
      }
      final headers = res.headers ?? const <String, String>{};
      final suggested =
          _filenameFromHeaders(headers) ?? 'serial_matches_export.xlsx';
      final path = await FilePicker.platform.saveFile(
        fileName: suggested,
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        dialogTitle: 'Guardar Excel',
      );
      if (path == null) {
        _showSnack('Descarga cancelada');
        return;
      }
      final file = File(path);
      await file.writeAsBytes(res.body as List<int>, flush: true);
      _showSnack('Archivo guardado en $path');
    } catch (e) {
      _showSnack('Error exportando Excel: $e');
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  String _defaultActaName(String numOrden) {
    final centro = _orderInfo?['codigo_centro']?.toString().trim();
    final suffix = (centro == null || centro.isEmpty) ? 'SINCC' : centro;
    return 'Acta_${suffix}_$numOrden.pdf';
  }

  String? _filenameFromHeaders(Map<String, String> headers) {
    final cd = headers['content-disposition'] ?? headers['Content-Disposition'];
    if (cd == null || cd.isEmpty) return null;
    final star = RegExp(
      r"filename\*\s*=\s*(?:UTF-8''|utf-8'')?([^;]+)",
      caseSensitive: false,
    );
    final matchStar = star.firstMatch(cd);
    if (matchStar != null) {
      final raw = (matchStar.group(1) ?? '').replaceAll('"', '').trim();
      try {
        return Uri.decodeFull(raw);
      } catch (_) {
        return raw;
      }
    }
    final plain = RegExp(
      r'filename\s*=\s*("?)([^";]+)\1',
      caseSensitive: false,
    );
    final matchPlain = plain.firstMatch(cd);
    if (matchPlain != null) return matchPlain.group(2)?.trim();
    return null;
  }

  Widget _buildAssignTab() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Registro Serial', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            'Escanea el serial y el sistema asignará la siguiente etiqueta disponible.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _serialCtrl,
                  focusNode: _serialFocus,
                  decoration: InputDecoration(
                    labelText: 'Serial',
                    hintText: 'Escanear o escribir serial',
                    suffixText: _nextInventory != null
                        ? 'Siguiente: $_nextInventory'
                        : null,
                  ),
                  onSubmitted: (value) {
                    final trimmed = value.trim();
                    if (trimmed.isEmpty) return;
                    _assignSerial(trimmed);
                    _serialCtrl.clear();
                    _serialFocus.requestFocus();
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _assigning
                    ? null
                    : () {
                        final trimmed = _serialCtrl.text.trim();
                        if (trimmed.isEmpty) return;
                        _assignSerial(trimmed);
                        _serialCtrl.clear();
                        _serialFocus.requestFocus();
                      },
                icon: _assigning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.done_all),
                label: Text(_assigning ? 'Asignando...' : 'Asignar'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _assigning ? null : _fetchNextInventory,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar siguiente'),
              ),
              const SizedBox(width: 12),
              if (_lastInventory != null)
                Text(
                  'Último inventario: $_lastInventory',
                  style: theme.textTheme.bodyMedium,
                ),
            ],
          ),
          if (_assignError != null) ...[
            const SizedBox(height: 8),
            Text(
              _assignError!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Asignaciones recientes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _loadingRecent
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              : _recent.isEmpty
              ? const Text('No hay asignaciones todavía.')
              : ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: _recent.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final row = _recent[index];
                    return ListTile(
                      leading: Text('#${index + 1}'),
                      title: Text(row['inventory_code'] ?? '-'),
                      subtitle: Text(row['serial'] ?? '-'),
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildMatchTab() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final totalUnits = (_orderInfo?['unidades'] as num?)?.toInt() ?? 0;
    final savedUnits = _orderSerials.length;
    final progress = totalUnits > 0
        ? (savedUnits / totalUnits).clamp(0.0, 1.0)
        : 0.0;
    final manualDouble = _isManualDouble;
    final mq = MediaQuery.of(context);
    final isSmall = mq.size.width < 700;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ALWAYS VISIBLE SEARCH BAR
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _orderCtrl,
                  focusNode: _orderFocus,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Número de Orden',
                    hintText: 'XX-XXXXX-XX',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                  ),
                  inputFormatters: [OrderInputFormatter()],
                  onSubmitted: (_) => _fetchOrder(),
                ),
              ),
              if (_orderInfo != null) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      // SECUENCIA BUTTON
                      TextButton.icon(
                        onPressed: _showSequenceDialog,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(
                          Icons.list_alt_rounded,
                          size: 16,
                          color: Colors.tealAccent,
                        ),
                        label: const Text(
                          'SECUENCIA',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.tealAccent,
                          ),
                        ),
                      ),
                      const VerticalDivider(
                        width: 16,
                        color: Colors.white10,
                        indent: 8,
                        endIndent: 8,
                      ),
                      const Text(
                        'DOBLE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white54,
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 32,
                        child: Switch(
                          value: manualDouble,
                          onChanged: (val) => setState(
                            () => _orderInfo!['manual_double'] = val,
                          ),
                          activeColor: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          if (_orderInfo == null) ...[
            const SizedBox(height: 80),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 64,
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
                  const SizedBox(height: 16),
                  const Text('Ingresa un número de orden para comenzar'),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 24),
            // HEADER CARD (Progress & Info)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primaryColor.withOpacity(0.15),
                    primaryColor.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primaryColor.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ORDEN ${_orderInfo!['num_orden']}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              manualDouble
                                  ? 'MODO DOBLE (Serial + IMEI)'
                                  : 'MODO UNITARIO (Solo Serial)',
                              style: TextStyle(
                                color: manualDouble
                                    ? Colors.orangeAccent
                                    : Colors.cyanAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$savedUnits / $totalUnits',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: progress >= 1
                              ? Colors.greenAccent
                              : primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: isDark ? Colors.white10 : Colors.black12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        progress >= 1 ? Colors.greenAccent : primaryColor,
                      ),
                    ),
                  ),
                  if (_orderInfo?['manual'] == true) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.edit_note_rounded,
                            size: 14,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Registro Manual Externo',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // MASTER SCANNER CARD
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primaryColor.withOpacity(0.5),
                    primaryColor.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.center_focus_strong,
                          color: primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ESCÁNER MAESTRO',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                            color: primaryColor,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.info_outline,
                          size: 14,
                          color: Colors.white24,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _quickScanCtrl,
                      focusNode: _quickScanFocus,
                      autofocus: true,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Escaneo rápido o verificación...',
                        prefixIcon: const Icon(Icons.qr_code_scanner),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.03),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 12,
                        ),
                      ),
                      onSubmitted: _handleQuickScan,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Usa este campo para verificar si un serial ya existe o para capturar rápidamente el siguiente.',
                      style: TextStyle(fontSize: 11, color: Colors.white38),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // PENDING SLOTS (New Design)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PENDIENTES DE VINCULACIÓN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.white54,
                  ),
                ),
                if (_matchRows.isNotEmpty)
                  Text(
                    '${_matchRows.length.formattedInt} UNIDADES',
                    style: const TextStyle(fontSize: 10, color: Colors.white30),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (_matchRows.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      color: Colors.greenAccent,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '¡Todas las unidades vinculadas!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _exporting ? null : _exportActa,
                      icon: _exporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf),
                      label: const Text('Exportar Acta (PDF)'),
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _matchRows.length,
                itemBuilder: (_, index) {
                  final row = _matchRows[index];
                  final duplicate = _duplicateRows.contains(index);

                  return Container(
                    key: ValueKey(row),
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.04)
                          : Colors.black.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: duplicate
                            ? Colors.redAccent.withOpacity(0.5)
                            : Colors.white10,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'UNIDAD ${(savedUnits + index + 1).formattedInt}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                            if (duplicate) ...[
                              const SizedBox(width: 8),
                              const Text(
                                'VALOR DUPLICADO',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                            const Spacer(),
                            if (row.isSaving)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.clear,
                                  size: 16,
                                  color: Colors.white24,
                                ),
                                onPressed: () {
                                  row.serial.clear();
                                  row.inventory.clear();
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (isSmall || !manualDouble)
                          Column(
                            children: [
                              _buildModernInput(
                                controller: row.serial,
                                focusNode: row.focus,
                                label: manualDouble
                                    ? 'SERIAL / SN'
                                    : 'SERIAL ÚNICO',
                                icon: Icons.qr_code_scanner_rounded,
                                onSubmitted: (val) =>
                                    _handleSerialSubmit(index, val),
                              ),
                              if (manualDouble) ...[
                                const SizedBox(height: 12),
                                _buildModernInput(
                                  controller: row.inventory,
                                  focusNode: row.inventoryFocus,
                                  label: 'IMEI / INVENTARIO',
                                  icon: Icons.inventory_2_rounded,
                                  onSubmitted: (_) =>
                                      _handleInventorySubmit(index),
                                ),
                              ],
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: _buildModernInput(
                                  controller: row.serial,
                                  focusNode: row.focus,
                                  label: 'SERIAL / SN',
                                  icon: Icons.qr_code_scanner_rounded,
                                  onSubmitted: (val) =>
                                      _handleSerialSubmit(index, val),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildModernInput(
                                  controller: row.inventory,
                                  focusNode: row.inventoryFocus,
                                  label: 'IMEI / INVENTARIO',
                                  icon: Icons.inventory_2_rounded,
                                  onSubmitted: (_) =>
                                      _handleInventorySubmit(index),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),

            const SizedBox(height: 32),

            // HISTORY SECTION (Previously registered)
            if (_orderSerials.isNotEmpty) ...[
              const Text(
                'RECIÉN VINCULADOS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _orderSerials.length.clamp(0, 10), // Show last 10
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: Colors.white10,
                    indent: 16,
                    endIndent: 16,
                  ),
                  itemBuilder: (_, index) {
                    final item =
                        _orderSerials[(_orderSerials.length - 1) - index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.greenAccent,
                        size: 18,
                      ),
                      title: Text(item['serial'] ?? '-'),
                      subtitle: item['inventory_code']?.isNotEmpty == true
                          ? Text(item['inventory_code']!)
                          : null,
                      trailing: Text(
                        '#${(_orderSerials.length - index).formattedInt}',
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildModernInput({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    required Function(String) onSubmitted,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.cyanAccent),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  void _handleSerialSubmit(int index, String val) async {
    final isDup = await _isDuplicateInMatch(index, val);
    if (isDup) {
      _matchRows[index].serial.clear();
      _validateRows();
      _matchRows[index].focus.requestFocus();
      return;
    }
    if (_isManualDouble) {
      if (_sequenceQueue.isNotEmpty) {
        // Auto-fill from sequence
        final nextCode = _sequenceQueue.removeAt(0);
        _matchRows[index].inventory.text = nextCode;
        _handleInventorySubmit(index);
      } else {
        // Try autocomplete from database
        final client = _clientOrNull();
        if (client != null) {
          try {
            final res = await client.get('$_basePath/serial-to-inventory?serial=$val');
            if (res.ok && res.body is Map) {
              final code = res.body['inventory_code']?.toString();
              if (code != null && code.isNotEmpty) {
                _matchRows[index].inventory.text = code;
                _duplicateRows.remove(index);
                _handleInventorySubmit(index);
                return;
              }
            }
          } catch (e) {
            debugPrint('Autocomplete error: $e');
          }
        }
        _matchRows[index].inventoryFocus.requestFocus();
      }
    } else {
      final saved = await _saveRow(index, forceConfirm: false);
      if (saved) {
        if (index < _matchRows.length) {
          _matchRows[index].focus.requestFocus();
        }
      } else {
        _matchRows[index].focus.requestFocus();
      }
    }
  }

  Widget _buildUploadTab() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gestión de órdenes', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _uploading ? null : _importOrders,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: Text(_uploading ? 'Subiendo...' : 'Importar archivo'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                ),
                onPressed: _resetting ? null : _resetOrders,
                icon: _resetting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.delete_sweep),
                label: Text(_resetting ? 'Reseteando...' : 'Reset tabla'),
              ),
              if (_orderInfo != null &&
                  (_orderInfo!['familia']?.toString().toUpperCase().contains(
                            'MANIPULAC',
                          ) ==
                          true &&
                      _orderInfo!['familia']?.toString().toUpperCase().contains(
                            'ETIQUETADO',
                          ) ==
                          true))
                FilledButton.icon(
                  onPressed: _exporting ? null : _exportActa,
                  icon: _exporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf),
                  label: Text(_exporting ? 'Exportando...' : 'Exportar acta'),
                ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green[700],
                ),
                onPressed: _exportingExcel ? null : _exportMatchesToExcel,
                icon: _exportingExcel
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.table_view),
                label: Text(
                  _exportingExcel ? 'Exportando...' : 'Exportar Excel',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Plantillas', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _templatesLoading ? null : _loadTemplates,
                icon: _templatesLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(_templatesLoading ? 'Cargando...' : 'Refrescar'),
              ),
              FilledButton.icon(
                onPressed: _templateUploading ? null : _uploadTemplate,
                icon: _templateUploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload),
                label: Text(
                  _templateUploading ? 'Subiendo...' : 'Añadir plantilla',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_templates.isEmpty)
            const Text('No hay plantillas registradas aún.')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _templates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final item = _templates[index];
                final size = item['size'];
                final modified = item['modified'];
                return ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(item['filename']?.toString() ?? '-'),
                  subtitle: Text(
                    '${size ?? '—'} bytes • ${modified ?? 'sin fecha'}',
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRecentTab() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: _loadingRecent
          ? const Center(child: CircularProgressIndicator())
          : _recent.isEmpty
          ? const Center(child: Text('No hay asignaciones recientes.'))
          : ListView.separated(
              itemCount: _recent.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final row = _recent[index];
                return ListTile(
                  title: Text(
                    row['inventory_code'] ?? '-',
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: Text(row['serial'] ?? '-'),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _activePanels.map((panel) {
      switch (panel) {
        case _SerialPanel.assign:
          return const Tab(icon: Icon(Icons.qr_code), text: 'Serial');
        case _SerialPanel.match:
          return const Tab(icon: Icon(Icons.link), text: 'Match');
        case _SerialPanel.upload:
          return const Tab(icon: Icon(Icons.upload_file), text: 'Carga');
        case _SerialPanel.recent:
          return const Tab(icon: Icon(Icons.history), text: 'Recientes');
      }
    }).toList();

    final views = _activePanels.map((panel) {
      switch (panel) {
        case _SerialPanel.assign:
          return _buildAssignTab();
        case _SerialPanel.match:
          return _buildMatchTab();
        case _SerialPanel.upload:
          return _buildUploadTab();
        case _SerialPanel.recent:
          return _buildRecentTab();
      }
    }).toList();

    if (widget.matchOnly) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.isEmbedded)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary.withOpacity(0.16),
                      Colors.transparent,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(0.2),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Manipulacion y Etiquetado',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_sequenceQueue.isNotEmpty)
                          Chip(
                            avatar: const Icon(
                              Icons.auto_fix_high,
                              size: 14,
                              color: Colors.cyanAccent,
                            ),
                            label: Text(
                              'SEQ: ${_sequenceQueue.length}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.cyanAccent,
                              ),
                            ),
                            backgroundColor: Colors.cyanAccent.withOpacity(0.1),
                            onDeleted: () =>
                                setState(() => _sequenceQueue.clear()),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Modo Match directo para esta orden',
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            Expanded(child: views.first),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          leading: const EdgeNavHandle(),
          title: const Text('VINCULAR SERIAL (MATCH)'),
          actions: [
            if (_sequenceQueue.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Chip(
                  avatar: const Icon(
                    Icons.auto_fix_high,
                    size: 14,
                    color: Colors.cyanAccent,
                  ),
                  label: Text(
                    'SEQ: ${_sequenceQueue.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.cyanAccent,
                    ),
                  ),
                  backgroundColor: Colors.cyanAccent.withOpacity(0.1),
                  onDeleted: () => setState(() => _sequenceQueue.clear()),
                ),
              ),
          ],
          bottom: TabBar(controller: _tabs, tabs: tabs, isScrollable: true),
        ),
        body: TabBarView(controller: _tabs, children: views),
      ),
    );
  }
}

class _ManualOrderPromptResult {
  const _ManualOrderPromptResult({
    required this.unitsText,
    required this.doubleEntry,
    this.sequence,
  });

  final String unitsText;
  final bool doubleEntry;
  final List<String>? sequence;
}

class _ManualUnitsDialog extends StatefulWidget {
  const _ManualUnitsDialog({required this.numOrden});

  final String numOrden;

  @override
  State<_ManualUnitsDialog> createState() => _ManualUnitsDialogState();
}

class _ManualUnitsDialogState extends State<_ManualUnitsDialog> {
  late final TextEditingController _ctrl;
  bool _doubleEntry = false;
  List<String>? _sequence;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      _ManualOrderPromptResult(
        unitsText: _ctrl.text.trim(),
        doubleEntry: _doubleEntry,
        sequence: _sequence,
      ),
    );
  }

  Future<void> _configureSequence() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) =>
          _SequenceSetupDialog(targetCount: int.tryParse(_ctrl.text) ?? 0),
    );
    if (result != null) {
      setState(() {
        _sequence = result;
        _doubleEntry = true; // Auto-enable double if sequence is set
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Orden no encontrada'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Introduce el número de unidades para la orden ${widget.numOrden}.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Número de unidades'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Text('Tipo de registro'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Unitario'),
                selected: !_doubleEntry,
                onSelected: (_) => setState(() => _doubleEntry = false),
              ),
              ChoiceChip(
                label: const Text('Doble'),
                selected: _doubleEntry,
                onSelected: (_) => setState(() => _doubleEntry = true),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _doubleEntry
                ? 'Captura Serial y Inventario/IMEI'
                : 'Solo Serial (S/N)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_doubleEntry) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _configureSequence,
                icon: Icon(
                  _sequence != null ? Icons.check_circle : Icons.auto_fix_high,
                ),
                label: Text(
                  _sequence != null
                      ? 'Secuencia activa (${_sequence!.length})'
                      : 'Configurar secuencia automática',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _sequence != null
                      ? Colors.greenAccent
                      : Colors.cyanAccent,
                  side: BorderSide(
                    color: _sequence != null
                        ? Colors.greenAccent
                        : Colors.cyanAccent,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Confirmar')),
      ],
    );
  }
}

class _MatchRow {
  _MatchRow();

  final TextEditingController serial = TextEditingController();
  final TextEditingController inventory = TextEditingController();
  final FocusNode focus = FocusNode();
  final FocusNode inventoryFocus = FocusNode();
  bool disposed = false;
  int generation = 0;
  bool isSaving = false;

  void dispose() {
    if (disposed) return;
    disposed = true;
    serial.dispose();
    inventory.dispose();
    focus.dispose();
    inventoryFocus.dispose();
  }
}

enum _SequenceSegmentType { static, numeric }

class _SequenceSegment {
  _SequenceSegment({
    this.type = _SequenceSegmentType.static,
    this.staticValue = '',
    this.start = 1,
    this.end = 10,
    this.padding = 0,
  });

  _SequenceSegmentType type;
  String staticValue;
  int start;
  int end;
  int padding;

  int get count =>
      type == _SequenceSegmentType.numeric ? (end - start).abs() + 1 : 1;
}

class _SequenceSetupDialog extends StatefulWidget {
  const _SequenceSetupDialog({required this.targetCount});
  final int targetCount;

  @override
  State<_SequenceSetupDialog> createState() => _SequenceSetupDialogState();
}

class _SequenceSetupDialogState extends State<_SequenceSetupDialog> {
  final List<_SequenceSegment> _segments = [
    _SequenceSegment(type: _SequenceSegmentType.static, staticValue: 'HZ'),
    _SequenceSegment(
      type: _SequenceSegmentType.numeric,
      start: 1,
      end: 10,
      padding: 1,
    ),
  ];

  List<String> _generate() {
    int maxCount = 0;
    for (var s in _segments) {
      if (s.type == _SequenceSegmentType.numeric) {
        if (s.count > maxCount) maxCount = s.count;
      }
    }
    if (maxCount == 0)
      maxCount = widget.targetCount > 0 ? widget.targetCount : 1;
    if (maxCount > 5000) maxCount = 5000;

    List<String> results = [];
    for (int i = 0; i < maxCount; i++) {
      String code = '';
      for (var s in _segments) {
        if (s.type == _SequenceSegmentType.static) {
          code += s.staticValue;
        } else {
          int val = s.start < s.end ? s.start + i : s.start - i;
          String sVal = val.toString();
          if (s.padding > sVal.length) {
            sVal = sVal.padLeft(s.padding, '0');
          }
          code += sVal;
        }
      }
      results.add(code);
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final preview = _generate();

    return AlertDialog(
      title: const Text('Configurar Secuencia'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Define los segmentos de la secuencia (ej: HZ + 1-1000 + GW)',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _segments.length,
                itemBuilder: (ctx, index) {
                  final s = _segments[index];
                  return Card(
                    color: Colors.white.withOpacity(0.05),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          DropdownButton<_SequenceSegmentType>(
                            value: s.type,
                            onChanged: (v) => setState(() => s.type = v!),
                            items: const [
                              DropdownMenuItem(
                                value: _SequenceSegmentType.static,
                                child: Text('Estatico'),
                              ),
                              DropdownMenuItem(
                                value: _SequenceSegmentType.numeric,
                                child: Text('Número'),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          if (s.type == _SequenceSegmentType.static)
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  hintText: 'Texto ej: HZ',
                                ),
                                onChanged: (v) =>
                                    setState(() => s.staticValue = v),
                                controller:
                                    TextEditingController(text: s.staticValue)
                                      ..selection = TextSelection.collapsed(
                                        offset: s.staticValue.length,
                                      ),
                              ),
                            )
                          else ...[
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Inicio',
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => setState(
                                  () => s.start = int.tryParse(v) ?? 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text('-'),
                            const SizedBox(width: 4),
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Fin',
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => setState(
                                  () => s.end = int.tryParse(v) ?? 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 60,
                              child: TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Dígitos',
                                ),
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 12),
                                onChanged: (v) => setState(
                                  () => s.padding = int.tryParse(v) ?? 0,
                                ),
                              ),
                            ),
                          ],
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _segments.removeAt(index)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _segments.add(_SequenceSegment())),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Agregar segmento'),
            ),
            const Divider(height: 32),
            const Text(
              'VISTA PREVIA (Primeros 5):',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: preview
                  .take(5)
                  .map(
                    (e) => Chip(
                      label: Text(e, style: const TextStyle(fontSize: 10)),
                    ),
                  )
                  .toList(),
            ),
            if (preview.length > 5)
              const Text('...', style: TextStyle(color: Colors.white24)),
            const SizedBox(height: 8),
            Text(
              'Se generarán ${preview.length} códigos.',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.cyanAccent,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _generate()),
          child: const Text('USAR SECUENCIA'),
        ),
      ],
    );
  }
}
