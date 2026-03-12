import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';

class AmzQualityGaugeWidget extends StatefulWidget {
  final String wsUrl;
  AmzQualityGaugeWidget({super.key, String? wsUrl})
    : wsUrl = wsUrl ?? ('$kBackendWebSocketBase/ws/amz/stats/quality');

  @override
  State<AmzQualityGaugeWidget> createState() => _AmzQualityGaugeWidgetState();
}

class _AmzQualityGaugeWidgetState extends State<AmzQualityGaugeWidget> {
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  double _qualityIndex = 0.0;
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
          if (data is Map && data['type'] == 'amz.quality') {
            setState(() {
              _qualityIndex = (data['index'] ?? 0.0).toDouble();
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
                'Índice Calidad',
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
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: ExcludeSemantics(
                    child: CustomPaint(
                      painter: _GaugePainter(
                        value: _qualityIndex,
                        color: _getQualityColor(
                          _qualityIndex > 1.0
                              ? _qualityIndex / 100.0
                              : _qualityIndex,
                        ),
                        backgroundColor: Colors.white10,
                      ),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _qualityIndex > 1.0
                          ? '${_qualityIndex.toStringAsFixed(1)}%'
                          : '${(_qualityIndex * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'Sitio',
                      style: TextStyle(fontSize: 10, color: Colors.white54),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getQualityColor(double value) {
    if (value >= 0.98) return Colors.greenAccent;
    if (value >= 0.95) return Colors.blueAccent;
    if (value >= 0.90) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  final Color backgroundColor;

  _GaugePainter({
    required this.value,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width / 2, size.height / 2);
    final strokeWidth = 10.0;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      -math.pi * 1.25,
      math.pi * 1.5,
      false,
      bgPaint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      -math.pi * 1.25,
      math.pi * 1.5 * (value > 1.0 ? value / 100.0 : value).clamp(0.0, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
