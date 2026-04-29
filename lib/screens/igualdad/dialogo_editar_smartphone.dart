import 'package:flutter/material.dart';

class DialogoEditarSmartphone extends StatefulWidget {
  final Map<String, dynamic> datos;

  const DialogoEditarSmartphone({super.key, required this.datos});

  @override
  State<DialogoEditarSmartphone> createState() => _DialogoEditarSmartphoneState();
}

class _DialogoEditarSmartphoneState extends State<DialogoEditarSmartphone> {
  late Map<String, String?> _respuestas;
  late TextEditingController _bateriaController;
  late TextEditingController _cometaController;
  late String _tipoSmartphone;

  @override
  void initState() {
    super.initState();
    _bateriaController = TextEditingController(
      text: widget.datos['porcentaje_bateria']?.toString() ?? '',
    );
    _cometaController = TextEditingController(
      text: widget.datos['version_cometa']?.toString() ?? '',
    );
    _tipoSmartphone = widget.datos['tipo']?.toString() ?? 'SM-OFENSOR';

    _respuestas = {
      'remaquetado': widget.datos['remaquetado']?.toString(),
      'danos_fisicos': widget.datos['danos_fisicos']?.toString(),
      'empareja_pulsera_boton': widget.datos['empareja_pulsera_boton']?.toString(),
      'solapa_cargador': widget.datos['solapa_cargador']?.toString(),
      'sonido': widget.datos['sonido']?.toString(),
    };
  }

  @override
  void dispose() {
    _bateriaController.dispose();
    _cometaController.dispose();
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
      title: const Text('Editar Smartphone'),
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
              value: _tipoSmartphone,
              decoration: const InputDecoration(
                labelText: 'Tipo',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'SM-OFENSOR', child: Text('Ofensor')),
                DropdownMenuItem(value: 'SM-VICTIMA', child: Text('Víctima')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _tipoSmartphone = val);
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
            TextField(
              controller: _cometaController,
              decoration: const InputDecoration(
                labelText: 'Versión Cometa',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildYesNoSelector('remaquetado', '¿Remaquetado?'),
            _buildYesNoSelector('danos_fisicos', '¿Daños físicos?'),
            _buildYesNoSelector('empareja_pulsera_boton', '¿Empareja botón/pulsera?'),
            _buildYesNoSelector('solapa_cargador', '¿Solapa cargador OK?'),
            _buildYesNoSelector('sonido', '¿Sonido OK?'),
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
              'tipo': _tipoSmartphone,
              'porcentaje_bateria': _bateriaController.text.trim(),
              'version_cometa': _cometaController.text.trim(),
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
