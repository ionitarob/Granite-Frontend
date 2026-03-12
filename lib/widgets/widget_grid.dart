import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A simple responsive widget grid with drag-and-drop and persistent layout.
///
/// Usage: pass a map of available widgets keyed by id, and a username to store layout per-user.
class WidgetGrid extends StatefulWidget {
  final Map<String, Widget> availableWidgets;
  final String storageKey; // unique per-user, e.g. 'widget_layout_<username>'
  final Map<String, int>?
  spanColumns; // optional: widgetId -> number of columns to span

  const WidgetGrid({
    super.key,
    required this.availableWidgets,
    required this.storageKey,
    this.spanColumns,
  });

  @override
  State<WidgetGrid> createState() => _WidgetGridState();
}

class _WidgetGridState extends State<WidgetGrid> {
  late List<String?> _layout; // index -> widgetId or null

  @override
  void initState() {
    super.initState();
    _layout = [];
    _loadLayout();
  }

  @override
  void didUpdateWidget(WidgetGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storageKey != widget.storageKey) {
      _loadLayout();
    }
  }

  Future<void> _loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(widget.storageKey);
    if (raw != null) {
      try {
        final List parsed = json.decode(raw) as List;
        setState(() => _layout = parsed.map((e) => e?.toString()).toList());
        return;
      } catch (_) {
        // ignore and fall through to default
      }
    }

    // default layout: place available widgets in first slots
    setState(() {
      _layout = widget.availableWidgets.keys.map((k) => k).toList();
    });
    await _saveLayout();
  }

  Future<void> _saveLayout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(widget.storageKey, json.encode(_layout));
  }

  void _ensureSlots(int count) {
    if (_layout.length < count) {
      _layout.addAll(List<String?>.filled(count - _layout.length, null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // responsive columns based on width
    int columns;
    if (width < 600) {
      columns = 1;
    } else if (width < 900)
      columns = 2;
    else if (width < 1200)
      columns = 3;
    else
      columns = 4;

    // ensure some extra slots so user can place more widgets
    final minSlots = columns * 2; // two rows available
    _ensureSlots(minSlots);

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
        final children = <Widget>[];
        int i = 0;
        while (i < _layout.length) {
          final widgetId = _layout[i];
          final span = widget.spanColumns?[widgetId] ?? 1;
          if (widgetId != null &&
              widget.availableWidgets.containsKey(widgetId) &&
              span > 1) {
            // make spanning item width
            final widthSpan = itemWidth * span + (span - 1) * 12;
            children.add(
              _buildDraggableItem(i, widgetId, widthSpan, span: span),
            );
            i += 1;
          } else if (widgetId != null &&
              widget.availableWidgets.containsKey(widgetId)) {
            children.add(_buildDraggableItem(i, widgetId, itemWidth));
            i += 1;
          } else {
            children.add(_buildEmptySlot(i, itemWidth));
            i += 1;
          }
        }
        return Wrap(spacing: 12, runSpacing: 12, children: children);
      },
    );
  }

  Widget _buildDraggableItem(
    int index,
    String widgetId,
    double width, {
    int span = 1,
  }) {
    final w = widget.availableWidgets[widgetId]!;
    return SizedBox(
      width: width,
      child: LongPressDraggable<String>(
        data: widgetId,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: width,
            child: Opacity(opacity: 0.95, child: w),
          ),
        ),
        childWhenDragging: Container(
          height: 90,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withAlpha(15)),
          ),
          child: const Center(child: Text('Moving...')),
        ),
        child: DragTarget<String>(
          onWillAcceptWithDetails: (details) => details.data != widgetId,
          onAcceptWithDetails: (details) =>
              _moveWidget(details.data, index, span: span),
          builder: (context, candidate, rejected) => w,
        ),
      ),
    );
  }

  Widget _buildEmptySlot(int index, double width) {
    return SizedBox(
      width: width,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) => _moveWidget(details.data, index),
        builder: (context, candidate, rejected) => Container(
          height: 90,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withAlpha(15)),
          ),
          child: Center(
            child: candidate.isNotEmpty
                ? const Text('Release to place')
                : const Text(
                    'Empty slot',
                    style: TextStyle(color: Colors.white70),
                  ),
          ),
        ),
      ),
    );
  }

  // Move widget into the target index; if span>1, reserve additional slots (may overwrite other widgets)
  void _moveWidget(String widgetId, int toIndex, {int span = 1}) {
    setState(() {
      // clear previous occurrence
      final from = _layout.indexWhere((id) => id == widgetId);
      if (from != -1) _layout[from] = null;
      _ensureSlots(toIndex + span);
      // clear target range
      for (int k = toIndex; k < toIndex + span; k++) {
        if (k < _layout.length) _layout[k] = null;
      }
      // place widget at start
      _layout[toIndex] = widgetId;
    });
    _saveLayout();
  }
}
