import 'package:flutter/material.dart';
import '../../services/analisis_service.dart';
import '../../models/analisis_models.dart';

class CreateServiceDialog extends StatefulWidget {
  const CreateServiceDialog({super.key});

  @override
  State<CreateServiceDialog> createState() => _CreateServiceDialogState();
}

class _CreateServiceDialogState extends State<CreateServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _analisisService = const AnalisisService();

  // Controllers for Text Fields
  final _orderController = TextEditingController();
  final _skuController = TextEditingController();
  final _unitsController = TextEditingController();
  final _descController = TextEditingController();
  final _obsController = TextEditingController();
  final _sapController = TextEditingController();
  final _palletsController = TextEditingController();
  final _accountController = TextEditingController();
  final _costController = TextEditingController(); // PVD Total
  final _serviceController =
      TextEditingController(); // For custom service input

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
    _loadData();
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
      // Construct payload
      final payload = {
        'idxiaomi': _idXiaomi == 'No Aplica' ? null : _idXiaomi,
        'estado': 'Open',
        'cost': double.tryParse(_costController.text.trim()) ?? 0.0,
        'cliente': _cliente,
        'fabricante': _fabricante, // Assuming backend accepts this
        'descripcion': _descController.text.trim(),
        'servicio': _serviceController.text.trim(),
        'orden': _orderController.text.trim(), // Assuming backend field names
        'sku': _skuController.text.trim(),
        'unit': int.tryParse(_unitsController.text.trim()) ?? 0,
        'observaciones': _obsController.text.trim(),
        'sap_vdf': _sapController.text.trim(),
        'palets': int.tryParse(_palletsController.text.trim()) ?? 0,
        'account_claim': _accountController.text.trim(),
        'internal_im': _internalIm,
      };

      await _analisisService.createAnalisis(payload);

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
                      const Text(
                        'Registro de servicio',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C3E50),
                        ),
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
                                    if ((v == null || v.isEmpty) &&
                                        _skuController.text.isEmpty) {
                                      return 'Orden o SKU requerido';
                                    }
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
                                      if (!RegExp(r'^\d{5}$').hasMatch(v)) {
                                        return 'Debe tener 5 dígitos';
                                      }
                                    }
                                    if ((v == null || v.isEmpty) &&
                                        _orderController.text.isEmpty) {
                                      return 'Orden o SKU requerido';
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
                                            'REGISTRA EL SERVICIO',
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
          fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
            // Sync the internal controller with this one if needed, or just use this one
            // Here we use the passed controller but we need to ensure _serviceController is updated
            // We can just use _serviceController as the controller for this field if we attach it properly
            // But Autocomplete creates its own unless we pass one.
            // Actually, let's just use the fieldViewBuilder's controller to drive the UI,
            // and sync changes to _serviceController, or just use _serviceController directly if possible.
            // Simpler: Use a LayoutBuilder or just assign the controller.

            // Hack: we want to use _serviceController, but Autocomplete manages its own state.
            // We'll just listen to the controller provided by Autocomplete and update ours.
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
