import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/orderops_service.dart';
import '../../models/agent_models.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';

class WorkItemsScreen extends StatefulWidget {
  const WorkItemsScreen({super.key});

  @override
  State<WorkItemsScreen> createState() => _WorkItemsScreenState();
}

class _WorkItemsScreenState extends State<WorkItemsScreen> {
  OrderOpsService? _orderOpsService;
  List<WorkItem> _items = [];
  bool _loading = true;
  String? _filterStatus;
  OverlayEntry? _edgeOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      _orderOpsService = OrderOpsService(apiService.client);
      _loadItems();

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
    _edgeOverlay?.remove();
    _edgeOverlay = null;
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final items = await _orderOpsService!.getWorkItems(status: _filterStatus);
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(WorkItem item, String newStatus) async {
    // Optimistic update
    setState(() {
      final index = _items.indexWhere((i) => i.workItemId == item.workItemId);
      if (index != -1) {
        // Create copy with new status
        // Since fields are final, we can't edit.
        // Ideally WorkItem would have copyWith. For now, just re-fetch or ignore UI update until fetch.
        // Let's just re-fetch for simplicity or show loading.
      }
    });

    try {
      await _orderOpsService!.updateWorkItem(
        item.workItemId,
        status: newStatus,
      );
      _loadItems(); // refresh
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 0.7),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Tareas Pendientes',
                        style: theme.textTheme.headlineLarge,
                      ),
                      DropdownButton<String>(
                        value: _filterStatus,
                        hint: const Text('Filtrar Estado'),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Todos')),
                          DropdownMenuItem(
                            value: 'open',
                            child: Text('Pendiente'),
                          ),
                          DropdownMenuItem(
                            value: 'in_progress',
                            child: Text('En Progreso'),
                          ),
                          DropdownMenuItem(
                            value: 'blocked',
                            child: Text('Bloqueado'),
                          ),
                          DropdownMenuItem(value: 'done', child: Text('Hecho')),
                        ],
                        onChanged: (val) {
                          setState(() => _filterStatus = val);
                          _loadItems();
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _items.length,
                          itemBuilder: (ctx, i) {
                            final item = _items[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: theme.cardColor.withOpacity(0.8),
                              child: ListTile(
                                title: Text(item.description),
                                subtitle: Text(
                                  'Pedido #${item.idnbr} • ${item.type}',
                                ),
                                trailing: DropdownButton<String>(
                                  value: item.status,
                                  underline: const SizedBox(),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'open',
                                      child: Text('Pendiente'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'in_progress',
                                      child: Text('En Progreso'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'blocked',
                                      child: Text('Bloqueado'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'done',
                                      child: Text('Hecho'),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) _updateStatus(item, val);
                                  },
                                ),
                                leading: _getStatusIcon(item.status),
                              ),
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

  Widget _getStatusIcon(String status) {
    switch (status) {
      case 'open':
        return const Icon(Icons.radio_button_unchecked, color: Colors.grey);
      case 'in_progress':
        return const Icon(Icons.autorenew, color: Colors.blue);
      case 'blocked':
        return const Icon(Icons.block, color: Colors.red);
      case 'done':
        return const Icon(Icons.check_circle, color: Colors.green);
      default:
        return const Icon(Icons.help_outline);
    }
  }
}
