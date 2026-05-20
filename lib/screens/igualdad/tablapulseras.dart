import 'dart:async';
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
  final ValueChanged<String>? onSearchChanged;
  final String searchQuery;
  final bool isLoading;

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
    this.onSearchChanged,
    this.searchQuery = '',
    this.isLoading = false,
  });

  @override
  State<TablaPulseras> createState() => _TablaPulserasState();
}

class _TablaPulserasState extends State<TablaPulseras> {
  late final TextEditingController _searchController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchQuery);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(covariant TablaPulseras oldWidget) {
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
              final fecha =
                  registro['created_at']?.toString().toLowerCase() ??
                  registro['fecha']?.toString().toLowerCase() ??
                  '';
              return imei.contains(query) ||
                  id.contains(query) ||
                  fecha.contains(query);
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
            labelText: 'Buscar por IMEI, ID o fecha',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        if (widget.isLoading)
          const LinearProgressIndicator(),
        if (widget.isLoading) const SizedBox(height: 12),
        Expanded(
          child: filtered.isEmpty
              ? Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      hasQuery
                          ? 'Sin resultados para "${_searchController.text}".'
                          : 'No hay pulseras registradas todavía.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final p = filtered[index];
                    final idRaw = p['id'] ?? p['imei'] ?? '';
                    final imei = p['imei'] ?? '';
                    final created = p['created_at'] ?? p['fecha'] ?? '';
                    final id = _parseId(idRaw);
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'IMEI: $imei',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ID: $idRaw  •  $created',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.onEditar != null)
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => widget.onEditar!(id, p),
                                ),
                              const SizedBox(width: 12),
                              if (widget.onEliminar != null)
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 18),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => widget.onEliminar!(id),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (filtered.isNotEmpty && (widget.onPrevPage != null || widget.onNextPage != null))
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: widget.onPrevPage,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Anterior'),
                ),
                Text(
                  'Página ${widget.paginaActual ?? 1}' + (widget.totalItems != null && widget.registrosPorPagina != null ? ' de ${(widget.totalItems! / widget.registrosPorPagina!).ceil()}' : ''),
                  style: theme.textTheme.bodyMedium,
                ),
                ElevatedButton.icon(
                  onPressed: widget.onNextPage,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Siguiente'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
