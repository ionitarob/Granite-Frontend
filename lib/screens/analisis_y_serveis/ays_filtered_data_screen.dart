import 'package:flutter/material.dart';
import '../../models/analisis_models.dart';
import '../../utils/formatters.dart';
import 'package:intl/intl.dart';
import '../../services/analisis_service.dart';

class ServiceStat {
  final String name;
  final double units;
  final double pvd;
  final double totalPrice;

  ServiceStat({
    required this.name,
    required this.units,
    required this.pvd,
    required this.totalPrice,
  });
}

class AysFilteredDataDialog extends StatefulWidget {
  final List<Transaction> transactions;
  final String title;

  const AysFilteredDataDialog({
    super.key,
    required this.transactions,
    required this.title,
  });

  @override
  State<AysFilteredDataDialog> createState() => _AysFilteredDataDialogState();
}

class _AysFilteredDataDialogState extends State<AysFilteredDataDialog> {
  late List<Transaction> _sortedTransactions;
  bool _sortAscending = true;

  final _analisisService = const AnalisisService();
  List<MasterService> _masterServices = [];
  bool _loadingServices = true;
  String _sortBy = 'ID'; // 'ID', 'Coste', 'Fecha'

  @override
  void initState() {
    super.initState();
    _sortedTransactions = List.from(widget.transactions);
    _loadMasterServices();
    _applySort();
  }

  Future<void> _loadMasterServices() async {
    try {
      final services = await _analisisService.getMasterServicios();
      if (mounted) {
        setState(() {
          _masterServices = services;
          _loadingServices = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingServices = false;
        });
      }
    }
  }

  void _applySort() {
    _sortedTransactions.sort((a, b) {
      dynamic valA;
      dynamic valB;

      if (_sortBy == 'ID') {
        valA = a.id ?? 0;
        valB = b.id ?? 0;
      } else if (_sortBy == 'Coste') {
        valA = a.cost ?? 0.0;
        valB = b.cost ?? 0.0;
      } else if (_sortBy == 'Fecha') {
        valA = _parseDate(a.fechaf ?? a.fechai)?.millisecondsSinceEpoch ?? 0;
        valB = _parseDate(b.fechaf ?? b.fechai)?.millisecondsSinceEpoch ?? 0;
      } else {
        valA = 0;
        valB = 0;
      }

      if (_sortAscending) {
        return Comparable.compare(valA, valB);
      } else {
        return Comparable.compare(valB, valA);
      }
    });
  }

  void _onSortChanged(String criteria) {
    setState(() {
      if (_sortBy == criteria) {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = criteria;
        _sortAscending = false; // default desc for new criteria
      }
      _applySort();
    });
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    String clean = s.trim().replaceAll(',', '');
    clean = clean
        .replaceAll('AM', ' AM')
        .replaceAll('PM', ' PM')
        .replaceAll('  ', ' ');
    final iso = DateTime.tryParse(clean);
    if (iso != null) return iso;
    final formats = [
      'MMM d yyyy h:mm a',
      'MMMM d yyyy h:mm a',
      'd/M/yyyy',
      'dd/MM/yyyy',
      'MMM d yyyy HH:mm',
      'yyyy-MM-dd',
      'yyyy-MM-dd HH:mm:ss',
    ];
    for (final format in formats) {
      try {
        return DateFormat(format, 'en_US').parse(clean);
      } catch (_) {
        try {
          return DateFormat(format, 'es_ES').parse(clean);
        } catch (_) {}
      }
    }
    return null;
  }

  String _formatDate(String? s) {
    if (s == null || s.isEmpty || s == 'N/A' || s == '-') return '-';
    final d = _parseDate(s);
    if (d == null) return s;
    if (d.hour == 0 && d.minute == 0) {
      return DateFormat('dd/MM/yyyy').format(d);
    }
    return DateFormat('dd/MM/yyyy HH:mm').format(d);
  }

  double _parseUnits(String? s) {
    if (s == null || s.isEmpty) return 0.0;
    String clean = s.replaceAll(',', '.').trim();
    return double.tryParse(clean) ?? 0.0;
  }

  List<ServiceStat> _getServiceStats() {
    final Map<String, double> serviceUnits = {};
    for (final t in widget.transactions) {
      final sName = t.servicio ?? 'Sin servicio';
      final units = _parseUnits(t.unit);
      serviceUnits[sName] = (serviceUnits[sName] ?? 0.0) + units;
    }

    final List<ServiceStat> stats = [];
    serviceUnits.forEach((name, units) {
      final master = _masterServices.firstWhere(
        (m) => m.servicio.trim().toLowerCase() == name.trim().toLowerCase(),
        orElse: () => MasterService(id: 0, servicio: name, pvd: 0.0),
      );
      final pvd = master.pvd ?? 0.0;
      final totalPrice = units * pvd;
      stats.add(ServiceStat(
        name: name,
        units: units,
        pvd: pvd,
        totalPrice: totalPrice,
      ));
    });

    stats.sort((a, b) {
      final comp = b.units.compareTo(a.units);
      if (comp != 0) return comp;
      return b.totalPrice.compareTo(a.totalPrice);
    });

    return stats;
  }

