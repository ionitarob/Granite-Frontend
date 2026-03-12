import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import 'package:intl/intl.dart';

class AmzRecentInventoryWidget extends StatefulWidget {
  final String wsUrl;
  AmzRecentInventoryWidget({super.key, String? wsUrl})
    : wsUrl = wsUrl ?? ('$kBackendWebSocketBase/ws/amz/inventory/logs');

  @override
  State<AmzRecentInventoryWidget> createState() =>
      _AmzRecentInventoryWidgetState();
}

class _AmzRecentInventoryWidgetState extends State<AmzRecentInventoryWidget> {
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  List<Map<String, dynamic>> _logs = [];
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
          if (data is Map && data['type'] == 'amz.inventory.logs') {
            final List<dynamic> rawLogs = data['logs'] ?? [];
            setState(() {
              _logs = rawLogs
                  .take(10)
                  .map((l) => Map<String, dynamic>.from(l))
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Actividad Reciente',
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
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      'Sin actividad',
                      style: TextStyle(color: Colors.white30, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: _logs.length,
                    padding: EdgeInsets.zero,
                    itemBuilder: (ctx, i) {
                      final log = _logs[i];
                      return _buildLogItem(log);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    final action = log['action'] ?? 'Unknown';
    final user = log['user'] ?? 'Bot';
    final dateStr = log['date'] != null
        ? DateFormat('HH:mm').format(DateTime.parse(log['date']))
        : '--:--';

    IconData icon;
    Color color;

    if (action.contains('Grading')) {
      icon = Icons.assignment_turned_in_outlined;
      color = Colors.greenAccent;
    } else if (action.contains('Sorting')) {
      icon = Icons.move_to_inbox_outlined;
      color = Colors.orangeAccent;
    } else if (action.contains('Adjustment')) {
      icon = Icons.settings_backup_restore_outlined;
      color = Colors.redAccent;
    } else {
      icon = Icons.swap_horiz_outlined;
      color = Colors.blueAccent;
    }

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(icon, size: 14, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    user,
                    style: const TextStyle(fontSize: 9, color: Colors.white38),
                  ),
                ],
              ),
            ),
            Text(
              dateStr,
              style: const TextStyle(fontSize: 10, color: Colors.white24),
            ),
          ],
        ),
      ),
    );
  }
}
