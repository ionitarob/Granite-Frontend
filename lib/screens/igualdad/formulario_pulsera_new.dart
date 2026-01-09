import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'form_palette.dart';

class FormularioPulseraNew extends StatefulWidget {
  final TextEditingController imeiController;
  final TextEditingController bateriaController;
  final Map<String, dynamic>? opcionesRegistro;
  final String? tipoRegistroSeleccionado;
  final String? registroSeleccionado;
  final Map<String, String?> radioValues;
  final void Function(String tipo, String id) onChangeRegistro;
  final void Function(String key, String? value) onChangeRadio;
  final VoidCallback onRegistrar;
  final bool isSubmitting;
  final bool isLookupInProgress;
  final Map<String, dynamic>? lookupResult;
  final String? lookupError;
  final String? lookupImeiSearched;

  const FormularioPulseraNew({
    super.key,
    required this.imeiController,
    required this.bateriaController,
    required this.opcionesRegistro,
    required this.tipoRegistroSeleccionado,
    required this.registroSeleccionado,
    required this.radioValues,
    required this.onChangeRegistro,
    required this.onChangeRadio,
    required this.onRegistrar,
    this.isSubmitting = false,
    this.isLookupInProgress = false,
    this.lookupResult,
    this.lookupError,
    this.lookupImeiSearched,
  });

  @override
  State<FormularioPulseraNew> createState() => _FormularioPulseraNewState();
}

