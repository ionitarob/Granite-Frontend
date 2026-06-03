import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../utils/formatters.dart';

import 'package:configtool_granite_frontend/config.dart';
import 'package:configtool_granite_frontend/src/api/igualdad_api.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:configtool_granite_frontend/services/api_service.dart';

import '../../widgets/main_sidebar.dart';
import 'resumen_stock.dart';

class _ManualEndpointConfig {
  final String id;
  final String label;
  final Future<void> Function(Map<String, dynamic>) submit;
  final List<_ManualFieldConfig> fields;

  const _ManualEndpointConfig({
    required this.id,
    required this.label,
    required this.submit,
    required this.fields,
  });
}

enum _ManualFieldType { number, text }

class _ManualFieldConfig {
  final String id;
  final String label;
  final _ManualFieldType type;
  final bool isRequired;
  final int maxLines;

  const _ManualFieldConfig({
    required this.id,
    required this.label,
    required this.type,
    this.isRequired = false,
    this.maxLines = 1,
  });
}

class IgualdadDashboard extends StatefulWidget {
  const IgualdadDashboard({super.key});

  @override
  State<IgualdadDashboard> createState() => _IgualdadDashboardState();
}

class _IgualdadDashboardState extends State<IgualdadDashboard> {
  Map<String, dynamic> summaryData = {};
  bool loadingStats = true;
  String? errorStats;

  Map<String, int>? stockReal;
  Map<String, int>? idimActivoVals;
  Map<String, int>? oystaActivoVals;
  Map<String, int>? irrecuperablesVals;
  String? idimCodigo;
  String? oystaCodigo;
  bool loadingStock = true;
  String? errorStock;

  Map<String, dynamic>? deviceStatusData;
  bool loadingDeviceStatus = true;
  String? errorDeviceStatus;

  late final List<_ManualEndpointConfig> _manualConfigs;
  final Map<String, TextEditingController> _manualControllers = {};
  String? _selectedManualId;
  final GlobalKey<FormState> _manualFormKey = GlobalKey<FormState>();
  bool _manualSubmitting = false;

  List<Map<String, dynamic>> _availableWeeks = [];
  bool _loadingWeeks = true;
  String? _weeksError;
  String? _selectedWeekFecha;
  bool? _selectedWeekEnviado;
  String? _selectedWeekObservaciones;
  bool _updatingEnviado = false;

  Future<void> _fetchSummaryData() async {
    setState(() {
      loadingStats = true;
      errorStats = null;
    });
    try {
      final svc = ApiService.instance;
      if (svc != null) {
        final res = await svc.client.get(
          '/igualdad/estadisticas/tarjetas_resumen',
        );
        if (!mounted) return;
        if (res.ok && res.body is Map) {
          setState(() {
            summaryData = Map<String, dynamic>.from(res.body as Map);
            loadingStats = false;
          });
        } else {
          final msg = res.body ?? res.error ?? 'HTTP ${res.statusCode}';
          setState(() {
            errorStats = 'Error: $msg';
            loadingStats = false;
          });
        }
        return;
      }

      final response = await http.get(
        Uri.parse('$kBackendBaseUrl/igualdad/estadisticas/tarjetas_resumen'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        setState(() {
          summaryData = data;
          loadingStats = false;
        });
      } else {
        setState(() {
          errorStats = 'Error: ${response.statusCode}';
          loadingStats = false;
        });
      }
    } catch (e) {
      setState(() {
        errorStats = e.toString();
        loadingStats = false;
      });
    }
  }

  Future<void> _fetchStockData() async {
    setState(() {
      loadingStock = true;
      errorStock = null;
    });
    try {
      final data = await IgualdadApi.getStockResumen();
      if (!mounted) return;
      setState(() {
        stockReal = Map<String, int>.from(data['stock_real']);
        idimActivoVals = Map<String, int>.from(data['idim_activo']);
        oystaActivoVals = Map<String, int>.from(data['oysta_activo']);
        irrecuperablesVals = data['irrecuperables'] != null ? Map<String, int>.from(data['irrecuperables']) : null;
        idimCodigo = data['idim'];
        oystaCodigo = data['oysta'];
        loadingStock = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorStock = e.toString();
        loadingStock = false;
      });
    }
  }

  Future<void> _fetchDeviceStatusData() async {
    setState(() {
      loadingDeviceStatus = true;
      errorDeviceStatus = null;
    });
    try {
      final svc = ApiService.instance;
      if (svc != null) {
        final res = await svc.client.get('/igualdad/dispositivos_resumen_estado');
        if (!mounted) return;
        if (res.ok && res.body is Map) {
          setState(() {
            deviceStatusData = Map<String, dynamic>.from(res.body as Map);
            loadingDeviceStatus = false;
          });
          return;
        }
      }
      final response = await http.get(
        Uri.parse('$kBackendBaseUrl/igualdad/dispositivos_resumen_estado'),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          deviceStatusData = json.decode(response.body) as Map<String, dynamic>;
          loadingDeviceStatus = false;
        });
      } else {
        setState(() {
          errorDeviceStatus = 'Error: ${response.statusCode}';
          loadingDeviceStatus = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorDeviceStatus = e.toString();
        loadingDeviceStatus = false;
      });
    }
  }

  double? _calculatePercentage(num current, num previous) {
    if (previous <= 0) return null;
    return ((current - previous) / previous) * 100;
  }

