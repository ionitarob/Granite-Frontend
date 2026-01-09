import 'dart:async';

import 'package:flutter/material.dart';

class TablaRegistros extends StatefulWidget {
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
  final ValueChanged<String>? onSearchChanged;
  final String searchQuery;
  final bool isLoading;

  const TablaRegistros({
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
    this.onSearchChanged,
    this.searchQuery = '',
    this.isLoading = false,
  });

  @override
  State<TablaRegistros> createState() => _TablaRegistrosState();
}

class _TablaRegistrosState extends State<TablaRegistros> {
  late final TextEditingController _searchController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchQuery);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(covariant TablaRegistros oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery &&
        widget.searchQuery != _searchController.text) {
      _searchController.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    if (widget.onSearchChanged != null) {
      _debounce = Timer(const Duration(milliseconds: 400), () {
        widget.onSearchChanged!(_searchController.text.trim());
      });
    }
    setState(() {});
  }

  int _parseId(dynamic raw) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final bool remoteSearch = widget.onSearchChanged != null;
    final List<Map<String, dynamic>> filtered;
    if (remoteSearch) {
      filtered = widget.registros;
    } else {
      final source = query.isEmpty
          ? widget.registros
          : (widget.allRegistros ?? widget.registros);
      filtered = query.isEmpty
          ? source
          : source.where((registro) {
              final imei = registro['imei']?.toString().toLowerCase() ?? '';
              final id = registro['id']?.toString().toLowerCase() ?? '';
              final tipo = registro['tipo']?.toString().toLowerCase() ?? '';
              return imei.contains(query) ||
                  id.contains(query) ||
                  tipo.contains(query);
            }).toList();
    }
    final hasQuery = _searchController.text.trim().isNotEmpty;

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: 'Buscar por IMEI, ID o tipo',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        if (widget.isLoading)
          const LinearProgressIndicator(),
        if (widget.isLoading) const SizedBox(height: 12),
        if (filtered.isEmpty)
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                hasQuery
                    ? 'Sin resultados para "${_searchController.text}".'
                    : 'No hay registros disponibles.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          )
        else
          ...filtered.map((r) {
            final idRaw = r['id'] ?? '';
            final imei = r['imei'] ?? '';
            final tipo = r['tipo'] ?? '';
            final id = _parseId(idRaw);
            return Card(
              child: ListTile(
                title: Text('IMEI: $imei'),
                subtitle: Text('ID: $idRaw  •  Tipo: $tipo'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onEditar != null)
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => widget.onEditar!(id, r),
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
