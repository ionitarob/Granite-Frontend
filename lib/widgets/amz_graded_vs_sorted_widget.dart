import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';

class AmzGradedVsSortedWidget extends StatefulWidget {
  final String wsUrl;
  AmzGradedVsSortedWidget({super.key, String? wsUrl})
    : wsUrl = wsUrl ?? ('$kBackendWebSocketBase/ws/amz/stats/performance');

  @override
  State<AmzGradedVsSortedWidget> createState() =>
      _AmzGradedVsSortedWidgetState();
}

class _AmzGradedVsSortedWidgetState extends State<AmzGradedVsSortedWidget> {
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  List<Map<String, dynamic>> _data = [];
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    final raw = widget.wsUrl.trim();
    var sanitized = raw.split('#').first;
    if (sanitized.startsWith('http://'))
      sanitized = sanitized.replaceFirst('http://', 'ws://');
    if (sanitized.startsWith('https://'))
      sanitized = sanitized.replaceFirst('https://', 'wss://');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(sanitized));
      _sub = _channel!.stream.listen(
        (message) {
          _reconnectAttempts = 0;
          final data = json.decode(message.toString());
          if (data is Map && data['type'] == 'amz.performance') {
            final List<dynamic> hourlyData = data['hourly'] ?? [];
            setState(() {
              _data = hourlyData
                  .map((d) => Map<String, dynamic>.from(d))
                  .toList();
              _isConnected = true;
            });
          }
        },
        onError: (_) => _handleDisconnect(),
        onDone: () => _handleDisconnect(),
      );
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    if (!mounted) return;
    setState(() {
      _isConnected = false;
    });
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: 5), () {
      if (mounted) _connect();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rendimiento (Graded vs Sorted)',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Icon(
                Icons.circle,
                color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                size: 8,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _data.isEmpty
                ? const Center(
                    child: Text(
                      'Cargando historial...',
                      style: TextStyle(color: Colors.white24, fontSize: 12),
                    ),
                  )
                : SizedBox(
                    height: 130,
                    child: ExcludeSemantics(
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: _getMaxValue() * 1.2,
                          barTouchData: BarTouchData(enabled: true),
                          titlesData: FlTitlesData(
                            show: true,
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (v, meta) {
                                  if (v.toInt() >= 0 &&
                                      v.toInt() < _data.length) {
                                    return Text(
                                      _data[v.toInt()]['hour'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 8,
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          barGroups: _data.asMap().entries.map((entry) {
                            return BarChartGroupData(
                              x: entry.key,
                              barRods: [
                                BarChartRodData(
                                  toY: (entry.value['graded'] ?? 0).toDouble(),
                                  color: Colors.greenAccent,
                                  width: 6,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                BarChartRodData(
                                  toY: (entry.value['sorted'] ?? 0).toDouble(),
                                  color: Colors.orangeAccent,
                                  width: 6,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegend('Graded', Colors.greenAccent),
              const SizedBox(width: 12),
              _buildLegend('Sorted', Colors.orangeAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.white54),
        ),
      ],
    );
  }

  double _getMaxValue() {
    double max = 1;
    for (final d in _data) {
      if ((d['graded'] ?? 0) > max) max = (d['graded'] as int).toDouble();
      if ((d['sorted'] ?? 0) > max) max = (d['sorted'] as int).toDouble();
    }
    return max;
  }
}
