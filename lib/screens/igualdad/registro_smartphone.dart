import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:configtool_granite_frontend/src/api/igualdad_api.dart';
import '../../../models/paged_response.dart';
import '../../../models/smartphone.dart';

import 'formulario_smartphone_new.dart';
import 'resumen_stock.dart';
import 'tabla_registros.dart';
import 'dialogo_editar_smartphone.dart';
import '../../widgets/animated_background.dart';

class RegistroSmartphoneScreen extends StatefulWidget {
  const RegistroSmartphoneScreen({super.key});

  @override
  State<RegistroSmartphoneScreen> createState() =>
      _RegistroSmartphoneScreenState();
}

class _RegistroSmartphoneScreenState extends State<RegistroSmartphoneScreen> {
  // Pagination state
  int _paginaActual = 1;
  static const int _registrosPorPagina = 10;
  int _totalItems = 0;

  // Controllers & other state
  final TextEditingController _imeiController = TextEditingController();
  final TextEditingController _bateriaController = TextEditingController();
  final TextEditingController _cometaController = TextEditingController();
  final TextEditingController _simController = TextEditingController();
  final TextEditingController _imeiQrController = TextEditingController();
  final TextEditingController _simQrController = TextEditingController();
  final TextEditingController _btController = TextEditingController();
  final TextEditingController _imei2Controller = TextEditingController();

  Map<String, dynamic>? _opcionesRegistro;
  String? _registroSeleccionado;
  String? _tipoRegistroSeleccionado;
  String? _tipoSmartphone = 'AGRESOR';
  List<Map<String, dynamic>> _usuarios = [];
  int? _selectedUsuarioId;
  final Map<String, String?> _radioValues = {
    'remaquetado': null,
    'danos_fisicos': null,
    'empareja_pulsera_boton': null,
    'solapa_cargador': null,
    'sonido': null,
    'wifi_activada': null,
    'geolocalizacion_funcional': null,
  };
  bool _registrando = false;
  bool _registrandoIrrecuperable = false;
  bool _lookupLoading = false;
  String? _lookupError;
  Map<String, dynamic>? _lookupResult;
  String? _lastLookupImei;
  int _lookupRequestId = 0;
  int _formularioResetToken = 0;

