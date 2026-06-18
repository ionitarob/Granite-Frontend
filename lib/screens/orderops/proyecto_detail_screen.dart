import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    _taskController.dispose();
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
        _localTasks = List.of(updated.tasks ?? []);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar detalle del proyecto: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _renameProyecto(Proyecto p) async {
    if (_service == null) return;
    final ctrl = TextEditingController(text: p.nombre);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar Proyecto'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      try {
        await _service!.updateProyecto(p.id, nombre: ctrl.text.trim());
        await _refreshProyecto();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _toggleArchive(Proyecto p) async {
    if (_service == null) return;
    final isArchiving = p.status == 'Activo';
    final newStatus = isArchiving ? 'Archivado' : 'Activo';
    final label = isArchiving ? 'archivar' : 'restaurar';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isArchiving ? 'Archivar Proyecto' : 'Restaurar Proyecto'),
        content: Text('¿Seguro que quieres $label "${p.nombre}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isArchiving ? 'Archivar' : 'Restaurar')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _service!.updateProyecto(p.id, status: newStatus);
        await _refreshProyecto();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
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
                              final isArchived = proyecto.status == 'Archivado';
                              final statusColor = isArchived ? Colors.grey : Colors.green;

                              final infoColumn = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Status chip
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.13),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: statusColor.withOpacity(0.4), width: 1),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
                                        const SizedBox(width: 5),
                                        Text(
                                          proyecto.status,
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    proyecto.nombre,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    proyecto.description?.isNotEmpty == true
                                        ? proyecto.description!
                                        : 'Sin descripción',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface.withOpacity(0.68),
                                      height: 1.35,
                                    ),
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      _buildMetricPill(theme, Icons.receipt_long_rounded, 'pedidos', proyecto.effectiveOrderCount, compact: isPhoneCard),
                                      _buildMetricPill(theme, Icons.forum_outlined, 'comentarios', proyecto.effectiveObsCount, compact: isPhoneCard),
                                      _buildMetricPill(theme, Icons.folder_open_rounded, 'archivos', proyecto.effectiveFileCount, compact: isPhoneCard),
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
                                  FilledButton.tonalIcon(
                                    onPressed: _showAddCommentDialog,
                                    icon: const Icon(Icons.add_comment_rounded, size: 18),
                                    label: const Text('Comentario'),
                                    style: FilledButton.styleFrom(
                                      visualDensity: isNarrow ? VisualDensity.compact : VisualDensity.standard,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
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
                      title: 'Pedidos (${proyecto.effectiveOrderCount})',
                      child: proyecto.orders == null || proyecto.orders!.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text('No hay pedidos asignados a este proyecto.'),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Estado distribution bar
                                _EstadoBar(orders: proyecto.orders!),
                                const SizedBox(height: 12),
                                ...proyecto.orders!.map((order) {
                                  return _OrderRow(
                                    order: order,
                                    theme: theme,
                                    onTap: () async {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => OrderDetailScreen(orderId: order.idnbr),
                                        ),
                                      );
                                      if (result == true) _refreshProyecto();
                                    },
                                  );
                                }),
                              ],
                            ),
                    ),

                    const SizedBox(height: 24),
                    _buildChecklistPanel(theme),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'Opciones del proyecto',
            onSelected: (v) async {
              final p = _detailedProyecto ?? widget.proyecto;
              switch (v) {
                case 'rename':
                  await _renameProyecto(p);
                case 'archive':
                  await _toggleArchive(p);
                case 'refresh':
                  _refreshProyecto();
              }
            },
            itemBuilder: (_) {
              final p = _detailedProyecto ?? widget.proyecto;
              final isArchived = p.status == 'Archivado';
              return [
                const PopupMenuItem(
                  value: 'rename',
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Renombrar'),
                  ]),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: Row(children: [
                    Icon(
                        isArchived
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                        size: 18),
                    const SizedBox(width: 10),
                    Text(isArchived ? 'Restaurar' : 'Archivar'),
                  ]),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'refresh',
                  child: Row(children: [
                    Icon(Icons.refresh_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('Recargar'),
                  ]),
                ),
              ];
            },
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

  // ── Checklist ──────────────────────────────────────────────────────────────

  List<ProyectoTask> _localTasks = [];
  final TextEditingController _taskController = TextEditingController();

  Future<void> _addTask() async {
    final title = _taskController.text.trim();
    if (title.isEmpty || _service == null) return;
    final proyecto = _detailedProyecto ?? widget.proyecto;
    final task = await _service!.createProyectoTask(proyecto.id, title);
    if (task != null) {
      _taskController.clear();
      setState(() => _localTasks.add(task));
    }
  }

  Future<void> _toggleTask(ProyectoTask task) async {
    if (_service == null) return;
    final proyecto = _detailedProyecto ?? widget.proyecto;
    final newDone = !task.done;
    setState(() {
      final idx = _localTasks.indexWhere((t) => t.id == task.id);
      if (idx != -1) _localTasks[idx] = task.copyWith(done: newDone);
    });
    final ok = await _service!.toggleProyectoTask(proyecto.id, task.id, newDone);
    if (!ok) {
      setState(() {
        final idx = _localTasks.indexWhere((t) => t.id == task.id);
        if (idx != -1) _localTasks[idx] = task.copyWith(done: task.done);
      });
    }
  }

  Future<void> _deleteTask(ProyectoTask task) async {
    if (_service == null) return;
    final proyecto = _detailedProyecto ?? widget.proyecto;
    setState(() => _localTasks.removeWhere((t) => t.id == task.id));
    await _service!.deleteProyectoTask(proyecto.id, task.id);
  }

  Future<void> _renameTask(ProyectoTask task) async {
    if (_service == null) return;
    final ctrl = TextEditingController(text: task.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar tarea'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      final newTitle = ctrl.text.trim();
      final proyecto = _detailedProyecto ?? widget.proyecto;
      setState(() {
        final idx = _localTasks.indexWhere((t) => t.id == task.id);
        if (idx != -1) _localTasks[idx] = task.copyWith(title: newTitle);
      });
      await _service!.renameProyectoTask(proyecto.id, task.id, newTitle);
    }
  }

  Widget _buildChecklistPanel(ThemeData theme) {
    final isLight = theme.brightness == Brightness.light;

    final done = _localTasks.where((t) => t.done).length;
    final total = _localTasks.length;
    final pct = total > 0 ? done / total : 0.0;

    return _buildSectionShell(
      theme,
      title: 'Checklist de Tareas',
      trailing: total > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: pct == 1.0
                    ? Colors.green.withOpacity(0.15)
                    : theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: pct == 1.0
                      ? Colors.green.withOpacity(0.5)
                      : theme.colorScheme.primary.withOpacity(0.3),
                ),
              ),
              child: Text(
                '$done / $total',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: pct == 1.0 ? Colors.green : theme.colorScheme.primary,
                ),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress bar
          if (total > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: theme.colorScheme.outline.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation<Color>(
                  pct == 1.0 ? Colors.green : theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Task list
          if (_localTasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.checklist_rounded,
                      size: 18, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                  const SizedBox(width: 8),
                  Text(
                    'Sin tareas. Añade la primera abajo.',
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4)),
                  ),
                ],
              ),
            )
          else
            ..._localTasks.map((task) => _buildTaskRow(task, theme, isLight)),

          const SizedBox(height: 12),

          // Add task row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _taskController,
                  onSubmitted: (_) => _addTask(),
                  decoration: InputDecoration(
                    hintText: 'Nueva tarea...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: theme.colorScheme.surface.withOpacity(0.45),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _addTask,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Icon(Icons.add_rounded, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskRow(ProyectoTask task, ThemeData theme, bool isLight) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: task.done
              ? (isLight ? Colors.green.withOpacity(0.06) : Colors.green.withOpacity(0.08))
              : theme.colorScheme.surface.withOpacity(0.35),
          border: Border.all(
            color: task.done
                ? Colors.green.withOpacity(0.28)
                : theme.colorScheme.outline.withOpacity(0.18),
          ),
        ),
        child: Row(
          children: [
            // Checkbox
            SizedBox(
              width: 44,
              child: Checkbox(
                value: task.done,
                onChanged: (_) => _toggleTask(task),
                activeColor: Colors.green,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              ),
            ),
            // Title
            Expanded(
              child: GestureDetector(
                onTap: () => _toggleTask(task),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    task.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      decoration: task.done ? TextDecoration.lineThrough : null,
                      color: task.done
                          ? theme.colorScheme.onSurface.withOpacity(0.45)
                          : null,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
            // Actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.edit_outlined, size: 16,
                      color: theme.colorScheme.onSurface.withOpacity(0.45)),
                  tooltip: 'Editar',
                  onPressed: () => _renameTask(task),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                  tooltip: 'Eliminar',
                  onPressed: () => _deleteTask(task),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildObservationsPanel(ThemeData theme) {
    final observations = List.of(
      (_detailedProyecto ?? widget.proyecto).observations ?? [],
    )..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));

    return _buildSectionShell(
      theme,
      title: 'Comentarios (${observations.length})',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Chat-style list ─────────────────────────────────────────────
          if (observations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.chat_bubble_outline_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurface.withOpacity(0.3)),
                  const SizedBox(width: 8),
                  Text(
                    'Sin comentarios aún. Sé el primero.',
                    style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.4)),
                  ),
                ],
              ),
            )
          else
            ...observations.map((obs) {
              final author = obs.author?.isNotEmpty == true ? obs.author! : 'Usuario';
              final initials = author
                  .trim()
                  .split(' ')
                  .where((String w) => w.isNotEmpty)
                  .take(2)
                  .map((w) => w[0].toUpperCase())
                  .join();
              final dateStr = obs.createdAt != null
                  ? DateFormat('dd/MM HH:mm').format(obs.createdAt!)
                  : '';

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primary.withOpacity(0.15),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Bubble
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(2),
                            topRight: Radius.circular(12),
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          color: theme.colorScheme.surface.withOpacity(0.55),
                          border: Border.all(
                              color: theme.colorScheme.outline
                                  .withOpacity(0.22)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(author,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                                const Spacer(),
                                Text(
                                  dateStr,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.5),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(obs.body,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(height: 1.35)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 12),
          // ── Compose row ─────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _obsController,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'Escribe un comentario...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor:
                        theme.colorScheme.surface.withOpacity(0.45),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _addObservation,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Icon(Icons.send_rounded, size: 20),
              ),
            ],
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

  void _showPhotoPreview(String filePath) {
    final imageUrl = _resolveArchivoUrl(filePath);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.85,
              height: 500,
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  headers: {
                    if (ApiService.instance?.client.accessToken != null)
                      'Authorization':
                          'Bearer ${ApiService.instance!.client.accessToken}',
                  },
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Icon(Icons.broken_image, size: 48)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cerrar')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Estado distribution bar ──────────────────────────────────────────────────

class _EstadoBar extends StatelessWidget {
  final List<AgentOrder> orders;
  const _EstadoBar({required this.orders});

  static String _labelFor(String k) {
    switch (k) {
      case '1': return 'Validada';
      case '2': return 'Pendiente';
      case '3': return 'En Ejecución';
      case '4': return 'Parada';
      case '5': return 'Finalizada';
      case '6': return 'Facturada';
      default:  return 'Estado $k';
    }
  }

  static Color _colorFor(String k) {
    switch (k) {
      case '1': return Colors.blue;
      case '2': return Colors.orange;
      case '3': return Colors.cyan;
      case '4': return Colors.red;
      case '5': return Colors.green;
      case '6': return Colors.purple;
      default:  return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final o in orders) {
      final key = o.estado.replaceAll(RegExp(r'[^0-9]'), '');
      final k = key.isNotEmpty ? key[0] : '?';
      counts[k] = (counts[k] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: counts.entries.map((e) {
        final label = _labelFor(e.key);
        final color = _colorFor(e.key);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.4), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 5),
              Text(
                '$label · ${e.value}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Order row ────────────────────────────────────────────────────────────────

class _OrderRow extends StatelessWidget {
  final AgentOrder order;
  final ThemeData theme;
  final VoidCallback onTap;
  const _OrderRow({required this.order, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 760;
    final assignee = order.assignedToName?.isNotEmpty == true
        ? order.assignedToName!
        : null;
    final family = order.family?.isNotEmpty == true ? order.family! : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surface.withOpacity(0.4),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.22)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 8 : 10,
          ),
          child: Row(
            children: [
              // ID circle
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withOpacity(0.12),
                ),
                alignment: Alignment.center,
                child: Text(
                  '#${order.idnbr % 100}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Main info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Orden #${order.idnbr}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (family != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              family,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.customer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    if (assignee != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.person_outline_rounded, size: 12,
                              color: theme.colorScheme.onSurface.withOpacity(0.45)),
                          const SizedBox(width: 3),
                          Text(
                            assignee,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Status + chevron
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusBadge(status: order.estado, isNative: true),
                  if (order.completedAt != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('dd/MM/yy').format(order.completedAt!),
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurface.withOpacity(0.3)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status badge ─────────────────────────────────────────────────────────────

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
