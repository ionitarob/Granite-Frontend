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

  Future<void> _confirmarEliminar(BuildContext context, int id, String imei) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFC62828)),
            SizedBox(width: 10),
            Text('Eliminar registro'),
          ],
        ),
        content: Text(
          '¿Seguro que quieres eliminar el smartphone con IMEI:\n\n$imei\n\nEsta acción no se puede deshacer.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true && widget.onEliminar != null) {
      widget.onEliminar!(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final bool remoteSearch = widget.onSearchChanged != null;
    final List<Map<String, dynamic>> filtered;
    if (remoteSearch) {
      filtered = List<Map<String, dynamic>>.from(widget.registros);
    } else {
      final source = query.isEmpty
          ? widget.registros
          : (widget.allRegistros ?? widget.registros);
      filtered = query.isEmpty
          ? List<Map<String, dynamic>>.from(source)
          : source.where((r) {
              final imei = r['imei']?.toString().toLowerCase() ?? '';
              final id = r['id']?.toString().toLowerCase() ?? '';
              final tipo = r['tipo']?.toString().toLowerCase() ?? '';
              return imei.contains(query) || id.contains(query) || tipo.contains(query);
            }).toList();
    }

    // Sort strictly from most recent (newest) to oldest by ID
    filtered.sort((a, b) {
      final aId = int.tryParse(a['id']?.toString() ?? '') ?? 0;
      final bId = int.tryParse(b['id']?.toString() ?? '') ?? 0;
      return bId.compareTo(aId);
    });

    final theme = Theme.of(context);
    final totalPages = (widget.totalItems != null && widget.registrosPorPagina != null)
        ? ((widget.totalItems! / widget.registrosPorPagina!).ceil())
        : null;
    final currentPage = widget.paginaActual ?? 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Search bar ──────────────────────────────────────────────
        _StyledSearchBar(
          controller: _searchController,
          hintText: 'Buscar por IMEI, ID o tipo…',
        ),
        const SizedBox(height: 12),

        // ── Loading indicator ────────────────────────────────────────
        if (widget.isLoading)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(minHeight: 3),
          ),
        if (widget.isLoading) const SizedBox(height: 10),

        // ── Row count pill ───────────────────────────────────────────
        if (widget.totalItems != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${widget.totalItems} registro${widget.totalItems == 1 ? '' : 's'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── List ─────────────────────────────────────────────────────
        Expanded(
          child: filtered.isEmpty
              ? _EmptyState(hasQuery: _searchController.text.trim().isNotEmpty)
              : ListView.builder(
                  itemCount: filtered.length,
                itemBuilder: (context, index) {
                    final r = filtered[index];
                    final idRaw = r['id'] ?? '';
                    final id = _parseId(idRaw);
                    final imei = r['imei']?.toString() ?? '—';
                    final tipo = r['tipo']?.toString().toUpperCase() ?? '';
                    final bateria = r['porcentaje_bateria']?.toString();
                    final cometa = r['version_cometa']?.toString();
                    final fecha = _formatFecha(r['created_at'] ?? r['fecha']);
                    final idim = r['idim']?.toString();
                    final oysta = r['oysta']?.toString();

                    return _SmartphoneCard(
                      imei: imei,
                      tipo: tipo,
                      bateria: bateria,
                      cometa: cometa,
                      fecha: fecha,
                      idim: idim,
                      oysta: oysta,
                      onEditar: widget.onEditar != null
                          ? () => widget.onEditar!(id, r)
                          : null,
                      onEliminar: widget.onEliminar != null
                          ? () => _confirmarEliminar(context, id, imei)
                          : null,
                    );
                  },
                ),
        ),

        // ── Pagination ────────────────────────────────────────────────
        if (filtered.isNotEmpty && totalPages != null && totalPages > 1)
          _PaginationBar(
            currentPage: currentPage,
            totalPages: totalPages,
            onPrev: widget.onPrevPage,
            onNext: widget.onNextPage,
          ),
      ],
    );
  }

  String _formatFecha(dynamic raw) {
    if (raw == null) return '—';
    final s = raw.toString();
    if (s.length >= 16) return s.substring(0, 16).replaceAll('T', '  ');
    return s;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual smartphone card
// ─────────────────────────────────────────────────────────────────────────────

class _SmartphoneCard extends StatelessWidget {
  final String imei;
  final String tipo;
  final String? bateria;
  final String? cometa;
  final String fecha;
  final String? idim;
  final String? oysta;
  final VoidCallback? onEditar;
  final VoidCallback? onEliminar;

  const _SmartphoneCard({
    required this.imei,
    required this.tipo,
    required this.fecha,
    this.bateria,
    this.cometa,
    this.idim,
    this.oysta,
    this.onEditar,
    this.onEliminar,
  });

  Color _tipoColor() {
    if (tipo == 'AGRESOR') return const Color(0xFF2E7D32);
    if (tipo == 'VICTIMA') return const Color(0xFF6B2B8F);
    return const Color(0xFF1565C0);
  }

  String _tipoLabel() {
    if (tipo == 'AGRESOR') return 'Agresor';
    if (tipo == 'VICTIMA') return 'Víctima';
    return tipo;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _tipoColor();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: c.withValues(alpha: 0.2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left accent bar
            Container(
              width: 4,
              height: 56,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // IMEI
                      Expanded(
                        child: Text(
                          imei,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace',
                            letterSpacing: 1.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Type badge
                      if (tipo.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: c.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            _tipoLabel(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: c,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Pills row
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (bateria != null && bateria!.isNotEmpty)
                        _MiniPill(
                          icon: Icons.battery_charging_full_rounded,
                          label: '$bateria%',
                          color: _batteryColor(bateria!),
                        ),
                      if (cometa != null && cometa!.isNotEmpty)
                        _MiniPill(
                          icon: Icons.system_update_alt_rounded,
                          label: cometa!,
                          color: theme.colorScheme.secondary,
                        ),
                      if (idim != null && idim!.isNotEmpty)
                        _MiniPill(
                          icon: Icons.storage_rounded,
                          label: 'IDIM: $idim',
                          color: const Color(0xFF1565C0),
                        ),
                      if (oysta != null && oysta!.isNotEmpty)
                        _MiniPill(
                          icon: Icons.storage_rounded,
                          label: 'OYSTA: $oysta',
                          color: const Color(0xFFE65100),
                        ),
                      _MiniPill(
                        icon: Icons.schedule_rounded,
                        label: fecha,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Actions
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onEditar != null)
                  _ActionBtn(
                    icon: Icons.edit_rounded,
                    tooltip: 'Editar',
                    color: theme.colorScheme.primary,
                    onPressed: onEditar!,
                  ),
                if (onEliminar != null)
                  _ActionBtn(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Eliminar',
                    color: const Color(0xFFC62828),
                    onPressed: onEliminar!,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _batteryColor(String b) {
    final v = int.tryParse(b) ?? 50;
    if (v >= 60) return const Color(0xFF2E7D32);
    if (v >= 30) return const Color(0xFFE65100);
    return const Color(0xFFC62828);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared micro-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _MiniPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MiniPill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  const _ActionBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

class _StyledSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;

  const _StyledSearchBar({required this.controller, required this.hintText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: theme.colorScheme.primary.withValues(alpha: 0.7),
        ),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: controller.clear,
              )
            : null,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.15),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasQuery;

  const _EmptyState({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasQuery ? Icons.search_off_rounded : Icons.inbox_rounded,
            size: 48,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 12),
          Text(
            hasQuery ? 'Sin resultados para la búsqueda.' : 'No hay registros todavía.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _NavBtn(
            icon: Icons.chevron_left_rounded,
            label: 'Anterior',
            enabled: onPrev != null,
            onPressed: onPrev,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$currentPage / $totalPages',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          _NavBtn(
            icon: Icons.chevron_right_rounded,
            label: 'Siguiente',
            enabled: onNext != null,
            onPressed: onNext,
            iconFirst: false,
          ),
        ],
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onPressed;
  final bool iconFirst;

  const _NavBtn({
    required this.icon,
    required this.label,
    required this.enabled,
    this.onPressed,
    this.iconFirst = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.25);

    final children = [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
    ];

    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: iconFirst ? children : children.reversed.toList(),
        ),
      ),
    );
  }
}
