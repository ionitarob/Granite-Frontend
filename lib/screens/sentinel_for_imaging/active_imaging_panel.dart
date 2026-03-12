import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sentinel_provider.dart';
import 'sentinel_models.dart';
import 'sentinel_theme.dart';
import 'dart:math' as math;

class ActiveImagingPanel extends StatelessWidget {
  const ActiveImagingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SentinelProvider>(context);

    final allDevices = provider.monitoredDevices.where((d) {
      return d.status.toLowerCase() == 'imaging' || d.activeRunId != null;
    }).toList();

    final activeDevices = allDevices.where((d) {
      final s = d.stage?.toLowerCase() ?? '';
      return s != 'done' &&
          s != 'wim_apply_done' &&
          s != 'finished' &&
          s != 'failed' &&
          s != 'wim_apply_failed';
    }).toList();

    final completedDevices = allDevices.where((d) {
      final s = d.stage?.toLowerCase() ?? '';
      return s == 'done' ||
          s == 'finished' ||
          s == 'wim_apply_done' ||
          s == 'failed' ||
          s == 'wim_apply_failed';
    }).toList();

    // 2. Sort Lists
    // Active: High progress first (Almost done -> Just began)
    activeDevices.sort((a, b) {
      final pA = a.imagingProgress ?? 0;
      final pB = b.imagingProgress ?? 0;
      return pB.compareTo(pA); // Descending
    });

    // Completed: Most recent finish first
    completedDevices.sort((a, b) {
      // Fallback to activeRunId roughly if date missing (though we added date)
      final tA = a.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tB = b.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tB.compareTo(tA); // Descending
    });

    // 3. Dynamic Sizing Logic
    return LayoutBuilder(
      builder: (context, constraints) {
        final double totalHeight = constraints.maxHeight;
        final double dividerHeight = 1.0;
        final double availableHeight = totalHeight - dividerHeight;

        final int cActive = activeDevices.length;
        final int cCompleted = completedDevices.length;
        final int totalCount = cActive + cCompleted;

        double activeRatio = 0.66; // Default bias towards active

        if (totalCount > 0) {
          activeRatio = cActive / totalCount;
        }

        // Clamp to ensure neither section disappears completely
        // Keep at least 25% for headers/empty state visibility
        activeRatio = activeRatio.clamp(0.25, 0.75);

        // If no active but has completed, give completed more space (activeRatio small)
        // calculated ratio naturally does this: 0/10 -> 0 -> clamped to 0.25. (Active 25%, Completed 75%)
        // If no completed but has active: 10/10 -> 1 -> clamped to 0.75. (Active 75%, Completed 25%)

        final double hActive = availableHeight * activeRatio;
        final double hCompleted = availableHeight - hActive;

        return Column(
          children: [
            // --- TOP PART (Active) ---
            AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOutCubic,
              height: hActive,
              child: Column(
                children: [
                  _buildHeader(
                    label: 'MAQUETADO ACTIVO',
                    count: activeDevices.length,
                    color: SentinelTheme.primary,
                    icon: Icons.downloading,
                    showLegend: true,
                    showBranding: true,
                    actions: [
                      IconButton(
                        icon: Icon(
                          provider.monitoredSwitchIds.isEmpty
                              ? Icons.filter_alt_off
                              : Icons.filter_alt,
                          color: provider.monitoredSwitchIds.isEmpty
                              ? Colors.white38
                              : SentinelTheme.primary,
                          size: 20,
                        ),
                        tooltip: "Filtrar mesas visualizadas",
                        onPressed: () => _showFilterDialog(context, provider),
                      ),
                    ],
                  ),
                  Expanded(
                    child: _buildGrid(
                      activeDevices,
                      emptyMessage: "No hay procesos activos",
                    ),
                  ),
                ],
              ),
            ),

            Divider(height: dividerHeight, color: Colors.white10),

            // --- BOTTOM PART (Completed) ---
            AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOutCubic,
              height: hCompleted,
              child: Container(
                color: Colors.black.withOpacity(
                  0.2,
                ), // Slightly darker background
                child: Column(
                  children: [
                    _buildHeader(
                      label: 'COMPLETADOS RECIENTES',
                      count: completedDevices.length,
                      color: SentinelTheme.success,
                      icon: Icons.check_circle_outline,
                      showLegend: false,
                    ),
                    Expanded(
                      child: _buildGrid(
                        completedDevices,
                        emptyMessage: "No hay completados recientes",
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showFilterDialog(BuildContext context, SentinelProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SentinelTheme.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: SentinelTheme.primary.withOpacity(0.2)),
        ),
        title: const Text('Filtrar Mesas', style: SentinelTheme.header),
        content: SizedBox(
          width: 300,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (provider.switches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      "No hay mesas detectadas.",
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ...provider.switches.map((s) {
                  final isExplicitlySelected = provider.monitoredSwitchIds
                      .contains(s.switchId);

                  return CheckboxListTile(
                    title: Text(s.name, style: SentinelTheme.body),
                    subtitle: Text(
                      s.location ?? 'Sin ubicación',
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                    value: isExplicitlySelected,
                    activeColor: SentinelTheme.primary,
                    checkColor: Colors.black,
                    onChanged: (_) {
                      provider.toggleMonitoredSwitch(s.switchId);
                      (ctx as Element)
                          .markNeedsBuild(); // Quick fix or use StatefulBuilder
                    },
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'CERRAR',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranding() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Potenciado por",
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 9,
            letterSpacing: 0.5,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              "Sentinel",
              style: SentinelTheme.header.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: SentinelTheme.primary,
                letterSpacing: 1.0,
                shadows: [
                  BoxShadow(
                    color: SentinelTheme.primary.withOpacity(0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              "AI Agent",
              style: SentinelTheme.mono.copyWith(
                fontSize: 10,
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeader({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
    bool showLegend = false,
    bool showBranding = false,
    List<Widget>? actions,
  }) {
    // Helper for Left Content
    final leftContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.2), blurRadius: 10),
            ],
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: SentinelTheme.header),
            Text(
              '$count DISPOSITIVOS',
              style: SentinelTheme.label.copyWith(color: color),
            ),
          ],
        ),
      ],
    );

    // Helper for Right Content
    final rightContent = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (showLegend)
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                _LegendItem(
                  label: 'Descargando Imagen',
                  color: SentinelTheme.warning,
                ),
                _LegendItem(
                  label: 'Aplicando Imagen',
                  color: Colors.purpleAccent,
                ),
                _LegendItem(
                  label: 'Imagen Aplicada',
                  color: SentinelTheme.success,
                ),
              ],
            ),
          ),
        if (actions != null) ...[const SizedBox(width: 8), ...actions],
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: color.withOpacity(0.1))),
      ),
      child: showBranding
          ? Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: leftContent,
                  ),
                ),
                _buildBranding(),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: rightContent,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                leftContent,
                const Spacer(),
                Flexible(child: rightContent),
              ],
            ),
    );
  }

  Widget _buildGrid(
    List<SentinelDevice> devices, {
    required String emptyMessage,
  }) {
    if (devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.settings_ethernet,
              size: 32,
              color: Colors.white.withOpacity(0.05),
            ),
            const SizedBox(height: 8),
            Text(
              emptyMessage,
              style: const TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 1.0,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final dev = devices[index];
        return ImagingCard(key: ValueKey(dev.mac), device: dev);
      },
    );
  }
}

