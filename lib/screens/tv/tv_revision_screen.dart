import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../api_client.dart';
import '../../services/sound_player.dart';
import '../../widgets/animated_background.dart';

class TvRevisionScreen extends StatefulWidget {
  const TvRevisionScreen({super.key});

  @override
  State<TvRevisionScreen> createState() => _TvRevisionScreenState();
}

class _TvRevisionScreenState extends State<TvRevisionScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _partNumberController = TextEditingController();
  final TextEditingController _serialNumberController = TextEditingController();
  final TextEditingController _eanController = TextEditingController();
  final TextEditingController _stickerController = TextEditingController();
  final TextEditingController _pulgadasController = TextEditingController();
  final TextEditingController _comentariosController = TextEditingController();
  
  // Focus nodes for scanner flow
  final FocusNode _partNumberFocus = FocusNode();
  final FocusNode _serialNumberFocus = FocusNode();
  final FocusNode _eanFocus = FocusNode();
  final FocusNode _stickerFocus = FocusNode();
  final FocusNode _pulgadasFocus = FocusNode();
  final FocusNode _comentariosFocus = FocusNode();
  final FocusNode _saveBtnFocus = FocusNode();
  
  String _estado = 'Correcto';
  bool _chequeoVisual = false;
  
  final List<XFile> _images = [];
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _images.add(image);
      });
    }
  }

  Future<void> _removeImage(int index) async {
    setState(() {
      _images.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_images.isEmpty) {
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
      
      final fields = {
        'part_number': _partNumberController.text,
        'serial_number': _serialNumberController.text,
        'ean': _eanController.text,
        'sticker': _stickerController.text,
        'pulgadas': _pulgadasController.text,
        'estado': _estado,
        'chequeo_visual': _chequeoVisual.toString(),
        'comentarios': _comentariosController.text,
        'usuario': api.currentUser?.username ?? 'desconocido',
      };

      final List<MultipartAttachment> attachments = [];
      for (int i = 0; i < _images.length; i++) {
        final bytes = await _images[i].readAsBytes();
        attachments.add(MultipartAttachment(
          fieldName: 'images',
          fileName: _images[i].name,
          bytes: bytes.toList(),
        ));
      }

      final res = await api.client.postMultipart(
        '/tv/revisions/',
        fields: fields,
        files: attachments,
      );

      if (res.ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Revisión guardada correctamente')),
          );
          _resetForm();
        }
      } else {
        throw Exception(res.error ?? 'Error desconocido al guardar');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _partNumberController.clear();
    _serialNumberController.clear();
    _eanController.clear();
    _stickerController.clear();
    _pulgadasController.clear();
    _comentariosController.clear();
    setState(() {
      _estado = 'Correcto';
      _chequeoVisual = false;
      _images.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisión TV'),
        centerTitle: true,
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
                            focusNode: _partNumberFocus,
                            nextFocus: _serialNumberFocus,
                            isRequired: true,
                            autoFocus: true,
                          ),
                          _buildTextField(
                            'Serial Number', 
                            _serialNumberController, 
                            focusNode: _serialNumberFocus,
                            nextFocus: _eanFocus,
                            isRequired: true,
                          ),
                          _buildTextField(
                            'EAN', 
                            _eanController,
                            focusNode: _eanFocus,
                            nextFocus: _stickerFocus,
                          ),
                          _buildTextField(
                            'Sticker', 
                            _stickerController,
                            focusNode: _stickerFocus,
                            nextFocus: _pulgadasFocus,
                          ),
                          _buildTextField(
                            'Pulgadas', 
                            _pulgadasController, 
                            focusNode: _pulgadasFocus,
                            nextFocus: _comentariosFocus,
                            hint: 'ej: 55',
                          ),
                          _buildDropdown('Estado', ['Correcto', 'Defectuoso', 'Dañado']),
                          _buildVisualCheck(),
                          _buildTextField(
                            'Comentarios', 
                            _comentariosController, 
                            focusNode: _comentariosFocus,
                            nextFocus: _saveBtnFocus,
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
                      focusNode: _saveBtnFocus,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                      ),
                      child: _isSaving 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('GUARDAR REVISIÓN', style: TextStyle(fontWeight: FontWeight.bold)),
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
    FocusNode? focusNode,
    FocusNode? nextFocus,
    bool isRequired = false, 
    int maxLines = 1, 
    String? hint,
    bool autoFocus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autoFocus,
        maxLines: maxLines,
        textInputAction: nextFocus != null ? TextInputAction.next : TextInputAction.done,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        validator: isRequired ? (value) => (value == null || value.isEmpty) ? 'Campo obligatorio' : null : null,
        onFieldSubmitted: (_) {
          SoundPlayer.playSuccess();
          if (nextFocus != null) {
            nextFocus.requestFocus();
          }
        },
      ),
    );
  }

  Widget _buildDropdown(String label, List<String> options) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: DropdownButtonFormField<String>(
        value: _estado,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: options.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (val) => setState(() => _estado = val!),
      ),
    );
  }

  Widget _buildVisualCheck() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chequeo visual', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            CheckboxListTile(
              title: const Text('Confirmo que la revisión visual está correcta'),
              value: _chequeoVisual,
              onChanged: (val) => setState(() => _chequeoVisual = val!),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const Text(
              'Debes marcar esta casilla para registrar la revisión como correcta.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Imágenes (Obligatorio)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_images.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No hay imágenes seleccionadas', style: TextStyle(color: Colors.redAccent))),
            )
          else
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(_images[index].path), width: 120, height: 120, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              color: Colors.black54,
                              child: const Icon(Icons.close, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.camera_alt),
            label: const Text('TOMAR FOTO'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _partNumberController.dispose();
    _serialNumberController.dispose();
    _eanController.dispose();
    _stickerController.dispose();
    _pulgadasController.dispose();
    _comentariosController.dispose();
    _partNumberFocus.dispose();
    _serialNumberFocus.dispose();
    _eanFocus.dispose();
    _stickerFocus.dispose();
    _pulgadasFocus.dispose();
    _comentariosFocus.dispose();
    _saveBtnFocus.dispose();
    super.dispose();
  }
}
