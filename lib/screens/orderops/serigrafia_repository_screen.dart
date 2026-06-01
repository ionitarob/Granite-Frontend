import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import '../../services/api_service.dart';
import '../../services/serigrafia_service.dart';
import '../../api_client.dart';
import '../../widgets/main_sidebar.dart';

class SerigrafiaRepositoryScreen extends StatefulWidget {
  const SerigrafiaRepositoryScreen({super.key});

  @override
  State<SerigrafiaRepositoryScreen> createState() => _SerigrafiaRepositoryScreenState();
}

class _SerigrafiaRepositoryScreenState extends State<SerigrafiaRepositoryScreen> {
  late SerigrafiaService _service;
  List<SerigrafiaStandard> _standards = [];
  bool _isLoading = true;
  String _searchQuery = '';

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

  List<SerigrafiaStandard> get _filteredStandards {
    if (_searchQuery.isEmpty) return _standards;
    final q = _searchQuery.toLowerCase();
    return _standards.where((s) {
      return s.name.toLowerCase().contains(q) ||
          s.url.toLowerCase().contains(q) ||
          s.variables.any((v) => v.toLowerCase().contains(q));
    }).toList();
  }

  void _showEditor([SerigrafiaStandard? existing]) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl = TextEditingController(text: existing?.url ?? '');
    final varCtrl = TextEditingController(text: existing?.variables.join(', ') ?? '');
    final imgUrlCtrl = TextEditingController(
      text: (existing?.image != null && !existing!.image!.startsWith('data:image') && !existing.image!.contains('/serigrafia_standards/')) 
          ? existing.image 
          : ''
    );
    
    String? currentBase64Image = (existing?.image != null && existing!.image!.startsWith('data:image'))
        ? existing.image
        : null;
        
    Uint8List? pickedFileBytes;
    String? pickedFileName;
    bool isImageRemoved = false;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final variablesList = varCtrl.text
              .split(',')
              .map((e) => e.trim().toUpperCase())
              .where((e) => e.isNotEmpty)
              .toList();

          final hasImage = !isImageRemoved && (
              currentBase64Image != null || 
              imgUrlCtrl.text.isNotEmpty || 
              (existing?.image != null && existing!.image!.isNotEmpty)
          );
          