  Widget _buildStatCard({
    required String title,
    required num value,
    required String comparisonText,
    required double? percentage,
    required Color baseColor,
    required double height,
    num? smVal,
    num? pulserasVal,
    String? dateRange,
  }) {
    final theme = Theme.of(context);
    final formattedValue = NumberFormat.decimalPattern('es_ES').format(value);

    Widget? percentageChip;
    if (percentage != null) {
      final isPositive = percentage >= 0;
      final text = '${isPositive ? "+" : ""}${percentage.toStringAsFixed(0)}%';
      final color = isPositive ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
      percentageChip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              color: color,
              size: 12,
            ),
            const SizedBox(width: 2),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    Widget? desglosePills;
    if (smVal != null && pulserasVal != null) {
      desglosePills = Row(
        children: [
          _buildDesglosePill(
            icon: Icons.smartphone_rounded,
            label: 'SM',
            count: smVal,
            color: baseColor,
          ),
          const SizedBox(width: 6),
          _buildDesglosePill(
            icon: Icons.watch_rounded,
            label: 'Pulseras',
            count: pulserasVal,
            color: baseColor,
          ),
        ],
      );
    }

    final double extraHeight = (desglosePills != null ? 36.0 : 0.0) + (dateRange != null ? 14.0 : 0.0);

    return Container(
      height: height + extraHeight,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: baseColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: baseColor.withOpacity(0.25),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: baseColor.withOpacity(0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (dateRange != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      dateRange,
                      style: TextStyle(
                        color: baseColor.withOpacity(0.65),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              if (percentageChip != null) percentageChip,
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formattedValue,
                style: TextStyle(
                  fontSize: height > 150 ? 32 : 28,
                  fontWeight: FontWeight.w900,
                  color: theme.textTheme.titleLarge?.color,
                  height: 1.1,
                ),
              ),
              if (desglosePills != null) ...[const SizedBox(height: 8), desglosePills],
              const SizedBox(height: 4),
              Text(
                comparisonText,
                style: TextStyle(
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesglosePill({
    required IconData icon,
    required String label,
    required num count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color.withOpacity(0.8)),
          const SizedBox(width: 4),
          Text(
            '$label: $count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color.withOpacity(0.9),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards({bool compact = false}) {
    final decoration = BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(compact ? 22 : 26),
      border: Border.all(
        color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Theme.of(context).shadowColor.withOpacity(0.05),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ],
    );

    if (loadingStats) {
      return Container(
        decoration: decoration,
        padding: EdgeInsets.symmetric(
          vertical: compact ? 28 : 40,
          horizontal: compact ? 24 : 32,
        ),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }
    if (errorStats != null) {
      return Container(
        decoration: decoration,
        padding: EdgeInsets.symmetric(
          vertical: compact ? 28 : 40,
          horizontal: compact ? 24 : 32,
        ),
        alignment: Alignment.center,
        child: Text(
          'Error al cargar estadísticas: $errorStats',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontWeight: FontWeight.w600,
            fontSize: compact ? 14 : 16,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final double titleFontSize = compact ? 18 : 20;

    return Container(
      decoration: decoration,
      padding: EdgeInsets.fromLTRB(
        compact ? 20 : 28,
        compact ? 22 : 28,
        compact ? 20 : 28,
        compact ? 22 : 28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.inventory_2_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: compact ? 22 : 26,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'TOTAL UNIDADES',
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Theme.of(context).textTheme.titleLarge?.color,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () {
                  _fetchSummaryData();
                  _fetchStockData();
                  _fetchDeviceStatusData();
                },
                tooltip: 'Actualizar estadísticas',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final double cardHeight = compact ? 140 : 160;
              final bool useVerticalLayout = constraints.maxWidth < 600;

              final hoyVal = summaryData['hoy'] ?? 0;
              final ayerVal = summaryData['ayer'] ?? 0;
              final estaSemanaVal = summaryData['esta_semana'] ?? 0;
              final semanaPasadaVal = summaryData['semana_pasada'] ?? 0;
              final esteMesVal = summaryData['este_mes'] ?? 0;
              final mesPasadoVal = summaryData['mes_pasado'] ?? 0;
              final esteAnoVal = summaryData['este_ano'] ?? 0;
              final anoPasadoVal = summaryData['ano_pasado'] ?? 0;

              final hoySmVal = summaryData['hoy_sm'] ?? 0;
              final hoyPulserasVal = summaryData['hoy_pulseras'] ?? 0;
              final estaSemanaSmVal = summaryData['esta_semana_sm'] ?? 0;
              final estaSemanaPulserasVal = summaryData['esta_semana_pulseras'] ?? 0;
              final esteMesSmVal = summaryData['este_mes_sm'] ?? 0;
              final esteMesPulserasVal = summaryData['este_mes_pulseras'] ?? 0;
              final esteAnoSmVal = summaryData['este_ano_sm'] ?? 0;
              final esteAnoPulserasVal = summaryData['este_ano_pulseras'] ?? 0;

              final cardHoy = _buildStatCard(
                title: 'HOY',
                value: hoyVal,
                comparisonText: 'vs $ayerVal (ayer)',
                percentage: null,
                baseColor: const Color(0xFF4E9F3D), // Green
                height: cardHeight,
                smVal: hoySmVal,
                pulserasVal: hoyPulserasVal,
                dateRange: summaryData['hoy_rango'],
              );

              final cardSemana = _buildStatCard(
                title: 'ESTA SEMANA',
                value: estaSemanaVal,
                comparisonText: 'vs $semanaPasadaVal (sem. pasada)',
                percentage: _calculatePercentage(estaSemanaVal, semanaPasadaVal),
                baseColor: const Color(0xFF2B5C8F), // Blue
                height: cardHeight,
                smVal: estaSemanaSmVal,
                pulserasVal: estaSemanaPulserasVal,
                dateRange: summaryData['esta_semana_rango'],
              );

              final cardMes = _buildStatCard(
                title: 'ESTE MES',
                value: esteMesVal,
                comparisonText: 'vs $mesPasadoVal (mes pasado)',
                percentage: _calculatePercentage(esteMesVal, mesPasadoVal),
                baseColor: const Color(0xFF6B2B8F), // Purple
                height: cardHeight,
                smVal: esteMesSmVal,
                pulserasVal: esteMesPulserasVal,
                dateRange: summaryData['este_mes_rango'],
              );

              final cardAno = _buildStatCard(
                title: 'ESTE AÑO',
                value: esteAnoVal,
                comparisonText: 'vs $anoPasadoVal (año pasado)',
                percentage: _calculatePercentage(esteAnoVal, anoPasadoVal),
                baseColor: const Color(0xFF8F5C2B), // Bronze/Brown
                height: cardHeight,
                smVal: esteAnoSmVal,
                pulserasVal: esteAnoPulserasVal,
                dateRange: summaryData['este_ano_rango'],
              );

              if (useVerticalLayout) {
                return Column(
                  children: [
                    cardHoy,
                    const SizedBox(height: 12),
                    cardSemana,
                    const SizedBox(height: 12),
                    cardMes,
                    const SizedBox(height: 12),
                    cardAno,
                  ],
                );
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: cardHoy),
                      const SizedBox(width: 12),
                      Expanded(child: cardSemana),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: cardMes),
                      const SizedBox(width: 12),
                      Expanded(child: cardAno),
                    ],
                  ),
                ],
              );
            },
          ),
          _buildHistorySection(compact: compact),
        ],
      ),
    );
  }

  Widget _buildHistorySection({required bool compact}) {
    final theme = Theme.of(context);
    final days = List<Map<String, dynamic>>.from(summaryData['historial_dias'] ?? []);
    final weeks = List<Map<String, dynamic>>.from(summaryData['historial_semanas'] ?? []);
    final months = List<Map<String, dynamic>>.from(summaryData['historial_meses'] ?? []);

    if (days.isEmpty && weeks.isEmpty && months.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget buildHistoryList(String title, IconData icon, Color color, List<Map<String, dynamic>> items, String type) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor.withOpacity(0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.08),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map((item) {
              final label = item['label'] ?? '';
              final sm = item['sm'] ?? 0;
              final pul = item['pulseras'] ?? 0;
              
              String dateText = '';
              String itemTitle = label;
              
              if (type == 'day') {
                if (label != 'Hoy' && label != 'Ayer') {
                  itemTitle = label;
                } else if (label == 'Ayer') {
                  itemTitle = 'Ayer (${item['fecha']})';
                } else {
                  itemTitle = 'Hoy';
                }
              } else {
                dateText = ' (${item['fecha_inicio']} - ${item['fecha_fin']})';
              }

              final isLast = items.indexOf(item) == items.length - 1;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$itemTitle$dateText',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.85),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildDesgloseMiniPill(
                          icon: Icons.smartphone_rounded,
                          label: '$sm SM',
                          color: color,
                        ),
                        const SizedBox(width: 6),
                        _buildDesgloseMiniPill(
                          icon: Icons.watch_rounded,
                          label: '$pul Pulseras',
                          color: color,
                        ),
                      ],
                    ),
                    if (!isLast) ...[
                      const SizedBox(height: 8),
                      Divider(color: theme.colorScheme.outline.withOpacity(0.05), height: 1),
                    ],
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      );
    }

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'HISTORIAL DE DISPOSITIVOS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 12),
          buildHistoryList('ÚLTIMOS DÍAS', Icons.calendar_today_rounded, const Color(0xFF4E9F3D), days, 'day'),
          const SizedBox(height: 12),
          buildHistoryList('ÚLTIMAS SEMANAS', Icons.view_week_rounded, const Color(0xFF2B5C8F), weeks, 'week'),
          const SizedBox(height: 12),
          buildHistoryList('ÚLTIMOS MESES', Icons.calendar_month_rounded, const Color(0xFF6B2B8F), months, 'month'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        Text(
          'HISTORIAL DE DISPOSITIVOS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: buildHistoryList('ÚLTIMOS DÍAS', Icons.calendar_today_rounded, const Color(0xFF4E9F3D), days, 'day')),
            const SizedBox(width: 12),
            Expanded(child: buildHistoryList('ÚLTIMAS SEMANAS', Icons.view_week_rounded, const Color(0xFF2B5C8F), weeks, 'week')),
            const SizedBox(width: 12),
            Expanded(child: buildHistoryList('ÚLTIMOS MESES', Icons.calendar_month_rounded, const Color(0xFF6B2B8F), months, 'month')),
          ],
        ),
      ],
    );
  }

  Widget _buildDesgloseMiniPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color.withOpacity(0.8)),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: color.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceStatusCard({bool compact = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final decoration = BoxDecoration(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(compact ? 22 : 26),
      border: Border.all(
        color: theme.colorScheme.outline.withOpacity(0.1),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: theme.shadowColor.withOpacity(0.05),
          blurRadius: 20,
          offset: const Offset(0, 4),
         )
      ],
    );

    if (loadingDeviceStatus) {
      return Container(
        decoration: decoration,
        padding: const EdgeInsets.all(28),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    if (errorDeviceStatus != null) {
      return Container(
        decoration: decoration,
        padding: const EdgeInsets.all(28),
        alignment: Alignment.center,
        child: Text(
          'Error: $errorDeviceStatus',
          style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600),
        ),
      );
    }

    final data = deviceStatusData ?? {'active': 0, 'oysta': 0, 'irrecuperable': 0, 'total': 0};
    final active = int.tryParse(data['active'].toString()) ?? 0;
    final oysta = int.tryParse(data['oysta'].toString()) ?? 0;
    final irrecuperable = int.tryParse(data['irrecuperable'].toString()) ?? 0;
    final total = int.tryParse(data['total'].toString()) ?? 0;

    final List<PieChartSectionData> sections = [];
    if (active > 0) {
      sections.add(
        PieChartSectionData(
          color: const Color(0xFF4E9F3D),
          value: active.toDouble(),
          title: '$active',
          radius: 35,
          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    }
    if (oysta > 0) {
      sections.add(
        PieChartSectionData(
          color: const Color(0xFF2B5C8F),
          value: oysta.toDouble(),
          title: '$oysta',
          radius: 35,
          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    }
    if (irrecuperable > 0) {
      sections.add(
        PieChartSectionData(
          color: const Color(0xFFC62828),
          value: irrecuperable.toDouble(),
          title: '$irrecuperable',
          radius: 35,
          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    }

    return Container(
      decoration: decoration,
      padding: EdgeInsets.all(compact ? 20 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pie_chart_rounded,
                color: theme.colorScheme.primary,
                size: compact ? 22 : 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ESTADO DE DISPOSITIVOS',
                  style: TextStyle(
                    fontSize: compact ? 18 : 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: theme.textTheme.titleLarge?.color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: sections.isEmpty
                    ? const Center(child: Text('Sin datos', style: TextStyle(fontSize: 11)))
                    : PieChart(
                        PieChartData(
                          sections: sections,
                          centerSpaceRadius: 20,
                          sectionsSpace: 2,
                        ),
                      ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLegendItem(
                      color: const Color(0xFF4E9F3D),
                      label: 'Activos / IDIM',
                      value: active,
                      percentage: total > 0 ? (active / total * 100).toStringAsFixed(1) : '0',
                    ),
                    const SizedBox(height: 6),
                    _buildLegendItem(
                      color: const Color(0xFF2B5C8F),
                      label: 'Enviados OYSTA',
                      value: oysta,
                      percentage: total > 0 ? (oysta / total * 100).toStringAsFixed(1) : '0',
                    ),
                    const SizedBox(height: 6),
                    _buildLegendItem(
                      color: const Color(0xFFC62828),
                      label: 'Irrecuperables',
                      value: irrecuperable,
                      percentage: total > 0 ? (irrecuperable / total * 100).toStringAsFixed(1) : '0',
                    ),
                    const Divider(height: 12),
                    Text(
                      'Total único IMEIs: $total',
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required int value,
    required String percentage,
  }) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '$value ($percentage%)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Map<String, dynamic>? resumenSemanal;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _manualConfigs = _buildManualConfigs();
    for (final config in _manualConfigs) {
      for (final field in config.fields) {
        _manualControllers.putIfAbsent(field.id, () => TextEditingController());
      }
    }
    if (_manualConfigs.isNotEmpty) {
      _selectedManualId = _manualConfigs.first.id;
    }
    _fetchSemanas(refreshResumen: true);
    _fetchSummaryData();
    _fetchStockData();
    _fetchDeviceStatusData();
  }

  Future<void> _fetchSemanas({bool refreshResumen = false}) async {
    setState(() {
      _loadingWeeks = true;
      _weeksError = null;
    });
    try {
      final weeks = await IgualdadApi.getResumenSemanas(limit: 12);
      String? nextSelected = _selectedWeekFecha;
      Map<String, dynamic>? selectedWeek;
      if (weeks.isNotEmpty) {
        if (nextSelected != null) {
          for (final week in weeks) {
            final inicio = week['fecha_inicio']?.toString();
            if (inicio == nextSelected) {
              selectedWeek = week;
              break;
            }
          }
        }
        if (selectedWeek == null) {
          selectedWeek = weeks.first;
          nextSelected = selectedWeek['fecha_inicio']?.toString();
        }
      } else {
        nextSelected = null;
      }
      final bool? selectedEnviado = _parseBool(selectedWeek?['enviado']);
      final String? selectedObs;
      if (selectedWeek == null) {
        selectedObs = null;
      } else if (selectedWeek.containsKey('observaciones')) {
        final dynamic rawObs = selectedWeek['observaciones'];
        selectedObs = rawObs?.toString();
      } else {
        selectedObs = _selectedWeekObservaciones;
      }
      if (!mounted) return;
      setState(() {
        _availableWeeks = weeks;
        _selectedWeekFecha = nextSelected;
        _selectedWeekEnviado = selectedWeek == null ? null : selectedEnviado;
        _selectedWeekObservaciones = selectedObs;
        _loadingWeeks = false;
      });
      if (refreshResumen) {
        final bool showLoader = resumenSemanal == null;
        await _fetchResumen(fecha: nextSelected, showLoader: showLoader);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _weeksError = e.toString();
        _loadingWeeks = false;
      });
      if (refreshResumen && resumenSemanal == null) {
        await _fetchResumen();
      }
    }
  }

  bool? _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) return null;
      if (normalized == 'true' ||
          normalized == '1' ||
          normalized == 'si' ||
          normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return null;
  }

  Future<void> _fetchResumen({String? fecha, bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        loading = true;
        error = null;
      });
    } else {
      setState(() {
        error = null;
      });
    }
    try {
      final data = await IgualdadApi.getResumenSemanal(fecha: fecha);
      final bool hasEnviadoKey = data.containsKey('enviado');
      final bool? resumenEnviado = hasEnviadoKey
          ? _parseBool(data['enviado'])
          : null;
      final bool hasObsKey = data.containsKey('observaciones');
      final String? resumenObs;
      if (hasObsKey) {
        final dynamic rawObs = data['observaciones'];
        resumenObs = rawObs?.toString();
      } else {
        resumenObs = null;
      }
      final String? resolvedFecha =
          fecha ??
          (data['fecha_inicio'] is String
              ? data['fecha_inicio'] as String
              : _selectedWeekFecha);
      List<Map<String, dynamic>>? updatedWeeks;
      if (resolvedFecha != null && (hasEnviadoKey || hasObsKey)) {
        updatedWeeks = _availableWeeks.map((week) {
          if (week['fecha_inicio']?.toString() == resolvedFecha) {
            final updated = Map<String, dynamic>.from(week);
            if (hasEnviadoKey) {
              updated['enviado'] = resumenEnviado;
            }
            if (hasObsKey) {
              updated['observaciones'] = resumenObs;
            }
            return updated;
          }
          return week;
        }).toList();
      }
      if (!mounted) return;
      setState(() {
        if (updatedWeeks != null) {
          _availableWeeks = updatedWeeks;
        }
        resumenSemanal = data;
        loading = false;
        _selectedWeekFecha = resolvedFecha;
        if (hasEnviadoKey) {
          _selectedWeekEnviado = resumenEnviado;
        }
        if (hasObsKey) {
          _selectedWeekObservaciones = resumenObs;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _handleWeekSelection(String? fecha) async {
    if (fecha == null || fecha == _selectedWeekFecha) {
      return;
    }
    Map<String, dynamic>? selectedWeek;
    for (final week in _availableWeeks) {
      if (week['fecha_inicio']?.toString() == fecha) {
        selectedWeek = week;
        break;
      }
    }
    final bool? enviadoSeleccionado = _parseBool(selectedWeek?['enviado']);
    String? obsSeleccionada;
    if (selectedWeek == null) {
      obsSeleccionada = null;
    } else if (selectedWeek.containsKey('observaciones')) {
      final dynamic rawObs = selectedWeek['observaciones'];
      obsSeleccionada = rawObs?.toString();
    } else {
      obsSeleccionada = _selectedWeekObservaciones;
    }
    setState(() {
      _selectedWeekFecha = fecha;
      _selectedWeekEnviado = enviadoSeleccionado;
      _selectedWeekObservaciones = obsSeleccionada;
    });
    await _fetchResumen(fecha: fecha);
  }

  Future<String?> _askObservaciones({String? initial}) async {
    final controller = TextEditingController(text: initial ?? '');
    final String? result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Observaciones del envío'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Deja el campo vacío para que el sistema rellene "Enviado el ..." automáticamente.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observaciones',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<bool> _confirmResetEnvio() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar como pendiente'),
        content: const Text(
          'Esto eliminará las observaciones almacenadas y dejará la semana como pendiente. ¿Quieres continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return confirm ?? false;
  }

  Future<void> _markWeekEnviado() async {
    final fecha = _selectedWeekFecha;
    if (fecha == null) return;
    final note = await _askObservaciones(initial: _selectedWeekObservaciones);
    if (note == null) {
      return;
    }
    final normalized = note.trim();
    final String? payloadNote = normalized.isEmpty ? null : normalized;
    await _submitEnvioChange(
      fecha: fecha,
      enviado: true,
      observaciones: payloadNote,
    );
  }

  Future<void> _resetWeekEnviado() async {
    final fecha = _selectedWeekFecha;
    if (fecha == null) return;
    final confirmed = await _confirmResetEnvio();
    if (!confirmed) {
      return;
    }
    await _submitEnvioChange(fecha: fecha, enviado: false, observaciones: null);
  }

  Future<void> _submitEnvioChange({
    required String fecha,
    required bool enviado,
    String? observaciones,
  }) async {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _updatingEnviado = true;
    });
    try {
      await IgualdadApi.marcarResumenSemanalEnviado(
        fecha: fecha,
        enviado: enviado,
        observaciones: observaciones,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enviado
                ? 'Semana marcada como enviada.'
                : 'Semana marcada como pendiente.',
          ),
        ),
      );
      await _fetchSemanas(refreshResumen: false);
      await _fetchResumen(
        fecha: _selectedWeekFecha ?? fecha,
        showLoader: false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar estado: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingEnviado = false;
        });
      }
    }
  }

  Widget? _buildWeekStatusControls(bool compact) {
    final String? fecha = _selectedWeekFecha;
    if (fecha == null) {
      return null;
    }
    final theme = Theme.of(context);
    final bool sent = _selectedWeekEnviado ?? false;
    final String? obs = _selectedWeekObservaciones;
    final bool busy = _updatingEnviado;
    final Color baseColor = sent
        ? const Color(0xFF2E7D32)
        : const Color(0xFFF57C00);
    final double backgroundOpacity = sent ? 0.18 : 0.17;
    final double borderOpacity = sent ? 0.55 : 0.50;
    final Color statusBackground = baseColor.withValues(
      alpha: backgroundOpacity,
    );
    final Color statusBorder = baseColor.withValues(alpha: borderOpacity);
    final IconData statusIcon = sent ? Icons.check_circle : Icons.schedule;
    final String statusLabel = sent ? 'Enviado' : 'Pendiente';

    final List<Widget> children = [
      Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: statusBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: statusBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon, size: compact ? 18 : 20, color: baseColor),
            const SizedBox(width: 8),
            Text(
              statusLabel,
              style: TextStyle(
                color: baseColor,
                fontWeight: FontWeight.w700,
                fontSize: compact ? 12 : 13,
              ),
            ),
          ],
        ),
      ),
    ];

    if (obs != null && obs.trim().isNotEmpty) {
      children.add(
        Container(
          constraints: BoxConstraints(maxWidth: compact ? 260 : 360),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 6 : 8,
          ),
          decoration: BoxDecoration(
            color: const Color(0x14000000),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            'Obs.: $obs',
            style: TextStyle(
              color: Colors.black87,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    final Widget actionButton = sent
        ? OutlinedButton.icon(
            onPressed: busy ? null : _resetWeekEnviado,
            icon: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  )
                : const Icon(Icons.undo),
            label: Text(busy ? 'Actualizando…' : 'Marcar como pendiente'),
          )
        : FilledButton.icon(
            onPressed: busy ? null : _markWeekEnviado,
            icon: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.onPrimary,
                      ),
                    ),
                  )
                : const Icon(Icons.send),
            label: Text(busy ? 'Actualizando…' : 'Marcar como enviado'),
          );

    children.add(actionButton);

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  Widget _buildResumenTable({bool compact = false}) {
    if (resumenSemanal == null) return const SizedBox();
    final resumen = resumenSemanal!["resumen"] as List<dynamic>? ?? [];
    // Make a modifiable copy we can augment for display purposes
    final List<dynamic> displayResumen = List<dynamic>.from(resumen);
    // Ensure there's a "Recibido por Securitas" row. Backend may provide it as a separate field
    bool hasRecibido = displayResumen.any((r) {
      final cat = (r['categoria'] ?? '').toString().toLowerCase();
      return cat.contains('securitas') ||
          cat.contains('recibido por securitas') ||
          cat.contains('recibido por securit');
    });
    if (!hasRecibido) {
      final reciboData =
          resumenSemanal!["recibido_por_securitas"] ??
          resumenSemanal!["recibido_securitas"] ??
          resumenSemanal!["recibido_por_securit"];
      if (reciboData != null) {
        // reciboData might be a map with counts per column or a single number
        final Map<String, dynamic> row = {
          'categoria': 'Recibido por Securitas',
          'sma': reciboData is Map && reciboData['sma'] != null
              ? reciboData['sma']
              : (reciboData is num ? reciboData : 0),
          'smv': reciboData is Map && reciboData['smv'] != null
              ? reciboData['smv']
              : 0,
          'pulseras': reciboData is Map && reciboData['pulseras'] != null
              ? reciboData['pulseras']
              : 0,
          'botones': reciboData is Map && reciboData['botones'] != null
              ? reciboData['botones']
              : 0,
          'pw':
              reciboData is Map &&
                  (reciboData['pw'] != null || reciboData['powerbanks'] != null)
              ? (reciboData['pw'] ?? reciboData['powerbanks'])
              : 0,
          'referencia_envio':
              reciboData is Map && reciboData['referencia'] != null
              ? reciboData['referencia']
              : '',
          'observaciones':
              reciboData is Map && reciboData['observaciones'] != null
              ? reciboData['observaciones']
              : '',
        };
        // insert near the top for visibility
        displayResumen.insert(0, row);
      }
    }
    final servicios =
        resumenSemanal!["servicios_adicionales"] as Map<String, dynamic>? ?? {};
    final fechaInicio = resumenSemanal!["fecha_inicio"] ?? '';
    final fechaFin = resumenSemanal!["fecha_fin"] ?? '';
    final Widget? statusControls = _buildWeekStatusControls(compact);

    Widget weekSelector;
    if (_loadingWeeks) {
      weekSelector = Row(
        children: [
          SizedBox(
            width: compact ? 16 : 18,
            height: compact ? 16 : 18,
            child: const CircularProgressIndicator(strokeWidth: 2.2),
          ),
          SizedBox(width: compact ? 8 : 10),
          Expanded(
            child: Text(
              'Cargando semanas disponibles…',
              style: TextStyle(
                color: Colors.black.withOpacity(0.75),
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else if (_weeksError != null) {
      weekSelector = Row(
        children: [
          Expanded(
            child: Text(
              'Error al cargar semanas: $_weeksError',
              style: TextStyle(
                color: Colors.black.withOpacity(0.75),
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () => _fetchSemanas(refreshResumen: false),
            tooltip: 'Reintentar',
            icon: const Icon(Icons.refresh, size: 20, color: Colors.black87),
          ),
        ],
      );
    } else if (_availableWeeks.isEmpty) {
      weekSelector = Text(
        'No hay semanas previas registradas.',
        style: TextStyle(
          color: Colors.black.withOpacity(0.75),
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.w600,
        ),
      );
    } else {
      final validWeeks = _availableWeeks
          .where((week) => week['fecha_inicio'] != null)
          .toList();
      if (validWeeks.isEmpty) {
        weekSelector = Text(
          'No hay semanas previas registradas.',
          style: TextStyle(
            color: Colors.black.withOpacity(0.75),
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
          ),
        );
      } else {
        final hasSelection = validWeeks.any(
          (w) => w['fecha_inicio'].toString() == _selectedWeekFecha,
        );
        final selectedValue = hasSelection ? _selectedWeekFecha : null;
        weekSelector = InputDecorator(
          decoration: InputDecoration(
            labelText: 'Selecciona semana',
            filled: true,
            fillColor: Colors.white.withOpacity(0.16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.22)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.22)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: const Color(0xFF7C3AED)),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 6 : 8,
            ),
          ),
          isEmpty: selectedValue == null,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedValue,
              isExpanded: true,
              dropdownColor: Colors.white,
              style: TextStyle(
                color: Colors.black87,
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w600,
              ),
              hint: Text(
                'Selecciona semana',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              items: validWeeks.map((week) {
                final inicio = week['fecha_inicio']?.toString() ?? '';
                final fin = week['fecha_fin']?.toString() ?? '';
                final bool isSent = _parseBool(week['enviado']) ?? false;
                final IconData iconData = isSent
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked;
                final Color iconColor = isSent
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF757575);
                final String label =
                    '${inicio.isEmpty ? '?' : inicio} → ${fin.isEmpty ? '?' : fin}${isSent ? ' • Enviado' : ''}';
                return DropdownMenuItem<String>(
                  value: week['fecha_inicio']?.toString(),
                  child: Row(
                    children: [
                      Icon(iconData, size: compact ? 18 : 20, color: iconColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: compact ? 13 : 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: _handleWeekSelection,
            ),
          ),
        );
      }
    }

    final List<Color> headerColors = [
      const Color(0xFFB03A5B),
      const Color(0xFFD72660),
      const Color(0xFF7C3AED),
      const Color(0xFFB03A5B),
      const Color(0xFF7C3AED),
      const Color(0xFFD72660),
      const Color(0xFFB03A5B),
      const Color(0xFF7C3AED),
    ];
    final List<String> headers = [
      'Categoría',
      'SMA',
      'SMV',
      'Pulseras',
      'Botones',
      'PowerBanks',
      'Referencia',
      'Obs.',
    ];

    final boxDecoration = BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(compact ? 22 : 26),
      border: Border.all(
        color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Theme.of(context).shadowColor.withOpacity(0.05),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ],
    );
    final bool useHorizontalScroll = compact;

    return Container(
      decoration: boxDecoration,
      padding: EdgeInsets.fromLTRB(
        compact ? 20 : 28,
        compact ? 22 : 28,
        compact ? 20 : 28,
        compact ? 18 : 22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumen semanal',
                      style: TextStyle(
                        fontSize: compact ? 20 : 22,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$fechaInicio  ·  $fechaFin',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: compact ? 10 : 12),
                    weekSelector,
                    if (statusControls != null) ...[
                      SizedBox(height: compact ? 8 : 10),
                      statusControls,
                    ],
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 12,
                  vertical: compact ? 5 : 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.26),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.22)),
                ),
                child: Text(
                  '${resumen.length} categorías',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                    fontSize: compact ? 12 : 13,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 18 : 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(compact ? 16 : 20),
            child: Container(
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.06)),
              child: useHorizontalScroll
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: compact ? 2 : 4,
                          horizontal: compact ? 2 : 4,
                        ),
                        child: _buildResumenTableBody(
                          headers,
                          headerColors,
                          displayResumen,
                          compact,
                          true,
                        ),
                      ),
                    )
                  : Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: compact ? 2 : 4,
                        horizontal: compact ? 2 : 4,
                      ),
                      child: _buildResumenTableBody(
                        headers,
                        headerColors,
                        displayResumen,
                        compact,
                        false,
                      ),
                    ),
            ),
          ),
          SizedBox(height: compact ? 18 : 22),
          Divider(color: Colors.white.withOpacity(0.24), thickness: 1),
          SizedBox(height: compact ? 8 : 12),
          Text(
            'Servicios adicionales',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 14 : 16,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Wrap(
            spacing: compact ? 12 : 16,
            runSpacing: compact ? 8 : 10,
            alignment: compact ? WrapAlignment.start : WrapAlignment.start,
            children: [
              _buildLegendChip(
                const Color(0xFFFFB366),
                'Serigrafía pulseras: ${(servicios['serigrafia_pulseras'] as num? ?? 0).formattedInt}',
                compact: compact,
              ),
              _buildLegendChip(
                const Color(0xFF66BB6A),
                'Tornillería: ${servicios['tornilleria'] ?? 0}',
                compact: compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResumenTableBody(
    List<String> headers,
    List<Color> headerColors,
    List<dynamic> resumen,
    bool compact,
    bool scrollable,
  ) {
    return Table(
      columnWidths: scrollable
          ? const {
              0: FixedColumnWidth(160),
              1: FixedColumnWidth(60),
              2: FixedColumnWidth(60),
              3: FixedColumnWidth(75),
              4: FixedColumnWidth(70),
              5: FixedColumnWidth(95),
              6: FixedColumnWidth(100),
              7: FixedColumnWidth(90),
            }
          : const {
              0: FlexColumnWidth(2.8),
              1: FlexColumnWidth(1.0),
              2: FlexColumnWidth(1.0),
              3: FlexColumnWidth(1.1),
              4: FlexColumnWidth(1.0),
              5: FlexColumnWidth(1.2),
              6: FlexColumnWidth(1.6),
              7: FlexColumnWidth(1.3),
            },
      border: const TableBorder(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            for (int idx = 0; idx < headers.length; idx++)
              Container(
                margin: EdgeInsets.only(
                  right: idx < headers.length - 1 ? (compact ? 4 : 6) : 0,
                  bottom: compact ? 10 : 12,
                ),
                padding: EdgeInsets.symmetric(
                  vertical: compact ? 12 : 14,
                  horizontal: compact ? 14 : 18,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [
                      headerColors[idx].withOpacity(0.95),
                      headerColors[idx].withOpacity(0.70),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  headers[idx],
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 13.5 : 15,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
          ],
        ),
        ...List.generate(resumen.length, (index) {
          final row = resumen[index];
          Color rowBg;
          if (index < 3) {
            rowBg = const Color(0xFFFF9999).withOpacity(0.65);
          } else if (index == 3) {
            rowBg = const Color(0xFFFFB366).withOpacity(0.65);
          } else if (index == 4 || index == 5) {
            rowBg = const Color(0xFFFFFF99).withOpacity(0.55);
          } else if (index == 6 || index == 7) {
            rowBg = const Color(0xFF66CCFF).withOpacity(0.60);
          } else if (index == 8) {
            rowBg = const Color(0xFFCC99FF).withOpacity(0.62);
          } else {
            rowBg = Colors.white.withOpacity(0.22);
          }
          final cells = [
            row['categoria'],
            row['sma'],
            row['smv'],
            row['pulseras'],
            row['botones'],
            row['pw'],
            row['referencia_envio'],
            row['observaciones'],
          ];
          return TableRow(
            children: [
              for (int idx = 0; idx < cells.length; idx++)
                Container(
                  margin: EdgeInsets.only(
                    right: idx < cells.length - 1 ? (compact ? 4 : 6) : 0,
                    bottom: compact ? 8 : 10,
                  ),
                  padding: EdgeInsets.symmetric(
                    vertical: compact ? 10 : 12,
                    horizontal: compact ? 12 : 16,
                  ),
                  decoration: BoxDecoration(
                    color: rowBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                  ),
                  alignment: Alignment.center,
                  child: Builder(
                    builder: (context) {
                      final textVal = cells[idx] == null ? '' : cells[idx].toString();
                      if (idx == 0 && (textVal == 'Irrecuperables' || textVal == 'Enviado a Securitas Irrecuperables')) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 15,
                              color: Color(0xFFE53935),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                textVal,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      return Text(
                        textVal,
                        style: TextStyle(
                          color: idx == 0 ? Colors.black : Colors.black87,
                          fontWeight: idx == 0 ? FontWeight.w700 : FontWeight.w500,
                          fontSize: compact ? 13 : 14,
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildStatusCard({required Widget child}) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.1),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isVeryNarrow = MediaQuery.of(context).size.width < 450;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.equalizer_rounded,
            size: 32,
            color: theme.colorScheme.primary,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dashboard Igualdad',
              style: (isVeryNarrow 
                ? theme.textTheme.headlineSmall 
                : theme.textTheme.headlineMedium)?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            Text(
              'Gestión de stock, envíos y estadísticas',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendChip(Color color, String label, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.45), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 8 : 10,
            height: compact ? 8 : 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: compact ? 6 : 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 12 : 13,
            ),
          ),
        ],
      ),
    );
  }

  List<_ManualEndpointConfig> _buildManualConfigs() {
    return [
      _ManualEndpointConfig(
        id: 'enviado_vodafone',
        label: 'Enviado a Vodafone',
        submit: IgualdadApi.registrarEnviadoVodafone,
        fields: _commonCountFields(includeObservaciones: true),
      ),
      _ManualEndpointConfig(
        id: 'equipos_nuevos',
        label: 'Equipos nuevos sin enviar',
        submit: IgualdadApi.registrarEquiposNuevos,
        fields: _commonCountFields(),
      ),
      _ManualEndpointConfig(
        id: 'en_diagnostico',
        label: 'En Diagnóstico',
        submit: IgualdadApi.registrarEnDiagnostico,
        fields: _commonCountFields(includeObservaciones: true),
      ),
      _ManualEndpointConfig(
        id: 'irrecuperables_general',
        label: 'Irrecuperables',
        submit: IgualdadApi.registrarIrrecuperablesGeneral,
        fields: _commonCountFields(includeObservaciones: true),
      ),
      _ManualEndpointConfig(
        id: 'irrecuperables',
        label: 'Enviado a Securitas Irrecuperables',
        submit: IgualdadApi.registrarIrrecuperables,
        fields: _commonCountFields(includeObservaciones: true),
      ),
      _ManualEndpointConfig(
        id: 'servicios_adicionales',
        label: 'Servicios adicionales',
        submit: IgualdadApi.registrarServiciosAdicionales,
        fields: const [
          _ManualFieldConfig(
            id: 'serigrafia_pulseras',
            label: 'Serigrafía pulseras',
            type: _ManualFieldType.number,
          ),
          _ManualFieldConfig(
            id: 'tornilleria',
            label: 'Tornillería',
            type: _ManualFieldType.number,
          ),
        ],
      ),
    ];
  }

  List<_ManualFieldConfig> _commonCountFields({
    bool includeObservaciones = false,
  }) {
    final fields = <_ManualFieldConfig>[
      const _ManualFieldConfig(
        id: 'sma',
        label: 'Smartphones Agresor (SMA)',
        type: _ManualFieldType.number,
      ),
      const _ManualFieldConfig(
        id: 'smv',
        label: 'Smartphones Víctima (SMV)',
        type: _ManualFieldType.number,
      ),
      const _ManualFieldConfig(
        id: 'pulseras',
        label: 'Pulseras',
        type: _ManualFieldType.number,
      ),
      const _ManualFieldConfig(
        id: 'botones',
        label: 'Botones',
        type: _ManualFieldType.number,
      ),
      const _ManualFieldConfig(
        id: 'pw',
        label: 'PowerBanks (PW)',
        type: _ManualFieldType.number,
      ),
      const _ManualFieldConfig(
        id: 'referencia_envio',
        label: 'Referencia de envío',
        type: _ManualFieldType.text,
        isRequired: true,
      ),
    ];
    if (includeObservaciones) {
      fields.add(
        const _ManualFieldConfig(
          id: 'observaciones',
          label: 'Observaciones',
          type: _ManualFieldType.text,
          maxLines: 3,
        ),
      );
    }
    return fields;
  }

  Widget _buildManualOverrideCard({required bool compact}) {
    if (_manualConfigs.isEmpty || _selectedManualId == null) {
      return const SizedBox.shrink();
    }
    final config = _manualConfigs.firstWhere(
      (c) => c.id == _selectedManualId,
      orElse: () => _manualConfigs.first,
    );
    final theme = Theme.of(context);
    final decoration = BoxDecoration(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(compact ? 22 : 26),
      border: Border.all(
        color: theme.colorScheme.outline.withOpacity(0.1),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: theme.shadowColor.withOpacity(0.05),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ],
    );
    final EdgeInsets padding = EdgeInsets.fromLTRB(
      compact ? 20 : 28,
      compact ? 22 : 28,
      compact ? 20 : 28,
      compact ? 18 : 24,
    );

    return Container(
      decoration: decoration,
      padding: padding,
      child: Form(
        key: _manualFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Registrar ajustes manuales',
                        style: TextStyle(
                          fontSize: compact ? 18 : 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Estos datos se envían a los endpoints manuales para mantener actualizado el resumen semanal.',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: compact ? 12 : 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _manualSubmitting ? null : () => setState(() {}),
                  icon: const Icon(Icons.info_outline, color: Colors.black87),
                  tooltip: 'Los campos vacíos se envían como 0 o vacío.',
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedManualId,
              decoration: InputDecoration(
                labelText: 'Categoría',
                filled: true,
                fillColor: Colors.white.withOpacity(0.16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.22)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.22)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: theme.colorScheme.primary),
                ),
              ),
              items: _manualConfigs
                  .map(
                    (c) => DropdownMenuItem<String>(
                      value: c.id,
                      child: Text(c.label),
                    ),
                  )
                  .toList(),
              onChanged: _manualSubmitting
                  ? null
                  : (value) {
                      setState(() {
                        _selectedManualId = value;
                      });
                    },
            ),
            const SizedBox(height: 20),
            ...config.fields.map((field) {
              final controller = _manualControllers[field.id]!;
              final isNumber = field.type == _ManualFieldType.number;
              final inputDecoration = InputDecoration(
                labelText: field.label,
                filled: true,
                fillColor: Colors.white.withOpacity(0.14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: theme.colorScheme.primary),
                ),
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextFormField(
                  controller: controller,
                  keyboardType: isNumber
                      ? TextInputType.number
                      : TextInputType.text,
                  inputFormatters: isNumber
                      ? [FilteringTextInputFormatter.digitsOnly]
                      : null,
                  decoration: inputDecoration,
                  style: const TextStyle(color: Colors.black87),
                  maxLines: field.maxLines,
                  validator: (value) {
                    if (field.isRequired &&
                        (value == null || value.trim().isEmpty)) {
                      return 'Obligatorio';
                    }
                    if (isNumber &&
                        value != null &&
                        value.trim().isNotEmpty &&
                        int.tryParse(value.trim()) == null) {
                      return 'Número inválido';
                    }
                    return null;
                  },
                ),
              );
            }),
            Text(
              'Los campos numéricos vacíos se envían como 0. Agrega una referencia si necesitas rastrear el ajuste.',
              style: TextStyle(
                color: Colors.black.withOpacity(0.75),
                fontSize: compact ? 12 : 13,
              ),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _manualSubmitting ? null : _submitManualEntry,
                icon: _manualSubmitting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.onPrimary,
                          ),
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(_manualSubmitting ? 'Enviando…' : 'Registrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitManualEntry() async {
    if (_manualFormKey.currentState == null) return;
    if (!_manualFormKey.currentState!.validate()) return;
    if (_manualConfigs.isEmpty || _selectedManualId == null) return;
    final config = _manualConfigs.firstWhere(
      (c) => c.id == _selectedManualId,
      orElse: () => _manualConfigs.first,
    );
    final payload = <String, dynamic>{};
    for (final field in config.fields) {
      final text = _manualControllers[field.id]!.text.trim();
      if (field.type == _ManualFieldType.number) {
        payload[field.id] = text.isEmpty ? 0 : int.parse(text);
      } else {
        payload[field.id] = text;
      }
    }
    final hasNumeric = config.fields.any(
      (f) => f.type == _ManualFieldType.number,
    );
    if (hasNumeric) {
      final allZero = config.fields
          .where((f) => f.type == _ManualFieldType.number)
          .every((f) => (payload[f.id] as int) == 0);
      if (allZero) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Introduce al menos un valor numérico mayor que cero.',
            ),
          ),
        );
        return;
      }
    }

    FocusScope.of(context).unfocus();
    setState(() => _manualSubmitting = true);
    try {
      await config.submit(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registro enviado: ${config.label}')),
      );
      for (final field in config.fields) {
        _manualControllers[field.id]?.clear();
      }
      await _fetchResumen(fecha: _selectedWeekFecha);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al enviar ajuste: $e')));
    } finally {
      if (mounted) {
        setState(() => _manualSubmitting = false);
      }
    }
  }

  Widget _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final bool isDesktop = width >= 1400;
        final bool isMobile = width < 960;
        final bool compact = isMobile || width < 1100;

        final double gap = isDesktop ? 40 : 24;
        final double maxContentWidth = width;

        Widget dashboard;
        if (isDesktop) {
          final double available = maxContentWidth - gap;
          double chartWidth = available * 0.45;
          if (chartWidth < 480) {
            chartWidth = 480;
          }
          double tableWidth = available - chartWidth;
          if (tableWidth < 740) {
            tableWidth = 740;
            chartWidth = available - tableWidth;
          }
          final double chartBoxWidth = chartWidth.clamp(360.0, available);
          final double tableBoxWidth = tableWidth.clamp(600.0, available);
          dashboard = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: chartBoxWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSummaryCards(),
                        if (!loadingStock && errorStock == null && stockReal != null) ...[
                          const SizedBox(height: 24),
                          ResumenStock(
                            stockReal: stockReal,
                            idimActivoVals: idimActivoVals,
                            oystaActivoVals: oystaActivoVals,
                            idimCodigo: idimCodigo,
                            oystaCodigo: oystaCodigo,
                            irrecuperablesVals: irrecuperablesVals,
                          ),
                        ] else if (loadingStock) ...[
                          const SizedBox(height: 24),
                          const Center(child: CircularProgressIndicator()),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: gap),
                  SizedBox(
                    width: tableBoxWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildResumenTable(),
                        const SizedBox(height: 24),
                        _buildDeviceStatusCard(),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        } else {
          dashboard = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSummaryCards(compact: compact),
              SizedBox(height: gap),
              if (!loadingStock && errorStock == null && stockReal != null) ...[
                ResumenStock(
                  stockReal: stockReal,
                  idimActivoVals: idimActivoVals,
                  oystaActivoVals: oystaActivoVals,
                  idimCodigo: idimCodigo,
                  oystaCodigo: oystaCodigo,
                  irrecuperablesVals: irrecuperablesVals,
                ),
                SizedBox(height: gap),
              ] else if (loadingStock) ...[
                const Center(child: CircularProgressIndicator()),
                SizedBox(height: gap),
              ],
              _buildResumenTable(compact: compact || isMobile),
              SizedBox(height: gap),
              _buildDeviceStatusCard(compact: compact),
            ],
          );
        }

        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: dashboard,
        );
      },
    );
  }

  @override
  void dispose() {
    for (final controller in _manualControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Main Content
          Padding(
            padding: EdgeInsets.only(
              left: MediaQuery.of(context).size.width < 500 ? 12.0 : 60.0,
              top: 32,
              right: 28,
              bottom: 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 32),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      child: loading
                          ? _buildStatusCard(
                              child: const CircularProgressIndicator(),
                            )
                          : error != null
                          ? _buildStatusCard(
                              child: Text(
                                'Error: $error',
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : _buildContent(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Sidebar Handle
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: EdgeNavHandle(
                user: Provider.of<ApiService>(
                  context,
                  listen: false,
                ).currentUser,
                width: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
