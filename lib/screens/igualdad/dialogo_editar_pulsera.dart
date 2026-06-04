import 'package:flutter/material.dart';

class DialogoEditarPulsera extends StatefulWidget {
  final Map<String, dynamic> datos;

  const DialogoEditarPulsera({super.key, required this.datos});

  @override
  State<DialogoEditarPulsera> createState() => _DialogoEditarPulseraState();
}

class _DialogoEditarPulseraState extends State<DialogoEditarPulsera> {
  late Map<String, String?> _respuestas;
  late TextEditingController _bateriaController;
  late String _selectedContrato;

  @override
  void initState() {
    super.initState();
    _bateriaController = TextEditingController(
      text: widget.datos['porcentaje_bateria']?.toString() ?? '',
    );
    _selectedContrato = widget.datos['contrato']?.toString() ?? 'Contrato Antiguo 3 años';
    _respuestas = {
      'danos_fisicos': widget.datos['danos_fisicos']?.toString(),
      'empareja_pulsera_boton': widget.datos['empareja_pulsera_boton']?.toString(),
      'sin_alertas': widget.datos['sin_alertas']?.toString(),
      'chequeo_abierta': widget.datos['chequeo_abierta']?.toString(),
      'serigrafia': widget.datos['serigrafia']?.toString(),
      'tornilleria': widget.datos['tornilleria']?.toString(),
    };
  }

  @override
  void dispose() {
    _bateriaController.dispose();
    super.dispose();
  }

  Widget _buildYesNoSelector(String field, String label) {
    final value = _respuestas[field];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Sí'),
                selected: value == 'SI',
                onSelected: (s) => setState(() => _respuestas[field] = 'SI'),
              ),
              ChoiceChip(
                label: const Text('No'),
                selected: value == 'NO',
                onSelected: (s) => setState(() => _respuestas[field] = 'NO'),
              ),
              ChoiceChip(
                label: const Text('Sin dato'),
                selected: value == null || (value != 'SI' && value != 'NO'),
                onSelected: (s) => setState(() => _respuestas[field] = null),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imei = widget.datos['imei']?.toString() ?? 'N/A';
    final idRaw = widget.datos['id']?.toString() ?? 'N/A';
    final fecha = widget.datos['fecha']?.toString() ?? 'N/A';
    final idim = widget.datos['idim_codigo']?.toString();
    final oysta = widget.datos['oysta_codigo']?.toString();
    final String origen = idim != null ? 'IDIM: $idim' : (oysta != null ? 'OYSTA: $oysta' : 'Origen desconocido');

    return AlertDialog(
      title: const Text('Editar Pulsera'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('IMEI: $imei', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('ID: $idRaw', style: const TextStyle(fontSize: 12)),
                  Text(origen, style: const TextStyle(fontSize: 12)),
                  Text('Fecha original: $fecha', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              value: _selectedContrato,
              decoration: const InputDecoration(
                labelText: 'Contrato',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'Contrato Antiguo 3 años',
                  child: Text('Contrato Antiguo 3 años'),
                ),
                DropdownMenuItem(
                  value: 'Contrato Ampliación Sept 2026',
                  child: Text('Contrato Ampliación Sept 2026'),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedContrato = val);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bateriaController,
              decoration: const InputDecoration(
                labelText: '% Batería',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _buildYesNoSelector('danos_fisicos', '¿Daños físicos?'),
            _buildYesNoSelector('empareja_pulsera_boton', '¿Empareja pulsera/botón?'),
            _buildYesNoSelector('sin_alertas', '¿Sin alertas?'),
            _buildYesNoSelector('chequeo_abierta', '¿Chequeo abierta?'),
            _buildYesNoSelector('serigrafia', '¿Serigrafía?'),
            _buildYesNoSelector('tornilleria', '¿Tornillería?'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final result = {
              'porcentaje_bateria': _bateriaController.text.trim(),
              'contrato': _selectedContrato,
              ..._respuestas,
            };
            Navigator.of(context).pop(result);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