          final previewImageStr = currentBase64Image ?? imgUrlCtrl.text ?? existing?.image ?? '';

          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 540,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.cyan.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyan.withOpacity(0.08),
                    blurRadius: 40,
                    spreadRadius: -10,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.8),
                    blurRadius: 30,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.cyan.withOpacity(0.2), Colors.blue.withOpacity(0.1)],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.cyan.withOpacity(0.3)),
                          ),
                          child: Icon(
                            existing == null ? Icons.playlist_add_rounded : Icons.edit_note_rounded,
                            color: Colors.cyan,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                existing == null ? 'Nueva Plantilla' : 'Editar Plantilla',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                existing == null 
                                    ? 'Crea un nuevo estándar de impresión Bartender' 
                                    : 'Modifica la configuración de impresión seleccionada',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    
                    // Image selector and preview
                    Text(
                      'IMAGEN DE LA ETIQUETA (SE GUARDARÁ EN EL SERVIDOR)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.cyan.withOpacity(0.8),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Image Thumbnail Preview
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.02),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: hasImage
                                ? _buildPreviewThumbnail(previewImageStr)
                                : Center(
                                    child: Icon(
                                      Icons.image_search_rounded,
                                      color: Colors.white.withOpacity(0.2),
                                      size: 32,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () async {
                                  try {
                                    final XFile? file = await openFile(
                                      acceptedTypeGroups: <XTypeGroup>[
                                        const XTypeGroup(
                                          label: 'Imágenes',
                                          extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
                                        ),
                                      ],
                                    );
                                    if (file != null) {
                                      final bytes = await file.readAsBytes();
                                      setDialogState(() {
                                        pickedFileBytes = bytes;
                                        pickedFileName = file.name;
                                        currentBase64Image = 'data:image/png;base64,${base64.encode(bytes)}';
                                        isImageRemoved = false;
                                        imgUrlCtrl.clear();
                                      });
                                    }
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error seleccionando imagen: $e')),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.upload_file_rounded),
                                label: const Text('SUBIR IMAGEN LOCAL'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.cyan.withOpacity(0.1),
                                  foregroundColor: Colors.cyan,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(color: Colors.cyan.withOpacity(0.3)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (hasImage)
                                TextButton.icon(
                                  onPressed: () {
                                    setDialogState(() {
                                      currentBase64Image = null;
                                      pickedFileBytes = null;
                                      pickedFileName = null;
                                      imgUrlCtrl.clear();
                                      isImageRemoved = true;
                                    });
                                  },
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                                  label: const Text('ELIMINAR IMAGEN', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: imgUrlCtrl,
                      label: 'O enlace a Imagen Web (URL alternativo)',
                      hint: 'https://ejemplo.com/etiqueta.png',
                      icon: Icons.image_outlined,
                      onChanged: (_) => setDialogState(() {
                        if (imgUrlCtrl.text.isNotEmpty) {
                          currentBase64Image = null;
                          pickedFileBytes = null;
                          pickedFileName = null;
                          isImageRemoved = false;
                        }
                      }),
                    ),
                    const Divider(color: Colors.white10, height: 32),
                    
                    _buildField(
                      controller: nameCtrl,
                      label: 'Nombre de la Etiqueta',
                      hint: 'Ej: Etiqueta Estándar 4x6',
                      icon: Icons.label_outline_rounded,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 20),
                    _buildField(
                      controller: urlCtrl,
                      label: 'URL del Endpoint (Bartender)',
                      hint: 'http://servidor:8080/print',
                      icon: Icons.lan_rounded,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 20),
                    _buildField(
                      controller: varCtrl,
                      label: 'Variables Requeridas',
                      hint: 'Separadas por coma: DSN, MAC, CI_CODE',
                      icon: Icons.terminal_rounded,
                      helper: 'Las variables que el operario deberá escanear.',
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    if (variablesList.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'VISTA PREVIA DE VARIABLES (${variablesList.length})',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white.withOpacity(0.4),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: variablesList.map((v) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.cyan.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.cyan.withOpacity(0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.code_rounded, size: 10, color: Colors.cyan),
                              const SizedBox(width: 4),
                              Text(
                                v,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.cyan,
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
                    ],
                    const SizedBox(height: 40),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              side: BorderSide(color: Colors.white.withOpacity(0.12)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'CANCELAR',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.cyan.withOpacity(0.25),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: FilledButton(
                              onPressed: () async {
                                if (nameCtrl.text.isEmpty || urlCtrl.text.isEmpty) return;
                                
                                String? finalImageStr;
                                if (isImageRemoved) {
                                  finalImageStr = null;
                                } else {
                                  finalImageStr = imgUrlCtrl.text.isNotEmpty 
                                      ? imgUrlCtrl.text 
                                      : (pickedFileBytes != null ? null : existing?.image);
                                }

                                final s = SerigrafiaStandard(
                                  id: existing?.id,
                                  name: nameCtrl.text,
                                  url: urlCtrl.text,
                                  variables: variablesList,
                                  image: finalImageStr,
                                );
                                
                                final res = await _service.saveStandard(s);
                                if (res.ok && mounted) {
                                  int? newId = existing?.id;
                                  if (newId == null && res.body is Map) {
                                    newId = res.body['id'] as int?;
                                  }
                                  
                                  if (newId != null && pickedFileBytes != null) {
                                    await _service.uploadStandardImage(newId, pickedFileBytes!, pickedFileName!);
                                  }
                                  
                                  Navigator.pop(ctx);
                                  _refresh();
                                }
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.cyan,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                'GUARDAR',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String getImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return '';
    if (imagePath.startsWith('http') || imagePath.startsWith('data:image')) {
      return imagePath;
    }
    
    final baseUrl = ApiService.instance?.client.baseUrl ?? '';
    final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final cleanPath = imagePath.startsWith('/') ? imagePath : '/$imagePath';
    
    if (cleanPath.startsWith('/uploads/')) {
      return '$cleanBaseUrl$cleanPath';
    } else {
      return '$cleanBaseUrl/uploads$cleanPath';
    }
  }

  Widget _buildPreviewThumbnail(String path) {
    if (path.startsWith('data:image')) {
      try {
        final bytes = base64.decode(path.split(',').last);
        return Image.memory(bytes, fit: BoxFit.cover);
      } catch (_) {}
    }
    
    final fullUrl = getImageUrl(path);
    if (fullUrl.startsWith('http')) {
      return Image.network(
        fullUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, color: Colors.redAccent)),
      );
    }
    return const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white24));
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? helper,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.cyan,
              letterSpacing: 0.5,
            ),
          ),
        ),
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
            prefixIcon: Icon(icon, size: 20, color: Colors.cyan.withOpacity(0.7)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.015),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.cyan, width: 1.5),
            ),
            helperText: helper,
            helperMaxLines: 2,
            helperStyle: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      appBar: AppBar(
        title: const Column(
          children: [
            Text(
              'REPOSITORIO DE ETIQUETAS',
              style: TextStyle(
                letterSpacing: 2.0,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Bartender Label Templates & Endpoints Manager',
              style: TextStyle(
                fontSize: 10,
                color: Colors.cyan,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0A0A0C),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white60),
            onPressed: _refresh,
            tooltip: 'Sincronizar Repositorio',
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: Colors.white.withOpacity(0.05),
            height: 1.0,
          ),
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.cyan.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => _showEditor(),
          label: const Text(
            'NUEVA ETIQUETA',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          icon: const Icon(Icons.add_circle_outline_rounded),
          backgroundColor: Colors.cyan,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.cyan.withOpacity(0.015),
                  const Color(0xFF0A0A0C),
                ],
              ),
            ),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSearchBar(),
                      Expanded(
                        child: _filteredStandards.isEmpty
                            ? _buildEmptyState()
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  int crossAxisCount = 1;
                                  double spacing = 20.0;
                                  if (constraints.maxWidth > 1400) {
                                    crossAxisCount = 3;
                                  } else if (constraints.maxWidth > 800) {
                                    crossAxisCount = 2;
                                  }

                                  return GridView.builder(
                                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 36),
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      crossAxisSpacing: spacing,
                                      mainAxisSpacing: spacing,
                                      mainAxisExtent: 310, // Increased height to comfortably fit the preview image banner
                                    ),
                                    itemCount: _filteredStandards.length,
                                    itemBuilder: (ctx, idx) => _buildStandardCard(_filteredStandards[idx]),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
          ),
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: EdgeNavHandle(
                currentRoute: '/serials/repository',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Filtrar plantillas por nombre, endpoint o variables...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.cyan.withOpacity(0.8), size: 22),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.white38),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF131317),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.04)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: Colors.cyan.withOpacity(0.5), width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasFilter = _searchQuery.isNotEmpty;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(36),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: const Color(0xFF131317),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.05),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.cyan.withOpacity(0.1)),
              ),
              child: Icon(
                hasFilter ? Icons.search_off_rounded : Icons.inventory_2_outlined,
                size: 52,
                color: Colors.cyan,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              hasFilter ? 'Sin resultados de búsqueda' : 'No hay etiquetas configuradas',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'No se encontraron plantillas que coincidan con "$_searchQuery". Prueba con otros términos.'
                  : 'Comienza agregando un nuevo estándar de etiquetas Bartender al repositorio.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            if (hasFilter)
              OutlinedButton.icon(
                onPressed: () => setState(() => _searchQuery = ''),
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('LIMPIAR FILTRO'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyan,
                  side: BorderSide(color: Colors.cyan.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _showEditor(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('AGREGAR ETIQUETA'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyan,
                  side: BorderSide(color: Colors.cyan.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandardCard(SerigrafiaStandard s) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131317),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview Image Banner
            SizedBox(
              height: 100,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildPreviewThumbnail(s.image ?? ''),
                  // Linear gradient overlay on image for a premium look
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.1),
                          Colors.black.withOpacity(0.6),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 3,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.cyan, Colors.blue],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.lan_outlined, size: 12, color: Colors.white.withOpacity(0.35)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Tooltip(
                                message: s.url,
                                child: Text(
                                  s.url,
                                  style: TextStyle(
                                    color: Colors.cyan.withOpacity(0.8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.copy_all_rounded, size: 14, color: Colors.white.withOpacity(0.4)),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: s.url));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Endpoint URL copiado al portapapeles'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              splashRadius: 16,
                              tooltip: 'Copiar Endpoint',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit_note_rounded, size: 22, color: Colors.white.withOpacity(0.5)),
                        onPressed: () => _showEditor(s),
                        splashRadius: 20,
                        tooltip: 'Editar plantilla',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                        onPressed: () => _confirmDelete(s),
                        splashRadius: 20,
                        tooltip: 'Eliminar plantilla',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 8, thickness: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.terminal_rounded, size: 10, color: Colors.white.withOpacity(0.35)),
                        const SizedBox(width: 6),
                        Text(
                          'VARIABLES REQUERIDAS (${s.variables.length})',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: s.variables.isEmpty
                          ? Text(
                              'Ninguna variable requerida',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.2),
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            )
                          : SingleChildScrollView(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: s.variables.map((v) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.cyan.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.cyan.withOpacity(0.12)),
                                  ),
                                  child: Text(
                                    v,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.cyan,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                )).toList(),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(SerigrafiaStandard s) {
    if (s.id == null) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141416),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 26),
            SizedBox(width: 12),
            Text(
              'Eliminar Plantilla',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar "${s.name}"? Esta acción removerá el estándar de impresión del repositorio permanentemente.',
          style: TextStyle(color: Colors.white.withOpacity(0.7), height: 1.5, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            child: Text(
              'CANCELAR',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.bold),
            ),
          ),
          FilledButton(
            onPressed: () async {
              final res = await _service.deleteStandard(s.id!);
              if (res.ok && mounted) {
                Navigator.pop(ctx);
                _refresh();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('ELIMINAR ETIQUETA', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
