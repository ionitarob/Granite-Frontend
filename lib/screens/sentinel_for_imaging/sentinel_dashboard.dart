import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sentinel_provider.dart';
import 'sentinel_models.dart';
import 'device_detail_screen.dart';

import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';
import 'sentinel_theme.dart';
import 'sentinel_stats_dashboard.dart';

class SentinelDashboard extends StatefulWidget {
  const SentinelDashboard({super.key});

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
                    width: 32,
                    currentRoute: routeName,
                    showIndicator: true,
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
    final provider = Provider.of<SentinelProvider>(context);
    final sentinelService = provider.service;

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
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              child: TabBar(
                indicatorColor: Colors.cyanAccent,
                labelColor: Colors.cyanAccent,
                unselectedLabelColor: Colors.white.withOpacity(0.5),
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: 'MESA DE TRABAJO'),
                  Tab(text: 'ESTADÍSTICAS'),
                ],
              ),
            ),
          ),
          body: TabBarView(
            children: [
              // Tab 1: Workspace
              Row(
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
                        Expanded(child: _PortMap()),
                      ],
                    ),
                  ),
                ],
              ),
              // Tab 2: Statistics
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: SentinelStatsDashboard(service: sentinelService),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Option 1 (simple): Consumer for guaranteed repaints
    return Consumer<SentinelProvider>(
      builder: (context, provider, child) {
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
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300,
                  childAspectRatio: 2.0, // Taller Rectangle to prevent overflow
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: recognized.length,
                itemBuilder: (context, index) {
                  final device = recognized[index];
                  return _DeviceListItem(device: device);
                },
              ),
            ),
          ],
        );
      },
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
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: SentinelTheme.primary, size: 20),
              const SizedBox(width: 12),
              Text(
                title.toUpperCase(),
                style: SentinelTheme.header.copyWith(fontSize: 14),
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
                  color: SentinelTheme.warning,
                ),
              ),
              label: const Text(
                'DESCONOCIDO',
                style: TextStyle(
                  color: SentinelTheme.warning,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                backgroundColor: SentinelTheme.warning.withOpacity(0.1),
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
                backgroundColor: SentinelTheme.bgPanel,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: SentinelTheme.warning.withOpacity(0.3),
                  ),
                ),
                title: Row(
                  children: const [
                    Icon(Icons.help_outline, color: SentinelTheme.warning),
                    SizedBox(width: 12),
                    Text('Unrecognized Devices', style: SentinelTheme.header),
                  ],
                ),
                content: SizedBox(
                  width: 400,
                  height: 500,
                  child: unknown.isEmpty
                      ? const Center(
                          child: Text(
                            'No unknown devices found',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          itemCount: unknown.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _DeviceListItem(device: unknown[index]),
                            );
                          },
                        ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'CLOSE',
                      style: TextStyle(color: SentinelTheme.primary),
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

class _DeviceListItem extends StatelessWidget {
  final SentinelDevice device;

  const _DeviceListItem({required this.device});

  @override
  Widget build(BuildContext context) {
    Color statusColor;

    switch (device.status.toLowerCase()) {
      case 'alive':
        statusColor = SentinelTheme.success;
        break;
      case 'imaging':
        statusColor = SentinelTheme.secondary;
        break;
      case 'failure':
        statusColor = SentinelTheme.error;
        break;
      default:
        statusColor = Colors.grey;
    }

    final provider = Provider.of<SentinelProvider>(context);
    final associatedPort = provider.portForDevice(device);
    final bool isImageEnabled = associatedPort?.imageEnabled ?? false;
    final String? selectedImage = associatedPort?.selectedImage;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isImageEnabled
              ? SentinelTheme.secondary.withOpacity(0.3)
              : Colors.transparent,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DeviceDetailScreen(device: device),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Port Badge
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Center(
                    child: Text(
                      '${device.portNumber ?? "?"}',
                      style: SentinelTheme.header.copyWith(
                        color: statusColor,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.hostname ?? device.mac,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SentinelTheme.body.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.hub,
                            size: 10,
                            color: SentinelTheme.textDisabled,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              device.switchPort ?? 'Unknown',
                              style: SentinelTheme.mono.copyWith(fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (selectedImage != null) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.album,
                              size: 10,
                              color: SentinelTheme.secondary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                selectedImage,
                                style: SentinelTheme.label.copyWith(
                                  color: SentinelTheme.secondary,
                                  fontSize: 10,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SentinelProvider>(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: SentinelTheme.primary.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.table_restaurant, // Switch/Table icon
            color: SentinelTheme.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text('ACTIVE SWITCH:', style: SentinelTheme.label),
          const SizedBox(width: 8),
          // Connection Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: provider.isConnected
                  ? SentinelTheme.success.withOpacity(0.1)
                  : SentinelTheme.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: provider.isConnected
                    ? SentinelTheme.success.withOpacity(0.5)
                    : SentinelTheme.error.withOpacity(0.5),
                width: 1,
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
                        ? SentinelTheme.success
                        : SentinelTheme.error,
                    shape: BoxShape.circle,
                    boxShadow: [
                      if (provider.isConnected)
                        BoxShadow(
                          color: SentinelTheme.success.withOpacity(0.6),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  provider.isConnected ? 'EN LINEA' : 'DESCONECTADO',
                  style: SentinelTheme.label.copyWith(
                    color: provider.isConnected
                        ? SentinelTheme.success
                        : SentinelTheme.error,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: SentinelTheme.glassDecoration(
                borderRadius: 8,
                opacity: 0.05,
                border: true,
              ),
              child: PopupMenuButton<SentinelSwitch>(
                tooltip: 'Seleccionar Mesa Activa',
                offset: const Offset(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: SentinelTheme.primary.withOpacity(0.2),
                  ),
                ),
                color: SentinelTheme.bgPanel,
                itemBuilder: (context) {
                  return provider.switches.map((s) {
                    final isSelected =
                        s.switchId == provider.selectedSwitch?.switchId;
                    final isVisible = provider.isSwitchVisible(s.switchId);

                    return PopupMenuItem<SentinelSwitch>(
                      value: s,
                      child: Row(
                        children: [
                          // Visibility Toggle (Eye/Checkbox)
                          InkWell(
                            onTap: () {
                              provider.toggleSwitchVisibility(s.switchId);
                              Navigator.pop(context); // Close menu
                            },
                            child: Icon(
                              isVisible
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              color: isVisible
                                  ? SentinelTheme.success
                                  : Colors.white24,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Main Selection (Title)
                          Expanded(
                            child: Text(
                              '${s.name} (${s.location ?? 'N/A'})',
                              style: SentinelTheme.body.copyWith(
                                color: isSelected
                                    ? SentinelTheme.primary
                                    : Colors.white70,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: SentinelTheme.primary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'ACTIVO',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: SentinelTheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList();
                },
                onSelected: (s) {
                  provider.selectSwitch(s);
                },
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        provider.selectedSwitch?.name ?? 'Seleccionar Switch',
                        style: SentinelTheme.body.copyWith(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_drop_down,
                      color: SentinelTheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              if (provider.selectedSwitch != null) {
                showDialog(
                  context: context,
                  builder: (_) => ChangeNotifierProvider.value(
                    value: provider,
                    child: _SwitchImageDialog(
                      sentinelSwitch: provider.selectedSwitch!,
                    ),
                  ),
                );
              }
            },
            icon: const Icon(
              Icons.settings_system_daydream,
              color: SentinelTheme.secondary,
            ),
            tooltip: 'Configurar Imágenes de Switch',
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
    // If we can't find specific M2/M3, just show selected or all.
    // For now, let's try to show M3 and M2 if they exist, or just the current one if not.
    final targets = <SentinelSwitch>{};
    if (provider.switches.any((s) => s.name.toLowerCase().contains('m3'))) {
      targets.add(
        provider.switches.firstWhere(
          (s) => s.name.toLowerCase().contains('m3'),
        ),
      );
    }
    if (provider.switches.any((s) => s.name.toLowerCase().contains('m2'))) {
      targets.add(
        provider.switches.firstWhere(
          (s) => s.name.toLowerCase().contains('m2'),
        ),
      );
    }

    // Fallback if no specific tables found
    if (targets.isEmpty && provider.selectedSwitch != null) {
      targets.add(provider.selectedSwitch!);
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: SentinelTheme.primary.withOpacity(0.1)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.hub, color: SentinelTheme.primary, size: 18),
                  const SizedBox(width: 12),
                  const Text('MESAS FÍSICAS', style: SentinelTheme.header),
                ],
              ),
              _Legend(),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: provider.visibleSwitches.map((s) {
                return Padding(
                  padding: const EdgeInsets.only(right: 32),
                  child: _PhysicalTableLayout(sentinelSwitch: s),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _item(SentinelTheme.success, 'Activo'),
        const SizedBox(width: 12),
        _item(SentinelTheme.secondary, 'Maquetando'),
        const SizedBox(width: 12),
        _item(Colors.grey, 'Inactivo'),
      ],
    );
  }

  Widget _item(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.5), blurRadius: 4),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: SentinelTheme.label),
      ],
    );
  }
}

class _PhysicalTableLayout extends StatelessWidget {
  final SentinelSwitch sentinelSwitch;

  const _PhysicalTableLayout({required this.sentinelSwitch});

  @override
  Widget build(BuildContext context) {
    // Generate the specific seat pattern: Compact Blocks (2 Rows per Block)
    // Usage: M3 (32 ports) = 4 Blocks. M2 (24 ports) = 3 Blocks.
    //
    // Pattern per block (8 ports):
    // Row 1 (Top):    [7][8]  <gap>  [3][4]
    // Row 2 (Bottom): [5][6]  <gap>  [1][2]
    //
    // This reduces height by 50% compared to the 4-row stack, while keeping the standard
    // vertical block stacking (32..25 top, 8..1 bottom).

    int maxPort = sentinelSwitch.ports.length;
    if (sentinelSwitch.name.toLowerCase().contains('m3')) maxPort = 32;
    if (sentinelSwitch.name.toLowerCase().contains('m2')) maxPort = 24;

    final blockCount = (maxPort / 8).ceil();
    final List<Widget> blockWidgets = [];

    // Build blocks from Top (Highest Port Numbers) to Bottom (Lowest)
    for (int b = blockCount - 1; b >= 0; b--) {
      final offset = b * 8;

      // Row 1: 7,8 ... 3,4
      final row1 = _buildCompactRow(
        context,
        p1: offset + 7,
        p2: offset + 8,
        p3: offset + 3,
        p4: offset + 4,
      );

      // Row 2: 5,6 ... 1,2
      final row2 = _buildCompactRow(
        context,
        p1: offset + 5,
        p2: offset + 6,
        p3: offset + 1,
        p4: offset + 2,
      );

      blockWidgets.add(
        Column(children: [row1, const SizedBox(height: 4), row2]),
      );

      // Gap between blocks
      if (b > 0) {
        blockWidgets.add(const SizedBox(height: 16));
        // Optional: Divider line between blocks?
        // blockWidgets.add(Container(height: 1, color: Colors.white10));
        // blockWidgets.add(const SizedBox(height: 8));
      }
    }

    return Column(
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: SentinelTheme.glassDecoration(
            opacity: 0.1,
            borderRadius: 8,
            border: true,
          ),
          child: Text(
            sentinelSwitch.name.toUpperCase(),
            style: SentinelTheme.header.copyWith(
              color: SentinelTheme.primary,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // The Seats Container
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white10),
            borderRadius: BorderRadius.circular(16),
            color: Colors.black26,
          ),
          child: Column(children: blockWidgets),
        ),
      ],
    );
  }

  Widget _buildCompactRow(
    BuildContext context, {
    required int p1,
    required int p2,
    required int p3,
    required int p4,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Seat(sentinelSwitch: sentinelSwitch, portNum: p1),
        const SizedBox(width: 4),
        _Seat(sentinelSwitch: sentinelSwitch, portNum: p2),
        const SizedBox(width: 24), // Gap between pairing
        _Seat(sentinelSwitch: sentinelSwitch, portNum: p3),
        const SizedBox(width: 4),
        _Seat(sentinelSwitch: sentinelSwitch, portNum: p4),
      ],
    );
  }
}

class _Seat extends StatelessWidget {
  final SentinelSwitch sentinelSwitch;
  final int portNum;

  const _Seat({required this.sentinelSwitch, required this.portNum});

  @override
  Widget build(BuildContext context) {
    // Find the port
    final port = sentinelSwitch.ports.firstWhere(
      (p) => p.portNumber == portNum,
      orElse: () => SentinelPort(
        portId: 0,
        portNumber: portNum,
        label: '',
        role: '',
        enabled: false,
        status: 'disabled',
      ),
    );

    // Look up live device
    final provider = Provider.of<SentinelProvider>(context);
    final liveDevice = provider.deviceByMac(port.connectedMac);

    Color color = Colors.grey[800]!;
    Color textColor = Colors.white54;
    Color glowColor = Colors.transparent;
    bool isGlowing = false;

    if (liveDevice != null && liveDevice.stage != null) {
      final s = liveDevice.stage!.toLowerCase();
      if (s == 'wim_apply_done' || s == 'done') {
        color = SentinelTheme.success;
        textColor = Colors.black;
        glowColor = SentinelTheme.success;
        isGlowing = true;
      } else if (s.contains('apply')) {
        color = Colors.purpleAccent;
        textColor = Colors.white;
        glowColor = Colors.purpleAccent;
        isGlowing = true;
      } else {
        // Imaging/Downloading
        color = SentinelTheme.secondary;
        textColor = Colors.white;
        glowColor = SentinelTheme.secondary;
        isGlowing = true;
      }
    } else if (port.enabled) {
      if (port.connectedMac != null) {
        color = SentinelTheme.success.withOpacity(0.2);
        textColor = SentinelTheme.success;
        glowColor = SentinelTheme.success;
      } else {
        // Enabled but Empty
        color = Colors.white10;
        textColor = Colors.white24;
      }
    } else {
      // STRICTLY DISABLED based on phantom ports logic
      // If it's in the map but disabled, show as empty/dark
      color = Colors.black;
      textColor = Colors.white10;
    }

    return Tooltip(
      message:
          'Puerto: ${port.label}\nEstado: ${port.status}\nRol: ${port.role}${port.imageEnabled ? '\nImagen: ${port.selectedImage ?? "N/A"}' : ''}${liveDevice != null ? '\nHost: ${liveDevice.hostname}\nIP: ${liveDevice.ip}' : ''}',
      child: InkWell(
        onTap: () {
          // Use the passed sentinelSwitch as the parent switch
          showDialog(
            context: context,
            builder: (_) => ChangeNotifierProvider.value(
              value: Provider.of<SentinelProvider>(context, listen: false),
              child: _PortDetailDialog(
                port: port,
                parentSwitch: sentinelSwitch,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 60,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isGlowing ? glowColor.withOpacity(0.6) : Colors.white12,
              width: isGlowing ? 1.5 : 1.0,
            ),
            boxShadow: [
              if (isGlowing)
                BoxShadow(
                  color: glowColor.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  '$portNum',
                  style: SentinelTheme.mono.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    shadows: isGlowing
                        ? [
                            BoxShadow(
                              color: glowColor,
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              if (liveDevice != null)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.8),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              if (port.imageEnabled)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Icon(
                    Icons.download_for_offline,
                    color: SentinelTheme.secondary,
                    size: 8,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchImageDialog extends StatefulWidget {
  final SentinelSwitch sentinelSwitch;

  const _SwitchImageDialog({required this.sentinelSwitch});

  @override
  State<_SwitchImageDialog> createState() => _SwitchImageDialogState();
}

class _SwitchImageDialogState extends State<_SwitchImageDialog> {
  String? _selectedImage;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    // Refresh images when dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SentinelProvider>(
        context,
        listen: false,
      ).loadAvailableImages();
      _fetchCurrentSelection();
    });
  }

  Future<void> _fetchCurrentSelection() async {
    final provider = Provider.of<SentinelProvider>(context, listen: false);
    final selection = await provider.fetchImageSelection(
      scope: 'switch',
      scopeId: widget.sentinelSwitch.switchId,
    );

    if (mounted && selection != null) {
      setState(() {
        _enabled = selection['enabled'] == true;
        // Backend might send null or empty string for no image
        final img = selection['image']?.toString();
        _selectedImage = (img != null && img.isNotEmpty) ? img : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SentinelProvider>(context);
    final images = provider.availableImages;

    return AlertDialog(
      backgroundColor: SentinelTheme.bgPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: SentinelTheme.primary.withOpacity(0.3)),
      ),
      title: Text(
        'Configuración de Switch: ${widget.sentinelSwitch.name}',
        style: SentinelTheme.header,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Esta configuración se aplicara a TODOS los puertos.',
            style: SentinelTheme.body.copyWith(
              color: SentinelTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text('Habilitar Maquetado', style: SentinelTheme.body),
            subtitle: Text(
              'Permitir despliegue de imágenes',
              style: SentinelTheme.label.copyWith(
                color: SentinelTheme.textSecondary,
                fontWeight: FontWeight.normal,
              ),
            ),
            value: _enabled,
            onChanged: (val) => setState(() => _enabled = val),
            activeColor: SentinelTheme.secondary,
          ),
          const SizedBox(height: 20),
          Text(
            'Seleccionar Imagen:',
            style: SentinelTheme.subHeader.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          if (provider.imagesError != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: SentinelTheme.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: SentinelTheme.error.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: SentinelTheme.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Error cargando imágenes: ${provider.imagesError}',
                      style: SentinelTheme.label.copyWith(color: SentinelTheme.error),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: SentinelTheme.glassDecoration(
              borderRadius: 8,
              opacity: 0.05,
              border: true,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedImage,
                hint: Text(
                  'Selecc. Imagen (WIM/ESD/Dual-Boot)',
                  style: SentinelTheme.body.copyWith(
                    color: SentinelTheme.textDisabled,
                  ),
                ),
                dropdownColor: SentinelTheme.bgPanel,
                isExpanded: true,
                style: SentinelTheme.body.copyWith(color: Colors.white),
                icon: const Icon(
                  Icons.arrow_drop_down,
                  color: SentinelTheme.primary,
                ),
                items: [
                  ...images.map((img) {
                    final name = img['name']?.toString() ?? '';
                    final isDualBoot = img['type']?.toString() == 'dualboot';
                    return DropdownMenuItem<String>(
                      value: name,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: SentinelTheme.body.copyWith(
                                color: isDualBoot ? Colors.purple[200] : Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDualBoot
                                  ? Colors.purple.withOpacity(0.25)
                                  : Colors.cyan.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isDualBoot ? Colors.purple : Colors.cyan,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              isDualBoot ? 'DUAL-BOOT' : 'WIM',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isDualBoot ? Colors.purple[100] : Colors.cyan[200],
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  // Archived fallback
                  if (_selectedImage != null &&
                      _selectedImage!.isNotEmpty &&
                      !images.any((img) => img['name'] == _selectedImage))
                    DropdownMenuItem<String>(
                      value: _selectedImage,
                      child: Text(
                        '$_selectedImage (Archived)',
                        style: SentinelTheme.body.copyWith(
                          fontStyle: FontStyle.italic,
                          color: SentinelTheme.warning,
                        ),
                      ),
                    ),
                ],
                onChanged: (val) => setState(() => _selectedImage = val),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'CANCELAR',
            style: SentinelTheme.body.copyWith(
              color: SentinelTheme.textDisabled,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () async {
            // Allow disabling even if image is null
            if (_selectedImage == null && _enabled) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Debe seleccionar una imagen para habilitar el maquetado',
                  ),
                  backgroundColor: SentinelTheme.error,
                ),
              );
              return;
            }

            try {
              await provider.setImageSelection(
                scope: 'switch',
                scopeId: widget.sentinelSwitch.switchId,
                image: _enabled ? (_selectedImage ?? '') : '',
                enabled: _enabled,
              );

              if (mounted) Navigator.pop(context);
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error guardando: $e')));
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: SentinelTheme.secondary,
            foregroundColor: Colors.white,
          ),
          child: const Text('APLICAR A TODOS'),
        ),
      ],
    );
  }
}

class _PortDetailDialog extends StatefulWidget {
  final SentinelPort port;
  final SentinelSwitch parentSwitch;

  const _PortDetailDialog({required this.port, required this.parentSwitch});

  @override
  State<_PortDetailDialog> createState() => _PortDetailDialogState();
}

class _PortDetailDialogState extends State<_PortDetailDialog> {
  late bool _enabled;
  String? _selectedImage;

  @override
  void initState() {
    super.initState();
    _enabled = widget.port.imageEnabled;
    _selectedImage = widget.port.selectedImage;
    // Refresh images when dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SentinelProvider>(
        context,
        listen: false,
      ).loadAvailableImages();
      _fetchCurrentSelection();
    });
  }

  Future<void> _fetchCurrentSelection() async {
    final provider = Provider.of<SentinelProvider>(context, listen: false);
    final selection = await provider.fetchImageSelection(
      scope: 'port',
      scopeId: widget.port.portId,
    );

    if (mounted && selection != null) {
      setState(() {
        _enabled = selection['enabled'] == true;
        // Backend might send null or empty string for no image
        final img = selection['image']?.toString();
        _selectedImage = (img != null && img.isNotEmpty) ? img : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SentinelProvider>(context);
    final images = provider.availableImages;

    return AlertDialog(
      backgroundColor: SentinelTheme.bgPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: SentinelTheme.primary.withOpacity(0.3)),
      ),
      title: Row(
        children: [
          const Icon(Icons.settings_ethernet, color: SentinelTheme.primary),
          const SizedBox(width: 12),
          Text('Puerto ${widget.port.portNumber}', style: SentinelTheme.header),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Etiqueta', widget.port.label),
            _buildInfoRow('Estado', widget.port.status.toUpperCase()),
            _buildInfoRow('Rol', widget.port.role.toUpperCase()),
            if (widget.port.connectedDevice != null) ...[
              const Divider(color: Colors.white10),
              _buildInfoRow(
                'Dispositivo',
                widget.port.connectedDevice!.hostname ?? 'Desconocido',
              ),
              _buildInfoRow('MAC', widget.port.connectedDevice!.mac),
              _buildInfoRow('IP', widget.port.connectedDevice!.ip ?? '-'),
            ],
            const Divider(color: Colors.white10, height: 32),
            Text(
              'CONFIGURACIÓN MAQUETADO',
              style: SentinelTheme.header.copyWith(
                color: SentinelTheme.secondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Habilitar Maquetado',
                style: SentinelTheme.body,
              ),
              subtitle: Text(
                widget.port.imageEnabledAt != null
                    ? 'Habilitado en: ${widget.port.imageEnabledAt}'
                    : 'Estado: ${widget.port.imageEnabled ? "Activo" : "Inactivo"}',
                style: SentinelTheme.label.copyWith(
                  color: SentinelTheme.textSecondary,
                  fontWeight: FontWeight.normal,
                ),
              ),
              value: _enabled,
              onChanged: (val) => setState(() => _enabled = val),
              activeColor: SentinelTheme.secondary,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: SentinelTheme.glassDecoration(
                borderRadius: 8,
                opacity: 0.05,
                border: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedImage,
                  hint: Text(
                    'Seleccionar Imagen',
                    style: SentinelTheme.body.copyWith(
                      color: SentinelTheme.textDisabled,
                    ),
                  ),
                  dropdownColor: SentinelTheme.bgPanel,
                  isExpanded: true,
                  style: SentinelTheme.body.copyWith(color: Colors.white),
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: SentinelTheme.primary,
                  ),
                  items: [
                    ...images.map((img) {
                      final name = img['name']?.toString() ?? '';
                      final isDualBoot = img['type']?.toString() == 'dualboot';
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                style: SentinelTheme.body.copyWith(
                                  color: isDualBoot ? Colors.purple[200] : Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDualBoot
                                    ? Colors.purple.withOpacity(0.25)
                                    : Colors.cyan.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isDualBoot ? Colors.purple : Colors.cyan,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                isDualBoot ? 'DUAL-BOOT' : 'WIM',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: isDualBoot ? Colors.purple[100] : Colors.cyan[200],
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    // Archived fallback
                    if (_selectedImage != null &&
                        _selectedImage!.isNotEmpty &&
                        !images.any((img) => img['name'] == _selectedImage))
                      DropdownMenuItem<String>(
                        value: _selectedImage,
                        child: Text(
                          '$_selectedImage (Archived)',
                          style: SentinelTheme.body.copyWith(
                            fontStyle: FontStyle.italic,
                            color: SentinelTheme.warning,
                          ),
                        ),
                      ),
                  ],
                  onChanged: (val) => setState(() => _selectedImage = val),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'CANCELAR',
            style: SentinelTheme.body.copyWith(
              color: SentinelTheme.textDisabled,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () async {
            if (_selectedImage == null && _enabled) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Debe seleccionar una imagen para habilitar el maquetado',
                  ),
                  backgroundColor: SentinelTheme.error,
                ),
              );
              return;
            }

            try {
              await provider.setImageSelection(
                scope: 'port',
                scopeId: widget.port.portId,
                image: _enabled ? (_selectedImage ?? '') : '',
                enabled: _enabled,
              );

              if (mounted) Navigator.pop(context);
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error guardando: $e'),
                    backgroundColor: SentinelTheme.error,
                  ),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: SentinelTheme.secondary,
            foregroundColor: Colors.white,
          ),
          child: const Text('GUARDAR'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
