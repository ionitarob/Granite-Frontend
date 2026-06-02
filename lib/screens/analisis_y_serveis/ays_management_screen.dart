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
  List<String> _widgetOrder = ['stats', 'funds', 'master_list'];

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
                      return ListView(
                        padding: EdgeInsets.fromLTRB(
                          isWide ? 24 : 12,
                          isWide ? 24 : 10,
                          isWide ? 24 : 12,
                          isWide ? 120 : 140,
                        ),
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
                        'Análisis y Servicios Dashboard',
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
                    'Análisis y Servicios Dashboard',
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
          style: const TextStyle(
            color: Colors.blue,
            fontWeight: FontWeight.bold,
          ),
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
          style: const TextStyle(
            color: Colors.orange,
            fontWeight: FontWeight.bold,
          ),
        ),
        onPressed: _showExportModal,
      ),
    );
  }

  void _showExportModal() {
    showDialog(context: context, builder: (ctx) => const _FilterDataDialog());
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

  List<Widget> _buildBentoItems(bool isWide, ThemeData theme) {
    final List<Widget> items = [];

    // Keys that should be grouped together if wide
    final detailKeys = ['master_list', 'funds', 'stats'];

    // We process the order but skip the ones we group
    final skipKeys = isWide ? {...detailKeys} : <String>{};

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
      items.add(
        Padding(
          key: const ValueKey('details_row'),
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _buildDashboardWidget('stats', isWide),
                    const SizedBox(height: 20),
                    _buildDashboardWidget('funds', isWide),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(child: _buildDashboardWidget('master_list', isWide)),
            ],
          ),
        ),
      );
    }

    return items;
  }

  Widget _buildDashboardWidget(String key, bool isWide) {
    switch (key) {
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
              onAddService: _showAddMasterServiceDialog,
            );
          },
        );
      case 'stats':
        return _DashboardServiceStats(
          history: _history,
          masterServices: _masterServices,
        );
      default:
        return const SizedBox.shrink();
    }
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
    final costController = TextEditingController();
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
                const SizedBox(height: 16),
                TextField(
                  controller: costController,
                  decoration: InputDecoration(
                    labelText: 'Costo del Servicio',
                    suffixText: '€',
                    prefixIcon: const Icon(Icons.money_off_rounded, size: 20),
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
        final cost = double.tryParse(costController.text);
        await _analisisService.createMasterServicio(
          nameController.text,
          pvd,
          cost,
        );
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

class _DashboardFunds extends StatefulWidget {
  final List<ProjectFund> funds;
  final VoidCallback onRefresh;

  const _DashboardFunds({required this.funds, required this.onRefresh});

  @override
  State<_DashboardFunds> createState() => _DashboardFundsState();
}

class _DashboardFundsState extends State<_DashboardFunds> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _BentoCard(
      title: 'Control ID XIAOMI',
      icon: Icons.account_balance_rounded,
      action: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.blue.withOpacity(0.15),
          foregroundColor: Colors.blue,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text(
          'Añadir ID Xiaomi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => const CreateProjectFundDialog(),
          ).then((_) => widget.onRefresh());
        },
      ),
      child: SizedBox(
        height: 200,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          child: ListView.builder(
            controller: _scrollController,
            shrinkWrap: false,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: widget.funds.length,
            itemBuilder: (ctx, i) {
              final f = widget.funds[i];
              final percent = (f.totalSpent / (f.fondos ?? 1.0)).clamp(
                0.0,
                1.0,
              );
              return Container(
                margin: const EdgeInsets.only(bottom: 8, right: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withOpacity(0.03)
                      : Colors.black.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => ProjectTransactionsDialog(
                        idxiaomi: f.idxiaomi ?? 'Varios',
                      ),
                    ).then((_) => widget.onRefresh());
                  },
                  title: Text(
                    f.idxiaomi ?? 'Varios',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
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
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DashboardMasterServices extends StatefulWidget {
  final List<MasterService> services;
  final ValueNotifier<List<MasterService>> masterServicesNotifier;
  final VoidCallback onRefresh;
  final VoidCallback? onAddService;

  const _DashboardMasterServices({
    required this.services,
    required this.masterServicesNotifier,
    required this.onRefresh,
    this.onAddService,
  });

  @override
  State<_DashboardMasterServices> createState() =>
      _DashboardMasterServicesState();
}

class _DashboardMasterServicesState extends State<_DashboardMasterServices> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _BentoCard(
      title: 'Servicios Configuraciones',
      icon: Icons.list_alt_rounded,
      action: widget.onAddService != null
          ? FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32).withOpacity(0.15),
                foregroundColor: const Color(0xFF2E7D32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text(
                'Añadir Servicio',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: widget.onAddService,
            )
          : null,
      child: SizedBox(
        height: 600,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          child: ListView.builder(
            controller: _scrollController,
            shrinkWrap: false,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: widget.services.length,
            itemBuilder: (ctx, i) {
              final s = widget.services[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 8, right: 12),
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
                  subtitle: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'PVD: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.grey,
                          ),
                        ),
                        TextSpan(
                          text: '${s.pvd?.formatted ?? "0,00"}€',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF43A047),
                          ),
                        ),
                        const TextSpan(
                          text: '  •  ',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const TextSpan(
                          text: 'Coste: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.grey,
                          ),
                        ),
                        TextSpan(
                          text: '${s.cost?.formatted ?? "0,00"}€',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFB8C00),
                          ),
                        ),
                      ],
                    ),
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
        ),
      ),
    );
  }

  void _showEditPriceDialog(BuildContext context, MasterService s) {
    final pvdController = TextEditingController(text: s.pvd?.toString() ?? '');
    final costController = TextEditingController(
      text: s.cost?.toString() ?? '',
    );
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
                      'Editar Tarifas',
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
                  controller: pvdController,
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
                const SizedBox(height: 16),
                TextField(
                  controller: costController,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Costo del Servicio',
                    suffixText: '€',
                    prefixIcon: const Icon(Icons.money_off_rounded, size: 20),
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
                          final cleanPvd = pvdController.text.trim().replaceAll(
                            ',',
                            '.',
                          );
                          final cleanCost = costController.text
                              .trim()
                              .replaceAll(',', '.');
                          final price = double.tryParse(cleanPvd);
                          final costVal = double.tryParse(cleanCost);
                          try {
                            await const AnalisisService().updateMasterServicio(
                              s.id,
                              pvd: price,
                              cost: costVal,
                            );
                            widget.onRefresh();
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
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
              widget.onRefresh();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

class ServiceStat {
  final String name;
  final double units;
  final double pvd;
  final double totalPrice;
  final double palets;

  ServiceStat({
    required this.name,
    required this.units,
    required this.pvd,
    required this.totalPrice,
    required this.palets,
  });
}

class _DashboardServiceStats extends StatefulWidget {
  final List<Transaction> history;
  final List<MasterService> masterServices;

  const _DashboardServiceStats({
    required this.history,
    required this.masterServices,
  });

  @override
  State<_DashboardServiceStats> createState() => _DashboardServiceStatsState();
}

class _DashboardServiceStatsState extends State<_DashboardServiceStats> {
  final ScrollController _scrollController = ScrollController();
  String _selectedPeriod = 'Semana';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

  double _parseUnits(String? s) {
    if (s == null || s.isEmpty) return 0.0;
    String clean = s.replaceAll(',', '.').trim();
    return double.tryParse(clean) ?? 0.0;
  }

  List<ServiceStat> _getServiceStats() {
    final now = DateTime.now();
    final filtered = widget.history.where((t) {
      final date = _parseDate(t.fechaf) ?? _parseDate(t.fechai);
      if (date == null) return false;

      final diff = now.difference(date);
      if (_selectedPeriod == 'Día') {
        return date.year == now.year &&
            date.month == now.month &&
            date.day == now.day;
      } else if (_selectedPeriod == 'Semana') {
        return diff.inDays <= 7;
      } else if (_selectedPeriod == 'Mes') {
        return diff.inDays <= 30;
      } else if (_selectedPeriod == 'Año') {
        return diff.inDays <= 365;
      }
      return true;
    }).toList();

    final Map<String, double> serviceUnits = {};
    final Map<String, double> servicePalets = {};
    for (final t in filtered) {
      final sName = t.servicio ?? 'Sin servicio';
      final units = _parseUnits(t.unit);
      final palets = _parseUnits(t.palets);
      serviceUnits[sName] = (serviceUnits[sName] ?? 0.0) + units;
      servicePalets[sName] = (servicePalets[sName] ?? 0.0) + palets;
    }

    final List<ServiceStat> stats = [];
    serviceUnits.forEach((name, units) {
      final master = widget.masterServices.firstWhere(
        (m) => m.servicio.trim().toLowerCase() == name.trim().toLowerCase(),
        orElse: () => MasterService(id: 0, servicio: name, pvd: 0.0),
      );
      final pvd = master.pvd ?? 0.0;
      final totalPrice = units * pvd;
      final palets = servicePalets[name] ?? 0.0;
      stats.add(
        ServiceStat(
          name: name,
          units: units,
          pvd: pvd,
          totalPrice: totalPrice,
          palets: palets,
        ),
      );
    });

    stats.sort((a, b) {
      final comp = b.units.compareTo(a.units);
      if (comp != 0) return comp;
      return b.totalPrice.compareTo(a.totalPrice);
    });

    return stats;
  }

  Widget _buildPeriodSelector() {
    final theme = Theme.of(context);
    final periods = ['Día', 'Semana', 'Mes', 'Año'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: periods.map((p) {
          final isSelected = _selectedPeriod == p;
          return Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedPeriod = p;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? theme.primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    p,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : theme.textTheme.bodyMedium?.color,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _getServiceStats();

    return _BentoCard(
      title: 'Servicios más usados',
      icon: Icons.analytics_rounded,
      child: SizedBox(
        height: 380,
        child: Column(
          children: [
            _buildPeriodSelector(),
            const SizedBox(height: 12),
            Expanded(
              child: stats.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay estadísticas para este período.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  : Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      child: ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(right: 8),
                        itemCount: stats.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 12),
                        itemBuilder: (context, index) {
                          final stat = stats[index];
                          return InkWell(
                            onTap: () {
                              final now = DateTime.now();
                              final serviceTx = widget.history.where((t) {
                                if (t.servicio?.trim().toLowerCase() !=
                                    stat.name.trim().toLowerCase()) {
                                  return false;
                                }
                                final date =
                                    _parseDate(t.fechaf) ??
                                    _parseDate(t.fechai);
                                if (date == null) return false;

                                final diff = now.difference(date);
                                if (_selectedPeriod == 'Día') {
                                  return date.year == now.year &&
                                      date.month == now.month &&
                                      date.day == now.day;
                                } else if (_selectedPeriod == 'Semana') {
                                  return diff.inDays <= 7;
                                } else if (_selectedPeriod == 'Mes') {
                                  return diff.inDays <= 30;
                                } else if (_selectedPeriod == 'Año') {
                                  return diff.inDays <= 365;
                                }
                                return true;
                              }).toList();

                              showDialog(
                                context: context,
                                builder: (_) => AysFilteredDataDialog(
                                  transactions: serviceTx,
                                  title:
                                      'Servicio: ${stat.name} ($_selectedPeriod)',
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 4,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: theme.primaryColor.withOpacity(
                                        0.1,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: theme.primaryColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          stat.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${stat.units.toStringAsFixed(0)} unds. x ${stat.pvd.formatted} € · ${stat.palets.formatted} palets',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: theme
                                                .textTheme
                                                .bodySmall
                                                ?.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${stat.totalPrice.formatted} €',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: theme.primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
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
                    child: Icon(
                      icon,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
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
          msg =
              'Error de permisos: No se pudo escribir el archivo en esa ubicación.';
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
