import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:configtool_granite_frontend/src/api/igualdad_api.dart';
import 'formulario_pulsera_new.dart';
import 'resumen_stock.dart';
import 'tablapulseras.dart';
import 'dialogo_editar_pulsera.dart';
import '../../widgets/main_sidebar.dart';
import '../../widgets/animated_background.dart';

class RegistroPulseraScreen extends StatefulWidget {
  const RegistroPulseraScreen({super.key});

  @override
  State<RegistroPulseraScreen> createState() => _RegistroPulseraScreenState();
}

class _RegistroPulseraScreenState extends State<RegistroPulseraScreen> {
  // ─── Formulario ────────────────────────────────────────────────────────
  final _imeiController = TextEditingController();
  final _bateriaController = TextEditingController();
  final _simController = TextEditingController();
  final _imeiQrController = TextEditingController();
  final _simQrController = TextEditingController();
  final _btController = TextEditingController();
  final _imei2Controller = TextEditingController();
  Map<String, dynamic>? _opcionesRegistro;
  String? _registroSeleccionado;
  String? _tipoRegistroSeleccionado;
  final Map<String, String?> _radioValues = {
    "danos_fisicos": null,
    "empareja_pulsera_boton": null,
    "sin_alertas": null,
    "chequeo_abierta": null,
    "serigrafia": null,
    "tornilleria": null,
    "wifi_activada": null,
    "geolocalizacion_funcional": null,
  };
  bool _registrando = false;
  bool _registrandoIrrecuperable = false;
  bool _lookupLoading = false;
  String? _lookupError;
  Map<String, dynamic>? _lookupResult;
  String? _lastLookupImei;
  int _lookupRequestId = 0;

  // ─── Stock / Resumen ──────────────────────────────────────────────────
  Map<String, int>? stockReal;
  Map<String, int>? idimActivoVals;
  Map<String, int>? oystaActivoVals;
  Map<String, int>? irrecuperablesVals;
  String? idimCodigo;
  String? oystaCodigo;

