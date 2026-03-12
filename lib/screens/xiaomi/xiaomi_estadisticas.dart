import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';

class XiaomiEstadisticasPage extends StatefulWidget {
  const XiaomiEstadisticasPage({super.key});

  @override
  State<XiaomiEstadisticasPage> createState() => _XiaomiEstadisticasPageState();
}

class _OperatorMetrics {
  double totalUnits = 0;
  double totalMinutes = 0;
  int tasksWithTime = 0;
  Set<String> activeHours = {}; // "YYYY-MM-DD HH"
}

class _XiaomiEstadisticasPageState extends State<XiaomiEstadisticasPage> {
  OverlayEntry? _edgeOverlay;
  bool loading = true;
  List<dynamic> records = [];

  Map<String, _OperatorMetrics> operatorMetricsMonth = {};
  Map<String, _OperatorMetrics> operatorMetricsToday = {};

  Map<int, int> dailyStats = {};
  Map<int, int> hourlyStats = {};
  Map<String, int> skuStats = {};

  int totalUnits = 0;
  int totalCartons = 0;
  int unitsToday = 0;
  int maxDaily = 0;
  int maxHourly = 0;

  bool showOperatorsToday = true;

  @override
  void initState() {
    super.initState();
    _setupSidebar();
    _fetchData();
  }

