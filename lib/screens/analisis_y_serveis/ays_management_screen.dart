import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../services/api_service.dart';
import '../../services/analisis_service.dart';
import '../../models/analisis_models.dart';
import '../../widgets/main_sidebar.dart';
import 'project_transactions_dialog.dart';
import 'create_project_fund_dialog.dart';
import 'ays_filtered_data_screen.dart';
import '../../utils/formatters.dart';

class AysManagementScreen extends StatefulWidget {
  static const routeName = '/analisis/management';
  const AysManagementScreen({super.key});

  @override
  State<AysManagementScreen> createState() => _AysManagementScreenState();
}

class _AysManagementScreenState extends State<AysManagementScreen> {
  final _analisisService = const AnalisisService();
  OverlayEntry? _edgeOverlay;

  // Data
  List<ProjectFund> _funds = [];
  List<Transaction> _history = [];
  List<MasterService> _masterServices = [];
  final _masterServicesNotifier = ValueNotifier<List<MasterService>>([]);
  List<String> _manufacturers = [];
  bool _loading = true;

  // Reordering & Widget State
  List<String> _widgetOrder = [
    'kpis',
    'trend',
    'manufacturers',
    'services',
    'clients',
    'funds',
    'master_list',
    'efficiency',
  ];

  // Analytics Filters
  DateTime? _filterDateStart;
  DateTime? _filterDateEnd;
  String? _filterManufacturer;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _setupSidebar();
  }

  void _setupSidebar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final isMobile = MediaQuery.of(context).size.width < 980;
      if (isMobile) return;
      final overlay = Overlay.of(context, rootOverlay: true);
      _edgeOverlay = OverlayEntry(
        builder: (ctx) => Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: SafeArea(
            child: Align(
              alignment: Alignment.centerLeft,
              child: EdgeNavHandle(
                user: Provider.of<ApiService>(ctx, listen: false).currentUser,
                width: 32,
                currentRoute: AysManagementScreen.routeName,
                showIndicator: true,
              ),
            ),
          ),
        ),
      );
      overlay.insert(_edgeOverlay!);
    });
  }

  Future<void> _loadAllData({bool showLoader = true}) async {
    if (showLoader) {
      setState(() => _loading = true);
    }
    try {
      final results = await Future.wait([
        _analisisService.getFunds(),
        _analisisService.getClosedTransactions(),
        _analisisService.getMasterServicios(),
        _analisisService.getFabricantes(),
      ]);

      if (mounted) {
        setState(() {
          _funds = results[0] as List<ProjectFund>;
          _history = results[1] as List<Transaction>;
          _masterServices = results[2] as List<MasterService>;
          _masterServicesNotifier.value = _masterServices;
          _manufacturers = results[3] as List<String>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Budget Analysis Helpers
  Map<String, double> get _manufacturerBudgets {
    final Map<String, double> budgets = {};
    for (var f in _funds) {
      final m = f.idxiaomi ?? 'Varios';
      budgets[m] = (budgets[m] ?? 0) + (f.fondos ?? 0.0);
    }
    return budgets;
  }

  Map<String, double> get _manufacturerDebt {
    final Map<String, double> debt = {};
    for (var t in _history) {
      if (t.paid != true) {
        final m = t.fabricante ?? 'Otros';
        debt[m] = (debt[m] ?? 0) + (t.cost ?? 0.0);
      }
    }
    return debt;
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    String clean = s.trim().replaceAll(',', '');
    clean = clean
        .replaceAll('AM', ' AM')
        .replaceAll('PM', ' PM')
        .replaceAll('  ', ' ');
    final iso = DateTime.tryParse(clean);
    if (iso != null) return iso;
    final formats = [
      'MMM d yyyy h:mm a',
      'MMMM d yyyy h:mm a',
      'd/M/yyyy',
      'dd/MM/yyyy',
      'MMM d yyyy HH:mm',
      'yyyy-MM-dd',
      'yyyy-MM-dd HH:mm:ss',
    ];
    for (final format in formats) {
      try {
        return DateFormat(format, 'en_US').parse(clean);
      } catch (_) {
        try {
          return DateFormat(format, 'es_ES').parse(clean);
        } catch (_) {}
      }
    }
    return null;
  }

  String _formatDate(String? s) {
    if (s == null || s.isEmpty || s == 'N/A' || s == '-') return '';
    final d = _parseDate(s);
    if (d == null) return s!;
    if (d.hour == 0 && d.minute == 0) {
      return DateFormat('dd/MM/yyyy').format(d);
    }
    return DateFormat('dd/MM/yyyy HH:mm').format(d);
  }

  @override
  void dispose() {
    _edgeOverlay?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _funds.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 980;
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // Glassmorphic Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: theme.brightness == Brightness.dark
                    ? [
                        const Color(
                          0xFF1B5E20,
                        ).withOpacity(0.08), // Forest Green
                        const Color(0xFF2E7D32).withOpacity(0.05), // Emerald
                        theme.scaffoldBackgroundColor,
                      ]
                    : [
                        const Color(0xFFE8F5E9), // Very light mint
                        const Color(0xFFF1F8E9), // Very light lime/moss
                        const Color(0xFFF8F9FA),
                      ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildHeader(theme, isMobile: isMobile),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 900;
                      return ReorderableListView(
                        padding: EdgeInsets.fromLTRB(
                          isWide ? 24 : 12,
                          isWide ? 24 : 10,
                          isWide ? 24 : 12,
                          isWide ? 120 : 140,
                        ),
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = _widgetOrder.removeAt(oldIndex);
                            _widgetOrder.insert(newIndex, item);
                          });
                        },
                        children: _buildBentoItems(isWide, theme),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: isMobile ? 84 : 0),
        child: _buildFab(isMobile: isMobile),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, {required bool isMobile}) {
    if (isMobile) {
      return Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AYS Management Dashboard',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.4,
                        ),
                      ),
                      Text(
                        'Gestión consolidada y analítica avanzada',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildViewDataAction(theme, isMobile: true),
                _buildExportAction(theme, isMobile: true),
                _buildGlobalFilterAction(theme),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AYS Management Dashboard',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'Gestión consolidada y analítica avanzada',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          _buildViewDataAction(theme, isMobile: false),
          const SizedBox(width: 8),
          _buildExportAction(theme, isMobile: false),
          const SizedBox(width: 8),
          _buildGlobalFilterAction(theme),
        ],
      ),
    );
  }

  Widget _buildViewDataAction(ThemeData theme, {required bool isMobile}) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
      ),
      child: TextButton.icon(
        icon: const Icon(Icons.table_view_rounded, color: Colors.blue),
        label: Text(
          isMobile ? 'Datos' : 'Ver Datos',
          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
        ),
        onPressed: _showExportModal, // Both use same dialog now
      ),
    );
  }

  Widget _buildExportAction(ThemeData theme, {required bool isMobile}) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
      ),
      child: TextButton.icon(
        icon: const Icon(Icons.file_download_rounded, color: Colors.orange),
        label: Text(
          isMobile ? 'Excel' : 'Exportar',
          style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
        ),
        onPressed: _showExportModal,
      ),
    );
  }

  Widget _buildFab({required bool isMobile}) {
    if (isMobile) {
      return FloatingActionButton(
        onPressed: _showQuickActionMenu,
        child: const Icon(Icons.bolt_rounded),
      );
    }

    return FloatingActionButton.extended(
      onPressed: _showQuickActionMenu,
      label: const Text('Acciones'),
      icon: const Icon(Icons.bolt_rounded),
    );
  }

  Widget _buildGlobalFilterAction(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
      ),
      child: IconButton(
        icon: const Icon(Icons.tune_rounded),
        onPressed: _showFilterDialog,
        tooltip: 'Filtros Globales',
      ),
    );
  }

  void _showQuickActionMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(ctx).canvasColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_card_rounded, color: Colors.blue),
              title: const Text('Añadir Fondo (ID XIAOMI)'),
              onTap: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (_) => const CreateProjectFundDialog(),
                ).then((_) => _loadAllData());
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.build_circle_rounded,
                color: Colors.green,
              ),
              title: const Text('Añadir Servicio al Maestro'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddMasterServiceDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Refrescar Datos'),
              onTap: () {
                Navigator.pop(ctx);
                _loadAllData();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showExportModal() {
    showDialog(context: context, builder: (ctx) => const _FilterDataDialog());
  }

  List<Widget> _buildBentoItems(bool isWide, ThemeData theme) {
    final List<Widget> items = [];

    // Keys that should be grouped together if wide
    final distributionKeys = ['manufacturers', 'services', 'clients'];
    final detailKeys = ['funds', 'master_list', 'efficiency'];

    // We process the order but skip the ones we group
    final skipKeys = isWide ? {...distributionKeys, ...detailKeys} : <String>{};

    for (var key in _widgetOrder) {
      if (skipKeys.contains(key)) continue;

      items.add(
        Padding(
          key: ValueKey(key),
          padding: const EdgeInsets.only(bottom: 20),
          child: _buildDashboardWidget(key, isWide),
        ),
      );
    }

    if (isWide) {
      // Add Distributions as a single reorderable Row
      items.add(
        Padding(
          key: const ValueKey('distributions_row'),
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: distributionKeys.map((k) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: k == distributionKeys.last ? 0 : 20,
                  ),
                  child: _buildDashboardWidget(k, isWide),
                ),
              );
            }).toList(),
          ),
        ),
      );

      // Add Details as a single reorderable Row
      items.add(
        Padding(
          key: const ValueKey('details_row'),
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: detailKeys.map((k) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: k == detailKeys.last ? 0 : 20,
                  ),
                  child: _buildDashboardWidget(k, isWide),
                ),
              );
            }).toList(),
          ),
        ),
      );
    }

    return items;
  }

  Widget _buildDashboardWidget(String key, bool isWide) {
    switch (key) {
      case 'kpis':
        return _DashboardKpis(
          history: _history,
          filterManufacturer: _filterManufacturer,
          filterDateStart: _filterDateStart,
          filterDateEnd: _filterDateEnd,
          parseDate: _parseDate,
        );
      case 'trend':
        return _DashboardTrend(history: _history, parseDate: _parseDate);
      case 'manufacturers':
        return _DashboardDistribution(
          title: 'Gasto por Fabricante',
          data: _getManufacturerDistribution(),
          isWide: isWide,
        );
      case 'services':
        return _DashboardDistribution(
          title: 'Gasto por Servicio',
          data: _getServiceDistribution(),
          isWide: isWide,
        );
      case 'clients':
        return _DashboardDistribution(
          title: 'Gasto por Cliente',
          data: _getClientDistribution(),
          isWide: isWide,
        );
      case 'funds':
        return _DashboardFunds(
          funds: _funds,
          onRefresh: () => _loadAllData(showLoader: false),
        );
      case 'master_list':
        return ValueListenableBuilder<List<MasterService>>(
          valueListenable: _masterServicesNotifier,
          builder: (context, services, _) {
            return _DashboardMasterServices(
              services: services,
              masterServicesNotifier: _masterServicesNotifier,
              onRefresh: () => _loadAllData(showLoader: false),
            );
          },
        );
      case 'efficiency':
        return _DashboardEfficiency(
          budgets: _manufacturerBudgets,
          debt: _manufacturerDebt,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Map<String, double> _getManufacturerDistribution() {
    final Map<String, double> dist = {};
    for (var t in _history) {
      final m = t.fabricante ?? 'Otros';
      dist[m] = (dist[m] ?? 0) + (t.cost ?? 0.0);
    }
    return dist;
  }

  Map<String, double> _getServiceDistribution() {
    final Map<String, double> dist = {};
    for (var t in _history) {
      final s = t.servicio ?? 'Varios';
      dist[s] = (dist[s] ?? 0) + (t.cost ?? 0.0);
    }
    return dist;
  }

  Map<String, double> _getClientDistribution() {
    final Map<String, double> dist = {};
    for (var t in _history) {
      final c = t.cliente ?? 'General';
      dist[c] = (dist[c] ?? 0) + (t.cost ?? 0.0);
    }
    return dist;
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _DashboardFilterDialog(
        currentStart: _filterDateStart,
        currentEnd: _filterDateEnd,
        currentManufacturer: _filterManufacturer,
        manufacturers: _manufacturers,
        onApply: (start, end, m) {
          setState(() {
            _filterDateStart = start;
            _filterDateEnd = end;
            _filterManufacturer = m;
          });
        },
      ),
    );
  }

  Future<void> _showAddMasterServiceDialog() async {
    final nameController = TextEditingController();
    final pvdController = TextEditingController();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E26) : Colors.white,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: const Color(0xFF2E7D32).withOpacity(0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2E7D32).withOpacity(0.15),
                  blurRadius: 30,
                  spreadRadius: -5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.add_task_rounded,
                      color: Color(0xFF2E7D32),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Nuevo Servicio',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Nombre del Servicio',
                    prefixIcon: const Icon(Icons.label_rounded, size: 20),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withOpacity(0.03)
                        : Colors.black.withOpacity(0.02),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pvdController,
                  decoration: InputDecoration(
                    labelText: 'Precio PVD',
                    suffixText: '€',
                    prefixIcon: const Icon(Icons.euro_rounded, size: 20),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withOpacity(0.03)
                        : Colors.black.withOpacity(0.02),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text(
                          'Crear Servicio',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      try {
        final pvd = double.tryParse(pvdController.text);
        await _analisisService.createMasterServicio(nameController.text, pvd);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Servicio añadido correctamente')),
          );
          _loadAllData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }
}

// --- Dashboard Widgets ---

class _DashboardKpis extends StatelessWidget {
  final List<Transaction> history;
  final String? filterManufacturer;
  final DateTime? filterDateStart;
  final DateTime? filterDateEnd;
  final DateTime? Function(String?) parseDate;

  const _DashboardKpis({
    required this.history,
    this.filterManufacturer,
    this.filterDateStart,
    this.filterDateEnd,
    required this.parseDate,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = history.where((t) {
      if (filterManufacturer != null && t.fabricante != filterManufacturer) {
        return false;
      }
      if (filterDateStart != null || filterDateEnd != null) {
        final d = parseDate(t.fechaf ?? t.fechai);
        if (d == null) return false;
        if (filterDateStart != null && d.isBefore(filterDateStart!)) {
          return false;
        }
        if (filterDateEnd != null && d.isAfter(filterDateEnd!)) return false;
      }
      return true;
    }).toList();

    double total = 0;
    double paid = 0;
    for (var t in filtered) {
      total += (t.cost ?? 0);
      if (t.paid == true) paid += (t.cost ?? 0);
    }

    double previousTotal = 0;
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1);

    for (var t in history) {
      final d = parseDate(t.fechai);
      if (d == null) continue;

      // Filter logic matches DashboardKpis logic for consistency
      bool matchesFilter = true;
      if (filterManufacturer != null && t.fabricante != filterManufacturer) {
        matchesFilter = false;
      }
      if (filterDateStart != null && d.isBefore(filterDateStart!)) {
        matchesFilter = false;
      }
      if (filterDateEnd != null && d.isAfter(filterDateEnd!)) {
        matchesFilter = false;
      }

      if (matchesFilter) {
        // We already calculated Current Month 'total' above in the loop,
        // but here we specifically need MoM comparison.
        if (d.year == lastMonth.year && d.month == lastMonth.month) {
          previousTotal += (t.cost ?? 0);
        }
      }
    }

    double mom = 0;
    if (previousTotal > 0) {
      mom = ((total - previousTotal) / previousTotal) * 100;
    }

    final cards = [
      _KpiCard(
        title: 'Gasto Total',
        value: total.asCurrency,
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFF2E7D32),
      ),
      _KpiCard(
        title: 'Tendencia MoM',
        value: '${mom > 0 ? "+" : ""}${mom.formatted}%',
        icon: mom > 0
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded,
        color: mom > 10 ? Colors.red : (mom < 0 ? Colors.blue : Colors.orange),
        subtitle: 'Vs mes anterior',
      ),
      _KpiCard(
        title: 'Pendiente',
        value: (total - paid).asCurrency,
        icon: Icons.pending_actions_rounded,
        color: Colors.orange,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 760;
        if (isCompact) {
          return Column(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i < cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 16),
            Expanded(child: cards[1]),
            const SizedBox(width: 16),
            Expanded(child: cards[2]),
          ],
        );
      },
    );
  }
}

