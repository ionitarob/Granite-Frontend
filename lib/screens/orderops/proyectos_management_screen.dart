
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/orderops_service.dart';
import '../../models/agent_models.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';
import 'proyecto_detail_screen.dart';

class ProyectosManagementScreen extends StatefulWidget {
  const ProyectosManagementScreen({super.key});

  @override
  State<ProyectosManagementScreen> createState() => _ProyectosManagementScreenState();
}

class _ProyectosManagementScreenState extends State<ProyectosManagementScreen> {
  OrderOpsService? _orderOpsService;
  List<Proyecto> _proyectos = [];
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      _orderOpsService = OrderOpsService(apiService.client);
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await _orderOpsService!.getProyectos();
      setState(() {
        _proyectos = results;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _createProyecto() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo Proyecto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nombre del Proyecto'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: 'Descripción (Opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (confirmed == true && nameController.text.isNotEmpty) {
      setState(() => _loading = true);
      try {
        await _orderOpsService!.createProyecto(nameController.text, description: descController.text);
        await _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
          setState(() => _loading = false);
        }
      }
    }
  }

  Future<void> _deleteProyecto(Proyecto p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Proyecto'),
        content: Text('¿Estás seguro de que quieres eliminar "${p.nombre}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _loading = true);
      try {
        await _orderOpsService!.deleteProyecto(p.id);
        await _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
          setState(() => _loading = false);
        }
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    final isMobile = screenWidth < 700;

    final filtered = _proyectos.where((p) {
      final q = _searchQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      final name = p.nombre.toLowerCase();
      final desc = (p.description ?? '').toLowerCase();
      return name.contains(q) || desc.contains(q);
    }).toList(growable: false);
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Gestión de Proyectos'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 0.3),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(isDesktop ? 56 : 12, 12, 12, 12),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.colorScheme.outline.withOpacity(0.28)),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 10 : 12,
                      vertical: isMobile ? 4 : 6,
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Buscar proyecto por nombre o descripcion...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.trim().isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                            ? Center(child: Text('Error: $_error'))
                            : filtered.isEmpty
                                ? Center(
                                    child: Text(
                                      _proyectos.isEmpty
                                          ? 'No hay proyectos creados.'
                                          : 'No hay resultados para "${_searchQuery.trim()}".',
                                    ),
                                  )
                                : RefreshIndicator(
                                    onRefresh: _loadData,
                                    child: isMobile
                                        ? ListView.separated(
                                            physics: const AlwaysScrollableScrollPhysics(),
                                            itemCount: filtered.length,
                                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                                            itemBuilder: (ctx, index) {
                                              final p = filtered[index];
                                              return SizedBox(
                                                height: 164,
                                                child: _buildProyectoCard(theme, p),
                                              );
                                            },
                                          )
                                        : GridView.builder(
                                            physics: const AlwaysScrollableScrollPhysics(),
                                            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                              maxCrossAxisExtent: 420,
                                              mainAxisExtent: screenWidth < 1100 ? 188 : 180,
                                              crossAxisSpacing: 16,
                                              mainAxisSpacing: 16,
                                            ),
                                            itemCount: filtered.length,
                                            itemBuilder: (ctx, index) {
                                              final p = filtered[index];
                                              return _buildProyectoCard(theme, p);
                                            },
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
        label: isMobile ? const SizedBox.shrink() : const Text('Nuevo Proyecto'),
        icon: const Icon(Icons.add),
        isExtended: !isMobile,
      ),
    );
  }

  Widget _buildProyectoCard(ThemeData theme, Proyecto p) {
    final dateStr = p.createdAt != null ? DateFormat('dd/MM/yyyy').format(p.createdAt!) : 'N/A';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProyectoDetailScreen(proyecto: p),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 340;
            return Padding(
              padding: EdgeInsets.all(isCompact ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.nombre,
                          style: (isCompact
                                  ? theme.textTheme.titleMedium
                                  : theme.textTheme.titleLarge)
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: isCompact ? 18 : 20),
                        onPressed: () => _deleteProyecto(p),
                        color: Colors.redAccent.withOpacity(0.7),
                        visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
                      ),
                    ],
                  ),
                  SizedBox(height: isCompact ? 2 : 4),
                  Text(
                    p.description ?? 'Sin descripción',
                    style: (isCompact
                            ? theme.textTheme.bodySmall
                            : theme.textTheme.bodyMedium)
                        ?.copyWith(color: theme.hintColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 7 : 8,
                      vertical: isCompact ? 3 : 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Creado: $dateStr',
                      style: TextStyle(
                        fontSize: isCompact ? 11 : 12,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
