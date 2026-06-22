import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// import '../../config.dart';
import '../../services/api_service.dart';
import '../../services/xiaomi_provider.dart';
import 'package:provider/provider.dart';
import '../../widgets/main_sidebar.dart';
import '../../widgets/liquid_glass_card.dart';

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
  
  final _validationController = TextEditingController();
  final _validationFocus = FocusNode();
  List<dynamic> pendingItems = [];
  bool loadingPending = false;

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error procesando datos: $e')),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> fetchPending() async {
    if (!mounted) return;
    setState(() => loadingPending = true);
    try {
      final api = ApiService.instance?.client;
      if (api == null) return;
      final resp = await api.get('/xiaomieco/not_finished_cesb');
      if (resp.ok && resp.body is Map) {
        setState(() {
          pendingItems = resp.body['not_finished'] as List? ?? [];
          unitsPending = pendingItems.fold<int>(
            0,
            (sum, item) => sum + (int.tryParse(item['qty']?.toString() ?? '0') ?? 0),
          );
        });
      }
    } catch (e) {
      debugPrint('Error fetching pending: $e');
    } finally {
      if (mounted) setState(() => loadingPending = false);
    }
  }

  Future<void> _validateCesb(String cesb) async {
    final code = cesb.trim();
    if (code.isEmpty) return;

    setState(() => loadingPending = true);
    try {
      final provider = Provider.of<XiaomiProvider>(context, listen: false);
      final success = await provider.validateCesb(code);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CESB $code Validado con éxito'), backgroundColor: Colors.green),
        );
        _validationController.clear();
        await fetchPending();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al validar CESB $code. Asegúrate de que existe y no está cerrado.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => loadingPending = false);
      _validationFocus.requestFocus();
    }
  }

  Future<void> _deleteCesb(int id, String cesbLabel) async {
    debugPrint('[_deleteCesb] called id=$id cesb=$cesbLabel');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar registro?'),
        content: Text('Se eliminará el CESB "$cesbLabel" de forma permanente. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    debugPrint('[_deleteCesb] dialog result=$confirmed');
    if (confirmed != true || !mounted) return;

    final provider = Provider.of<XiaomiProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.deleteCesb(id);
    debugPrint('[_deleteCesb] success=$success');
    if (!mounted) return;
    if (success) {
      messenger.showSnackBar(
        SnackBar(content: Text('CESB "$cesbLabel" eliminado'), backgroundColor: Colors.red),
      );
      fetchHistorico();
      fetchPending();
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('Error al eliminar CESB "$cesbLabel"'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deletePendingCesb(String cesb) async {
    debugPrint('[_deletePendingCesb] called cesb=$cesb');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar CESB pendiente?'),
        content: Text('Se eliminará el CESB "$cesb" de forma permanente. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    debugPrint('[_deletePendingCesb] dialog result=$confirmed');
    if (confirmed != true || !mounted) return;

    final provider = Provider.of<XiaomiProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.deleteCesbByCode(cesb);
    debugPrint('[_deletePendingCesb] success=$success');
    if (!mounted) return;
    if (success) {
      messenger.showSnackBar(
        SnackBar(content: Text('CESB "$cesb" eliminado'), backgroundColor: Colors.red),
      );
      fetchHistorico();
      fetchPending();
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('Error al eliminar CESB "$cesb"'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _unvalidateCesb(String cesb) async {
    final code = cesb.trim();
    if (code.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Desvalidar CESB?'),
        content: Text('Esto devolverá el CESB $code a estado PENDIENTE y reseteará cualquier inicio de trabajo previo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Desvalidar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => loadingPending = true);
    try {
      final provider = Provider.of<XiaomiProvider>(context, listen: false);
      final success = await provider.unvalidateCesb(code);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CESB $code ahora está PENDIENTE'), backgroundColor: Colors.orange),
        );
        await fetchPending();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al desvalidar CESB $code'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => loadingPending = false);
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
    fetchPending(); // New
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 900;
                
                Widget content = Column(
                  children: [
                    // 1. Top Stats Section
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: isMobile ? 8 : 16,
                      ),
                      child: isMobile
                          ? GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 2.2, // Taller cards to prevent internal value overflow
                              children: [
                                _StatCard(
                                  label: 'Unid. Hoy',
                                  value: '$unitsToday',
                                  icon: Icons.bolt_rounded,
                                  color: Colors.blueAccent,
                                ),
                                _StatCard(
                                  label: 'CESB',
                                  value: '$filteredCesb',
                                  icon: Icons.qr_code_2_rounded,
                                  color: Colors.greenAccent,
                                ),
                                _StatCard(
                                  label: 'Unid. (Filtradas)',
                                  value: '$filteredUnits',
                                  icon: Icons.layers_rounded,
                                  color: Colors.orangeAccent,
                                ),
                                _StatCard(
                                  label: 'Unid. Pendientes',
                                  value: '$unitsPending',
                                  icon: Icons.pending_actions_rounded,
                                  color: Colors.redAccent,
                                ),
                              ],
                            )
                          : Row(
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
                    ),

                    // 2. Filters Section
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: EdgeInsets.all(isMobile ? 12 : 16),
                      decoration: BoxDecoration(
                        color: theme.cardColor.withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: theme.dividerColor.withValues(alpha: .1)),
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
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
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
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: operarioSeleccionado,
                                      icon: const Icon(Icons.person_outline_rounded, size: 18),
                                      style: theme.textTheme.bodyMedium,
                                      items: ['Selecciona un valor', ...operarios]
                                          .map((o) => DropdownMenuItem(
                                                value: o,
                                                child: Text(o == 'Selecciona un valor' ? 'Todos los operarios' : o),
                                              ))
                                          .toList(),
                                      onChanged: (v) => setState(() => operarioSeleccionado = v!),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ActionChip(
                                  avatar: const Icon(Icons.cleaning_services_rounded, size: 16),
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
                                  backgroundColor: theme.colorScheme.errorContainer.withValues(alpha: .2),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 3. Main Split Layout
                    isMobile
                        ? Column(
                            children: [
                              _buildPendingSection(theme, isMobile),
                              const SizedBox(height: 12),
                              _buildHistorySection(theme, isMobile),
                            ],
                          )
                        : Expanded(
                            child: Flex(
                              direction: Axis.horizontal,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // --- PRIMARY COLUMN (HISTORY on Desktop) ---
                                Expanded(
                                  flex: 3,
                                  child: _buildHistorySection(theme, isMobile),
                                ),
                                const VerticalDivider(width: 1),
                                // --- SECONDARY COLUMN (PENDING on Desktop) ---
                                Expanded(
                                  flex: 2,
                                  child: _buildPendingSection(theme, isMobile),
                                ),
                              ],
                            ),
                          ),
                  ],
                );
                return isMobile ? SingleChildScrollView(child: content) : content;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(ThemeData theme, bool isMobile) {
    return Column(
      mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: isMobile ? 4 : 8),
          child: Row(
            children: [
              const Icon(Icons.history_rounded, size: 20, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Text('HISTÓRICO ACABADOS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.hintColor, letterSpacing: 1.1)),
            ],
          ),
        ),
        if (!isMobile)
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : records.isEmpty
                    ? _buildNoData(theme)
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _LazyDataTable(records: records, theme: theme, onDelete: _deleteCesb),
                      ),
          )
        else
          // On mobile, just a regular container for the table (it has internal scroll)
          loading
              ? const Center(child: CircularProgressIndicator())
              : records.isEmpty
                  ? _buildNoData(theme)
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        height: 400, // Reasonable height for the table on mobile
                        child: _LazyDataTable(records: records, theme: theme, onDelete: _deleteCesb),
                      ),
                    ),
      ],
    );
  }

  Widget _buildPendingSection(ThemeData theme, bool isMobile) {
    return Container(
      color: theme.colorScheme.surface.withOpacity(0.3),
      child: Column(
        mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          // Scanner Area
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.05),
              border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.1))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.qr_code_scanner_rounded, size: 20, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('VALIDAR CESB', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange)),
                  ],
                ),
                SizedBox(height: isMobile ? 8 : 12),
                _GlassTextField(
                  controller: _validationController,
                  focusNode: _validationFocus,
                  hint: 'Escanear CESB...',
                  icon: Icons.barcode_reader,
                  onSubmitted: (v) => _validateCesb(v),
                ),
              ],
            ),
          ),

          // Pending List
          if (!isMobile)
            Expanded(
              child: _buildPendingList(),
            )
          else
            SizedBox(
              height: 450, // Fixed height on mobile for 'scroll in scroll'
              child: _buildPendingList(shrinkWrap: false), // Enable internal scroll
            ),
        ],
      ),
    );
  }

  Widget _buildPendingList({bool shrinkWrap = false}) {
    return loadingPending
        ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
        : pendingItems.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Todo está al día', style: TextStyle(color: Colors.grey))))
            : ListView.separated(
                shrinkWrap: shrinkWrap,
                physics: shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 20, left: 12, right: 12, top: 12),
                itemCount: pendingItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) {
                  final item = pendingItems[i];
                  final isValidated = item['fecha_hora_validado'] != null;
                  final isStarted = item['fecha_hora_inicio'] != null;

                  return _PendingCesbTile(
                    item: item,
                    isValidated: isValidated,
                    isStarted: isStarted,
                    onTap: () {
                      if (!isValidated) {
                        _validationController.text = item['cesb'] ?? '';
                        _validationFocus.requestFocus();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('CESB ${item['cesb']} está validado. Puedes empezar el trabajo desde la pantalla de Ejecución.'),
                            backgroundColor: Colors.blue,
                          ),
                        );
                      }
                    },
                    onUnvalidate: (isValidated || isStarted) ? () => _unvalidateCesb(item['cesb'] ?? '') : null,
                    onDelete: () {
                      final cesb = item['cesb']?.toString() ?? '';
                      debugPrint('[pendingDelete] using cesb=$cesb for delete (id was null)');
                      if (cesb.isNotEmpty) _deletePendingCesb(cesb);
                    },
                  );
                },
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
      padding: const EdgeInsets.all(10),
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
  final FocusNode? focusNode;
  final Function(String)? onSubmitted;

  const _GlassTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.focusNode,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(128),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onSubmitted: onSubmitted,
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

