import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:barcode_widget/barcode_widget.dart';

import 'form_palette.dart';

class FormularioPulseraNew extends StatefulWidget {
  final TextEditingController imeiController;
  final TextEditingController bateriaController;
  final TextEditingController simController;
  final TextEditingController imeiQrController;
  final TextEditingController simQrController;
  final TextEditingController btController;
  final TextEditingController imei2Controller;
  final Map<String, dynamic>? opcionesRegistro;
  final String? tipoRegistroSeleccionado;
  final String? registroSeleccionado;
  final Map<String, String?> radioValues;
  final void Function(String tipo, String id) onChangeRegistro;
  final void Function(String key, String? value) onChangeRadio;
  final VoidCallback onRegistrar;
  final VoidCallback? onRegistrarIrrecuperable;
  final bool isSubmitting;
  final bool isSubmittingIrrecuperable;
  final bool isLookupInProgress;
  final Map<String, dynamic>? lookupResult;
  final String? lookupError;
  final String? lookupImeiSearched;
  final String selectedContrato;
  final void Function(String contrato) onChangeContrato;

  const FormularioPulseraNew({
    super.key,
    required this.imeiController,
    required this.bateriaController,
    required this.simController,
    required this.imeiQrController,
    required this.simQrController,
    required this.btController,
    required this.imei2Controller,
    required this.opcionesRegistro,
    required this.tipoRegistroSeleccionado,
    required this.registroSeleccionado,
    required this.radioValues,
    required this.onChangeRegistro,
    required this.onChangeRadio,
    required this.onRegistrar,
    required this.selectedContrato,
    required this.onChangeContrato,
    this.onRegistrarIrrecuperable,
    this.isSubmitting = false,
    this.isSubmittingIrrecuperable = false,
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
  final FocusNode _imeiFocus = FocusNode();
  final FocusNode _simFocus = FocusNode();

  late Map<String, String?> _answers;
  int _currentStep = 0; // index of the active step in _getSteps()
  bool _overrideSimEditable = false;

  List<String> _getSteps() {
    return [
      'Datos',
      'Escáner QR',
      'Checklist',
      'Registro',
    ];
  }

  @override
  void initState() {
    super.initState();
    _answers = Map<String, String?>.from(widget.radioValues);
    widget.imeiQrController.addListener(_onQrControllersChanged);
    widget.simQrController.addListener(_onQrControllersChanged);
    if (widget.lookupResult != null) {
      final sim = widget.lookupResult!['sim']?.toString();
      final imeiFull = widget.lookupResult!['imei']?.toString();
      final imei2 = widget.lookupResult!['imei2']?.toString();
      if (sim != null && sim.isNotEmpty) {
        widget.simController.text = sim;
        widget.simQrController.text = sim;
        _overrideSimEditable = false;
      }
      if (imei2 != null && imei2.isNotEmpty) {
        widget.imei2Controller.text = imei2;
      }
      if (imeiFull != null && imeiFull.isNotEmpty) {
        if (imeiFull.contains('BT:')) {
          try {
            final btRaw = imeiFull.split('BT:')[1].split(';')[0];
            final btCleaned = btRaw.replaceAll(':', '');
            widget.btController.text = btCleaned;
            final parts = imeiFull.split('BT:');
            widget.imeiQrController.text = '${parts[0]}BT:$btCleaned;';
          } catch (_) {
            widget.imeiQrController.text = imeiFull;
          }
        } else {
          widget.imeiQrController.text = imeiFull;
        }
        if (imeiFull.contains('IMEI2:')) {
          try {
            widget.imei2Controller.text = imeiFull.split('IMEI2:')[1].split(';')[0];
          } catch (_) {}
        }
      }
    }
  }

  void _onQrControllersChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.imeiQrController.removeListener(_onQrControllersChanged);
    widget.simQrController.removeListener(_onQrControllersChanged);
    _imeiFocus.dispose();
    _simFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FormularioPulseraNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.radioValues, widget.radioValues)) {
      _answers = Map<String, String?>.from(widget.radioValues);
    }
    // Auto-populate SIM/QR/BT if we get a result from lookup
    if (widget.lookupResult != oldWidget.lookupResult) {
      if (widget.lookupResult != null) {
        final sim = widget.lookupResult!['sim']?.toString();
        final imeiFull = widget.lookupResult!['imei']?.toString();
        final imei2 = widget.lookupResult!['imei2']?.toString();
        setState(() {
          if (sim != null && sim.isNotEmpty) {
            widget.simController.text = sim;
            widget.simQrController.text = sim;
            _overrideSimEditable = false;
          } else {
            widget.simController.clear();
            widget.simQrController.clear();
            _overrideSimEditable = true;
          }
          if (imei2 != null && imei2.isNotEmpty) {
            widget.imei2Controller.text = imei2;
          } else {
            widget.imei2Controller.clear();
          }
          if (imeiFull != null && imeiFull.isNotEmpty) {
            if (imeiFull.contains('BT:')) {
              try {
                final btRaw = imeiFull.split('BT:')[1].split(';')[0];
                final btCleaned = btRaw.replaceAll(':', '');
                widget.btController.text = btCleaned;
                final parts = imeiFull.split('BT:');
                widget.imeiQrController.text = '${parts[0]}BT:$btCleaned;';
              } catch (_) {
                widget.imeiQrController.text = imeiFull;
              }
            } else {
              widget.imeiQrController.text = imeiFull;
            }
            if (imeiFull.contains('IMEI2:')) {
              try {
                widget.imei2Controller.text = imeiFull.split('IMEI2:')[1].split(';')[0];
              } catch (_) {}
            }
          } else {
            widget.imeiQrController.clear();
            widget.btController.clear();
          }
        });
      } else {
        setState(() {
          widget.simController.clear();
          widget.simQrController.clear();
          widget.imeiQrController.clear();
          widget.btController.clear();
          widget.imei2Controller.clear();
          _overrideSimEditable = true;
        });
      }
    }
    final stepsCount = _getSteps().length;
    if (_currentStep >= stepsCount) {
      _currentStep = stepsCount - 1;
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
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStepperIndicator(theme, palette),
                  const SizedBox(height: 24),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: _buildCurrentStepContent(theme, palette),
                  ),
                  const SizedBox(height: 28),
                  Divider(color: palette.divider),
                  const SizedBox(height: 16),
                  _buildNavigationButtons(theme, palette),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepperIndicator(ThemeData theme, FormPalette palette) {
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = palette.textMuted.withOpacity(0.3);
    final steps = _getSteps();

    final widgets = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      widgets.add(_stepIndicatorItem(i, '${i + 1}. ${steps[i]}', activeColor, inactiveColor, theme, palette));
      if (i < steps.length - 1) {
        widgets.add(_stepConnector(i, activeColor, inactiveColor));
      }
    }