  Widget _buildStatsCard({bool isWide = true}) {
    final theme = Theme.of(context);
    if (_loadingServices) {
      return Container(
        width: isWide ? 320 : double.infinity,
        height: isWide ? null : 200,
        decoration: BoxDecoration(
          color: theme.primaryColor.withOpacity(0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.primaryColor.withOpacity(0.1)),
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final stats = _getServiceStats();

    return Container(
      width: isWide ? 320 : double.infinity,
      height: isWide ? null : 200,
      decoration: BoxDecoration(
        color: theme.primaryColor.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.primaryColor.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_rounded, color: theme.primaryColor),
              const SizedBox(width: 8),
              Text(
                'Desglose servicio',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (stats.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No hay estadísticas para estos datos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: stats.length,
                separatorBuilder: (context, index) => const Divider(height: 12),
                itemBuilder: (context, index) {
                  final stat = stats[index];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: theme.primaryColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stat.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${stat.units.toStringAsFixed(0)} unds. x ${stat.pvd.formatted} €',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${stat.totalPrice.formatted} €',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: theme.primaryColor,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniDetailRow(String label, String value) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontalCards(ThemeData theme) {
    if (_sortedTransactions.isEmpty) {
      return const Center(child: Text('No hay datos.'));
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: _sortedTransactions.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final t = _sortedTransactions[index];
        final isPaid = t.paid ?? false;
        return Container(
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? theme.cardColor.withOpacity(0.4)
                : theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.dividerColor.withOpacity(0.15),
            ),
            boxShadow: theme.brightness == Brightness.light
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Left side: ID, SKU & Status
              SizedBox(
                width: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'ID: ${t.id}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'CSKU: ${(t.csku == null || t.csku!.trim().isEmpty) ? '-' : t.csku}',
                      style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPaid ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isPaid ? 'PAGADO' : 'PENDIENTE',
                        style: TextStyle(
                          color: isPaid ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(
                height: 50,
                child: VerticalDivider(width: 32, thickness: 1),
              ),
              // 2. Middle: Service Title & Description
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      t.servicio ?? 'Sin servicio',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.descripcion ?? '-',
                      style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Fecha: ${_formatDate(t.fechaf ?? t.fechai)}',
                      style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
                    ),
                  ],
                ),
              ),
              const SizedBox(
                height: 50,
                child: VerticalDivider(width: 32, thickness: 1),
              ),
              // 3. Right: Client details
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildMiniDetailRow('Cliente', t.cliente ?? '-'),
                    const SizedBox(height: 4),
                    _buildMiniDetailRow('Fabricante', t.fabricante ?? '-'),
                    const SizedBox(height: 4),
                    _buildMiniDetailRow('ID Xiaomi', t.idxiaomi ?? '-'),
                  ],
                ),
              ),
              const SizedBox(
                height: 50,
                child: VerticalDivider(width: 32, thickness: 1),
              ),
              // 4. Far Right: Cost & Units
              SizedBox(
                width: 160,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${t.unit ?? '0'} unidades',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${t.cost?.formatted ?? '0,00'} €',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Total: ${(_parseUnits(t.unit) * (t.cost ?? 0.0)).formatted} €',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: theme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSortHeader(ThemeData theme) {
    final criteria = ['ID', 'Coste', 'Fecha'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.primaryColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.sort_rounded, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          const Text(
            'Ordenar por:',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(width: 12),
          Row(
            children: criteria.map((c) {
              final isSelected = _sortBy == c;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c, style: const TextStyle(fontSize: 11)),
                      if (isSelected) ...[
                        const SizedBox(width: 4),
                        Icon(
                          _sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                          size: 11,
                        ),
                      ],
                    ],
                  ),
                  selected: isSelected,
                  selectedColor: theme.primaryColor.withOpacity(0.15),
                  checkmarkColor: theme.primaryColor,
                  labelStyle: TextStyle(
                    color: isSelected ? theme.primaryColor : theme.textTheme.bodyMedium?.color,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  backgroundColor: Colors.transparent,
                  side: BorderSide(
                    color: isSelected ? theme.primaryColor.withOpacity(0.3) : Colors.transparent,
                  ),
                  padding: EdgeInsets.zero,
                  onSelected: (_) => _onSortChanged(c),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 1100;

    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: size.width * 0.9,
        constraints: BoxConstraints(maxHeight: size.height * 0.85),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_sortedTransactions.length} registros encontrados',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildSortHeader(theme),
            const SizedBox(height: 16),
            Flexible(
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: _buildHorizontalCards(theme),
                          ),
                        ),
                        const SizedBox(width: 24),
                        _buildStatsCard(isWide: true),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildStatsCard(isWide: false),
                        const SizedBox(height: 16),
                        Flexible(
                          child: SingleChildScrollView(
                            child: _buildHorizontalCards(theme),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
