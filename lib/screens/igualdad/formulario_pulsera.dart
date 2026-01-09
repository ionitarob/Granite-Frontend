import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FormularioPulsera extends StatelessWidget {
  final TextEditingController imeiController;
  final TextEditingController bateriaController;
  final Map<String, dynamic>? opcionesRegistro;
  final String? tipoRegistroSeleccionado;
  final String? registroSeleccionado;
  final Map<String, String?> radioValues;
  final void Function(String tipo, String id) onChangeRegistro;
  final void Function(String key, String? value) onChangeRadio;
  final VoidCallback onRegistrar;

  const FormularioPulsera({
    super.key,
    required this.imeiController,
    required this.bateriaController,
    required this.opcionesRegistro,
    required this.tipoRegistroSeleccionado,
    required this.registroSeleccionado,
    required this.radioValues,
    required this.onChangeRegistro,
    required this.onChangeRadio,
    required this.onRegistrar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // IMEI —solo dígitos, sin maxLength—
        TextFormField(
          controller: imeiController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: 'IMEI',
            hintText: 'Introduce cualquier cantidad de dígitos',
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            labelStyle: const TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
        ),

        const SizedBox(height: 12),

        // % Batería
        TextFormField(
          controller: bateriaController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: '% Batería',
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            labelStyle: const TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
        ),

        const SizedBox(height: 12),

        // Dropdown de IDIM / OYSTA
        DropdownButtonFormField<String>(
          initialValue: tipoRegistroSeleccionado,
          items: opcionesRegistro?.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.key, style: const TextStyle(color: Colors.white)),
                      ))
                  .toList() ??
              [],
          dropdownColor: Colors.white.withValues(alpha: 0.2),
          decoration: InputDecoration(
            labelText: 'Tipo de Registro',
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            labelStyle: const TextStyle(color: Colors.white70),
          ),
          onChanged: (tipo) {
            if (tipo != null) {
              final id = opcionesRegistro![tipo]!['id'].toString();
              onChangeRegistro(tipo, id);
            }
          },
          style: const TextStyle(color: Colors.white),
        ),

        const SizedBox(height: 12),

        // Ahora tus radios / dropdowns de inspección…
        _buildSiNoDropdown('¿Daños físicos?', 'danos_fisicos'),
        const SizedBox(height: 12),
        _buildSiNoDropdown('¿Empareja con pulsera/botón?', 'empareja_pulsera_boton'),
        const SizedBox(height: 12),
        _buildSiNoDropdown('¿Sin alertas?', 'sin_alertas'),
        const SizedBox(height: 12),
        _buildSiNoDropdown('¿Chequeo abierta?', 'chequeo_abierta'),
        const SizedBox(height: 12),
        _buildSiNoDropdown('¿Serigrafía?', 'serigrafia'),
        const SizedBox(height: 12),
        _buildSiNoDropdown('¿Tornillería?', 'tornilleria'),

        // …y finalmente el botón registrar:
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: onRegistrar,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyanAccent,
          ),
          child: const Text('Registrar Pulsera', style: TextStyle(color: Colors.black)),
        ),
      ],
    );
  }

  Widget _buildSiNoDropdown(String label, String key) {
    return DropdownButtonFormField<String>(
      initialValue: radioValues[key],
      items: const [
        DropdownMenuItem(value: 'SI', child: Text('✅ Sí')),
        DropdownMenuItem(value: 'NO', child: Text('❌ No')),
      ],
      dropdownColor: Colors.white.withValues(alpha: 0.2),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        labelStyle: const TextStyle(color: Colors.white70),
      ),
      onChanged: (v) => onChangeRadio(key, v),
      style: const TextStyle(color: Colors.white),
    );
  }
}
