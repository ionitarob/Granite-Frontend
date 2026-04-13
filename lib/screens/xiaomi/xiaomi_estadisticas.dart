import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../services/xiaomi_provider.dart';
import '../../widgets/main_sidebar.dart';
import '../../utils/formatters.dart';

class XiaomiEstadisticasPage extends StatefulWidget {
  const XiaomiEstadisticasPage({super.key});

  @override
  State<XiaomiEstadisticasPage> createState() => _XiaomiEstadisticasPageState();
}

class _XiaomiEstadisticasPageState extends State<XiaomiEstadisticasPage> {
  OverlayEntry? _edgeOverlay;
  double _effectiveHours = 7.5;
  double _customUph = 100.0;
  String _selectedPeriod = 'Hoy'; // Trends
  String _selectedTeamPeriod = 'Hoy'; // Teams

  @override
  void initState() {
    _setupSidebar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<XiaomiProvider>().fetchSummary();
      _fetchTrend();
    });
  }

  void _fetchTrend() {
    final now = DateTime.now();
    DateTime start = now;
    DateTime end = now;

    switch (_selectedPeriod) {
      case 'Hoy':
        start = DateTime(now.year, now.month, now.day);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'Semana':
        start = now.subtract(const Duration(days: 7));
        break;
      case 'Mes':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'Año':
        start = DateTime(now.year, 1, 1);
        break;
      case 'Personalizado':
        return;
    }
    context.read<XiaomiProvider>().fetchUphTrend(start, end);
  }

  void _fetchTeamHistory() {
    if (_selectedTeamPeriod == 'Hoy') return;

    final now = DateTime.now();
    DateTime start = now;
    DateTime end = now;

    switch (_selectedTeamPeriod) {
      case 'Semana':
        start = now.subtract(const Duration(days: 7));
        break;
      case 'Mes':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'Año':
        start = DateTime(now.year, 1, 1);
        break;
      case 'Personalizado':
        return; // Date picker handled separately
    }
    context.read<XiaomiProvider>().fetchTeamPerformance(start, end);
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
                  user: context.read<XiaomiProvider>().apiService.currentUser,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final xiaomi = context.watch<XiaomiProvider>();
    final summary = xiaomi.summary;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Estadísticas Xiaomi (Equipos)'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primaryContainer.withOpacity(0.9),
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
                  theme.colorScheme.tertiary.withOpacity(0.05),
                  theme.colorScheme.primary.withOpacity(0.05),
                  theme.scaffoldBackgroundColor,
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
          ),
          if (xiaomi.isLoading && summary == null)
            const Center(child: CircularProgressIndicator())
          else
            RefreshIndicator(
              onRefresh: () => xiaomi.fetchSummary(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 900;
                    
                    final blockTotal = _buildTotalBlock(summary, theme);
                    final blockPrevision = _buildPrevisionBlock(summary, theme, isDesktop);
                    final blockRendimiento = _buildRendimientoBlock(summary, theme);
                    final blockUphChart = _buildUPHChartBlock(context, theme);

                    if (isDesktop) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                blockTotal,
                                const SizedBox(height: 16),
                                blockRendimiento,
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 3,
                            child: Column(
                              children: [
                                blockPrevision,
                                const SizedBox(height: 16),
                                blockUphChart,
                              ],
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          blockTotal,
                          const SizedBox(height: 16),
                          blockPrevision,
                          const SizedBox(height: 16),
                          blockRendimiento,
                          const SizedBox(height: 16),
                          blockUphChart,
                        ],
                      );
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTotalBlock(XiaomiStatsSummary? summary, ThemeData theme) {
    final totals = summary?.totals ?? {};
    return _StatCardBase(
      title: 'TOTAL UNIDADES',
      icon: Icons.inventory_2_rounded,
      color: Colors.blueAccent,
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.1,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        children: [
          _SubStat(label: 'Hoy', value: totals['hoy']?.formattedInt ?? '0', color: Colors.greenAccent),
          _SubStat(label: 'Este Mes', value: totals['mes']?.formattedInt ?? '0', color: Colors.blueAccent),
          _SubStat(label: 'Mes Pasado', value: totals['mes_pasado']?.formattedInt ?? '0', color: Colors.purpleAccent),
          _SubStat(label: 'Este Año', value: totals['ano']?.formattedInt ?? '0', color: Colors.orangeAccent),
        ],
      ),
    );
  }

  Widget _buildPrevisionBlock(XiaomiStatsSummary? summary, ThemeData theme, bool isDesktop) {
    final pending = summary?.pending ?? 0;
    final uphToday = summary?.uphToday ?? 0.0;
    final uphWeek = summary?.uphWeek ?? 0.0;
    
    // Calculations
    final hoursNeededToday = uphToday > 0 ? pending / uphToday : 0.0;
    final personalToday = _effectiveHours > 0 ? (hoursNeededToday / _effectiveHours).ceil() : 0;
    
    final hoursNeededWeek = uphWeek > 0 ? pending / uphWeek : 0.0;
    final personalWeek = _effectiveHours > 0 ? (hoursNeededWeek / _effectiveHours).ceil() : 0;

    final hoursNeededCustom = _customUph > 0 ? pending / _customUph : 0.0;
    final personalCustom = _effectiveHours > 0 ? (hoursNeededCustom / _effectiveHours).ceil() : 0;

    return _StatCardBase(
      title: 'PREVISIÓN & SIMULACIÓN',
      icon: Icons.query_stats,
      color: Colors.orangeAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pending_actions_rounded, size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              const Text('Unidades Pendientes Total: ', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(pending.formattedInt, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.orange)),
            ],
          ),
          Text('(UPH = Unidades por hora por persona)', style: TextStyle(fontSize: 10, color: theme.hintColor, fontStyle: FontStyle.italic)),
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildInputRow(
                    label: 'HORAS EFECTIVAS',
                    value: _effectiveHours.toStringAsFixed(1),
                    suffix: 'h / persona',
                    icon: Icons.timer_outlined,
                    color: Colors.blue,
                    onChanged: (v) {
                      final val = double.tryParse(v);
                      if (val != null && val > 0) setState(() => _effectiveHours = val);
                    },
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _buildInputRow(
                    label: 'SIMULAR UPH',
                    value: _customUph.toInt().toString(),
                    suffix: 'UPH / persona',
                    icon: Icons.speed_outlined,
                    color: Colors.orange,
                    onChanged: (v) {
                      final val = double.tryParse(v);
                      if (val != null && val > 0) setState(() => _customUph = val);
                    },
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          const SizedBox(height: 20),
          
          Row(
            children: [
              Expanded(
                child: _buildPredictionResults(
                  context,
                  title: 'SEGÚN HOY',
                  uph: uphToday,
                  hoursNeeded: hoursNeededToday,
                  personal: personalToday,
                  color: Colors.green,
                  icon: Icons.today_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPredictionResults(
                  context,
                  title: 'TENDENCIA SEMANA',
                  uph: uphWeek,
                  hoursNeeded: hoursNeededWeek,
                  personal: personalWeek,
                  color: Colors.blue,
                  icon: Icons.date_range_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPredictionResults(
                  context,
                  title: 'SIMULACIÓN MANUAL',
                  uph: _customUph,
                  hoursNeeded: hoursNeededCustom,
                  personal: personalCustom,
                  color: Colors.orange,
                  icon: Icons.edit_note_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow({
    required String label,
    required String value,
    required String suffix,
    required IconData icon,
    required Color color,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: TextEditingController(text: value)..selection = TextSelection.fromPosition(TextPosition(offset: value.length)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.start,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          decoration: InputDecoration(
            isDense: true,
            suffixText: suffix,
            suffixStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.grey),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildPredictionResults(
    BuildContext context, {
    required String title,
    required double uph,
    required double hoursNeeded,
    required int personal,
    required Color color,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.3)),
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title, 
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: color, letterSpacing: 1.0),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          _InfoRow(label: 'UPH actual', value: uph.toStringAsFixed(1), icon: Icons.speed_rounded),
          _InfoRow(label: 'Horas necesarias', value: '${hoursNeeded.toStringAsFixed(1)} h', icon: Icons.timer_rounded),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                const Text('PERSONAL NECESARIO', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('$personal', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRendimientoBlock(XiaomiStatsSummary? summary, ThemeData theme) {
    final xiaomi = context.watch<XiaomiProvider>();
    final isToday = _selectedTeamPeriod == 'Hoy';
    final isLoading = xiaomi.isLoadingTeamHistory;
    final teams = isToday ? (summary?.teamPerformance ?? []) : xiaomi.teamHistory;

    return _StatCardBase(
      title: 'RENDIMIENTO EQUIPOS',
      icon: Icons.groups_rounded,
      color: Colors.purpleAccent,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: ['Hoy', 'Semana', 'Mes', 'Año', 'Personalizado'].map((p) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(p),
                    selected: _selectedTeamPeriod == p,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedTeamPeriod = p);
                        if (p == 'Personalizado') {
                          _selectTeamDateRange();
                        } else {
                          _fetchTeamHistory();
                        }
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else if (teams.isEmpty)
             Center(child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(isToday ? 'Sin datos de producción hoy' : 'Sin datos en este período', style: TextStyle(color: theme.hintColor)),
              ))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: teams.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (ctx, i) {
                final t = teams[i];
                final name = t['nombre'] ?? 'Desconocido';
                final qty = (t['qty'] as num?)?.toInt() ?? 0;
                final members = (t['members'] as num?)?.toInt() ?? 1;
                // Use the UPH returned by backend for range, or calculate for today
                final double uphVal = isToday 
                    ? (qty / (7.5 * members)) 
                    : ((t['uph_p'] as num?)?.toDouble() ?? 0.0);

                return ListTile(
                  leading: Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: _getColorFromName(name)),
                  ),
                  title: Text('Equipo $name'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isToday ? '$members personas' : '$members colaboradores'),
                      if (t['member_names'] != null)
                        Text(
                          t['member_names'], 
                          style: TextStyle(fontSize: 10, color: theme.hintColor, fontStyle: FontStyle.italic),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${uphVal.toStringAsFixed(1)} UPH/p', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('$qty total', style: TextStyle(fontSize: 10, color: theme.hintColor)),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _selectTeamDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 7)),
        end: DateTime.now(),
      ),
    );
    if (picked != null) {
      if (!mounted) return;
      context.read<XiaomiProvider>().fetchTeamPerformance(picked.start, picked.end);
    }
  }

  Widget _buildUPHChartBlock(BuildContext context, ThemeData theme) {
    final xiaomi = context.watch<XiaomiProvider>();
    final trend = xiaomi.uphTrend;
    final isHourly = xiaomi.isHourlyTrend;
    final isLoading = xiaomi.isLoadingTrend;

    return _StatCardBase(
      title: 'TENDENCIA DE RENDIMIENTO',
      icon: Icons.trending_up_rounded,
      color: Colors.blueAccent,
      child: Column(
        children: [
          Text('(UPH = Unidades por hora por persona)', style: TextStyle(fontSize: 10, color: theme.hintColor, fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: ['Hoy', 'Semana', 'Mes', 'Año', 'Personalizado'].map((p) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(p),
                      selected: _selectedPeriod == p,
                      onSelected: (val) async {
                        if (val) {
                          if (p == 'Personalizado') {
                            final range = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2023),
                              lastDate: DateTime.now(),
                            );
                            if (range != null) {
                              setState(() => _selectedPeriod = p);
                              xiaomi.fetchUphTrend(range.start, range.end);
                            }
                          } else {
                            setState(() => _selectedPeriod = p);
                            _fetchTrend();
                          }
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 280,
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : trend.isEmpty
                    ? const Center(child: Text('No hay datos para este periodo'))
                    : _buildLineChart(trend, isHourly, theme),
          ),
          if (trend.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            _buildChartSummary(trend, theme),
          ],
        ],
      ),
    );
  }

  Widget _buildChartSummary(List<Map<String, dynamic>> trend, ThemeData theme) {
    final uphValues = trend.map((e) => (e['uph'] as num).toDouble()).toList();
    final maxUph = uphValues.isNotEmpty ? uphValues.reduce((a, b) => a > b ? a : b) : 0.0;
    final avgUph = uphValues.isNotEmpty ? uphValues.reduce((a, b) => a + b) / uphValues.length : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('MEJOR UPH', maxUph.toStringAsFixed(1), Colors.blue),
          _buildSummaryItem('PROMEDIO', avgUph.toStringAsFixed(1), Colors.blueGrey),
          _buildSummaryItem('PUNTOS', trend.length.toString(), Colors.cyan),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7), fontWeight: FontWeight.bold, letterSpacing: 1)),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildLineChart(List<Map<String, dynamic>> data, bool isHourly, ThemeData theme) {
    final spots = data.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), (e.value['uph'] as num).toDouble());
    }).toList();

    return LineChart(
      LineChartData(
        backgroundColor: Colors.transparent,
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.surface,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((s) {
                final idx = s.x.toInt();
                final d = data[idx];
                return LineTooltipItem(
                  'UPH: ${s.y.toStringAsFixed(1)}\n',
                  TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 16),
                  children: [
                    TextSpan(
                      text: '${d['qty']} uds | ${d['workers']} op',
                      style: TextStyle(color: theme.hintColor, fontSize: 12, fontWeight: FontWeight.normal),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: theme.dividerColor.withOpacity(0.5), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            axisNameWidget: Text(
              isHourly ? 'HORA DEL DÍA' : 'FECHA / DÍA', 
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.hintColor, letterSpacing: 1)
            ),
            axisNameSize: 18,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: (data.length / 5).clamp(1, 100).toDouble(),
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= data.length) return const SizedBox();
                final label = data[idx]['label'];
                String text = label;
                if (!isHourly && label.length >= 10) {
                  text = label.substring(8, 10) + '/' + label.substring(5, 7);
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: theme.hintColor)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: Text(
              'UPH', 
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.hintColor, letterSpacing: 1)
            ),
            axisNameSize: 18,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: TextStyle(color: theme.hintColor, fontSize: 10),
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            gradient: const LinearGradient(colors: [Colors.blue, Colors.cyanAccent]),
            barWidth: 5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 4,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: Colors.blue,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [Colors.blue.withOpacity(0.3), Colors.blue.withOpacity(0.0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _getMaxUPH(Map<String, double> data) {
    if (data.isEmpty) return 100;
    final max = data.values.reduce((curr, next) => curr > next ? curr : next);
    return max > 0 ? max : 100;
  }

  Color _getColorFromName(String name) {
    switch (name.toLowerCase()) {
      case 'rojo': return Colors.red;
      case 'azul': return Colors.blue;
      case 'verde': return Colors.green;
      case 'amarillo': return Colors.yellow;
      case 'naranja': return Colors.orange;
      case 'morado': return Colors.purple;
      case 'rosa': return Colors.pink;
      case 'marrón': return Colors.brown;
      case 'gris': return Colors.grey;
      case 'negro': return Colors.black;
      default: return Colors.blueGrey;
    }
  }
}

class _StatCardBase extends StatelessWidget {
  final String title;
  final Widget child;
  final IconData icon;
  final Color color;

  const _StatCardBase({required this.title, required this.child, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _SubStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SubStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.hintColor,
              letterSpacing: 0.5,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoRow({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.hintColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label, 
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value, 
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