  void _setupSidebar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final routeName = ModalRoute.of(context)?.settings.name;
      final overlay = Overlay.of(context, rootOverlay: true);
      _edgeOverlay = OverlayEntry(
        builder: (ctx) {
          return Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: EdgeNavHandle(
                  user: ApiService.instance?.currentUser,
                  width: 32,
                  currentRoute: routeName,
                  showIndicator: true,
                ),
              ),
            ),
          );
        },
      );
      overlay.insert(_edgeOverlay!);
    });
  }

  @override
  void dispose() {
    _edgeOverlay?.remove();
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      final api = ApiService.instance?.client;
      if (api == null) return;

      final resp = await api.get('/xiaomieco/historico?filtro_tiempo=mes');
      if (!resp.ok) throw Exception(resp.error);

      final decoded = resp.body;
      if (decoded == null || decoded is! Map) throw Exception('Invalid format');

      final rawRecords = decoded['records'] as List? ?? [];
      _processData(rawRecords);
    } catch (e) {
      debugPrint('Error fetching stats: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando estadísticas: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _processData(List<dynamic> data) {
    if (data.isEmpty) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    operatorMetricsMonth = {};
    operatorMetricsToday = {};
    dailyStats = {};
    hourlyStats = {};
    skuStats = {};
    totalUnits = 0;
    totalCartons = 0;
    unitsToday = 0;
    maxDaily = 0;
    maxHourly = 0;

    for (var r in data) {
      if (r is! Map) continue;

      final qty = int.tryParse(r['qty']?.toString() ?? '0') ?? 0;
      final cartons = int.tryParse(r['cartons']?.toString() ?? '0') ?? 0;
      final operario = r['operario']?.toString() ?? 'Unknown';
      final sku = r['sku']?.toString() ?? 'Unknown';

      final endStr = r['fecha_hora_fin']?.toString();
      final startStr = r['fecha_hora_registro']?.toString();

      if (endStr == null) continue;

      final endDate = DateTime.tryParse(endStr);
      if (endDate == null) continue;

      // Totals
      totalUnits += qty;
      totalCartons += cartons;

      // Today
      final isToday =
          endDate.year == today.year &&
          endDate.month == today.month &&
          endDate.day == today.day;
      if (isToday) unitsToday += qty;

      // Operator Metrics
      void updateMetrics(Map<String, _OperatorMetrics> map) {
        final metrics = map.putIfAbsent(operario, () => _OperatorMetrics());
        metrics.totalUnits += qty;
        metrics.activeHours.add(
          '${endDate.year}-${endDate.month}-${endDate.day} ${endDate.hour}',
        );

        if (startStr != null) {
          final startDate = DateTime.tryParse(startStr);
          if (startDate != null) {
            final diff = endDate.difference(startDate).inMinutes;
            if (diff >= 0 && diff < 600) {
              metrics.totalMinutes += diff;
              metrics.tasksWithTime++;
            }
          }
        }
      }

      updateMetrics(operatorMetricsMonth);
      if (isToday) updateMetrics(operatorMetricsToday);

      // Other Stats
      skuStats[sku] = (skuStats[sku] ?? 0) + qty;

      dailyStats[endDate.day] = (dailyStats[endDate.day] ?? 0) + qty;
      if (dailyStats[endDate.day]! > maxDaily)
        maxDaily = dailyStats[endDate.day]!;

      hourlyStats[endDate.hour] = (hourlyStats[endDate.hour] ?? 0) + qty;
      if (hourlyStats[endDate.hour]! > maxHourly)
        maxHourly = hourlyStats[endDate.hour]!;
    }

    records = data;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Select Metrics
    final currentMetrics = showOperatorsToday
        ? operatorMetricsToday
        : operatorMetricsMonth;
    final topOperators = currentMetrics.entries.toList()
      ..sort((a, b) => b.value.totalUnits.compareTo(a.value.totalUnits));
    final top5 = topOperators.take(5).toList();

    // Charts Data
    final daysInMonth = DateUtils.getDaysInMonth(
      DateTime.now().year,
      DateTime.now().month,
    );
    final spots = List.generate(daysInMonth, (index) {
      final day = index + 1;
      return FlSpot(day.toDouble(), (dailyStats[day] ?? 0).toDouble());
    });

    final hourlySpots = List.generate(24, (index) {
      final val = (hourlyStats[index] ?? 0).toDouble();
      final pct = maxHourly > 0 ? val / maxHourly : 0.0;
      Color barColor;
      if (pct < 0.3)
        barColor = Colors.blueAccent.withOpacity(0.6);
      else if (pct < 0.7)
        barColor = Colors.orangeAccent.withOpacity(0.8);
      else
        barColor = Colors.redAccent;

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: val,
            color: barColor,
            width: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    });

    final topSkus = skuStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5Skus = topSkus.take(5).toList();
    final avgUnitsPerCarton = totalCartons > 0
        ? (totalUnits / totalCartons).toStringAsFixed(1)
        : '0';

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Estadísticas Xiaomi'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primaryContainer.withValues(alpha: .9),
                theme.colorScheme.surface,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.tertiary.withValues(alpha: .05),
                  theme.colorScheme.primary.withValues(alpha: .05),
                  theme.scaffoldBackgroundColor,
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
          ),

          if (loading)
            const Center(child: CircularProgressIndicator())
          else
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _KpiCard(
                          title: 'Total Unidades',
                          value: totalUnits.toString(),
                          subtitle: 'Este mes',
                          icon: Icons.inventory_2_rounded,
                          color: Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _KpiCard(
                          title: 'Producción Hoy',
                          value: unitsToday.toString(),
                          subtitle: 'Unidades',
                          icon: Icons.today_rounded,
                          color: Colors.greenAccent,
                          trend: unitsToday > (totalUnits / 30)
                              ? '+ High'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _KpiCard(
                          title: 'Total Cartones',
                          value: totalCartons.toString(),
                          subtitle: 'Procesados',
                          icon: Icons.inbox_rounded,
                          color: Colors.purpleAccent,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _KpiCard(
                          title: 'Unid. / Cartón',
                          value: avgUnitsPerCarton,
                          subtitle: 'Promedio',
                          icon: Icons.compress_rounded,
                          color: Colors.orangeAccent,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // TOP OPERATORS
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Top Operarios',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            _ToggleButton(
                              label: 'Hoy',
                              selected: showOperatorsToday,
                              onTap: () =>
                                  setState(() => showOperatorsToday = true),
                            ),
                            _ToggleButton(
                              label: 'Mes',
                              selected: !showOperatorsToday,
                              onTap: () =>
                                  setState(() => showOperatorsToday = false),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.cardColor.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: .1),
                      ),
                    ),
                    child: top5.isEmpty
                        ? SizedBox(
                            height: 150,
                            child: Center(
                              child: Text(
                                'Sin datos para este periodo',
                                style: TextStyle(color: theme.hintColor),
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              SizedBox(
                                height: 180,
                                child: PieChart(
                                  PieChartData(
                                    sectionsSpace: 2,
                                    centerSpaceRadius: 30,
                                    sections: top5.asMap().entries.map((e) {
                                      final i = e.key;
                                      final metrics = e.value.value;
                                      final colors = [
                                        Colors.blueAccent,
                                        Colors.purpleAccent,
                                        Colors.orangeAccent,
                                        Colors.greenAccent,
                                        Colors.redAccent,
                                      ];
                                      return PieChartSectionData(
                                        color: colors[i % colors.length],
                                        value: metrics.totalUnits,
                                        title: '${metrics.totalUnits.toInt()}',
                                        radius: 50,
                                        titleStyle: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                        badgeWidget: _Badge(
                                          e.value.key.isNotEmpty
                                              ? e.value.key[0]
                                              : '?',
                                          size: 24,
                                          borderColor:
                                              colors[i % colors.length],
                                        ),
                                        badgePositionPercentageOffset: .98,
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Header for List
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        'NOMBRE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: theme.hintColor,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 60,
                                      child: Text(
                                        'UNITS',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: theme.hintColor,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 60,
                                      child: Text(
                                        'AVG TIME',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: theme.hintColor,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 50,
                                      child: Text(
                                        'UPH',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: theme.hintColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              ...top5.asMap().entries.map((e) {
                                final i = e.key;
                                final entry = e.value;
                                final m = entry.value;
                                final colors = [
                                  Colors.blueAccent,
                                  Colors.purpleAccent,
                                  Colors.orangeAccent,
                                  Colors.greenAccent,
                                  Colors.redAccent,
                                ];
                                final avgTime = m.tasksWithTime > 0
                                    ? (m.totalMinutes / m.tasksWithTime)
                                          .toStringAsFixed(1)
                                    : '-';
                                final uph = m.activeHours.isNotEmpty
                                    ? (m.totalUnits / m.activeHours.length)
                                          .toStringAsFixed(0)
                                    : '-';

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: colors[i % colors.length],
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          entry.key,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 60,
                                        child: Text(
                                          m.totalUnits.toInt().toString(),
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 60,
                                        child: Text(
                                          '$avgTime m',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: theme.hintColor,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 50,
                                        child: Text(
                                          uph,
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                  ),

                  const SizedBox(height: 32),
                  // DAILY TREND
                  Row(
                    children: [
                      Icon(
                        Icons.show_chart_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Tendencia Mensual',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Unidades procesadas por día del mes actual',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 250,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.cardColor.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: .1),
                      ),
                    ),
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 500,
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          rightTitles: const AxisTitles(),
                          topTitles: const AxisTitles(),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (v, m) => Text(
                                '${v.toInt()}',
                                style: TextStyle(
                                  color: theme.hintColor,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 3,
                              getTitlesWidget: (v, m) => Text(
                                '${v.toInt()}',
                                style: TextStyle(
                                  color: theme.hintColor,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) => Colors.blueGrey,
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((spot) {
                                return LineTooltipItem(
                                  'Día ${spot.x.toInt()}\n${spot.y.toInt()} unidades',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            gradient: LinearGradient(
                              colors: [Colors.blueAccent, Colors.purpleAccent],
                            ),
                            barWidth: 4,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blueAccent.withValues(alpha: .3),
                                  Colors.purpleAccent.withValues(alpha: .0),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  // HOURLY
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, color: Colors.orangeAccent),
                      const SizedBox(width: 8),
                      Text(
                        'Actividad por Hora',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Volumen acumulado por hora del día (24h)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.cardColor.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: .1),
                      ),
                    ),
                    child: BarChart(
                      BarChartData(
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => Colors.blueGrey,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                '${group.x}:00 - ${group.x + 1}:00\n',
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                children: [
                                  TextSpan(text: '${rod.toY.toInt()} unidades'),
                                ],
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          rightTitles: const AxisTitles(),
                          topTitles: const AxisTitles(),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (v, m) => Text(
                                '${v.toInt()}',
                                style: TextStyle(
                                  color: theme.hintColor,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 4,
                              getTitlesWidget: (v, m) => Text(
                                '${v.toInt()}h',
                                style: TextStyle(
                                  color: theme.hintColor,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: hourlySpots,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  // TOP SKUS
                  Text(
                    'Top SKUs',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: top5Skus.map((e) {
                        final maxVal = top5Skus.isNotEmpty
                            ? top5Skus.first.value
                            : 1;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    e.key,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${e.value} uds',
                                    style: TextStyle(
                                      color: theme.hintColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: e.value / maxVal,
                                  minHeight: 8,
                                  backgroundColor: theme.dividerColor
                                      .withValues(alpha: .1),
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.blueAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? theme.colorScheme.onSurface : theme.hintColor,
          ),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? trend;
  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.trend,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .05)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    trend!,
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.dividerColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.size, required this.borderColor});
  final String text;
  final double size;
  final Color borderColor;
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: PieChart.defaultDuration,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(.5),
            offset: const Offset(3, 3),
            blurRadius: 3,
          ),
        ],
      ),
      padding: EdgeInsets.all(size * .15),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: size * .5,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
