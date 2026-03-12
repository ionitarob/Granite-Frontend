import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'form_palette.dart';

/// This widget keeps the same external contract as the previous
/// `FormularioSmartphone` so it can be swapped in without changing the
/// surrounding screen logic.  The presentation is split into clear sections:
///   1. Dispositivo: IMEI + tipo + batería + versión de Cometa.
///   2. Registro asociado: selector entre IDIM/OYSTA con el código visible.
///   3. Checklist: switches/segmented controls for the hardware checks.
///
/// Validation lives inside the widget – it will block submission when the IMEI
class FormularioSmartphoneNew extends StatefulWidget {
  final TextEditingController imeiController;
  final TextEditingController bateriaController;
  final TextEditingController cometaController;
  final Map<String, dynamic>? opcionesRegistro;
  final String? tipoRegistroSeleccionado;
  final String? registroSeleccionado;
  final String? tipoSmartphone;
  final Map<String, String?> radioValues;
  final void Function(String tipo, String id) onChangeRegistro;
  final void Function(String?) onChangeTipoSmartphone;
  final VoidCallback onRegistrar;
  final bool isSubmitting;
  final bool isLookupInProgress;
  final Map<String, dynamic>? lookupResult;
  final String? lookupError;
  final String? lookupImeiSearched;

  const FormularioSmartphoneNew({
    super.key,
    required this.imeiController,
    required this.bateriaController,
    required this.cometaController,
    required this.opcionesRegistro,
    required this.tipoRegistroSeleccionado,
    required this.registroSeleccionado,
    required this.tipoSmartphone,
    required this.radioValues,
    required this.onChangeRegistro,
    required this.onChangeTipoSmartphone,
    required this.onRegistrar,
    this.isSubmitting = false,
    this.isLookupInProgress = false,
    this.lookupResult,
    this.lookupError,
    this.lookupImeiSearched,
  });

  @override
  State<FormularioSmartphoneNew> createState() =>
      _FormularioSmartphoneNewState();
}

