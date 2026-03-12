import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/main_sidebar.dart';
import '../../services/api_service.dart';

/// Migrated ProductPickScreen (legacy) adapted to use ApiService.client
class ProductPickScreen extends StatefulWidget {
  const ProductPickScreen({super.key});

  @override
  State<ProductPickScreen> createState() => _ProductPickScreenState();
}

class _ProductPickScreenState extends State<ProductPickScreen>
    with TickerProviderStateMixin {
  final _wplController = TextEditingController();
  PalletPickInfo? _pallet;
  bool _loading = false;
  String? _error;
  String? _selectedPart;
  final _qtyController = TextEditingController();
  final _openReasonController = TextEditingController();

  late final AnimationController _bgController;
  late final AnimationController _panelController; // for panel transitions
  late final Animation<double> _panelScale;
  late final Animation<double> _panelFade;
  OverlayEntry? _edgeOverlay;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    )..repeat();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _panelScale = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOutBack,
    );
    _panelFade = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOut,
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
    _wplController.dispose();
    _qtyController.dispose();
    _openReasonController.dispose();
    _bgController.dispose();
    _panelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final wpl = _wplController.text.trim();
    if (wpl.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _pallet = null;
    });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.get('/amz/picking/wpl/$wpl');
      if (!res.ok) throw Exception('HTTP ${res.statusCode}');
      // parse into local model
      final body = res.body;
      if (body is Map) {
        setState(() {
          _pallet = PalletPickInfo.fromJson(body);
          if (_pallet!.parts.isNotEmpty) {
            _selectedPart ??= _pallet!.parts.first.partNumber;
          }
        });
      } else {
        setState(() => _error = 'Unexpected response shape');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _openPallet() async {
    if (_pallet == null) return;
    final reason = _openReasonController.text.trim();
    setState(() => _loading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post(
        '/amz/picking/wpl/${_pallet!.wplId}/open',
        jsonBody: {'reason': reason.isEmpty ? null : reason},
      );
      if (!res.ok) throw Exception('Open failed: ${res.statusCode}');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Pallet opened')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Open failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick() async {
    if (_pallet == null || !_pallet!.isOpen) return;
    final part = _selectedPart;
    if (part == null) return;
    final qty = int.tryParse(_qtyController.text.trim());
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a positive quantity')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post(
        '/amz/picking/wpl/${_pallet!.wplId}/pick',
        jsonBody: {'part_number': part, 'quantity': qty},
      );
      if (!res.ok) throw Exception('Pick failed: ${res.statusCode}');
      // assume backend returns updated pallet
      if (res.body is Map) {
        setState(() {
          _pallet = PalletPickInfo.fromJson(res.body as Map);
          _qtyController.clear();
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Picked $qty from $part')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Pick failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _closePallet() async {
    if (_pallet == null || !_pallet!.isOpen) return;
    final originalLocation = _pallet!.locationNo;
    final locController = TextEditingController(text: originalLocation ?? '');
    String chosen = originalLocation ?? '';
    bool changeLocation = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            title: const Text('Close Pallet'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (originalLocation != null)
                  RadioListTile<bool>(
                    value: false,
                    groupValue: changeLocation,
                    onChanged: (v) =>
                        setStateDialog(() => changeLocation = v ?? false),
                    title: Text('Keep same location ($originalLocation)'),
                  ),
                RadioListTile<bool>(
                  value: true,
                  groupValue: changeLocation,
                  onChanged: (v) =>
                      setStateDialog(() => changeLocation = v ?? true),
                  title: const Text('Change location'),
                ),
                if (changeLocation)
                  TextField(
                    controller: locController,
                    decoration: const InputDecoration(
                      labelText: 'New Location',
                    ),
                    onChanged: (v) => chosen = v.trim(),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post(
        '/amz/picking/wpl/${_pallet!.wplId}/close',
        jsonBody: {'location_no': changeLocation ? chosen : originalLocation},
      );
      if (!res.ok) throw Exception('Close failed: ${res.statusCode}');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Pallet closed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Close failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  PreferredSizeWidget _buildGlassAppBar(
    BuildContext context, {
    required bool compact,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return PreferredSize(
      preferredSize: const Size.fromHeight(70),
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 8 : 16, 10, compact ? 8 : 16, 0),
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
                  // intentionally do not show system back arrow (app uses edge nav handle)
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.inventory_2_rounded,
                    size: 26,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  ShaderMask(
                    shaderCallback: (r) => LinearGradient(
                      colors: [primary, Colors.white],
                    ).createShader(r),
                    blendMode: BlendMode.srcIn,
                    child: const Text(
                      'Product Pick',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Reload',
                    onPressed: () => _load(),
                    icon: const Icon(Icons.refresh, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar({required bool compact}) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _wplController,
            decoration: const InputDecoration(labelText: 'WPL ID'),
            onSubmitted: (_) => _load(),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.search),
            label: const Text('Search'),
          ),
        ),
      ],
    );
  }

  Widget _buildPickForm(PalletPickInfo p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pick Units', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 620;
            final fields = [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedPart,
                  items: p.parts
                      .map(
                        (part) => DropdownMenuItem(
                          value: part.partNumber,
                          child: Text('${part.partNumber} (${part.units})'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedPart = v),
                  decoration: const InputDecoration(labelText: 'Part Number'),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: _pick,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: Text('Pick'),
                  ),
                ),
              ),
            ];
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  fields[0],
                  const SizedBox(height: 12),
                  Row(children: [fields[1], fields[2], fields[3]]),
                ],
              );
            }
            return Row(children: fields);
          },
        ),
      ],
    );
  }

  Widget _buildPartsTable(PalletPickInfo p) {
    if (p.parts.isEmpty) return const Text('No parts on pallet.');
    return DataTable(
      columns: const [
        DataColumn(label: Text('Part Number')),
        DataColumn(label: Text('Units')),
      ],
      rows: p.parts
          .map(
            (part) => DataRow(
              cells: [
                DataCell(Text(part.partNumber)),
                DataCell(Text(part.units.toString())),
              ],
            ),
          )
          .toList(),
      headingRowHeight: 32,
      dataRowMinHeight: 32,
      dataRowMaxHeight: 38,
    );
  }

  Widget _buildContent() {
    final p = _pallet;
    if (p == null) return const Center(child: Text('Enter a WPL ID to begin'));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GlassPanel(
            title: 'Pallet Overview',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _InfoChip(label: 'WPL', value: p.wplId),
                    _InfoChip(
                      label: 'Status',
                      value: p.status,
                      color: p.isOpen ? Colors.green : Colors.red,
                    ),
                    if (p.locationNo != null)
                      _InfoChip(label: 'Location', value: p.locationNo!),
                    if (p.disposition != null)
                      _InfoChip(label: 'Disposition', value: p.disposition!),
                    if (p.node != null)
                      _InfoChip(label: 'Node', value: p.node!),
                  ],
                ),
                const SizedBox(height: 18),
                if (!p.isOpen)
                  _ClosedPalletPanel(
                    openReasonController: _openReasonController,
                    onOpen: _openPallet,
                  )
                else
                  _buildPickForm(p),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _GlassPanel(title: 'Parts on Pallet', child: _buildPartsTable(p)),
          const SizedBox(height: 22),
          _GlassPanel(
            title: 'Units (Detailed)',
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              initiallyExpanded: false,
              title: const Text('Tap to expand units list'),
              children: p.units
                  .map(
                    (u) => ListTile(
                      dense: true,
                      title: Text('${u.partNumber}  x${u.quantity}'),
                      subtitle: Text(u.id),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (p.picked != null) ...[
            const SizedBox(height: 22),
            _GlassPanel(
              title: 'Last Pick Summary',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Part: ${p.picked!.partNumber}  Removed: ${p.picked!.removed}/${p.picked!.requested}',
                  ),
                  const SizedBox(height: 8),
                  ...p.picked!.events.map(
                    (e) => Text(
                      'Unit ${e.unitId} - ${e.removed} ( ${e.before} -> ${e.after} )',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading;
    final size = MediaQuery.of(context).size;
    final compact = size.width < 420;
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: _buildGlassAppBar(context, compact: compact),
      floatingActionButton: (_pallet != null && _pallet!.isOpen)
          ? FloatingActionButton.extended(
              onPressed: busy ? null : _closePallet,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Close'),
            )
          : null,
      body: Stack(
        children: [
          _PickBackground(animation: _bgController),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _bgController,
                builder: (_, __) => CustomPaint(
                  painter: _PickAmbientPainter(progress: _bgController.value),
                ),
              ),
            ),
          ),

          SafeArea(
            child: AbsorbPointer(
              absorbing: busy,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 24,
                  16,
                  compact ? 14 : 24,
                  40,
                ),
                child: Column(
                  children: [
                    _buildSearchBar(compact: compact),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      _ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 18),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 450),
                        transitionBuilder: (c, a) => FadeTransition(
                          opacity: a,
                          child: ScaleTransition(scale: a, child: c),
                        ),
                        child: _pallet == null
                            ? const _EmptyPrompt(key: ValueKey('empty'))
                            : ScaleTransition(
                                key: const ValueKey('content'),
                                scale: _panelScale,
                                child: FadeTransition(
                                  opacity: _panelFade,
                                  child: _buildContent(),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (busy)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),

          // Edge nav handle so the MainSidebar can be shown
          // EdgeNavHandle moved to OverlayEntry
        ],
      ),
    );
  }
}

// --- Local lightweight models to avoid depending on legacy packages ---
class PalletPickInfo {
  final String wplId;
  final bool isOpen;
  final String status;
  final String? locationNo;
  final String? disposition;
  final String? node;
  final List<PartInfo> parts;
  final List<UnitInfo> units;
  final PickSummary? picked;

  PalletPickInfo({
    required this.wplId,
    required this.isOpen,
    required this.status,
    this.locationNo,
    this.disposition,
    this.node,
    required this.parts,
    required this.units,
    this.picked,
  });

  factory PalletPickInfo.fromJson(Map m) {
    final parts = <PartInfo>[];
    if (m['parts'] is List) {
      for (final e in m['parts']) {
        try {
          parts.add(PartInfo.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
    }
    final units = <UnitInfo>[];
    if (m['units'] is List) {
      for (final e in m['units']) {
        try {
          units.add(UnitInfo.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
    }
    PickSummary? picked;
    if (m['picked'] is Map) {
      picked = PickSummary.fromJson(Map<String, dynamic>.from(m['picked']));
    }
    return PalletPickInfo(
      wplId: (m['wplId'] ?? m['wpl_id'] ?? m['id'] ?? '').toString(),
      isOpen: (m['isOpen'] ?? m['is_open'] ?? m['open'] ?? false) as bool,
      status: (m['status'] ?? '').toString(),
      locationNo: m['locationNo']?.toString() ?? m['location_no']?.toString(),
      disposition: m['disposition']?.toString(),
      node: m['node']?.toString(),
      parts: parts,
      units: units,
      picked: picked,
    );
  }
}

class PartInfo {
  final String partNumber;
  final int units;
  PartInfo({required this.partNumber, required this.units});
  factory PartInfo.fromJson(Map m) => PartInfo(
    partNumber: (m['partNumber'] ?? m['part_number'] ?? '').toString(),
    units: (m['units'] ?? m['quantity'] ?? 0) as int,
  );
}

class UnitInfo {
  final String id;
  final String partNumber;
  final int quantity;
  UnitInfo({
    required this.id,
    required this.partNumber,
    required this.quantity,
  });
  factory UnitInfo.fromJson(Map m) => UnitInfo(
    id: (m['id'] ?? '').toString(),
    partNumber: (m['partNumber'] ?? m['part_number'] ?? '').toString(),
    quantity: (m['quantity'] ?? 0) as int,
  );
}

class PickSummary {
  final String partNumber;
  final int removed;
  final int requested;
  final List<PickEvent> events;
  PickSummary({
    required this.partNumber,
    required this.removed,
    required this.requested,
    required this.events,
  });
  factory PickSummary.fromJson(Map m) => PickSummary(
    partNumber: (m['partNumber'] ?? m['part_number'] ?? '').toString(),
    removed: (m['removed'] ?? 0) as int,
    requested: (m['requested'] ?? 0) as int,
    events: m['events'] is List
        ? (m['events'] as List)
              .map((e) => PickEvent.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : [],
  );
}

class PickEvent {
  final String unitId;
  final int removed;
  final dynamic before;
  final dynamic after;
  PickEvent({
    required this.unitId,
    required this.removed,
    this.before,
    this.after,
  });
  factory PickEvent.fromJson(Map m) => PickEvent(
    unitId: (m['unitId'] ?? m['unit_id'] ?? '').toString(),
    removed: (m['removed'] ?? 0) as int,
    before: m['before'],
    after: m['after'],
  );
}

// === Glass / Background Components ===
class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _InfoChip({required this.label, required this.value, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withOpacity(0.4), width: 1),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withOpacity(0.22), c.withOpacity(0.06)],
        ),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: Colors.white,
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
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(30, 28, 30, 32),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
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
                      color: primary.withOpacity(0.9),
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
      ),
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(
        opacity: 0.85,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_rounded,
              size: 64,
              color: Colors.white.withOpacity(0.55),
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter or scan a WPL ID to begin',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClosedPalletPanel extends StatelessWidget {
  final TextEditingController openReasonController;
  final VoidCallback onOpen;
  const _ClosedPalletPanel({
    required this.openReasonController,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pallet is closed. Open to pick.',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: openReasonController,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.lock_open),
          label: const Text('Open Pallet'),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.red.withOpacity(0.12),
        border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 13.5,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickBackground extends StatelessWidget {
  final Animation<double> animation;
  const _PickBackground({required this.animation});
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
              Color.lerp(primary.withOpacity(0.95), Colors.black, 0.4)!,
              Color.lerp(Colors.black, secondary.withOpacity(0.6), 0.25)!,
              Colors.black,
            ],
          ),
        ),
      ),
    );
  }
}

class _PickAmbientPainter extends CustomPainter {
  final double progress;
  _PickAmbientPainter({required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.white.withOpacity(0.055);
    const spacing = 88.0;
    final shift = progress * spacing;
    for (double x = -spacing + shift; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x - 48, size.height), paint);
    }
    for (double y = -spacing + shift; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 48), paint);
    }
    final glowCenter = Offset(
      size.width * (0.5 + 0.25 * math.sin(progress * 2 * math.pi)),
      size.height * 0.34,
    );
    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [Colors.white.withOpacity(0.085), Colors.transparent],
          ).createShader(
            Rect.fromCircle(center: glowCenter, radius: size.width * 0.85),
          );
    canvas.drawCircle(glowCenter, size.width * 0.85, glow);
  }

  @override
  bool shouldRepaint(covariant _PickAmbientPainter oldDelegate) => true;
}