class _DashboardTrend extends StatelessWidget {
  final List<Transaction> history;
  final DateTime? Function(String?) parseDate;

  const _DashboardTrend({required this.history, required this.parseDate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Map<DateTime, double> monthly = {};
    for (var t in history) {
      final date = parseDate(t.fechai);
      if (date != null) {
        final key = DateTime(date.year, date.month);
        monthly[key] = (monthly[key] ?? 0) + (t.cost ?? 0);
      }
    }

    final sortedEntries = monthly.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // Map DateTime to a sequence for the chart X axis
    final spots = sortedEntries.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.value);
    }).toList();

    return _ChartContainer(
      title: 'Tendencia Mensual de Gastos',
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => theme.cardColor.withOpacity(0.8),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${spot.y.asCurrency}',
                    TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: theme.dividerColor.withOpacity(0.05),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (val, _) {
                  int idx = val.toInt();
                  if (idx < 0 || idx >= sortedEntries.length) {
                    return const SizedBox.shrink();
                  }
                  final date = sortedEntries[idx].key;
                  final months = [
                    '',
                    'Ene',
                    'Feb',
                    'Mar',
                    'Abr',
                    'May',
                    'Jun',
                    'Jul',
                    'Ago',
                    'Sep',
                    'Oct',
                    'Nov',
                    'Dic',
                  ];
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      '${months[date.month]}\n${date.year.toString().substring(2)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        color: theme.hintColor,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.4,
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF43A047),
                  Color(0xFF2E7D32),
                ], // Emerald/Forest Green
              ),
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(
                      radius: 4,
                      color: Colors.white,
                      strokeWidth: 2,
                      strokeColor: const Color(0xFF43A047),
                    ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF43A047).withOpacity(0.2),
                    const Color(0xFF43A047).withOpacity(0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardDistribution extends StatelessWidget {
  final String title;
  final Map<String, double> data;
  final bool isWide;

  const _DashboardDistribution({
    required this.title,
    required this.data,
    required this.isWide,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final colors = [
      const Color(0xFF43A047), // Emerald
      const Color(0xFF651FFF), // Deep Purple
      const Color(0xFFFBC02D), // Amber (Professional Yellow)
      const Color(0xFFFF9100), // Orange
      const Color(0xFFF50057), // Pink
    ];

    return _ChartContainer(
      title: title,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          final chart = PieChart(
            PieChartData(
              sectionsSpace: 4,
              centerSpaceRadius: isWide ? 40 : 50,
              sections: top.asMap().entries.map((e) {
                return PieChartSectionData(
                  value: e.value.value,
                  title: '',
                  radius: isWide ? 25 : 30,
                  color: colors[e.key % colors.length],
                  badgeWidget: null,
                );
              }).toList(),
            ),
          );

          final legend = ListView(
            padding: EdgeInsets.zero,
            children: top.asMap().entries.map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors[e.key % colors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.value.key,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      e.value.value.asCurrency,
                      style: TextStyle(fontSize: 10, color: theme.hintColor),
                    ),
                  ],
                ),
              );
            }).toList(),
          );

          if (compact) {
            return Column(
              children: [
                Expanded(child: chart),
                const SizedBox(height: 10),
                Expanded(child: legend),
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 3, child: chart),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: legend),
            ],
          );
        },
      ),
    );
  }
}

