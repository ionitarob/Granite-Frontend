import 'dart:async';
import 'dart:io';
// no convert import needed

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';

class HistorialCambiosSerialScreen extends StatefulWidget {
  const HistorialCambiosSerialScreen({super.key});

  static const routeName = '/serials/serial-changes';

  @override
  State<HistorialCambiosSerialScreen> createState() =>
      _HistorialCambiosSerialScreenState();
}

class _HistorialCambiosSerialScreenState
    extends State<HistorialCambiosSerialScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _limitCtrl = TextEditingController(text: '1000');
  bool _loading = false;
  List<Map<String, dynamic>> _rows = [];

  ApiClient? _clientOrNull() {
    final svc = ApiService.instance;
    if (svc != null) return svc.client;
    try {
      return Provider.of<ApiService>(context, listen: false).client;
    } catch (_) {
      return null;
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final client = _clientOrNull();
      if (client == null) throw Exception('Servicio API no disponible');
      final q = Uri.encodeQueryComponent(_searchCtrl.text.trim());
      final limit = int.tryParse(_limitCtrl.text.trim()) ?? 1000;
      final res = await client.get('/serials/serial-changes?q=$q&limit=$limit');
      if (!mounted) return;
      if (!res.ok) throw Exception('Error fetching (${res.statusCode})');
      final body = res.body;
      List<Map<String, dynamic>> list = [];
      if (body is Map && body['results'] is List) {
        list = (body['results'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (body is List) {
        list = body
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      setState(() => _rows = list);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteRow(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirmar borrado'),
        content: const Text(
          '¿Eliminar registro? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final client = _clientOrNull();
      if (client == null) throw Exception('Servicio API no disponible');
      final res = await client.delete('/serials/serial-changes/$id');
      if (!mounted) return;
      if (!res.ok) throw Exception('Error borrando (${res.statusCode})');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Registro eliminado')));
      await _refresh();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _editRow(Map<String, dynamic> row) async {
    final map = Map<String, TextEditingController>.fromEntries(
      [
        'nr_orden',
        'nr_sku',
        'nr_unidades',
        'tipo_etiqueta',
        'fecha_creacion',
        'usuario',
        'tipo_etiqueta_id',
        'nr_box',
        'nr_unidades_box',
        'serial_old',
        'serial_new',
        'fecha_finalizacion',
      ].map(
        (k) => MapEntry(
          k,
          TextEditingController(text: (row[k]?.toString() ?? '')),
        ),
      ),
    );

    final save = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Editar registro #${row['id'] ?? ''}'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: map.entries
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: TextField(
                        controller: e.value,
                        decoration: InputDecoration(labelText: e.key),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    // dispose controllers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final ctrl in map.values) {
        try {
          ctrl.dispose();
        } catch (_) {}
      }
    });

    if (save != true) return;
    try {
      final client = _clientOrNull();
      if (client == null) throw Exception('Servicio API no disponible');
      final payload = <String, dynamic>{};
      for (final entry in map.entries) {
        final v = entry.value.text.trim();
        if (v.isNotEmpty) payload[entry.key] = v;
      }
      final id = row['id'];
      if (id == null) throw Exception('Row has no id');
      final res = await client.put(
        '/serials/serial-changes/$id',
        jsonBody: payload,
      );
      if (!mounted) return;
      if (!res.ok) throw Exception('Error actualizando (${res.statusCode})');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Registro actualizado')));
      await _refresh();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPrinters({
    String q = '',
    int limit = 1000,
  }) async {
    final client = _clientOrNull();
    if (client == null) throw Exception('Servicio API no disponible');
    final encoded = Uri.encodeQueryComponent(q.trim());
    final res = await client.get('/serials/printers?q=$encoded&limit=$limit');
    if (!res.ok) throw Exception('Error fetching printers (${res.statusCode})');
    final body = res.body;
    if (body is Map && body['results'] is List) {
      return (body['results'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } else if (body is List) {
      return body
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  Future<void> _exportOrder(String orden) async {
    try {
      final client = _clientOrNull();
      if (client == null) throw Exception('Servicio API no disponible');
      final enc = Uri.encodeQueryComponent(orden);
      // Use getBytes to request raw bytes so ApiClient won't attempt JSON decoding.
      final res = await client.getBytes(
        '/serials/export-serial-changes?nr_orden=$enc',
      );
      if (!mounted) return;
      if (!res.ok) throw Exception('Error exportando (${res.statusCode})');

      // Expect raw bytes in res.body
      final body = res.body;
      if (body is! List<int>)
        throw Exception('Respuesta de exportación inesperada (no-binaria)');

      // Prefer filename from Content-Disposition if provided
      String fileName;
      try {
        final cd = res.headers?['content-disposition'] ?? '';
        final m = RegExp(
          r'filename\*?=(?:UTF-8'
          ""
          ')?"?([^";]+)"?',
          caseSensitive: false,
        ).firstMatch(cd);
        if (m != null && m.groupCount >= 1) {
          fileName = Uri.decodeFull(m.group(1)!.replaceAll(RegExp(r'"'), ''));
        } else {
          final timestamp = DateTime.now().toIso8601String().replaceAll(
            ':',
            '-',
          );
          fileName =
              'export-serial-changes-${orden.isNotEmpty ? orden : 'all'}-$timestamp.xlsx';
        }
      } catch (_) {
        final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
        fileName =
            'export-serial-changes-${orden.isNotEmpty ? orden : 'all'}-$timestamp.xlsx';
      }

      final tmp = Directory.systemTemp;
      final file = File('${tmp.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(body);

      // Try to open the exported file automatically.
      var opened = false;
      try {
        if (Platform.isWindows) {
          // Use cmd /c start "" "file"
          await Process.run('cmd', ['/c', 'start', '', file.path]);
          opened = true;
        } else if (Platform.isMacOS) {
          await Process.run('open', [file.path]);
          opened = true;
        } else {
          // Assume Linux
          await Process.run('xdg-open', [file.path]);
          opened = true;
        }
      } catch (_) {
        opened = false;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Exportado a: ${file.path}${opened ? ' (abierto)' : ''}',
          ),
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error exportando: $e')));
    }
  }

  Future<void> _uploadOrderToSftp(String orden) async {
    try {
      final client = _clientOrNull();
      if (client == null) throw Exception('Servicio API no disponible');

      final res = await client.post(
        '/serials/finish-order-upload',
        jsonBody: {'nr_orden': orden},
      );

      if (!mounted) return;
      if (res.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Archivo enviado a SFTP correctamente')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar SFTP: ${res.statusCode}')),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error SFTP: $e')));
    }
  }

  Future<void> _printRow(Map<String, dynamic> row) async {
    try {
      final client = _clientOrNull();
      if (client == null) throw Exception('Servicio API no disponible');

      // Fetch printers first
      List<Map<String, dynamic>> printers = [];
      String? manualIp;
      try {
        printers = await _fetchPrinters();
      } catch (_) {
        printers = [];
      }

      Map<String, dynamic>? selectedPrinter;
      final txtIp = TextEditingController();

      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Seleccionar impresora'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (printers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'No se encontraron impresoras en el servidor. Puedes introducir una IP manualmente.',
                    ),
                  )
                else
                  Column(
                    children: printers
                        .map(
                          (p) => RadioListTile<Map<String, dynamic>>(
                            value: p,
                            groupValue: selectedPrinter,
                            title: Text(
                              p['printer_name']?.toString() ??
                                  p['ip_address']?.toString() ??
                                  'Impresora',
                            ),
                            subtitle: Text(p['ip_address']?.toString() ?? ''),
                            onChanged: (v) {
                              selectedPrinter = v;
                              // rebuild dialog
                              (c as Element).markNeedsBuild();
                            },
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: txtIp,
                  decoration: const InputDecoration(
                    labelText:
                        'IP de impresora (opcional, sobreescribe selección)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Imprimir'),
            ),
          ],
        ),
      );

      txtIp.dispose();
      if (ok != true) return;

      manualIp = txtIp.text.trim().isNotEmpty ? txtIp.text.trim() : null;

      final payload = <String, dynamic>{};
      if (manualIp != null) {
        payload['printer_ip'] = manualIp;
      } else if (selectedPrinter != null) {
        // prefer id if available
        if (selectedPrinter!['id_printer'] != null) {
          payload['printer_id'] = selectedPrinter!['id_printer'];
        } else if (selectedPrinter!['ip_address'] != null) {
          payload['printer_ip'] = selectedPrinter!['ip_address'];
        }
      } else if (printers.isNotEmpty) {
        // if user didn't explicitly select but printers exist, pick first
        final first = printers.first;
        if (first['id_printer'] != null)
          payload['printer_id'] = first['id_printer'];
        else if (first['ip_address'] != null)
          payload['printer_ip'] = first['ip_address'];
      } else {
        throw Exception('No printer selected or provided');
      }

      // Compose payload from row (single-record printing)
      payload['data'] = row['nr_box']?.toString() ?? '';
      payload['orden'] = row['nr_orden']?.toString() ?? '';
      final total = int.tryParse(row['nr_unidades']?.toString() ?? '') ?? 1;
      payload['total_serials'] = total;
      payload['ean'] = row['ean']?.toString() ?? '';
      // Use nested lists as expected by backend (batches)
      final snNew = row['serial_new']?.toString() ?? '';
      final snOld = row['serial_old']?.toString() ?? '';
      payload['sn_batches'] = [
        [snNew],
      ];
      payload['serial_batches'] = [
        [snOld],
      ];
      payload['label_counter'] = 1;

      // send
      final res = await client.post(
        '/serials/print-serial-change',
        jsonBody: payload,
      );
      if (!mounted) return;
      if (res.ok) {
        final body = res.body;
        String msg = 'Impresión enviada';
        if (body is Map && body['printed'] != null) {
          msg = 'Impresos: ${body['printed']}';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      } else {
        final error = res.body is Map
            ? (res.body['error']?.toString() ?? res.error ?? 'Error')
            : (res.error ?? 'Error');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error imprimiendo: $error')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _printBox(
    String orden,
    String boxNumber,
    List<Map<String, dynamic>> regs,
  ) async {
    try {
      final client = _clientOrNull();
      if (client == null) throw Exception('Servicio API no disponible');

      // select printer
      List<Map<String, dynamic>> printers = [];
      try {
        printers = await _fetchPrinters();
      } catch (_) {
        printers = [];
      }

      Map<String, dynamic>? selectedPrinter;
      final txtIp = TextEditingController();

      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Seleccionar impresora para la caja'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (printers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'No se encontraron impresoras en el servidor. Puedes introducir una IP manualmente.',
                    ),
                  )
                else
                  Column(
                    children: printers
                        .map(
                          (p) => RadioListTile<Map<String, dynamic>>(
                            value: p,
                            groupValue: selectedPrinter,
                            title: Text(
                              p['printer_name']?.toString() ??
                                  p['ip_address']?.toString() ??
                                  'Impresora',
                            ),
                            subtitle: Text(p['ip_address']?.toString() ?? ''),
                            onChanged: (v) {
                              selectedPrinter = v;
                              (c as Element).markNeedsBuild();
                            },
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: txtIp,
                  decoration: const InputDecoration(
                    labelText:
                        'IP de impresora (opcional, sobreescribe selección)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Imprimir'),
            ),
          ],
        ),
      );

      txtIp.dispose();
      if (ok != true) return;
      final manualIp = txtIp.text.trim().isNotEmpty ? txtIp.text.trim() : null;

      final payload = <String, dynamic>{};
      if (manualIp != null) {
        payload['printer_ip'] = manualIp;
      } else if (selectedPrinter != null) {
        if (selectedPrinter!['id_printer'] != null)
          payload['printer_id'] = selectedPrinter!['id_printer'];
        else if (selectedPrinter!['ip_address'] != null)
          payload['printer_ip'] = selectedPrinter!['ip_address'];
      } else if (printers.isNotEmpty) {
        final first = printers.first;
        if (first['id_printer'] != null)
          payload['printer_id'] = first['id_printer'];
        else if (first['ip_address'] != null)
          payload['printer_ip'] = first['ip_address'];
      } else {
        throw Exception('No printer selected or provided');
      }

      // build payload from regs
      final newSerials = regs
          .map((r) => r['serial_new']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      final oldSerials = regs
          .map((r) => r['serial_old']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      payload['data'] = boxNumber;
      payload['orden'] = orden;
      payload['total_serials'] = newSerials.length;
      payload['ean'] =
          regs.firstWhere(
            (r) => (r['ean']?.toString() ?? '').isNotEmpty,
            orElse: () => {},
          )['ean'] ??
          '';
      payload['sn_batches'] = [newSerials];
      payload['serial_batches'] = [oldSerials];
      payload['label_counter'] = 1;

      final res = await client.post(
        '/serials/print-serial-change',
        jsonBody: payload,
      );
      if (!mounted) return;
      if (res.ok) {
        final body = res.body;
        String msg = 'Impresión enviada';
        if (body is Map && body['printed'] != null)
          msg = 'Impresos: ${body['printed']}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      } else {
        final error = res.body is Map
            ? (res.body['error']?.toString() ?? res.error ?? 'Error')
            : (res.error ?? 'Error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error imprimiendo caja: $error')),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _deleteOrder(
    String orden,
    List<Map<String, dynamic>> regs,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Borrar orden $orden'),
        content: Text(
          '¿Confirmas borrar ${regs.length} registros de la orden "$orden"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final client = _clientOrNull();
      if (client == null) throw Exception('Servicio API no disponible');
      int failures = 0;
      int succeeded = 0;
      for (final r in regs) {
        try {
          final id = r['id'];
          if (id == null) {
            failures++;
            continue;
          }
          final res = await client.delete(
            '/serials/serial-changes/${(id as num).toInt()}',
          );
          if (res.ok) {
            succeeded++;
          } else {
            failures++;
          }
        } catch (_) {
          failures++;
        }
      }
      if (!mounted) return;
      if (failures == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Orden $orden borrada ($succeeded registros).'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Borrados $succeeded registros; $failures fallidos.'),
          ),
        );
      }
      await _refresh();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error borrando orden: $e')));
    }
  }

  OverlayEntry? _edgeOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
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
                    user: _clientOrNull() != null
                        ? Provider.of<ApiService>(
                            context,
                            listen: false,
                          ).currentUser
                        : null,
                    width: 28,
                    currentRoute: routeName,
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
    _searchCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  String _formatDate(dynamic v) {
    if (v == null) return '';
    try {
      final dt = v is String
          ? DateTime.tryParse(v)
          : (v is DateTime ? v : null);
      if (dt == null) return v.toString();
      return DateFormat('dd MMM yyyy HH:mm').format(dt);
    } catch (_) {
      return v.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial - Cambio de serial'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Buscar nr_orden o nr_sku',
                      ),
                      onSubmitted: (_) => _refresh(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _limitCtrl,
                      decoration: const InputDecoration(labelText: 'Límite'),
                      keyboardType: TextInputType.number,
                      onSubmitted: (_) => _refresh(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _refresh,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Refrescar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _rows.isEmpty
                        ? Center(
                            child: _loading
                                ? const CircularProgressIndicator()
                                : const Text('Sin registros'),
                          )
                        : ListView(
                            children: () {
                              // Group rows by order -> box
                              final Map<
                                String,
                                Map<String, List<Map<String, dynamic>>>
                              >
                              grouped = {};
                              for (final r in _rows) {
                                final ord = (r['nr_orden'] ?? '').toString();
                                final box = (r['nr_box'] ?? '').toString();
                                grouped.putIfAbsent(ord, () => {});
                                grouped[ord]!.putIfAbsent(box, () => []);
                                grouped[ord]![box]!.add(r);
                              }

                              return grouped.entries.map((ordEntry) {
                                final ordKey = ordEntry.key;
                                final ord = ordKey.isEmpty
                                    ? '<sin orden>'
                                    : ordKey;
                                final boxes = ordEntry.value;
                                final totalRegs = boxes.values.fold<int>(
                                  0,
                                  (s, l) => s + l.length,
                                );
                                return ExpansionTile(
                                  key: PageStorageKey('order-$ordKey'),
                                  title: Row(
                                    children: [
                                      Expanded(child: Text('Orden: $ord')),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.download_outlined,
                                        ),
                                        tooltip: 'Exportar orden',
                                        onPressed: () => _exportOrder(ordKey),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.cloud_upload_outlined,
                                        ),
                                        tooltip: 'Reenviar SFTP',
                                        onPressed: () =>
                                            _uploadOrderToSftp(ordKey),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.redAccent,
                                        ),
                                        tooltip: 'Borrar orden',
                                        onPressed: () => _deleteOrder(
                                          ordKey,
                                          boxes.values
                                              .expand((e) => e)
                                              .toList(),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${boxes.length} cajas · $totalRegs registros',
                                  ),
                                  children: boxes.entries.map((boxEntry) {
                                    final boxNum = boxEntry.key.isEmpty
                                        ? '<sin caja>'
                                        : boxEntry.key;
                                    final regs = boxEntry.value;
                                    return Card(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      child: ExpansionTile(
                                        key: PageStorageKey(
                                          'order-$ordKey-box-$boxNum',
                                        ),
                                        title: Row(
                                          children: [
                                            Expanded(
                                              child: Text('Box: $boxNum'),
                                            ),
                                            Text('${regs.length} regs'),
                                          ],
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(
                                            Icons.print_outlined,
                                          ),
                                          tooltip: 'Imprimir etiqueta de caja',
                                          onPressed: () =>
                                              _printBox(ordKey, boxNum, regs),
                                        ),
                                        children: regs.map((r) {
                                          return ListTile(
                                            title: Text(
                                              r['nr_orden']?.toString() ??
                                                  r['nr_sku']?.toString() ??
                                                  'ID ${r['id'] ?? ''}',
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'SKU: ${r['nr_sku'] ?? ''}  Box: ${r['nr_box'] ?? ''}',
                                                ),
                                                Text(
                                                  'Old: ${r['serial_old'] ?? ''} → New: ${r['serial_new'] ?? ''}',
                                                ),
                                                Text(
                                                  'Fecha: ${_formatDate(r['fecha'])}  Fin: ${_formatDate(r['fecha_finalizacion'])}',
                                                ),
                                              ],
                                            ),
                                            isThreeLine: true,
                                            trailing: Wrap(
                                              spacing: 4,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.print),
                                                  onPressed: () => _printRow(r),
                                                  tooltip: 'Imprimir registro',
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.edit),
                                                  onPressed: () => _editRow(r),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                  ),
                                                  onPressed: () => _deleteRow(
                                                    (r['id'] as num).toInt(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    );
                                  }).toList(),
                                );
                              }).toList();
                            }(),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
