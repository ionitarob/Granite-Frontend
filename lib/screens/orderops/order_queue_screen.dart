import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/orderops_service.dart';
import '../../models/agent_models.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';

import 'order_detail_screen.dart';

class OrderQueueScreen extends StatefulWidget {
  const OrderQueueScreen({super.key});

  @override
  State<OrderQueueScreen> createState() => _OrderQueueScreenState();
}

class _OrderQueueScreenState extends State<OrderQueueScreen> {
  OrderOpsService? _orderOpsService;
  List<AgentOrder> _orders = [];
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;
  OverlayEntry? _edgeOverlay;
  bool _autoFamilyScanInProgress = false;
  final Set<int> _autoFamilyScannedOrderIds = <int>{};

  // Filters
  final TextEditingController _searchController = TextEditingController();
  String? _selectedEstado;

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

      // Insert overlay for sidebar only on desktop widths.
      final logicalWidth =
          MediaQuery.maybeOf(context)?.size.width ??
          (View.of(context).physicalSize.width / View.of(context).devicePixelRatio);
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
    _edgeOverlay?.remove();
    _edgeOverlay = null;
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders({bool silent = false}) async {
    if (_orderOpsService == null) return;
    if (!silent) setState(() => _loading = true);

    try {
      final orders = await _orderOpsService!.getAgentOrders(limit: 200);
      setState(() {
        _orders = orders;
        _error = null;
        _loading = false;
      });

      // Run family auto-assignment in background from queue context, so
      // users do not need to open detail screen to trigger it.
      unawaited(_autoAssignFamiliesFromQueue(orders));
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
      final description =
          (row['DESCRIP1'] ?? row['description'] ?? '').toString().toUpperCase();
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
          return family.isEmpty && !_autoFamilyScannedOrderIds.contains(o.idnbr);
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
                ? 'Familia autoasignada en 1 pedido'
                : 'Familia autoasignada en $assignedCount pedidos',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      await _loadOrders(silent: true);
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
    if (_orderOpsService == null) return;

    const extraFamilies = <String>[
      'SERIGRAFIADO',
      'MANIPULACIÓN Y ETIQUETADO',
    ];

    List<String> families = [];
    try {
      families = await _orderOpsService!.getCatalogFamilies();
    } catch (e) {
      debugPrint('Error fetching families: $e');
    }

    if (families.isEmpty) {
      families = [
        'ORDENADORES SERVIDOR',
        'CAMBIO DE SERIAL',
        'XIAOMI ETIQUETADO',
      ];
    }

    families = {...families, ...extraFamilies}.toList();
    families.sort();

    if (!mounted) return;

    final currentFamily = (order.family ?? '').trim();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (ctx, scrollController) => Material(
            color: const Color(0xFF1A1A2E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'Seleccionar Familia de Pedido',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: families.length,
                      itemBuilder: (ctx, index) {
                        final f = families[index];
                        final selected =
                            f.toLowerCase() == currentFamily.toLowerCase();
                        return ListTile(
                          leading: Icon(
                            Icons.category_outlined,
                            color: selected ? Colors.tealAccent : Colors.white70,
                          ),
                          title: Text(
                            f,
                            style: TextStyle(
                              color: selected ? Colors.tealAccent : Colors.white,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: selected
                              ? const Icon(Icons.check, color: Colors.tealAccent)
                              : null,
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            if (selected) return;

                            final ok = await _orderOpsService!.updateAgentOrder(
                              order.idnbr,
                              family: f,
                              reason: 'Cambio manual de familia a: $f',
                            );
                            if (!mounted) return;

                            if (ok) {
                              _loadOrders(silent: true);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Familia actualizada correctamente'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('No se pudo actualizar la familia'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Removed _runAgent as AI triage is deprecated.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 0.8),
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
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: _buildTable(theme),
                      ),
                    ),
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
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            'Cola de Pedidos',
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
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _loadOrders(),
          tooltip: 'Actualizar',
        ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    // Unique native estados to filter by (normalized to avoid duplicates/stale values)
    final estados = _orders
        .map((e) => e.estado.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final selectedEstadoValue =
        (_selectedEstado != null && estados.contains(_selectedEstado))
        ? _selectedEstado
        : null;
    final isMobile = MediaQuery.of(context).size.width < 800;
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Flex(
          direction: isMobile ? Axis.vertical : Axis.horizontal,
          children: [
            Expanded(
              flex: isMobile ? 0 : 2,
              child: TextField(
                controller: _searchController,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar por pedido, cliente...',
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(isDark ? 0.65 : 0.55),
                  ),
                  filled: true,
                  fillColor: isDark
                      ? theme.colorScheme.surface.withOpacity(0.5)
                      : theme.colorScheme.surface.withOpacity(0.95),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: theme.dividerColor.withOpacity(isDark ? 0.1 : 0.35),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: theme.dividerColor.withOpacity(isDark ? 0.1 : 0.35),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: (val) => setState(() {}),
              ),
            ),
            if (isMobile) const SizedBox(height: 12) else const SizedBox(width: 16),
            Container(
              width: isMobile ? double.infinity : null,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.surface.withOpacity(0.5)
                    : theme.colorScheme.surface.withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.dividerColor.withOpacity(isDark ? 0.1 : 0.35),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedEstadoValue,
                  isExpanded: isMobile,
                  hint: const Text('Estado (Todos)'),
                  icon: const Icon(Icons.filter_list, size: 20),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Todos los estados'),
                    ),
                    ...estados.map((e) {
                      String label = e;
                      if (e.contains('1')) label = 'Validada';
                      else if (e.contains('2')) label = 'Pendiente';
                      else if (e.contains('3')) label = 'En Ejecución';
                      else if (e.contains('4')) label = 'Parada';
                      else if (e.contains('5')) label = 'Finalizada';
                      else if (e.contains('6')) label = 'Facturada';
                      return DropdownMenuItem(
                        value: e,
                        child: Text(label.isEmpty ? 'Sin Estado' : label),
                      );
                    }),
                  ],
                  onChanged: (val) => setState(() => _selectedEstado = val),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to group orders by Month/Year
  Map<String, List<AgentOrder>> _groupOrdersByMonth(List<AgentOrder> orders) {
    final Map<String, List<AgentOrder>> groups = {};
    for (var order in orders) {
      final date = order.orderDate;
      String key = 'Sin Fecha';
      if (date != null) {
        // "Enero 2026", "Febrero 2026", etc.
        // Expecting intl is imported and initialized with 'es'
        // But to be safe, we can default to English if checks fail,
        // strictly speaking main.dart initializes 'es'.
        // We'll use a direct formatting approach with First letter caps.
        final month = DateFormat('MMMM', 'es').format(date);
        final year = DateFormat('yyyy').format(date);
        key = '${month[0].toUpperCase()}${month.substring(1)} $year';
      }
      if (!groups.containsKey(key)) {
        groups[key] = [];
      }
      groups[key]!.add(order);
    }
    // Sort keys? Ideally we want newest months first.
    // Since keys are strings, sorting is tricky.
    // Better to use a sorted list of keys derived from dates if needed,
    // but typically regular iteration might suffice if source list is sorted.
    // If we assume source `orders` list is sorted by date descending (from API),
    // then the insertion order into map is preserved in Dart.
    return groups;
  }

  String _formatOrderNbr(String nbr) {
    // Standardize to xx-xxxxx-xx
    // Remove any non-numeric characters for processing if we assume it's just numbers
    // But since it might already have parts, let's keep it simple.
    // If it's a 9-digit string like 101234567, map to 10-12345-67
    final clean = nbr.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length == 9) {
      return '${clean.substring(0, 2)}-${clean.substring(2, 7)}-${clean.substring(7, 9)}';
    }
    return nbr;
  }

  List<AgentOrder> get _filteredOrders {
    var list = _orders;
    if (_selectedEstado != null) {
      list = list.where((o) => o.estado == _selectedEstado).toList();
    }
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      final cleanQuery = query.replaceAll('-', '');
      list = list.where((o) {
        final cleanOrderNbr = o.orderNbr.toLowerCase().replaceAll('-', '');
        
        // Match exact clean nbr, or if query is 5 digits, check if it's contained in the middle
        bool nbrMatch = cleanOrderNbr.contains(cleanQuery);
        if (cleanQuery.length == 5 && cleanOrderNbr.length >= 7) {
            // Specifically check the middle 5 digits if it's a standard format
            // but .contains(cleanQuery) already covers this and more.
        }

        return nbrMatch ||
            o.customer.toLowerCase().contains(query) ||
            (o.sourcePrimaryDesc ?? '').toLowerCase().contains(query);
      }).toList();
    }
    return list;
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

    final filtered = _filteredOrders;

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'No se encontraron pedidos.',
          style: theme.textTheme.titleMedium,
        ),
      );
    }

    final grouped = _groupOrdersByMonth(filtered);

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

    const double minWidth = 1150;

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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: minWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // STICKY HEADER ROW
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(
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
                    _headerCell('Prioridad', 110),
                    _headerCell('Estado/Manual', 130),
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
                        (index + 1 < tableItems.length && tableItems[index+1] is String)) {
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
                      return _buildOrderRow(item as AgentOrder, theme, idx % 2 == 0);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
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
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                order.orderDate != null
                    ? DateFormat('dd/MM/yyyy').format(order.orderDate!)
                    : '-',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(isDark ? 0.6 : 0.68),
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
                    color: theme.colorScheme.onSurface.withOpacity(isDark ? 0.7 : 0.78),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Builder(builder: (context) {
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  }),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
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
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthRow(String groupTitle, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.4),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 4),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        groupTitle,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildOrderRow(AgentOrder order, ThemeData theme, bool isEven) {
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: isEven
          ? Colors.transparent
          : theme.colorScheme.surface.withOpacity(isDark ? 0.02 : 0.05),
      child: InkWell(
        onTap: () => _onOrderTap(order),
        child: Container(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Nº Pedido
              SizedBox(
                width: 150,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    _formatOrderNbr(order.orderNbr),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary.withOpacity(0.9),
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
                      color: theme.colorScheme.onSurface.withOpacity(isDark ? 0.7 : 0.72),
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
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
                        color: theme.colorScheme.onSurface.withOpacity(isDark ? 0.62 : 0.72),
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
                          child: Builder(builder: (context) {
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
                                horizontal: 6,
                                vertical: 2,
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
                                  letterSpacing: 0.5,
                                ),
                              ),
                            );
                          }),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              // Estado
              SizedBox(
                width: 130,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _StatusBadge(status: order.estado, isNative: true),
                        ),
                      ),
                      if (order.family == null || order.family!.isEmpty)
                        IconButton(
                          icon: const Icon(Icons.assignment_add, size: 18, color: Colors.amber),
                          tooltip: 'Asignar Familia Manualmente',
                          onPressed: () => _showManualFamilyPicker(order),
                        ),
                    ],
                  ),
                ),
              ),
            ],
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

  @override
  Widget build(BuildContext context) {
    if (status.isEmpty) return const SizedBox.shrink();

    String statusLabel = status;
    Color color;

    if (isNative) {
      // Map numeric status to labels if applicable
      if (status.contains('1')) {
        statusLabel = 'Validada';
        color = Colors.blue;
      } else if (status.contains('2')) {
        statusLabel = 'Pendiente';
        color = Colors.orange;
      } else if (status.contains('3')) {
        statusLabel = 'En Ejecución';
        color = Colors.cyan;
      } else if (status.contains('4')) {
        statusLabel = 'Parada';
        color = Colors.red;
      } else if (status.contains('5')) {
        statusLabel = 'Finalizada';
        color = Colors.green;
      } else if (status.contains('6')) {
        statusLabel = 'Facturada';
        color = Colors.purple;
      } else {
        switch (status.toLowerCase()) {
          case 'abierto':
          case 'open':
            color = Colors.blue;
            break;
          case 'completado':
          case 'closed':
          case 'done':
            color = Colors.green;
            break;
          case 'cancelado':
          case 'cancelled':
            color = Colors.red;
            break;
          case 'en pausa':
          case 'hold':
            color = Colors.orange;
            break;
          default:
            color = Colors.blueGrey;
        }
      }
    } else {
      switch (status.toLowerCase()) {
        case 'new':
          color = Colors.blue;
          break;
        case 'triaged':
          color = Colors.green;
          break;
        case 'blocked':
          color = Colors.red;
          break;
        case 'needs_manual_triage':
          color = Colors.orange;
          break;
        default:
          color = Colors.blueGrey;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        statusLabel.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
