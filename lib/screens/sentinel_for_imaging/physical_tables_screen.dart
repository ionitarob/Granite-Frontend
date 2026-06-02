import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'sentinel_provider.dart';
import 'sentinel_models.dart';
import '../../services/orderops_service.dart';
import '../../models/agent_models.dart';

import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';
import 'sentinel_theme.dart';
import 'package:dropdown_button2/dropdown_button2.dart';

class PhysicalTablesScreen extends StatefulWidget {
  final int? orderId;
  const PhysicalTablesScreen({super.key, this.orderId});

  @override
  State<PhysicalTablesScreen> createState() => _PhysicalTablesScreenState();
}

class _PhysicalTablesScreenState extends State<PhysicalTablesScreen>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _edgeOverlay;
  late TransformationController _transformationController;
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  // OverlayEntry? _contextMenuOverlay; // Removed in favor of Route
  Route? _currentConfigRoute; // Track the route to pop it programmatically
  final GlobalKey _contentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    print('DEBUG: PhysicalTablesScreen initState with orderId=${widget.orderId}');
    _transformationController = TransformationController();
    _animationController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 400),
        )..addListener(() {
          if (_animation != null) {
            _transformationController.value = _animation!.value;
          }
        });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final user = Provider.of<ApiService>(context, listen: false).currentUser;
        if (user != null) {
          Provider.of<SentinelProvider>(context, listen: false).setUserName(
            user.displayName(),
          );
        }

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
                  child: widget.orderId != null
                      ? const SizedBox.shrink()
                      : EdgeNavHandle(
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

        // Enable Voice Service for this screen
        Provider.of<SentinelProvider>(
          context,
          listen: false,
        ).setVoiceEnabled(true);
      }
    });
  }

  @override
  void dispose() {
    _edgeOverlay?.remove();
    // _contextMenuOverlay?.remove(); // Handled by Route disposal usually
    if (_currentConfigRoute != null && _currentConfigRoute!.isActive) {
      if (mounted) Navigator.of(context).removeRoute(_currentConfigRoute!);
    }
    _transformationController.dispose();
    _animationController.dispose();
    _edgeOverlay = null;
    _edgeOverlay = null;
    // Disable Voice Service when leaving
    if (mounted) {
      // Check mounted just in case, though dispose shouldn't strictly depend on it for logic,
      // but Provider lookup needs context. If hierarchy is gone, this might fail?
      // Actually 'context' is still valid for looking up ancestors in dispose usually?
      // Flutter docs say "The State object's BuildContext is available... at this point".
    }
    // Safer to just try:
    try {
      Provider.of<SentinelProvider>(
        context,
        listen: false,
      ).setVoiceEnabled(false);
    } catch (_) {} // Ignore if provider missing
    super.dispose();
  }

  void _onPortTap(
    BuildContext portContext,
    SentinelPort port,
    SentinelSwitch parentSwitch,
    LayerLink link,
  ) {
    // 1. Calculate zoom target
    final renderBox = portContext.findRenderObject() as RenderBox;

    // We want to center this port on the viewport
    _animateZoomToBox(renderBox, 1.5);

    // 2. Show Contextual Details Overlay
    _showContextOverlay(portContext, port, parentSwitch, link);
  }

  void _animateZoomToBox(RenderBox box, double scale) {
    final boxSize = box.size;

    // Transform to scene coordinates
    // We assume the box is a descendant of the InteractiveViewer's child
    // Since InteractiveViewer transforms the canvas, we need to find where the box is *on the canvas*.
    // Simple way: box.localToGlobal(Offset.zero) gives screen coords.
    // _transformationController.toScene(screenCoords) gives coords on the canvas.

    final sceneTopLeft = _transformationController.toScene(
      box.localToGlobal(Offset.zero),
    );
    final sceneCenter =
        sceneTopLeft + Offset(boxSize.width / 2, boxSize.height / 2);

    final viewerSize = MediaQuery.of(context).size;
    final viewportCenter = Offset(viewerSize.width / 2, viewerSize.height / 2);

    // Target Matrix:
    // Translate viewport center to origin -> Scale -> Translate scene point to origin (inverse)
    // M = T(Vc) * S(s) * T(-P)

    final Matrix4 targetMatrix = Matrix4.identity()
      ..translate(viewportCenter.dx, viewportCenter.dy)
      ..scale(scale)
      ..translate(-sceneCenter.dx, -sceneCenter.dy);

    // Animate
    _animation =
        Matrix4Tween(
          begin: _transformationController.value,
          end: targetMatrix,
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );

    _animationController.forward(from: 0);
  }

  void _closeOverlay() {
    if (_currentConfigRoute != null) {
      if (_currentConfigRoute!.isActive) {
        Navigator.of(context).removeRoute(_currentConfigRoute!);
      }
      _currentConfigRoute = null;
    }
  }

  void _resetView() {
    _closeOverlay();

    Matrix4 targetMatrix = Matrix4.identity();

    // Calculate centering if content is available
    final renderBox =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final contentSize = renderBox.size;
      final viewportSize = MediaQuery.of(context).size;

      // We want to center the content.
      final double dx = (viewportSize.width - contentSize.width) / 2;
      final double dy = (viewportSize.height - contentSize.height) / 2;

      targetMatrix = Matrix4.identity()..translate(dx, dy);
    }

    _animation =
        Matrix4Tween(
          begin: _transformationController.value,
          end: targetMatrix,
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );

    _animationController.forward(from: 0);
  }

  void _showContextOverlay(
    BuildContext ctx,
    SentinelPort port,
    SentinelSwitch s,
    LayerLink link,
  ) {
    // If existing route is present, remove it first
    _closeOverlay();

    // Capture provider data before rewrite
    final provider = Provider.of<SentinelProvider>(ctx, listen: false);

    _currentConfigRoute = PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            // Dismissible background
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  _resetView();
                },
                behavior: HitTestBehavior.translucent,
                child: Container(color: Colors.transparent),
              ),
            ),
            // The Popup
            CompositedTransformFollower(
              link: link,
              targetAnchor: Alignment.centerRight,
              followerAnchor: Alignment.centerLeft,
              offset: const Offset(10, 0), // 10px gap to the right
              child: Theme(
                // Ensure theme is passed
                data: Theme.of(ctx),
                child: ChangeNotifierProvider.value(
                  value: provider,
                  child: _PortContextPopup(
                    port: port,
                    parentSwitch: s,
                    orderId: widget.orderId,
                    onClose: () {
                      _resetView();
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Navigator.of(context).push(_currentConfigRoute!);
  }

  @override
  Widget build(BuildContext context) {
    // Access Control
    final user = Provider.of<ApiService>(context, listen: false).currentUser;
    final role = user?.role.toLowerCase() ?? '';
    // Block "operario básico" and "operario avanzado" (handling accents/caps)
    if (role.contains('operario') &&
        (role.contains('básico') ||
            role.contains('basico') ||
            role.contains('avanzado'))) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, color: Colors.white24, size: 64),
              SizedBox(height: 24),
              Text(
                "ACCESO RESTRINGIDO",
                style: SentinelTheme.header.copyWith(
                  fontSize: 20,
                  color: Colors.white54,
                  letterSpacing: 2.0,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "Tu rol ($role) no tiene permisos para visualización física.",
                style: TextStyle(color: Colors.white38),
              ),
            ],
          ),
        ),
      );
    }

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
          body: Container(
            decoration: const BoxDecoration(
              gradient: SentinelTheme.backgroundGradient,
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      _SwitchSelector(orderId: widget.orderId),
                      const Divider(height: 1, color: Colors.white10),
                      Expanded(
                        child: Consumer<SentinelProvider>(
                          builder: (context, provider, child) {
                            return _LayoutResetTrigger(
                              visibleIds: provider.visibleSwitches
                                  .map((s) => s.switchId)
                                  .toList(),
                              onReset: _resetView,
                              child: child!,
                            );
                          },
                          child: GestureDetector(
                            onTap: _resetView,
                            behavior: HitTestBehavior
                                .translucent, // Catch taps on void
                            child: InteractiveViewer(
                              transformationController:
                                  _transformationController,
                              minScale: 0.1,
                              maxScale: 4.0,
                              boundaryMargin: const EdgeInsets.all(
                                500,
                              ), // Huge margin for free roam
                              constrained: false, // Infinite canvas feeling
                              child: KeyedSubtree(
                                key: _contentKey,
                                child: _PortMap(
                                  onPortTap: (ctx, p, s, link) =>
                                      _onPortTap(ctx, p, s, link),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Legend in Bottom-Right Corner
                  Positioned(bottom: 32, right: 32, child: _Legend()),
                ],
              ),
            ),
          ),
      ),
    );
  }
}

