import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

class ResumenStock extends StatefulWidget {
  final Map<String, int>? stockReal;
  final Map<String, int>? idimActivoVals;
  final Map<String, int>? oystaActivoVals;
  final String? idimCodigo;
  final String? oystaCodigo;
  /// Irrecuperables del IDIM activo. Keys: 'sm', 'pulseras', 'botones', 'powerbanks'.
  final Map<String, int>? irrecuperablesVals;

  const ResumenStock({
    super.key,
    required this.stockReal,
    required this.idimActivoVals,
    required this.oystaActivoVals,
    required this.idimCodigo,
    required this.oystaCodigo,
    this.irrecuperablesVals,
  });

  @override
  State<ResumenStock> createState() => _ResumenStockState();
}

class _ResumenStockState extends State<ResumenStock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  Alignment _borderAlignment(double t) {
    final seg = (t % 1) * 4;
    final part = seg.floor();
    final local = seg - part;
    switch (part) {
      case 0:
        return Alignment(_lerp(-1, 1, local), -1);
      case 1:
        return Alignment(1, _lerp(-1, 1, local));
      case 2:
        return Alignment(_lerp(1, -1, local), 1);
      default:
        return Alignment(-1, _lerp(1, -1, local));
    }
  }

  /// Standard row for Stock Real / IDIM activo / OYSTA activo.
  /// Uses keys: sma, smv, pulseras, botones, powerbanks.
  TableRow _buildRow(String label, Map<String, int> datos, Color color) {
    return TableRow(
      decoration: BoxDecoration(color: color.withOpacity(0.1)),
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        for (var key in ['sma', 'smv', 'pulseras', 'botones', 'powerbanks'])
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.circle, size: 12, color: color),
                const SizedBox(width: 6),
                Text(
                  '${datos[key] ?? 0}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Irrecuperables row: SM is grouped (no distinction agresor/victima).
  /// Column order: label | SM (sma col) | — (smv col) | Pulseras | Botones | P.Banks
  TableRow _buildIrrecuperablesRow(Map<String, int> datos) {
    const color = Color(0xFFE53935); // red
    final onSurface = Theme.of(context).colorScheme.onSurface;

    Widget numCell(int value) => Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.circle, size: 12, color: color),
              const SizedBox(width: 6),
              Text('$value', style: TextStyle(color: onSurface, fontWeight: FontWeight.w600)),
            ],
          ),
        );

    Widget dashCell() => Padding(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: Text('—', style: TextStyle(color: onSurface.withOpacity(0.35), fontSize: 13)),
          ),
        );

    return TableRow(
      decoration: BoxDecoration(color: color.withOpacity(0.08)),
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 15, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  'Irrecuperables',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
        // SMA column → SM total
        numCell(datos['sm'] ?? 0),
        // SMV column → dash (no distinction)
        dashCell(),
        numCell(datos['pulseras'] ?? 0),
        numCell(datos['botones'] ?? 0),
        numCell(datos['powerbanks'] ?? 0),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;

        final hasIrrecuperables = widget.irrecuperablesVals != null;

        // build the table as a horizontal scrollable list
        Widget table = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: math.max(600.0, availW * 0.95),
            ),
            child: Table(
              border: TableBorder.all(color: Colors.white10),
              columnWidths: const {
                0: FlexColumnWidth(1.8),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1),
                4: FlexColumnWidth(1),
                5: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  ),
                  children: [
                    for (var header in ['', 'SMA', 'SMV', 'Pulseras', 'Botones', 'P.Banks'])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        child: Text(
                          header,
                          textAlign: header.isEmpty ? TextAlign.start : TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
                _buildRow("Stock Real", widget.stockReal!, Colors.green),
                _buildRow("IDIM activo", widget.idimActivoVals!, Colors.blue),
                _buildRow("OYSTA activo", widget.oystaActivoVals!, Colors.red),
                if (hasIrrecuperables)
                  _buildIrrecuperablesRow(widget.irrecuperablesVals!),
              ],
            ),
          ),
        );

        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: availW * 0.98,
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          "Resumen de Stock",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        if (widget.idimCodigo != null)
                          _buildCodeBadge('IDIM: ${widget.idimCodigo}', Colors.blue),
                        if (widget.oystaCodigo != null)
                          const SizedBox(width: 8),
                        if (widget.oystaCodigo != null)
                          _buildCodeBadge('OYSTA: ${widget.oystaCodigo}', Colors.red),
                      ],
                    ),
                    if (hasIrrecuperables) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 13, color: Color(0xFFE53935)),
                          const SizedBox(width: 4),
                          Text(
                            'Irrecuperables: columna SM agrupa agresor+víctima',
                            style: TextStyle(
                              fontSize: 11,
                              color: const Color(0xFFE53935).withOpacity(0.75),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    table,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCodeBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