  int _paginaActual = 1;
  static const int _porPagina = 10;
  static const int _maxBusquedaPulseras = 500;
  int _totalItems = 0;
  List<Map<String, dynamic>> _pagePulseras = [];
  List<Map<String, dynamic>> _allPulseras = [];
  bool _cargandoRegistros = false;
  String _searchQuery = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Force rebuild to update theme colors
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadPulseras(1, refreshAll: true);
    _imeiController.addListener(_onImeiChanged);
  }

  @override
  void dispose() {
    _imeiController.removeListener(_onImeiChanged);
    _imeiController.dispose();
    _bateriaController.dispose();
    _simController.dispose();
    _imeiQrController.dispose();
    _simQrController.dispose();
    _btController.dispose();
    _imei2Controller.dispose();
    super.dispose();
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

  Future<void> _loadData() async {
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
      ).showSnackBar(SnackBar(content: Text('Error cargando datos: $e')));
    }
  }

  void _onSearchQueryChanged(String query) {
    final normalized = query.trim();
    if (normalized == _searchQuery) return;
    setState(() {
      _searchQuery = normalized;
      _paginaActual = 1;
    });
    _loadPulseras(1);
  }

  // Carga una página de pulseras desde el servidor
  Future<void> _loadPulseras(int page, {bool refreshAll = false}) async {
    setState(() => _cargandoRegistros = true);
    try {
      final result = await IgualdadApi.getUltimasPulseras(
        page: page,
        perPage: _porPagina,
        query: _searchQuery.isEmpty ? null : _searchQuery,
      );
      if (!mounted) return;
      final pageData = List<Map<String, dynamic>>.from(result['data'] as List);
      final int total = (result['total'] as int?) ?? pageData.length;
      setState(() {
        _pagePulseras = pageData;
        _totalItems = total;
        _paginaActual = page;
      });
      final int expectedCache =
          math.min(total, _maxBusquedaPulseras).toInt();
      final bool necesitaAll = refreshAll ||
          _allPulseras.isEmpty ||
          _allPulseras.length != expectedCache;
      if (necesitaAll && _searchQuery.isEmpty) {
        await _cargarPulserasParaBusqueda(expectedCache);
      } else if (page == 1 && _allPulseras.isNotEmpty && _searchQuery.isEmpty) {
        setState(() {
          _allPulseras = [
            ...pageData,
            ..._allPulseras.skip(pageData.length),
          ];
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cargando pulseras: $e')));
    } finally {
      if (mounted) setState(() => _cargandoRegistros = false);
    }
  }

  Future<void> _cargarPulserasParaBusqueda(int desiredSize) async {
    final int perPageAll = (desiredSize > 0 ? desiredSize : _porPagina)
        .clamp(1, _maxBusquedaPulseras)
        .toInt();
    if (perPageAll <= 0) {
      if (!mounted) return;
      setState(() => _allPulseras = []);
      return;
    }
    try {
      final allResult = await IgualdadApi.getUltimasPulseras(
        page: 1,
        perPage: perPageAll,
      );
      if (!mounted) return;
      setState(() {
        _allPulseras = List<Map<String, dynamic>>.from(
          allResult['data'] as List,
        );
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error actualizando pulseras para búsqueda: $e');
    }
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

  Future<void> _registrarPulseraIrrecuperable() async {
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
      'tipo_dispositivo': 'PULSERA',
      'registro_id': int.parse(_registroSeleccionado!),
      'registro_tipo': _tipoRegistroSeleccionado,
      'sim': simVal,
      'imei1': imei1Val,
      'imei2': imei2Val,
      'bt': btVal,
    };
    try {
      setState(() => _registrandoIrrecuperable = true);
      await IgualdadApi.registrarIrrecuperableDispositivo(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pulsera registrada como irrecuperable')),
      );
      setState(() {
        _lookupResult = null;
        _lookupError = null;
        _lastLookupImei = null;
        _imeiController.clear();
        _imei2Controller.clear();
        _simController.clear();
        _imeiQrController.clear();
        _simQrController.clear();
        _btController.clear();
        _bateriaController.clear();
        for (final k in _radioValues.keys) {
          _radioValues[k] = null;
        }
      });
      await _loadData();
      setState(() => _paginaActual = 1);
      await _loadPulseras(1, refreshAll: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al registrar irrecuperable: $e')),
      );
    } finally {
      if (mounted) setState(() => _registrandoIrrecuperable = false);
    }
  }

  Future<void> _registrarPulsera() async {
    if (_registroSeleccionado == null || _tipoRegistroSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Selecciona IDIM u OYSTA correctamente.")),
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
      "imei": _imeiController.text.trim(),
      "registro_id": int.parse(_registroSeleccionado!),
      "registro_tipo": _tipoRegistroSeleccionado,
      "porcentaje_bateria": _bateriaController.text.trim(),
      "danos_fisicos": _radioValues['danos_fisicos'],
      "empareja_pulsera_boton": _radioValues['empareja_pulsera_boton'],
      "sin_alertas": _radioValues['sin_alertas'],
      "chequeo_abierta": _radioValues['chequeo_abierta'],
      "serigrafia": _radioValues['serigrafia'],
      "tornilleria": _radioValues['tornilleria'],
      'sim': simVal,
      'imei1': imei1Val,
      'imei2': imei2Val,
      'bt': btVal,
    };
    try {
      setState(() => _registrando = true);
      await IgualdadApi.registrarPulsera(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Pulsera registrada")));
      setState(() {
        _lookupResult = null;
        _lookupError = null;
        _lastLookupImei = null;
        _imeiController.clear();
        _imei2Controller.clear();
        _simController.clear();
        _imeiQrController.clear();
        _simQrController.clear();
        _btController.clear();
        _bateriaController.clear();
        for (final k in _radioValues.keys) {
          _radioValues[k] = null;
        }
      });
      await _loadData();
      setState(() => _paginaActual = 1);
      await _loadPulseras(1, refreshAll: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al registrar: $e')));
    } finally {
      if (mounted) {
        setState(() => _registrando = false);
      }
    }
  }

  Future<void> _eliminarPulsera(int id) async {
    try {
      await IgualdadApi.deletePulsera(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pulsera eliminada')));
      // Actualizar stock y lista de pulseras después de eliminar
    await _loadData();
    await _loadPulseras(_paginaActual, refreshAll: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
    }
  }

  Future<void> _editarPulsera(int id, Map<String, dynamic> antiguosDatos) async {
    final Map<String, dynamic>? nuevosDatos = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => DialogoEditarPulsera(datos: antiguosDatos),
    );

    if (nuevosDatos == null) return;

    try {
      await IgualdadApi.updatePulsera(id, nuevosDatos);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pulsera actualizada')));
      await _loadData();
      await _loadPulseras(_paginaActual, refreshAll: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al actualizar: $e')));
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
                      // ── Header row ──────────────────────────────────────────
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
                              color: const Color(0xFF6B2B8F).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.watch_rounded,
                              color: Color(0xFF9C27B0),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Registro de Pulseras',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Text(
                                'Control de estado y stock',
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
                              _loadPulseras(1, refreshAll: true);
                            },
                            tooltip: 'Actualizar',
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Main content ─────────────────────────────────────────
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withValues(alpha: 0.18),
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
          const Positioned(left: 0, top: 0, bottom: 0, child: Align(alignment: Alignment.centerLeft, child: EdgeNavHandle())),
        ],
      ),
    );
  }

  Widget _buildFormulario() {
    return FormularioPulseraNew(
      imeiController: _imeiController,
      bateriaController: _bateriaController,
      simController: _simController,
      imeiQrController: _imeiQrController,
      simQrController: _simQrController,
      btController: _btController,
      imei2Controller: _imei2Controller,
      opcionesRegistro: _opcionesRegistro,
      tipoRegistroSeleccionado: _tipoRegistroSeleccionado,
      registroSeleccionado: _registroSeleccionado,
      radioValues: _radioValues,
      onChangeRegistro: (t, id) {
        setState(() {
          _tipoRegistroSeleccionado = t;
          _registroSeleccionado = id;
        });
      },
      onChangeRadio: (k, v) => setState(() => _radioValues[k] = v),
      onRegistrar: _registrarPulsera,
      onRegistrarIrrecuperable: _registrarPulseraIrrecuperable,
      isSubmitting: _registrando,
      isSubmittingIrrecuperable: _registrandoIrrecuperable,
      isLookupInProgress: _lookupLoading,
      lookupResult: _lookupResult,
      lookupError: _lookupError,
      lookupImeiSearched: _lastLookupImei,
    );
  }

  Widget _buildTabla() {
    return TablaPulseras(
      registros: _pagePulseras,
      allRegistros: _allPulseras,
      paginaActual: _paginaActual,
      totalItems: _totalItems,
      registrosPorPagina: _porPagina,
      searchQuery: _searchQuery,
      isLoading: _cargandoRegistros,
      onSearchChanged: _onSearchQueryChanged,
      onPrevPage: _paginaActual > 1
          ? () => _loadPulseras(_paginaActual - 1)
          : null,
      onNextPage:
          _paginaActual * _porPagina < _totalItems
          ? () => _loadPulseras(_paginaActual + 1)
          : null,
      onEliminar: _eliminarPulsera,
      onEditar: _editarPulsera,
      onPageChanged: (page) => _loadPulseras(page),
    );
  }
}
