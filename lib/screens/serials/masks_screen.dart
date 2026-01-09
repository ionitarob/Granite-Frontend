import 'package:flutter/material.dart';

import '../../services/mask_service.dart';
import '../../widgets/main_sidebar.dart';

class MasksScreen extends StatefulWidget {
  const MasksScreen({super.key});

  @override
  State<MasksScreen> createState() => _MasksScreenState();
}

class _MasksScreenState extends State<MasksScreen> {
  final _searchCtrl = TextEditingController();
  final _testCtrl = TextEditingController();
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  bool _checking = false;
  List<Map<String, dynamic>> _checkMatches = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final list = await MaskService.list(q: _searchCtrl.text.trim());
      setState(() => _items = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addMask() async {
    final ctrl = TextEditingController();
    final val = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nueva máscara'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Texto de máscara'),
          onSubmitted: (_) => Navigator.pop(c, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    // Dispose after the dialog has fully unwound to avoid use-after-dispose
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ctrl.dispose();
      } catch (_) {}
    });
    if (val == null || val.isEmpty) return;
    try {
      await MaskService.add(val);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo crear: $e')));
      }
    }
  }

  Future<void> _editMask(int id, String current) async {
    final ctrl = TextEditingController(text: current);
    final val = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Editar máscara'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          onSubmitted: (_) => Navigator.pop(c, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    // Dispose after the dialog has fully unwound to avoid use-after-dispose
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ctrl.dispose();
      } catch (_) {}
    });
    if (val == null || val.isEmpty || val == current) return;
    try {
      await MaskService.update(id, val);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo actualizar: $e')));
      }
    }
  }

  Future<void> _removeMask(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('¿Eliminar máscara?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MaskService.remove(id);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
      }
    }
  }

  Future<void> _checkSample() async {
    final s = _testCtrl.text.trim();
    if (s.isEmpty) return;
    setState(() {
      _checking = true;
      _checkMatches = [];
    });
    try {
      final res = await MaskService.checkSerial(s);
      setState(() => _checkMatches = res.matches);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error comprobando: $e')));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _testCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildHeader(colorScheme),
          Expanded(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildBody(colorScheme),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            const Positioned(left: 0, top: 0, bottom: 0, child: EdgeNavHandle()),
            Align(
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fact_check, size: 30, color: colorScheme.onPrimary.withOpacity(0.95)),
                  const SizedBox(width: 8),
                  Text(
                    'Máscaras de Serial',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: CircleAvatar(
                radius: 18,
                backgroundColor: colorScheme.onSurface.withOpacity(0.1),
                child: IconButton(
                  icon: Icon(Icons.add, color: colorScheme.onPrimary),
                  tooltip: 'Nueva máscara',
                  onPressed: _addMask,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(labelText: 'Buscar'),
                onSubmitted: (_) => _refresh(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _loading ? null : _refresh,
              icon: _loading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                    )
                  : const Icon(Icons.refresh),
              label: const Text('Refrescar'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _addMask,
              icon: const Icon(Icons.add),
              label: const Text('Añadir'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _loading
                        ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
                        : _items.isEmpty
                            ? const Center(child: Text('Sin datos'))
                            : ListView.separated(
                                itemCount: _items.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (c, i) {
                                  final it = _items[i];
                                  final id = (it['id'] as num?)?.toInt();
                                  final mask = it['mask']?.toString() ?? '';
                                  return ListTile(
                                    title: Text(mask),
                                    leading: Text('#${id ?? '-'}'),
                                    trailing: Wrap(
                                      spacing: 4,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit),
                                          tooltip: 'Editar',
                                          onPressed: id == null ? null : () => _editMask(id, mask),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline),
                                          tooltip: 'Eliminar',
                                          onPressed: id == null ? null : () => _removeMask(id),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                  ),
                  const Divider(height: 24),
                  const Text('Probar cadena contra máscaras'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _testCtrl,
                          decoration: const InputDecoration(hintText: 'Pega o escribe...'),
                          onSubmitted: (_) => _checkSample(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _checking ? null : _checkSample,
                        child: _checking
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                              )
                            : const Text('Comprobar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_checkMatches.isNotEmpty)
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        itemCount: _checkMatches.length,
                        itemBuilder: (c, i) {
                          final m = _checkMatches[i];
                          final mask = m['mask']?.toString() ?? '';
                          final reason = m['reason']?.toString() ?? '';
                          final score = (m['score'] is num) ? (m['score'] as num).toString() : '';
                          return ListTile(
                            dense: true,
                            title: Text(mask),
                            subtitle: Text('$reason ${score.isNotEmpty ? '($score)' : ''}'),
                          );
                        },
                      ),
                    )
                  else
                    const Text('Sin coincidencias'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
