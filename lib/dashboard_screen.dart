import 'dart:ui';
import 'package:flutter/material.dart';

import 'widgets/main_sidebar.dart';
import 'widgets/animated_background.dart';
import 'widgets/total_grading_widget.dart';
import 'widgets/grading_hoy_widget.dart';
import 'widgets/widget_grid.dart';
import 'widgets/grading_series_widget.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/orderops_service.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'models/user_model.dart';
import 'models/agent_models.dart';
import 'config.dart';
import 'screens/orderops/order_detail_screen.dart';
import 'widgets/kit_digital_stats_table.dart';
import 'widgets/amz_bucket_distribution_widget.dart';
import 'widgets/amz_sorting_backlog_widget.dart';
import 'widgets/amz_recent_inventory_widget.dart';
import 'widgets/amz_quality_gauge_widget.dart';
import 'widgets/amz_graded_vs_sorted_widget.dart';
import 'widgets/amz_transfer_status_widget.dart';

enum DashboardTab { amazon, kitDigital, ordenes }

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
  bool _ordersLoading = false;
  String? _ordersError;
  List<AgentOrder> _dashboardOrders = const [];

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
      final all = await service.getAgentOrders(limit: 300);
      final allowed = {'1', '2', '3', '4'};
      final filtered = all
          .where((o) => allowed.contains(o.estado.trim()))
          .toList();

      filtered.sort((a, b) {
        final rank = _estadoSortRank(a.estado).compareTo(_estadoSortRank(b.estado));
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

          return ListView.separated(
            itemCount: _dashboardOrders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final o = _dashboardOrders[i];
              final statusColor = _estadoColor(o.estado);
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderDetailScreen(orderId: o.idnbr),
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
                      color: theme.colorScheme.onSurface.withOpacity(0.08),
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
                              style: theme.textTheme.titleMedium?.copyWith(
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
                              border: Border.all(color: statusColor.withOpacity(0.55)),
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
                            color: theme.colorScheme.onSurface.withOpacity(0.65),
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
                            color: theme.colorScheme.onSurface.withOpacity(0.65),
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
    return [DashboardTab.amazon, DashboardTab.kitDigital, DashboardTab.ordenes];
  }

  /// Garantiza que el tab actual sea válido según el rol/asignación.
  void _ensureValidTab(User u) {
    final allowed = _availableTabsFor(u);
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
    final isVeryNarrow = width < 420;

    return Expanded(
      flex: isVeryNarrow ? 0 : 1,
      child: Container(
        height: isVeryNarrow ? 85 : 100,
        width: isVeryNarrow ? double.infinity : null,
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
      ),
    );
  }

  Widget _buildTopHeader(User u, ThemeData theme) {
    final isOperario = _isOperario(u);
    final isDark = theme.brightness == Brightness.dark;

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
            final isVeryNarrow = constraints.maxWidth < 420;
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
                SizedBox(width: isVeryNarrow ? 12 : 20),
                SizedBox(
                  width: isVeryNarrow ? (constraints.maxWidth - 60) : (constraints.maxWidth - 300) / 2,
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
                if (isVeryNarrow) const SizedBox(height: 12, width: double.infinity),
                if (!isVeryNarrow)
                  Container(
                    height: 50,
                    width: 1,
                    color: theme.dividerColor.withOpacity(0.1),
                  ),
                if (!isVeryNarrow) const SizedBox(width: 20),
                SizedBox(
                  width: isVeryNarrow ? (constraints.maxWidth - 20) : (constraints.maxWidth - 300) / 2,
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
                                : Icons.trending_down_rounded, // Placeholder logic
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
      // Admin / Supervisor View with Cards
      final width = MediaQuery.of(context).size.width;
      final isVeryNarrow = width < 520;

      block = SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: isVeryNarrow ? 8 : 0,
          runSpacing: isVeryNarrow ? 8 : 0,
          children: [
            _buildMetricCard(
              title: 'Órdenes pendientes',
              value: '0',
              gradientColors: [
                const Color(0xFFF12711),
                const Color(0xFFF5AF19),
              ], // Orange/Red
              isDark: isDark,
            ),
            _buildMetricCard(
              title: 'Órdenes asignadas',
              value: '0',
              gradientColors: [
                const Color(0xFF2193b0),
                const Color(0xFF6dd5ed),
              ], // Blue
              isDark: isDark,
            ),
            _buildMetricCard(
              title: 'Incidencias',
              value: '0',
              gradientColors: [
                const Color(0xFF833ab4),
                const Color(0xFFfd1d1d),
              ], // Pink/Red
              isDark: isDark,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${_greeting()}, ',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w400,
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
              ),
            ),
            Text(
              _displayName(u),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
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

    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

  void _navigateToRoute(String route) {
    Navigator.of(context, rootNavigator: true).pushNamed(route);
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
                            ('Grading', '/amazon/grading'),
                            ('Sorting', '/amazon/sorting'),
                            ('Quality Check', '/amazon/quality'),
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
                            (
                              'Herramientas · Cerrar Box',
                              '/amazon/herramientas/closebox',
                            ),
                            (
                              'Herramientas · Buscar Box',
                              '/amazon/herramientas/findbox',
                            ),
                            (
                              'Herramientas · Buscar DSN',
                              '/amazon/herramientas/finddsn',
                            ),
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
                            ('Registro · Pulsera', '/igualdad/registro/pulsera'),
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
                            ('Cerrar CESB', '/xiaomi/cerrar_cesb'),
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
                    leading: Icon(Icons.people_alt_rounded, color: Colors.white),
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
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
      ),
      child: ExpansionTile(
        leading: Icon(icon, color: Colors.white70),
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white70,
        textColor: Colors.white,
        collapsedTextColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        children: routes
            .map(
              (entry) => _sheetRouteTile(entry.$1, entry.$2, leftPad: 28),
            )
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobileRoot = MediaQuery.of(context).size.width < 900;
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
          // Animated, interactive AI Sphere in bottom-right
          _AispherePosition(bottomInset: isMobileRoot ? 106 : 20),
        ],
      ),
    );
  }
}

// Small widget that shows the animated AI sphere in the bottom-right.
// It plays the provided Lottie animation and reacts to mouse hover by growing
// slightly and adding a glow.
class _AispherePosition extends StatelessWidget {
  final double bottomInset;

  const _AispherePosition({this.bottomInset = 20});

  @override
  Widget build(BuildContext context) {
    // Provide a finite sized container so the inner Stack in _Aisphere has
    // bounded constraints (it needs finite width/height to layout the chat
    // panel above the sphere). The size covers the chat panel + sphere.
    return Positioned(
      right: 20,
      bottom: bottomInset,
      // make the wrapper compact so the sphere is clearly visible at
      // bottom-right; the ChatPanel will still position itself above the
      // sphere using the internal Stack.
      child: SizedBox(width: 120, height: 120, child: _Aisphere()),
    );
  }
}

class _Aisphere extends StatefulWidget {
  const _Aisphere();

  @override
  State<_Aisphere> createState() => _AisphereState();
}

class _AisphereState extends State<_Aisphere> {
  bool _hover = false;
  bool _chatOpen = false;
  final GlobalKey<_ChatPanelState> _panelKey = GlobalKey<_ChatPanelState>();

  void _setHover(bool v) {
    // Schedule hover state changes after the current frame to avoid
    // mutating widget tree during layout/device updates which can cause
    // assertions like '!_debugDoingThisLayout' or mouse tracker errors.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _hover = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    // size adjusts with hover (kept intentionally small)
    final size = _hover ? 72.0 : 56.0;

    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      cursor: SystemMouseCursors.click,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_chatOpen)
            Positioned(
              right: 0,
              bottom: 72.0,
              child: ChatPanel(
                key: _panelKey,
                onClose: () => setState(() => _chatOpen = false),
              ),
            ),

          // Only the sphere itself is gesture-aware now. The ChatPanel is a
          // sibling so clicks inside it won't toggle the sphere or steal focus.
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTapDown: (_) => _setHover(true),
              onTapUp: (_) => _setHover(false),
              onTapCancel: () => _setHover(false),
              onTap: () => WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final newOpen = !_chatOpen;
                setState(() => _chatOpen = newOpen);
                if (newOpen) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _panelKey.currentState?.requestFocus();
                  });
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.blue.shade700.withAlpha(220),
                      Colors.black.withAlpha(10),
                    ],
                    center: const Alignment(-0.4, -0.6),
                    radius: 0.9,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blueAccent.withAlpha(_hover ? 80 : 40),
                      blurRadius: _hover ? 10 : 4,
                      spreadRadius: _hover ? 1 : 0,
                    ),
                  ],
                ),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: _hover ? 1.06 : 1.0,
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: ClipOval(
                      child: Material(
                        color: Colors.transparent,
                        child: SizedBox.expand(
                          child: Center(
                            child: LottieBuilder.asset(
                              'lib/assets/AI Sphere.json',
                              fit: BoxFit.contain,
                              repeat: true,
                              animate: true,
                            ),
                          ),
                        ),
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

class ChatPanel extends StatefulWidget {
  final VoidCallback? onClose;
  const ChatPanel({super.key, this.onClose});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final List<Map<String, String>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;
  http.Client? _httpClient;
  StreamSubscription<String>? _streamSub;
  bool _aborted = false;

  // Called by parent to move keyboard focus into the input field.
  void requestFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _sending = true;
      _controller.clear();
    });
    // schedule scrolling after this frame to avoid changing layout during
    // the current frame which can trigger rendering assertions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        try {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent + 120,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        } catch (_) {}
      }
    });

    try {
      // Use centralized backend base URL so the app respects `kBackendBaseUrl`.
      final uri = Uri.parse('$kBackendBaseUrl/ask');
      // Prepare client/request to read streamed SSE (server-sent events)
      _httpClient = http.Client();
      final req = http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json'
        ..body = json.encode({'prompt': text});

      // Add an empty assistant entry that we'll fill progressively
      int assistantIndex = -1;
      setState(() {
        _messages.add({'role': 'assistant', 'text': ''});
        assistantIndex = _messages.length - 1;
      });

      final streamed = await _httpClient!
          .send(req)
          .timeout(const Duration(seconds: 20));
      if (streamed.statusCode != 200) {
        final body = await streamed.stream.bytesToString();
        setState(() {
          _messages[assistantIndex]['text'] =
              'Error ${streamed.statusCode}: $body';
          _sending = false;
        });
        return;
      }

      // Listen to the byte stream, decode UTF8 and parse SSE events separated by "\n\n"
      final decoder = streamed.stream.transform(utf8.decoder);
      String buffer = '';
      _aborted = false;
      _streamSub = decoder.listen(
        (chunk) {
          if (_aborted) return;
          buffer += chunk;
          // Extract complete events separated by double-newline
          while (true) {
            final idx = buffer.indexOf('\n\n');
            if (idx < 0) break;
            final event = buffer.substring(0, idx);
            buffer = buffer.substring(idx + 2);
            // Each event may have multiple lines. We only process lines that start with 'data:'
            for (final line in event.split('\n')) {
              if (line.trim().isEmpty) continue;
              if (line.startsWith('data:')) {
                var chunkText = line.substring(5).trim();
                // Server may escape newlines as literal '\\n' — unescape those
                chunkText = chunkText.replaceAll('\\n', '\n');
                // Handle [DONE] sentinel
                if (chunkText.trim() == '[DONE]') {
                  continue;
                }
                // Append chunk to assistant message
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final prev = _messages[assistantIndex]['text'] ?? '';
                  _messages[assistantIndex]['text'] = prev + chunkText;
                  // keep UI responsive by updating state
                  setState(() {});
                  // auto-scroll
                  if (_scroll.hasClients) {
                    try {
                      _scroll.animateTo(
                        _scroll.position.maxScrollExtent + 120,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                      );
                    } catch (_) {}
                  }
                });
              }
            }
          }
        },
        onDone: () async {
          // If there's leftover buffer with a final event, process it quickly
          if (buffer.isNotEmpty && !_aborted) {
            for (final line in buffer.split('\n')) {
              if (line.startsWith('data:')) {
                var chunkText = line.substring(5).trim();
                chunkText = chunkText.replaceAll('\\n', '\n');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final prev = _messages[assistantIndex]['text'] ?? '';
                  _messages[assistantIndex]['text'] = prev + chunkText;
                  setState(() {});
                });
              }
            }
          }
          _httpClient?.close();
          _httpClient = null;
          _streamSub = null;
          if (!mounted) return;
          setState(() {
            _sending = false;
          });
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _messages.add({'role': 'assistant', 'text': 'Stream error: $e'});
            _sending = false;
          });
        },
        cancelOnError: true,
      );
    } catch (e) {
      setState(() {
        _messages.add({'role': 'assistant', 'text': 'Network error: $e'});
        _sending = false;
      });
    } finally {
      // final state is set in onDone/onError of the stream; but ensure flag is clear if something left it on
      if (mounted) setState(() => _sending = false);
    }
    // after assistant reply, schedule scroll-to-bottom after the frame completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        try {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent + 120,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    _streamSub?.cancel();
    _httpClient?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 360,
        height: 480,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Header with Sentinel name and close
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 10.0,
              ),
              child: Row(
                children: [
                  const CircleAvatar(child: Text('S')),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Sentinel',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Messages list
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: _messages.length,
                  itemBuilder: (ctx, i) {
                    final m = _messages[i];
                    final isUser = m['role'] == 'user';
                    final bubbleColor = isUser
                        ? theme.colorScheme.primary
                        : theme.dividerColor.withAlpha(30);
                    final textColor = isUser
                        ? Colors.white
                        : theme.textTheme.bodyMedium?.color ?? Colors.black87;
                    return Align(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 240),
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 4,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 14,
                          ),
                          decoration: BoxDecoration(
                            color: bubbleColor,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isUser ? 16 : 4),
                              bottomRight: Radius.circular(isUser ? 4 : 16),
                            ),
                          ),
                          child: Text(
                            m['text'] ?? '',
                            style: TextStyle(color: textColor),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const Divider(height: 1),

            // Input row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            theme.inputDecorationTheme.fillColor ??
                            theme.cardColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Focus(
                              onKey: (node, event) {
                                // Send on Enter, allow Shift+Enter to insert newline
                                if (event is RawKeyDownEvent &&
                                    event.logicalKey ==
                                        LogicalKeyboardKey.enter) {
                                  final isShift = event.isShiftPressed;
                                  if (!isShift) {
                                    _send();
                                    return KeyEventResult.handled;
                                  } else {
                                    // Insert newline at cursor
                                    final sel = _controller.selection;
                                    final textBefore = _controller.text
                                        .substring(0, sel.start);
                                    final textAfter = _controller.text
                                        .substring(sel.end);
                                    final newText = '$textBefore\n$textAfter';
                                    final newPos = ('$textBefore\n').length;
                                    _controller.text = newText;
                                    _controller.selection =
                                        TextSelection.collapsed(offset: newPos);
                                    return KeyEventResult.handled;
                                  }
                                }
                                return KeyEventResult.ignored;
                              },
                              child: TextField(
                                focusNode: _focus,
                                controller: _controller,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'Message',
                                ),
                                minLines: 1,
                                maxLines: 4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _sending
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : GestureDetector(
                          onTap: _send,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// _DashboardTile removed — widgets area now uses a draggable, persistent WidgetGrid.
