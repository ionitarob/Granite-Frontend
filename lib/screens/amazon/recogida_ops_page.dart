import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../themes/amazon_theme.dart';
import '../../services/api_service.dart';

class RecogidaOpsPage extends StatefulWidget {
  const RecogidaOpsPage({super.key});

  @override
  _RecogidaOpsPageState createState() => _RecogidaOpsPageState();
}

class _RecogidaOpsPageState extends State<RecogidaOpsPage> {
  List<dynamic> _ops = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.get('/amz/grading/recogida_ops/list');
      if (res.ok && res.body is Map) {
        setState(() { _ops = (res.body['ops'] as List<dynamic>?) ?? []; });
      } else {
        setState(() { _error = res.error ?? 'Error cargando operaciones'; });
      }
    } catch (e) {
      setState(() { _error = 'Excepción: $e'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _markPicked(String opId) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post('/amz/grading/recogida_ops/pick', jsonBody: {'op_id': opId});
      if (res.ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marcado como recogido')));
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error ?? 'Error')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excepción: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AmazonTheme(
      child: Builder(builder: (ctx) {
        final theme = Theme.of(ctx);
        return Scaffold(
          appBar: AppBar(title: const Text('Recogida OPS')),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _loading && _ops.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _ops.isEmpty
                      ? Center(child: Text(_error ?? 'No hay operaciones', style: TextStyle(color: theme.colorScheme.onSurface)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            itemCount: _ops.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (_, i) {
                              final op = _ops[i] as Map<String, dynamic>;
                              return ListTile(
                                title: Text('OP: ${op['id'] ?? op['op_id'] ?? '—'}'),
                                subtitle: Text(op['description']?.toString() ?? ''),
                                trailing: ElevatedButton(onPressed: () => _markPicked(op['id']?.toString() ?? op['op_id']?.toString() ?? ''), child: const Text('Recoger')),
                              );
                            },
                          ),
                        ),
            ),
          ),
        );
      }),
    );
  }
}
