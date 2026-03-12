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

      // Insert overlay for sidebar
      if (mounted) {
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
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
                  Expanded(child: _buildTable(theme)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Cola de Pedidos OrderOps',
          style:
              theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ) ??
              const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
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
    // Unique native estados to filter by
    final estados = _orders.map((e) => e.estado).toSet().toList()..sort();

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar por pedido, cliente o desc...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (val) => setState(() {}),
          ),
        ),
        const SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedEstado,
              hint: const Text('Estado (Todos)'),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Todos los estados'),
                ),
                ...estados.map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(e.isEmpty ? 'Sin Estado' : e),
                  ),
                ),
              ],
              onChanged: (val) => setState(() => _selectedEstado = val),
            ),
          ),
        ),
      ],
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

  List<AgentOrder> get _filteredOrders {
    var list = _orders;
    if (_selectedEstado != null) {
      list = list.where((o) => o.estado == _selectedEstado).toList();
    }
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((o) {
        return o.orderNbr.toLowerCase().contains(query) ||
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

    const double minWidth = 1100;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.cardColor.withOpacity(0.8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: minWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // STICKY HEADER ROW
                Container(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(
                    0.5,
                  ),
                  height: 48,
                  child: Row(
                    children: [
                      _headerCell('Nº Pedido', 100),
                      _headerCell('Fecha', 100),
                      _headerCell('Cliente', 180),
                      _headerCell('Descripción', 260),
                      _headerCell('Prioridad', 100),
                      _headerCell('Estado', 120),
                      _headerCell('Margen', 120),
                      _headerCell('Acciones', 100),
                    ],
                  ),
                ),
                // SCROLLABLE BODY
                Expanded(
                  child: ListView.builder(
                    itemCount: tableItems.length,
                    itemBuilder: (ctx, idx) {
                      final item = tableItems[idx];
                      if (item is String) {
                        return _buildMonthRow(item, theme);
                      } else {
                        return _buildOrderRow(item as AgentOrder, theme);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String title, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
      child: Text(
        groupTitle,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildOrderRow(AgentOrder order, ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onOrderTap(order),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Nº Pedido
              SizedBox(
                width: 100,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Text(
                    order.orderNbr,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              // Fecha
              SizedBox(
                width: 100,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Text(
                    order.orderDate != null
                        ? DateFormat('dd/MM/yyyy').format(order.orderDate!)
                        : '-',
                  ),
                ),
              ),
              // Cliente
              SizedBox(
                width: 180,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Text(
                    order.customer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Descripción
              SizedBox(
                width: 260,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Tooltip(
                    message: order.sourceCommentsExcerpt ?? 'Sin comentarios',
                    child: Text(
                      order.sourcePrimaryDesc?.isNotEmpty == true
                          ? order.sourcePrimaryDesc!
                          : 'Sin descripción',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              // Prioridad
              SizedBox(
                width: 100,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: order.prioridad.isNotEmpty
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  order.prioridad.toLowerCase().contains('alta')
                                  ? Colors.red.withOpacity(0.1)
                                  : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              order.prioridad,
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    order.prioridad.toLowerCase().contains(
                                      'alta',
                                    )
                                    ? Colors.red
                                    : theme.hintColor,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              // Estado
              SizedBox(
                width: 120,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _StatusBadge(status: order.estado, isNative: true),
                  ),
                ),
              ),
              // Margen
              SizedBox(
                width: 120,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '\$${(order.estimatedMargin ?? 0).toStringAsFixed(2)}',
                        style: TextStyle(
                          color: (order.estimatedMargin ?? 0) >= 0
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${(order.estimatedMarginPct ?? 0).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Acciones
              SizedBox(
                width: 100,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: theme.primaryColor,
                    ),
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

    Color color;
    if (isNative) {
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
