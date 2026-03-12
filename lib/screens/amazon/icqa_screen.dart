import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';

enum IcqaAction { reprint, disposition, lostFound }

class ICQAScreen extends StatefulWidget {
  const ICQAScreen({super.key});
  @override
  State<ICQAScreen> createState() => _ICQAScreenState();
}

class _ICQAScreenState extends State<ICQAScreen> with TickerProviderStateMixin {
  IcqaAction _action = IcqaAction.reprint;
  final _wplReprintController = TextEditingController();
  final _wplDispositionController = TextEditingController();
  final _wplLostFoundController = TextEditingController();
  String? _selectedDisposition;
  bool _busy = false;
  Map<String, dynamic>? _lastResult;
  late AnimationController _anim;
  late Animation<double> _fade;
  late AnimationController _bgController;
  late AnimationController _panelController;
  late Animation<double> _panelFade;
  late Animation<double> _panelScale;
  OverlayEntry? _edgeOverlay;

  static const List<String> dispositions = [
    'sellable',
    'unsellable',
    'damaged',
    'hold',
    'lost',
    'found',
    'qc',
    'return',
  ];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeInOut)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _anim.forward();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _panelFade = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOut,
    );
    _panelScale = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOutBack,
    );
    _panelController.forward();

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
    _anim.dispose();
    _bgController.dispose();
    _panelController.dispose();
    _wplReprintController.dispose();
    _wplDispositionController.dispose();
    _wplLostFoundController.dispose();
    super.dispose();
  }

  void _change(IcqaAction a) {
    if (_action == a) return;
    setState(() => _action = a);
    _anim.forward(from: 0);
  }

  Future<void> _doReprint() async {
    final w = _wplReprintController.text.trim();
    if (w.isEmpty) return _snack('Enter WPL');
    await _exec(() async {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post('/amz/tools/wpl/$w/reprint-label');
      if (!res.ok) throw Exception('Failed (${res.statusCode})');
      final b = res.body;
      return b is Map
          ? Map<String, dynamic>.from(b)
          : {'message': 'Reprint scheduled', 'wpl_id': w};
    }, clear: () => _wplReprintController.clear());
  }

  Future<void> _doUpdateDisposition() async {
    final w = _wplDispositionController.text.trim();
    if (w.isEmpty) return _snack('Enter WPL');
    final d = _selectedDisposition;
    if (d == null) return _snack('Select disposition');
    await _exec(() async {
      final api = Provider.of<ApiService>(context, listen: false);
      // API exposes a tools/wpl disposition endpoint; use the wpl path and send the new disposition
      final res = await api.client.post(
        '/amz/tools/wpl/$w/disposition',
        jsonBody: {'disposition': d},
      );
      if (!res.ok) throw Exception('Failed (${res.statusCode})');
      final b = res.body;
      return b is Map
          ? Map<String, dynamic>.from(b)
          : {'message': 'Disposition updated', 'wpl_id': w, 'new': d};
    });
  }

  Future<void> _doLostFound(bool lost) async {
    final w = _wplLostFoundController.text.trim();
    if (w.isEmpty) return _snack('Enter WPL');
    await _exec(() async {
      final api = Provider.of<ApiService>(context, listen: false);
      // Use the explicit lost/found endpoints when available
      final path = lost ? '/amz/tools/wpl/$w/lost' : '/amz/tools/wpl/$w/found';
      final res = await api.client.post(path);
      if (!res.ok) throw Exception('Failed (${res.statusCode})');
      final b = res.body;
      return b is Map
          ? Map<String, dynamic>.from(b)
          : {'message': lost ? 'Marked lost' : 'Marked found', 'wpl_id': w};
    }, clear: () => _wplLostFoundController.clear());
  }

  Future<void> _exec(
    Future<Map<String, dynamic>> Function() op, {
    VoidCallback? clear,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await op();
      setState(() => _lastResult = res);
      _snack(res['message']?.toString() ?? 'Done');
      clear?.call();
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final wide = size.width > 980;
    final compact = size.width < 520;
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: _buildGlassAppBar(context, compact: compact),
      body: Stack(
        children: [
          _IcqaBackground(animation: _bgController),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _bgController,
                builder: (_, __) => CustomPaint(
                  painter: _IcqaAmbientPainter(progress: _bgController.value),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (wide) ...[
                  SizedBox(
                    width: 250,
                    child: _SideNav(action: _action, onSelect: _change),
                  ),
                  const SizedBox(width: 24),
                ],
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 0 : 16,
                      8,
                      wide ? 8 : 16,
                      40,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!wide)
                          _TopSelectorBar(action: _action, onSelect: _change),
                        const SizedBox(height: 18),
                        FadeTransition(
                          opacity: _panelFade,
                          child: ScaleTransition(
                            scale: _panelScale,
                            child: _GlassPanel(
                              title: _panelTitle(),
                              child: _buildPanel(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),
                        if (_lastResult != null)
                          FadeTransition(
                            opacity: _fade,
                            child: _ResultCard(result: _lastResult!),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_busy) const _BusyOverlay(label: 'Processing...'),
          // EdgeNavHandle moved to OverlayEntry
        ],
      ),
    );
  }

  PreferredSizeWidget _buildGlassAppBar(
    BuildContext context, {
    required bool compact,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return PreferredSize(
      preferredSize: const Size.fromHeight(70),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 10 : 18,
          10,
          compact ? 10 : 18,
          0,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.07),
                    Colors.white.withOpacity(0.015),
                  ],
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 42),
                  const SizedBox(width: 10),
                  ShaderMask(
                    shaderCallback: (r) => LinearGradient(
                      colors: [primary, Colors.white],
                    ).createShader(r),
                    blendMode: BlendMode.srcIn,
                    child: const Text(
                      'ICQA Tools',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.05,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.qr_code_scanner,
                    size: 26,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _panelTitle() {
    switch (_action) {
      case IcqaAction.reprint:
        return 'Reprint WPL Label';
      case IcqaAction.disposition:
        return 'Update Pallet Disposition';
      case IcqaAction.lostFound:
        return 'Mark Lost or Found';
    }
  }

  Widget _buildPanel() {
    switch (_action) {
      case IcqaAction.reprint:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the WPL to schedule a label reprint.'),
            const SizedBox(height: 16),
            TextField(
              controller: _wplReprintController,
              decoration: const InputDecoration(labelText: 'WPL'),
              onSubmitted: (_) => _doReprint(),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _doReprint,
              icon: const Icon(Icons.print),
              label: Text(_busy ? 'Working...' : 'Reprint'),
            ),
          ],
        );
      case IcqaAction.disposition:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Change WPL disposition to one of the allowed values.'),
            const SizedBox(height: 16),
            TextField(
              controller: _wplDispositionController,
              decoration: const InputDecoration(labelText: 'WPL'),
              onSubmitted: (_) => _doUpdateDisposition(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedDisposition,
              decoration: const InputDecoration(labelText: 'Disposition'),
              items: dispositions
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedDisposition = v),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _doUpdateDisposition,
              icon: const Icon(Icons.update),
              label: Text(_busy ? 'Working...' : 'Update'),
            ),
          ],
        );
      case IcqaAction.lostFound:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Update pallet disposition quickly to lost or found.'),
            const SizedBox(height: 16),
            TextField(
              controller: _wplLostFoundController,
              decoration: const InputDecoration(labelText: 'WPL'),
              onSubmitted: (_) => _doLostFound(true),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _doLostFound(true),
                    icon: const Icon(Icons.visibility_off_outlined),
                    label: Text(_busy ? '...' : 'Mark Lost'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent.shade400,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _doLostFound(false),
                    icon: const Icon(Icons.visibility_outlined),
                    label: Text(_busy ? '...' : 'Mark Found'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }
}

// Reuse small components from the original file (kept local)
class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;
  const _NavTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(selected ? 0.45 : 0.12),
            width: 1,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(selected ? 0.18 : 0.07),
              Colors.white.withOpacity(0.018),
            ],
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: Colors.white.withOpacity(selected ? 0.95 : 0.75),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 260),
              opacity: selected ? 1 : 0,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopChip extends StatelessWidget {
  final String label;
  final bool sel;
  final VoidCallback onTap;
  const _TopChip({required this.label, required this.sel, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withOpacity(sel ? 0.5 : 0.15),
            width: 1,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(sel ? 0.20 : 0.07),
              Colors.white.withOpacity(0.02),
            ],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 16,
              color: Colors.white.withOpacity(0.9),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final String title;
  final Widget child;
  const _GlassPanel({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(30, 26, 30, 30),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.07),
                Colors.white.withOpacity(0.015),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 34,
                spreadRadius: 2,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.layers,
                    size: 22,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.9),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> result;
  const _ResultCard({required this.result});
  @override
  Widget build(BuildContext context) {
    final message = result['message']?.toString();
    final wpl = result['wpl_id']?.toString();
    final oldDisp = result['old']?.toString();
    final newDisp = result['new']?.toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(.25),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blueGrey.withOpacity(.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message != null)
            Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (wpl != null) Text('WPL: $wpl'),
          if (oldDisp != null && newDisp != null)
            Text('Disposition: $oldDisp -> $newDisp'),
          if (result.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: result.entries
                  .where(
                    (e) =>
                        e.key != 'message' &&
                        e.key != 'wpl_id' &&
                        e.key != 'old' &&
                        e.key != 'new',
                  )
                  .map((e) => Chip(label: Text('${e.key}: ${e.value}')))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  final IcqaAction action;
  final ValueChanged<IcqaAction> onSelect;
  const _SideNav({required this.action, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 40),
      child: Column(
        children: [
          _NavTile(
            icon: Icons.print_outlined,
            title: 'Reprint Label',
            selected: action == IcqaAction.reprint,
            onTap: () => onSelect(IcqaAction.reprint),
          ),
          _NavTile(
            icon: Icons.swap_horiz_outlined,
            title: 'Update Disposition',
            selected: action == IcqaAction.disposition,
            onTap: () => onSelect(IcqaAction.disposition),
          ),
          _NavTile(
            icon: Icons.search_off_outlined,
            title: 'Lost / Found',
            selected: action == IcqaAction.lostFound,
            onTap: () => onSelect(IcqaAction.lostFound),
          ),
        ],
      ),
    );
  }
}

class _TopSelectorBar extends StatelessWidget {
  final IcqaAction action;
  final ValueChanged<IcqaAction> onSelect;
  const _TopSelectorBar({required this.action, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _TopChip(
          label: 'Reprint',
          sel: action == IcqaAction.reprint,
          onTap: () => onSelect(IcqaAction.reprint),
        ),
        _TopChip(
          label: 'Disposition',
          sel: action == IcqaAction.disposition,
          onTap: () => onSelect(IcqaAction.disposition),
        ),
        _TopChip(
          label: 'Lost / Found',
          sel: action == IcqaAction.lostFound,
          onTap: () => onSelect(IcqaAction.lostFound),
        ),
      ],
    );
  }
}

class _BusyOverlay extends StatelessWidget {
  final String label;
  const _BusyOverlay({required this.label});
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 54,
                height: 54,
                child: CircularProgressIndicator(strokeWidth: 5),
              ),
              const SizedBox(height: 20),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IcqaBackground extends StatelessWidget {
  final Animation<double> animation;
  const _IcqaBackground({required this.animation});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(primary.withOpacity(0.95), Colors.black, 0.45)!,
              Color.lerp(Colors.black, secondary.withOpacity(0.55), 0.22)!,
              Colors.black,
            ],
          ),
        ),
      ),
    );
  }
}

class _IcqaAmbientPainter extends CustomPainter {
  final double progress;
  _IcqaAmbientPainter({required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05
      ..color = Colors.white.withOpacity(0.055);
    const spacing = 86.0;
    final shift = progress * spacing;
    for (double x = -spacing + shift; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x - 46, size.height), paint);
    }
    for (double y = -spacing + shift; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 46), paint);
    }
    final glowCenter = Offset(
      size.width * (0.5 + 0.24 * math.sin(progress * 2 * math.pi)),
      size.height * 0.36,
    );
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [Colors.white.withOpacity(0.09), Colors.transparent],
          ).createShader(
            Rect.fromCircle(center: glowCenter, radius: size.width * 0.9),
          );
    canvas.drawCircle(glowCenter, size.width * 0.9, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _IcqaAmbientPainter oldDelegate) => true;
}
