import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import 'sentinel_service.dart';

class SentinelStatsDashboard extends StatefulWidget {
  final SentinelService service;

  const SentinelStatsDashboard({Key? key, required this.service}) : super(key: key);

  @override
  _SentinelStatsDashboardState createState() => _SentinelStatsDashboardState();
}

class _SentinelStatsDashboardState extends State<SentinelStatsDashboard> {
  List<Map<String, dynamic>> _dailyStats = [];
  List<Map<String, dynamic>> _imageStats = [];
  bool _isLoading = true;
  String _error = '';
  int _days = 7;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final res = await widget.service.fetchStats(days: _days);
      if (mounted) {
        setState(() {
          _dailyStats = List<Map<String, dynamic>>.from(res['daily'] ?? []);
          _imageStats = List<Map<String, dynamic>>.from(res['images'] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
        ),
      );
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              'Error al cargar estadísticas',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadStats,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent.withOpacity(0.2),
                foregroundColor: Colors.cyanAccent,
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_dailyStats.isEmpty) {
      return Center(
        child: Text(
          'No hay datos de telemetría para los últimos $_days días',
          style: TextStyle(color: Colors.white.withOpacity(0.5)),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'MÉTRICAS DE PRODUCCIÓN',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  fontSize: 16,
                ),
              ),
              DropdownButton<int>(
                value: _days,
                dropdownColor: const Color(0xFF1E1E1E),
                style: const TextStyle(color: Colors.cyanAccent),
                underline: Container(),
                items: const [
                  DropdownMenuItem(value: 7, child: Text('Últimos 7 días')),
                  DropdownMenuItem(value: 14, child: Text('Últimos 14 días')),
                  DropdownMenuItem(value: 30, child: Text('Últimos 30 días')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _days = val);
                    _loadStats();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildOverviewCards(),
          const SizedBox(height: 24),
          _buildVolumeChart(),
          const SizedBox(height: 24),
          _buildTrendChart(
            title: 'TENDENCIA DE VELOCIDAD (Mbps)',
            color: Colors.cyanAccent,
            spots: _dailyStats.reversed.toList().asMap().entries.map((e) {
              return FlSpot(e.key.toDouble(), (e.value['avg_speed'] ?? 0.0).toDouble());
            }).toList(),
            yLabel: (val) => '${val.toInt()} Mb',
          ),
          const SizedBox(height: 24),
          _buildTrendChart(
            title: 'TASA DE ÉXITO (%)',
            color: Colors.greenAccent,
            spots: _dailyStats.reversed.toList().asMap().entries.map((e) {
              int total = (e.value['total'] as num).toInt();
              int success = (e.value['success'] as num).toInt();
              double rate = total > 0 ? (success / total) * 100 : 0;
              return FlSpot(e.key.toDouble(), rate);
            }).toList(),
            maxY: 100,
            yLabel: (val) => '${val.toInt()}%',
          ),
          const SizedBox(height: 24),
          _buildImageLeaderboard(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildImageLeaderboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RENDIMIENTO POR IMAGEN',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...(_imageStats.isEmpty 
          ? [Text('No hay datos por imagen', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10))]
          : _imageStats.map((img) => _buildImageCard(img)).toList()),
      ],
    );
  }

