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
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_channel != null) {
        _channel!.sink.add(jsonEncode({"action": "get_inventory"}));
      }
    });
  }

  void _connectEventSocket() {
    try {
      final sanitizedUrl = _wsUrl.trim();
      print('Connecting to Sentinel WS: $sanitizedUrl');

      final token = ApiService.instance?.client.accessToken;
      print(
        'SENTINEL_SERVICE: ApiService.instance is available: ${ApiService.instance != null}',
      );
      print('SENTINEL_SERVICE: Access Token length: ${token?.length ?? 0}');

      final Map<String, dynamic> headers = {};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
        print('SENTINEL_SERVICE: Added Authorization header');
      } else {
        print(
          'SENTINEL_SERVICE: WARNING - No access token available for WebSocket',
        );
      }

      print(
        'SENTINEL_SERVICE: Handshake headers keys: ${headers.keys.toList()}',
      );

      _isConnected = true;
      _connectionStatusController.add(true);
      _channel = IOWebSocketChannel.connect(
        Uri.parse(sanitizedUrl),
        headers: headers,
      );
      _channel!.stream.listen(
        (message) {
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

            _handleNewEvent(data);

            // CHECK FOR ACTIVE RUN (Robust Multi-Support)
            if (data is Map) {
              final Map<String, dynamic> devicesToProcess = {};

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
                  if (pv is Map && pv.containsKey('active_run_id')) {
                    devicesToProcess[pk] = pv;
                  }
                });
              }
              devicesToProcess.forEach((key, info) {
                if (info is Map && info.containsKey('active_run_id')) {
                  final runId = info['active_run_id']?.toString();
                  if (runId != null && runId.isNotEmpty) {
                    if (!_runSockets.containsKey(runId.toLowerCase())) {
                      print("Found active run ID: $runId");
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
          _connectionStatusController.add(false);
        },
        onDone: () {
          print('WebSocket Closed');
          _isConnected = false;
          _connectionStatusController.add(false);
        },
      );
    } catch (e) {
      print('Connection Error: $e');
      _connectionStatusController.add(false);
    }
  }

  void _connectRunSocket(String rawRunId) {
    final runId = rawRunId.toLowerCase(); // Enforce lowercase
    if (_runSockets.containsKey(runId)) return;

    // Try both header and query param (belt and suspenders)
    final token = ApiService.instance?.client.accessToken ?? '';
    final url = 'ws://10.20.31.10:7000/ws/runs/$runId/?token=$token';
    print('Connecting to Telemetry Run: $url');

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
    } else if (data is Map<String, dynamic>) {
      // Check if this is a Raw Device Update (Map<Mac, DeviceData>)
      // The backend sometimes sends { "mac_addr": { device_data } } without a "type" wrapper
      if (!data.containsKey('type')) {
        bool potentialDeviceMap = false;
        data.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            // Assume this is a device update
            potentialDeviceMap = true;
            _eventController.add(
              SentinelEvent(
                type: 'device_update',
                message: 'Update for $key',
                timestamp: DateTime.now(),
                data:
                    value, // The value is the device data containing active_run_id
                mac: key,
              ),
            );
          }
        });

        if (potentialDeviceMap) return;
      }

      final event = SentinelEvent.fromJson(data);
      _eventController.add(event);
    }
  }

  void _connectChatSocket() {
    try {
      final sanitizedUrl = _chatWsUrl.trim();
      print('Connecting to Chat WS: $sanitizedUrl');

      final token = ApiService.instance?.client.accessToken;
      print(
        'SENTINEL_CHAT_SERVICE: Access Token length: ${token?.length ?? 0}',
      );

      final Map<String, String> headers = {};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
        print('SENTINEL_CHAT_SERVICE: Added Authorization header');
      } else {
        print(
          'SENTINEL_CHAT_SERVICE: WARNING - No access token available for WebSocket',
        );
      }

      _chatChannel = IOWebSocketChannel.connect(
        Uri.parse(sanitizedUrl),
        headers: headers,
      );

      _chatChannel!.stream.listen(
        (message) {
          _chatController.add(message.toString());
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

  void disconnect() {
    _pollingTimer?.cancel();
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
}
