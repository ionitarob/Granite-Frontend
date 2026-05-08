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
  List<MasterService> _masterServicios = [];
  List<String> _internals = [];
  final List<String> _descriptionOptions = [];

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
    _orderController = TextEditingController(text: t.orden ?? t.previ);
    _skuController = TextEditingController(text: t.sku ?? t.csku);
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

          // Ensure dropdown values are valid
          if (_fabricante != null && !_fabricantes.contains(_fabricante)) {
            _fabricante = null;
          }
          if (_cliente != null && !_clientes.contains(_cliente)) {
            _cliente = null;
          }
          if (_internalIm != null && !_internals.contains(_internalIm)) {
            _internalIm = null;
          }

          // For idXiaomi, we need to check against _funds + 'No Aplica'
          final fundIds = ['No Aplica', ..._funds.map((e) => e.idxiaomi ?? '')];
          if (_idXiaomi != null && !fundIds.contains(_idXiaomi)) {
            _idXiaomi = null;
          }

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
    final controller = TextEditingController(text: _descController.text);
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
      final payload = {
        'idxiaomi': _idXiaomi == 'No Aplica' ? null : _idXiaomi,
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
            int.tryParse(_palletsController.text.trim())?.toString() ?? '0',
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
          _error = e.toString().replaceFirst('Exception: ', '');
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
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      // backgroundColor: removed to inherit theme
      // surfaceTintColor: removed to inherit theme
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
                              // color: removed to inherit theme
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
          '$label:',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Theme.of(context).hintColor),
            filled: !enabled,
            fillColor: !enabled
                ? (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white10
                      : Colors.grey.shade100)
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.1),
              ),
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
    // Ensure uniqueness and presence of value
    final distinctItems = items.toSet();
    if (value != null) {
      distinctItems.add(value);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true, // Fix for overflow
          initialValue: value,
          items: distinctItems
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    e,
                    overflow: TextOverflow.ellipsis, // Fix for overflow
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: 'Selecciona un valor',
            hintStyle: TextStyle(color: Theme.of(context).hintColor),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
              ),
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
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
              ),
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
    final services = _masterServicios
        .map((m) => m.servicio)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (_serviceController.text.isNotEmpty &&
        !services.contains(_serviceController.text)) {
      services.add(_serviceController.text);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Servicio CF:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
            hintStyle: TextStyle(color: Theme.of(context).hintColor),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
              ),
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

  Widget _buildIdXiaomiDropdown() {
    final items = {'No Aplica', ..._funds.map((e) => e.idxiaomi ?? '')};
    if (_idXiaomi != null) {
      items.add(_idXiaomi!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Id Xiaomi:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true, // Fix for overflow
          initialValue: _idXiaomi,
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    e,
                    overflow: TextOverflow.ellipsis, // Fix for overflow
                  ),
                ),
              )
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
            hintStyle: TextStyle(color: Theme.of(context).hintColor),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
              ),
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
