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
  List<MasterService> _masterServicios = [];
  List<String> _internals = [];
  final List<String> _descriptionOptions = [];

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
        _analisisService.getMasterServicios(),
        _analisisService.getInternals(),
        _analisisService.getDescriptions(),
      ]);

      if (mounted) {
        setState(() {
          _funds = results[0] as List<ProjectFund>;
          _clientes = results[1] as List<String>;
          _fabricantes = results[2] as List<String>;
          _masterServicios = results[3] as List<MasterService>;
          _internals = results[4] as List<String>;
          _descriptionOptions
            ..clear()
            ..addAll(results[5] as List<String>);
          _descriptionOptions.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
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

  Future<void> _promptCustomDescription() async {
    final controller = TextEditingController();
    final description = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva descripción'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Descripción',
            hintText: 'Escribe una nueva descripción',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.pop(ctx, value);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (description == null || description.trim().isEmpty) return;

    final clean = description.trim();
    setState(() {
      if (!_descriptionOptions.contains(clean)) {
        _descriptionOptions.add(clean);
        _descriptionOptions.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      }
      _descController.text = clean;
    });
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
        'idxiaomi': _idXiaomi == 'No Aplica' ? 'N/A' : _idXiaomi,
        'estado': 'Open',
        'cost': double.tryParse(_costController.text.trim()) ?? 0.0,
        'cliente': _cliente,
        'fabricante': _fabricante,
        'descripcion': _descController.text.trim(),
        'servicio': _serviceController.text.trim(),
        'previ': _orderController.text.trim(), // Mapped to 'previ'
        'csku': _skuController.text.trim(),
        'unit': int.tryParse(_unitsController.text.trim()) ?? 0,
        'observacion': _obsController.text.trim(), // Mapped to 'observacion'
        'numsap': _sapController.text.trim(), // Mapped to 'numsap'
        'palets':
            int.tryParse(_palletsController.text.trim())?.toString() ??
            '0', // Backend expects string? No, 'palets' is allowed, likely int or string. Let's send string if controller is text.
        'claimacc': _accountController.text.trim(), // Mapped to 'claimacc'
        'internal': _internalIm, // Mapped to 'internal'
      };

      // Check local funds before submitting
      if (_idXiaomi != null && _idXiaomi != 'No Aplica') {
        final fund = _funds.firstWhere(
          (f) => f.idxiaomi == _idXiaomi,
          orElse: () => ProjectFund(totalSpent: 0, transactions: 0),
        );
        if ((fund.remaining ?? 0) <= 0) {
          setState(() {
            _error =
                "No hay fondos disponibles para realizar este servicio en este ID XIAOMI";
            _isLoading = false;
          });
          return;
        }
      }

      // Check if service exists in master list
      final serviceName = _serviceController.text.trim();
      final master = _masterServicios.where((m) => m.servicio == serviceName);
      if (master.isEmpty) {
        setState(() {
          _error =
              "El servicio '$serviceName' no existe en la lista maestra. Por favor, selecciona uno de la lista.";
          _isLoading = false;
        });
        return;
      }

      await _analisisService.createAnalisis(payload);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.cardColor,
      surfaceTintColor: Colors.transparent,
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
                      Text(
                        'Registro de servicio',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF2C3E50),
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
                                    if (v == null || v.isEmpty) {
                                      return 'Requerido';
                                    }
                                    if (int.tryParse(v) == null) {
                                      return 'Debe ser un número';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildDescriptionDropdown(),
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
                                      _idXiaomi == 'No Aplica' ||
                                      (_idXiaomi?.toUpperCase().contains(
                                            'VODAFONE',
                                          ) ??
                                          false),
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
                                    onPressed:
                                        _isLoading ||
                                            (_idXiaomi != null &&
                                                _idXiaomi != 'No Aplica' &&
                                                (_funds
                                                            .firstWhere(
                                                              (f) =>
                                                                  f.idxiaomi ==
                                                                  _idXiaomi,
                                                              orElse: () =>
                                                                  ProjectFund(
                                                                    totalSpent:
                                                                        0,
                                                                    transactions:
                                                                        0,
                                                                  ),
                                                            )
                                                            .remaining ??
                                                        0) <=
                                                    0)
                                        ? null
                                        : _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2980B9),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: _isLoading
                                        ? const CircularProgressIndicator(
                                            color: Colors.white,
                                          )
                                        : Text(
                                            (_idXiaomi != null &&
                                                    _idXiaomi != 'No Aplica' &&
                                                    (_funds
                                                                .firstWhere(
                                                                  (f) =>
                                                                      f.idxiaomi ==
                                                                      _idXiaomi,
                                                                  orElse: () =>
                                                                      ProjectFund(
                                                                        totalSpent:
                                                                            0,
                                                                        transactions:
                                                                            0,
                                                                      ),
                                                                )
                                                                .remaining ??
                                                            0) <=
                                                        0)
                                                ? 'ID SIN FONDOS'
                                                : 'REGISTRA EL SERVICIO',
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: theme.hintColor.withOpacity(0.5),
              fontSize: 13,
            ),
            filled: true,
            fillColor: !enabled
                ? (isDark ? Colors.white10 : Colors.grey.shade100)
                : (isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.grey.shade50),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF2980B9),
                width: 1.5,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.white10 : Colors.grey.shade100,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: value,
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    e,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          dropdownColor: isDark ? const Color(0xFF1B2631) : Colors.white,
          decoration: InputDecoration(
            hintText: 'Selecciona un valor',
            filled: true,
            fillColor: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.grey.shade50,
            hintStyle: TextStyle(
              color: theme.hintColor.withOpacity(0.5),
              fontSize: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDescriptionDropdown() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final options = _descriptionOptions.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (_descController.text.isNotEmpty && !options.contains(_descController.text)) {
      options.add(_descController.text);
    }
    options.add('Nueva descripción...');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Descripción:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: options.contains(_descController.text) ? _descController.text : null,
          items: options
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (selection) async {
            if (selection == 'Nueva descripción...') {
              await _promptCustomDescription();
              return;
            }
            setState(() {
              _descController.text = selection ?? '';
            });
          },
          validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
          decoration: InputDecoration(
            hintText: 'Selecciona o crea una descripción',
            filled: true,
            fillColor: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.grey.shade50,
            hintStyle: TextStyle(
              color: theme.hintColor.withOpacity(0.5),
              fontSize: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2980B9), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServiceAutocomplete() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final services = _masterServicios
        .map((m) => m.servicio)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Servicio CF:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: services.contains(_serviceController.text)
              ? _serviceController.text
              : null,
          items: services
              .map(
                (service) => DropdownMenuItem(
                  value: service,
                  child: Text(service, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (selection) {
            setState(() {
              _serviceController.text = selection ?? '';
              final master = _masterServicios.firstWhere(
                (m) => m.servicio == selection,
                orElse: () => MasterService(id: 0, servicio: '', pvd: null),
              );
              if (master.pvd != null) {
                _costController.text = master.pvd!.toStringAsFixed(2);
              }
            });
          },
          decoration: InputDecoration(
            hintText: 'Selecciona un servicio',
            filled: true,
            fillColor: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.grey.shade50,
            hintStyle: TextStyle(
              color: theme.hintColor.withOpacity(0.5),
              fontSize: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF2980B9),
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIdXiaomiDropdown() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final items = {
      'No Aplica',
      ..._funds.map((e) => e.idxiaomi ?? ''),
    }.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Id Xiaomi:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: _idXiaomi,
          dropdownColor: isDark ? const Color(0xFF1B2631) : Colors.white,
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    e,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            setState(() {
              _idXiaomi = v;
              if (v != null && v != 'No Aplica') {
                // If it's not VODAFONE, clear SAP
                bool isVodafone = v.toUpperCase().contains('VODAFONE');
                if (!isVodafone) {
                  _sapController.clear();
                }
              }
            });
          },
          decoration: InputDecoration(
            hintText: 'Selecciona un valor',
            filled: true,
            fillColor: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.grey.shade50,
            hintStyle: TextStyle(
              color: theme.hintColor.withOpacity(0.5),
              fontSize: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }
}
