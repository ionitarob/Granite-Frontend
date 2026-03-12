import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:ui'; // For ImageFilter
import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';

import '../../services/analisis_service.dart';
import '../../models/analisis_models.dart';

import 'create_service_dialog.dart';
import 'create_client_manufacturer_dialog.dart';
import 'edit_service_dialog.dart';
import 'ays_management_screen.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';

class AysDashboard extends StatefulWidget {
  static const routeName = '/analisis/dashboard';
  const AysDashboard({super.key});

  @override
  State<AysDashboard> createState() => _AysDashboardState();
}

class _AysDashboardState extends State<AysDashboard> {
  final _analisisService = const AnalisisService();

  // Overlay for robust sidebar handle visibility
  OverlayEntry? _edgeOverlay;

  List<Transaction> _openTransactions = [];
  List<Transaction> _historyTransactions = [];

  // Filter Options
  List<String> _clients = [];
  List<String> _manufacturers = [];
  List<String> _services = [];
  List<String> _xiaomiIds = [];

  // Filter State
  DateTime? _filterDateStart;
  DateTime? _filterDateEnd;
  String? _filterManufacturer;
  String? _filterClient;
  String? _filterService;
  String? _filterIdXiaomi;
  bool? _filterPaid;
  bool _filtersExpanded = false;
  final _searchController = TextEditingController();

  bool _loadingOpen = true;
  bool _loadingHistory = true;

  final _openTransactionsScrollController = ScrollController();
  final _historyTransactionsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _loadFilterOptions();

    // Insert the sidebar handle into the root overlay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final routeName =
          ModalRoute.of(context)?.settings.name ?? AysDashboard.routeName;

