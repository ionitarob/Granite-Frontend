import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';

import 'widgets/main_sidebar.dart';
import 'widgets/animated_background.dart';
import 'widgets/total_grading_widget.dart';
import 'widgets/grading_hoy_widget.dart';
import 'widgets/widget_grid.dart';
import 'widgets/grading_series_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/orderops_service.dart';
import 'dart:convert';
import 'models/user_model.dart';
import 'models/agent_models.dart';
import 'screens/orderops/order_detail_screen.dart';
import 'widgets/kit_digital_stats_table.dart';
import 'widgets/amz_bucket_distribution_widget.dart';
import 'widgets/amz_sorting_backlog_widget.dart';
import 'widgets/amz_recent_inventory_widget.dart';
import 'widgets/amz_quality_gauge_widget.dart';
import 'widgets/amz_graded_vs_sorted_widget.dart';
import 'widgets/amz_transfer_status_widget.dart';

enum DashboardTab { amazon, performance, kitDigital, ordenes }

class DashboardScreen extends StatefulWidget {
  final User? user;

  const DashboardScreen({super.key, this.user});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  DashboardTab _currentTab = DashboardTab.amazon;
  bool _initialTabApplied = false;
  bool _ordersLoading = false;
  String? _ordersError;
  List<AgentOrder> _dashboardOrders = const [];
  List<AgentOrder> _completedOrdersStats = const [];
  List<Map<String, String>> _ingramUsers = const [];
  final TextEditingController _ordersSearchController = TextEditingController();
  String? _ordersSelectedEstado;
  bool _ordersFilterByMe = false;

  String _normalizedRole(User u) {
    final raw = u.role.trim().toLowerCase();
    if (raw.startsWith('role_')) return raw.substring(5);
    return raw;
  }

  bool _isAdminOrChief(User u) {
    final role = _normalizedRole(u);
    return role == 'admin' || role == 'chief';
  }

