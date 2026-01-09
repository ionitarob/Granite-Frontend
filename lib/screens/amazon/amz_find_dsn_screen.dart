import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../themes/amazon_theme.dart';
import '../../services/api_service.dart';

class AmzFindDsnScreen extends StatefulWidget {
  const AmzFindDsnScreen({Key? key}) : super(key: key);

  @override
  _AmzFindDsnScreenState createState() => _AmzFindDsnScreenState();
}

class _AmzFindDsnScreenState extends State<AmzFindDsnScreen> {
  final TextEditingController _dsnController = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void dispose() {
    _dsnController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() { _loading = true; _error = null; _result = null; });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post('/amz/grading/find_dsn', jsonBody: {'dsn': _dsnController.text.trim()});
      if (res.ok && res.body is Map) {
        setState(() { _result = res.body as Map<String,dynamic>; });
      } else {
        setState(() { _error = res.error ?? 'No encontrado'; });
      }
    } catch (e) {
      setState(() { _error = 'Excepción: $e'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AmazonTheme(
      child: Builder(builder: (ctx) {
        final theme = Theme.of(ctx);
        return Scaffold(
          appBar: AppBar(title: const Text('Buscar por DSN')),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(controller: _dsnController, decoration: InputDecoration(labelText: 'DSN', filled: true, fillColor: theme.cardColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _loading ? null : _search, child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Buscar')),
                  const SizedBox(height: 12),
                  if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                  _result != null
                      ? Expanded(child: Card(color: theme.cardColor, child: Padding(padding: const EdgeInsets.all(12), child: ListView(children: _result!.entries.map((e) => ListTile(title: Text(e.key), subtitle: Text(e.value?.toString() ?? '—'))).toList()))))
                      : const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
