import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';

/// Grading Hoy widget: connects to /ws/amz/today and displays today's count.
class GradingHoyWidget extends StatefulWidget {
  final String wsUrl;

  GradingHoyWidget({Key? key, String? wsUrl}) : wsUrl = wsUrl ?? ('$kBackendWebSocketBase/ws/amz/today'), super(key: key);

  @override
  State<GradingHoyWidget> createState() => _GradingHoyWidgetState();
}

class _GradingHoyWidgetState extends State<GradingHoyWidget> {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  int? _count;
  String? _status;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    final raw = widget.wsUrl.trim();
    var sanitized = raw.split('#').first;
    if (sanitized.startsWith('http://')) sanitized = sanitized.replaceFirst('http://', 'ws://');
    if (sanitized.startsWith('https://')) sanitized = sanitized.replaceFirst('https://', 'wss://');
    developer.log('GradingHoyWidget connecting to: $sanitized');
    try {
      _channel = WebSocketChannel.connect(Uri.parse(sanitized));
      _status = 'connected';
      _reconnectAttempts = 0;
      _sub = _channel!.stream.listen((message) {
        try {
          final data = json.decode(message.toString());
          if (data is Map && data['type'] == 'amz.today') {
            final c = data['count'];
            if (c is int) setState(() => _count = c);
            else if (c is String) setState(() => _count = int.tryParse(c));
          }
        } catch (e, st) {
          developer.log('GradingHoyWidget parse error: $e', stackTrace: st);
        }
      }, onError: (err, st) {
        developer.log('GradingHoyWidget stream error: $err', stackTrace: st);
        setState(() => _status = 'disconnected');
        _scheduleReconnect();
      }, onDone: () {
        developer.log('GradingHoyWidget stream closed');
        setState(() => _status = 'disconnected');
        _scheduleReconnect();
      });
    } catch (e, st) {
      developer.log('GradingHoyWidget failed to connect: $e', stackTrace: st);
      setState(() => _status = 'disconnected');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectAttempts++;
    final delaySeconds = math.min(30, math.pow(2, math.min(6, _reconnectAttempts)).toInt());
    developer.log('GradingHoyWidget scheduling reconnect in ${delaySeconds}s (attempt $_reconnectAttempts)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted) _connect();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reconnectTimer?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.cardColor.withAlpha(31),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Grading Hoy', style: TextStyle(color: theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(_count != null ? _count.toString() : '--', style: TextStyle(color: theme.colorScheme.primary, fontSize: 20, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(width: 16),
            Column(
              children: [
                Icon(_status == 'connected' ? Icons.circle : Icons.circle_outlined, color: _status == 'connected' ? Colors.greenAccent : Colors.redAccent, size: 14),
                const SizedBox(height: 6),
                Text(_status == 'connected' ? 'Live' : 'Disconnected', style: TextStyle(color: theme.textTheme.bodySmall?.color ?? theme.colorScheme.onSurface.withAlpha(179), fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