      final overlay = Overlay.of(context, rootOverlay: true);
      if (overlay == null) return;

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
                  user: Provider.of<ApiService>(ctx, listen: false).currentUser,
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
    });
  }

  @override
  void dispose() {
    _edgeOverlay?.remove();
    _edgeOverlay = null;

    _openTransactionsScrollController.dispose();
    _historyTransactionsScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    _loadOpenTransactions();
    _loadHistoryTransactions();
  }

  Future<void> _loadFilterOptions() async {
    try {
      final clients = await _analisisService.getClientes();
      final manufacturers = await _analisisService.getFabricantes();
      final services = await _analisisService.getServicios();
      // IDs are loaded with funds or separately if needed, but we can extract unique IDs from history + open for now or fetch funds regardless
      // Actually fetching funds gives us IDs. Even if user can't SEE funds, we might need IDs for filtering?
      // Let's fetch funds purely for ID extraction if not already loaded, or just reuse funds list if available.
      // But _loadFunds is restricted. Let's use getFunds just for IDs if needed, or extract from loaded transactions.
      // Better: reuse _funds if loaded, otherwise maybe we don't show ID filter or fetch it silently?
      // For now let's just use what we have in _funds if available.

      if (mounted) {
        setState(() {
          _clients = clients;
          _manufacturers = manufacturers;
          _services = services;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadOpenTransactions() async {
    try {
      final data = await _analisisService.getOpenTransactions();
      if (mounted) {
        setState(() {
          _openTransactions = data;
          _loadingOpen = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingOpen = false;
        });
      }
    }
  }

  Future<void> _loadHistoryTransactions() async {
    try {
      // Potentially increase limit here if filters require more data
      final data = await _analisisService.getClosedTransactions();
      if (mounted) {
        setState(() {
          _historyTransactions = data;
          _loadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingHistory = false;
        });
      }
    }
  }

  Future<void> _closeTransaction(int id, String? name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar Servicio'),
        content: Text(
          '¿Estás seguro de que deseas cerrar el servicio "${name ?? 'Sin ID'}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _analisisService.closeTransaction(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Servicio cerrado correctamente')),
        );
        _loadDashboardData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error cerrando servicio: $e')));
      }
    }
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;

    // Clean up string
    // Remove commas and ensure there's a space before AM/PM for easier parsing
    String clean = s.trim().replaceAll(',', '');
    clean = clean
        .replaceAll('AM', ' AM')
        .replaceAll('PM', ' PM')
        .replaceAll('  ', ' ');

    // 1. Try ISO
    final iso = DateTime.tryParse(clean);
    if (iso != null) return iso;

    // 2. Try common formats
    final formats = [
      'MMM d yyyy h:mm a', // Feb 3 2026 9:42 AM
      'MMMM d yyyy h:mm a',
      'd/M/yyyy',
      'dd/MM/yyyy',
      'MMM d yyyy HH:mm',
      'yyyy-MM-dd',
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

  List<Transaction> get _filteredHistory {
    return _historyTransactions.where((t) {
      // Date Filter (using fechai or fechaf)
      if (_filterDateStart != null || _filterDateEnd != null) {
        final date = _parseDate(t.fechaf) ?? _parseDate(t.fechai);
        if (date == null) return false;

        if (_filterDateStart != null && date.isBefore(_filterDateStart!))
          return false;
        if (_filterDateEnd != null &&
            date.isAfter(_filterDateEnd!.add(const Duration(days: 1))))
          return false;
      }

      // Case-insensitive string matching
      bool matchFilter(String? value, String? filter) {
        if (filter == null) return true;
        if (value == null) return false;
        return value.trim().toLowerCase() == filter.trim().toLowerCase();
      }

      if (!matchFilter(t.fabricante, _filterManufacturer)) return false;
      if (!matchFilter(t.cliente, _filterClient)) return false;
      if (!matchFilter(t.servicio, _filterService)) return false;
      if (!matchFilter(t.idxiaomi, _filterIdXiaomi)) return false;

      if (_filterPaid != null && t.paid != _filterPaid) return false;

      // General Search
      final query = _searchController.text.toLowerCase().trim();
      if (query.isNotEmpty) {
        final content = [
          t.orden,
          t.sku,
          t.servicio,
          t.fabricante,
          t.cliente,
          t.descripcion,
          t.unit,
          t.idxiaomi,
          t.claimacc,
          t.internal,
          t.fechaf,
          t.fechai,
        ].where((s) => s != null).join(' ').toLowerCase();
        if (!content.contains(query)) return false;
      }

      return true;
    }).toList();
  }

  void _clearFilters() {
    setState(() {
      _filterDateStart = null;
      _filterDateEnd = null;
      _filterManufacturer = null;
      _filterClient = null;
      _filterService = null;
      _filterIdXiaomi = null;
      _filterPaid = null;
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = Provider.of<ApiService>(context).currentUser;
    final canSeeFunds =
        user != null && (user.role == 'admin' || user.role == 'chief');

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // Premium Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.tertiary.withOpacity(0.05),
                  theme.colorScheme.primary.withOpacity(0.05),
                  theme.scaffoldBackgroundColor,
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
          ),

          // Main Content
          Padding(
            padding: const EdgeInsets.fromLTRB(60, 32, 32, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 24),
                if (canSeeFunds) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 24),
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          AysManagementScreen.routeName,
                        );
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(20),
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.dashboard_customize_rounded),
                      label: const Text(
                        'Ir al Panel de Gestión (Fondos y Analíticas)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 900;

                      if (isMobile) {
                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 100),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildServiciosPendientesBlock(context),
                              const SizedBox(height: 32),
                              _buildHistorialBlock(context),
                            ],
                          ),
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 5,
                            child: _buildServiciosPendientesBlock(context),
                          ),
                          const SizedBox(width: 32),
                          Expanded(
                            flex: 7,
                            child: _buildHistorialBlock(context),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Floating Action Button
          Positioned(bottom: 40, right: 40, child: _buildAddButton(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            Icons.analytics_rounded,
            size: 32,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Panel de Servicios',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Resumen general de actividad',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildServiciosPendientesBlock(BuildContext context) {
    final theme = Theme.of(context);
    return _buildListBlock(
      context,
      title: 'Órdenes Pendientes',
      icon: Icons.pending_actions_rounded,
      isLoading: _loadingOpen,
      isEmpty: _openTransactions.isEmpty,
      emptyText: 'No hay órdenes pendientes',
      controller: _openTransactionsScrollController,
      child: ListView.separated(
        controller: _openTransactionsScrollController,
        physics: const BouncingScrollPhysics(),
        itemCount: _openTransactions.length,
        padding: const EdgeInsets.only(right: 12),
        separatorBuilder: (ctx, i) =>
            Divider(height: 1, color: theme.dividerColor.withOpacity(0.1)),
        itemBuilder: (ctx, i) {
          final t = _openTransactions[i];
          final order = t.orden ?? t.csku;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: theme.cardColor.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor.withOpacity(0.05)),
            ),
            child: ListTile(
              onTap: () async {
                final result = await showDialog<bool>(
                  context: context,
                  builder: (_) => EditServiceDialog(transaction: t),
                );
                if (result == true) {
                  _loadDashboardData();
                }
              },
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.access_time_rounded,
                  color: Colors.orange,
                  size: 20,
                ),
              ),
              title: Text(
                '${order != null ? '$order - ' : ''}${t.idxiaomi ?? 'N/A'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${t.previ != null ? '${t.previ} - ' : ''}${t.descripcion ?? 'Sin descripción'}${t.unit != null ? ' - ${t.unit} uds' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      t.estado ?? 'Pendiente',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: Colors.green,
                    ),
                    tooltip: 'Cerrar Servicio',
                    onPressed: () {
                      if (t.id != null) {
                        _closeTransaction(t.id!, t.idxiaomi);
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistorialBlock(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredHistory;
    final user = Provider.of<ApiService>(context, listen: false).currentUser;

    // Custom List Block with filters embedded
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 400),
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.history_rounded,
                            color: theme.colorScheme.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Historial y Filtros',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            _filtersExpanded
                                ? Icons.filter_list_off_rounded
                                : Icons.filter_list_rounded,
                            color: _filtersExpanded
                                ? theme.colorScheme.primary
                                : null,
                          ),
                          onPressed: () => setState(
                            () => _filtersExpanded = !_filtersExpanded,
                          ),
                          tooltip: 'Mostrar/Ocultar Filtros',
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _clearFilters,
                          tooltip: 'Limpiar Filtros',
                        ),
                      ],
                    ),
                    if (_filtersExpanded) ...[
                      const SizedBox(height: 24),
                      _buildFilterSection(context),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              if (_loadingHistory)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filtered.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      'No hay resultados',
                      style: TextStyle(color: theme.hintColor),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Scrollbar(
                    controller: _historyTransactionsScrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    child: ListView.separated(
                      controller: _historyTransactionsScrollController,
                      physics: const BouncingScrollPhysics(),
                      itemCount: filtered.length,
                      padding: const EdgeInsets.all(12),
                      separatorBuilder: (ctx, i) => Divider(
                        height: 1,
                        color: theme.dividerColor.withOpacity(0.1),
                      ),
                      itemBuilder: (ctx, i) {
                        final t = filtered[i];
                        final order = t.orden ?? t.csku;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: theme.cardColor.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            onTap: () async {
                              final result = await showDialog<bool>(
                                context: context,
                                builder: (_) =>
                                    EditServiceDialog(transaction: t),
                              );
                              if (result == true) {
                                _loadDashboardData();
                              }
                            },
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.check_circle_outline_rounded,
                                color: Colors.green,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              '${order != null ? '$order - ' : ''}${t.idxiaomi ?? 'N/A'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${t.previ != null ? '${t.previ} - ' : ''}${t.descripcion ?? 'Sin descripción'}${t.unit != null ? ' - ${t.unit} uds' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (user != null &&
                                    (user.role == 'admin' ||
                                        user.role == 'chief'))
                                  InkWell(
                                    onTap: () async {
                                      try {
                                        await _analisisService
                                            .togglePaymentStatus(
                                              t.id!,
                                              !(t.paid ?? false),
                                            );
                                        if (!context.mounted) return;
                                        _loadDashboardData();
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(content: Text('Error: $e')),
                                        );
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(24),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            (t.paid == true
                                                    ? Colors.green
                                                    : Colors.orange)
                                                .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color:
                                              (t.paid == true
                                                      ? Colors.green
                                                      : Colors.orange)
                                                  .withOpacity(0.3),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            t.paid == true
                                                ? Icons.check_circle_rounded
                                                : Icons.pending_rounded,
                                            color: t.paid == true
                                                ? Colors.green
                                                : Colors.orange,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            t.paid == true
                                                ? 'PAGADO'
                                                : 'NO PAGADO',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: t.paid == true
                                                  ? Colors.green
                                                  : Colors.orange,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                Text(
                                  t.fechaf ?? t.fechai ?? '',
                                  style: theme.textTheme.bodySmall,
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
      ),
    );
  }

  Widget _buildFilterSection(BuildContext context) {
    final user = Provider.of<ApiService>(context).currentUser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildDatePicker(
                label: 'Desde',
                value: _filterDateStart,
                onChanged: (d) => setState(() => _filterDateStart = d),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDatePicker(
                label: 'Hasta',
                value: _filterDateEnd,
                onChanged: (d) => setState(() => _filterDateEnd = d),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                label: 'Fabricante',
                value: _filterManufacturer,
                items: _manufacturers,
                onChanged: (v) => setState(() => _filterManufacturer = v),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdown(
                label: 'Cliente',
                value: _filterClient,
                items: _clients,
                onChanged: (v) => setState(() => _filterClient = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                label: 'Servicio CF',
                value: _filterService,
                items: _services,
                onChanged: (v) => setState(() => _filterService = v),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdown(
                label: 'Id Xiaomi',
                value: _filterIdXiaomi,
                items: _xiaomiIds,
                onChanged: (v) => setState(() => _filterIdXiaomi = v),
              ),
            ),
            if (user != null &&
                (user.role == 'admin' || user.role == 'chief')) ...[
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estado Pago:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<bool?>(
                      value: _filterPaid,
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Todos')),
                        DropdownMenuItem(value: true, child: Text('Pagado')),
                        DropdownMenuItem(
                          value: false,
                          child: Text('No Pagado'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _filterPaid = v),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.surface.withOpacity(0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Búsqueda general (Orden, SKU, Descripción...)',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.surface.withOpacity(0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: _filteredHistory.isEmpty ? null : _exportToExcel,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.file_download_rounded),
              label: const Text('EXCEL'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _exportToExcel() async {
    try {
      final excel = excel_pkg.Excel.createExcel();
      // In version 2.0.1, createExcel() already creates a 'Sheet1'.
      // Deleting it can cause "Unsupported operation: Cannot remove from an unmodifiable list".
      // We'll just use the first available sheet or naming it appropriately if it doesn't crash.
      final sheetName = excel.sheets.keys.first;
      final sheet = excel[sheetName];

      // Add Headers
      sheet.appendRow([
        'ID XIAOMI',
        'ORDEN',
        'SKU',
        'SERVICIO',
        'FABRICANTE',
        'CLIENTE',
        'DESCRIPCIÓN',
        'COSTO (€)',
        'ESTADO PAGO',
        'FECHA FINAL',
      ]);

      // Add Data
      double total = 0;
      for (final t in _filteredHistory) {
        total += (t.cost ?? 0.0);
        sheet.appendRow([
          t.idxiaomi ?? '',
          t.orden ?? '',
          t.sku ?? '',
          t.servicio ?? '',
          t.fabricante ?? '',
          t.cliente ?? '',
          t.descripcion ?? '',
          t.cost ?? 0.0,
          t.paid == true ? 'PAGADO' : 'PENDIENTE',
          t.fechaf ?? t.fechai ?? '',
        ]);
      }

      // Add Total Row
      sheet.appendRow(['']); // Spacer
      sheet.appendRow(['', '', '', '', '', '', 'TOTAL:', total, '', '']);

      // Save file
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${directory.path}/Reporte_AYS_$timestamp.xlsx';
      final fileBytes = excel.encode();

      if (fileBytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        await OpenFilex.open(filePath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error exportando Excel: $e')));
      }
    }
  }

  Widget _buildDatePicker({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(
          value != null
              ? '${value.day}/${value.month}/${value.year}'
              : 'dd/mm/yyyy',
          style: value != null
              ? null
              : TextStyle(color: Theme.of(context).hintColor),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: items.contains(value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Todos')),
        ...items.map(
          (i) => DropdownMenuItem(
            value: i,
            child: Text(i, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
      isExpanded: true,
    );
  }

  Widget _buildListBlock(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isLoading,
    required bool isEmpty,
    required String emptyText,
    required Widget child,
    required ScrollController controller,
  }) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 600, // Matched with Historial block
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isLoading) ...[
                      const Spacer(),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
              if (!isLoading && isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_rounded,
                          size: 48,
                          color: theme.colorScheme.onSurface.withOpacity(0.2),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          emptyText,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (!isLoading)
                Expanded(
                  child: Scrollbar(
                    controller: controller,
                    thumbVisibility: true,
                    trackVisibility: true,
                    child: child,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      offset: const Offset(0, -150),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      color:
          theme.menuButtonTheme.style?.backgroundColor?.resolve({}) ??
          theme.cardColor,
      onSelected: (value) async {
        if (value == 'Servicio') {
          final result = await showDialog<bool>(
            context: context,
            builder: (_) => const CreateServiceDialog(),
          );
          if (result == true) _loadDashboardData();
        } else if (value == 'Clientes, Fabricantes y Internals') {
          await showDialog(
            context: context,
            builder: (_) => const CreateClientManufacturerDialog(),
          );
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'Servicio',
          child: ListTile(
            leading: Icon(
              Icons.build_rounded,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Servicio'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<String>(
          value: 'Clientes, Fabricantes y Internals',
          child: ListTile(
            leading: Icon(
              Icons.people_rounded,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Gestión de Entidades'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}
