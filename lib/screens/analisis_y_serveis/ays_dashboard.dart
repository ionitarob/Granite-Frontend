import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';

import '../../services/analisis_service.dart';
import '../../models/analisis_models.dart';

import 'project_transactions_dialog.dart';
import 'create_project_fund_dialog.dart';
import 'create_service_dialog.dart';
import 'create_client_manufacturer_dialog.dart';
import 'edit_service_dialog.dart';

class AysDashboard extends StatefulWidget {
  const AysDashboard({super.key});

  @override
  State<AysDashboard> createState() => _AysDashboardState();
}

class _AysDashboardState extends State<AysDashboard> {
  final _analisisService = const AnalisisService();
  List<ProjectFund> _funds = [];
  List<Transaction> _openTransactions = [];
  List<Transaction> _historyTransactions = [];
  bool _loadingFunds = true;
  bool _loadingOpen = true;
  bool _loadingHistory = true;
  String? _fundsError;

  final _fundsScrollController = ScrollController();
  final _openTransactionsScrollController = ScrollController();
  final _historyTransactionsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _fundsScrollController.dispose();
    _openTransactionsScrollController.dispose();
    _historyTransactionsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    _loadFunds();
    _loadOpenTransactions();
    _loadHistoryTransactions();
  }

  Future<void> _loadFunds() async {
    try {
      final data = await _analisisService.getFunds();
      if (mounted) {
        setState(() {
          _funds = data;
          _loadingFunds = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fundsError = e.toString();
          _loadingFunds = false;
        });
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Main Content
          Padding(
            padding: const EdgeInsets.only(
              left: 60.0, // More space for sidebar
              top: 32,
              right: 32,
              bottom: 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 32),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFondosBlock(context),
                        const SizedBox(height: 32),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildServiciosPendientesBlock(context),
                            ),
                            const SizedBox(width: 32),
                            Expanded(child: _buildHistorialBlock(context)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Floating Action Button
          Positioned(bottom: 40, right: 40, child: _buildAddButton(context)),
          // Sidebar Handle
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: EdgeNavHandle(
                user: Provider.of<ApiService>(
                  context,
                  listen: false,
                ).currentUser,
                width: 28,
              ),
            ),
          ),
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
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
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
                color: theme.colorScheme.onBackground,
              ),
            ),
            Text(
              'Resumen general de actividad',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onBackground.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFondosBlock(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Fondos Activos',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_loadingFunds)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_fundsError != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Text(
              'Error al cargar fondos: $_fundsError',
              style: const TextStyle(color: Colors.red),
            ),
          )
        else if (_funds.isEmpty && !_loadingFunds)
          Container(
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.1),
              ),
            ),
            child: Center(
              child: Text(
                'No hay fondos disponibles',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 180,
            child: Scrollbar(
              controller: _fundsScrollController,
              thumbVisibility: true,
              trackVisibility: true,
              child: ListView.separated(
                controller: _fundsScrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _funds.length,
                padding: const EdgeInsets.only(bottom: 12),
                separatorBuilder: (ctx, i) => const SizedBox(width: 20),
                itemBuilder: (ctx, i) {
                  final p = _funds[i];
                  return _buildFundCard(context, p);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFundCard(BuildContext context, ProjectFund p) {
    final theme = Theme.of(context);
    final total = p.fondos ?? 0.0;
    final used = p.totalSpent;
    final remaining = p.remaining ?? 0.0;
    final percent = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final isLow = remaining < 5000;

    return GestureDetector(
      onTap: () {
        if (p.idxiaomi != null) {
          showDialog(
            context: context,
            builder: (_) => ProjectTransactionsDialog(
              idxiaomi: p.idxiaomi!,
              projectName: p.descripcion,
            ),
          );
        }
      },
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.folder_open_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  p.idxiaomi ?? 'Sin ID',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  p.descripcion ?? 'Sin descripción',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(percent * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      '${remaining.toStringAsFixed(0)} €',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isLow ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent,
                    backgroundColor: theme.colorScheme.surfaceVariant,
                    color: percent > 0.9
                        ? Colors.red
                        : theme.colorScheme.primary,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiciosPendientesBlock(BuildContext context) {
    final theme = Theme.of(context);
    return _buildListBlock(
      context,
      title: 'Servicios Pendientes',
      icon: Icons.pending_actions_rounded,
      isLoading: _loadingOpen,
      isEmpty: _openTransactions.isEmpty,
      emptyText: 'No hay servicios pendientes',
      controller: _openTransactionsScrollController,
      child: ListView.separated(
        controller: _openTransactionsScrollController,
        physics: const BouncingScrollPhysics(),
        itemCount: _openTransactions.length,
        padding: const EdgeInsets.only(right: 12),
        separatorBuilder: (ctx, i) =>
            Divider(height: 1, color: theme.dividerColor.withOpacity(0.5)),
        itemBuilder: (ctx, i) {
          final t = _openTransactions[i];
          return ListTile(
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
              t.idxiaomi ?? 'N/A',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              t.descripcion ?? 'Sin descripción',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          );
        },
      ),
    );
  }

  Widget _buildHistorialBlock(BuildContext context) {
    final theme = Theme.of(context);
    return _buildListBlock(
      context,
      title: 'Historial Reciente',
      icon: Icons.history_rounded,
      isLoading: _loadingHistory,
      isEmpty: _historyTransactions.isEmpty,
      emptyText: 'No hay historial disponible',
      controller: _historyTransactionsScrollController,
      child: ListView.separated(
        controller: _historyTransactionsScrollController,
        physics: const BouncingScrollPhysics(),
        itemCount: _historyTransactions.length,
        padding: const EdgeInsets.only(right: 12),
        separatorBuilder: (ctx, i) =>
            Divider(height: 1, color: theme.dividerColor.withOpacity(0.5)),
        itemBuilder: (ctx, i) {
          final t = _historyTransactions[i];
          return ListTile(
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
              t.idxiaomi ?? 'N/A',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              t.descripcion ?? 'Sin descripción',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              t.fechaf ?? t.fechai ?? '',
              style: theme.textTheme.bodySmall,
            ),
          );
        },
      ),
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
    return Container(
      height: 400, // Fixed height for scrolling
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
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
    );
  }

  Widget _buildAddButton(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      offset: const Offset(0, -150),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      onSelected: (value) async {
        if (value == 'ID Xiaomi') {
          final result = await showDialog<bool>(
            context: context,
            builder: (_) => const CreateProjectFundDialog(),
          );
          if (result == true) _loadDashboardData();
        } else if (value == 'Servicio') {
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
          value: 'ID Xiaomi',
          child: ListTile(
            leading: Icon(
              Icons.phone_android_rounded,
              color: theme.colorScheme.primary,
            ),
            title: const Text('ID Xiaomi'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: theme.colorScheme.onPrimary),
            const SizedBox(width: 8),
            Text(
              'Nuevo Registro',
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
