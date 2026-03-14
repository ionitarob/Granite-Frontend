import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../services/api_service.dart';
import '../../services/orderops_service.dart';
import '../../models/agent_models.dart';
import '../../widgets/animated_background.dart';
import '../../config.dart';
import '../servers/registro_servidor_screen.dart';
import '../serials/serial_link.dart';
import '../serials/serial_change.dart';
import '../xiaomi/xiaomi_registro_orden.dart';
import '../sentinel_for_imaging/physical_tables_screen.dart';

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
  List<AgentOrderObservation> _observations = [];
  List<AgentOrderPhoto> _photos = [];
  List<AgentOrderService> _services = [];
  final Map<int, Uint8List> _pdfPreviewCache = {};

  bool _loading = true;
  String? _error;
  bool _autoAssigningMasterFamily = false;

  final TextEditingController _obsController = TextEditingController();

  String _normalizedRole() {
    final raw = (ApiService.instance?.currentUser?.role ?? '').trim().toLowerCase();
    if (raw.startsWith('role_')) return raw.substring(5);
    return raw;
  }

  bool get _isPrivilegedRole {
    final role = _normalizedRole();
    return role == 'admin' || role == 'chief';
  }

  bool get _canViewFinancialData => _isPrivilegedRole;

  bool get _canEditOrderMeta => _isPrivilegedRole;

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
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final futures = await Future.wait([
        _orderOpsService!.getAgentOrder(widget.orderId),
        _orderOpsService!.getObservations(widget.orderId),
        _orderOpsService!.getPhotos(widget.orderId),
        _orderOpsService!.getServices(widget.orderId),
      ]);

      if (mounted) {
        final loadedDetail = futures[0] as OrderOpsDetail;
        setState(() {
          _detail = loadedDetail;
          _observations = futures[1] as List<AgentOrderObservation>;
          _photos = futures[2] as List<AgentOrderPhoto>;
          _services = futures[3] as List<AgentOrderService>;
          _loading = false;
          _error = null;
        });

        await _autoAssignMasterFamilyFromLinesIfNeeded(loadedDetail);
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

  bool _linesContainMasterKeyword(OrderOpsDetail detail) {
    final source = detail.sourceOrder;
    if (source == null) return false;
    final lines = source['lines'];
    if (lines is! List) return false;

    for (final raw in lines) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final description =
          (row['DESCRIP1'] ?? row['description'] ?? '').toString().toUpperCase();
      if (description.contains('MASTER')) {
        return true;
      }
    }
    return false;
  }

  Future<void> _autoAssignMasterFamilyFromLinesIfNeeded(
    OrderOpsDetail detail,
  ) async {
    if (_autoAssigningMasterFamily || _orderOpsService == null) return;

    final currentFamily = (detail.agentOrder.family ?? '').trim().toUpperCase();
    if (currentFamily.contains('MASTERIZ')) return;
    if (!_linesContainMasterKeyword(detail)) return;

    _autoAssigningMasterFamily = true;
    try {
      final ok = await _orderOpsService!.updateAgentOrder(
        detail.agentOrder.idnbr,
        family: 'MASTERIZACIÓN',
        reason: 'Autoasignación por línea de pedido con palabra MASTER',
      );
      if (ok && mounted) {
        await _loadData();
      }
    } catch (e) {
      debugPrint('Auto-assign MASTERIZACIÓN failed: $e');
    } finally {
      _autoAssigningMasterFamily = false;
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
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
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
        estado: '2', // Code for "Pendiente" according to order_queue_screen.dart
        department: 'Recepcionado',
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido marcado como Pendiente (Recepcionado)')),
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
      cardColor: isDark ? const Color(0xFF1E1E1E) : baseTheme.colorScheme.surface,
    );
    final title = _detail != null
      ? _formatOrderNbr(_detail!.agentOrder.orderNbr)
      : 'Pedido #${widget.orderId}';

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
          ),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          ],
        ),
        body: Stack(
          children: [
            const AnimatedBackgroundWidget(intensity: 0.3),
            SafeArea(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        'Error: $_error',
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : _buildDashboard(theme),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isEnEjecucion) ...[
                _buildTopExecutionStrip(theme),
                const SizedBox(height: 20),
                _buildEmbeddedServicePanel(theme),
                const SizedBox(height: 24),
              ] else ...[
                _buildHeaderCard(theme),
                const SizedBox(height: 24),
                _buildLinesCard(theme),
                const SizedBox(height: 24),
                _buildServicesCard(theme),
                const SizedBox(height: 24),
                _buildObservationsCard(theme),
                const SizedBox(height: 24),
              ],
              _buildQualityQualityCard(theme),
              const SizedBox(height: 24),
              _buildArchivosCard(theme),
              const SizedBox(height: 24),
              _buildLogCard(theme),
              const SizedBox(height: 80), // bottom padding
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopExecutionStrip(ThemeData theme) {
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
                'Informacion del Pedido',
                Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildInfoItem('Pedido', order.orderNbr, maxLines: 1),
                            const SizedBox(height: 4),
                            _buildInfoItem('Cliente', order.customer, maxLines: 1),
                            const SizedBox(height: 4),
                            _buildInfoItem(
                              'Fecha',
                              order.orderDate != null
                                  ? DateFormat('yyyy-MM-dd').format(order.orderDate!)
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
                          _buildMiniBadge('Estado: ${estadoMeta.$1}', estadoMeta.$2),
                          const SizedBox(height: 6),
                          _buildMiniBadge('Prioridad: ${prioridadMeta.$1}', prioridadMeta.$2),
                          const SizedBox(height: 6),
                                    _canEditOrderMeta
                                        ? GestureDetector(
                                            onTap: () => _showFamilyPicker(order.family ?? ''),
                                            child: _buildMiniBadge(
                                              'Familia: ${order.family?.trim().isEmpty ?? true ? 'SIN ASIGNAR' : order.family!.toUpperCase()}',
                                              order.family?.trim().isEmpty ?? true ? Colors.redAccent : Colors.tealAccent,
                                            ),
                                          )
                                        : _buildMiniBadge(
                                            'Familia: ${order.family?.trim().isEmpty ?? true ? 'SIN ASIGNAR' : order.family!.toUpperCase()}',
                                            order.family?.trim().isEmpty ?? true ? Colors.redAccent : Colors.tealAccent,
                                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                headerTrailing: SizedBox(
                  height: 26,
                  child: ElevatedButton(
                              onPressed: order.estado.contains('5')
                        ? null
                        : () => _updateStatus('5', allowWorkflowAction: true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 26),
                    ),
                    child: const Text(
                      'Finalizar',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
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
                onTap: _showAddObservationDialog,
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
        child: content,
      ),
    );
  }

  (String, Color) _mapEstado(String rawEstado) {
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

  (String, Color) _mapPrioridad(String rawPrioridad) {
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

  bool _hasQualityEvidence() => _photos.any(_isImageFile);

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
        SelectableText(
          'Familia: ${family ?? 'No asignada'}',
          maxLines: 2,
          style: TextStyle(color: theme.hintColor),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Scrollbar(
            thumbVisibility: _showPersistentScrollbar(context),
            child: ListView.builder(
              padding: const EdgeInsets.only(right: 12),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[index];
                final sku = line['SKU']?.toString() ?? '-';
                final desc =
                    (line['DESCRIP1'] ?? line['description'])?.toString() ?? '';
                final qty = line['QTY_ORD']?.toString() ?? '0';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _panelItemFill(theme),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _panelItemBorder(theme)),
                    ),
                    child: SelectableText(
                      '$sku | Qty: $qty | $desc',
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
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
            child: ListView.builder(
              itemCount: _services.length,
              itemBuilder: (context, index) {
                final svc = _services[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _panelItemFill(theme),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _panelItemBorder(theme)),
                    ),
                    child: SelectableText(
                      '${svc.skuConfig ?? '-'} | ${svc.description ?? 'Sin descripcion'}',
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildObservacionesPreview(ThemeData theme) {
    if (_observations.isEmpty) {
      return SelectableText(
        'Sin observaciones',
        style: TextStyle(color: theme.hintColor),
      );
    }

    return Scrollbar(
      thumbVisibility: _showPersistentScrollbar(context),
      child: ListView.builder(
        itemCount: _observations.length,
        itemBuilder: (context, index) {
          final obs = _observations[index];
          final author = (obs.author ?? 'Sin autor').trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _panelItemFill(theme),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _panelItemBorder(theme)),
              ),
              child: SelectableText(
                '$author: ${obs.body}',
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
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

    return _buildCard(
      theme: theme,
      title: 'Información del Pedido',
      actions: [
        if (isPendiente)
          ElevatedButton.icon(
            onPressed: () => _updateStatus('3', allowWorkflowAction: true),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Comenzar orden'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan,
              foregroundColor: Colors.white,
            ),
          )
        else if (isValidada)
          ElevatedButton.icon(
            onPressed: _markRecepcionado,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Recepcionado'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
      ],
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 32,
        runSpacing: 16,
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
            onTap: _canEditOrderMeta ? () => _showStatusPicker(order.estado) : null,
          ),
          _buildBadgeItem(
            'Prioridad',
            prioText,
            prioColor,
          ),
          _buildBadgeItem(
            'Familia',
            order.family?.trim().isEmpty ?? true ? 'SIN ASIGNAR' : order.family!,
            order.family?.trim().isEmpty ?? true ? Colors.redAccent : Colors.tealAccent,
            onTap: _canEditOrderMeta ? () => _showFamilyPicker(order.family ?? '') : null,
          ),
        ],
      ),
    );
  }

  Future<void> _showFamilyPicker(String currentFamily) async {
    if (!_canEditOrderMeta) return;
    if (_orderOpsService == null) return;
    const extraFamilies = <String>[
      'SERIGRAFIADO',
      'MANIPULACIÓN Y ETIQUETADO',
    ];

    // Show loading state or fetch before showing sheet
    List<String> families = [];
    try {
      families = await _orderOpsService!.getCatalogFamilies();
    } catch (e) {
      debugPrint('Error fetching families: $e');
    }

    // Ensure a baseline list and always include extra families not present in DB.
    if (families.isEmpty) {
      families = [
        'ORDENADORES SERVIDOR',
        'CAMBIO DE SERIAL',
        'XIAOMI ETIQUETADO',
      ];
    }
    families = {...families, ...extraFamilies}.toList();
    
    // Sort families
    families.sort();

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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                      'Seleccionar Familia de Pedido',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: families.length,
                      itemBuilder: (context, index) {
                        final f = families[index];
                        return ListTile(
                          leading: Icon(
                            Icons.category_outlined,
                            color: f == currentFamily ? Colors.tealAccent : Colors.white70,
                          ),
                          title: Text(
                            f,
                            style: TextStyle(
                              color: f == currentFamily ? Colors.tealAccent : Colors.white,
                              fontWeight: f == currentFamily ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          trailing: f == currentFamily
                              ? const Icon(Icons.check, color: Colors.tealAccent)
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            if (f != currentFamily) {
                              _updateFamily(f);
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

  Future<void> _updateFamily(String family) async {
    if (!_canEditOrderMeta) return;
    if (_orderOpsService == null || _detail == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Actualizando familia...')),
    );

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
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
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
                'Cambiar Estado del Pedido',
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
    if (_orderOpsService == null) {
      debugPrint('Error: _orderOpsService is null');
      return;
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

    if (_isSerigrafiadoFamily() && code == '3' && !_hasArchivosAttached()) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Necesitas adjuntar los archivos de la serigrafia para poder comenzar con la orden',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (_isSerigrafiadoFamily() && code == '5' && !_hasQualityEvidence()) {
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
        String backendMessage = result.error ?? 'El servidor no pudo guardar el estado';
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
            backendMessage = (body['non_field_errors'] as List).first.toString();
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
    if (!mounted) return;
    final currentDetail = _detail;
    if (currentDetail == null || _orderOpsService == null) return;

    final order = currentDetail.agentOrder;
    final family = (order.family ?? '').trim().toUpperCase();
    if (family != 'CAMBIO DE SERIAL') return;

    final client = ApiService.instance?.client;
    if (client == null) return;

    final normalizedOrder = _formatOrderNbr(order.orderNbr).trim();
    if (normalizedOrder.isEmpty) return;

    try {
      final exportRes = await client.post(
        '/serials/finish-order-upload',
        jsonBody: {'nr_orden': normalizedOrder},
      );
      if (!exportRes.ok) {
        debugPrint(
          'OrderDetail: finish-order-upload failed (${exportRes.statusCode})',
        );
        return;
      }

      String fileName = '$normalizedOrder.xlsx';
      String? filePath;

      if (exportRes.body is Map) {
        final body = Map<String, dynamic>.from(exportRes.body as Map);
        fileName =
            _firstNonEmptyString(body, const [
              'file_name',
              'filename',
              'name',
              'excel_file',
            ]) ??
            fileName;
        filePath = _firstNonEmptyString(body, const [
          'file_path',
          'path',
          'excel_path',
          'export_path',
          'archivo_path',
          'relative_path',
        ]);
      }

      if (filePath == null || filePath.isEmpty) {
        // If backend doesn't return a path we cannot register an Archivo reliably.
        debugPrint(
          'OrderDetail: export completed but no file_path returned for Archivo registry.',
        );
        return;
      }

      final author = ApiService.instance?.currentUser?.username;
      final attached = await _orderOpsService!.addArchivoManual(
        order.idnbr,
        fileName,
        filePath,
        author: author,
      );
      if (!attached) {
        debugPrint('OrderDetail: addArchivoManual failed for $filePath');
      }
    } catch (e) {
      debugPrint('OrderDetail: export/archive registration error: $e');
    }
  }

  Widget? _resolveEmbeddedServiceWidget() {
    if (_detail == null) return null;

    final order = _detail!.agentOrder;
    final family = (order.family ?? '').trim().toUpperCase();
    if (family == 'ORDENADORES SERVIDOR' || family == 'ORDENADORES SERVIDORES') {
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
    final family = (order.family ?? '').trim().toUpperCase();
    final isEnEjecucion = order.estado.contains('3');
    if (!isEnEjecucion) {
      return const SizedBox.shrink();
    }

    // Serigrafiado works only with Archivos/Calidad gates; no embedded service UI.
    if (family.contains('SERIGRAF')) {
      return const SizedBox.shrink();
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
                    : 'Familia no detectada para este pedido.',
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

    return SizedBox(
      width: double.infinity,
      height: 860,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: serviceWidget,
        ),
      ),
    );
  }

  Widget _buildInfoItem(
    String label,
    String value, {
    int maxLines = 2,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          maxLines: maxLines,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildBadgeItem(
    String label,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              border: Border.all(color: color.withOpacity(0.6)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 12, color: color.withOpacity(0.7)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLinesCard(ThemeData theme) {
    final sourceOrder = _detail!.sourceOrder;
    if (sourceOrder == null || !sourceOrder.containsKey('lines')) {
      return _buildCard(
        theme: theme,
        title: 'Líneas de la orden',
        child: const Text('Sin líneas.'),
      );
    }

    final lines = sourceOrder['lines'] as List<dynamic>;

    const double financialCellsWidth = 100 + 100 + 110 + 90 + 120;
    const double baseCellsWidth = 100 + 250 + 60;
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
    final mappedCostColor = isDark
      ? Colors.blueGrey
      : const Color(0xFF475569);

    return _buildCard(
      theme: theme,
      title: 'Líneas de la orden (${lines.length})',
      height: 400,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth;
          final contentWidth = viewportWidth > lineOuterWidth
              ? viewportWidth
              : lineOuterWidth;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: lineOuterWidth,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: headerBg,
                          border: Border(
                            left: BorderSide(color: Colors.transparent, width: 4),
                          ),
                        ),
                        child: Row(
                          children: [
                            _headerCell('SKU', 100),
                            _headerCell('Descripción', 250),
                            _headerCell('Cant.', 60, alignment: TextAlign.center),
                            if (_canViewFinancialData)
                              _headerCell('Coste', 100, alignment: TextAlign.right),
                            if (_canViewFinancialData)
                              _headerCell('Precio', 100, alignment: TextAlign.right),
                            if (_canViewFinancialData)
                              _headerCell('Beneficio', 110, alignment: TextAlign.right),
                            if (_canViewFinancialData)
                              _headerCell('Margen %', 90, alignment: TextAlign.right),
                            if (_canViewFinancialData)
                              _headerCell('Total', 120, alignment: TextAlign.right),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: Column(
                            children: lines.map<Widget>((line) {
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
                              final effectiveCost = unitCost > 0
                                  ? unitCost
                                  : mappedCost;
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
                                    _dataCell(line['SKU']?.toString() ?? '', 100),
                                    _dataCell(
                                      (line['DESCRIP1'] ?? line['description'])
                                              ?.toString() ??
                                          '',
                                      250,
                                    ),
                                    _dataCell(
                                      line['QTY_ORD']?.toString() ?? '0',
                                      60,
                                      alignment: TextAlign.center,
                                    ),
                                    if (_canViewFinancialData)
                                      _dataCell(
                                        '€${effectiveCost.toStringAsFixed(2)}',
                                        100,
                                        alignment: TextAlign.right,
                                        color: (unitCost == 0 && mappedCost > 0)
                                          ? mappedCostColor
                                            : null,
                                      ),
                                    if (_canViewFinancialData)
                                      _dataCell(
                                        '€${price.toStringAsFixed(2)}',
                                        100,
                                        alignment: TextAlign.right,
                                        isBold: statusColor != null,
                                      ),
                                    if (_canViewFinancialData)
                                      _dataCell(
                                        '€${(price - effectiveCost).toStringAsFixed(2)}',
                                        110,
                                        alignment: TextAlign.right,
                                        color: (price - effectiveCost) < 0
                                          ? profitNegativeColor
                                          : profitPositiveColor,
                                      ),
                                    if (_canViewFinancialData)
                                      _dataCell(
                                        '${(((price - effectiveCost) / (price != 0 ? price : 1)) * 100).toStringAsFixed(1)}%',
                                        90,
                                        alignment: TextAlign.right,
                                        color:
                                            price != 0 &&
                                                ((price - effectiveCost) / price) < 0.05
                                          ? lowMarginColor
                                            : Colors.grey,
                                      ),
                                    if (_canViewFinancialData)
                                      _dataCell(
                                        '€${(double.tryParse(line['TOTAL']?.toString() ?? '0') ?? 0).toStringAsFixed(2)}',
                                        120,
                                        alignment: TextAlign.right,
                                        isBold: true,
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
      return _buildCard(
        theme: theme,
        title: 'Servicios Asignados',
        child: const Center(
          child: Text(
            'No se han encontrado servicios (cotizaciones) para estos SKUs.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return _buildCard(
      theme: theme,
      title: 'Servicios de Montaje / Extras',
      actions: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Colors.tealAccent),
          tooltip: 'Añadir Servicio Manual',
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
                              'Precio Pedido',
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
          Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300, // Reasonable min width for text field
                child: TextField(
                  controller: _obsController,
                  decoration: const InputDecoration(
                    hintText: 'Añadir nueva observación...',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.black26,
                  ),
                  maxLines: 2,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addObservation,
                icon: const Icon(Icons.add),
                label: const Text('Añadir'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                ),
              ),
            ],
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
    final imageFiles = _photos.where(_isImageFile).toList(growable: false);
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
          onPressed: _takePhoto,
        ),
      ],
      height: null,
      child: imageFiles.isEmpty
          ? const Center(
              child: Text(
                'No hay fotos registradas.',
                style: TextStyle(color: Colors.grey),
              ),
            )
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
          onPressed: _uploadArchivo,
        ),
      ],
      height: null,
      child: _photos.isEmpty
          ? const Center(
              child: Text(
                'No hay archivos adjuntos.',
                style: TextStyle(color: Colors.grey),
              ),
            )
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
                  children: _photos
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

  Widget _buildArchivoThumbCard(AgentOrderPhoto file) {
    final isImage = _isImageFile(file);
    final isPdf = _isPdfFile(file);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
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
                          child: Icon(Icons.broken_image, color: Colors.white38),
                        ),
                      )
                    : isPdf
                    ? FutureBuilder<Uint8List?>(
                        future: _getPdfPreviewBytes(file),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
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
                          return IgnorePointer(child: SfPdfViewer.memory(bytes));
                        },
                      )
                    : const Center(
                        child: Icon(Icons.insert_drive_file, color: Colors.white70, size: 40),
                      ),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: InkWell(
                  onTap: () => _openOrderFile(file),
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
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                Expanded(
                  child: SfPdfViewer.memory(bytes),
                ),
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
    final picked = await _pickArchivoFile();
    if (picked == null) return;
    if (picked.bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo leer el archivo seleccionado')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final success = await _orderOpsService?.uploadPhoto(
        widget.orderId,
        picked.name.isNotEmpty
            ? picked.name
            : 'archivo_${DateTime.now().millisecondsSinceEpoch}',
        picked.bytes,
      );
      if (!mounted) return;
      if (success == true) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Archivo subido en Archivos')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo subir el archivo')),
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

  Future<_PickedBinaryFile?> _pickArchivoFile() async {
    final platform = defaultTargetPlatform;
    final isDesktop = !kIsWeb &&
        (platform == TargetPlatform.macOS ||
            platform == TargetPlatform.windows ||
            platform == TargetPlatform.linux);

    if (isDesktop) {
      try {
        final xFile = await fs.openFile();
        if (xFile == null) return null;
        final bytes = await xFile.readAsBytes();
        if (bytes.isEmpty) return null;
        final fallback = 'archivo_${DateTime.now().millisecondsSinceEpoch}';
        final name = xFile.name.isNotEmpty ? xFile.name : fallback;
        return _PickedBinaryFile(name: name, bytes: bytes);
      } catch (_) {
        // Fall through to file_picker fallback.
      }
    }

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.any,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.first;
    final bytes =
        file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null || bytes.isEmpty) return null;
    final fallback = 'archivo_${DateTime.now().millisecondsSinceEpoch}';
    final name = file.name.isNotEmpty ? file.name : fallback;
    return _PickedBinaryFile(name: name, bytes: bytes);
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
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Abriendo selector de imagen...'),
          duration: Duration(milliseconds: 900),
        ),
      );
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
        final success = await _orderOpsService?.uploadPhoto(
          widget.orderId,
          picked.name,
          picked.bytes,
        );
        if (success == true) {
          // Refresh photos
          final newPhotos = await _orderOpsService?.getPhotos(widget.orderId);
          setState(() {
            _photos = newPhotos ?? [];
            _loading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto guardada correctamente')),
          );
        } else {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al subir la foto')),
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
    final isDesktop = !kIsWeb &&
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
        return _PickedImage(name: name.isNotEmpty ? name : fallback, bytes: bytes);
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
          final fallback = 'quality_${DateTime.now().millisecondsSinceEpoch}.jpg';
          return _PickedImage(name: file.name.isNotEmpty ? file.name : fallback, bytes: bytes);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('File picker no respondio, intentando selector alternativo...'),
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
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camara'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeria'),
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
      height: 300,
      child: combined.isEmpty
          ? const Center(child: Text('Sin registros de LOG.'))
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
                                  left: BorderSide(color: Colors.transparent, width: 4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _headerCell('Fecha', _logDateColumnWidth),
                                  _headerCell('Usuario', _logActorColumnWidth),
                                  _headerCell('Acción', _logActionColumnWidth),
                                  _headerCell('Mensaje', _logMessageColumnWidth),
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
                                          bottom: const BorderSide(color: Colors.white10),
                                          left: BorderSide(
                                            color: Colors.transparent,
                                            width: 4,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          _dataCell(dateStr, _logDateColumnWidth),
                                          _dataCell(entry.actor, _logActorColumnWidth),
                                          _dataCell(
                                            entry.action,
                                            _logActionColumnWidth,
                                            isBold: true,
                                            color: entry.color,
                                          ),
                                          _dataCell(entry.message, _logMessageColumnWidth),
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