class _FormularioSmartphoneNewState extends State<FormularioSmartphoneNew> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _imeiFocus = FocusNode();
  late Map<String, String?> _checks;
  late bool _imeiLegible;

  @override
  void initState() {
    super.initState();
    _checks = Map<String, String?>.from(widget.radioValues);
    _imeiLegible = !_isNoLegibleValue(widget.imeiController.text);
  }

  @override
  void dispose() {
    _imeiFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FormularioSmartphoneNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.radioValues, widget.radioValues)) {
      _checks = Map<String, String?>.from(widget.radioValues);
    }
    if (oldWidget.imeiController.text != widget.imeiController.text) {
      _imeiLegible = !_isNoLegibleValue(widget.imeiController.text);
    }
  }

  void _handleSubmit() {
    final form = _formKey.currentState;
    if (form == null) return;
    if (form.validate()) {
      widget.onRegistrar();
    } else {
      FocusScope.of(context).requestFocus(_imeiFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = FormPalette.fromTheme(theme);

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
                    title: 'Datos del dispositivo',
                    subtitle: 'Identifica el terminal y su estado inicial.',
                    titleColor: palette.textPrimary,
                    subtitleColor: palette.textMuted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Por favor inserta el IMEI si es legible. Si no puedes leerlo, márcalo como "No legible".',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildImeiAndTipoRow(theme, palette),
                  ..._buildLookupSection(theme, palette),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 640;
                      final fields = [
                        Expanded(
                          child: TextFormField(
                            controller: widget.bateriaController,
                            decoration: _inputDecoration(
                              theme,
                              palette,
                              '% batería',
                              Icons.battery_charging_full,
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: palette.textPrimary,
                            ),
                            cursorColor: palette.textPrimary,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null; // optional
                              }
                              final parsed = int.tryParse(value);
                              if (parsed == null ||
                                  parsed < 0 ||
                                  parsed > 100) {
                                return '0 a 100';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: widget.cometaController,
                            decoration: _inputDecoration(
                              theme,
                              palette,
                              'Versión Cometa',
                              Icons.system_update_alt,
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: palette.textPrimary,
                            ),
                            cursorColor: palette.textPrimary,
                          ),
                        ),
                      ];

                      if (isWide) {
                        return Row(children: fields);
                      }
                      return Column(
                        children: [
                          fields[0],
                          const SizedBox(height: 16),
                          fields[2],
                        ],
                      );
                    },
                  ),
                  _SectionHeader(
                    title: 'Registro asociado',
                    subtitle:
                        'Selecciona el origen que corresponde al terminal.',
                    titleColor: palette.textPrimary,
                    subtitleColor: palette.textMuted,
                  ),
                  const SizedBox(height: 16),
                  _buildRegistroSelector(theme, palette),
                  const SizedBox(height: 32),
                  _SectionHeader(
                    title: 'Checklist del equipo',
                    subtitle: 'Evalúa rápidamente el estado del kit.',
                    titleColor: palette.textPrimary,
                    subtitleColor: palette.textMuted,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _qualityChip(
                        theme,
                        palette,
                        'remaquetado',
                        '¿Remaquetado?',
                      ),
                      _qualityChip(
                        theme,
                        palette,
                        'danos_fisicos',
                        '¿Daños físicos?',
                      ),
                      _qualityChip(
                        theme,
                        palette,
                        'empareja_pulsera_boton',
                        '¿Empareja pulsera/botón?',
                      ),
                      _qualityChip(
                        theme,
                        palette,
                        'solapa_cargador',
                        '¿Tiene solapa de cargador?',
                      ),
                      _qualityChip(theme, palette, 'sonido', '¿Emite sonido?'),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Divider(color: palette.divider),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
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
                        widget.isSubmitting
                            ? 'Registrando…'
                            : 'Registrar smartphone',
                      ),
                      onPressed: widget.isSubmitting ? null : _handleSubmit,
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary.withOpacity(
                          .9,
                        ),
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

  List<Widget> _buildLookupSection(ThemeData theme, FormPalette palette) {
    final feedback = _buildLookupFeedback(theme, palette);
    if (feedback == null) return const <Widget>[];
    return <Widget>[const SizedBox(height: 12), feedback];
  }

  Widget? _buildLookupFeedback(ThemeData theme, FormPalette palette) {
    if (!_imeiLegible) return null;

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
                'Consultando el IMEI en el histórico…',
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
      final tipoSugeridoCode = _mapReferenciaToTipoCode(referencia);
      final tipoSugeridoLabel = _friendlyTipo(tipoSugeridoCode);
      final currentLabel = _friendlyTipo(widget.tipoSmartphone);
      final tiposCoinciden =
          tipoSugeridoCode != null &&
          widget.tipoSmartphone != null &&
          tipoSugeridoCode == widget.tipoSmartphone;

      return _LookupResultCard(
        imei: searched,
        referencia: referencia,
        origen: origen,
        numeroPedido: numeroPedido,
        tipoSugeridoLabel: tipoSugeridoLabel,
        currentTipoLabel: currentLabel,
        tiposCoinciden: tiposCoinciden,
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

  InputDecoration _inputDecoration(
    ThemeData theme,
    FormPalette palette,
    String label,
    IconData icon,
  ) {
    final borderRadius = BorderRadius.circular(16);
    return InputDecoration(
      labelText: label,
      labelStyle: theme.textTheme.bodyMedium?.copyWith(
        color: palette.fieldLabel,
      ),
      floatingLabelStyle: theme.textTheme.bodyMedium?.copyWith(
        color: palette.fieldLabel,
      ),
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
          color: theme.colorScheme.error.withOpacity(.9),
          width: 1.5,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
      ),
    );
  }

  Widget _buildImeiAndTipoRow(ThemeData theme, FormPalette palette) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 720;

        final Widget imeiField = _imeiLegible
            ? TextFormField(
                controller: widget.imeiController,
                focusNode: _imeiFocus,
                decoration: _inputDecoration(
                  theme,
                  palette,
                  'IMEI (15 dígitos)',
                  Icons.confirmation_number_outlined,
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textPrimary,
                ),
                cursorColor: palette.textPrimary,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(15),
                ],
                validator: (value) {
                  if (!_imeiLegible) return null;
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return 'Introduce el IMEI';
                  if (trimmed.length != 15) return 'Deben ser 15 dígitos';
                  return null;
                },
              )
            : _NoLegibleNotice(palette: palette);

        final Widget tipoDropdown = DropdownButtonFormField<String>(
          initialValue: widget.tipoSmartphone,
          decoration: _inputDecoration(
            theme,
            palette,
            'Tipo de smartphone',
            Icons.person_outline,
          ),
          items: [
            DropdownMenuItem(
              value: 'AGRESOR',
              child: Text(
                'Agresor',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
            DropdownMenuItem(
              value: 'VICTIMA',
              child: Text(
                'Víctima',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
          dropdownColor: palette.dropdownBackground,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: palette.textPrimary,
          ),
          iconEnabledColor: palette.textPrimary,
          iconDisabledColor: palette.textMuted,
          onChanged: widget.onChangeTipoSmartphone,
        );

        final Widget toggleButton = SizedBox(
          width: isWide ? 150 : double.infinity,
          child: OutlinedButton.icon(
            icon: Icon(
              _imeiLegible ? Icons.visibility_off : Icons.edit,
              color: palette.textPrimary,
            ),
            label: Text(
              _imeiLegible ? 'No legible' : 'IMEI legible',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            onPressed: _toggleImeiLegible,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              side: BorderSide(color: palette.toggleBorder),
              foregroundColor: palette.textPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: imeiField),
              const SizedBox(width: 16),
              toggleButton,
              const SizedBox(width: 16),
              Expanded(child: tipoDropdown),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            imeiField,
            const SizedBox(height: 12),
            toggleButton,
            const SizedBox(height: 16),
            tipoDropdown,
          ],
        );
      },
    );
  }

  void _toggleImeiLegible() {
    FocusScope.of(context).unfocus();
    setState(() {
      _imeiLegible = !_imeiLegible;
      if (_imeiLegible) {
        widget.imeiController.clear();
        _imeiFocus.requestFocus();
      } else {
        widget.imeiController.text = 'NO_LEGIBLE';
      }
    });
  }

  bool _isNoLegibleValue(String? value) {
    if (value == null) return false;
    final normalized = value.trim().toUpperCase();
    return normalized == 'NO_LEGIBLE' || normalized == 'NO LEGIBLE';
  }

  String? _mapReferenciaToTipoCode(String? referencia) {
    if (referencia == null) return null;
    final ref = referencia.trim().toUpperCase();
    if (ref == 'SEVDG-D_TRACK_AGR') return 'AGRESOR';
    if (ref == 'SEVDG-D_TRACK_VICT') return 'VICTIMA';
    return null;
  }

  String? _friendlyTipo(String? code) {
    if (code == null || code.isEmpty) return null;
    final normalized = code.toUpperCase();
    if (normalized == 'AGRESOR') return 'Agresor';
    if (normalized == 'VICTIMA') return 'Víctima';
    return code;
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

  Widget _qualityChip(
    ThemeData theme,
    FormPalette palette,
    String field,
    String label,
  ) {
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
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              _buildChoiceChip(theme, palette, field, 'OK', 'Correcto'),
              _buildChoiceChip(theme, palette, field, 'NO OK', 'Falla'),
              _buildChoiceChip(theme, palette, field, null, 'Sin dato'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip(
    ThemeData theme,
    FormPalette palette,
    String field,
    String? value,
    String label,
  ) {
    final isSelected = _checks[field] == value;
    return ChoiceChip(
      selected: isSelected,
      label: Text(label),
      avatar: value == null
          ? Icon(
              Icons.remove_circle_outline,
              size: 16,
              color: palette.textMuted,
            )
          : Icon(
              value == 'OK' ? Icons.check_circle : Icons.highlight_off,
              size: 16,
              color: value == 'OK'
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.tertiary,
            ),
      onSelected: (_) {
        setState(() {
          _checks[field] = value;
          widget.radioValues[field] = value;
        });
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
                  color: palette.textMuted.withOpacity(.8),
                ),
              ),
            ],
          ),
        ],
      ),
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

class _NoLegibleNotice extends StatelessWidget {
  final FormPalette palette;

  const _NoLegibleNotice({required this.palette});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: palette.warningBackground,
        border: Border.all(color: palette.warningBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.report_problem_outlined, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'IMEI marcado como no legible. Se enviará "NO_LEGIBLE" en el registro.',
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

class _LookupResultCard extends StatelessWidget {
  final String imei;
  final String? referencia;
  final String? origen;
  final String? numeroPedido;
  final String? tipoSugeridoLabel;
  final String? currentTipoLabel;
  final bool tiposCoinciden;
  final String? observaciones;
  final FormPalette palette;

  const _LookupResultCard({
    required this.imei,
    this.referencia,
    this.origen,
    this.numeroPedido,
    this.tipoSugeridoLabel,
    this.currentTipoLabel,
    this.tiposCoinciden = false,
    this.observaciones,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasObservaciones =
        observaciones != null && observaciones!.trim().isNotEmpty;
    final tipoIcon = tiposCoinciden
        ? Icons.verified_outlined
        : Icons.auto_fix_high;
    final tipoColor = tiposCoinciden
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;

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
                color: theme.colorScheme.secondary.withOpacity(.9),
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
          if (tipoSugeridoLabel != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(tipoIcon, color: tipoColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tiposCoinciden
                        ? 'Tipo sugerido confirmado: $tipoSugeridoLabel'
                        : 'Tipo sugerido: $tipoSugeridoLabel'
                              '${currentTipoLabel != null ? ' (actual: $currentTipoLabel)' : ''}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
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
                      ? 'Fallo encontrado: $observaciones'
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
