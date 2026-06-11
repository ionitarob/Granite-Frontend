import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/orderops_service.dart';
import '../../models/agent_models.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';
import 'order_detail_screen.dart';

class OrderAlertsScreen extends StatefulWidget {
  const OrderAlertsScreen({super.key});

  @override
  State<OrderAlertsScreen> createState() => _OrderAlertsScreenState();
}

class _OrderAlertsScreenState extends State<OrderAlertsScreen> {
  OrderOpsService? _orderOpsService;
  List<AgentServiceAlert> _alerts = [];
  bool _loading = true;
  String? _error;
  OverlayEntry? _edgeOverlay;

  // Filters & Search
  String _statusFilter = 'pending'; // Default to pending alerts
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  int _currentPage = 0;
  final int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      _orderOpsService = OrderOpsService(apiService.client);
      _loadAlerts();

      // Sidebar Overlay
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
    _edgeOverlay?.remove();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_orderOpsService == null) return;
      final items = await _orderOpsService!.getServiceAlerts();
      if (mounted) {
        setState(() {
          _alerts = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _updateAlertStatus(AgentServiceAlert alert, String newStatus, String notes) async {
    setState(() => _loading = true);
    try {
      final ok = await _orderOpsService!.updateServiceAlert(alert.idnbr, alert.sku, newStatus, notes);
      if (ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Alerta de servicio actualizada a: $newStatus')),
          );
        }
        await _loadAlerts();
      } else {
        throw Exception('No se pudo actualizar la alerta');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showValidationDialog(AgentServiceAlert alert) {
    String currentStatus = alert.status;
    final notesCtrl = TextEditingController(text: alert.notes);

    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Validar / Reportar Alerta',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Artículo: ${alert.sku}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      alert.description,
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Precio venta: ${alert.orderUnitPrice.toStringAsFixed(2)} €'),
                        Text('Precio teórico: ${alert.theoreticalPvd.toStringAsFixed(2)} €'),
                      ],
                    ),
                    Text(
                      'Coste: ${alert.coste.toStringAsFixed(2)} €',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Divider(height: 24),
                    const Text(
                      'Estado de Validación:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: currentStatus,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? Colors.black26 : Colors.grey.withOpacity(0.1),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'pending', child: Text('Pendiente (Alerta Activa)')),
                        DropdownMenuItem(value: 'validated', child: Text('Validado (Forzar a Verde)')),
                        DropdownMenuItem(value: 'reported', child: Text('Reportado (Seguimiento)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => currentStatus = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Notas / Justificación:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Añade notas sobre la discrepancia o justificación...',
                        filled: true,
                        fillColor: isDark ? Colors.black26 : Colors.grey.withOpacity(0.1),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _updateAlertStatus(alert, currentStatus, notesCtrl.text);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<AgentServiceAlert> _getFilteredAlerts() {
    return _alerts.where((item) {
      // 1. Status Filter
      if (_statusFilter != 'all') {
        if (item.status != _statusFilter) {
          return false;
        }
      }

      // 2. Search Query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchSku = item.sku.toLowerCase().contains(query);
        final matchDesc = item.description.toLowerCase().contains(query);
        final matchCustomer = item.customer.toLowerCase().contains(query);
        final matchOrder = item.orderNbr.toLowerCase().contains(query);
        return matchSku || matchDesc || matchCustomer || matchOrder;
      }

      return true;
    }).toList();
  }

  Widget _buildFilterChip(String label, String value, Color color) {
    final isSelected = _statusFilter == value;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        selected: isSelected,
        label: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? Colors.white70 : Colors.black54),
          ),
        ),
        backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        selectedColor: color.withOpacity(isDark ? 0.35 : 0.25),
        checkmarkColor: isDark ? Colors.white : Colors.black87,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        onSelected: (selected) {
          if (selected) {
            setState(() {
              _statusFilter = value;
              _currentPage = 0;
            });
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final filtered = _getFilteredAlerts();
    final totalFiltered = filtered.length;
    final totalPages = (totalFiltered / _pageSize).ceil();
    
    // Safety check for page range
    if (_currentPage >= totalPages && totalPages > 0) {
      _currentPage = totalPages - 1;
    }
    
    final startIndex = _currentPage * _pageSize;
    final endIndex = (startIndex + _pageSize) < totalFiltered ? (startIndex + _pageSize) : totalFiltered;
    final pageItems = totalFiltered > 0 ? filtered.sublist(startIndex, endIndex) : <AgentServiceAlert>[];

    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 0.6),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alertas de Servicios',
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Control y validación de precios desviados en ordenes de servicio',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: _loadAlerts,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Recargar Alertas',
                        style: IconButton.styleFrom(
                          backgroundColor: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Search and Filters Bar
                  Row(
                    children: [
                      // Filters
                      Expanded(
                        child: Wrap(
                          children: [
                            _buildFilterChip('Pendientes', 'pending', Colors.orange),
                            _buildFilterChip('Validadas', 'validated', Colors.green),
                            _buildFilterChip('Reportadas', 'reported', Colors.blue),
                            _buildFilterChip('Todas', 'all', Colors.purple),
                          ],
                        ),
                      ),
                      // Search box
                      SizedBox(
                        width: 300,
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Buscar SKU, cliente, orden...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() {
                                        _searchQuery = '';
                                        _currentPage = 0;
                                      });
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                              _currentPage = 0;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Main Content
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('Error al cargar alertas: $_error', style: const TextStyle(color: Colors.red)),
                                    const SizedBox(height: 12),
                                    ElevatedButton(
                                      onPressed: _loadAlerts,
                                      child: const Text('Reintentar'),
                                    ),
                                  ],
                                ),
                              )
                            : pageItems.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No hay alertas de servicios que coincidan con los filtros.',
                                      style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                                    ),
                                  )
                                : Container(
                                    decoration: BoxDecoration(
                                      color: isDark 
                                          ? const Color(0xFF0F172A).withOpacity(0.90)
                                          : Colors.white.withOpacity(0.96),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.10),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.15),
                                          blurRadius: 16,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.vertical,
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Left scrollable columns
                                            Expanded(
                                              child: LayoutBuilder(
                                                builder: (context, constraints) {
                                                  final double otherColumnsWidth = 720;
                                                  final double descWidth = (constraints.maxWidth - otherColumnsWidth).clamp(250.0, double.infinity);
                                                  return SingleChildScrollView(
                                                    scrollDirection: Axis.horizontal,
                                                    child: ConstrainedBox(
                                                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                                      child: DataTable(
                                                        dataRowMinHeight: 56,
                                                        dataRowMaxHeight: 56,
                                                        headingRowHeight: 56,
                                                        horizontalMargin: 12,
                                                        columnSpacing: 16,
                                                        headingRowColor: WidgetStateProperty.all(
                                                          isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.02),
                                                        ),
                                                        columns: [
                                                          const DataColumn(label: Text('Alerta')),
                                                          const DataColumn(label: Text('Orden')),
                                                          const DataColumn(label: Text('Fecha Orden')),
                                                          const DataColumn(label: Text('Cliente')),
                                                          DataColumn(
                                                            label: SizedBox(
                                                              width: descWidth,
                                                              child: const Text('SKU / Descripción'),
                                                            ),
                                                          ),
                                                          const DataColumn(label: Text('Coste')),
                                                          const DataColumn(label: Text('P. Teórico')),
                                                          const DataColumn(label: Text('P. Venta')),
                                                        ],
                                                        rows: pageItems.map((item) {
                                                          Color indicatorColor;
                                                          String indicatorLabel;

                                                          if (item.status == 'validated') {
                                                            indicatorColor = Colors.green;
                                                            indicatorLabel = 'Validado (Verde)';
                                                          } else if (item.status == 'reported') {
                                                            indicatorColor = Colors.blue;
                                                            indicatorLabel = 'Reportado';
                                                          } else {
                                                            if (item.colorState == 'red') {
                                                              indicatorColor = Colors.red;
                                                              indicatorLabel = 'Bajo Coste';
                                                            } else {
                                                              indicatorColor = Colors.orange;
                                                              indicatorLabel = 'Desv. Margen';
                                                            }
                                                          }

                                                          return DataRow(
                                                            cells: [
                                                              DataCell(
                                                                Row(
                                                                  children: [
                                                                    Container(
                                                                      width: 12,
                                                                      height: 12,
                                                                      decoration: BoxDecoration(
                                                                        color: indicatorColor,
                                                                        shape: BoxShape.circle,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(width: 8),
                                                                    Text(
                                                                      indicatorLabel,
                                                                      style: TextStyle(
                                                                        color: indicatorColor,
                                                                        fontWeight: FontWeight.bold,
                                                                        fontSize: 12,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                              DataCell(
                                                                InkWell(
                                                                  onTap: () {
                                                                    Navigator.of(context).push(
                                                                      MaterialPageRoute(
                                                                        builder: (_) => OrderDetailScreen(orderId: item.idnbr),
                                                                      ),
                                                                    );
                                                                  },
                                                                  child: Text(
                                                                    item.orderNbr,
                                                                    style: TextStyle(
                                                                      color: theme.colorScheme.primary,
                                                                      fontWeight: FontWeight.bold,
                                                                      decoration: TextDecoration.underline,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              DataCell(
                                                                Text(
                                                                  item.orderDate != null
                                                                      ? item.orderDate!.toLocal().toString().substring(0, 10)
                                                                      : '-',
                                                                ),
                                                              ),
                                                              DataCell(
                                                                SizedBox(
                                                                  width: 150,
                                                                  child: Text(
                                                                    item.customer,
                                                                    overflow: TextOverflow.ellipsis,
                                                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                                                  ),
                                                                ),
                                                              ),
                                                              DataCell(
                                                                SizedBox(
                                                                  width: descWidth,
                                                                  child: Column(
                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                                    children: [
                                                                      Text(
                                                                        item.sku,
                                                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                                                      ),
                                                                      Text(
                                                                        item.description,
                                                                        style: theme.textTheme.bodySmall?.copyWith(
                                                                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                                                                        ),
                                                                        overflow: TextOverflow.ellipsis,
                                                                        maxLines: 1,
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ),
                                                              DataCell(Text('${item.coste.toStringAsFixed(2)} €')),
                                                              DataCell(Text('${item.theoreticalPvd.toStringAsFixed(2)} €')),
                                                              DataCell(
                                                                Text(
                                                                  '${item.orderUnitPrice.toStringAsFixed(2)} €',
                                                                  style: TextStyle(
                                                                    fontWeight: FontWeight.bold,
                                                                    color: indicatorColor == Colors.red ? Colors.red : null,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          );
                                                        }).toList(),
                                                      ),
                                                    ),
                                                  );
                                                }
                                              ),
                                            ),
                                            // Fixed right columns
                                            Container(
                                              decoration: BoxDecoration(
                                                border: Border(
                                                  left: BorderSide(
                                                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                                                    width: 1,
                                                  ),
                                                ),
                                                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                              ),
                                              child: DataTable(
                                                dataRowMinHeight: 56,
                                                dataRowMaxHeight: 56,
                                                headingRowHeight: 56,
                                                horizontalMargin: 12,
                                                columnSpacing: 16,
                                                headingRowColor: WidgetStateProperty.all(
                                                  isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                                                ),
                                                columns: const [
                                                  DataColumn(label: Text('Estado Valid.')),
                                                  DataColumn(label: Text('Notas')),
                                                  DataColumn(label: Text('Acción')),
                                                ],
                                                rows: pageItems.map((item) {
                                                  return DataRow(
                                                    cells: [
                                                      DataCell(
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: item.status == 'validated'
                                                                ? Colors.green.withOpacity(0.2)
                                                                : item.status == 'reported'
                                                                    ? Colors.blue.withOpacity(0.2)
                                                                    : Colors.orange.withOpacity(0.2),
                                                            borderRadius: BorderRadius.circular(12),
                                                          ),
                                                          child: Text(
                                                            item.status.toUpperCase(),
                                                            style: TextStyle(
                                                              color: item.status == 'validated'
                                                                  ? Colors.green
                                                                  : item.status == 'reported'
                                                                      ? Colors.blue
                                                                      : Colors.orange,
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      DataCell(
                                                        SizedBox(
                                                          width: 150,
                                                          child: Text(
                                                            item.notes.isEmpty ? '-' : item.notes,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: const TextStyle(fontStyle: FontStyle.italic),
                                                          ),
                                                        ),
                                                      ),
                                                      DataCell(
                                                        IconButton(
                                                          icon: const Icon(Icons.edit_outlined),
                                                          tooltip: 'Validar o Reportar',
                                                          onPressed: () => _showValidationDialog(item),
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                  ),

                  // Bottom Pagination ControlsBar
                  if (totalPages > 1) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Mostrando ${startIndex + 1} - $endIndex de $totalFiltered alertas',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left),
                              onPressed: _currentPage > 0
                                  ? () => setState(() => _currentPage--)
                                  : null,
                              tooltip: 'Página Anterior',
                            ),
                            Text(
                              'Página ${_currentPage + 1} de $totalPages',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right),
                              onPressed: _currentPage < totalPages - 1
                                  ? () => setState(() => _currentPage++)
                                  : null,
                              tooltip: 'Siguiente Página',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