class _PendingCesbTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isValidated;
  final bool isStarted;
  final VoidCallback onTap;
  final VoidCallback? onUnvalidate;
  final VoidCallback? onDelete;

  const _PendingCesbTile({
    required this.item,
    required this.isValidated,
    required this.isStarted,
    required this.onTap,
    this.onUnvalidate,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isStarted ? Colors.blue : (isValidated ? Colors.green : Colors.grey);
    
    return LiquidGlassCard(
      radius: 12,
      blur: 10,
      padding: const EdgeInsets.symmetric(vertical: 4),
      onTap: onTap,
      tint: color.withValues(alpha: .02),
      child: ListTile(
        dense: true,
        title: Text(
          item['cesb'] ?? 'SIN CESB',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        subtitle: Text(
          '${item['sku']}\n${item['qty']} uds',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.hintColor,
            height: 1.3,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onDelete != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                onPressed: onDelete,
                tooltip: 'Eliminar CESB mal picado',
              ),
            if (onUnvalidate != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.undo_rounded, size: 18, color: Colors.orange),
                onPressed: onUnvalidate,
                tooltip: 'Desvalidar / Revertir',
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: .2)),
              ),
              child: Text(
                isStarted ? 'TRABAJANDO' : (isValidated ? 'VALIDADO' : 'PENDIENTE'),
                style: TextStyle(
                  fontSize: 9, 
                  fontWeight: FontWeight.bold, 
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildNoData(ThemeData theme) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.history_toggle_off_rounded, size: 48, color: theme.disabledColor.withAlpha(50)),
        const SizedBox(height: 12),
        Text('No hay registros', style: TextStyle(color: theme.disabledColor)),
      ],
    ),
  );
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