class ImagingCard extends StatelessWidget {
  final SentinelDevice device;

  const ImagingCard({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SentinelProvider>(context, listen: false);

    Color progressColor = SentinelTheme.secondary;
    String statusText = device.stage ?? 'MAQUETANDO';

    // Normalize logic
    final stage = device.stage?.toLowerCase() ?? '';

    // Stage-based styling & Calculated Progress
    double visualProgress = 0.05; // Default connecting/starting

    if (stage == 'failed' ||
        stage == 'wim_apply_failed' ||
        stage == 'guard_blocked') {
      progressColor = Colors.redAccent;
      statusText = 'ERROR';
      visualProgress = 1.0;
    } else if (stage == 'streaming' ||
        stage == 'downloading' ||
        stage == 'smb_progress') {
      progressColor = SentinelTheme.warning;
      statusText = 'DESCARGANDO';
      // Map 0-100 download progress to 10-80% visual range
      final raw = (device.imagingProgress ?? 0) / 100.0;
      visualProgress = 0.10 + (raw * 0.70);
    } else if (stage == 'applying' ||
        stage == 'wim_apply_start' ||
        stage == 'wim_apply_progress' ||
        stage == 'smb_complete') {
      progressColor = Colors.purpleAccent;
      statusText = 'APLICANDO';

      if (stage == 'wim_apply_progress') {
        final raw = (device.imagingProgress ?? 0) / 100.0;
        visualProgress = 0.80 + (raw * 0.19); // 80% to 99%
      } else {
        visualProgress = 0.80; // Fixed 80% when apply starts
      }
    } else if (stage == 'done' ||
        stage == 'finished' ||
        stage == 'wim_apply_done') {
      progressColor = SentinelTheme.success;
      statusText = 'COMPLETADO';
      visualProgress = 1.0;
    } else {
      statusText = 'PREPARANDO';
      if (stage == 'smb_start' ||
          stage == 'smb_init' ||
          stage == 'connecting') {
        visualProgress = 0.10;
      }
    }

    // Shorter Status Text for square card
    if (statusText.length > 10) {
      statusText = statusText.substring(0, 10);
    }

    // For display
    final percentString = (visualProgress * 100).toInt();

    // Construct Location ID (e.g., M3-01 or A-19-P11)
    String locationText = '--';
    double locationFontSize = 28;

    if (device.switchName != null) {
      if (device.switchName!.toLowerCase().contains('a-sw3')) {
        // Try to get the specific port label from switches
        String? portLabel;
        try {
          final s = provider.switches.firstWhere(
            (sw) => sw.name == device.switchName,
          );
          final p = s.ports.firstWhere(
            (p) => p.portNumber == device.portNumber,
          );
          portLabel = p.label;
        } catch (_) {}

        if (portLabel != null &&
            portLabel.isNotEmpty &&
            portLabel != device.portNumber.toString()) {
          locationText = portLabel; // e.g. A-19-P11
          locationFontSize = 18; // Smaller size for longer text
        } else {
          locationText =
              'A-${device.portNumber?.toString().padLeft(2, '0') ?? '?'}';
          locationFontSize = 28;
        }
      } else {
        // "m3-table" -> "M3"
        final swPrefix = device.switchName!.split('-').first.toUpperCase();
        if (device.portNumber != null) {
          final p = device.portNumber.toString().padLeft(2, '0');
          locationText = '$swPrefix-$p';
        } else {
          locationText = swPrefix;
        }
      }
    } else if (device.portNumber != null) {
      locationText = '#${device.portNumber}';
    }

    return Stack(
      children: [
        // 1. Liquid Fill Background
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LiquidFillAnimation(
              progress: visualProgress,
              color: progressColor,
            ),
          ),
        ),

        // 2. Glass Frame & Border
        Container(
          decoration:
              SentinelTheme.glassDecoration(
                opacity: 0.05,
                borderRadius: 12,
                border: true,
              ).copyWith(
                border: Border.all(color: progressColor.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: progressColor.withOpacity(0.05),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ],
              ),
        ),

        // 3. Content
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Hostname ONLY (Removed Port Badge)
              Text(
                device.hostname ?? device.mac,
                style: SentinelTheme.body.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: Colors.white,
                  shadows: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.8),
                      blurRadius: 4,
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // Center: Location ID (HUGE) + Percent (Small)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        locationText,
                        style: SentinelTheme.header.copyWith(
                          fontSize:
                              locationFontSize, // Dynamic size based on length
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.6),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$percentString%',
                        style: SentinelTheme.mono.copyWith(
                          fontSize: 14, // Demoted
                          color: Colors.white.withOpacity(0.9),
                          shadows: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.8),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      if (device.speedMbps != null)
                        Text(
                          '${device.speedMbps!.toInt()} Mbps',
                          style: SentinelTheme.mono.copyWith(
                            fontSize: 10,
                            color: Colors.white.withOpacity(0.7),
                            shadows: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.8),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Footer: Status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: progressColor.withOpacity(0.5)),
                ),
                child: Text(
                  statusText,
                  style: SentinelTheme.label.copyWith(
                    color: progressColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class LiquidFillAnimation extends StatefulWidget {
  final double progress; // 0.0 to 1.0
  final Color color;

  const LiquidFillAnimation({
    super.key,
    required this.progress,
    required this.color,
  });

  @override
  State<LiquidFillAnimation> createState() => _LiquidFillAnimationState();
}

class _LiquidFillAnimationState extends State<LiquidFillAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fill the available space
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _WavePainter(
            animationValue: _controller.value,
            progress: widget.progress,
            color: widget.color,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class LiquidCircularProgress extends StatefulWidget {
  final double progress; // 0.0 to 1.0
  final Color color;
  final Widget? centerWidget;

  const LiquidCircularProgress({
    super.key,
    required this.progress,
    required this.color,
    this.centerWidget,
  });

  @override
  State<LiquidCircularProgress> createState() => _LiquidCircularProgressState();
}

class _LiquidCircularProgressState extends State<LiquidCircularProgress>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background Circle (Empty container)
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withOpacity(0.05),
              border: Border.all(
                color: widget.color.withOpacity(0.2),
                width: 1,
              ),
            ),
          ),
          // Liquid Wave
          ClipOval(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: _WavePainter(
                    animationValue: _controller.value,
                    progress: widget.progress,
                    color: widget.color,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),
          // Center Content
          if (widget.centerWidget != null) widget.centerWidget!,
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double animationValue;
  final double progress;
  final Color color;

  _WavePainter({
    required this.animationValue,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity(0.5);
    final path = Path();

    final width = size.width;
    final height = size.height;
    // Calculate base height (upside down for canvas y-axis)
    // progress 0 -> baseHeight = height
    // progress 1 -> baseHeight = 0
    final baseHeight = height * (1 - progress);

    path.moveTo(0, baseHeight);
    for (double i = 0; i <= width; i++) {
      // Sine wave: y = A * sin(kx + phase)
      // Amplitude scales down as we get full to avoid clipping weirdness at top
      final amplitude = 4.0;
      path.lineTo(
        i,
        baseHeight +
            amplitude *
                math.sin(
                  2 * math.pi * (i / width) + 2 * math.pi * animationValue,
                ),
      );
    }
    path.lineTo(width, height);
    path.lineTo(0, height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => true;
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendItem({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
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
        Text(
          label,
          style: SentinelTheme.mono.copyWith(
            fontSize: 10,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}
