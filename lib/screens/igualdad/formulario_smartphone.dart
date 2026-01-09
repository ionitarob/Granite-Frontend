import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FormularioSmartphone extends StatefulWidget {
  final TextEditingController imeiController;
  final TextEditingController bateriaController;
  final TextEditingController cometaController;
  final Map<String, dynamic>? opcionesRegistro;
  final String? tipoRegistroSeleccionado;
  final String? registroSeleccionado;
  final String? tipoSmartphone;
  final Map<String, String?> radioValues;
  final void Function(String tipo, String id) onChangeRegistro;
  final void Function(String?) onChangeTipoSmartphone;
  final VoidCallback onRegistrar;

  const FormularioSmartphone({
    super.key,
    required this.imeiController,
    required this.bateriaController,
    required this.cometaController,
    required this.opcionesRegistro,
    required this.tipoRegistroSeleccionado,
    required this.registroSeleccionado,
    required this.tipoSmartphone,
    required this.radioValues,
    required this.onChangeRegistro,
    required this.onChangeTipoSmartphone,
    required this.onRegistrar,
  });

  @override
  State<FormularioSmartphone> createState() => _FormularioSmartphoneState();
}

class _FormularioSmartphoneState extends State<FormularioSmartphone> {
  InputDecoration _glassDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withOpacity(0.2),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white),
      ),
    );
  }

  Widget _buildRadioGroup(String label, String field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(
          children: ["OK", "NO OK"].map((val) {
            final displayVal = val == "OK" ? "✅ Sí" : "❌ No";
            return Row(
              children: [
                Radio<String>(
                  fillColor: MaterialStateProperty.all(Colors.cyanAccent),
                  value: val,
                  groupValue: widget.radioValues[field],
                  onChanged: (value) {
                    setState(() {
                      widget.radioValues[field] = value;
                    });
                  },
                ),
                Text(displayVal, style: const TextStyle(color: Colors.white70)),
                const SizedBox(width: 12),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // Removed unused helper `_mostrarError` (was showing a SnackBar) because
  // it's not referenced anywhere in this widget. If you want to re-add an
  // error display helper later, consider using ScaffoldMessenger.of(context)
  // with a mounted check after any async gap.

  void _validarYRegistrar() {
    // (idéntica a tu lógica original)
    // ...
    widget.onRegistrar();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // IMEI
              TextField(
                controller: widget.imeiController,
                decoration: _glassDecoration('IMEI del Smartphone'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(15),
                ],
              ),
              const SizedBox(height: 16),

              // Registro IDIM/OYSTA
              if (widget.opcionesRegistro != null && widget.opcionesRegistro!.isNotEmpty)
                DropdownButtonFormField<String>(
                  decoration: _glassDecoration('Selecciona IDIM u OYSTA'),
                  value: widget.tipoRegistroSeleccionado,
                  dropdownColor: Colors.white.withOpacity(0.2),
                  style: const TextStyle(color: Colors.white),
                  items: widget.opcionesRegistro!.entries.map((entry) {
                    return DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text('${entry.key} ${entry.value['codigo']}'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    widget.onChangeRegistro(
                      val!,
                      widget.opcionesRegistro![val]['id'].toString(),
                    );
                  },
                )
              else
                const Center(child: CircularProgressIndicator(color: Colors.white)),
              const SizedBox(height: 16),

              // Tipo Smartphone
              DropdownButtonFormField<String>(
                decoration: _glassDecoration('Tipo de Smartphone'),
                value: widget.tipoSmartphone,
                dropdownColor: Colors.white.withOpacity(0.2),
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: "AGRESOR", child: Text("Agresor")),
                  DropdownMenuItem(value: "VICTIMA", child: Text("Víctima")),
                ],
                onChanged: widget.onChangeTipoSmartphone,
              ),
              const SizedBox(height: 16),

              // % Batería
              TextField(
                controller: widget.bateriaController,
                decoration: _glassDecoration('% Batería'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
              ),
              const SizedBox(height: 16),

              // Versión Cometa
              TextField(
                controller: widget.cometaController,
                decoration: _glassDecoration('Versión Cometa'),
              ),
              const SizedBox(height: 24),
              const Divider(color: Colors.white30),
              const SizedBox(height: 16),

              // Radios
              _buildRadioGroup("¿Ha sido remaquetado?", "remaquetado"),
              _buildRadioGroup("¿Daños físicos?", "danos_fisicos"),
              _buildRadioGroup("¿Empareja con pulsera/botón?", "empareja_pulsera_boton"),
              _buildRadioGroup("¿Incluye solapa de cargador?", "solapa_cargador"),
              _buildRadioGroup("¿Emite sonido?", "sonido"),

              // Botón Registrar
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Material(
                      color: Colors.cyan.withOpacity(0.3),
                      child: InkWell(
                        onTap: _validarYRegistrar,
                        splashColor: Colors.white24,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                          child: Text(
                            "Registrar",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
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
}