class _FormularioPulseraNewState extends State<FormularioPulseraNew> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late Map<String, String?> _answers;

  @override
  void initState() {
    super.initState();
    _answers = Map<String, String?>.from(widget.radioValues);
  }

  @override
  void didUpdateWidget(covariant FormularioPulseraNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.radioValues, widget.radioValues)) {
      _answers = Map<String, String?>.from(widget.radioValues);
    }
  }

  void _handleSubmit() {
    final form = _formKey.currentState;
    if (form == null) return;
    if (form.validate()) {
      widget.onRegistrar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = FormPalette.fromTheme(theme);

    final inspectionItems = <_InspectionItem>[
      const _InspectionItem('danos_fisicos', '¿Daños físicos?'),
      const _InspectionItem('empareja_pulsera_boton', '¿Empareja pulsera/botón?'),
      const _InspectionItem('sin_alertas', '¿Sin alertas?'),
      const _InspectionItem('chequeo_abierta', '¿Chequeo abierta?'),
      const _InspectionItem('serigrafia', '¿Serigrafía?'),
      const _InspectionItem('tornilleria', '¿Tornillería?'),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [palette.panelGradientStart, palette.panelGradientEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: palette.panelBorder),
            boxShadow: [
              BoxShadow(
                color: palette.panelShadow,
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 36),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SectionHeader(
                    title: 'Datos de la pulsera',
                    subtitle: 'Completa la información básica antes de inspeccionar.',
                    titleColor: palette.textPrimary,
                    subtitleColor: palette.textMuted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Introduce el IMEI y el nivel de batería. Recuerda verificar que los datos coinciden con la pulsera entregada.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 640;
                      final imeiField = TextFormField(
                        controller: widget.imeiController,
                        decoration: _inputDecoration(
                          theme,
                          palette,
                          'IMEI de la pulsera',
                          Icons.confirmation_number_outlined,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Introduce el IMEI';
                          }
                          return null;
                        },
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.textPrimary,
                        ),
                        cursorColor: palette.textPrimary,
                      );
                      final bateriaField = TextFormField(
                        controller: widget.bateriaController,
                        decoration: _inputDecoration(
                          theme,
                          palette,
                          '% batería',
                          Icons.battery_charging_full,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final parsed = int.tryParse(value);
                          if (parsed == null || parsed < 0 || parsed > 100) {
                            return '0 a 100';
                          }
                          return null;
                        },
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.textPrimary,
                        ),
                        cursorColor: palette.textPrimary,
                      );

                      if (isWide) {
                        return Row(
                          children: [
                            Expanded(child: imeiField),
                            const SizedBox(width: 16),
                            Expanded(child: bateriaField),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          imeiField,
                          const SizedBox(height: 16),
                          bateriaField,
                        ],
                      );
                    },
                  ),
                  ..._buildLookupSection(theme, palette),
                  const SizedBox(height: 28),
                  _SectionHeader(
                    title: 'Registro asociado',
                    subtitle: 'Selecciona el identificador disponible en stock.',
                    titleColor: palette.textPrimary,
                    subtitleColor: palette.textMuted,
                  ),
                  const SizedBox(height: 16),
                  _buildRegistroSelector(theme, palette),
                  const SizedBox(height: 32),
                  _SectionHeader(
                    title: 'Inspección rápida',
                    subtitle: 'Confirma el estado de la pulsera y sus accesorios.',
                    titleColor: palette.textPrimary,
                    subtitleColor: palette.textMuted,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final item in inspectionItems)
                        _inspectionCard(theme, palette, item),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Divider(color: palette.divider),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: widget.isSubmitting ? null : _handleSubmit,
                      icon: widget.isSubmitting
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.primary,
                                ),
                              ),
                            )
                          : const Icon(Icons.save_alt_rounded),
                      label: Text(
                        widget.isSubmitting ? 'Registrando…' : 'Registrar pulsera',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: .9),
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 16,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    ThemeData theme,
    FormPalette palette,
    String label,
    IconData icon,
  ) {
    final borderRadius = BorderRadius.circular(16);
    return InputDecoration(
      labelText: label,
      labelStyle: theme.textTheme.bodyMedium?.copyWith(color: palette.fieldLabel),
      floatingLabelStyle:
          theme.textTheme.bodyMedium?.copyWith(color: palette.fieldLabel),
      prefixIcon: Icon(icon, size: 20, color: palette.fieldIcon),
      filled: true,
      fillColor: palette.fieldFill,
      border: OutlineInputBorder(borderRadius: borderRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: palette.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: palette.fieldFocusedBorder, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(
          color: theme.colorScheme.error.withValues(alpha: .9),
          width: 1.5,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
      ),
    );
  }

  Widget _buildRegistroSelector(ThemeData theme, FormPalette palette) {
    final opciones = widget.opcionesRegistro;
    if (opciones == null) {
      return _ShimmerPlaceholder(palette: palette);
    }
    if (opciones.isEmpty) {
      return _InfoBanner(
        icon: Icons.info_outline,
        message:
            'No hay IDIM/OYSTA activos para asignar. Revisa el panel de stock.',
        palette: palette,
      );
    }

    final entries = opciones.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<String>(
          style: ButtonStyle(
            visualDensity: VisualDensity.standard,
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return palette.segmentedSelectedBackground;
              }
              return palette.segmentedUnselectedBackground;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return palette.segmentedSelectedForeground;
              }
              return palette.segmentedUnselectedForeground;
            }),
            side: WidgetStateProperty.all(
              BorderSide(color: palette.segmentedBorder),
            ),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          segments: entries
              .map(
                (entry) => ButtonSegment<String>(
                  value: entry.key,
                  icon: const Icon(Icons.storage_rounded),
                  label: Text(
                    entry.key,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
          selected: {
            if (widget.tipoRegistroSeleccionado != null)
              widget.tipoRegistroSeleccionado!,
          },
          onSelectionChanged: (selection) {
            if (selection.isEmpty) return;
            final value = selection.first;
            widget.onChangeRegistro(value, opciones[value]['id'].toString());
          },
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: widget.tipoRegistroSeleccionado == null
              ? Text(
                  'Selecciona un registro para continuar.',
                  key: const ValueKey('empty-registro'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                )
              : _RegistroSummary(
                  key: ValueKey(widget.tipoRegistroSeleccionado),
                  label: widget.tipoRegistroSeleccionado!,
                  codigo:
                      opciones[widget.tipoRegistroSeleccionado!]?['codigo']
                              ?.toString() ??
                          '--',
                  id:
                      opciones[widget.tipoRegistroSeleccionado!]?['id']
                              .toString() ??
                          '--',
                ),
        ),
      ],
    );
  }

  Widget _inspectionCard(
    ThemeData theme,
    FormPalette palette,
    _InspectionItem item,
  ) {
    final value = _answers[item.key];
    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.chipBorder),
        color: palette.chipBackground,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              _buildYesNoChip(theme, palette, item.key, 'SI', 'Sí', value),
              _buildYesNoChip(theme, palette, item.key, 'NO', 'No', value),
              _buildYesNoChip(theme, palette, item.key, null, 'Sin dato', value),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildYesNoChip(
    ThemeData theme,
    FormPalette palette,
    String field,
    String? chipValue,
    String label,
    String? currentValue,
  ) {
    final isSelected = currentValue == chipValue;
    return ChoiceChip(
      selected: isSelected,
      label: Text(label),
      avatar: chipValue == null
          ? Icon(
              Icons.remove_circle_outline,
              size: 16,
              color: palette.textMuted,
            )
          : Icon(
              chipValue == 'SI' ? Icons.check_circle : Icons.highlight_off,
              size: 16,
              color:
                  chipValue == 'SI' ? theme.colorScheme.secondary : theme.colorScheme.error,
            ),
      onSelected: (_) {
        setState(() {
          _answers[field] = chipValue;
        });
        widget.onChangeRadio(field, chipValue);
      },
      selectedColor: palette.chipSelectedBackground,
      backgroundColor: palette.chipBackground,
      labelStyle: theme.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: isSelected
            ? palette.chipSelectedForeground
            : palette.chipUnselectedForeground,
      ),
    );
  }

  List<Widget> _buildLookupSection(ThemeData theme, FormPalette palette) {
    final feedback = _buildLookupFeedback(theme, palette);
    if (feedback == null) return const <Widget>[];
    return <Widget>[const SizedBox(height: 12), feedback];
  }

  Widget? _buildLookupFeedback(ThemeData theme, FormPalette palette) {
    if (widget.isLookupInProgress) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: palette.neutralCardBackground,
          border: Border.all(color: palette.neutralCardBorder),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  theme.colorScheme.secondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Consultando el IMEI de la pulsera…',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final error = widget.lookupError;
    if (error != null && error.isNotEmpty) {
      return _InfoBanner(
        icon: Icons.error_outline,
        message: 'No se pudo consultar el IMEI: $error',
        palette: palette,
      );
    }

    final result = widget.lookupResult;
    final searched = widget.lookupImeiSearched;
    if (result != null && searched != null) {
      final referencia = result['REFERENCIA']?.toString();
      final origen = result['ORIGEN']?.toString();
      final numeroPedido = result['NUMERO_PEDIDO']?.toString();
      final observacionesRaw = result['OBSERVACIONES']?.toString().trim();
      final observaciones =
          (observacionesRaw != null && observacionesRaw.isNotEmpty)
              ? observacionesRaw
              : null;

      return _LookupResultCard(
        imei: searched,
        referencia: referencia,
        origen: origen,
        numeroPedido: numeroPedido,
        observaciones: observaciones,
        palette: palette,
      );
    }

    if (searched != null && searched.isNotEmpty) {
      return _InfoBanner(
        icon: Icons.search_off_outlined,
        message:
            'No se encontraron coincidencias previas para el IMEI $searched.',
        palette: palette,
      );
    }

    return null;
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final Color? subtitleColor;

  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.titleColor,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: titleColor ?? theme.colorScheme.onSurface,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: subtitleColor ?? theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final FormPalette palette;

  const _InfoBanner({
    required this.icon,
    required this.message,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: palette.infoBackground,
        border: Border.all(color: palette.infoBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.textPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerPlaceholder extends StatelessWidget {
  final FormPalette palette;

  const _ShimmerPlaceholder({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: palette.placeholderBackground,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

class _RegistroSummary extends StatelessWidget {
  final String label;
  final String codigo;
  final String id;

  const _RegistroSummary({
    super.key,
    required this.label,
    required this.codigo,
    required this.id,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = FormPalette.fromTheme(theme);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: palette.neutralCardBackground,
        border: Border.all(color: palette.neutralCardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.assignment_ind_outlined, color: palette.textPrimary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label seleccionado',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Código: $codigo',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              Text(
                'ID: $id',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted.withValues(alpha: .8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InspectionItem {
  final String key;
  final String label;

  const _InspectionItem(this.key, this.label);
}

class _LookupResultCard extends StatelessWidget {
  final String imei;
  final String? referencia;
  final String? origen;
  final String? numeroPedido;
  final String? observaciones;
  final FormPalette palette;

  const _LookupResultCard({
    required this.imei,
    this.referencia,
    this.origen,
    this.numeroPedido,
    this.observaciones,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasObservaciones =
        observaciones != null && observaciones!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: palette.neutralCardBackground,
        border: Border.all(color: palette.neutralCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.manage_search_outlined,
                color: theme.colorScheme.secondary.withValues(alpha: .9),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Resultado para IMEI $imei',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (referencia != null && referencia!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Referencia: $referencia',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
          if (origen != null && origen!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Origen: $origen',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
          if (numeroPedido != null && numeroPedido!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Pedido: $numeroPedido',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                hasObservaciones
                    ? Icons.report_problem_outlined
                    : Icons.check_circle_outline,
                color: hasObservaciones
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasObservaciones
                      ? 'Observaciones: $observaciones'
                      : 'Sin observaciones registradas para este IMEI.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

