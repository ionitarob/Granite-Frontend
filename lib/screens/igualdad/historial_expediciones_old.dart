import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '/src/api/igualdad_api.dart';

class HistorialExpedicionesOldScreen extends StatefulWidget {
  const HistorialExpedicionesOldScreen({Key? key}) : super(key: key);

  @override
  _HistorialExpedicionesOldScreenState createState() =>
      _HistorialExpedicionesOldScreenState();
}

class _HistorialExpedicionesOldScreenState
    extends State<HistorialExpedicionesOldScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  // gradient animation
  // gradient animation
  List<List<Color>> get _gradients => [
    [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.secondary,
    ],
    [
      Theme.of(context).colorScheme.secondary,
      Theme.of(context).colorScheme.tertiary,
    ],
    [
      Theme.of(context).colorScheme.tertiary,
      Theme.of(context).colorScheme.primary,
    ],
  ];
  int _current = 0;
  Timer? _timer;

  // scroll controllers
  final _hCtrl = ScrollController();
  final _vCtrl = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Force rebuild to update theme colors
  }

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      setState(() => _current = (_current + 1) % _gradients.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await IgualdadApi.getHistorialExpedicionesOld();
      if (!mounted) return;
      setState(() => _rows = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cargando datos: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[_current];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // moving gradient background
          AnimatedContainer(
            duration: const Duration(seconds: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // back button
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Material(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withOpacity(0.2),
                          child: IconButton(
                            icon: Icon(
                              Icons.arrow_back,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: 'Volver',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _loading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        )
                      : _rows.isEmpty
                      ? Center(
                          child: Text(
                            'No hay expediciones antiguas.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              margin: const EdgeInsets.all(16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surface.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              child: Scrollbar(
                                controller: _hCtrl,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _hCtrl,
                                  scrollDirection: Axis.horizontal,
                                  child: Scrollbar(
                                    controller: _vCtrl,
                                    thumbVisibility: true,
                                    child: SingleChildScrollView(
                                      controller: _vCtrl,
                                      scrollDirection: Axis.vertical,
                                      child: DataTable(
                                        headingTextStyle: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        dataTextStyle: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Theme.of(
                                              context,
                                            ).dividerColor,
                                          ),
                                        ),
                                        columns: const [
                                          DataColumn(label: Text('Num Exp')),
                                          DataColumn(label: Text('JJD')),
                                          DataColumn(label: Text('Tipo')),
                                          DataColumn(label: Text('Código')),
                                          DataColumn(label: Text('Fecha')),
                                          DataColumn(
                                            label: Text('SMA'),
                                            numeric: true,
                                          ),
                                          DataColumn(
                                            label: Text('SMV'),
                                            numeric: true,
                                          ),
                                          DataColumn(
                                            label: Text('Pulseras'),
                                            numeric: true,
                                          ),
                                        ],
                                        rows: _rows.map((r) {
                                          return DataRow(
                                            cells: [
                                              DataCell(
                                                Text(
                                                  r['numero_expedicion'] ?? '',
                                                ),
                                              ),
                                              DataCell(Text(r['jjd'] ?? '')),
                                              DataCell(Text(r['tipo'] ?? '')),
                                              DataCell(Text(r['codigo'] ?? '')),
                                              DataCell(
                                                Text(
                                                  r['fecha']?.toString() ?? '',
                                                ),
                                              ),
                                              DataCell(Text('${r['sma']}')),
                                              DataCell(Text('${r['smv']}')),
                                              DataCell(
                                                Text('${r['pulseras']}'),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
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
