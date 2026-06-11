
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/orderops_service.dart';
import '../../models/agent_models.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';
import 'proyecto_detail_screen.dart';

enum _SortMode { recientes, az, masPedidos }

class ProyectosManagementScreen extends StatefulWidget {
  const ProyectosManagementScreen({super.key});

  @override
  State<ProyectosManagementScreen> createState() =>
      _ProyectosManagementScreenState();
}

class _ProyectosManagementScreenState
    extends State<ProyectosManagementScreen> {
  OrderOpsService? _svc;
  List<Proyecto> _proyectos = [];
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  String _statusFilter = 'Todos';
  _SortMode _sortMode = _SortMode.recientes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final api = Provider.of<ApiService>(context, listen: false);
      _svc = OrderOpsService(api.client);
      _load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await _svc!.getProyectos();
      setState(() { _proyectos = results; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Proyecto> get _filtered {
    var list = _proyectos.where((p) {
      if (_statusFilter != 'Todos' && p.status != _statusFilter) return false;
      final q = _searchQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      return p.nombre.toLowerCase().contains(q) ||
          (p.description ?? '').toLowerCase().contains(q);
    }).toList();

    switch (_sortMode) {
      case _SortMode.recientes:
        list.sort((a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      case _SortMode.az:
        list.sort((a, b) =>
            a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      case _SortMode.masPedidos:
        list.sort((a, b) =>
            b.effectiveOrderCount.compareTo(a.effectiveOrderCount));
    }
    return list;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _createProyecto() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String newStatus = 'Activo';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nuevo Proyecto'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes_rounded),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: newStatus,
                  decoration: const InputDecoration(
                    labelText: 'Estado inicial',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label_outline_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Activo', child: Text('Activo')),
                    DropdownMenuItem(
                        value: 'Archivado', child: Text('Archivado')),
                  ],
                  onChanged: (v) => setS(() => newStatus = v ?? 'Activo'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Crear')),
          ],
        ),
      ),
    );

    if (confirmed == true && nameCtrl.text.trim().isNotEmpty) {
      try {
        await _svc!.createProyecto(nameCtrl.text.trim(),
            description: descCtrl.text.trim());
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _renameProyecto(Proyecto p) async {
    final ctrl = TextEditingController(text: p.nombre);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              labelText: 'Nombre', border: OutlineInputBorder()),
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
        await _svc!.updateProyecto(p.id, nombre: ctrl.text.trim());
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _toggleArchive(Proyecto p) async {
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
        await _svc!.updateProyecto(p.id, status: newStatus);
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _deleteProyecto(Proyecto p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Proyecto'),
        icon: const Icon(Icons.delete_forever_rounded,
            color: Colors.redAccent, size: 32),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RichText(
              text: TextSpan(
                style: Theme.of(ctx).textTheme.bodyMedium,
                children: [
                  const TextSpan(text: '¿Eliminar '),
                  TextSpan(
                      text: '"${p.nombre}"',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: '? Esta acción no se puede deshacer.'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Los pedidos vinculados no se eliminarán.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _svc!.deleteProyecto(p.id);
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  void _openDetail(Proyecto p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProyectoDetailScreen(proyecto: p)),
    ).then((_) => _load());
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sw = MediaQuery.of(context).size.width;
    final isDesktop = sw >= 900;
    final isMobile = sw < 700;

    final filtered = _filtered;
    final totalCount = _proyectos.length;
    final activoCount =
        _proyectos.where((p) => p.status == 'Activo').length;
    final archivadoCount =
        _proyectos.where((p) => p.status == 'Archivado').length;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Proyectos'),
        automaticallyImplyLeading: !isDesktop,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Ordenar',
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (_) => [
              _sortMenuItem(Icons.access_time_rounded, 'Más recientes',
                  _SortMode.recientes),
              _sortMenuItem(
                  Icons.sort_by_alpha_rounded, 'A → Z', _SortMode.az),
              _sortMenuItem(Icons.receipt_long_rounded, 'Más pedidos',
                  _SortMode.masPedidos),
            ],
          ),
          IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Recargar'),
        ],
      ),
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 0.3),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  isDesktop ? 56 : 12, 12, 12, 12),
              child: Column(
                children: [
                  // ── Search bar ─────────────────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color:
                          theme.colorScheme.surface.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: theme.colorScheme.outline
                              .withOpacity(0.28)),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) =>
                          setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText:
                            'Buscar proyecto por nombre o descripción...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ── Filter chips ───────────────────────────────────────────
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _chip('Todos ($totalCount)', 'Todos',
                            Colors.blueGrey),
                        const SizedBox(width: 8),
                        _chip('Activo ($activoCount)', 'Activo',
                            Colors.green),
                        const SizedBox(width: 8),
                        _chip('Archivado ($archivadoCount)',
                            'Archivado', Colors.grey),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ── Content ────────────────────────────────────────────────
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator())
                        : _error != null
                            ? _ErrorView(
                                error: _error!, onRetry: _load)
                            : filtered.isEmpty
                                ? _EmptyView(
                                    hasFilters: _searchQuery
                                            .isNotEmpty ||
                                        _statusFilter != 'Todos',
                                  )
                                : RefreshIndicator(
                                    onRefresh: _load,
                                    child: isMobile
                                        ? ListView.separated(
                                            physics:
                                                const AlwaysScrollableScrollPhysics(),
                                            itemCount: filtered.length,
                                            separatorBuilder: (_, __) =>
                                                const SizedBox(
                                                    height: 10),
                                            itemBuilder: (ctx, i) =>
                                                _ProyectoCard(
                                              proyecto: filtered[i],
                                              onTap: () => _openDetail(
                                                  filtered[i]),
                                              onRename: () =>
                                                  _renameProyecto(
                                                      filtered[i]),
                                              onToggleArchive: () =>
                                                  _toggleArchive(
                                                      filtered[i]),
                                              onDelete: () =>
                                                  _deleteProyecto(
                                                      filtered[i]),
                                            ),
                                          )
                                        : GridView.builder(
                                            physics:
                                                const AlwaysScrollableScrollPhysics(),
                                            gridDelegate:
                                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                              maxCrossAxisExtent: 420,
                                              mainAxisExtent: 200,
                                              crossAxisSpacing: 14,
                                              mainAxisSpacing: 14,
                                            ),
                                            itemCount: filtered.length,
                                            itemBuilder: (ctx, i) =>
                                                _ProyectoCard(
                                              proyecto: filtered[i],
                                              onTap: () => _openDetail(
                                                  filtered[i]),
                                              onRename: () =>
                                                  _renameProyecto(
                                                      filtered[i]),
                                              onToggleArchive: () =>
                                                  _toggleArchive(
                                                      filtered[i]),
                                              onDelete: () =>
                                                  _deleteProyecto(
                                                      filtered[i]),
                                            ),
                                          ),
                                  ),
                  ),
                ],
              ),
            ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProyecto,
        label:
            isMobile ? const SizedBox.shrink() : const Text('Nuevo Proyecto'),
        icon: const Icon(Icons.add_rounded),
        isExtended: !isMobile,
      ),
    );
  }

  Widget _chip(String label, String value, Color color) {
    final selected = _statusFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(0.18)
              : Theme.of(context).colorScheme.surface.withOpacity(0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                selected ? color.withOpacity(0.7) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight:
                selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? color
                : Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.65),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<_SortMode> _sortMenuItem(
      IconData icon, String label, _SortMode mode) {
    final selected = _sortMode == mode;
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : null;
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontWeight: selected
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: color)),
        ],
      ),
    );
  }
}

