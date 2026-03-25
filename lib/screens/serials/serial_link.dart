import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api_client.dart';
import '../../services/api_service.dart';
import '../../services/order_input_formatter.dart';
import '../../services/orderops_service.dart';
import '../../widgets/main_sidebar.dart';

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

  @override
  void dispose() {
    _edgeOverlay?.remove();
    _edgeOverlay = null;
    _tabs.dispose();
    _serialCtrl.dispose();
    _serialFocus.dispose();
    _orderCtrl.dispose();
    _orderFocus.dispose();
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

  String _normalizeOrder(String raw) => OrderInputFormatter.normalize(raw.trim());

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
      _showSnack('Match completado, pero no hay id de orden para adjuntar en Archivos');
      return;
    }
    final client = _clientOrNull();
    if (client == null) {
      _showSnack('Match completado, pero no hay servicio API para adjuntar Excel');
      return;
    }

    setState(() => _exportingExcel = true);
    try {
      final res = await client.getBytes(
        '$_basePath/matches/export?num_orden=${Uri.encodeQueryComponent(numOrden)}',
      );
      if (!mounted) return;
      if (!res.ok || res.body is! List<int>) {
        _showSnack('Match completado, pero no se pudo generar Excel (${res.statusCode})');
        return;
      }

      final headers = res.headers ?? const {};
      final defaultName = 'serial_matches_${numOrden.replaceAll('-', '')}.xlsx';
      final fileName = _filenameFromHeaders(headers) ?? defaultName;

      final uploaded = await OrderOpsService(client).uploadPhoto(
        orderId,
        fileName,
        res.body as List<int>,
      );
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
        (s) => (s['inventory_code'] ?? s['inventory'] ?? '').toString().trim().isNotEmpty,
      );
      _applyOrderData(
        order: Map<String, dynamic>.from(orderMap),
        serials: serials,
        manualDouble: (orderMap['manual_double'] == true) || hasInventoryCodes,
      );
    } catch (e) {
      _showSnack('Error refrescando orden: $e');
    } finally {
      if (mounted) setState(() => _loadingOrder = false);
    }
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
    });
    

    _disposeRowsLater(removed);

    if (_matchRows.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _matchRows.isEmpty) return;
        _matchRows.first.focus.requestFocus();
      });
    }
  }

  ({int units, bool doubleEntry})? _existingManualConfig(String numOrden) {
    if (_orderInfo == null) return null;
    if (_orderInfo!['manual'] != true) return null;
    if (_orderInfo!['num_orden']?.toString() != numOrden) return null;
    final Object? unitsValue = _orderInfo!['unidades'];
    final int? parsedUnits = unitsValue is int
        ? unitsValue
        : int.tryParse(unitsValue?.toString() ?? '');
    if (parsedUnits == null || parsedUnits <= 0) return null;
    final bool doubleEntry = _orderInfo!['manual_double'] == true;
    return (units: parsedUnits, doubleEntry: doubleEntry);
  }

  bool get _isManualDouble => _orderInfo?['manual_double'] == true;

  Future<({int units, bool doubleEntry})?> _promptManualUnits(
    String numOrden,
  ) async {
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
    return (units: parsed, doubleEntry: result.doubleEntry);
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
        final isEmbeddedMatchFlow = widget.matchOnly || widget.isEmbedded || _tabs.index == 1;
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
              _showSnack('No se pudo registrar la orden (${regRes.statusCode})');
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
              manualDouble: manualConfig.doubleEntry || (orderMap['manual_double'] == true),
            );
          } catch (e) {
            _showSnack('Error registrando orden: $e');
          }
          return;
        }
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
        }
        return;
      }
      if (!res.ok || res.body is! Map) {
        // TRICK: If the server returns a 500 but it's clearly a missing order
        // (common in dev/staging environments with complex SQL triggers),
        // we still allow the manual registration prompt if we are in one of the match flows.
        final isEmbeddedMatchFlow = widget.matchOnly || widget.isEmbedded || _tabs.index == 1;

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
              _showSnack('No se pudo registrar la orden (${regRes.statusCode})');
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
              manualDouble: manualConfig.doubleEntry || (orderMap['manual_double'] == true) || serials.any((s) => (s['inventory_code'] ?? s['inventory'] ?? '').toString().trim().isNotEmpty),
            );
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
        (s) => (s['inventory_code'] ?? s['inventory'] ?? '').toString().trim().isNotEmpty,
      );
      _applyOrderData(
        order: order,
        serials: serials,
        manualDouble: (order['manual_double'] == true) || hasInventoryCodes,
      );
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

  bool _allRowsFilled() {
    if (_matchRows.isEmpty) return false;
    final manualDouble = _isManualDouble;
    return _matchRows.every((row) {
      final serialFilled = row.serial.text.trim().isNotEmpty;
      final inventoryFilled =
          !manualDouble || row.inventory.text.trim().isNotEmpty;
      return serialFilled && inventoryFilled;
    });
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

  Future<bool> _saveRow(int index) async {
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
    setState(() => _savingRows = true);
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
        row.serial.clear();
        row.inventory.clear();
        return true;
      }
      if (res.statusCode == 409) {
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
      _showSnack('Error guardando: $e');
      return false;
    } finally {
      if (mounted) setState(() => _savingRows = false);
    }
  }

  Future<void> _saveAllRows() async {
    if (_orderInfo == null) return;
    final initialPendingRows = _matchRows.length;
    if (!_allRowsFilled()) {
      final remaining = _matchRows
          .where((row) => row.serial.text.trim().isEmpty)
          .length;
      _showSnack(
        remaining == 1
            ? 'Falta un serial por rellenar'
            : 'Faltan $remaining seriales por rellenar',
      );
      return;
    }
    _validateRows();
    if (_duplicateRows.isNotEmpty) {
      _showSnack('Elimina los seriales duplicados antes de guardar');
      return;
    }
    int saved = 0;
    final completedOrder = _normalizeOrder(
      _orderInfo?['num_orden']?.toString() ?? _orderCtrl.text,
    );
    for (var i = 0; i < _matchRows.length; i++) {
      final ok = await _saveRow(i);
      if (ok) saved++;
    }
    if (!mounted) return;
    _showSnack('Guardados: $saved');
    if (_orderInfo?['manual'] == true) {
      final removed = _resizeMatchRows(0);
      _orderCtrl.clear();
      setState(() {
        _orderInfo = null;
        _orderSerials = [];
        _duplicateRows.clear();
      });
      _disposeRowsLater(removed);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _orderFocus.requestFocus();
        }
      });
      return;
    }

    final allPendingSaved = initialPendingRows > 0 && saved == initialPendingRows;
    if (allPendingSaved) {
      await _completeOrderAndAttach(completedOrder);
      return;
    }

    await _refreshOrderAfterSave(completedOrder);
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
            onSubmitted: (_) => Navigator.of(ctx).pop(_normalizeOrder(ctrl.text)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(_normalizeOrder(ctrl.text)),
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
      final res = await client.getBytes('/docgen/order/$num/pdf');
      if (!mounted) return;
      if (!res.ok || res.body is! List<int>) {
        _showSnack('No se pudo exportar (${res.statusCode})');
        return;
      }
      final headers = res.headers ?? const {};
      final suggested = _filenameFromHeaders(headers) ?? _defaultActaName(num);
      final ext = suggested.toLowerCase().endsWith('.docx') ? 'docx' : 'pdf';
      final path = await FilePicker.platform.saveFile(
        fileName: suggested,
        type: FileType.custom,
        allowedExtensions: [ext],
        dialogTitle: 'Guardar acta',
      );
      if (path == null) {
        _showSnack('Descarga cancelada');
        return;
      }
      final file = File(path);
      await file.writeAsBytes(res.body as List<int>, flush: true);
      _showSnack('Archivo guardado en $path');
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
            onSubmitted: (_) => Navigator.of(ctx).pop(_normalizeOrder(ctrl.text)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(_normalizeOrder(ctrl.text)),
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
      final headers = res.headers ?? const {};
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
    final manualDouble = _isManualDouble;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Match unidad / orden', style: theme.textTheme.titleLarge),
          // (manualDouble state not shown in UI)
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _orderCtrl,
                  focusNode: _orderFocus,
                  decoration: const InputDecoration(
                    labelText: 'Número de orden',
                    hintText: 'XX-XXXXX-XX',
                  ),
                  inputFormatters: [OrderInputFormatter()],
                  onSubmitted: (_) => _fetchOrder(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _loadingOrder ? null : _fetchOrder,
                icon: _loadingOrder
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_loadingOrder ? 'Buscando...' : 'Buscar'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_orderInfo != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SwitchListTile(
                title: const Text('Modo Registro Doble (Serial + Código)'),
                subtitle: const Text('Habilitar para escanear dos campos por unidad'),
                value: _isManualDouble,
                activeColor: theme.colorScheme.primary,
                onChanged: (val) {
                  setState(() {
                    _orderInfo!['manual_double'] = val;
                  });
                },
              ),
            ),
          const SizedBox(height: 8),
          if (_orderInfo != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Orden ${_orderInfo!['num_orden'] ?? '-'}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Unidades esperadas: ${_orderInfo!['unidades'] ?? '-'}',
                    ),
                    if (_orderInfo?['manual'] == true) ...[
                      const SizedBox(height: 8),
                      Chip(
                        label: const Text('Orden manual'),
                        avatar: const Icon(Icons.edit, size: 16),
                        backgroundColor: theme.colorScheme.secondaryContainer,
                      ),
                    ],
                    if (_orderSerials.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Seriales registrados',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _orderSerials.length,
                        itemBuilder: (_, index) {
                          final row = _orderSerials[index];
                          return ListTile(
                            dense: true,
                            title: Text(row['serial'] ?? '-'),
                            subtitle: Text(row['inventory_code'] ?? '-'),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Añadir seriales pendientes',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (_matchRows.isEmpty)
              const Text('No hay unidades pendientes.')
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _matchRows.length,
                itemBuilder: (_, index) {
                  final row = _matchRows[index];
                  return Padding(
                    key: ValueKey(row),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: row.serial,
                            focusNode: row.focus,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Serial ${index + 1}',
                              errorText: _duplicateRows.contains(index)
                                  ? 'Duplicado'
                                  : null,
                            ),
                            onChanged: (_) => _validateRows(),
                            onSubmitted: (_) {
                              if (manualDouble) {
                                row.inventoryFocus.requestFocus();
                              } else {
                                _lookupInventory(index);
                                if (index + 1 < _matchRows.length) {
                                  _matchRows[index + 1].focus.requestFocus();
                                }
                              }
                            },
                            onEditingComplete: () {
                              // Ensure Tab/Enter both move focus correctly
                              if (manualDouble) {
                                row.inventoryFocus.requestFocus();
                              } else {
                                if (index + 1 < _matchRows.length) {
                                  _matchRows[index + 1].focus.requestFocus();
                                } else {
                                  FocusScope.of(context).nextFocus();
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 160,
                          child: TextField(
                            controller: row.inventory,
                            focusNode: row.inventoryFocus,
                            readOnly: !manualDouble,
                            enabled: manualDouble,
                            decoration: const InputDecoration(
                              labelText: 'Inventario/IMEI',
                            ),
                            textInputAction: manualDouble
                                ? TextInputAction.next
                                : TextInputAction.none,
                            onSubmitted: manualDouble
                                ? (_) {
                                    if (index + 1 < _matchRows.length) {
                                      _matchRows[index + 1].focus
                                          .requestFocus();
                                    } else {
                                      FocusScope.of(context).unfocus();
                                    }
                                  }
                                : null,
                            onEditingComplete: manualDouble
                                ? () {
                                    if (index + 1 < _matchRows.length) {
                                      _matchRows[index + 1].focus.requestFocus();
                                    } else {
                                      FocusScope.of(context).unfocus();
                                    }
                                  }
                                : null,
                          ),
                        ),
                        IconButton(
                          tooltip: manualDouble
                              ? 'Inventario manual'
                              : 'Buscar etiqueta',
                          onPressed: manualDouble
                              ? null
                              : () => _lookupInventory(index),
                          icon: const Icon(Icons.search),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _savingRows ? null : _saveAllRows,
                  icon: _savingRows
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_alt),
                  label: Text(_savingRows ? 'Guardando...' : 'Guardar todo'),
                ),
                const SizedBox(width: 12),
                Text(
                  '${_matchRows.length - _duplicateRows.length} / ${_matchRows.length} sin duplicados',
                ),
              ],
            ),
          ] else if (!_loadingOrder) ...[
            const Text('Busca una orden para mostrar los seriales pendientes.'),
          ],
        ],
      ),
    );
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
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manipulacion y Etiquetado',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
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
          title: const Text('Seriales'),
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
  });

  final String unitsText;
  final bool doubleEntry;
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
      ),
    );
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

  void dispose() {
    if (disposed) return;
    disposed = true;
    serial.dispose();
    inventory.dispose();
    focus.dispose();
    inventoryFocus.dispose();
  }
}
