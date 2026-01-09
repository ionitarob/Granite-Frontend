import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';

class XiaomiHistoricoPage extends StatefulWidget {
  const XiaomiHistoricoPage({super.key});

  @override
  State<XiaomiHistoricoPage> createState() => _XiaomiHistoricoPageState();
}

class _XiaomiHistoricoPageState extends State<XiaomiHistoricoPage> {
  final _terminoController = TextEditingController();
  String filtroTiempo = 'dia';
  String operarioSeleccionado = 'Selecciona un valor';
  DateTime? fechaDesde;
  DateTime? fechaHasta;
  bool ignorarFechas = false;

  bool loading = false;
  List<dynamic> records = [];
  Map<String, dynamic> summary = {};
  List<String> operarios = [];

  Future<void> fetchHistorico() async {
    setState(() => loading = true);

    final params = <String, String>{};

    if (!ignorarFechas) {
      if (fechaDesde != null) {
        params['fecha_desde'] = fechaDesde!.toIso8601String().split('T').first;
      }
      if (fechaHasta != null) {
        params['fecha_hasta'] = fechaHasta!.toIso8601String().split('T').first;
      }
    }

    params['filtro_tiempo'] = filtroTiempo;
    if (operarioSeleccionado != 'Selecciona un valor') {
      params['operario'] = operarioSeleccionado;
    }
    if (_terminoController.text.isNotEmpty) {
      params['termino_busqueda'] = _terminoController.text;
    }
    if (ignorarFechas) {
      params['ignorar_fechas'] = 'on';
    }

    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final path = '/xiaomieco/historico?$queryString';

    try {
      final api = ApiService.instance?.client;
      if (api == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: API no disponible')),
        );
        return;
      }

      final resp = await api.get(path);
      if (!resp.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('HTTP ${resp.statusCode}: ${resp.error ?? 'Error'}'),
          ),
        );
        return;
      }

      final decoded = resp.body;
      if (decoded == null || decoded is! Map) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Formato de respuesta no soportado')),
        );
        return;
      }

      final rawRecords = decoded['records'];
      final rawSummary = decoded['summary'];
      final rawOperarios = decoded['operarios'];

      final parsedOperarios = <String>[];
      if (rawOperarios is List) {
        for (final o in rawOperarios) {
          parsedOperarios.add(
            o == null || (o is String && o.trim().isEmpty)
                ? '(Sin nombre)'
                : o.toString(),
          );
        }
      }

      setState(() {
        records = rawRecords is List ? rawRecords : [];
        summary = rawSummary is Map<String, dynamic> ? rawSummary : {};
        operarios = parsedOperarios
            .toSet()
            .toList(); // sin el valor por defecto duplicado
        if (![
          'Selecciona un valor',
          ...operarios,
        ].contains(operarioSeleccionado)) {
          operarioSeleccionado = 'Selecciona un valor';
        }
      });
    } catch (e, st) {
      debugPrint('fetchHistorico error: $e\n$st');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error procesando datos: $e')));
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _pickFechaDesde() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaDesde ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => fechaDesde = picked);
    }
  }

  Future<void> _pickFechaHasta() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaHasta ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => fechaHasta = picked);
    }
  }

  @override
  void initState() {
    super.initState();
    fetchHistorico();
  }

  Future<void> _showNotFinishedCesb() async {
    // show a loading indicator while fetching
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final api = ApiService.instance?.client;
      if (api == null) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: API no disponible')));
        return;
      }

      final resp = await api.get('/xiaomieco/not_finished_cesb');
      Navigator.of(context).pop(); // remove loading

      if (!resp.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('HTTP ${resp.statusCode}: ${resp.error ?? 'Error'}')),
        );
        return;
      }

      final decoded = resp.body;
      if (decoded == null || decoded is! Map || decoded['not_finished'] is! List) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Formato de respuesta no soportado')),
        );
        return;
      }

      final List items = decoded['not_finished'] as List;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('CESB no finalizados'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: items.isEmpty
                ? const Center(child: Text('No hay CESB pendientes'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, i) {
                      final r = items[i];
                      String _val(dynamic v) => (v == null || (v is String && v.trim().isEmpty)) ? '-' : v.toString();
                      String _openDate(dynamic v) {
                        if (v == null) return '-';
                        try {
                          final parsed = DateTime.parse(v.toString()).toLocal();
                          return parsed.toString().split('.').first; // YYYY-MM-DD HH:MM:SS
                        } catch (_) {
                          return v.toString();
                        }
                      }

                      return ListTile(
                        title: Text('${_val(r['cesb'])} / ${_val(r['sku'])}'),
                        subtitle: Text('P/N: ${_val(r['partn'])} • Qty: ${_val(r['qty'])} • Cartons: ${_val(r['cartons'])}'),
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Operario: ${_val(r['operario'])}'),
                            const SizedBox(height: 4),
                            Text('Abierto: ${_openDate(r['fecha_hora_registro'])}', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
          ],
        ),
      );
    } catch (e, st) {
      Navigator.of(context).pop();
      debugPrint('fetch not_finished_cesb error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error procesando datos: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Histórico de Etiquetado'),
      ),
      body: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: EdgeNavHandle(user: ApiService.instance?.currentUser),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                // Filtros
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            DropdownButton<String>(
                              value: filtroTiempo,
                              items: const [
                                DropdownMenuItem(
                                  value: 'dia',
                                  child: Text('Día específico'),
                                ),
                                DropdownMenuItem(
                                  value: 'mes',
                                  child: Text('Mes completo'),
                                ),
                                DropdownMenuItem(
                                  value: 'año',
                                  child: Text('Año completo'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => filtroTiempo = v);
                              },
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: _pickFechaDesde,
                              child: Text(
                                fechaDesde != null
                                    ? 'Desde: ${fechaDesde!.toLocal().toIso8601String().split('T').first}'
                                    : 'Seleccionar fecha desde',
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (filtroTiempo == 'dia')
                              ElevatedButton(
                                onPressed: _pickFechaHasta,
                                child: Text(
                                  fechaHasta != null
                                      ? 'Hasta: ${fechaHasta!.toLocal().toIso8601String().split('T').first}'
                                      : 'Seleccionar fecha hasta',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButton<String>(
                                value: operarioSeleccionado,
                                isExpanded: true,
                                items: ['Selecciona un valor', ...operarios]
                                    .map(
                                      (o) => DropdownMenuItem(
                                        value: o,
                                        child: Text(o),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null)
                                    setState(() => operarioSeleccionado = v);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _terminoController,
                                decoration: const InputDecoration(
                                  labelText: 'Búsqueda general',
                                  hintText:
                                      'CESB / SKU / Part Number / Qty / Carton',
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Checkbox(
                              value: ignorarFechas,
                              onChanged: (v) {
                                if (v != null)
                                  setState(() => ignorarFechas = v);
                              },
                            ),
                            const Text('Ignorar fechas'),
                            const Spacer(),
                            ElevatedButton(
                              onPressed: fetchHistorico,
                              child: const Text('Buscar'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _showNotFinishedCesb,
                              child: const Text('No finalizados'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  filtroTiempo = 'dia';
                                  operarioSeleccionado = 'Selecciona un valor';
                                  fechaDesde = null;
                                  fechaHasta = null;
                                  _terminoController.clear();
                                  ignorarFechas = false;
                                });
                                fetchHistorico();
                              },
                              child: const Text('Limpiar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Resumen
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Total CESB: ${summary['total_cesb'] ?? 0}',
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Total Qty: ${summary['total_qty'] ?? 0}',
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Total Cartons: ${summary['total_cartons'] ?? 0}',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Lista
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : records.isEmpty
                      ? const Center(
                          child: Text(
                            'No se encontraron registros con los filtros aplicados',
                          ),
                        )
                      : ListView.builder(
                          itemCount: records.length,
                          itemBuilder: (context, i) {
                            final r = records[i];
                            if (r == null) {
                              return const ListTile(
                                title: Text('Registro nulo'),
                                subtitle: Text(
                                  'Este registro no contiene datos.',
                                ),
                                leading: Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.orange,
                                ),
                              );
                            }
                            if (r is! Map) {
                              return ListTile(
                                title: const Text('Formato desconocido'),
                                subtitle: Text(r.toString()),
                                leading: const Icon(Icons.help_outline),
                              );
                            }

                            String _val(dynamic v) =>
                                (v == null || (v is String && v.trim().isEmpty))
                                ? '-'
                                : v.toString();

                            return ListTile(
                              title: Text(
                                '${_val(r['cesb'])} / ${_val(r['sku'])}',
                              ),
                              subtitle: Text(
                                'P/N: ${_val(r['partn'])} • Qty: ${_val(r['qty'])} • Cartons: ${_val(r['cartons'])}',
                              ),
                              trailing: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Operario: ${_val(r['operario'])}'),
                                  Text('Fecha: ${_val(r['fecha_hora_fin'])}'),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
