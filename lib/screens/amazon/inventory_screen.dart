import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';

import '../../themes/amazon_theme.dart';
import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';

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
  // Registries
  List<Map<String, dynamic>> _partsRegistry = [];
  List<Map<String, dynamic>> _wplsRegistry = [];
  bool _partsRegistryLoading = false;
  bool _wplsRegistryLoading = false;
  String? _partsRegistryError;
  String? _wplsRegistryError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // load registries on first frame
      _fetchPartsRegistry();
      _fetchWplsRegistry();
    });
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

  Future<void> _fetchPartsRegistry({String q = '', int limit = 1000, int offset = 0}) async {
    setState(() {
      _partsRegistryLoading = true;
      _partsRegistryError = null;
    });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final enc = Uri.encodeQueryComponent(q);
      final path = '/amz/inventory/parts?q=$enc&limit=$limit&offset=$offset';
      final res = await api.client.get(path);
      if (res.ok) {
        final body = res.body;
        List<dynamic> list = [];
        if (body is Map && body['results'] is List) list = body['results'];
        else if (body is List) list = body;
        setState(() {
          _partsRegistry = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        });
      } else {
        setState(() => _partsRegistryError = res.error ?? 'Failed to load parts registry');
      }
    } catch (e) {
      setState(() => _partsRegistryError = e.toString());
    } finally {
      setState(() => _partsRegistryLoading = false);
    }
  }

  Future<void> _showPartsRegistry() async {
    final api = Provider.of<ApiService>(context, listen: false);
    String q = '';
    int limit = 50;
    int offset = 0;
    List<Map<String, dynamic>> items = [];
    bool loading = false;
    bool hasMore = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setStateDialog) {
          Future<void> loadPage({bool reset = false}) async {
            if (loading) return;
            setStateDialog(() { loading = true; });
            try {
              if (reset) {
                offset = 0;
                items = [];
                hasMore = true;
              }
              final enc = Uri.encodeQueryComponent(q);
              final path = '/amz/inventory/parts?q=$enc&limit=$limit&offset=$offset';
              final res = await api.client.get(path);
              if (res.ok) {
                final body = res.body;
                List<dynamic> list = [];
                if (body is Map && body['results'] is List) list = body['results'];
                else if (body is List) list = body;
                final fetched = list.whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
                items.addAll(fetched);
                offset += fetched.length;
                if (fetched.length < limit) hasMore = false;
              } else {
                hasMore = false;
              }
            } catch (_) {
              hasMore = false;
            } finally {
              setStateDialog(() { loading = false; });
            }
          }

          // initial load
          if (items.isEmpty && !loading) loadPage();

          return AlertDialog(
            title: const Text('Parts Registry'),
            content: SizedBox(
              width: 720,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search parts...'),
                    onChanged: (v) { q = v.trim(); },
                    onSubmitted: (_) => loadPage(reset: true),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: loading && items.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.separated(
                            itemCount: items.length + (hasMore ? 1 : 0),
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (c, i) {
                              if (i >= items.length) {
                                // load more
                                if (!loading) loadPage();
                                return const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              final it = items[i];
                              final pn = (it['part_number'] ?? it['part'] ?? it['sku'] ?? '').toString();
                              final qty = (it['total_units'] ?? it['units'] ?? '').toString();
                              return ListTile(
                                title: Text(pn.isEmpty ? '(no part)' : pn),
                                subtitle: Text('Units: $qty'),
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  _partCtrl.text = pn;
                                  _searchPart();
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
          );
        });
      },
    );
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

  Future<void> _fetchWplsRegistry({String q = '', int limit = 1000, int offset = 0}) async {
    setState(() {
      _wplsRegistryLoading = true;
      _wplsRegistryError = null;
    });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final enc = Uri.encodeQueryComponent(q);
      final path = '/amz/inventory/wpls?q=$enc&limit=$limit&offset=$offset';
      final res = await api.client.get(path);
      if (res.ok) {
        final body = res.body;
        List<dynamic> list = [];
        if (body is Map && body['results'] is List) list = body['results'];
        else if (body is List) list = body;
        setState(() {
          _wplsRegistry = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        });
      } else {
        setState(() => _wplsRegistryError = res.error ?? 'Failed to load WPLs registry');
      }
    } catch (e) {
      setState(() => _wplsRegistryError = e.toString());
    } finally {
      setState(() => _wplsRegistryLoading = false);
    }
  }

  Future<void> _showWplsRegistry() async {
    final api = Provider.of<ApiService>(context, listen: false);
    String q = '';
    int limit = 50;
    int offset = 0;
    List<Map<String, dynamic>> items = [];
    bool loading = false;
    bool hasMore = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setStateDialog) {
          Future<void> loadPage({bool reset = false}) async {
            if (loading) return;
            setStateDialog(() { loading = true; });
            try {
              if (reset) {
                offset = 0;
                items = [];
                hasMore = true;
              }
              final enc = Uri.encodeQueryComponent(q);
              final path = '/amz/inventory/wpls?q=$enc&limit=$limit&offset=$offset';
              final res = await api.client.get(path);
              if (res.ok) {
                final body = res.body;
                List<dynamic> list = [];
                if (body is Map && body['results'] is List) list = body['results'];
                else if (body is List) list = body;
                final fetched = list.whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
                items.addAll(fetched);
                offset += fetched.length;
                if (fetched.length < limit) hasMore = false;
              } else {
                hasMore = false;
              }
            } catch (_) {
              hasMore = false;
            } finally {
              setStateDialog(() { loading = false; });
            }
          }

          if (items.isEmpty && !loading) loadPage();

          return AlertDialog(
            title: const Text('WPLs Registry'),
            content: SizedBox(
              width: 720,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search WPLs...'),
                    onChanged: (v) { q = v.trim(); },
                    onSubmitted: (_) => loadPage(reset: true),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: loading && items.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.separated(
                            itemCount: items.length + (hasMore ? 1 : 0),
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (c, i) {
                              if (i >= items.length) {
                                if (!loading) loadPage();
                                return const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              final it = items[i];
                              final id = (it['wpl_id'] ?? it['pallet_id'] ?? it['id'] ?? '').toString();
                              final qty = (it['total_units'] ?? it['units'] ?? '').toString();
                              return ListTile(
                                title: Text(id.isEmpty ? '(no id)' : id),
                                subtitle: Text('Units: $qty'),
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  _wplCtrl.text = id;
                                  _searchWpl();
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
          );
        });
      },
    );
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

  Widget _buildRegistryTable(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const Center(child: Text('No items'));
    final mobile = MediaQuery.of(context).size.width < 720;
    if (mobile) {
      // compact list for mobile
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (c, i) {
          final it = items[i];
          final pn = (it['part_number'] ?? it['part'] ?? it['sku'] ?? it['wpl_id'] ?? it['id'] ?? '').toString();
          final qty = (it['total_units'] ?? it['units'] ?? '').toString();
          return ListTile(
            title: Text(pn.isEmpty ? '(no id)' : pn),
            subtitle: qty.isEmpty ? null : Text('Units: $qty'),
            onTap: () {
              // on mobile, fill corresponding search depending on available keys
              if (it.containsKey('part_number') || it.containsKey('part') || it.containsKey('sku')) {
                _partCtrl.text = pn;
                _searchPart();
              } else {
                _wplCtrl.text = pn;
                _searchWpl();
              }
            },
          );
        },
      );
    }

    // desktop/tablet: full table
    // Collect keys
    final keys = <String>{};
    for (final it in items) keys.addAll(it.keys.map((k) => k.toString()));
    final cols = keys.toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: cols.map((c) => DataColumn(label: Text(c))).toList(),
        rows: items.map((row) {
          return DataRow(
            cells: cols.map((c) {
              final v = row[c];
              return DataCell(Text(v == null ? '' : v.toString()));
            }).toList(),
          );
        }).toList(),
      ),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_partResult != null)
                      SizedBox(height: 240, child: Card(child: _buildKeyValueList(_partResult!)))
                    else
                      const SizedBox.shrink(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Parts Registry', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        if (_partsRegistryLoading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Refresh parts registry',
                          onPressed: _partsRegistryLoading ? null : () => _fetchPartsRegistry(),
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _partsRegistryLoading
                          ? const Center(child: CircularProgressIndicator())
                          : (_partsRegistryError != null
                              ? Center(child: Text(_partsRegistryError!))
                              : _buildRegistryTable(_partsRegistry)),
                    ),
                  ],
                ),
              ),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_wplResult != null)
                      SizedBox(height: 240, child: Card(child: Padding(padding: const EdgeInsets.all(8), child: _buildWplView(_wplResult!))))
                    else
                      const SizedBox.shrink(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('WPLs Registry', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        if (_wplsRegistryLoading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Refresh WPLs registry',
                          onPressed: _wplsRegistryLoading ? null : () => _fetchWplsRegistry(),
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _wplsRegistryLoading
                          ? const Center(child: CircularProgressIndicator())
                          : (_wplsRegistryError != null
                              ? Center(child: Text(_wplsRegistryError!))
                              : _buildRegistryTable(_wplsRegistry)),
                    ),
                  ],
                ),
              ),
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
