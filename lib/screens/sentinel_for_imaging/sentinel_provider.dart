import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';

import 'sentinel_service.dart';
import 'sentinel_models.dart';
import 'voice_service.dart';

class SentinelProvider extends ChangeNotifier {
  final SentinelService _service = SentinelService();
  // Voice Control
  final VoiceService _voiceService = VoiceService();
  bool _voiceEnabled = false; // "voice service will only work in this screen"

  void setVoiceEnabled(bool enabled) {
    _voiceEnabled = enabled;
    if (!enabled) {
      _voiceService.stopSpeaking();
      _voiceService.stopListening();
    } else {
      // Re-init listener if needed?
      // Current implementation of voice service starts listening explicitly?
      // Let's just control output for now as requested for TTS.
    }
  }
  // Legacy sockets removed (Managed by Service)

  List<SentinelSwitch> _switches = [];
  SentinelSwitch? _selectedSwitch;
  Map<int, SentinelPort> _portNumberMap = {}; // O(1) lookup
  // Immutable state pattern: replace, don't mutate
  Map<String, SentinelDevice> _deviceMap = {}; // Removed 'final'

  Map<String, SentinelDevice> get deviceMap => _deviceMap;

  SentinelDevice? deviceByMac(String? mac) {
    if (mac == null) return null;
    return _deviceMap[mac];
  }

  // ... inside _handleEvent for bulk update ...

  final List<SentinelEvent> _events = [];
  final List<Map<String, String>> _chatMessages = [];
  List<String> _availableImages = []; // New
  bool _isLoading = false;
  bool _isThinking = false;
  bool _isConnected = false;
  String _userName = 'Commander'; // Default name

  // Streaming & TTS state
  final StringBuffer _streamBuffer = StringBuffer();
  bool _hasSpokenStream = false;

  // Stream Subscriptions
  StreamSubscription? _eventSub;
  StreamSubscription? _telemetrySub;
  StreamSubscription? _chatSub;
  StreamSubscription? _connSub;
  StreamSubscription? _speechSub;

  Timer? _staleTimer;
  DateTime _lastWsUpdateAt = DateTime.fromMillisecondsSinceEpoch(0);

  // O(1) Lookups for Telemetry
  final Map<String, String> _runToMac = {}; // runIdLower -> macKey
  final Map<String, String> _macToRun = {}; // macKey -> runIdLower

  void _markWsUpdate() {
    _lastWsUpdateAt = DateTime.now();
  }

