import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../api_client.dart';
import '../../models/agent_models.dart';
import '../../services/api_service.dart';
import '../../services/orderops_service.dart';
import '../../widgets/main_sidebar.dart';
import 'order_detail_screen.dart';
import '../../config.dart';

class _ManualOrderPromptResult {
  const _ManualOrderPromptResult({
    required this.unitsText,
    required this.doubleEntry,
  });

  final String unitsText;
  final bool doubleEntry;
}

class _ManualUnitsDialog extends StatefulWidget {
  const _ManualUnitsDialog({required this.numOrden});

  final String numOrden;

  @override
  State<_ManualUnitsDialog> createState() => _ManualUnitsDialogState();
}

class _ManualUnitsDialogState extends State<_ManualUnitsDialog> {
  late final TextEditingController _ctrl;
  bool _doubleEntry = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      _ManualOrderPromptResult(
        unitsText: _ctrl.text.trim(),
        doubleEntry: _doubleEntry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Orden no encontrada'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Introduce el número de unidades para la orden ${widget.numOrden}.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Número de unidades'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          const Text('Tipo de registro'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Unitario'),
                selected: !_doubleEntry,
                onSelected: (_) => setState(() => _doubleEntry = false),
              ),
              ChoiceChip(
                label: const Text('Doble'),
                selected: _doubleEntry,
                onSelected: (_) => setState(() => _doubleEntry = true),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _doubleEntry
                ? 'Captura Serial y Inventario/IMEI'
                : 'Solo Serial (S/N)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Confirmar')),
      ],
    );
  }
}

class ProyectoDetailScreen extends StatefulWidget {
  final Proyecto proyecto;

  const ProyectoDetailScreen({Key? key, required this.proyecto}) : super(key: key);

  @override
  _ProyectoDetailScreenState createState() => _ProyectoDetailScreenState();
}

