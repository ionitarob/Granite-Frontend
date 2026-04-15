import 'package:flutter/material.dart';
import '../../widgets/main_sidebar.dart';
import '../../services/api_service.dart';
import 'dart:ui'; // For ImageFilter

class XiaomiRegistroOrdenScreen extends StatefulWidget {
  const XiaomiRegistroOrdenScreen({super.key});

  @override
  State<XiaomiRegistroOrdenScreen> createState() =>
      _XiaomiRegistroOrdenScreenState();
}

class _XiaomiRegistroOrdenScreenState extends State<XiaomiRegistroOrdenScreen> {
  OverlayEntry? _edgeOverlay;
  final _formKey = GlobalKey<FormState>();
  final _cesbController = TextEditingController();
  final _skuController = TextEditingController();
  final _partNumberController = TextEditingController();
  final _cantidadController = TextEditingController();
  final _cartonesController = TextEditingController();

  final FocusNode _cesbFocus = FocusNode();
  final FocusNode _skuFocus = FocusNode();
  final FocusNode _partFocus = FocusNode();
  final FocusNode _cantidadFocus = FocusNode();
  final FocusNode _cartonesFocus = FocusNode();

  final List<_XiaomiOrderEntry> _orders = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
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
    _edgeOverlay?.remove();
    _cesbController.dispose();
    _skuController.dispose();
    _partNumberController.dispose();
    _cantidadController.dispose();
    _cartonesController.dispose();
    _cesbFocus.dispose();
    _skuFocus.dispose();
    _partFocus.dispose();
    _cantidadFocus.dispose();
    _cartonesFocus.dispose();
    super.dispose();
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);

    final now = DateTime.now();
    final cesb = _cesbController.text.trim();
    final sku = _skuController.text.trim();
    final part = _partNumberController.text.trim();
    final qty = int.tryParse(_cantidadController.text.trim()) ?? 0;
    final cartons = int.tryParse(_cartonesController.text.trim());

    // Validation warnings
    final warnings = <String>[];
    if (!cesb.toUpperCase().startsWith('CESB')) {
      warnings.add('CESB no comienza con "CESB".');
    }
    if (!RegExp(r'^\d{5}$').hasMatch(sku)) {
      warnings.add('SKU no parece ser de 5 dígitos.');
    }

    if (warnings.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Advertencia de Formato'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Se detectaron inconsistencias:'),
                const SizedBox(height: 8),
                ...warnings.map(
                  (w) =>
                      Text('• $w', style: const TextStyle(color: Colors.orange)),
                ),
                const SizedBox(height: 16),
                const Text('¿Continuar de todos modos?'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Corregir'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Registrar'),
            ),
          ],
        ),
      );
      if (proceed != true) {
        setState(() => _submitting = false);
        return;
      }
    }

    final entry = _XiaomiOrderEntry(
      cesb: cesb,
      sku: sku,
      partNumber: part,
      quantity: qty,
      cartons: cartons,
      createdAt: now,
    );

    final username = ApiService.instance?.currentUser?.username;
    final payload = {
      'cesb': entry.cesb,
      'sku': entry.sku,
      'partn': entry.partNumber,
      'qty': entry.quantity,
      'cartons': entry.cartons,
      'operario': username,
      'etiquetado': null,
      'fecha_hora_registro': now.toIso8601String(),
      'fecha_hora_fin': null,
    };

    try {
      final api = ApiService.instance?.client;
      if (api == null) throw Exception('API client init fail');

      final resp = await api.post(
        '/xiaomieco/add_xiaomieco',
        jsonBody: payload,
      );

      if (!mounted) return;

      if (resp.ok) {
        dynamic body = resp.body;
        if (body is Map &&
            body['inserted'] is List &&
            body['inserted'].isNotEmpty) {
          final inserted = body['inserted'][0];
          final newEntry = _XiaomiOrderEntry(
            cesb: inserted['cesb']?.toString() ?? entry.cesb,
            sku: inserted['sku']?.toString() ?? entry.sku,
            partNumber: inserted['partn']?.toString() ?? entry.partNumber,
            quantity:
                int.tryParse(inserted['qty']?.toString() ?? '') ??
                entry.quantity,
            cartons: int.tryParse(inserted['cartons']?.toString() ?? ''),
            createdAt: entry.createdAt,
          );
          _addOrderToLocal(newEntry);
        } else {
          _addOrderToLocal(entry);
        }
      } else {
        _showError(resp.body ?? resp.error ?? 'Error ${resp.statusCode}');
      }
    } catch (e) {
      _showError('Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _addOrderToLocal(_XiaomiOrderEntry entry) {
    setState(() {
      _orders.insert(0, entry);
      _cesbController.clear();
      _skuController.clear();
      _partNumberController.clear();
      _cantidadController.clear();
      _cartonesController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            const Text('Orden registrada correctamente'),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
    _cesbFocus.requestFocus();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _removeOrder(_XiaomiOrderEntry entry) {
    setState(() => _orders.remove(entry));
  }

  String _formatTimestamp(DateTime value) {
    final t = value.toLocal();
    String two(int i) => i.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text('Registro de Material'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primaryContainer.withOpacity(0.9),
                theme.colorScheme.surface,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        actions: [
          if (_orders.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.cleaning_services_rounded),
              tooltip: 'Limpiar lista',
              onPressed: () => setState(() => _orders.clear()),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // BACKGROUND
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.tertiary.withOpacity(0.05),
                  theme.colorScheme.primary.withOpacity(0.05),
                  theme.scaffoldBackgroundColor,
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    children: [
                      // GLASSMORPHIC FORM
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: EdgeInsets.all(isMobile ? 16 : 32),
                            decoration: BoxDecoration(
                              color: theme.cardColor.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.1),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: theme
                                              .colorScheme
                                              .primaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.qr_code_scanner_rounded,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Nueva Entrada',
                                              style: theme
                                                  .textTheme
                                                  .headlineSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            Text(
                                              'Escanea o introduce los datos',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme.hintColor,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 32),
                                  _buildTextField(
                                    controller: _cesbController,
                                    label: 'CESB',
                                    icon: Icons.qr_code,
                                    focus: _cesbFocus,
                                    nextFocus: _skuFocus,
                                    validator: (v) => (v?.isEmpty ?? true)
                                        ? 'Requerido'
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
                                  if (isMobile) ...[
                                    _buildTextField(
                                      controller: _skuController,
                                      label: 'SKU',
                                      icon: Icons.tag,
                                      focus: _skuFocus,
                                      nextFocus: _partFocus,
                                      keyboardType: TextInputType.number,
                                      validator: (v) => (v?.isEmpty ?? true)
                                          ? 'Requerido'
                                          : null,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildTextField(
                                      controller: _partNumberController,
                                      label: 'Part Number',
                                      icon: Icons.memory,
                                      focus: _partFocus,
                                      nextFocus: _cantidadFocus,
                                      validator: (v) => (v?.isEmpty ?? true)
                                          ? 'Requerido'
                                          : null,
                                    ),
                                  ] else
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: _buildTextField(
                                            controller: _skuController,
                                            label: 'SKU',
                                            icon: Icons.tag,
                                            focus: _skuFocus,
                                            nextFocus: _partFocus,
                                            keyboardType: TextInputType.number,
                                            validator: (v) =>
                                                (v?.isEmpty ?? true)
                                                ? 'Requerido'
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          flex: 3,
                                          child: _buildTextField(
                                            controller: _partNumberController,
                                            label: 'Part Number',
                                            icon: Icons.memory,
                                            focus: _partFocus,
                                            nextFocus: _cantidadFocus,
                                            validator: (v) =>
                                                (v?.isEmpty ?? true)
                                                ? 'Requerido'
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 16),
                                  if (isMobile) ...[
                                    _buildTextField(
                                      controller: _cantidadController,
                                      label: 'Cantidad',
                                      icon: Icons.exposure_plus_1,
                                      focus: _cantidadFocus,
                                      nextFocus: _cartonesFocus,
                                      keyboardType: TextInputType.number,
                                      validator: (v) =>
                                          (v?.isEmpty ?? true) ? 'Req.' : null,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildTextField(
                                      controller: _cartonesController,
                                      label: 'Cartones',
                                      icon: Icons.inbox,
                                      focus: _cartonesFocus,
                                      keyboardType: TextInputType.number,
                                      isLast: true,
                                      onSubmit: _submitOrder,
                                      validator: (v) =>
                                          (v?.isEmpty ?? true) ? 'Req.' : null,
                                    ),
                                  ] else
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildTextField(
                                            controller: _cantidadController,
                                            label: 'Cantidad',
                                            icon: Icons.exposure_plus_1,
                                            focus: _cantidadFocus,
                                            nextFocus: _cartonesFocus,
                                            keyboardType: TextInputType.number,
                                            validator: (v) =>
                                                (v?.isEmpty ?? true)
                                                ? 'Req.'
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: _buildTextField(
                                            controller: _cartonesController,
                                            label: 'Cartones',
                                            icon: Icons.inbox,
                                            focus: _cartonesFocus,
                                            keyboardType: TextInputType.number,
                                            isLast: true,
                                            onSubmit: _submitOrder,
                                            validator: (v) =>
                                                (v?.isEmpty ?? true)
                                                ? 'Req.'
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 32),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 54,
                                    child: FilledButton.icon(
                                      onPressed: _submitting
                                          ? null
                                          : _submitOrder,
                                      style: FilledButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        // Removed elevation here to fix lint error
                                      ),
                                      icon: _submitting
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.check_rounded),
                                      label: Text(
                                        _submitting
                                            ? 'Guardando...'
                                            : 'Registrar Orden',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
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

                      const SizedBox(height: 40),

                      // RECENT ORDERS LIST
                      if (_orders.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.history_rounded,
                              color: theme.hintColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Registros Recientes',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.hintColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _orders.length,
                          itemBuilder: (ctx, i) {
                            final item = _orders[i];
                            return Dismissible(
                              key: ValueKey(item),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) => _removeOrder(item),
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                color: Colors.redAccent.withOpacity(0.2),
                                child: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: theme.cardColor,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.03),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 8,
                                  ),
                                  leading: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color:
                                          theme.colorScheme.secondaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '${item.quantity}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: theme
                                            .colorScheme
                                            .onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    item.sku,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${item.cesb} • ${item.partNumber}',
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _formatTimestamp(item.createdAt),
                                        style: TextStyle(
                                          color: theme.hintColor,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        '${item.cartons} box',
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required FocusNode focus,
    FocusNode? nextFocus,
    TextInputType keyboardType = TextInputType.text,
    bool isLast = false,
    VoidCallback? onSubmit,
    String? Function(String?)? validator,
  }) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      focusNode: focus,
      textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
      keyboardType: keyboardType,
      onFieldSubmitted: (_) {
        if (nextFocus != null) {
          nextFocus.requestFocus();
        } else if (isLast && onSubmit != null) {
          onSubmit();
        }
      },
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: theme.hintColor),
        filled: true,
        fillColor: theme.colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
    );
  }
}

class _XiaomiOrderEntry {
  const _XiaomiOrderEntry({
    this.cesb,
    required this.sku,
    this.partNumber,
    required this.quantity,
    this.cartons,
    required this.createdAt,
  });

  final String? cesb;
  final String sku;
  final String? partNumber;
  final int quantity;
  final int? cartons;
  final DateTime createdAt;
}
