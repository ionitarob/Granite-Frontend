import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/api_service.dart';
import '../../services/orderops_service.dart';
import '../../services/order_input_formatter.dart';
import '../../models/agent_models.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';

import 'order_detail_screen.dart';
import '../../widgets/multi_family_selection_dialog.dart';

class OrderQueueScreen extends StatefulWidget {
  const OrderQueueScreen({super.key});

  @override
  State<OrderQueueScreen> createState() => _OrderQueueScreenState();
}

class _OrderQueueScreenState extends State<OrderQueueScreen>
    with SingleTickerProviderStateMixin {
  OrderOpsService? _orderOpsService;
  late TabController _tabController;

  // Aprovisionamiento tab state
  List<AprovisionamientoRecord> _aprovisionamiento = [];
  bool _aprovLoading = false;
  final Set<int> _expandedAprov = {};

  // Mis Tareas tab state
  List<Map<String, dynamic>> _myTasks = [];
  bool _myTasksLoading = false;
  bool _myTasksShowTemplates = false;
  List<ChecklistTemplate> _templates = [];
  bool _templatesLoading = false;

  // Bulk selection state
  bool _selectionMode = false;
  final Set<int> _selectedOrderIds = {};

  List<AgentOrder> _orders = [];
  bool _loading = true;
  bool _syncingOrders = false;
  bool _importingCsv = false;
  bool _exportingOrders = false;
  double _syncProgress = 0.0;
  String _syncMessage = '';
  String? _error;
  Timer? _refreshTimer;
  OverlayEntry? _edgeOverlay;
  bool _autoFamilyScanInProgress = false;
  final Set<int> _autoFamilyScannedOrderIds = <int>{};

  // Filters
  final TextEditingController _searchController = TextEditingController();
  String? _selectedEstado;
  bool _filterByMe = false;
  bool _filterNoQuality = false;

  // Performance Cache: Avoid redundant computations in build()
  List<AgentOrder> _filteredOrdersList = [];
  Map<String, List<AgentOrder>> _groupedOrders = {};
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _aprovisionamiento.isEmpty && !_aprovLoading) {
        _loadAprovisionamiento();
      }
      if (_tabController.index == 2 && _myTasks.isEmpty && !_myTasksLoading) {
        _loadMyTasks();
      }
    });
    // Initialize service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      _orderOpsService = OrderOpsService(apiService.client);
      _loadOrders();
      // Auto-refresh every 30 seconds
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _loadOrders(silent: true),
      );

      // PERFORMANCE: Debounce search to prevent rebuilds on every keystroke
      _searchController.addListener(_onSearchChanged);

      // Insert overlay for sidebar only on desktop widths.
      final logicalWidth =
          MediaQuery.maybeOf(context)?.size.width ??
          (View.of(context).physicalSize.width /
              View.of(context).devicePixelRatio);
      final isMobile = logicalWidth < 900;

      if (mounted && !isMobile) {
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
                    user: Provider.of<ApiService>(
                      ctx,
                      listen: false,
                    ).currentUser,
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
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    _searchDebounce?.cancel();
    _edgeOverlay?.remove();
    _edgeOverlay = null;
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAprovisionamiento() async {
    if (_orderOpsService == null) return;
    setState(() => _aprovLoading = true);
    try {
      final list = await _orderOpsService!.getAprovisionamiento();
      if (mounted) setState(() => _aprovisionamiento = list);
    } finally {
      if (mounted) setState(() => _aprovLoading = false);
    }
  }

  Future<void> _loadMyTasks() async {
    if (_orderOpsService == null) return;
    setState(() => _myTasksLoading = true);
    try {
      final currentUser = ApiService.instance?.currentUser?.username ?? '';
      final list = await _orderOpsService!.getMyTasks(assignedTo: currentUser);
      if (mounted) setState(() => _myTasks = list);
    } finally {
      if (mounted) setState(() => _myTasksLoading = false);
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _applyFilters();
    });
  }

  /// PERFORMANCE: Centralized filtering and grouping logic.
  /// This is called only when data or filters change, not on every build cycle.
  void _applyFilters() {
    var list = _orders;

    // 1. Filter by Status
    if (_selectedEstado != null) {
      list = list.where((o) => o.estado == _selectedEstado).toList();
    }

    // 2. Filter by "My Orders"
    if (_filterByMe) {
      final currentUser = Provider.of<ApiService>(context, listen: false).currentUser;
      if (currentUser != null) {
        list = list
            .where(
              (o) =>
                  o.assignedTo == currentUser.username ||
                  o.assignedTo == currentUser.id.toString(),
            )
            .toList();
      }
    }

    // 3. Filter: Sin proceso de calidad (no quality photos, excluding Facturada)
    if (_filterNoQuality) {
      list = list.where((o) => o.estado != 'Facturada' && o.qualityPhotosCount == 0).toList();
    }

    // 4. Filter by Search Query (Using pre-calculated searchable fields)
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      final cleanQuery = query.replaceAll('-', '');
      list = list.where((o) {
        final nbrMatch = o.searchableOrderNbr.contains(cleanQuery);
        final customerMatch = o.searchableCustomer.contains(query);
        final descMatch = o.searchableDesc.contains(query);
        return nbrMatch || customerMatch || descMatch;
      }).toList();
    }

    // 4. Group by Month
    final Map<String, List<AgentOrder>> grouped = {};
    for (final order in list) {
      final date = order.orderDate ?? order.createdAt ?? DateTime.now();
      final monthStr = DateFormat('MMMM yyyy', 'es').format(date);
      final capitalizedMonth = monthStr[0].toUpperCase() + monthStr.substring(1).toLowerCase();
      if (!grouped.containsKey(capitalizedMonth)) {
        grouped[capitalizedMonth] = [];
      }
      grouped[capitalizedMonth]!.add(order);
    }

    setState(() {
      _filteredOrdersList = list;
      _groupedOrders = grouped;
    });
  }

  String _normalizedRole() {
    final raw = (ApiService.instance?.currentUser?.role ?? '')
        .trim()
        .toLowerCase();
    if (raw.startsWith('role_')) return raw.substring(5);
    return raw;
  }

  bool get _canEditProyectoOrFamily {
    final role = _normalizedRole();
    return role == 'admin' || role == 'chief' || role.contains('clerc');
  }

  Future<void> _loadOrders({bool silent = false}) async {
    if (_orderOpsService == null) return;
    if (!silent) setState(() => _loading = true);

    try {
      final allOrders = await _orderOpsService!.getAgentOrders(limit: 1000);
      final orders = allOrders.toList();

      // PERFORMANCE: Change detection. If no functional changes, skip heavy UI updates.
      if (silent && _orders.length == orders.length) {
        bool identical = true;
        for (int i = 0; i < orders.length; i++) {
          if (_orders[i].idnbr != orders[i].idnbr ||
              _orders[i].estado != orders[i].estado ||
              _orders[i].assignedTo != orders[i].assignedTo) {
            identical = false;
            break;
          }
        }
        if (identical) return;
      }

      if (mounted) {
        _orders = orders;
        _applyFilters(); // Computes _filteredOrdersList and _groupedOrders
        setState(() {
          _error = null;
          _loading = false;
        });

        unawaited(_autoAssignFamiliesFromQueue(orders));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool _detailContainsMasterKeyword(OrderOpsDetail detail) {
    final source = detail.sourceOrder;
    if (source == null) return false;
    final lines = source['lines'];
    if (lines is! List) return false;

    for (final raw in lines) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final description = (row['DESCRIP1'] ?? row['description'] ?? '')
          .toString()
          .toUpperCase();
      if (description.contains('MASTER')) {
        return true;
      }
    }
    return false;
  }

  Future<void> _autoAssignFamiliesFromQueue(List<AgentOrder> orders) async {
    if (_orderOpsService == null || _autoFamilyScanInProgress) return;

    final candidates = orders
        .where((o) {
          final family = (o.family ?? '').trim();
          return family.isEmpty &&
              !_autoFamilyScannedOrderIds.contains(o.idnbr);
        })
        .take(25)
        .toList(growable: false);

    if (candidates.isEmpty) return;

    _autoFamilyScanInProgress = true;
    var assignedCount = 0;

    try {
      for (final order in candidates) {
        _autoFamilyScannedOrderIds.add(order.idnbr);

        try {
          final detail = await _orderOpsService!.getAgentOrder(order.idnbr);
          final currentFamily = (detail.agentOrder.family ?? '')
              .trim()
              .toUpperCase();

          if (currentFamily.contains('MASTERIZ')) {
            continue;
          }
          if (!_detailContainsMasterKeyword(detail)) {
            continue;
          }

          final ok = await _orderOpsService!.updateAgentOrder(
            detail.agentOrder.idnbr,
            family: 'MASTERIZACIÓN',
            reason: 'Autoasignación por línea de pedido con palabra MASTER',
          );
          if (ok) {
            assignedCount += 1;
          }
        } catch (e) {
          debugPrint(
            'OrderQueueScreen auto family assign failed for ${order.idnbr}: $e',
          );
        }
      }
    } finally {
      _autoFamilyScanInProgress = false;
    }

    if (assignedCount > 0 && mounted) {
      debugPrint(
        'OrderQueueScreen auto-assigned MASTERIZACION for $assignedCount order(s).',
      );
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            assignedCount == 1
                ? 'Familia autoasignada en 1 orden'
                : 'Familia autoasignada en $assignedCount ordenes',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      await _loadOrders(silent: true);
    }
  }

  Future<void> _handleSyncOrders() async {
    if (_orderOpsService == null || _syncingOrders) return;

    setState(() {
      _syncingOrders = true;
      _syncProgress = 0.0;
      _syncMessage = 'Iniciando sincronización...';
    });

    try {
      final stream = _orderOpsService!.ingestOrders();
      await for (final update in stream) {
        if (mounted) {
          setState(() {
            if (update.containsKey('percent')) {
              _syncProgress = (update['percent'] as num).toDouble() / 100.0;
            }
            if (update.containsKey('message')) {
              _syncMessage = update['message'] as String;
            }
            if (update.containsKey('error')) {
              throw Exception(update['error']);
            }
          });
        }
        if (update['done'] == true) {
          break;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pedidos sincronizados correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        _loadOrders(silent: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncingOrders = false;
          _syncProgress = 0.0;
          _syncMessage = '';
        });
      }
    }
  }

  Future<void> _handleImportCsv() async {
    if (_importingCsv) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );

    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;

    setState(() => _importingCsv = true);

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final res = await apiService.client.postMultipart(
        '/docgen/import/csv',
        fileFieldName: 'file',
        fileName: file.name,
        fileBytes: file.bytes!,
      );

      if (!mounted) return;

      if (res.ok) {
        final body = res.body as Map;
        final summary = body['summary'] as Map;
        final total = summary['total'] ?? 0;
        final success = summary['success'] ?? 0;
        final failed = summary['failed'] ?? 0;

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Importación Completada'),
            content: Text(
              'Total filas: $total\n'
              'Éxito: $success\n'
              'Fallidos: $failed',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
        _loadOrders();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al importar: ${res.statusCode}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _importingCsv = false);
    }
  }

  Future<void> _handleExportOrders() async {
    if (_exportingOrders || _orderOpsService == null) return;
    setState(() => _exportingOrders = true);
    try {
      final bytes = await _orderOpsService!.exportOrdersExcel();
      if (!mounted) return;

      final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
      final fileName = 'ordenes_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exportado: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exportando: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingOrders = false);
    }
  }

  void _onOrderTap(AgentOrder order) {
    if (_selectionMode) {
      setState(() {
        if (_selectedOrderIds.contains(order.idnbr)) {
          _selectedOrderIds.remove(order.idnbr);
        } else {
          _selectedOrderIds.add(order.idnbr);
        }
      });
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(orderId: order.idnbr),
          ),
        )
        .then((_) => _loadOrders(silent: true));
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedOrderIds.clear();
    });
  }

  void _selectAll() {
    setState(() {
      _selectedOrderIds.addAll(_filteredOrdersList.map((o) => o.idnbr));
    });
  }

  Future<void> _showBulkConfigDialog() async {
    if (_orderOpsService == null || _selectedOrderIds.isEmpty) return;

    List<String> families = [];
    try {
      families = await _orderOpsService!.getCatalogFamilies();
    } catch (_) {}
    families = {...families}.toList()..sort();

    if (!mounted) return;

    List<String> selectedFamilies = [];
    String? prioridad;
    final notaCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Configurar ${_selectedOrderIds.length} órdenes'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Servicios / Familia',
                  style: Theme.of(ctx).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: families.map((f) {
                    final sel = selectedFamilies.contains(f);
                    return FilterChip(
                      label: Text(f, style: const TextStyle(fontSize: 12)),
                      selected: sel,
                      onSelected: (v) => setLocal(() {
                        v ? selectedFamilies.add(f) : selectedFamilies.remove(f);
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: prioridad,
                  decoration: const InputDecoration(
                    labelText: 'Prioridad',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: '1', child: Text('Alta')),
                    DropdownMenuItem(value: '2', child: Text('Media')),
                    DropdownMenuItem(value: '3', child: Text('Baja')),
                  ],
                  onChanged: (v) => setLocal(() => prioridad = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Observación (opcional)',
                    isDense: true,
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    ).then((confirmed) async {
      notaCtrl.dispose();
      if (confirmed != true) return;
      if (selectedFamilies.isEmpty && prioridad == null) return;
      await _executeBulkUpdate(
        family: selectedFamilies.isNotEmpty ? selectedFamilies.first : null,
        subfamilies: selectedFamilies.isNotEmpty ? selectedFamilies : null,
        prioridad: prioridad,
        observation: notaCtrl.text.trim().isEmpty ? null : notaCtrl.text.trim(),
      );
    });
  }

  Future<void> _showBulkEstadoDialog() async {
    if (_selectedOrderIds.isEmpty) return;
    String? estado;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Cambiar estado — ${_selectedOrderIds.length} órdenes'),
          content: DropdownButtonFormField<String>(
            value: estado,
            decoration: const InputDecoration(labelText: 'Nuevo estado', isDense: true),
            items: const [
              DropdownMenuItem(value: '1', child: Text('Validada')),
              DropdownMenuItem(value: '2', child: Text('Pendiente')),
              DropdownMenuItem(value: '3', child: Text('En Ejecución')),
              DropdownMenuItem(value: '5', child: Text('Finalizada')),
              DropdownMenuItem(value: '6', child: Text('Facturada')),
            ],
            onChanged: (v) => setLocal(() => estado = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: estado == null ? null : () => Navigator.of(ctx).pop(true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && estado != null) {
      await _executeBulkUpdate(estado: estado);
    }
  }

  Future<void> _showBulkObservationDialog() async {
    if (_selectedOrderIds.isEmpty) return;
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Añadir nota — ${_selectedOrderIds.length} órdenes'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Observación a añadir a todas las órdenes seleccionadas...',
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (confirmed == true && text.isNotEmpty) {
      await _executeBulkUpdate(observation: text);
    }
  }

  Future<void> _showBulkAssigneeDialog() async {
    if (_selectedOrderIds.isEmpty || _orderOpsService == null) return;
    List<Map<String, dynamic>> employees = [];
    try {
      employees = await _orderOpsService!.getEmployees(limit: 100);
    } catch (_) {}
    if (!mounted) return;

    Map<String, dynamic>? picked;
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> filtered = List.from(employees);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Asignar — ${_selectedOrderIds.length} órdenes'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Buscar empleado…',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: (q) => setLocal(() {
                    final ql = q.toLowerCase();
                    filtered = employees
                        .where((e) => (e['display_name'] ?? '').toString().toLowerCase().contains(ql))
                        .toList();
                  }),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final e = filtered[i];
                      final isSelected = picked?['id'] == e['id'];
                      return ListTile(
                        dense: true,
                        title: Text(e['display_name']?.toString() ?? ''),
                        subtitle: e['empresa_nombre'] != null
                            ? Text(e['empresa_nombre'].toString(),
                                style: const TextStyle(fontSize: 11))
                            : null,
                        selected: isSelected,
                        selectedTileColor: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.1),
                        onTap: () => setLocal(() => picked = isSelected ? null : e),
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: Theme.of(ctx).colorScheme.primary, size: 18)
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: picked == null ? null : () => Navigator.of(ctx).pop(true),
              child: const Text('Asignar'),
            ),
          ],
        ),
      ),
    ).then((confirmed) async {
      searchCtrl.dispose();
      if (confirmed == true && picked != null) {
        await _executeBulkUpdate(
          assignedTo: picked!['id']?.toString(),
          assignedToName: picked!['display_name']?.toString(),
        );
      }
    });
  }

  Future<void> _executeBulkUpdate({
    String? family,
    List<String>? subfamilies,
    String? estado,
    String? prioridad,
    String? assignedTo,
    String? assignedToName,
    String? observation,
  }) async {
    if (_orderOpsService == null || _selectedOrderIds.isEmpty) return;
    final ids = _selectedOrderIds.toList();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Actualizando ${ids.length} órdenes...'),
        duration: const Duration(seconds: 30),
      ),
    );

    try {
      final result = await _orderOpsService!.bulkUpdateOrders(
        ids,
        family: family,
        subfamilies: subfamilies,
        estado: estado,
        prioridad: prioridad,
        assignedTo: assignedTo,
        assignedToName: assignedToName,
        observation: observation,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final okCount = result['ok_count'] as int? ?? 0;
      final total = result['total'] as int? ?? ids.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$okCount/$total órdenes actualizadas'),
          backgroundColor: okCount == total ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      setState(() {
        _selectionMode = false;
        _selectedOrderIds.clear();
      });
      await _loadOrders(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildBulkActionBar(ThemeData theme) {
    if (!_selectionMode || _selectedOrderIds.isEmpty) return const SizedBox.shrink();
    final isDark = theme.brightness == Brightness.dark;
    return Positioned(
      left: 24,
      right: 24,
      bottom: 16,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(16),
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.inverseSurface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_selectedOrderIds.length} seleccionadas',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: isDark ? Colors.white : theme.colorScheme.onInverseSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _bulkAction(
                icon: Icons.settings_outlined,
                label: 'Configurar',
                onTap: _showBulkConfigDialog,
                color: theme.colorScheme.primary,
                isDark: isDark,
              ),
              const SizedBox(width: 6),
              _bulkAction(
                icon: Icons.check_circle_outline,
                label: 'Estado',
                onTap: _showBulkEstadoDialog,
                color: Colors.green,
                isDark: isDark,
              ),
              const SizedBox(width: 6),
              _bulkAction(
                icon: Icons.note_add_outlined,
                label: 'Nota',
                onTap: _showBulkObservationDialog,
                color: Colors.orange,
                isDark: isDark,
              ),
              const SizedBox(width: 6),
              _bulkAction(
                icon: Icons.person_outlined,
                label: 'Asignar',
                onTap: _showBulkAssigneeDialog,
                color: Colors.purple,
                isDark: isDark,
              ),
              const Spacer(),
              TextButton(
                onPressed: _selectAll,
                style: TextButton.styleFrom(
                  foregroundColor: isDark
                      ? Colors.white70
                      : theme.colorScheme.onInverseSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Todo', style: TextStyle(fontSize: 12)),
              ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  color: isDark ? Colors.white70 : theme.colorScheme.onInverseSurface,
                  size: 20,
                ),
                onPressed: _toggleSelectionMode,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bulkAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showManualFamilyPicker(AgentOrder order) async {
    if (!_canEditProyectoOrFamily) return;
    if (_orderOpsService == null) return;

    List<String> families = [];
    try {
      families = await _orderOpsService!.getCatalogFamilies();
    } catch (e) {
      debugPrint('Error fetching families: $e');
    }

    // Ensure catalog list includes what is already assigned (consistency fix)
    families = {...families, ...order.subfamilies}.toList();
    families.sort();

    // Sync fix: combine primary family and all subfamilies for the menu view
    final currentSelection = {
      if (order.family != null && order.family!.isNotEmpty) order.family!,
      ...order.subfamilies,
    }.toList();

    if (!mounted) return;

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => MultiFamilySelectionDialog(
        allFamilies: families,
        initiallySelected: currentSelection,
        title: 'Asignar Servicios',
      ),
    );

    if (result != null) {
      setState(() => _loading = true);
      try {
        // Sync fix: primary family should always be part of the subfamilies list
        String? primaryFamily = order.family;
        if (result.isEmpty) {
          primaryFamily = '';
        } else if (primaryFamily == null ||
            primaryFamily.isEmpty ||
            !result.contains(primaryFamily)) {
          primaryFamily = result.first;
        }

        final ok = await _orderOpsService!.updateAgentOrder(
          order.idnbr,
          family: primaryFamily,
          subfamilies: result,
          reason: 'Sync manual subfamilias desde cola: ${result.join(", ")}',
        );
        if (ok) await _loadOrders();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  // Removed _runAgent as AI triage is deprecated.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // PERFORMANCE: Reduced intensity to 0.4 to prevent GPU stuttering during scrolling.
          const AnimatedBackgroundWidget(intensity: 0.4),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Stack(
                children: [
                  Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme),
                  const SizedBox(height: 16),
                  // Tab bar
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? theme.colorScheme.surface.withOpacity(0.45)
                          : theme.colorScheme.surface.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor.withOpacity(0.12),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      indicator: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.primary.withOpacity(0.3),
                        ),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.list_alt_rounded, size: 16),
                              SizedBox(width: 8),
                              Text('Cola de Órdenes'),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 16),
                              SizedBox(width: 8),
                              Text('Aprovisionamiento'),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.task_alt_rounded, size: 16),
                              SizedBox(width: 8),
                              Text('Mis Tareas'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Tab 0 — orders list
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSearchBar(theme),
                            const SizedBox(height: 16),
                            if (_syncingOrders)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                              Colors.tealAccent,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _syncMessage,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.white70,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '${(_syncProgress * 100).toInt()}%',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.tealAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: _syncProgress,
                                        minHeight: 10,
                                        backgroundColor: Colors.white12,
                                        valueColor: const AlwaysStoppedAnimation<Color>(
                                          Colors.tealAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Expanded(child: _buildTable(theme)),
                          ],
                        ),
                        // Tab 1 — aprovisionamiento
                        _buildAprovisionamientoTab(theme),
                        // Tab 2 — mis tareas
                        _buildMyTasksTab(theme),
                      ],
                    ),
                  ),
                ],
              ),
              _buildBulkActionBar(theme),
            ],
          ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Aprovisionamiento Tab ─────────────────────────────────────────────────

  // ─── Aprovisionamiento tab ───────────────────────────────────────────────

  Widget _buildAprovisionamientoTab(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    if (_aprovLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final pending = _aprovisionamiento.where((r) => !r.isLinked).length;
    final linked = _aprovisionamiento.where((r) => r.isLinked).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (_aprovisionamiento.isNotEmpty) ...[
              _aprovStatChip('${pending} pendiente${pending == 1 ? '' : 's'}',
                  Colors.orange, theme),
              const SizedBox(width: 8),
              _aprovStatChip('${linked} enlazado${linked == 1 ? '' : 's'}',
                  Colors.green, theme),
              const Spacer(),
            ] else
              const Spacer(),
            FilledButton.icon(
              onPressed: () => _showAprovSheet(context, theme),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nuevo'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _aprovisionamiento.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 56,
                          color: theme.colorScheme.onSurface.withOpacity(0.15)),
                      const SizedBox(height: 16),
                      Text(
                        'Sin registros de aprovisionamiento',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withOpacity(0.4)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Crea uno para pre-configurar una orden antes de que entre en el sistema.\nCuando llegue, sus datos se aplican automáticamente.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withOpacity(0.3)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _aprovisionamiento.length,
                  padding: const EdgeInsets.only(bottom: 80),
                  itemBuilder: (ctx, i) =>
                      _buildAprovCard(_aprovisionamiento[i], theme, isDark),
                ),
        ),
      ],
    );
  }

  Widget _buildMyTasksTab(ThemeData theme) {
    if (_myTasksLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Group by a string key: "order:idnbr" or "aprv:aprovisionamiento_id"
    final Map<String, Map<String, dynamic>> byGroup = {};
    for (final t in _myTasks) {
      final type = t['type'] as String? ?? 'order';
      final String key;
      final String label;
      final String customer;
      if (type == 'order') {
        final idnbr = t['idnbr'] as int? ?? 0;
        key = 'order:$idnbr';
        label = t['order_nbr']?.toString() ?? idnbr.toString();
        customer = t['customer']?.toString() ?? '';
      } else {
        final aprovId = t['aprovisionamiento_id'] as int? ?? 0;
        key = 'aprv:$aprovId';
        label = t['order_nbr']?.toString() ?? 'Aprv #$aprovId';
        customer = t['customer']?.toString() ?? '';
      }
      byGroup.putIfAbsent(key, () => {
        'key': key,
        'type': type,
        'idnbr': t['idnbr'],
        'aprovisionamiento_id': t['aprovisionamiento_id'],
        'order_nbr': label,
        'customer': customer,
        'tasks': <Map<String, dynamic>>[],
      });
      (byGroup[key]!['tasks'] as List).add(t);
    }
    final groups = byGroup.values.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Segmented toggle: Tareas / Plantillas
            Container(
              height: 34,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _tabToggleBtn('Tareas', !_myTasksShowTemplates, () {
                    if (_myTasksShowTemplates) setState(() => _myTasksShowTemplates = false);
                  }, theme),
                  _tabToggleBtn('Plantillas', _myTasksShowTemplates, () {
                    if (!_myTasksShowTemplates) {
                      setState(() => _myTasksShowTemplates = true);
                      if (_templates.isEmpty && !_templatesLoading) _loadTemplates();
                    }
                  }, theme),
                ],
              ),
            ),
            const Spacer(),
            if (!_myTasksShowTemplates && _myTasks.isNotEmpty)
              _aprovStatChip(
                '${_myTasks.where((t) => t['done'] == true).length}/${_myTasks.length} hechas',
                Colors.teal,
                theme,
              ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Actualizar',
              onPressed: _myTasksShowTemplates ? _loadTemplates : _loadMyTasks,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_myTasksShowTemplates)
          Expanded(
            child: _templatesLoading
                ? const Center(child: CircularProgressIndicator())
                : _TemplateManagerSheet(
                    orderOpsService: _orderOpsService!,
                    initialTemplates: _templates,
                    theme: theme,
                  ),
          )
        else
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.task_alt_rounded,
                          size: 56,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.15)),
                      const SizedBox(height: 16),
                      Text(
                        'Sin tareas asignadas',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Las tareas asignadas a ti aparecerán aquí,\nagrupadas por orden.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: groups.length,
                  itemBuilder: (_, gi) {
                    final group = groups[gi];
                    final groupType = group['type'] as String? ?? 'order';
                    final idnbr = group['idnbr'] as int?;
                    final aprovId = group['aprovisionamiento_id'] as int?;
                    final tasks = group['tasks'] as List<Map<String, dynamic>>;
                    final done = tasks.where((t) => t['done'] == true).length;
                    final isAprov = groupType == 'aprovisionamiento';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.dividerColor.withOpacity(0.15),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          InkWell(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            onTap: idnbr != null
                                ? () => Navigator.of(context).pushNamed(
                                    '/orderops/detail', arguments: idnbr)
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  if (isAprov)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Icon(Icons.inventory_2_outlined, size: 13, color: theme.hintColor),
                                    ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          group['order_nbr'].toString(),
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if ((group['customer'] as String).isNotEmpty)
                                          Text(
                                            group['customer'] as String,
                                            style: TextStyle(fontSize: 11, color: theme.hintColor),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '$done/${tasks.length}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: done == tasks.length ? Colors.green : theme.hintColor,
                                    ),
                                  ),
                                  if (idnbr != null) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right_rounded, size: 18),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          // Progress bar
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: tasks.isEmpty ? 0 : done / tasks.length,
                                minHeight: 4,
                                backgroundColor: theme.dividerColor.withOpacity(0.2),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  done == tasks.length ? Colors.green : theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Task rows
                          ...tasks.map((t) {
                            final taskId = t['id'] as int? ?? 0;
                            final isDone = t['done'] as bool? ?? false;
                            final tType = t['type'] as String? ?? 'order';
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: isDone,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      onChanged: (_) async {
                                        if (_orderOpsService == null) return;
                                        final newDone = !isDone;
                                        setState(() => t['done'] = newDone);
                                        if (tType == 'order' && idnbr != null) {
                                          await _orderOpsService!.toggleOrderTask(idnbr, taskId, newDone);
                                        } else if (tType == 'aprovisionamiento' && aprovId != null) {
                                          await _orderOpsService!.toggleAprovisionamientoTask(aprovId, taskId, newDone);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      t['titulo']?.toString() ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        decoration: isDone ? TextDecoration.lineThrough : null,
                                        color: isDone ? theme.hintColor : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _loadTemplates() async {
    if (_orderOpsService == null) return;
    setState(() => _templatesLoading = true);
    try {
      final list = await _orderOpsService!.getChecklistTemplates();
      if (mounted) setState(() => _templates = list);
    } finally {
      if (mounted) setState(() => _templatesLoading = false);
    }
  }

  Widget _aprovStatChip(String label, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3)),
    );
  }

  Widget _tabToggleBtn(String label, bool active, VoidCallback onTap, ThemeData theme) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? theme.colorScheme.onPrimary : theme.hintColor,
          ),
        ),
      ),
    );
  }

  Widget _buildAprovCard(
      AprovisionamientoRecord record, ThemeData theme, bool isDark) {
    final isExpanded = _expandedAprov.contains(record.id);
    final isLinked = record.isLinked;
    final statusColor = isLinked ? Colors.green : Colors.orange;
    final svcProgress = record.servicios.isEmpty
        ? 0.0
        : record.doneCount / record.servicios.length;
    final taskProgress = record.tasks.isEmpty
        ? 0.0
        : record.taskDoneCount / record.tasks.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: isLinked
                ? Colors.green.withOpacity(0.35)
                : theme.dividerColor.withOpacity(0.18)),
      ),
      color: isDark
          ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.6)
          : theme.colorScheme.surface,
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () => setState(() {
              isExpanded
                  ? _expandedAprov.remove(record.id)
                  : _expandedAprov.add(record.id);
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status dot
                  Padding(
                    padding: const EdgeInsets.only(top: 3, right: 10),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: statusColor),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Customer + status badge
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                record.customer,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isLinked ? 'ENLAZADO' : 'PENDIENTE',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: statusColor,
                                    letterSpacing: 0.6),
                              ),
                            ),
                          ],
                        ),
                        // Order number
                        if (record.orderNbr?.isNotEmpty == true) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(Icons.receipt_long_outlined,
                                  size: 12,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.45)),
                              const SizedBox(width: 4),
                              Text(
                                record.orderNbr!,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.65),
                                    letterSpacing: 0.5),
                              ),
                            ],
                          ),
                        ],
                        // Linked idnbr
                        if (isLinked && record.linkedIdnbr != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.link,
                                  size: 12, color: Colors.green),
                              const SizedBox(width: 4),
                              Text(
                                'Orden #${record.linkedIdnbr}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                        // Chips row: family, prioridad, assignee
                        if (record.family != null ||
                            record.prioridad != null ||
                            record.assignedToName != null) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (record.family != null)
                                _aprvInfoChip(record.family!,
                                    Icons.category_outlined, theme),
                              if (record.prioridad != null)
                                _aprvInfoChip(
                                    _prioLabel(record.prioridad!),
                                    Icons.flag_outlined,
                                    theme,
                                    color: _prioColor(record.prioridad!)),
                              if (record.assignedToName != null)
                                _aprvInfoChip(record.assignedToName!,
                                    Icons.person_outline, theme),
                            ],
                          ),
                        ],
                        // Progress bars
                        if (record.tasks.isNotEmpty ||
                            record.servicios.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          if (record.tasks.isNotEmpty)
                            _aprovProgressRow('Tareas',
                                record.taskDoneCount, record.tasks.length,
                                taskProgress, theme),
                          if (record.servicios.isNotEmpty) ...[
                            if (record.tasks.isNotEmpty)
                              const SizedBox(height: 4),
                            _aprovProgressRow('Servicios',
                                record.doneCount, record.servicios.length,
                                svcProgress, theme),
                          ],
                        ],
                      ],
                    ),
                  ),
                  // Edit + expand
                  Column(
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit_outlined,
                            size: 16,
                            color: theme.colorScheme.onSurface.withOpacity(0.4)),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: 'Editar',
                        onPressed: () =>
                            _showAprovSheet(context, theme, existing: record),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurface.withOpacity(0.35),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded body ───────────────────────────────────────────────
          if (isExpanded) ...[
            Divider(
                height: 1, color: theme.dividerColor.withOpacity(0.12)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Notes
                  if (record.notas?.isNotEmpty == true) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        record.notas!,
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.65)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Tasks section
                  Row(
                    children: [
                      Expanded(
                        child: _aprovSectionHeader(
                            'Tareas', Icons.check_circle_outline, theme),
                      ),
                      GestureDetector(
                        onTap: () => _applyTemplateToAprov(record, theme),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.playlist_add_check_rounded,
                                size: 14,
                                color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Plantilla',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (record.tasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6),
                      child: Text('Sin tareas',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.35))),
                    )
                  else
                    ...record.tasks.map((t) =>
                        _buildTaskRow(record, t, theme)),
                  const SizedBox(height: 6),
                  _buildAddItemRow(
                    hint: 'Añadir tarea...',
                    onAdd: (v) => _addTask(record, v),
                    theme: theme,
                  ),
                  const SizedBox(height: 12),

                  // Action bar
                  Row(
                    children: [
                      if (!isLinked)
                        FilledButton.icon(
                          onPressed: () => _showLinkDialog(record),
                          icon: const Icon(Icons.link, size: 14),
                          label: const Text('Enlazar orden'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.teal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        )
                      else
                        Row(
                          children: [
                            const Icon(Icons.check_circle,
                                size: 14, color: Colors.green),
                            const SizedBox(width: 4),
                            Text('Enlazado a #${record.linkedIdnbr}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.green)),
                          ],
                        ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _deleteAprovRecord(record),
                        icon: Icon(Icons.delete_outline,
                            size: 15,
                            color: Colors.red.withOpacity(0.7)),
                        label: Text('Eliminar',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.red.withOpacity(0.7))),
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _aprovSectionHeader(
      String title, IconData icon, ThemeData theme) {
    return Row(
      children: [
        Icon(icon,
            size: 13, color: theme.colorScheme.onSurface.withOpacity(0.45)),
        const SizedBox(width: 5),
        Text(
          title.toUpperCase(),
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: theme.colorScheme.onSurface.withOpacity(0.45)),
        ),
      ],
    );
  }

  Widget _aprovProgressRow(String label, int done, int total,
      double progress, ThemeData theme) {
    final isComplete = progress >= 1.0;
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withOpacity(0.4))),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: theme.dividerColor.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(
                  isComplete ? Colors.green : theme.colorScheme.primary),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('$done/$total',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isComplete
                    ? Colors.green
                    : theme.colorScheme.onSurface.withOpacity(0.45))),
      ],
    );
  }

  Widget _aprvInfoChip(String label, IconData icon, ThemeData theme,
      {Color? color}) {
    final c = color ?? theme.colorScheme.onSurface.withOpacity(0.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: c),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: c)),
        ],
      ),
    );
  }

  String _prioLabel(String p) {
    if (p == '1') return 'Alta';
    if (p == '2') return 'Media';
    if (p == '3') return 'Baja';
    return p;
  }

  Color _prioColor(String p) {
    if (p == '1') return Colors.red;
    if (p == '2') return Colors.orange;
    return Colors.grey;
  }

  Widget _buildTaskRow(AprovisionamientoRecord record,
      AprovisionamientoTask t, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: t.done,
              onChanged: (_) => _toggleTask(record, t),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.titulo,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                decoration: t.done ? TextDecoration.lineThrough : null,
                color: t.done
                    ? theme.colorScheme.onSurface.withOpacity(0.35)
                    : null,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close,
                size: 13,
                color: theme.colorScheme.onSurface.withOpacity(0.3)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _deleteTask(record, t),
          ),
        ],
      ),
    );
  }

  Widget _buildAddItemRow({
    required String hint,
    required void Function(String) onAdd,
    required ThemeData theme,
  }) {
    final ctrl = TextEditingController();
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withOpacity(0.3)),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: theme.dividerColor.withOpacity(0.2)),
              ),
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) onAdd(v.trim());
            },
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, size: 20),
          color: theme.colorScheme.primary,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () {
            if (ctrl.text.trim().isNotEmpty) onAdd(ctrl.text.trim());
          },
        ),
      ],
    );
  }

  bool _isValidOrderNbr(String val) {
    if (val.isEmpty) return true;
    return RegExp(r'^[A-Z0-9]{2}-[A-Z0-9]{5}-[A-Z0-9]{2}$').hasMatch(val);
  }

  // ── Create / Edit sheet ───────────────────────────────────────────────────

  Future<void> _showAprovSheet(BuildContext context, ThemeData theme,
      {AprovisionamientoRecord? existing}) async {
    List<String> families = [];
    try {
      families = await _orderOpsService!.getCatalogFamilies();
      families = {...families}.toList()..sort();
    } catch (_) {}

    if (!mounted) return;

    final customerCtrl =
        TextEditingController(text: existing?.customer ?? '');
    final orderNbrCtrl =
        TextEditingController(text: existing?.orderNbr ?? '');
    final notasCtrl = TextEditingController(text: existing?.notas ?? '');
    // Assignee is selected from the employee list — not free-text
    Map<String, dynamic>? selectedEmployee = existing?.assignedTo != null
        ? {'id': existing!.assignedTo, 'display_name': existing.assignedToName ?? existing.assignedTo}
        : null;
    String? selectedFamily = existing?.family;
    String? selectedPrio = existing?.prioridad;
    bool autoApply = existing?.autoApply ?? true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return DraggableScrollableSheet(
            initialChildSize: 0.88,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollCtrl) => Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.dividerColor.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Title
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Row(
                      children: [
                        Text(
                          existing == null
                              ? 'Nuevo aprovisionamiento'
                              : 'Editar aprovisionamiento',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                      height: 1,
                      color: theme.dividerColor.withOpacity(0.15)),
                  Expanded(
                    child: ListView(
                      controller: scrollCtrl,
                      padding: EdgeInsets.fromLTRB(
                          20,
                          16,
                          20,
                          MediaQuery.of(ctx).viewInsets.bottom + 24),
                      children: [
                        // Customer
                        TextField(
                          controller: customerCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Cliente *',
                            prefixIcon: Icon(Icons.business_outlined,
                                size: 18),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Order number
                        TextField(
                          controller: orderNbrCtrl,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [OrderInputFormatter()],
                          onChanged: (val) {
                            setLocal(() {});
                          },
                          decoration: InputDecoration(
                            labelText: 'Nº Orden esperado',
                            hintText: 'SE-12345-01',
                            prefixIcon:
                                const Icon(Icons.receipt_long_outlined, size: 18),
                            helperText:
                                'Formato: XX-XXXXX-XX  (p.ej. SE-12345-01)',
                            errorText: _isValidOrderNbr(orderNbrCtrl.text)
                                ? null
                                : 'Formato incorrecto. Debe ser XX-XXXXX-XX',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Family chips
                        Text('Familia',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.6))),
                        const SizedBox(height: 8),
                        families.isEmpty
                            ? Text('Cargando familias...',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.35)))
                            : Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: families.map((f) {
                                  final sel = selectedFamily == f;
                                  return FilterChip(
                                    label: Text(f,
                                        style:
                                            const TextStyle(fontSize: 12)),
                                    selected: sel,
                                    onSelected: (v) => setLocal(
                                        () => selectedFamily =
                                            v ? f : null),
                                    selectedColor: theme
                                        .colorScheme.primary
                                        .withOpacity(0.2),
                                    checkmarkColor:
                                        theme.colorScheme.primary,
                                  );
                                }).toList(),
                              ),
                        const SizedBox(height: 14),

                        // Priority
                        DropdownButtonFormField<String>(
                          value: selectedPrio,
                          decoration: const InputDecoration(
                            labelText: 'Prioridad',
                            prefixIcon:
                                Icon(Icons.flag_outlined, size: 18),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: '1', child: Text('Alta')),
                            DropdownMenuItem(
                                value: '2', child: Text('Media')),
                            DropdownMenuItem(
                                value: '3', child: Text('Baja')),
                          ],
                          onChanged: (v) =>
                              setLocal(() => selectedPrio = v),
                        ),
                        const SizedBox(height: 14),

                        // Assignee autocomplete
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Autocomplete<Map<String, dynamic>>(
                              initialValue: selectedEmployee != null
                                  ? TextEditingValue(
                                      text: selectedEmployee!['display_name']
                                              ?.toString() ??
                                          '')
                                  : TextEditingValue.empty,
                              displayStringForOption: (e) =>
                                  e['display_name']?.toString() ?? '',
                              optionsBuilder:
                                  (TextEditingValue v) async {
                                if (v.text.isEmpty) return [];
                                try {
                                  return await _orderOpsService!
                                      .getEmployees(q: v.text, limit: 20);
                                } catch (_) {
                                  return [];
                                }
                              },
                              onSelected: (emp) =>
                                  setLocal(() => selectedEmployee = emp),
                              fieldViewBuilder: (ctx2, fCtrl, fNode, onSub) =>
                                  TextField(
                                controller: fCtrl,
                                focusNode: fNode,
                                onEditingComplete: onSub,
                                decoration: InputDecoration(
                                  labelText: 'Asignar a',
                                  hintText: 'Buscar técnico...',
                                  prefixIcon: const Icon(
                                      Icons.person_outline,
                                      size: 18),
                                  suffixIcon: selectedEmployee != null
                                      ? const Icon(Icons.check_circle,
                                          size: 16, color: Colors.green)
                                      : null,
                                  border: const OutlineInputBorder(),
                                  helperText: selectedEmployee != null
                                      ? 'Seleccionado: ${selectedEmployee!['display_name']}'
                                      : null,
                                  helperStyle: const TextStyle(
                                      fontSize: 11, color: Colors.green),
                                ),
                              ),
                              optionsViewBuilder: (ctx2, onSel, options) =>
                                  Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 4,
                                  borderRadius: BorderRadius.circular(8),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                        maxHeight: 220, maxWidth: 380),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (_, i) {
                                        final emp =
                                            options.elementAt(i);
                                        final name = emp['display_name']
                                                ?.toString() ??
                                            '';
                                        final company =
                                            emp['empresa_nombre']
                                                    ?.toString() ??
                                                '';
                                        return ListTile(
                                          dense: true,
                                          leading: const Icon(
                                              Icons.person_outline,
                                              size: 18),
                                          title: Text(name,
                                              style: const TextStyle(
                                                  fontSize: 13)),
                                          subtitle: company.isNotEmpty
                                              ? Text(company,
                                                  style: const TextStyle(
                                                      fontSize: 11))
                                              : null,
                                          onTap: () => onSel(emp),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Notes
                        TextField(
                          controller: notasCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Notas',
                            prefixIcon:
                                Icon(Icons.notes_outlined, size: 18),
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Auto-apply toggle
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withOpacity(0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: theme.colorScheme.primary
                                    .withOpacity(0.15)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.auto_awesome_outlined,
                                  size: 18,
                                  color: theme.colorScheme.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('Aplicar al enlazar',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: theme
                                                .colorScheme.onSurface)),
                                    Text(
                                      'Al enlazar con una orden real, aplicar familia, prioridad y asignación automáticamente.',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: theme
                                              .colorScheme.onSurface
                                              .withOpacity(0.5)),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: autoApply,
                                onChanged: (v) =>
                                    setLocal(() => autoApply = v),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Save button
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700),
                            ),
                            onPressed: () async {
                              final customer =
                                  customerCtrl.text.trim();
                              if (customer.isEmpty) return;
                              final orderNbr =
                                  orderNbrCtrl.text.trim().isEmpty
                                      ? null
                                      : orderNbrCtrl.text.trim();
                              if (orderNbr != null && !_isValidOrderNbr(orderNbr)) {
                                return;
                              }
                              final notas = notasCtrl.text.trim().isEmpty
                                  ? null
                                  : notasCtrl.text.trim();
                              final assignedTo = selectedEmployee?['id']?.toString();
                              final assignedToName = selectedEmployee?['display_name']?.toString();
                              Navigator.of(ctx).pop();
                              if (existing == null) {
                                await _createAprov(
                                  customer: customer,
                                  orderNbr: orderNbr,
                                  notas: notas,
                                  family: selectedFamily,
                                  prioridad: selectedPrio,
                                  assignedTo: assignedTo,
                                  assignedToName: assignedToName,
                                  autoApply: autoApply,
                                );
                              } else {
                                await _updateAprov(
                                  existing,
                                  customer: customer,
                                  orderNbr: orderNbr,
                                  notas: notas,
                                  family: selectedFamily ?? '',
                                  prioridad: selectedPrio ?? '',
                                  assignedTo: assignedTo ?? '',
                                  assignedToName: assignedToName ?? '',
                                  autoApply: autoApply,
                                );
                              }
                            },
                            child: Text(existing == null ? 'Crear' : 'Guardar'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showLinkDialog(AprovisionamientoRecord record) async {
    // Pre-fill with the stripped order number so the user can confirm/correct it
    final ctrl = TextEditingController(
        text: record.orderNbr?.replaceAll('-', '') ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enlazar a orden'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (record.autoApply)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.auto_awesome_outlined,
                        size: 14, color: Colors.teal),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Se aplicará automáticamente la familia, prioridad y asignación configuradas.',
                        style: TextStyle(fontSize: 12, color: Colors.teal),
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: 'Nº de orden',
                hintText: record.orderNbr?.replaceAll('-', '') ?? '291453111',
                helperText: 'Sin guiones — igual que aparece en la cola de órdenes',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.text,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.link, size: 16),
            label: const Text('Enlazar'),
            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () async {
              final raw = ctrl.text.trim();
              if (raw.isEmpty) return;
              Navigator.of(ctx).pop();
              try {
                // Pass as order_nbr — server normalizes (strips dashes) before matching
                final result = await _orderOpsService!
                    .linkAprovisionamiento(record.id, orderNbr: raw);
                await _loadAprovisionamiento();
                if (mounted && result != null) {
                  final applied = (result['applied_fields'] as List? ?? []);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(applied.isNotEmpty
                        ? 'Enlazado. Aplicado: ${applied.join(', ')}'
                        : 'Orden enlazada correctamente'),
                    backgroundColor: Colors.teal,
                  ));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _createAprov({
    required String customer,
    String? orderNbr,
    String? notas,
    String? family,
    String? prioridad,
    String? assignedTo,
    String? assignedToName,
    bool autoApply = true,
  }) async {
    if (_orderOpsService == null) return;
    try {
      await _orderOpsService!.createAprovisionamiento(
        customer: customer,
        orderNbr: orderNbr,
        notas: notas,
        family: family,
        prioridad: prioridad,
        assignedTo: assignedTo,
        assignedToName: assignedToName,
        autoApply: autoApply,
      );
      await _loadAprovisionamiento();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _updateAprov(
    AprovisionamientoRecord record, {
    required String customer,
    String? orderNbr,
    String? notas,
    String? family,
    String? prioridad,
    String? assignedTo,
    String? assignedToName,
    bool autoApply = true,
  }) async {
    if (_orderOpsService == null) return;
    try {
      await _orderOpsService!.updateAprovisionamiento(
        record.id,
        customer: customer,
        orderNbr: orderNbr,
        notas: notas,
        family: family,
        prioridad: prioridad,
        assignedTo: assignedTo,
        assignedToName: assignedToName,
        autoApply: autoApply,
      );
      await _loadAprovisionamiento();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addTask(AprovisionamientoRecord record, String titulo) async {
    if (_orderOpsService == null) return;
    try {
      await _orderOpsService!.addAprovisionamientoTask(record.id, titulo);
      await _loadAprovisionamiento();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _applyTemplateToAprov(
      AprovisionamientoRecord record, ThemeData theme) async {
    if (_orderOpsService == null) return;
    final templates = await _orderOpsService!.getChecklistTemplates();
    if (!mounted) return;
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay plantillas disponibles')),
      );
      return;
    }
    final template = await showDialog<ChecklistTemplate>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aplicar plantilla'),
        content: SizedBox(
          width: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: templates.length,
            itemBuilder: (_, i) {
              final t = templates[i];
              return ListTile(
                title: Text(t.name),
                subtitle: t.description != null ? Text(t.description!) : null,
                trailing: t.family != null
                    ? Chip(
                        label: Text(t.family!,
                            style: const TextStyle(fontSize: 11)))
                    : null,
                onTap: () => Navigator.of(ctx).pop(t),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar')),
        ],
      ),
    );
    if (template == null || !mounted) return;

    // Add each template item as an aprovisionamiento task (skip duplicates)
    final existingTitles = record.tasks.map((t) => t.titulo).toSet();
    final toAdd = template.items
        .where((item) => !existingTitles.contains(item.titulo))
        .toList();

    for (final item in toAdd) {
      await _orderOpsService!
          .addAprovisionamientoTask(record.id, item.titulo);
    }
    if (toAdd.isNotEmpty) await _loadAprovisionamiento();
  }

  Future<void> _toggleTask(
      AprovisionamientoRecord record, AprovisionamientoTask t) async {
    if (_orderOpsService == null) return;
    final idx = _aprovisionamiento.indexWhere((r) => r.id == record.id);
    if (idx == -1) return;
    setState(() {
      final updated = _aprovisionamiento[idx];
      final tIdx = updated.tasks.indexWhere((x) => x.id == t.id);
      if (tIdx == -1) return;
      final newList = List.of(updated.tasks);
      newList[tIdx] = t.copyWith(done: !t.done);
      _aprovisionamiento[idx] = updated.copyWith(tasks: newList);
    });
    try {
      await _orderOpsService!
          .toggleAprovisionamientoTask(record.id, t.id, !t.done);
    } catch (_) {
      await _loadAprovisionamiento();
    }
  }

  Future<void> _deleteTask(
      AprovisionamientoRecord record, AprovisionamientoTask t) async {
    if (_orderOpsService == null) return;
    try {
      await _orderOpsService!.deleteAprovisionamientoTask(record.id, t.id);
      await _loadAprovisionamiento();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteAprovRecord(AprovisionamientoRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar registro'),
        content: Text(
            '¿Eliminar el registro de "${record.customer}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || _orderOpsService == null) return;
    try {
      await _orderOpsService!.deleteAprovisionamiento(record.id);
      setState(() {
        _aprovisionamiento.removeWhere((r) => r.id == record.id);
        _expandedAprov.remove(record.id);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Widget _buildHeader(ThemeData theme) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final apiService = Provider.of<ApiService>(context, listen: false);
    final user = apiService.currentUser;
    final role = user?.role.toLowerCase() ?? '';
    final canSync = role == 'admin' || role == 'chief';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            'Cola de Ordenes',
            overflow: TextOverflow.ellipsis,
            style: isMobile
                ? theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  )
                : theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
          ),
        ),
        if (canSync)
          if (_syncingOrders)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(
                Icons.sync_alt_rounded,
                color: Colors.tealAccent,
              ),
              onPressed: _handleSyncOrders,
              tooltip: 'Sincronizar Ordenes (SFTP)',
            ),
        if (canSync)
          _importingCsv
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(
                    Icons.cloud_upload_rounded,
                    color: Colors.orangeAccent,
                  ),
                  onPressed: _handleImportCsv,
                  tooltip: 'Importar Ordenes (CSV)',
                ),
        _exportingOrders
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.download_rounded, color: Colors.greenAccent),
                onPressed: _handleExportOrders,
                tooltip: 'Exportar Órdenes (Excel)',
              ),
        IconButton(
          icon: Icon(
            _selectionMode ? Icons.close : Icons.checklist_rounded,
            color: _selectionMode ? Colors.orange : null,
          ),
          onPressed: _toggleSelectionMode,
          tooltip: _selectionMode
              ? 'Cancelar selección (${_selectedOrderIds.length})'
              : 'Selección múltiple',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _loadOrders(),
          tooltip: 'Actualizar',
        ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final presentStatuses = _orders
        .map((e) => e.estado.trim())
        .where((String s) => s.isNotEmpty)
        .toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Buscar por orden, cliente o descripción...',
            prefixIcon: Icon(
              Icons.search,
              size: 20,
              color: theme.colorScheme.onSurface.withOpacity(0.45),
            ),
            hintStyle: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(isDark ? 0.4 : 0.45),
            ),
            filled: true,
            fillColor: isDark
                ? theme.colorScheme.surface.withOpacity(0.5)
                : theme.colorScheme.surface.withOpacity(0.95),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.12)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.12)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _searchController.clear();
                      _applyFilters();
                    },
                  )
                : null,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip(
                label: 'Todas',
                selected: _selectedEstado == null && !_filterByMe,
                color: theme.colorScheme.primary,
                isDark: isDark,
                onTap: () {
                  setState(() {
                    _selectedEstado = null;
                    _filterByMe = false;
                  });
                  _applyFilters();
                },
              ),
              const SizedBox(width: 6),
              ...['1', '2', '3', '4', '5', '6']
                  .where((code) => presentStatuses.any((s) => s.contains(code)))
                  .map((code) {
                    final color = _statusColor(code);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _filterChip(
                        label: _statusLabel(code),
                        dotColor: color,
                        selected: _selectedEstado != null &&
                            _selectedEstado!.contains(code),
                        color: color,
                        isDark: isDark,
                        onTap: () {
                          _selectedEstado =
                              (_selectedEstado != null &&
                                      _selectedEstado!.contains(code))
                                  ? null
                                  : code;
                          _applyFilters();
                        },
                      ),
                    );
                  }),
              Container(
                width: 1,
                height: 22,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: theme.dividerColor.withOpacity(0.35),
              ),
              _filterChip(
                label: 'Mis órdenes',
                selected: _filterByMe,
                color: theme.colorScheme.secondary,
                isDark: isDark,
                onTap: () {
                  _filterByMe = !_filterByMe;
                  _applyFilters();
                },
              ),
              const SizedBox(width: 6),
              _filterChip(
                label: 'Sin calidad',
                selected: _filterNoQuality,
                color: Colors.orange,
                isDark: isDark,
                onTap: () {
                  setState(() => _filterNoQuality = !_filterNoQuality);
                  _applyFilters();
                },
              ),
            ],
          ),
        ),
        if (_filteredOrdersList.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${_filteredOrdersList.length} orden${_filteredOrdersList.length == 1 ? '' : 'es'}',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withOpacity(0.45),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
    Color? dotColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(isDark ? 0.18 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? color.withOpacity(0.55)
                : Colors.grey.withOpacity(0.28),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? dotColor : dotColor.withOpacity(0.45),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? color : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(String code) {
    if (code.contains('1')) return 'Validada';
    if (code.contains('2')) return 'Pendiente';
    if (code.contains('3')) return 'En Ejecución';
    if (code.contains('4')) return 'Parada';
    if (code.contains('5')) return 'Finalizada';
    if (code.contains('6')) return 'Facturada';
    return code.isEmpty ? '' : code;
  }

  static Color _statusColor(String code) {
    if (code.contains('1')) return Colors.blue;
    if (code.contains('2')) return Colors.orange;
    if (code.contains('3')) return Colors.cyan;
    if (code.contains('4')) return Colors.red;
    if (code.contains('5')) return Colors.green;
    if (code.contains('6')) return Colors.purple;
    return Colors.blueGrey;
  }

  String _formatOrderNbr(String nbr) {
    final clean = nbr.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length == 9) {
      return '${clean.substring(0, 2)}-${clean.substring(2, 7)}-${clean.substring(7, 9)}';
    }
    return nbr;
  }

  Widget _buildTable(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          'Error: $_error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    final filtered = _filteredOrdersList;

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'No se encontraron pedidos.',
          style: theme.textTheme.titleMedium,
        ),
      );
    }

    final grouped = _groupedOrders;

    // Build flattened list of items: String (Month name) or AgentOrder
    final List<dynamic> tableItems = [];
    grouped.forEach((month, orders) {
      tableItems.add(month); // Header
      tableItems.addAll(orders); // Rows
    });

    final isMobile = MediaQuery.of(context).size.width < 800;

    if (isMobile) {
      return ListView.builder(
        itemCount: tableItems.length,
        padding: const EdgeInsets.only(bottom: 24),
        itemBuilder: (ctx, idx) {
          final item = tableItems[idx];
          if (item is String) {
            return _buildMonthRow(item, theme);
          } else {
            return _buildOrderCard(item as AgentOrder, theme);
          }
        },
      );
    }

    const double minWidth = 1330;

    return Card(
      elevation: 8,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      color: theme.brightness == Brightness.dark
          ? theme.cardColor.withOpacity(0.9)
          : theme.colorScheme.surface.withOpacity(0.98),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth < minWidth
              ? minWidth
              : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // STICKY HEADER ROW
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withOpacity(
                        theme.brightness == Brightness.dark ? 0.3 : 0.65,
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: theme.dividerColor.withOpacity(
                            theme.brightness == Brightness.dark ? 0.1 : 0.28,
                          ),
                        ),
                      ),
                    ),
                    height: 56,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_selectionMode)
                          SizedBox(
                            width: 44,
                            child: Checkbox(
                              value: _selectedOrderIds.length == _filteredOrdersList.length &&
                                  _filteredOrdersList.isNotEmpty,
                              tristate: true,
                              onChanged: (_) {
                                if (_selectedOrderIds.length == _filteredOrdersList.length) {
                                  setState(() => _selectedOrderIds.clear());
                                } else {
                                  _selectAll();
                                }
                              },
                            ),
                          ),
                        _headerCell('Nº Pedido', 150),
                        _headerCell('Fecha', 110),
                        _headerCell('Cliente', 200),
                        _headerCell('Descripción', 300),
                        _headerCell('Familia', 150),
                        _headerCell('Prioridad', 110),
                        _headerCell('Asignado', 150),
                        _headerCell('Estado', 160),
                      ],
                    ),
                  ),
                  // SCROLLABLE BODY
                  Expanded(
                    child: ListView.separated(
                      itemCount: tableItems.length,
                      padding: EdgeInsets.zero,
                      separatorBuilder: (context, index) {
                        if (tableItems[index] is String ||
                            (index + 1 < tableItems.length &&
                                tableItems[index + 1] is String)) {
                          return const SizedBox.shrink();
                        }
                        return Divider(
                          height: 1,
                          color: theme.dividerColor.withOpacity(0.05),
                          indent: 16,
                          endIndent: 16,
                        );
                      },
                      itemBuilder: (ctx, idx) {
                        final item = tableItems[idx];
                        if (item is String) {
                          return _buildMonthRow(item, theme);
                        } else {
                          return _buildOrderRow(
                            item as AgentOrder,
                            theme,
                            idx % 2 == 0,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(AgentOrder order, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = _selectedOrderIds.contains(order.idnbr);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: isSelected ? 6 : 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      color: isSelected
          ? theme.colorScheme.primary.withOpacity(0.07)
          : isDark
              ? theme.cardColor.withOpacity(0.9)
              : theme.colorScheme.surface.withOpacity(0.98),
      child: InkWell(
        onTap: () => _onOrderTap(order),
        onLongPress: () {
          if (!_selectionMode) {
            setState(() {
              _selectionMode = true;
              _selectedOrderIds.add(order.idnbr);
            });
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_selectionMode)
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => _onOrderTap(order),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      _formatOrderNbr(order.orderNbr),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  _StatusBadge(status: order.estado, isNative: true),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                order.customer,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                order.orderDate != null
                    ? DateFormat('dd/MM/yyyy').format(order.orderDate!)
                    : '-',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(
                    isDark ? 0.6 : 0.68,
                  ),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              if (order.sourcePrimaryDesc?.isNotEmpty == true) ...[
                Text(
                  order.sourcePrimaryDesc!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(
                      isDark ? 0.7 : 0.78,
                    ),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Familia (Mobile)
              Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 14,
                    color: theme.colorScheme.primary.withOpacity(0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.subfamiliesDisplay.isNotEmpty
                          ? order.subfamiliesDisplay
                          : (order.family ?? 'Sin servicio'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Builder(
                    builder: (context) {
                      String prioText = order.prioridad;
                      Color prioColor = Colors.grey;
                      if (prioText.contains('1')) {
                        prioText = 'Alta';
                        prioColor = Colors.red;
                      } else if (prioText.contains('2')) {
                        prioText = 'Media';
                        prioColor = Colors.orange;
                      } else if (prioText.contains('3')) {
                        prioText = 'Baja';
                        prioColor = Colors.green;
                      } else if (prioText.toLowerCase().contains('alta')) {
                        prioColor = Colors.red;
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: prioColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: prioColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          prioText.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            color: prioColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.grey,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

    Widget _headerCell(String title, double width) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.1,
              color: theme.colorScheme.onSurface.withOpacity(0.55),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthRow(String groupTitle, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  theme.colorScheme.primaryContainer.withOpacity(0.18),
                  theme.colorScheme.primaryContainer.withOpacity(0.04),
                ]
              : [
                  theme.colorScheme.primaryContainer.withOpacity(0.35),
                  theme.colorScheme.primaryContainer.withOpacity(0.1),
                ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 6),
          bottom: BorderSide(color: theme.dividerColor.withOpacity(isDark ? 0.05 : 0.15)),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text(
            groupTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              letterSpacing: 0.5,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderRow(AgentOrder order, ThemeData theme, bool isEven) {
    final isDark = theme.brightness == Brightness.dark;
    final statusAccent = _statusColor(order.estado);
    final isSelected = _selectedOrderIds.contains(order.idnbr);
    return Material(
      color: isSelected
          ? theme.colorScheme.primary.withOpacity(0.08)
          : isEven
              ? Colors.transparent
              : theme.colorScheme.surface.withOpacity(isDark ? 0.02 : 0.05),
      child: InkWell(
        onTap: () => _onOrderTap(order),
        onLongPress: () {
          if (!_selectionMode) {
            setState(() {
              _selectionMode = true;
              _selectedOrderIds.add(order.idnbr);
            });
          }
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isSelected
                    ? theme.colorScheme.primary
                    : statusAccent.withOpacity(0.55),
                width: isSelected ? 4 : 3,
              ),
            ),
          ),
          child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (_selectionMode)
                SizedBox(
                  width: 44,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _onOrderTap(order),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              // Nº Orden
              SizedBox(
                width: 150,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.colorScheme.primary.withOpacity(0.15)),
                    ),
                    child: Text(
                      _formatOrderNbr(order.orderNbr),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: theme.colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              // Fecha
              SizedBox(
                width: 110,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    order.orderDate != null
                        ? DateFormat('dd/MM/yyyy').format(order.orderDate!)
                        : '-',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface.withOpacity(
                        isDark ? 0.7 : 0.72,
                      ),
                    ),
                  ),
                ),
              ),
              // Cliente
              SizedBox(
                width: 200,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    order.customer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // Descripción
              SizedBox(
                width: 300,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Tooltip(
                    message: order.sourceCommentsExcerpt ?? 'Sin comentarios',
                    child: Text(
                      order.sourcePrimaryDesc?.isNotEmpty == true
                          ? order.sourcePrimaryDesc!
                          : 'Sin descripción',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(
                          isDark ? 0.62 : 0.72,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Familia
              SizedBox(
                width: 150,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Tooltip(
                    message: order.subfamiliesDisplay,
                    child: Text(
                      order.subfamiliesDisplay.isNotEmpty
                          ? order.subfamiliesDisplay
                          : (order.family ?? '-'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.primary.withOpacity(0.8),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              // Prioridad
              SizedBox(
                width: 110,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: order.prioridad.isNotEmpty
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Builder(
                            builder: (context) {
                              String prioText = order.prioridad;
                              Color prioColor = Colors.grey;
                              if (prioText.contains('1')) {
                                prioText = 'Alta';
                                prioColor = const Color(0xFFEF5350);
                              } else if (prioText.contains('2')) {
                                prioText = 'Media';
                                prioColor = const Color(0xFFFFA726);
                              } else if (prioText.contains('3')) {
                                prioText = 'Baja';
                                prioColor = const Color(0xFF66BB6A);
                              } else if (prioText.toLowerCase().contains(
                                'alta',
                              )) {
                                prioColor = const Color(0xFFEF5350);
                              }

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: prioColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: prioColor.withOpacity(0.25),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: prioColor,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      prioText.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: prioColor,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              // Asignado
              SizedBox(
                width: 150,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    order.assignedToName ?? order.assignedTo ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface.withOpacity(
                        isDark ? 0.8 : 0.9,
                      ),
                    ),
                  ),
                ),
              ),
              // Estado/Manual
              SizedBox(
                width: 160,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _StatusBadge(
                            status: order.estado,
                            isNative: true,
                          ),
                        ),
                      ),
                      if (order.family == null || order.family!.isEmpty) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(
                            Icons.assignment_add,
                            size: 18,
                            color: Colors.amber,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          splashRadius: 20,
                          tooltip: 'Asignar Familia Manualmente',
                          onPressed: () => _showManualFamilyPicker(order),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool isNative;
  const _StatusBadge({required this.status, this.isNative = false});

  static String _label(String s, bool isNative) {
    if (isNative) {
      if (s.contains('1')) return 'Validada';
      if (s.contains('2')) return 'Pendiente';
      if (s.contains('3')) return 'En Ejecución';
      if (s.contains('4')) return 'Parada';
      if (s.contains('5')) return 'Finalizada';
      if (s.contains('6')) return 'Facturada';
    }
    return s.replaceAll('_', ' ');
  }

  static Color _color(String s, bool isNative) {
    if (isNative) {
      if (s.contains('1')) return Colors.blue;
      if (s.contains('2')) return Colors.orange;
      if (s.contains('3')) return Colors.cyan;
      if (s.contains('4')) return Colors.red;
      if (s.contains('5')) return Colors.green;
      if (s.contains('6')) return Colors.purple;
    }
    switch (s.toLowerCase()) {
      case 'new': return Colors.blue;
      case 'triaged': return Colors.green;
      case 'blocked': return Colors.red;
      case 'needs_manual_triage': return Colors.orange;
      case 'open': return Colors.blue;
      case 'done': case 'completado': case 'closed': return Colors.green;
      case 'cancelled': case 'cancelado': return Colors.red;
      case 'hold': case 'en pausa': return Colors.orange;
      default: return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (status.isEmpty) return const SizedBox.shrink();
    final color = _color(status, isNative);
    final label = _label(status, isNative).toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Template Manager Sheet
// ---------------------------------------------------------------------------

class _TemplateManagerSheet extends StatefulWidget {
  final OrderOpsService orderOpsService;
  final List<ChecklistTemplate> initialTemplates;
  final ThemeData theme;

  const _TemplateManagerSheet({
    required this.orderOpsService,
    required this.initialTemplates,
    required this.theme,
  });

  @override
  State<_TemplateManagerSheet> createState() => _TemplateManagerSheetState();
}

class _TemplateManagerSheetState extends State<_TemplateManagerSheet> {
  late List<ChecklistTemplate> _templates;
  int? _expandedId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _templates = List.from(widget.initialTemplates);
  }

  Future<void> _createTemplate() async {
    // Fetch families in parallel while the sheet opens
    final familiesFuture = widget.orderOpsService.getCatalogFamilies();

    final result = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NewTemplateSheet(familiesFuture: familiesFuture),
    );

    if (result == null || (result['name'] ?? '').isEmpty) return;
    setState(() => _saving = true);
    final t = await widget.orderOpsService.createChecklistTemplate(
      name: result['name']!,
      family: result['family'],
    );
    if (t != null && mounted) {
      setState(() {
        _templates = [..._templates, t];
        _expandedId = t.id;
      });
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _deleteTemplate(ChecklistTemplate t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar plantilla'),
        content: Text('¿Eliminar "${t.name}"? Se borrarán todos sus items.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await widget.orderOpsService.deleteChecklistTemplate(t.id);
    if (ok && mounted) {
      setState(() {
        _templates = _templates.where((x) => x.id != t.id).toList();
        if (_expandedId == t.id) _expandedId = null;
      });
    }
  }

  Future<void> _addItem(ChecklistTemplate t) async {
    final ctrl = TextEditingController();
    final titulo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Añadir item'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Descripción del item…',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    if (titulo == null || titulo.isEmpty) return;
    final item = await widget.orderOpsService.addTemplateItem(t.id, titulo);
    if (item != null && mounted) {
      setState(() {
        _templates = _templates.map((tmpl) {
          if (tmpl.id != t.id) return tmpl;
          return ChecklistTemplate(
            id: tmpl.id,
            name: tmpl.name,
            description: tmpl.description,
            family: tmpl.family,
            createdAt: tmpl.createdAt,
            items: [...tmpl.items, item],
          );
        }).toList();
      });
    }
  }

  Future<void> _deleteItem(ChecklistTemplate t, ChecklistTemplateItem item) async {
    final ok = await widget.orderOpsService.deleteTemplateItem(t.id, item.id);
    if (ok && mounted) {
      setState(() {
        _templates = _templates.map((tmpl) {
          if (tmpl.id != t.id) return tmpl;
          return ChecklistTemplate(
            id: tmpl.id,
            name: tmpl.name,
            description: tmpl.description,
            family: tmpl.family,
            createdAt: tmpl.createdAt,
            items: tmpl.items.where((i) => i.id != item.id).toList(),
          );
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Text(
              'Plantillas de Checklist',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (_saving)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              FilledButton.icon(
                onPressed: _createTemplate,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Nueva'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        // Template list
        Expanded(
          child: _templates.isEmpty
              ? Center(
                  child: Text(
                    'Sin plantillas. Crea una para empezar.',
                    style: TextStyle(color: theme.hintColor),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
                      itemCount: _templates.length,
                      itemBuilder: (_, i) {
                        final t = _templates[i];
                        final isExpanded = _expandedId == t.id;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.dividerColor.withOpacity(0.15),
                            ),
                          ),
                          child: Column(
                            children: [
                              // Template header row
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => setState(
                                  () => _expandedId = isExpanded ? null : t.id,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              t.name,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (t.family != null || t.items.isNotEmpty)
                                              const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                if (t.family != null)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 7, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: theme.colorScheme.primary
                                                          .withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      t.family!,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: theme.colorScheme.primary,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                if (t.family != null && t.items.isNotEmpty)
                                                  const SizedBox(width: 6),
                                                Text(
                                                  '${t.items.length} item${t.items.length == 1 ? '' : 's'}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: theme.hintColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        color: Colors.red.withOpacity(0.7),
                                        tooltip: 'Eliminar plantilla',
                                        onPressed: () => _deleteTemplate(t),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        isExpanded
                                            ? Icons.expand_less_rounded
                                            : Icons.expand_more_rounded,
                                        size: 20,
                                        color: theme.hintColor,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Expanded items
                              if (isExpanded) ...[
                                Divider(height: 1, color: theme.dividerColor.withOpacity(0.15)),
                                ...t.items.map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 6),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.drag_handle_rounded,
                                            size: 16, color: Colors.grey),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.check_box_outline_blank_rounded,
                                            size: 14, color: Colors.grey),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(item.titulo,
                                              style: const TextStyle(fontSize: 13)),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close_rounded, size: 14),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          tooltip: 'Eliminar item',
                                          onPressed: () => _deleteItem(t, item),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Add item row
                                InkWell(
                                  onTap: () => _addItem(t),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    child: Row(
                                      children: [
                                        Icon(Icons.add_rounded,
                                            size: 16,
                                            color: theme.colorScheme.primary),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Añadir item',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
  }
}

// ---------------------------------------------------------------------------
// New Template Sheet — name + family picker with chips
// ---------------------------------------------------------------------------

class _NewTemplateSheet extends StatefulWidget {
  final Future<List<String>> familiesFuture;
  const _NewTemplateSheet({required this.familiesFuture});

  @override
  State<_NewTemplateSheet> createState() => _NewTemplateSheetState();
}

class _NewTemplateSheetState extends State<_NewTemplateSheet> {
  final _nameCtrl = TextEditingController();
  String? _selectedFamily;
  List<String> _families = [];
  bool _loadingFamilies = true;

  @override
  void initState() {
    super.initState();
    widget.familiesFuture.then((list) {
      if (mounted) setState(() { _families = list; _loadingFamilies = false; });
    }).catchError((_) {
      if (mounted) setState(() => _loadingFamilies = false);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop({'name': name, 'family': _selectedFamily});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Nueva plantilla',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              labelText: 'Nombre *',
              hintText: 'Ej: Montaje estándar de servidores',
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Familia',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 10),
          if (_loadingFamilies)
            const SizedBox(
              height: 32,
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_families.isEmpty)
            Text('Sin familias disponibles', style: TextStyle(color: theme.hintColor, fontSize: 13))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FamilyChip(
                  label: 'Ninguna',
                  selected: _selectedFamily == null,
                  onTap: () => setState(() => _selectedFamily = null),
                  theme: theme,
                ),
                ..._families.map((f) => _FamilyChip(
                  label: f,
                  selected: _selectedFamily == f,
                  onTap: () => setState(() => _selectedFamily = _selectedFamily == f ? null : f),
                  theme: theme,
                )),
              ],
            ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Crear plantilla', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FamilyChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  const _FamilyChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.dividerColor.withOpacity(0.25),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

