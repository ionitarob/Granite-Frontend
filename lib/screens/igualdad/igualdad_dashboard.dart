import 'dart:convert';

import 'package:configtool_granite_frontend/config.dart';
import 'package:configtool_granite_frontend/src/api/igualdad_api.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:configtool_granite_frontend/services/api_service.dart';

import '../../widgets/main_sidebar.dart';

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
  const IgualdadDashboard({Key? key}) : super(key: key);

  @override
  State<IgualdadDashboard> createState() => _IgualdadDashboardState();
}

class _IgualdadDashboardState extends State<IgualdadDashboard> {
  List<Map<String, dynamic>> dailyStats = [];
  bool loadingStats = true;
  String? errorStats;

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

  Future<void> _fetchDailyStats() async {
    setState(() {
      loadingStats = true;
      errorStats = null;
    });
    try {
      final svc = ApiService.instance;
      if (svc != null) {
        final res = await svc.client.get(
          '/igualdad/estadisticas/entradas_diarias',
        );
        if (!mounted) return;
        if (res.ok && res.body is List) {
          final data = (res.body as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          setState(() {
            dailyStats = data
                .map((e) => {"fecha": e["fecha"], "total": e["total"]})
                .toList();
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
        Uri.parse('$kBackendBaseUrl/igualdad/estadisticas/entradas_diarias'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          dailyStats = data
              .map((e) => {"fecha": e["fecha"], "total": e["total"]})
              .toList();
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

  Widget _buildDailyStatsChart({bool compact = false}) {
    final BorderRadius borderRadius = BorderRadius.circular(compact ? 22 : 26);
    final EdgeInsets padding = EdgeInsets.fromLTRB(
      compact ? 20 : 28,
      compact ? 22 : 28,
      compact ? 20 : 28,
      compact ? 18 : 22,
    );
    final double chartHeight = compact ? 230 : 280;
    final double titleFontSize = compact ? 18 : 20;
    final double subtitleFontSize = compact ? 12 : 13;
    final double axisFontSize = compact ? 11 : 12;
    final double bottomFontSize = compact ? 10 : 11;

    final decoration = BoxDecoration(
      color: Theme.of(context).cardColor.withOpacity(0.9),
      borderRadius: borderRadius,
      border: Border.all(
        color: Theme.of(context).dividerColor.withOpacity(0.1),
        width: 1.4,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 18,
          offset: const Offset(0, 6),
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
    if (dailyStats.isEmpty) {
      return Container(
        decoration: decoration,
        padding: EdgeInsets.symmetric(
          vertical: compact ? 28 : 40,
          horizontal: compact ? 24 : 32,
        ),
        alignment: Alignment.center,
        child: Text(
          'No hay datos de registros diarios.',
          style: TextStyle(
            fontSize: compact ? 14 : 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
      );
    }

    final spots = dailyStats.asMap().entries.map((entry) {
      final index = entry.key;
      final value = entry.value;
      return FlSpot(index.toDouble(), (value['total'] as num).toDouble());
    }).toList();
    final labels = dailyStats.map((e) => e['fecha'] as String).toList();
    final double highestY = spots.fold<double>(
      0,
      (max, spot) => spot.y > max ? spot.y : max,
    );
    final double topPadding = highestY == 0 ? 4 : highestY * 1.25;
    final double average = spots.isEmpty
        ? 0
        : spots.map((spot) => spot.y).reduce((a, b) => a + b) / spots.length;

    return Container(
      decoration: decoration,
      padding: padding,
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
                      'Registros diarios (últimos 7 días)',
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${labels.first} a ${labels.last}',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                        fontSize: subtitleFontSize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                width: 36,
                child: IconButton(
                  onPressed: _fetchDailyStats,
                  tooltip: 'Actualizar gráfico',
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: Theme.of(context).iconTheme.color,
                  ),
                  iconSize: compact ? 22 : 24,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 14 : 18),
          SizedBox(
            height: chartHeight,
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    // tooltipBgColor: Colors.black.withOpacity(0.75),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final dateLabel = labels[spot.spotIndex];
                        final total = spot.y.toStringAsFixed(0);
                        return LineTooltipItem(
                          '$dateLabel\n$total registros',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  verticalInterval: 1,
                  horizontalInterval: highestY <= 5 ? 1 : null,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Theme.of(context).dividerColor.withOpacity(0.2),
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: Theme.of(context).dividerColor.withOpacity(0.1),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: compact ? 36 : 42,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            fontSize: axisFontSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: compact ? 36 : 44,
                      getTitlesWidget: (value, meta) {
                        final int index = value.toInt();
                        if (index < 0 || index >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        final label = labels[index].substring(5);
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Transform.rotate(
                            angle: compact ? -0.35 : -0.4,
                            child: Text(
                              label,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.color,
                                fontSize: bottomFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (spots.length - 1).toDouble(),
                minY: 0,
                maxY: topPadding,
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (average > 0)
                      HorizontalLine(
                        y: average,
                        color: Theme.of(context).dividerColor.withOpacity(0.5),
                        strokeWidth: 1.5,
                        dashArray: const [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          padding: const EdgeInsets.only(left: 8),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).textTheme.bodySmall?.color?.withOpacity(0.7),
                            fontSize: compact ? 11 : 12,
                            fontWeight: FontWeight.w600,
                          ),
                          alignment: Alignment.topLeft,
                          labelResolver: (_) => 'Promedio',
                        ),
                      ),
                  ],
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.secondary,
                      ],
                    ),
                    barWidth: compact ? 3 : 4,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, p, barData, index) {
                        return FlDotCirclePainter(
                          radius: compact ? 3.4 : 4,
                          color: Colors.white,
                          strokeColor: Theme.of(context).colorScheme.primary,
                          strokeWidth: compact ? 1.8 : 2,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.secondary,
                        ].map((c) => c.withOpacity(0.14)).toList(),
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: compact ? 12 : 18),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: compact ? WrapAlignment.center : WrapAlignment.start,
            children: [
              _buildLegendChip(
                Theme.of(context).colorScheme.primary,
                'Total de entradas',
                compact: compact,
              ),
              Text(
                'Promedio diario: ${average.toStringAsFixed(1)}',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 12 : 14,
                ),
              ),
              if (highestY > 0)
                Text(
                  'Pico máximo: ${highestY.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                    fontWeight: FontWeight.w600,
                    fontSize: compact ? 12 : 14,
                  ),
                ),
            ],
          ),
        ],
      ),
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
    _fetchDailyStats();
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
        selectedObs = rawObs == null ? null : rawObs.toString();
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
        resumenObs = rawObs == null ? null : rawObs.toString();
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
      obsSeleccionada = rawObs == null ? null : rawObs.toString();
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
      color: Colors.white.withOpacity(0.20),
      borderRadius: BorderRadius.circular(compact ? 22 : 26),
      border: Border.all(color: Colors.white.withOpacity(0.16), width: 1.4),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 18,
          offset: const Offset(0, 6),
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
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$fechaInicio  ·  $fechaFin',
                      style: TextStyle(
                        color: Colors.grey[700],
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
                'Serigrafía pulseras: ${servicios['serigrafia_pulseras'] ?? 0}',
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
  ) {
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
        4: IntrinsicColumnWidth(),
        5: IntrinsicColumnWidth(),
        6: IntrinsicColumnWidth(),
        7: IntrinsicColumnWidth(),
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
                  child: Text(
                    cells[idx] == null ? '' : cells[idx].toString(),
                    style: TextStyle(
                      color: idx == 0 ? Colors.black : Colors.black87,
                      fontWeight: idx == 0 ? FontWeight.w700 : FontWeight.w500,
                      fontSize: compact ? 13 : 14,
                    ),
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
          color: Colors.white.withOpacity(0.28),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.5),
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
      color: Colors.white.withOpacity(0.20),
      borderRadius: BorderRadius.circular(compact ? 22 : 26),
      border: Border.all(color: Colors.white.withOpacity(0.16), width: 1.4),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 18,
          offset: const Offset(0, 6),
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
              value: _selectedManualId,
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

  Widget _buildDashboardLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final bool isDesktop = width >= 1400;
        final bool isTablet = width >= 960 && width < 1400;
        final bool isMobile = width < 960;
        final bool compact = isMobile || width < 1100;

        final double gap = isDesktop ? 40 : 24;
        final double maxContentWidth = width;
        final EdgeInsets verticalPadding = EdgeInsets.symmetric(
          vertical: isDesktop
              ? 36
              : isTablet
              ? 28
              : 20,
        );

        Widget dashboard;
        final manualCard = _manualConfigs.isEmpty
            ? const SizedBox.shrink()
            : _buildManualOverrideCard(compact: compact || isMobile);
        if (isDesktop) {
          final double available = maxContentWidth - gap;
          double chartWidth = available * 0.34;
          if (chartWidth < 420) {
            chartWidth = 420;
          }
          double tableWidth = available - chartWidth;
          if (tableWidth < 820) {
            tableWidth = 820;
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
                    child: _buildDailyStatsChart(),
                  ),
                  SizedBox(width: gap),
                  SizedBox(width: tableBoxWidth, child: _buildResumenTable()),
                ],
              ),
              if (_manualConfigs.isNotEmpty) ...[
                SizedBox(height: gap),
                _buildManualOverrideCard(compact: false),
              ],
            ],
          );
        } else {
          dashboard = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDailyStatsChart(compact: compact),
              SizedBox(height: gap),
              _buildResumenTable(compact: compact || isMobile),
              if (_manualConfigs.isNotEmpty) ...[
                SizedBox(height: gap),
                manualCard,
              ],
            ],
          );
        }

        return Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: verticalPadding,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: dashboard,
            ),
          ),
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
    final Size screenSize = MediaQuery.of(context).size;
    final bool compactSafeArea = screenSize.width < 720;
    final EdgeInsets safePadding = EdgeInsets.symmetric(
      horizontal: compactSafeArea ? 16 : 24,
      vertical: compactSafeArea ? 16 : 24,
    );
    final List<List<Color>> _gradients = [
      [Colors.deepPurple, Colors.purple],
      [Colors.purple, Colors.indigo],
      [Colors.indigo, Colors.blue],
      [Colors.blue, Colors.teal],
    ];
    int _currentGradient = DateTime.now().second % _gradients.length;
    final gradient = _gradients[_currentGradient];
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const EdgeNavHandle(),
        title: const Text(
          'Dashboard Igualdad',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _fetchSemanas(refreshResumen: true);
              _fetchDailyStats();
            },
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedContainer(
            duration: const Duration(seconds: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  gradient[0].withOpacity(0.92),
                  gradient[1].withOpacity(0.92),
                  const Color(0xFFB388FF).withOpacity(0.8),
                  const Color(0xFF80DEEA).withOpacity(0.8),
                ],
                stops: const [0.0, 0.5, 0.8, 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(),
          ),
          SafeArea(
            child: Padding(
              padding: safePadding,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                child: loading
                    ? _buildStatusCard(child: const CircularProgressIndicator())
                    : error != null
                    ? _buildStatusCard(
                        child: Text(
                          'Error: $error',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : _buildDashboardLayout(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
