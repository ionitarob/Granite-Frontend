import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:flutter/services.dart';

import '../../widgets/pdf_preview_dialog.dart';
import '../../models/agent_models.dart';

import '../../api_client.dart';
import '../../services/api_service.dart';
import '../../services/orderops_service.dart';
import '../../widgets/animated_background.dart';
import '../../config.dart';
import '../servers/registro_servidor_screen.dart';
import '../serials/serial_link.dart';
import '../serials/serial_change.dart';
import '../serials/historial_match_unidad.dart';
import '../serials/historial_cambios_serial.dart';
import '../xiaomi/xiaomi_registro_orden.dart';
import '../sentinel_for_imaging/physical_tables_screen.dart';
import '../../widgets/family_selection_dialog.dart';
import '../../utils/formatters.dart';
import 'serigrafia_panel.dart';
import '../../widgets/multi_family_selection_dialog.dart';

class OrderDetailScreen extends StatefulWidget {
  final int orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  static const double _tableCellsWidth = 930;
  static const double _tableOuterWidth = _tableCellsWidth + 4;
  static const double _logDateColumnWidth = 150;
  static const double _logActorColumnWidth = 140;
  static const double _logActionColumnWidth = 140;
  static const double _logMessageColumnWidth =
      _tableCellsWidth -
      _logDateColumnWidth -
      _logActorColumnWidth -
      _logActionColumnWidth;

  OrderOpsService? _orderOpsService;
  OrderOpsDetail? _detail;
  int? _activeProyectoId;
  String? _activeProyectoName;
  List<AgentOrderObservation> _observations = [];
  List<AgentOrderPhoto> _photos = [];
  List<AgentOrderService> _services = [];
  final Map<int, Uint8List> _pdfPreviewCache = {};

  bool _loading = true;
  bool _isArchivoDropActive = false;
  bool _isExporting = false;
  bool _showLogs = false;
  String? _error;
  String? _sessionActiveFamily;

  final TextEditingController _obsController = TextEditingController();
  final FocusNode _obsFocusNode = FocusNode();

  String _normalizedRole() {
    final raw = (ApiService.instance?.currentUser?.role ?? '')
        .trim()
        .toLowerCase();
    if (raw.startsWith('role_')) return raw.substring(5);
    return raw;
  }

  bool get _isPrivilegedRole {
    final role = _normalizedRole();
    return role == 'admin' || role == 'chief';
  }

  bool get _canViewFinancialData => _isPrivilegedRole;

  bool get _canEditOrderMeta => _isPrivilegedRole;

  // Allow limited edits (proyecto and family) to clerks as well.
  bool get _canEditProyectoOrFamily {
    final role = _normalizedRole();
    return role == 'admin' || role == 'chief' || role.contains('clerc');
  }

