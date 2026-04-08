import 'dart:async';
import 'dart:io';
// no convert import needed

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';

class HistorialCambiosSerialScreen extends StatefulWidget {
  final String? initialSearch;
  const HistorialCambiosSerialScreen({super.key, this.initialSearch});

  static const routeName = '/serials/serial-changes';

  @override
  State<HistorialCambiosSerialScreen> createState() =>
      _HistorialCambiosSerialScreenState();
}

class _HistorialCambiosSerialScreenState
    extends State<HistorialCambiosSerialScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _limitCtrl = TextEditingController(
    text: '1000000',
  );
  bool _loading = false;
  String _searchFilter = 'serial'; // 'serial', 'nr_orden', 'nr_box'
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
      final term = _searchCtrl.text.trim();
      final limit = int.tryParse(_limitCtrl.text.trim()) ?? 1000000;

      String url;
      if (term.isEmpty) {
        url = '/serials/serial-changes?limit=$limit';
      } else {
        final enc = Uri.encodeQueryComponent(term);
        // "search" endpoint expects filtering params
        url = '/serials/serial-changes/search?$_searchFilter=$enc&limit=$limit';
      }

      final res = await client.get(url);
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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
    // Normalize several possible backend shapes to a List<Map>
    if (body is List) {
      return body
          .whereType<Map>()
          .map((e) => _normalizePrinterEntry(Map<String, dynamic>.from(e)))
          .toList();
    }

    if (body is Map) {
      for (final key in ['results', 'printers', 'data']) {
        if (body[key] is List) {
          return (body[key] as List)
              .whereType<Map>()
              .map((e) => _normalizePrinterEntry(Map<String, dynamic>.from(e)))
              .toList();
        }
      }

      for (final v in body.values) {
        if (v is List) {
          return v
              .whereType<Map>()
              .map((e) => _normalizePrinterEntry(Map<String, dynamic>.from(e)))
              .toList();
        }
      }

      if (kDebugMode) {
        try {
          debugPrint(
            'Unexpected printers response shape: ${body.runtimeType} -> $body',
          );
        } catch (_) {}
      }
    }
    return [];
  }

  Map<String, dynamic> _normalizePrinterEntry(Map<String, dynamic> e) {
    String? id;
    try {
      id = (e['id_printer'] ?? e['id'] ?? e['printer_id'] ?? e['idPrinter'])
          ?.toString();
    } catch (_) {
      id = null;
    }
    String? name;
    try {
      name = (e['printer_name'] ?? e['name'] ?? e['printerName'])?.toString();
    } catch (_) {
      name = null;
    }
    String? ip;
    try {
      ip =
          (e['ip_address'] ??
                  e['ip'] ??
                  e['address'] ??
                  e['ip_address']?.toString())
              ?.toString();
    } catch (_) {
      ip = null;
    }
    final out = <String, dynamic>{};
    if (id != null && id.isNotEmpty) out['id_printer'] = int.tryParse(id) ?? id;
    if (name != null) out['printer_name'] = name;
    if (ip != null) out['ip_address'] = ip;
    for (final kv in e.entries) {
      if (!out.containsKey(kv.key)) out[kv.key.toString()] = kv.value;
    }
    return out;
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
      if (body is! List<int>) {
        throw Exception('Respuesta de exportación inesperada (no-binaria)');
      }

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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error exportando: $e')));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error SFTP: $e')));
      }
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
        if (first['id_printer'] != null) {
          payload['printer_id'] = first['id_printer'];
        } else if (first['ip_address'] != null)
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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
        if (selectedPrinter!['id_printer'] != null) {
          payload['printer_id'] = selectedPrinter!['id_printer'];
        } else if (selectedPrinter!['ip_address'] != null)
          payload['printer_ip'] = selectedPrinter!['ip_address'];
      } else if (printers.isNotEmpty) {
        final first = printers.first;
        if (first['id_printer'] != null) {
          payload['printer_id'] = first['id_printer'];
        } else if (first['ip_address'] != null)
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error imprimiendo caja: $error')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error borrando orden: $e')));
      }
    }
  }

  Future<void> _deleteBox(
    String boxNum,
    List<Map<String, dynamic>> regs,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Borrar caja $boxNum'),
        content: Text(
          '¿Confirmas borrar todos los registros (${regs.length}) de la caja "$boxNum"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Borrar Caja'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Borrados $succeeded registros de la caja $boxNum; $failures fallidos.',
          ),
        ),
      );
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error borrando caja: $e')),
        );
      }
    }
  }

  // OverlayEntry? _edgeOverlay; // REMOVED: Causing navigation leaks

  @override
  void initState() {
    super.initState();
    if (widget.initialSearch != null) {
      _searchCtrl.text = widget.initialSearch!;
      _searchFilter = 'nr_orden';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      // Overlay logic removed to prevent sidebar state leaks
    });
  }

  @override
  void dispose() {
    // _edgeOverlay?.remove(); // REMOVED
    // _edgeOverlay = null; // REMOVED
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
    // Premium Dark Theme Colors
    const kBgDark = Color(0xFF0F172A); // Slate 900
    const kBgLight = Color(0xFF1E293B); // Slate 800
    const kAccent = Color(0xFF06B6D4); // Cyan 500
    const kSurface = Color(0xFF334155); // Slate 700

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'HISTORIAL DE CAMBIO DE SERIAL',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        elevation: 0,
        backgroundColor: kBgDark.withOpacity(0.8),
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kBgDark.withOpacity(0.9), Colors.transparent],
            ),
          ),
        ),
      ),
      backgroundColor: kBgDark, // Fallback
      body: Stack(
        children: [
          // 1) Background Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [kBgDark, Color(0xFF111827), Color(0xFF000000)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // 2) Content
          SafeArea(
            child: Column(
              children: [
                _buildPremiumFilterBar(kSurface, kAccent),
                Expanded(
                  child: _rows.isEmpty && !_loading
                      ? _buildEmptyState(kSurface)
                      : _loading && _rows.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(color: kAccent),
                        )
                      : _buildPremiumList(kBgLight, kSurface, kAccent),
                ),
              ],
            ),
          ),
          // 3) Sidebar Handle
          Positioned(
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
                  currentRoute: HistorialCambiosSerialScreen.routeName,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumFilterBar(Color surfaceColor, Color accentColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: surfaceColor.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Filter Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _searchFilter,
                dropdownColor: surfaceColor,
                icon: Icon(Icons.tune, color: accentColor.withOpacity(0.8)),
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: 'serial', child: Text('Serial')),
                  DropdownMenuItem(value: 'nr_orden', child: Text('Orden')),
                  DropdownMenuItem(value: 'nr_box', child: Text('Caja')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _searchFilter = val);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Search Field
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar...',
                hintStyle: TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.black26,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search, color: Colors.white54),
                  onPressed: _refresh,
                  splashRadius: 20,
                ),
              ),
              onSubmitted: (_) => _refresh(),
            ),
          ),
          const SizedBox(width: 12),
          // Limit
          SizedBox(
            width: 80,
            child: TextField(
              controller: _limitCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Limit',
                labelStyle: TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.black26,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _refresh(),
            ),
          ),
          const SizedBox(width: 12),
          // Refresh Button
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accentColor,
                    ),
                  )
                : Icon(Icons.refresh, color: accentColor),
            tooltip: 'Refrescar',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black26,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color surfaceColor) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_toggle_off, size: 60, color: Colors.white12),
          const SizedBox(height: 16),
          Text(
            'Sin registros encontrados',
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumList(
    Color cardColor,
    Color surfaceColor,
    Color accentColor,
  ) {
    final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final r in _rows) {
      final ord = (r['nr_orden'] ?? '').toString();
      final box = (r['nr_box'] ?? '').toString();
      grouped.putIfAbsent(ord, () => {});
      grouped[ord]!.putIfAbsent(box, () => []);
      grouped[ord]![box]!.add(r);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: grouped.length,
      itemBuilder: (ctx, i) {
        final ordKey = grouped.keys.elementAt(i);
        final boxes = grouped[ordKey]!;
        final totalRegs = boxes.values.fold<int>(0, (s, l) => s + l.length);
        final displayOrd = ordKey.isEmpty ? 'Sin Orden' : ordKey;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: surfaceColor.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            key: PageStorageKey('order-$ordKey'),
            collapsedBackgroundColor: Colors.transparent,
            backgroundColor: Colors.black12,
            iconColor: accentColor,
            collapsedIconColor: Colors.white70,
            textColor: accentColor,
            collapsedTextColor: Colors.white,
            shape: const Border(), // Removes internal borders
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    size: 20,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayOrd,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '$totalRegs registros en ${boxes.length} cajas',
                        style: TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionIcon(
                  Icons.download_rounded,
                  'Exportar',
                  () => _exportOrder(ordKey),
                ),
                _buildActionIcon(
                  Icons.cloud_upload_rounded,
                  'SFTP',
                  () => _uploadOrderToSftp(ordKey),
                ),
                const SizedBox(width: 4),
                _buildActionIcon(
                  Icons.delete_forever_rounded,
                  'Borrar',
                  () => _deleteOrder(
                    ordKey,
                    boxes.values.expand((e) => e).toList(),
                  ),
                  color: Colors.redAccent,
                ),
              ],
            ),
            children: boxes.entries.map((boxEntry) {
              final boxNum = boxEntry.key.isEmpty ? 'N/A' : boxEntry.key;
              final regs = boxEntry.value;
              return _buildBoxTile(
                ordKey,
                boxNum,
                regs,
                surfaceColor,
                accentColor,
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildActionIcon(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    Color? color,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      color: color ?? Colors.white70,
      tooltip: tooltip,
      onPressed: onTap,
      splashRadius: 24,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildBoxTile(
    String ordKey,
    String boxNum,
    List<Map<String, dynamic>> regs,
    Color surfaceColor,
    Color accentColor,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.5), // Darker inner
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: accentColor, width: 3)),
      ),
      child: ExpansionTile(
        key: PageStorageKey('order-$ordKey-box-$boxNum'),
        shape: const Border(),
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white38,
        title: Row(
          children: [
            const Icon(Icons.inbox, size: 16, color: Colors.white54),
            const SizedBox(width: 8),
            Text(
              'Box $boxNum',
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${regs.length}',
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.print, size: 18),
              color: Colors.white70,
              onPressed: () => _printBox(ordKey, boxNum, regs),
              tooltip: 'Imprimir Caja',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: Colors.redAccent.withOpacity(0.7),
              onPressed: () => _deleteBox(boxNum, regs),
              tooltip: 'Borrar Caja',
            ),
          ],
        ),
        children: regs.map((r) => _buildRecordRow(r)).toList(),
      ),
    );
  }

  Widget _buildRecordRow(Map<String, dynamic> r) {
    final oldS = r['serial_old']?.toString() ?? '-';
    final newS = r['serial_new']?.toString() ?? '-';
    // Style differently if null or changes
    final bool changed = oldS != newS;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.02))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SKU / ID
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r['nr_sku'] ?? 'NO-SKU',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(r['fecha']),
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
          // Serials
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        oldS,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 10,
                        color: Colors.white24,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        newS,
                        style: TextStyle(
                          color: changed ? Colors.greenAccent : Colors.white,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (r['usuario'] != null)
                  Text(
                    'User: ${r['usuario']}',
                    style: const TextStyle(color: Colors.white24, fontSize: 10),
                  ),
              ],
            ),
          ),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSmallAction(
                Icons.print,
                Colors.white38,
                () => _printRow(r),
              ),
              const SizedBox(width: 8),
              _buildSmallAction(Icons.edit, Colors.white38, () => _editRow(r)),
              const SizedBox(width: 8),
              _buildSmallAction(
                Icons.close,
                Colors.redAccent.withOpacity(0.5),
                () => _deleteRow((r['id'] as num).toInt()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallAction(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
