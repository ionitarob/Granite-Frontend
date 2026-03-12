import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';

class AmzTransferStatusWidget extends StatefulWidget {
  final String wsUrl;
  AmzTransferStatusWidget({super.key, String? wsUrl})
    : wsUrl = wsUrl ?? ('$kBackendWebSocketBase/ws/amz/transfers/status');

  @override
  State<AmzTransferStatusWidget> createState() =>
      _AmzTransferStatusWidgetState();
}

class _AmzTransferStatusWidgetState extends State<AmzTransferStatusWidget> {
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  List<Map<String, dynamic>> _transfers = [];
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
          if (data is Map && data['type'] == 'amz.transfers') {
            final List<dynamic> records = data['records'] ?? [];
            setState(() {
              _transfers = records
                  .map((r) => Map<String, dynamic>.from(r))
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
                'Estado de Transferencias',
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
            child: _transfers.isEmpty
                ? const Center(
                    child: Text(
                      'Sin transferencias activas',
                      style: TextStyle(color: Colors.white24, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: _transfers.length,
                    padding: EdgeInsets.zero,
                    itemBuilder: (ctx, i) {
                      final t = _transfers[i];
                      return _buildTransferRow(t);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferRow(Map<String, dynamic> t) {
    final name = t['name_file'] ?? 'Unknown';
    final progress = (t['progress'] ?? 0.0).toDouble(); // 0.0 to 1.0
    final count = t['count'] ?? 0;
    final total = t['total'] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count/$total',
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: Colors.white10,
              color: progress >= 1.0 ? Colors.greenAccent : Colors.blueAccent,
            ),
          ),
        ],
      ),
    );
  }
}