    return Row(
      children: widgets,
    );
  }

  Widget _stepIndicatorItem(int stepIndex, String title, Color activeColor, Color inactiveColor, ThemeData theme, FormPalette palette) {
    final isActive = _currentStep == stepIndex;
    final isDone = _currentStep > stepIndex;

    return Expanded(
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? activeColor : (isDone ? activeColor.withOpacity(0.2) : Colors.transparent),
              border: Border.all(
                color: (isActive || isDone) ? activeColor : inactiveColor,
                width: 2,
              ),
            ),
            child: Center(
              child: isDone
                  ? Icon(Icons.check, size: 16, color: activeColor)
                  : Text(
                      '${stepIndex + 1}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isActive ? theme.colorScheme.onPrimary : (isDone ? activeColor : palette.textMuted),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? theme.colorScheme.onSurface : palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepConnector(int stepIndex, Color activeColor, Color inactiveColor) {
    final isPassed = _currentStep > stepIndex;
    return Container(
      width: 30,
      height: 2,
      margin: const EdgeInsets.only(bottom: 20),
      color: isPassed ? activeColor : inactiveColor,
    );
  }

  Widget _buildCurrentStepContent(ThemeData theme, FormPalette palette) {
    final steps = _getSteps();
    final stepLabel = steps[_currentStep];
    switch (stepLabel) {
      case 'Datos':
        return _buildStepDatos(theme, palette);
      case 'Escáner QR':
        return _buildStepEscanerQr(theme, palette);
      case 'Checklist':
        return _buildStepChecklist(theme, palette);
      case 'Registro':
        return _buildStepRegistro(theme, palette);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStepDatos(ThemeData theme, FormPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Datos de la pulsera',
          subtitle: 'Identifica el terminal.',
          titleColor: palette.textPrimary,
          subtitleColor: palette.textMuted,
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: widget.imeiController,
          focusNode: _imeiFocus,
          decoration: _inputDecoration(
            theme,
            palette,
            'IMEI de la pulsera (15 dígitos)',
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
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) return 'Introduce el IMEI';
            if (trimmed.length != 15) return 'Deben ser 15 dígitos';
            return null;
          },
        ),
        ..._buildLookupSection(theme, palette),
        const SizedBox(height: 16),
        _buildContratoSelection(theme, palette),
        const SizedBox(height: 16),
        TextFormField(
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
              return null;
            }
            final parsed = int.tryParse(value);
            if (parsed == null || parsed < 0 || parsed > 100) {
              return '0 a 100';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildStepEscanerQr(ThemeData theme, FormPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Escáner de Códigos QR',
          subtitle: 'Escanee el código QR del terminal.',
          titleColor: palette.textPrimary,
          subtitleColor: palette.textMuted,
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: widget.imeiQrController,
          decoration: _inputDecoration(
            theme,
            palette,
            'Código QR del IMEI',
            Icons.qr_code_scanner,
          ).copyWith(
            helperText: 'Escanee el código QR que contiene el IMEI.',
            helperStyle: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: palette.textPrimary,
          ),
          cursorColor: palette.textPrimary,
          onChanged: (val) {
            final text = val.trim();
            if (text.length == 15 && RegExp(r'^\d+$').hasMatch(text)) {
              if (widget.imeiController.text != text) {
                widget.imeiController.text = text;
              }
            }
          },
        ),
        if (widget.imeiQrController.text.isNotEmpty) ...[
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: BarcodeWidget(
                    barcode: Barcode.qrCode(),
                    data: widget.imeiQrController.text,
                    width: 140,
                    height: 140,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'QR IMEI',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStepChecklist(ThemeData theme, FormPalette palette) {
    final inspectionItems = <_InspectionItem>[
      const _InspectionItem('danos_fisicos', '¿Daños físicos?'),
      const _InspectionItem('empareja_pulsera_boton', '¿Empareja pulsera/botón?'),
      const _InspectionItem('sin_alertas', '¿Sin alertas?'),
      const _InspectionItem('chequeo_abierta', '¿Chequeo abierta?'),
      const _InspectionItem('serigrafia', '¿Serigrafía?'),
      const _InspectionItem('tornilleria', '¿Tornillería?'),
      const _InspectionItem('wifi_activada', '¿Wi-fi Activada?'),
      const _InspectionItem('geolocalizacion_funcional', '¿Geolocalización Funcional?'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Checklist de la pulsera',
          subtitle: 'Evalúa rápidamente el estado del kit.',
          titleColor: palette.textPrimary,
          subtitleColor: palette.textMuted,
        ),
        const SizedBox(height: 20),
        Center(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              for (final item in inspectionItems)
                _inspectionCard(theme, palette, item),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepRegistro(ThemeData theme, FormPalette palette) {
    final isDanosFisicos = _answers['danos_fisicos'] == 'SI';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Registro asociado',
          subtitle: 'Selecciona el destino que corresponde al terminal.',
          titleColor: palette.textPrimary,
          subtitleColor: palette.textMuted,
        ),
        const SizedBox(height: 20),
        _buildRegistroSelector(theme, palette),
        if (isDanosFisicos)
          ..._buildIrrecuperableBanner(theme, palette),
      ],
    );
  }

  Widget _buildNavigationButtons(ThemeData theme, FormPalette palette) {
    final steps = _getSteps();
    final isFirstStep = _currentStep == 0;
    final isLastStep = _currentStep == steps.length - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (!isFirstStep)
          OutlinedButton.icon(
            icon: const Icon(Icons.arrow_back),
            label: const Text('Anterior'),
            onPressed: () {
              setState(() {
                _currentStep--;
              });
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          )
        else
          const SizedBox.shrink(),
        
        if (!isLastStep)
          FilledButton.icon(
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Siguiente'),
            onPressed: () {
              final form = _formKey.currentState;
              if (form != null && form.validate()) {
                final steps = _getSteps();
                final isOnDatosStep = steps[_currentStep] == 'Datos';
                if (isOnDatosStep && widget.lookupResult == null) {
                  final imei1 = widget.imeiController.text.trim();
                  widget.imeiQrController.text = imei1;
                }
                setState(() {
                  _currentStep++;
                });
              }
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          )
        else
          FilledButton.icon(
            icon: widget.isSubmitting || widget.isSubmittingIrrecuperable
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(_answers['danos_fisicos'] == 'SI' ? Icons.delete_forever : Icons.save_alt_rounded),
            label: Text(
              _answers['danos_fisicos'] == 'SI'
                  ? (widget.isSubmittingIrrecuperable ? 'Registrando…' : 'Registrar como Irrecuperable')
                  : (widget.isSubmitting ? 'Registrando…' : 'Registrar Pulsera'),
            ),
            onPressed: (widget.isSubmitting || widget.isSubmittingIrrecuperable)
                ? null
                : () {
                    if (_answers['danos_fisicos'] == 'SI') {
                      if (widget.onRegistrarIrrecuperable != null) {
                        widget.onRegistrarIrrecuperable!();
                      }
                    } else {
                      _handleSubmit();
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: _answers['danos_fisicos'] == 'SI' ? theme.colorScheme.error : theme.colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
      ],
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

  Widget _buildContratoSelection(ThemeData theme, FormPalette palette) {
    return DropdownButtonFormField<String>(
      value: widget.selectedContrato,
      decoration: _inputDecoration(
        theme,
        palette,
        'Tipo de Contrato',
        Icons.description_outlined,
      ),
      items: const [
        DropdownMenuItem(
          value: 'Contrato Antiguo 3 años',
          child: Text('Contrato Antiguo 3 años'),
        ),
        DropdownMenuItem(
          value: 'Contrato Ampliación Sept 2026',
          child: Text('Contrato Ampliación Sept 2026'),
        ),
      ],
      dropdownColor: palette.dropdownBackground,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: palette.textPrimary,
      ),
      iconEnabledColor: palette.textPrimary,
      iconDisabledColor: palette.textMuted,
      onChanged: (val) {
        if (val != null) {
          widget.onChangeContrato(val);
        }
      },
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: palette.neutralCardBackground,
          border: Border.all(color: palette.neutralCardBorder),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
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
                  fontSize: 13,
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SegmentedButton<String>(
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
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
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          segments: entries
              .map(
                (entry) => ButtonSegment<String>(
                  value: entry.key,
                  icon: const Icon(Icons.storage_rounded, size: 18),
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
      width: 280,
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

  List<Widget> _buildIrrecuperableBanner(ThemeData theme, FormPalette palette) {
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: theme.colorScheme.error.withOpacity(0.1),
          border: Border.all(color: theme.colorScheme.error.withOpacity(0.6), width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¡Esta unidad es irrecuperable!',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'La pulsera presenta daños físicos y no puede ser enviada a IDIM. '
                    'Regístrala como irrecuperable para que quede constancia en el resumen semanal.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: titleColor ?? theme.colorScheme.onSurface,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
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
            ],
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
  final String? observaciones;
  final FormPalette palette;

  const _LookupResultCard({
    required this.imei,
    required this.referencia,
    required this.origen,
    required this.numeroPedido,
    required this.observaciones,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              const Icon(Icons.history_toggle_off_rounded, color: Colors.green),
              const SizedBox(width: 12),
              Text(
                'Histórico: Coincidencia encontrada',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow('Referencia', referencia ?? '--', palette, theme),
          _infoRow('Origen', origen ?? '--', palette, theme),
          _infoRow('Número Pedido', numeroPedido ?? '--', palette, theme),
          if (observaciones != null) ...[
            const SizedBox(height: 8),
            Text(
              'Observaciones:',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              observaciones!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, FormPalette palette, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted)),
          Text(value, style: theme.textTheme.bodySmall?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600)),
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
