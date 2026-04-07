import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../../services/api_service.dart';
import 'sentinel_models.dart';

class SentinelService {
  final String _wsUrl = 'ws://10.20.31.10:7000/ws/sentinel/merged/';
  final String _chatWsUrl = 'ws://10.20.31.70:8080/chat';

  WebSocketChannel? _channel;
  WebSocketChannel? _chatChannel;

  // Dynamic Run Sockets
  final Map<String, WebSocketChannel> _runSockets = {};
  final StreamController<dynamic> _telemetryController =
      StreamController<dynamic>.broadcast();
  Timer? _pollingTimer;
  Timer? _pingTimer;
  DateTime _lastPongAt = DateTime.fromMillisecondsSinceEpoch(0);

  final StreamController<SentinelEvent> _eventController =
      StreamController<SentinelEvent>.broadcast();
  final StreamController<String> _chatController =
      StreamController<String>.broadcast();
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  Stream<SentinelEvent> get eventStream => _eventController.stream;
  Stream<String> get chatStream => _chatController.stream;
  Stream<dynamic> get telemetryStream => _telemetryController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  void connect() {
    _connectEventSocket();
    _connectChatSocket();
    // _startPolling(); // Removed as per request
  }

  Future<void> _connectEventSocket() async {
    try {
      final sanitizedUrl = _wsUrl.trim();
      print('Connecting to Sentinel WS: $sanitizedUrl');

      // Force refresh if token is expired or about to expire
      final api = ApiService.instance;
      if (api != null && api.client.isTokenExpired(bufferSeconds: 300)) {
        print('Event Socket: Token close to expiry. Refreshing...');
        await api.refreshAccessToken();
      }

      final token = ApiService.instance?.client.accessToken;
      print(
        'SENTINEL_SERVICE: ApiService.instance is available: ${ApiService.instance != null}',
      );

      final Map<String, dynamic> headers = {};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      } else {
        print(
          'SENTINEL_SERVICE: WARNING - No access token available for WebSocket',
        );
      }

      // Cancel any pending reconnect timer if we successfully connected
      _reconnectTimer?.cancel();
      _reconnectAttempts = 0;

      _channel = IOWebSocketChannel.connect(
        Uri.parse(sanitizedUrl),
        headers: headers,
        pingInterval: const Duration(seconds: 30), // Keep-alive every 30s
      );

      // Ask for inventory once (compat)
      try {
        _channel!.sink.add(jsonEncode({"action": "get_inventory"}));
      } catch (e) {
        print('Error sending initial inventory request: $e');
      }

      bool _hasReceivedFirstMessage = false;

      _channel!.stream.listen(
        (message) {
          if (!_hasReceivedFirstMessage) {
            _hasReceivedFirstMessage = true;
            _isConnected = true;
            _connectionStatusController.add(true);
          }

          try {
            // Handle "UPDATE RECEIVED:" prefix if present
            String rawMessage = message.toString();
            dynamic data;
            if (rawMessage.startsWith('UPDATE RECEIVED:')) {
              final jsonPart = rawMessage
                  .substring('UPDATE RECEIVED:'.length)
                  .trim();
              data = jsonDecode(jsonPart);
            } else {
              data = jsonDecode(message);
            }

            if (data is Map && data['type'] == 'pong') {
              _lastPongAt = DateTime.now();
              return;
            }

            data = _unwrap(data); // ✅ NEW: Normalize first!

            _handleNewEvent(data);

            // CHECK FOR ACTIVE RUN (Robust Multi-Support)
            if (data is Map) {
              final Map<String, dynamic> devicesToProcess = {};

              // Safe Map access
              if (data.containsKey('devices')) {
                devicesToProcess.addAll(
                  Map<String, dynamic>.from(data['devices']),
                );
              } else if (data['type'] == 'device_update' &&
                  data['data'] is Map) {
                devicesToProcess['single'] = data['data'];
              } else if (data.containsKey('active_run_id')) {
                devicesToProcess['single'] = data;
              } else {
                // ESSENTIAL: Check if it's a raw MAC map (e.g. the initial snapshot)
                data.forEach((pk, pv) {
                  if (pv is Map &&
                      (pv.containsKey('active_run_id') ||
                          pv.containsKey('imaging_progress'))) {
                    devicesToProcess[pk] = pv;
                  }
                });
              }

              devicesToProcess.forEach((key, info) {
                if (info is Map) {
                  final runId =
                      info['active_run_id']?.toString() ??
                      info['run_id']?.toString();
                  if (runId != null && runId.isNotEmpty) {
                    final lowRunId = runId.toLowerCase();
                    if (!_runSockets.containsKey(lowRunId)) {
                      _connectRunSocket(runId);
                    }
                  }
                }
              });
            }
          } catch (e) {
            print('Error parsing event: $e');
          }
        },
        onError: (error) {
          print('WebSocket Error: $error');
          _hasReceivedFirstMessage = false;
          _isConnected = false;
          _connectionStatusController.add(false);
          _scheduleReconnect();
        },
        onDone: () {
          print('WebSocket Closed (Done)');
          _hasReceivedFirstMessage = false;
          _isConnected = false;
          _connectionStatusController.add(false);
          _scheduleReconnect();
        },
      );

      _startKeepAlive();
    } catch (e) {
      print('Connection Error: $e');
      _isConnected = false;
      _connectionStatusController.add(false);
      _scheduleReconnect();
    }
  }

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  void _scheduleReconnect() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;

    // Exponential backoff: 2s, 4s, 8s, 16s... max 30s
    int delaySeconds = 2 * (1 << _reconnectAttempts);
    if (delaySeconds > 30) delaySeconds = 30;

    print(
      'Scheduling WebSocket reconnect in ${delaySeconds}s (Attempt ${_reconnectAttempts + 1})...',
    );

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _reconnectAttempts++;
      _connectEventSocket();
    });
  }

  void _startKeepAlive() {
    _pingTimer?.cancel();
    _lastPongAt = DateTime.now();

    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_channel == null) return;

      // Check timeout
      if (DateTime.now().difference(_lastPongAt).inSeconds > 60) {
        print('WebSocket Keep-Alive Timeout. Reconnecting...');
        _channel?.sink.close();
        _isConnected = false;
        _connectionStatusController.add(false);
        _scheduleReconnect();
        _pingTimer?.cancel();
        return;
      }

      // Send Ping
      try {
        _channel!.sink.add(jsonEncode({"action": "ping"}));
      } catch (e) {
        print('Error sending ping: $e');
      }
    });
  }

  Future<void> _connectRunSocket(String rawRunId) async {
    final runId = rawRunId.toLowerCase(); // Enforce lowercase
    if (_runSockets.containsKey(runId)) return;

    // Force refresh if token is expired or about to expire (buffer 5 mins)
    final api = ApiService.instance;
    if (api != null && api.client.isTokenExpired(bufferSeconds: 300)) {
      print('Token close to expiry. Refreshing before WebSocket connection...');
      await api.refreshAccessToken();
    }

    // Try both header and query param (belt and suspenders)
    final token = ApiService.instance?.client.accessToken ?? '';
    // Removed token from URL print for security
    // final url = 'ws://10.20.31.10:7000/ws/runs/$runId/?token=$token';
    final url = 'ws://10.20.31.10:7000/ws/runs/$runId/?token=$token';

    try {
      final Map<String, dynamic> headers = {};
      if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

      final channel = IOWebSocketChannel.connect(
        Uri.parse(url),
        headers: headers,
      );
      _runSockets[runId] = channel;

      channel.stream.listen(
        (message) {
          try {
            final event = jsonDecode(message);
            if (event is Map) {
              event['run_id'] = runId;

              // AUTO-CLEANUP: If imaging is finished or failed, we can close the socket
              final payload = event['payload'];
              if (payload is Map) {
                final stage = (payload['stage']?.toString() ?? "")
                    .toUpperCase();
                if (stage == 'FINISHED' || stage == 'FAILED') {
                  print(
                    "WS_CLEANUP: Closing run socket $runId because stage=$stage",
                  );
                  _runSockets[runId]?.sink.close();
                  _runSockets.remove(runId);
                }
              }
            }
            _telemetryController.add(event);
          } catch (e) {
            print('Error parsing telemetry: $e');
          }
        },
        onDone: () async {
          final code = channel.closeCode;
          final reason = channel.closeReason;
          print("Run Socket $runId Closed. Code: $code, Reason: $reason");
          _runSockets.remove(runId);
        },
        onError: (e) {
          print("Run Socket $runId Error: $e");
          _runSockets.remove(runId);
        },
      );
    } catch (e) {
      print("Run Socket Connection Error: $e");
    }
  }

  bool _looksLikeMacKey(String k) =>
      RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(k) ||
      RegExp(r'^([0-9a-fA-F]{2}[:\-]){5}[0-9a-fA-F]{2}$').hasMatch(k);

  dynamic _unwrap(dynamic data) {
    if (data is! Map) return data;
    // Channels group_send wraps payload in {type: "event.message", message: ...}
    if (data['type'] == 'event.message' && data['message'] != null) {
      dynamic inner = data['message'];
      if (inner is String) {
        try {
          inner = jsonDecode(inner);
        } catch (_) {}
      }
      // Recursive unwrap? No, usually one level is enough, but safe to call again if needed.
      // For now, return inner.
      return inner;
    }
    return data;
  }

  void _handleNewEvent(dynamic data) {
    if (data is List) {
      _eventController.add(
        SentinelEvent(
          type: 'devices_update',
          message: 'Device list updated',
          timestamp: DateTime.now(),
          data: {'devices': data},
        ),
      );
      return;
    }

    if (data is! Map) return;
    // Safe cast to Map<String, dynamic>
    final map = Map<String, dynamic>.from(data);

    // ✅ NEW: backend monitor events come as {event_type: "..."} not {type: "..."}
    if (!map.containsKey('type') && map.containsKey('event_type')) {
      final t = map['event_type']?.toString() ?? 'event';
      _eventController.add(
        SentinelEvent(
          type: t,
          message: 'Monitor event: $t',
          timestamp: DateTime.now(),
          data: map, // includes mac + port_info
          mac: map['mac']?.toString(),
        ),
      );
      return;
    }

    // Existing: raw map of MAC -> device
    if (!map.containsKey('type')) {
      final keys = map.keys.toList();
      final macLike = keys.isNotEmpty && keys.every(_looksLikeMacKey);

      if (macLike) {
        // ✅ OPTIMIZATION: Emit SINGLE batch event instead of loop
        _eventController.add(
          SentinelEvent(
            type: 'devices_update', // Provider handles this as batch
            message: 'Bulk device update',
            timestamp: DateTime.now(),
            data: {'devices': map},
          ),
        );
        return;
      }

      // ✅ IMPORTANT: don’t silently ignore unknown messages anymore
      _eventController.add(
        SentinelEvent(
          type: 'event',
          message: 'Unclassified WS message',
          timestamp: DateTime.now(),
          data: map,
        ),
      );
      return;
    }

    // Normal typed events
    final event = SentinelEvent.fromJson(map);
    _eventController.add(event);
  }

  Future<void> _connectChatSocket() async {
    try {
      final sanitizedUrl = _chatWsUrl.trim();

      // Force refresh if token is expired or about to expire
      final api = ApiService.instance;
      if (api != null && api.client.isTokenExpired(bufferSeconds: 300)) {
        print('Chat Socket: Token close to expiry. Refreshing...');
        await api.refreshAccessToken();
      }

      final token = ApiService.instance?.client.accessToken;

      final Map<String, String> headers = {};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      _chatChannel = IOWebSocketChannel.connect(
        Uri.parse(sanitizedUrl),
        headers: headers,
      );

      _chatChannel!.stream.listen(
        (message) {
          try {
            final decoded = jsonDecode(message.toString());
            if (decoded is Map && decoded.containsKey('message')) {
              String msg = decoded['message'].toString();
              if (msg == "Sentinel companion online") {
                msg = "Bienvenido, Sentinel Listo";
              }
              _chatController.add(msg);
            } else {
              _chatController.add(message.toString());
            }
          } catch (_) {
            // Not JSON, send as is
            _chatController.add(message.toString());
          }
        },
        onError: (error) {
          print('Chat WebSocket Error: $error');
        },
        onDone: () {
          print('Chat WebSocket Closed');
        },
      );
    } catch (e) {
      print('Chat Connection Error: $e');
    }
  }

  void disconnectRunSocket(String runId) {
    final rid = runId.toLowerCase();
    _runSockets[rid]?.sink.close();
    _runSockets.remove(rid);
  }

  void disconnect() {
    _pollingTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _chatChannel?.sink.close();
    // Close all run sockets
    for (var s in _runSockets.values) {
      s.sink.close();
    }
    _runSockets.clear();

    _eventController.close();
    _chatController.close();
    _telemetryController.close();
    _connectionStatusController.close();
  }

  void sendMessage(String message) {
    if (_chatChannel != null) {
      _chatChannel!.sink.add(message);
    } else {
      print('Chat socket not connected');
    }
  }

  void requestInventory() {
    try {
      if (_channel != null) {
        _channel!.sink.add(jsonEncode({"action": "get_inventory"}));
      }
    } catch (e) {
      print("requestInventory error: $e");
    }
  }

  // New API Methods
  Future<List<SentinelSwitch>> fetchSwitches() async {
    final api = ApiService.instance;
    if (api == null) throw Exception('ApiService not initialized');

    final res = await api.client.get('/sentinel/api/switches/');
    if (!res.ok) {
      throw Exception('Failed to load switches: ${res.error}');
    }

    final List<dynamic> data = res.body is List ? res.body : [];
    return data.map((e) => SentinelSwitch.fromJson(e)).toList();
  }

  Future<SentinelSwitch> fetchSwitchDetails(int id) async {
    // Since fetchSwitches returns full details now, we might not need this individually
    // unless we want to refresh a specific switch.
    final api = ApiService.instance;
    if (api == null) throw Exception('ApiService not initialized');

    final res = await api.client.get('/sentinel/api/switches/$id/');
    if (!res.ok) {
      throw Exception('Failed to load switch details: ${res.error}');
    }

    return SentinelSwitch.fromJson(res.body);
  }

  Future<List<String>> fetchAvailableImages() async {
    final api = ApiService.instance;
    if (api == null) throw Exception('ApiService not initialized');

    final res = await api.client.get('/sentinel/api/images/available/');
    if (!res.ok) {
      throw Exception('Failed to load available images: ${res.error}');
    }

    // Check if the backend returns a List directly or a Map with an 'images' key
    List<dynamic> images;
    if (res.body is List) {
      images = res.body;
    } else if (res.body is Map) {
      images = res.body['images'] is List ? res.body['images'] : [];
    } else {
      images = [];
    }

    return images.map((e) {
      if (e is Map && e.containsKey('name')) {
        return e['name'].toString();
      }
      return e.toString();
    }).toList();
  }

  Future<void> updateImageSelection({
    required String scope, // 'port' or 'switch'
    required int scopeId,
    required String image,
    required bool enabled,
    int? orderId,
  }) async {
    final api = ApiService.instance;
    if (api == null) throw Exception('ApiService not initialized');

    final Map<String, dynamic> body = {
      'scope': scope,
      'scope_id': scopeId,
      'image': image,
      'enabled': enabled,
    };
    if (orderId != null) {
      body['order_id'] = orderId;
    }

    final res = await api.client.post(
      '/sentinel/api/image-selection/',
      jsonBody: body,
    );

    if (!res.ok) {
      throw Exception('Failed to update image selection: ${res.error}');
    }
  }

  Future<Map<String, dynamic>?> fetchImageSelection({
    required String scope,
    required int scopeId,
  }) async {
    final api = ApiService.instance;
    if (api == null) throw Exception('ApiService not initialized');

    final res = await api.client.get('/sentinel/api/image-selection/');
    if (!res.ok) return null;

    final body = res.body;

    // backend returns List by default
    final List<dynamic> list = body is List
        ? body
        : (body is Map && body['selections'] is List ? body['selections'] : []);

    for (final e in list) {
      if (e is Map) {
        final s = e['scope']?.toString();
        final id = e['scope_id'];
        final parsedId = id is int ? id : int.tryParse('$id');
        if (s == scope && parsedId == scopeId) {
          return Map<String, dynamic>.from(e);
        }
      }
    }
    return null;
  }

  // Mock Data Methods (Keeping for backward compatibility or testing)
  Future<List<SentinelDevice>> fetchDevices() async {
    await Future.delayed(const Duration(seconds: 1));
    return [
      SentinelDevice(
        mac: '00:1A:2B:3C:4D:5E',
        ip: '192.168.50.101',
        hostname: 'PC-LAB-01',
        status: 'Alive',
        switchPort: '1',
        vendor: 'Dell Inc.',
        logs: ['Booted successfully', 'Agent started'],
      ),
    ];
  }
  Future<Map<String, dynamic>> fetchStats({int days = 7}) async {
    final api = ApiService.instance;
    if (api == null) throw Exception('ApiService not initialized');

    final res = await api.client.get('/sentinel/api/stats/?days=$days');
    if (!res.ok) {
      throw Exception('Failed to load stats: ${res.error}');
    }

    return Map<String, dynamic>.from(res.body is Map ? res.body : {});
  }
}
