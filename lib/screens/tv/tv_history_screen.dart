import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../services/api_service.dart';
import '../../widgets/animated_background.dart';

class TvHistoryScreen extends StatefulWidget {
  const TvHistoryScreen({super.key});

  @override
  State<TvHistoryScreen> createState() => _TvHistoryScreenState();
}

class _TvHistoryScreenState extends State<TvHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _historial = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.get('/tv/revisions/');
      
      if (res.ok) {
        if (!mounted) return;
        setState(() {
          _historial = res.body as List<dynamic>;
          _loading = false;
        });
      } else {
        throw Exception(res.error ?? 'Error al cargar el historial');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _exportGlobalPdf() async {
    if (_historial.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay datos para exportar'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _showLoadingDialog('Generando reporte global...');

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.getBytes('/tv/revisions/export_global_pdf/');
      
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (res.ok && res.body is List<int>) {
        await _saveAndOpenPdf(res.body as List<int>, 'Reporte_Global_TV.pdf');
      } else {
        throw Exception(res.error ?? 'Error al descargar el PDF global');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Ensure dialog is closed
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al obtener PDF: $e'), 
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleSinglePdf(dynamic item) async {
    final id = item['id'];
    _showLoadingDialog('Preparando PDF para ${item['serial_number']}...');

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.getBytes('/tv/revisions/$id/export_pdf/');
      
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (res.ok && res.body is List<int>) {
        await _saveAndOpenPdf(res.body as List<int>, 'Revision_${item['serial_number']}.pdf');
      } else {
        throw Exception(res.error ?? 'El servidor no devolvió el archivo PDF');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Ensure dialog is closed
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAndOpenPdf(List<int> bytes, String filename) async {
    try {
      // Sanitize filename to avoid directory separator issues if SN contains '/'
      final safeName = filename.replaceAll('/', '_').replaceAll('\\', '_');
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$safeName');
      await file.writeAsBytes(bytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al abrir PDF: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteRecord(dynamic item) async {
    final id = item['id'];
    final sn = item['serial_number'];
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Registro'),
        content: Text('¿Estás seguro de que deseas eliminar permanentemente la revisión de SN $sn? Esto también borrará las imágenes en el servidor.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('ELIMINAR')
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.delete('/tv/revisions/$id/');
      
      if (res.ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro eliminado correctamente')),
        );
        _loadData(); // Refresh list
      } else {
        throw Exception(res.error ?? 'Error al eliminar');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial Revisión TV'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(),
          _loading 
            ? const Center(child: CircularProgressIndicator())
            : _error != null
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Error: $_error', style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _loadData, child: const Text('Reintentar')),
                  ],
                ))
              : _historial.isEmpty
                ? const Center(child: Text('No hay revisiones registradas', style: TextStyle(color: Colors.white70, fontSize: 18)))
                : Column(
                    children: [
                      _buildHeaderStats(),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: _historial.length,
                          itemBuilder: (context, index) {
                            final item = _historial[index];
                            return _buildHistoryCard(item);
                          },
                        ),
                      ),
                    ],
                  ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _exportGlobalPdf,
        label: const Text('EXPORTAR GLOBAL'),
        icon: const Icon(Icons.picture_as_pdf),
        backgroundColor: Colors.blue.shade900,
      ),
    );
  }

  Widget _buildHeaderStats() {
    final int total = _historial.length;
    final int correctos = _historial.where((item) => item['estado'] == 'Correcto').length;
    final int incidencias = _historial.where((item) => item['estado'] == 'Dañado' || item['estado'] == 'Defectuoso').length;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('TOTAL', total.toString(), Colors.white),
          _statItem('OK', correctos.toString(), Colors.greenAccent),
          _statItem('FALLOS', incidencias.toString(), Colors.orangeAccent),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
        Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildHistoryCard(dynamic item) {
    final estado = item['estado'];
    final bool isOk = estado == 'Correcto';
    final dateStr = item['created_at'] != null 
        ? DateFormat('dd/MM/yy HH:mm').format(DateTime.parse(item['created_at']).toLocal())
        : '-';

    return Card(
      key: ValueKey(item['id']),
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isOk ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)),
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: isOk ? Colors.green : Colors.red,
          child: Icon(isOk ? Icons.check : Icons.warning, color: Colors.white, size: 20),
        ),
        title: Text(
          item['serial_number'] ?? 'Sin SN',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          '${item['part_number']} - $dateStr',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.blueAccent),
              onPressed: () => _handleSinglePdf(item),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _deleteRecord(item),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('EAN:', item['ean'] ?? '-'),
                _detailRow('Pulgadas:', item['pulgadas'] ?? '-'),
                _detailRow('Sticker:', item['sticker'] ?? '-'),
                _detailRow('Usuario:', item['usuario'] ?? '-'),
                _detailRow('Visual OK:', item['chequeo_visual'] == true ? 'Correcto' : 'Fallos detectados'),
                const SizedBox(height: 8),
                const Text('Comentarios:', style: TextStyle(color: Colors.white60, fontSize: 11)),
                Text(item['comentarios'] ?? 'Sin comentarios', style: const TextStyle(color: Colors.white, fontSize: 13)),
                
                // Detailed Checklist (if any is 'Da\u00f1ado')
                if (item['rev_accesorios'] == 'Da\u00f1ado' || item['rev_roturas'] == 'Da\u00f1ado' ||
                    item['rev_pantalla'] == 'Da\u00f1ado' || item['rev_golpes'] == 'Da\u00f1ado' ||
                    item['rev_sistema'] == 'Da\u00f1ado' || item['rev_humedad'] == 'Da\u00f1ado') ...[
                  const SizedBox(height: 12),
                  const Text('Checklist Incidencias:', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  if (item['rev_accesorios'] == 'Da\u00f1ado') _checklistDetailText('Revisi\u00f3n accesorios'),
                  if (item['rev_roturas'] == 'Da\u00f1ado') _checklistDetailText('Revisi\u00f3n Roturas'),
                  if (item['rev_pantalla'] == 'Da\u00f1ado') _checklistDetailText('Revisi\u00f3n de la pantalla'),
                  if (item['rev_golpes'] == 'Da\u00f1ado') _checklistDetailText('Revisi\u00f3n de golpes o ara\u00f1azos'),
                  if (item['rev_sistema'] == 'Da\u00f1ado') _checklistDetailText('Revisi\u00f3n de Errores sistema'),
                  if (item['rev_humedad'] == 'Da\u00f1ado') _checklistDetailText('Revisi\u00f3n de humedad'),
                ],

                if (item['image_filename'] != null && item['image_filename'].toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Evidencia fotográfica:', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: item['image_filename'].toString().split(',').length,
                      itemBuilder: (ctx, i) {
                        final filename = item['image_filename'].toString().split(',')[i];
                        final api = Provider.of<ApiService>(context, listen: false);
                        final imageUrl = '${api.client.baseUrl}/tv/revisions/${item['id']}/image/?filename=$filename';
                        
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => const Icon(Icons.image_not_supported, color: Colors.white24),
                              ),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (c) => Dialog(
                                        child: Image.network(imageUrl),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _checklistDetailText(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text('• $text', style: const TextStyle(color: Colors.white, fontSize: 13)),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}