// ── Card ────────────────────────────────────────────────────────────────────

class _ProyectoCard extends StatelessWidget {
  final Proyecto proyecto;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onToggleArchive;
  final VoidCallback onDelete;

  const _ProyectoCard({
    required this.proyecto,
    required this.onTap,
    required this.onRename,
    required this.onToggleArchive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final isArchived = proyecto.status == 'Archivado';
    final statusColor = isArchived ? Colors.grey : Colors.green;
    final dateStr = proyecto.createdAt != null
        ? DateFormat('dd/MM/yyyy').format(proyecto.createdAt!)
        : '—';

    return Card(
      elevation: 0,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isLight
          ? Colors.white.withOpacity(isArchived ? 0.7 : 0.94)
          : theme.colorScheme.surface.withOpacity(isArchived ? 0.2 : 0.35),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      proyecto.nombre,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isArchived
                            ? theme.colorScheme.onSurface.withOpacity(0.45)
                            : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 3-dot popup
                  _CardMenu(
                    isArchived: isArchived,
                    onRename: onRename,
                    onToggleArchive: onToggleArchive,
                    onDelete: onDelete,
                    onOpen: onTap,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // ── Description ─────────────────────────────────────────────
              Text(
                proyecto.description?.isNotEmpty == true
                    ? proyecto.description!
                    : 'Sin descripción',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface
                      .withOpacity(isArchived ? 0.35 : 0.58),
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              // ── Footer row ──────────────────────────────────────────────
              Row(
                children: [
                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: statusColor.withOpacity(0.45),
                          width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          proyecto.status,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Stat pills
                  _StatPill(Icons.receipt_long_rounded,
                      proyecto.effectiveOrderCount),
                  const SizedBox(width: 6),
                  _StatPill(Icons.chat_bubble_outline_rounded,
                      proyecto.effectiveObsCount),
                  const SizedBox(width: 6),
                  _StatPill(
                      Icons.folder_open_rounded, proyecto.effectiveFileCount),
                ],
              ),
              const SizedBox(height: 6),
              // ── Date ────────────────────────────────────────────────────
              Text(
                'Creado $dateStr',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardMenu extends StatelessWidget {
  final bool isArchived;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onToggleArchive;
  final VoidCallback onDelete;

  const _CardMenu({
    required this.isArchived,
    required this.onOpen,
    required this.onRename,
    required this.onToggleArchive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
      tooltip: 'Opciones',
      onSelected: (v) {
        switch (v) {
          case 'open':
            onOpen();
          case 'rename':
            onRename();
          case 'archive':
            onToggleArchive();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'open',
          child: Row(children: [
            Icon(Icons.open_in_full_rounded, size: 18),
            SizedBox(width: 10),
            Text('Abrir'),
          ]),
        ),
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
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline_rounded,
                size: 18, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Eliminar',
                style: TextStyle(color: Colors.redAccent)),
          ]),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final int count;
  const _StatPill(this.icon, this.count);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: 12,
            color: theme.colorScheme.onSurface.withOpacity(0.45)),
        const SizedBox(width: 3),
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withOpacity(0.55),
          ),
        ),
      ],
    );
  }
}

// ── Empty / Error states ─────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final bool hasFilters;
  const _EmptyView({required this.hasFilters});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasFilters
                ? Icons.search_off_rounded
                : Icons.folder_open_rounded,
            size: 64,
            color: theme.colorScheme.onSurface.withOpacity(0.22),
          ),
          const SizedBox(height: 16),
          Text(
            hasFilters
                ? 'Sin resultados para los filtros aplicados'
                : 'Aún no hay proyectos',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.45),
            ),
          ),
          if (!hasFilters) ...[
            const SizedBox(height: 8),
            Text(
              'Pulsa "Nuevo Proyecto" para empezar',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text('Error al cargar proyectos',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(error,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