class _LazyDataTable extends StatefulWidget {
  final List records;
  final ThemeData theme;
  final Future<void> Function(int id, String cesb)? onDelete;

  const _LazyDataTable({required this.records, required this.theme, this.onDelete});

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

    // Column widths
    final Map<String, int> columnFlex = {
      'cesb': 4,
      'sku': 2,
      'partn': 3,
      'qty': 2,
      'cartons': 2,
      'operario': 3,
      'fecha': 4,
    };

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
                        flex: columnFlex['cesb']!,
                        isHeader: true,
                        sortKey: 'cesb',
                      ),
                      buildCell(
                        'SKU',
                        flex: columnFlex['sku']!,
                        isHeader: true,
                        sortKey: 'sku',
                      ),
                      buildCell(
                        'P/N',
                        flex: columnFlex['partn']!,
                        isHeader: true,
                        sortKey: 'partn',
                      ),
                      buildCell(
                        'Uds.',
                        flex: columnFlex['qty']!,
                        align: TextAlign.right,
                        isHeader: true,
                        sortKey: 'qty',
                      ),
                      buildCell(
                        'Cart.',
                        flex: columnFlex['cartons']!,
                        align: TextAlign.right,
                        isHeader: true,
                        sortKey: 'cartons',
                      ),
                      buildCell(
                        'Operario',
                        flex: columnFlex['operario']!,
                        isHeader: true,
                        sortKey: 'operario',
                      ),
                      buildCell(
                        'Fecha Fin',
                        flex: columnFlex['fecha']!,
                        isHeader: true,
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
                              flex: columnFlex['cesb']!,
                            ),
                            buildCell(
                              val(r['sku']),
                              flex: columnFlex['sku']!,
                            ),
                            buildCell(
                              val(r['partn']),
                              flex: columnFlex['partn']!,
                            ),
                            buildCell(
                              val(r['qty']),
                              flex: columnFlex['qty']!,
                              align: TextAlign.right,
                            ),
                            buildCell(
                              val(r['cartons']),
                              flex: columnFlex['cartons']!,
                              align: TextAlign.right,
                            ),
                            buildCell(
                              val(r['operario']),
                              flex: columnFlex['operario']!,
                            ),
                            buildCell(
                              dateStr,
                              flex: columnFlex['fecha']!,
                            ),
                            if (widget.onDelete != null)
                              SizedBox(
                                width: 40,
                                child: IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                                  tooltip: 'Eliminar registro',
                                  onPressed: () {
                                    final id = r['registro'];
                                    final cesb = val(r['cesb']);
                                    debugPrint('[historialDelete] raw registro=$id type=${id?.runtimeType} cesb=$cesb');
                                    if (id != null) {
                                      final idInt = int.tryParse(id.toString());
                                      debugPrint('[historialDelete] parsed idInt=$idInt');
                                      if (idInt != null) widget.onDelete!(idInt, cesb);
                                    } else {
                                      debugPrint('[historialDelete] id is NULL! full record keys: ${r.keys.toList()}');
                                    }
                                  },
                                ),
                              ),
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
