import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../api_client.dart';
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

  Future<void> _editRecord(dynamic item) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return _EditRevisionDialog(item: item);
      },
    );
    if (result == true) {
      _loadData();
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
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white70),
          color: const Color(0xFF1E1E2E),
          onSelected: (val) {
            if (val == 'edit') {
              _editRecord(item);
            } else if (val == 'pdf') {
              _handleSinglePdf(item);
            } else if (val == 'delete') {
              _deleteRecord(item);
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, color: Colors.orangeAccent, size: 20),
                  SizedBox(width: 8),
                  Text('Editar', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'pdf',
              child: Row(
                children: [
                  Icon(Icons.picture_as_pdf, color: Colors.blueAccent, size: 20),
                  SizedBox(width: 8),
                  Text('Ver PDF', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  SizedBox(width: 8),
                  Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
                ],
              ),
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
                
                // Detailed Checklist (if any is 'Dañado')
                if (item['rev_accesorios'] == 'Dañado' || item['rev_roturas'] == 'Dañado' ||
                    item['rev_pantalla'] == 'Dañado' || item['rev_golpes'] == 'Dañado' ||
                    item['rev_sistema'] == 'Dañado' || item['rev_humedad'] == 'Dañado') ...[
                  const SizedBox(height: 12),
                  const Text('Checklist Incidencias:', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  if (item['rev_accesorios'] == 'Dañado') _checklistDetailText('Revisión accesorios'),
                  if (item['rev_roturas'] == 'Dañado') _checklistDetailText('Revisión Roturas'),
                  if (item['rev_pantalla'] == 'Dañado') _checklistDetailText('Revisión de la pantalla'),
                  if (item['rev_golpes'] == 'Dañado') _checklistDetailText('Revisión de golpes o arañazos'),
                  if (item['rev_sistema'] == 'Dañado') _checklistDetailText('Revisión de Errores sistema'),
                  if (item['rev_humedad'] == 'Dañado') _checklistDetailText('Revisión de humedad'),
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

class _EditRevisionDialog extends StatefulWidget {
  final dynamic item;
  const _EditRevisionDialog({required this.item});

  @override
  State<_EditRevisionDialog> createState() => _EditRevisionDialogState();
}

class _EditRevisionDialogState extends State<_EditRevisionDialog> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _partNumberController;
  late TextEditingController _serialNumberController;
  late TextEditingController _eanController;
  late TextEditingController _stickerController;
  late TextEditingController _pulgadasController;
  late TextEditingController _comentariosController;

  late String _estado;
  late bool _chequeoVisual;

  late String _revAccesorios;
  late String _revRoturas;
  late String _revPantalla;
  late String _revGolpes;
  late String _revSistema;
  late String _revHumedad;

  final List<String> _existingImages = [];
  final List<XFile> _newImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _partNumberController = TextEditingController(text: item['part_number'] ?? '');
    _serialNumberController = TextEditingController(text: item['serial_number'] ?? '');
    _eanController = TextEditingController(text: item['ean'] ?? '');
    _stickerController = TextEditingController(text: item['sticker'] ?? '');
    _pulgadasController = TextEditingController(text: item['pulgadas'] ?? '');
    _comentariosController = TextEditingController(text: item['comentarios'] ?? '');

    _estado = item['estado'] ?? 'Correcto';
    _chequeoVisual = item['chequeo_visual'] ?? false;

    _revAccesorios = item['rev_accesorios'] ?? 'Correcto';
    _revRoturas = item['rev_roturas'] ?? 'Correcto';
    _revPantalla = item['rev_pantalla'] ?? 'Correcto';
    _revGolpes = item['rev_golpes'] ?? 'Correcto';
    _revSistema = item['rev_sistema'] ?? 'Correcto';
    _revHumedad = item['rev_humedad'] ?? 'Correcto';

    if (item['image_filename'] != null && item['image_filename'].toString().isNotEmpty) {
      _existingImages.addAll(item['image_filename'].toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
    }
  }

  @override
  void dispose() {
    _partNumberController.dispose();
    _serialNumberController.dispose();
    _eanController.dispose();
    _stickerController.dispose();
    _pulgadasController.dispose();
    _comentariosController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E).withOpacity(0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Seleccionar Origen',
              style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _sourceOption(
                  icon: Icons.camera_alt,
                  label: 'Cámara',
                  onTap: () {
                    Navigator.pop(context);
                    _executePick(ImageSource.camera);
                  },
                ),
                _sourceOption(
                  icon: Icons.photo_library,
                  label: 'Galería / Archivo',
                  onTap: () {
                    Navigator.pop(context);
                    _executePick(ImageSource.gallery);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _sourceOption({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.redAccent, size: 30),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _executePick(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _newImages.add(image);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_existingImages.isEmpty && _newImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La imagen es obligatoria para guardar la revisión.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final id = widget.item['id'];

      final fields = {
        'part_number': _partNumberController.text.trim(),
        'serial_number': _serialNumberController.text.trim(),
        'ean': _eanController.text.trim(),
        'sticker': _stickerController.text.trim(),
        'pulgadas': _pulgadasController.text.trim(),
        'estado': _estado,
        'chequeo_visual': _chequeoVisual.toString(),
        'comentarios': _comentariosController.text.trim(),
        'rev_accesorios': _revAccesorios,
        'rev_roturas': _revRoturas,
        'rev_pantalla': _revPantalla,
        'rev_golpes': _revGolpes,
        'rev_sistema': _revSistema,
        'rev_humedad': _revHumedad,
        'image_filename': _existingImages.join(','),
      };

      final List<MultipartAttachment> attachments = [];
      for (int i = 0; i < _newImages.length; i++) {
        final bytes = await _newImages[i].readAsBytes();
        attachments.add(MultipartAttachment(
          fieldName: 'images',
          fileName: _newImages[i].name,
          bytes: bytes.toList(),
        ));
      }

      final res = await api.client.patchMultipart(
        '/tv/revisions/$id/',
        fields: fields,
        files: attachments,
      );

      if (res.ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Revisión actualizada correctamente'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          final errorMsg = res.body is Map ? (res.body['error'] ?? res.error) : res.error;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg ?? 'Error al actualizar revisión'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de conexión o sistema: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Revisión TV'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 0.2),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCard(
                      child: Column(
                        children: [
                          _buildTextField(
                            'Part Number', 
                            _partNumberController, 
                            isRequired: true,
                          ),
                          _buildTextField(
                            'Serial Number', 
                            _serialNumberController, 
                            isRequired: true,
                          ),
                          _buildTextField(
                            'EAN', 
                            _eanController,
                          ),
                          _buildTextField(
                            'Sticker', 
                            _stickerController,
                          ),
                          _buildTextField(
                            'Pulgadas', 
                            _pulgadasController, 
                            hint: 'ej: 55',
                          ),
                          _buildDropdown('Estado', ['Correcto', 'Defectuoso', 'Dañado']),
                          if (_estado != 'Correcto') _buildDetailedChecklist(),
                          _buildVisualCheck(),
                          _buildTextField(
                            'Comentarios', 
                            _comentariosController, 
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildImageSection(),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                      ),
                      child: _isSaving 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('GUARDAR CAMBIOS', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: child,
      ),
    );
  }

  Widget _buildTextField(
    String label, 
    TextEditingController controller, {
    bool isRequired = false, 
    int maxLines = 1, 
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white30),
          enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        validator: isRequired ? (value) => (value == null || value.isEmpty) ? 'Campo obligatorio' : null : null,
      ),
    );
  }

  Widget _buildDropdown(String label, List<String> options) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: DropdownButtonFormField<String>(
        value: _estado,
        dropdownColor: const Color(0xFF1E1E2E),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
          border: const OutlineInputBorder(),
        ),
        items: options.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: Colors.white)))).toList(),
        onChanged: (val) => setState(() => _estado = val!),
      ),
    );
  }

  Widget _buildVisualCheck() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: CheckboxListTile(
        title: const Text('Chequeo Visual OK', style: TextStyle(color: Colors.white, fontSize: 13)),
        value: _chequeoVisual,
        onChanged: (val) => setState(() => _chequeoVisual = val ?? false),
        activeColor: Colors.blueAccent,
        checkColor: Colors.white,
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
    );
  }

  Widget _buildDetailedChecklist() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DETALLE DE INCIDENCIAS',
            style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _checklistTile('Revisión accesorios', _revAccesorios, (v) => setState(() => _revAccesorios = v)),
          _checklistTile('Revisión Roturas', _revRoturas, (v) => setState(() => _revRoturas = v)),
          _checklistTile('Revisión de la pantalla', _revPantalla, (v) => setState(() => _revPantalla = v)),
          _checklistTile('Revisión de golpes o arañazos', _revGolpes, (v) => setState(() => _revGolpes = v)),
          _checklistTile('Revisión de Errores sistema', _revSistema, (v) => setState(() => _revSistema = v)),
          _checklistTile('Revisión de humedad', _revHumedad, (v) => setState(() => _revHumedad = v)),
        ],
      ),
    );
  }

  Widget _checklistTile(String title, String value, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13))),
          _buildStatusToggle(value, onChanged),
        ],
      ),
    );
  }

  Widget _buildStatusToggle(String value, ValueChanged<String> onChanged) {
    bool isDanado = value == 'Dañado';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleBtn('Correcto', !isDanado, () => onChanged('Correcto')),
          _toggleBtn('Dañado', isDanado, () => onChanged('Dañado')),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? (label == 'Dañado' ? Colors.redAccent : Colors.green) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white38,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    final api = Provider.of<ApiService>(context, listen: false);
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Imágenes (Al menos una requerida)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          if (_existingImages.isEmpty && _newImages.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No hay imágenes cargadas o seleccionadas', style: TextStyle(color: Colors.redAccent))),
            )
          else
            SizedBox(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  // Existing network images
                  ..._existingImages.map((filename) {
                    final imageUrl = '${api.client.baseUrl}/tv/revisions/${widget.item['id']}/image/?filename=$filename';
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(imageUrl, width: 120, height: 120, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.image_not_supported, color: Colors.white24)),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _existingImages.remove(filename);
                                });
                              },
                              child: Container(
                                color: Colors.black54,
                                child: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  // New picked images
                  ..._newImages.asMap().entries.map((entry) {
                    final index = entry.key;
                    final file = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(file.path), width: 120, height: 120, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _newImages.removeAt(index);
                                });
                              },
                              child: Container(
                                color: Colors.black54,
                                child: const Icon(Icons.close, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.camera_alt),
            label: const Text('TOMAR/AÑADIR FOTO'),
          ),
        ],
      ),
    );
  }
}
