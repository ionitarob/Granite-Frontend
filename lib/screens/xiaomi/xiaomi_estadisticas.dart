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
  int _simulatedPersonnel = 4; // New: Personnel for simulation
  String _selectedPeriod = 'Hoy'; // Trends
  String _selectedTeamPeriod = 'Hoy'; // Teams
  String _selectedEfficiencyPeriod = 'Hoy'; // Efficiency

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
                    final blockEfficiency = _buildEfficiencyBlock(summary, theme);
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
                                const SizedBox(height: 16),
                                blockEfficiency,
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
                          blockEfficiency,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmall = constraints.maxWidth < 400;
          return GridView.count(
            crossAxisCount: isSmall ? 1 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: isSmall ? 2.5 : 2.0,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _buildComparisonCard(
                label: 'Hoy',
                current: totals['hoy'] ?? 0,
                previous: totals['ayer'] ?? 0,
                comparisonLabel: 'ayer',
                color: Colors.greenAccent,
              ),
              _buildComparisonCard(
                label: 'Esta Semana',
                current: totals['semana'] ?? 0,
                previous: totals['semana_pasada'] ?? 0,
                comparisonLabel: 'sem. pasada',
                color: Colors.blueAccent,
              ),
              _buildComparisonCard(
                label: 'Este Mes',
                current: totals['mes'] ?? 0,
                previous: totals['mes_pasado'] ?? 0,
                comparisonLabel: 'mes pasado',
                color: Colors.purpleAccent,
              ),
              _buildComparisonCard(
                label: 'Este Año',
                current: totals['ano'] ?? 0,
                previous: totals['ano_pasado'] ?? 0,
                comparisonLabel: 'año pasado',
                color: Colors.orangeAccent,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildComparisonCard({
    required String label,
    required int current,
    required int previous,
    required String comparisonLabel,
    required Color color,
  }) {
    final delta = previous > 0 ? ((current - previous) / previous * 100) : 0.0;
    final isPositive = current >= previous;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color, letterSpacing: 1.1)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(current.formattedInt, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const Spacer(),
              if (previous > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isPositive ? Colors.green : Colors.red).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward, size: 10, color: isPositive ? Colors.green : Colors.red),
                      Text('${delta.abs().toStringAsFixed(0)}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isPositive ? Colors.green : Colors.red)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('vs $previous ($comparisonLabel)', style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildPrevisionBlock(XiaomiStatsSummary? summary, ThemeData theme, bool isDesktop) {
    final pending = summary?.pending ?? 0;
    
    // Logic fix: summary.uphToday is currently total group throughput.
    // We need to normalize it to per-person UPH for consistent prediction math.
    final teamPerformance = summary?.teamPerformance ?? [];
    int totalMembers = 0;
    for (var t in teamPerformance) {
      totalMembers += (t['members'] as num?)?.toInt() ?? 0;
    }
    // Safety fallback to 1 if no members found (should not happen if producing)
    final denom = totalMembers > 0 ? totalMembers : 1;

    final uphTodayTotal = summary?.uphToday ?? 0.0;
    final uphWeekTotal = summary?.uphWeek ?? 0.0;
    
    // Normalize to per-person
    final uphTodayPerPerson = uphTodayTotal / denom;
    final uphWeekPerPerson = uphWeekTotal / denom;

    // 1. Calculate absolute workload in "Man-Days" (Jornadas Totales)
    // Man-Hours = Pending / UPH_per_person
    // Jornadas = Man-Hours / Shift_Hours_per_person
    final manHoursToday = uphTodayPerPerson > 0 ? pending / uphTodayPerPerson : 0.0;
    final jornadasToday = _effectiveHours > 0 ? manHoursToday / _effectiveHours : 0.0;
    
    final manHoursWeek = uphWeekPerPerson > 0 ? pending / uphWeekPerPerson : 0.0;
    final jornadasWeek = _effectiveHours > 0 ? manHoursWeek / _effectiveHours : 0.0;

    final manHoursCustom = _customUph > 0 ? pending / _customUph : 0.0;
    final jornadasCustom = _effectiveHours > 0 ? manHoursCustom / _effectiveHours : 0.0;

    // 2. Forecast: Days to complete based on staff size
    // Days = Total_Jornadas / Current_Personnel
    final daysToFinishToday = denom > 0 ? jornadasToday / denom : 0.0;
    final daysToFinishWeek = denom > 0 ? jornadasWeek / denom : 0.0; // Assuming same staff level
    final daysToFinishCustom = _simulatedPersonnel > 0 ? jornadasCustom / _simulatedPersonnel : 0.0;

    return _StatCardBase(
      title: 'PREVISIÓN & SIMULACIÓN',
      icon: Icons.query_stats,
      color: Colors.orangeAccent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputRow(
                            label: 'HORAS/JORNADA',
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
                        const SizedBox(width: 16),
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
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildInputRow(
                            label: 'SIMULAR PLANTILLA',
                            value: _simulatedPersonnel.toString(),
                            suffix: 'operarios',
                            icon: Icons.groups_outlined,
                            color: Colors.purple,
                            onChanged: (v) {
                              final val = int.tryParse(v);
                              if (val != null && val > 0) setState(() => _simulatedPersonnel = val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: isDesktop ? constraints.maxWidth / 3 - 16 : double.infinity,
                    child: _buildPredictionResults(
                      context,
                      title: 'SEGÚN HOY',
                      uph: uphTodayPerPerson,
                      days: daysToFinishToday,
                      jornadas: jornadasToday,
                      staff: denom,
                      color: Colors.green,
                      icon: Icons.today_rounded,
                    ),
                  ),
                  SizedBox(
                    width: isDesktop ? constraints.maxWidth / 3 - 16 : double.infinity,
                    child: _buildPredictionResults(
                      context,
                      title: 'TENDENCIA SEMANA',
                      uph: uphWeekPerPerson,
                      days: daysToFinishWeek,
                      jornadas: jornadasWeek,
                      staff: denom, // Assuming current staff level
                      color: Colors.blue,
                      icon: Icons.date_range_rounded,
                    ),
                  ),
                  SizedBox(
                    width: isDesktop ? constraints.maxWidth / 3 - 16 : double.infinity,
                    child: _buildPredictionResults(
                      context,
                      title: 'SIMULACIÓN MANUAL',
                      uph: _customUph,
                      days: daysToFinishCustom,
                      jornadas: jornadasCustom,
                      staff: _simulatedPersonnel,
                      color: Colors.orange,
                      icon: Icons.edit_note_rounded,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
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
    required double days,
    required double jornadas,
    required int staff,
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
          _InfoRow(label: 'UPH/p actual', value: uph.toStringAsFixed(1), icon: Icons.speed_rounded),
          _InfoRow(label: 'Plantilla', value: '$staff op.', icon: Icons.groups_rounded),
          _InfoRow(label: 'Jornadas totales', value: jornadas.toStringAsFixed(1), icon: Icons.assignment_rounded),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                const Text('DÍAS ESTIMADOS', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    days.toStringAsFixed(1), 
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEfficiencyBlock(XiaomiStatsSummary? summary, ThemeData theme) {
    if (summary == null) return const SizedBox.shrink();
    
    final avgMinutes = summary.avgExecutionAll[_selectedEfficiencyPeriod] ?? 0.0;
    final hours = avgMinutes ~/ 60;
    final minutes = (avgMinutes % 60).toInt();
    
    String timeStr = avgMinutes > 0 
      ? (hours > 0 ? '${hours.toInt()}h ${minutes}m' : '${minutes}m')
      : '---';

    return _StatCardBase(
      title: 'EFICIENCIA DE EJECUCIÓN',
      icon: Icons.timer_rounded,
      color: Colors.greenAccent,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: ['Hoy', 'Semana', 'Mes', 'Año'].map((p) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(p),
                    selected: _selectedEfficiencyPeriod == p,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedEfficiencyPeriod = p);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  Text(
                    timeStr,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Tiempo medio por CESB (${_selectedEfficiencyPeriod})',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Basado en el inicio y fin real de cada palet trabajado ${_selectedEfficiencyPeriod.toLowerCase()}.',
            style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey),
            textAlign: TextAlign.center,
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
                
                final int avgT = (t['avg_time'] as num?)?.toInt() ?? 0;

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
                      if (avgT > 0)
                        Text('Avg: ${avgT}m', style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold))
                      else
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
    final xiaomi = context.read<XiaomiProvider>();
    final summary = xiaomi.summary;
    int todayMembers = 0;
    for (var t in (summary?.teamPerformance ?? [])) {
      todayMembers += (t['members'] as num?)?.toInt() ?? 0;
    }
    final todayDenom = todayMembers > 0 ? todayMembers : 1;

    final uphValues = trend.asMap().entries.map((entry) {
      final e = entry.value;
      final totalUph = (e['uph'] as num).toDouble();
      int workers = (e['workers'] as num?)?.toInt() ?? 0;
      
      // Fallback for current day point
      if (workers <= 0 || (entry.key == trend.length - 1 && workers == 1)) {
        workers = todayDenom;
      }
      
      return totalUph / (workers > 0 ? workers : 1);
    }).toList();
    
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
    // Determine active workers today for fallback
    final xiaomi = context.read<XiaomiProvider>();
    final summary = xiaomi.summary;
    int todayMembers = 0;
    for (var t in (summary?.teamPerformance ?? [])) {
      todayMembers += (t['members'] as num?)?.toInt() ?? 0;
    }
    final todayDenom = todayMembers > 0 ? todayMembers : 1;

    final spots = data.asMap().entries.map((e) {
      final totalUph = (e.value['uph'] as num).toDouble();
      int workers = (e.value['workers'] as num?)?.toInt() ?? 0;
      
      // Sync fix: if workers count is missing or defaulting to 1 in trend (common for today's point), 
      // use the total active members from summary as fallback.
      if (workers <= 0 || (e.key == data.length - 1 && workers == 1)) {
        workers = todayDenom;
      }
      
      final uphPerPerson = totalUph / (workers > 0 ? workers : 1);
      return FlSpot(e.key.toDouble(), uphPerPerson);
    }).toList();

    return LineChart(
      LineChartData(
        backgroundColor: Colors.transparent,
        minY: 0, // Ensure axis starts at 0 for perspective
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.surface,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((s) {
                final idx = s.x.toInt();
                final d = data[idx];
                int w = (d['workers'] as num?)?.toInt() ?? 0;
                if (w <= 0) w = todayDenom;

                return LineTooltipItem(
                  'UPH/p: ${s.y.toStringAsFixed(1)}\n',
                  TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 16),
                  children: [
                    TextSpan(
                      text: '${d['qty']} uds | $w op',
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
          drawVerticalLine: true, // Enable vertical lines for date alignment
          getDrawingHorizontalLine: (value) => FlLine(color: theme.dividerColor.withOpacity(0.3), strokeWidth: 1),
          getDrawingVerticalLine: (value) => FlLine(color: theme.dividerColor.withOpacity(0.3), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            axisNameWidget: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                isHourly ? 'HORA DEL DÍA' : 'FECHA / DÍA', 
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.hintColor, letterSpacing: 1)
              ),
            ),
            axisNameSize: 22,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: 1, // Show all points if possible
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= data.length) return const SizedBox();
                final label = data[idx]['label'];
                String text = label;
                if (!isHourly && label.length >= 10) {
                  text = label.substring(8, 10) + '/' + label.substring(5, 7);
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 8,
                  child: Text(
                    text, 
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: theme.hintColor)
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: Text(
              'UPH/p', 
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.hintColor, letterSpacing: 1)
            ),
            axisNameSize: 18,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 45,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  value.toInt().toString(),
                  style: TextStyle(color: theme.hintColor, fontSize: 10),
                ),
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
            curveSmoothness: 0.25,
            gradient: const LinearGradient(colors: [Colors.blue, Colors.cyanAccent]),
            barWidth: 4,
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
                colors: [Colors.blue.withOpacity(0.2), Colors.blue.withOpacity(0.0)],
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
