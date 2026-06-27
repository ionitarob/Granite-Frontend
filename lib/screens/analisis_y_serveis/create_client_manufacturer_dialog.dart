import 'package:flutter/material.dart';
import '../../services/analisis_service.dart';

class CreateClientManufacturerDialog extends StatefulWidget {
  const CreateClientManufacturerDialog({super.key});

  @override
  State<CreateClientManufacturerDialog> createState() =>
      _CreateClientManufacturerDialogState();
}

class _CreateClientManufacturerDialogState
    extends State<CreateClientManufacturerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _analisisService = const AnalisisService();
  final _nameController = TextEditingController();

  int _selectedType = 0; // 0 = Cliente, 1 = Fabricante, 2 = Internal
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final name = _nameController.text.trim();
      if (_selectedType == 0) {
        await _analisisService.createCliente(name);
      } else if (_selectedType == 1) {
        await _analisisService.createFabricante(name);
      } else {
        await _analisisService.createInternal(name);
      }

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
        width: 500, // Slightly wider to fit 3 buttons
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Nuevo Registro',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                      hoverColor: Colors.grey.shade200,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
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
              // Toggle Buttons
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _buildToggleButton('Cliente', 0),
                    _buildToggleButton('Fabricante', 1),
                    _buildToggleButton('Internal', 2),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                autofocus: true,
                style: const TextStyle(color: Color(0xFF2C3E50)),
                decoration: InputDecoration(
                  labelText: _getLabel(),
                  labelStyle: const TextStyle(color: Color(0xFF7F8C8D)),
                  hintText: 'Ingrese nombre',
                  hintStyle: const TextStyle(color: Color(0xFFB0BEC5)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, color: Color(0xFF7F8C8D)),
                    onPressed: _nameController.clear,
                  ),
                ),
                validator: (v) =>
                    v?.trim().isEmpty == true ? 'Requerido' : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1ABC9C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Guardar',
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
      ),
    );
  }

  Widget _buildToggleButton(String label, int index) {
    final isSelected = _selectedType == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedType = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected
                  ? const Color(0xFF2C3E50)
                  : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }

  String _getLabel() {
    switch (_selectedType) {
      case 0:
        return 'Nombre del Cliente';
      case 1:
        return 'Nombre del Fabricante';
      case 2:
        return 'Nombre Internal';
      default:
        return 'Nombre';
    }
  }
}
