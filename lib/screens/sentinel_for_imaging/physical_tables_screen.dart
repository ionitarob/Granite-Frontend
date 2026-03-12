import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sentinel_provider.dart';
import 'sentinel_models.dart';

import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';
import 'sentinel_theme.dart';
import 'package:dropdown_button2/dropdown_button2.dart';

class PhysicalTablesScreen extends StatefulWidget {
  const PhysicalTablesScreen({super.key});

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

    return ChangeNotifierProvider(
      create: (context) {
        final provider = SentinelProvider();
        final user = Provider.of<ApiService>(
          context,
          listen: false,
        ).currentUser;
        if (user != null) {
          provider.setUserName(user.displayName());
        }
        return provider;
      },
      child: Theme(
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
                      _SwitchSelector(),
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
        color: Colors.black26,
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
          Container(
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
                  'Selecc. Imagen (WIM/ESD/FFU)',
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
                      return DropdownMenuItem(
                        value: img,
                        child: Text(
                          img,
                          overflow: TextOverflow.ellipsis,
                          style: SentinelTheme.body.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      );
                    }).toList()..addAll(
                      // Ensure the currently selected image is in the list to avoid crash
                      (_selectedImage != null &&
                              _selectedImage!.isNotEmpty &&
                              !images.contains(_selectedImage))
                          ? [
                              DropdownMenuItem(
                                value: _selectedImage,
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

class _PortContextPopup extends StatefulWidget {
  final SentinelPort port;
  final SentinelSwitch parentSwitch;
  final VoidCallback onClose;

  const _PortContextPopup({
    required this.port,
    required this.parentSwitch,
    required this.onClose,
  });

  @override
  State<_PortContextPopup> createState() => _PortContextPopupState();
}

class _PortContextPopupState extends State<_PortContextPopup> {
  late bool _enabled;
  String? _selectedImage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.port.imageEnabled;
    _selectedImage = widget.port.selectedImage;
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
        final img = selection['image']?.toString();
        _selectedImage = (img != null && img.isNotEmpty) ? img : null;
      });
    }
  }

  Future<void> _save() async {
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

    setState(() => _isLoading = true);
    try {
      final provider = Provider.of<SentinelProvider>(context, listen: false);
      await provider.setImageSelection(
        scope: 'port',
        scopeId: widget.port.portId,
        image: _enabled ? (_selectedImage ?? '') : '',
        enabled: _enabled,
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
                    'Habilitar Maquetado',
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
              Container(
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
                      'Seleccionar Imagen',
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
                          return DropdownMenuItem(
                            value: img,
                            child: Text(
                              img,
                              overflow: TextOverflow.ellipsis,
                              style: SentinelTheme.body.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          );
                        }).toList()..addAll(
                          (_selectedImage != null &&
                                  _selectedImage!.isNotEmpty &&
                                  !images.contains(_selectedImage))
                              ? [
                                  DropdownMenuItem(
                                    value: _selectedImage,
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
