import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../themes/amazon_theme.dart';
import '../../widgets/animated_background.dart';

class AmzFindDsnScreen extends StatefulWidget {
  const AmzFindDsnScreen({super.key});

  @override
  State<AmzFindDsnScreen> createState() => _AmzFindDsnScreenState();
}

class _AmzFindDsnScreenState extends State<AmzFindDsnScreen> {
  final TextEditingController _dsnController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;
  final List<String> _recentQueries = [];

  @override
  void dispose() {
    _dsnController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _search({String? preset}) async {
    final query = (preset ?? _dsnController.text).trim().toUpperCase();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post(
        '/amz/search',
        jsonBody: {'dsn_scan': query},
      );

      if (!mounted) return;

      if (res.ok && res.body is Map<String, dynamic>) {
        setState(() {
          _result = res.body as Map<String, dynamic>;
          _addToHistory(query);
          _dsnController.text = query;
        });
      } else {
        setState(() {
          _error = res.error ?? 'DSN no encontrado';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error de red: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        FocusScope.of(context).requestFocus(_inputFocus);
      }
    }
  }

  void _addToHistory(String value) {
    if (value.isEmpty) return;
    setState(() {
      _recentQueries.remove(value);
      _recentQueries.insert(0, value);
      if (_recentQueries.length > 5) _recentQueries.removeLast();
    });
  }

  Widget _buildResultSection(_ResultSectionConfig section, dynamic data) {
    final records = _extractRows(data);
    if (records.isEmpty) return const SizedBox.shrink();

    final header = '${section.title} Records';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _iconForSection(section.title),
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                header,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: records
                .map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildRecordCard(row, section.tableName),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> row, String tableName) {
    final dsnLabel = _primaryLabel(row);
    final bucketLabel = _bucketLine(row);
    final additionalLine = _secondaryLine(row);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.black87,
        border: Border.all(color: Colors.white24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            offset: const Offset(0, 6),
            blurRadius: 14,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$dsnLabel → $bucketLabel',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                onPressed: _loading
                    ? null
                    : () => _deleteRecord(row, tableName),
                tooltip: 'Eliminar registro',
              ),
            ],
          ),
          if (additionalLine.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              additionalLine,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  String _secondaryLine(Map<String, dynamic> row) {
    final fields = [
      _DisplayField(
        label: 'UPC',
        keys: const ['UPC_Scan', 'upc_scan', 'UPC', 'upc'],
      ),
      _DisplayField(label: 'ASIN', keys: const ['ASIN', 'asin']),
      _DisplayField(
        label: 'FC_Origin',
        keys: const ['FC_Origin', 'fc_origin', 'FC', 'fc'],
      ),
      _DisplayField(
        label: 'Box ID',
        keys: const ['box_id', 'boxId', 'box_id_fk', 'box', 'box_name'],
      ),
      _DisplayField(
        label: 'Username',
        keys: const ['username', 'user', 'usuario'],
      ),
    ];

    final entries = <String>[];
    for (final field in fields) {
      dynamic value;
      for (final key in field.keys) {
        value = _valueFromRow(row, key);
        if (_hasValue(value)) break;
      }
      if (_hasValue(value)) {
        entries.add('${field.label}: ${value.toString()}');
      }
    }

    return entries.join(' · ');
  }

  String _bucketLine(Map<String, dynamic> row) {
    final bucket =
        _valueFromRow(row, 'Grading_Bucket') ??
        _valueFromRow(row, 'grading_bucket') ??
        _valueFromRow(row, 'gradingBucket') ??
        _valueFromRow(row, 'bucket');
    if (_hasValue(bucket)) return bucket.toString();
    return 'Sin bucket';
  }

  Future<void> _deleteRecord(Map<String, dynamic> row, String tableName) async {
    final id = row['id'] ?? row['ID'] ?? row['registro_id'] ?? row['registro'];
    if (!_hasValue(id)) {
      _showSnackbar('No se encontró el ID del registro');
      return;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Eliminar registro'),
            content: Text('¿Eliminar $id del historial de grading?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final payload = {'table': tableName, 'id': id};
      if (!_hasServerAuth(api)) {
        final username = _resolveCurrentUser(api);
        if (username != null && username.isNotEmpty) {
          payload['username'] = username;
        }
      }
      final res = await api.client.post(
        '/amz/search/delete_record',
        jsonBody: payload,
      );

      if (!mounted) return;

      if (res.ok && res.body is Map<String, dynamic>) {
        final body = res.body as Map<String, dynamic>;
        final success = body['success'] == true;
        if (success) {
          _removeRowLocally(tableName, id);
          _showSnackbar('Registro eliminado');
        } else {
          _showSnackbar(body['message']?.toString() ?? 'No se pudo borrar');
        }
      } else {
        _showSnackbar(res.error ?? 'No se pudo borrar el registro');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackbar('Error al eliminar: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  bool _hasServerAuth(ApiService api) {
    return api.client.hasAccessToken || api.client.hasSessionCookie;
  }

  String? _resolveCurrentUser(ApiService api) {
    final user = api.currentUser;
    if (user == null) return null;
    final username = user.username.trim();
    if (username.isNotEmpty) return username;
    final display = user.displayName().trim();
    return display.isNotEmpty ? display : null;
  }

  List<Map<String, dynamic>> _extractRows(dynamic data) {
    final rows = <Map<String, dynamic>>[];
    if (data is Map<String, dynamic>) {
      rows.add(data);
    } else if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) rows.add(item);
      }
    }
    return rows;
  }

  void _removeRowLocally(String tableName, dynamic id) {
    if (_result == null) return;
    final keys = <String>[];
    if (tableName == 'amzgrading') {
      keys.addAll(['results1', 'amzgrading']);
    } else if (tableName == 'amzgradingbox') {
      keys.addAll(['results2', 'amzgradingbox']);
    }
    if (keys.isEmpty) return;

    final updated = Map<String, dynamic>.from(_result!);
    for (final key in keys) {
      final data = updated[key];
      if (data is List) {
        updated[key] = data.where((row) {
          if (row is Map<String, dynamic>) {
            final rowId = row['id'] ?? row['ID'] ?? row['registro_id'];
            return rowId?.toString() != id.toString();
          }
          return true;
        }).toList();
      }
    }

    setState(() {
      _result = updated;
    });
  }

  String _primaryLabel(Map<String, dynamic> row) {
    const prioritizedKeys = ['dsn', 'DSN', 'DSN_Scan', 'dsn_scan', 'dsnScan'];
    for (final key in prioritizedKeys) {
      final value = _valueFromRow(row, key);
      if (_hasValue(value)) return value.toString();
    }

    final status = _valueFromRow(row, 'status') ?? _valueFromRow(row, 'estado');
    if (_hasValue(status)) {
      final fallback = row.entries
          .firstWhere(
            (entry) => _hasValue(entry.value),
            orElse: () => const MapEntry('registro', 'Registro'),
          )
          .value;
      return '$fallback → $status';
    }

    return row.entries
        .map((entry) => entry.value?.toString() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => 'Registro');
  }

  bool _hasValue(dynamic value) {
    if (value == null) return false;
    final text = value.toString().trim();
    return text.isNotEmpty && text.toLowerCase() != 'null';
  }

  dynamic _valueFromRow(Map<String, dynamic> row, String key) {
    if (row.containsKey(key)) return row[key];
    if (row.containsKey(key.toUpperCase())) return row[key.toUpperCase()];
    if (row.containsKey(key.toLowerCase())) return row[key.toLowerCase()];
    final normalizedKey = key.toLowerCase();
    for (final entry in row.entries) {
      if (entry.key.toLowerCase() == normalizedKey) return entry.value;
    }
    return null;
  }

  IconData _iconForSection(String title) {
    if (title.toLowerCase().contains('grading')) {
      return Icons.emoji_events_outlined;
    }
    if (title.toLowerCase().contains('sorting')) {
      return Icons.layers_outlined;
    }
    return Icons.folder_open;
  }

  List<Widget> _buildResultWidgets() {
    if (_result == null) return const [];
    final sections = [
      _ResultSectionConfig(
        title: 'Grading',
        subtitle: 'Registro principal',
        tableName: 'amzgrading',
        keys: const ['results1', 'amzgrading'],
      ),
      _ResultSectionConfig(
        title: 'Sorting',
        subtitle: 'Registro de cajas',
        tableName: 'amzgradingbox',
        keys: const ['results2', 'amzgradingbox'],
      ),
    ];
    final widgets = <Widget>[];
    for (final section in sections) {
      final data = section.keys
          .map((key) => _result![key])
          .firstWhere((element) => element != null, orElse: () => null);
      if (data == null) continue;
      widgets.add(_buildResultSection(section, data));
    }
    return widgets;
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AmazonTheme(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Buscar DSN'),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        extendBodyBehindAppBar: true,
        body: SelectionArea(
          child: Stack(
            children: [
              const AnimatedBackgroundWidget(intensity: 0.6),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 8,
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      TextFormField(
                                        controller: _dsnController,
                                        focusNode: _inputFocus,
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        decoration: InputDecoration(
                                          labelText: 'DSN',
                                          prefixIcon: Icon(
                                            Icons.qr_code,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                        onFieldSubmitted: (_) => _search(),
                                      ),
                                      const SizedBox(height: 16),
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                        ),
                                        icon: _loading
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(Icons.search),
                                        onPressed: _loading
                                            ? null
                                            : () => _search(),
                                        label: Align(
                                          alignment: Alignment.center,
                                          child: Text(
                                            _loading
                                                ? 'Buscando...'
                                                : 'Buscar DSN',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_recentQueries.isNotEmpty)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _recentQueries
                                      .map(
                                        (value) => ActionChip(
                                          label: Text(value),
                                          avatar: const Icon(
                                            Icons.history,
                                            size: 18,
                                          ),
                                          onPressed: () =>
                                              _search(preset: value),
                                        ),
                                      )
                                      .toList(),
                                ),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: colorScheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 16),
                              if (_result != null) ..._buildResultWidgets(),
                              SizedBox(height: constraints.maxHeight * 0.08),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@immutable
class _ResultSectionConfig {
  const _ResultSectionConfig({
    required this.title,
    required this.subtitle,
    required this.tableName,
    required this.keys,
  });

  final String title;
  final String subtitle;
  final String tableName;
  final List<String> keys;
}

class _DisplayField {
  const _DisplayField({required this.label, required this.keys});

  final String label;
  final List<String> keys;
}