class _ProyectoDetailScreenState extends State<ProyectoDetailScreen> {
  OrderOpsService? _service;
  bool _isLoading = false;
  bool _isArchivoDropActive = false;
  Proyecto? _detailedProyecto;
  final TextEditingController _obsController = TextEditingController();
  final Map<int, Uint8List> _pdfPreviewCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      _service = OrderOpsService(apiService.client);
      _refreshProyecto();
    });
  }

  @override
  void dispose() {
    _obsController.dispose();
    super.dispose();
  }

  int _resolveUploadOrderId(Proyecto proyecto) {
    if (proyecto.orders?.isNotEmpty == true) {
      return proyecto.orders!.first.idnbr;
    }
    // Allow project-level files even when there are no linked orders.
    return 0;
  }

  Future<void> _refreshProyecto() async {
    if (_service == null) return;
    setState(() => _isLoading = true);
    try {
      final updated = await _service!.getProyectoDetail(widget.proyecto.id);
      setState(() {
        _detailedProyecto = updated;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar detalle del proyecto: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildSectionShell(
    ThemeData theme, {
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    final isLight = theme.brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight
              ? theme.colorScheme.outline.withOpacity(0.22)
              : theme.colorScheme.outline.withOpacity(0.35),
        ),
        color: isLight
            ? Colors.white.withOpacity(0.92)
            : theme.colorScheme.surface.withOpacity(0.34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isLight ? 0.06 : 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildMetricPill(
    ThemeData theme,
    IconData icon,
    String label,
    int value, {
    bool compact = false,
  }) {
    final isLight = theme.brightness == Brightness.light;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 11,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isLight
            ? theme.colorScheme.primary.withOpacity(0.07)
            : theme.colorScheme.surface.withOpacity(0.5),
        border: Border.all(
          color: isLight
              ? theme.colorScheme.primary.withOpacity(0.2)
              : theme.colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 3 : 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: compact ? 11 : 12, color: theme.colorScheme.primary),
          ),
          SizedBox(width: compact ? 5 : 6),
          Text(
            '$value $label',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final proyecto = _detailedProyecto ?? widget.proyecto;
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isLight = theme.brightness == Brightness.light;
    final isDesktop = screenWidth >= 900;
    final isMobile = screenWidth < 700;
    final isPhone = screenWidth < 430;
    final bottomSafeSpace = isPhone ? 120.0 : (isMobile ? 96.0 : 40.0);
    final mainContent = _isLoading && _detailedProyecto == null
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              vertical: isMobile ? 12 : 20,
              horizontal: isMobile ? 12 : 16,
            ).copyWith(bottom: bottomSafeSpace),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Project header
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                      color: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.all(0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: isLight
                                  ? [const Color(0xFFFDF7F5), const Color(0xFFF6ECE8)]
                                  : [const Color(0xFF2C1E1A), const Color(0xFF1F1513)],
                            ),
                            border: Border.all(
                              color: theme.colorScheme.outline.withOpacity(0.24),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(isLight ? 0.07 : 0.25),
                                blurRadius: 22,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(20),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 760;
                              final isPhoneCard = constraints.maxWidth < 430;
                              final infoColumn = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    proyecto.nombre,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                      fontSize: isPhoneCard ? 34 : null,
                                    ),
                                    maxLines: isPhoneCard ? 2 : 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    proyecto.description ?? 'Sin descripción',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface.withOpacity(0.78),
                                      height: 1.35,
                                      fontSize: isPhoneCard ? 13 : null,
                                    ),
                                    maxLines: isPhoneCard ? 3 : 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      _buildMetricPill(theme, Icons.receipt_long_rounded, 'pedidos', proyecto.orders?.length ?? 0, compact: isPhoneCard),
                                      _buildMetricPill(theme, Icons.forum_outlined, 'comentarios', proyecto.observations?.length ?? 0, compact: isPhoneCard),
                                      _buildMetricPill(theme, Icons.folder_open_rounded, 'archivos', proyecto.photos?.length ?? 0, compact: isPhoneCard),
                                    ],
                                  ),
                                ],
                              );

                              final actionsColumn = Column(
                                crossAxisAlignment: isNarrow ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: theme.colorScheme.primary.withOpacity(isLight ? 0.16 : 0.26),
                                    ),
                                    child: Text(
                                      proyecto.createdAt != null ? DateFormat('dd/MM/yyyy').format(proyecto.createdAt!) : '-',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: _refreshProyecto,
                                        icon: const Icon(Icons.refresh, size: 18),
                                        label: const Text('Refrescar'),
                                        style: OutlinedButton.styleFrom(
                                          visualDensity: isNarrow ? VisualDensity.compact : VisualDensity.standard,
                                          side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.35)),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                      FilledButton.tonalIcon(
                                        onPressed: _showAddCommentDialog,
                                        icon: const Icon(Icons.add_comment, size: 18),
                                        label: const Text('Comentario'),
                                        style: FilledButton.styleFrom(
                                          visualDensity: isNarrow ? VisualDensity.compact : VisualDensity.standard,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );

                              if (isNarrow) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    infoColumn,
                                    const SizedBox(height: 14),
                                    actionsColumn,
                                  ],
                                );
                              }

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: infoColumn),
                                  const SizedBox(width: 16),
                                  actionsColumn,
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Orders section
                    _buildSectionShell(
                      theme,
                      title: 'Pedidos',
                      child: proyecto.orders == null || proyecto.orders!.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text('No hay pedidos asignados a este proyecto.'),
                            )
                          : Column(
                              children: proyecto.orders!.map((order) {
                                final compactOrderRow = MediaQuery.of(context).size.width < 760;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: theme.colorScheme.surface.withOpacity(0.4),
                                    border: Border.all(color: theme.colorScheme.outline.withOpacity(0.25)),
                                  ),
                                  child: ListTile(
                                    dense: compactOrderRow,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: compactOrderRow ? 10 : 16,
                                      vertical: compactOrderRow ? 2 : 4,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: theme.colorScheme.primary.withOpacity(0.14),
                                      child: Text(
                                        order.idnbr.toString().substring(order.idnbr.toString().length - 2),
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    title: Text('Orden #${order.idnbr}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    subtitle: compactOrderRow
                                        ? Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(order.customer, maxLines: 1, overflow: TextOverflow.ellipsis),
                                              const SizedBox(height: 4),
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: _StatusBadge(status: order.estado, isNative: true),
                                              ),
                                            ],
                                          )
                                        : Text(order.customer, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    trailing: compactOrderRow
                                        ? const Icon(Icons.chevron_right_rounded)
                                        : _StatusBadge(status: order.estado, isNative: true),
                                    onTap: () async {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => OrderDetailScreen(orderId: order.idnbr),
                                        ),
                                      );
                                      if (result == true) {
                                        _refreshProyecto();
                                      }
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                    ),

                    const SizedBox(height: 24),
                    _buildObservationsPanel(theme),
                    const SizedBox(height: 24),
                    _buildArchivosPanel(theme),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          );

    return Scaffold(
      backgroundColor: isLight ? const Color(0xFFF8F7F6) : null,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: isDesktop
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Volver',
                onPressed: () => Navigator.of(context).pop(),
              ),
        actions: [
          if (isDesktop)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Volver',
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
      body: DropTarget(
        onDragEntered: (_) {
          if (!mounted) return;
          setState(() => _isArchivoDropActive = true);
        },
        onDragExited: (_) {
          if (!mounted) return;
          setState(() => _isArchivoDropActive = false);
        },
        onDragDone: (details) async {
          if (!mounted) return;
          setState(() => _isArchivoDropActive = false);
          await _uploadDroppedArchivos(details.files);
        },
        child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isLight
                        ? [const Color(0xFFF8F7F6), const Color(0xFFF1EEEC)]
                        : [theme.scaffoldBackgroundColor, theme.scaffoldBackgroundColor],
                  ),
                ),
                child: mainContent,
              ),
              if (isDesktop)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: SafeArea(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: const EdgeNavHandle(
                        currentRoute: '/orderops/proyectos',
                        showIndicator: true,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
    );
  }

  Future<void> _addObservation() async {
    final text = _obsController.text.trim();
    if (text.isEmpty) return;
    if (_service == null) return;

    setState(() => _isLoading = true);
    try {
      final proyecto = _detailedProyecto ?? widget.proyecto;
      final firstOrderId = (proyecto.orders?.isNotEmpty == true)
          ? proyecto.orders![0].idnbr
          : 0;

      final success = await _service!.postObservation(
        firstOrderId,
        text,
        proyectoId: proyecto.id,
      );
      if (success) {
        _obsController.clear();
        _refreshProyecto();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Floating actions are exposed via the AppBar menu and section buttons now.

  Widget _buildOrdersTab(Proyecto proyecto) {
    final orders = proyecto.orders ?? [];
    if (orders.isEmpty) {
      return const Center(child: Text('No hay pedidos asignados a este proyecto.'));
    }

    return ListView.builder(
      itemCount: orders.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final order = orders[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.withOpacity(0.1),
              child: Text(order.idnbr.toString().characters.takeLast(2).toString()),
            ),
            title: Text('Orden #${order.idnbr}'),
            subtitle: Text(order.customer),
            trailing: _StatusBadge(status: order.estado ?? '', isNative: true),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OrderDetailScreen(orderId: order.idnbr),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCommentsTab(Proyecto proyecto) {
    final observations = proyecto.observations ?? [];
    if (observations.isEmpty) {
      return const Center(child: Text('No hay comentarios en este proyecto.'));
    }

    return ListView.separated(
      itemCount: observations.length,
      padding: const EdgeInsets.all(16),
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final obs = observations[index];
        final dateStr = obs.createdAt != null 
            ? DateFormat('dd/MM HH:mm').format(obs.createdAt!)
            : '';
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  obs.author ?? 'Usuario',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                Text(
                  dateStr,
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(obs.body),
          ],
        );
      },
    );
  }

  Widget _buildFilesTab(Proyecto proyecto) {
    final photos = proyecto.photos ?? [];
    if (photos.isEmpty) {
      return const Center(child: Text('No hay archivos compartidos.'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        return InkWell(
          onTap: () {
            final isDoc = photo.filePath.toLowerCase().endsWith('.pdf') || photo.filePath.toLowerCase().endsWith('.doc');
            if (isDoc) {
              _openFile(photo.filePath);
            } else {
              _showPhotoPreview(photo.filePath);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: photo.filePath.toLowerCase().endsWith('.pdf') || 
                     photo.filePath.toLowerCase().endsWith('.doc')
                  ? Center(child: Icon(Icons.insert_drive_file, size: 40, color: Colors.blue[700]))
                  : Image.network(
                      photo.filePath,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image)),
                    ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddCommentDialog() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Comentario de Proyecto'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Escribe algo que todos verán...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('PUBLICAR')),
        ],
      ),
    );

    if (ok == true && controller.text.trim().isNotEmpty) {
      if (_service == null) return;
      setState(() => _isLoading = true);
      try {
        final proyecto = _detailedProyecto ?? widget.proyecto;
        final firstOrderId = (proyecto.orders?.isNotEmpty == true)
            ? proyecto.orders![0].idnbr
            : 0;

        final success = await _service!.postObservation(
          firstOrderId,
          controller.text.trim(),
          proyectoId: proyecto.id,
        );
        if (success) _refreshProyecto();
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadArchivo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (_service == null) return;

    setState(() => _isLoading = true);
    try {
      final attachments = <MultipartAttachment>[];
      for (final file in result.files) {
        final bytes = file.bytes ??
            (file.path != null ? await File(file.path!).readAsBytes() : null);
        if (bytes == null || bytes.isEmpty) {
          continue;
        }
        attachments.add(
          MultipartAttachment(
            fieldName: 'files',
            fileName: file.name.isNotEmpty
                ? file.name
                : 'archivo_${DateTime.now().millisecondsSinceEpoch}',
            bytes: bytes,
          ),
        );
      }

      if (attachments.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo leer ningun archivo seleccionado')),
        );
        return;
      }

      final proyecto = _detailedProyecto ?? widget.proyecto;
      final uploadOrderId = _resolveUploadOrderId(proyecto);

      final response = await _service!.uploadPhotos(
        uploadOrderId,
        attachments,
        proyectoId: proyecto.id,
      );
      if (response.ok) {
        await _refreshProyecto();
        final body = response.body;
        int uploaded = attachments.length;
        int skipped = 0;
        if (body is Map) {
          uploaded = (body['count_uploaded'] as num?)?.toInt() ?? uploaded;
          skipped = (body['count_skipped'] as num?)?.toInt() ?? 0;
        }
        final msg = skipped > 0
            ? 'Subidos $uploaded archivo(s). $skipped duplicado(s) omitido(s).'
            : 'Subidos $uploaded archivo(s) en Archivos.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      } else if (response.statusCode == 409) {
        final body = response.body;
        final skipped = body is Map
            ? ((body['count_skipped'] as num?)?.toInt() ?? attachments.length)
            : attachments.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se subio ningun archivo: $skipped ya existia(n).')),
        );
      } else {
        final body = response.body;
        final message = body is Map
            ? (body['error']?.toString() ?? body['detail']?.toString() ?? 'Error desconocido')
            : (body?.toString() ?? 'Error desconocido');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo subir archivos: $message')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error subiendo: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadDroppedArchivos(List<dynamic> droppedFiles) async {
    if (droppedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drop detectado, pero no se recibieron archivos.')),
      );
      return;
    }
    if (_service == null) {
      final api = ApiService.instance;
      if (api != null) {
        _service = OrderOpsService(api.client);
      }
    }
    if (_service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servicio de subida no disponible.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final attachments = <MultipartAttachment>[];
      var failedReads = 0;
      for (final dropped in droppedFiles) {
        try {
          List<int> bytes = const [];
          try {
            bytes = await dropped.readAsBytes();
          } catch (_) {
            bytes = const [];
          }
          final rawPath = (dropped.path ?? '').toString();
          if (bytes.isEmpty && rawPath.isNotEmpty) {
            try {
              bytes = await File(rawPath).readAsBytes();
            } catch (_) {
              bytes = const [];
            }
          }
          if (bytes.isEmpty) {
            failedReads += 1;
            continue;
          }
          final rawName = (dropped.name ?? '').toString().trim();
          final fallback = 'archivo_${DateTime.now().millisecondsSinceEpoch}';
          final fileName = rawName.isNotEmpty ? rawName : fallback;
          attachments.add(
            MultipartAttachment(
              fieldName: 'files',
              fileName: fileName,
              bytes: bytes,
            ),
          );
        } catch (_) {
          failedReads += 1;
        }
      }

      if (attachments.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failedReads > 0
                  ? 'Se detectaron ${droppedFiles.length} archivo(s), pero no se pudieron leer.'
                  : 'No se detectaron archivos validos en el drop.',
            ),
          ),
        );
        return;
      }

      final proyecto = _detailedProyecto ?? widget.proyecto;
      final uploadOrderId = _resolveUploadOrderId(proyecto);

      final response = await _service!.uploadPhotos(
        uploadOrderId,
        attachments,
        proyectoId: proyecto.id,
      );
      if (response.ok) {
        await _refreshProyecto();
        final body = response.body;
        int uploaded = attachments.length;
        int skipped = 0;
        if (body is Map) {
          uploaded = (body['count_uploaded'] as num?)?.toInt() ?? uploaded;
          skipped = (body['count_skipped'] as num?)?.toInt() ?? 0;
        }
        final msg = skipped > 0
            ? 'Subidos $uploaded archivo(s). $skipped duplicado(s) omitido(s).'
            : 'Subidos $uploaded archivo(s) en Archivos.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      } else if (response.statusCode == 409) {
        final body = response.body;
        final skipped = body is Map
            ? ((body['count_skipped'] as num?)?.toInt() ?? attachments.length)
            : attachments.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se subio ningun archivo: $skipped ya existia(n).')),
        );
      } else {
        final body = response.body;
        final message = body is Map
            ? (body['error']?.toString() ?? body['detail']?.toString() ?? 'Error desconocido')
            : (body?.toString() ?? 'Error desconocido');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo subir archivos: $message')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error subiendo archivos: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildObservationsPanel(ThemeData theme) {
    final observations = (_detailedProyecto ?? widget.proyecto).observations ?? [];

    return _buildSectionShell(
      theme,
      title: 'Comentarios',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 700;
              final textField = TextField(
                controller: _obsController,
                decoration: InputDecoration(
                  hintText: 'Añadir nueva observación...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: theme.colorScheme.surface.withOpacity(0.45),
                ),
                maxLines: 2,
              );

              final addButton = FilledButton.icon(
                onPressed: _addObservation,
                icon: const Icon(Icons.add_comment, size: 18),
                label: const Text('Añadir'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    textField,
                    const SizedBox(height: 10),
                    addButton,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: textField),
                  const SizedBox(width: 12),
                  addButton,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          observations.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('No hay comentarios en este proyecto.'),
                )
              : Column(
                  children: observations.map((obs) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: theme.colorScheme.surface.withOpacity(0.4),
                        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.28)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(obs.author ?? 'Usuario', style: const TextStyle(fontWeight: FontWeight.w700)),
                              const Spacer(),
                              Text(
                                obs.createdAt != null ? DateFormat('dd/MM HH:mm').format(obs.createdAt!) : '',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withOpacity(0.62),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(obs.body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.3)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ],
      ),
    );
  }

  Widget _buildArchivosPanel(ThemeData theme) {
    final photos = (_detailedProyecto ?? widget.proyecto).photos ?? [];
    final borderColor = _isArchivoDropActive
        ? theme.colorScheme.primary
        : theme.colorScheme.outline.withOpacity(0.5);

    return _buildSectionShell(
      theme,
      title: 'Archivos',
      trailing: IconButton(
        onPressed: _uploadArchivo,
        icon: const Icon(Icons.drive_folder_upload_rounded),
        tooltip: 'Subir archivo',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _uploadArchivo,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1.5),
                color: _isArchivoDropActive
                    ? theme.colorScheme.primary.withOpacity(0.08)
                    : theme.colorScheme.surface.withOpacity(0.12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.upload_file_rounded,
                    color: _isArchivoDropActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withOpacity(0.75),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isArchivoDropActive
                          ? 'Suelta los archivos para subirlos'
                          : 'Arrastra y suelta 1 o mas archivos aqui, o haz click para seleccionar',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.85),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          photos.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('No hay archivos compartidos.'),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = constraints.maxWidth >= 1200
                        ? 220.0
                        : constraints.maxWidth >= 700
                            ? 200.0
                            : constraints.maxWidth;

                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: photos
                          .map(
                            (file) => SizedBox(
                              width: cardWidth,
                              child: _buildArchivoThumbCard(file),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
        ],
      ),
    );
  }

  bool _isImageFile(AgentOrderPhoto file) {
    final path = file.filePath.toLowerCase();
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.webp') ||
        path.endsWith('.gif') ||
        path.endsWith('.bmp');
  }

  bool _isPdfFile(AgentOrderPhoto file) {
    return file.filePath.toLowerCase().endsWith('.pdf');
  }

  String _resolveArchivoUrl(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return '$kBackendBaseUrl/uploads/';

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    var path = trimmed;
    if (path.startsWith('/uploads/')) {
      path = path.substring('/uploads/'.length);
    } else if (path.startsWith('uploads/')) {
      path = path.substring('uploads/'.length);
    } else if (path.startsWith('/')) {
      path = path.substring(1);
    }

    return '$kBackendBaseUrl/uploads/$path';
  }

  Widget _buildArchivoThumbCard(AgentOrderPhoto file) {
    final isImage = _isImageFile(file);
    final isPdf = _isPdfFile(file);
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (isImage) {
          _showPhotoPreview(file.filePath);
        } else if (isPdf) {
          _previewPdfFile(file);
        } else {
          _downloadAndOpenArchivo(file);
        }
      },
      child: Container(
        height: 138,
        decoration: BoxDecoration(
          color: isLight
              ? Colors.white
              : theme.colorScheme.surface.withOpacity(0.32),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLight
                ? theme.colorScheme.outline.withOpacity(0.42)
                : theme.colorScheme.outline.withOpacity(0.3),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Positioned.fill(
                child: isImage
                    ? Image.network(
                    _resolveArchivoUrl(file.filePath),
                        fit: BoxFit.cover,
                        headers: {
                          if (ApiService.instance?.client.accessToken != null)
                            'Authorization':
                                'Bearer ${ApiService.instance!.client.accessToken}',
                        },
                        errorBuilder: (_, __, ___) =>
                            const Center(child: Icon(Icons.broken_image, color: Colors.white38)),
                      )
                    : Container(
                        color: isLight
                            ? const Color(0xFFF2F2F2)
                            : Colors.white.withOpacity(0.05),
                        child: Center(
                          child: Icon(
                            isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                            color: isPdf
                                ? (isLight ? const Color(0xFFD33D2F) : Colors.redAccent)
                                : (isLight ? Colors.black54 : Colors.white70),
                            size: 40,
                          ),
                        ),
                      ),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: InkWell(
                  onTap: () => _downloadAndOpenArchivo(file),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.download_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 6,
                top: 6,
                child: InkWell(
                  onTap: () => _deleteArchivo(file),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: isLight ? Colors.black87 : Colors.black54,
                  child: Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _uploadFile() async {
    await _uploadArchivo();
  }

  Future<Uint8List> _downloadProjectFileBytes(AgentOrderPhoto file) async {
    final token = ApiService.instance?.client.accessToken;
    final normalizedPath = _resolveArchivoUrl(file.filePath);
    final url = Uri.parse(normalizedPath);
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      return await consolidateHttpClientResponseBytes(response);
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List?> _getPdfPreviewBytes(AgentOrderPhoto file) async {
    final cached = _pdfPreviewCache[file.id];
    if (cached != null) return cached;

    try {
      final bytes = await _downloadProjectFileBytes(file);
      _pdfPreviewCache[file.id] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _previewPdfFile(AgentOrderPhoto file) async {
    try {
      final bytes = await _getPdfPreviewBytes(file);
      if (bytes == null) {
        await _downloadAndOpenArchivo(file);
        return;
      }
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(18),
          child: SizedBox(
            width: 920,
            height: 720,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.black12,
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          file.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SfPdfViewer.memory(bytes),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      await _downloadAndOpenArchivo(file);
    }
  }

  Future<void> _downloadAndOpenArchivo(AgentOrderPhoto file) async {
    try {
      final bytes = await _downloadProjectFileBytes(file);
      final dir = await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/${file.fileName}');
      await out.writeAsBytes(bytes, flush: true);
      await OpenFilex.open(out.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir el archivo: $e')),
      );
    }
  }

  Future<void> _deleteArchivo(AgentOrderPhoto file) async {
    if (_service == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar archivo'),
        content: Text('Deseas eliminar ${file.fileName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final ok = await _service!.deletePhoto(file.idnbr, file.id);
      if (!mounted) return;
      if (ok) {
        await _refreshProyecto();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Archivo eliminado de Archivos')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo eliminar el archivo')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error eliminando archivo: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openFile(String url) {
    // Simple URL open logic (could use url_launcher)
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Abriendo: $url')));
  }

  void _showPhotoPreview(String filePath) {
    final imageUrl = _resolveArchivoUrl(filePath);

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                height: 480,
                child: InteractiveViewer(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 48)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () { Navigator.of(ctx).pop(); _openFile(imageUrl); }, child: const Text('Abrir')),
                    const SizedBox(width: 8),
                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool isNative;
  const _StatusBadge({required this.status, this.isNative = false});

  @override
  Widget build(BuildContext context) {
    if (status.isEmpty) return const SizedBox.shrink();

    String statusLabel = status;
    Color color = Colors.grey;

    if (isNative) {
      if (status.contains('1')) {
        statusLabel = 'Validada';
        color = Colors.blue;
      } else if (status.contains('2')) {
        statusLabel = 'Pendiente';
        color = Colors.orange;
      } else if (status.contains('3')) {
        statusLabel = 'En Ejecución';
        color = Colors.cyan;
      } else if (status.contains('4')) {
        statusLabel = 'Parada';
        color = Colors.red;
      } else if (status.contains('5')) {
        statusLabel = 'Finalizada';
        color = Colors.green;
      } else if (status.contains('6')) {
        statusLabel = 'Facturada';
        color = Colors.purple;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        statusLabel,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