  Widget _buildImageCard(Map<String, dynamic> img) {
    final String name = img['name'] ?? 'Sin Imagen';
    final int total = img['total'] ?? 0;
    final int success = img['success'] ?? 0;
    final double successRate = (img['success_rate'] ?? 0).toDouble();
    final double? avgSpeed = img['avg_speed']?.toDouble();
    final double? avgDur = img['avg_duration_min']?.toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, overflow: TextOverflow.ellipsis),
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              _buildSimpleBadge(
                '${successRate.toStringAsFixed(1)}%',
                successRate > 90 ? Colors.greenAccent : (successRate > 70 ? Colors.amberAccent : Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInlineMetric('TOTAL', total.toString(), Icons.numbers),
              _buildInlineMetric('ÉXITO', success.toString(), Icons.check),
              if (avgSpeed != null) 
                _buildInlineMetric('VELOCIDAD', '${avgSpeed.toStringAsFixed(1)} Mb/s', Icons.speed),
              if (avgDur != null)
                _buildInlineMetric('DURACIÓN', '${avgDur.toStringAsFixed(1)} min', Icons.timer_outlined),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildInlineMetric(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 10, color: Colors.white.withOpacity(0.3)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildOverviewCards() {
    int total = 0;
    int success = 0;
    int failed = 0;
    List<double> durations = [];
    List<double> speeds = [];
    List<double> imageSizes = [];

    for (var s in _dailyStats) {
      total += (s['total'] as num).toInt();
      success += (s['success'] as num).toInt();
      failed += (s['failed'] as num).toInt();
      if (s['avg_duration_min'] != null) durations.add((s['avg_duration_min'] as num).toDouble());
      if (s['avg_speed'] != null) speeds.add((s['avg_speed'] as num).toDouble());
      if (s['avg_image_size_gb'] != null) imageSizes.add((s['avg_image_size_gb'] as num).toDouble());
    }

    double successRate = total > 0 ? (success / total) * 100 : 0;
    double? avgDuration = durations.isNotEmpty ? durations.reduce((a, b) => a + b) / durations.length : null;
    double? avgSpeed = speeds.isNotEmpty ? speeds.reduce((a, b) => a + b) / speeds.length : null;
    double? avgSize = imageSizes.isNotEmpty ? imageSizes.reduce((a, b) => a + b) / imageSizes.length : null;

    String _fmtDuration(double? mins) {
      if (mins == null) return 'N/D';
      if (mins < 60) return '${mins.toStringAsFixed(1)} min';
      return '${(mins / 60).toStringAsFixed(1)} h';
    }

    return Column(
      children: [
        // Row 1: Volume metrics
        Row(
          children: [
            Expanded(
              child: _buildGlassCard(
                title: 'TOTAL IMAGING',
                value: total.toString(),
                color: Colors.white,
                icon: Icons.computer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGlassCard(
                title: 'EXITOSOS',
                value: success.toString(),
                color: Colors.greenAccent,
                icon: Icons.check_circle_outline,
                subtitle: '${successRate.toStringAsFixed(1)}%',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGlassCard(
                title: 'FALLIDOS',
                value: failed.toString(),
                color: Colors.redAccent,
                icon: Icons.error_outline,
                subtitle: total > 0 ? '${(failed / total * 100).toStringAsFixed(1)}%' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Row 2: Performance metrics
        Row(
          children: [
            Expanded(
              child: _buildGlassCard(
                title: 'DURACIÓN MEDIA',
                value: _fmtDuration(avgDuration),
                color: Colors.amberAccent,
                icon: Icons.timer_outlined,
                subtitle: 'por equipo',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGlassCard(
                title: 'VELOCIDAD MEDIA',
                value: avgSpeed != null ? '${avgSpeed.toStringAsFixed(1)} MB/s' : 'N/D',
                color: Colors.cyanAccent,
                icon: Icons.speed_rounded,
                subtitle: avgSize != null ? '${avgSize.toStringAsFixed(1)} GB/img' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGlassCard(
                title: 'EFICIENCIA',
                value: (avgSpeed != null && avgSpeed > 0)
                    ? '${(136.53 / avgSpeed).toStringAsFixed(1)} min/GB'
                    : 'N/D',
                color: Colors.purpleAccent,
                icon: Icons.insights_rounded,
                subtitle: 'tiempo por GB',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGlassCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(icon, color: color, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: color.withOpacity(0.5),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVolumeChart() {
    return Container(
      height: 200,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VOLUMEN DIARIO',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _dailyStats.reversed.map((s) => _buildBar(s)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart({
    required String title,
    required Color color,
    required List<FlSpot> spots,
    double? maxY,
    required String Function(double) yLabel,
  }) {
    return Container(
      height: 200,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (val, meta) => Text(
                        yLabel(val),
                        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        int idx = val.toInt();
                        if (idx < 0 || idx >= _dailyStats.length) return const SizedBox();
                        DateTime date = DateTime.parse(_dailyStats.reversed.toList()[idx]['date']);
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            DateFormat('dd').format(date),
                            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8),
                          ),
                        );
                      },
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
                    color: color,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withOpacity(0.1),
                    ),
                  ),
                ],
                maxY: maxY,
                minY: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBar(Map<String, dynamic> stat) {
    int total = (stat['total'] as num).toInt();
    // int success = (stat['success'] as num).toInt();
    // int failed = (stat['failed'] as num).toInt();

    // Max height in data for scaling
    double maxVal = _dailyStats.map((e) => (e['total'] as num).toDouble()).reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) maxVal = 1;

    double heightRatio = total / maxVal;
    
    DateTime date = DateTime.parse(stat['date']);
    String label = DateFormat('dd/MM').format(date);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          total.toString(),
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
        const SizedBox(height: 4),
        Container(
          width: 20,
          height: 100 * heightRatio,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.cyanAccent.withOpacity(0.3),
                Colors.cyanAccent,
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8),
        ),
      ],
    );
  }
}
