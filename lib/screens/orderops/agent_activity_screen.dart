import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/orderops_service.dart';
import '../../models/agent_models.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';

class AgentActivityScreen extends StatefulWidget {
  const AgentActivityScreen({super.key});

  @override
  State<AgentActivityScreen> createState() => _AgentActivityScreenState();
}

class _AgentActivityScreenState extends State<AgentActivityScreen> {
  OrderOpsService? _orderOpsService;
  List<AgentOrder> _recentActivity = [];
  bool _loading = true;
  OverlayEntry? _edgeOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      _orderOpsService = OrderOpsService(apiService.client);
      _loadActivity();

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

  Future<void> _loadActivity() async {
    setState(() => _loading = true);
    try {
      // We fetch recent orders that have been triaged.
      // Ideally backend would have /agent/activity, but we simulate by fetching recent lists
      // and showing those with last_triaged_at != null
      final orders = await _orderOpsService!.getAgentOrders(limit: 50);

      final triaged = orders.where((o) => o.lastTriagedAt != null).toList();
      triaged.sort((a, b) => b.lastTriagedAt!.compareTo(a.lastTriagedAt!));

      setState(() {
        _recentActivity = triaged;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Registro de Actividad del Agente',
                        style: theme.textTheme.headlineLarge,
                      ),
                      IconButton(
                        onPressed: _loadActivity,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: _recentActivity.length,
                            itemBuilder: (ctx, i) {
                              final item = _recentActivity[i];
                              return Card(
                                color: theme.cardColor.withOpacity(0.8),
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: item.llmConfidence >= 0.8
                                        ? Colors.green
                                        : Colors.orange,
                                    child: Icon(
                                      item.llmConfidence >= 0.8
                                          ? Icons.check
                                          : Icons.priority_high,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                  title: Text(
                                    'Pedido Analizado #${item.orderNbr}',
                                  ),
                                  subtitle: Text(
                                    'Confianza: ${(item.llmConfidence * 100).toStringAsFixed(1)}% • Riesgo: ${item.riskLevel.toUpperCase()}'
                                    '\n${item.lastTriagedAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(item.lastTriagedAt!) : ""}',
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
