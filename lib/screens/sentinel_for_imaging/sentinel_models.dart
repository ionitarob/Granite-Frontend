import '../../utils/formatters.dart';

class SentinelDevice {
  final String mac;
  final String? ip;
  final String? hostname;
  final String? vendor;
  final String? switchPort; // e.g., "Gi1/0/3"
  final String status; // "Alive", "Imaging", "Offline", "Failure"
  final int? imagingProgress; // 0-100
  final List<String> logs;
  final String? switchName;
  final int? portNumber;
  final Map<String, dynamic>? dhcp;
  final String? activeRunId;
  final String? stage;
  final double? speedMbps;
  final int? downloadedBytes;
  final int? totalBytes;
  final DateTime? completedAt;

  SentinelDevice({
    required this.mac,
    this.ip,
    this.hostname,
    this.vendor,
    this.switchPort,
    this.status = 'Offline',
    this.imagingProgress,
    this.logs = const [],
    this.switchName,
    this.portNumber,
    this.dhcp,
    this.activeRunId,
    this.stage,
    this.speedMbps,
    this.downloadedBytes,
    this.totalBytes,
    this.completedAt,
  });

  factory SentinelDevice.fromJson(Map<String, dynamic> json) {
    return SentinelDevice.fromMap(json);
  }

  factory SentinelDevice.fromMap(Map<String, dynamic> map) {
    final dhcp = map['dhcp'] as Map<String, dynamic>?;

    return SentinelDevice(
      mac: map['mac']?.toString() ?? '',
      ip:
          dhcp?['ip']?.toString() ??
          map['device_ip']?.toString() ??
          map['ip']?.toString(),
      hostname:
          dhcp?['host']?.toString() ??
          map['device_name']?.toString() ??
          map['hostname']?.toString(),
      vendor: map['vendor']?.toString(),
      switchPort:
          '${map['switch_name'] ?? '??'} Port ${map['port_number'] ?? '??'}',
      status: map['status']?.toString() ?? 'Alive',
      imagingProgress: map['imaging_progress'] is num
          ? (map['imaging_progress'] as num)
                .toInt() // Handle num
          : int.tryParse(
              map['imaging_progress']?.toString() ?? '',
            ), // Handle String
      logs: (map['logs'] as List?)?.map((e) => e.toString()).toList() ?? [],
      switchName: map['switch_name']?.toString(),
      portNumber: map['port_number'] is num
          ? (map['port_number'] as num).toInt()
          : int.tryParse(map['port_number']?.toString() ?? ''),
      dhcp: dhcp,
      activeRunId:
          map['active_run_id']?.toString() ??
          map['run_id']?.toString() ??
          map['activeRunId']?.toString(),
      stage: map['stage']?.toString(),
      speedMbps: map['speed_mbps'] is num
          ? (map['speed_mbps'] as num).toDouble()
          : double.tryParse(map['speed_mbps']?.toString() ?? ''),
      downloadedBytes: map['downloaded_bytes'] is num
          ? (map['downloaded_bytes'] as num).toInt()
          : int.tryParse(map['downloaded_bytes']?.toString() ?? ''),
      totalBytes: map['total_bytes'] is num
          ? (map['total_bytes'] as num).toInt()
          : int.tryParse(map['total_bytes']?.toString() ?? ''),
      completedAt: map['completed_at'] != null
          ? DateTime.tryParse(map['completed_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mac': mac,
      'ip': ip,
      'hostname': hostname,
      'vendor': vendor,
      'switch_port': switchPort,
      'status': status,
      'imaging_progress': imagingProgress,
      'logs': logs,
      'switch_name': switchName,
      'port_number': portNumber,
      'dhcp': dhcp,
      'active_run_id': activeRunId,
      'stage': stage,
      'speed_mbps': speedMbps,
      'downloaded_bytes': downloadedBytes,
      'total_bytes': totalBytes,
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SentinelDevice &&
          mac == other.mac &&
          ip == other.ip &&
          hostname == other.hostname &&
          vendor == other.vendor &&
          status == other.status &&
          imagingProgress == other.imagingProgress &&
          activeRunId == other.activeRunId &&
          stage == other.stage &&
          speedMbps == other.speedMbps &&
          downloadedBytes == other.downloadedBytes &&
          totalBytes == other.totalBytes &&
          switchName == other.switchName &&
          portNumber == other.portNumber &&
          completedAt == other.completedAt;

  @override
  int get hashCode => Object.hash(
    mac,
    ip,
    hostname,
    vendor,
    status,
    imagingProgress,
    activeRunId,
    stage,
    speedMbps,
    downloadedBytes,
    totalBytes,
    switchName,
    portNumber,
    completedAt,
  );

  SentinelDevice copyWith({
    String? mac,
    String? ip,
    String? hostname,
    String? vendor,
    String? switchPort,
    String? status,
    int? imagingProgress,
    List<String>? logs,
    String? switchName,
    int? portNumber,
    Map<String, dynamic>? dhcp,
    String? activeRunId,
    String? stage,
    double? speedMbps,
    int? downloadedBytes,
    int? totalBytes,
    DateTime? completedAt,
  }) {
    return SentinelDevice(
      mac: mac ?? this.mac,
      ip: ip ?? this.ip,
      hostname: hostname ?? this.hostname,
      vendor: vendor ?? this.vendor,
      switchPort: switchPort ?? this.switchPort,
      status: status ?? this.status,
      imagingProgress: imagingProgress ?? this.imagingProgress,
      logs: logs ?? this.logs,
      switchName: switchName ?? this.switchName,
      portNumber: portNumber ?? this.portNumber,
      dhcp: dhcp ?? this.dhcp,
      activeRunId: activeRunId ?? this.activeRunId,
      stage: stage ?? this.stage,
      speedMbps: speedMbps ?? this.speedMbps,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

class SentinelEvent {
  final String type;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  final String? mac;

  SentinelEvent({
    required this.type,
    required this.message,
    required this.timestamp,
    this.data,
    this.mac,
  });

  factory SentinelEvent.fromJson(Map<String, dynamic> json) {
    String type = json['type']?.toString() ?? 'unknown';
    dynamic rawTimestamp = json['timestamp'];
    Map<String, dynamic>? data = json['data'] is Map<String, dynamic>
        ? json['data']
        : null;
    String message = json['message']?.toString() ?? '';
    String? mac = json['mac']?.toString();

    // Handle nested "monitors" events
    if (type == 'monitors' && json['payload'] is Map) {
      final payload = json['payload'];
      type = payload['event_type']?.toString() ?? type;
      rawTimestamp = payload['timestamp'];
      data = payload['data'] is Map<String, dynamic> ? payload['data'] : null;

      // Auto-generate message for monitor events if not present
      if (message.isEmpty) {
        if (type == 'ping_sample') {
          final name = data?['name'] ?? 'Unknown';
          final status = data?['status'] ?? 'unknown';
          final rtt = data?['rtt_ms'];
          message = 'Ping $name: $status${rtt != null ? ' (${rtt}ms)' : ''}';
        } else if (type == 'bandwidth_sample') {
          final up = (data?['upload_mbps'] as num?)?.formatted ?? '0';
          final down =
              (data?['download_mbps'] as num?)?.formatted ?? '0';
          message = 'Bandwidth: Up ${up}Mbps, Down ${down}Mbps';
        } else if (type == 'mac_table_entry') {
          final port = data?['port_name'] ?? '?';
          final mac = data?['mac'] ?? 'unknown';
          final vendor = data?['vendor'] ?? '';
          message = 'Switch Port $port: Detected $mac ($vendor)';
        }
      }
    }

    // Handle initial_snapshot and device_update from new merged websocket
    if ((type == 'device_update' || type == 'initial_snapshot') &&
        (data != null || json.containsKey('devices'))) {
      final devicesData = data?['devices'] ?? json['devices'];
      if (devicesData != null) {
        // This exists to let the provider know it's a bulk update
        type = 'devices_update';
        data = {'devices': devicesData};
      }

      final host = data?['dhcp']?['host'] ?? 'Unknown';
      final port = data?['port_label'] ?? data?['port_number'] ?? '?';
      message = (type == 'initial_snapshot')
          ? 'Snapshot received'
          : 'Device $host detected on $port';
    }

    DateTime timestamp;
    if (rawTimestamp is num) {
      // Assume Unix timestamp in seconds (float or int)
      timestamp = DateTime.fromMillisecondsSinceEpoch(
        (rawTimestamp * 1000).toInt(),
      );
    } else if (rawTimestamp != null) {
      try {
        timestamp = DateTime.parse(rawTimestamp.toString());
      } catch (_) {
        timestamp = DateTime.now();
      }
    } else {
      timestamp = DateTime.now();
    }

    return SentinelEvent(
      type: type,
      message: message,
      timestamp: timestamp,
      data: data,
      mac: mac,
    );
  }
}

class SentinelPort {
  final int portId;
  final int portNumber;
  final String label;
  final String role;
  final bool enabled;
  final String status; // "up", "down", "imaging", "anomaly"
  final SentinelDevice? connectedDevice;
  final String? connectedMac;
  final bool imageEnabled;
  final String? imageEnabledAt;
  final String? selectedImage;

  SentinelPort({
    required this.portId,
    required this.portNumber,
    required this.label,
    required this.role,
    required this.enabled,
    this.status = 'down',
    this.connectedDevice,
    this.connectedMac,
    this.imageEnabled = false,
    this.imageEnabledAt,
    this.selectedImage,
  });

  factory SentinelPort.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic v) {
      if (v == true) return true;
      if (v == 1 || v == '1') return true;
      return false;
    }

    final isEnabled = parseBool(json['enabled']);

    return SentinelPort(
      portId: json['port_id'] is num ? (json['port_id'] as num).toInt() : 0,
      portNumber: json['port_number'] is num
          ? (json['port_number'] as num).toInt()
          : 0,
      label: json['label']?.toString() ?? '',
      role: json['role']?.toString() ?? 'access',
      enabled: isEnabled,
      status: isEnabled ? 'down' : 'disabled',
      imageEnabled: parseBool(json['image_enabled']),
      imageEnabledAt: json['image_enabled_at']?.toString(),
      connectedMac:
          json['connected_mac']?.toString() ?? json['mac']?.toString(),
      selectedImage:
          json['selected_image']?.toString() ??
          json['image']?.toString() ??
          json['current_image']?.toString(),
    );
  }

  SentinelPort copyWith({
    int? portId,
    int? portNumber,
    String? label,
    String? role,
    bool? enabled,
    String? status,
    SentinelDevice? Function()? connectedDevice,
    String? connectedMac,
    bool? imageEnabled,
    String? imageEnabledAt,
    String? selectedImage,
  }) {
    return SentinelPort(
      portId: portId ?? this.portId,
      portNumber: portNumber ?? this.portNumber,
      label: label ?? this.label,
      role: role ?? this.role,
      enabled: enabled ?? this.enabled,
      status: status ?? this.status,
      connectedDevice: connectedDevice != null
          ? connectedDevice()
          : this.connectedDevice,
      connectedMac: connectedMac ?? this.connectedMac,
      imageEnabled: imageEnabled ?? this.imageEnabled,
      imageEnabledAt: imageEnabledAt ?? this.imageEnabledAt,
      selectedImage: selectedImage ?? this.selectedImage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SentinelPort &&
          portId == other.portId &&
          portNumber == other.portNumber &&
          label == other.label &&
          role == other.role &&
          enabled == other.enabled &&
          status == other.status &&
          imageEnabled == other.imageEnabled &&
          selectedImage == other.selectedImage &&
          // device identity
          connectedMac == other.connectedMac &&
          connectedDevice?.mac == other.connectedDevice?.mac &&
          // device UI telemetry
          connectedDevice?.imagingProgress ==
              other.connectedDevice?.imagingProgress &&
          connectedDevice?.stage == other.connectedDevice?.stage &&
          connectedDevice?.speedMbps == other.connectedDevice?.speedMbps &&
          connectedDevice?.downloadedBytes ==
              other.connectedDevice?.downloadedBytes &&
          connectedDevice?.totalBytes == other.connectedDevice?.totalBytes;

  @override
  int get hashCode => Object.hash(
    portId,
    portNumber,
    label,
    role,
    enabled,
    status,
    imageEnabled,
    selectedImage,
    connectedMac,
    connectedDevice?.mac,
    connectedDevice?.imagingProgress,
    connectedDevice?.stage,
    connectedDevice?.speedMbps,
    connectedDevice?.downloadedBytes,
    connectedDevice?.totalBytes,
  );
}

class SentinelSwitch {
  final int switchId;
  final String name;
  final String ip;
  final String vendor;
  final String? location;
  final bool enabled;
  final List<SentinelPort> ports;

  SentinelSwitch({
    required this.switchId,
    required this.name,
    required this.ip,
    required this.vendor,
    this.location,
    required this.enabled,
    this.ports = const [],
  });

  factory SentinelSwitch.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic v) {
      if (v == true) return true;
      if (v == 1 || v == '1') return true;
      return false;
    }

    return SentinelSwitch(
      switchId: json['switch_id'] is num
          ? (json['switch_id'] as num).toInt()
          : 0,
      name: json['name']?.toString() ?? '',
      ip: json['ip']?.toString() ?? '',
      vendor: json['vendor']?.toString() ?? '',
      location: json['location']?.toString(),
      enabled: parseBool(json['enabled']),
      ports:
          (json['ports'] as List?)
              ?.map((p) => SentinelPort.fromJson(p))
              .toList() ??
          [],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SentinelSwitch &&
          runtimeType == other.runtimeType &&
          switchId == other.switchId;

  @override
  int get hashCode => switchId.hashCode;
}

class VirtualTableGroup {
  final String tableName; // e.g., "A-18" or "M3-Table"
  final String switchName;
  final List<SentinelPort> ports;
  final dynamic
  packColor; // Using dynamic for Color to avoid dart:ui import in models if needed, but usually fine in Flutter
  final int? packId; // 1, 2, or 3

  VirtualTableGroup({
    required this.tableName,
    required this.switchName,
    required this.ports,
    this.packColor,
    this.packId,
  });
}