  bool _applyInitialTab(User u) {
    if (_initialTabApplied) return false;
    final allowed = _availableTabsFor(u);
    if (allowed.contains(DashboardTab.performance)) {
      _currentTab = DashboardTab.performance;
    } else if (!allowed.contains(_currentTab)) {
      _currentTab = allowed.first;
    }
    _initialTabApplied = true;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _ctrl.repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDashboardOrders();
    });
  }

  int _estadoSortRank(String estado) {
    switch (estado.trim()) {
      case '3':
        return 0;
      case '2':
        return 1;
      case '4':
        return 2;
      case '1':
        return 3;
      default:
        return 99;
    }
  }

  Future<void> _loadDashboardOrders({bool silent = false}) async {
    if (_ordersLoading) return;
    if (!mounted) return;

    final api = Provider.of<ApiService>(context, listen: false);
    final service = OrderOpsService(api.client);

    if (!silent) {
      setState(() {
        _ordersLoading = true;
        _ordersError = null;
      });
    } else {
      _ordersLoading = true;
    }

    try {
      final users = await service.getIngramUsers();
      final all = await service.getAgentOrders(limit: 300);
      final completedStats = await service.getCompletedOrdersStats();
      
      final allowed = {'1', '2', '3', '4'};
      final filtered = all
          .where((o) => allowed.contains(o.estado.trim()))
          .toList();

      filtered.sort((a, b) {
        final rank = _estadoSortRank(
          a.estado,
        ).compareTo(_estadoSortRank(b.estado));
        if (rank != 0) return rank;

        final ad = a.orderDate ?? a.createdAt;
        final bd = b.orderDate ?? b.createdAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });

      if (!mounted) return;
      setState(() {
        _dashboardOrders = filtered;
        _completedOrdersStats = completedStats;
        _ingramUsers = users;
        _ordersError = null;
        _ordersLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ordersError = e.toString();
        _ordersLoading = false;
      });
    }
  }

  String _estadoLabel(String estado) {
    switch (estado.trim()) {
      case '1':
        return 'Pendiente';
      case '2':
        return 'Iniciada';
      case '3':
        return 'En ejecución';
      case '4':
        return 'En revisión';
      case '5':
        return 'Finalizado';
      default:
        return 'Estado $estado';
    }
  }

  Color _estadoColor(String estado) {
    switch (estado.trim()) {
      case '3':
        return const Color(0xFF00B8D9);
      case '2':
        return const Color(0xFFFFB300);
      case '4':
        return const Color(0xFF8E24AA);
      case '1':
        return const Color(0xFF43A047);
      case '5':
        return const Color(0xFF00897B);
      default:
        return Colors.blueGrey;
    }
  }

  String _fmtDate(DateTime? date) {
    if (date == null) return '--/--/----';
    final d = date.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year.toString();
    return '$dd/$mm/$yy';
  }

  String _formatOrderNbr(String nbr) {
    final clean = nbr.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length < 9) return nbr;
    final first = clean.substring(0, 2);
    final mid = clean.substring(2, 7);
    final last = clean.substring(7, 9);
    return '$first-$mid-$last';
  }

  DateTime? _orderStartDate(AgentOrder order) {
    return order.createdAt ?? order.orderDate;
  }

  DateTime? _orderEndDate(AgentOrder order) {
    return order.completedAt ?? order.lastTriagedAt;
  }

  Duration? _orderAge(AgentOrder order) {
    final start = _orderStartDate(order);
    if (start == null) return null;
    return DateTime.now().difference(start);
  }

  Map<String, int> _agingBucketsHours(List<AgentOrder> orders) {
    final buckets = {
      '0-24h': 0,
      '1-3d': 0,
      '4-7d': 0,
      '>7d': 0,
    };
    for (final order in orders) {
      final age = _orderAge(order);
      if (age == null) continue;
      final hours = age.inHours;
      if (hours < 24) {
        buckets['0-24h'] = (buckets['0-24h'] ?? 0) + 1;
      } else if (hours < 72) {
        buckets['1-3d'] = (buckets['1-3d'] ?? 0) + 1;
      } else if (hours < 168) {
        buckets['4-7d'] = (buckets['4-7d'] ?? 0) + 1;
      } else {
        buckets['>7d'] = (buckets['>7d'] ?? 0) + 1;
      }
    }
    return buckets;
  }

  Map<String, List<AgentOrder>> _agingBucketsLists(List<AgentOrder> orders) {
    final buckets = {
      '0-24h': <AgentOrder>[],
      '1-3d': <AgentOrder>[],
      '4-7d': <AgentOrder>[],
      '>7d': <AgentOrder>[],
    };
    for (final order in orders) {
      final age = _orderAge(order);
      if (age == null) continue;
      final hours = age.inHours;
      if (hours < 24) {
        buckets['0-24h']!.add(order);
      } else if (hours < 72) {
        buckets['1-3d']!.add(order);
      } else if (hours < 168) {
        buckets['4-7d']!.add(order);
      } else {
        buckets['>7d']!.add(order);
      }
    }
    return buckets;
  }

  String _agingBucketsDetail(Map<String, int> buckets, int total) {
    String fmt(String key, String label) {
      final count = buckets[key] ?? 0;
      final pct = total > 0 ? (count / total) * 100 : 0.0;
      return '$label: $count (${pct.toStringAsFixed(1)}%)';
    }

    return '${fmt('0-24h', '0-24h')} · ${fmt('1-3d', '1-3d')}\n'
        '${fmt('4-7d', '4-7d')} · ${fmt('>7d', '>7d')}';
  }

  String _formatOrderList(List<AgentOrder> orders, {int limit = 8}) {
    if (orders.isEmpty) return 'Sin órdenes';
    final ids = orders
        .take(limit)
        .map((o) => _formatOrderNbr(o.orderNbr))
        .toList();
    final remaining = orders.length - ids.length;
    if (remaining > 0) {
      ids.add('+$remaining más');
    }
    return ids.join(' · ');
  }

  Widget _buildOrderChip(AgentOrder order) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(orderId: order.idnbr),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.white.withOpacity(0.12),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Text(
          _formatOrderNbr(order.orderNbr),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildAgingColumn(
    ThemeData theme,
    String label,
    List<AgentOrder> orders,
    Color accentColor,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: accentColor.withOpacity(isDark ? 0.18 : 0.14),
        border: Border.all(color: accentColor.withOpacity(0.55)),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: accentColor.withOpacity(0.25),
              border: Border.all(color: accentColor.withOpacity(0.65)),
            ),
            child: Text(
              '$label (${orders.length})',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            height: 180,
            child: orders.isEmpty
                ? Center(
                    child: Text(
                      '—',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: orders.map(_buildOrderChip).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _slaBreachRateLabel(List<AgentOrder> orders, {int hours = 48}) {
    if (orders.isEmpty) return '0%';
    var breached = 0;
    for (final order in orders) {
      final age = _orderAge(order);
      if (age != null && age.inHours > hours) breached += 1;
    }
    final pct = (breached / orders.length) * 100;
    return '${pct.toStringAsFixed(1)}%';
  }

  Future<void> _showAgingBucketsPopup(List<AgentOrder> orders) async {
    final buckets = _agingBucketsLists(orders);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    await showDialog<void>(
      context: context,
      builder: (dctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 700),
              decoration: BoxDecoration(
                color: isDark ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withOpacity(isDark ? 0.12 : 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF26A69A).withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.stacked_bar_chart_rounded,
                            color: Color(0xFF26A69A),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Antigüedad de órdenes pendientes',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dctx).pop(),
                          icon: const Icon(Icons.close_rounded),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      children: [
                        _agingSection('0-24h', buckets['0-24h'] ?? []),
                        const SizedBox(height: 8),
                        _agingSection('1-3d', buckets['1-3d'] ?? []),
                        const SizedBox(height: 8),
                        _agingSection('4-7d', buckets['4-7d'] ?? []),
                        const SizedBox(height: 8),
                        _agingSection('>7d', buckets['>7d'] ?? []),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextButton(
                      onPressed: () => Navigator.of(dctx).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleAtMost(20),
                      ),
                      child: const Text(
                        'Cerrar',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _agingSection(String label, List<AgentOrder> orders) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        ),
      ),
      child: ExpansionTile(
        title: Text(
          '$label (${orders.length})',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        leading: Icon(
          Icons.calendar_today_rounded, 
          size: 18, 
          color: theme.colorScheme.primary.withOpacity(0.7),
        ),
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: orders.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('Sin órdenes')),
                ),
              ]
            : orders.map((o) => Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: _buildModernOrderCard(o),
              )).toList(),
      ),
    );
  }

  String _formatDurationCompact(Duration duration) {
    if (duration.isNegative) return '--';
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  List<AgentOrder> _getRecentCompletedOrders() {
    return _completedOrdersStats;
  }

  String _avgTimeToEstado4Label() {
    final recent = _getRecentCompletedOrders();
    if (recent.isEmpty) return '--';

    // The backend already calculates duration_ms for us based on real DB data
    final totalMillis = recent.fold<int>(0, (sum, o) {
      // Use duration_ms from backend if available, fallback to manual diff
      if (o.durationMs != null) return sum + o.durationMs!;
      
      final start = _orderStartDate(o);
      final end = o.completedAt ?? DateTime.now();
      if (start == null) return sum;
      return sum + end.difference(start).inMilliseconds;
    });

    final avgMillis = (totalMillis / recent.length).round();
    return _formatDurationCompact(Duration(milliseconds: avgMillis));
  }

  List<AgentOrder> _getSlaBreachOrders(List<AgentOrder> orders, {int hours = 48}) {
    return orders.where((o) {
      final age = _orderAge(o);
      return age != null && age.inHours > hours;
    }).toList();
  }

  Future<void> _showOrdersPopup(
    String title,
    List<AgentOrder> orders,
  ) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    await showDialog<void>(
      context: context,
      builder: (dctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              decoration: BoxDecoration(
                color: isDark ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withOpacity(isDark ? 0.12 : 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.assignment_rounded,
                            color: theme.colorScheme.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dctx).pop(),
                          icon: const Icon(Icons.close_rounded),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Content
                  Flexible(
                    child: orders.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(40.0),
                            child: Center(
                              child: Text('No hay órdenes disponibles.'),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            itemCount: orders.length,
                            itemBuilder: (ctx, i) {
                              final o = orders[i];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: _buildModernOrderCard(o),
                              );
                            },
                          ),
                  ),
                  const Divider(height: 1),
                  // Footer
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextButton(
                      onPressed: () => Navigator.of(dctx).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleAtMost(20),
                      ),
                      child: const Text(
                        'Cerrar',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildModernOrderCard(AgentOrder o) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = _estadoColor(o.estado);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OrderDetailScreen(orderId: o.idnbr),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatOrderNbr(o.orderNbr),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${o.customer} · ${_fmtDate(o.orderDate ?? o.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Text(
                  _estadoLabel(o.estado),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // RoundedRectangleAtMost helper for consistent UI
  RoundedRectangleBorder RoundedRectangleAtMost(double radius) => 
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

  Widget _buildPerformanceTile({
    required ThemeData theme,
    required String title,
    required Color accent,
    IconData? icon,
    String? value,
    String? subtitle,
    Widget? body,
    double? width,
    VoidCallback? onTap,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final tile = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: width,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: accent.withOpacity(isDark ? 0.22 : 0.18),
            border: Border.all(
              color: accent.withOpacity(isDark ? 0.5 : 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.25),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: accent),
                const SizedBox(height: 8),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: 10),
                body,
              ] else if (value != null) ...[
                const SizedBox(height: 10),
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 26),
                ],
              ],
            ],
          ),
        ),
      ),
    );

    if (onTap == null) return tile;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: tile,
    );
  }

  Widget _buildPerformanceSection(User u, ThemeData theme) {
    final estado1 = _dashboardOrders.where((o) => o.estado.trim() == '1');
    final estado2 = _dashboardOrders.where((o) => o.estado.trim() == '2');
    final estado3 = _dashboardOrders.where((o) => o.estado.trim() == '3');
    final estado4 = _dashboardOrders.where((o) => o.estado.trim() == '4');

    final e1 = estado1.toList();
    final e2 = estado2.toList();
    final e3 = estado3.toList();
    final e4 = estado4.toList();
    final activeOrders = _dashboardOrders
        .where((o) => ['1', '2', '3', '4'].contains(o.estado.trim()))
        .toList();
    final aging = _agingBucketsHours(activeOrders);
    final agingLists = _agingBucketsLists(activeOrders);
    final slaRate = _slaBreachRateLabel(activeOrders, hours: 48);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final cols = maxWidth >= 1100
            ? 4
            : (maxWidth >= 860 ? 3 : (maxWidth >= 600 ? 2 : 1));
        final spacing = 12.0;
        final tileWidth =
            (maxWidth - (cols - 1) * spacing) / cols;
        final wideWidth = cols > 1 ? (tileWidth * 2 + spacing) : tileWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed_rounded, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Performance',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                _buildPerformanceTile(
                  theme: theme,
                  title: 'Pendientes de recibir',
                  value: '${e1.length}',
                  subtitle: 'Estado 1 · Validada',
                  accent: const Color(0xFF4F7BFF),
                  icon: Icons.inbox_rounded,
                  width: tileWidth,
                  onTap: () => _showOrdersPopup(
                    'Órdenes pendientes de recibir',
                    e1,
                  ),
                ),
                _buildPerformanceTile(
                  theme: theme,
                  title: 'Recibidas pendientes de ejecutar',
                  value: '${e2.length}',
                  subtitle: 'Estado 2 · Pendiente',
                  accent: const Color(0xFFFFB74D),
                  icon: Icons.pending_actions_rounded,
                  width: tileWidth,
                  onTap: () => _showOrdersPopup(
                    'Órdenes recibidas pendientes de ejecutar',
                    e2,
                  ),
                ),
                _buildPerformanceTile(
                  theme: theme,
                  title: 'Órdenes en ejecución',
                  value: '${e3.length}',
                  subtitle: 'Estado 3 · En ejecución',
                  accent: const Color(0xFF26C6DA),
                  icon: Icons.play_circle_rounded,
                  width: tileWidth,
                  onTap: () => _showOrdersPopup(
                    'Órdenes en ejecución',
                    e3,
                  ),
                ),
                _buildPerformanceTile(
                  theme: theme,
                  title: 'Órdenes paradas',
                  value: '${e4.length}',
                  subtitle: 'Estado 4 · Parada',
                  accent: const Color(0xFFE57373),
                  icon: Icons.pause_circle_filled_rounded,
                  width: tileWidth,
                  onTap: () => _showOrdersPopup('Órdenes paradas', e4),
                ),
                _buildPerformanceTile(
                  theme: theme,
                  title: 'Tiempo promedio a finalización (últimas 20 Ordenes)',
                  value: _avgTimeToEstado4Label(),
                  subtitle: 'Desde creación a finalización',
                  accent: const Color(0xFF7E57C2),
                  icon: Icons.timer_rounded,
                  width: tileWidth,
                  onTap: () {
                    final recent = _getRecentCompletedOrders();
                    _showOrdersPopup('Últimas 20 órdenes finalizadas', recent);
                  },
                ),
                _buildPerformanceTile(
                  theme: theme,
                  title: 'Antiguedad de ordenes pendientes',
                  accent: const Color(0xFF26A69A),
                  icon: Icons.stacked_bar_chart_rounded,
                  width: wideWidth,
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildAgingColumn(
                              theme,
                              '0-24h',
                              agingLists['0-24h']!,
                              const Color(0xFF4CAF50),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildAgingColumn(
                              theme,
                              '1-3d',
                              agingLists['1-3d']!,
                              const Color(0xFFFFD54F),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildAgingColumn(
                              theme,
                              '4-7d',
                              agingLists['4-7d']!,
                              const Color(0xFFFFA726),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildAgingColumn(
                              theme,
                              '>7d',
                              agingLists['>7d']!,
                              const Color(0xFFEF5350),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                _buildPerformanceTile(
                  theme: theme,
                  title: 'Órdenes con antigüedad >48h',
                  value: slaRate,
                  accent: const Color(0xFFF06292),
                  icon: Icons.warning_amber_rounded,
                  width: tileWidth,
                  onTap: () {
                    final breached = _getSlaBreachOrders(activeOrders, hours: 48);
                    _showOrdersPopup('Órdenes con antigüedad >48h', breached);
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  List<AgentOrder> get _filteredDashboardOrders {
    var list = _dashboardOrders;

    if (_ordersSelectedEstado != null) {
      list = list
          .where((o) => o.estado.trim() == _ordersSelectedEstado)
          .toList();
    }

    if (_ordersFilterByMe) {
      final currentUser =
          Provider.of<ApiService>(context, listen: false).currentUser;
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

    final query = _ordersSearchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      final cleanQuery = query.replaceAll('-', '');
      list = list.where((o) {
        final cleanOrderNbr = o.orderNbr.toLowerCase().replaceAll('-', '');
        final nbrMatch = cleanOrderNbr.contains(cleanQuery);
        return nbrMatch ||
            o.customer.toLowerCase().contains(query) ||
            (o.sourcePrimaryDesc ?? '').toLowerCase().contains(query);
      }).toList();
    }

    return list;
  }

  Widget _buildOrdersSearchBar(ThemeData theme) {
    final estados =
        _dashboardOrders
            .map((e) => e.estado.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final selectedEstadoValue =
        (_ordersSelectedEstado != null &&
                estados.contains(_ordersSelectedEstado))
            ? _ordersSelectedEstado
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
                controller: _ordersSearchController,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar por orden, cliente...',
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(
                      isDark ? 0.65 : 0.55,
                    ),
                  ),
                  filled: true,
                  fillColor: isDark
                      ? theme.colorScheme.surface.withOpacity(0.5)
                      : theme.colorScheme.surface.withOpacity(0.95),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: theme.dividerColor.withOpacity(
                        isDark ? 0.1 : 0.35,
                      ),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: theme.dividerColor.withOpacity(
                        isDark ? 0.1 : 0.35,
                      ),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (isMobile)
              const SizedBox(height: 12)
            else
              const SizedBox(width: 16),
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
                      if (e.contains('1'))
                        label = 'Validada';
                      else if (e.contains('2'))
                        label = 'Pendiente';
                      else if (e.contains('3'))
                        label = 'En Ejecución';
                      else if (e.contains('4'))
                        label = 'Parada';
                      else if (e.contains('5'))
                        label = 'Finalizada';
                      else if (e.contains('6'))
                        label = 'Facturada';
                      return DropdownMenuItem(
                        value: e,
                        child: Text(label.isEmpty ? 'Sin Estado' : label),
                      );
                    }),
                  ],
                  onChanged: (val) =>
                      setState(() => _ordersSelectedEstado = val),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Mis órdenes'),
              selected: _ordersFilterByMe,
              onSelected: (val) => setState(() => _ordersFilterByMe = val),
              selectedColor: theme.colorScheme.primaryContainer,
              checkmarkColor: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdenesPage(ThemeData theme) {
    return DashboardSurface(
      title: 'Órdenes',
      subtitle: 'Pendientes, en ejecución o en revisión',
      headerRight: IconButton(
        tooltip: 'Actualizar',
        onPressed: () => _loadDashboardOrders(),
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: Builder(
        builder: (ctx) {
          final u =
              widget.user ??
              Provider.of<ApiService>(ctx, listen: false).currentUser ??
              User(username: 'demo', role: 'admin');
          if (_ordersLoading && _dashboardOrders.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_ordersError != null && _dashboardOrders.isEmpty) {
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
                    _ordersError!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _loadDashboardOrders(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          if (_dashboardOrders.isEmpty) {
            return const Center(
              child: Text('No hay órdenes en estados 1, 2, 3 o 4'),
            );
          }

          final filteredOrders = _filteredDashboardOrders;

          return Column(
            children: [
              _buildOrdersSearchBar(theme),
              const SizedBox(height: 16),
              if (filteredOrders.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      'No se encontraron órdenes.',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: filteredOrders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final o = filteredOrders[i];
                      final statusColor = _estadoColor(o.estado);
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  OrderDetailScreen(orderId: o.idnbr),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: theme.brightness == Brightness.dark
                                ? Colors.white.withOpacity(0.04)
                                : Colors.black.withOpacity(0.03),
                            border: Border.all(
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _formatOrderNbr(o.orderNbr),
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: statusColor.withOpacity(0.55),
                                      ),
                                    ),
                                    child: Text(
                                      _estadoLabel(o.estado),
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                o.customer,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    size: 14,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.65),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _fmtDate(o.orderDate ?? o.createdAt),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(width: 14),
                                  Icon(
                                    Icons.flag_rounded,
                                    size: 14,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.65),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    o.prioridad,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
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
        },
      ),
    );
  }

  // Bump this to force WidgetGrid to reinitialize when layout changes.
  int _widgetGridRevision = 0;

  Future<void> _addWidgetToLayout(String storageKey, String widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final raw = prefs.getString(storageKey);
    List layout;
    if (raw != null) {
      try {
        layout = json.decode(raw) as List;
      } catch (_) {
        layout = [];
      }
    } else {
      layout = [];
    }

    // Place into first null slot if present, otherwise append
    final nullIndex = layout.indexWhere((e) => e == null);
    if (nullIndex >= 0) {
      layout[nullIndex] = widgetId;
    } else {
      layout.add(widgetId);
    }

    await prefs.setString(storageKey, json.encode(layout));
    setState(() => _widgetGridRevision++);
  }

  Future<void> _onAddWidgetPressed(BuildContext ctx) async {
    // Use this state's context for synchronous lookups to avoid holding on to
    // the caller's BuildContext across async gaps.
    final api = Provider.of<ApiService>(context, listen: false);
    final u =
        widget.user ?? api.currentUser ?? User(username: 'demo', role: 'admin');
    final storageKey = 'widget_layout_${u.username}';

    // Available widgets (same keys used by WidgetGrid)
    final available = <String, String>{
      'total_grading': 'Total grading',
      'grading_hoy': 'Grading Hoy',
      'grading_series': 'Grading Series',
      'amz_buckets': 'Distribución Buckets',
      'amz_sorting': 'Sorting Backlog',
      'amz_inventory_logs': 'Actividad Reciente',
      'amz_quality': 'Índice Calidad',
      'amz_performance': 'Rendimiento (G vs S)',
      'amz_transfers': 'Estado Transferencias',
    };

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    List existing = [];
    if (raw != null) {
      try {
        existing = json.decode(raw) as List;
      } catch (_) {
        existing = [];
      }
    } else {
      // default: assume nothing persisted yet
      existing = [];
    }

    final present = <String>{};
    for (final e in existing) {
      if (e is String) present.add(e);
    }

    final remaining = available.keys
        .where((k) => !present.contains(k))
        .toList();
    if (remaining.isEmpty) {
      // Use the State's context after async gaps to avoid build-context warnings
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more widgets available to add')),
      );
      return;
    }

    final selected = await showDialog<String?>(
      context: context,
      builder: (dctx) => SimpleDialog(
        title: const Text('Add widget'),
        children: remaining
            .map(
              (id) => SimpleDialogOption(
                onPressed: () => Navigator.of(dctx).pop(id),
                child: Text(available[id] ?? id),
              ),
            )
            .toList(),
      ),
    );

    if (!mounted) return;
    if (selected != null) {
      await _addWidgetToLayout(storageKey, selected);
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 6 && h < 12) return 'Buenos días';
    if (h >= 12 && h < 20) return 'Buenas tardes';
    return 'Buenas noches';
  }

  String _displayName(User u) {
    if (u.nombre != null && u.nombre!.isNotEmpty) {
      return u.nombre!;
    }
    return (u.username.isNotEmpty) ? u.username : 'Usuario';
  }

  bool _isOperario(User u) {
    final r = (u.role).toLowerCase().trim().replaceAll(' ', '_');
    return r == 'operario_básico' || r == 'operario_avanzado';
  }

  /// Placeholder: más adelante lo traerás del backend.
  /// Por ahora puedes hardcodear o sacar de SharedPrefs cuando lo implementes.
  String _assignedArea(User u) {
    // ejemplos: "Amazon" / "Kit Digital"
    // si no existe, default Amazon para operarios:
    return 'Amazon';
  }

  int _currentPerformancePct(User u) {
    // placeholder
    return 0;
  }

  List<DashboardTab> _availableTabsFor(User u) {
    if (_isOperario(u)) {
      final area = _assignedArea(u).toLowerCase().trim();
      if (area.contains('kit')) {
        return [DashboardTab.kitDigital, DashboardTab.ordenes];
      }
      return [DashboardTab.amazon, DashboardTab.ordenes]; // default Amazon
    }
    // Otros roles ven todo
    if (_isAdminOrChief(u)) {
      return [
        DashboardTab.performance,
        DashboardTab.amazon,
        DashboardTab.kitDigital,
        DashboardTab.ordenes,
      ];
    }
    return [DashboardTab.amazon, DashboardTab.kitDigital, DashboardTab.ordenes];
  }

  /// Garantiza que el tab actual sea válido según el rol/asignación.
  void _ensureValidTab(User u) {
    final allowed = _availableTabsFor(u);
    if (!_initialTabApplied) {
      if (_applyInitialTab(u) && mounted) {
        setState(() {});
      }
      return;
    }
    if (!allowed.contains(_currentTab)) {
      setState(() => _currentTab = allowed.first);
    }
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required List<Color> gradientColors,
    required bool isDark,
  }) {
    final width = MediaQuery.of(context).size.width;
    final isVeryNarrow = width < 520;

    final card = Container(
      height: 100,
      width: isVeryNarrow ? 160 : null,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E1E2C).withOpacity(0.8)
            : Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Bottom Gradient Line
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 2,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
                gradient: LinearGradient(colors: gradientColors),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: isVeryNarrow ? 12 : 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isVeryNarrow ? 22 : 28,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          // Subtle Glow
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    gradientColors.first.withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (isVeryNarrow) return card;
    return Expanded(child: card);
  }

  Widget _buildTopHeader(User u, ThemeData theme) {
    final isOperario = _isOperario(u);
    final isDark = theme.brightness == Brightness.dark;
    final isVeryNarrow = MediaQuery.of(context).size.width < 520;

    Widget block;

    if (isOperario) {
      final area = _assignedArea(u);
      final perf = _currentPerformancePct(u);

      block = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          // Glassmorphism subtle
          color: isDark
              ? const Color(0xFF1E1E2C).withOpacity(0.6)
              : Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.05),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isVeryNarrowLayout = constraints.maxWidth < 420;
            return Wrap(
              direction: Axis.horizontal,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.tertiary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                SizedBox(width: isVeryNarrowLayout ? 12 : 20),
                SizedBox(
                  width: isVeryNarrowLayout
                      ? (constraints.maxWidth - 60)
                      : (constraints.maxWidth - 300) / 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Asignación Actual',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        area,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isVeryNarrowLayout)
                  const SizedBox(height: 12, width: double.infinity),
                if (!isVeryNarrowLayout)
                  Container(
                    height: 50,
                    width: 1,
                    color: theme.dividerColor.withOpacity(0.1),
                  ),
                if (!isVeryNarrowLayout) const SizedBox(width: 20),
                SizedBox(
                  width: isVeryNarrowLayout
                      ? (constraints.maxWidth - 20)
                      : (constraints.maxWidth - 300) / 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rendimiento',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '$perf%',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: perf >= 90
                                  ? Colors.greenAccent
                                  : (perf >= 70
                                        ? Colors.orangeAccent
                                        : Colors.redAccent),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            perf >= 0
                                ? Icons.trending_up_rounded
                                : Icons
                                      .trending_down_rounded, // Placeholder logic
                            color: perf >= 90
                                ? Colors.greenAccent
                                : (perf >= 70
                                      ? Colors.orangeAccent
                                      : Colors.redAccent),
                            size: 20,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    } else {
      // Orders that are not Finalizado (5) nor Facturado (6) — already filtered in _dashboardOrders.
      final pendingCount = _dashboardOrders.length;
      final pendingLabel = _ordersLoading && _dashboardOrders.isEmpty
          ? '...'
          : '$pendingCount';

      // Orders that belong to Ingram users (assigned_to field)
      final assignedCount = _dashboardOrders
          .where(
            (o) =>
                o.assignedTo != null &&
                _ingramUsers.any((u) => u['username'] == o.assignedTo!.trim()),
          )
          .length;
      final assignedLabel = _ordersLoading && _dashboardOrders.isEmpty
          ? '...'
          : '$assignedCount';

      block = isVeryNarrow
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  _buildMetricCard(
                    title: 'Órdenes pendientes',
                    value: pendingLabel,
                    gradientColors: [
                      const Color(0xFFF12711),
                      const Color(0xFFF5AF19),
                    ],
                    isDark: isDark,
                  ),
                  _buildMetricCard(
                    title: 'Órdenes asignadas',
                    value: assignedLabel,
                    gradientColors: [
                      const Color(0xFF2193b0),
                      const Color(0xFF6dd5ed),
                    ],
                    isDark: isDark,
                  ),
                  _buildMetricCard(
                    title: 'Incidencias',
                    value: '0',
                    gradientColors: [
                      const Color(0xFF833ab4),
                      const Color(0xFFfd1d1d),
                    ],
                    isDark: isDark,
                  ),
                ],
              ),
            )
          : Row(
              children: [
                _buildMetricCard(
                  title: 'Órdenes pendientes',
                  value: pendingLabel,
                  gradientColors: [
                    const Color(0xFFF12711),
                    const Color(0xFFF5AF19),
                  ],
                  isDark: isDark,
                ),
                _buildMetricCard(
                  title: 'Órdenes asignadas',
                  value: assignedLabel,
                  gradientColors: [
                    const Color(0xFF2193b0),
                    const Color(0xFF6dd5ed),
                  ],
                  isDark: isDark,
                ),
                _buildMetricCard(
                  title: 'Incidencias',
                  value: '0',
                  gradientColors: [
                    const Color(0xFF833ab4),
                    const Color(0xFFfd1d1d),
                  ],
                  isDark: isDark,
                ),
              ],
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${_greeting()}, ',
              style:
                  (isOperario
                          ? theme.textTheme.headlineSmall
                          : (isVeryNarrow
                                ? theme.textTheme.titleMedium
                                : theme.textTheme.headlineSmall))
                      ?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(
                          0.8,
                        ),
                      ),
            ),
            Text(
              _displayName(u),
              style:
                  (isOperario
                          ? theme.textTheme.headlineSmall
                          : (isVeryNarrow
                                ? theme.textTheme.titleMedium
                                : theme.textTheme.headlineSmall))
                      ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 20),
        block,
      ],
    );
  }

  // Central content area shared by desktop and mobile layouts.
  Widget _buildNavigationSelector(ThemeData theme, User u) {
    final allowed = _availableTabsFor(u);

    final segments = <ButtonSegment<DashboardTab>>[];
    if (allowed.contains(DashboardTab.amazon)) {
      segments.add(
        const ButtonSegment(
          value: DashboardTab.amazon,
          label: Text('Amazon'),
          icon: Icon(Icons.storefront),
        ),
      );
    }
    if (allowed.contains(DashboardTab.performance)) {
      segments.add(
        const ButtonSegment(
          value: DashboardTab.performance,
          label: Text('Performance'),
          icon: Icon(Icons.speed_rounded),
        ),
      );
    }
    if (allowed.contains(DashboardTab.kitDigital)) {
      segments.add(
        const ButtonSegment(
          value: DashboardTab.kitDigital,
          label: Text('Kit Digital'),
          icon: Icon(Icons.auto_graph_rounded),
        ),
      );
    }
    if (allowed.contains(DashboardTab.ordenes)) {
      segments.add(
        const ButtonSegment(
          value: DashboardTab.ordenes,
          label: Text('Órdenes'),
          icon: Icon(Icons.receipt_long_rounded),
        ),
      );
    }

    final isVeryNarrow = MediaQuery.of(context).size.width < 520;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SegmentedButton<DashboardTab>(
          segments: segments,
          selected: {_currentTab},
          onSelectionChanged: (s) {
            final next = s.first;
            setState(() => _currentTab = next);
            if (next == DashboardTab.ordenes) {
              _loadDashboardOrders(silent: true);
            }
          },
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: isVeryNarrow
                ? VisualDensity.compact
                : VisualDensity.comfortable,
            padding: EdgeInsets.symmetric(
              horizontal: isVeryNarrow ? 8 : 12,
              vertical: isVeryNarrow ? 6 : 8,
            ),
            textStyle: TextStyle(
              fontSize: isVeryNarrow ? 12 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // Central content area shared by desktop and mobile layouts.
  Widget _buildMainContent(ThemeData theme, ColorScheme colorScheme, User u) {
    // asegura tab válido (por rol/asignación)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureValidTab(u);
    });

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // HEADER ARRIBA
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: _buildTopHeader(u, theme),
            ),
          ),

          const SizedBox(height: 18),

          // Tabs más abajo (como querías)
          _buildNavigationSelector(theme, u),
          const SizedBox(height: 24),

          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: KeyedSubtree(
                    key: ValueKey<DashboardTab>(_currentTab),
                    child: _buildCurrentPage(theme, colorScheme, u),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPage(ThemeData theme, ColorScheme colorScheme, User u) {
    switch (_currentTab) {
      case DashboardTab.amazon:
        return _buildAmazonPage(theme, colorScheme);

      case DashboardTab.performance:
        return _buildPerformancePage(theme, u);

      case DashboardTab.kitDigital:
        return DashboardSurface(
          title: 'Kit Digital',
          subtitle: 'Resumen de actividad y métricas',
          child: const Padding(
            padding: EdgeInsets.only(top: 6),
            child: KitDigitalStatsTable(),
          ),
        );

      case DashboardTab.ordenes:
        return _buildOrdenesPage(theme);
    }
  }

  Widget _buildPerformancePage(ThemeData theme, User u) {
    return DashboardSurface(
      title: 'Performance',
      subtitle: 'Métricas operativas y tiempos de ejecución',
      headerRight: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => _showExportDialog(theme),
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
            onPressed: () => _loadDashboardOrders(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      child: Builder(
        builder: (ctx) {
          if (_ordersLoading && _dashboardOrders.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_ordersError != null && _dashboardOrders.isEmpty) {
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
                    _ordersError!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _loadDashboardOrders(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          if (_dashboardOrders.isEmpty) {
            return const Center(
              child: Text('No hay órdenes en estados 1, 2, 3 o 4'),
            );
          }

          if (!_isAdminOrChief(u)) {
            return const Center(child: Text('Sin permisos para Performance'));
          }

          return SingleChildScrollView(
            child: _buildPerformanceSection(u, theme),
          );
        },
      ),
    );
  }

  void _navigateToRoute(String route) {
    Navigator.of(context, rootNavigator: true).pushNamed(route);
  }

  Future<void> _showExportDialog(ThemeData theme) async {
    DateTimeRange? selectedRange;
    DateTime? selectedMonth = DateTime.now();
    bool isMonthMode = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = theme.brightness == Brightness.dark;
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AlertDialog(
              backgroundColor: theme.colorScheme.surface.withOpacity(0.85),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                ),
              ),
              title: Row(
                children: [
                  Icon(Icons.download_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  const Text('Exportar Datos'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('Por Mes'),
                        icon: Icon(Icons.calendar_month_rounded),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('Rango Personalizado'),
                        icon: Icon(Icons.date_range_rounded),
                      ),
                    ],
                    selected: {isMonthMode},
                    onSelectionChanged: (val) {
                      setDialogState(() => isMonthMode = val.first);
                    },
                  ),
                  const SizedBox(height: 24),
                  if (isMonthMode)
                    ListTile(
                      title: const Text('Mes seleccionado'),
                      subtitle: Text(
                        DateFormat('MMMM yyyy', 'es_ES').format(selectedMonth!),
                      ),
                      trailing: const Icon(Icons.edit_calendar_rounded),
                      onTap: () async {
                        final now = DateTime.now();
                        // Show a simplified month picker instead of a full calendar
                        final month = await showDialog<DateTime>(
                          context: context,
                          builder: (ctx) => BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: AlertDialog(
                              title: const Text('Seleccionar Mes'),
                              content: SizedBox(
                                width: 300,
                                height: 400,
                                child: ListView.builder(
                                  itemCount: 36, // Last 3 years
                                  itemBuilder: (context, index) {
                                    final d = DateTime(now.year, now.month - index, 1);
                                    final isSelected = selectedMonth?.month == d.month && selectedMonth?.year == d.year;
                                    return ListTile(
                                      title: Text(
                                        DateFormat('MMMM yyyy', 'es_ES').format(d),
                                        style: TextStyle(
                                          fontWeight: isSelected ? FontWeight.bold : null,
                                          color: isSelected ? theme.colorScheme.primary : null,
                                        ),
                                      ),
                                      selected: isSelected,
                                      onTap: () => Navigator.pop(ctx, d),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                        if (month != null) {
                          setDialogState(() => selectedMonth = month);
                        }
                      },
                    )
                  else
                    ListTile(
                      title: const Text('Rango de fechas'),
                      subtitle: Text(
                        selectedRange == null
                            ? 'No seleccionado'
                            : '${DateFormat('dd/MM/yyyy').format(selectedRange!.start)} - ${DateFormat('dd/MM/yyyy').format(selectedRange!.end)}',
                      ),
                      trailing: const Icon(Icons.date_range_rounded),
                      onTap: () async {
                        // Custom dialog to pick two dates without full-screen takeover
                        await showDialog(
                          context: context,
                          builder: (ctx) => BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: StatefulBuilder(
                              builder: (context, setInternalState) {
                                return AlertDialog(
                                  title: const Text('Seleccionar Rango'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        title: const Text('Desde'),
                                        subtitle: Text(selectedRange?.start == null ? 'Seleccionar' : DateFormat('dd/MM/yyyy').format(selectedRange!.start)),
                                        leading: const Icon(Icons.calendar_today_rounded),
                                        onTap: () async {
                                          final d = await showDatePicker(
                                            context: context,
                                            initialDate: selectedRange?.start ?? DateTime.now(),
                                            firstDate: DateTime(2020),
                                            lastDate: DateTime.now(),
                                          );
                                          if (d != null) {
                                            setInternalState(() {
                                              selectedRange = DateTimeRange(start: d, end: selectedRange?.end ?? d.add(const Duration(days: 1)));
                                              setDialogState(() {});
                                            });
                                          }
                                        },
                                      ),
                                      ListTile(
                                        title: const Text('Hasta'),
                                        subtitle: Text(selectedRange?.end == null ? 'Seleccionar' : DateFormat('dd/MM/yyyy').format(selectedRange!.end)),
                                        leading: const Icon(Icons.event_available_rounded),
                                        onTap: () async {
                                          final d = await showDatePicker(
                                            context: context,
                                            initialDate: selectedRange?.end ?? DateTime.now(),
                                            firstDate: selectedRange?.start ?? DateTime(2020),
                                            lastDate: DateTime.now(),
                                          );
                                          if (d != null) {
                                            setInternalState(() {
                                              selectedRange = DateTimeRange(start: selectedRange?.start ?? d.subtract(const Duration(days: 1)), end: d);
                                              setDialogState(() {});
                                            });
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Aceptar'),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    if (isMonthMode) {
                      final start = DateTime(selectedMonth!.year, selectedMonth!.month, 1);
                      final end = DateTime(selectedMonth!.year, selectedMonth!.month + 1, 0, 23, 59, 59);
                      _exportData(start, end);
                    } else if (selectedRange != null) {
                      _exportData(selectedRange!.start, selectedRange!.end);
                    }
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Exportar Excel'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _exportData(DateTime start, DateTime end) async {
    setState(() => _ordersLoading = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final service = OrderOpsService(apiService.client);
      
      final bytes = await service.exportOrdersExcel(
        start: start.toIso8601String(),
        end: end.toIso8601String(),
      );

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'orders_export_${DateFormat('yyyyMMdd').format(start)}_${DateFormat('yyyyMMdd').format(end)}.xlsx';
      final file = File('${dir.path}/$fileName');
      
      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exportación completada y abierta')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al exportar: $e')),
      );
    } finally {
      if (mounted) setState(() => _ordersLoading = false);
    }
  }

  Future<void> _showProjectsPopup() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.62,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (ctx, scrollController) {
            return Material(
              color: const Color(0xFF111827),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.widgets_rounded, color: Colors.white70),
                        SizedBox(width: 8),
                        Text(
                          'Proyectos',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Colors.white10),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        _projectSection(
                          title: 'Amazon',
                          icon: Icons.shopping_basket_rounded,
                          routes: const [
                            ('Grading · Registro Grading', '/amazon/grading'),
                            ('Grading · Sorting', '/amazon/sorting'),
                            ('Grading · Quality Check', '/amazon/quality'),
                            (
                              'Grading · Herramientas · Cerrar Box',
                              '/amazon/herramientas/closebox',
                            ),
                            (
                              'Grading · Herramientas · Buscar Box',
                              '/amazon/herramientas/findbox',
                            ),
                            (
                              'Grading · Herramientas · Buscar DSN',
                              '/amazon/herramientas/finddsn',
                            ),
                            ('Inventory · Registro', '/amazon/inventory'),
                            (
                              'Inventory · Picking',
                              '/amazon/inventory/picking',
                            ),
                            (
                              'Inventory · Receiving',
                              '/amazon/inventory/receiving',
                            ),
                            ('Inventory · ICQA', '/amazon/inventory/icqa'),
                          ],
                        ),
                        _projectSection(
                          title: 'Igualdad',
                          icon: Icons.dashboard_rounded,
                          routes: const [
                            ('Dashboard', '/igualdad/dashboard'),
                            ('Entrada Stock', '/igualdad/entrada'),
                            (
                              'Registro · Smartphone',
                              '/igualdad/registro/smartphone',
                            ),
                            (
                              'Registro · Pulsera',
                              '/igualdad/registro/pulsera',
                            ),
                            (
                              'Registro · Powerbank',
                              '/igualdad/registro/powerbank',
                            ),
                            ('Registro · Botón', '/igualdad/registro/boton'),
                            ('Historial', '/igualdad/historial'),
                          ],
                        ),
                        _projectSection(
                          title: 'Serials',
                          icon: Icons.swap_horizontal_circle_rounded,
                          routes: const [
                            ('Registro Serial', '/serials/cambio'),
                            ('Cambio Serial', '/serials/change'),
                            ('Etiquetas', '/serials/labels'),
                            ('Máscaras', '/serials/masks'),
                            ('Historial Cambios', '/serials/serial-changes'),
                          ],
                        ),
                        _projectSection(
                          title: 'Xiaomi',
                          icon: Icons.smartphone_rounded,
                          routes: const [
                            ('Registro Unidades', '/xiaomi/registro/unidades'),
                            ('Producción CESB', '/xiaomi/cerrar_cesb'),
                            ('Historial', '/xiaomi/historial'),
                            ('Estadísticas', '/xiaomi/estadisticas'),
                          ],
                        ),
                        _projectSection(
                          title: 'Servidores',
                          icon: Icons.storage_rounded,
                          routes: const [
                            ('Previ', '/servers/previ'),
                            ('Servidores', '/servers/servidores'),
                          ],
                        ),
                        _projectSection(
                          title: 'Sentinel AI',
                          icon: Icons.psychology_rounded,
                          routes: const [
                            ('Mesa Activa', '/sentinel/tables'),
                            ('Imágenes Activas', '/sentinel/active'),
                          ],
                        ),
                        _projectSection(
                          title: 'Análisis y Servicios',
                          icon: Icons.analytics_rounded,
                          routes: const [
                            ('Dashboard', '/analisis/dashboard'),
                            ('Gestión', '/analisis/management'),
                          ],
                        ),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showHrPopup() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Material(
          color: const Color(0xFF111827),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const ListTile(
                    leading: Icon(
                      Icons.people_alt_rounded,
                      color: Colors.white,
                    ),
                    title: Text(
                      'Recursos Humanos',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  _sheetRouteTile('Fichaje', '/hr/fichaje'),
                  _sheetRouteTile('Alta Empleado', '/hr/alta_empleado'),
                  _sheetRouteTile('Registro Fichajes', '/hr/registro_fichaje'),
                  _sheetRouteTile(
                    'Asignación Trabajo',
                    '/hr/asignacion_trabajo',
                  ),
                  _sheetRouteTile('Gestión Empleado', '/hr/gestion_empleado'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _projectSection({
    required String title,
    required IconData icon,
    required List<(String, String)> routes,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(icon, color: Colors.white70),
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white70,
        textColor: Colors.white,
        collapsedTextColor: Colors.white,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        children: routes
            .map((entry) => _sheetRouteTile(entry.$1, entry.$2, leftPad: 28))
            .toList(),
      ),
    );
  }

  Widget _sheetRouteTile(String label, String route, {double leftPad = 12}) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: leftPad, right: 12),
      leading: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: Colors.white54,
      ),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      onTap: () {
        Navigator.of(context).pop();
        _navigateToRoute(route);
      },
    );
  }

  Widget _mobileDockButton({
    required IconData icon,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: selected ? 56 : 48,
        height: selected ? 56 : 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? primary.withOpacity(0.18) : Colors.transparent,
          border: selected
              ? Border.all(color: primary.withOpacity(0.5))
              : Border.all(color: Colors.transparent),
        ),
        child: Icon(
          icon,
          color: selected ? primary : Colors.white,
          size: selected ? 30 : 28,
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildMobileDock(ThemeData theme, User u) {
    final canSeeHr = !_isOperario(u);
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF111827).withOpacity(0.88),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: Colors.white10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _mobileDockButton(
                icon: Icons.receipt_long_rounded,
                onTap: () => _navigateToRoute('/orderops/queue'),
              ),
              _mobileDockButton(
                icon: Icons.home_rounded,
                selected: true,
                onTap: () {
                  final allowed = _availableTabsFor(u);
                  if (allowed.contains(_currentTab)) return;
                  setState(() => _currentTab = allowed.first);
                },
              ),
              _mobileDockButton(
                icon: Icons.widgets_rounded,
                onTap: _showProjectsPopup,
              ),
              if (canSeeHr)
                _mobileDockButton(
                  icon: Icons.people_alt_rounded,
                  onTap: _showHrPopup,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // The inner content block that holds widgets; reused by desktop and mobile
  Widget _buildAmazonPage(ThemeData theme, ColorScheme colorScheme) {
    // Reusing the DashboardSurface for Amazon to ensure consistency
    return DashboardSurface(
      title: 'Amazon',
      subtitle: 'Grading y Sorting Metricas',
      // We can leave title null if we want to rely on the widgets themselves,
      // but providing a container establishes the glass look.
      // Amazon tab has a dynamic grid, so we might not want a fixed title here
      // or we can add one for consistency.
      headerRight: Container(
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          onPressed: () => _onAddWidgetPressed(context),
          icon: const Icon(Icons.add_rounded),
          color: theme.textTheme.bodyLarge?.color,
          tooltip: 'Add widget',
        ),
      ),
      child: Builder(
        builder: (ctx) {
          final u =
              widget.user ??
              Provider.of<ApiService>(ctx, listen: false).currentUser ??
              User(username: 'demo', role: 'admin');
          final available = <String, Widget>{
            'total_grading': TotalGradingWidget(),
            'grading_hoy': GradingHoyWidget(),
            'grading_series': GradingSeriesWidget(),
            'amz_buckets': AmzBucketDistributionWidget(),
            'amz_sorting': AmzSortingBacklogWidget(),
            'amz_inventory_logs': AmzRecentInventoryWidget(),
            'amz_quality': AmzQualityGaugeWidget(),
            'amz_performance': AmzGradedVsSortedWidget(),
            'amz_transfers': AmzTransferStatusWidget(),
          };
          final spans = <String, int>{
            'grading_series': 2,
            'amz_performance': 2,
            'amz_transfers': 2,
          };
          return WidgetGrid(
            key: ValueKey(_widgetGridRevision),
            availableWidgets: available,
            storageKey: 'widget_layout_${u.username}',
            spanColumns: spans,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _ordersSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,

      // Removed AppBar for full-height sidebar and macOS aesthetic
      body: Stack(
        children: [
          // Animated background that adapts to Bright/Dark theme
          const AnimatedBackgroundWidget(intensity: 1.0),

          // Content: show permanent sidebar on wide screens; on mobile show
          // a compact header with an EdgeNavHandle and the main content full-width.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Builder(
                builder: (ctx) {
                  final isMobileInner = MediaQuery.of(ctx).size.width < 900;
                  final u =
                      widget.user ??
                      Provider.of<ApiService>(ctx, listen: false).currentUser ??
                      User(username: 'demo', role: 'admin');
                  if (!isMobileInner) {
                    // Desktop: permanent sidebar + content
                    final routeName = ModalRoute.of(context)?.settings.name;
                    return Row(
                      children: [
                        MainSidebar(
                          user: u,
                          permanent: true,
                          currentRoute: routeName,
                        ),
                        Expanded(
                          child: _buildMainContent(theme, colorScheme, u),
                        ),
                      ],
                    );
                  }

                  // Mobile: full content + floating dock navigation.
                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              _buildTopHeader(u, theme),
                              const SizedBox(height: 14),
                              _buildNavigationSelector(theme, u),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: MediaQuery.of(ctx).size.height * 0.7,
                                child: _buildCurrentPage(theme, colorScheme, u),
                              ),
                              const SizedBox(height: 110),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Small widget that shows the animated AI sphere in the bottom-right.
// It plays the provided Lottie animation and reacts to mouse hover by growing
// slightly and adding a glow.

class DashboardSurface extends StatelessWidget {
  final Widget child;
  final Widget? headerRight;
  final String? title;
  final String? subtitle;

  const DashboardSurface({
    super.key,
    required this.child,
    this.headerRight,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withOpacity(0.22)
                : Colors.white.withOpacity(0.16),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.10), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null || headerRight != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (title != null)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title!,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.65),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    else
                      const Spacer(),
                    if (headerRight != null) headerRight!,
                  ],
                ),
                const SizedBox(height: 14),
                Divider(color: Colors.white.withOpacity(0.08), height: 1),
                const SizedBox(height: 14),
              ],
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
