import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';

import '../../api_client.dart';
import '../../services/api_service.dart';
import '../../services/local_label_generator.dart';
import '../../services/order_input_formatter.dart';
import '../../services/mask_service.dart';
import '../../services/sound_player.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';

// NOTE: This file contains many awaited dialogs and uses of BuildContext after
// async gaps. The code attempts to guard uses with `if (!mounted) return;` and
// captures Navigator/ScaffoldMessenger where appropriate. Temporarily ignore the
// lint to avoid noisy warnings during iterative development.
// ignore_for_file: use_build_context_synchronously

class SerialChangeScreen extends StatefulWidget {
  final String? initialOrderNumber;

  const SerialChangeScreen({super.key, this.initialOrderNumber});

  @override
  State<SerialChangeScreen> createState() => _SerialChangeScreenState();
}

class _SerialChangeScreenState extends State<SerialChangeScreen> {
  final _generalFormKey = GlobalKey<FormState>();
  final _boxFormKey = GlobalKey<FormState>();

  final TextEditingController _orderController = TextEditingController();
  final TextEditingController _skuController = TextEditingController();
  final TextEditingController _unitsController = TextEditingController();
  final TextEditingController _startSeqController = TextEditingController(
    text: '1',
  );
  final TextEditingController _boxNumberController = TextEditingController();
  final TextEditingController _boxUnitsController = TextEditingController();
  // Whether this entry has been persisted to the server already
  // (moved to each entry) whether a specific S/N has been persisted to the server

  // Search controller used to filter label types in the UI
  final TextEditingController _typeSearchController = TextEditingController();
  String _typeSearch = '';

  DateTime _productionDate = DateTime.now();
  bool _continueSequence = false;
  bool _configLocked = false;

  // Focus nodes to support scanner/tab flow
  final FocusNode _orderFocus = FocusNode();
  final FocusNode _boxNumberFocus = FocusNode();
  final FocusNode _boxUnitsFocus = FocusNode();
  // Timer for active box stopwatch
  Timer? _boxTimer;
  Duration _boxElapsed = Duration.zero;

  bool _operatorsLoading = false;
  bool _typesLoading = false;
  bool _generatingLabels = false;
  bool _registeringBox = false;
  bool _checkingOrder = false;
  bool _isShowingPrinterDialog = false;

  List<LabelOperatorOption> _operators = const [];
  LabelOperatorOption? _selectedOperator;
  List<LabelTypeOption> _labelTypes = const [];
  LabelTypeOption? _selectedType;

  String? _operatorsError;
  String? _typesError;
  String? _generationError;
  String? _boxError;
  String? _completionMessage;

  List<String> _pendingLabels = const [];
  final List<String> _consumedLabels = [];
  _BoxSession? _activeBox;
  final List<BoxHistoryEntry> _history = [];
  // Collected mapping pairs across boxes (old -> new) for final label printing
  // Keep mappings with optional backend id so we can edit later
  final List<Map<String, dynamic>> _registeredMappings = [];
  String? _ean;
  int? _originalSerialMaskLength;
  Map<String, dynamic>? _cachedPrinter;

