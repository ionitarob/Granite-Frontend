import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api_client.dart';
import '../../services/api_service.dart';
import '../../services/local_label_generator.dart';
import '../../services/order_input_formatter.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';

class SerialLabelGeneratorScreen extends StatefulWidget {
  const SerialLabelGeneratorScreen({super.key});

  @override
  State<SerialLabelGeneratorScreen> createState() => _SerialLabelGeneratorScreenState();
}

class _SerialLabelGeneratorScreenState extends State<SerialLabelGeneratorScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _orderController = TextEditingController();
  final TextEditingController _skuController = TextEditingController();
  final TextEditingController _unitsController = TextEditingController(text: '100');
  final TextEditingController _startSeqController = TextEditingController(text: '1');

  DateTime _productionDate = DateTime.now();
  bool _operatorsLoading = false;
  bool _typesLoading = false;
  bool _generating = false;
  bool _continueSequence = false;

  String? _operatorsError;
  String? _typesError;
  String? _generationError;

  List<LabelOperatorOption> _operators = const [];
  LabelOperatorOption? _selectedOperator;
  List<LabelTypeOption> _labelTypes = const [];
  LabelTypeOption? _selectedType;

  List<String> _generatedLabels = const [];
  Map<String, dynamic>? _generationSummary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOperators());
  }

  @override
  void dispose() {
    _orderController.dispose();
    _skuController.dispose();
    _unitsController.dispose();
    _startSeqController.dispose();
    super.dispose();
  }

  ApiClient? _clientOrNull() {
    final svc = ApiService.instance;
    if (svc != null) return svc.client;
    try {
      return Provider.of<ApiService>(context, listen: false).client;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadOperators() async {
    final client = _clientOrNull();
    if (client == null) {
      setState(() {
        _operatorsLoading = false;
        _operatorsError = 'Servicio API no disponible';
      });
      return;
    }
    setState(() {
      _operatorsLoading = true;
      _operatorsError = null;
    });
    try {
  final res = await client.get('/serials/labels/operators');
      if (!mounted) return;
      if (res.ok) {
        final rawList = _extractList(res.body);
        final parsed = rawList
            .whereType<Map>()
            .map(LabelOperatorOption.fromJson)
            .where((op) => op.name.isNotEmpty)
            .toList();
        setState(() {
          _operators = parsed;
          if (parsed.isEmpty) {
            _selectedOperator = null;
            _labelTypes = const [];
            _selectedType = null;
          } else {
            LabelOperatorOption? next;
            if (_selectedOperator != null) {
              for (final op in parsed) {
                if (op.name.toLowerCase() == _selectedOperator!.name.toLowerCase()) {
                  next = op;
                  break;
                }
              }
            }
            _selectedOperator = next ?? parsed.first;
          }
        });
        if (_selectedOperator != null) {
          await _loadTypesForOperator(_selectedOperator!);
        }
      } else {
        setState(() => _operatorsError = 'No se pudieron cargar los operadores (${res.statusCode}).');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _operatorsError = 'Error cargando operadores: $e');
      }
    } finally {
      if (mounted) setState(() => _operatorsLoading = false);
    }
  }

  Future<void> _loadTypesForOperator(LabelOperatorOption operatorOption) async {
    final client = _clientOrNull();
    if (client == null) {
      setState(() {
        _typesLoading = false;
        _typesError = 'Servicio API no disponible';
        _labelTypes = const [];
        _selectedType = null;
      });
      return;
    }
    setState(() {
      _typesLoading = true;
      _typesError = null;
      _labelTypes = const [];
      _selectedType = null;
    });
    try {
      final encoded = Uri.encodeQueryComponent(operatorOption.name);
  final res = await client.get('/serials/labels/types?operador=$encoded');
      if (!mounted) return;
      if (res.ok) {
        final rawList = _extractList(res.body);
        final parsed = rawList
            .whereType<Map>()
            .map(LabelTypeOption.fromJson)
            .where((e) => e.id != null)
            .toList();
        setState(() {
          _labelTypes = parsed;
          if (parsed.isNotEmpty) {
            _selectedType = parsed.first;
            _normalizeUnits();
          }
        });
      } else {
        setState(() => _typesError = 'No se pudo cargar la lista (${res.statusCode}).');
      }
    } catch (e) {
      if (mounted) setState(() => _typesError = 'Error obteniendo tipos: $e');
    } finally {
      if (mounted) setState(() => _typesLoading = false);
    }
  }

  List<dynamic> _extractList(dynamic body) {
    if (body is List) return body;
    if (body is Map && body['results'] is List) return body['results'] as List;
    return const [];
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _productionDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
      locale: const Locale('es'),
    );
    if (picked != null) {
      setState(() => _productionDate = picked);
    }
  }

  void _normalizeUnits() {
    if (_selectedType == null) return;
    final min = _selectedType!.minUnits;
    final max = _selectedType!.maxUnits ?? LabelTypeOption.defaultMaxUnits;
    final current = int.tryParse(_unitsController.text.trim());
    final normalized = (current ?? min).clamp(min, max);
    _unitsController.text = normalized.toString();
  }

  Future<void> _generateLabels() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedOperator == null || _selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona operador y tipo.')));
      return;
    }
    final units = int.tryParse(_unitsController.text.trim()) ?? 0;
    final minUnits = _selectedType!.minUnits;
    final maxUnits = _selectedType!.maxUnits ?? LabelTypeOption.defaultMaxUnits;
    if (units < minUnits || units > maxUnits) {
      setState(() => _generationError = 'Unidades fuera de rango ($minUnits - $maxUnits).');
      return;
    }
    int? startSeq;
    if (_continueSequence) {
      final parsed = int.tryParse(_startSeqController.text.trim());
      if (parsed == null || parsed <= 0) {
        setState(() => _generationError = 'Introduce un inicio de secuencia válido.');
        return;
      }
      startSeq = parsed;
    }

    // Normalize SKU to uppercase and confirm if it doesn't match expected pattern (XXYYYY)
    final rawSku = _skuController.text.trim();
    final normalizedSku = rawSku.toUpperCase();
    _skuController.text = normalizedSku;
    // Expected: 2 digits followed by 4 letters (e.g. 12ABCD)
    final bool skuIsOk = (() {
      if (normalizedSku.length != 6) return false;
      int d0 = normalizedSku.codeUnitAt(0);
      int d1 = normalizedSku.codeUnitAt(1);
      if (d0 < 48 || d0 > 57) return false; // not digit
      if (d1 < 48 || d1 > 57) return false;
      for (int i = 2; i < 6; i++) {
        final c = normalizedSku.codeUnitAt(i);
        if (c < 65 || c > 90) return false; // not uppercase letter
      }
      return true;
    })();
    if (!skuIsOk) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('SKU no estándar'),
          content: Text('El SKU "$normalizedSku" no cumple el formato XXYYYY. ¿Deseas continuar de todos modos?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Continuar')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() {
      _generationError = null;
      _generating = true;
      _generatedLabels = const [];
      _generationSummary = null;
    });

    try {
      final start = startSeq ?? 1;
      final labels = await Future<List<String>>(
        () => LocalLabelGenerator.generate(
          operatorName: _selectedOperator!.name,
          productionDate: _productionDate,
          totalUnits: units,
          article: _selectedType!.article,
          sapClient: _selectedType!.sapClient,
          codeLetter: _selectedType!.codeLetter,
          startSequence: start,
        ),
      );
      if (!mounted) return;
      setState(() {
        _generatedLabels = labels;
        _generationSummary = {
          'operador': _selectedOperator!.name,
          'tipo': {
            'articulo': _selectedType!.article,
            'codigo': _selectedType!.codeLetter,
            'sap': _selectedType!.sapClient,
          },
          'fecha_us': DateFormat('MM/dd/yyyy').format(_productionDate),
          'count': labels.length,
          'secuencia': {
            'inicio': start,
            'fin': start + labels.length - 1,
          },
        };
      });
      // Fire-and-forget audit call to backend to record the generation request.
      try {
        final client = _clientOrNull();
        if (client != null) {
          final auditPayload = <String, dynamic>{
            'operador': _selectedOperator!.name,
            'tipo_id': _selectedType!.id,
            'nr_unidades': units,
            'fecha': DateFormat('yyyy-MM-dd').format(_productionDate),
            'inicio': start,
            'nr_orden': _orderController.text.trim(),
            'nr_sku': _skuController.text.trim(),
            'allow_inactive': false,
          };
          // Send but don't await long — await to capture errors but don't use response to replace labels
          final res = await client.post('/serials/labels/generate', jsonBody: auditPayload);
          if (res.ok && res.body is Map) {
            final map = Map<String, dynamic>.from(res.body as Map);
            // merge backend info into summary for debugging (non-destructive)
            if (mounted) {
              setState(() {
                _generationSummary = {...?_generationSummary, 'backend': map};
              });
            }
          }
        }
      } catch (_) {
        // ignore audit errors — client labels are authoritative
      }
    } catch (e) {
      if (mounted) setState(() => _generationError = 'Error generando etiquetas: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _copyLabels() async {
    if (_generatedLabels.isEmpty) return;
    final buffer = StringBuffer();
    for (final label in _generatedLabels) {
      buffer.writeln(label);
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Etiquetas copiadas al portapapeles.')));
  }

  String _formatDisplayDate(DateTime value) {
    return DateFormat('dd MMM yyyy', 'es').format(value);
  }

  Widget _buildGlassContainer(Widget child) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: theme.cardColor.withValues(alpha: .85),
            border: Border.all(color: Colors.white.withValues(alpha: .2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .12),
                blurRadius: 26,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildOperatorSelector() {
    if (_operatorsLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
    }
    if (_operatorsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_operatorsError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: _loadOperators, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ],
      );
    }
    if (_operators.isEmpty) {
      return const Text('No hay operadores disponibles.');
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _operators
          .map(
            (op) => ChoiceChip(
              label: SizedBox(
                width: 160,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(op.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${op.activeTypes}/${op.totalTypes} activos', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              selected: _selectedOperator?.name == op.name,
              onSelected: (selected) {
                if (!selected) return;
                setState(() {
                  _selectedOperator = op;
                });
                _loadTypesForOperator(op);
              },
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          )
          .toList(),
    );
  }

  Widget _buildTypeSelector() {
    if (_selectedOperator == null) {
      return const Text('Selecciona un operador primero.');
    }
    if (_typesLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
    }
    if (_typesError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_typesError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: () => _loadTypesForOperator(_selectedOperator!), icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ],
      );
    }
    if (_labelTypes.isEmpty) {
      return const Text('No hay tipos activos para este operador.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _labelTypes.length,
      separatorBuilder: (_, __) => const Divider(height: 1, thickness: .4),
      itemBuilder: (_, index) {
        final item = _labelTypes[index];
        final selected = _selectedType?.id == item.id;
        final min = item.minUnits;
        final max = item.maxUnits ?? LabelTypeOption.defaultMaxUnits;
        final subtitle = [
          if ((item.article ?? '').isNotEmpty) 'Artículo: ${item.article}',
          if ((item.sapClient ?? '').isNotEmpty) 'SAP: ${item.sapClient}',
          'Rango unidades: $min - $max',
        ].join(' • ');
        return ListTile(
          leading: Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).iconTheme.color,
          ),
          title: Text(item.displayName, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          subtitle: Text(subtitle),
          trailing: item.codeLetter == null || item.codeLetter!.isEmpty
              ? null
              : Chip(label: Text(item.codeLetter!)),
          onTap: () {
            setState(() => _selectedType = item);
            _normalizeUnits();
          },
        );
      },
    );
  }

  Widget _buildFormSection(double fieldWidth) {
    final theme = Theme.of(context);
    final min = _selectedType?.minUnits ?? 1;
    final max = _selectedType?.maxUnits ?? LabelTypeOption.defaultMaxUnits;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 20,
            children: [
              SizedBox(
                width: fieldWidth,
                child: TextFormField(
                  controller: _orderController,
                  decoration: _inputDecoration('Nr. de orden', Icons.receipt_long),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')), OrderInputFormatter()],
                  validator: (value) {
                    final v = value?.trim().toUpperCase() ?? '';
                    final pattern = RegExp(r'^[A-Z0-9]{2}-[A-Z0-9]{5}-[A-Z0-9]{2}$');
                    if (v.isEmpty) return 'Introduce el número de orden';
                    if (!pattern.hasMatch(v)) return 'Formato requerido: XX-XXXXX-XX';
                    return null;
                  },
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: TextFormField(
                  controller: _skuController,
                  decoration: _inputDecoration('Nr. SKU', Icons.qr_code),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Introduce el SKU' : null,
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: TextFormField(
                  controller: _unitsController,
                  decoration: _inputDecoration('Nr. unidades', Icons.onetwothree).copyWith(helperText: 'Mínimo $min • Máximo $max'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    final parsed = int.tryParse(value ?? '');
                    if (parsed == null) return 'Introduce un número válido';
                    if (parsed < min) return 'Debe ser >= $min';
                    if (parsed > max) return 'Debe ser <= $max';
                    return null;
                  },
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(18),
                  child: InputDecorator(
                    decoration: _inputDecoration('Fecha de producción', Icons.event),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDisplayDate(_productionDate), style: theme.textTheme.bodyLarge),
                        const Icon(Icons.edit_calendar),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Continuar secuencia'),
            subtitle: const Text('Define el inicio manualmente para enlazar lotes previos.'),
            value: _continueSequence,
            onChanged: (value) => setState(() => _continueSequence = value),
          ),
          if (_continueSequence)
            SizedBox(
              width: fieldWidth,
              child: TextFormField(
                controller: _startSeqController,
                decoration: _inputDecoration('Inicio secuencia', Icons.format_list_numbered),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (!_continueSequence) return null;
                  final parsed = int.tryParse(value ?? '');
                  if (parsed == null || parsed <= 0) return 'Usa un número positivo';
                  return null;
                },
              ),
            ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _generating
                    ? null
                    : () {
                        _formKey.currentState?.reset();
                        _orderController.clear();
                        _skuController.clear();
                        _unitsController.text = (_selectedType?.minUnits ?? 1).toString();
                        setState(() {
                          _continueSequence = false;
                          _startSeqController.text = '1';
                          _generationError = null;
                          _generatedLabels = const [];
                          _generationSummary = null;
                        });
                      },
                icon: const Icon(Icons.clear_all),
                label: const Text('Limpiar'),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: _generating ? null : _generateLabels,
                icon: _generating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
                    : const Icon(Icons.print),
                label: Text(_generating ? 'Generando...' : 'Generar etiquetas'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
              ),
            ],
          ),
          if (_generationError != null) ...[
            const SizedBox(height: 12),
            Text(_generationError!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: colorScheme.primary),
      filled: true,
      fillColor: Colors.white.withValues(alpha: .92),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .25)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
      ),
    );
  }

  Widget _buildResultsCard() {
    if (_generatedLabels.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: .3)),
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .25),
        ),
        child: const Text('Cuando generes etiquetas, aparecerán aquí.'),
      );
    }
    final summary = _generationSummary ?? const {};
    final meta = <Widget>[
      _SummaryChip(label: 'Operador', value: summary['operador']?.toString() ?? _selectedOperator?.name ?? '—'),
      _SummaryChip(label: 'Artículo', value: summary['tipo']?['articulo']?.toString() ?? _selectedType?.article ?? '—'),
      _SummaryChip(label: 'Fecha', value: summary['fecha_us']?.toString() ?? DateFormat('MM/dd/yyyy').format(_productionDate)),
      _SummaryChip(label: 'Total', value: (summary['count'] ?? _generatedLabels.length).toString()),
    ];
    final seq = summary['secuencia'];
    if (seq is Map) {
      final inicio = seq['inicio'];
      final fin = seq['fin'];
      if (inicio != null && fin != null) {
        meta.add(_SummaryChip(label: 'Secuencia', value: '$inicio → $fin'));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Resultado (${_generatedLabels.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(onPressed: _copyLabels, tooltip: 'Copiar todo', icon: const Icon(Icons.copy_all)),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: meta),
        const SizedBox(height: 16),
        Container(
          constraints: const BoxConstraints(maxHeight: 320),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .5)),
            color: Colors.black.withValues(alpha: .06),
          ),
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              itemCount: _generatedLabels.length,
              separatorBuilder: (_, __) => const Divider(height: 1, thickness: .2),
              itemBuilder: (_, index) {
                final label = _generatedLabels[index];
                return ListTile(
                  dense: true,
                  title: Text(label, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                  leading: Text('#${index + 1}'.padLeft(3)),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: label));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Etiqueta ${index + 1} copiada.')));
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Generador de etiquetas'),
        centerTitle: true,
        backgroundColor: Colors.black.withValues(alpha: .15),
        elevation: 0,
      ),
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 1.2),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: EdgeNavHandle(
                  width: 28,
                  user: ApiService.instance?.currentUser,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1024),
                  child: _buildGlassContainer(
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final fieldWidth = constraints.maxWidth > 640 ? (constraints.maxWidth - 48) / 2 : constraints.maxWidth;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Generar etiquetas de operador', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text('Selecciona operador, tipo de etiqueta y define los parámetros de producción.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: .7))),
                            const SizedBox(height: 28),
                            Text('1. Selecciona operador', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 12),
                            _buildOperatorSelector(),
                            const SizedBox(height: 28),
                            Text('2. Tipo de etiqueta', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 12),
                            _buildTypeSelector(),
                            const SizedBox(height: 28),
                            Text('3. Datos del lote', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 12),
                            _buildFormSection(fieldWidth),
                            const SizedBox(height: 32),
                            _buildResultsCard(),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LabelOperatorOption {
  const LabelOperatorOption({required this.name, required this.totalTypes, required this.activeTypes});

  final String name;
  final int totalTypes;
  final int activeTypes;

  factory LabelOperatorOption.fromJson(Map<dynamic, dynamic> map) {
    final operador = (map['operador'] ?? map['name'] ?? '').toString();
    int parseInt(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
    final total = parseInt(map['tipos'] ?? map['total'] ?? map['total_types']);
    final activos = parseInt(map['activos'] ?? map['active'] ?? map['active_types']);
    return LabelOperatorOption(name: operador, totalTypes: total == 0 ? activos : total, activeTypes: activos == 0 ? total : activos);
  }
}

class LabelTypeOption {
  static const int defaultMaxUnits = 5000;

  const LabelTypeOption({
    required this.id,
    required this.operatorName,
    required this.article,
    required this.sapClient,
    required this.codeLetter,
    required this.active,
    required this.minUnits,
    required this.maxUnits,
  });

  final int? id;
  final String operatorName;
  final String? article;
  final String? sapClient;
  final String? codeLetter;
  final bool active;
  final int minUnits;
  final int? maxUnits;

  String get displayName => (article?.isNotEmpty ?? false) ? article! : (codeLetter?.isNotEmpty ?? false) ? codeLetter! : 'Tipo ${id ?? ''}';

  factory LabelTypeOption.fromJson(Map<dynamic, dynamic> map) {
    int? parseInt(dynamic value) => value == null ? null : int.tryParse(value.toString());
    bool parseBool(dynamic value) {
      if (value is bool) return value;
      final text = value?.toString().toLowerCase();
      return text == '1' || text == 'true' || text == 'yes';
    }

    final min = parseInt(map['min_unidades'] ?? map['minUnits'] ?? map['min_units'] ?? map['minimo']) ?? 1;
    final max = parseInt(map['max_unidades'] ?? map['maxUnits'] ?? map['max_units'] ?? map['maximo']);
    return LabelTypeOption(
      id: parseInt(map['id']),
      operatorName: (map['operador'] ?? '').toString(),
      article: map['articulo']?.toString(),
      sapClient: map['sap_cliente']?.toString(),
      codeLetter: map['codigo_letra']?.toString(),
      active: parseBool(map['activo']),
      minUnits: min <= 0 ? 1 : min,
      maxUnits: (max != null && max > 0) ? max : null,
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.secondaryContainer.withValues(alpha: .6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer.withValues(alpha: .7))),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
