import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';

import 'sentinel_service.dart';
import 'sentinel_models.dart';
import 'voice_service.dart';

class SentinelProvider extends ChangeNotifier {
  final SentinelService _service = SentinelService();
  final VoiceService _voiceService = VoiceService();
  // Legacy sockets removed (Managed by Service)

  List<SentinelSwitch> _switches = [];
  SentinelSwitch? _selectedSwitch;
  final Map<String, SentinelDevice> _deviceMap = {};
  List<SentinelEvent> _events = [];
  List<Map<String, String>> _chatMessages = [];
  bool _isLoading = false;
  bool _isThinking = false;
  bool _isConnected = false;
  String _userName = 'Commander'; // Default name

  // Streaming & TTS state
  StringBuffer _streamBuffer = StringBuffer();
  bool _hasSpokenStream = false;

  List<SentinelSwitch> get switches => _switches;
  SentinelSwitch? get selectedSwitch => _selectedSwitch;
  List<SentinelPort> get ports => _selectedSwitch?.ports ?? [];

  /// Total devices received via WebSocket
  List<SentinelDevice> get devices => _deviceMap.values.toList();

  /// Devices that belong to the currently selected switch/table topology
  List<SentinelDevice> get recognizedDevices {
    if (_selectedSwitch == null) return [];
    return _deviceMap.values
        .where(
          (d) =>
              d.switchName?.toLowerCase() ==
                  _selectedSwitch!.name.toLowerCase() &&
              d.portNumber != null &&
              _selectedSwitch!.ports.any((p) => p.portNumber == d.portNumber),
        )
        .toList();
  }

  /// Devices that are connected to unknown ports or other switches not currently in view
  List<SentinelDevice> get unrecognizedDevices {
    final recognized = recognizedDevices;
    return _deviceMap.values
        .where((d) => !recognized.any((r) => r.mac == d.mac))
        .toList();
  }

  List<SentinelEvent> get events => _events;
  List<Map<String, String>> get chatMessages => _chatMessages;
  bool get isLoading => _isLoading;
  bool get isThinking => _isThinking;
  bool get isListening => _voiceService.isListening;
  bool get isConnected => _isConnected;

  SentinelProvider() {
    _init();
  }

  void setUserName(String name) {
    _userName = name;
  }

  Future<void> _init() async {
    // Initialize state from service
    _isConnected = _service.isConnected;

    // Attach listeners first
    _service.eventStream.listen(_handleEvent);
    _service.telemetryStream.listen(_handleTelemetryMessage);
    _service.chatStream.listen(_handleChatMessage);
    _service.connectionStatusStream.listen((status) {
      _isConnected = status;
      notifyListeners();
    });

    _voiceService.speechStream.listen(_handleVoiceInput);

    await _voiceService.init();

    fetchInitialData();
    _service.connect(); // Connect AFTER listeners are ready
  }

