import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';

import '../../services/api_service.dart';
import '../../services/orderops_service.dart';
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

class _OrderQueueScreenState extends State<OrderQueueScreen> {
  OrderOpsService? _orderOpsService;
  List<AgentOrder> _orders = [];
  bool _loading = true;
  bool _syncingOrders = false;
  bool _importingCsv = false;
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

  // Performance Cache: Avoid redundant computations in build()
  List<AgentOrder> _filteredOrdersList = [];
  Map<String, List<AgentOrder>> _groupedOrders = {};
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
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
    _refreshTimer?.cancel();
    _searchDebounce?.cancel();
    _edgeOverlay?.remove();
    _edgeOverlay = null;
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
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

    // 3. Filter by Search Query (Using pre-calculated searchable fields)
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

  bool get _isPrivilegedRole {
    final role = _normalizedRole();
    return role == 'admin' || role == 'chief';
  }

  bool get _canEditProyectoOrFamily {
    final role = _normalizedRole();
    return role == 'admin' || role == 'chief' || role.contains('clerc');
  }

  Future<void> _loadOrders({bool silent = false}) async {
    if (_orderOpsService == null) return;
    if (!silent) setState(() => _loading = true);

    try {
      final allOrders = await _orderOpsService!.getAgentOrders(limit: 10000);
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

  void _onOrderTap(AgentOrder order) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(orderId: order.idnbr),
          ),
        )
        .then((_) => _loadOrders(silent: true)); // Refresh on return
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

    return Scaffold(
      body: Stack(
        children: [
          // PERFORMANCE: Reduced intensity to 0.4 to prevent GPU stuttering during scrolling.
          const AnimatedBackgroundWidget(intensity: 0.4),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme),
                  const SizedBox(height: 24),
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
                  Expanded(
                    child: _buildTable(theme),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark
          ? theme.cardColor.withOpacity(0.9)
          : theme.colorScheme.surface.withOpacity(0.98),
      child: InkWell(
        onTap: () => _onOrderTap(order),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatOrderNbr(order.orderNbr),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: theme.colorScheme.primary,
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
    return Material(
      color: isEven
          ? Colors.transparent
          : theme.colorScheme.surface.withOpacity(isDark ? 0.02 : 0.05),
      child: InkWell(
        onTap: () => _onOrderTap(order),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: statusAccent.withOpacity(0.55), width: 3),
            ),
          ),
          child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
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
