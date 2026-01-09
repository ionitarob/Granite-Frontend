import 'package:flutter/material.dart';

class TablaPulseras extends StatefulWidget {
  final List<Map<String, dynamic>> registros;
  final List<Map<String, dynamic>>? allRegistros;
  final int? paginaActual;
  final int? totalItems;
  final int? registrosPorPagina;
  final VoidCallback? onPrevPage;
  final VoidCallback? onNextPage;
  final void Function(int id)? onEliminar;
  final void Function(int id, Map<String, dynamic> nuevo)? onEditar;
  final void Function(int page)? onPageChanged;

  const TablaPulseras({
    super.key,
    required this.registros,
    this.allRegistros,
    this.paginaActual,
    this.totalItems,
    this.registrosPorPagina,
    this.onPrevPage,
    this.onNextPage,
    this.onEliminar,
    this.onEditar,
    this.onPageChanged,
  });

  @override
  State<TablaPulseras> createState() => _TablaPulserasState();
}

class _TablaPulserasState extends State<TablaPulseras> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
  }

  int _parseId(dynamic raw) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final source = query.isEmpty
        ? widget.registros
        : (widget.allRegistros ?? widget.registros);
    final filtered = query.isEmpty
        ? source
        : source.where((registro) {
            final imei = registro['imei']?.toString().toLowerCase() ?? '';
            final id = registro['id']?.toString().toLowerCase() ?? '';
            final fecha =
                registro['created_at']?.toString().toLowerCase() ??
                registro['fecha']?.toString().toLowerCase() ??
                '';
            return imei.contains(query) ||
                id.contains(query) ||
                fecha.contains(query);
          }).toList();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: 'Buscar por IMEI, ID o fecha',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                query.isEmpty
                    ? 'No hay pulseras registradas todavía.'
                    : 'Sin resultados para "$query".',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          )
        else
          ...filtered.map((p) {
            final idRaw = p['id'] ?? p['imei'] ?? '';
            final imei = p['imei'] ?? '';
            final created = p['created_at'] ?? p['fecha'] ?? '';
            final id = _parseId(idRaw);
            return Card(
              child: ListTile(
                title: Text('IMEI: $imei'),
                subtitle: Text('ID: $idRaw  •  $created'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onEditar != null)
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => widget.onEditar!(id, p),
                      ),
                    if (widget.onEliminar != null)
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => widget.onEliminar!(id),
                      ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
