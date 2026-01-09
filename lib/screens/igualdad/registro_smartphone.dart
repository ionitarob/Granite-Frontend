import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:configtool_granite_frontend/src/api/igualdad_api.dart';
import '../../../models/paged_response.dart';
import '../../../models/smartphone.dart';

import 'formulario_smartphone_new.dart';
import 'resumen_stock.dart';
import 'tabla_registros.dart';
import '../../widgets/main_sidebar.dart';

class RegistroSmartphoneScreen extends StatefulWidget {
  const RegistroSmartphoneScreen({super.key});

  @override
  State<RegistroSmartphoneScreen> createState() =>
      _RegistroSmartphoneScreenState();
}

class _RegistroSmartphoneScreenState extends State<RegistroSmartphoneScreen> {
  // Background gradient animation
  // Background gradient animation
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

  // Pagination state
  int _paginaActual = 1;
  static const int _registrosPorPagina = 10;
  int _totalItems = 0;

  // Controllers & other state
  final TextEditingController _imeiController = TextEditingController();
  final TextEditingController _bateriaController = TextEditingController();
  final TextEditingController _cometaController = TextEditingController();

  Map<String, dynamic>? _opcionesRegistro;
  String? _registroSeleccionado;
  String? _tipoRegistroSeleccionado;
  String? _tipoSmartphone = 'AGRESOR';
  final Map<String, String?> _radioValues = {
    'remaquetado': null,
    'danos_fisicos': null,
    'empareja_pulsera_boton': null,
    'solapa_cargador': null,
    'sonido': null,
  };
  bool _registrando = false;
  bool _lookupLoading = false;
  String? _lookupError;
  Map<String, dynamic>? _lookupResult;
  String? _lastLookupImei;
  int _lookupRequestId = 0;

  List<Map<String, dynamic>> ultimosRegistros = [];
  bool _cargandoRegistros = false;
  String _searchQuery = '';
  Map<String, int>? stockReal;
  Map<String, int>? idimActivoVals;
  Map<String, int>? oystaActivoVals;
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
    // Start gradient animation
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      setState(() {
        _currentGradient = (_currentGradient + 1) % _gradients.length;
      });
    });
    _imeiController.addListener(_onImeiChanged);
    _cargarRegistroActivo();
  _cargarUltimosRegistros();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _imeiController.removeListener(_onImeiChanged);
    _imeiController.dispose();
    _bateriaController.dispose();
    _cometaController.dispose();
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

  Future<void> _registrarSmartphone() async {
    if (_registroSeleccionado == null || _tipoRegistroSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona IDIM u OYSTA correctamente.')),
      );
      return;
    }
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
    Map<String, dynamic> nuevosDatos,
  ) async {
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
    final gradient = _gradients[_currentGradient];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo degradado animado
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

          // Contenido glass
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Flecha atrás
                          Align(
                            alignment: Alignment.topLeft,
                            child: IconButton(
                              icon: Icon(
                                Icons.arrow_back,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              tooltip: 'Volver',
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Formulario
                          FormularioSmartphoneNew(
                            imeiController: _imeiController,
                            bateriaController: _bateriaController,
                            cometaController: _cometaController,
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
                            isSubmitting: _registrando,
                            isLookupInProgress: _lookupLoading,
                            lookupResult: _lookupResult,
                            lookupError: _lookupError,
                            lookupImeiSearched: _lastLookupImei,
                          ),

                          const SizedBox(height: 32),
                          Divider(color: Theme.of(context).dividerColor),
                          const SizedBox(height: 16),

                          // Resumen y tabla
                          ResumenStock(
                            stockReal: stockReal,
                            idimActivoVals: idimActivoVals,
                            oystaActivoVals: oystaActivoVals,
                            idimCodigo: idimCodigo,
                            oystaCodigo: oystaCodigo,
                          ),
                          const SizedBox(height: 16),

                          // ← PAGE BUTTONS → TABLE
                          TablaRegistros(
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
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Sidebar handle (left edge) — placed on top so it's always reachable
          Positioned(top: 12, left: 6, child: const EdgeNavHandle()),
        ],
      ),
    );
  }
}
