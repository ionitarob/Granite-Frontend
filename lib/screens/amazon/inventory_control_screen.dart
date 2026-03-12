import 'dart:math' as math;
import 'dart:ui';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';

enum _Mode { part, wpl }

class InventoryControlScreen extends StatefulWidget {
  const InventoryControlScreen({super.key});
  @override
  State<InventoryControlScreen> createState() => _InventoryControlScreenState();
}

class _InventoryControlScreenState extends State<InventoryControlScreen>
    with TickerProviderStateMixin {
  _Mode _mode = _Mode.part;
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  PartInventory? _partInventory;
  WplInventory? _wplInventory;
  late final AnimationController _bgController;
  late final AnimationController _panelController;
  late final Animation<double> _panelFade;
  late final Animation<double> _panelScale;
  OverlayEntry? _edgeOverlay;

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _partInventory = null;
      _wplInventory = null;
    });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      if (_mode == _Mode.part) {
        final res = await api.client.get('/amz/inventory/part/$query');
        if (res.ok && res.body is Map) {
          setState(
            () => _partInventory = PartInventory.fromJson(
              Map<String, dynamic>.from(res.body as Map),
            ),
          );
        } else if (res.error != null) {
          setState(() => _error = res.error);
        } else {
          setState(() => _error = 'Not found');
        }
      } else {
        final res = await api.client.get('/amz/inventory/wpl/$query');
        if (res.ok && res.body is Map) {
          setState(
            () => _wplInventory = WplInventory.fromJson(
              Map<String, dynamic>.from(res.body as Map),
            ),
          );
        } else if (res.error != null) {
          setState(() => _error = res.error);
        } else {
          setState(() => _error = 'Not found');
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final compact = size.width < 420;
    // Use an edge navigation handle (like AmazonGradingScreen) so the sidebar
    // can be opened from the left; don't show a permanent sidebar here.
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: _buildGlassAppBar(context, compact: compact),
      body: Stack(
        children: [
          _InventoryBackground(animation: _bgController),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _bgController,
                builder: (_, __) => CustomPaint(
                  painter: _InventoryAmbientPainter(
                    progress: _bgController.value,
                  ),
                ),
              ),
            ),
          ),
          // Make all body text white by default (app bar remains unchanged)
          DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 24,
                  16,
                  compact ? 14 : 24,
                  26,
                ),
                child: Column(
                  children: [
                    _buildSearchBar(compact: compact),
                    const SizedBox(height: 14),
                    if (_loading) const LinearProgressIndicator(minHeight: 3),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 12),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 420),
                        transitionBuilder: (c, a) => FadeTransition(
                          opacity: a,
                          child: ScaleTransition(scale: a, child: c),
                        ),
                        child: _buildResult(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Edge nav handle so the MainSidebar can be shown (same pattern as grading screen)
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
                  // Back arrow intentionally removed to keep the sidebar as the
                  // persistent navigation element for this screen.
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
                      'Inventory Control',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _ExportAllButton(onExport: _exportAll),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Clear',
                    onPressed: () {
                      setState(() {
                        _controller.clear();
                        _partInventory = null;
                        _wplInventory = null;
                        _error = null;
                      });
                    },
                    icon: const Icon(Icons.clear_all, color: Colors.white70),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 18, 18, compact ? 18 : 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.07),
                Colors.white.withOpacity(0.02),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SegmentedButton<_Mode>(
                    segments: const [
                      ButtonSegment(value: _Mode.part, label: Text('Part #')),
                      ButtonSegment(value: _Mode.wpl, label: Text('WPL')),
                    ],
                    selected: <_Mode>{_mode},
                    onSelectionChanged: (s) {
                      setState(() {
                        _mode = s.first;
                        _partInventory = null;
                        _wplInventory = null;
                        _error = null;
                      });
                    },
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        labelText: _mode == _Mode.part
                            ? 'Part Number'
                            : 'WPL ID',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: _loading ? null : _search,
                        ),
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Opacity(
                opacity: 0.55,
                child: Text(
                  _mode == _Mode.part
                      ? 'Search by part number to view aggregated inventory and unit breakdown.'
                      : 'Search by WPL (pallet) ID to view its parts and units.',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResult() {
    if (_partInventory == null && _wplInventory == null) {
      return const _EmptyPrompt(message: 'Enter a query to view inventory');
    }
    if (_partInventory != null) {
      return FadeTransition(
        opacity: _panelFade,
        child: ScaleTransition(
          scale: _panelScale,
          child: _GlassPanel(
            title: 'Part Inventory',
            child: _PartInventoryView(inv: _partInventory!),
          ),
        ),
      );
    }
    if (_wplInventory != null) {
      return FadeTransition(
        opacity: _panelFade,
        child: ScaleTransition(
          scale: _panelScale,
          child: _GlassPanel(
            title: 'WPL Inventory',
            child: _WplInventoryView(inv: _wplInventory!),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    _edgeOverlay?.remove();
    _controller.dispose();
    _bgController.dispose();
    _panelController.dispose();
    super.dispose();
  }

  // Note: export is implemented by the _ExportButton and _ExportAllButton
  // which call the ApiClient directly. This helper was removed because it
  // wasn't referenced elsewhere.

  Future<void> _exportAll() async {
    setState(() => _loading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      // backend exposes /amz/inventory/export for exports
      final res = await api.client.getBytes('/amz/inventory/export');
      if (res.ok && res.body is Uint8List) {
        final bytes = res.body as Uint8List;
        final dir = await getTemporaryDirectory();
        final fname =
            'inventory_export_all_${DateTime.now().toUtc().toIso8601String().replaceAll(':', '')}.xlsx';
        final path = '${dir.path}/$fname';
        final f = File(path);
        await f.writeAsBytes(bytes, flush: true);
        await OpenFilex.open(path);
      } else {
        setState(() => _error = res.error ?? 'Export failed');
      }
    } catch (e) {
      setState(() => _error = 'Export exception: $e');
    } finally {
      setState(() => _loading = false);
    }
  }
}

// --- Models adapted for the backend JSON shape ---
class PartInventory {
  final String partNumber;
  final int totalUnits;
  final List<LocationEntry> locations;
  final List<UnitEntry> units;
  final List<InventoryLog> logs;

  PartInventory({
    required this.partNumber,
    required this.totalUnits,
    required this.locations,
    required this.units,
    required this.logs,
  });

  factory PartInventory.fromJson(Map<String, dynamic> j) {
    return PartInventory(
      partNumber: j['part_number']?.toString() ?? '',
      totalUnits: (j['total_units'] is int)
          ? j['total_units'] as int
          : int.tryParse((j['total_units'] ?? '0').toString()) ?? 0,
      locations:
          (j['locations'] as List<dynamic>?)
              ?.map(
                (e) =>
                    LocationEntry.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList() ??
          [],
      units:
          (j['units'] as List<dynamic>?)
              ?.map(
                (e) => UnitEntry.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList() ??
          [],
      logs:
          (j['logs'] as List<dynamic>?)
              ?.map(
                (e) =>
                    InventoryLog.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList() ??
          [],
    );
  }
}

class LocationEntry {
  final String wplId;
  final String? locationNo;
  final int units;
  LocationEntry({required this.wplId, this.locationNo, required this.units});
  factory LocationEntry.fromJson(Map<String, dynamic> j) => LocationEntry(
    wplId: j['wpl_id']?.toString() ?? '',
    locationNo: j['location_no']?.toString(),
    units: (j['units'] is int)
        ? j['units'] as int
        : int.tryParse((j['units'] ?? '0').toString()) ?? 0,
  );
}

class UnitEntry {
  final String id;
  final int quantity;
  final String? partNumber;
  final String? wplId;
  final String? locationNo;
  UnitEntry({
    required this.id,
    required this.quantity,
    this.partNumber,
    this.wplId,
    this.locationNo,
  });
  factory UnitEntry.fromJson(Map<String, dynamic> j) => UnitEntry(
    id: j['id']?.toString() ?? '',
    quantity: (j['quantity'] is int)
        ? j['quantity'] as int
        : int.tryParse((j['quantity'] ?? '0').toString()) ?? 0,
    partNumber: j['part_number']?.toString(),
    wplId: j['wpl_id']?.toString(),
    locationNo: j['location_no']?.toString(),
  );
}

class InventoryLog {
  final DateTime? date;
  final String action;
  final int? quantityDelta;
  final String? partNumber;
  final String? wplId;
  final String? fromWplId;
  final String? toWplId;
  final String? user;

  InventoryLog({
    this.date,
    required this.action,
    this.quantityDelta,
    this.partNumber,
    this.wplId,
    this.fromWplId,
    this.toWplId,
    this.user,
  });

  factory InventoryLog.fromJson(Map<String, dynamic> j) {
    String? pick(List<String> keys) {
      for (final k in keys) {
        if (j.containsKey(k) && j[k] != null) return j[k].toString();
      }
      return null;
    }

    return InventoryLog(
      date: j['date'] != null ? DateTime.tryParse(j['date'].toString()) : null,
      action: j['action']?.toString() ?? '',
      quantityDelta: j['quantity_delta'] is int
          ? j['quantity_delta'] as int
          : int.tryParse((j['quantity_delta'] ?? '').toString()),
      partNumber: j['part_number']?.toString(),
      wplId: pick(['wpl_id', 'pallet_id', 'pallet_unit_id']),
      fromWplId: pick(['from_wpl_id', 'from_pallet_id', 'fromWplId']),
      toWplId: pick(['to_wpl_id', 'to_pallet_id', 'toWplId']),
      user: j['user']?.toString(),
    );
  }
}

class WplInventory {
  final String wplId;
  final String? locationNo;
  final int totalUnits;
  final List<PartAggregation> parts;
  final List<UnitEntry> units;
  final List<InventoryLog> logs;
  WplInventory({
    required this.wplId,
    this.locationNo,
    required this.totalUnits,
    required this.parts,
    required this.units,
    required this.logs,
  });
  factory WplInventory.fromJson(Map<String, dynamic> j) => WplInventory(
    wplId: j['wpl_id']?.toString() ?? '',
    locationNo: j['location_no']?.toString(),
    totalUnits: (j['total_units'] is int)
        ? j['total_units'] as int
        : int.tryParse((j['total_units'] ?? '0').toString()) ?? 0,
    parts:
        (j['parts'] as List<dynamic>?)
            ?.map(
              (e) =>
                  PartAggregation.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList() ??
        [],
    units:
        (j['units'] as List<dynamic>?)
            ?.map(
              (e) => UnitEntry.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList() ??
        [],
    logs:
        (j['logs'] as List<dynamic>?)
            ?.map(
              (e) => InventoryLog.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList() ??
        [],
  );
}

class PartAggregation {
  final String partNumber;
  final int units;
  PartAggregation({required this.partNumber, required this.units});
  factory PartAggregation.fromJson(Map<String, dynamic> j) => PartAggregation(
    partNumber: j['part_number']?.toString() ?? '',
    units: (j['units'] is int)
        ? j['units'] as int
        : int.tryParse((j['units'] ?? '0').toString()) ?? 0,
  );
}

// The rest of the UI widgets (_PartInventoryView, _WplInventoryView, _LogsSection,
// _SummaryTile, etc.) are re-used below. For brevity they are copied from the
// original and adapted to use the local models and the _ExportButton calling
// _exportWplExcel above.

class _PartInventoryView extends StatelessWidget {
  final PartInventory inv;
  const _PartInventoryView({required this.inv});
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryRow(
            items: [
              _SummaryTile(title: 'Part', value: inv.partNumber),
              _SummaryTile(
                title: 'Total Units',
                value: inv.totalUnits.toString(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (inv.locations.isNotEmpty) ...[
            const _SectionHeader('Locations'),
            ...inv.locations.map(
              (l) => _GlassListTile(
                leading: Icons.inventory_2_outlined,
                title: l.wplId,
                subtitle: l.locationNo ?? 'No location',
                trailing: l.units.toString(),
              ),
            ),
            const Divider(height: 28),
          ],
          const _SectionHeader('Units'),
          ...inv.units.map(
            (u) => _GlassListTile(
              dense: true,
              leading: Icons.widgets_outlined,
              title: 'Qty ${u.quantity}',
              subtitle: (u.locationNo ?? u.wplId) ?? '',
              trailing: u.id.substring(0, u.id.length > 6 ? 6 : u.id.length),
            ),
          ),
          const Divider(height: 32),
          _LogsSection(logs: inv.logs),
        ],
      ),
    );
  }
}

class _WplInventoryView extends StatelessWidget {
  final WplInventory inv;
  const _WplInventoryView({required this.inv});
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: _ExportButton(wplId: inv.wplId),
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            items: [
              _SummaryTile(title: 'WPL', value: inv.wplId),
              _SummaryTile(title: 'Location', value: inv.locationNo ?? '—'),
              _SummaryTile(
                title: 'Total Units',
                value: inv.totalUnits.toString(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (inv.parts.isNotEmpty) ...[
            const _SectionHeader('Parts Aggregation'),
            ...inv.parts.map(
              (p) => _GlassListTile(
                leading: Icons.category_outlined,
                title: p.partNumber,
                trailing: p.units.toString(),
              ),
            ),
            const Divider(height: 28),
          ],
          const _SectionHeader('Units'),
          ...inv.units.map(
            (u) => _GlassListTile(
              dense: true,
              leading: Icons.widgets_outlined,
              title: u.partNumber ?? '',
              subtitle: 'Qty ${u.quantity}',
              trailing: u.id.substring(0, u.id.length > 6 ? 6 : u.id.length),
            ),
          ),
          const Divider(height: 32),
          _LogsSection(logs: inv.logs),
        ],
      ),
    );
  }
}

class _LogsSection extends StatelessWidget {
  final List<InventoryLog> logs;
  const _LogsSection({required this.logs});
  @override
  Widget build(BuildContext context) {
    return _GlassExpander(
      icon: Icons.history,
      title: 'History (${logs.length})',
      child: logs.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('No history'),
            )
          : Column(
              children: logs.reversed.take(50).map((l) {
                final ts = l.date != null ? _fmt(l.date!) : '';
                final desc = StringBuffer(l.action)
                  ..write(' Δ${l.quantityDelta ?? ''}')
                  ..write(l.partNumber != null ? ' ${l.partNumber}' : '')
                  ..write(l.wplId != null ? ' @${l.wplId}' : '')
                  ..write(l.fromWplId ?? '')
                  ..write(l.toWplId ?? '');
                return _GlassListTile(
                  dense: true,
                  leading: Icons.event_note_outlined,
                  title: desc.toString(),
                  subtitle: ts,
                  trailing: l.user ?? '',
                );
              }).toList(),
            ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _SummaryTile extends StatelessWidget {
  final String title;
  final String value;
  const _SummaryTile({required this.title, required this.value});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.02),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontSize: 11, letterSpacing: .5),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final List<_SummaryTile> items;
  const _SummaryRow({required this.items});
  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 12, runSpacing: 12, children: items);
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
      ),
    ),
  );
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

class _InventoryBackground extends StatelessWidget {
  final Animation<double> animation;
  const _InventoryBackground({required this.animation});
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

class _InventoryAmbientPainter extends CustomPainter {
  final double progress;
  _InventoryAmbientPainter({required this.progress});
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
  bool shouldRepaint(covariant _InventoryAmbientPainter oldDelegate) => true;
}

class _GlassPanel extends StatelessWidget {
  final String title;
  final Widget child;
  const _GlassPanel({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
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
                  Icon(Icons.layers, size: 22, color: primary.withOpacity(0.9)),
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

class _GlassListTile extends StatelessWidget {
  final IconData leading;
  final String title;
  final String? subtitle;
  final String? trailing;
  final bool dense;
  const _GlassListTile({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.dense = false,
  });
  @override
  Widget build(BuildContext context) {
    final textColor = Colors.white.withOpacity(0.9);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 10 : 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
        color: Colors.white.withOpacity(0.04),
      ),
      child: Row(
        children: [
          Icon(leading, color: Colors.white70, size: dense ? 18 : 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: TextStyle(fontSize: 11.5, color: Colors.white70),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
        ],
      ),
    );
  }
}

class _GlassExpander extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _GlassExpander({
    required this.title,
    required this.icon,
    required this.child,
  });
  @override
  State<_GlassExpander> createState() => _GlassExpanderState();
}

class _GlassExpanderState extends State<_GlassExpander>
    with SingleTickerProviderStateMixin {
  bool _open = false;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOut,
  );
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withOpacity(0.06),
                width: 1,
              ),
              color: Colors.white.withOpacity(0.04),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 20, color: Colors.white70),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 350),
                  child: const Icon(Icons.expand_more, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
        ClipRect(
          child: Align(
            heightFactor: _fade.value,
            child: FadeTransition(
              opacity: _fade,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: widget.child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
            color: Colors.white.withOpacity(0.07),
          ),
          child: Icon(icon, size: 22, color: Colors.white.withOpacity(0.9)),
        ),
      ),
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  final String message;
  const _EmptyPrompt({required this.message});
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
            Text(
              message,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportButton extends StatefulWidget {
  final String wplId;
  const _ExportButton({required this.wplId});
  @override
  State<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<_ExportButton> {
  bool _busy = false;
  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.getBytes(
        '/inventory/wpl/export/${widget.wplId}',
      );
      if (res.ok && res.body is Uint8List) {
        final bytes = res.body as Uint8List;
        final dir = await getTemporaryDirectory();
        final name = 'wpl_${widget.wplId}.xlsx';
        final path = '${dir.path}/$name';
        final f = File(path);
        await f.writeAsBytes(bytes, flush: true);
        await OpenFilex.open(path);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Exported $name')));
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${res.error ?? res.statusCode}'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _busy ? null : _export,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download),
      label: const Text('Export Excel'),
      style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }
}

class _ExportAllButton extends StatefulWidget {
  final Future<void> Function() onExport;
  const _ExportAllButton({required this.onExport});
  @override
  State<_ExportAllButton> createState() => _ExportAllButtonState();
}

class _ExportAllButtonState extends State<_ExportAllButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Export all inventory',
      child: _GlassIconButton(
        icon: _busy ? Icons.hourglass_bottom : Icons.download_for_offline,
        tooltip: 'Export all inventory',
        onTap: _busy
            ? () {}
            : () async {
                setState(() => _busy = true);
                try {
                  await widget.onExport();
                } finally {
                  setState(() => _busy = false);
                }
              },
      ),
    );
  }
}
