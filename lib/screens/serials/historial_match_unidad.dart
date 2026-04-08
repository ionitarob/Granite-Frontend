import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api_client.dart';
import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';

class HistorialMatchUnidadScreen extends StatefulWidget {
  final String? initialSearch;
  const HistorialMatchUnidadScreen({super.key, this.initialSearch});

  static const routeName = '/serials/match-history';

  @override
  State<HistorialMatchUnidadScreen> createState() =>
      _HistorialMatchUnidadScreenState();
}

class _HistorialMatchUnidadScreenState
    extends State<HistorialMatchUnidadScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = false;
  String _typeFilter = 'TODOS';

  // Grouped results
  Map<String, List<Map<String, dynamic>>> _groupedRows = {};

  ApiClient? _clientOrNull() {
    final svc = ApiService.instance;
    if (svc != null) return svc.client;
    try {
      return Provider.of<ApiService>(context, listen: false).client;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialSearch != null) {
      _searchCtrl.text = widget.initialSearch!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final client = _clientOrNull();
      if (client == null) throw Exception('Servicio API no disponible');
      
      final term = _searchCtrl.text.trim();
      final url = term.isEmpty 
          ? '/serials/matches' 
          : '/serials/matches?q=${Uri.encodeComponent(term)}';

      final res = await client.get(url);
      if (!mounted) return;
      if (!res.ok) throw Exception('Error fetching (${res.statusCode})');
      
      final body = res.body;
      List<Map<String, dynamic>> list = [];
      if (body is Map && body['results'] is List) {
        list = (body['results'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (body is List) {
        list = body
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      // Filter locally for Type if needed
      if (_typeFilter != 'TODOS') {
        list = list.where((r) {
          final hasInventory = (r['inventory_code']?.toString().trim().isNotEmpty ?? false);
          if (_typeFilter == 'UNITARIO') return !hasInventory;
          if (_typeFilter == 'DOBLE') return hasInventory;
          return true;
        }).toList();
      }

      // Grouping logic (by Order Number)
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final r in list) {
        final order = r['num_orden']?.toString() ?? 'SIN ORDEN';
        if (!grouped.containsKey(order)) {
          grouped[order] = [];
        }
        grouped[order]!.add(r);
      }

      setState(() {
        _groupedRows = grouped;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirmar borrado'),
        content: Text(
          '¿Eliminar el vínculo del serial "${row['serial']}" con la orden "${row['num_orden']}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final client = _clientOrNull();
      if (client == null) throw Exception('Servicio API no disponible');
      
      final s = Uri.encodeComponent(row['serial']?.toString() ?? '');
      final n = Uri.encodeComponent(row['num_orden']?.toString() ?? '');
      final res = await client.delete(
        '/serials/matches/delete?serial=$s&num_orden=$n',
      );
      
      if (!mounted) return;
      if (!res.ok) throw Exception('Error borrando (${res.statusCode})');
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vínculo eliminado correctamente')),
      );
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _deleteOrder(String orderNum, List<Map<String, dynamic>> records) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Borrar orden $orderNum'),
        content: Text(
          '¿Eliminar todos los registros (${records.length}) vinculados a la orden "$orderNum"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar Todo'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final client = _clientOrNull();
      if (client == null) throw Exception('Servicio API no disponible');
      
      int successes = 0;
      int errors = 0;

      for (final row in records) {
        try {
          final s = Uri.encodeComponent(row['serial']?.toString() ?? '');
          final n = Uri.encodeComponent(row['num_orden']?.toString() ?? '');
          final res = await client.delete(
            '/serials/matches/delete?serial=$s&num_orden=$n',
          );
          if (res.ok) {
            successes++;
          } else {
            errors++;
          }
        } catch (_) {
          errors++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Proceso terminado. Éxitos: $successes, Errores: $errors',
            ),
          ),
        );
        await _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Premium Dark Theme Colors
    const kBgDark = Color(0xFF0F172A); // Slate 900
    const kBgLight = Color(0xFF1E293B); // Slate 800
    const kAccent = Color(0xFF06B6D4); // Cyan 500
    const kSurface = Color(0xFF334155); // Slate 700

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'HISTORIAL DE VINCULAR SERIAL (MATCH)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        elevation: 0,
        backgroundColor: kBgDark.withOpacity(0.8),
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kBgDark.withOpacity(0.9), Colors.transparent],
            ),
          ),
        ),
      ),
      backgroundColor: kBgDark,
      body: Stack(
        children: [
          // Background Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [kBgDark, Color(0xFF111827), Color(0xFF000000)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // Content
          SafeArea(
            child: Column(
              children: [
                _buildPremiumFilterBar(kSurface, kAccent),
                Expanded(
                  child: _groupedRows.isEmpty && !_loading
                      ? _buildEmptyState(kSurface)
                      : _loading && _groupedRows.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(color: kAccent),
                        )
                      : _buildPremiumList(kBgLight, kSurface, kAccent),
                ),
              ],
            ),
          ),
          // Sidebar Handle
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: EdgeNavHandle(
                  user: _clientOrNull() != null
                      ? Provider.of<ApiService>(
                          context,
                          listen: false,
                        ).currentUser
                      : null,
                  width: 28,
                  currentRoute: HistorialMatchUnidadScreen.routeName,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumFilterBar(Color surfaceColor, Color accentColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: surfaceColor.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Filter Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _typeFilter,
                dropdownColor: surfaceColor,
                icon: Icon(Icons.tune, color: accentColor.withOpacity(0.8)),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(value: 'TODOS', child: Text('TODOS TIPO')),
                  DropdownMenuItem(value: 'UNITARIO', child: Text('UNITARIO')),
                  DropdownMenuItem(value: 'DOBLE', child: Text('DOBLE')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _typeFilter = val);
                    _refresh();
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Search Field
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar Serial, Orden o Inventario...',
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                filled: true,
                fillColor: Colors.black26,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search, color: Colors.white54, size: 20),
                  onPressed: _refresh,
                  splashRadius: 20,
                ),
              ),
              onSubmitted: (_) => _refresh(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumList(Color bgColor, Color surfaceColor, Color accentColor) {
    final orders = _groupedRows.keys.toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: orders.length,
      itemBuilder: (ctx, idx) {
        final orderNum = orders[idx];
        final records = _groupedRows[orderNum]!;
        return _buildOrderGroupCard(orderNum, records, bgColor, surfaceColor, accentColor);
      },
    );
  }

  Widget _buildOrderGroupCard(
    String orderNum,
    List<Map<String, dynamic>> records,
    Color bgColor,
    Color surfaceColor,
    Color accentColor,
  ) {
    final bool allDoble = records.every((r) => (r['inventory_code']?.toString().trim().isNotEmpty ?? false));
    final bool allUnitario = records.every((r) => (r['inventory_code']?.toString().trim().isEmpty ?? true));
    final String modeText = allDoble ? 'DOBLE' : (allUnitario ? 'UNITARIO' : 'MIXTO');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ExpansionTile(
        initiallyExpanded: _groupedRows.length == 1,
        title: Row(
          children: [
            const Icon(Icons.receipt_long_rounded, color: Colors.blueAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    orderNum,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    modeText,
                    style: TextStyle(
                      color: allDoble ? Colors.orangeAccent : Colors.blueAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${records.length} u.',
                style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 18),
              onPressed: () => _deleteOrder(orderNum, records),
              tooltip: 'Borrar Orden',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.all(12),
        children: records.map((r) => _buildRecordRow(r, accentColor)).toList(),
      ),
    );
  }

  Widget _buildRecordRow(Map<String, dynamic> r, Color accentColor) {
    final hasInventory = (r['inventory_code']?.toString().trim().isNotEmpty ?? false);
    final serial = r['serial']?.toString() ?? '-';
    final inv = r['inventory_code']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.03)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Serial Display
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.qr_code_rounded, size: 14, color: Colors.white24),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            serial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (hasInventory) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.repeat_one_rounded, size: 14, color: Colors.orangeAccent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              inv,
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Type Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hasInventory ? Colors.orange.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: hasInventory ? Colors.orange.withOpacity(0.3) : Colors.blue.withOpacity(0.3)),
                ),
                child: Text(
                  hasInventory ? 'DOBLE' : 'UNITARIO',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: hasInventory ? Colors.orangeAccent : Colors.blueAccent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Delete Action
              IconButton(
                icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                onPressed: () => _deleteRow(r),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          if (r['usuario'] != null) ...[
            const SizedBox(height: 4),
            Text(
              'Usuario: ${r['usuario']}',
              style: const TextStyle(color: Colors.white24, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color surfaceColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: surfaceColor),
          const SizedBox(height: 16),
          Text(
            'No se encontraron registros.',
            style: TextStyle(color: surfaceColor, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
