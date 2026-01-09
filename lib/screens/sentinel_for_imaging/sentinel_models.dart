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
          ? (map['imaging_progress'] as num).toInt()
          : null,
      logs: (map['logs'] as List?)?.map((e) => e.toString()).toList() ?? [],
      switchName: map['switch_name']?.toString(),
      portNumber: map['port_number'] is num
          ? (map['port_number'] as num).toInt()
          : null,
      dhcp: dhcp,
      activeRunId:
          map['active_run_id']?.toString() ??
          map['run_id']?.toString() ??
          map['activeRunId']?.toString(),
      stage: map['stage']?.toString(),
      speedMbps: map['speed_mbps'] is num
          ? (map['speed_mbps'] as num).toDouble()
          : null,
      downloadedBytes: map['downloaded_bytes'] is num
          ? (map['downloaded_bytes'] as num).toInt()
          : null,
      totalBytes: map['total_bytes'] is num
          ? (map['total_bytes'] as num).toInt()
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
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SentinelDevice &&
          runtimeType == other.runtimeType &&
          mac == other.mac;

  @override
  int get hashCode => mac.hashCode;

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
          final up = (data?['upload_mbps'] as num?)?.toStringAsFixed(2) ?? '0';
          final down =
              (data?['download_mbps'] as num?)?.toStringAsFixed(2) ?? '0';
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

  SentinelPort({
    required this.portId,
    required this.portNumber,
    required this.label,
    required this.role,
    required this.enabled,
    this.status = 'down',
    this.connectedDevice,
  });

  factory SentinelPort.fromJson(Map<String, dynamic> json) {
    return SentinelPort(
      portId: json['port_id'] is num ? (json['port_id'] as num).toInt() : 0,
      portNumber: json['port_number'] is num
          ? (json['port_number'] as num).toInt()
          : 0,
      label: json['label']?.toString() ?? '',
      role: json['role']?.toString() ?? 'access',
      enabled: json['enabled'] == true,
      status: json['enabled'] == true ? 'down' : 'disabled',
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
    );
  }
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
    return SentinelSwitch(
      switchId: json['switch_id'] is num
          ? (json['switch_id'] as num).toInt()
          : 0,
      name: json['name']?.toString() ?? '',
      ip: json['ip']?.toString() ?? '',
      vendor: json['vendor']?.toString() ?? '',
      location: json['location']?.toString(),
      enabled: json['enabled'] == true,
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