  List<Map<String, dynamic>> ultimosRegistros = [];
  bool _cargandoRegistros = false;
  String _searchQuery = '';
  Map<String, int>? stockReal;
  Map<String, int>? idimActivoVals;
  Map<String, int>? oystaActivoVals;
  Map<String, int>? irrecuperablesVals;
  String? idimCodigo;
  String? oystaCodigo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Force rebuild to update theme colors
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _cargarUltimosRegistros();
    _imeiController.addListener(_onImeiChanged);
  }

  @override
  void dispose() {
    _imeiController.removeListener(_onImeiChanged);
    _imeiController.dispose();
    _bateriaController.dispose();
    _cometaController.dispose();
    _simController.dispose();
    _imeiQrController.dispose();
    _simQrController.dispose();
    _btController.dispose();
    _imei2Controller.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _cargarRegistroActivo();
    await _cargarUsuarios();
  }

  Future<void> _cargarUsuarios() async {
    try {
      final list = await IgualdadApi.getUsuarios();
      if (!mounted) return;
      setState(() => _usuarios = list);
    } catch (e) {
      if (!mounted) return;
      print("[WARN _cargarUsuarios] error: $e");
    }
  }

  void _onImeiChanged() {
    final raw = _imeiController.text.trim();
    if (raw.isEmpty || raw.toUpperCase() == 'NO_LEGIBLE' || raw.length < 15) {
      setState(() {
        _lookupLoading = false;
        _lookupError = null;
        _lookupResult = null;
        _lastLookupImei = null;
      });
      return;
    }
    if (raw.length == 15 && raw != _lastLookupImei) {
      _buscarRegistroPorImei(raw);
    }
  }

  Future<void> _buscarRegistroPorImei(String imei) async {
    setState(() {
      _lookupLoading = true;
      _lookupError = null;
      _lookupResult = null;
    });
    final requestId = ++_lookupRequestId;
    try {
      final data = await IgualdadApi.buscarRegistroEntrada(
        imei: imei,
        exact: true,
        limit: 1,
      );
      if (!mounted || requestId != _lookupRequestId) return;
      final result = data.isNotEmpty ? data.first : null;
      setState(() {
        _lookupLoading = false;
        _lookupResult = result;
        _lookupError = null;
        _lastLookupImei = imei;
      });
      if (result != null) {
        _autoSeleccionarTipoDesdeReferencia(result['REFERENCIA']?.toString());
      }
    } catch (e) {
      if (!mounted || requestId != _lookupRequestId) return;
      setState(() {
        _lookupLoading = false;
        _lookupError = e.toString();
        _lookupResult = null;
        _lastLookupImei = imei;
      });
    }
  }

  void _autoSeleccionarTipoDesdeReferencia(String? referencia) {
    if (referencia == null) return;
    final ref = referencia.trim().toUpperCase();
    String? nuevoTipo;
    if (ref == 'SEVDG-D_TRACK_AGR') {
      nuevoTipo = 'AGRESOR';
    } else if (ref == 'SEVDG-D_TRACK_VICT') {
      nuevoTipo = 'VICTIMA';
    }
    if (nuevoTipo != null && nuevoTipo != _tipoSmartphone) {
      setState(() => _tipoSmartphone = nuevoTipo);
    }
  }

  Future<void> _cargarRegistroActivo() async {
    try {
      final data = await IgualdadApi.getStockResumen();
      if (!mounted) return;
      setState(() {
        _opcionesRegistro = {};
        if (data['idim'] != null && data['idim_id'] != null) {
          _opcionesRegistro!['IDIM'] = {
            'id': data['idim_id'],
            'codigo': data['idim'],
          };
        }
        if (data['oysta'] != null && data['oysta_id'] != null) {
          _opcionesRegistro!['OYSTA'] = {
            'id': data['oysta_id'],
            'codigo': data['oysta'],
          };
        }
        if (_opcionesRegistro!.isNotEmpty) {
          _tipoRegistroSeleccionado = _opcionesRegistro!.keys.first;
          _registroSeleccionado =
              _opcionesRegistro![_tipoRegistroSeleccionado]!['id'].toString();
        }
        stockReal = Map<String, int>.from(data['stock_real']);
        idimActivoVals = Map<String, int>.from(data['idim_activo']);
        oystaActivoVals = Map<String, int>.from(data['oysta_activo']);
        idimCodigo = data['idim'];
        oystaCodigo = data['oysta'];
        if (data['irrecuperables'] != null) {
          final raw = data['irrecuperables'] as Map;
          irrecuperablesVals = raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
        } else {
          irrecuperablesVals = {'sm': 0, 'pulseras': 0, 'botones': 0, 'powerbanks': 0};
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cargando resumen: $e')));
    }
  }

  Future<void> _cargarUltimosRegistros() async {
    setState(() => _cargandoRegistros = true);
    try {
      final PagedResponse<Smartphone> pageResp =
          await IgualdadApi.getUltimosSmartphones(
            page: _paginaActual,
            size: _registrosPorPagina,
            query: _searchQuery.isEmpty ? null : _searchQuery,
          );
      if (!mounted) return;
      setState(() {
        _totalItems = pageResp.total;
        ultimosRegistros = pageResp.data.map((s) => s.toJson()).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cargando registros: $e')));
    } finally {
      if (mounted) {
        setState(() => _cargandoRegistros = false);
      }
    }
  }

  void _onSearchQueryChanged(String query) {
    final normalized = query.trim();
    if (normalized == _searchQuery) return;
    setState(() {
      _searchQuery = normalized;
      _paginaActual = 1;
    });
    _cargarUltimosRegistros();
  }

  Map<String, String> _parseImeiQr(String qrText) {
    final result = <String, String>{};
    final imei1Reg = RegExp(r'IMEI1:([^;]+)');
    final imei2Reg = RegExp(r'IMEI2:([^;]+)');
    final btReg = RegExp(r'BT:([^;]+)');

    final m1 = imei1Reg.firstMatch(qrText);
    if (m1 != null) result['imei1'] = m1.group(1)!.trim();

    final m2 = imei2Reg.firstMatch(qrText);
    if (m2 != null) result['imei2'] = m2.group(1)!.trim();

    final m3 = btReg.firstMatch(qrText);
    if (m3 != null) result['bt'] = m3.group(1)!.trim().replaceAll(':', '');

    return result;
  }

  Future<void> _registrarSmartphoneIrrecuperable() async {
    if (_registroSeleccionado == null || _tipoRegistroSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona IDIM u OYSTA correctamente.')),
      );
      return;
    }
    final qrParsed = _parseImeiQr(_imeiQrController.text);
    final imei1Val = qrParsed['imei1'] ?? _lookupResult?['imei1'] ?? _imeiController.text.trim();
    final imei2Val = qrParsed['imei2'] ?? _lookupResult?['imei2'];
    final btVal = _btController.text.trim().isNotEmpty
        ? _btController.text.trim()
        : (qrParsed['bt'] ?? (_lookupResult != null && _lookupResult!['imei'] != null && _lookupResult!['imei'].toString().contains('BT:')
            ? _lookupResult!['imei'].toString().split('BT:')[1].split(';')[0]
            : ''));
    final simVal = _simController.text.trim().isNotEmpty
        ? _simController.text.trim()
        : (_simQrController.text.trim().isNotEmpty
            ? _simQrController.text.trim()
            : (_lookupResult?['sim']?.toString() ?? ''));

    final payload = {
      'imei': _imeiController.text.trim(),
      'tipo_dispositivo': 'SM',
      'registro_id': int.parse(_registroSeleccionado!),
      'registro_tipo': _tipoRegistroSeleccionado,
      'sim': simVal,
      'imei1': imei1Val,
      'imei2': imei2Val,
      'bt': btVal,
      'usuario_id': _selectedUsuarioId,
    };
    try {
      setState(() => _registrandoIrrecuperable = true);
      await IgualdadApi.registrarIrrecuperableDispositivo(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Smartphone registrado como irrecuperable')),
      );
      setState(() {
        _lookupResult = null;
        _lookupError = null;
        _lastLookupImei = null;
        _selectedUsuarioId = null;
        _formularioResetToken++;
        _imeiController.clear();
        _imei2Controller.clear();
        _bateriaController.clear();
        _cometaController.clear();
        _simController.clear();
        _imeiQrController.clear();
        _simQrController.clear();
        _btController.clear();
        for (final k in _radioValues.keys) {
          _radioValues[k] = null;
        }
      });
      await _cargarRegistroActivo();
      setState(() => _paginaActual = 1);
      await _cargarUltimosRegistros();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al registrar irrecuperable: $e')),
      );
    } finally {
      if (mounted) setState(() => _registrandoIrrecuperable = false);
    }
  }

  Future<void> _registrarSmartphone() async {
    if (_registroSeleccionado == null || _tipoRegistroSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona IDIM u OYSTA correctamente.')),
      );
      return;
    }
    final qrParsed = _parseImeiQr(_imeiQrController.text);
    final imei1Val = qrParsed['imei1'] ?? _lookupResult?['imei1'] ?? _imeiController.text.trim();
    final imei2Val = _imei2Controller.text.trim().isNotEmpty
        ? _imei2Controller.text.trim()
        : (qrParsed['imei2'] ?? _lookupResult?['imei2']);
    final btVal = _btController.text.trim().isNotEmpty
        ? _btController.text.trim()
        : (qrParsed['bt'] ?? (_lookupResult != null && _lookupResult!['imei'] != null && _lookupResult!['imei'].toString().contains('BT:')
            ? _lookupResult!['imei'].toString().split('BT:')[1].split(';')[0]
            : ''));
    final simVal = _simController.text.trim().isNotEmpty
        ? _simController.text.trim()
        : (_simQrController.text.trim().isNotEmpty
            ? _simQrController.text.trim()
            : (_lookupResult?['sim']?.toString() ?? ''));

    final payload = {
      'imei': _imeiController.text.trim(),
      'registro_id': int.parse(_registroSeleccionado!),
      'registro_tipo': _tipoRegistroSeleccionado,
      'tipo': _tipoSmartphone,
      'porcentaje_bateria': _bateriaController.text.trim(),
      'version_cometa': _cometaController.text.trim(),
      'remaquetado': _radioValues['remaquetado'],
      'danos_fisicos': _radioValues['danos_fisicos'],
      'empareja_pulsera_boton': _radioValues['empareja_pulsera_boton'],
      'solapa_cargador': _radioValues['solapa_cargador'],
      'sonido': _radioValues['sonido'],
      'wifi_activada': _radioValues['wifi_activada'],
      'geolocalizacion_funcional': _radioValues['geolocalizacion_funcional'],
      'sim': simVal,
      'imei1': imei1Val,
      'imei2': imei2Val,
      'bt': btVal,
      'usuario_id': _selectedUsuarioId,
    };
    try {
      setState(() => _registrando = true);
      await IgualdadApi.registrarSmartphone(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Smartphone registrado')));
      setState(() {
        _lookupResult = null;
        _lookupError = null;
        _lastLookupImei = null;
        _selectedUsuarioId = null;
        _formularioResetToken++;
        _imeiController.clear();
        _imei2Controller.clear();
        _bateriaController.clear();
        _cometaController.clear();
        _simController.clear();
        _imeiQrController.clear();
        _simQrController.clear();
        _btController.clear();
        for (final k in _radioValues.keys) {
          _radioValues[k] = null;
        }
      });
      await _cargarRegistroActivo();
      setState(() => _paginaActual = 1);
      await _cargarUltimosRegistros();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al registrar smartphone: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _registrando = false);
      }
    }
  }

  Future<void> _eliminarSmartphone(int id) async {
    try {
      await IgualdadApi.deleteSmartphone(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro eliminado correctamente')),
      );
      await _cargarRegistroActivo();
      await _cargarUltimosRegistros();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al eliminar registro: $e')));
    }
  }

  Future<void> _editarSmartphone(
    int id,
    Map<String, dynamic> antiguosDatos,
  ) async {
    final Map<String, dynamic>? nuevosDatos = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => DialogoEditarSmartphone(
        datos: antiguosDatos,
        usuarios: _usuarios,
      ),
    );

    if (nuevosDatos == null) return;

    try {
      await IgualdadApi.updateSmartphone(id, nuevosDatos);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro actualizado correctamente')),
      );
      await _cargarRegistroActivo();
      await _cargarUltimosRegistros();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al actualizar registro: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: AnimatedBackgroundWidget(intensity: 0.2),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header row ──────────────────────────────
                      Row(
                        children: [
                          Material(
                            color: theme.colorScheme.surface.withValues(alpha: 0.25),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => Navigator.of(context).pop(),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Icon(
                                  Icons.arrow_back_rounded,
                                  color: theme.colorScheme.onSurface,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.smartphone_rounded,
                              color: theme.colorScheme.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Registro de Smartphones',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Text(
                                'Agresores y víctimas',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () {
                              _loadData();
                              _cargarUltimosRegistros();
                            },
                            tooltip: 'Actualizar',
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // ── Main content ─────────────────────────────
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                            child: Container(
                              width: double.infinity,
                              height: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: theme.dividerColor.withValues(alpha: 0.5),
                                ),
                              ),
                              child: LayoutBuilder(
                                builder: (context, inner) {
                                  final isDesktop = inner.maxWidth > 900;
                                  if (isDesktop) {
                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 7,
                                          child: Column(
                                            children: [
                                              Expanded(
                                                child: SingleChildScrollView(
                                                  child: Center(
                                                    child: ConstrainedBox(
                                                      constraints: const BoxConstraints(maxWidth: 1000),
                                                      child: _buildFormulario(),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (stockReal != null &&
                                                  idimActivoVals != null &&
                                                  oystaActivoVals != null) ...[
                                                const SizedBox(height: 16),
                                                ResumenStock(
                                                  stockReal: stockReal,
                                                  idimActivoVals: idimActivoVals,
                                                  oystaActivoVals: oystaActivoVals,
                                                  irrecuperablesVals: irrecuperablesVals,
                                                  idimCodigo: idimCodigo,
                                                  oystaCodigo: oystaCodigo,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 28),
                                        Expanded(
                                          flex: 3,
                                          child: _buildTabla(),
                                        ),
                                      ],
                                    );
                                  } else {
                                    return SingleChildScrollView(
                                      child: Column(
                                        children: [
                                          Center(
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(maxWidth: 1000),
                                              child: _buildFormulario(),
                                            ),
                                          ),
                                          const SizedBox(height: 24),
                                          if (stockReal != null &&
                                              idimActivoVals != null &&
                                              oystaActivoVals != null)
                                            ResumenStock(
                                              stockReal: stockReal,
                                              idimActivoVals: idimActivoVals,
                                              oystaActivoVals: oystaActivoVals,
                                              irrecuperablesVals: irrecuperablesVals,
                                              idimCodigo: idimCodigo,
                                              oystaCodigo: oystaCodigo,
                                            ),
                                          const SizedBox(height: 24),
                                          SizedBox(height: 600, child: _buildTabla()),
                                        ],
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormulario() {
    return FormularioSmartphoneNew(
      key: ValueKey(_formularioResetToken),
      imeiController: _imeiController,
      bateriaController: _bateriaController,
      cometaController: _cometaController,
      simController: _simController,
      imeiQrController: _imeiQrController,
      simQrController: _simQrController,
      btController: _btController,
      imei2Controller: _imei2Controller,
      opcionesRegistro: _opcionesRegistro,
      tipoRegistroSeleccionado: _tipoRegistroSeleccionado,
      registroSeleccionado: _registroSeleccionado,
      tipoSmartphone: _tipoSmartphone,
      radioValues: _radioValues,
      onChangeRegistro: (t, id) => setState(() {
        _tipoRegistroSeleccionado = t;
        _registroSeleccionado = id;
      }),
      onChangeTipoSmartphone: (t) =>
          setState(() => _tipoSmartphone = t),
      onRegistrar: () => _registrarSmartphone(),
      usuarios: _usuarios,
      selectedUsuarioId: _selectedUsuarioId,
      onChangeUsuario: (uId) => setState(() => _selectedUsuarioId = uId),
      onRefreshUsuarios: () => _cargarUsuarios(),
      onRegistrarIrrecuperable: _registrarSmartphoneIrrecuperable,
      isSubmitting: _registrando,
      isSubmittingIrrecuperable: _registrandoIrrecuperable,
      isLookupInProgress: _lookupLoading,
      lookupResult: _lookupResult,
      lookupError: _lookupError,
      lookupImeiSearched: _lastLookupImei,
    );
  }

  Widget _buildTabla() {
    return TablaRegistros(
      registros: ultimosRegistros,
      paginaActual: _paginaActual,
      totalItems: _totalItems,
      registrosPorPagina: _registrosPorPagina,
      searchQuery: _searchQuery,
      onSearchChanged: _onSearchQueryChanged,
      isLoading: _cargandoRegistros,
      onPrevPage: _paginaActual > 1
          ? () {
              setState(() => _paginaActual--);
              _cargarUltimosRegistros();
            }
          : null,
      onNextPage:
          _paginaActual * _registrosPorPagina <
              _totalItems
          ? () {
              setState(() => _paginaActual++);
              _cargarUltimosRegistros();
            }
          : null,
      onEliminar: _eliminarSmartphone,
      onEditar: _editarSmartphone,
      onPageChanged: (p) {
        setState(() => _paginaActual = p);
        _cargarUltimosRegistros();
      },
    );
  }
}
