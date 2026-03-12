import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../services/orderops_service.dart';
import '../../models/agent_models.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';
import '../../config.dart';

class OrderDetailScreen extends StatefulWidget {
  final int orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  OrderOpsService? _orderOpsService;
  OrderOpsDetail? _detail;
  List<AgentOrderObservation> _observations = [];
  List<AgentOrderPhoto> _photos = [];
  List<AgentOrderService> _services = [];

  bool _loading = true;
  String? _error;
  OverlayEntry? _edgeOverlay;

  final TextEditingController _obsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      _orderOpsService = OrderOpsService(apiService.client);
      _loadData();

      // Sidebar
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
                    user: Provider.of<ApiService>(
                      ctx,
                      listen: false,
                    ).currentUser,
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
      }
    });
  }

  @override
  void dispose() {
    _obsController.dispose();
    _edgeOverlay?.remove();
    _edgeOverlay = null;
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
        setState(() {
          _detail = futures[0] as OrderOpsDetail;
          _observations = futures[1] as List<AgentOrderObservation>;
          _photos = futures[2] as List<AgentOrderPhoto>;
          _services = futures[3] as List<AgentOrderService>;
          _loading = false;
          _error = null;
        });
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

  // Legacy photo pick method replaced by _takePhoto

  Future<void> _markRecepcionado() async {
    setState(() => _loading = true);
    try {
      // Mocking setting department or status for now
      await _orderOpsService!.updateAgentOrder(
        widget.orderId,
        department: 'Recepcionado',
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido marcado como Recepcionado')),
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
    final theme = ThemeData.dark().copyWith(
      cardColor: const Color(0xFF1E1E1E),
      scaffoldBackgroundColor: const Color(0xFF121212),
      colorScheme: ColorScheme.dark(
        primary: Colors.blueAccent,
        secondary: Colors.tealAccent,
        surface: const Color(0xFF1E1E1E),
      ),
    );
    final title = _detail?.agentOrder.orderNbr ?? 'Pedido #${widget.orderId}';

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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
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
              _buildLogCard(theme),
              const SizedBox(height: 80), // bottom padding
            ],
          ),
        ),
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
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
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

    return _buildCard(
      theme: theme,
      title: 'Información del Pedido',
      actions: [
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
            onTap: () => _showStatusPicker(order.estado),
          ),
          _buildBadgeItem('Prioridad', prioText, prioColor),
        ],
      ),
    );
  }

  void _showStatusPicker(String currentEstado) {
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

  Future<void> _updateStatus(String code) async {
    debugPrint(
      'Updating status to: $code for order: ${_detail?.agentOrder.idnbr}',
    );
    if (_orderOpsService == null) {
      debugPrint('Error: _orderOpsService is null');
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
      final success = await _orderOpsService!.updateAgentOrder(
        _detail!.agentOrder.idnbr,
        estado: code,
      );
      debugPrint('Update status success: $success');
      if (success) {
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
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: El servidor no pudo guardar el estado'),
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

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
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

    return _buildCard(
      theme: theme,
      title: 'Líneas de la orden (${lines.length})',
      height: 400,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 934, // 930 (cells) + 4 (left border)
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _headerCell('SKU', 100),
                    _headerCell('Descripción', 250),
                    _headerCell('Cant.', 60, alignment: TextAlign.center),
                    _headerCell('Coste', 100, alignment: TextAlign.right),
                    _headerCell('Precio', 100, alignment: TextAlign.right),
                    _headerCell('Beneficio', 110, alignment: TextAlign.right),
                    _headerCell('Margen %', 90, alignment: TextAlign.right),
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
                            bottom: const BorderSide(color: Colors.white10),
                            left: statusColor != null
                                ? BorderSide(color: statusColor, width: 4)
                                : BorderSide.none,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
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
                            _dataCell(
                              '€${effectiveCost.toStringAsFixed(2)}',
                              100,
                              alignment: TextAlign.right,
                              color: (unitCost == 0 && mappedCost > 0)
                                  ? Colors.blueGrey
                                  : null,
                            ),
                            _dataCell(
                              '€${price.toStringAsFixed(2)}',
                              100,
                              alignment: TextAlign.right,
                              isBold: statusColor != null,
                            ),
                            _dataCell(
                              '€${(price - effectiveCost).toStringAsFixed(2)}',
                              110,
                              alignment: TextAlign.right,
                              color: (price - effectiveCost) < 0
                                  ? Colors.redAccent
                                  : Colors.tealAccent,
                            ),
                            _dataCell(
                              '${(((price - effectiveCost) / (price != 0 ? price : 1)) * 100).toStringAsFixed(1)}%',
                              90,
                              alignment: TextAlign.right,
                              color:
                                  price != 0 &&
                                      ((price - effectiveCost) / price) < 0.05
                                  ? Colors.orangeAccent
                                  : Colors.grey,
                            ),
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
    );
  }

  Widget _headerCell(
    String label,
    double width, {
    TextAlign alignment = TextAlign.left,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        label,
        textAlign: alignment,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: Colors.grey,
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
          final statusColor = _getPriceColor(
            actual: svc.orderUnitPrice ?? 0,
            theoretical: svc.theoreticalPvd,
            cost: svc.coste ?? 0,
          );

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
          tooltip: 'Tomar Foto',
          onPressed: _takePhoto,
        ),
      ],
      height: 300,
      child: _photos.isEmpty
          ? const Center(
              child: Text(
                'No hay fotos registradas.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 500,
                child: Column(
                  children: [
                    Container(
                      color: Colors.black38,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          _headerCell('Fecha', 120),
                          _headerCell('Usuario', 120),
                          _headerCell(
                            'Imagen',
                            60,
                            alignment: TextAlign.center,
                          ),
                          _headerCell('Archivo', 150),
                          _headerCell('Ver', 50, alignment: TextAlign.center),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: _photos.map((p) {
                            final dateStr = p.uploadedAt != null
                                ? DateFormat(
                                    'yyyy-MM-dd HH:mm',
                                  ).format(p.uploadedAt!)
                                : '';
                            return Container(
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.white10),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _dataCell(dateStr, 120),
                                  _dataCell(p.author ?? 'Usuario', 120),
                                  SizedBox(
                                    width: 60,
                                    height: 40,
                                    child: Center(child: _buildThumbnail(p)),
                                  ),
                                  _dataCell(p.fileName, 150),
                                  SizedBox(
                                    width: 50,
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.visibility,
                                        size: 18,
                                        color: Colors.tealAccent,
                                      ),
                                      padding: EdgeInsets.zero,
                                      onPressed: () => _showPhotoPreview(p),
                                    ),
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
    );
  }

  Widget _buildThumbnail(AgentOrderPhoto photo) {
    final imageUrl = '$kBackendBaseUrl/media/${photo.filePath}';
    return GestureDetector(
      onTap: () => _showPhotoPreview(photo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          imageUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          headers: {
            if (ApiService.instance?.client.accessToken != null)
              'Authorization':
                  'Bearer ${ApiService.instance!.client.accessToken}',
          },
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.broken_image, size: 20, color: Colors.white24),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          },
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );

    if (image != null) {
      setState(() => _loading = true);
      try {
        final bytes = await image.readAsBytes();
        final success = await _orderOpsService?.uploadPhoto(
          widget.orderId,
          image.name,
          bytes,
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
    }
  }

  void _showPhotoPreview(AgentOrderPhoto photo) {
    // Construct full URL. Assumes filePath is something like 'uploads/orders/xxx.jpg'
    final imageUrl = '$kBackendBaseUrl/media/${photo.filePath}';

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

  Widget _buildLogCard(ThemeData theme) {
    final workItems = _detail?.workItems ?? [];
    final qualityLogs = _detail?.qualityLogs ?? [];

    // Combine and sort
    final combined = [
      ...workItems.map(
        (wi) => _LogEntry(
          date: wi.createdAt,
          level: wi.type.toUpperCase(),
          message: wi.description,
          color: Colors.white70,
        ),
      ),
      ...qualityLogs.map(
        (ql) => _LogEntry(
          date: ql.createdAt,
          level: ql.level.toUpperCase(),
          message: ql.message,
          color: ql.level.toLowerCase() == 'warning'
              ? Colors.orangeAccent
              : ql.level.toLowerCase() == 'error'
              ? Colors.redAccent
              : Colors.white70,
        ),
      ),
    ];

    combined.sort(
      (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
    );

    return _buildCard(
      theme: theme,
      title: 'LOG de Sistema',
      height: 300,
      child: combined.isEmpty
          ? const Center(child: Text('Sin registros de LOG.'))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 650,
                child: Column(
                  children: [
                    Container(
                      color: Colors.black38,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          _headerCell('Fecha', 150),
                          _headerCell('Nivel', 100),
                          _headerCell('Mensaje', 400),
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
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.white10),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _dataCell(dateStr, 150),
                                  _dataCell(
                                    entry.level,
                                    100,
                                    isBold: true,
                                    color: entry.color,
                                  ),
                                  _dataCell(entry.message, 400),
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
  final String level;
  final String message;
  final Color color;

  _LogEntry({
    required this.date,
    required this.level,
    required this.message,
    required this.color,
  });
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
