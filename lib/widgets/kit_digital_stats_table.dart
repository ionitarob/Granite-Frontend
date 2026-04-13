import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../utils/formatters.dart';

class KitDigitalStatsTable extends StatefulWidget {
  const KitDigitalStatsTable({super.key});

  @override
  State<KitDigitalStatsTable> createState() => _KitDigitalStatsTableState();
}

class _KitDigitalStatsTableState extends State<KitDigitalStatsTable> {
  final String _wsUrl = 'ws://10.20.31.10:7000/ws/kd/stats/';
  WebSocketChannel? _channel;
  StreamController<List<Map<String, dynamic>>>? _streamController;
  Timer? _reconnectTimer;

  bool _isConnected = false;
  DateTime? _lastUpdate;
  String? _lastError;

  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    if (_isConnected) return;

    _streamController ??=
        StreamController<List<Map<String, dynamic>>>.broadcast();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      setState(() {
        _isConnected = true;
        _lastError = null;
      });

      _channel!.stream.listen(
        (message) {
          try {
            final parsed = json.decode(message);

            List rawList = [];
            if (parsed is Map && parsed.containsKey('data')) {
              final d = parsed['data'];
              if (d is List) rawList = d;
            } else if (parsed is List) {
              rawList = parsed;
            }

            final stats = rawList
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();

            _lastUpdate = DateTime.now();
            _streamController?.add(stats);

            if (mounted) setState(() {});
          } catch (e) {
            debugPrint('Error parsing WebSocket message: $e');
          }
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _isConnected = false);
          _scheduleReconnect();
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          if (!mounted) return;
          setState(() {
            _isConnected = false;
            _lastError = error.toString();
          });
          _scheduleReconnect();
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnected = false;
        _lastError = e.toString();
      });
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      _connect();
    });
  }

  void _forceReconnect() {
    _reconnectTimer?.cancel();
    try {
      _channel?.sink.close(status.goingAway);
    } catch (_) {}
    _channel = null;
    if (mounted) {
      setState(() {
        _isConnected = false;
        _lastError = null;
      });
    }
    _connect();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close(status.goingAway);
    _streamController?.close();
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  bool _isNumericColumn(String col) {
    final c = col.toLowerCase();
    // Ajusta esto a tus columnas reales
    return c.contains('total') ||
        c.contains('count') ||
        c.contains('qty') ||
        c.contains('importe') ||
        c.contains('amount') ||
        c.contains('€') ||
        c.contains('eur') ||
        c.contains('sum') ||
        c.contains('units');
  }

  String _formatCell(dynamic v) {
    if (v == null) return '-';
    final s = v.toString().trim();
    if (s.isEmpty) return '-';

    // Si parece número, formatea con la extensión centralizada
    final numVal = double.tryParse(s.replaceAll(',', '.'));
    if (numVal != null) {
      final isInt = (numVal - numVal.round()).abs() < 0.000001;
      return isInt ? numVal.formattedInt : numVal.formatted;
    }
    return s;
  }

  List<String> _orderColumns(List<String> cols) {
    // Pon primero columnas importantes si existen
    const preferred = [
      'CustomerName',
      'Customer',
      'Cliente',
      'Project',
      'Proyecto',
      'Total',
      'Total€',
      'Amount',
      'Importe',
    ];

    final out = <String>[];
    for (final p in preferred) {
      if (cols.contains(p)) out.add(p);
    }
    for (final c in cols) {
      if (!out.contains(c)) out.add(c);
    }
    return out;
  }

  String _prettyHeader(String col) {
    // Header más “humano”
    final s = col.replaceAll('_', ' ').trim();
    if (s.isEmpty) return col;
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Surface Apple-like (suave + blur)
    Widget surface({required Widget child}) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withOpacity(0.22)
                  : Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: child,
          ),
        ),
      );
    }

    Widget topBar() {
      final dotColor = _isConnected ? Colors.greenAccent : Colors.orangeAccent;
      final last = _lastUpdate;
      final lastText = last == null
          ? '—'
          : '${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}:${last.second.toString().padLeft(2, '0')}';

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: dotColor.withOpacity(0.35),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _isConnected ? 'En vivo' : 'Reconectando…',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Última actualización: $lastText',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.65),
              ),
            ),
            const Spacer(),
            if (_lastError != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  _lastError!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.redAccent.withOpacity(0.85),
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Reconectar',
              onPressed: _forceReconnect,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _streamController?.stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return surface(
            child: SizedBox(
              height: 220,
              child: Center(child: Text('Error: ${snapshot.error}')),
            ),
          );
        }

        if (!snapshot.hasData) {
          return surface(
            child: SizedBox(
              height: 260,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Conectando a Kit Digital…',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _wsUrl,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        }

        final data = snapshot.data!;
        if (data.isEmpty) {
          return surface(
            child: SizedBox(
              height: 200,
              child: Center(
                child: Text(
                  'No hay datos disponibles.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                  ),
                ),
              ),
            ),
          );
        }

        final rawCols = data.first.keys.toList();
        final columns = _orderColumns(rawCols);

        final divider = BorderSide(
          color: theme.colorScheme.onSurface.withOpacity(0.08),
          width: 1,
        );

        return surface(
          child: Column(
            children: [
              topBar(),
              Divider(height: 1, thickness: 1, color: divider.color),

              // Table area
              Expanded(
                child: Scrollbar(
                  controller: _hScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _hScroll,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 920),
                      child: Scrollbar(
                        controller: _vScroll,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _vScroll,
                          child: DataTable(
                            showCheckboxColumn: false,
                            columnSpacing: 22,
                            horizontalMargin: 16,
                            headingRowHeight: 44,
                            dataRowMinHeight: 44,
                            dataRowMaxHeight: 56,
                            dividerThickness: 0, // quitamos líneas “duras”
                            headingRowColor: WidgetStatePropertyAll(
                              theme.colorScheme.surfaceContainerHighest
                                  .withOpacity(isDark ? 0.35 : 0.65),
                            ),
                            border: TableBorder(
                              horizontalInside: divider, // separadores suaves
                              verticalInside: BorderSide.none,
                            ),
                            columns: columns.map((col) {
                              final numeric = _isNumericColumn(col);
                              return DataColumn(
                                numeric: numeric,
                                label: Text(
                                  _prettyHeader(col).toUpperCase(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.75),
                                  ),
                                ),
                              );
                            }).toList(),
                            rows: List.generate(data.length, (i) {
                              final row = data[i];
                              final isTotalRow = row['CustomerName'] == 'TOTAL';

                              final baseBg = i.isEven
                                  ? Colors.transparent
                                  : theme.colorScheme.onSurface.withOpacity(
                                      isDark ? 0.03 : 0.02,
                                    );

                              final bg = isTotalRow
                                  ? theme.colorScheme.primary.withOpacity(0.10)
                                  : baseBg;

                              final textStyle = isTotalRow
                                  ? theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    )
                                  : theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    );

                              return DataRow(
                                color: WidgetStatePropertyAll(bg),
                                cells: columns.map((col) {
                                  final numeric = _isNumericColumn(col);
                                  final value = _formatCell(row[col]);

                                  return DataCell(
                                    Align(
                                      alignment: numeric
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: Text(
                                        value,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textStyle,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
