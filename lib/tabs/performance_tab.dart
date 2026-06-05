import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../models/agent_models.dart';
import '../services/api_service.dart';
import '../screens/orderops/order_detail_screen.dart';
import '../dashboard_screen.dart'; // For DashboardSurface

class PerformanceTab extends StatelessWidget {
  final List<AgentOrder> orders;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final Function(DateTime start, DateTime end) onExport;
  final User currentUser;

  const PerformanceTab({
    super.key,
    required this.orders,
    required this.isLoading,
    this.error,
    required this.onRefresh,
    required this.onExport,
    required this.currentUser,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DashboardSurface(
      title: 'Performance',
      subtitle: 'Métricas operativas y tiempos de ejecución',
      headerRight: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => _showExportDialog(context, theme),
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text(
              'Exportar Ordenes',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      child: _buildBody(theme, context),
    );
  }

  Widget _buildBody(ThemeData theme, BuildContext context) {
    if (isLoading && orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null && orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 34),
            const SizedBox(height: 10),
            Text(
              'No se pudieron cargar las órdenes',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              error!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (orders.isEmpty) {
      return const Center(
        child: Text('No hay órdenes en estados 1, 2, 3 o 4'),
      );
    }

    // Role check (admin/chief)
    final role = _normalizedRole(currentUser);
    if (role != 'admin' && role != 'chief') {
      return const Center(child: Text('Sin permisos para Performance'));
    }

    return SingleChildScrollView(
      child: _buildPerformanceSection(context, theme),
    );
  }

  String _normalizedRole(User u) {
    final raw = u.role.trim().toLowerCase();
    if (raw.startsWith('role_')) return raw.substring(5);
    return raw;
  }

  Widget _buildPerformanceSection(BuildContext context, ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDark = theme.brightness == Brightness.dark;
        final spacing = width < 1200 ? 12.0 : 20.0;
        
        // Accurate width detection
        final tileWidth = (width - (spacing * 3)) / 4;
        final doubleWidth = (tileWidth * 2) + spacing;

        final e1 = orders.where((o) => o.estado.trim() == '1').toList();
        final e2 = orders.where((o) => o.estado.trim() == '2').toList();
        final e3 = orders.where((o) => o.estado.trim() == '3').toList();
        final e4 = orders.where((o) => o.estado.trim() == '4').toList();

        final agingLists = _agingBucketsLists(orders);
        final activeOrders = orders.where((o) => ['1', '2', '3', '4'].contains(o.estado.trim())).toList();
        final slaRate = _slaBreachRateLabel(activeOrders);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_rounded, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Métricas de Ejecución',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Grid Row 1: Statuses
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                _buildPerformanceTile(
                  theme: theme,
                  title: 'Pendientes Recibir',
                  value: '${e1.length}',
                  subtitle: 'Estado 1 · Validada',
                  accent: const Color(0xFF4F7BFF),
                  icon: Icons.inbox_rounded,
                  width: tileWidth,
                  onTap: () => _showOrdersPopup(context, 'Órdenes pendientes de recibir', e1),
                ),
                _buildPerformanceTile(
                  theme: theme,
                  title: 'Pendientes Ejecutar',
                  value: '${e2.length}',
                  subtitle: 'Estado 2 · Pendiente',
                  accent: const Color(0xFFFFB74D),
                  icon: Icons.pending_actions_rounded,
                  width: tileWidth,
                  onTap: () => _showOrdersPopup(context, 'Órdenes recibidas pendientes de ejecutar', e2),
                ),
                _buildPerformanceTile(
                  theme: theme,
                  title: 'En Ejecución',
                  value: '${e3.length}',
                  subtitle: 'Estado 3 · En proceso',
                  accent: const Color(0xFF26C6DA),
                  icon: Icons.play_circle_rounded,
                  width: tileWidth,
                  onTap: () => _showOrdersPopup(context, 'Órdenes en ejecución', e3),
                ),
                _buildPerformanceTile(
                  theme: theme,
                  title: 'Órdenes Paradas',
                  value: '${e4.length}',
                  subtitle: 'Estado 4 · Parada',
                  accent: const Color(0xFFE57373),
                  icon: Icons.pause_circle_filled_rounded,
                  width: tileWidth,
                  onTap: () => _showOrdersPopup(context, 'Órdenes paradas', e4),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Grid Row 2: Metrics sandwich! 
            // Purple (1/4) | Big Green (2/4) | Pink (1/4)
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                _buildPerformanceTile(
                  theme: theme,
                  title: 'T. Promedio',
                  value: _avgTimeToEstado4Label(),
                  subtitle: 'Últimas 20',
                  accent: const Color(0xFF7E57C2),
                  icon: Icons.timer_rounded,
                  width: tileWidth,
                  onTap: () {
                    final recent = _getRecentCompletedOrders();
                    _showOrdersPopup(context, 'Últimas 20 órdenes finalizadas', recent);
                  },
                ),
                _buildPerformanceTile(
                  theme: theme,
                  title: 'Antigüedad de Órdenes Pendientes',
                  accent: const Color(0xFF26A69A),
                  icon: Icons.stacked_bar_chart_rounded,
                  width: doubleWidth,
                  body: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: [
                        Expanded(child: _buildAgingColumn(context, theme, '0-24h', agingLists['0-24h']!, const Color(0xFF4CAF50))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildAgingColumn(context, theme, '1-3d', agingLists['1-3d']!, const Color(0xFFFFD54F))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildAgingColumn(context, theme, '4-7d', agingLists['4-7d']!, const Color(0xFFFFA726))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildAgingColumn(context, theme, '>7d', agingLists['>7d']!, const Color(0xFFEF5350))),
                      ],
                    ),
                  ),
                ),
                _buildPerformanceTile(
                  theme: theme,
                  title: 'SLA Breach',
                  value: slaRate,
                  subtitle: '>48h',
                  accent: const Color(0xFFF06292),
                  icon: Icons.warning_amber_rounded,
                  width: tileWidth,
                  onTap: () {
                    final breached = _getSlaBreachOrders(activeOrders, hours: 48);
                    _showOrdersPopup(context, 'Órdenes con antigüedad >48h', breached);
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildPerformanceTile({
    required ThemeData theme,
    required String title,
    String? value,
    String? subtitle,
    required Color accent,
    IconData? icon,
    Widget? body,
    required double width,
    VoidCallback? onTap,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final tile = Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: accent.withOpacity(isDark ? 0.35 : 0.25),
        border: Border.all(color: accent.withOpacity(isDark ? 0.5 : 0.4)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 22, color: accent),
            const SizedBox(height: 8),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          if (value != null) ...[
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
          ],
          if (body != null) ...[
            const SizedBox(height: 12),
            body,
          ],
        ],
      ),
    );

    if (onTap == null) return tile;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: tile,
    );
  }

  Widget _buildAgingColumn(BuildContext context, ThemeData theme, String label, List<AgentOrder> orders, Color accentColor) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: accentColor.withOpacity(isDark ? 0.18 : 0.14),
        border: Border.all(color: accentColor.withOpacity(0.55)),
      ),
      padding: const EdgeInsets.all(4), // Tighter padding for sandwich layout
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: accentColor.withOpacity(0.25),
            ),
            child: Text(
              '$label (${orders.length})',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            height: 120, // Shorter height to fit sandwich better
            child: orders.isEmpty
                ? Center(child: Text('—', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.4))))
                : ListView.builder(
                    itemCount: orders.length,
                    padding: EdgeInsets.zero,
                    itemBuilder: (ctx, index) => _buildOrderChip(context, orders[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderChip(BuildContext context, AgentOrder order, {bool compact = true}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = _estadoColor(order.estado);

    Widget content;
    if (compact) {
      content = Text(
        order.orderNbr,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (order.isBlocked)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.red.withOpacity(0.5)),
                  ),
                  child: const Text(
                    'BLOQUEADA',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: Colors.red,
                    ),
                  ),
                ),
              Text(
                order.orderNbr,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black87,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (order.proyecto != null && order.proyecto!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Text(
                    order.proyecto!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: color.withOpacity(0.9),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _estadoLabel(order.estado).toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : color.withOpacity(1.0),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 14, color: theme.colorScheme.onSurface.withOpacity(0.6)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  order.customer,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withOpacity(0.9),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (order.sourcePrimaryDesc != null && order.sourcePrimaryDesc!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.description_outlined, size: 12, color: theme.colorScheme.onSurface.withOpacity(0.4)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.sourcePrimaryDesc!,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    return InkWell(
      onTap: () {
        Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute(builder: (ctx) => OrderDetailScreen(orderId: order.idnbr)))
            .then((_) => onRefresh());
      },
      borderRadius: BorderRadius.circular(compact ? 6 : 12),
      child: Container(
        margin: EdgeInsets.only(bottom: compact ? 3 : 0),
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 14, vertical: compact ? 4 : 12),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(compact ? 6 : 12),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: compact ? null : [
            BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: content,
      ),
    );
  }

  Color _estadoColor(String estado) {
    switch (estado.trim()) {
      case '3': return const Color(0xFF00B8D9);
      case '2': return const Color(0xFFFFB300);
      case '4': return const Color(0xFF8E24AA);
      case '1': return const Color(0xFF43A047);
      case '5': return const Color(0xFF00897B);
      default: return Colors.blueGrey;
    }
  }

  String _estadoLabel(String estado) {
    switch (estado.trim()) {
      case '1': return 'Validada';
      case '2': return 'Pendiente';
      case '3': return 'En proceso';
      case '4': return 'Parada';
      case '5': return 'Finalizada';
      default: return 'Estado $estado';
    }
  }

  String _avgTimeToEstado4Label() {
    final completed = orders.where((o) => o.estado.trim() == '4' || o.estado.trim() == '5').toList()
      ..sort((a, b) => (b.completedAt ?? DateTime(1900)).compareTo(a.completedAt ?? DateTime(1900)));
    final last20 = completed.take(20).toList();
    if (last20.isEmpty) return '--';
    var totalMins = 0;
    var count = 0;
    for (final o in last20) {
      final start = o.createdAt ?? o.orderDate;
      final end = o.completedAt ?? o.lastTriagedAt;
      if (start != null && end != null) {
        totalMins += end.difference(start).inMinutes;
        count++;
      }
    }
    if (count == 0) return '--';
    final avgMins = totalMins / count;
    if (avgMins < 60) return '${avgMins.toStringAsFixed(0)}m';
    if (avgMins < 1440) return '${(avgMins / 60).toStringAsFixed(1)}h';
    return '${(avgMins / 1440).toStringAsFixed(1)}d';
  }

  List<AgentOrder> _getRecentCompletedOrders() {
    return orders.where((o) => o.estado.trim() == '4' || o.estado.trim() == '5').toList()
      ..sort((a, b) => (b.completedAt ?? DateTime(1900)).compareTo(a.completedAt ?? DateTime(1900)));
  }

  List<AgentOrder> _getSlaBreachOrders(List<AgentOrder> list, {int hours = 48}) {
    return list.where((o) {
      final start = o.createdAt ?? o.orderDate;
      if (start == null) return false;
      return DateTime.now().difference(start).inHours > hours;
    }).toList();
  }

  String _slaBreachRateLabel(List<AgentOrder> list, {int hours = 48}) {
    if (list.isEmpty) return '0%';
    final breached = _getSlaBreachOrders(list, hours: hours).length;
    return '${((breached / list.length) * 100).toStringAsFixed(1)}%';
  }

  Map<String, List<AgentOrder>> _agingBucketsLists(List<AgentOrder> list) {
    final buckets = {'0-24h': <AgentOrder>[], '1-3d': <AgentOrder>[], '4-7d': <AgentOrder>[], '>7d': <AgentOrder>[]};
    for (final o in list) {
      final start = o.createdAt ?? o.orderDate;
      if (start == null) continue;
      final hours = DateTime.now().difference(start).inHours;
      if (hours < 24) buckets['0-24h']!.add(o);
      else if (hours < 72) buckets['1-3d']!.add(o);
      else if (hours < 168) buckets['4-7d']!.add(o);
      else buckets['>7d']!.add(o);
    }
    return buckets;
  }

  Future<void> _showOrdersPopup(BuildContext context, String title, List<AgentOrder> orders) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.85) : Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) => _buildOrderChip(context, orders[i], compact: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showExportDialog(BuildContext context, ThemeData theme) async {
    DateTime selectedDate = DateTime.now();
    final List<String> months = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Exportar Datos'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Seleccione el mes para exportar:'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        selectedDate = DateTime(selectedDate.year - 1, selectedDate.month);
                      });
                    },
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text(
                    '${selectedDate.year}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        selectedDate = DateTime(selectedDate.year + 1, selectedDate.month);
                      });
                    },
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (rowIndex) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: List.generate(4, (colIndex) {
                          final index = rowIndex * 4 + colIndex;
                          final isSelected = selectedDate.month == (index + 1);
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    selectedDate = DateTime(selectedDate.year, index + 1);
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.primaryContainer.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.outline.withOpacity(0.2),
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    months[index],
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected
                                          ? theme.colorScheme.onPrimary
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                final start = DateTime(selectedDate.year, selectedDate.month, 1);
                final end = DateTime(selectedDate.year, selectedDate.month + 1, 0, 23, 59, 59);
                onExport(start, end);
              },
              child: const Text('Exportar'),
            ),
          ],
        ),
      ),
    );
  }
}
