import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../themes/amazon_theme.dart';
import '../../services/api_service.dart';

class AmzFindBoxScreen extends StatefulWidget {
  const AmzFindBoxScreen({Key? key}) : super(key: key);

  @override
  _AmzFindBoxScreenState createState() => _AmzFindBoxScreenState();
}

class _AmzFindBoxScreenState extends State<AmzFindBoxScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _boxFocus = FocusNode();

  bool _loading = false;
  String? _error;
  List<dynamic> _results = [];

  late AnimationController _searchIconController;

  @override
  void initState() {
    super.initState();
    _searchIconController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) { FocusScope.of(context).requestFocus(_boxFocus); });
  }

  @override
  void dispose() {
    _searchIconController.dispose();
    _controller.dispose();
    _boxFocus.dispose();
    super.dispose();
  }

  Future<void> _searchBox() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() { _loading = true; _error = null; _results = []; });

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post('/amz/grading/sorting/search_box', jsonBody: {'box_name': _controller.text.trim()});
      if (res.ok && res.body is Map) {
        final data = res.body as Map<String, dynamic>;
        setState(() { _results = data['results'] as List<dynamic>? ?? []; });
      } else {
        setState(() { _error = res.error ?? 'Error al buscar caja'; });
      }
    } catch (e) {
      setState(() { _error = 'Excepción: $e'; });
    } finally {
      setState(() { _loading = false; });
      FocusScope.of(context).requestFocus(_boxFocus);
    }
  }

  Future<void> _deleteBox(String boxName) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post('/amz/grading/sorting/delete_box', jsonBody: {'box_name': boxName});
      if (res.ok) {
        setState(() { _results.removeWhere((r) => r['box_name'] == boxName); });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.body is Map ? (res.body['message'] ?? 'Eliminado') : 'Eliminado')));
      } else {
        throw Exception(res.error ?? 'Error eliminando caja');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _reprintLabel(String boxName) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post('/amz/grading/sorting/reprint_label', jsonBody: {'box_name': boxName});
      final msg = (res.body is Map) ? (res.body['message'] ?? 'Etiqueta reimpresa') : 'Etiqueta reimpresa';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error reimprimiendo etiqueta')));
    }
  }

  void _showDetails(Map<String, dynamic> item) {
    showDialog(context: context, builder: (_) => SelectionArea(child: AlertDialog(
      title: Text('Detalle de la Caja ${item['box_name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildDetailRow('ASIN', item['asin']),
        _buildDetailRow('DSN', item['dsn_scan']),
        _buildDetailRow('Estado (Bucket)', item['grading_status']),
        _buildDetailRow('Código UPC', item['upc_scan']),
        const Divider(),
        _buildDetailRow('Fecha de puesta', _formatDate(item['put_time'])),
        _buildDetailRow('Usuario que inserto la box', item['username_put']),
        _buildDetailRow('Fecha de OPS-Pick', _formatDate(item['opspick_time'])),
        _buildDetailRow('Usuario OPS-Pick', item['username_opspick']),
        _buildDetailRow('Fecha de cierre', _formatDate(item['box_close'])),
        _buildDetailRow('Usuario que cerró la box', item['username_close']),
      ])), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar'))],)));
  }

  Widget _buildDetailRow(String etiqueta, dynamic valor) {
    final texto = (valor == null || valor.toString().isEmpty || valor == 'null') ? '—' : valor.toString();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: SelectableText.rich(TextSpan(children: [TextSpan(text: '$etiqueta: ', style: const TextStyle(fontWeight: FontWeight.w600)), TextSpan(text: texto)]))),
      if (valor != null && valor.toString().isNotEmpty && valor.toString() != 'null') IconButton(icon: const Icon(Icons.copy, size: 20), tooltip: 'Copiar', onPressed: () { Clipboard.setData(ClipboardData(text: texto)); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copiado: $texto'))); }),
    ]));
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw.toString());
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return raw.toString(); }
  }

  @override
  Widget build(BuildContext context) {
    return AmazonTheme(
      child: Builder(builder: (ctx) {
        final theme = Theme.of(ctx);

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Buscar Caja Amazon'),
          ),
          body: SafeArea(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [theme.colorScheme.primary.withOpacity(0.9), theme.colorScheme.surface],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1)),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                        ),
                        child: Column(
                          children: [
                            Form(
                              key: _formKey,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _controller,
                                      focusNode: _boxFocus,
                                      textInputAction: TextInputAction.done,
                                      onFieldSubmitted: (_) => _searchBox(),
                                      style: TextStyle(color: theme.colorScheme.onSurface),
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: theme.cardColor,
                                        labelText: 'Número de Caja',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        prefixIcon: RotationTransition(turns: _searchIconController, child: Icon(Icons.search, color: theme.colorScheme.onSurface)),
                                      ),
                                      validator: (v) => (v == null || v.isEmpty) ? 'Campo requerido' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _loading ? null : _searchBox,
                                    child: _loading
                                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Text('Ir'),
                                  ),
                                ],
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(_error!, style: const TextStyle(color: Colors.red)),
                            ],
                            const SizedBox(height: 12),
                            if (_results.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text('Total de unidades en la caja: ${_results.length}', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
                              ),
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: () async => _searchBox(),
                                child: _loading && _results.isEmpty
                                    ? const Center(child: CircularProgressIndicator())
                                    : _results.isEmpty
                                        ? const Center(child: Text('Sin resultados'))
                                        : ListView.separated(
                                            itemCount: _results.length,
                                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                                            itemBuilder: (_, i) {
                                              final item = _results[i] as Map<String, dynamic>;
                                              return Dismissible(
                                                key: Key(item['box_name']),
                                                direction: DismissDirection.endToStart,
                                                onDismissed: (_) => _deleteBox(item['box_name']),
                                                background: Container(
                                                  alignment: Alignment.centerRight,
                                                  color: Colors.redAccent,
                                                  child: const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Icon(Icons.delete_forever, color: Colors.white, size: 32)),
                                                ),
                                                child: Container(
                                                  decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))]),
                                                  child: ListTile(
                                                    onTap: () => _showDetails(item),
                                                    title: Text('DSN: ${item['dsn_scan']}'),
                                                    subtitle: Text('Bucket: ${item['grading_status']}'),
                                                    trailing: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        IconButton(icon: Icon(Icons.print_outlined, size: 20, color: theme.colorScheme.onSurface), tooltip: 'Reimprimir etiqueta', onPressed: () => _reprintLabel(item['box_name'])),
                                                        IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent), tooltip: 'Eliminar caja', onPressed: () => _deleteBox(item['box_name'])),
                                                        const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                                                      ],
                                                    ),
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
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