  bool _isTabletWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 760 && width < 1200;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      _orderOpsService = OrderOpsService(apiService.client);
      _loadData();
    });
  }

  @override
  void dispose() {
    _obsController.dispose();
    _obsFocusNode.dispose();
    super.dispose();
  }

  Future<void> _exportActa(String orderNbr) async {
    setState(() => _isExporting = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      // Construct the normalized order number if needed (e.g. 23-12345-01)
      final num = orderNbr.trim();
      final res = await api.client.getBytes('/docgen/order/$num/pdf');
      if (!mounted) return;

      if (!res.ok || res.body is! List<int>) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar el acta (${res.statusCode})')),
        );
        return;
      }

      final pdfBytes = Uint8List.fromList(res.body as List<int>);
      final suggested = 'Acta_$num.pdf';

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => PdfPreviewDialog(
            pdfBytes: pdfBytes,
            fileName: suggested,
            service: _orderOpsService!,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exportando: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String _normalizeProyectoName(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  Future<int?> _resolveProyectoIdByOrderProyectoName(
    String? proyectoName,
  ) async {
    if (_orderOpsService == null) return null;
    final normalized = _normalizeProyectoName(proyectoName);
    if (normalized.isEmpty) return null;

    final asId = int.tryParse(normalized);
    if (asId != null && asId > 0) {
      return asId;
    }

    final proyectos = await _orderOpsService!.getProyectos();
    for (final proyecto in proyectos) {
      if (_normalizeProyectoName(proyecto.nombre) == normalized) {
        return proyecto.id;
      }
    }
    return null;
  }

  Future<int?> _resolveActiveProyectoId(AgentOrder order) async {
    if (order.proyectoId != null && order.proyectoId! > 0) {
      return order.proyectoId;
    }
    if (_activeProyectoId != null && _activeProyectoId! > 0) {
      return _activeProyectoId;
    }
    return _resolveProyectoIdByOrderProyectoName(order.proyecto);
  }

  List<AgentOrderObservation> _mergeObservations(
    List<AgentOrderObservation> primary,
    List<AgentOrderObservation> secondary,
  ) {
    final merged = <AgentOrderObservation>[];
    final seen = <String>{};

    String keyFor(AgentOrderObservation obs) {
      if (obs.id > 0) return 'id:${obs.id}';
      return 'raw:${obs.idnbr}|${obs.proyectoId}|${obs.author ?? ''}|${obs.body}|${obs.createdAt?.toIso8601String() ?? ''}';
    }

    for (final obs in [...primary, ...secondary]) {
      final key = keyFor(obs);
      if (seen.add(key)) {
        merged.add(obs);
      }
    }

    return merged;
  }

  List<AgentOrderPhoto> _mergePhotos(
    List<AgentOrderPhoto> primary,
    List<AgentOrderPhoto> secondary,
  ) {
    final merged = <AgentOrderPhoto>[];
    final seen = <String>{};

    String keyFor(AgentOrderPhoto photo) {
      if (photo.id > 0) return 'id:${photo.id}';
      return 'raw:${photo.idnbr}|${photo.proyectoId}|${photo.fileName}|${photo.filePath}|${photo.uploadedAt?.toIso8601String() ?? ''}';
    }

    for (final photo in [...primary, ...secondary]) {
      final key = keyFor(photo);
      if (seen.add(key)) {
        merged.add(photo);
      }
    }

    return merged;
  }

  bool _observationBelongsToOrderOrGeneral(AgentOrderObservation obs) {
    final orderId = widget.orderId;
    final idnbr = obs.idnbr;
    return idnbr <= 0 || idnbr == orderId;
  }

  bool _photoBelongsToOrderOrGeneral(AgentOrderPhoto photo) {
    final orderId = widget.orderId;
    final idnbr = photo.idnbr;
    return idnbr <= 0 || idnbr == orderId;
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final detail = await _orderOpsService!.getAgentOrder(widget.orderId);
      final futures = await Future.wait([
        _orderOpsService!.getObservations(widget.orderId),
        _orderOpsService!.getPhotos(widget.orderId),
        _orderOpsService!.getServices(widget.orderId),
      ]);

      var observations = futures[0] as List<AgentOrderObservation>;
      var photos = futures[1] as List<AgentOrderPhoto>;
      final services = futures[2] as List<AgentOrderService>;

      int? proyectoId;
      String? proyectoName;
      try {
        proyectoId = await _resolveActiveProyectoId(detail.agentOrder);
        if (proyectoId != null) {
          final proyecto = await _orderOpsService!.getProyectoDetail(
            proyectoId,
          );
          proyectoName = proyecto.nombre;
          final scopedProyectoObservations = (proyecto.observations ?? const [])
              .where(_observationBelongsToOrderOrGeneral)
              .toList(growable: false);
          final scopedProyectoPhotos = (proyecto.photos ?? const [])
              .where(_photoBelongsToOrderOrGeneral)
              .toList(growable: false);
          observations = _mergeObservations(
            observations,
            scopedProyectoObservations,
          );
          photos = _mergePhotos(photos, scopedProyectoPhotos);
        }
      } catch (e) {
        debugPrint('Could not merge Proyecto data into order detail: $e');
      }

      if (mounted) {
        setState(() {
          _detail = detail;
          _activeProyectoId = proyectoId;
          _activeProyectoName = proyectoName ?? _activeProyectoName;
          _observations = observations;
          _photos = photos;
          _services = services;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        final errorStr = e.toString();
        if (errorStr.contains('404')) {
          _handleOrderNotFound();
          return;
        }
        setState(() {
          _error = errorStr;
          _loading = false;
        });
      }
    }
  }

  Future<void> _handleOrderNotFound() async {
    final result = await showDialog<_ManualOrderPromptResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _ManualUnitsDialog(numOrden: widget.orderId.toString()),
    );

    if (result == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() => _loading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final token = api.client.accessToken;
      final response = await api.client.post(
        '/serials/order-info',
        jsonBody: {
          'num_orden': widget.orderId.toString(),
          'save': true,
          'unidades': int.tryParse(result.unitsText) ?? 1,
          'manual': !result.doubleEntry,
          'manual_double': result.doubleEntry,
        },
        extraHeaders: (token != null && token.isNotEmpty)
            ? {'Authorization': 'Bearer $token'}
            : null,
      );

      if (response.ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Orden registrada exitosamente')),
          );
        }
        await _loadData();
      } else {
        throw Exception(response.error ?? 'Error registrando orden');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo crear la orden: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _addObservation() async {
    final text = _obsController.text.trim();
    if (text.isEmpty) return;

    setState(() => _loading = true);
    try {
      final user = Provider.of<ApiService>(context, listen: false).currentUser;

      await _orderOpsService!.postObservation(
        widget.orderId,
        text,
        author: user?.username,
        proyectoId: _activeProyectoId,
      );
      _obsController.clear();
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _showAddObservationDialog() async {
    final controller = TextEditingController();
    final newNote = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nueva observacion'),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'Escribe una observacion...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (newNote == null || newNote.isEmpty) return;
    _obsController.text = newNote;
    await _addObservation();
  }

  // Legacy photo pick method replaced by _takePhoto

  Future<void> _markRecepcionado() async {
    setState(() => _loading = true);
    try {
      // Mark as "Pendiente" (Code '2') instead of just setting department
      await _orderOpsService!.updateAgentOrder(
        widget.orderId,
        estado:
            '2', // Code for "Pendiente" according to order_queue_screen.dart
        department: 'Recepcionado',
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Orden marcada como Pendiente (Recepcionado)'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final isDark = baseTheme.brightness == Brightness.dark;
    final theme = baseTheme.copyWith(
      cardColor: isDark
          ? const Color(0xFF1E1E1E)
          : baseTheme.colorScheme.surface,
    );
    final title = _detail != null
        ? _formatOrderNbr(_detail!.agentOrder.orderNbr)
        : 'Orden #${widget.orderId}';

    return Theme(
      data: theme,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
            focusNode: FocusNode(canRequestFocus: false),
          ),
          actions: [
            if (_detail != null) ...[
              Builder(
                builder: (ctx) {
                  final family = (_detail!.agentOrder.family ?? '')
                      .trim()
                      .toUpperCase();
                  final nf = _normalizeText(family);
                  final isMatch =
                      nf.contains('MANIPUL') && nf.contains('ETIQUETADO');
                  final isChange =
                      nf.contains('CAMBIO') && nf.contains('SERIAL');

                  if (isMatch || isChange) {
                    return IconButton(
                      icon: const Icon(Icons.history, color: Colors.cyanAccent),
                      tooltip: isMatch
                          ? 'Ver Historial de Match'
                          : 'Ver Historial de Cambios',
                      onPressed: () {
                        final orderNbr = _formatOrderNbr(
                          _detail!.agentOrder.orderNbr,
                        );
                        Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (c) => isMatch
                                ? HistorialMatchUnidadScreen(
                                    initialSearch: orderNbr,
                                  )
                                : HistorialCambiosSerialScreen(
                                    initialSearch: orderNbr,
                                  ),
                          ),
                        );
                      },
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
            IconButton(
              icon: const Icon(Icons.refresh),
              focusNode: FocusNode(canRequestFocus: false),
              onPressed: _loadData,
            ),
            if (_detail != null)
              IconButton(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.orangeAccent),
                tooltip: 'Exportar acta',
                onPressed: () => _exportActa(_detail!.agentOrder.orderNbr),
              ),
          ],
        ),
        body: Stack(
          children: [
            const AnimatedBackgroundWidget(intensity: 0.3),
            DropTarget(
              onDragEntered: (_) {
                if (!mounted) return;
                setState(() => _isArchivoDropActive = true);
              },
              onDragExited: (_) {
                if (!mounted) return;
                setState(() => _isArchivoDropActive = false);
              },
              onDragDone: (details) async {
                if (!mounted) return;
                setState(() => _isArchivoDropActive = false);
                await _uploadDroppedArchivos(details.files);
              },
              child: SafeArea(
                child: _loading && _detail == null
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null && _detail == null
                    ? Center(
                        child: Text(
                          'Error: $_error',
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : Stack(
                        children: [
                          _buildDashboard(theme),
                          if (_loading)
                            const Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: LinearProgressIndicator(minHeight: 2),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard(ThemeData theme) {
    if (_detail == null) return const SizedBox();
    final isEnEjecucion = _detail!.agentOrder.estado.contains('3');

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1700),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: isEnEjecucion 
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTopExecutionStrip(theme),
                    const SizedBox(height: 20),
                    _buildEmbeddedServicePanel(theme),
                    const SizedBox(height: 24),
                  ],
                )
              : _buildResponsiveGrid(theme),
        ),
      ),
    );
  }

  Widget _buildResponsiveGrid(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Breakpoint for Desktop vs Tablet/Mobile
        final isDesktop = constraints.maxWidth >= 1024;

        if (isDesktop) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main Data Column (Left Side - ~70%)
              Expanded(
                flex: 7,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeaderCard(theme),
                    const SizedBox(height: 24),
                    _buildLinesCard(theme),
                    const SizedBox(height: 24),
                    _buildServicesCard(theme),
                    const SizedBox(height: 24),
                    _buildLogCard(theme),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Action & Attachments Column (Right Side - ~30%)
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildObservationsCard(theme),
                    const SizedBox(height: 24),
                    _buildQualityQualityCard(theme),
                    const SizedBox(height: 24),
                    _buildArchivosCard(theme),
                  ],
                ),
              ),
            ],
          );
        }

        // Fallback for narrower screens
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderCard(theme),
            const SizedBox(height: 24),
            _buildLinesCard(theme),
            const SizedBox(height: 24),
            _buildServicesCard(theme),
            const SizedBox(height: 24),
            _buildObservationsCard(theme),
            const SizedBox(height: 24),
            _buildQualityQualityCard(theme),
            const SizedBox(height: 24),
            _buildArchivosCard(theme),
            const SizedBox(height: 24),
            _buildLogCard(theme),
          ],
        );
      },
    );
  }

  Widget _buildTopExecutionStrip(ThemeData theme) {
    if (_detail == null) return const SizedBox();
    final order = _detail!.agentOrder;
    final sourceOrder = _detail!.sourceOrder;
    final lines = (sourceOrder?['lines'] as List<dynamic>?) ?? const [];
    const topCardHeight = 244.0;
    final estadoMeta = _mapEstado(order.estado);
    final prioridadMeta = _mapPrioridad(order.prioridad);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        final isMedium = constraints.maxWidth >= 760;

        final infoAndObsWidth = isWide
            ? (constraints.maxWidth - 48) * 0.22
            : isMedium
            ? (constraints.maxWidth - 16) / 2
            : constraints.maxWidth;

        final linesAndServicesWidth = isWide
            ? (constraints.maxWidth - 48) * 0.28
            : isMedium
            ? (constraints.maxWidth - 16) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: infoAndObsWidth,
              child: _buildSummaryCard(
                theme,
                'Informacion de la Orden',
                Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildInfoItem(
                              'Cliente',
                              order.customer,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 4),
                            _buildInfoItem(
                              'Orden',
                              order.orderNbr,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 4),
                            _buildInfoItem(
                              'Fecha',
                              order.orderDate != null
                                  ? DateFormat(
                                      'yyyy-MM-dd',
                                    ).format(order.orderDate!)
                                  : '-',
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildMiniBadge(
                            'Estado: ${estadoMeta.$1}',
                            estadoMeta.$2,
                          ),
                          const SizedBox(height: 6),
                          _buildMiniBadge(
                            'Prioridad: ${prioridadMeta.$1}',
                            prioridadMeta.$2,
                          ),
                          const SizedBox(height: 6),
                          _canEditProyectoOrFamily
                              ? GestureDetector(
                                  onTap: () =>
                                      _showFamilyPicker(order.family ?? ''),
                                  child: _buildMiniBadge(
                                    'Familia: ${order.family?.trim().isEmpty ?? true ? 'SIN ASIGNAR' : order.family!.toUpperCase()}',
                                    order.family?.trim().isEmpty ?? true
                                        ? Colors.redAccent
                                        : Colors.tealAccent,
                                  ),
                                )
                              : _buildMiniBadge(
                                  'Familia: ${order.family?.trim().isEmpty ?? true ? 'SIN ASIGNAR' : order.family!.toUpperCase()}',
                                  order.family?.trim().isEmpty ?? true
                                      ? Colors.redAccent
                                      : Colors.tealAccent,
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
                headerTrailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (order.estado.contains('3')) ...[
                      OutlinedButton(
                        onPressed: () =>
                            _updateStatus('4', allowWorkflowAction: true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(
                            color: Colors.redAccent,
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Parar',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (order.estado.contains('4')) ...[
                      ElevatedButton(
                        onPressed: () =>
                            _updateStatus('3', allowWorkflowAction: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyan,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Reanudar',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ElevatedButton(
                      onPressed: order.estado.contains('5')
                          ? null
                          : () => _updateStatus('5', allowWorkflowAction: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(0, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Finalizar',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                height: topCardHeight,
              ),
            ),
            SizedBox(
              width: linesAndServicesWidth,
              child: _buildSummaryCard(
                theme,
                'Lineas de la orden',
                _buildLinesPreview(theme, lines, order.family),
                count: lines.length,
                height: topCardHeight,
              ),
            ),
            SizedBox(
              width: linesAndServicesWidth,
              child: _buildSummaryCard(
                theme,
                'Servicios de montaje',
                _buildServicesPreview(theme),
                count: _services.length,
                height: topCardHeight,
              ),
            ),
            SizedBox(
              width: infoAndObsWidth,
              child: _buildSummaryCard(
                theme,
                'Observaciones',
                _buildObservacionesPreview(theme),
                onTap: () => _obsFocusNode.requestFocus(),
                headerTrailing: IconButton(
                  icon: const Icon(Icons.add_comment_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _obsFocusNode.requestFocus(),
                  tooltip: 'Añadir observación',
                ),
                count: _observations.length,
                height: topCardHeight,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard(
    ThemeData theme,
    String title,
    Widget body, {
    bool selected = false,
    VoidCallback? onTap,
    int? count,
    double? height,
    Widget? headerTrailing,
  }) {
    final content = Container(
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary.withOpacity(0.12)
            : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary.withOpacity(0.9)
              : Colors.white10,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              if (headerTrailing != null) ...[
                const SizedBox(width: 8),
                headerTrailing,
              ],
              if (count != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.7),
                    ),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(child: body),
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        focusNode: FocusNode(canRequestFocus: false),
        child: content,
      ),
    );
  }

  (String, Color) _mapEstado(String rawEstado) {
    if (rawEstado.isEmpty) return ('Desconocido', Colors.grey);
    var text = rawEstado;
    Color color = Colors.grey;
    if (text.contains('1')) {
      text = 'Validada';
      color = Colors.blue;
    } else if (text.contains('2')) {
      text = 'Pendiente';
      color = Colors.orange;
    } else if (text.contains('3')) {
      text = 'En Ejecucion';
      color = Colors.cyan;
    } else if (text.contains('4')) {
      text = 'Parada';
      color = Colors.red;
    } else if (text.contains('5')) {
      text = 'Finalizada';
      color = Colors.green;
    } else if (text.contains('6')) {
      text = 'Facturada';
      color = Colors.purple;
    }
    return (text, color);
  }

  String _formatOrderNbr(String nbr) {
    final clean = nbr.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.length == 9) {
      return '${clean.substring(0, 2)}-${clean.substring(2, 7)}-${clean.substring(7, 9)}';
    }
    return nbr;
  }

  String _normalizeText(String s) {
    var t = (s ?? '').toUpperCase();
    // Replace common Spanish accents/characters with ASCII equivalents
    t = t
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ñ', 'N');
    // Remove any non-alphanumeric/space characters
    t = t.replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ');
    // Collapse whitespace
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  (String, Color) _mapPrioridad(String rawPrioridad) {
    if (rawPrioridad.isEmpty) return ('Baja', Colors.grey);
    var text = rawPrioridad;
    Color color = Colors.grey;
    if (text.contains('1')) {
      text = 'Alta';
      color = Colors.redAccent;
    } else if (text.contains('2')) {
      text = 'Media';
      color = Colors.orangeAccent;
    } else if (text.contains('3')) {
      text = 'Baja';
      color = Colors.greenAccent;
    }
    return (text, color);
  }

  bool _isSerigrafiadoFamily() {
    final family = (_detail?.agentOrder.family ?? '').trim().toUpperCase();
    return family.contains('SERIGRAF');
  }

  bool _hasArchivosAttached() => _photos.isNotEmpty;
  bool _hasXlsxAttached() {
    return _photos.any((photo) {
      final path = (photo.filePath.isNotEmpty ? photo.filePath : photo.fileName)
          .toLowerCase();
      return path.endsWith('.xlsx') || path.endsWith('.xls');
    });
  }

  bool _hasQualityEvidence() =>
      _photos.any((p) => _isImageFile(p) || _isPdfFile(p));

  Widget _buildMiniBadge(String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.7)),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  bool _showPersistentScrollbar(BuildContext context) {
    if (kIsWeb) return true;
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
  }

  Widget _buildLinesPreview(
    ThemeData theme,
    List<dynamic> lines,
    String? family,
  ) {
    if (lines.isEmpty) {
      return SelectableText(
        'Sin lineas disponibles',
        style: TextStyle(color: theme.hintColor),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Familia: ${family ?? 'No asignada'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Scrollbar(
            thumbVisibility: _showPersistentScrollbar(context),
            child: ListView.separated(
              padding: const EdgeInsets.only(right: 12, top: 8),
              itemCount: lines.length,
              separatorBuilder: (context, index) => Divider(
                height: 12,
                color: theme.dividerColor.withOpacity(0.05),
              ),
              itemBuilder: (context, index) {
                final line = lines[index];
                final sku = line['SKU']?.toString() ?? '-';
                final desc =
                    (line['DESCRIP1'] ?? line['description'])?.toString() ?? '';
                final qtyRaw = line['QTY_ORD'];
                final qty = (qtyRaw is num)
                    ? qtyRaw.formattedInt
                    : qtyRaw?.toString() ?? '0';

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 3,
                      height: 32,
                      margin: const EdgeInsets.only(top: 2, right: 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface,
                              ),
                              children: [
                                TextSpan(
                                  text: sku,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const TextSpan(text: ' | '),
                                TextSpan(
                                  text: 'Qty: $qty',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (desc.isNotEmpty)
                            Text(
                              desc,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 10,
                                color: theme.hintColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServicesPreview(ThemeData theme) {
    if (_services.isEmpty) {
      return SelectableText(
        'Sin servicios detectados',
        style: TextStyle(color: theme.hintColor),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Scrollbar(
            thumbVisibility: _showPersistentScrollbar(context),
            child: ListView.separated(
              padding: const EdgeInsets.only(right: 12, top: 4),
              itemCount: _services.length,
              separatorBuilder: (context, index) => Divider(
                height: 12,
                color: theme.dividerColor.withOpacity(0.05),
              ),
              itemBuilder: (context, index) {
                final svc = _services[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 8),
                      child: Icon(
                        Icons.settings_suggest_rounded,
                        size: 14,
                        color: theme.colorScheme.primary.withOpacity(0.7),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            svc.skuConfig ?? '-',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            svc.description ?? 'Sin descripción',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildObservacionesPreview(ThemeData theme) {
    return Column(
      children: [
        Expanded(
          child: Scrollbar(
            thumbVisibility: _showPersistentScrollbar(context),
            child: _observations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: theme.hintColor.withOpacity(0.15),
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sin observaciones',
                          style: TextStyle(
                            color: theme.hintColor,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _observations.length,
                    padding: const EdgeInsets.only(right: 12, top: 4),
                    separatorBuilder: (context, index) => Divider(
                      height: 20,
                      color: theme.dividerColor.withOpacity(0.05),
                    ),
                    itemBuilder: (context, index) {
                      final obs = _observations[index];
                      final author = (obs.author ?? 'Sin autor').trim();
                      final canManage = _canManageObservations;
                      final dateStr = obs.createdAt != null
                          ? DateFormat('dd/MM HH:mm').format(obs.createdAt!)
                          : '';

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: 10),
                            child: Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 14,
                              color: theme.hintColor.withOpacity(0.5),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      author,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      dateStr,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: theme.hintColor,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  obs.body ?? '',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 14),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: obs.body ?? ''),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Copiado')),
                                  );
                                },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                splashRadius: 16,
                                tooltip: 'Copiar',
                              ),
                              if (canManage) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                  ),
                                  onPressed: () => _editObservation(obs),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  splashRadius: 16,
                                  tooltip: 'Editar',
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 16,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () =>
                                      _confirmDeleteObservation(obs),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  splashRadius: 16,
                                  tooltip: 'Eliminar',
                                ),
                              ],
                            ],
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _obsController,
                  focusNode: _obsFocusNode,
                  onSubmitted: (_) => _addObservation(),
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'Escribe una observación...',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.send_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                onPressed: _addObservation,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool get _canManageObservations {
    final role = _normalizedRole();
    return role == 'admin' ||
        role == 'chief' ||
        role == 'technician' ||
        role.contains('clerc') ||
        role.contains('tech');
  }

  Future<void> _editObservation(AgentOrderObservation obs) async {
    if (!_canManageObservations || _orderOpsService == null || _detail == null)
      return;
    final controller = TextEditingController(text: obs.body ?? '');
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar observación'),
        content: TextField(
          controller: controller,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated == null) return;
    final text = updated.trim();
    if (text.isEmpty) return;

    setState(() => _loading = true);
    try {
      final author = ApiService.instance?.currentUser?.username;
      final ok = await _orderOpsService!.updateObservation(
        _detail!.agentOrder.idnbr,
        obs.id,
        text,
        author: author,
      );
      if (ok) {
        await _loadData();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Observación actualizada')),
          );
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo actualizar la observación'),
            ),
          );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmDeleteObservation(AgentOrderObservation obs) async {
    if (!_canManageObservations || _orderOpsService == null || _detail == null)
      return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar observación'),
        content: const Text(
          '¿Seguro que desea eliminar esta observación? Esta acción quedará registrada en el log.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      final success = await _orderOpsService!.deleteObservation(
        _detail!.agentOrder.idnbr,
        obs.id,
      );
      if (success) {
        await _loadData();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Observación eliminada')),
          );
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo eliminar la observación')),
          );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildCard({
    required ThemeData theme,
    required String title,
    required Widget child,
    List<Widget>? actions,
    double? height,
  }) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder(theme)),
        boxShadow: [
          BoxShadow(
            color: _cardShadow(theme),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _cardHeaderFill(theme),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (actions != null) ...actions,
              ],
            ),
          ),
          if (height != null)
            Expanded(
              child: Padding(padding: const EdgeInsets.all(16.0), child: child),
            )
          else
            Padding(padding: const EdgeInsets.all(16.0), child: child),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 13,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Color _panelItemFill(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return isDark
        ? Colors.white.withOpacity(0.03)
        : theme.colorScheme.primary.withOpacity(0.05);
  }

  Color _panelItemBorder(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return isDark
        ? Colors.white24
        : theme.colorScheme.outline.withOpacity(0.35);
  }

  Color _cardHeaderFill(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return isDark
        ? Colors.black26
        : theme.colorScheme.primary.withOpacity(0.08);
  }

  Color _cardBorder(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return isDark
        ? Colors.white12
        : theme.colorScheme.outline.withOpacity(0.32);
  }

  Color _cardShadow(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return isDark ? Colors.black26 : Colors.black12;
  }

  Widget _buildHeaderCard(ThemeData theme) {
    final order = _detail!.agentOrder;
    final isTablet = _isTabletWidth(context);

    // Map Estado to User Logic
    // 1=Validada,2=Pendiente,3=En Ejecución,4=Parada,5=Finalizada,6=Facturada
    String estadoText = order.estado;
    Color estadoColor = Colors.grey;
    if (estadoText.contains('1')) {
      estadoText = 'Validada';
      estadoColor = Colors.blue;
    } else if (estadoText.contains('2')) {
      estadoText = 'Pendiente';
      estadoColor = Colors.orange;
    } else if (estadoText.contains('3')) {
      estadoText = 'En Ejecución';
      estadoColor = Colors.cyan;
    } else if (estadoText.contains('4')) {
      estadoText = 'Parada';
      estadoColor = Colors.red;
    } else if (estadoText.contains('5')) {
      estadoText = 'Finalizada';
      estadoColor = Colors.green;
    } else if (estadoText.contains('6')) {
      estadoText = 'Facturada';
      estadoColor = Colors.purple;
    }

    // Map Prioridad to User Logic
    // 1=Alta, 2=Media, 3=Baja
    String prioText = order.prioridad;
    Color prioColor = Colors.grey;
    if (prioText.contains('1')) {
      prioText = 'Alta';
      prioColor = Colors.redAccent;
    } else if (prioText.contains('2')) {
      prioText = 'Media';
      prioColor = Colors.orangeAccent;
    } else if (prioText.contains('3')) {
      prioText = 'Baja';
      prioColor = Colors.greenAccent;
    }

    final isValidada = order.estado.contains('1');
    final isPendiente = order.estado.contains('2');

    final currentFamily = _sessionActiveFamily ?? order.family;
    // Multi-service visibility fix: show all assigned families if available
    final familyText = order.subfamilies.isNotEmpty 
        ? order.subfamiliesDisplay 
        : ((currentFamily?.trim().isEmpty ?? true) ? 'SIN ASIGNAR' : currentFamily!);
          
    final subCount = order.subfamilies.length;
    final familyLabel = subCount > 1 
        ? 'Servicios ($subCount)' 
        : 'Familia';

    final doneCount = order.completedFamilies.length;
    final progressText = subCount > 1 ? ' ($doneCount/$subCount)' : '';

    return _buildCard(
      theme: theme,
      title: 'Información de la Orden',
      actions: [
        if (isValidada || isPendiente)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilledButton.icon(
              onPressed: () => _updateStatus('3'),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Comenzar Orden'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.tealAccent,
                foregroundColor: Colors.black,
              ),
            ),
          ),
        if (order.estado.contains('3') || order.estado.contains('4'))
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilledButton.icon(
              onPressed: () => _updateStatus('5'),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Finalizar Orden'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
              ),
            ),
          ),
        if (order.estado.contains('3'))
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilledButton.icon(
              onPressed: () => _updateStatus('4'),
              icon: const Icon(Icons.pause),
              label: const Text('Parar Orden'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        if (order.estado.contains('5') &&
            (order.family ?? '').trim().toUpperCase() == 'CAMBIO DE SERIAL' &&
            !_hasXlsxAttached())
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilledButton.icon(
              onPressed: () async {
                if (!mounted) return;
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Adjuntando Excel...')),
                );
                try {
                  await _exportFinalSerialFileToSftpAndAttachArchivo();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Archivo adjuntado correctamente'),
                      ),
                    );
                    await _loadData();
                  }
                } catch (e) {
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error adjuntando XLSX: $e')),
                    );
                }
              },
              icon: const Icon(Icons.attach_file),
              label: const Text('Adjuntar XLSX'),
            ),
          ),
      ],
      child: Wrap(
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: isTablet ? 20 : 16,
        runSpacing: isTablet ? 12 : 12,
        children: [
          _buildInfoItem('Cliente', order.customer),
          _buildInfoItem(
            'Fecha',
            order.orderDate != null
                ? DateFormat('yyyy-MM-dd').format(order.orderDate!)
                : '-',
          ),
          _buildBadgeItem(
            'Estado',
            estadoText,
            estadoColor,
            onTap: _canEditOrderMeta
                ? () => _showStatusPicker(order.estado)
                : null,
          ),
          _buildBadgeItem('Prioridad', prioText, prioColor),
          _buildBadgeItem(
            'Proyecto',
            (_activeProyectoName ?? order.proyecto)?.trim().isNotEmpty == true
                ? (_activeProyectoName ?? order.proyecto)!
                : 'SIN PROYECTO',
            (_activeProyectoName ?? order.proyecto)?.trim().isNotEmpty == true
                ? Colors.indigoAccent
                : Colors.grey,
            onTap: _canEditProyectoOrFamily
                ? () => _showProyectoPicker(order.proyecto ?? '')
                : null,
          ),
          _buildBadgeItem(
            familyLabel,
            familyText + progressText,
            Colors.orange,
            onTap: _canEditProyectoOrFamily
                ? () => _showFamilyPicker(order.family ?? '')
                : null,
          ),
          if (subCount > 1 && order.estado.contains('3'))
            _buildBadgeItem(
              'Enfoque',
              'Cambiar de Servicio',
              Colors.tealAccent,
              onTap: () async {
                final choice = await showDialog<String>(
                  context: context,
                  builder: (context) => FamilySelectionDialog(
                    families: order.subfamilies.where((f) => !order.completedFamilies.contains(f)).toList(),
                    title: 'Cambiar Enfoque de Sesión',
                    currentFamily: _sessionActiveFamily,
                  ),
                );
                if (choice != null && mounted) {
                  setState(() => _sessionActiveFamily = choice);
                }
              },
            ),
          _buildBadgeItem(
            'Asignado',
            order.assignedToName ?? order.assignedTo ?? 'SIN ASIGNAR',
            order.assignedTo != null ? Colors.orange : Colors.grey,
            onTap: _isPrivilegedRole
                ? () => _showAssigneePicker(order.assignedTo)
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _showAssigneePicker(String? currentAssignee) async {
    if (!_isPrivilegedRole) return;
    if (_orderOpsService == null) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    List<Map<String, String>> assignees = [];
    try {
      assignees = await _orderOpsService!.getIngramUsers();
    } catch (e) {
      debugPrint('Error fetching assignees: $e');
    }

    if (mounted) Navigator.pop(context); // Close loading

    if (assignees.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontraron usuarios de Ingram')),
        );
      }
      return;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) => Material(
            color: const Color(0xFF1A1A2E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Asignar Orden',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: assignees.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return ListTile(
                          leading: const Icon(Icons.person_off, color: Colors.grey),
                          title: const Text('Sin asignar', style: TextStyle(color: Colors.white)),
                          onTap: () {
                            Navigator.pop(context);
                            _updateAssignment(null, null);
                          },
                        );
                      }
                      final user = assignees[index - 1];
                      final username = user['username']!;
                      final name = user['name']!;
                      
                      return ListTile(
                        leading: const Icon(Icons.person, color: Colors.blueAccent),
                        title: Text(name, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(username, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                        trailing: currentAssignee == username
                            ? const Icon(Icons.check, color: Colors.greenAccent)
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          _updateAssignment(username, name);
                        },
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

  Future<void> _updateAssignment(String? username, String? name) async {
    if (_orderOpsService == null) return;
    setState(() => _loading = true);
    try {
      final ok = await _orderOpsService!.updateAgentOrder(
        widget.orderId,
        assignedTo: username,
        assignedToName: name,
      );
      if (ok) {
        await _loadData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al actualizar asignación')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showFamilyPicker(String currentFamily) async {
    if (!_canEditProyectoOrFamily) return;
    if (_orderOpsService == null) return;
    const extraFamilies = <String>['SERIGRAFIADO', 'MANIPULACIÓN Y ETIQUETADO'];

    List<String> families = [];
    try {
      families = await _orderOpsService!.getCatalogFamilies();
    } catch (e) {
      debugPrint('Error fetching families: $e');
    }

    // Consistency fix: ensure catalog list includes currently assigned subfamilies
    families = {...families, ..._detail!.agentOrder.subfamilies}.toList();
    final order = _detail!.agentOrder;
    // Sync fix: combine primary family and all subfamilies for the menu view
    final currentSelection = {
      if (order.family != null && order.family!.isNotEmpty) order.family!,
      ...order.subfamilies,
    }.toList();

    if (!mounted) return;

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => MultiFamilySelectionDialog(
        allFamilies: families,
        initiallySelected: currentSelection,
        title: 'Asignar Servicios (Subfamilias)',
      ),
    );

    if (result != null) {
      await _updateSubfamilies(result);
    }
  }

  Future<void> _updateSubfamilies(List<String> subfamilies) async {
    if (!_canEditProyectoOrFamily) return;
    if (_orderOpsService == null || _detail == null) return;

    setState(() => _loading = true);
    try {
      // Sync fix: primary family should always be part of the subfamilies list
      String? primaryFamily = _detail!.agentOrder.family;
      
      if (subfamilies.isEmpty) {
        primaryFamily = '';
      } else if (primaryFamily == null || primaryFamily.isEmpty || !subfamilies.contains(primaryFamily)) {
        // If current primary is gone or missing, pick the first from the new selection
        primaryFamily = subfamilies.first;
      }

      final ok = await _orderOpsService!.updateAgentOrder(
        _detail!.agentOrder.idnbr,
        family: primaryFamily,
        subfamilies: subfamilies,
        reason: 'Sync subfamilias: ${subfamilies.join(", ")}',
      );

      if (ok) {
        await _loadData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al actualizar servicios')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateFamily(String family) async {
    if (!_canEditProyectoOrFamily) return;
    if (_orderOpsService == null || _detail == null) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Actualizando familia...')));

    try {
      final success = await _orderOpsService!.updateAgentOrder(
        _detail!.agentOrder.idnbr,
        family: family,
        reason: 'Cambio manual de familia a: $family',
      );

      if (success) {
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Familia actualizada correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showProyectoPicker(String currentProyecto) async {
    if (!_canEditProyectoOrFamily) return;
    if (_orderOpsService == null) return;

    List<Proyecto> proyectos = [];
    try {
      proyectos = await _orderOpsService!.getProyectos();
    } catch (e) {
      debugPrint('Error fetching proyectos: $e');
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) => Material(
            color: const Color(0xFF1A1A2E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'Enlazar con Proyecto',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  if (currentProyecto.isNotEmpty)
                    ListTile(
                      leading: const Icon(
                        Icons.link_off,
                        color: Colors.redAccent,
                      ),
                      title: const Text(
                        'Desvincular Proyecto',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _updateProyecto(proyectoNombre: '');
                      },
                    ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: proyectos.length,
                      itemBuilder: (context, index) {
                        final p = proyectos[index];
                        final isSel = p.nombre == currentProyecto;
                        return ListTile(
                          leading: Icon(
                            Icons.assignment_outlined,
                            color: isSel ? Colors.indigoAccent : Colors.white70,
                          ),
                          title: Text(
                            p.nombre,
                            style: TextStyle(
                              color: isSel ? Colors.indigoAccent : Colors.white,
                              fontWeight: isSel
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: isSel
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.indigoAccent,
                                )
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            if (p.nombre != currentProyecto) {
                              _updateProyecto(
                                proyectoNombre: p.nombre,
                                proyectoId: p.id,
                                reasonLabel: p.nombre,
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _updateProyecto({
    required String proyectoNombre,
    int? proyectoId,
    String? reasonLabel,
  }) async {
    if (!_canEditProyectoOrFamily) return;
    if (_orderOpsService == null || _detail == null) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Actualizando proyecto...')));

    try {
      final success = await _orderOpsService!.updateAgentOrder(
        _detail!.agentOrder.idnbr,
        proyecto: proyectoId == null ? '' : null,
        proyectoId: proyectoId,
        reason: 'Relación con proyecto: ${reasonLabel ?? proyectoNombre}',
      );

      if (success) {
        if (mounted) {
          setState(() {
            _activeProyectoId = proyectoId;
            _activeProyectoName = proyectoNombre.trim().isEmpty
                ? null
                : proyectoNombre;
          });
        }
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Proyecto vinculado correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showStatusPicker(String currentEstado) {
    if (!_canEditOrderMeta) return;
    debugPrint('Opening status picker. Current estado: $currentEstado');
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Cambiar Estado de la Orden',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const Divider(height: 1, color: Colors.white10),
            _statusOption('1', 'Validada', Colors.blue, currentEstado),
            _statusOption('2', 'Pendiente', Colors.orange, currentEstado),
            _statusOption('3', 'En Ejecución', Colors.cyan, currentEstado),
            _statusOption('4', 'Parada', Colors.red, currentEstado),
            _statusOption('5', 'Finalizada', Colors.green, currentEstado),
            _statusOption('6', 'Facturada', Colors.purple, currentEstado),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _statusOption(String code, String label, Color color, String current) {
    final isSelected = current.contains(code);
    return ListTile(
      focusNode: FocusNode(canRequestFocus: false),
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? color : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected ? Icon(Icons.check, color: color) : null,
      onTap: () {
        debugPrint('Selected status option: $code ($label)');
        Navigator.pop(context);
        if (!isSelected) {
          _updateStatus(code);
        } else {
          debugPrint('Status is already $code, skipping update.');
        }
      },
    );
  }

  Future<void> _updateStatus(
    String code, {
    bool allowWorkflowAction = false,
  }) async {
    debugPrint(
      'Updating status to: $code for order: ${_detail?.agentOrder.idnbr}',
    );
    if (_detail == null || _orderOpsService == null) {
      debugPrint('Error: _detail or _orderOpsService is null');
      return;
    }

    final order = _detail!.agentOrder;
    final allPossibleFamilies = [
      if (order.family != null && order.family!.isNotEmpty) order.family!,
      ...order.subfamilies,
    ];

    // Case: Moving to En Ejecución (3)
    if (code == '3' && allPossibleFamilies.length >= 1) {
      if (_sessionActiveFamily != null && allPossibleFamilies.contains(_sessionActiveFamily)) {
        // Already have a session family, just update state to 3
        setState(() => _loading = true);
        try {
          final ok = await _orderOpsService!.updateAgentOrder(
            order.idnbr,
            estado: '3',
            family: _sessionActiveFamily,
          );
          if (ok) await _loadData();
          return;
        } catch (e) {
          debugPrint('Error starting order: $e');
          setState(() => _loading = false);
          return;
        }
      }

      final selectedFamily = await showDialog<String>(
        context: context,
        builder: (context) => FamilySelectionDialog(
          families: allPossibleFamilies,
          title: 'Iniciar Servicio',
          currentFamily: _sessionActiveFamily ?? order.family,
        ),
      );

      if (selectedFamily == null) return; // User cancelled

      setState(() => _loading = true);
      try {
        final ok = await _orderOpsService!.updateAgentOrder(
          order.idnbr,
          estado: '3',
          family: selectedFamily,
        );
        if (ok) {
          setState(() => _sessionActiveFamily = selectedFamily);
          await _loadData();
        }
        return;
      } catch (e) {
        debugPrint('Error starting subfamily: $e');
        setState(() => _loading = false);
        return;
      }
    }

    // Case: Finishing (5) - Check for subfamilies loop
    if (code == '5') {
      final currentToMarkDone = _sessionActiveFamily ?? order.family;
      final pendingFamilies = allPossibleFamilies
          .where(
            (f) => !order.completedFamilies.contains(f) && f != currentToMarkDone,
          )
          .toList();

      if (pendingFamilies.isNotEmpty) {
        // Partial completion: current active family is done
        final nextFamily = await showDialog<String>(
          context: context,
          builder: (context) => FamilySelectionDialog(
            families: pendingFamilies,
            title: 'Servicio Finalizado. ¿Continuar?',
          ),
        );

        // User can choose next or just stay in state 3 with no focus
        setState(() => _loading = true);
        try {
          final newCompleted = {
            ...order.completedFamilies,
            if (currentToMarkDone != null) currentToMarkDone,
          }.toList();
          
          final ok = await _orderOpsService!.updateAgentOrder(
            order.idnbr,
            estado: '3', // Stay in execution
            family: nextFamily ?? order.family,
            completedFamilies: newCompleted,
          );
          if (ok) {
            setState(() => _sessionActiveFamily = nextFamily);
            await _loadData();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    nextFamily != null 
                      ? 'Servicio finalizado. Iniciando: $nextFamily'
                      : 'Servicio finalizado. Orden pendiente de otros servicios.'
                  ),
                ),
              );
            }
          }
          return;
        } catch (e) {
          debugPrint('Error transitioning to next subfamily: $e');
          setState(() => _loading = false);
          return;
        }
      }
    }

    if (!_canEditOrderMeta && !allowWorkflowAction) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No tienes permisos para cambiar estado o familia'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (code == '5' && !_hasQualityEvidence()) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Necesitas adjuntar al menos una foto en Registro de Calidad para poder finalizar la orden',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Guardando cambios...'),
          duration: Duration(seconds: 1),
        ),
      );
    }

    try {
      final result = await _orderOpsService!.updateAgentOrderWithResult(
        _detail!.agentOrder.idnbr,
        estado: code,
      );
      debugPrint('Update status success: ${result.ok}');
      if (result.ok) {
        if (code == '5') {
          await _exportFinalSerialFileToSftpAndAttachArchivo();
        }
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Estado actualizado y guardado correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        String backendMessage =
            result.error ?? 'El servidor no pudo guardar el estado';
        final body = result.body;
        if (body is Map<String, dynamic>) {
          if (body['detail'] != null) {
            backendMessage = body['detail'].toString();
          } else if (body['message'] != null) {
            backendMessage = body['message'].toString();
          } else if (body['error'] != null) {
            backendMessage = body['error'].toString();
          } else if (body['non_field_errors'] is List &&
              (body['non_field_errors'] as List).isNotEmpty) {
            backendMessage = (body['non_field_errors'] as List).first
                .toString();
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error actualizando estado: $backendMessage'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Update status error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de red al actualizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String? _firstNonEmptyString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  Future<void> _exportFinalSerialFileToSftpAndAttachArchivo() async {
    if (!mounted || _isExporting) return;

    setState(() => _isExporting = true);

    try {
      final currentDetail = _detail;
      if (currentDetail == null || _orderOpsService == null) return;

      final order = currentDetail.agentOrder;
      final family = (order.family ?? '').trim();
      final nf = _normalizeText(family);
      final isCambioSerial = nf.contains('CAMBIO') && nf.contains('SERIAL');
      final isManipulacionEtq =
          nf.contains('MANIPUL') && nf.contains('ETIQUETADO');
      if (!isCambioSerial && !isManipulacionEtq) return;

      final client = ApiService.instance?.client;
      if (client == null) return;

      final normalizedOrder = _formatOrderNbr(order.orderNbr).trim();
      if (normalizedOrder.isEmpty) return;

      final enc = Uri.encodeQueryComponent(normalizedOrder);
      List<int>? bytes;

      // Step 1: Export bytes
      try {
        if (isManipulacionEtq) {
          final rawOrder = Uri.encodeQueryComponent(
            order.orderNbr ?? normalizedOrder,
          );
          final fallbackRes = await client.getBytes(
            '/serials/matches/export?num_orden=$rawOrder',
          );
          if (fallbackRes.ok && fallbackRes.body is List<int>) {
            bytes = List<int>.from(fallbackRes.body as List<int>);
          }
        } else {
          final expRes = await client.getBytes(
            '/serials/export-serial-changes?nr_orden=$enc',
          );
          if (expRes.ok && expRes.body is List<int>) {
            bytes = List<int>.from(expRes.body as List<int>);
          }
        }
      } catch (e) {
        debugPrint('OrderDetail: export bytes error: $e');
      }

      final fileName = '$normalizedOrder.xlsx';

      // Step 2: Check existence
      final exists = _photos.any((p) {
        final name = (p.fileName).trim();
        final path = (p.filePath).trim();
        if (name.isNotEmpty && name == fileName) return true;
        if (path.isNotEmpty && path.endsWith(fileName)) return true;
        return false;
      });
      if (exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Archivo $fileName ya existe; no se exporta.'),
            ),
          );
        }
        return;
      }

      // Step 3: Upload to Archivos
      bool attached = false;
      if (bytes != null && bytes.isNotEmpty) {
        try {
          attached = await _orderOpsService!.uploadPhoto(
            order.idnbr,
            fileName,
            bytes,
          );
        } catch (e) {
          debugPrint('OrderDetail: uploadPhoto exception: $e');
        }
      }

      // Step 4: Finish order (SFTP)
      try {
        final targetOrderNo = isManipulacionEtq
            ? (order.orderNbr ?? normalizedOrder)
            : normalizedOrder;

        final exportRes = await client.post(
          '/serials/finish-order-upload',
          jsonBody: {
            'nr_orden': targetOrderNo,
            'familia': (order.family ?? '').trim().toUpperCase(),
          },
        );

        if (exportRes.ok && !attached && exportRes.body is Map) {
          final body = Map<String, dynamic>.from(exportRes.body as Map);
          final filePath = _firstNonEmptyString(body, const [
            'file_path',
            'path',
            'excel_path',
            'export_path',
            'archivo_path',
            'relative_path',
          ]);
          final returnedName =
              _firstNonEmptyString(body, const [
                'file_name',
                'filename',
                'name',
                'excel_file',
              ]) ??
              fileName;

          if (filePath != null && filePath.isNotEmpty) {
            await _orderOpsService!.addArchivoManual(
              order.idnbr,
              returnedName,
              filePath,
              author: ApiService.instance?.currentUser?.username,
            );
          }
        }
      } catch (e) {
        debugPrint('OrderDetail: finish-order-upload exception: $e');
      }
    } catch (e) {
      debugPrint('OrderDetail: export whole process catch: $e');
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _promptForActiveService() async {
    if (_detail == null || !mounted) return;
    final order = _detail!.agentOrder;
    
    // Only prompt if in execution and there are multiple options
    if (!order.estado.contains('3')) {
      if (_sessionActiveFamily != null) {
        setState(() => _sessionActiveFamily = null);
      }
      return;
    }

    final available = order.subfamilies.where((f) => !order.completedFamilies.contains(f)).toList();
    if (available.isEmpty) return;

    if (_sessionActiveFamily == null || !available.contains(_sessionActiveFamily)) {
      if (available.length == 1) {
        setState(() => _sessionActiveFamily = available.first);
      } else {
        // Show dialog to choose
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => FamilySelectionDialog(
            families: available,
            title: '¿Qué servicio vas a realizar?',
            currentFamily: _sessionActiveFamily ?? order.family,
          ),
        );
        if (choice != null && mounted) {
          setState(() => _sessionActiveFamily = choice);
        } else if (_sessionActiveFamily == null && mounted) {
          // Default to the global family if it's in the available list
          setState(() => _sessionActiveFamily = available.contains(order.family) ? order.family : available.first);
        }
      }
    }
  }

  Widget? _resolveEmbeddedServiceWidget() {
    if (_detail == null) return null;

    final order = _detail!.agentOrder;
    final family = (_sessionActiveFamily ?? order.family ?? '').trim().toUpperCase();
    if (family == 'ORDENADORES SERVIDOR' ||
        family == 'ORDENADORES SERVIDORES') {
      return RegistroServidorScreen(
        isEmbedded: true,
        orderId: widget.orderId,
        initialPrevi: order.orderNbr,
        initialCliente: order.customer,
      );
    }
    if (family == 'MASTERIZACIÓN' || family == 'MASTERIZACION') {
      return PhysicalTablesScreen(orderId: widget.orderId);
    }
    if (family == 'MANIPULACIÓN Y ETIQUETADO') {
      return SerialLinkScreen(
        isEmbedded: true,
        matchOnly: true,
        initialOrderNumber: order.orderNbr,
        orderId: widget.orderId,
      );
    }
    if (family == 'CAMBIO DE SERIAL') {
      return SerialChangeScreen(initialOrderNumber: order.orderNbr);
    }
    if (family == 'XIAOMI ETIQUETADO') {
      return const XiaomiRegistroOrdenScreen();
    }
    return null;
  }

  Widget _buildEmbeddedServicePanel(ThemeData theme) {
    if (_detail == null) return const SizedBox.shrink();

    final order = _detail!.agentOrder;
    final family = (_sessionActiveFamily ?? order.family ?? '').trim().toUpperCase();
    final isEnEjecucion = order.estado.contains('3');
    if (!isEnEjecucion) {
      return const SizedBox.shrink();
    }

    // Serigrafiado workflow
    if (family.contains('SERIGRAF')) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: SerigrafiaPanel(
          order: order,
          detail: _detail,
          service: _orderOpsService,
        ),
      );
    }

    final serviceWidget = _resolveEmbeddedServiceWidget();
    if (serviceWidget == null) {
      final hasFamily = order.family?.trim().isNotEmpty ?? false;
      return _buildCard(
        theme: theme,
        title: 'Panel de servicio',
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                hasFamily ? Icons.help_outline : Icons.warning_amber_rounded,
                size: 64,
                color: hasFamily ? Colors.grey : Colors.orangeAccent,
              ),
              const SizedBox(height: 16),
              Text(
                hasFamily
                    ? 'No hay pantalla configurada para la familia:\n${order.family}'
                    : 'Familia no detectada para esta orden.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _showFamilyPicker(order.family ?? ''),
                icon: const Icon(Icons.edit),
                label: const Text('Asignar Familia Manualmente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent.withOpacity(0.12),
                  foregroundColor: Colors.tealAccent,
                  side: const BorderSide(color: Colors.tealAccent),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: 2500, // safety cap
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: serviceWidget,
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, {int maxLines = 2}) {
    final isTablet = _isTabletWidth(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            label,
            style: TextStyle(color: Colors.white60, fontSize: isTablet ? 11 : 12),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            maxLines: maxLines,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: isTablet ? 14 : 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeItem(
    String label,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) {
    final isTablet = _isTabletWidth(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey, fontSize: isTablet ? 11 : 12),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: BoxConstraints(maxWidth: isTablet ? 600 : 340),
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 8 : 10,
                vertical: isTablet ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                border: Border.all(color: color.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      value.toUpperCase(),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: isTablet ? 12 : 12,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.edit, size: 14, color: color.withOpacity(0.8)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinesCard(ThemeData theme) {
    final sourceOrder = _detail!.sourceOrder;
    if (sourceOrder == null || !sourceOrder.containsKey('lines')) {
      return _buildCard(
        theme: theme,
        title: 'Líneas de la orden',
        child: _buildEmptyState(theme, 'Sin líneas.'),
      );
    }

    final lines = sourceOrder['lines'] as List<dynamic>;

    const double financialCellsWidth = 100 + 100 + 110 + 90 + 120;
    const double baseCellsWidth = 100 + 250 + 80;
    final lineCellsWidth = _canViewFinancialData
        ? baseCellsWidth + financialCellsWidth
        : baseCellsWidth;
    final lineOuterWidth = lineCellsWidth + 4;
    final isDark = theme.brightness == Brightness.dark;
    final headerBg = isDark
        ? Colors.black38
        : theme.colorScheme.surfaceContainerHighest.withOpacity(0.88);
    final rowDivider = theme.dividerColor.withOpacity(isDark ? 0.16 : 0.24);
    final profitPositiveColor = isDark
        ? Colors.tealAccent
        : const Color(0xFF0F766E);
    final profitNegativeColor = isDark
        ? Colors.redAccent
        : const Color(0xFFB91C1C);
    final lowMarginColor = isDark
        ? Colors.orangeAccent
        : const Color(0xFFB45309);
    final mappedCostColor = isDark ? Colors.blueGrey : const Color(0xFF475569);

    return _buildCard(
      theme: theme,
      title: 'Líneas de la orden (${lines.length})',
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: constraints.maxWidth > lineOuterWidth
                    ? constraints.maxWidth
                    : lineOuterWidth,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: lineOuterWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: headerBg,
                            border: const Border(
                              left: BorderSide(
                                color: Colors.transparent,
                                width: 4,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              _headerCell('SKU', 100),
                              _headerCell('Descripción', 250),
                                _headerCell(
                                  'Cant.',
                                  80,
                                  alignment: TextAlign.right,
                                ),
                              if (_canViewFinancialData)
                                _headerCell(
                                  'Coste',
                                  100,
                                  alignment: TextAlign.right,
                                ),
                              if (_canViewFinancialData)
                                _headerCell(
                                  'Precio',
                                  100,
                                  alignment: TextAlign.right,
                                ),
                              if (_canViewFinancialData)
                                _headerCell(
                                  'Beneficio',
                                  110,
                                  alignment: TextAlign.right,
                                ),
                              if (_canViewFinancialData)
                                _headerCell(
                                  'Margen %',
                                  90,
                                  alignment: TextAlign.right,
                                ),
                              if (_canViewFinancialData)
                                _headerCell(
                                  'Total',
                                  120,
                                  alignment: TextAlign.right,
                                ),
                            ],
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 500),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            scrollDirection: Axis.vertical,
                            shrinkWrap: true,
                            itemCount: lines.length,
                            itemBuilder: (context, index) {
                              final line = lines[index];
                              final price =
                                  double.tryParse(
                                    line['UNIT_PRICE']?.toString() ?? '0',
                                  ) ??
                                  0;
                              final unitCost =
                                  double.tryParse(
                                    line['UNIT_COST']?.toString() ?? '0',
                                  ) ??
                                  0;
                              final mappedCost =
                                  double.tryParse(
                                    line['mapped_cost']?.toString() ?? '0',
                                  ) ??
                                  0;
                              final effectiveCost =
                                  unitCost > 0 ? unitCost : mappedCost;
                              final mappedPvd =
                                  double.tryParse(
                                    line['mapped_pvd']?.toString() ?? '0',
                                  ) ??
                                  0;

                              final statusColor = _getPriceColor(
                                actual: price,
                                theoretical: mappedPvd,
                                cost: effectiveCost,
                              );

                              return Container(
                                decoration: BoxDecoration(
                                  color: statusColor?.withOpacity(0.12),
                                  border: Border(
                                    bottom: BorderSide(color: rowDivider),
                                    left: BorderSide(
                                      color: statusColor ?? Colors.transparent,
                                      width: 4,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    _dataCell(
                                      line['SKU']?.toString() ?? '',
                                      100,
                                    ),
                                    _dataCell(
                                      (line['DESCRIP1'] ?? line['description'])
                                              ?.toString() ??
                                          '',
                                      250,
                                    ),
                                    _dataCell(
                                      (double.tryParse(
                                                line['QTY_ORD']?.toString() ??
                                                    '0',
                                              ) ??
                                              0)
                                          .formattedInt,
                                      80,
                                      alignment: TextAlign.right,
                                    ),
                                    if (_canViewFinancialData)
                                      _dataCell(
                                        effectiveCost.asCurrency,
                                        100,
                                        alignment: TextAlign.right,
                                        color: (unitCost == 0 && mappedCost > 0)
                                            ? mappedCostColor
                                            : null,
                                      ),
                                    if (_canViewFinancialData)
                                      _dataCell(
                                        price.asCurrency,
                                        100,
                                        alignment: TextAlign.right,
                                        isBold: statusColor != null,
                                      ),
                                    if (_canViewFinancialData)
                                      _dataCell(
                                        (price - effectiveCost).asCurrency,
                                        110,
                                        alignment: TextAlign.right,
                                        color: (price - effectiveCost) < 0
                                            ? profitNegativeColor
                                            : profitPositiveColor,
                                      ),
                                    if (_canViewFinancialData)
                                      _dataCell(
                                        '${(((price - effectiveCost) / (price != 0 ? price : 1)) * 100).formatted}%',
                                        90,
                                        alignment: TextAlign.right,
                                        color:
                                            price != 0 &&
                                                ((price - effectiveCost) /
                                                        price) <
                                                    0.05
                                            ? lowMarginColor
                                            : Colors.grey,
                                      ),
                                    if (_canViewFinancialData)
                                      _dataCell(
                                        (double.tryParse(
                                                  line['TOTAL']?.toString() ??
                                                      '0',
                                                ) ??
                                                0)
                                            .asCurrency,
                                        120,
                                        alignment: TextAlign.right,
                                        isBold: true,
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(
    String label,
    double width, {
    TextAlign alignment = TextAlign.left,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        label,
        textAlign: alignment,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: isDark
              ? Colors.white70
              : theme.colorScheme.onSurface.withOpacity(0.76),
        ),
      ),
    );
  }

  Widget _dataCell(
    String text,
    double width, {
    bool isBold = false,
    Color? color,
    TextAlign alignment = TextAlign.left,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        text,
        textAlign: alignment,
        style: TextStyle(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontSize: 14,
          color: color,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildServicesCard(ThemeData theme) {
    if (_services.isEmpty) {
      return _buildEmptyState(theme, 'Sin servicios asignados');
    }

    return _buildCard(
      theme: theme,
      title: 'Servicios de Montaje / Extras',
      actions: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Colors.tealAccent),
          tooltip: 'Añadir Servicio Manual',
          focusNode: FocusNode(canRequestFocus: false),
          onPressed: _showAddServiceDialog,
        ),
      ],
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 16,
        children: _services.map((svc) {
          final statusColor = _canViewFinancialData
              ? _getPriceColor(
                  actual: svc.orderUnitPrice ?? 0,
                  theoretical: svc.theoreticalPvd,
                  cost: svc.coste ?? 0,
                )
              : null;

          return Container(
            constraints: const BoxConstraints(maxWidth: 320),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor?.withOpacity(0.1) ?? Colors.black12,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: statusColor?.withOpacity(0.5) ?? Colors.white12,
                width: statusColor != null ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: true,
                  onChanged: (v) {},
                  activeColor: statusColor ?? theme.colorScheme.secondary,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            svc.skuConfig ?? 'SKU',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          if (svc.isManual)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.teal.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.tealAccent),
                              ),
                              child: const Text(
                                'MANUAL',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.tealAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else if (statusColor != null)
                            const Tooltip(
                              message: 'Discrepancia de precio detectada',
                              child: Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange,
                                size: 16,
                              ),
                            ),
                          if (svc.isManual)
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              focusNode: FocusNode(canRequestFocus: false),
                              onPressed: () => _removeManualService(svc),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        svc.description ?? 'Sin descripción',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_canViewFinancialData) ...[
                        const Divider(height: 16, color: Colors.white10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _smallInfo('Coste', '${svc.coste ?? 0} €'),
                            _smallInfo('Margen', '${svc.margen ?? 0}%'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _smallInfo(
                              'PVD Teórico',
                              '${svc.theoreticalPvd ?? 0} €',
                              isBold: true,
                            ),
                            _smallInfo(
                              'Precio Orden',
                              '${svc.orderUnitPrice ?? 0} €',
                              isBold: true,
                            ),
                          ],
                        ),
                      ],
                      if (svc.collectionInfo != null &&
                          svc.collectionInfo!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Collection: ${svc.collectionInfo}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.blueGrey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _smallInfo(
    String label,
    String value, {
    Color? color,
    bool isBold = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color ?? Colors.white,
          ),
        ),
      ],
    );
  }

  Color? _getPriceColor({
    required double actual,
    required double? theoretical,
    required double cost,
  }) {
    if (theoretical == null || theoretical == 0) return null;
    if (actual < cost - 0.05) return Colors.redAccent;
    if ((actual - theoretical).abs() <= 0.05) return Colors.greenAccent;
    return Colors.yellowAccent;
  }

  Widget _buildObservationsCard(ThemeData theme) {
    return _buildCard(
      theme: theme,
      title: 'Observaciones',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _obsController,
                    decoration: const InputDecoration(
                      hintText: 'Añadir nueva observación...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                    maxLines: 2,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton.icon(
                    onPressed: _addObservation,
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_observations.isNotEmpty) ...[
            const Divider(),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _observations.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (ctx, i) {
                final obs = _observations[i];
                final dateStr = obs.createdAt != null
                    ? DateFormat('yyyy-MM-dd HH:mm').format(obs.createdAt!)
                    : '';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(obs.body, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '${obs.author ?? "Usuario"} • $dateStr',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  leading: const Icon(Icons.comment, color: Colors.grey),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQualityQualityCard(ThemeData theme) {
    final imageFiles = _photos
        .where(
          (photo) => _isImageFile(photo) && _photoScope(photo) == 'quality',
        )
        .toList(growable: false);
    return _buildCard(
      theme: theme,
      title: 'Registro de Calidad (Obligatorio)',
      actions: [
        IconButton(
          icon: const Icon(
            Icons.add_a_photo,
            size: 20,
            color: Colors.tealAccent,
          ),
          tooltip: 'Adjuntar foto',
          focusNode: FocusNode(canRequestFocus: false),
          onPressed: _takePhoto,
        ),
      ],
      height: null,
      child: imageFiles.isEmpty
          ? _buildEmptyState(theme, 'No hay fotos registradas.')
          : LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth >= 1200
                    ? 220.0
                    : constraints.maxWidth >= 700
                    ? 200.0
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: imageFiles
                      .map(
                        (file) => SizedBox(
                          width: cardWidth,
                          child: _buildArchivoThumbCard(file),
                        ),
                      )
                      .toList(),
                );
              },
            ),
    );
  }

  Widget _buildArchivosCard(ThemeData theme) {
    final archivoFiles = _photos
        .where((photo) => _photoScope(photo) != 'quality')
        .toList(growable: false);
    final borderColor = _isArchivoDropActive
        ? theme.colorScheme.primary
        : theme.colorScheme.outline.withOpacity(0.5);

    return _buildCard(
      theme: theme,
      title: 'Archivos',
      actions: [
        IconButton(
          icon: const Icon(
            Icons.drive_folder_upload_rounded,
            size: 20,
            color: Colors.tealAccent,
          ),
          tooltip: 'Subir archivo',
          focusNode: FocusNode(canRequestFocus: false),
          onPressed: _uploadArchivo,
        ),
        // Manual attach Excel for Cambio de Serial when order is finalized
        if (_detail != null) ...[
          Builder(
            builder: (ctx) {
              final order = _detail!.agentOrder;
              final family = (order.family ?? '').trim();
              final estado = (order.estado ?? '').toString();
              final normalizedOrder = _formatOrderNbr(order.orderNbr).trim();
              final expectedFileName = '$normalizedOrder.xlsx';
              final lcExpected = expectedFileName.toLowerCase();
              final alreadyAttached = archivoFiles.any((f) {
                final fn = (f.fileName ?? '').toLowerCase();
                final fp = (f.filePath ?? '').toLowerCase();
                // Prefer explicit .xlsx attachments. If any archivo has .xlsx, treat as attached.
                if (fn.endsWith('.xlsx') || fp.endsWith('.xlsx')) return true;
                // Fall back to exact filename match.
                if (fn == lcExpected) return true;
                return false;
              });
              final isFinished = estado.contains('5') || estado.contains('6');
              final nf = _normalizeText(family);
              final isManipulacionEtq =
                  nf.contains('MANIPUL') && nf.contains('ETIQUETADO');
              final isCambioSerial =
                  nf.contains('CAMBIO') && nf.contains('SERIAL');
              if (((isCambioSerial && isFinished) || isManipulacionEtq) &&
                  !alreadyAttached) {
                return IconButton(
                  icon: const Icon(
                    Icons.attach_file,
                    size: 20,
                    color: Colors.amber,
                  ),
                  tooltip: 'Adjuntar XLSX automáticamente',
                  focusNode: FocusNode(canRequestFocus: false),
                  onPressed: () async {
                    // Automatic export and attach without manual input
                    try {
                      ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Adjuntando Excel...')),
                      );
                      await _exportFinalSerialFileToSftpAndAttachArchivo();
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Archivo adjuntado correctamente'),
                        ),
                      );
                      // reload via parent context
                      if (mounted) await _loadData();
                    } catch (e) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Error adjuntando XLSX: $e')),
                      );
                    }
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ],
      height: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _uploadArchivo,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1.5),
                color: _isArchivoDropActive
                    ? theme.colorScheme.primary.withOpacity(0.08)
                    : theme.colorScheme.surface.withOpacity(0.12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.upload_file_rounded,
                    color: _isArchivoDropActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withOpacity(0.75),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isArchivoDropActive
                          ? 'Suelta los archivos para subirlos'
                          : 'Arrastra y suelta 1 o mas archivos aqui, o haz click para seleccionar',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.85),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (archivoFiles.isEmpty)
            _buildEmptyState(theme, 'No hay archivos adjuntos.')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth >= 1200
                    ? 220.0
                    : constraints.maxWidth >= 700
                    ? 200.0
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: archivoFiles
                      .map(
                        (file) => SizedBox(
                          width: cardWidth,
                          child: _buildArchivoThumbCard(file),
                        ),
                      )
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _promptAttachExcelManual() async {
    if (_detail == null || _orderOpsService == null) return;
    final order = _detail!.agentOrder;
    final normalizedOrder = _formatOrderNbr(order.orderNbr).trim();
    final defaultName = '$normalizedOrder.xlsx';

    final pathCtrl = TextEditingController();
    final nameCtrl = TextEditingController(text: defaultName);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adjuntar Excel manualmente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pathCtrl,
              decoration: const InputDecoration(
                labelText: 'Ruta de servidor (ej: /exports/ORDER123.xlsx)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre de archivo (opcional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Adjuntar'),
          ),
        ],
      ),
    );

    nameCtrl.dispose();
    final filePath = pathCtrl.text.trim();
    pathCtrl.dispose();
    if (ok != true) return;
    if (filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se requiere la ruta del archivo en el servidor.'),
        ),
      );
      return;
    }

    final fileName = nameCtrl.text.trim().isNotEmpty
        ? nameCtrl.text.trim()
        : defaultName;
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Adjuntando archivo...')));
      final author = ApiService.instance?.currentUser?.username;
      final okAdd = await _orderOpsService!.addArchivoManual(
        order.idnbr,
        fileName,
        filePath,
        author: author,
      );
      if (okAdd) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Archivo adjuntado correctamente')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo adjuntar el archivo.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error adjuntando archivo: $e')));
    }
  }

  Widget _buildArchivoThumbCard(AgentOrderPhoto file) {
    final isImage = _isImageFile(file);
    final isPdf = _isPdfFile(file);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      focusNode: FocusNode(canRequestFocus: false),
      onTap: () {
        if (isImage) {
          _showPhotoPreview(file);
        } else if (isPdf) {
          _previewPdfFile(file);
        } else {
          _openOrderFile(file);
        }
      },
      child: Container(
        height: 132,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              Positioned.fill(
                child: isImage
                    ? Image.network(
                        '$kBackendBaseUrl/uploads/${file.filePath}',
                        fit: BoxFit.cover,
                        headers: {
                          if (ApiService.instance?.client.accessToken != null)
                            'Authorization':
                                'Bearer ${ApiService.instance!.client.accessToken}',
                        },
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.white38,
                          ),
                        ),
                      )
                    : isPdf
                    ? FutureBuilder<Uint8List?>(
                        future: _getPdfPreviewBytes(file),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          final bytes = snapshot.data;
                          if (bytes == null) {
                            return Container(
                              color: Colors.white,
                              child: const Center(
                                child: Icon(
                                  Icons.picture_as_pdf,
                                  color: Colors.redAccent,
                                  size: 34,
                                ),
                              ),
                            );
                          }
                          return IgnorePointer(
                            child: SfPdfViewer.memory(bytes),
                          );
                        },
                      )
                    : const Center(
                        child: Icon(
                          Icons.insert_drive_file,
                          color: Colors.white70,
                          size: 40,
                        ),
                      ),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: InkWell(
                  onTap: () => _openOrderFile(file),
                  focusNode: FocusNode(canRequestFocus: false),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.download_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 6,
                top: 6,
                child: InkWell(
                  onTap: () => _deleteArchivo(file),
                  focusNode: FocusNode(canRequestFocus: false),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 36,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    // Tag shows whether the archivo is project-general or belongs to this order
                    (file.idnbr == widget.orderId) ? 'Orden' : 'Proyecto',
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
              ),

              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  color: Colors.black54,
                  child: Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List?> _getPdfPreviewBytes(AgentOrderPhoto file) async {
    final cached = _pdfPreviewCache[file.id];
    if (cached != null) {
      return cached;
    }

    try {
      final bytes = await _downloadOrderFileBytes(file);
      _pdfPreviewCache[file.id] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  bool _isImageFile(AgentOrderPhoto photo) {
    final path = (photo.filePath.isNotEmpty ? photo.filePath : photo.fileName)
        .toLowerCase();
    return path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.webp') ||
        path.endsWith('.gif') ||
        path.endsWith('.bmp');
  }

  bool _isPdfFile(AgentOrderPhoto photo) {
    final path = (photo.filePath.isNotEmpty ? photo.filePath : photo.fileName)
        .toLowerCase();
    return path.endsWith('.pdf');
  }

  String _photoScope(AgentOrderPhoto photo) {
    final declared = (photo.scope ?? '').trim().toLowerCase();
    if (declared == 'quality' || declared == 'archivo') {
      return declared;
    }

    final normalizedPath = photo.filePath.replaceAll('\\', '/').toLowerCase();
    if (normalizedPath.startsWith('order_quality/')) return 'quality';

    final normalizedName = photo.fileName.toLowerCase();
    if (normalizedName.startsWith('quality_')) return 'quality';

    return 'archivo';
  }

  Future<Uint8List> _downloadOrderFileBytes(AgentOrderPhoto file) async {
    final token = ApiService.instance?.client.accessToken;
    final url = Uri.parse('$kBackendBaseUrl/uploads/${file.filePath}');
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      return await consolidateHttpClientResponseBytes(response);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _previewPdfFile(AgentOrderPhoto file) async {
    try {
      final bytes = await _downloadOrderFileBytes(file);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(18),
          child: SizedBox(
            width: 920,
            height: 720,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: Colors.black12,
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          file.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(child: SfPdfViewer.memory(bytes)),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      await _openOrderFile(file);
    }
  }

  Future<void> _openOrderFile(AgentOrderPhoto file) async {
    try {
      final bytes = await _downloadOrderFileBytes(file);
      final dir = await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/${file.fileName}');
      await out.writeAsBytes(bytes, flush: true);
      await OpenFilex.open(out.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir el archivo: $e')),
      );
    }
  }

  Future<void> _uploadArchivo() async {
    final platform = defaultTargetPlatform;
    final isDesktop =
        !kIsWeb &&
        (platform == TargetPlatform.macOS ||
            platform == TargetPlatform.windows ||
            platform == TargetPlatform.linux);

    if (!kIsWeb && !isDesktop) {
      final source = await showModalBottomSheet<_ArchivoSource>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Fotos'),
                subtitle: const Text('Seleccionar desde la galería'),
                onTap: () => Navigator.of(ctx).pop(_ArchivoSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open_rounded),
                title: const Text('Archivos'),
                subtitle: const Text('Seleccionar desde la app Archivos'),
                onTap: () => Navigator.of(ctx).pop(_ArchivoSource.files),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;
      final pickedFiles = source == _ArchivoSource.gallery
          ? await _pickArchivoImagesFromGallery()
          : await _pickArchivoFiles();
      await _uploadArchivoBatch(pickedFiles);
      return;
    }

    final pickedFiles = await _pickArchivoFiles();
    await _uploadArchivoBatch(pickedFiles);
  }

  Future<List<_PickedBinaryFile>> _pickArchivoImagesFromGallery() async {
    final picker = ImagePicker();
    final out = <_PickedBinaryFile>[];

    try {
      final images = await picker.pickMultiImage(imageQuality: 90);
      for (final image in images) {
        final bytes = await image.readAsBytes();
        if (bytes.isEmpty) continue;
        final fallback = 'archivo_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final name = image.name.isNotEmpty ? image.name : fallback;
        out.add(_PickedBinaryFile(name: name, bytes: bytes));
      }
      if (out.isNotEmpty) return out;
    } catch (_) {
      // Fall back to single-image picker if multi-image is unavailable.
    }

    try {
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (image == null) return const [];
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) return const [];
      final fallback = 'archivo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final name = image.name.isNotEmpty ? image.name : fallback;
      return [_PickedBinaryFile(name: name, bytes: bytes)];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _uploadDroppedArchivos(List<XFile> droppedFiles) async {
    if (droppedFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Drop detectado, pero no se recibieron archivos.'),
        ),
      );
      return;
    }

    final pickedFiles = <_PickedBinaryFile>[];
    var failedReads = 0;
    for (final dropped in droppedFiles) {
      try {
        List<int> bytes = const [];
        try {
          bytes = await dropped.readAsBytes();
        } catch (_) {
          bytes = const [];
        }
        if (bytes.isEmpty && dropped.path.isNotEmpty) {
          try {
            bytes = await File(dropped.path).readAsBytes();
          } catch (_) {
            bytes = const [];
          }
        }
        if (bytes.isEmpty) continue;
        final fallback = 'archivo_${DateTime.now().millisecondsSinceEpoch}';
        final name = dropped.name.isNotEmpty ? dropped.name : fallback;
        pickedFiles.add(
          _PickedBinaryFile(name: name, bytes: Uint8List.fromList(bytes)),
        );
      } catch (_) {
        failedReads += 1;
      }
    }

    if (pickedFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failedReads > 0
                ? 'Se detectaron ${droppedFiles.length} archivo(s), pero no se pudieron leer.'
                : 'No se detectaron archivos validos en el drop.',
          ),
        ),
      );
      return;
    }

    await _uploadArchivoBatch(pickedFiles);
  }

  Future<void> _uploadArchivoBatch(List<_PickedBinaryFile> pickedFiles) async {
    if (pickedFiles.isEmpty) return;
    if (pickedFiles.any((f) => f.bytes.isEmpty)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo leer uno o mas archivos seleccionados'),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final attachments = pickedFiles
          .map(
            (picked) => MultipartAttachment(
              fieldName: 'files',
              fileName: picked.name.isNotEmpty
                  ? picked.name
                  : 'archivo_${DateTime.now().millisecondsSinceEpoch}',
              bytes: picked.bytes,
            ),
          )
          .toList(growable: false);

      // When uploading from the Order detail, do not register the files
      // under the Proyecto even if the order is linked to one. Attach
      // archivos to the order only by omitting proyectoId.
      final result = await _orderOpsService!.uploadPhotos(
        widget.orderId,
        attachments,
        proyectoId: null,
        scope: 'archivo',
      );
      if (!mounted) return;
      if (result.ok) {
        await _loadData();
        final body = result.body;
        int uploaded = attachments.length;
        int skipped = 0;
        if (body is Map) {
          uploaded = (body['count_uploaded'] as num?)?.toInt() ?? uploaded;
          skipped = (body['count_skipped'] as num?)?.toInt() ?? 0;
        }
        final msg = skipped > 0
            ? 'Subidos $uploaded archivo(s). $skipped duplicado(s) omitido(s).'
            : 'Subidos $uploaded archivo(s) en Archivos.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      } else if (result.statusCode == 409) {
        final body = result.body;
        int skipped = attachments.length;
        if (body is Map) {
          skipped = (body['count_skipped'] as num?)?.toInt() ?? skipped;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se subio ningun archivo: $skipped ya existia(n).',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo subir los archivos')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error subiendo archivo: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<_PickedBinaryFile>> _pickArchivoFiles() async {
    final platform = defaultTargetPlatform;
    final isDesktop =
        !kIsWeb &&
        (platform == TargetPlatform.macOS ||
            platform == TargetPlatform.windows ||
            platform == TargetPlatform.linux);

    if (isDesktop) {
      try {
        final xFiles = await fs.openFiles();
        if (xFiles.isEmpty) return const [];
        final out = <_PickedBinaryFile>[];
        for (final xFile in xFiles) {
          final bytes = await xFile.readAsBytes();
          if (bytes.isEmpty) continue;
          final fallback = 'archivo_${DateTime.now().millisecondsSinceEpoch}';
          final name = xFile.name.isNotEmpty ? xFile.name : fallback;
          out.add(_PickedBinaryFile(name: name, bytes: bytes));
        }
        return out;
      } catch (_) {
        // Fall through to file_picker fallback.
      }
    }

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.any,
    );
    if (picked == null || picked.files.isEmpty) return const [];
    final out = <_PickedBinaryFile>[];
    for (final file in picked.files) {
      final bytes =
          file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null || bytes.isEmpty) continue;
      final fallback = 'archivo_${DateTime.now().millisecondsSinceEpoch}';
      final name = file.name.isNotEmpty ? file.name : fallback;
      out.add(_PickedBinaryFile(name: name, bytes: bytes));
    }
    return out;
  }

  Future<void> _deleteArchivo(AgentOrderPhoto file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar archivo'),
        content: Text('Deseas eliminar ${file.fileName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final ok = await _orderOpsService?.deletePhoto(widget.orderId, file.id);
      if (!mounted) return;
      if (ok == true) {
        _pdfPreviewCache.remove(file.id);
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Archivo eliminado de Archivos')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo eliminar el archivo')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error eliminando archivo: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _takePhoto() async {
    // Hide snackbars immediately to avoid UI clutter
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    _PickedImage? picked;
    try {
      picked = await _pickImageForQuality();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir el selector: $e')),
      );
      return;
    }

    if (picked != null) {
      setState(() => _loading = true);
      try {
        // Attach quality photos to the order only; do not register them
        // under the Proyecto even if the order is linked to one.
        // Ensure filename indicates quality so frontend can classify it
        String name = picked.name;
        final dot = name.lastIndexOf('.');
        final ext = (dot >= 0) ? name.substring(dot) : '.jpg';
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        if (!name.toLowerCase().startsWith('quality_')) {
          name = 'quality_$timestamp$ext';
        }

        final attachment = MultipartAttachment(
          fieldName: 'file',
          fileName: name,
          bytes: picked.bytes,
        );

        final res = await _orderOpsService?.uploadPhotos(
          widget.orderId,
          [attachment],
          proyectoId: null,
          scope: 'quality',
        );

        if (res == null) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al subir la foto (servicio)')),
          );
        } else if (res.ok) {
          await _loadData();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto guardada correctamente')),
          );
        } else {
          setState(() => _loading = false);
          String bodyText = '';
          try {
            bodyText = res.body?.toString() ?? res.error ?? 'unknown';
          } catch (_) {
            bodyText = res.error ?? 'error';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al subir la foto: $bodyText')),
          );
        }
      } catch (e) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se selecciono ninguna imagen.')),
      );
    }
  }

  Future<_PickedImage?> _pickImageForQuality() async {
    final picker = ImagePicker();
    final platform = defaultTargetPlatform;
    final isDesktop =
        !kIsWeb &&
        (platform == TargetPlatform.macOS ||
            platform == TargetPlatform.windows ||
            platform == TargetPlatform.linux);

    if (kIsWeb || isDesktop) {
      try {
        final xFile = await fs.openFile(
          acceptedTypeGroups: const [
            fs.XTypeGroup(
              label: 'images',
              extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
            ),
          ],
        );
        if (xFile == null) return null;
        final bytes = await xFile.readAsBytes();
        if (bytes.isEmpty) return null;
        final name = xFile.name;
        final fallback = 'quality_${DateTime.now().millisecondsSinceEpoch}.jpg';
        return _PickedImage(
          name: name.isNotEmpty ? name : fallback,
          bytes: bytes,
        );
      } catch (_) {
        try {
          final picked = await FilePicker.platform.pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: true,
          );
          if (picked == null || picked.files.isEmpty) return null;
          final file = picked.files.first;
          Uint8List? bytes = file.bytes;
          if (bytes == null && file.path != null) {
            bytes = await File(file.path!).readAsBytes();
          }
          if (bytes == null) return null;
          final fallback =
              'quality_${DateTime.now().millisecondsSinceEpoch}.jpg';
          return _PickedImage(
            name: file.name.isNotEmpty ? file.name : fallback,
            bytes: bytes,
          );
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'File picker no respondio, intentando selector alternativo...',
                ),
                duration: Duration(seconds: 2),
              ),
            );
          }
          final image = await picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 80,
          );
          if (image == null) return null;
          final bytes = await image.readAsBytes();
          return _PickedImage(name: image.name, bytes: bytes);
        }
      }
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Cámara'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galería'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return null;
    final image = await picker.pickImage(source: source, imageQuality: 80);
    if (image == null) return null;
    final bytes = await image.readAsBytes();
    return _PickedImage(name: image.name, bytes: bytes);
  }

  void _showPhotoPreview(AgentOrderPhoto photo) {
    // Construct full URL. Assumes filePath is something like 'uploads/orders/xxx.jpg'
    final imageUrl = '$kBackendBaseUrl/uploads/${photo.filePath}';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            Flexible(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrl,
                    headers: {
                      if (ApiService.instance?.client.accessToken != null)
                        'Authorization':
                            'Bearer ${ApiService.instance!.client.accessToken}',
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      padding: const EdgeInsets.all(24),
                      color: Colors.black54,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.broken_image,
                            color: Colors.redAccent,
                            size: 48,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'No se pudo cargar la imagen',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              photo.fileName,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  String _qualityActionLabel(AgentOrderQualityLog ql) {
    final msg = (ql.message).toLowerCase();
    if (msg.contains('archivo agregado manualmente') ||
        msg.contains('archivo agregado')) {
      return 'ARCHIVO +';
    }
    if (msg.contains('archivo eliminado')) {
      return 'ARCHIVO -';
    }
    return ql.level.toUpperCase();
  }

  Color _qualityActionColor(AgentOrderQualityLog ql) {
    final msg = (ql.message).toLowerCase();
    if (msg.contains('archivo agregado manualmente') ||
        msg.contains('archivo agregado')) {
      return Colors.greenAccent;
    }
    if (msg.contains('archivo eliminado')) {
      return Colors.redAccent;
    }
    return ql.level.toLowerCase() == 'warning'
        ? Colors.orangeAccent
        : ql.level.toLowerCase() == 'error'
        ? Colors.redAccent
        : Colors.white70;
  }

  Widget _buildLogCard(ThemeData theme) {
    final workItems = _detail?.workItems ?? [];
    final qualityLogs = _detail?.qualityLogs ?? [];
    final observations = _observations;
    final order = _detail?.agentOrder;

    // Combine and sort
    final combined = [
      ...workItems.map(
        (wi) => _LogEntry(
          date: wi.updatedAt ?? wi.createdAt,
          actor: (wi.assignedTo ?? '').trim().isNotEmpty
              ? wi.assignedTo!.trim()
              : 'Sistema',
          action: 'WORK ITEM',
          message: wi.description,
          color: Colors.white70,
        ),
      ),
      ...qualityLogs.map(
        (ql) => _LogEntry(
          date: ql.createdAt,
          actor: (ql.author ?? '').trim().isNotEmpty
              ? ql.author!.trim()
              : 'Sistema',
          action: _qualityActionLabel(ql),
          message: ql.message,
          color: _qualityActionColor(ql),
        ),
      ),
      ...observations.map(
        (obs) => _LogEntry(
          date: obs.createdAt,
          actor: (obs.author ?? '').trim().isNotEmpty
              ? obs.author!.trim()
              : 'Sistema',
          action: 'OBSERVACION',
          message: obs.body,
          color: Colors.cyanAccent,
        ),
      ),
    ];

    if (order?.completedAt != null) {
      combined.add(
        _LogEntry(
          date: order!.completedAt,
          actor: (order.completionAuthor ?? '').trim().isNotEmpty
              ? order.completionAuthor!.trim()
              : 'Sistema',
          action: 'FINALIZADA',
          message: (order.completionSummary ?? '').trim().isNotEmpty
              ? order.completionSummary!.trim()
              : 'Orden finalizada',
          color: Colors.green,
        ),
      );
    }

    combined.sort(
      (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
    );

    return _buildCard(
      theme: theme,
      title: 'LOG de Sistema',
      actions: [
        TextButton.icon(
          onPressed: () => setState(() => _showLogs = !_showLogs),
          icon: Icon(_showLogs ? Icons.expand_less : Icons.expand_more),
          label: Text(_showLogs ? 'Ocultar' : 'Ver Logs'),
        ),
      ],
      child: !_showLogs 
          ? const SizedBox.shrink()
          : combined.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: Text('Sin registros de LOG.')),
                )
          : LayoutBuilder(
              builder: (context, constraints) {
                final viewportWidth = constraints.maxWidth;
                final contentWidth = viewportWidth > _tableOuterWidth
                    ? viewportWidth
                    : _tableOuterWidth;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentWidth,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: _tableOuterWidth,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: const BoxDecoration(
                                color: Colors.black38,
                                border: Border(
                                  left: BorderSide(
                                    color: Colors.transparent,
                                    width: 4,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _headerCell('Fecha', _logDateColumnWidth),
                                  _headerCell('Usuario', _logActorColumnWidth),
                                  _headerCell('Acción', _logActionColumnWidth),
                                  _headerCell(
                                    'Mensaje',
                                    _logMessageColumnWidth,
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: combined.map((entry) {
                                    final dateStr = entry.date != null
                                        ? DateFormat(
                                            'yyyy-MM-dd HH:mm',
                                          ).format(entry.date!)
                                        : '';
                                    return Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: const BorderSide(
                                            color: Colors.white10,
                                          ),
                                          left: BorderSide(
                                            color: Colors.transparent,
                                            width: 4,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          _dataCell(
                                            dateStr,
                                            _logDateColumnWidth,
                                          ),
                                          _dataCell(
                                            entry.actor,
                                            _logActorColumnWidth,
                                          ),
                                          _dataCell(
                                            entry.action,
                                            _logActionColumnWidth,
                                            isBold: true,
                                            color: entry.color,
                                          ),
                                          _dataCell(
                                            entry.message,
                                            _logMessageColumnWidth,
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _removeManualService(AgentOrderService svc) async {
    if (svc.manualId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Servicio'),
        content: const Text(
          '¿Estás seguro de que quieres eliminar este servicio manual?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _orderOpsService!.removeManualService(svc.manualId!);
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
        }
      }
    }
  }

  void _showAddServiceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => CatalogSearchDialog(
        service: _orderOpsService!,
        orderId: widget.orderId,
        onAdded: () {
          _loadData();
        },
      ),
    );
  }
}

class _LogEntry {
  final DateTime? date;
  final String actor;
  final String action;
  final String message;
  final Color color;

  _LogEntry({
    required this.date,
    required this.actor,
    required this.action,
    required this.message,
    required this.color,
  });
}

class _PickedImage {
  final String name;
  final Uint8List bytes;

  _PickedImage({required this.name, required this.bytes});
}

class _PickedBinaryFile {
  final String name;
  final Uint8List bytes;

  _PickedBinaryFile({required this.name, required this.bytes});
}

enum _ArchivoSource { gallery, files }

class _ManualOrderPromptResult {
  const _ManualOrderPromptResult({
    required this.unitsText,
    required this.doubleEntry,
  });

  final String unitsText;
  final bool doubleEntry;
}

class _ManualUnitsDialog extends StatefulWidget {
  const _ManualUnitsDialog({required this.numOrden});

  final String numOrden;

  @override
  State<_ManualUnitsDialog> createState() => _ManualUnitsDialogState();
}

class _ManualUnitsDialogState extends State<_ManualUnitsDialog> {
  late final TextEditingController _ctrl;
  bool _doubleEntry = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      _ManualOrderPromptResult(
        unitsText: _ctrl.text.trim(),
        doubleEntry: _doubleEntry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Orden no encontrada'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Introduce el número de unidades para la orden ${widget.numOrden}.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Número de unidades'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          const Text('Tipo de registro'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Unitario'),
                selected: !_doubleEntry,
                onSelected: (_) => setState(() => _doubleEntry = false),
              ),
              ChoiceChip(
                label: const Text('Doble'),
                selected: _doubleEntry,
                onSelected: (_) => setState(() => _doubleEntry = true),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _doubleEntry
                ? 'Captura Serial y Inventario/IMEI'
                : 'Solo Serial (S/N)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Confirmar')),
      ],
    );
  }
}

class CatalogSearchDialog extends StatefulWidget {
  final OrderOpsService service;
  final int orderId;
  final VoidCallback onAdded;

  const CatalogSearchDialog({
    super.key,
    required this.service,
    required this.orderId,
    required this.onAdded,
  });

  @override
  State<CatalogSearchDialog> createState() => _CatalogSearchDialogState();
}

class _CatalogSearchDialogState extends State<CatalogSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;

  Future<void> _performSearch(String q) async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.service.searchCotizaciones(q);
      setState(() => _results = res);
    } catch (e) {
      debugPrint('Search error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addService(Map<String, dynamic> item) async {
    try {
      final ok = await widget.service.addManualService(widget.orderId, {
        'sku': item['sku_config'] ?? item['sku_hp'] ?? item['sku_lenovo'],
        'description': item['description'],
        'coste': item['coste'],
        'pvd': item['pvd'],
        'margen': item['margen'],
        'qty': 1,
      });
      if (ok) {
        widget.onAdded();
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catálogo de Servicios'),
      content: SizedBox(
        width: 500,
        height: 600,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por SKU o descripción...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  focusNode: FocusNode(canRequestFocus: false),
                  onPressed: () => _performSearch(_searchController.text),
                ),
              ),
              onSubmitted: _performSearch,
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (ctx, i) {
                    final item = _results[i];
                    return ListTile(
                      title: Text(item['description'] ?? ''),
                      subtitle: Text(
                        'SKU: ${item['sku_config'] ?? '-'} | HP: ${item['sku_hp'] ?? '-'} | LV: ${item['sku_lenovo'] ?? '-'} \nCoste: ${item['coste'] ?? 0} €',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.add, color: Colors.tealAccent),
                        focusNode: FocusNode(canRequestFocus: false),
                        onPressed: () => _addService(item),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CERRAR'),
        ),
      ],
    );
  }
}
