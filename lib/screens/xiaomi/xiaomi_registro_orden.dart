import 'package:flutter/material.dart';

import '../../widgets/main_sidebar.dart';
import '../../services/api_service.dart';

class XiaomiRegistroOrdenScreen extends StatefulWidget {
  const XiaomiRegistroOrdenScreen({super.key});

  @override
  State<XiaomiRegistroOrdenScreen> createState() =>
      _XiaomiRegistroOrdenScreenState();
}

class _XiaomiRegistroOrdenScreenState extends State<XiaomiRegistroOrdenScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cesbController = TextEditingController();
  final _skuController = TextEditingController();
  final _partNumberController = TextEditingController();
  final _cantidadController = TextEditingController();
  final _cartonesController = TextEditingController();
  // Focus nodes to allow Enter -> next-field navigation
  final FocusNode _cesbFocus = FocusNode();
  final FocusNode _skuFocus = FocusNode();
  final FocusNode _partFocus = FocusNode();
  final FocusNode _cantidadFocus = FocusNode();
  final FocusNode _cartonesFocus = FocusNode();

  final List<_XiaomiOrderEntry> _orders = [];
  bool _submitting = false;

  @override
  void dispose() {
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
    // Ensure required fields are present via the form validators
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);

    final now = DateTime.now();
    final cesb = _cesbController.text.trim();
    final sku = _skuController.text.trim();
    final part = _partNumberController.text.trim();
    final qty = int.tryParse(_cantidadController.text.trim()) ?? 0;
    final cartons = int.tryParse(_cartonesController.text.trim());

    // Format checks that are "recommended" but can be overridden by user
    final warnings = <String>[];
    if (!cesb.toUpperCase().startsWith('CESB')) {
      warnings.add('CESB no comienza con "CESB" (valor: "$cesb").');
    }
    if (!RegExp(r'^\d{9}$').hasMatch(sku)) {
      warnings.add('SKU no parece ser 9 dígitos (valor: "$sku").');
    }
    if (!RegExp(r'^\d{5}$').hasMatch(part)) {
      warnings.add('Part Number no parece ser 5 dígitos (valor: "$part").');
    }

    if (warnings.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Formato no estándar'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                const Text('Se detectaron las siguientes inconsistencias:'),
                const SizedBox(height: 8),
                ...warnings.map((w) => Text('• $w')),
                const SizedBox(height: 12),
                const Text('¿Deseas continuar de todos modos y registrar la orden?'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Continuar')),
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
      if (api == null) throw Exception('API client not available');

  final resp = await api.post('/xiaomieco/add_xiaomieco', jsonBody: payload);
      debugPrint('xiaomi post -> status: ${resp.statusCode}, ok: ${resp.ok}, body: ${resp.body}');
      if (!mounted) return;

      if (resp.ok) {
        dynamic body = resp.body;
        if (body is Map && body['inserted'] is List && body['inserted'].isNotEmpty) {
          final inserted = body['inserted'][0];
          final newEntry = _XiaomiOrderEntry(
            cesb: inserted['cesb']?.toString() ?? entry.cesb,
            sku: inserted['sku']?.toString() ?? entry.sku,
            partNumber: inserted['partn']?.toString() ?? entry.partNumber,
            quantity: inserted['qty'] is int ? inserted['qty'] as int : int.tryParse(inserted['qty']?.toString() ?? '') ?? entry.quantity,
            cartons: inserted['cartons'] is int ? inserted['cartons'] as int : int.tryParse(inserted['cartons']?.toString() ?? ''),
            createdAt: entry.createdAt,
          );
          setState(() {
            _orders.insert(0, newEntry);
            _submitting = false;
            _cesbController.clear();
            _skuController.clear();
            _partNumberController.clear();
            _cantidadController.clear();
            _cartonesController.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Orden registrada en el servidor')));
        } else {
          // Server responded OK but did not return inserted details. Treat as error and do NOT save locally.
          setState(() => _submitting = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Respuesta del servidor no contiene datos de inserción. No se registró la orden.')));
        }
      } else {
        final err = resp.body ?? resp.error ?? 'HTTP ${resp.statusCode}';
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al enviar: $err')));
      }
    } catch (e, st) {
      debugPrint('Error posting xiaomi entry: $e\n$st');
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al enviar: $e')));
    }

    // clear inputs were handled in the branches above
  }

  void _removeOrder(_XiaomiOrderEntry entry) {
    setState(() => _orders.remove(entry));
  }

  String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int input) => input.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        // allow default back button when available
        automaticallyImplyLeading: true,
        elevation: 6,
        centerTitle: false,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Registro de órdenes Xiaomi'),
            const SizedBox(height: 2),
            Text(
              'Registrar unidades rápidamente',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (_orders.isNotEmpty)
            IconButton(
              tooltip: 'Limpiar listado',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => setState(() => _orders.clear()),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primaryContainer.withOpacity(0.6),
                  theme.scaffoldBackgroundColor,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          elevation: 8,
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Registro Unidades Xiaomi',
                                    style: theme.textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Rellena los datos y presiona Guardar registro',
                                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    focusNode: _cesbFocus,
                                    controller: _cesbController,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      labelText: 'CESB *',
                                      hintText: 'CESB (debe comenzar con "CESB")',
                                      filled: true,
                                      fillColor: theme.colorScheme.surfaceVariant.withAlpha(18),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    validator: (value) {
                                      final v = value?.trim() ?? '';
                                      if (v.isEmpty) return 'Introduce CESB';
                                      return null;
                                    },
                                    onFieldSubmitted: (_) => _skuFocus.requestFocus(),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    focusNode: _skuFocus,
                                    controller: _skuController,
                                    textInputAction: TextInputAction.next,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'SKU *',
                                      hintText: 'Sólo dígitos, 9 caracteres',
                                      filled: true,
                                      fillColor: theme.colorScheme.surfaceVariant.withAlpha(18),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    validator: (value) {
                                      final trimmed = value?.trim() ?? '';
                                      if (trimmed.isEmpty) return 'Introduce un SKU';
                                      // Format checks (numeric + length) are handled at submit time
                                      return null;
                                    },
                                    onFieldSubmitted: (_) => _partFocus.requestFocus(),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    focusNode: _partFocus,
                                    controller: _partNumberController,
                                    textInputAction: TextInputAction.next,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Part Number *',
                                      hintText: '5 dígitos',
                                      filled: true,
                                      fillColor: theme.colorScheme.surfaceVariant.withAlpha(18),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    validator: (value) {
                                      final v = value?.trim() ?? '';
                                      if (v.isEmpty) return 'Introduce Part Number';
                                      // Format checks (5 digits) are handled at submit time with confirmation
                                      return null;
                                    },
                                    onFieldSubmitted: (_) => _cantidadFocus.requestFocus(),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          focusNode: _cantidadFocus,
                                          controller: _cantidadController,
                                          keyboardType: TextInputType.number,
                                          textInputAction: TextInputAction.next,
                                          decoration: InputDecoration(
                                            labelText: 'Cantidad (Qty) *',
                                            hintText: 'Cantidad',
                                            filled: true,
                                            fillColor: theme.cardColor,
                                            border: const OutlineInputBorder(),
                                          ),
                                          validator: (value) {
                                            final raw = value?.trim() ?? '';
                                            if (raw.isEmpty) return 'Introduce una cantidad';
                                            final parsed = int.tryParse(raw);
                                            if (parsed == null || parsed <= 0) return 'Debe ser un número positivo';
                                            return null;
                                          },
                                          onFieldSubmitted: (_) => _cartonesFocus.requestFocus(),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      SizedBox(
                                        width: 140,
                                        child: TextFormField(
                                          focusNode: _cartonesFocus,
                                          controller: _cartonesController,
                                          keyboardType: TextInputType.number,
                                          textInputAction: TextInputAction.done,
                                          decoration: InputDecoration(
                                            labelText: 'Cartones *',
                                            hintText: 'Cartones',
                                            filled: true,
                                            fillColor: theme.cardColor,
                                            border: const OutlineInputBorder(),
                                          ),
                                          validator: (value) {
                                            final raw = value?.trim() ?? '';
                                            if (raw.isEmpty) return 'Introduce cartones';
                                            final parsed = int.tryParse(raw);
                                            if (parsed == null || parsed < 0) return 'Debe ser un número';
                                            return null;
                                          },
                                          onFieldSubmitted: (_) {
                                            // When pressing Enter on the last field, submit the form
                                            if (!_submitting) _submitOrder();
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton.icon(
                                      icon: _submitting
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.save_alt),
                                      label: Text(_submitting ? 'Guardando...' : 'Guardar registro'),
                                      onPressed: _submitting ? null : _submitOrder,
                                      style: ButtonStyle(
                                        padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                                        shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                        backgroundColor: MaterialStateProperty.all(theme.colorScheme.primary),
                                        foregroundColor: MaterialStateProperty.all(theme.colorScheme.onPrimary),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'Órdenes registradas (${_orders.length})',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        if (_orders.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Todavía no hay órdenes registradas.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          )
                        else
                          Column(
                            children: _orders.map((entry) {
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: theme.colorScheme.primaryContainer,
                                    child: Icon(Icons.inventory_2, color: theme.colorScheme.onPrimary),
                                  ),
                                  title: Text(
                                    entry.partNumber != null && entry.partNumber!.isNotEmpty
                                        ? '${entry.sku} — ${entry.partNumber}'
                                        : entry.sku,
                                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (entry.cesb != null && entry.cesb!.isNotEmpty) Text('CESB: ${entry.cesb}'),
                                      Text('Cantidad: ${entry.quantity}'),
                                      Text('Cartones: ${entry.cartons ?? '—'}'),
                                      Text('Creado: ${_formatTimestamp(entry.createdAt)}', style: theme.textTheme.bodySmall),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Eliminar',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _removeOrder(entry),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: EdgeNavHandle(
                user:
                    null, // Will use ApiService.instance?.currentUser from showAppSidebar
              ),
            ),
          ),
        ],
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