class _DashboardFunds extends StatelessWidget {
  final List<ProjectFund> funds;
  final VoidCallback onRefresh;

  const _DashboardFunds({required this.funds, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return _BentoCard(
      title: 'Control de Fondos',
      icon: Icons.account_balance_rounded,
      action: TextButton(
        onPressed: () => _showAllFundsDialog(context),
        child: const Text('Ver todo'),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: funds.length.clamp(0, 3), // Show top 3 in dashboard
        itemBuilder: (ctx, i) {
          final f = funds[i];
          final percent = (f.totalSpent / (f.fondos ?? 1.0)).clamp(0.0, 1.0);
          return ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) =>
                    ProjectTransactionsDialog(idxiaomi: f.idxiaomi ?? 'Varios'),
              ).then((_) => onRefresh());
            },
            title: Text(f.idxiaomi ?? 'Varios'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: percent,
                  backgroundColor: Colors.grey.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation(
                    percent > 0.9 ? Colors.red : Colors.blue,
                  ),
                ),
              ],
            ),
            trailing: Text(
              f.fondos?.asCurrency ?? '-',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        },
      ),
    );
  }

  void _showAllFundsDialog(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 40,
          ),
          child: Container(
            width: 500,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E1E26).withOpacity(0.9)
                  : Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: const Color(0xFF2E7D32).withOpacity(0.1),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2E7D32).withOpacity(0.05),
                  blurRadius: 40,
                  spreadRadius: -10,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogHeader(
                  ctx,
                  'Fondos Activos (ID XIAOMI)',
                  Icons.account_balance_wallet_rounded,
                ),
                Flexible(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(24),
                    shrinkWrap: true,
                    itemCount: funds.length,
                    itemBuilder: (ctx, i) {
                      final f = funds[i];
                      final percent = (f.totalSpent / (f.fondos ?? 1.0)).clamp(
                        0.0,
                        1.0,
                      );
                      return _buildDialogRow(
                        context: ctx,
                        title: f.idxiaomi ?? 'Varios',
                        subtitle:
                            '${f.totalSpent.formattedInt}€ gastados de ${f.fondos?.formattedInt}€',
                        trailing: '${f.fondos?.formattedInt}€',
                        percent: percent,
                        onTap: () {
                          Navigator.pop(ctx);
                          showDialog(
                            context: context,
                            builder: (ctx) => ProjectTransactionsDialog(
                              idxiaomi: f.idxiaomi ?? 'Varios',
                            ),
                          ).then((_) => onRefresh());
                        },
                      );
                    },
                  ),
                ),
                _buildDialogFooter(ctx),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardMasterServices extends StatelessWidget {
  final List<MasterService> services;
  final ValueNotifier<List<MasterService>> masterServicesNotifier;
  final VoidCallback onRefresh;

  const _DashboardMasterServices({
    required this.services,
    required this.masterServicesNotifier,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return _BentoCard(
      title: 'Servicios Maestros',
      icon: Icons.list_alt_rounded,
      action: TextButton(
        onPressed: () => _showAllServicesDialog(context),
        child: const Text('Ver todo'),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: services.length.clamp(0, 5),
        itemBuilder: (ctx, i) {
          final s = services[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.03)
                  : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text(
                s.servicio,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'PVD: ${s.pvd?.formatted ?? "0,00"}€',
                style: const TextStyle(color: Color(0xFF43A047)),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    onPressed: () => _showEditPriceDialog(context, s),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: Colors.redAccent,
                    ),
                    onPressed: () => _showDeleteConfirm(context, s),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAllServicesDialog(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 40,
          ),
          child: Container(
            width: 500,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E1E26).withOpacity(0.9)
                  : Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: const Color(0xFF43A047).withOpacity(0.1),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2E7D32).withOpacity(0.05),
                  blurRadius: 40,
                  spreadRadius: -10,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogHeader(
                  ctx,
                  'Catálogo de Servicios',
                  Icons.list_alt_rounded,
                ),
                Flexible(
                  child: ValueListenableBuilder<List<MasterService>>(
                    valueListenable: masterServicesNotifier,
                    builder: (context, latestServices, _) {
                      return ListView.builder(
                        padding: const EdgeInsets.all(24),
                        shrinkWrap: true,
                        itemCount: latestServices.length,
                        itemBuilder: (ctx, i) {
                          final s = latestServices[i];
                          return _buildDialogRow(
                            context: ctx,
                            title: s.servicio,
                            subtitle:
                                'Precio actual: ${s.pvd?.formatted ?? "0,00"}€',
                            trailingWidget: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${s.pvd?.formatted ?? "0,00"}€',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF43A047),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                ),
                              ],
                            ),
                            onTap: () {
                              _showEditPriceDialog(context, s);
                            },
                            onLongPress: () {
                              _showDeleteConfirm(context, s);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                _buildDialogFooter(ctx),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditPriceDialog(BuildContext context, MasterService s) {
    final controller = TextEditingController(text: s.pvd?.toString() ?? '');
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E26) : Colors.white,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: const Color(0xFF43A047).withOpacity(0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2E7D32).withOpacity(0.15),
                  blurRadius: 30,
                  spreadRadius: -5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.edit_rounded,
                      color: const Color(0xFF43A047),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Editar Precio',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  s.servicio,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Precio PVD',
                    suffixText: '€',
                    prefixIcon: const Icon(Icons.euro_rounded, size: 20),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withOpacity(0.03)
                        : Colors.black.withOpacity(0.02),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: Color(0xFF43A047),
                        width: 1.5,
                      ),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF43A047),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () async {
                          // Allow both dot and comma as decimal separator
                          final cleanText =
                              controller.text.trim().replaceAll(',', '.');
                          final price = double.tryParse(cleanText);
                          if (price != null) {
                            try {
                              await const AnalisisService()
                                  .updateMasterServicioPrice(s.id, price);
                              onRefresh();
                              if (ctx.mounted) Navigator.pop(ctx);
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            }
                          } else {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Precio no válido'),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text(
                          'Actualizar',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, MasterService s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Servicio'),
        content: Text('¿Estás seguro de que deseas eliminar "${s.servicio}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await const AnalisisService().deleteMasterServicio(s.id);
              onRefresh();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

class _DashboardEfficiency extends StatelessWidget {
  final Map<String, double> budgets;
  final Map<String, double> debt;

  const _DashboardEfficiency({required this.budgets, required this.debt});

  @override
  Widget build(BuildContext context) {
    // Top Efficiency Insight: Consumption vs Debt
    return _BentoCard(
      title: 'Consumo de Presupuesto (Top 3)',
      icon: Icons.speed_rounded,
      child: Column(
        children: budgets.entries.take(3).map((e) {
          final total = e.value;
          final spent = debt[e.key] ?? 0;
          final pct = (spent / (total > 0 ? total : 1)).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(e.key, overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: 3,
                  child: LinearProgressIndicator(
                    value: pct,
                    color: spent > total ? Colors.red : Colors.teal,
                  ),
                ),
                const SizedBox(width: 8),
                Text('${(pct * 100).formattedInt}%'),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BentoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  const _BentoCard({
    required this.title,
    required this.icon,
    required this.child,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? theme.cardColor.withOpacity(0.5)
            : theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? theme.dividerColor.withOpacity(0.1)
              : theme.dividerColor.withOpacity(0.2),
        ),
        boxShadow: theme.brightness == Brightness.light
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 430;
              final titleRow = Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              );

              if (compact && action != null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleRow,
                    const SizedBox(height: 6),
                    Align(alignment: Alignment.centerRight, child: action!),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: titleRow),
                  if (action != null) action!,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _DashboardFilterDialog extends StatefulWidget {
  final DateTime? currentStart;
  final DateTime? currentEnd;
  final String? currentManufacturer;
  final List<String> manufacturers;
  final Function(DateTime?, DateTime?, String?) onApply;

  const _DashboardFilterDialog({
    this.currentStart,
    this.currentEnd,
    this.currentManufacturer,
    required this.manufacturers,
    required this.onApply,
  });

  @override
  State<_DashboardFilterDialog> createState() => _DashboardFilterDialogState();
}

class _DashboardFilterDialogState extends State<_DashboardFilterDialog> {
  DateTime? _start;
  DateTime? _end;
  String? _manufacturer;

  @override
  void initState() {
    super.initState();
    _start = widget.currentStart;
    _end = widget.currentEnd;
    _manufacturer = widget.currentManufacturer;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filtros del Dashboard'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _manufacturer,
            decoration: const InputDecoration(labelText: 'Fabricante'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todos')),
              ...widget.manufacturers.map(
                (m) => DropdownMenuItem(value: m, child: Text(m)),
              ),
            ],
            onChanged: (val) => setState(() => _manufacturer = val),
          ),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('Rango de Fechas'),
            subtitle: Text(
              _start == null
                  ? 'Sin filtro'
                  : '${DateFormat('dd/MM').format(_start!)} - ${_end == null ? '...' : DateFormat('dd/MM').format(_end!)}',
            ),
            onTap: () async {
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (range != null) {
                setState(() {
                  _start = range.start;
                  _end = range.end;
                });
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            widget.onApply(_start, _end, _manufacturer);
            Navigator.pop(context);
          },
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

class _ChartContainer extends StatelessWidget {
  final String title;
  final Widget child;

  const _ChartContainer({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 260, // Reduced height
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? theme.cardColor.withOpacity(0.5)
            : theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? theme.dividerColor.withOpacity(0.1)
              : theme.dividerColor.withOpacity(0.3),
        ),
        boxShadow: theme.brightness == Brightness.light
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E26) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(isDark ? 0.15 : 0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.2), color.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white60 : Colors.black54,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                    letterSpacing: -1,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 10,
                      color: color.withOpacity(0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Premium Dialog Helpers ---

Widget _buildDialogHeader(BuildContext context, String title, IconData icon) {
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF43A047), size: 28),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
          style: IconButton.styleFrom(
            backgroundColor: theme.brightness == Brightness.dark
                ? Colors.white.withOpacity(0.03)
                : Colors.black.withOpacity(0.02),
          ),
        ),
      ],
    ),
  );
}

Widget _buildDialogFooter(BuildContext context) {
  return Container(
    padding: const EdgeInsets.all(28),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cerrar Ventana',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

Widget _buildDialogRow({
  required BuildContext context,
  required String title,
  required String subtitle,
  String? trailing,
  Widget? trailingWidget,
  required VoidCallback onTap,
  VoidCallback? onLongPress,
  double? percent,
  IconData? icon,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: isDark
          ? Colors.white.withOpacity(0.03)
          : Colors.black.withOpacity(0.02),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isDark
            ? Colors.white.withOpacity(0.02)
            : Colors.black.withOpacity(0.02),
      ),
    ),
    child: ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
          ),
          if (percent != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 4,
                backgroundColor: Colors.grey.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation(
                  percent > 0.9 ? Colors.redAccent : const Color(0xFF43A047),
                ),
              ),
            ),
          ],
        ],
      ),
      trailing:
          trailingWidget ??
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color:
                  (icon != null
                          ? const Color(0xFF43A047)
                          : const Color(0xFF2E7D32))
                      .withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: icon != null
                ? Icon(icon, size: 16, color: const Color(0xFF43A047))
                : Text(
                    trailing ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF43A047),
                      fontSize: 12,
                    ),
                  ),
          ),
    ),
  );
}

class _FilterDataDialog extends StatefulWidget {
  const _FilterDataDialog({Key? key}) : super(key: key);

  @override
  State<_FilterDataDialog> createState() => _FilterDataDialogState();
}

class _FilterDataDialogState extends State<_FilterDataDialog> {
  String _exportType = 'current_month';

  final List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  late String _selectedMonth;
  late String _selectedYear;

  DateTime? _startDate;
  DateTime? _endDate;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateFormat('MMM', 'en_US').format(now);
    _selectedYear = DateFormat('yyyy').format(now);
  }

  Future<void> _viewInApp() async {
    setState(() => _isLoading = true);
    try {
      final filters = _getFilters();
      final data = await const AnalisisService().getTransactionsByDate(
        monthStr: filters['month'],
        yearStr: filters['year'],
        startDate: filters['start'],
        endDate: filters['end'],
      );

      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (_) => AysFilteredDataDialog(
            transactions: data,
            title: _getDisplayTitle(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar datos: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportData() async {
    setState(() => _isLoading = true);

    try {
      String? savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Please select an output file:',
        fileName: 'AyS_Data_Export.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (savePath == null) {
        setState(() => _isLoading = false);
        return;
      }

      final filters = _getFilters();
      final bytes = await const AnalisisService().exportTransactionsExcel(
        monthStr: filters['month'],
        yearStr: filters['year'],
        startDate: filters['start'],
        endDate: filters['end'],
      );

      final file = File(savePath);
      await file.writeAsBytes(bytes, flush: true);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exportación completada exitosamente.')),
        );
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Error al exportar: $e';
        if (e.toString().contains('Permission denied')) {
          msg = 'Error de permisos: No se pudo escribir el archivo en esa ubicación.';
        } else if (e.toString().contains('AnalisisService')) {
          msg = 'Error del servidor: No se pudo obtener el archivo Excel.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, String?> _getFilters() {
    String? qMonth;
    String? qYear;
    String? qStart;
    String? qEnd;

    if (_exportType == 'current_month') {
      final now = DateTime.now();
      qMonth = DateFormat('MMM', 'en_US').format(now);
      qYear = DateFormat('yyyy').format(now);
    } else if (_exportType == 'specific_month') {
      qMonth = _selectedMonth;
      qYear = _selectedYear;
    } else if (_exportType == 'date_range') {
      if (_startDate != null && _endDate != null) {
        qStart = DateFormat('yyyy-MM-dd').format(_startDate!);
        qEnd = DateFormat('yyyy-MM-dd').format(_endDate!);
      }
    }
    return {'month': qMonth, 'year': qYear, 'start': qStart, 'end': qEnd};
  }

  String _getDisplayTitle() {
    if (_exportType == 'current_month') return 'Mes Actual';
    if (_exportType == 'specific_month')
      return '$_selectedMonth $_selectedYear';
    if (_exportType == 'date_range' && _startDate != null && _endDate != null) {
      return '${DateFormat('dd/MM').format(_startDate!)} - ${DateFormat('dd/MM').format(_endDate!)}';
    }
    return 'Datos Filtrados';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Procesando solicitud...'),
          ],
        ),
      );
    }
    final years = List.generate(
      10,
      (i) => (DateTime.now().year - 5 + i).toString(),
    );

    return AlertDialog(
      title: const Text('Filtro FECHAF'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Mes Actual'),
              leading: Radio<String>(
                value: 'current_month',
                groupValue: _exportType,
                onChanged: (v) => setState(() => _exportType = v!),
              ),
            ),
            ListTile(
              title: const Text('Mes Específico'),
              leading: Radio<String>(
                value: 'specific_month',
                groupValue: _exportType,
                onChanged: (v) => setState(() => _exportType = v!),
              ),
            ),
            if (_exportType == 'specific_month')
              Padding(
                padding: const EdgeInsets.only(left: 48.0, bottom: 8.0),
                child: Row(
                  children: [
                    DropdownButton<String>(
                      value: _selectedMonth,
                      items: _months
                          .map(
                            (m) => DropdownMenuItem(value: m, child: Text(m)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedMonth = v!),
                    ),
                    const SizedBox(width: 16),
                    DropdownButton<String>(
                      value: _selectedYear,
                      items: years
                          .map(
                            (y) => DropdownMenuItem(value: y, child: Text(y)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedYear = v!),
                    ),
                  ],
                ),
              ),
            ListTile(
              title: const Text('Rango de Fechas'),
              leading: Radio<String>(
                value: 'date_range',
                groupValue: _exportType,
                onChanged: (v) => setState(() => _exportType = v!),
              ),
            ),
            if (_exportType == 'date_range')
              Padding(
                padding: const EdgeInsets.only(left: 48.0, bottom: 8.0),
                child: Column(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        _startDate == null
                            ? 'Inicio'
                            : DateFormat('dd/MM/yyyy').format(_startDate!),
                      ),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _startDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (d != null) setState(() => _startDate = d);
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        _endDate == null
                            ? 'Fin'
                            : DateFormat('dd/MM/yyyy').format(_endDate!),
                      ),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _endDate ?? _startDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (d != null) setState(() => _endDate = d);
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: _viewInApp,
          icon: const Icon(Icons.table_view),
          label: const Text('Ver Datos'),
        ),
        ElevatedButton.icon(
          onPressed: _exportData,
          icon: const Icon(Icons.file_download),
          label: const Text('Excel'),
        ),
      ],
    );
  }
}
