import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/orderops_service.dart';
import '../../models/agent_models.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';
import 'order_detail_screen.dart'; // To navigate to source order

class AgentMemoryScreen extends StatefulWidget {
  const AgentMemoryScreen({super.key});

  @override
  State<AgentMemoryScreen> createState() => _AgentMemoryScreenState();
}

class _AgentMemoryScreenState extends State<AgentMemoryScreen> {
  OrderOpsService? _orderOpsService;
  List<AgentMemory> _memories = [];
  bool _loading = true;
  String? _error;
  OverlayEntry? _edgeOverlay;

  // Filters
  String _statusFilter = 'open'; // Default to open questions

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      _orderOpsService = OrderOpsService(apiService.client);
      _loadMemories();

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
    super.dispose();
  }

  Future<void> _loadMemories() async {
    setState(() => _loading = true);
    try {
      // If filter is 'all', pass null
      final status = _statusFilter == 'all' ? null : _statusFilter;
      final items = await _orderOpsService!.getAgentMemory(status: status);
      setState(() {
        _memories = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _answerQuestion(AgentMemory memory, String answer) async {
    try {
      await _orderOpsService!.updateAgentMemory(
        memory.id,
        answer: answer,
        status: 'answered',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Answered & Triggered Re-triage')),
      );
      _loadMemories(); // Refresh list
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showAnswerDialog(AgentMemory memory) {
    String answer = '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Responder Pregunta del Agente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'P: ${memory.question}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (memory.sourceExcerpt != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Contexto: "${memory.sourceExcerpt}"',
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Tu Respuesta',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              onChanged: (val) => answer = val,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (answer.isNotEmpty) {
                _answerQuestion(memory, answer);
              }
            },
            child: const Text('Enviar Respuesta'),
          ),
        ],
      ),
    );
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
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme),
                  const SizedBox(height: 24),
                  _buildContent(theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Memoria del Agente (P/R)',
          style: theme.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        DropdownButton<String>(
          value: _statusFilter,
          items: const [
            DropdownMenuItem(value: 'open', child: Text('Preguntas Abiertas')),
            DropdownMenuItem(value: 'answered', child: Text('Respondidas')),
            DropdownMenuItem(value: 'ignored', child: Text('Ignoradas')),
            DropdownMenuItem(value: 'all', child: Text('Todas')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _statusFilter = val);
              _loadMemories();
            }
          },
        ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error'));
    if (_memories.isEmpty) {
      return const Center(child: Text('No se encontraron preguntas.'));
    }

    return Expanded(
      child: ListView.separated(
        itemCount: _memories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, index) {
          final m = _memories[index];
          return Card(
            color: theme.cardColor.withOpacity(0.9),
            elevation: 2,
            child: ListTile(
              title: Text(m.question),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  if (m.answer != null)
                    Text(
                      'R: ${m.answer}',
                      style: const TextStyle(color: Colors.green),
                    ),
                  Text(
                    'Contexto: ${m.sourceExcerpt ?? "Ninguno"} • Dept: ${m.department ?? "General"}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              trailing: m.status == 'open'
                  ? ElevatedButton(
                      onPressed: () => _showAnswerDialog(m),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                      ),
                      child: const Text('Responder'),
                    )
                  : Chip(label: Text(m.status!.toUpperCase())),
              onTap: m.sourceIdnbr != null
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              OrderDetailScreen(orderId: m.sourceIdnbr!),
                        ),
                      );
                    }
                  : null,
            ),
          );
        },
      ),
    );
  }
}