  void _startStaleWatchdog() {
    _staleTimer?.cancel();
    _staleTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final silentFor = DateTime.now().difference(_lastWsUpdateAt);
      if (silentFor.inSeconds >= 15 && _isConnected) {
        print(
          "WATCHDOG: WS silent ${silentFor.inSeconds}s -> requesting snapshot",
        );
        _service.requestInventory();
      }
    });
  }

  List<SentinelSwitch> get switches => _switches;
  SentinelSwitch? get selectedSwitch => _selectedSwitch;
  List<SentinelPort> get ports => _selectedSwitch?.ports ?? [];
  List<String> get availableImages => _availableImages; // New getter

  bool _isDoneStage(String? stage) {
    final s = (stage ?? '').toLowerCase();
    return s == 'done' ||
        s == 'completed' ||
        s == 'success' ||
        s == 'wim_apply_done';
  }

  bool _isFailedStage(String? stage) {
    final s = (stage ?? '').toLowerCase();
    return s == 'failed' || s == 'error' || s == 'wim_apply_failed';
  }

  List<SentinelPort> get allPorts =>
      _switches.expand((s) => s.ports).toList(growable: false);

  int get configuredPortsCount => allPorts
      .where((p) => p.imageEnabled && (p.selectedImage ?? '').trim().isNotEmpty)
      .length;

  int get matchedDevicesCount => allPorts
      .where(
        (p) =>
            p.imageEnabled &&
            (p.selectedImage ?? '').trim().isNotEmpty &&
            (p.connectedDevice != null || (p.connectedMac ?? '').trim().isNotEmpty),
      )
      .length;

  int get activelyImagingDevicesCount => _deviceMap.values
      .where(
        (d) =>
            (d.activeRunId ?? '').trim().isNotEmpty &&
            !_isDoneStage(d.stage) &&
            !_isFailedStage(d.stage),
      )
      .length;

  int get completedImagingDevicesCount => _deviceMap.values
      .where(
        (d) =>
            _isDoneStage(d.stage) ||
            d.completedAt != null ||
            ((d.imagingProgress ?? 0) >= 100),
      )
      .length;

  String buildImagingSnapshotCsv({int? orderId}) {
    final b = StringBuffer();
    b.writeln(
      'order_id,switch_id,switch_name,port_id,port_number,label,image_enabled,selected_image,connected_mac,device_hostname,device_ip,status,stage,progress,active_run_id,completed_at',
    );

    for (final s in _switches) {
      for (final p in s.ports) {
        final d = p.connectedDevice;
        final row = [
          orderId?.toString() ?? '',
          s.switchId.toString(),
          _csv(s.name),
          p.portId.toString(),
          p.portNumber.toString(),
          _csv(p.label),
          p.imageEnabled ? '1' : '0',
          _csv(p.selectedImage ?? ''),
          _csv(p.connectedMac ?? d?.mac ?? ''),
          _csv(d?.hostname ?? ''),
          _csv(d?.ip ?? ''),
          _csv(d?.status ?? p.status),
          _csv(d?.stage ?? ''),
          (d?.imagingProgress ?? '').toString(),
          _csv(d?.activeRunId ?? ''),
          _csv(d?.completedAt?.toIso8601String() ?? ''),
        ];
        b.writeln(row.join(','));
      }
    }

    return b.toString();
  }

  String buildEventsCsv({int? orderId}) {
    final b = StringBuffer();
    b.writeln('order_id,timestamp,type,mac,message');

    for (final e in _events) {
      b.writeln(
        [
          orderId?.toString() ?? '',
          _csv(e.timestamp.toIso8601String()),
          _csv(e.type),
          _csv(e.mac ?? ''),
          _csv(e.message),
        ].join(','),
      );
    }

    return b.toString();
  }

  String _csv(String value) {
    final v = value.replaceAll('"', '""');
    return '"$v"';
  }

  // O(1) Port Lookup for UI
  SentinelPort? portForDevice(SentinelDevice device) {
    if (device.portNumber == null) return null;
    return _portNumberMap[device.portNumber];
  }

  /// Total devices received via WebSocket
  List<SentinelDevice> get devices => _deviceMap.values.toList();

  List<SentinelDevice> _cachedRecognized = [];
  List<SentinelDevice> _cachedMonitored = [];

  List<SentinelDevice> get recognizedDevices => _cachedRecognized;
  List<SentinelDevice> get monitoredDevices => _cachedMonitored;

  void _recalculateDerivedLists() {
    // 1. Recognized
    if (visibleSwitches.isEmpty) {
      _cachedRecognized = [];
    } else {
      final visibleMap = {
        for (var s in visibleSwitches) s.name.toLowerCase().trim(): s,
      };
      _cachedRecognized = _deviceMap.values.where((d) {
        final swName = d.switchName?.toLowerCase().trim();
        if (swName == null || !visibleMap.containsKey(swName)) return false;

        final switchObj = visibleMap[swName]!;
        final pn = d.portNumber;
        if (pn == null) return false;

        final port = switchObj.ports.firstWhere(
          (p) => p.portNumber == pn,
          orElse: () => SentinelPort(
            portId: 0,
            portNumber: pn,
            enabled: false,
            label: '',
            role: 'access',
          ),
        );
        return port.enabled;
      }).toList();
    }

    // 2. Monitored
    if (_monitoredSwitchIds.isEmpty) {
      _cachedMonitored = _deviceMap.values.toList();
    } else {
      final monitoredNames = _switches
          .where((s) => _monitoredSwitchIds.contains(s.switchId))
          .map((s) => s.name.toLowerCase().trim())
          .toSet();

      _cachedMonitored = _deviceMap.values.where((d) {
        // Always show actively imaging devices regardless of switch!
        if (d.activeRunId != null && d.activeRunId!.isNotEmpty) {
          final s = d.stage?.toLowerCase();
          if (s != 'done' &&
              s != 'failed' &&
              s != 'wim_apply_done' &&
              s != 'wim_apply_failed') {
            return true;
          }
        }

        final swName = d.switchName?.toLowerCase().trim();
        if (swName == null) return false;
        return monitoredNames.contains(swName);
      }).toList();
    }
  }

  /// Devices that are connected to unknown ports or switches not currently in view
  List<SentinelDevice> get unrecognizedDevices {
    if (visibleSwitches.isEmpty) return _deviceMap.values.toList();
    // ... unrecognized logic is usually rare, kept dynamic for now or cache if needed
    // (keeping original logic for unrecognized as it's less critical)
    final visibleMap = {
      for (var s in visibleSwitches) s.name.toLowerCase().trim(): s,
    };

    return _deviceMap.values.where((d) {
      final swName = d.switchName?.toLowerCase().trim();
      if (swName == null || !visibleMap.containsKey(swName)) return true;

      final switchObj = visibleMap[swName]!;
      final pn = d.portNumber;
      if (pn == null) return true;

      final port = switchObj.ports.firstWhere(
        (p) => p.portNumber == pn,
        orElse: () => SentinelPort(
          portId: 0,
          portNumber: pn,
          enabled: false,
          label: '',
          role: 'access',
        ),
      );

      return !port.enabled;
    }).toList();
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
    _eventSub = _service.eventStream.listen(_handleEvent);
    _telemetrySub = _service.telemetryStream.listen(_handleTelemetryMessage);
    _chatSub = _service.chatStream.listen(_handleChatMessage);
    _connSub = _service.connectionStatusStream.listen((status) {
      _isConnected = status;
      notifyListeners();
    });

    _speechSub = _voiceService.speechStream.listen(_handleVoiceInput);

    // Only init voice on non-Windows to avoid threading issues
    if (!Platform.isWindows) {
      try {
        await _voiceService.init();
      } catch (e) {
        print('SentinelProvider: Voice init failed (likely MissingPluginException): $e');
      }
    }

    // Load images in background
    loadAvailableImages();

    fetchInitialData();
    _startStaleWatchdog();
    _service.connect(); // Connect AFTER listeners are ready
  }

  // PERSISTENCE METHODS
  Future<void> _loadSavedLayout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSwitchId = prefs.getInt('selected_switch_id');
      final savedVisibleIds = prefs.getStringList('visible_switch_ids');

      if (savedSwitchId != null && _switches.isNotEmpty) {
        // Try to find the saved switch
        final s = _switches.firstWhere(
          (sw) => sw.switchId == savedSwitchId,
          orElse: () => _switches.first,
        );
        // Don't call selectSwitch here to avoid redundant saves/notifies, just set it
        _selectedSwitch = s;
      }

      if (savedVisibleIds != null) {
        _additionalVisibleIds.clear();
        for (var idStr in savedVisibleIds) {
          final id = int.tryParse(idStr);
          if (id != null) _additionalVisibleIds.add(id);
        }
      }

      final savedMonitoredIds = prefs.getStringList('monitored_switch_ids');
      if (savedMonitoredIds != null) {
        _monitoredSwitchIds.clear();
        for (var idStr in savedMonitoredIds) {
          final id = int.tryParse(idStr);
          if (id != null) _monitoredSwitchIds.add(id);
        }
      }

      // Sync topology after loading everything
      if (_selectedSwitch != null) {
        _syncTopologyWithDevices();
      }
      notifyListeners();
    } catch (e) {
      print('Error loading saved layout: $e');
    }
  }

  Future<void> _saveLayout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_selectedSwitch != null) {
        await prefs.setInt('selected_switch_id', _selectedSwitch!.switchId);
      }
      final List<String> visibleList = _additionalVisibleIds
          .map((id) => id.toString())
          .toList();
      await prefs.setStringList('visible_switch_ids', visibleList);

      final List<String> monitoredList = _monitoredSwitchIds
          .map((id) => id.toString())
          .toList();
      await prefs.setStringList('monitored_switch_ids', monitoredList);
    } catch (e) {
      print('Error saving layout: $e');
    }
  }

  // ...

  Future<void> fetchInitialData() async {
    _isLoading = true;
    notifyListeners();
    try {
      _switches = await _service.fetchSwitches();

      // Load layout preference AFTER fetching switches
      await _loadSavedLayout();

      // If no saved selection (or first launch), default to first switch
      if (_selectedSwitch == null && _switches.isNotEmpty) {
        await selectSwitch(_switches.first);
      }
    } catch (e) {
      print('Error fetching initial data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ...

  void toggleSwitchVisibility(int id) {
    if (_selectedSwitch?.switchId == id) return; // Always visible

    if (_additionalVisibleIds.contains(id)) {
      _additionalVisibleIds.remove(id);
    } else {
      _additionalVisibleIds.add(id);
    }
    _saveLayout(); // Save change
    // Critical: Sync topology immediately...
    _recalculateDerivedLists();
    _syncTopologyWithDevices();
    notifyListeners();
  }

  // Layout Persistence State
  List<int> _additionalVisibleIds = [];
  List<int> _monitoredSwitchIds = []; // For ActiveImagingPanel

  List<int> get additionalVisibleIds => _additionalVisibleIds;
  List<int> get monitoredSwitchIds => _monitoredSwitchIds;

  // a-sw3 Pack Selection: 0=All, 1=Pack1 (17-19), 2=Pack2 (20-22), 3=Pack3 (23)
  final Set<int> _activeASW3Packs = {0};
  Set<int> get activeASW3Packs => _activeASW3Packs;

  bool isPackActive(int packId) => _activeASW3Packs.contains(packId);

  void toggleASW3Pack(int pack) {
    if (pack == 0) {
      _activeASW3Packs.clear();
      _activeASW3Packs.add(0);
    } else {
      _activeASW3Packs.remove(0);
      if (_activeASW3Packs.contains(pack)) {
        _activeASW3Packs.remove(pack);
      } else {
        _activeASW3Packs.add(pack);
      }
      if (_activeASW3Packs.isEmpty) _activeASW3Packs.add(0);
    }
    notifyListeners();
  }

  /// Groups ports of a switch into VirtualTableGroups based on labels like "A-18-P01"
  List<VirtualTableGroup> getVirtualGroups(SentinelSwitch s) {
    if (!s.name.toLowerCase().contains('a-sw3')) {
      // Legacy behavior for M2/M3 or others
      return [
        VirtualTableGroup(
          tableName: s.name,
          switchName: s.name,
          ports: s.ports,
          packColor: Colors.blueAccent,
        ),
      ];
    }

    // Special logic for a-sw3
    final Map<String, List<SentinelPort>> groups = {};
    for (var p in s.ports) {
      if (p.label.startsWith('A-')) {
        final parts = p.label.split('-');
        if (parts.length >= 2) {
          final tableId = "A-${parts[1]}";
          groups.putIfAbsent(tableId, () => []).add(p);
        }
      }
    }

    final sortedKeys = groups.keys.toList()..sort();

    return sortedKeys
        .map((key) {
          final tableNum = int.tryParse(key.replaceFirst('A-', '')) ?? 0;

          // Determine Pack & Color
          int pack = 0;
          Color color = Colors.grey;

          if (tableNum >= 17 && tableNum <= 19) {
            pack = 1;
            color = Colors.redAccent;
          } else if (tableNum >= 20 && tableNum <= 22) {
            pack = 2;
            color = Colors.pinkAccent;
          } else if (tableNum >= 23) {
            pack = 3;
            color = Colors.greenAccent;
          }

          // Filter by active pack if selected (0 = All)
          if (!_activeASW3Packs.contains(0) &&
              !_activeASW3Packs.contains(pack)) {
            return null;
          }

          return VirtualTableGroup(
            tableName: key,
            switchName: s.name,
            ports: groups[key]!,
            packColor: color,
            packId: pack,
          );
        })
        .whereType<VirtualTableGroup>()
        .toList();
  }

  List<SentinelSwitch> get visibleSwitches {
    if (_selectedSwitch == null) return [];

    // Main selected switch is always first
    final List<SentinelSwitch> list = [_selectedSwitch!];

    // Add additional visible switches
    for (final id in _additionalVisibleIds) {
      // Find the switch in the full list
      try {
        final s = _switches.firstWhere((sw) => sw.switchId == id);
        // Avoid duplicates if something went wrong with logic
        if (s.switchId != _selectedSwitch!.switchId) {
          list.add(s);
        }
      } catch (_) {
        // Switch might not exist anymore, ignore
      }
    }
    return list;
  }

  bool isSwitchVisible(int id) {
    if (_selectedSwitch?.switchId == id) return true;
    return _additionalVisibleIds.contains(id);
  }

  bool isSwitchMonitored(int id) {
    if (_monitoredSwitchIds.isEmpty)
      return true; // Default to ALL if none selected? Or explicit?
    // User requested "selection... will remain". If empty, maybe assume ALL (0-touch mode default).
    return _monitoredSwitchIds.contains(id);
  }

  void toggleMonitoredSwitch(int id) {
    if (_monitoredSwitchIds.contains(id)) {
      _monitoredSwitchIds.remove(id);
    } else {
      _monitoredSwitchIds.add(id);
    }
    _saveLayout();
    _recalculateDerivedLists();
    notifyListeners();
  }

  Future<void> selectSwitch(SentinelSwitch s) async {
    _isLoading = true;
    notifyListeners();
    try {
      // Clear additional visibility when focusing a new switch
      // User requested standard behavior: "M3 is M3". Only explicit add action shows both.
      _additionalVisibleIds.clear();

      _selectedSwitch = s;
      _saveLayout(); // Save change

      // Load image selection info for this switch context if needed,
      // but usually the specific UI components fetch what they need.

      _recalculateDerivedLists();
      _syncTopologyWithDevices();
    } catch (e) {
      print('Error selecting switch: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // IMAGE MANAGEMENT WRAPPERS

  Future<void> loadAvailableImages() async {
    try {
      final imgs = await _service.fetchAvailableImages();
      _availableImages = imgs;
      notifyListeners();
    } catch (e) {
      print('Error loading images: $e');
    }
  }

  Future<Map<String, dynamic>?> fetchImageSelection({
    required String scope,
    required int scopeId,
  }) async {
    return await _service.fetchImageSelection(scope: scope, scopeId: scopeId);
  }

  Future<void> setImageSelection({
    required String scope,
    required int scopeId,
    required String image,
    required bool enabled,
    int? orderId,
  }) async {
    // 1. Send API Request
    await _service.updateImageSelection(
      scope: scope,
      scopeId: scopeId,
      image: image,
      enabled: enabled,
      orderId: orderId,
    );

    // 2. Optimistic Local Update
    bool changed = false;
    List<SentinelSwitch> newSwitches = [];
    print(
      'DEBUG: setImageSelection scope=$scope id=$scopeId enabled=$enabled image=$image',
    );

    for (var s in _switches) {
      if (scope == 'switch') {
        if (s.switchId == scopeId) {
          // Update ALL ports for this switch
          final newPorts = s.ports.map((p) {
            return p.copyWith(imageEnabled: enabled, selectedImage: image);
          }).toList();

          final newSwitch = SentinelSwitch(
            switchId: s.switchId,
            name: s.name,
            ip: s.ip,
            vendor: s.vendor,
            location: s.location,
            enabled: s.enabled,
            ports: newPorts,
          );
          newSwitches.add(newSwitch);
          if (_selectedSwitch?.switchId == s.switchId) {
            _selectedSwitch = newSwitch;
          }
          changed = true;
        } else {
          newSwitches.add(s);
        }
      } else if (scope == 'port') {
        // Find if this switch contains the target port
        final pIndex = s.ports.indexWhere((p) => p.portId == scopeId);
        if (pIndex != -1) {
          print('DEBUG: Found port in switch ${s.name} (ID: ${s.switchId})');
          // Update specific port
          final oldPort = s.ports[pIndex];
          final newPort = oldPort.copyWith(
            imageEnabled: enabled,
            selectedImage: image,
          );

          List<SentinelPort> newPorts = List.from(s.ports);
          newPorts[pIndex] = newPort;

          final newSwitch = SentinelSwitch(
            switchId: s.switchId,
            name: s.name,
            ip: s.ip,
            vendor: s.vendor,
            location: s.location,
            enabled: s.enabled,
            ports: newPorts,
          );
          newSwitches.add(newSwitch);
          if (_selectedSwitch?.switchId == s.switchId) {
            _selectedSwitch = newSwitch;
          }
          changed = true;
        } else {
          newSwitches.add(s);
        }
      } else {
        newSwitches.add(s);
      }
    }

    if (changed) {
      print('DEBUG: Optimistic update applied. Notifying listeners.');
      _switches = newSwitches;
      // Re-sync topology to ensure any derived device states are updated if necessary
      _syncTopologyWithDevices();
      notifyListeners();
    } else {
      print('DEBUG: No local change detected for scope=$scope id=$scopeId');
    }

    // Refresh inventory as backup
    _service.requestInventory();
  }

  Map<String, dynamic> _normalizeIncoming(
    Map<String, dynamic> data, {
    String? mac,
  }) {
    final out = Map<String, dynamic>.from(data);

    if (mac != null && !out.containsKey('mac')) out['mac'] = mac;

    // standard run id mapping
    final rid = out['active_run_id'] ?? out['run_id'] ?? out['run'];
    if (rid != null) {
      out['activeRunId'] = rid.toString();
    }

    // fallback: extract % from message if not present in payload
    if (out['imaging_progress'] == null && out['message'] != null) {
      final msg = out['message'].toString();
      final match = RegExp(r'(\d+)\s*%').firstMatch(msg);
      if (match != null) {
        out['imaging_progress'] = int.tryParse(match.group(1)!);
      }
    }

    // port_info flattening
    final pi = out['port_info'];
    if (pi is Map) {
      out['switchName'] ??= pi['switch_name'];
      out['portNumber'] ??= pi['port_number'];
    }
    out['switchName'] ??= out['switch_name'];

    final pn = out['port_number'];
    if (out['portNumber'] == null) {
      if (pn is num) {
        out['portNumber'] = pn.toInt();
      } else if (pn is String) {
        out['portNumber'] = int.tryParse(pn);
      }
    }

    // Ensure it is int locally for consistency
    if (out['portNumber'] is num) {
      out['portNumber'] = (out['portNumber'] as num).toInt();
    } else if (out['portNumber'] is String) {
      out['portNumber'] = int.tryParse(out['portNumber']);
    }

    // ✅ CRITICAL: mirror to the keys your model actually reads
    if (out['switchName'] != null) out['switch_name'] = out['switchName'];
    if (out['portNumber'] != null) out['port_number'] = out['portNumber'];

    return out;
  }

  String _normalizeMacKey(String mac) {
    final norm = mac.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    // Windows DHCP client-id sometimes prefixes hardware type: "01" + mac
    if (norm.length == 14 && norm.startsWith('01')) return norm.substring(2);
    return norm;
  }

  bool _isRealtimeAttachEvent(String type) =>
      type == 'snmp_observed' ||
      type == 'device_moved' ||
      type == 'device_detected';

  void _applyRealtimeAttachFromEvent(SentinelEvent event) {
    // event payload may be in event.data or event itself depending on your fromJson
    final raw = <String, dynamic>{...(event.data ?? {})};

    // Sometimes backend sends mac at top-level
    if (event.mac != null && event.mac!.isNotEmpty) raw['mac'] = event.mac;
    if (!raw.containsKey('mac') && raw['mac'] == null) {
      // fallback if your SentinelEvent stores mac elsewhere
      final m = event.data?['mac']?.toString();
      if (m != null) raw['mac'] = m;
    }

    // Reuse normalization logic!
    final normalized = _normalizeIncoming(raw);

    // Provide safe defaults (SNMP doesn’t always have ip/hostname yet)
    normalized['ip'] ??= normalized['ip_address'];
    normalized['hostname'] ??=
        normalized['host'] ?? normalized['dhcp']?['host'];
    normalized['status'] ??= 'Alive';

    final rawMac = normalized['mac']?.toString();
    if (rawMac == null || rawMac.isEmpty) return;

    final key = _normalizeMacKey(rawMac);
    normalized['mac'] = key; // IMPORTANT: store normalized key

    // Merge, don’t replace
    final nextMap = Map<String, SentinelDevice>.from(_deviceMap);
    SentinelDevice newDevice;
    if (nextMap.containsKey(key)) {
      final existing = nextMap[key]!;
      newDevice = SentinelDevice.fromMap({...existing.toJson(), ...normalized});
    } else {
      newDevice = SentinelDevice.fromMap(normalized);
    }
    nextMap[key] = newDevice;
    _deviceMap = nextMap; // Atomic Swap
    _recalculateDerivedLists();

    // Update Lookup Maps
    final run = newDevice.activeRunId;
    if (run != null && run.isNotEmpty) {
      final r = run.toLowerCase();
      _runToMac[r] = key;
      _macToRun[key] = r;
    }
  }

  void _handleEvent(SentinelEvent event) {
    _markWsUpdate();

    if (event.type == 'device_disconnected') {
      String? mac = event.data?['mac']?.toString();

      // fallback if it comes nested (BaseMonitor.emit shape)
      mac ??= (event.data?['data']?['mac'])?.toString();

      if (mac != null) {
        final key = _normalizeMacKey(mac);
        final nextMap = Map<String, SentinelDevice>.from(_deviceMap);
        if (nextMap.containsKey(key)) {
          nextMap.remove(key);
          _deviceMap = nextMap; // Atomic Swap
          _recalculateDerivedLists();

          final r = _macToRun.remove(key);
          if (r != null) {
            _runToMac.remove(r);
            _service.disconnectRunSocket(r);
          }

          _syncTopologyWithDevices(triggerAlerts: true);
          notifyListeners();
        }
      }
      return;
    }

    // NEW: Handle realtime SNMP/DHCP/Move events as device updates
    if (_isRealtimeAttachEvent(event.type)) {
      _applyRealtimeAttachFromEvent(event);
      _syncTopologyWithDevices(triggerAlerts: true);
      notifyListeners();
      return;
    }

    if (event.type == 'devices_update' || event.type == 'initial_snapshot') {
      try {
        final rawDevices = event.data?['devices'];
        final nextMap = <String, SentinelDevice>{};
        bool changed = false;

        if (rawDevices is List) {
          for (var d in rawDevices) {
            final rawDevice = d is SentinelDevice
                ? d
                : SentinelDevice.fromJson(d);
            final key = _normalizeMacKey(rawDevice.mac);

            // Ensure the device object itself has the normalized MAC
            final newDevice = SentinelDevice.fromMap({
              ...rawDevice.toJson(),
              'mac': key,
            });

            if (_deviceMap.containsKey(key)) {
              final existing = _deviceMap[key]!;
              nextMap[key] = newDevice.copyWith(
                imagingProgress:
                    newDevice.imagingProgress ?? existing.imagingProgress,
                downloadedBytes:
                    newDevice.downloadedBytes ?? existing.downloadedBytes,
                totalBytes: newDevice.totalBytes ?? existing.totalBytes,
                speedMbps: newDevice.speedMbps ?? existing.speedMbps,
                stage: newDevice.stage ?? existing.stage,
                completedAt: newDevice.completedAt ?? existing.completedAt,
              );
            } else {
              nextMap[key] = newDevice;
            }
          }
          changed = true; // Always treat list replace as change/sync
        } else if (rawDevices is Map) {
          rawDevices.forEach((mac, devData) {
            if (devData is Map) {
              final rawMac = mac.toString();
              final normalizedMac = _normalizeMacKey(rawMac);

              final mapData = _normalizeIncoming(
                Map<String, dynamic>.from(devData),
                mac: normalizedMac,
              );
              mapData['mac'] = normalizedMac;

              final newDevice = SentinelDevice.fromMap(mapData);
              final existing = _deviceMap[normalizedMac];

              if (existing != null) {
                final d = newDevice.copyWith(
                  imagingProgress:
                      newDevice.imagingProgress ?? existing.imagingProgress,
                  downloadedBytes:
                      newDevice.downloadedBytes ?? existing.downloadedBytes,
                  totalBytes: newDevice.totalBytes ?? existing.totalBytes,
                  speedMbps: newDevice.speedMbps ?? existing.speedMbps,
                  stage: newDevice.stage ?? existing.stage,
                  completedAt: newDevice.completedAt ?? existing.completedAt,
                );
                nextMap[d.mac] = d;
              } else {
                nextMap[newDevice.mac] = newDevice;
              }
            }
          });
          changed = true;
        }

        if (changed) {
          // Full Sync: Replace map completely to remove ghosts
          _deviceMap = nextMap;
          _recalculateDerivedLists();

          // Rebuild Lookup Maps
          _runToMac.clear();
          _macToRun.clear();
          for (var d in _deviceMap.values) {
            final rid = d.activeRunId;
            if (rid != null && rid.isNotEmpty) {
              final low = rid.toLowerCase();
              _runToMac[low] = d.mac;
              _macToRun[d.mac] = low;
            }
          }

          _syncTopologyWithDevices(
            triggerAlerts: event.type != 'initial_snapshot',
          );
          notifyListeners();
        }
      } catch (e) {
        print('Error parsing device update: $e');
      }
    } else if (event.type == 'device_update' && event.data != null) {
      _handleRealtimeDeviceUpdate(event.data!);
    } else {
      _events.insert(0, event);
    }

    _syncTopologyWithDevices(triggerAlerts: event.type != 'initial_snapshot');
    notifyListeners();
  }

  void _handleRealtimeDeviceUpdate(Map<String, dynamic> data) {
    final normalized = _normalizeIncoming(data);
    final rawMac = normalized['mac']?.toString();
    print(
      'PROVIDER_LIVE_UPDATE: Device $rawMac (Run: ${normalized['activeRunId']})',
    );

    if (rawMac == null || rawMac.isEmpty) return;

    final key = _normalizeMacKey(rawMac);
    normalized['mac'] = key;

    // IMMUTABLE UPDATE PATTERN
    final nextMap = Map<String, SentinelDevice>.from(_deviceMap);

    if (nextMap.containsKey(key)) {
      // MERGE instead of replace to keep switch/port info!
      final existing = nextMap[key]!;
      final updated = SentinelDevice.fromMap({
        ...existing.toJson(), // Keep what we have
        ...normalized, // Overwrite with new telemetry/run_id
      });

      // Preserve completedAt if not explicitly overwritten (unless stage flips back?)
      // If new stage is not done, clear completedAt? Or keep history?
      // For now, keep history.
      if (updated.stage == 'done' || updated.stage == 'wim_apply_done') {
        if (existing.completedAt == null && updated.completedAt == null) {
          // Just finished now via this update
          // We have to use copyWith because fromMap creates a new one
          nextMap[key] = updated.copyWith(completedAt: DateTime.now());
        } else {
          nextMap[key] = updated;
        }
      } else {
        nextMap[key] = updated;
      }

      // Update Lookup Map
      final run = updated.activeRunId;
      if (run != null && run.isNotEmpty) {
        final r = run.toLowerCase();
        _runToMac[r] = key;
        _macToRun[key] = r;
      }
    } else {
      // New device: check if it came in as completed (unlikely but possible)
      if (normalized['stage'] == 'done' ||
          normalized['stage'] == 'wim_apply_done') {
        normalized['completedAt'] = DateTime.now();
      }

      final updated = SentinelDevice.fromMap(normalized);
      nextMap[key] = updated;

      // Update Lookup Map
      final run = updated.activeRunId;
      if (run != null && run.isNotEmpty) {
        final r = run.toLowerCase();
        _runToMac[r] = key;
        _macToRun[key] = r;
      }
    }
    _deviceMap = nextMap; // Atomic Swap
    _recalculateDerivedLists();

    // Capture switch/port from the (potentially merged) device
    final device = _deviceMap[key];
    final switchName =
        device?.switchName ?? normalized['switchName']?.toString();
    final portNum =
        device?.portNumber ??
        (normalized['portNumber'] is num
            ? (normalized['portNumber'] as num).toInt()
            : null);

    // Ensure topology is synced with the new device map status
    print(
      ' _handleRealtimeDeviceUpdate: Syncing topology. Device switch=${device?.switchName} port=${device?.portNumber}',
    );
    _syncTopologyWithDevices(triggerAlerts: true);

    // Also add to global events if it's a new connection
    _events.insert(
      0,
      SentinelEvent(
        type: 'device_update',
        message:
            'Device ${normalized['dhcp']?['host'] ?? 'Unknown'} detected on $switchName port $portNum',
        timestamp: DateTime.now(),
        data: normalized,
      ),
    );
    print(
      'DEBUG_UI_UPDATE: device ${device?.mac} stage=${device?.stage} progress=${device?.imagingProgress}% bytes=${device?.downloadedBytes}',
    );
    notifyListeners();
  }

  void _handleTelemetryMessage(dynamic event) {
    if (event is! Map) return;
    final t0 = DateTime.now();

    final runId = event['run_id']?.toString() ?? event['run']?.toString();
    if (runId == null) return;
    final kind = event['kind']?.toString() ?? event['event']?.toString();

    dynamic payload = event['payload'];
    if (payload is String) {
      try {
        payload = jsonDecode(payload);
      } catch (_) {}
    }
    if (payload == null) {
      payload = event; // Fallback to flat structure
    }
    if (payload is! Map) return;

    // Standardize!
    final normalized = _normalizeIncoming(Map<String, dynamic>.from(payload));
    payload = normalized;

    // Latency Check (kept the logic but removed the print)
    final serverTimeStr =
        event['timestamp']?.toString() ?? payload['timestamp']?.toString();
    if (serverTimeStr != null) {
      try {
        DateTime.parse(serverTimeStr);
      } catch (_) {}
    }

    // OPTIMIZATION (1): O(1) Lookup
    final rid = runId.toLowerCase();

    // Also try mac direct from payload if flat, to help find it if run is not tracked
    String? rawMac = event['mac']?.toString();
    String? targetMac = _runToMac[rid];
    if (targetMac == null && rawMac != null) {
      targetMac = _normalizeMacKey(rawMac);
    }
    if (targetMac == null) return;

    SentinelDevice? device = _deviceMap[targetMac];
    final nextMap = Map<String, SentinelDevice>.from(_deviceMap);
    bool stateChanged = false;

    if (device == null) {
      // Create a skeleton device for instant tracking so we don't drop telemetry
      final swName =
          payload['switch_name']?.toString() ?? payload['switch']?.toString();
      int? pNum;
      final rawPort = payload['port_number'] ?? payload['port'];
      if (rawPort is num) {
        pNum = rawPort.toInt();
      } else if (rawPort != null) {
        pNum = int.tryParse(rawPort.toString());
      }
      device = SentinelDevice(
        mac: targetMac,
        status: 'Imaging',
        activeRunId: runId,
        switchName: swName,
        portNumber: pNum,
        ip: event['ip']?.toString() ?? payload['ip']?.toString(),
        hostname: event['hostname']?.toString() ?? payload['model']?.toString(),
      );
    }

    final isProgressKind =
        (kind == 'progress' ||
        kind == 'run_progress' ||
        kind == 'smb_progress' ||
        payload['event'] == 'progress');

    if (isProgressKind) {
      final done = payload['bytes_done'] as num? ?? 0;

      int progress = 0;
      int totalInt = 1;

      if (payload['imaging_progress'] != null) {
        progress = (payload['imaging_progress'] as num).toInt();
        totalInt = payload['bytes_total'] as int? ?? 1;
      } else {
        // Broaden regex: Extract percentage from ANY message string (SMB, Extracting, etc)
        if (payload['message'] != null) {
          final msg = payload['message'].toString();
          final match = RegExp(r'([\d\.]+)%').firstMatch(msg);
          if (match != null) {
            progress = double.parse(match.group(1)!).toInt();
            if (progress > 0 && done > 0) {
              totalInt = (done / (progress / 100.0)).toInt();
            }
          }
        }

        // Only fall back to bytes_total calculation if we didn't get a percentage from the string
        if (progress == 0 &&
            (payload['bytes_total'] != null ||
                payload['source_size_bytes'] != null)) {
          final total =
              payload['bytes_total'] as num? ??
              payload['source_size_bytes'] as num? ??
              1;
          totalInt = total > 0 ? total.toInt() : 1;
          progress = (done / totalInt * 100).toInt();
        }
      }

      print(
        'DEBUG_PROGRESS_UPDATE: device $targetMac stage=${payload['stage'] ?? payload['event']} progress=$progress% bytes=$done',
      );

      final speed =
          (payload['mbps_current'] as num? ?? payload['mbps_avg'] as num?)
              ?.toDouble();
      final stageStr =
          payload['stage']?.toString() ??
          payload['event']?.toString() ??
          "STREAMING";

      if (stageStr != device.stage) {
        print(
          "DEBUG_STAGE_CHANGE: device $targetMac ${device.stage} -> $stageStr",
        );
      }

      // Final states detection
      final isFinal =
          (stageStr.toLowerCase() == 'done' ||
          stageStr.toLowerCase() == 'finished' ||
          stageStr.toLowerCase() == 'wim_apply_done' ||
          stageStr.toLowerCase() == 'failed' ||
          stageStr.toLowerCase() == 'wim_apply_failed');

      // Extract switch info if available
      final swName =
          payload['switch_name']?.toString() ?? payload['switch']?.toString();
      int? pNum;
      final rawPort = payload['port_number'] ?? payload['port'];
      if (rawPort is num) {
        pNum = rawPort.toInt();
      } else if (rawPort != null) {
        pNum = int.tryParse(rawPort.toString());
      }

      nextMap[targetMac] = device.copyWith(
        imagingProgress: isFinal ? 100 : progress,
        downloadedBytes: done.toInt(),
        totalBytes: totalInt,
        stage: stageStr,
        speedMbps: speed,
        switchName: swName ?? device.switchName,
        portNumber: pNum ?? device.portNumber,
        activeRunId: runId,
        status: 'Imaging',
        completedAt: isFinal
            ? (device.completedAt ?? DateTime.now())
            : device.completedAt,
      );
      stateChanged = true;
    } else if (payload['stage'] != null || payload['event'] != null) {
      // Handle non-progress events that still change stage (e.g. smb_complete, dry_run, etc)
      String? stageStr =
          payload['stage']?.toString() ?? payload['event']?.toString();

      // Filter out neutral/identity events as stages if we are already imaging
      if (stageStr == 'run_started' || stageStr == 'run_progress') {
        stageStr = device.stage;
      }
      stageStr ??= device.stage;

      // EXTRACT PROGRESS FALLBACK for non-progress events
      int? progress;
      if (payload['imaging_progress'] != null) {
        progress = (payload['imaging_progress'] as num).toInt();
      } else if (payload['message'] != null) {
        final msg = payload['message'].toString();
        final match = RegExp(r'(\d+)\s*%').firstMatch(msg);
        if (match != null) {
          progress = int.tryParse(match.group(1)!);
        }
      }

      if (stageStr != device.stage) {
        print(
          "DEBUG_STAGE_CHANGE: device $targetMac ${device.stage} -> $stageStr",
        );
      }

      // Final states detection
      final isFinal =
          (stageStr?.toLowerCase() == 'done' ||
          stageStr?.toLowerCase() == 'finished' ||
          stageStr?.toLowerCase() == 'wim_apply_done' ||
          stageStr?.toLowerCase() == 'failed' ||
          stageStr?.toLowerCase() == 'wim_apply_failed');

      // Extract switch info if available
      final swName =
          payload['switch_name']?.toString() ?? payload['switch']?.toString();
      int? pNum;
      final rawPort = payload['port_number'] ?? payload['port'];
      if (rawPort is num) {
        pNum = rawPort.toInt();
      } else if (rawPort != null) {
        pNum = int.tryParse(rawPort.toString());
      }

      nextMap[targetMac] = device.copyWith(
        stage: stageStr,
        imagingProgress: isFinal ? 100 : (progress ?? device.imagingProgress),
        switchName: swName ?? device.switchName,
        portNumber: pNum ?? device.portNumber,
        activeRunId: runId,
        status: 'Imaging',
        completedAt: isFinal
            ? (device.completedAt ?? DateTime.now())
            : device.completedAt,
      );
      stateChanged = true;
    }

    if (stateChanged) {
      _deviceMap = nextMap; // Atomic Swap
      _runToMac[rid] = targetMac;
      _macToRun[targetMac] = rid;
      _recalculateDerivedLists();

      // OPTIMIZATION (2): Progress updates don't change topology
      if (kind != 'progress') {
        _syncTopologyWithDevices(triggerAlerts: true);
      }

      // OPTIMIZATION (3): Push to UI right away
      notifyListeners();
    }

    final ms = DateTime.now().difference(t0).inMilliseconds;
    if (ms > 10) print("TELEMETRY_HANDLER_MS=$ms");
  }

  void _handleChatMessage(String message) {
    if (Platform.isWindows) {
      // Skip TTS processing/thinking state if voice is disabled on Windows
      _chatMessages.add({'role': 'sentinel', 'message': message});
      notifyListeners();
      return;
    }

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
    if (Platform.isWindows) return;
    _voiceService.startListening();
    notifyListeners();
  }

  void stopListening() {
    if (Platform.isWindows) return;
    _voiceService.stopListening();
    notifyListeners();
  }

  bool _samePortState(SentinelPort a, SentinelPort b) {
    final ad = a.connectedDevice;
    final bd = b.connectedDevice;

    return a.status == b.status &&
        a.imageEnabled == b.imageEnabled &&
        a.selectedImage == b.selectedImage &&
        ad?.mac == bd?.mac &&
        ad?.imagingProgress == bd?.imagingProgress &&
        ad?.stage == bd?.stage &&
        ad?.speedMbps == bd?.speedMbps &&
        ad?.downloadedBytes == bd?.downloadedBytes &&
        ad?.totalBytes == bd?.totalBytes;
  }

  void _syncTopologyWithDevices({bool triggerAlerts = false}) {
    if (_switches.isEmpty) return;

    // We update ALL visible switches, not just the selected one.
    // This ensures that side-by-side tables are both "live".
    final targets = visibleSwitches;

    for (var targetSwitch in targets) {
      final targetName = targetSwitch.name.toLowerCase().trim();

      // 1. Find devices for this switch
      final Map<int, SentinelDevice> byPort = {};
      for (final d in _deviceMap.values) {
        if (d.switchName?.toLowerCase().trim() == targetName &&
            d.portNumber != null) {
          byPort[d.portNumber!] = d;
        }
      }

      // 2. Update ports
      final oldPorts = targetSwitch.ports;
      final updatedPorts = oldPorts.map((port) {
        if (!port.enabled) {
          return port.copyWith(
            status: 'disabled',
            connectedDevice: () => null,
            connectedMac: null,
          );
        }

        final connectedDevice = byPort[port.portNumber];
        if (connectedDevice != null) {
          String status = 'up';
          if (connectedDevice.activeRunId != null ||
              connectedDevice.status.toLowerCase() == 'imaging') {
            status = 'imaging';
          } else if (connectedDevice.status.toLowerCase() == 'failure') {
            status = 'anomaly';
          }
          return port.copyWith(
            status: status,
            connectedDevice: () => connectedDevice,
            connectedMac: connectedDevice.mac,
          );
        } else {
          return port.copyWith(
            status: 'down',
            connectedDevice: () => null,
            connectedMac: null,
          );
        }
      }).toList();

      // 3. Trigger Alerts
      // User Request: "only say events from the ports /location the users are currently seeing"
      // We interpret this as ONLY the actively selected switch, to reduce noise from other visible (but secondary) switches.
      // 3. Trigger Alerts
      // User Request: "all with the selected tables" -> Use monitored list filter
      // "voice service will only work in this screen" -> handled by _voiceEnabled check in triggerAudio
      if (triggerAlerts && isSwitchMonitored(targetSwitch.switchId)) {
        for (int i = 0; i < updatedPorts.length; i++) {
          final newPort = updatedPorts[i];
          final oldPort = oldPorts.firstWhere(
            (p) => p.portNumber == newPort.portNumber,
            orElse: () => newPort,
          );
          if (_samePortState(oldPort, newPort)) continue;

          if (oldPort.connectedDevice == null &&
              newPort.connectedDevice != null) {
            _triggerAudioAlert(
              "Puerto ${newPort.portNumber} conectado en ${targetSwitch.name}",
            );
          } else if (oldPort.connectedDevice != null &&
              newPort.connectedDevice == null) {
            _triggerAudioAlert(
              "Puerto ${newPort.portNumber} desconectado en ${targetSwitch.name}",
            );
          } else if (oldPort.status != 'imaging' &&
              newPort.status == 'imaging') {
            _triggerAudioAlert(
              "Maquetado iniciado puerto ${newPort.portNumber} en ${targetSwitch.name}",
            );
          } else if (oldPort.status == 'imaging' &&
              (newPort.status == 'up' || newPort.status == 'alive')) {
            _triggerAudioAlert(
              "Maquetado finalizado puerto ${newPort.portNumber} en ${targetSwitch.name}",
            );
          }
        }
      }

      // 4. Update the Switch Object in the main list
      final updatedSwitch = SentinelSwitch(
        switchId: targetSwitch.switchId,
        name: targetSwitch.name,
        ip: targetSwitch.ip,
        vendor: targetSwitch.vendor,
        location: targetSwitch.location,
        enabled: targetSwitch.enabled,
        ports: updatedPorts,
      );

      // Replace in _switches list
      final idx = _switches.indexWhere(
        (s) => s.switchId == targetSwitch.switchId,
      );
      if (idx != -1) {
        _switches[idx] = updatedSwitch;
      }

      // Update _selectedSwitch refernece if needed
      if (_selectedSwitch?.switchId == targetSwitch.switchId) {
        _selectedSwitch = updatedSwitch;
        // Also update legacy map for safety, though we moved away from it
        _portNumberMap = {for (var p in updatedPorts) p.portNumber: p};
      }
    }
  }

  Future<void> _triggerAudioAlert(String text) async {
    if (!_voiceEnabled)
      return; // Only speak if allowed (e.g. inside PhysicalTablesScreen)

    // if (Platform.isWindows) return; // Guard removed to allow alerts on Windows
    print('TRIGGER ALERT: $text');
    await _voiceService.playTriggerSound();
    await Future.delayed(const Duration(milliseconds: 500)); // Wait for sound
    await _voiceService.speak(text);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _telemetrySub?.cancel();
    _chatSub?.cancel();
    _connSub?.cancel();
    _speechSub?.cancel();
    _staleTimer?.cancel();
    // Only dispose service and background tasks
    _service.disconnect();
    _voiceService.stopListening();
    super.dispose();
  }
}
