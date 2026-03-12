import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';

import '../../themes/amazon_theme.dart';
import '../../services/api_service.dart';

class AmazonInventoryScreen extends StatefulWidget {
  const AmazonInventoryScreen({super.key});

  @override
  _AmazonInventoryScreenState createState() => _AmazonInventoryScreenState();
}

class _AmazonInventoryScreenState extends State<AmazonInventoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final TextEditingController _partCtrl = TextEditingController();
  final TextEditingController _wplCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _partResult;
  Map<String, dynamic>? _wplResult;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _partCtrl.dispose();
    _wplCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchPart() async {
    final part = _partCtrl.text.trim();
    if (part.isEmpty) return;
    setState(() { _loading = true; _error = null; _partResult = null; });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
  final res = await api.client.get('/amz/inventory/part/$part');
      if (res.ok && res.body is Map) {
        setState(() { _partResult = Map<String, dynamic>.from(res.body as Map); });
      } else {
        setState(() { _error = res.error ?? 'No encontrado'; });
      }
    } catch (e) {
      setState(() { _error = 'Excepción: $e'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _searchWpl() async {
    final wpl = _wplCtrl.text.trim();
    if (wpl.isEmpty) return;
    setState(() { _loading = true; _error = null; _wplResult = null; });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
  final res = await api.client.get('/amz/inventory/wpl/$wpl');
      if (res.ok && res.body is Map) {
        setState(() { _wplResult = Map<String, dynamic>.from(res.body as Map); });
      } else {
        setState(() { _error = res.error ?? 'No encontrado'; });
      }
    } catch (e) {
      setState(() { _error = 'Excepción: $e'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _exportWplExcel(String wplId) async {
    try {
      setState(() { _loading = true; _error = null; });
      final api = Provider.of<ApiService>(context, listen: false);
      // Try obvious export path used by the backend. If your backend differs
      // adjust this path accordingly (common variants: /inventory/wpl/export/<id>)
  final res = await api.client.getBytes('/amz/inventory/wpl/$wplId/export');
      if (res.ok && res.body is Uint8List) {
        final bytes = res.body as Uint8List;
        final dir = await getTemporaryDirectory();
        final fname = 'wpl_${wplId}_export_${DateTime.now().toUtc().toIso8601String().replaceAll(':', '')}.xlsx';
        final path = '${dir.path}/$fname';
        final f = File(path);
        await f.writeAsBytes(bytes, flush: true);
        await OpenFilex.open(path);
      } else {
        setState(() { _error = res.error ?? 'Export failed'; });
      }
    } catch (e) {
      setState(() { _error = 'Export exception: $e'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Widget _buildKeyValueList(Map<String, dynamic> m) {
    final entries = m.entries.toList();
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final e = entries[i];
        return ListTile(title: Text(e.key), subtitle: Text(e.value?.toString() ?? '—'));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AmazonTheme(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Amazon Inventory'),
          bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'By Part'), Tab(text: 'By WPL')]),
        ),
        body: TabBarView(controller: _tabs, children: [
          // By Part
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              TextField(controller: _partCtrl, decoration: const InputDecoration(labelText: 'Part number', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              Row(children: [Expanded(child: ElevatedButton(onPressed: _loading ? null : _searchPart, child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Search')))]),
              const SizedBox(height: 8),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              Expanded(child: _partResult != null ? Card(child: _buildKeyValueList(_partResult!)) : const SizedBox.shrink()),
            ]),
          ),
          // By WPL
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              TextField(controller: _wplCtrl, decoration: const InputDecoration(labelText: 'WPL ID', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: ElevatedButton(onPressed: _loading ? null : _searchWpl, child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Search'))),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: (_loading || _wplCtrl.text.trim().isEmpty) ? null : () => _exportWplExcel(_wplCtrl.text.trim()), child: const Text('Export'))
              ]),
              const SizedBox(height: 8),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              Expanded(child: _wplResult != null ? Card(child: Padding(padding: const EdgeInsets.all(8), child: _buildWplView(_wplResult!))) : const SizedBox.shrink()),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildWplView(Map<String, dynamic> m) {
    // Build a composed view showing summary, parts and logs if present.
    final parts = m['parts'] as List<dynamic>?;
    final units = m['units'] as List<dynamic>?;
    final logs = m['logs'] as List<dynamic>?;
    return ListView(children: [
      ListTile(title: const Text('WPL'), subtitle: Text(m['wpl_id']?.toString() ?? '—')),
      ListTile(title: const Text('Location'), subtitle: Text(m['location_no']?.toString() ?? '—')),
      ListTile(title: const Text('Total units'), subtitle: Text('${m['total_units'] ?? 0}')),
      if (parts != null) ...[
        const Divider(),
        const ListTile(title: Text('Parts')),
        ...parts.map((p) => ListTile(title: Text(p['part_number']?.toString() ?? ''), trailing: Text('${p['units'] ?? 0}'))),
      ],
      if (units != null) ...[
        const Divider(),
        const ListTile(title: Text('Units')),
        ...units.map((u) => ListTile(title: Text(u['part_number']?.toString() ?? ''), subtitle: Text('Qty: ${u['quantity'] ?? 0}'))),
      ],
      if (logs != null) ...[
        const Divider(),
        const ListTile(title: Text('History')),
        ...logs.map((h) => ListTile(title: Text(h['action']?.toString() ?? ''), subtitle: Text('${h['date'] ?? ''} • ${h['user'] ?? ''}'))),
      ],
    ]);
  }
}
