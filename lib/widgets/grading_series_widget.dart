import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config.dart';
import 'package:http/http.dart' as http;
import 'package:configtool_granite_frontend/services/api_service.dart';

class GradingSeriesWidget extends StatefulWidget {
  final String apiUrl;
  final int minutes;

  GradingSeriesWidget({Key? key, String? apiUrl, this.minutes = 60}) : apiUrl = apiUrl ?? ('$kBackendBaseUrl/amz/grading/today_series'), super(key: key);

  @override
  State<GradingSeriesWidget> createState() => _GradingSeriesWidgetState();
}

class _GradingSeriesWidgetState extends State<GradingSeriesWidget> {
  List<Map<String, dynamic>> _series = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchSeries();
  }

  Future<void> _fetchSeries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ApiService.instance;
      if (svc != null) {
        final baseUri = Uri.parse(widget.apiUrl);
        final query = Map<String, String>.from(baseUri.queryParameters);
        query['minutes'] = widget.minutes.toString();
        final pathWithQuery = Uri(path: baseUri.path, queryParameters: query).toString();
        final res = await svc.client.get(pathWithQuery);
        if (!mounted) return;
        if (res.ok && res.body is Map) {
          final data = Map<String, dynamic>.from(res.body as Map);
          final items = (data['series'] ?? []) as List;
          setState(() {
            _series = items
                .whereType<Map>()
                .map((e) => {
                      'minute': e['minute'],
                      'count': e['count'],
                    })
                .toList();
            _loading = false;
          });
        } else {
          final msg = res.body ?? res.error ?? 'HTTP ${res.statusCode}';
          setState(() {
            _error = '$msg';
            _loading = false;
          });
        }
        return;
      }

      final uri = Uri.parse(widget.apiUrl).replace(queryParameters: {'minutes': widget.minutes.toString()});
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final List items = (data['series'] ?? []) as List;
        setState(() {
          _series = items.map((e) => {'minute': e['minute'], 'count': e['count']}).toList();
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'HTTP ${res.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return SizedBox(
        width: double.infinity,
        child: Card(
          color: theme.cardColor.withAlpha(31),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Live Grading', style: TextStyle(color: theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ]),
          ),
        ),
      );
    }

    if (_error != null) {
      return SizedBox(
        width: double.infinity,
        child: Card(
          color: theme.cardColor.withAlpha(31),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Live Grading', style: TextStyle(color: theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Error: $_error', style: TextStyle(color: theme.textTheme.bodySmall?.color ?? theme.colorScheme.onSurface)),
            ]),
          ),
        ),
      );
    }

    // convert series to FlSpot. X axis is index (older->left), y is count
    final spots = <FlSpot>[];
    for (var i = 0; i < _series.length; i++) {
      final c = (_series[i]['count'] ?? 0) as num;
      spots.add(FlSpot(i.toDouble(), c.toDouble()));
    }

    final minY = spots.map((s) => s.y).fold<double>(0.0, (p, e) => e < p ? e : p);
    final maxY = spots.isNotEmpty ? spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) : 1.0;

    return SizedBox(
      width: double.infinity,
      height: 240,
      child: Card(
        color: theme.cardColor.withAlpha(31),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Live Grading', style: TextStyle(color: theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Expanded(
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY + (maxY * 0.1),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                    ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          // compute interval as double safely to avoid int->double cast errors
                          interval: (_series.length / 6).clamp(1.0, double.infinity).toDouble(),
                          getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= _series.length) return const SizedBox();
                          final minute = _series[idx]['minute'] as String;
                          // fl_chart v1's SideTitleWidget signature differs across versions; returning a simple Text avoids
                          // incompatibilities and is sufficient for small bottom axis labels.
                          return Text(minute.split(' ').last, style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(show: true),
                  lineBarsData: [
                    LineChartBarData(spots: spots, isCurved: false, color: theme.colorScheme.primary, dotData: FlDotData(show: false)),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
