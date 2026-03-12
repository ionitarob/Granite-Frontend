import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// import '../../config.dart';
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
  OverlayEntry? _edgeOverlay;

  bool loading = false;
  List<dynamic> records = [];
  Map<String, dynamic> summary = {};
  List<String> operarios = [];

  // Global KPIs
  int unitsToday = 0;
  // unitsMonth/Year removed as per request
  int unitsPending = 0;
  bool loadingKPIs = false;

  WebSocketChannel? _statsChannel;
  StreamSubscription? _statsSubscription;

  void _connectStats() {
    _disconnectStats();
    // Hardcoded URL to rule out any construction issues
    var urlStr = 'ws://10.20.31.10:7000/ws/xiaomieco/today/';

    // 6. Final ultra-defensive cleanup
    if (urlStr.contains('#')) {
      urlStr = urlStr.replaceAll('#', '');
    }
    if (urlStr.startsWith('http://')) {
      urlStr = urlStr.replaceFirst('http://', 'ws://');
    } else if (urlStr.startsWith('https://')) {
      urlStr = urlStr.replaceFirst('https://', 'wss://');
    }

    debugPrint('Connecting to Xiaomi stats WS: $urlStr');
    try {
      _statsChannel = WebSocketChannel.connect(Uri.parse(urlStr));
      _statsSubscription = _statsChannel!.stream.listen(
        (message) {
          try {
            final data = json.decode(message.toString());
            if (data is Map && data.containsKey('count')) {
              if (mounted) {
                setState(() {
                  unitsToday = int.tryParse(data['count'].toString()) ?? 0;
                });
              }
            }
          } catch (e) {
            debugPrint('Error parsing Xiaomi stats WS message: $e');
          }
        },
        onError: (err) {
          debugPrint('Xiaomi stats WS error: $err');
          _reconnectStats();
        },
        onDone: () {
          debugPrint('Xiaomi stats WS closed');
          _reconnectStats();
        },
      );
    } catch (e) {
      debugPrint('Failed to connect to Xiaomi stats WS: $e');
      _reconnectStats();
    }
  }

  void _reconnectStats() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) _connectStats();
    });
  }

  void _disconnectStats() {
    _statsSubscription?.cancel();
    _statsChannel?.sink.close();
    _statsSubscription = null;
    _statsChannel = null;
  }

  int get unitsCurrentPeriod {
    // Only showing Today as per request
    return unitsToday;
  }

  int get filteredUnits {
    return records.fold<int>(0, (sum, item) {
      if (item is Map) {
        return sum + (int.tryParse(item['qty']?.toString() ?? '0') ?? 0);
      }
      return sum;
    });
  }

  int get filteredCesb => records.length;

  Future<void> _fetchGlobalKPIs() async {
    if (!mounted) return;
    setState(() => loadingKPIs = true);

    try {
      final api = ApiService.instance?.client;
      if (api == null) return;

      // Month/Year stats removed. Only WebSocket for Today is used.

      // Only fetch pending units, others are calculated from records
      final respPending = await api.get('/xiaomieco/not_finished_cesb');
      if (respPending.ok && respPending.body is Map) {
        final List items = respPending.body['not_finished'] as List? ?? [];
        unitsPending = items.fold<int>(
          0,
          (sum, item) =>
              sum + (int.tryParse(item['qty']?.toString() ?? '0') ?? 0),
        );
      }
    } catch (e) {
      debugPrint('Error fetching KPIs: $e');
    } finally {
      if (mounted) setState(() => loadingKPIs = false);
    }
  }

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
    _fetchGlobalKPIs();
    _connectStats();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
                  user: ApiService.instance?.currentUser,
                  width: 32,
                  currentRoute: routeName,
                  showIndicator: true,
                ),
              ),
            ),
          );
        },
      );
      overlay.insert(_edgeOverlay!);
    });
  }

  @override
  void dispose() {
    _terminoController.dispose();
    _edgeOverlay?.remove();
    _disconnectStats();
    super.dispose();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: API no disponible')),
        );
        return;
      }

      final resp = await api.get('/xiaomieco/not_finished_cesb');
      Navigator.of(context).pop(); // remove loading

      if (!resp.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('HTTP ${resp.statusCode}: ${resp.error ?? 'Error'}'),
          ),
        );
        return;
      }

      final decoded = resp.body;
      if (decoded == null ||
          decoded is! Map ||
          decoded['not_finished'] is! List) {
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
            height: 500,
            child: _PendingCesbSearchDialog(items: items),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e, st) {
      Navigator.of(context).pop();
      debugPrint('fetch not_finished_cesb error: $e\n$st');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error procesando datos: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Histórico de Etiquetado'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primaryContainer.withValues(alpha: .9),
                theme.colorScheme.surface,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Premium Gradient Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withValues(alpha: .05),
                  theme.colorScheme.secondary.withValues(alpha: .1),
                  theme.scaffoldBackgroundColor,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // 1. Top Stats Section
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    children: [
                      // Toggle "Bubble" removed as per request (only 'dia' supported now)

                      // KPI Row
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              label: 'Unid. Hoy',
                              value: '$unitsToday',
                              icon: Icons.bolt_rounded,
                              color: Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _StatCard(
                              label: 'CESB',
                              value: '$filteredCesb',
                              icon: Icons.qr_code_2_rounded,
                              color: Colors.greenAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _StatCard(
                              label: 'Unid. (Filtradas)',
                              value: '$filteredUnits',
                              icon: Icons.layers_rounded,
                              color: Colors.orangeAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _StatCard(
                              label: 'Unid. Pendientes',
                              value: '$unitsPending',
                              icon: Icons.pending_actions_rounded,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 2. Filters Section (Compact)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardColor.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: .1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _GlassTextField(
                              controller: _terminoController,
                              hint: 'Buscar CESB, SKU, P/N...',
                              icon: Icons.search_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filled(
                            onPressed: () {
                              fetchHistorico();
                              _fetchGlobalKPIs();
                            },
                            icon: const Icon(Icons.search),
                            style: IconButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // Filter chips for date range
                            _FilterChip(
                              label: fechaDesde != null
                                  ? 'Desde: ${fechaDesde!.toLocal().toString().split(' ').first}'
                                  : 'Inicio',
                              icon: Icons.start_rounded,
                              onTap: _pickFechaDesde,
                              isActive: fechaDesde != null,
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: fechaHasta != null
                                  ? 'Hasta: ${fechaHasta!.toLocal().toString().split(' ').first}'
                                  : 'Fin',
                              icon: Icons.keyboard_tab_rounded,
                              onTap: _pickFechaHasta,
                              isActive: fechaHasta != null,
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: .5),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: operarioSeleccionado,
                                  icon: const Icon(
                                    Icons.person_outline_rounded,
                                    size: 18,
                                  ),
                                  style: theme.textTheme.bodyMedium,
                                  items: ['Selecciona un valor', ...operarios]
                                      .map(
                                        (o) => DropdownMenuItem(
                                          value: o,
                                          child: Text(
                                            o == 'Selecciona un valor'
                                                ? 'Todos los operarios'
                                                : o,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => operarioSeleccionado = v!),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: const Icon(
                                Icons.cleaning_services_rounded,
                                size: 16,
                              ),
                              label: const Text('Limpiar'),
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
                                _fetchGlobalKPIs();
                              },
                              side: BorderSide.none,
                              backgroundColor: theme.colorScheme.errorContainer
                                  .withValues(alpha: .2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 3. List Section
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : records.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.history_toggle_off_rounded,
                                size: 80,
                                color: theme.disabledColor.withValues(
                                  alpha: .2,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No hay registros',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: theme.disabledColor,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _LazyDataTable(records: records, theme: theme),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNotFinishedCesb,
        icon: const Icon(Icons.warning_rounded, color: Colors.white),
        label: const Text('Pendientes', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.orange,
      ),
    );
  }
}

// --- Premium Widgets ---

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .5)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.cardColor.withValues(alpha: .9),
            theme.cardColor.withValues(alpha: .7),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.hintColor,
                    fontSize: 9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;

  const _GlassTextField({
    required this.controller,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: theme.hintColor),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? theme.colorScheme.primary.withValues(alpha: .5)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? theme.colorScheme.primary : theme.hintColor,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.hintColor,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingCesbSearchDialog extends StatefulWidget {
  final List items;
  const _PendingCesbSearchDialog({required this.items});

  @override
  State<_PendingCesbSearchDialog> createState() =>
      _PendingCesbSearchDialogState();
}

class _PendingCesbSearchDialogState extends State<_PendingCesbSearchDialog> {
  final _searchController = TextEditingController();
  late List _filteredItems;

  @override
  void initState() {
    super.initState();
    _filteredItems = List.from(widget.items);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filter(String query) {
    if (query.isEmpty) {
      if (mounted) setState(() => _filteredItems = List.from(widget.items));
      return;
    }
    final lower = query.toLowerCase();
    setState(() {
      _filteredItems = widget.items.where((item) {
        final cesb = item['cesb']?.toString().toLowerCase() ?? '';
        final sku = item['sku']?.toString().toLowerCase() ?? '';
        final partn = item['partn']?.toString().toLowerCase() ?? '';
        final operario = item['operario']?.toString().toLowerCase() ?? '';
        return cesb.contains(lower) ||
            sku.contains(lower) ||
            partn.contains(lower) ||
            operario.contains(lower);
      }).toList();
    });
  }

  String _val(dynamic v) =>
      (v == null || (v is String && v.trim().isEmpty)) ? '-' : v.toString();

  String _openDate(dynamic v) {
    if (v == null) return '-';
    try {
      final parsed = DateTime.parse(v.toString()).toLocal();
      return parsed.toString().split('.').first; // YYYY-MM-DD HH:MM:SS
    } catch (_) {
      return v.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            labelText: 'Buscar CESB, SKU, Operario...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onChanged: _filter,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _filteredItems.isEmpty
              ? const Center(child: Text('No se encontraron resultados'))
              : SelectionArea(
                  child: ListView.separated(
                    itemCount: _filteredItems.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, i) {
                      final r = _filteredItems[i];
                      return ListTile(
                        title: Text(
                          '${_val(r['cesb'])} / ${_val(r['sku'])}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'P/N: ${_val(r['partn'])} • Qty: ${_val(r['qty'])} • Cartons: ${_val(r['cartons'])}',
                        ),
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Operario: ${_val(r['operario'])}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Abierto: ${_openDate(r['fecha_hora_registro'])}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _LazyDataTable extends StatefulWidget {
  final List records;
  final ThemeData theme;

  const _LazyDataTable({required this.records, required this.theme});

  @override
  State<_LazyDataTable> createState() => _LazyDataTableState();
}

class _LazyDataTableState extends State<_LazyDataTable> {
  late List _sortedRecords;
  String? _sortColumn;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _sortedRecords = List.from(widget.records);
  }

  @override
  void didUpdateWidget(covariant _LazyDataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records) {
      _sortedRecords = List.from(widget.records);
      if (_sortColumn != null) {
        _applySort(_sortColumn!, _sortAscending);
      }
    }
  }

  void _applySort(String columnKey, bool ascending) {
    _sortedRecords.sort((a, b) {
      if (a == null || b == null) return 0;
      final valA = val(a[columnKey]);
      final valB = val(b[columnKey]);

      int result = 0;

      // Try numeric sort
      final numA = double.tryParse(valA);
      final numB = double.tryParse(valB);

      if (numA != null && numB != null) {
        result = numA.compareTo(numB);
      } else {
        // Fallback to alphabetical
        result = valA.toLowerCase().compareTo(valB.toLowerCase());
      }

      return ascending ? result : -result;
    });
  }

  void _onSort(String columnKey) {
    setState(() {
      if (_sortColumn == columnKey) {
        if (_sortAscending) {
          // Ascending -> Descending
          _sortAscending = false;
          _applySort(columnKey, _sortAscending);
        } else {
          // Descending -> Normal (Unsorted)
          _sortColumn = null;
          _sortAscending = true;
          _sortedRecords = List.from(widget.records);
        }
      } else {
        // New Column -> Ascending
        _sortColumn = columnKey;
        _sortAscending = true;
        _applySort(columnKey, _sortAscending);
      }
    });
  }

  String val(dynamic v) =>
      (v == null || (v is String && v.trim().isEmpty)) ? '-' : v.toString();

  @override
  Widget build(BuildContext context) {
    const double minWidth = 900;
    final theme = widget.theme;

    Widget buildCell(
      String text, {
      int flex = 1,
      TextAlign align = TextAlign.left,
      bool isHeader = false,
      Color? bgColor,
      String? sortKey,
    }) {
      Widget content;

      if (isHeader) {
        content = Row(
          mainAxisAlignment: align == TextAlign.right
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                text,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: align,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (sortKey != null && _sortColumn == sortKey)
              Icon(
                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 16,
                color: theme.colorScheme.primary,
              ),
          ],
        );
      } else {
        content = SelectableText(
          text,
          style: theme.textTheme.bodyMedium,
          textAlign: align,
        );
      }

      final cell = Expanded(
        flex: flex,
        child: Container(
          color: bgColor,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: content,
        ),
      );

      if (isHeader && sortKey != null) {
        return Expanded(
          flex: flex,
          child: InkWell(
            onTap: () => _onSort(sortKey),
            child: Container(
              color: bgColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: content,
            ),
          ),
        );
      }
      return cell;
    }

    // Column background colors to help readability
    final colColor1 = Colors.transparent;
    final colColor2 = theme.colorScheme.primaryContainer.withValues(alpha: .6);
    final colColor3 = theme.colorScheme.secondaryContainer.withValues(
      alpha: .6,
    );
    final colColor4 = theme.colorScheme.tertiaryContainer.withValues(alpha: .6);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth < minWidth
            ? minWidth
            : constraints.maxWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: contentWidth,
              maxWidth: contentWidth,
            ),
            child: Column(
              children: [
                // Header Row
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: .5,
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: theme.dividerColor.withValues(alpha: .2),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      buildCell(
                        'CESB',
                        flex: 3,
                        isHeader: true,
                        bgColor: colColor1,
                        sortKey: 'cesb',
                      ),
                      buildCell(
                        'SKU',
                        flex: 2,
                        isHeader: true,
                        bgColor: colColor2,
                        sortKey: 'sku',
                      ),
                      buildCell(
                        'Part Number',
                        flex: 2,
                        isHeader: true,
                        bgColor: colColor1,
                        sortKey: 'partn',
                      ),
                      buildCell(
                        'Unid.',
                        flex: 1,
                        align: TextAlign.right,
                        isHeader: true,
                        bgColor: colColor3,
                        sortKey: 'qty',
                      ),
                      buildCell(
                        'Cart.',
                        flex: 1,
                        align: TextAlign.right,
                        isHeader: true,
                        bgColor: colColor3,
                        sortKey: 'cartons',
                      ),
                      buildCell(
                        'Operario',
                        flex: 3,
                        isHeader: true,
                        bgColor: colColor4,
                        sortKey: 'operario',
                      ),
                      buildCell(
                        'Fecha Fin',
                        flex: 3,
                        isHeader: true,
                        bgColor: colColor1,
                        sortKey: 'fecha_hora_fin',
                      ),
                    ],
                  ),
                ),
                // Lazy List View for Data Rows
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: _sortedRecords.length,
                    itemBuilder: (context, i) {
                      final r = _sortedRecords[i];
                      if (r == null || r is! Map)
                        return const SizedBox.shrink();

                      String dateStr = val(r['fecha_hora_fin']);
                      if (dateStr != '-') {
                        try {
                          final dt = DateTime.parse(dateStr).toLocal();
                          dateStr =
                              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                        } catch (_) {
                          dateStr = dateStr.split('T').first;
                        }
                      }

                      return Container(
                        decoration: BoxDecoration(
                          color: i.isEven
                              ? Colors.transparent
                              : theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: .1),
                          border: Border(
                            bottom: BorderSide(
                              color: theme.dividerColor.withValues(alpha: .05),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            buildCell(
                              val(r['cesb']),
                              flex: 3,
                              bgColor: colColor1,
                            ),
                            buildCell(
                              val(r['sku']),
                              flex: 2,
                              bgColor: colColor2,
                            ),
                            buildCell(
                              val(r['partn']),
                              flex: 2,
                              bgColor: colColor1,
                            ),
                            buildCell(
                              val(r['qty']),
                              flex: 1,
                              align: TextAlign.right,
                              bgColor: colColor3,
                            ),
                            buildCell(
                              val(r['cartons']),
                              flex: 1,
                              align: TextAlign.right,
                              bgColor: colColor3,
                            ),
                            buildCell(
                              val(r['operario']),
                              flex: 3,
                              bgColor: colColor4,
                            ),
                            buildCell(dateStr, flex: 3, bgColor: colColor1),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