  Future<void> fetchInitialData() async {
    _isLoading = true;
    notifyListeners();
    try {
      _switches = await _service.fetchSwitches();
      if (_switches.isNotEmpty) {
        await selectSwitch(_switches.first);
      }
    } catch (e) {
      print('Error fetching initial data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectSwitch(SentinelSwitch s) async {
    _isLoading = true;
    notifyListeners();
    try {
      // The switch object from fetchSwitches() should already have ports.
      // If not, we could fetch details here, but user said the endpoint returns everything.
      _selectedSwitch = s;
      _syncTopologyWithDevices();
    } catch (e) {
      print('Error selecting switch: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _handleEvent(SentinelEvent event) {
    if (event.type == 'devices_update') {
      try {
        final rawDevices = event.data?['devices'];
        if (rawDevices is List) {
          for (var d in rawDevices) {
            final newDevice = d is SentinelDevice
                ? d
                : SentinelDevice.fromJson(d);
            if (_deviceMap.containsKey(newDevice.mac)) {
              final existing = _deviceMap[newDevice.mac]!;
              _deviceMap[newDevice.mac] = newDevice.copyWith(
                imagingProgress:
                    newDevice.imagingProgress ?? existing.imagingProgress,
                downloadedBytes:
                    newDevice.downloadedBytes ?? existing.downloadedBytes,
                totalBytes: newDevice.totalBytes ?? existing.totalBytes,
                speedMbps: newDevice.speedMbps ?? existing.speedMbps,
                stage: newDevice.stage ?? existing.stage,
              );
            } else {
              _deviceMap[newDevice.mac] = newDevice;
            }
          }
        } else if (rawDevices is Map) {
          rawDevices.forEach((mac, devData) {
            // GAP 1: Inject the MAC into the data before parsing!
            if (devData is Map) {
              final mapData = Map<String, dynamic>.from(devData);
              mapData['mac'] = mac;

              // GAP 2: Map the run ID field so the model sees it
              if (mapData.containsKey('active_run_id')) {
                mapData['activeRunId'] = mapData['active_run_id'];
              }

              final newDevice = SentinelDevice.fromMap(mapData);
              if (_deviceMap.containsKey(newDevice.mac)) {
                final existing = _deviceMap[newDevice.mac]!;
                _deviceMap[newDevice.mac] = newDevice.copyWith(
                  imagingProgress:
                      newDevice.imagingProgress ?? existing.imagingProgress,
                  downloadedBytes:
                      newDevice.downloadedBytes ?? existing.downloadedBytes,
                  totalBytes: newDevice.totalBytes ?? existing.totalBytes,
                  speedMbps: newDevice.speedMbps ?? existing.speedMbps,
                  stage: newDevice.stage ?? existing.stage,
                );
              } else {
                _deviceMap[newDevice.mac] = newDevice;
              }
            }
          });
        }
      } catch (e) {
        print('Error parsing device update: $e');
      }
    } else if (event.type == 'device_update' && event.data != null) {
      _handleRealtimeDeviceUpdate(event.data!);
    } else {
      _events.insert(0, event);
    }

    _syncTopologyWithDevices();
    notifyListeners();
  }

  void _handleRealtimeDeviceUpdate(Map<String, dynamic> data) {
    // FORCE field mapping for the model
    if (data.containsKey('active_run_id')) {
      data['activeRunId'] = data['active_run_id'];
    }

    final String? mac = data['mac']?.toString();
    if (mac != null) {
      if (_deviceMap.containsKey(mac)) {
        // MERGE instead of replace to keep switch/port info!
        final existing = _deviceMap[mac]!;
        _deviceMap[mac] = SentinelDevice.fromMap({
          ...existing.toJson(), // Keep what we have
          ...data, // Overwrite with new telemetry/run_id
        });
      } else {
        _deviceMap[mac] = SentinelDevice.fromMap(data);
      }
    }

    // Capture switch/port from the (potentially merged) device
    final device = mac != null ? _deviceMap[mac] : null;
    final switchName = device?.switchName ?? data['switch_name']?.toString();
    final portNum =
        device?.portNumber ??
        (data['port_number'] is num
            ? (data['port_number'] as num).toInt()
            : null);

    if (_selectedSwitch != null &&
        _selectedSwitch!.name.toLowerCase() == switchName?.toLowerCase() &&
        portNum != null) {
      // Find the port and update it
      final device = SentinelDevice.fromJson(data);

      // Update the port in the selected switch
      final updatedPorts = _selectedSwitch!.ports.map((p) {
        if (p.portNumber == portNum) {
          return p.copyWith(status: 'up', connectedDevice: () => device);
        }
        return p;
      }).toList();

      _selectedSwitch = SentinelSwitch(
        switchId: _selectedSwitch!.switchId,
        name: _selectedSwitch!.name,
        ip: _selectedSwitch!.ip,
        vendor: _selectedSwitch!.vendor,
        location: _selectedSwitch!.location,
        enabled: _selectedSwitch!.enabled,
        ports: updatedPorts,
      );
    }

    // Ensure topology is synced with the new device map status
    _syncTopologyWithDevices();

    // Also add to global events if it's a new connection
    _events.insert(
      0,
      SentinelEvent(
        type: 'device_update',
        message:
            'Device ${data['dhcp']?['host'] ?? 'Unknown'} detected on $switchName port $portNum',
        timestamp: DateTime.now(),
        data: data,
      ),
    );
    notifyListeners();
  }

  void _handleTelemetryMessage(dynamic event) {
    if (event is Map) {
      final runId = event['run_id']?.toString() ?? event['run']?.toString();
      if (runId == null) return;
      final kind = event['kind']?.toString() ?? event['event']?.toString();

      dynamic payload = event['payload'];
      if (payload is String) {
        try {
          payload = jsonDecode(payload);
        } catch (_) {}
      }
      if (payload is! Map) return;
      String? targetMac;
      for (var dev in _deviceMap.values) {
        if (dev.activeRunId?.toLowerCase() == runId.toLowerCase()) {
          targetMac = dev.mac;
          break;
        }
      }
      if (targetMac != null) {
        final device = _deviceMap[targetMac]!;

        if (kind == 'progress') {
          // Calculate percentage manually since it's missing from your JSON
          final done = payload['bytes_done'] as num? ?? 0;
          final total =
              payload['bytes_total'] as num? ??
              payload['source_size_bytes'] as num? ??
              1;
          final progress = (done / total * 100).toInt();
          // Map 'mbps_current' to speed
          final speed = (payload['mbps_current'] as num?)?.toDouble();
          _deviceMap[targetMac] = device.copyWith(
            imagingProgress: progress,
            downloadedBytes: done.toInt(),
            totalBytes: total.toInt(),
            stage: payload['stage'] ?? "STREAMING",
            speedMbps: speed,
          );
        } else if (payload.containsKey('stage')) {
          _deviceMap[targetMac] = device.copyWith(
            stage: payload['stage'].toString(),
          );
        }

        _syncTopologyWithDevices();
        notifyListeners();
      }
    }
  }

  void _handleChatMessage(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map) {
        // Handle Streaming
        if (decoded['status'] == 'stream') {
          final chunk = decoded['chunk'] as String? ?? '';
          final sequence = decoded['sequence'] as int? ?? 0;

          if (sequence == 0) {
            _isThinking = false;
            _hasSpokenStream = false;
            _chatMessages.add({'role': 'sentinel', 'message': chunk});
            _streamBuffer.clear();
            _streamBuffer.write(chunk);
          } else {
            if (_chatMessages.isNotEmpty &&
                _chatMessages.last['role'] == 'sentinel') {
              final currentMsg = _chatMessages.last['message'] ?? '';
              _chatMessages.last['message'] = currentMsg + chunk;
              _streamBuffer.write(chunk);
            }
          }
          notifyListeners();
          return;
        }
        // Handle Stream Completion
        else if (decoded['status'] == 'done') {
          print('Stream done. buffer: ${_streamBuffer.toString()}');
          _voiceService.speak(_streamBuffer.toString());
          _hasSpokenStream = true;
          return;
        }
        // Handle Standard JSON Reply
        else if (decoded.containsKey('reply')) {
          _isThinking = false;
          final reply = decoded['reply'].toString();

          if (_streamBuffer.isNotEmpty && _streamBuffer.toString() == reply) {
            if (_hasSpokenStream) {
              _streamBuffer.clear();
              return;
            } else {
              _streamBuffer.clear();
            }
          }

          _chatMessages.add({'role': 'sentinel', 'message': reply});
          _voiceService.speak(reply);
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      print('Error handling chat message: $e');
    }

    _isThinking = false;
    _chatMessages.add({'role': 'sentinel', 'message': message});
    _voiceService.speak(message);
    notifyListeners();
  }

  void _handleVoiceInput(String text) {
    if (text.toLowerCase().contains('hey sentinel')) {
      _voiceService.stopListening();
      _voiceService.speak("Yes $_userName");
      Future.delayed(const Duration(seconds: 2), () {
        _voiceService.startListening();
      });
    }
  }

  void sendMessage(String message) {
    _chatMessages.add({'role': 'user', 'message': message});
    _isThinking = true;
    _service.sendMessage(message);
    notifyListeners();
  }

  void startListening() {
    _voiceService.startListening();
    notifyListeners();
  }

  void stopListening() {
    _voiceService.stopListening();
    notifyListeners();
  }

  void _syncTopologyWithDevices() {
    if (_selectedSwitch == null) return;

    final updatedPorts = _selectedSwitch!.ports.map((port) {
      // Find a device that matches this switch and port
      SentinelDevice? connectedDevice;
      try {
        connectedDevice = _deviceMap.values.firstWhere((d) {
          final match =
              d.switchName?.toLowerCase().trim() ==
                  _selectedSwitch!.name.toLowerCase().trim() &&
              d.portNumber == port.portNumber;
          return match;
        });
      } catch (_) {
        connectedDevice = null;
      }

      if (connectedDevice != null) {
        String status = 'up';
        // If we have an active run ID, we are definitely imaging
        if (connectedDevice.activeRunId != null ||
            connectedDevice.status.toLowerCase() == 'imaging') {
          status = 'imaging';
        } else if (connectedDevice.status.toLowerCase() == 'failure') {
          status = 'anomaly';
        }

        return port.copyWith(
          status: status,
          connectedDevice: () => connectedDevice,
        );
      } else {
        return port.copyWith(status: 'down', connectedDevice: () => null);
      }
    }).toList();

    _selectedSwitch = SentinelSwitch(
      switchId: _selectedSwitch!.switchId,
      name: _selectedSwitch!.name,
      ip: _selectedSwitch!.ip,
      vendor: _selectedSwitch!.vendor,
      location: _selectedSwitch!.location,
      enabled: _selectedSwitch!.enabled,
      ports: updatedPorts,
    );
  }

  @override
  void dispose() {
    // Only dispose service and background tasks
    _service.disconnect();
    _voiceService.stopListening();
    super.dispose();
  }
}
