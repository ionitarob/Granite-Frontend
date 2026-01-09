import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sentinel_provider.dart';
import 'sentinel_models.dart';
import 'device_detail_screen.dart';

import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';

class SentinelDashboard extends StatefulWidget {
  const SentinelDashboard({Key? key}) : super(key: key);

  @override
  State<SentinelDashboard> createState() => _SentinelDashboardState();
}

class _SentinelDashboardState extends State<SentinelDashboard> {
  OverlayEntry? _edgeOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final routeName = ModalRoute.of(context)?.settings.name;
        final overlay = Overlay.of(context, rootOverlay: true);
        _edgeOverlay = OverlayEntry(
          builder: (ctx) {
            return Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: EdgeNavHandle(
                    user: Provider.of<ApiService>(
                      ctx,
                      listen: false,
                    ).currentUser,
                    width: 28,
                    currentRoute: routeName,
                  ),
                ),
              ),
            );
          },
        );
        overlay.insert(_edgeOverlay!);
      }
    });
  }

  @override
  void dispose() {
    _edgeOverlay?.remove();
    _edgeOverlay = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Using a dark theme for the dashboard to give it a "command center" feel
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        cardColor: const Color(0xFF2C2C2C),
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.blueAccent,
          surface: Color(0xFF2C2C2C),
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Row(
          children: [
            // Device List Section
            Expanded(
              flex: 3,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.white10)),
                ),
                child: _DeviceList(),
              ),
            ),
            // Right Panel: Topology & Events
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  _SwitchSelector(),
                  const Divider(height: 1, color: Colors.white10),
                  Expanded(flex: 2, child: _PortMap()),
                  const Divider(height: 1, color: Colors.white10),
                  Expanded(flex: 2, child: _ActiveImagingPanel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SentinelProvider>(context);

    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyanAccent),
      );
    }

    final recognized = provider.recognizedDevices;
    final unrecognizedCount = provider.unrecognizedDevices.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          'Equipos Conectados',
          Icons.devices,
          unrecognizedCount,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: recognized.length,
            itemBuilder: (context, index) {
              final device = recognized[index];
              return _DeviceCard(device: device);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    String title,
    IconData icon, [
    int unrecognizedCount = 0,
  ]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 12),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          if (unrecognizedCount > 0)
            TextButton.icon(
              onPressed: () => _showUnrecognizedDevices(context),
              icon: Badge(
                label: Text(unrecognizedCount.toString()),
                child: const Icon(
                  Icons.help_outline,
                  size: 18,
                  color: Colors.orangeAccent,
                ),
              ),
              label: const Text(
                'DESCONOCIDOS',
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                backgroundColor: Colors.orangeAccent.withOpacity(0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showUnrecognizedDevices(BuildContext context) {
    final provider = Provider.of<SentinelProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) {
        return ChangeNotifierProvider.value(
          value: provider,
          child: Consumer<SentinelProvider>(
            builder: (context, provider, child) {
              final unknown = provider.unrecognizedDevices;

              return AlertDialog(
                backgroundColor: const Color(0xFF1E1E1E),
                title: Row(
                  children: const [
                    Icon(Icons.help_outline, color: Colors.orangeAccent),
                    SizedBox(width: 12),
                    Text(
                      'Equipos No Reconocidos',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 400,
                  height: 500,
                  child: unknown.isEmpty
                      ? const Center(
                          child: Text(
                            'No se detectaron otros equipos',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          itemCount: unknown.length,
                          itemBuilder: (context, index) {
                            return _DeviceCard(device: unknown[index]);
                          },
                        ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'CERRAR',
                      style: TextStyle(color: Colors.cyanAccent),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final SentinelDevice device;

  const _DeviceCard({Key? key, required this.device}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;

    switch (device.status.toLowerCase()) {
      case 'alive':
        statusColor = Colors.greenAccent;
        statusIcon = Icons.check_circle_outline;
        break;
      case 'imaging':
        statusColor = Colors.blueAccent;
        statusIcon = Icons.downloading;
        break;
      case 'failure':
        statusColor = Colors.redAccent;
        statusIcon = Icons.error_outline;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: const Color(0xFF252525),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.white.withOpacity(0.05)),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DeviceDetailScreen(device: device),
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: statusColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.hostname ?? device.mac,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildBadge(device.ip ?? 'Sin IP', Colors.white54),
                        const SizedBox(width: 8),
                        _buildBadge(
                          device.switchPort ?? 'Desconocido',
                          Colors.white54,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (device.status == 'Imaging')
                SizedBox(
                  width: 60,
                  child: Column(
                    children: [
                      Text(
                        '${device.imagingProgress}%',
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: (device.imagingProgress ?? 0) / 100,
                        backgroundColor: Colors.blueAccent.withOpacity(0.2),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.blueAccent,
                        ),
                        minHeight: 4,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}

class _SwitchSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SentinelProvider>(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF1E1E1E),
      child: Row(
        children: [
          const Icon(
            Icons.table_restaurant,
            color: Colors.cyanAccent,
            size: 20,
          ),
          const SizedBox(width: 12),
          const Text(
            'MESA ACTIVA:',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 8),
          // Connection Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: provider.isConnected
                  ? Colors.greenAccent.withOpacity(0.1)
                  : Colors.redAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: provider.isConnected
                    ? Colors.greenAccent
                    : Colors.redAccent,
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: provider.isConnected
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      if (provider.isConnected)
                        BoxShadow(
                          color: Colors.greenAccent.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  provider.isConnected ? 'EN VIVO' : 'DESCONECTADO',
                  style: TextStyle(
                    color: provider.isConnected
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<SentinelSwitch>(
                  value: provider.selectedSwitch,
                  dropdownColor: const Color(0xFF2C2C2C),
                  isExpanded: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  items: provider.switches.map((s) {
                    return DropdownMenuItem(
                      value: s,
                      child: Text(
                        '${s.name} (${s.location ?? 'Sin Ubicación'})',
                      ),
                    );
                  }).toList(),
                  onChanged: (s) {
                    if (s != null) provider.selectSwitch(s);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortMap extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SentinelProvider>(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.hub, color: Colors.cyanAccent, size: 18),
                  const SizedBox(width: 12),
                  Text(
                    provider.selectedSwitch?.name.toUpperCase() ??
                        'TOPOLOGÍA DE RED',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              _buildLegend(),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF181818),
            child: GridView.builder(
              padding: const EdgeInsets.all(24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 60,
                childAspectRatio: 1.0,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: provider.ports.length,
              itemBuilder: (context, index) {
                final port = provider.ports[index];
                return _PortItem(port: port);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegend() {
    return Row(
      children: [
        _legendItem(Colors.greenAccent, 'Activo'),
        const SizedBox(width: 12),
        _legendItem(Colors.blueAccent, 'Imagen'),
        const SizedBox(width: 12),
        _legendItem(Colors.grey, 'Inactivo'),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }
}

class _PortItem extends StatelessWidget {
  final SentinelPort port;

  const _PortItem({Key? key, required this.port}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color color = Colors.grey[700]!;
    Color glowColor = Colors.transparent;

    // 1. Check for granular imaging stages first (High Priority)
    if (port.connectedDevice != null && port.connectedDevice!.stage != null) {
      final stage = port.connectedDevice!.stage!;
      if (stage == 'STREAMING') {
        color = Colors.yellowAccent;
        glowColor = Colors.yellowAccent.withOpacity(0.6);
      } else if (stage == 'APPLYING' || stage == 'WIM_APPLY_START') {
        color = Colors.purpleAccent;
        glowColor = Colors.purpleAccent.withOpacity(0.6);
      } else if (stage == 'DONE') {
        color = Colors.greenAccent;
        glowColor = Colors.greenAccent.withOpacity(0.4);
      }
    }

    // 2. If no specific stage color was set, fall back to standard port status
    if (color == Colors.grey[700]!) {
      switch (port.status) {
        case 'up':
          color = Colors.greenAccent;
          glowColor = Colors.greenAccent.withOpacity(0.4);
          break;
        case 'imaging':
          color = Colors.blueAccent;
          glowColor = Colors.blueAccent.withOpacity(0.4);
          break;
        case 'anomaly':
          color = Colors.orangeAccent;
          glowColor = Colors.orangeAccent.withOpacity(0.4);
          break;
        default:
          color = Colors.grey[700]!;
          glowColor = Colors.transparent;
      }
    }

    return Tooltip(
      message:
          'Puerto: ${port.label}\nEstado: ${port.status}\nRol: ${port.role}${port.connectedDevice != null ? '\nEquipo: ${port.connectedDevice!.hostname}\nIP: ${port.connectedDevice!.ip}' : ''}',
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF222222),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.5), width: 1.5),
          boxShadow: [
            BoxShadow(color: glowColor, blurRadius: 8, spreadRadius: 0),
          ],
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    port.portNumber.toString(),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  if (port.connectedDevice != null)
                    const Icon(Icons.computer, color: Colors.white54, size: 10),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ... (Replace _EventFeed with _ActiveImagingPanel)
class _ActiveImagingPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SentinelProvider>(context);
    final imagingDevices = provider.devices
        .where(
          (d) => d.status.toLowerCase() == 'imaging' || d.activeRunId != null,
        )
        .toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              const Icon(Icons.downloading, color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 12),
              Text(
                'ACTIVE IMAGING (${imagingDevices.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF0F0F0F),
            child: imagingDevices.isEmpty
                ? const Center(
                    child: Text(
                      "No active imaging processes",
                      style: TextStyle(color: Colors.white24),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: imagingDevices.length,
                    separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final device = imagingDevices[index];
                      return _ImagingCard(device: device);
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _ImagingCard extends StatelessWidget {
  final SentinelDevice device;

  const _ImagingCard({Key? key, required this.device}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color progressColor = Colors.blueAccent;
    String statusText = device.stage ?? 'IMAGING';

    // Stage-based styling
    if (device.stage == 'STREAMING') {
      progressColor = Colors.yellowAccent;
      statusText = 'DOWNLOADING IMAGE';
    } else if (device.stage == 'APPLYING' ||
        device.stage == 'WIM_APPLY_START') {
      progressColor = Colors.purpleAccent;
      statusText = 'APPLYING WIM';
    }

    // Calculate Data
    String dataText = '0.00 GB / 0.00 GB';
    if (device.downloadedBytes != null &&
        device.totalBytes != null &&
        device.totalBytes! > 0) {
      final dl = (device.downloadedBytes! / (1024 * 1024 * 1024))
          .toStringAsFixed(2);
      final total = (device.totalBytes! / (1024 * 1024 * 1024)).toStringAsFixed(
        2,
      );
      dataText = '$dl GB / $total GB';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.hostname ?? device.mac,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device.switchPort ?? 'Unknown Port',
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: progressColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: progressColor.withOpacity(0.5)),
                ),
                child: Text(
                  statusText.toUpperCase(),
                  style: TextStyle(
                    color: progressColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Metrics
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(device.imagingProgress ?? 0)}%',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              if (device.speedMbps != null)
                Text(
                  '${device.speedMbps!.toStringAsFixed(1)} Mbps',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (device.imagingProgress ?? 0) / 100,
            backgroundColor: Colors.white10,
            color: progressColor,
            minHeight: 6,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              dataText,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}
