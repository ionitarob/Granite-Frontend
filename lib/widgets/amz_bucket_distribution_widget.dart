import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';

class AmzBucketDistributionWidget extends StatefulWidget {
  final String wsUrl;
  AmzBucketDistributionWidget({super.key, String? wsUrl})
    : wsUrl = wsUrl ?? ('$kBackendWebSocketBase/ws/amz/stats/buckets');

  @override
  State<AmzBucketDistributionWidget> createState() =>
      _AmzBucketDistributionWidgetState();
}

class _AmzBucketDistributionWidgetState
    extends State<AmzBucketDistributionWidget> {
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Map<String, int> _counts = {};
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
          if (data is Map && data['type'] == 'amz.buckets') {
            final Map<String, dynamic> rawCounts = data['counts'] ?? {};
            setState(() {
              _counts = rawCounts.map(
                (key, value) => MapEntry(key, value as int),
              );
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

  Color _getColor(String bucket) {
    switch (bucket.toUpperCase()) {
      case 'PRIME':
        return Colors.greenAccent;
      case 'WOOT':
        return Colors.orangeAccent;
      case 'VAS':
        return Colors.blueAccent;
      case 'RETURN':
        return Colors.amberAccent;
      case 'RECYCLE':
        return Colors.redAccent;
      case 'RECYCLE DISCONTINUED':
        return Colors.purpleAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_counts.isEmpty) {
      return _buildContainer(
        child: const Center(
          child: Text(
            'Esperando datos...',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    final total = _counts.values.fold(0, (sum, v) => sum + v);
    final sections = _counts.entries.map((e) {
      final percentage = total > 0 ? (e.value / total) * 100 : 0.0;
      return PieChartSectionData(
        color: _getColor(e.key),
        value: e.value.toDouble(),
        title: '${percentage.toStringAsFixed(0)}%',
        radius: 40,
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();

    return _buildContainer(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Distribución Buckets',
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
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 140,
                    child: ExcludeSemantics(
                      child: PieChart(
                        PieChartData(
                          sections: sections,
                          centerSpaceRadius: 35,
                          sectionsSpace: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _counts.keys
                          .map((k) => _buildLegendItem(k))
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _getColor(label),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 9, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContainer({required Widget child}) {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: child,
    );
  }
}
