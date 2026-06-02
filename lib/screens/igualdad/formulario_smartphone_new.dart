import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:barcode_widget/barcode_widget.dart';

import 'form_palette.dart';

class FormularioSmartphoneNew extends StatefulWidget {
  final TextEditingController imeiController;
  final TextEditingController bateriaController;
  final TextEditingController cometaController;
  final TextEditingController simController;
  final TextEditingController imeiQrController;
  final TextEditingController simQrController;
  final TextEditingController btController;
  final TextEditingController imei2Controller;
  final Map<String, dynamic>? opcionesRegistro;
  final String? tipoRegistroSeleccionado;
  final String? registroSeleccionado;
  final String? tipoSmartphone;
  final Map<String, String?> radioValues;
  final void Function(String tipo, String id) onChangeRegistro;
  final void Function(String?) onChangeTipoSmartphone;
  final VoidCallback onRegistrar;
  final VoidCallback? onRegistrarIrrecuperable;
  final bool isSubmitting;
  final bool isSubmittingIrrecuperable;
  final bool isLookupInProgress;
  final Map<String, dynamic>? lookupResult;
  final String? lookupError;
  final String? lookupImeiSearched;

  const FormularioSmartphoneNew({
    super.key,
    required this.imeiController,
    required this.bateriaController,
    required this.cometaController,
    required this.simController,
    required this.imeiQrController,
    required this.simQrController,
    required this.btController,
    required this.imei2Controller,
    required this.opcionesRegistro,
    required this.tipoRegistroSeleccionado,
    required this.registroSeleccionado,
    required this.tipoSmartphone,
    required this.radioValues,
    required this.onChangeRegistro,
    required this.onChangeTipoSmartphone,
    required this.onRegistrar,
    this.onRegistrarIrrecuperable,
    this.isSubmitting = false,
    this.isSubmittingIrrecuperable = false,
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
  final FocusNode _simFocus = FocusNode();
  
  late Map<String, String?> _checks;
  late bool _imeiLegible;
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
    _checks = Map<String, String?>.from(widget.radioValues);
    _imeiLegible = !_isNoLegibleValue(widget.imeiController.text);
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
        widget.imeiQrController.text = imeiFull;
        if (imeiFull.contains('BT:')) {
          try {
            widget.btController.text = imeiFull.split('BT:')[1].split(';')[0];
          } catch (_) {}
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
  void didUpdateWidget(covariant FormularioSmartphoneNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.radioValues, widget.radioValues)) {
      _checks = Map<String, String?>.from(widget.radioValues);
    }
    if (oldWidget.imeiController.text != widget.imeiController.text) {
      _imeiLegible = !_isNoLegibleValue(widget.imeiController.text);
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
            widget.imeiQrController.text = imeiFull;
            if (imeiFull.contains('BT:')) {
              try {
                widget.btController.text = imeiFull.split('BT:')[1].split(';')[0];
              } catch (_) {}
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

  bool _isNoLegibleValue(String? value) {
    if (value == null) return false;
    final normalized = value.trim().toUpperCase();
    return normalized == 'NO_LEGIBLE' || normalized == 'NO LEGIBLE';
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
        widget.simController.clear();
      }
    });
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
    final hasSim = widget.simController.text.isNotEmpty;
    final isSimReadOnly = hasSim && !_overrideSimEditable;
    final dbSim = widget.lookupResult?['sim']?.toString();
    final hasDbMapping = dbSim != null && dbSim.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Datos del dispositivo',
          subtitle: 'Identifica el terminal y su tarjeta SIM.',
          titleColor: palette.textPrimary,
          subtitleColor: palette.textMuted,
        ),
        const SizedBox(height: 20),
        _buildImeiAndTipoRow(theme, palette),
        ..._buildLookupSection(theme, palette),
        const SizedBox(height: 16),
        // SIM input field
        if (_imeiLegible) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: widget.simController,
                  focusNode: _simFocus,
                  readOnly: isSimReadOnly,
                  decoration: _inputDecoration(
                    theme,
                    palette,
                    'Tarjeta SIM (ICCID - 20 dígitos)',
                    Icons.sim_card_outlined,
                  ).copyWith(
                    filled: true,
                    fillColor: isSimReadOnly ? palette.fieldFill.withOpacity(0.5) : palette.fieldFill,
                    suffixIcon: isSimReadOnly
                        ? const Icon(Icons.lock_outline, size: 18, color: Colors.green)
                        : null,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textPrimary,
                  ),
                  cursorColor: palette.textPrimary,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(20),
                  ],
                  validator: (value) {
                    if (!_imeiLegible) return null;
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return 'Introduce la SIM';
                    if (trimmed.length < 15) return 'Mínimo 15 dígitos';
                    return null;
                  },
                ),
              ),
              if (isSimReadOnly) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _overrideSimEditable = true;
                    });
                  },
                  tooltip: 'Editar SIM manualmente',
                  icon: const Icon(Icons.edit_off_outlined),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (!hasDbMapping) ...[
            TextFormField(
              controller: widget.imei2Controller,
              decoration: _inputDecoration(
                theme,
                palette,
                'IMEI 2 (15 dígitos)',
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
                if (hasDbMapping) return null;
                final trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) return 'Introduce el IMEI 2';
                if (trimmed.length != 15) return 'Deben ser 15 dígitos';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: widget.btController,
              decoration: _inputDecoration(
                theme,
                palette,
                'Bluetooth MAC (BT)',
                Icons.bluetooth_audio,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textPrimary,
              ),
              cursorColor: palette.textPrimary,
              validator: (value) {
                if (hasDbMapping) return null;
                final trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) return 'Introduce el Bluetooth MAC';
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 480;

            final batteryField = TextFormField(
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
            );

            final cometaField = TextFormField(
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
            );

            if (isWide) {
              return Row(
                children: [
                  Expanded(child: batteryField),
                  const SizedBox(width: 16),
                  Expanded(child: cometaField),
                ],
              );
            }
            return Column(
              children: [
                batteryField,
                const SizedBox(height: 16),
                cometaField,
              ],
            );
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
          subtitle: 'Escanee los códigos QR del terminal y de la SIM.',
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
            helperText: 'Escanee el código QR que contiene IMEI1, IMEI2 y BT.',
            helperStyle: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: palette.textPrimary,
          ),
          cursorColor: palette.textPrimary,
          onChanged: (val) {
            final text = val.trim();
            if (text.contains('IMEI1:')) {
              final imei1Reg = RegExp(r'IMEI1:([^;]+)');
              final imei2Reg = RegExp(r'IMEI2:([^;]+)');
              final btReg = RegExp(r'BT:([^;]+)');

              final m1 = imei1Reg.firstMatch(text);
              if (m1 != null) {
                final im1 = m1.group(1)!.trim();
                if (im1.isNotEmpty && widget.imeiController.text != im1) {
                  widget.imeiController.text = im1;
                }
              }
              final m2 = imei2Reg.firstMatch(text);
              if (m2 != null) {
                final im2 = m2.group(1)!.trim();
                if (im2.isNotEmpty && widget.imei2Controller.text != im2) {
                  widget.imei2Controller.text = im2;
                }
              }
              final m3 = btReg.firstMatch(text);
              if (m3 != null) {
                final btVal = m3.group(1)!.trim();
                if (btVal.isNotEmpty && widget.btController.text != btVal) {
                  widget.btController.text = btVal;
                }
              }
            }
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: widget.simQrController,
          decoration: _inputDecoration(
            theme,
            palette,
            'Código QR del SIM',
            Icons.qr_code_2,
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: palette.textPrimary,
          ),
          cursorColor: palette.textPrimary,
          onChanged: (val) {
            final text = val.trim();
            if (text.isNotEmpty && widget.simController.text != text) {
              widget.simController.text = text;
            }
          },
        ),
        if (widget.imeiQrController.text.isNotEmpty || widget.simQrController.text.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (widget.imeiQrController.text.isNotEmpty)
                Column(
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
              if (widget.simQrController.text.isNotEmpty)
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: BarcodeWidget(
                        barcode: Barcode.qrCode(),
                        data: widget.simQrController.text,
                        width: 140,
                        height: 140,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'QR SIM',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStepChecklist(ThemeData theme, FormPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Checklist del equipo',
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
              _qualityChip(theme, palette, 'remaquetado', '¿Remaquetado?'),
              _qualityChip(theme, palette, 'danos_fisicos', '¿Daños físicos?'),
              _qualityChip(theme, palette, 'empareja_pulsera_boton', '¿Empareja pulsera/botón?'),
              _qualityChip(theme, palette, 'solapa_cargador', '¿Tiene solapa de cargador?'),
              _qualityChip(theme, palette, 'sonido', '¿Emite sonido?'),
              _qualityChip(theme, palette, 'wifi_activada', '¿Wi-fi Activada?'),
              _qualityChip(theme, palette, 'geolocalizacion_funcional', '¿Geolocalización Funcional?'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepRegistro(ThemeData theme, FormPalette palette) {
    final isDanosFisicos = _checks['danos_fisicos'] == 'NO OK';
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
                // When moving from "Datos" step to "Escáner QR" step,
                // auto-build the QR format strings if there is no DB lookup
                // result (user filled IMEI2, BT and SIM manually).
                final steps = _getSteps();
                final isOnDatosStep = steps[_currentStep] == 'Datos';
                if (isOnDatosStep && widget.lookupResult == null) {
                  final imei1 = widget.imeiController.text.trim();
                  final imei2 = widget.imei2Controller.text.trim();
                  final bt = widget.btController.text.trim();
                  final currentQr = widget.imeiQrController.text.trim();
                  // Auto-build IMEI QR string if not already formatted.
                  if (imei1.isNotEmpty && imei2.isNotEmpty && bt.isNotEmpty &&
                      !currentQr.contains('IMEI1:')) {
                    widget.imeiQrController.text =
                        'IMEI1:$imei1;IMEI2:$imei2;BT:$bt;';
                  }
                  // Auto-populate SIM QR field from SIM controller.
                  final sim = widget.simController.text.trim();
                  if (sim.isNotEmpty && widget.simQrController.text.trim().isEmpty) {
                    widget.simQrController.text = sim;
                  }
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
                : Icon(_checks['danos_fisicos'] == 'NO OK' ? Icons.delete_forever : Icons.save_alt_rounded),
            label: Text(
              _checks['danos_fisicos'] == 'NO OK'
                  ? (widget.isSubmittingIrrecuperable ? 'Registrando…' : 'Registrar como Irrecuperable')
                  : (widget.isSubmitting ? 'Registrando…' : 'Registrar Smartphone'),
            ),
            onPressed: (widget.isSubmitting || widget.isSubmittingIrrecuperable)
                ? null
                : () {
                    if (_checks['danos_fisicos'] == 'NO OK') {
                      if (widget.onRegistrarIrrecuperable != null) {
                        widget.onRegistrarIrrecuperable!();
                      }
                    } else {
                      _handleSubmit();
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: _checks['danos_fisicos'] == 'NO OK' ? theme.colorScheme.error : theme.colorScheme.primary,
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

  Widget _buildImeiAndTipoRow(ThemeData theme, FormPalette palette) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 580;

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
          value: widget.tipoSmartphone,
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
          width: isWide ? 130 : double.infinity,
          child: OutlinedButton(
            onPressed: _toggleImeiLegible,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              side: BorderSide(color: palette.toggleBorder),
              foregroundColor: palette.textPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              _imeiLegible ? 'No legible' : 'IMEI legible',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: imeiField),
              const SizedBox(width: 10),
              toggleButton,
              const SizedBox(width: 10),
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

  List<Widget> _buildLookupSection(ThemeData theme, FormPalette palette) {
    final feedback = _buildLookupFeedback(theme, palette);
    if (feedback == null) return const <Widget>[];
    return <Widget>[const SizedBox(height: 12), feedback];
  }

  Widget? _buildLookupFeedback(ThemeData theme, FormPalette palette) {
    if (!_imeiLegible) return null;

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

  List<Widget> _buildIrrecuperableBanner(ThemeData theme, FormPalette palette) {
    return [
      const SizedBox(height: 20),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: theme.colorScheme.error.withOpacity(0.1),
          border: Border.all(
            color: theme.colorScheme.error.withOpacity(0.6),
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.error,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¡Esta unidad es irrecuperable!',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'El dispositivo presenta daños físicos y no puede ser enviado a IDIM/OYSTA.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error.withOpacity(0.85),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _qualityChip(
    ThemeData theme,
    FormPalette palette,
    String field,
    String label,
  ) {
    return Container(
      width: 300,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
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
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
      label: Text(label, style: const TextStyle(fontSize: 11)),
      avatar: value == null
          ? Icon(
              Icons.remove_circle_outline,
              size: 14,
              color: palette.textMuted,
            )
          : Icon(
              value == 'OK' ? Icons.check_circle : Icons.highlight_off,
              size: 14,
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: titleColor ?? theme.colorScheme.onSurface,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: palette.neutralCardBackground,
        border: Border.all(color: palette.neutralCardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.assignment_ind_outlined, color: palette.textPrimary, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label seleccionado',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Código: $codigo',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                  fontSize: 11,
                ),
              ),
              Text(
                'ID: $id',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted.withOpacity(.8),
                  fontSize: 11,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: palette.infoBackground,
        border: Border.all(color: palette.infoBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.textPrimary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
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
}

class _ShimmerPlaceholder extends StatelessWidget {
  final FormPalette palette;

  const _ShimmerPlaceholder({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: palette.placeholderBackground,
        borderRadius: BorderRadius.circular(12),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: palette.warningBackground,
        border: Border.all(color: palette.warningBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.report_problem_outlined, color: theme.colorScheme.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'IMEI marcado como no legible. Se enviará "NO_LEGIBLE" en el registro.',
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
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
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Resultado para IMEI $imei',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (referencia != null && referencia!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Referencia: $referencia',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
                fontSize: 11,
              ),
            ),
          ],
          if (origen != null && origen!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Origen: $origen',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
                fontSize: 11,
              ),
            ),
          ],
          if (numeroPedido != null && numeroPedido!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Pedido: $numeroPedido',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
                fontSize: 11,
              ),
            ),
          ],
          if (tipoSugeridoLabel != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(tipoIcon, color: tipoColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tiposCoinciden
                        ? 'Tipo sugerido confirmado: $tipoSugeridoLabel'
                        : 'Tipo sugerido: $tipoSugeridoLabel'
                              '${currentTipoLabel != null ? ' (actual: $currentTipoLabel)' : ''}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
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
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasObservaciones
                      ? 'Fallo encontrado: $observaciones'
                      : 'Sin observaciones registradas para este IMEI.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textPrimary,
                    fontSize: 12,
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
