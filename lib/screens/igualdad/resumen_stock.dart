import 'dart:ui';
import 'package:flutter/material.dart';

class ResumenStock extends StatefulWidget {
  final Map<String, int>? stockReal;
  final Map<String, int>? idimActivoVals;
  final Map<String, int>? oystaActivoVals;
  final String? idimCodigo;
  final String? oystaCodigo;

  const ResumenStock({
    super.key,
    required this.stockReal,
    required this.idimActivoVals,
    required this.oystaActivoVals,
    required this.idimCodigo,
    required this.oystaCodigo,
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

  Widget _neonCar(Color color) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.8),
          blurRadius: 8,
          spreadRadius: 4,
        ),
      ],
    ),
  );

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
                  '${datos[key]}',
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

  @override
  Widget build(BuildContext context) {
    if (widget.stockReal == null ||
        widget.idimActivoVals == null ||
        widget.oystaActivoVals == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // ancho real disponible
        final availW = constraints.maxWidth;
        // definimos ancho mínimo para la tabla (6 cols x 80px)
        const minTableW = 6 * 80.0;
        // girar si no cabe
        final rotate = availW < minTableW;

        // construimos la tabla con scroll horizontal y ancho mínimo
        Widget table = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: rotate ? minTableW : availW * 0.95,
            ),
            child: Table(
              border: TableBorder.all(color: Colors.white30),
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(),
                2: FlexColumnWidth(),
                3: FlexColumnWidth(),
                4: FlexColumnWidth(),
                5: FlexColumnWidth(),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.secondary,
                      ],
                    ),
                  ),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        '',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'SMA',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'SMV',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Pulseras',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Botones',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'PowerBanks',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                _buildRow("Stock Real", widget.stockReal!, Colors.green),
                _buildRow("IDIM activo", widget.idimActivoVals!, Colors.blue),
                _buildRow("OYSTA activo", widget.oystaActivoVals!, Colors.red),
              ],
            ),
          ),
        );

        // si rota, envuelve la tabla entera en RotatedBox
        if (rotate) {
          table = RotatedBox(quarterTurns: 1, child: table);
        }

        // ahora montamos el resto del widget
        return Stack(
          children: [
            // neón por el perímetro
            AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => Align(
                alignment: _borderAlignment(_controller.value),
                child: _neonCar(Theme.of(context).colorScheme.secondary),
              ),
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => Align(
                alignment: _borderAlignment(_controller.value + 0.5),
                child: _neonCar(Theme.of(context).colorScheme.tertiary),
              ),
            ),

            // scroll vertical si hace falta
            SingleChildScrollView(
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      width: rotate ? minTableW + 32 : availW * 0.95,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Resumen de Stock",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 12),
                          table,
                          const SizedBox(height: 12),
                          Text(
                            'IDIM activo: ${widget.idimCodigo}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                          Text(
                            'OYSTA activo: ${widget.oystaCodigo}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
