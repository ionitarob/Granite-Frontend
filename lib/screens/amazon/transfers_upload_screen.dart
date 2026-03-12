import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../themes/amazon_theme.dart';
import '../../services/api_service.dart';

class TransfersUploadScreen extends StatefulWidget {
  const TransfersUploadScreen({super.key});

  @override
  _TransfersUploadScreenState createState() => _TransfersUploadScreenState();
}

class _TransfersUploadScreenState extends State<TransfersUploadScreen> {
  final TextEditingController _payloadController = TextEditingController();
  bool _loading = false;
  String? _message;

  @override
  void dispose() {
    _payloadController.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    setState(() { _loading = true; _message = null; });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post('/amz/grading/transfers/upload', jsonBody: {'data': _payloadController.text});
      if (res.ok) {
        setState(() { _message = (res.body is Map) ? (res.body['message'] ?? 'Carga completada') : 'Carga completada'; });
      } else {
        setState(() { _message = res.error ?? 'Error en la carga'; });
      }
    } catch (e) {
      setState(() { _message = 'Excepción: $e'; });
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
          appBar: AppBar(title: const Text('Cargas - Transfers')),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text('Pega el contenido CSV o JSON aquí:', style: TextStyle(color: theme.colorScheme.onSurface)),
                const SizedBox(height: 8),
                Expanded(child: TextField(controller: _payloadController, maxLines: null, expands: true, decoration: InputDecoration(filled: true, fillColor: theme.cardColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                const SizedBox(height: 8),
                Row(children: [Expanded(child: ElevatedButton(onPressed: _loading ? null : _upload, child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Subir')))]),
                if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!)),
              ]),
            ),
          ),
        );
      }),
    );
  }
}