class _SwitchSelector extends StatelessWidget {
  final int? orderId;
  const _SwitchSelector({this.orderId});

  Future<void> _exportCsv(
    BuildContext context,
    SentinelProvider provider,
    String type,
  ) async {
    try {
      final now = DateTime.now().toIso8601String().replaceAll(':', '-');
      final orderPrefix = orderId != null ? 'order_${orderId}_' : '';
      final filename =
          type == 'events'
          ? '${orderPrefix}sentinel_events_$now.csv'
          : '${orderPrefix}sentinel_snapshot_$now.csv';

      final csv = type == 'events'
          ? provider.buildEventsCsv(orderId: orderId)
          : provider.buildImagingSnapshotCsv(orderId: orderId);

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString(csv, flush: true);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV generado: $filename')),
        );
      }

      await OpenFilex.open(file.path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error exportando CSV: $e')));
      }
    }
  }

  Widget _statPill(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        '$label: $value',
        style: SentinelTheme.label.copyWith(color: color, fontSize: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SentinelProvider>(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black26,
        border: Border(
          bottom: BorderSide(color: SentinelTheme.primary.withOpacity(0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
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
                  return provider.switches.expand((s) {
                    final isSelected =
                        s.switchId == provider.selectedSwitch?.switchId;
                    final isVisible = provider.isSwitchVisible(s.switchId);

                    final List<PopupMenuEntry<SentinelSwitch>> entries = [];

                    // Normal Switch Entry
                    entries.add(
                      PopupMenuItem<SentinelSwitch>(
                        value: s,
                        onTap: () => provider.toggleASW3Pack(0),
                        child: Row(
                          children: [
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
                                '${s.name} (All)',
                                style: SentinelTheme.body.copyWith(
                                  color:
                                      (isSelected && provider.isPackActive(0))
                                      ? SentinelTheme.primary
                                      : Colors.white70,
                                  fontWeight:
                                      (isSelected && provider.isPackActive(0))
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (isSelected && provider.isPackActive(0))
                              _buildActiveBadge(),
                          ],
                        ),
                      ),
                    );

                    // If a-sw3, add the 3 specific packs as sub-entries
                    if (s.name.toLowerCase().contains('a-sw3')) {
                      for (int packId = 1; packId <= 3; packId++) {
                        final isPackSelected =
                            isSelected && provider.isPackActive(packId);
                        final label = packId == 1
                            ? 'A17-19'
                            : packId == 2
                            ? 'A20-22'
                            : 'A23';
                        final packLabel = '   ↳ Part $packId ($label)';

                        entries.add(
                          PopupMenuItem<SentinelSwitch>(
                            value: s,
                            onTap: () => provider.toggleASW3Pack(packId),
                            child: Row(
                              children: [
                                const SizedBox(width: 30),
                                Expanded(
                                  child: Text(
                                    packLabel,
                                    style: SentinelTheme.body.copyWith(
                                      fontSize: 12,
                                      color: isPackSelected
                                          ? SentinelTheme.primary
                                          : Colors.white54,
                                      fontWeight: isPackSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (isPackSelected) _buildActiveBadge(),
                              ],
                            ),
                          ),
                        );
                      }
                    }

                    return entries;
                  }).toList();
                },
                onSelected: (s) {
                  provider.selectSwitch(s);
                },
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        provider.selectedSwitch == null
                            ? 'Seleccionar Switch'
                            : '${provider.selectedSwitch!.name}${provider.activeASW3Packs.contains(0) ? ' (All)' : ' (Part ${provider.activeASW3Packs.toList()..sort()})'}'
                                  .replaceAll('[', '')
                                  .replaceAll(']', ''),
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
                          orderId: orderId,
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
              PopupMenuButton<String>(
                tooltip: 'Exportar logs/snapshot',
                icon: const Icon(Icons.download, color: SentinelTheme.primary),
                onSelected: (value) {
                  if (value == 'snapshot') {
                    _exportCsv(context, provider, 'snapshot');
                  } else if (value == 'events') {
                    _exportCsv(context, provider, 'events');
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'snapshot',
                    child: Text('Exportar snapshot CSV'),
                  ),
                  PopupMenuItem(
                    value: 'events',
                    child: Text('Exportar eventos CSV'),
                  ),
                ],
              ),
            ],
          ),
          if (orderId != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statPill(
                  'PUERTOS CONFIG',
                  provider.configuredPortsCount,
                  SentinelTheme.primary,
                ),
                _statPill(
                  'MATCH PC-ORDEN',
                  provider.matchedDevicesCount,
                  SentinelTheme.secondary,
                ),
                _statPill(
                  'MAQUETANDO',
                  provider.activelyImagingDevicesCount,
                  SentinelTheme.warning,
                ),
                _statPill(
                  'COMPLETADOS',
                  provider.completedImagingDevicesCount,
                  SentinelTheme.success,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
    );
  }
}

class _PortMap extends StatelessWidget {
  final Function(BuildContext, SentinelPort, SentinelSwitch, LayerLink)?
  onPortTap;

  const _PortMap({this.onPortTap});

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
            ],
            // Legend moved to floating overlay
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: provider.visibleSwitches.map((s) {
              if (s.name.toLowerCase().contains('a-sw3')) {
                return _buildASW3Layout(context, provider, s);
              }

              final groups = provider.getVirtualGroups(s);
              return Column(
                children: groups.map((g) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: _PhysicalTableLayout(
                      group: g,
                      sentinelSwitch: s,
                      onPortTap: onPortTap,
                    ),
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildASW3Layout(
    BuildContext context,
    SentinelProvider provider,
    SentinelSwitch s,
  ) {
    final allGroups = provider.getVirtualGroups(s);
    final pack1 = allGroups.where((g) => g.packId == 1).toList();
    final pack2 = allGroups.where((g) => g.packId == 2).toList();
    final pack3 = allGroups.where((g) => g.packId == 3).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pack1.isNotEmpty) _buildPackLayout(context, 1, pack1, s),
          if (pack2.isNotEmpty) ...[
            const SizedBox(width: 48),
            _buildPackLayout(context, 2, pack2, s),
          ],
          if (pack3.isNotEmpty) ...[
            const SizedBox(width: 48),
            _buildPackLayout(context, 3, pack3, s),
          ],
        ],
      ),
    );
  }

  Widget _buildPackLayout(
    BuildContext context,
    int packId,
    List<VirtualTableGroup> groups,
    SentinelSwitch s,
  ) {
    if (packId == 3) {
      // Pack 3 is special (L-Shape A-23)
      return _PhysicalTableLayout(
        group: groups.first,
        sentinelSwitch: s,
        onPortTap: onPortTap,
      );
    }

    // Packs 1 & 2: Top Horizontal, Bottom 2 Vertical
    final horizontal = groups.firstWhere(
      (g) => g.tableName == (packId == 1 ? 'A-17' : 'A-20'),
      orElse: () => groups.first,
    );
    final verticals = groups
        .where((g) => g.tableName != horizontal.tableName)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PhysicalTableLayout(
          group: horizontal,
          sentinelSwitch: s,
          onPortTap: onPortTap,
        ),
        const SizedBox(height: 32),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: verticals.map((v) {
            return Padding(
              padding: const EdgeInsets.only(right: 32),
              child: _PhysicalTableLayout(
                group: v,
                sentinelSwitch: s,
                onPortTap: onPortTap,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black54, // Semi-transparent background
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _item(SentinelTheme.success, 'Imagen Completa'),
          const SizedBox(height: 8),
          _item(SentinelTheme.secondary, 'Maquetando'),
          const SizedBox(height: 8),
          _item(SentinelTheme.success.withOpacity(0.2), 'Activo'),
          const SizedBox(height: 8),
          _item(Colors.grey, 'Inactivo'),
        ],
      ),
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
  final VirtualTableGroup group;
  final SentinelSwitch sentinelSwitch;
  final Function(BuildContext, SentinelPort, SentinelSwitch, LayerLink)?
  onPortTap;

  const _PhysicalTableLayout({
    required this.group,
    required this.sentinelSwitch,
    this.onPortTap,
  });

  @override
  Widget build(BuildContext context) {
    // Specialized layout for a-sw3 virtual tables
    if (sentinelSwitch.name.toLowerCase().contains('a-sw3')) {
      return _buildSpecializedLayout(context);
    }

    // Default 8-port block logic (M2, M3, etc.)
    int maxPort = sentinelSwitch.ports.length;
    if (sentinelSwitch.name.toLowerCase().contains('m3')) maxPort = 32;
    if (sentinelSwitch.name.toLowerCase().contains('m2')) maxPort = 24;

    final blockCount = (maxPort / 8).ceil();
    final List<Widget> blockWidgets = [];

    // Build blocks from Left (Lowest Port Numbers) to Right (Highest)
    for (int b = 0; b < blockCount; b++) {
      final offset = b * 8;

      // Top Row: 5, 6, 7, 8
      final rowTop = _buildContinuousRow(context, [
        offset + 5,
        offset + 6,
        offset + 7,
        offset + 8,
      ]);

      // Bottom Row: 1, 2, 3, 4
      final rowBottom = _buildContinuousRow(context, [
        offset + 1,
        offset + 2,
        offset + 3,
        offset + 4,
      ]);

      blockWidgets.add(
        Column(
          children: [
            rowTop,
            const SizedBox(height: 12), // Gap between facing rows
            rowBottom,
          ],
        ),
      );

      // Gap between blocks (Horizontal)
      if (b < blockCount - 1) {
        blockWidgets.add(const SizedBox(width: 32));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCenteredHeader(sentinelSwitch.name, SentinelTheme.primary),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white10),
            borderRadius: BorderRadius.circular(16),
            color: Colors.black26,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: blockWidgets),
        ),
      ],
    );
  }

  Widget _buildSpecializedLayout(BuildContext context) {
    final String name = group.tableName;
    final color = group.packColor as Color? ?? Colors.grey;

    // Detect orientation based on image logic
    bool isVertical =
        name == 'A-18' || name == 'A-19' || name == 'A-21' || name == 'A-22';

    if (name == 'A-23') {
      return _buildLShapeLayout(context, color);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCenteredHeader(name, color),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.2)),
            borderRadius: BorderRadius.circular(16),
            color: color.withOpacity(0.05),
          ),
          child: isVertical
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: group.ports.map((p) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _Seat(
                        sentinelSwitch: sentinelSwitch,
                        portNum: p.portNumber,
                        onPortTap: onPortTap,
                      ),
                    );
                  }).toList(),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: group.ports.map((p) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Seat(
                        sentinelSwitch: sentinelSwitch,
                        portNum: p.portNumber,
                        onPortTap: onPortTap,
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildLShapeLayout(BuildContext context, Color color) {
    // 25, 26 horizontal, then 27-35 vertical
    final horizontalPorts =
        group.ports.where((p) => p.portNumber <= 26).toList()
          ..sort((a, b) => a.portNumber.compareTo(b.portNumber));
    final verticalPorts = group.ports.where((p) => p.portNumber >= 27).toList()
      ..sort((a, b) => a.portNumber.compareTo(b.portNumber));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCenteredHeader(group.tableName, color),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.2)),
            borderRadius: BorderRadius.circular(16),
            color: color.withOpacity(0.05),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: horizontalPorts.map((p) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _Seat(
                      sentinelSwitch: sentinelSwitch,
                      portNum: p.portNumber,
                      onPortTap: onPortTap,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              // Pad to start under the second horizontal port (26)
              Padding(
                padding: const EdgeInsets.only(left: 68), // 60 width + 8 gap
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: verticalPorts.map((p) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _Seat(
                        sentinelSwitch: sentinelSwitch,
                        portNum: p.portNumber,
                        onPortTap: onPortTap,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCenteredHeader(String name, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        name.toUpperCase(),
        style: SentinelTheme.header.copyWith(
          color: color,
          letterSpacing: 2,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildContinuousRow(BuildContext context, List<int> ports) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: ports.asMap().entries.map((entry) {
        final index = entry.key;
        final p = entry.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Seat(
              sentinelSwitch: sentinelSwitch,
              portNum: p,
              onPortTap: onPortTap,
            ),
            // Add small gap between seats, but not after the last one
            if (index < ports.length - 1) const SizedBox(width: 4),
          ],
        );
      }).toList(),
    );
  }
}

class _Seat extends StatefulWidget {
  final SentinelSwitch sentinelSwitch;
  final int portNum;
  final Function(BuildContext, SentinelPort, SentinelSwitch, LayerLink)?
  onPortTap;

  const _Seat({
    required this.sentinelSwitch,
    required this.portNum,
    this.onPortTap,
  });

  @override
  State<_Seat> createState() => _SeatState();
}

class _SeatState extends State<_Seat> {
  final LayerLink _layerLink = LayerLink();

  @override
  Widget build(BuildContext context) {
    // Find the port
    final port = widget.sentinelSwitch.ports.firstWhere(
      (p) => p.portNumber == widget.portNum,
      orElse: () => SentinelPort(
        portId: 0,
        portNumber: widget.portNum,
        label: '',
        role: '',
        enabled: false,
        status: 'disabled',
      ),
    );

    // Look up live device efficiently
    // We select only the device corresponding to this port's MAC.
    // If other devices update, this widget will NOT rebuild.
    final liveDevice = context.select<SentinelProvider, SentinelDevice?>(
      (provider) => provider.deviceByMac(port.connectedMac),
    );

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

    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: () {
          // Find the port object first to pass it back
          final port = widget.sentinelSwitch.ports.firstWhere(
            (p) => p.portNumber == widget.portNum,
            orElse: () => SentinelPort(
              portId: 0,
              portNumber: widget.portNum,
              label: '',
              role: '',
              enabled: false,
              status: 'disabled',
            ),
          );

          if (widget.onPortTap != null) {
            widget.onPortTap!(context, port, widget.sentinelSwitch, _layerLink);
          }
        },
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
                  '${widget.portNum}',
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
              if (port.orderId != null)
                Positioned(
                  bottom: 2,
                  left: 2,
                  child: Text(
                    '#${port.orderId}',
                    style: TextStyle(
                      fontSize: 8,
                      color: textColor.withOpacity(0.8),
                      fontWeight: FontWeight.bold,
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
                Builder(
                  builder: (context) {
                    final isScript = port.selectedImage?.toUpperCase().startsWith('SCRIPT:') ?? false;
                    return Positioned(
                      bottom: 2,
                      right: 2,
                      child: Icon(
                        isScript ? Icons.terminal : Icons.download_for_offline,
                        color: isScript ? Colors.greenAccent : SentinelTheme.secondary,
                        size: 8,
                      ),
                    );
                  }
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
  final int? orderId;

  const _SwitchImageDialog({required this.sentinelSwitch, this.orderId});

  @override
  State<_SwitchImageDialog> createState() => _SwitchImageDialogState();
}

Future<void> showSentinelPreview(BuildContext context, SentinelProvider provider, String imageName) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final details = await provider.fetchImageDetails(imageName);
    if (context.mounted) Navigator.pop(context); // pop loading

    if (details == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No details found for image.')));
      }
      return;
    }

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) {
          final manifest = details['manifest'] as Map<String, dynamic>? ?? {};
          final partitions = manifest['partitions'] as List<dynamic>? ?? [];
          final num diskSizeBytes = manifest['disk_size_bytes'] as num? ?? 0;
          final diskSizeGb = (diskSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2);
          final createdAt = manifest['created_at']?.toString() ?? 'Unknown';
          
          bool hasWindows = false;
          bool hasLinux = false;
          for (var p in partitions) {
            final pMap = p as Map<String, dynamic>? ?? {};
            final fs = pMap['fs']?.toString().toLowerCase() ?? '';
            final role = pMap['role']?.toString().toLowerCase() ?? '';
            final name = pMap['name']?.toString().toLowerCase() ?? '';
            final typeGuid = pMap['type_guid']?.toString().toUpperCase() ?? '';
            
            // Windows GUIDs & Fallbacks
            if (typeGuid.contains('EBD0A0A2-B9E5-4433-87C0-68B6B72699C7') ||
                typeGuid.contains('E3C9E316-0B5C-4DB8-817D-F92DF00215AE') ||
                typeGuid.contains('DE94BBA4-06D1-4D40-A16A-BFD50179D6AC')) {
              hasWindows = true;
            }
            if (fs == 'ntfs' || role.contains('msft') || role == 'msr' || role.contains('windows') || name.contains('windows') || name.contains('winpe') || name.contains('basic data partition') || name.contains('microsoft reserved')) {
              hasWindows = true;
            }
            
            // Linux GUIDs & Fallbacks
            if (typeGuid.contains('4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709') || // root
                typeGuid.contains('0657FD6D-A4AB-43C4-84E5-0933C84B4F4F') || // swap
                typeGuid.contains('933AC7E1-2EB4-4F13-B844-0E14E2AEF915') || // home
                typeGuid.contains('0FC63DAF-8483-4772-8E79-3D69D8477DE4')) { // generic
              hasLinux = true;
            }
            final isLinuxFsOrRole = (fs == 'ext4' || fs == 'ext3' || fs == 'btrfs' || fs == 'swap' || role.contains('linux') || name.contains('linux') || role == 'swap');
            final isRawPartitionName = (name.startsWith('nvme') || name.startsWith('sda') || name.startsWith('sdb') || name.startsWith('sdc') || name.startsWith('sdd'));
            
            final num sizeLba = pMap['size_lba'] as num? ?? 0;
            final double sizeBytes = sizeLba * 512.0;
            final isLargeEnough = sizeBytes >= 5.0 * 1024 * 1024 * 1024; // 5 GB

            if (isLinuxFsOrRole || (isRawPartitionName && isLargeEnough)) {
              hasLinux = true;
            }
          }

          String osBadgeText = 'UNKNOWN OS';
          Color osBadgeColor = Colors.grey;
          IconData osBadgeIcon = Icons.device_unknown;

          if (hasWindows && hasLinux) {
            osBadgeText = 'DUAL-BOOT';
            osBadgeColor = Colors.purpleAccent;
            osBadgeIcon = Icons.call_split;
          } else if (hasWindows) {
            osBadgeText = 'WINDOWS';
            osBadgeColor = Colors.blueAccent;
            osBadgeIcon = Icons.desktop_windows;
          } else if (hasLinux) {
            osBadgeText = 'LINUX';
            osBadgeColor = Colors.orangeAccent;
            osBadgeIcon = Icons.terminal;
          }
          
          return AlertDialog(
            backgroundColor: SentinelTheme.bgPanel,
            title: Row(
              children: [
                Icon(Icons.info_outline, color: SentinelTheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Sentinel Image: $imageName', style: SentinelTheme.header, overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: osBadgeColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: osBadgeColor, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(osBadgeIcon, size: 14, color: osBadgeColor),
                      const SizedBox(width: 6),
                      Text(osBadgeText, style: TextStyle(color: osBadgeColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    ]
                  )
                ),
              ]
            ),
            content: SizedBox(
              width: 800,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Created At: $createdAt', style: SentinelTheme.body),
                  const SizedBox(height: 16),
                  Text('Disk Layout:', style: SentinelTheme.subHeader),
                  const SizedBox(height: 8),
                  Container(
                    height: 110,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      color: const Color(0xFF1E1E1E), // Darker bg for disk row
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Disk Info Block (Left side)
                        Container(
                          width: 120,
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            border: Border(right: BorderSide(color: Colors.white24)),
                            color: Color(0xFF252525),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.dns, size: 16, color: Colors.white70),
                                  const SizedBox(width: 6),
                                  Text('Disk 0', style: SentinelTheme.body.copyWith(fontWeight: FontWeight.bold)),
                                ]
                              ),
                              const SizedBox(height: 4),
                              const Text('Básico', style: TextStyle(fontSize: 11, color: Colors.white70)),
                              Text('$diskSizeGb GB', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                              const Text('En línea', style: TextStyle(fontSize: 11, color: Colors.white70)),
                            ],
                          ),
                        ),
                        // Partitions
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              num totalDiskLba = 0;
                              for (var p in partitions) {
                                final pMap = p as Map<String, dynamic>? ?? {};
                                totalDiskLba += pMap['size_lba'] as num? ?? 0;
                              }
                              if (totalDiskLba <= 0) totalDiskLba = 1;

                              return Row(
                                children: partitions.map<Widget>((p) {
                                  final pMap = p as Map<String, dynamic>? ?? {};
                                  final num sizeLba = pMap['size_lba'] as num? ?? 0;
                                  final double sizeBytes = sizeLba * 512;
                                  
                                  String sizeStr = '';
                                  if (sizeBytes > 1024 * 1024 * 1024) {
                                    sizeStr = '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
                                  } else {
                                    sizeStr = '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
                                  }

                                  // Calculate flex based on ratio, with a minimum to ensure readability
                                  final double ratio = (sizeLba / totalDiskLba).clamp(0.0, 1.0);
                                  final int flex = (15 + (ratio * 85)).round();
                                  
                                  final String tooltipMessage = '''Name: ${pMap['name']} ${pMap['dev_path'] != null ? '(${pMap['dev_path']})' : ''}
Size: $sizeStr
FS: ${pMap['fs'] ?? 'Unknown'}
Role: ${pMap['role']}''';

                                  return Expanded(
                                    flex: flex,
                                    child: Tooltip(
                                      message: tooltipMessage,
                                      waitDuration: const Duration(milliseconds: 300),
                                      child: Container(
                                        margin: const EdgeInsets.fromLTRB(4, 4, 0, 4),
                                        decoration: BoxDecoration(
                                          color: SentinelTheme.bgPanel,
                                          border: Border.all(color: Colors.white24),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Container(
                                              height: 12,
                                              color: Colors.blue[800], // Primary partition color
                                            ),
                                            Expanded(
                                              child: Padding(
                                                padding: const EdgeInsets.all(6.0),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '${pMap['name']} ${pMap['dev_path'] != null ? '(${pMap['dev_path']})' : ''}',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '$sizeStr ${pMap['fs'] ?? ''}',
                                                      style: const TextStyle(fontSize: 10, color: Colors.white70),
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                    ),
                                                  const SizedBox(height: 2),
                                                  Expanded(
                                                    child: Text(
                                                      'Correcto (${pMap['role']})',
                                                      style: const TextStyle(fontSize: 9, color: Colors.white54),
                                                      overflow: TextOverflow.fade,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ),
                                  );
                                }).toList(),
                              );
                            }
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('CERRAR', style: SentinelTheme.body),
              )
            ],
          );
        }
      );
    }
  } catch (e) {
    if (context.mounted) Navigator.pop(context); // pop loading
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
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
              'Permitir despliegue de imágenes o scripts',
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
            'Seleccionar Imagen o Script:',
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
          Opacity(
            opacity: _enabled ? 1.0 : 0.55,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: SentinelTheme.glassDecoration(
                      borderRadius: 8,
                      opacity: 0.05,
                      border: true,
                    ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton2<String>(
                  value: _selectedImage,
                  hint: Text(
                    'Selecc. Objetivo (WIM/ESD/Dual-Boot/Sentinel/Script)',
                    style: SentinelTheme.body.copyWith(
                      color: SentinelTheme.textDisabled,
                    ),
                  ),
                  dropdownStyleData: DropdownStyleData(
                    decoration: BoxDecoration(
                      color: SentinelTheme.bgPanel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: SentinelTheme.primary.withOpacity(0.3),
                      ),
                    ),
                    offset: const Offset(0, -4),
                    maxHeight: 250,
                  ),
                  menuItemStyleData: const MenuItemStyleData(height: 40),
                  isExpanded: true,
                  buttonStyleData: ButtonStyleData(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  iconStyleData: const IconStyleData(
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: SentinelTheme.primary,
                    ),
                  ),
                  items:
                      images.map((img) {
                        final name = img['name']?.toString() ?? '';
                        final isDualBoot = img['type']?.toString() == 'dualboot';
                        final isSentinel = img['type']?.toString() == 'sentinel' ||
                            name.toLowerCase().endsWith('.sentinel');
                        final isScript = img['type']?.toString() == 'script' ||
                            name.toUpperCase().startsWith('SCRIPT:');
                        final displayName = isScript && name.startsWith('SCRIPT:')
                            ? name.substring(7)
                            : name;
                        return DropdownMenuItem<String>(
                          value: name,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  displayName,
                                  overflow: TextOverflow.ellipsis,
                                  style: SentinelTheme.body.copyWith(
                                    color: isDualBoot
                                        ? Colors.purple[200]
                                        : (isSentinel
                                            ? Colors.amber[200]
                                            : (isScript
                                                ? Colors.greenAccent
                                                : Colors.white)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isDualBoot
                                      ? Colors.purple.withOpacity(0.25)
                                      : (isSentinel
                                          ? Colors.amber.withOpacity(0.25)
                                          : (isScript
                                              ? Colors.green.withOpacity(0.2)
                                              : Colors.cyan.withOpacity(0.15))),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isDualBoot
                                        ? Colors.purple
                                        : (isSentinel
                                            ? Colors.amber
                                            : (isScript
                                                ? Colors.greenAccent
                                                : Colors.cyan)),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  isDualBoot
                                      ? 'DUAL-BOOT'
                                      : (isSentinel
                                          ? 'SENTINEL'
                                          : (isScript ? 'SCRIPT' : 'WIM')),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: isDualBoot
                                        ? Colors.purple[100]
                                        : (isSentinel
                                            ? Colors.amber[100]
                                            : (isScript
                                                ? Colors.greenAccent
                                                : Colors.cyan[200])),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList()..addAll(
                        // Ensure the currently selected image is in the list to avoid crash
                        (_selectedImage != null &&
                                _selectedImage!.isNotEmpty &&
                                !images.any((img) => img['name'] == _selectedImage))
                            ? [
                                DropdownMenuItem<String>(
                                  value: _selectedImage!,
                                  child: Text(
                                    '$_selectedImage (Archived)',
                                    style: SentinelTheme.body.copyWith(
                                      fontStyle: FontStyle.italic,
                                      color: SentinelTheme.warning,
                                    ),
                                  ),
                                ),
                              ]
                            : [],
                      ),
                  onChanged: _enabled
                      ? (val) => setState(() => _selectedImage = val)
                      : null,
                ),
              ),
            ),
            ),
            if (_selectedImage != null && (_selectedImage!.toLowerCase().endsWith('.sentinel') || images.any((i) => i['name'] == _selectedImage && i['type'] == 'sentinel')))
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: IconButton(
                  icon: Icon(Icons.preview, color: SentinelTheme.secondary),
                  tooltip: 'Preview .sentinel Image',
                  onPressed: _enabled ? () => showSentinelPreview(context, provider, _selectedImage!) : null,
                ),
              ),
            ],
          ),
          ),
          if (!_enabled)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Activa "Habilitar Maquetado" para aplicar una imagen o script.',
                style: SentinelTheme.label.copyWith(color: SentinelTheme.warning),
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
            if (!_enabled && _selectedImage != null && _selectedImage!.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Activa "Habilitar Maquetado" antes de aplicar la imagen.'),
                  backgroundColor: SentinelTheme.warning,
                ),
              );
              return;
            }

            // Allow disabling even if image is null
            if (_selectedImage == null && _enabled) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Debe seleccionar una imagen o script para habilitar la tarea',
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
                orderId: widget.orderId,
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

class _PortContextPopup extends StatefulWidget {
  final SentinelPort port;
  final SentinelSwitch parentSwitch;
  final int? orderId;
  final VoidCallback onClose;

  const _PortContextPopup({
    required this.port,
    required this.parentSwitch,
    this.orderId,
    required this.onClose,
  });

  @override
  State<_PortContextPopup> createState() => _PortContextPopupState();
}

class _PortContextPopupState extends State<_PortContextPopup> {
  late bool _enabled;
  bool _isCaptureMode = false;
  String? _selectedImage;
  bool _isLoading = false;
  final TextEditingController _captureNameController = TextEditingController();
  List<AgentOrder> _availableOrders = [];
  int? _selectedOrderId;
  bool _loadingOrders = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.port.imageEnabled;
    final img = widget.port.selectedImage;
    if (img != null && img.startsWith('CAPTURE:')) {
      _isCaptureMode = true;
      _captureNameController.text = img.substring(8);
    } else {
      _selectedImage = img;
    }
    _selectedOrderId = widget.orderId ?? widget.port.orderId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SentinelProvider>(
        context,
        listen: false,
      ).loadAvailableImages();
      _fetchCurrentSelection();
      _loadAvailableOrders();
    });
  }

  Future<void> _loadAvailableOrders() async {
    setState(() => _loadingOrders = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final service = OrderOpsService(apiService.client);
      final orders = await service.getAgentOrders(limit: 200);
      if (mounted) {
        setState(() {
          _availableOrders = orders;
        });
      }
    } catch (e) {
      debugPrint('Error loading orders in port context popup: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingOrders = false);
      }
    }
  }

  @override
  void dispose() {
    _captureNameController.dispose();
    super.dispose();
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
        final img = selection['image']?.toString();
        if (img != null && img.startsWith('CAPTURE:')) {
          _isCaptureMode = true;
          _selectedImage = null;
          _captureNameController.text = img.substring(8);
        } else {
          _isCaptureMode = false;
          _selectedImage = (img != null && img.isNotEmpty) ? img : null;
        }
        if (selection.containsKey('order_id')) {
          _selectedOrderId = selection['order_id'];
        }
      });
    }
  }

  Future<void> _save() async {
    String finalImageToSave = '';
    if (_enabled) {
      if (_isCaptureMode) {
        if (_captureNameController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Debe ingresar un nombre para la imagen a capturar'),
              backgroundColor: SentinelTheme.error,
            ),
          );
          return;
        }
        finalImageToSave = 'CAPTURE:${_captureNameController.text.trim()}';
      } else {
        if (_selectedImage == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Debe seleccionar una imagen o script para habilitar la tarea'),
              backgroundColor: SentinelTheme.error,
            ),
          );
          return;
        }
        finalImageToSave = _selectedImage!;
      }
    }

    setState(() => _isLoading = true);
    try {
      final provider = Provider.of<SentinelProvider>(context, listen: false);
      await provider.setImageSelection(
        scope: 'port',
        scopeId: widget.port.portId,
        image: finalImageToSave,
        enabled: _enabled,
        orderId: _selectedOrderId,
      );
      if (mounted) widget.onClose();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error guardando: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SentinelProvider>(context);
    final images = provider.availableImages;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SentinelTheme.bgPanel.withOpacity(0.98),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SentinelTheme.primary.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Port ${widget.port.portNumber}',
                      style: SentinelTheme.header,
                    ),
                    Text(
                      'Status: ${widget.port.status}',
                      style: SentinelTheme.label,
                    ),
                  ],
                ),
                if (widget.port.connectedMac != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: SentinelTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: SentinelTheme.primary.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      widget.port.connectedMac!,
                      style: SentinelTheme.mono.copyWith(fontSize: 10),
                    ),
                  ),
              ],
            ),
            const Divider(color: Colors.white24, height: 16),

            // Detailed Info
            _buildInfoRow('Etiqueta', widget.port.label),
            _buildInfoRow('Rol', widget.port.role.toUpperCase()),
            if (widget.port.orderId != null)
              _buildInfoRow('Orden ID', widget.port.orderId.toString()),
            if (widget.port.connectedDevice != null) ...[
              _buildInfoRow(
                'Dispositivo',
                widget.port.connectedDevice!.hostname ?? 'Desconocido',
              ),
              _buildInfoRow('IP', widget.port.connectedDevice!.ip ?? '-'),
              _buildInfoRow(
                'MAC',
                _normalizeMac(widget.port.connectedDevice!.mac),
              ),
            ],

            const Divider(color: Colors.white24, height: 16),

            // Image Settings
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Habilitar Tarea (Maquetado/Captura)',
                    style: SentinelTheme.subHeader.copyWith(
                      color: SentinelTheme.secondary,
                    ),
                  ),
                ),
                Switch(
                  value: _enabled,
                  onChanged: (val) => setState(() => _enabled = val),
                  activeColor: SentinelTheme.secondary,
                ),
              ],
            ),

            if (_enabled) ...[
              const SizedBox(height: 8),
              Text(
                'Asociar Orden',
                style: SentinelTheme.subHeader.copyWith(
                  color: SentinelTheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              _loadingOrders
                  ? const SizedBox(
                      height: 40,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: SentinelTheme.glassDecoration(
                        borderRadius: 8,
                        opacity: 0.05,
                        border: true,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton2<int>(
                          value: _selectedOrderId,
                          hint: Text(
                            'Seleccionar Orden...',
                            style: SentinelTheme.label.copyWith(
                              color: SentinelTheme.textDisabled,
                            ),
                          ),
                          dropdownStyleData: DropdownStyleData(
                            decoration: BoxDecoration(
                              color: SentinelTheme.bgPanel,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: SentinelTheme.primary.withOpacity(0.3),
                              ),
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 10),
                              ],
                            ),
                            elevation: 24,
                            offset: const Offset(0, -4),
                            maxHeight: 300,
                          ),
                          menuItemStyleData: const MenuItemStyleData(height: 40),
                          isExpanded: true,
                          buttonStyleData: ButtonStyleData(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          iconStyleData: const IconStyleData(
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: SentinelTheme.primary,
                            ),
                          ),
                          items: _availableOrders.map((ord) {
                            return DropdownMenuItem<int>(
                              value: ord.idnbr,
                              child: Text(
                                '${ord.orderNbr} - ${ord.customer} (${ord.proyecto ?? 'Sin Proy.'})',
                                overflow: TextOverflow.ellipsis,
                                style: SentinelTheme.body,
                              ),
                            );
                          }).toList()..addAll(
                            (_selectedOrderId != null &&
                                    !_availableOrders.any((ord) => ord.idnbr == _selectedOrderId))
                                ? [
                                    DropdownMenuItem<int>(
                                      value: _selectedOrderId!,
                                      child: Text(
                                        'Orden #$_selectedOrderId',
                                        style: SentinelTheme.body.copyWith(
                                          fontStyle: FontStyle.italic,
                                          color: SentinelTheme.warning,
                                        ),
                                      ),
                                    ),
                                  ]
                                : [],
                          ),
                          onChanged: (val) => setState(() => _selectedOrderId = val),
                        ),
                      ),
                    ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Modo Captura de Imagen',
                      style: SentinelTheme.subHeader.copyWith(
                        color: SentinelTheme.warning,
                      ),
                    ),
                  ),
                  Switch(
                    value: _isCaptureMode,
                    onChanged: (val) => setState(() => _isCaptureMode = val),
                    activeColor: SentinelTheme.warning,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (_isCaptureMode) ...[
                // Capture input field
                TextFormField(
                  controller: _captureNameController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Nombre de imagen deseado (ej. PC_NUEVA)',
                    labelStyle: TextStyle(color: SentinelTheme.warning.withOpacity(0.8), fontSize: 12),
                    hintText: 'ej. 1H84332Y5L',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: SentinelTheme.warning.withOpacity(0.5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: SentinelTheme.warning.withOpacity(0.5)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: SentinelTheme.warning),
                    ),
                    prefixIcon: const Icon(Icons.download, color: SentinelTheme.warning, size: 18),
                  ),
                ),
              ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: SentinelTheme.glassDecoration(
                        borderRadius: 8,
                        opacity: 0.05,
                        border: true,
                      ),
                      child: DropdownButtonHideUnderline(
                  child: DropdownButton2<String>(
                    value: _selectedImage,
                    hint: Text(
                      'Selecc. Objetivo (WIM/ESD/Dual-Boot/Sentinel/Script)',
                      style: SentinelTheme.label.copyWith(
                        color: SentinelTheme.textDisabled,
                      ),
                    ),
                    dropdownStyleData: DropdownStyleData(
                      decoration: BoxDecoration(
                        color: SentinelTheme.bgPanel,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: SentinelTheme.primary.withOpacity(0.3),
                        ),
                        boxShadow: [
                          BoxShadow(color: Colors.black54, blurRadius: 10),
                        ],
                      ),
                      elevation: 24,
                      offset: const Offset(0, -4),
                      maxHeight: 400,
                    ),
                    menuItemStyleData: const MenuItemStyleData(height: 40),
                    isExpanded: true,
                    buttonStyleData: ButtonStyleData(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    iconStyleData: const IconStyleData(
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: SentinelTheme.primary,
                      ),
                    ),
                    items:
                        images.map((img) {
                          final name = img['name']?.toString() ?? '';
                          final isDualBoot =
                              img['type']?.toString() == 'dualboot';
                          final isSentinel = img['type']?.toString() == 'sentinel' ||
                              name.toLowerCase().endsWith('.sentinel');
                          final isScript = img['type']?.toString() == 'script' ||
                              name.toUpperCase().startsWith('SCRIPT:');
                          final displayName = isScript && name.startsWith('SCRIPT:')
                              ? name.substring(7)
                              : name;
                          return DropdownMenuItem<String>(
                            value: name,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    displayName,
                                    overflow: TextOverflow.ellipsis,
                                    style: SentinelTheme.body.copyWith(
                                      color: isDualBoot
                                          ? Colors.purple[200]
                                          : (isSentinel
                                              ? Colors.amber[200]
                                              : (isScript
                                                  ? Colors.greenAccent
                                                  : Colors.white)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDualBoot
                                        ? Colors.purple.withOpacity(0.25)
                                        : (isSentinel
                                            ? Colors.amber.withOpacity(0.25)
                                            : (isScript
                                                ? Colors.green.withOpacity(0.2)
                                                : Colors.cyan.withOpacity(0.15))),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isDualBoot
                                          ? Colors.purple
                                          : (isSentinel
                                              ? Colors.amber
                                              : (isScript
                                                  ? Colors.greenAccent
                                                  : Colors.cyan)),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    isDualBoot
                                        ? 'DUAL-BOOT'
                                        : (isSentinel
                                            ? 'SENTINEL'
                                            : (isScript ? 'SCRIPT' : 'WIM')),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isDualBoot
                                          ? Colors.purple[100]
                                          : (isSentinel
                                              ? Colors.amber[100]
                                              : (isScript
                                                  ? Colors.greenAccent
                                                  : Colors.cyan[200])),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList()..addAll(
                          (_selectedImage != null &&
                                  _selectedImage!.isNotEmpty &&
                                  !images.any((img) => img['name'] == _selectedImage))
                              ? [
                                  DropdownMenuItem<String>(
                                    value: _selectedImage!,
                                    child: Text(
                                      '$_selectedImage (Archived)',
                                      style: SentinelTheme.body.copyWith(
                                        fontStyle: FontStyle.italic,
                                        color: SentinelTheme.warning,
                                      ),
                                    ),
                                  ),
                                ]
                              : [],
                        ),
                    onChanged: (val) => setState(() => _selectedImage = val),
                  ),
                ),
              ),
              ),
              if (_selectedImage != null && (_selectedImage!.toLowerCase().endsWith('.sentinel') || images.any((i) => i['name'] == _selectedImage && i['type'] == 'sentinel')))
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: IconButton(
                    icon: Icon(Icons.preview, color: SentinelTheme.secondary),
                    tooltip: 'Preview .sentinel Image',
                    onPressed: _enabled ? () => showSentinelPreview(context, provider, _selectedImage!) : null,
                  ),
                ),
              ],
            ),
              ],
            ],

            const SizedBox(height: 16),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SentinelTheme.secondary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: const Text('GUARDAR'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _normalizeMac(String mac) {
    // Basic normalization: remove non-hex chars, add colons, uppercase
    final clean = mac.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    if (clean.length != 12)
      return mac; // Return original if not standard length

    final buffer = StringBuffer();
    for (int i = 0; i < clean.length; i++) {
      buffer.write(clean[i]);
      if (i % 2 == 1 && i < clean.length - 1) {
        buffer.write(':');
      }
    }
    return buffer.toString();
  }
}

class _GridLinePainter extends CustomPainter {
  final double scale;
  final Offset offset;

  _GridLinePainter({required this.scale, required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    // Implementation for painting grid lines
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false; // Or implement logic to check if repaint is needed
  }
}

class _LayoutResetTrigger extends StatefulWidget {
  final List<int> visibleIds;
  final VoidCallback onReset;
  final Widget child;

  const _LayoutResetTrigger({
    super.key,
    required this.visibleIds,
    required this.onReset,
    required this.child,
  });

  @override
  State<_LayoutResetTrigger> createState() => _LayoutResetTriggerState();
}

class _LayoutResetTriggerState extends State<_LayoutResetTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.visibleIds.isNotEmpty) {
        widget.onReset();
      }
    });
  }

  @override
  void didUpdateWidget(_LayoutResetTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.visibleIds, oldWidget.visibleIds)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onReset();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
