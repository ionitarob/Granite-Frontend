import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'dart:convert';
import 'sentinel_models.dart';
import '../../services/api_service.dart';

class DeviceDetailScreen extends StatefulWidget {
  final SentinelDevice device;

  const DeviceDetailScreen({super.key, required this.device});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  // Local state to track real-time updates
  late int _imagingProgress;
  late String _status;
  late List<String> _logs;
  String? _currentStep;
  double? _speedMbps;

  // WebSocket
  WebSocketChannel? _channel;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    // Initialize state from widget
    _imagingProgress = widget.device.imagingProgress ?? 0;
    _status = widget.device.status;
    _logs = List.from(widget.device.logs);

    if (widget.device.activeRunId != null) {
      _connectToTelemetry(widget.device.activeRunId!);
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  void _connectToTelemetry(String runId) {
    try {
      // Construct URL: ws://10.20.31.10:7000/ws/runs/<run_id>/
      final url = 'ws://10.20.31.10:7000/ws/runs/$runId/';
      print('Connecting to Telemetry WS: $url');

      final token = ApiService.instance?.client.accessToken;
      final Map<String, dynamic> headers = {};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      _channel = IOWebSocketChannel.connect(Uri.parse(url), headers: headers);

      _channel!.stream.listen(
        (data) {
          if (!_isConnected) {
            setState(() => _isConnected = true);
          }
          _handleTelemetryEvent(data);
        },
        onDone: () {
          print('Telemetry socket closed');
          if (mounted) setState(() => _isConnected = false);
        },
        onError: (error) {
          print('Telemetry socket error: $error');
          if (mounted) setState(() => _isConnected = false);
        },
      );
    } catch (e) {
      print('Error connecting to telemetry: $e');
    }
  }

  void _handleTelemetryEvent(dynamic data) {
    if (!mounted) return;
    try {
      final Map<String, dynamic> event = jsonDecode(data.toString());
      // Structure: { kind: "...", payload: "..." or {...}, emitted_at: "..." }

      final String kind = event['kind']?.toString() ?? 'unknown';
      dynamic payload = event['payload'];

      // Payload might be a stringified JSON
      if (payload is String) {
        try {
          payload = jsonDecode(payload);
        } catch (_) {
          // Keep as string if not JSON
        }
      }

      setState(() {
        if (kind == 'pipeline_update' || kind == 'status_update') {
          // Handle the new stages
          final stage =
              payload['stage']?.toString() ?? payload['status']?.toString();

          if (stage != null) {
            switch (stage) {
              case 'CONNECTING':
              case 'STREAM_READY':
                _status = 'Imaging';
                _currentStep = 'Initializing Stream...';
                break;
              case 'STREAMING':
                _status = 'Imaging';
                _currentStep = 'Downloading Image...';
                // Expect percentage/speed in payload if available
                if (payload['percentage'] != null) {
                  _imagingProgress = (payload['percentage'] as num).toInt();
                }
                if (payload['speed_mbps'] != null) {
                  _speedMbps = (payload['speed_mbps'] as num).toDouble();
                }
                break;
              case 'APPLYING':
              case 'WIM_APPLY_START':
                _status = 'Imaging';
                _currentStep = 'Applying Image...';
                _imagingProgress = 100; // Download done
                break;
              case 'WIM_APPLY_DONE':
                _status = 'Imaging';
                _currentStep = 'Finalizing...';
                break;
              case 'DONE':
                _status = 'Alive';
                _currentStep = 'Completed';
                _imagingProgress = 100;
                break;
              case 'RETRY':
                _status = 'Imaging';
                _currentStep = 'Retrying Connection...';
                break;
              default:
                // Fallback for other status updates
                _currentStep = stage;
            }
          }
        }
        // Keep backward compatibility for 'download_progress' if that's still sent separately
        else if (kind == 'download_progress' && payload is Map) {
          final pct = payload['percentage'];
          final speed = payload['speed_mbps'];
          if (pct is num) _imagingProgress = pct.toInt();
          if (speed is num) _speedMbps = speed.toDouble();

          if (_status.toLowerCase() != 'imaging') {
            _status = 'Imaging';
          }
        } else if (kind == 'log' && payload is Map) {
          final msg = payload['message']?.toString();
          if (msg != null) {
            _logs.insert(0, msg);
          }
        }
      });
    } catch (e) {
      print('Error parsing telemetry event: $e');
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'alive':
        return Colors.greenAccent;
      case 'imaging':
        return Colors.blueAccent;
      case 'failure':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.blueAccent,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            (widget.device.hostname ?? widget.device.mac).toUpperCase(),
            style: const TextStyle(letterSpacing: 1.2, fontSize: 16),
          ),
          actions: [
            if (_isConnected)
              Container(
                margin: const EdgeInsets.only(right: 12),
                child: const Icon(
                  Icons.flash_on,
                  color: Colors.greenAccent,
                  size: 16,
                ),
              ),
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getStatusColor(_status).withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _getStatusColor(_status)),
              ),
              child: Center(
                child: Text(
                  _status.toUpperCase(),
                  style: TextStyle(
                    color: _getStatusColor(_status),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              // Debug Connection Status
              Container(
                padding: const EdgeInsets.all(8),
                color: _isConnected
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                child: Row(
                  children: [
                    Icon(
                      _isConnected ? Icons.link : Icons.link_off,
                      color: _isConnected
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isConnected
                            ? 'CONNECTED to Telemetry Stream'
                            : 'DISCONNECTED (Waiting for data...)',
                        style: TextStyle(
                          color: _isConnected
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.device.activeRunId != null)
                      Text(
                        'ID: ${widget.device.activeRunId}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('DEVICE INFORMATION'),
              const SizedBox(height: 16),
              _buildInfoGrid(),
              const SizedBox(height: 32),
              _buildSectionTitle('ACTIONS'),
              const SizedBox(height: 16),
              _buildActionButtons(context),
              const SizedBox(height: 32),
              _buildSectionTitle('SYSTEM LOGS'),
              const SizedBox(height: 16),
              _buildLogs(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.cyanAccent.withOpacity(0.5),
              width: 2,
            ),
          ),
          child: const Icon(Icons.computer, size: 40, color: Colors.cyanAccent),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.device.hostname ?? 'Unknown Host',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.device.mac,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.5),
                  fontFamily: 'Courier',
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Run ID: ${widget.device.activeRunId ?? "None"}',
                style: TextStyle(
                  color: widget.device.activeRunId != null
                      ? Colors.cyanAccent
                      : Colors.grey,
                  fontSize: 10,
                ),
              ),
              if (_currentStep != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Step: $_currentStep',
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.cyanAccent,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildInfoGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.5,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      children: [
        _buildInfoCard(Icons.wifi, 'IP Address', widget.device.ip ?? 'N/A'),
        _buildInfoCard(
          Icons.business,
          'Vendor',
          widget.device.vendor ?? 'Unknown',
        ),
        _buildInfoCard(
          Icons.hub,
          'Switch Port',
          widget.device.switchPort ?? 'Unknown',
        ),
        // Progress Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              const Icon(Icons.downloading, color: Colors.white54, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'IMAGING PROGRESS',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_speedMbps != null)
                          Text(
                            '${_speedMbps!.toStringAsFixed(1)} Mbps',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: _imagingProgress / 100,
                            backgroundColor: Colors.white10,
                            color: Colors.blueAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$_imagingProgress%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            context,
            'Restart Port',
            Icons.refresh,
            Colors.orangeAccent,
            () {},
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildActionButton(
            context,
            'Start Imaging',
            Icons.system_update,
            Colors.blueAccent,
            () {},
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildActionButton(
            context,
            'Wake-on-LAN',
            Icons.power_settings_new,
            Colors.greenAccent,
            () {},
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return ElevatedButton(
      onPressed: () {
        onPressed();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Executing: $label'),
            backgroundColor: const Color(0xFF333333),
          ),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withOpacity(0.5)),
        ),
        elevation: 0,
      ),
      child: Column(
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildLogs() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ListView.builder(
        itemCount: _logs.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '> ${_logs[index]}',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontFamily: 'Courier',
                fontSize: 13,
              ),
            ),
          );
        },
      ),
    );
  }
}
