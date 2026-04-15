import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/serigrafia_service.dart';
import '../../api_client.dart';

class SerigrafiaRepositoryScreen extends StatefulWidget {
  const SerigrafiaRepositoryScreen({super.key});

  @override
  State<SerigrafiaRepositoryScreen> createState() => _SerigrafiaRepositoryScreenState();
}

class _SerigrafiaRepositoryScreenState extends State<SerigrafiaRepositoryScreen> {
  late SerigrafiaService _service;
  List<SerigrafiaStandard> _standards = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final client = ApiService.instance?.client;
    if (client != null) {
      _service = SerigrafiaService(client);
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final list = await _service.getStandards();
    if (mounted) {
      setState(() {
        _standards = list;
        _isLoading = false;
      });
    }
  }

  void _showEditor([SerigrafiaStandard? existing]) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl = TextEditingController(text: existing?.url ?? '');
    final varCtrl = TextEditingController(text: existing?.variables.join(', ') ?? '');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      existing == null ? Icons.label_outline_rounded : Icons.edit_note_rounded,
                      color: Colors.cyan,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    existing == null ? 'Nueva Etiqueta' : 'Editar Etiqueta',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _buildField(
                controller: nameCtrl,
                label: 'Nombre de la Etiqueta',
                hint: 'Ej: Etiqueta Estándar 4x6',
                icon: Icons.label_outline_rounded,
              ),
              const SizedBox(height: 20),
              _buildField(
                controller: urlCtrl,
                label: 'URL del Endpoint (Bartender)',
                hint: 'http://servidor:8080/print',
                icon: Icons.link_rounded,
              ),
              const SizedBox(height: 20),
              _buildField(
                controller: varCtrl,
                label: 'Variables Requeridas',
                hint: 'Separadas por coma: DSN, MAC, CI_CODE',
                icon: Icons.list_alt_rounded,
                helper: 'Estas variables se pedirán al operario al escanear.',
              ),
              const SizedBox(height: 40),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('CANCELAR', style: TextStyle(color: Colors.white38)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        if (nameCtrl.text.isEmpty || urlCtrl.text.isEmpty) return;
                        
                        final s = SerigrafiaStandard(
                          id: existing?.id,
                          name: nameCtrl.text,
                          url: urlCtrl.text,
                          variables: varCtrl.text.split(',').map((e) => e.trim().toUpperCase()).where((e) => e.isNotEmpty).toList(),
                        );
                        
                        final res = await _service.saveStandard(s);
                        if (res.ok && mounted) {
                          Navigator.pop(ctx);
                          _refresh();
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.cyan,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? helper,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ),
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20, color: Colors.cyan.withOpacity(0.5)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.03),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.cyan, width: 1),
            ),
            helperText: helper,
            helperStyle: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.3)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('REPOSITORIO DE ETIQUETAS', style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.bold, fontSize: 14)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(),
        label: const Text('NUEVA ETIQUETA'),
        icon: const Icon(Icons.add_rounded),
        backgroundColor: Colors.cyan,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.cyan.withOpacity(0.05), Colors.black],
          ),
        ),
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
          : _standards.isEmpty 
            ? _buildEmptyState()
            : ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: _standards.length,
                itemBuilder: (ctx, idx) => _buildStandardCard(_standards[idx]),
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.white10),
          const SizedBox(height: 16),
          Text('No hay etiquetas configuradas', style: TextStyle(color: Colors.white24)),
        ],
      ),
    );
  }

  Widget _buildStandardCard(SerigrafiaStandard s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(s.url, style: TextStyle(color: Colors.cyan.withOpacity(0.7), fontSize: 11)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: s.variables.map((v) => Chip(
                    label: Text(v, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    backgroundColor: Colors.cyan.withOpacity(0.1),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )).toList(),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit_rounded, size: 20), onPressed: () => _showEditor(s)),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                  onPressed: () => _confirmDelete(s),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(SerigrafiaStandard s) {
    if (s.id == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Etiqueta'),
        content: Text('¿Estás seguro de que deseas eliminar "${s.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () async {
              final res = await _service.deleteStandard(s.id!);
              if (res.ok && mounted) {
                Navigator.pop(ctx);
                _refresh();
              }
            },
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