  String _normalizedInitialOrder() {
    final initial = widget.initialOrderNumber?.trim() ?? '';
    if (initial.isEmpty) return '';
    final normalized = initial.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    if (normalized.length == 9) {
      return '${normalized.substring(0, 2)}-${normalized.substring(2, 7)}-${normalized.substring(7, 9)}';
    }
    return initial.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initialOrder = _normalizedInitialOrder();
      if (initialOrder.isNotEmpty) {
        _orderController.text = initialOrder;
      }
      await _loadOperators();
      if (initialOrder.isNotEmpty && !_configLocked) {
        await _triggerOrderResumeSearch(order: initialOrder);
      }
      // Ensure focus on order field if it's empty, or on box number if order is set
      if (initialOrder.isEmpty) {
        _orderFocus.requestFocus();
      } else if (!_configLocked) {
        _boxNumberFocus.requestFocus();
      }
    });
  }

  Future<void> _confirmAndStartBox() async {
    // Validate form first
    if (!_boxFormKey.currentState!.validate()) return;
    await _startBox();
  }

  Future<void> _triggerOrderResumeSearch({String? order}) async {
    if (_configLocked || _checkingOrder) return;
    setState(() => _checkingOrder = true);
    try {
      await _checkOrderResume(order);
    } finally {
      if (mounted) {
        setState(() => _checkingOrder = false);
      }
    }
  }

  @override
  void dispose() {
    _orderController.dispose();
    _skuController.dispose();
    _unitsController.dispose();
    _startSeqController.dispose();
    _boxNumberController.dispose();
    _boxUnitsController.dispose();
    _orderFocus.dispose();
    _boxNumberFocus.dispose();
    _boxUnitsFocus.dispose();
    _typeSearchController.dispose();
    _boxTimer?.cancel();
    _activeBox?.dispose();
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

  Future<void> _loadOperators() async {
    final client = _clientOrNull();
    if (client == null) {
      setState(() => _operatorsError = 'Servicio API no disponible');
      return;
    }
    setState(() {
      _operatorsLoading = true;
      _operatorsError = null;
    });
    try {
      final res = await client.get('/serials/labels/operators');
      if (!mounted) return;
      if (res.ok) {
        final list = _extractList(res.body)
            .whereType<Map>()
            .map(LabelOperatorOption.fromJson)
            .where((op) => op.name.isNotEmpty)
            .toList();
        setState(() {
          _operators = list;
          if (list.isNotEmpty) {
            if (_selectedOperator == null) {
              _selectedOperator = list.first;
            } else {
              _selectedOperator = list.firstWhere(
                (op) =>
                    op.name.toLowerCase() ==
                    _selectedOperator!.name.toLowerCase(),
                orElse: () => list.first,
              );
            }
          } else {
            _selectedOperator = null;
          }
        });
        if (_selectedOperator != null) {
          await _loadTypesForOperator(_selectedOperator!);
        }
      } else {
        setState(
          () => _operatorsError =
              'No se pudieron cargar los operadores (${res.statusCode}).',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _operatorsError = 'Error cargando operadores: $e');
      }
    } finally {
      if (mounted) setState(() => _operatorsLoading = false);
    }
  }

  Future<List<LabelTypeOption>> _fetchTypes(String operatorName) async {
    final client = _clientOrNull();
    if (client == null) return [];
    try {
      final encoded = Uri.encodeQueryComponent(operatorName);
      final res = await client.get('/serials/labels/types?operador=$encoded');
      if (res.ok) {
        return _extractList(res.body)
            .whereType<Map>()
            .map(LabelTypeOption.fromJson)
            .where((item) => item.id != null)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _loadTypesForOperator(LabelOperatorOption operatorOption) async {
    final client = _clientOrNull();
    if (client == null) {
      setState(() {
        _typesError = 'Servicio API no disponible';
        _labelTypes = const [];
        _selectedType = null;
      });
      return;
    }
    setState(() {
      _typesLoading = true;
      _typesError = null;
      _labelTypes = const [];
      _selectedType = null;
    });
    try {
      final parsed = await _fetchTypes(operatorOption.name);
      if (!mounted) return;
      setState(() {
        _labelTypes = parsed;
        _selectedType = parsed.isNotEmpty ? parsed.first : null;
      });
    } catch (e) {
      if (mounted) setState(() => _typesError = 'Error obteniendo tipos: $e');
    } finally {
      if (mounted) setState(() => _typesLoading = false);
    }
  }

  List<dynamic> _extractList(dynamic body) {
    if (body is List) return body;
    if (body is Map && body['results'] is List) return body['results'] as List;
    return const [];
  }

  String? _boxFromRecord(Map<String, dynamic> record) {
    final raw = record['nr_box'] ?? record['nrCaja'] ?? record['box'];
    final text = raw?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  int? _boxUnitsFromRecord(Map<String, dynamic> record) {
    final raw =
        record['nr_unidades_box'] ?? record['nr_unidades'] ?? record['units'];
    final units = int.tryParse(raw?.toString() ?? '');
    return (units != null && units > 0) ? units : null;
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    try {
      final text = raw.toString();
      final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
      if (match != null) {
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        return DateTime(year, month, day);
      }
      final parsed = DateTime.parse(text);
      return DateTime(parsed.year, parsed.month, parsed.day);
    } catch (_) {
      return null;
    }
  }

  DateTime? _extractDateFromSerial(String? serial) {
    if (serial == null || serial.length < 8) return null;
    // Check if starts with YYYYMMDD
    final match = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(serial);
    if (match != null) {
      try {
        final y = int.parse(match.group(1)!);
        final m = int.parse(match.group(2)!);
        final d = int.parse(match.group(3)!);
        // Basic validation
        if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          return DateTime(y, m, d);
        }
      } catch (_) {}
    }
    return null;
  }

  DateTime? _recordDate(Map<String, dynamic> record) {
    final raw =
        record['fecha_finalizacion'] ??
        record['fecha'] ??
        record['fecha_creacion'] ??
        record['created_at'] ??
        record['createdAt'];
    return _parseDate(raw);
  }

  DateTime? _getProductionDate(Map<String, dynamic> record) {
    // 1. Try to extract from the label string itself (most reliable for "same label date")
    final sn =
        (record['serial_new'] ??
                record['serial_new_label'] ??
                record['label_new'])
            ?.toString();
    final fromSerial = _extractDateFromSerial(sn);
    if (fromSerial != null) return fromSerial;

    // 2. Try the explicit 'fecha' field (production date)
    final fromFecha = _parseDate(record['fecha']);
    if (fromFecha != null) return fromFecha;

    // 3. Fallback to record creation/scan date
    return _recordDate(record);
  }

  DateTime? _latestProductionDate(List<Map<String, dynamic>> records) {
    DateTime? latest;
    for (final record in records) {
      final date = _getProductionDate(record);
      if (date == null) continue;
      // We want the LATEST date found (assuming user wants to match the most recent batch)
      // Or do we want the common date? Usually for Resume, if they are all from same order,
      // they should have same date. If mixed, taking latest is safer than earliest?
      // Actually, if we are resuming an order from yesterday, and we find records from yesterday,
      // we want yesterday. If we find records from TODAY (which shouldn't happen unless we already started today),
      // then likely we continue with today.
      if (latest == null || date.isAfter(latest)) {
        latest = date;
      }
    }
    return latest;
  }

  Map<String, dynamic> _pickLastBoxInfo(List<Map<String, dynamic>> records) {
    String? lastBox;
    DateTime? lastDate;
    int? lastId;

    for (final record in records) {
      final box = _boxFromRecord(record);
      if (box == null) continue;

      final date = _recordDate(record);
      final id = int.tryParse(record['id']?.toString() ?? '');

      final isLater = () {
        if (date != null) {
          if (lastDate == null) return true;
          return date.isAfter(lastDate);
        }
        if (lastDate == null && id != null) {
          if (lastId == null) return true;
          return id > lastId;
        }
        return false;
      }();

      if (isLater) {
        lastBox = box;
        lastDate = date ?? lastDate;
        lastId = id ?? lastId;
      }
    }

    int? lastUnits;
    if (lastBox != null) {
      for (final record in records) {
        final box = _boxFromRecord(record);
        if (box != lastBox) continue;
        lastUnits = _boxUnitsFromRecord(record);
        if (lastUnits != null) break;
      }
    }

    return {'box': lastBox, 'units': lastUnits};
  }

  /// Tries to identify a Vodafone SAP prefix from a serial whose format is
  /// `{sap}{yearDigit}{monthLetter}{day:2}{seq:n}`.  Returns the SAP string
  /// (digits only, length 4–8) if the pattern is recognised, otherwise null.
  String? _inferSapFromSerial(String serial) {
    const vodafoneMonthLetters = {'E', 'F', 'M', 'A', 'Y', 'J', 'L', 'S', 'O', 'N', 'D'};
    for (int sapLen = 4; sapLen <= 8 && sapLen + 4 < serial.length; sapLen++) {
      final sapPart = serial.substring(0, sapLen);
      if (!RegExp(r'^\d+$').hasMatch(sapPart)) break; // SAP must be all digits
      final rest = serial.substring(sapLen);
      if (rest.length < 4) continue;
      final yearChar = rest[0];
      final monthChar = rest[1];
      final dayStr = rest.substring(2, 4);
      if (!RegExp(r'^\d$').hasMatch(yearChar)) continue;
      if (!vodafoneMonthLetters.contains(monthChar)) continue;
      final day = int.tryParse(dayStr);
      if (day == null || day < 1 || day > 31) continue;
      return sapPart;
    }
    return null;
  }

  String? _vodafoneMonthLetter(DateTime date) {
    switch (date.month) {
      case 1:
        return 'E';
      case 2:
        return 'F';
      case 3:
        return 'M';
      case 4:
        return 'A';
      case 5:
        return 'Y';
      case 6:
        return 'J';
      case 7:
        return 'L';
      case 8:
        return 'A';
      case 9:
        return 'S';
      case 10:
        return 'O';
      case 11:
        return 'N';
      case 12:
        return 'D';
    }
    return null;
  }

  Map<String, int?> _sequenceBounds(
    List<Map<String, dynamic>> records, {
    String? operatorName,
    String? sapClient,
  }) {
    int? minSeq;
    int? maxSeq;
    int? minSuffix;
    int? maxSuffix;
    bool foundVodafoneSeq = false;
    final isVodafone =
        operatorName != null &&
        operatorName.trim().toLowerCase().contains('vodafone');
    final sap = sapClient?.trim() ?? '';

    for (final record in records) {
      final seq = int.tryParse(record['inicio']?.toString() ?? '');
      if (!isVodafone && seq != null && seq > 0) {
        if (minSeq == null || seq < minSeq) minSeq = seq;
        if (maxSeq == null || seq > maxSeq) maxSeq = seq;
      }

      final sn =
          (record['serial_new'] ??
                  record['serial_new_label'] ??
                  record['label_new'])
              ?.toString();
      if (sn != null && sn.isNotEmpty) {
        int? extracted;
        if (isVodafone) {
          final d = _getProductionDate(record);
          if (d != null) {
            final yearDigit = d.year % 10;
            final monthLetter = _vodafoneMonthLetter(d);
            final dayText = d.day.toString().padLeft(2, '0');
            if (sap.isNotEmpty && monthLetter != null) {
              final prefix = '$sap$yearDigit$monthLetter$dayText';
              if (sn.startsWith(prefix) && sn.length > prefix.length) {
                final seqPart = sn.substring(prefix.length);
                extracted = int.tryParse(seqPart);
                if (extracted != null && extracted > 0) {
                  foundVodafoneSeq = true;
                }
              }
            }
            if (extracted == null) {
              final trailing = RegExp(r'(\d+)$').firstMatch(sn)?.group(1);
              if (trailing != null && trailing.length > dayText.length) {
                if (trailing.startsWith(dayText)) {
                  final seqPart = trailing.substring(dayText.length);
                  extracted = int.tryParse(seqPart);
                  if (extracted != null && extracted > 0) {
                    foundVodafoneSeq = true;
                  }
                }
              }
            }
          }
        }
        extracted ??= int.tryParse(
          RegExp(r'(\d+)$').firstMatch(sn)?.group(1) ?? '',
        );
        if (extracted != null && extracted > 0) {
          if (minSuffix == null || extracted < minSuffix) {
            minSuffix = extracted;
          }
          if (maxSuffix == null || extracted > maxSuffix) {
            maxSuffix = extracted;
          }
        }
      }
    }

    if (isVodafone &&
        foundVodafoneSeq &&
        (minSuffix != null || maxSuffix != null)) {
      return {'min': minSuffix, 'max': maxSuffix};
    }

    return {'min': minSeq ?? minSuffix, 'max': maxSeq ?? maxSuffix};
  }

  /// Fetch serial-change rows for a given order using a no-limit endpoint when available.
  /// Tries the preferred '/serials/serial-changes-by-order?nr_orden=...' first, then falls
  /// back to '/serials/serial-changes?nr_orden=...' if available. Returns the ApiClient
  /// response object or null on failure.
  Future<dynamic> _fetchSerialChangesByOrder(
    ApiClient client,
    String nr,
  ) async {
    final enc = Uri.encodeQueryComponent(nr);
    final endpoints = [
      '/serials/serial-changes-by-order?nr_orden=$enc',
      '/serials/serial-changes?nr_orden=$enc',
    ];
    for (final ep in endpoints) {
      try {
        final resp = await client.get(ep);
        if (resp.ok) return resp;
        // If resp exists but not ok, continue to next endpoint to allow fallbacks
      } catch (_) {
        // ignore and try next endpoint
      }
    }
    return null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _productionDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _productionDate = picked);
    }
  }

  Future<void> _askEanAndOriginalExample() async {
    final eanCtrl = TextEditingController(text: _ean ?? '');
    final origCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Configuración inicial para registro'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: eanCtrl,
                decoration: const InputDecoration(
                  labelText: 'EAN (para código de barras)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: origCtrl,
                decoration: const InputDecoration(
                  labelText:
                      'Ejemplo S/N original (usa como máscara de longitud)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Omitir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      _ean = eanCtrl.text.trim().isNotEmpty ? eanCtrl.text.trim() : null;
      final example = origCtrl.text.trim();
      _originalSerialMaskLength = example.isNotEmpty ? example.length : null;
    }
    try {
      eanCtrl.dispose();
    } catch (_) {}
    try {
      origCtrl.dispose();
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _fetchPrinters({
    String q = '',
    int limit = 1000,
  }) async {
    final client = _clientOrNull();
    if (client == null) throw Exception('Servicio API no disponible');
    final encoded = Uri.encodeQueryComponent(q.trim());
    final res = await client.get('/serials/printers?q=$encoded&limit=$limit');
    if (!res.ok) throw Exception('Error fetching printers (${res.statusCode})');
    final body = res.body;
    // Normalize several possible backend shapes to a List<Map>
    if (body is List) {
      return body
          .whereType<Map>()
          .map((e) => _normalizePrinterEntry(Map<String, dynamic>.from(e)))
          .toList();
    }

    if (body is Map) {
      // Common patterns: {'results': [...]}, {'printers': [...]}, {'data': [...]}
      for (final key in ['results', 'printers', 'data']) {
        if (body[key] is List) {
          return (body[key] as List)
              .whereType<Map>()
              .map((e) => _normalizePrinterEntry(Map<String, dynamic>.from(e)))
              .toList();
        }
      }

      // As a last resort, if any value is a List, use the first one found.
      for (final v in body.values) {
        if (v is List) {
          return v
              .whereType<Map>()
              .map((e) => _normalizePrinterEntry(Map<String, dynamic>.from(e)))
              .toList();
        }
      }

      // Unexpected shape: log for debug and return empty
      if (kDebugMode) {
        try {
          debugPrint(
            'Unexpected printers response shape: ${body.runtimeType} -> $body',
          );
        } catch (_) {}
      }
    }
    return [];
  }

  Map<String, dynamic> _normalizePrinterEntry(Map<String, dynamic> e) {
    String? id;
    try {
      id = (e['id_printer'] ?? e['id'] ?? e['printer_id'] ?? e['idPrinter'])
          ?.toString();
    } catch (_) {
      id = null;
    }
    String? name;
    try {
      name = (e['printer_name'] ?? e['name'] ?? e['printerName'])?.toString();
    } catch (_) {
      name = null;
    }
    String? ip;
    try {
      ip =
          (e['ip_address'] ??
                  e['ip'] ??
                  e['address'] ??
                  e['ip_address']?.toString())
              ?.toString();
    } catch (_) {
      ip = null;
    }
    final out = <String, dynamic>{};
    if (id != null && id.isNotEmpty) out['id_printer'] = int.tryParse(id) ?? id;
    if (name != null) out['printer_name'] = name;
    if (ip != null) out['ip_address'] = ip;
    // preserve any other keys too
    for (final kv in e.entries) {
      if (!out.containsKey(kv.key)) out[kv.key.toString()] = kv.value;
    }
    return out;
  }

  Future<Map<String, dynamic>?> _getOrSelectPrinter(String title) async {
    if (_cachedPrinter != null) return _cachedPrinter;
    if (_isShowingPrinterDialog) return null; // Avoid concurrent dialogs

    _isShowingPrinterDialog = true;
    try {
      List<Map<String, dynamic>> printers = [];
      try {
        printers = await _fetchPrinters();
      } catch (e) {
        printers = [];
        if (mounted) {
          try {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error obteniendo impresoras: $e')),
            );
          } catch (_) {}
        }
      }

      Map<String, dynamic>? selectedPrinter;
      final txtIp = TextEditingController();

      if (!mounted) return null;

      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (printers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'No se encontraron impresoras en el servidor. Puedes introducir una IP manualmente.',
                    ),
                  )
                else
                  Column(
                    children: printers
                        .map(
                          (p) => RadioListTile<Map<String, dynamic>>(
                            value: p,
                            groupValue: selectedPrinter,
                            title: Text(
                              p['printer_name']?.toString() ??
                                  p['ip_address']?.toString() ??
                                  'Impresora',
                            ),
                            subtitle: Text(p['ip_address']?.toString() ?? ''),
                            onChanged: (v) {
                              selectedPrinter = v;
                              (c as Element).markNeedsBuild();
                            },
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: txtIp,
                  decoration: const InputDecoration(
                    labelText:
                        'IP de impresora (opcional, sobreescribe selección)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );

      final manualIp = txtIp.text.trim().isNotEmpty ? txtIp.text.trim() : null;
      txtIp.dispose();

      if (ok != true) return null;

      final result = <String, dynamic>{};
      if (manualIp != null) {
        result['printer_ip'] = manualIp;
      } else if (selectedPrinter != null) {
        if (selectedPrinter!['id_printer'] != null) {
          result['printer_id'] = selectedPrinter!['id_printer'];
        } else if (selectedPrinter!['ip_address'] != null)
          result['printer_ip'] = selectedPrinter!['ip_address'];
      } else if (printers.isNotEmpty) {
        final first = printers.first;
        if (first['id_printer'] != null) {
          result['printer_id'] = first['id_printer'];
        } else if (first['ip_address'] != null)
          result['printer_ip'] = first['ip_address'];
      } else {
        throw Exception('No printer selected or provided');
      }
      setState(() {
        _cachedPrinter = result;
      });
      return result;
    } finally {
      _isShowingPrinterDialog = false;
    }
  }

  Future<void> _printFinalLabel() async {
    // Capture scaffold messenger before awaiting dialogs to avoid
    // using BuildContext across async gaps. Declare outside the try so it's
    // available in the catch block as well.
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final client = _clientOrNull();
      if (client == null) throw Exception('Servicio API no disponible');

      final payload = await _getOrSelectPrinter(
        'Seleccionar impresora para etiqueta final',
      );
      if (payload == null) return; // cancelled

      payload['data'] = _boxNumberController.text.trim();
      payload['orden'] = _orderController.text.trim();
      payload['total_serials'] = _plannedUnits;
      payload['ean'] = '';

      // Build batches from collected mappings: single batch containing all serials
      final newSerials = _registeredMappings
          .map((m) => m['new'] ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      final oldSerials = _registeredMappings
          .map((m) => m['old'] ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      payload['sn_batches'] = [newSerials];
      payload['serial_batches'] = [oldSerials];
      payload['label_counter'] = 1;

      final res = await client.post(
        '/serials/print-serial-change',
        jsonBody: payload,
      );
      if (!mounted) return;
      if (res.ok) {
        final body = res.body;
        String msg = 'Impresión enviada';
        if (body is Map && body['printed'] != null) {
          msg = 'Impresos: ${body['printed']}';
        }
        scaffoldMessenger.showSnackBar(SnackBar(content: Text(msg)));
      } else {
        final error = res.body is Map
            ? (res.body['error']?.toString() ?? res.error ?? 'Error')
            : (res.error ?? 'Error');
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Error imprimiendo etiqueta final: $error')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _printForBox(
    String boxNumber,
    List<String> newSerials,
    List<String> oldSerials,
    int units,
  ) async {
    try {
      final client = _clientOrNull();
      if (client == null) throw Exception('Servicio API no disponible');

      final payload = await _getOrSelectPrinter(
        'Seleccionar impresora para esta caja',
      );
      if (payload == null) return; // cancelled

      payload['data'] = boxNumber;
      payload['orden'] = _orderController.text.trim();
      payload['total_serials'] = units;
      payload['ean'] = _ean ?? '';
      payload['sn_batches'] = [newSerials];
      payload['serial_batches'] = [oldSerials];
      payload['label_counter'] = 1;

      final res = await client.post(
        '/serials/print-serial-change',
        jsonBody: payload,
      );
      if (!mounted) return;
      if (res.ok) {
        final body = res.body;
        String msg = 'Impresión enviada';
        if (body is Map && body['printed'] != null) {
          msg = 'Impresos: ${body['printed']}';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      } else {
        final error = res.body is Map
            ? (res.body['error']?.toString() ?? res.error ?? 'Error')
            : (res.error ?? 'Error');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error imprimiendo: $error')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error impresión: $e')));
      }
    }
  }

  Future<void> _showEditRegisteredDialog(_BoxEntryField entry) async {
    if (entry.registryId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registro no disponible para edición (sin id).'),
        ),
      );
      return;
    }
    final editCtrl = TextEditingController(text: entry.controller.text.trim());
    final res = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Editar S/N registrado'),
        content: TextField(
          controller: editCtrl,
          decoration: const InputDecoration(labelText: 'S/N original'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final newVal = editCtrl.text.trim();
    try {
      editCtrl.dispose();
    } catch (_) {}
    if (res != true) return;
    if (newVal.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('S/N no puede estar vacío')),
        );
      }
      return;
    }
    try {
      final client = _clientOrNull();
      if (client == null) throw Exception('Servicio API no disponible');
      final id = entry.registryId!;
      final payload = <String, dynamic>{'serial_old': newVal};
      final resp = await client.put(
        '/serials/serial-changes/$id',
        jsonBody: payload,
      );
      if (!mounted) return;
      if (resp.ok) {
        // update local UI and mappings
        final oldVal = entry.controller.text.trim();
        setState(() {
          entry.controller.text = newVal;
        });
        // update registeredMappings where id matches
        for (final m in _registeredMappings) {
          try {
            if (m['id'] != null && (m['id'] as num).toInt() == id) {
              m['old'] = newVal;
            } else if (m['old'] == oldVal && m['id'] == null) {
              // fallback: if mapping has no id but old matches, update it
              m['old'] = newVal;
            }
          } catch (_) {}
        }
        SoundPlayer.playSuccess();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('S/N actualizado')));
      } else {
        final err = resp.body is Map
            ? (resp.body['error']?.toString() ?? resp.error ?? 'Error')
            : (resp.error ?? 'Error');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error actualizando: $err')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error actualizando S/N: $e')));
      }
    }
  }

  int get _plannedUnits => int.tryParse(_unitsController.text.trim()) ?? 0;

  Future<void> _prepareLabels() async {
    if (!_generalFormKey.currentState!.validate()) return;
    if (_selectedOperator == null || _selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona operador y tipo.')),
      );
      return;
    }
    final totalUnits = _plannedUnits;
    if (totalUnits <= 0) {
      setState(() => _generationError = 'Define un número válido de unidades.');
      return;
    }
    // Before generating, check whether this order already has registries on the server.
    // If there are existing registries and they don't complete the planned units,
    // offer to resume/finish the order and load server-side data so the operator can continue.
    try {
      final clientCheck = _clientOrNull();
      if (clientCheck != null) {
        final ord = _orderController.text.trim();
        if (ord.isNotEmpty) {
          // try to fetch existing serial-change records for this order (best-effort)
          // Prefer the no-limit endpoint if available; helper will attempt fallbacks.
          final resp = await _fetchSerialChangesByOrder(clientCheck, ord);
          if (resp.ok) {
            final list = _extractList(resp.body)
                .whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList();
            // Debug: surface server count so we can confirm the resume endpoint returned records
            if (kDebugMode) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Resume check: server returned ${list.length} records',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
            final existing = list.length;
            if (existing > 0 && existing < totalUnits) {
              final resume = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Orden parcialmente registrada'),
                  content: Text(
                    'Se encontraron $existing registros para la orden "$ord" de $totalUnits unidades. ¿Deseas cargar y continuar la orden?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(c).pop(false),
                      child: const Text('No'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(c).pop(true),
                      child: const Text('Sí, continuar'),
                    ),
                  ],
                ),
              );
              if (resume == true) {
                // Best-effort: reconstruct consumed labels and pending labels
                final serverNew = <String>[];
                for (final m in list) {
                  try {
                    final snNew =
                        (m['serial_new'] ??
                                m['serial_new_label'] ??
                                m['label_new'])
                            ?.toString();
                    if (snNew != null && snNew.isNotEmpty) serverNew.add(snNew);
                  } catch (_) {}
                }
                final latestDate = _latestProductionDate(list);
                if (latestDate != null) {
                  _productionDate = latestDate;
                }
                final lastBoxInfo = _pickLastBoxInfo(list);
                final lastBox = lastBoxInfo['box'] as String?;
                final lastBoxUnits = lastBoxInfo['units'] as int?;
                final seqBounds = _sequenceBounds(
                  list,
                  operatorName: _selectedOperator?.name,
                  sapClient: _selectedType?.sapClient,
                );
                final startSequenceForGeneration = seqBounds['min'] ?? 1;
                final lastUsedSeq = seqBounds['max'];
                final recordsInLastBox = lastBox == null
                    ? const <Map<String, dynamic>>[]
                    : list
                          .where(
                            (m) =>
                                (m['nr_box'] ?? m['nrCaja'] ?? m['box'])
                                    ?.toString() ==
                                lastBox,
                          )
                          .toList();
                final registeredInLastBox = recordsInLastBox.length;
                final shouldResume =
                    lastBox != null &&
                    (lastBoxUnits == null ||
                        registeredInLastBox < lastBoxUnits);
                final lastBoxLabels = shouldResume
                    ? recordsInLastBox
                          .map(
                            (m) =>
                                (m['serial_new'] ??
                                        m['serial_new_label'] ??
                                        m['label_new'])
                                    ?.toString(),
                          )
                          .where((s) => s != null && s.isNotEmpty)
                          .cast<String>()
                          .toList()
                    : const <String>[];
                final consumedLabels = shouldResume
                    ? serverNew
                          .where((s) => !lastBoxLabels.contains(s))
                          .toList()
                    : serverNew;
                // Generate labels locally so we can compute pending labels and box labels
                final labels = await Future<List<String>>(
                  () => LocalLabelGenerator.generate(
                    operatorName: _selectedOperator!.name,
                    productionDate: _productionDate,
                    totalUnits: totalUnits,
                    article: _selectedType!.article,
                    sapClient: _selectedType!.sapClient,
                    codeLetter: _selectedType!.codeLetter,
                    startSequence: startSequenceForGeneration,
                  ),
                );
                if (!mounted) return;
                if (lastUsedSeq != null) {
                  _startSeqController.text = (lastUsedSeq + 1).toString();
                  _continueSequence = true;
                }
                // Mark consumed labels and set pending labels
                setState(() {
                  _configLocked = true;
                  _consumedLabels.clear();
                  _consumedLabels.addAll(consumedLabels);
                  _pendingLabels = labels
                      .where((l) => !consumedLabels.contains(l))
                      .toList();
                  _history.clear();
                });

                // If server reports a lastBox value and that box seems incomplete, open it for continuation
                if (lastBox != null) {
                  final lastBoxNumber = lastBox;
                  _boxNumberController.text = lastBoxNumber;
                  if (lastBoxUnits != null) {
                    _boxUnitsController.text = lastBoxUnits.toString();
                  }
                  if (shouldResume) {
                    // Build a new _BoxSession for this box and mark already registered entries
                    final startIndex = labels.indexWhere(
                      (l) => !_consumedLabels.contains(l),
                    );
                    final fallbackUnits = registeredInLastBox > 0
                        ? registeredInLastBox
                        : 1;
                    final boxUnits = lastBoxUnits ?? fallbackUnits;
                    final boxLabels = <String>[];
                    if (startIndex >= 0) {
                      final end = (startIndex + boxUnits) <= labels.length
                          ? (startIndex + boxUnits)
                          : labels.length;
                      boxLabels.addAll(labels.sublist(startIndex, end));
                    } else {
                      // fallback: take next boxUnits from pending labels
                      boxLabels.addAll(_pendingLabels.take(boxUnits));
                    }
                    setState(() {
                      _activeBox?.dispose();
                      _activeBox = _BoxSession(
                        boxNumber: lastBoxNumber,
                        units: boxUnits,
                        labels: boxLabels,
                      );
                      _activeBox!.startTime = DateTime.now();
                      // prefill controllers for entries that are already registered by matching serial_old
                      for (final entry in _activeBox!.entries) {
                        // try to find server record that maps to this label
                        final found = list.firstWhere(
                          (m) =>
                              (m['serial_new']?.toString() ?? '') ==
                              entry.label,
                          orElse: () => {} as Map<String, dynamic>,
                        );
                        if (found.isNotEmpty) {
                          entry.controller.text =
                              (found['serial_old'] ??
                                      found['serial_old_value'] ??
                                      '')
                                  .toString();
                          entry.registered = true;
                          entry.isValid = true;
                          try {
                            entry.registryId = (found['id'] is num)
                                ? (found['id'] as num).toInt()
                                : null;
                          } catch (_) {}
                        }
                      }
                    });
                  }
                }
                // Focus UX: land on first unregistered entry if activeBox is open
                await Future.delayed(const Duration(milliseconds: 120));
                if (!mounted) return;
                if (_activeBox != null) {
                  _BoxEntryField? next;
                  for (final e in _activeBox!.entries) {
                    if (!e.registered) {
                      next = e;
                      break;
                    }
                  }
                  if (next != null) {
                    FocusScope.of(context).requestFocus(next.focusNode);
                  }
                }
                // We finished the resume flow; stop prepareLabels early.
                return;
              }
            }
          }
        }
      }
    } catch (_) {
      // ignore errors from resume-check; proceed with normal generation flow
    }
    setState(() {
      _generatingLabels = true;
      _generationError = null;
      _completionMessage = null;
    });
    try {
      int startSeq = 1;
      if (_continueSequence) {
        final parsed = int.tryParse(_startSeqController.text.trim());
        if (parsed == null || parsed <= 0) {
          setState(() => _generationError = 'Secuencia inicial inválida.');
          return;
        }
        startSeq = parsed;
      }
      // Normalize SKU to uppercase and confirm if it doesn't match expected pattern (XXYYYY)
      final rawSku = _skuController.text.trim();
      final normalizedSku = rawSku.toUpperCase();
      _skuController.text = normalizedSku;
      final bool skuIsOk = (() {
        if (normalizedSku.length != 6) return false;
        int d0 = normalizedSku.codeUnitAt(0);
        int d1 = normalizedSku.codeUnitAt(1);
        if (d0 < 48 || d0 > 57) return false;
        if (d1 < 48 || d1 > 57) return false;
        for (int i = 2; i < 6; i++) {
          final c = normalizedSku.codeUnitAt(i);
          if (c < 65 || c > 90) return false;
        }
        return true;
      })();
      if (!skuIsOk) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('SKU no estándar'),
            content: Text(
              'El SKU "$normalizedSku" no cumple el formato XXYYYY. ¿Deseas continuar de todos modos?',
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
        if (!mounted) return;
        if (proceed != true) return;
      }
      final labels = await Future<List<String>>(
        () => LocalLabelGenerator.generate(
          operatorName: _selectedOperator!.name,
          productionDate: _productionDate,
          totalUnits: totalUnits,
          article: _selectedType!.article,
          sapClient: _selectedType!.sapClient,
          codeLetter: _selectedType!.codeLetter,
          startSequence: startSeq,
        ),
      );
      if (!mounted) return;
      if (labels.length != totalUnits) {
        setState(
          () => _generationError = 'Error generando etiquetas localmente.',
        );
        return;
      }

      // Show a preview dialog with the first generated label so the user sees the format
      final proceedPreview = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final scanCtrl = TextEditingController();
          String scanned = '';
          return StatefulBuilder(
            builder: (ctx, setS) {
              final expected = labels.first.trim();
              final match = scanned.trim() == expected;
              final hasInput = scanned.trim().isNotEmpty;
              return AlertDialog(
                title: const Text('Vista previa de formato'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Este será el formato que se usará:'),
                    const SizedBox(height: 10),
                    SelectableText(
                      expected,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Escanea una etiqueta para verificar:',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: scanCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Escanear aquí...',
                        prefixIcon: const Icon(Icons.qr_code_scanner),
                        suffixIcon: hasInput
                            ? Icon(
                                match ? Icons.check_circle : Icons.cancel,
                                color: match ? Colors.green : Colors.red,
                              )
                            : null,
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: hasInput
                                ? (match ? Colors.green : Colors.red)
                                : Colors.blue,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (v) => setS(() => scanned = v),
                      onSubmitted: (_) {
                        if (match) Navigator.of(ctx).pop(true);
                      },
                    ),
                    if (hasInput) ...[
                      const SizedBox(height: 8),
                      Text(
                        match
                            ? '✓ El formato es correcto'
                            : '✗ No coincide con el formato esperado',
                        style: TextStyle(
                          fontSize: 12,
                          color: match ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Aceptar'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (!mounted) return;
      if (proceedPreview != true) {
        // User cancelled preview; do not lock configuration.
        return;
      }

      setState(() {
        _pendingLabels = labels;
        _configLocked = true;
        _activeBox?.dispose();
        _activeBox = null;
        _history.clear();
        _consumedLabels.clear();
        _boxNumberController.clear();
        _boxUnitsController.clear();
      });
      // Ask for EAN and an example original S/N to derive mask length before starting step 3
      await _askEanAndOriginalExample();

      if (mounted) {
        _boxNumberController.clear();
        _boxUnitsController.clear();
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) _boxNumberFocus.requestFocus();
      }
      // Send generation audit to backend (non-blocking for the user flow)
      try {
        final client2 = _clientOrNull();
        if (client2 != null) {
          final audit = <String, dynamic>{
            'operador': _selectedOperator!.name,
            'tipo_id': _selectedType!.id,
            'nr_unidades': totalUnits,
            'fecha': DateFormat('yyyy-MM-dd').format(_productionDate),
            'inicio': startSeq,
            'nr_orden': _orderController.text.trim(),
            'nr_sku': _skuController.text.trim(),
            'allow_inactive': false,
          };
          final resp = await client2.post(
            '/serials/labels/generate',
            jsonBody: audit,
          );
          if (resp.ok && resp.body is Map) {
            // optional: we could compare returned labels with local ones for debugging
          }
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _generationError = 'Error generando etiquetas: $e');
      }
    } finally {
      if (mounted) setState(() => _generatingLabels = false);
    }
  }

  /// Check server for existing registries for the given order and, if partial
  /// records exist, offer the operator to resume the in-progress box.
  Future<void> _checkOrderResume([String? order]) async {
    final nr = (order ?? _orderController.text).trim();
    if (nr.isEmpty) return;

    final client = _clientOrNull();
    if (client == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servicio API no disponible')),
      );
      return;
    }

    try {
      // Try the no-limit endpoint first; _fetchSerialChangesByOrder handles encoding and fallbacks
      final resp = await _fetchSerialChangesByOrder(client, nr);
      if (resp == null || !resp.ok) return;
      final list = _extractList(resp.body);
      if (list.isEmpty) return; // nothing to resume

      // Extract details from the first record
      final first = list.first as Map;

      final dbUnits =
          int.tryParse((first['nr_unidades'] ?? '').toString()) ?? 0;
      final dbSku = (first['nr_sku'] ?? first['sku'] ?? first['csku'] ?? '')
          .toString();
      final dbTypeId = int.tryParse(
        (first['tipo_etiqueta_id'] ?? '').toString(),
      );
      final dbTypeName = (first['tipo_etiqueta'] ?? '').toString();
      final dbOperator = (first['operador'] ?? '').toString();
      final dbEan = (first['ean'] ?? '').toString();
      // Iterate to find:
      // 1. Last used sequence (to continue from the latest registry)
      // 2. Earliest date (to resume with the original production date)
      // 3. Mask length from the very first registry (lowest ID)
      int? maxStartSeq;
      int? maxSerialSuffix;
      DateTime? minDate;
      int? minIdForMask;
      int? maskLength;

      for (final item in list) {
        final m = item as Map;

        // Sequence
        final seq = int.tryParse((m['inicio'] ?? '').toString());
        if (seq != null && seq > 0) {
          if (maxStartSeq == null || seq > maxStartSeq) {
            maxStartSeq = seq;
          }
        }

        // Date (Production Date)
        final d = _getProductionDate(m.cast<String, dynamic>());
        if (d != null) {
          if (minDate == null || d.isBefore(minDate)) {
            minDate = d;
          }
        }

        // Try to extract sequence from serial_new suffix (always, regardless of inicio)
        final sn = (m['serial_new'] ?? m['serial_new_label'] ?? m['label_new'])
            ?.toString();
        if (sn != null && sn.isNotEmpty) {
          // Look for trailing digits
          final match = RegExp(r'(\d+)$').firstMatch(sn);
          if (match != null) {
            final extracted = int.tryParse(match.group(1)!);
            if (extracted != null && extracted > 0) {
              if (maxSerialSuffix == null || extracted > maxSerialSuffix) {
                maxSerialSuffix = extracted;
              }
            }
          }
        }

        // Mask from first registry (lowest ID)
        final id = int.tryParse((m['id'] ?? '').toString());
        if (id != null) {
          if (minIdForMask == null || id < minIdForMask) {
            minIdForMask = id;
            final old = (m['serial_old'] ?? m['serial_old_value'])?.toString();
            if (old != null && old.isNotEmpty) {
              maskLength = old.length;
            }
          }
        } else if (minIdForMask == null) {
          // Fallback if no ID: just take the first one we see
          final old = (m['serial_old'] ?? m['serial_old_value'])?.toString();
          if (old != null && old.isNotEmpty) {
            maskLength = old.length;
          }
        }
      }

      // Autofill/overwrite units with server value so resume uses server's planned total
      if (dbUnits > 0) {
        _unitsController.text = dbUnits.toString();
      }
      // Autofill SKU if empty
      if (dbSku.isNotEmpty && _skuController.text.trim().isEmpty) {
        _skuController.text = dbSku;
      }

      // Autofill EAN if available (always prefer server value on resume)
      if (dbEan.isNotEmpty) {
        _ean = dbEan;
      }

      // Restore date (earliest)
      if (minDate != null) {
        _productionDate = minDate;
      }

      // Restore mask length (from first registry)
      _originalSerialMaskLength = maskLength;

      final planned = int.tryParse(_unitsController.text.trim()) ?? dbUnits;
      if (planned <= 0) return; // Still no units?

      // Count server records and show a diagnostic so operator knows what was found.
      final existing = list.length;
      try {
        developer.log(
          'Order resume check: order=$nr, planned=$planned, found=$existing, operator=$dbOperator, type=$dbTypeName, ean=$dbEan',
          name: 'SerialChange._checkOrderResume',
        );
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 4),
            content: Text(
              'Orden $nr: encontrados $existing registros (plan: $planned)',
            ),
          ),
        );
      }

      // If server has fewer records than planned, offer to resume
      if (existing >= planned) {
        // already complete or equal; nothing to resume
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                existing > 0
                    ? 'La orden parece completa en el servidor ($existing/$planned).'
                    : 'No se encontraron registros.',
              ),
            ),
          );
        }
        return;
      }

      // Ensure operators are loaded
      if (_operators.isEmpty) {
        await _loadOperators();
      }

      // Attempt to automatically select operator and type
      String? selectionError;
      LabelOperatorOption? foundOp;
      LabelTypeOption? foundType;

      // 1. Try to find operator by name
      if (dbOperator.isNotEmpty) {
        try {
          foundOp = _operators.firstWhere(
            (op) =>
                op.name.trim().toLowerCase() == dbOperator.trim().toLowerCase(),
          );
        } catch (_) {}
      }

      // 2. If operator found, try to find type in that operator
      if (foundOp != null) {
        final types = await _fetchTypes(foundOp.name);
        // Try ID match first
        if (dbTypeId != null) {
          try {
            foundType = types.firstWhere((t) => t.id == dbTypeId);
          } catch (_) {}
        }
        // Try Exact Name match
        if (foundType == null && dbTypeName.isNotEmpty) {
          try {
            foundType = types.firstWhere(
              (t) =>
                  t.displayName.trim().toLowerCase() ==
                  dbTypeName.trim().toLowerCase(),
            );
          } catch (_) {}
        }
        // Try Partial Name match
        if (foundType == null && dbTypeName.isNotEmpty) {
          try {
            foundType = types.firstWhere(
              (t) => t.displayName.trim().toLowerCase().contains(
                dbTypeName.trim().toLowerCase(),
              ),
            );
          } catch (_) {}
        }
      }

      // 3. If operator NOT found (or type not found in that operator), try brute force across all operators
      if (foundOp == null || foundType == null) {
        for (final op in _operators) {
          final types = await _fetchTypes(op.name);

          // Try ID
          if (dbTypeId != null) {
            try {
              foundType = types.firstWhere((t) => t.id == dbTypeId);
              foundOp = op;
              break;
            } catch (_) {}
          }

          // Try Name
          if (foundType == null && dbTypeName.isNotEmpty) {
            try {
              foundType = types.firstWhere(
                (t) =>
                    t.displayName.trim().toLowerCase() ==
                    dbTypeName.trim().toLowerCase(),
              );
              foundOp = op;
              break;
            } catch (_) {}
          }
        }
      }

      // 4. SAP-prefix inference — for Vodafone-style serials that don't start with YYYYMMDD.
      // Sample the existing new serials and check which type's sapClient they start with.
      if (foundOp == null || foundType == null) {
        final sampleSerials = list
            .whereType<Map>()
            .map(
              (m) =>
                  (m['serial_new'] ??
                          m['serial_new_label'] ??
                          m['label_new'])
                      ?.toString(),
            )
            .where((s) => s != null && s.isNotEmpty)
            .cast<String>()
            .where((s) => !RegExp(r'^\d{8}').hasMatch(s)) // not date-prefixed
            .take(5)
            .toList();

        if (sampleSerials.isNotEmpty) {
          outer:
          for (final op in _operators) {
            final types = await _fetchTypes(op.name);
            for (final t in types) {
              final sap = (t.sapClient ?? '').trim();
              if (sap.length < 3) continue; // too short to be meaningful
              if (sampleSerials.any((s) => s.startsWith(sap))) {
                foundOp = op;
                foundType = t;
                break outer;
              }
            }
          }
        }
      }

      // Apply selection
      if (foundOp != null) {
        setState(() => _selectedOperator = foundOp);
        // Ensure types are loaded for the UI
        final types = await _fetchTypes(foundOp.name);
        setState(() {
          _labelTypes = types;
          if (foundType != null) {
            _selectedType = foundType;
          } else if (types.isNotEmpty) {
            selectionError =
                'Tipo de etiqueta "$dbTypeName" no encontrado. Por favor selecciona uno.';
          }
        });
      } else {
        selectionError = 'Operador "$dbOperator" no encontrado.';
      }

      // 5. Infer SAP directly from existing serials.
      // Steps 1-3 may find a product-type record (e.g. tipo_etiqueta_id=144 "REDMI WATCH 6 BLACK")
      // that carries no sapClient.  If the actual serial_new values follow the Vodafone pattern
      // {sap}{yearDigit}{monthLetter}{day:2}{seq} we extract the real SAP prefix here and
      // override whatever sapClient the DB type carries (which may be empty).
      String? inferredSap;
      {
        final sampleSerials = list
            .whereType<Map>()
            .map(
              (m) =>
                  (m['serial_new'] ??
                          m['serial_new_label'] ??
                          m['label_new'])
                      ?.toString(),
            )
            .where((s) => s != null && s.isNotEmpty)
            .cast<String>()
            .where((s) => !RegExp(r'^\d{8}').hasMatch(s))
            .take(5)
            .toList();
        for (final s in sampleSerials) {
          final sap = _inferSapFromSerial(s);
          if (sap != null) {
            inferredSap = sap;
            break;
          }
        }
      }

      // Restore sequence (continue from last used + 1), but generate labels from earliest
      final seqBounds = _sequenceBounds(
        list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList(),
        operatorName: inferredSap != null ? 'vodafone' : (_selectedOperator?.name ?? dbOperator),
        sapClient: inferredSap ?? _selectedType?.sapClient,
      );
      final lastUsedSeq = seqBounds['max'];
      final nextSeq = (lastUsedSeq ?? 0) + 1;
      if (lastUsedSeq != null) {
        _startSeqController.text = nextSeq.toString();
        _continueSequence = true;
      }
      final startSequenceForGeneration = seqBounds['min'] ?? 1;

      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Orden incompleta encontrada'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se encontraron $existing registros para la orden "$nr" (plan: $planned). ¿Quieres seguir con esta orden incompleta?',
              ),
              if (selectionError != null ||
                  (_selectedOperator == null || _selectedType == null)) ...[
                const SizedBox(height: 12),
                Text(
                  'Nota: ${selectionError ?? "No se pudo autoseleccionar la etiqueta."}',
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
                const Text(
                  'Por favor, selecciona el operador y tipo manualmente.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sí, continuar'),
            ),
          ],
        ),
      );
      if (proceed != true) return;

      // Build lists from server records
      final allServerRecords = list
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      try {
        developer.log(
          'allServerRecords type: ${allServerRecords.runtimeType}, length: ${allServerRecords.length}',
          name: 'SerialChange._checkOrderResume',
        );
      } catch (_) {}
      final lastBoxInfo = _pickLastBoxInfo(allServerRecords);
      final lastBox = lastBoxInfo['box'] as String?;
      final lastBoxUnits = lastBoxInfo['units'] as int?;

      // Generate labels locally
      if (_selectedOperator == null || _selectedType == null) {
        // If we couldn't auto-select operator/type, ask the user to select them
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Selecciona operador y tipo'),
            content: const Text(
              'No se pudo autoseleccionar el operador o tipo desde los registros. Por favor selecciona el operador y el tipo de etiqueta en la pantalla y vuelve a comprobar la orden.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
        return;
      }

      setState(() => _generatingLabels = true);

      try {
        final labels = await Future<List<String>>(
          () => LocalLabelGenerator.generate(
            // When an SAP was inferred from existing serials (Step 5), use it and
            // force the Vodafone format regardless of what the DB type record says.
            operatorName: inferredSap != null ? 'vodafone' : _selectedOperator!.name,
            productionDate: _productionDate,
            totalUnits: planned,
            article: _selectedType!.article,
            sapClient: inferredSap ?? _selectedType!.sapClient,
            codeLetter: _selectedType!.codeLetter,
            startSequence: startSequenceForGeneration,
          ),
        );
        if (!mounted) return;

        // Show format preview so the operator can verify the auto-selected type is correct.
        // Show the NEXT label (nextSeq) so the operator can scan a real one from the roll to confirm.
        if (labels.isNotEmpty) {
          // Generate just 1 label at nextSeq for the preview — keeps the labels list untouched.
          final previewLabel = LocalLabelGenerator.generate(
            operatorName: inferredSap != null ? 'vodafone' : _selectedOperator!.name,
            productionDate: _productionDate,
            totalUnits: 1,
            article: _selectedType!.article,
            sapClient: inferredSap ?? _selectedType!.sapClient,
            codeLetter: _selectedType!.codeLetter,
            startSequence: nextSeq,
          ).firstOrNull ?? labels.first;
          final proceedPreview = await showDialog<bool>(
            context: context,
            builder: (ctx) {
              final scanCtrl = TextEditingController();
              String scanned = '';
              return StatefulBuilder(
                builder: (ctx, setS) {
                  final expected = previewLabel.trim();
                  final match = scanned.trim() == expected;
                  final hasInput = scanned.trim().isNotEmpty;
                  return AlertDialog(
                    title: const Text('Verificar formato al reanudar'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Confirma que el formato generado es correcto antes de continuar:',
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          expected,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Escanea una etiqueta para verificar:',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: scanCtrl,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'Escanear aquí...',
                            prefixIcon: const Icon(Icons.qr_code_scanner),
                            suffixIcon: hasInput
                                ? Icon(
                                    match
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    color:
                                        match ? Colors.green : Colors.red,
                                  )
                                : null,
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: hasInput
                                    ? (match ? Colors.green : Colors.red)
                                    : Colors.blue,
                                width: 2,
                              ),
                            ),
                          ),
                          onChanged: (v) => setS(() => scanned = v),
                          onSubmitted: (_) {
                            if (match) Navigator.of(ctx).pop(true);
                          },
                        ),
                        if (hasInput) ...[
                          const SizedBox(height: 8),
                          Text(
                            match
                                ? '✓ El formato es correcto'
                                : '✗ No coincide — verifica el operador/tipo seleccionado',
                            style: TextStyle(
                              fontSize: 12,
                              color: match ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancelar — cambiar tipo'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Aceptar'),
                      ),
                    ],
                  );
                },
              );
            },
          );
          if (!mounted) return;
          if (proceedPreview != true) {
            // User rejected the format — reset so they can pick the right type
            setState(() => _configLocked = false);
            return;
          }
        }

        // Determine if the last box is incomplete
        bool resumeBox = false;
        List<Map<String, dynamic>> activeBoxRecords = [];
        List<String> consumedLabelsList = [];

        if (lastBox != null) {
          final recordsInLastBox = allServerRecords
              .where(
                (m) =>
                    (m['nr_box'] ?? m['nrCaja'] ?? m['box'])
                        ?.toString()
                        .trim() ==
                    lastBox,
              )
              .toList();
          if (lastBoxUnits == null || recordsInLastBox.length < lastBoxUnits) {
            resumeBox = true;
            activeBoxRecords = recordsInLastBox;
            try {
              developer.log(
                'activeBoxRecords assigned. Type: ${activeBoxRecords.runtimeType}, length: ${activeBoxRecords.length}',
                name: 'SerialChange._checkOrderResume',
              );
            } catch (_) {}
            // Consumed labels are everything NOT in the last box
            consumedLabelsList = allServerRecords
                .where(
                  (m) =>
                      (m['nr_box'] ?? m['nrCaja'] ?? m['box'])
                          ?.toString()
                          .trim() !=
                      lastBox,
                )
                .map(
                  (m) =>
                      (m['serial_new'] ??
                              m['serial_new_label'] ??
                              m['label_new'])
                          ?.toString() ??
                      '',
                )
                .where((s) => s.isNotEmpty)
                .toList();
          } else {
            // Last box is full, so everything is consumed
            consumedLabelsList = allServerRecords
                .map(
                  (m) =>
                      (m['serial_new'] ??
                              m['serial_new_label'] ??
                              m['label_new'])
                          ?.toString() ??
                      '',
                )
                .where((s) => s.isNotEmpty)
                .toList();
          }
        } else {
          // No box info, assume everything is consumed
          consumedLabelsList = allServerRecords
              .map(
                (m) =>
                    (m['serial_new'] ?? m['serial_new_label'] ?? m['label_new'])
                        ?.toString() ??
                    '',
              )
              .where((s) => s.isNotEmpty)
              .toList();
        }

        setState(() {
          _configLocked = true;
          _consumedLabels.clear();
          _consumedLabels.addAll(consumedLabelsList);
          _history.clear();

          // Reconstruct history from server records
          // Group by box number
          final Map<String, List<Map<String, dynamic>>> byBox = {};
          for (final m in allServerRecords) {
            final b = (m['nr_box'] ?? m['nrCaja'] ?? m['box'])?.toString();
            if (b != null) {
              byBox.putIfAbsent(b, () => []).add(m);
            }
          }

          // Sort box numbers (assuming numeric)
          final sortedBoxes = byBox.keys.toList()
            ..sort((a, b) {
              final ia = int.tryParse(a) ?? 0;
              final ib = int.tryParse(b) ?? 0;
              return ia.compareTo(ib);
            });

          for (final bNum in sortedBoxes) {
            // If we are resuming this box, don't add to history yet (it's active)
            if (resumeBox && bNum == lastBox) continue;

            final records = byBox[bNum]!;
            if (records.isEmpty) continue;

            // Determine units
            int units = 0;
            final uVal =
                (records.first['nr_unidades_box'] ??
                        records.first['nr_unidades'] ??
                        records.first['nr_unidades_box'])
                    ?.toString();
            if (uVal != null) units = int.tryParse(uVal) ?? 0;
            if (units == 0) units = records.length; // fallback

            // Determine submission date (latest in box)
            DateTime? submitted;
            for (final r in records) {
              final d = _recordDate(r);
              if (d != null) {
                if (submitted == null || d.isAfter(submitted)) {
                  submitted = d;
                }
              }
            }
            submitted ??= DateTime.now();

            // Determine last label (by highest ID or just last in list)
            // Assuming records are somewhat ordered or we can sort by ID
            records.sort((a, b) {
              final idA = int.tryParse((a['id'] ?? '0').toString()) ?? 0;
              final idB = int.tryParse((b['id'] ?? '0').toString()) ?? 0;
              return idA.compareTo(idB);
            });
            final lastLbl =
                (records.last['serial_new'] ??
                        records.last['serial_new_label'] ??
                        records.last['label_new'])
                    ?.toString();

            _history.add(
              BoxHistoryEntry(
                boxNumber: bNum,
                units: units,
                submittedAt: submitted,
                lastLabel: lastLbl,
                records: records,
              ),
            );
          }

          if (resumeBox && lastBox != null) {
            // Create active box with ALL labels for that box (registered + unregistered)
            // The start index is simply the number of consumed labels (since we assume sequential filling)
            final startIndex = _consumedLabels.length;
            final boxUnits =
                lastBoxUnits ??
                (activeBoxRecords.isNotEmpty ? activeBoxRecords.length : 1);
            final endIndex = startIndex + boxUnits;

            if (startIndex < labels.length) {
              final boxLabels = labels.sublist(
                startIndex,
                endIndex <= labels.length ? endIndex : labels.length,
              );

              _activeBox?.dispose();
              _activeBox = _BoxSession(
                boxNumber: lastBox,
                units: boxUnits,
                labels: boxLabels,
              );
              _activeBox!.startTime = DateTime.now();

              // Mark registered entries
              for (final entry in _activeBox!.entries) {
                final found = activeBoxRecords.firstWhere(
                  (m) =>
                      (m['serial_new'] ??
                              m['serial_new_label'] ??
                              m['label_new'])
                          ?.toString() ==
                      entry.label,
                  orElse: () => <String, dynamic>{},
                );
                if (found.isNotEmpty) {
                  entry.controller.text =
                      (found['serial_old'] ?? found['serial_old_value'] ?? '')
                          .toString();
                  entry.registered = true;
                  try {
                    entry.registryId = (found['id'] is num)
                        ? (found['id'] as num).toInt()
                        : null;
                  } catch (_) {}
                }
              }
            }
            _boxNumberController.text = lastBox;
            _boxUnitsController.text = (lastBoxUnits ?? boxUnits).toString();
          } else {
            // No active box, prepare for next
            _activeBox?.dispose();
            _activeBox = null;
            // Try to guess next box number
            if (lastBox != null) {
              final lbInt = int.tryParse(lastBox);
              if (lbInt != null) {
                _boxNumberController.text = (lbInt + 1).toString();
              }
            } else {
              _boxNumberController.clear();
            }
            // Default units to same as last box if available, or 20
            if (lastBoxUnits != null) {
              _boxUnitsController.text = lastBoxUnits.toString();
            } else {
              _boxUnitsController.text = '20';
            }
          }

          // Pending labels are those not in consumed AND not in active box
          final activeLabels = _activeBox?.labels ?? [];
          _pendingLabels = labels
              .where(
                (l) =>
                    !_consumedLabels.contains(l) && !activeLabels.contains(l),
              )
              .toList();
        });

        // Focus UX
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        if (_activeBox != null) {
          _BoxEntryField? next;
          for (final e in _activeBox!.entries) {
            if (!e.registered) {
              next = e;
              break;
            }
          }
          if (next != null) {
            Scrollable.ensureVisible(
              next.focusNode.context ?? context,
              alignment: 0.5,
            );
            next.focusNode.requestFocus();
          }
        } else if (_boxNumberController.text.isNotEmpty) {
          // If no active box but we have a number, focus units
          FocusScope.of(context).requestFocus(_boxUnitsFocus);
        } else {
          // If no active box and no number, focus box number input
          FocusScope.of(context).requestFocus(_boxNumberFocus);
        }
      } finally {
        if (mounted) setState(() => _generatingLabels = false);
      }
    } catch (e) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Error comprobando orden: $e')),
      );
    }
  }

  void _resetWorkflow() {
    setState(() {
      final initialOrder = _normalizedInitialOrder();
      _configLocked = false;
      _pendingLabels = const [];
      _consumedLabels.clear();
      _registeredMappings.clear();
      _activeBox?.dispose();
      _activeBox = null;
      _history.clear();
      _completionMessage = null;
      _generationError = null;
      _boxError = null;

      // Clear order inputs for fresh start
      _orderController.text = initialOrder;
      _skuController.clear();
      _unitsController.clear();
      _startSeqController.text = '1';
    });
    // Ensure we start fresh with focus on order number
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _orderFocus.requestFocus();
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  void _markEntryInvalid(_BoxEntryField entry, String message) {
    SoundPlayer.playError();
    setState(() {
      entry.isValid = false;
      entry.isInvalid = true;
      entry.errorMessage = message;
      _boxError = message;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusScope.of(context).requestFocus(entry.focusNode);
    });
  }

  Future<bool> _validateEntryForSubmit(
    _BoxEntryField entry,
    _BoxSession box,
  ) async {
    final text = entry.controller.text.trim();
    if (text.isEmpty) {
      _markEntryInvalid(entry, 'El S/N no puede estar vacío.');
      return false;
    }

    if (_originalSerialMaskLength != null &&
        text.length != _originalSerialMaskLength) {
      _markEntryInvalid(
        entry,
        'Longitud inválida: se esperan $_originalSerialMaskLength caracteres.',
      );
      return false;
    }

    final existingOlds = _registeredMappings
        .map((m) => m['old'])
        .whereType<String>()
        .toSet();
    for (final other in box.entries) {
      if (other != entry) {
        final v = other.controller.text.trim();
        if (v.isNotEmpty && v == text) {
          _markEntryInvalid(entry, 'S/N duplicado dentro de la caja.');
          return false;
        }
      }
    }
    if (existingOlds.contains(text)) {
      _markEntryInvalid(entry, 'Este S/N ya fue registrado previamente.');
      return false;
    }

    try {
      final check = await MaskService.checkSerial(text);
      if (check.suspicious == true) {
        final sample = check.matches.isNotEmpty
            ? (check.matches.first['mask'] ?? '').toString()
            : '';
        final suffix = sample.isNotEmpty ? ' ($sample)' : '';
        _markEntryInvalid(
          entry,
          'Entrada sospechosa: parece máscara y no S/N$suffix.',
        );
        return false;
      }
    } catch (_) {
      // If mask check fails, allow the operator to continue.
    }

    setState(() {
      entry.isValid = true;
      entry.isInvalid = false;
      entry.errorMessage = null;
      if (_boxError != null) {
        _boxError = null;
      }
    });
    return true;
  }

  // Validate a serial entry and update its UI state (sync+async checks)
  void _onSerialChanged(_BoxEntryField entry) {
    final text = entry.controller.text.trim();
    // Reset states quickly for empty
    if (text.isEmpty) {
      setState(() {
        entry.isValid = false;
        entry.isInvalid = false;
        entry.errorMessage = null;
      });
      return;
    }

    // Quick synchronous checks
    // Duplicate within registered mappings or other entries
    final existingOlds = _registeredMappings
        .map((m) => m['old'])
        .whereType<String>()
        .toSet();
    for (final other in _activeBox?.entries ?? []) {
      if (other != entry) {
        final v = other.controller.text.trim();
        if (v.isNotEmpty && v == text) {
          setState(() {
            entry.isValid = false;
            entry.isInvalid = true;
            entry.errorMessage = 'S/N duplicado dentro de la caja.';
          });
          return;
        }
      }
    }
    if (existingOlds.contains(text)) {
      setState(() {
        entry.isValid = false;
        entry.isInvalid = true;
        entry.errorMessage = 'Este S/N ya fue registrado previamente.';
      });
      return;
    }

    // Enforce original mask length if known
    if (_originalSerialMaskLength != null &&
        text.length != _originalSerialMaskLength) {
      setState(() {
        entry.isValid = false;
        entry.isInvalid = true;
        entry.errorMessage =
            'Longitud inválida: se esperan $_originalSerialMaskLength caracteres.';
      });
      return;
    }

    // If we pass quick checks, run MaskService asynchronously for deeper checks
    // Mark neutral until result
    setState(() {
      entry.isValid = false;
      entry.isInvalid = false;
      entry.errorMessage = null;
    });
    () async {
      try {
        final check = await MaskService.checkSerial(text);
        if (!mounted) return;
        if (check.suspicious == true) {
          setState(() {
            entry.isValid = false;
            entry.isInvalid = true;
            entry.errorMessage = 'Entrada sospechosa: parece máscara y no S/N.';
          });
        } else {
          setState(() {
            entry.isValid = true;
            entry.isInvalid = false;
            entry.errorMessage = null;
          });
        }
      } catch (_) {
        // On error, remain neutral (not invalid) so user can continue
        if (!mounted) return;
        setState(() {
          entry.isValid = true;
          entry.isInvalid = false;
          entry.errorMessage = null;
        });
      }
    }();
  }

  Color _entryBackgroundColor(_BoxEntryField entry, ThemeData theme) {
    final txt = entry.controller.text.trim();
    if (entry.registered) return Colors.green.withOpacity(.12);
    if (txt.isEmpty)
      return theme.colorScheme.surfaceContainerHighest.withOpacity(.04);
    if (entry.isInvalid) return Colors.red.withOpacity(.12);
    if (entry.isValid) return Colors.green.withOpacity(.12);
    return theme.colorScheme.surfaceContainerHighest.withOpacity(.02);
  }

  Future<void> _startBox() async {
    if (!_configLocked || _pendingLabels.isEmpty) {
      setState(
        () => _boxError = 'Genera las etiquetas antes de registrar cajas.',
      );
      return;
    }
    if (_activeBox != null) {
      setState(
        () => _boxError =
            'Completa o cancela la caja activa antes de crear una nueva.',
      );
      return;
    }
    if (!_boxFormKey.currentState!.validate()) return;
    final units = int.tryParse(_boxUnitsController.text.trim()) ?? 0;
    if (units <= 0) {
      setState(() => _boxError = 'Unidades por caja inválidas.');
      return;
    }
    if (units > _pendingLabels.length) {
      setState(
        () => _boxError =
            'Solo quedan ${_pendingLabels.length} etiquetas pendientes.',
      );
      return;
    }
    final chunk = _pendingLabels.sublist(0, units).toList();
    setState(() {
      _activeBox = _BoxSession(
        boxNumber: _boxNumberController.text.trim(),
        units: units,
        labels: chunk,
      );
      _pendingLabels = _pendingLabels.sublist(units);
      _boxError = null;
    });
    // After creating the active box, set start time and start stopwatch, then focus the first serial input
    _activeBox!.startTime = DateTime.now();
    _boxElapsed = Duration.zero;
    _boxTimer?.cancel();
    _boxTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {
        final st = _activeBox?.startTime;
        _boxElapsed = st == null
            ? Duration.zero
            : DateTime.now().difference(st);
      });
    });

    // allow widgets to build then focus the first serial input
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    if (_activeBox != null && _activeBox!.entries.isNotEmpty) {
      try {
        FocusScope.of(
          context,
        ).requestFocus(_activeBox!.entries.first.focusNode);
      } catch (_) {}
    }
  }

  void _cancelBox() {
    if (_activeBox == null) return;
    setState(() {
      _pendingLabels = [..._activeBox!.labels, ..._pendingLabels];
      _activeBox?.dispose();
      _activeBox = null;
      _boxTimer?.cancel();
      _boxElapsed = Duration.zero;
    });
    _boxNumberFocus.requestFocus();
  }

  Future<void> _finalizeOrderAndUpload(String orderNr) async {
    debugPrint('_finalizeOrderAndUpload called for order: $orderNr');

    // Add a small delay to ensure previous dialogs are fully closed
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // Show Progress Dialog
    // We do NOT await this because we want to run code while it is open.
    // However, we capture the future to ensure we can pop it correctly or wait for it if needed?
    // In this pattern, we just push it and then pop it.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Dialog(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 24),
                Expanded(child: Text('Finalizando orden y subiendo a SFTP...')),
              ],
            ),
          ),
        ),
      ),
    );

    // Perform check
    bool verified = false;
    String? errorMsg;

    try {
      final client = _clientOrNull();
      // Artificial delay to ensure user sees the progress dialog
      await Future.delayed(const Duration(seconds: 1));

      if (client != null) {
        debugPrint(
          '_finalizeOrderAndUpload: Client OK. Posting finish-order-upload...',
        );
        // Trigger
        final postRes = await client.post(
          '/serials/finish-order-upload',
          jsonBody: {'nr_orden': orderNr},
        );

        if (!postRes.ok) {
          debugPrint('Upload POST failed: ${postRes.statusCode}');
          // We continue to check anyway? Or fail?
          // Usually if POST fails, the file might not be there.
          // But let's let the loop check explicitly.
        }

        // Loop check
        final encFilename = Uri.encodeQueryComponent('$orderNr.xlsx');
        for (int i = 0; i < 5; i++) {
          debugPrint('_finalizeOrderAndUpload: Check Attempt ${i + 1}');
          await Future.delayed(const Duration(seconds: 2));
          try {
            final res = await client.get(
              '/serials/check-sftp?filename=$encFilename',
            );
            if (res.ok) {
              debugPrint('_finalizeOrderAndUpload: Verified OK');
              verified = true;
              break;
            } else {
              debugPrint(
                '_finalizeOrderAndUpload: Check failed ${res.statusCode}',
              );
            }
          } catch (e) {
            debugPrint('_finalizeOrderAndUpload: Check exception $e');
          }
        }
      } else {
        debugPrint('_finalizeOrderAndUpload: Client is NULL');
        errorMsg = 'API Client no disponible';
      }
    } catch (e) {
      debugPrint('_finalizeOrderAndUpload: Exception $e');
      errorMsg = e.toString();
    }

    // Close Progress Dialog
    if (mounted) {
      // Ensure we are popping the dialog we showed
      Navigator.of(context).pop();
    }

    // Show Result Dialog
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 300));

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(verified ? 'SUBIDA SFTP COMPLETADA' : 'AVISO SFTP'),
        content: Row(
          children: [
            Icon(
              verified ? Icons.check_circle : Icons.warning_amber_rounded,
              color: verified ? Colors.green : Colors.orange,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                verified
                    ? 'La orden se ha finalizado y el archivo Excel se ha subido correctamente al SFTP.'
                    : 'No se pudo verificar el archivo en el SFTP.\n${errorMsg ?? "Intentos agotados."}',
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    debugPrint('_finalizeOrderAndUpload: completed');
  }

  Future<bool> _checkAndTriggerCompletion() async {
    if (!mounted) return false;
    final orderNr = _orderController.text.trim();
    if (orderNr.isEmpty) return false;

    try {
      final client = _clientOrNull();
      if (client == null) return false;

      // Call the new endpoint
      final res = await client.get(
        '/serials/order-completion?num_orden=$orderNr',
      );

      bool isComplete = false;
      if (res.ok) {
        if (res.body is Map) {
          final m = res.body as Map;
          if (m['is_complete'] == true ||
              m['complete'] == true ||
              m['completed'] == true ||
              m['status'] == 'completed') {
            isComplete = true;
          }
        } else if (res.body.toString().toLowerCase() == 'true') {
          isComplete = true;
        }
      }

      if (isComplete) {
        SoundPlayer.playFinishOrder();
        await _finalizeOrderAndUpload(orderNr);
        return true;
      }
    } catch (e) {
      debugPrint('Error checking order completion: $e');
    }
    return false;
  }

  Future<void> _submitBox() async {
    // 1. Connectivity Check
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sin conexión'),
          content: const Text(
            'No hay conexión a internet. No se puede registrar la caja.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
      return;
    }

    final box = _activeBox;
    if (box == null) return;
    // Ensure all serial fields are filled. If any are empty, block submission.
    final entriesToSubmit = box.entries
        .where((entry) => entry.controller.text.trim().isNotEmpty)
        .toList();
    if (entriesToSubmit.length != box.entries.length) {
      setState(() => _boxError = 'Completa todos los S/N antes de registrar.');
      return;
    }

    // 2. Serial Length Validation
    if (entriesToSubmit.isNotEmpty) {
      final firstToken = entriesToSubmit.first.controller.text.trim();
      final expectedLength = _originalSerialMaskLength ?? firstToken.length;

      for (final entry in entriesToSubmit) {
        final s = entry.controller.text.trim();
        if (s.length != expectedLength) {
          setState(
            () => _boxError =
                'Longitud inválida: "$s" tiene ${s.length} caracteres (se esperaban $expectedLength).',
          );
          // Opt: Focus the invalid one
          FocusScope.of(context).requestFocus(entry.focusNode);
          return;
        }
      }
    }

    final client = _clientOrNull();
    if (client == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servicio API no disponible.')),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar caja'),
        content: Text(
          'Registrar caja ${box.boxNumber} con ${box.units} unidades?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirm != true) return;
    // Before starting registration, check for duplicates (local and server-side).
    // Collect originals entered in this box
    final enteredOldSerials = entriesToSubmit
        .map((e) => e.controller.text.trim())
        .toList();

    // Check local mappings first
    final localDuplicates = <String>[];
    final registeredOlds = _registeredMappings
        .map((m) => m['old'])
        .whereType<String>()
        .toSet();
    for (final s in enteredOldSerials) {
      if (registeredOlds.contains(s)) localDuplicates.add(s);
    }
    if (localDuplicates.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('S/N duplicados (local)'),
          content: Text(
            'Los siguientes S/N ya fueron registrados localmente:\n${localDuplicates.join('\n')}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      return;
    }

    // Check against server
    try {
      final clientCheck = _clientOrNull();
      if (clientCheck == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Servicio API no disponible para verificación de duplicados.',
            ),
          ),
        );
        return;
      }
      final serverDuplicates = <String, Map<String, dynamic>>{};
      // Query the server for each entered original serial. Use small parallelism via Future.wait.
      final checks = enteredOldSerials.map((s) async {
        try {
          final enc = Uri.encodeQueryComponent(s);
          // Check for duplicates on server side; ask for a large limit to be safe
          // For duplicate checks, request the server maximum so we don't miss matches
          final r = await clientCheck.get(
            '/serials/serial-changes?q=$enc&limit=10000',
          );
          if (r.ok) {
            final list = _extractList(r.body);
            if (list.isNotEmpty) {
              final Map first = list.first as Map;
              serverDuplicates[s] = Map<String, dynamic>.from(
                first.map((k, v) => MapEntry(k.toString(), v)),
              );
            }
          }
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }).toList();
      await Future.wait(checks);
      if (serverDuplicates.isNotEmpty) {
        // Build a friendly message showing where the serial was found if available
        final lines = serverDuplicates.entries
            .map((e) {
              final info = e.value;
              final orden =
                  info['nr_orden'] ?? info['orden'] ?? info['nr_order'] ?? '';
              final box = info['nr_box'] ?? info['nr_box'] ?? '';
              return '${e.key}  (${orden != null && orden.toString().isNotEmpty ? 'orden: $orden' : 'registrado'})${box != null && box.toString().isNotEmpty ? ', caja: $box' : ''}';
            })
            .join('\n');
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('S/N duplicados (servidor)'),
            content: Text(
              'No se puede registrar la caja. Los siguientes S/N ya existen:\n$lines',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(c).pop(),
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        return;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error verificando duplicados: $e')),
      );
      return;
    }

    setState(() => _registeringBox = true);
    try {
      final endTime = DateTime.now();
      final startStr = box.startTime != null
          ? DateFormat('yyyy-MM-dd HH:mm:ss').format(box.startTime!)
          : null;
      final endStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(endTime);
      final payload = <String, dynamic>{
        'nr_orden': _orderController.text.trim(),
        'nr_sku': _skuController.text.trim(),
        'nr_unidades': _plannedUnits,
        'operador': _selectedOperator?.name,
        'tipo_etiqueta_id': _selectedType?.id,
        'tipo_etiqueta': _selectedType?.displayName,
        'fecha': DateFormat('yyyy-MM-dd').format(_productionDate),
        'fecha_inicio': startStr,
        'fecha_finalizacion': endStr,
        'ean': _ean ?? '',
        'nr_box': box.boxNumber,
        'nr_unidades_box': box.units,
        'labels': entriesToSubmit
            .map(
              (entry) => {
                'label': entry.label,
                'serial': entry.controller.text.trim(),
              },
            )
            .toList(),
      };
      final currentUser = ApiService.instance?.currentUser;
      if (currentUser != null) {
        payload['usuario'] = currentUser.nombre?.isNotEmpty == true
            ? currentUser.nombre
            : currentUser.username;
      }
      final res = await client.post('/serials/add_registry', jsonBody: payload);
      if (!mounted) return;
      if (res.ok) {
        // mark end time on the box session and stop timer
        box.endTime = endTime;
        _boxTimer?.cancel();
        _boxElapsed = Duration.zero;
        setState(() {
          _consumedLabels.addAll(box.labels);
          _history.add(
            BoxHistoryEntry(
              boxNumber: box.boxNumber,
              units: box.units,
              submittedAt: DateTime.now(),
            ),
          );
          _activeBox?.dispose();
          _activeBox = null;
          final nextBox = int.tryParse(box.boxNumber);
          if (nextBox != null) {
            _boxNumberController.text = (nextBox + 1).toString();
          } else {
            _boxNumberController.clear();
          }
          _boxUnitsController.clear();
          _boxNumberFocus.requestFocus();
          if (_consumedLabels.length >= _plannedUnits) {
            _completionMessage =
                'Se registraron todas las $_plannedUnits unidades.';
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Caja ${box.boxNumber} registrada.')),
        );
        // After successful registration, persist individual serial mappings to backend via add_registry endpoint.
        SoundPlayer.playBoxComplete();

        try {
          final client2 = _clientOrNull();
          if (client2 != null) {
            final currentUser = ApiService.instance?.currentUser;
            final usuario = currentUser != null
                ? (currentUser.nombre?.isNotEmpty == true
                      ? currentUser.nombre
                      : currentUser.username)
                : null;
            int failures = 0;
            for (final entry in entriesToSubmit) {
              try {
                final audit = <String, dynamic>{
                  'nr_orden': _orderController.text.trim(),
                  'nr_sku': _skuController.text.trim(),
                  'nr_unidades': _plannedUnits,
                  'tipo_etiqueta': _selectedType?.displayName,
                  'fecha': DateFormat('yyyy-MM-dd').format(_productionDate),
                  'fecha_inicio': startStr,
                  'fecha_finalizacion': endStr,
                  'usuario': usuario,
                  'tipo_etiqueta_id': _selectedType?.id,
                  'nr_box': box.boxNumber,
                  'nr_unidades_box': box.units,
                  'ean': _ean ?? '',
                  'serial_old': entry.controller.text.trim(),
                  'serial_new': entry.label,
                };
                final resp = await client2.post(
                  '/serials/add_registry',
                  jsonBody: audit,
                );
                if (!resp.ok) {
                  failures++;
                } else {
                  // capture id if returned and keep mapping for printing
                  int? returnedId;
                  if (resp.body is Map && resp.body['id'] != null) {
                    try {
                      returnedId = (resp.body['id'] as num).toInt();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error impresión: $e')),
                      );
                    }
                  }
                  entry.registryId = returnedId;
                  try {
                    final Map<String, dynamic> map = {
                      'old': entry.controller.text.trim(),
                      'new': entry.label,
                    };
                    if (returnedId != null) map['id'] = returnedId;
                    _registeredMappings.add(map);
                  } catch (_) {}
                }
              } catch (e) {
                failures++;
              }
            }
            if (failures > 0 && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Guardados ${box.units - failures}/${box.units} registros; $failures fallidos.',
                  ),
                ),
              );
            }
          }
        } catch (_) {
          // ignore auditing errors
        }

        // After auditing, print one label per box (ask for printer)
        try {
          final newSerials = box.labels;
          final oldSerials = entriesToSubmit
              .map((e) => e.controller.text.trim())
              .toList();
          await _printForBox(box.boxNumber, newSerials, oldSerials, box.units);
        } catch (_) {
          // ignore print errors
        }

        // 3. Check backend completion
        if (await _checkAndTriggerCompletion()) {
          // debugPrint('Completion condition MET.');

          if (!mounted) return;

          // Offer to print final label
          final doPrint = await showDialog<bool>(
            context: context,
            builder: (dctx) => AlertDialog(
              title: const Text('Proceso completado'),
              content: const Text(
                'Se registraron todas las unidades. ¿Deseas imprimir una etiqueta final con todos los S/N?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dctx).pop(false),
                  child: const Text('No'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dctx).pop(true),
                  child: const Text('Sí, imprimir'),
                ),
              ],
            ),
          );
          // debugPrint(
          //   'DEBUG: (_submitBox) Print dialog closed. doPrint=$doPrint',
          // );
          if (doPrint == true) {
            try {
              // debugPrint('Calling _printFinalLabel...');
              await _printFinalLabel();
              // debugPrint('_printFinalLabel completed.');
            } catch (e) {
              debugPrint('Error in _printFinalLabel: $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error imprimiendo: $e')),
                );
              }
            }
          }

          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (dctx) => AlertDialog(
              title: const Text('Proceso completado'),
              content: Text(
                'Se registraron todas las $_plannedUnits unidades. El flujo se reiniciará.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(dctx).pop(),
                  child: const Text('Aceptar'),
                ),
              ],
            ),
          );

          if (!mounted) return;
          // debugPrint('DEBUG: (_submitBox) Reset dialog closed.');
          // debugPrint('DEBUG: (_submitBox) Resetting workflow...');
          _resetWorkflow();
        }
      } else {
        final message = res.body is Map
            ? (res.body['error']?.toString() ?? 'No se pudo registrar')
            : res.error ?? 'No se pudo registrar (${res.statusCode})';
        setState(() => _boxError = message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _boxError = 'Error registrando caja: $e');
    } finally {
      if (mounted) setState(() => _registeringBox = false);
    }
  }

  InputDecoration _inputDecoration(
    String label,
    IconData icon, {
    bool enabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: colorScheme.onSurface.withOpacity(0.75),
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: Icon(icon, color: colorScheme.primary),
      filled: true,
      enabled: enabled,
      fillColor: colorScheme.surfaceContainerHighest.withOpacity(.98),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.surface.withOpacity(.06)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.surface.withOpacity(.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, {String? subtitle}) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary.withOpacity(.12),
          ),
          child: Icon(icon, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(.7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOperatorSelector() {
    if (_operatorsLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_operatorsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _operatorsError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadOperators,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      );
    }
    if (_operators.isEmpty) return const Text('No hay operadores disponibles.');
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _operators
          .map(
            (op) => ChoiceChip(
              label: SizedBox(
                width: 150,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      op.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${op.activeTypes}/${op.totalTypes} activos',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              selected: _selectedOperator?.name == op.name,
              onSelected: (value) {
                if (!value) return;
                setState(() {
                  _selectedOperator = op;
                });
                _loadTypesForOperator(op);
              },
            ),
          )
          .toList(),
    );
  }

  Future<void> _confirmEraseLabelType() async {
    final client = _clientOrNull();
    if (client == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servicio API no disponible')),
      );
      return;
    }

    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un tipo para borrar.')),
      );
      return;
    }

    final type = _selectedType!;
    final operatorName = _selectedOperator?.name ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar borrado'),
        content: Text(
          '¿Seguro que quieres borrar el tipo "${type.displayName}" para $operatorName?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    try {
      // Construct payload
      final payload = <String, dynamic>{
        'operador': operatorName,
        'articulo': type.article ?? type.displayName,
      };
      if (type.id != null) {
        payload['tipo_id'] = type.id;
      }

      final res = await client.post('/serials/labels/erase', jsonBody: payload);

      if (res.ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Tipo borrado correctamente.')),
        );
        // Reload list
        if (_selectedOperator != null) {
          await _loadTypesForOperator(_selectedOperator!);
        } else {
          // Fallback if operator somehow lost, though unlikely
          setState(() {
            _selectedType = null;
          });
        }
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('Error borrando: ${res.statusCode}')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildTypeSelector() {
    if (_selectedOperator == null) {
      return const Text('Selecciona primero un operador.');
    }
    if (_typesLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_typesError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _typesError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _loadTypesForOperator(_selectedOperator!),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      );
    }
    if (_labelTypes.isEmpty) {
      return const Text('No hay tipos activos para este operador.');
    }
    final isOrange = _selectedOperator!.name.toLowerCase() == 'orange';
    final isVodafone = _selectedOperator!.name.toLowerCase() == 'vodafone';

    // Allow simple searching/filtering of the types list
    final filtered = _labelTypes.where((t) {
      final q = _typeSearch.trim().toLowerCase();
      if (q.isEmpty) return true;
      final hay =
          '${t.article ?? ''} ${t.codeLetter ?? ''} ${t.sapClient ?? ''} ${t.displayName}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();

    // Render a simplified two-column selectable list: Artículo | Código
    // Add a small header with a + button and a search field. The list is constrained in height
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tipos de etiqueta',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showAddLabelTypeDialog,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmEraseLabelType,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Search box
        TextField(
          controller: _typeSearchController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar tipos...',
            contentPadding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 12,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _typeSearch = v),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, thickness: .4),
            itemBuilder: (_, index) {
              final item = filtered[index];
              final selected = _selectedType?.id == item.id;
              final articleText = (item.article ?? '').isNotEmpty
                  ? item.article!
                  : item.displayName;
              String codeText;
              if (isOrange) {
                codeText = (item.codeLetter ?? '').isNotEmpty
                    ? item.codeLetter!
                    : '-';
              } else if (isVodafone) {
                codeText = (item.sapClient ?? '').isNotEmpty
                    ? item.sapClient!
                    : '-';
              } else {
                codeText = (item.codeLetter ?? item.sapClient ?? '-');
                if (codeText.isEmpty) codeText = '-';
              }

              return InkWell(
                onTap: () => setState(() => _selectedType = item),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 8,
                  ),
                  color: selected
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: .06)
                      : Colors.transparent,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).iconTheme.color,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          articleText,
                          style: TextStyle(
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 180,
                        child: Text(
                          codeText,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showAddLabelTypeDialog() async {
    final client = _clientOrNull();
    if (client == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servicio API no disponible')),
      );
      return;
    }

    final articuloCtrl = TextEditingController();
    final otherOperatorCtrl = TextEditingController();
    final codigoCtrl = TextEditingController();
    final sapCtrl = TextEditingController();
    bool activo = true;
    String? selectedOperator = _selectedOperator?.name;
    bool useOther = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setState2) {
            return AlertDialog(
              title: const Text('Añadir tipo de etiqueta'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text('Operador:'),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: useOther ? null : selectedOperator,
                            hint: useOther ? const Text('Otro...') : null,
                            items: [
                              ..._operators.map(
                                (op) => DropdownMenuItem(
                                  value: op.name,
                                  child: Text(op.name),
                                ),
                              ),
                              const DropdownMenuItem(
                                value: '__other__',
                                child: Text('Otro'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v == '__other__') {
                                setState2(() {
                                  useOther = true;
                                  selectedOperator = null;
                                });
                              } else {
                                setState2(() {
                                  useOther = false;
                                  selectedOperator = v;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    if (useOther) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: otherOperatorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre operador',
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: articuloCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Artículo (articulo)',
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 8),
                    // Operator-specific field hints
                    if ((selectedOperator ?? otherOperatorCtrl.text)
                            .toLowerCase() ==
                        'vodafone')
                      TextField(
                        controller: sapCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Número SAP (sap_cliente)',
                        ),
                      )
                    else if ((selectedOperator ?? otherOperatorCtrl.text)
                            .toLowerCase() ==
                        'orange')
                      TextField(
                        controller: codigoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Código letra (codigo_letra)',
                        ),
                      )
                    else ...[
                      const SizedBox.shrink(),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Activo'),
                        Switch(
                          value: activo,
                          onChanged: (v) => setState2(() => activo = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx2).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final operadorName = useOther
                        ? otherOperatorCtrl.text.trim()
                        : (selectedOperator ?? otherOperatorCtrl.text.trim());
                    final articulo = articuloCtrl.text.trim();
                    if (operadorName.isEmpty || articulo.isEmpty) {
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        const SnackBar(
                          content: Text('Operador y artículo son requeridos'),
                        ),
                      );
                      return;
                    }
                    final payload = <String, dynamic>{
                      'operador': operadorName,
                      'articulo': articulo,
                      'activo': activo,
                    };
                    final codigo = codigoCtrl.text.trim();
                    final sap = sapCtrl.text.trim();
                    if (codigo.isNotEmpty) payload['codigo_letra'] = codigo;
                    if (sap.isNotEmpty) payload['sap_cliente'] = sap;

                    // Capture navigator and messenger before awaiting to avoid using BuildContext across async gaps
                    final navigator = Navigator.of(ctx2);
                    final messenger = ScaffoldMessenger.of(ctx2);

                    try {
                      final resp = await client.post(
                        '/serials/labels',
                        jsonBody: payload,
                      );
                      if (resp.ok) {
                        navigator.pop(true);
                      } else if (resp.statusCode == 409) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Ese tipo ya existe para el operador',
                            ),
                          ),
                        );
                      } else {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Error: ${resp.statusCode}')),
                        );
                      }
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  },
                  child: const Text('Crear'),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted) return;

    try {
      articuloCtrl.dispose();
      otherOperatorCtrl.dispose();
      codigoCtrl.dispose();
      sapCtrl.dispose();
    } catch (_) {}

    if (result == true) {
      // reload operator types for current operator selection
      final opName = _selectedOperator?.name;
      if (opName != null) await _loadTypesForOperator(_selectedOperator!);
      await _loadOperators();
    }
  }

  Widget _buildProgressChips() {
    final processed = _consumedLabels.length;
    final pending = _pendingLabels.length + (_activeBox?.entries.length ?? 0);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _SummaryChip(label: 'Planificado', value: '$_plannedUnits'),
        _SummaryChip(label: 'Procesado', value: '$processed'),
        _SummaryChip(label: 'Pendiente', value: '$pending'),
        if (_activeBox != null)
          _SummaryChip(
            label: 'Caja activa',
            value: '#${_activeBox!.boxNumber} (${_activeBox!.units})',
          ),
      ],
    );
  }

  Widget _buildActiveBoxTable() {
    final box = _activeBox;
    if (box == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Caja ${box.boxNumber}',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 12),
            Chip(label: Text('${box.units} unidades')),
            const SizedBox(width: 8),
            if (box.startTime != null)
              Chip(label: Text('Duración ${_formatDuration(_boxElapsed)}')),
            const Spacer(),
            TextButton.icon(
              onPressed: _cancelBox,
              icon: const Icon(Icons.cancel),
              label: const Text('Cancelar caja'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: box.entries.length,
          separatorBuilder: (_, __) => const Divider(height: 1, thickness: .3),
          itemBuilder: (_, index) {
            final entry = box.entries[index];
            return Container(
              decoration: BoxDecoration(
                color: _entryBackgroundColor(entry, Theme.of(context)),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        '#${index + 1}'.padLeft(3, '0'),
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      if (entry.registered)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _showEditRegisteredDialog(entry),
                        ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: entry.controller,
                          focusNode: entry.focusNode,
                          maxLength: _originalSerialMaskLength,
                          maxLengthEnforcement: MaxLengthEnforcement.enforced,
                          decoration: InputDecoration(
                            labelText: 'Serial Viejo',
                            hintText: 'Ingresa el S/N ',
                            isDense: true,
                            errorText: entry.errorMessage,
                            counterText: '', // Hide the counter for a cleaner look
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9_\/\-#]'),
                            ),
                            if (_originalSerialMaskLength != null)
                              LengthLimitingTextInputFormatter(
                                _originalSerialMaskLength,
                              ),
                          ],
                          textInputAction: TextInputAction
                              .none, // Prevent automatic focus jumps
                          onChanged: (_) => _onSerialChanged(entry),
                          onSubmitted: (_) async {
                            if (entry.submitting) return;
                            entry.submitting = true;

                            // Move focus to next field immediately to accommodate fast scanners
                            if (index < box.entries.length - 1) {
                              FocusScope.of(context).requestFocus(
                                box.entries[index + 1].focusNode,
                              );
                            }

                            // Play success sound early if basic checks pass to ensure user hears it on scan
                            final text = entry.controller.text.trim();
                            if (_originalSerialMaskLength == null ||
                                text.length == _originalSerialMaskLength) {
                              SoundPlayer.playSuccess();
                            }

                            try {
                              final isValid = await _validateEntryForSubmit(
                                entry,
                                box,
                              );
                              if (!isValid) return;

                              // success: already played sound or play now if skipped before
                              if (_originalSerialMaskLength != null &&
                                  text.length != _originalSerialMaskLength) {
                                SoundPlayer.playSuccess();
                              }

                              // Check if we are updating an existing registry or creating a new one
                              if (entry.registered &&
                                  entry.registryId != null) {
                                // UPDATE EXISTING REGISTRY
                                try {
                                  final client2 = _clientOrNull();
                                  if (client2 == null) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Servicio API no disponible',
                                        ),
                                      ),
                                    );
                                    if (!mounted) return;
                                    FocusScope.of(
                                      context,
                                    ).requestFocus(entry.focusNode);
                                    return;
                                  }

                                  final id = entry.registryId!;
                                  final payload = <String, dynamic>{
                                    'serial_old': entry.controller.text.trim(),
                                  };

                                  final resp = await client2.put(
                                    '/serials/serial-changes/$id',
                                    jsonBody: payload,
                                  );

                                  if (resp.ok) {
                                    // update registeredMappings
                                    final newVal = entry.controller.text.trim();
                                    for (final m in _registeredMappings) {
                                      if (m['id'] == id) {
                                        m['old'] = newVal;
                                      }
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('S/N actualizado'),
                                      ),
                                    );
                                    // Do not auto-advance focus on edit; stay here or let user move
                                  } else {
                                    final err = resp.body is Map
                                        ? (resp.body['error']?.toString() ??
                                              resp.error ??
                                              'Error')
                                        : (resp.error ?? 'Error');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Error actualizando: $err',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Error actualizando S/N: $e',
                                        ),
                                      ),
                                    );
                                  }
                                }
                                return;
                              }

                              // Attempt to register this single S/N immediately so data is persisted even if the app closes
                              try {
                                final client2 = _clientOrNull();
                                if (client2 == null) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Servicio API no disponible',
                                      ),
                                    ),
                                  );
                                  if (!mounted) return;
                                  FocusScope.of(
                                    context,
                                  ).requestFocus(entry.focusNode);
                                  return;
                                }

                                final currentUser =
                                    ApiService.instance?.currentUser;
                                final usuario = currentUser != null
                                    ? (currentUser.nombre?.isNotEmpty == true
                                          ? currentUser.nombre
                                          : currentUser.username)
                                    : null;
                                final startStr = box.startTime != null
                                    ? DateFormat(
                                        'yyyy-MM-dd HH:mm:ss',
                                      ).format(box.startTime!)
                                    : null;
                                final endStr = DateFormat(
                                  'yyyy-MM-dd HH:mm:ss',
                                ).format(DateTime.now());

                                final audit = <String, dynamic>{
                                  'nr_orden': _orderController.text.trim(),
                                  'nr_sku': _skuController.text.trim(),
                                  'nr_unidades': _plannedUnits,
                                  'tipo_etiqueta': _selectedType?.displayName,
                                  'fecha': DateFormat(
                                    'yyyy-MM-dd',
                                  ).format(_productionDate),
                                  'fecha_inicio': startStr,
                                  'fecha_finalizacion': endStr,
                                  'usuario': usuario,
                                  'tipo_etiqueta_id': _selectedType?.id,
                                  'nr_box': box.boxNumber,
                                  'nr_unidades_box': box.units,
                                  'ean': _ean ?? '',
                                  'serial_old': entry.controller.text.trim(),
                                  'serial_new': entry.label,
                                };

                                final resp = await client2.post(
                                  '/serials/add_registry',
                                  jsonBody: audit,
                                );
                                if (resp.ok) {
                                  entry.registered = true;
                                  entry.isValid = true;
                                  // capture backend id if returned so the entry can be edited later
                                  int? returnedId;
                                  if (resp.body is Map &&
                                      resp.body['id'] != null) {
                                    try {
                                      returnedId = (resp.body['id'] as num)
                                          .toInt();
                                    } catch (_) {
                                      returnedId = null;
                                    }
                                  }
                                  entry.registryId = returnedId;
                                  try {
                                    final Map<String, dynamic> map = {
                                      'old': entry.controller.text.trim(),
                                      'new': entry.label,
                                    };
                                    if (returnedId != null)
                                      map['id'] = returnedId;
                                    _registeredMappings.add(map);
                                  } catch (_) {}

                                  // If last entry, finalize box similar to previous flow
                                  if (index == box.entries.length - 1) {
                                    final endTime = DateTime.now();
                                    box.endTime = endTime;
                                    _boxTimer?.cancel();
                                    _boxElapsed = Duration.zero;
                                    setState(() {
                                      _consumedLabels.addAll(box.labels);
                                      _history.add(
                                        BoxHistoryEntry(
                                          boxNumber: box.boxNumber,
                                          units: box.units,
                                          submittedAt: DateTime.now(),
                                          lastLabel: box.entries.isNotEmpty
                                              ? box.entries.last.label
                                              : null,
                                          records: box.entries.map((e) {
                                            return {
                                              'serial_old': e.controller.text
                                                  .trim(),
                                              'serial_new': e.label,
                                              'nr_box': box.boxNumber,
                                              'nr_unidades_box': box.units,
                                              'fecha': DateFormat(
                                                'yyyy-MM-dd',
                                              ).format(_productionDate),
                                              'fecha_finalizacion': DateFormat(
                                                'yyyy-MM-dd HH:mm:ss',
                                              ).format(DateTime.now()),
                                              'nr_sku': _skuController.text
                                                  .trim(),
                                              'nr_orden': _orderController.text
                                                  .trim(),
                                              'id': e.registryId,
                                            };
                                          }).toList(),
                                        ),
                                      );
                                      _activeBox?.dispose();
                                      _activeBox = null;
                                      final nextBox = int.tryParse(
                                        box.boxNumber,
                                      );
                                      if (nextBox != null) {
                                        _boxNumberController.text =
                                            (nextBox + 1).toString();
                                      } else {
                                        _boxNumberController.clear();
                                      }
                                      _boxUnitsController.clear();
                                      if (_consumedLabels.length >=
                                          _plannedUnits) {
                                        _completionMessage =
                                            'Se registraron todas las $_plannedUnits unidades.';
                                      } else {
                                        // If order not complete, focus on box number for next box
                                        _boxNumberFocus.requestFocus();
                                      }
                                    });

                                    // PLAY BOX FINISHED SOUND
                                    SoundPlayer.playBoxComplete();

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Caja ${box.boxNumber} registrada.',
                                        ),
                                      ),
                                    );
                                    try {
                                      final newSerials = box.labels;
                                      final oldSerials = box.entries
                                          .map((e) => e.controller.text.trim())
                                          .toList();
                                      await _printForBox(
                                        box.boxNumber,
                                        newSerials,
                                        oldSerials,
                                        box.units,
                                      );
                                    } catch (_) {}

                                    // Check backend and trigger logic
                                    // debugPrint(
                                    //   'DEBUG: (Single) Calling _checkAndTriggerCompletion...',
                                    // );
                                    if (mounted &&
                                        await _checkAndTriggerCompletion()) {
                                      // debugPrint('DEBUG: (Single) Completion MET.');
                                      if (!mounted) return;
                                      final doPrint = await showDialog<bool>(
                                        context: context,
                                        builder: (dctx) => AlertDialog(
                                          title: const Text(
                                            'Proceso completado',
                                          ),
                                          content: const Text(
                                            'Se registraron todas las unidades. ¿Deseas imprimir una etiqueta final con todos los S/N?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(dctx).pop(false),
                                              child: const Text('No'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.of(dctx).pop(true),
                                              child: const Text('Sí, imprimir'),
                                            ),
                                          ],
                                        ),
                                      );
                                      // debugPrint(
                                      //   'DEBUG: (Single) Print dialog closed. doPrint=$doPrint',
                                      // );
                                      if (doPrint == true)
                                        await _printFinalLabel();

                                      if (!mounted) {
                                        // debugPrint(
                                        //   'DEBUG: (Single) Not mounted after print.',
                                        // );
                                        return;
                                      }
                                      // debugPrint(
                                      //   'DEBUG: (Single) Showing reset dialog...',
                                      // );

                                      await showDialog<void>(
                                        context: context,
                                        builder: (dctx) => AlertDialog(
                                          title: const Text(
                                            'Proceso completado',
                                          ),
                                          content: Text(
                                            'Se registraron todas las $_plannedUnits unidades. El flujo se reiniciará.',
                                          ),
                                          actions: [
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.of(dctx).pop(),
                                              child: const Text('Aceptar'),
                                            ),
                                          ],
                                        ),
                                      );
                                      // debugPrint('DEBUG: (Single) Reset dialog closed.');
                                      if (!mounted) return;
                                      // debugPrint('DEBUG: (Single) Resetting workflow...');
                                      _resetWorkflow();
                                    }
                                  } else {
                                    // Focus already moved at the start of onSubmitted for speed
                                  }
                                } else {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error registrando S/N: ${resp.statusCode}',
                                      ),
                                    ),
                                  );
                                  if (!mounted) return;
                                  FocusScope.of(
                                    context,
                                  ).requestFocus(entry.focusNode);
                                }
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error registrando S/N: $e'),
                                  ),
                                );
                                if (!mounted) return;
                                FocusScope.of(
                                  context,
                                ).requestFocus(entry.focusNode);
                              }
                            } finally {
                              entry.submitting = false;
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withOpacity(.25),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant.withOpacity(.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nuevo Serial',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                entry.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _registeringBox ? null : _submitBox,
            icon: _registeringBox
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.inventory_outlined),
            label: Text(_registeringBox ? 'Registrando...' : 'Registrar caja'),
          ),
        ),
      ],
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) return const Text('Aún no hay cajas registradas.');
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _history.length,
      separatorBuilder: (_, __) => const Divider(height: 1, thickness: .2),
      itemBuilder: (_, index) {
        final entry = _history[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ExpansionTile(
            title: Row(
              children: [
                Text(
                  'Caja #${entry.boxNumber}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Text('${entry.units} unidades'),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('dd MMM HH:mm').format(entry.submittedAt)),
                if (entry.lastLabel != null)
                  Text(
                    'Último: ${entry.lastLabel}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.print_outlined),
              onPressed: () async {
                final newSerials = entry.records
                    .map((r) => (r['serial_new'] ?? '').toString())
                    .where((s) => s.isNotEmpty)
                    .toList();
                final oldSerials = entry.records
                    .map((r) => (r['serial_old'] ?? '').toString())
                    .where((s) => s.isNotEmpty)
                    .toList();
                await _printForBox(
                  entry.boxNumber,
                  newSerials,
                  oldSerials,
                  entry.units,
                );
              },
            ),
            children: entry.records.map((r) {
              final oldS = (r['serial_old'] ?? '').toString();
              final newS = (r['serial_new'] ?? '').toString();
              final date = (r['fecha'] ?? '').toString();
              final sku = (r['nr_sku'] ?? '').toString();
              final order = (r['nr_orden'] ?? '').toString();
              return ListTile(
                title: Text('Antiguo: $oldS    ->    Nuevo: $newS'),
                subtitle: Text('Orden: $order  SKU: $sku\nFecha: $date'),
                isThreeLine: true,
                dense: true,
              );
            }).toList(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fieldWidth = MediaQuery.of(context).size.width > 960
        ? 420.0
        : double.infinity;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('CAMBIO DE SERIAL (RMA)'),
        centerTitle: true,
        backgroundColor: Colors.black.withValues(alpha: .15),
        elevation: 0,
      ),
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 1.2),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: EdgeNavHandle(
                  width: 28,
                  user: ApiService.instance?.currentUser,
                  currentRoute: '/serials/change',
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.surface.withOpacity(.98),
                              theme.colorScheme.surfaceContainerHighest
                                  .withOpacity(.98),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: theme.colorScheme.surfaceTint.withOpacity(
                              .06,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(.18),
                              blurRadius: 34,
                              offset: const Offset(0, 20),
                            ),
                            BoxShadow(
                              color: Colors.white.withOpacity(.02),
                              blurRadius: 8,
                              offset: const Offset(-4, -4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _sectionHeader(
                                      '1. Datos generales',
                                      Icons.receipt_long,
                                      subtitle:
                                          'Introduce los datos de la orden y SKU',
                                    ),
                                    const SizedBox(height: 12),
                                    Form(
                                      key: _generalFormKey,
                                      child: Wrap(
                                        spacing: 24,
                                        runSpacing: 20,
                                        children: [
                                          SizedBox(
                                            width: fieldWidth,
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: TextFormField(
                                                    controller:
                                                        _orderController,
                                                    focusNode: _orderFocus,
                                                    enabled: !_configLocked,
                                                    decoration:
                                                        _inputDecoration(
                                                          'Nr. de orden',
                                                          Icons.receipt_long,
                                                          enabled:
                                                              !_configLocked,
                                                        ),
                                                    inputFormatters: [
                                                      FilteringTextInputFormatter.allow(
                                                        RegExp('[A-Za-z0-9-]'),
                                                      ),
                                                      OrderInputFormatter(),
                                                    ],
                                                    textInputAction:
                                                        TextInputAction.done,
                                                    onFieldSubmitted: (_) async {
                                                      await _triggerOrderResumeSearch();
                                                    },
                                                    validator: (value) {
                                                      final v =
                                                          value
                                                              ?.trim()
                                                              .toUpperCase() ??
                                                          '';
                                                      final pattern = RegExp(
                                                        r'^[A-Z0-9]{2}-[A-Z0-9]{5}-[A-Z0-9]{2}$',
                                                      );
                                                      if (v.isEmpty) {
                                                        return 'Introduce el número de orden';
                                                      }
                                                      if (!pattern.hasMatch(
                                                        v,
                                                      )) {
                                                        return 'Formato requerido: XX-XXXXX-XX';
                                                      }
                                                      return null;
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                SizedBox(
                                                  width: 44,
                                                  height: 44,
                                                  child: _checkingOrder
                                                      ? const Padding(
                                                          padding:
                                                              EdgeInsets.all(
                                                                10,
                                                              ),
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth:
                                                                    2.2,
                                                              ),
                                                        )
                                                      : IconButton(
                                                          icon: const Icon(
                                                            Icons.search,
                                                          ),
                                                          focusNode: FocusNode(
                                                            canRequestFocus:
                                                                false,
                                                          ),
                                                          onPressed:
                                                              _configLocked
                                                              ? null
                                                              : () async =>
                                                                    _triggerOrderResumeSearch(),
                                                        ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            width: fieldWidth,
                                            child: TextFormField(
                                              controller: _skuController,
                                              enabled: !_configLocked,
                                              decoration: _inputDecoration(
                                                'Nr. SKU',
                                                Icons.qr_code,
                                                enabled: !_configLocked,
                                              ),
                                              validator: (value) =>
                                                  value == null ||
                                                      value.trim().isEmpty
                                                  ? 'Introduce el SKU'
                                                  : null,
                                            ),
                                          ),
                                          SizedBox(
                                            width: fieldWidth,
                                            child: TextFormField(
                                              controller: _unitsController,
                                              enabled: !_configLocked,
                                              decoration: _inputDecoration(
                                                'Nr. unidades totales',
                                                Icons.onetwothree,
                                                enabled: !_configLocked,
                                              ),
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                              ],
                                              validator: (value) {
                                                final parsed = int.tryParse(
                                                  value ?? '',
                                                );
                                                if (parsed == null ||
                                                    parsed <= 0) {
                                                  return 'Introduce un entero positivo';
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                          SizedBox(
                                            width: fieldWidth,
                                            child: InkWell(
                                              onTap: _configLocked
                                                  ? null
                                                  : _pickDate,
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              child: InputDecorator(
                                                decoration: _inputDecoration(
                                                  'Fecha de producción',
                                                  Icons.event,
                                                  enabled: !_configLocked,
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      DateFormat(
                                                        'dd MMM yyyy',
                                                        'es',
                                                      ).format(_productionDate),
                                                      style: theme
                                                          .textTheme
                                                          .bodyLarge,
                                                    ),
                                                    const Icon(
                                                      Icons.edit_calendar,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    SwitchListTile.adaptive(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('Continuar secuencia'),
                                      subtitle: const Text(
                                        'Define manualmente el inicio de la secuencia.',
                                      ),
                                      value: _continueSequence,
                                      onChanged: _configLocked
                                          ? null
                                          : (value) => setState(() {
                                              _continueSequence = value;
                                            }),
                                    ),
                                    if (_continueSequence)
                                      SizedBox(
                                        width: fieldWidth,
                                        child: TextFormField(
                                          controller: _startSeqController,
                                          enabled: !_configLocked,
                                          decoration: _inputDecoration(
                                            'Inicio de secuencia',
                                            Icons.format_list_numbered,
                                            enabled: !_configLocked,
                                          ),
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _sectionHeader(
                                      '2. Selección de tipología de etiqueta según artículo',
                                      Icons.label,
                                      subtitle: 'Elige operador y tipo',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildOperatorSelector(),
                                    const SizedBox(height: 16),
                                    _buildTypeSelector(),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed: _configLocked
                                              ? _resetWorkflow
                                              : null,
                                          focusNode: FocusNode(
                                            canRequestFocus: false,
                                          ),
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('Reiniciar'),
                                        ),
                                        const SizedBox(width: 12),
                                        FilledButton.icon(
                                          onPressed:
                                              _configLocked || _generatingLabels
                                              ? null
                                              : _prepareLabels,
                                          icon: _generatingLabels
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2.2,
                                                      ),
                                                )
                                              : const Icon(Icons.auto_awesome),
                                          label: Text(
                                            _generatingLabels
                                                ? 'Generando...'
                                                : 'Generar etiquetas',
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_generationError != null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        _generationError!,
                                        style: TextStyle(
                                          color: theme.colorScheme.error,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            if (_configLocked) ...[
                              Divider(
                                color: theme.colorScheme.outline.withValues(
                                  alpha: .4,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _sectionHeader(
                                '3. Registro por cajas',
                                Icons.inventory_2_outlined,
                                subtitle: 'Registra S/N por caja',
                              ),
                              const SizedBox(height: 12),
                              _buildProgressChips(),
                              const SizedBox(height: 12),

                              Form(
                                key: _boxFormKey,
                                child: Wrap(
                                  spacing: 24,
                                  runSpacing: 20,
                                  children: [
                                    SizedBox(
                                      width: fieldWidth,
                                      child: TextFormField(
                                        controller: _boxNumberController,
                                        focusNode: _boxNumberFocus,
                                        decoration: _inputDecoration(
                                          'Nr. de caja',
                                          Icons.inbox,
                                        ),
                                        validator: (value) =>
                                            value == null ||
                                                value.trim().isEmpty
                                            ? 'Introduce el número de box'
                                            : null,
                                        textInputAction: TextInputAction.next,
                                        onFieldSubmitted: (_) => FocusScope.of(
                                          context,
                                        ).requestFocus(_boxUnitsFocus),
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: TextFormField(
                                        controller: _boxUnitsController,
                                        focusNode: _boxUnitsFocus,
                                        decoration: _inputDecoration(
                                          'Unidades en caja',
                                          Icons.format_list_numbered,
                                        ),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        textInputAction: TextInputAction.done,
                                        onFieldSubmitted: (_) =>
                                            _confirmAndStartBox(),
                                        validator: (value) {
                                          final parsed = int.tryParse(
                                            value ?? '',
                                          );
                                          if (parsed == null || parsed <= 0) {
                                            return 'Introduce un número válido';
                                          }
                                          if (parsed > _plannedUnits) {
                                            return 'No puede superar el total planificado';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  FilledButton.icon(
                                    onPressed: _activeBox == null
                                        ? _startBox
                                        : null,
                                    focusNode: FocusNode(
                                      canRequestFocus: false,
                                    ),
                                    icon: const Icon(
                                      Icons.inventory_2_outlined,
                                    ),
                                    label: const Text('Crear caja'),
                                  ),
                                  const SizedBox(width: 12),
                                  if (_boxError != null)
                                    Expanded(
                                      child: Text(
                                        _boxError!,
                                        style: TextStyle(
                                          color: theme.colorScheme.error,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              _buildActiveBoxTable(),
                              const SizedBox(height: 24),
                              Text(
                                'Historial de cajas',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildHistory(),
                              if (_completionMessage != null) ...[
                                const SizedBox(height: 16),
                                Card(
                                  color: theme.colorScheme.primaryContainer,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          color: theme
                                              .colorScheme
                                              .onPrimaryContainer,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _completionMessage!,
                                            style: theme.textTheme.bodyLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class LabelOperatorOption {
  const LabelOperatorOption({
    required this.name,
    required this.totalTypes,
    required this.activeTypes,
  });

  final String name;
  final int totalTypes;
  final int activeTypes;

  factory LabelOperatorOption.fromJson(Map<dynamic, dynamic> map) {
    final operador = (map['operador'] ?? map['name'] ?? '').toString();
    int parse(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
    final total = parse(map['tipos'] ?? map['total'] ?? map['total_types']);
    final activos = parse(
      map['activos'] ?? map['active'] ?? map['active_types'],
    );
    return LabelOperatorOption(
      name: operador,
      totalTypes: total == 0 ? activos : total,
      activeTypes: activos == 0 ? total : activos,
    );
  }
}

class LabelTypeOption {
  static const int defaultMaxUnits = 5000;

  const LabelTypeOption({
    required this.id,
    required this.operatorName,
    required this.article,
    required this.sapClient,
    required this.codeLetter,
    required this.active,
    required this.minUnits,
    required this.maxUnits,
  });

  final int? id;
  final String operatorName;
  final String? article;
  final String? sapClient;
  final String? codeLetter;
  final bool active;
  final int minUnits;
  final int? maxUnits;

  String get displayName {
    if ((article ?? '').isNotEmpty) return article!;
    if ((codeLetter ?? '').isNotEmpty) return codeLetter!;
    return 'Tipo ${id ?? ''}';
  }

  factory LabelTypeOption.fromJson(Map<dynamic, dynamic> map) {
    int? parseInt(dynamic value) =>
        value == null ? null : int.tryParse(value.toString());
    bool parseBool(dynamic value) {
      if (value is bool) return value;
      final text = value?.toString().toLowerCase();
      return text == '1' || text == 'true' || text == 'yes';
    }

    final min =
        parseInt(map['min_unidades'] ?? map['minUnits'] ?? map['min_units']) ??
        1;
    final max = parseInt(
      map['max_unidades'] ?? map['maxUnits'] ?? map['max_units'],
    );
    return LabelTypeOption(
      id: parseInt(map['id']),
      operatorName: (map['operador'] ?? '').toString(),
      article: map['articulo']?.toString(),
      sapClient: map['sap_cliente']?.toString(),
      codeLetter: map['codigo_letra']?.toString(),
      active: parseBool(map['activo']),
      minUnits: min <= 0 ? 1 : min,
      maxUnits: (max != null && max > 0) ? max : null,
    );
  }
}

class _BoxEntryField {
  _BoxEntryField({required this.label}) : controller = TextEditingController() {
    focusNode = FocusNode();
  }

  final String label;
  final TextEditingController controller;
  late FocusNode focusNode;
  // Whether this specific entry has been persisted to the server
  bool registered = false;
  // Backend record id for this registered mapping (if returned)
  int? registryId;
  // Validation UI state
  bool isValid = false;
  bool isInvalid = false;
  String? errorMessage;
  bool submitting = false;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _BoxSession {
  _BoxSession({
    required this.boxNumber,
    required this.units,
    required List<String> labels,
  }) : entries = labels.map((label) => _BoxEntryField(label: label)).toList();

  final String boxNumber;
  final int units;
  final List<_BoxEntryField> entries;
  DateTime? startTime;
  DateTime? endTime;

  List<String> get labels => entries.map((e) => e.label).toList();

  void dispose() {
    for (final entry in entries) {
      entry.dispose();
    }
  }
}

class BoxHistoryEntry {
  const BoxHistoryEntry({
    required this.boxNumber,
    required this.units,
    required this.submittedAt,
    this.lastLabel,
    this.records = const [],
  });

  final String boxNumber;
  final int units;
  final DateTime submittedAt;
  final String? lastLabel;
  final List<Map<String, dynamic>> records;
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.secondaryContainer.withValues(alpha: .6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer.withValues(
                alpha: .7,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
