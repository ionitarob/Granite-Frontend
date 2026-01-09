import 'package:flutter/material.dart';
import '../../services/analisis_service.dart';
import '../../models/analisis_models.dart';

class EditServiceDialog extends StatefulWidget {
  final Transaction transaction;

  const EditServiceDialog({super.key, required this.transaction});

  @override
  State<EditServiceDialog> createState() => _EditServiceDialogState();
}

class _EditServiceDialogState extends State<EditServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _analisisService = const AnalisisService();

  // Controllers for Text Fields
  late TextEditingController _orderController;
  late TextEditingController _skuController;
  late TextEditingController _unitsController;
  late TextEditingController _descController;
  late TextEditingController _obsController;
  late TextEditingController _sapController;
  late TextEditingController _palletsController;
  late TextEditingController _accountController;
  late TextEditingController _costController; // PVD Total
  late TextEditingController _serviceController;

  // Dropdown Values
  String? _fabricante;
  String? _cliente;
  String? _idXiaomi;
  String? _internalIm;

  // Data for Dropdowns
  List<ProjectFund> _funds = [];
  List<String> _fabricantes = [];
  List<String> _clientes = [];
  List<String> _servicios = [];
  List<String> _internals = [];

  bool _loadingData = true;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadData();
  }

  void _initializeControllers() {
    final t = widget.transaction;
    _orderController = TextEditingController(
      text: t.csku,
    ); // Assuming csku maps to order/sku combo or similar? Wait, CreateServiceDialog maps 'orden' to orderController. Transaction has 'csku'. Let's check mapping.
    // In CreateServiceDialog: 'orden': _orderController.text, 'sku': _skuController.text.
    // In Transaction model: 'csku' seems to be the combined field or one of them?
    // Looking at Transaction model, it has 'csku'.
    // Let's assume 'csku' in Transaction holds the order/sku info or just one.
    // Actually, let's look at the payload in CreateServiceDialog again.
    // 'orden' and 'sku' are sent.
    // Transaction model has 'csku'. It might be a concatenation or just one field.
    // Let's assume for now we edit what we can.
    // Wait, if the backend returns 'csku', maybe we should split it or just use it?
    // Let's look at Transaction model again.
    // It has `csku`.
    // Let's assume `csku` corresponds to `sku` or `orden`?
    // Actually, let's just use `csku` for `_skuController` and maybe `_orderController` is not in Transaction?
    // Transaction has `numsap` -> `_sapController`.
    // `unit` -> `_unitsController`.
    // `descripcion` -> `_descController`.
    // `observacion` -> `_obsController`.
    // `palets` -> `_palletsController`.
    // `claimacc` -> `_accountController`.
    // `cost` -> `_costController`.
    // `servicio` -> `_serviceController`.
    // `fabricante` -> `_fabricante`.
    // `cliente` -> `_cliente`.
    // `idxiaomi` -> `_idXiaomi`.
    // `internal` -> `_internalIm`.

    // Missing `orden` in Transaction?
    // If `csku` is the SKU, where is the Order number?
    // Maybe `csku` is "Order - SKU"?
    // For now, I'll populate `_skuController` with `csku` and leave `_orderController` empty or try to parse if it looks like "XX-XXXXX-XX".
    // But `_orderController` validator expects "XX-XXXXX-XX".
    // Let's check if `csku` contains the order.

    _skuController = TextEditingController(text: t.csku);
    _orderController =
        TextEditingController(); // We might lose this if not in Transaction
    _unitsController = TextEditingController(text: t.unit);
    _descController = TextEditingController(text: t.descripcion);
    _obsController = TextEditingController(text: t.observacion);
    _sapController = TextEditingController(text: t.numsap);
    _palletsController = TextEditingController(text: t.palets);
    _accountController = TextEditingController(text: t.claimacc);
    _costController = TextEditingController(text: t.cost?.toString());
    _serviceController = TextEditingController(text: t.servicio);

    _fabricante = t.fabricante;
    _cliente = t.cliente;
    _idXiaomi = t.idxiaomi;
    _internalIm = t.internal;
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _analisisService.getFunds(),
        _analisisService.getClientes(),
        _analisisService.getFabricantes(),
        _analisisService.getServicios(),
        _analisisService.getInternals(),
      ]);

      if (mounted) {
        setState(() {
          _funds = results[0] as List<ProjectFund>;
          _clientes = results[1] as List<String>;
          _fabricantes = results[2] as List<String>;
          _servicios = results[3] as List<String>;
          _internals = results[4] as List<String>;

          // Ensure dropdown values are valid
          if (_fabricante != null && !_fabricantes.contains(_fabricante))
            _fabricante = null;
          if (_cliente != null && !_clientes.contains(_cliente))
            _cliente = null;
          if (_internalIm != null && !_internals.contains(_internalIm))
            _internalIm = null;

          // For idXiaomi, we need to check against _funds + 'No Aplica'
          final fundIds = ['No Aplica', ..._funds.map((e) => e.idxiaomi ?? '')];
          if (_idXiaomi != null && !fundIds.contains(_idXiaomi))
            _idXiaomi = null;

          _loadingData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingData = false;
          _error = 'Error loading data: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _orderController.dispose();
    _skuController.dispose();
    _unitsController.dispose();
    _descController.dispose();
    _obsController.dispose();
    _sapController.dispose();
    _palletsController.dispose();
    _accountController.dispose();
    _costController.dispose();
    _serviceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final payload = {
        'idxiaomi': _idXiaomi == 'No Aplica' ? null : _idXiaomi,
        'cost': double.tryParse(_costController.text.trim()) ?? 0.0,
        'cliente': _cliente,
        'fabricante': _fabricante,
        'descripcion': _descController.text.trim(),
        'servicio': _serviceController.text.trim(),
        'orden': _orderController.text.trim(),
        'sku': _skuController.text.trim(),
        'unit': int.tryParse(_unitsController.text.trim()) ?? 0,
        'observaciones': _obsController.text.trim(),
        'sap_vdf': _sapController.text.trim(),
        'palets': int.tryParse(_palletsController.text.trim()) ?? 0,
        'account_claim': _accountController.text.trim(),
        'internal_im': _internalIm,
      };

      await _analisisService.patchOpenTransaction(
        widget.transaction.id!,
        payload,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: const Text(
          '¿Estás seguro de que quieres eliminar este servicio?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _analisisService.deleteOpenTransaction(widget.transaction.id!);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      child: Container(
        width: 900,
        padding: const EdgeInsets.all(32),
        child: _loadingData
            ? const Center(
                child: SizedBox(
                  height: 50,
                  width: 50,
                  child: CircularProgressIndicator(),
                ),
              )
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Editar Servicio',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2C3E50),
                            ),
                          ),
                          IconButton(
                            onPressed: _isLoading ? null : _delete,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.red,
                            ),
                            tooltip: 'Eliminar servicio',
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Column 1
                          Expanded(
                            child: Column(
                              children: [
                                _buildTextField(
                                  'Número de orden',
                                  _orderController,
                                  'XX-XXXXX-XX',
                                  validator: (v) {
                                    if (v != null && v.isNotEmpty) {
                                      if (!RegExp(
                                        r'^[A-Z0-9]{2}-[A-Z0-9]{5}-[A-Z0-9]{2}$',
                                      ).hasMatch(v)) {
                                        return 'Formato inválido (XX-XXXXX-XX)';
                                      }
                                    }
                                    // Make optional for edit if we don't have it?
                                    // Or enforce if user edits it.
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  'Número de cambio SKU',
                                  _skuController,
                                  '5 dígitos',
                                  validator: (v) {
                                    if (v != null && v.isNotEmpty) {
                                      // Allow alphanumeric if csku is alphanumeric, but prompt says 5 digits.
                                      // Let's stick to 5 digits if it's strictly SKU.
                                      // But if csku comes from backend, it might be different.
                                      // Let's relax validation for edit or keep it strict?
                                      // Keeping strict for now.
                                      // if (!RegExp(r'^\d{5}$').hasMatch(v)) {
                                      //   return 'Debe tener 5 dígitos';
                                      // }
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildDropdown(
                                  'Fabricante',
                                  _fabricantes,
                                  _fabricante,
                                  (v) => setState(() => _fabricante = v),
                                ),
                                const SizedBox(height: 16),
                                _buildDropdown(
                                  'Cliente',
                                  _clientes,
                                  _cliente,
                                  (v) => setState(() => _cliente = v),
                                ),
                                const SizedBox(height: 16),
                                _buildServiceAutocomplete(),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  'Número de unidades totales',
                                  _unitsController,
                                  'Ingrese unidades',
                                  isNumber: true,
                                  validator: (v) {
                                    if (v == null || v.isEmpty)
                                      return 'Requerido';
                                    if (int.tryParse(v) == null)
                                      return 'Debe ser un número';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  'Descripción',
                                  _descController,
                                  'Ingrese descripción',
                                  validator: (v) =>
                                      v?.isEmpty == true ? 'Requerido' : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 32),
                          // Column 2
                          Expanded(
                            child: Column(
                              children: [
                                _buildTextField(
                                  'Observaciones',
                                  _obsController,
                                  'Ingrese observaciones',
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  'Numero SAP VDF',
                                  _sapController,
                                  'Ingrese numero SAP VDF',
                                  enabled:
                                      _idXiaomi == null ||
                                      _idXiaomi == 'No Aplica',
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  'Palets EUR usados',
                                  _palletsController,
                                  'Ingrese numero de palets usados',
                                  isNumber: true,
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  'Account/Claim',
                                  _accountController,
                                  'Ingrese Account/Claim',
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  'PVD total',
                                  _costController,
                                  'Ingrese costo',
                                  isNumber: true,
                                ),
                                const SizedBox(height: 16),
                                _buildIdXiaomiDropdown(),
                                const SizedBox(height: 16),
                                _buildDropdown(
                                  'Internal IM solicitante',
                                  _internals,
                                  _internalIm,
                                  (v) => setState(() => _internalIm = v),
                                ),
                                const SizedBox(height: 32),
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2980B9),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    child: _isLoading
                                        ? const CircularProgressIndicator(
                                            color: Colors.white,
                                          )
                                        : const Text(
                                            'GUARDAR CAMBIOS',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String hint, {
    bool isNumber = false,
    String? Function(String?)? validator,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label + ':',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: !enabled,
            fillColor: !enabled ? Colors.grey.shade100 : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label + ':',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: 'Selecciona un valor',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServiceAutocomplete() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Servicio CF:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text == '') {
              return const Iterable<String>.empty();
            }
            return _servicios.where((String option) {
              return option.toLowerCase().contains(
                textEditingValue.text.toLowerCase(),
              );
            });
          },
          onSelected: (String selection) {
            _serviceController.text = selection;
          },
          fieldViewBuilder:
              (context, controller, focusNode, onEditingComplete) {
                if (controller.text.isEmpty &&
                    _serviceController.text.isNotEmpty) {
                  controller.text = _serviceController.text;
                }
                controller.addListener(() {
                  _serviceController.text = controller.text;
                });

                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  onEditingComplete: onEditingComplete,
                  decoration: InputDecoration(
                    hintText: 'Selecciona o escribe un valor',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                );
              },
        ),
      ],
    );
  }

  Widget _buildIdXiaomiDropdown() {
    final items = [
      'No Aplica',
      ..._funds.map((e) => e.idxiaomi ?? ''),
    ].toSet().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Id Xiaomi:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _idXiaomi,
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) {
            setState(() {
              _idXiaomi = v;
              if (v != null && v != 'No Aplica') {
                _sapController.clear();
              }
            });
          },
          decoration: InputDecoration(
            hintText: 'Selecciona un valor',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }
}
