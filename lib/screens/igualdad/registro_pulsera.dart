import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:configtool_granite_frontend/src/api/igualdad_api.dart';
import 'formulario_pulsera_new.dart';
import 'resumen_stock.dart';
import 'tablapulseras.dart';
import '../../widgets/main_sidebar.dart';

class RegistroPulseraScreen extends StatefulWidget {
  const RegistroPulseraScreen({super.key});

  @override
  State<RegistroPulseraScreen> createState() => _RegistroPulseraScreenState();
}

class _RegistroPulseraScreenState extends State<RegistroPulseraScreen> {
  // ─── Fondo animado ──────────────────────────────────────────────────────
  // ─── Fondo animado ──────────────────────────────────────────────────────
  List<List<Color>> get _gradients => [
    [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.secondary,
    ],
    [
      Theme.of(context).colorScheme.secondary,
      Theme.of(context).colorScheme.tertiary,
    ],
    [
      Theme.of(context).colorScheme.tertiary,
      Theme.of(context).colorScheme.primary,
    ],
  ];
  int _currentGradient = 0;
  Timer? _timer;

  // ─── Formulario ────────────────────────────────────────────────────────
  final _imeiController = TextEditingController();
  final _bateriaController = TextEditingController();
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
  };
  bool _registrando = false;
  bool _lookupLoading = false;
  String? _lookupError;
  Map<String, dynamic>? _lookupResult;
  String? _lastLookupImei;
  int _lookupRequestId = 0;

  // ─── Stock / Resumen ──────────────────────────────────────────────────
  Map<String, int>? stockReal;
  Map<String, int>? idimActivoVals;
  Map<String, int>? oystaActivoVals;
  String? idimCodigo;
  String? oystaCodigo;

  // ─── Paginación ───────────────────────────────────────────────────────
  int _paginaActual = 1;
  static const int _porPagina = 10;
  static const int _maxBusquedaPulseras = 500;
  int _totalItems = 0;
  List<Map<String, dynamic>> _pagePulseras = [];
  List<Map<String, dynamic>> _allPulseras = [];

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
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      setState(() {
        _currentGradient = (_currentGradient + 1) % _gradients.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _imeiController.removeListener(_onImeiChanged);
    _imeiController.dispose();
    _bateriaController.dispose();
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
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cargando datos: $e')));
    }
  }

  // Carga una página de pulseras desde el servidor
  Future<void> _loadPulseras(int page, {bool refreshAll = false}) async {
    try {
      final result = await IgualdadApi.getUltimasPulseras(
        page: page,
        perPage: _porPagina,
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
      if (necesitaAll) {
        await _cargarPulserasParaBusqueda(expectedCache);
      } else if (page == 1 && _allPulseras.isNotEmpty) {
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

  Future<void> _registrarPulsera() async {
    if (_registroSeleccionado == null || _tipoRegistroSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Selecciona IDIM u OYSTA correctamente.")),
      );
      return;
    }
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

  Future<void> _editarPulsera(int id, Map<String, dynamic> nuevosDatos) async {
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
    final gradient = _gradients[_currentGradient];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedContainer(
            duration: const Duration(seconds: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Volver
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withOpacity(0.2),
                        child: IconButton(
                          icon: Icon(
                            Icons.arrow_back,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Panel glass
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FormularioPulseraNew(
                                  imeiController: _imeiController,
                                  bateriaController: _bateriaController,
                                  opcionesRegistro: _opcionesRegistro,
                                  tipoRegistroSeleccionado:
                                      _tipoRegistroSeleccionado,
                                  registroSeleccionado: _registroSeleccionado,
                                  radioValues: _radioValues,
                                  onChangeRegistro: (t, id) {
                                    setState(() {
                                      _tipoRegistroSeleccionado = t;
                                      _registroSeleccionado = id;
                                    });
                                  },
                                  onChangeRadio: (k, v) =>
                                      setState(() => _radioValues[k] = v),
                                  onRegistrar: _registrarPulsera,
                                  isSubmitting: _registrando,
                                  isLookupInProgress: _lookupLoading,
                                  lookupResult: _lookupResult,
                                  lookupError: _lookupError,
                                  lookupImeiSearched: _lastLookupImei,
                                ),

                                const SizedBox(height: 24),
                                ResumenStock(
                                  stockReal: stockReal,
                                  idimActivoVals: idimActivoVals,
                                  oystaActivoVals: oystaActivoVals,
                                  idimCodigo: idimCodigo,
                                  oystaCodigo: oystaCodigo,
                                ),

                                const SizedBox(height: 24),
                                TablaPulseras(
                                  registros: _pagePulseras,
                                  allRegistros: _allPulseras,
                                  paginaActual: _paginaActual,
                                  totalItems: _totalItems,
                                  registrosPorPagina: _porPagina,
                                  onPrevPage: _paginaActual > 1
                                      ? () => _loadPulseras(_paginaActual - 1)
                                      : null,
                                  onNextPage:
                                      _paginaActual * _porPagina < _totalItems
                                      ? () => _loadPulseras(_paginaActual + 1)
                                      : null,
                                  onEliminar: _eliminarPulsera,
                                  onEditar: _editarPulsera,
                                  onPageChanged: (p) => _loadPulseras(p),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(top: 12, left: 6, child: const EdgeNavHandle()),
        ],
      ),
    );
  }
}
