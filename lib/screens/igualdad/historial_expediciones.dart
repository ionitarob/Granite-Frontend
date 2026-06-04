import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';

import 'package:configtool_granite_frontend/src/api/igualdad_api.dart';
import 'package:configtool_granite_frontend/services/api_service.dart';
import 'historial_expediciones_old.dart';
import '../../widgets/main_sidebar.dart';

class _ExportOptions {
  final bool marcarEnviado;
  final String? observaciones;

  const _ExportOptions({required this.marcarEnviado, this.observaciones});
}

class HistorialExpedicionesScreen extends StatefulWidget {
  const HistorialExpedicionesScreen({super.key});

  @override
  State<HistorialExpedicionesScreen> createState() =>
      _HistorialExpedicionesScreenState();
}

class _HistorialExpedicionesScreenState
    extends State<HistorialExpedicionesScreen>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _edgeOverlay;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true, _saving = false;

  // Scroll controllers
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  // Para animar el fondo degradado
  final List<List<Color>> _gradients = [
    [Colors.deepPurple, Colors.purple], // Default fallback
  ];
  late final AnimationController _ctrl;
  late final Animation<Alignment> _align1;
  late final Animation<Alignment> _align2;

  @override
  void initState() {
    super.initState();
    _fetchHistorial();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    _align1 = AlignmentTween(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _align2 = AlignmentTween(
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final logicalWidth =
          MediaQuery.maybeOf(context)?.size.width ??
          (View.of(context).physicalSize.width /
              View.of(context).devicePixelRatio);
      if (logicalWidth >= 900) {
        final routeName = ModalRoute.of(context)?.settings.name;
        final overlay = Overlay.of(context, rootOverlay: true);
        _edgeOverlay = OverlayEntry(
          builder: (ctx) => Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: EdgeNavHandle(
                  user: Provider.of<ApiService>(ctx, listen: false).currentUser,
                  width: 32,
                  currentRoute: routeName,
                  showIndicator: true,
                ),
              ),
            ),
          ),
        );
        overlay.insert(_edgeOverlay!);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    _gradients[0] = [
      theme.colorScheme.primaryContainer,
      theme.colorScheme.secondaryContainer,
    ];
  }

  @override
  void dispose() {
    _edgeOverlay?.remove();
    _edgeOverlay = null;
    _ctrl.dispose();
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  Future<void> _fetchHistorial() async {
    setState(() => _loading = true);
    try {
      final list = await IgualdadApi.getExpedicionesCerradas();
      if (!mounted) return;
      setState(() => _rows = List<Map<String, dynamic>>.from(list));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al cargar historial: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<String> _getExportDir() async {
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      return dir!.path;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    }
  }

  Future<void> _exportar() async {
    final codigo = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Exportar Expedición'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Escribe el código IDIM u OYSTA',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final text = ctrl.text.trim().toUpperCase();
                if (text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Debes escribir un código válido'),
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, text);
              },
              child: const Text('Exportar'),
            ),
          ],
        );
      },
    );
    if (codigo == null) return;

    final options = await _askExportOptions();
    if (options == null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Generando exportación…')));

    try {
      final export = await IgualdadApi.exportExpediciones(
        codigo,
        marcarEnviado: options.marcarEnviado,
        observaciones: options.observaciones,
      );
      final Uint8List bytes = export.bytes;
      final exportDir = await _getExportDir();
      final file = File('$exportDir/expedicion_$codigo.xlsx');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      final storedNote = export.observaciones;
      final buffer = StringBuffer('Exportado en: ${file.path}');
      if (storedNote != null && storedNote.isNotEmpty) {
        buffer.write('\nObs.: $storedNote');
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(buffer.toString())));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
    }
  }

  Future<_ExportOptions?> _askExportOptions() async {
    bool marcar = false;
    final obsController = TextEditingController();
    final result = await showDialog<_ExportOptions>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Opciones de exportación'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('Marcar semana como enviada'),
                    value: marcar,
                    onChanged: (value) => setStateDialog(() {
                      marcar = value;
                    }),
                  ),
                  TextField(
                    controller: obsController,
                    enabled: marcar,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones (opcional)',
                      helperText:
                          'Déjalo vacío para que se rellene "Enviado el ..." automáticamente.',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final note = obsController.text.trim();
                    Navigator.pop(
                      ctx,
                      _ExportOptions(
                        marcarEnviado: marcar,
                        observaciones: marcar && note.isNotEmpty ? note : null,
                      ),
                    );
                  },
                  child: const Text('Continuar'),
                ),
              ],
            );
          },
        );
      },
    );
    obsController.dispose();
    return result;
  }

  Future<void> _editExpedicion(int id, Map<String, dynamic> current) async {
    final formKey = GlobalKey<FormState>();
    final controllers = <String, TextEditingController>{
      'numero_expedicion': TextEditingController(
        text: current['numero_expedicion'],
      ),
      'jjd': TextEditingController(text: current['jjd']),
      'fecha_inicio': TextEditingController(text: current['fecha_inicio']),
      'fecha_fin': TextEditingController(text: current['fecha_fin']),
      'sma': TextEditingController(text: '${current['sma']}'),
      'smv': TextEditingController(text: '${current['smv']}'),
      'pulseras': TextEditingController(text: '${current['pulseras']}'),
      'botones': TextEditingController(text: '${current['botones']}'),
      'powerbanks': TextEditingController(text: '${current['powerbanks']}'),
    };

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar Expedición'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              children: controllers.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    controller: entry.value,
                    decoration: InputDecoration(
                      labelText: entry.key.replaceAll('_', ' ').toUpperCase(),
                    ),
                    validator: (v) => v!.isEmpty ? 'Obligatorio' : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != true) return;

    final body = {
      'numero_expedicion': controllers['numero_expedicion']!.text,
      'jjd': controllers['jjd']!.text,
      'fecha_inicio': controllers['fecha_inicio']!.text,
      'fecha_fin': controllers['fecha_fin']!.text,
      'sma': int.parse(controllers['sma']!.text),
      'smv': int.parse(controllers['smv']!.text),
      'pulseras': int.parse(controllers['pulseras']!.text),
      'botones': int.parse(controllers['botones']!.text),
      'powerbanks': int.parse(controllers['powerbanks']!.text),
    };

    setState(() => _saving = true);
    try {
      await IgualdadApi.updateExpedicion(id, body);
      await _fetchHistorial();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Expedición actualizada')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
                backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Historial Expediciones',
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color,
          ),
        ),
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
        actions: [
          IconButton(
            icon: Icon(
              Icons.download,
              color: Theme.of(context).iconTheme.color,
            ),
            onPressed: _exportar,
            tooltip: 'Exportar a Excel',
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo degradado animado
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: _align1.value,
                  end: _align2.value,
                  colors: _gradients[0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).dividerColor.withOpacity(0.1),
                      ),
                    ),
                    child: _loading
                        ? Center(
                            child: CircularProgressIndicator(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          )
                        : Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.1),
                                    foregroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const HistorialExpedicionesOldScreen(),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    'Ver historial de la app anterior',
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _rows.isEmpty
                                    ? Center(
                                        child: Text(
                                          'No hay expediciones cerradas.',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium?.color,
                                          ),
                                        ),
                                      )
                                    : Scrollbar(
                                        thumbVisibility: true,
                                        controller: _hScroll,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          controller: _hScroll,
                                          child: Scrollbar(
                                            thumbVisibility: true,
                                            controller: _vScroll,
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.vertical,
                                              controller: _vScroll,
                                              child: DataTable(
                                                headingTextStyle: TextStyle(
                                                  color: Theme.of(
                                                    context,
                                                  ).textTheme.titleSmall?.color,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                dataTextStyle: TextStyle(
                                                  color: Theme.of(
                                                    context,
                                                  ).textTheme.bodyMedium?.color,
                                                ),
                                                columns: const [
                                                  DataColumn(
                                                    label: Text('ID'),
                                                    numeric: true,
                                                  ),
                                                  DataColumn(
                                                    label: Text('Núm Exp'),
                                                  ),
                                                  DataColumn(
                                                    label: Text('JJD'),
                                                  ),
                                                  DataColumn(
                                                    label: Text('Tipo'),
                                                  ),
                                                  DataColumn(
                                                    label: Text('Código'),
                                                  ),
                                                  DataColumn(
                                                    label: Text('Inicio'),
                                                  ),
                                                  DataColumn(
                                                    label: Text('Fin'),
                                                  ),
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
                                                  DataColumn(
                                                    label: Text('Botones'),
                                                    numeric: true,
                                                  ),
                                                  DataColumn(
                                                    label: Text('PowerBanks'),
                                                    numeric: true,
                                                  ),
                                                  DataColumn(
                                                    label: Text('Acciones'),
                                                  ),
                                                ],
                                                rows: _rows.map((row) {
                                                  return DataRow(
                                                    cells: [
                                                      DataCell(
                                                        Text('${row['id']}'),
                                                      ),
                                                      DataCell(
                                                        Text(
                                                          '${row['numero_expedicion']}',
                                                        ),
                                                      ),
                                                      DataCell(
                                                        Text('${row['jjd']}'),
                                                      ),
                                                      DataCell(
                                                        Text('${row['tipo']}'),
                                                      ),
                                                      DataCell(
                                                        Text(
                                                          '${row['codigo']}',
                                                        ),
                                                      ),
                                                      DataCell(
                                                        Text(
                                                          '${row['fecha_inicio']}',
                                                        ),
                                                      ),
                                                      DataCell(
                                                        Text(
                                                          '${row['fecha_fin']}',
                                                        ),
                                                      ),
                                                      DataCell(
                                                        Text('${row['sma']}'),
                                                      ),
                                                      DataCell(
                                                        Text('${row['smv']}'),
                                                      ),
                                                      DataCell(
                                                        Text(
                                                          '${row['pulseras']}',
                                                        ),
                                                      ),
                                                      DataCell(
                                                        Text(
                                                          '${row['botones']}',
                                                        ),
                                                      ),
                                                      DataCell(
                                                        Text(
                                                          '${row['powerbanks']}',
                                                        ),
                                                      ),
                                                      DataCell(
                                                        IconButton(
                                                          icon: Icon(
                                                            Icons.edit,
                                                            color: Theme.of(
                                                              context,
                                                            ).iconTheme.color,
                                                          ),
                                                          onPressed: _saving
                                                              ? null
                                                              : () =>
                                                                    _editExpedicion(
                                                                      row['id']
                                                                          as int,
                                                                      row,
                                                                    ),
                                                        ),
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
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
