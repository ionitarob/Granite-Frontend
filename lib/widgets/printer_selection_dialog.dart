import 'package:flutter/material.dart';
import '../models/agent_models.dart';
import '../services/orderops_service.dart';

class PrinterSelectionDialog extends StatefulWidget {
  final OrderOpsService service;

  const PrinterSelectionDialog({super.key, required this.service});

  @override
  State<PrinterSelectionDialog> createState() => _PrinterSelectionDialogState();
}

class _PrinterSelectionDialogState extends State<PrinterSelectionDialog> {
  List<AgentPrinter> _printers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.service.getPrinters();
      if (mounted) {
        setState(() {
          _printers = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _addNewPrinter() async {
    final nameController = TextEditingController();
    final ipController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar Nueva Impresora'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre (ej: Zebra Almacen 1)',
                hintText: 'Nombre descriptivo',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: 'Dirección IP',
                hintText: '192.168.1.100',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == true) {
      final name = nameController.text.trim();
      final ip = ipController.text.trim();
      if (name.isEmpty || ip.isEmpty) return;

      setState(() => _loading = true);
      try {
        await widget.service.createPrinter(name, ip);
        await _loadPrinters();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error guardando impresora: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Seleccionar Impresora'),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _addNewPrinter,
            tooltip: 'Añadir impresora',
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('Error: $_error'))
                : _printers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('No hay impresoras registradas'),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _addNewPrinter,
                              icon: const Icon(Icons.add),
                              label: const Text('Registrar Primera'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _printers.length,
                        itemBuilder: (context, index) {
                          final p = _printers[index];
                          return ListTile(
                            leading: const Icon(Icons.print),
                            title: Text(p.name),
                            subtitle: Text(p.ip),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.pop(context, p),
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
