import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:configtool_granite_frontend/src/api/igualdad_api.dart';
import 'resumen_stock.dart';
import '../../widgets/main_sidebar.dart';

class RegistroBotonScreen extends StatefulWidget {
  const RegistroBotonScreen({super.key});

  @override
  State<RegistroBotonScreen> createState() => _RegistroBotonScreenState();
}

class _RegistroBotonScreenState extends State<RegistroBotonScreen> {
  Map<String, dynamic>? _opcionesRegistro;
  List<dynamic> _registros = [];
  String? _registroSeleccionado;
  bool _loading = true;

  // Para fondo animado
  final List<List<Color>> _gradients = [
    [Colors.deepPurple, Colors.purple], // Default fallback
  ];
  int _currentGradient = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      setState(() {
        _currentGradient = (_currentGradient + 1) % _gradients.length;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    _gradients[0] = [
      theme.colorScheme.primaryContainer,
      theme.colorScheme.secondaryContainer,
    ];
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final opciones = await IgualdadApi.getOpcionesRegistro();
      final regs = await IgualdadApi.getRegistrosBotones();
      setState(() {
        _opcionesRegistro = opciones;
        _registros = regs;
        // init dropdown
        if (_opcionesRegistro!['idim'] != null) {
          _registroSeleccionado = 'IDIM';
        } else if (_opcionesRegistro!['oysta'] != null) {
          _registroSeleccionado = 'OYSTA';
        }
      });
    } catch (e) {
      _showError('Error cargando datos: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _registrarBoton() async {
    if (_registroSeleccionado == null) return;
    try {
      await IgualdadApi.registrarBoton(_registroSeleccionado!);
      await _loadAll();
      setState(() => _registroSeleccionado = null);
    } catch (e) {
      _showError('Error al registrar botón: $e');
    }
  }

  Future<void> _eliminarRegistro(String tipo) async {
    try {
      await IgualdadApi.deleteBoton(tipo);
      await _loadAll();
    } catch (e) {
      _showError('Error al eliminar botón: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final gradient = _gradients[_currentGradient];
    final idim = _opcionesRegistro?['idim'];
    final oysta = _opcionesRegistro?['oysta'];

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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Flecha atrás
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Material(
                        color: Theme.of(context).cardColor.withOpacity(0.2),
                        child: IconButton(
                          icon: Icon(
                            Icons.arrow_back,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: 'Volver',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Glassmorphic panel
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
                            ).cardColor.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).dividerColor.withOpacity(0.3),
                            ),
                          ),
                          child: _loading
                              ? Center(
                                  child: CircularProgressIndicator(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                )
                              : SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Formulario de Registro",
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).textTheme.titleLarge?.color,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<String>(
                                        initialValue: _registroSeleccionado,
                                        decoration: InputDecoration(
                                          labelText:
                                              "Seleccionar Registro Activo",
                                          labelStyle: TextStyle(
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.color
                                                ?.withOpacity(0.7),
                                          ),
                                          filled: true,
                                          fillColor:
                                              Theme.of(context)
                                                  .inputDecorationTheme
                                                  .fillColor ??
                                              Theme.of(
                                                context,
                                              ).cardColor.withOpacity(0.5),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                        dropdownColor: Theme.of(
                                          context,
                                        ).cardColor,
                                        items: [
                                          if (idim != null)
                                            DropdownMenuItem(
                                              value: 'IDIM',
                                              child: Text(
                                                "IDIM: ${idim['codigo']}",
                                              ),
                                            ),
                                          if (oysta != null)
                                            DropdownMenuItem(
                                              value: 'OYSTA',
                                              child: Text(
                                                "OYSTA: ${oysta['codigo']}",
                                              ),
                                            ),
                                        ],
                                        onChanged: (v) => setState(
                                          () => _registroSeleccionado = v,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Center(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: BackdropFilter(
                                            filter: ImageFilter.blur(
                                              sigmaX: 15,
                                              sigmaY: 15,
                                            ),
                                            child: Material(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withOpacity(0.8),
                                              child: InkWell(
                                                onTap: _registrarBoton,
                                                splashColor: Theme.of(
                                                  context,
                                                ).splashColor,
                                                child: SizedBox(
                                                  height: 48,
                                                  width: double.infinity,
                                                  child: Center(
                                                    child: Text(
                                                      "Añadir Botón",
                                                      style: TextStyle(
                                                        color: Theme.of(
                                                          context,
                                                        ).colorScheme.onPrimary,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      Divider(
                                        color: Theme.of(context).dividerColor,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        "Resumen de Stock",
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).textTheme.titleLarge?.color,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      ResumenStock(
                                        stockReal:
                                            _opcionesRegistro?['stock']
                                                ?.cast<String, int>() ??
                                            {},
                                        idimActivoVals:
                                            _opcionesRegistro?['idim']?['valores']
                                                ?.cast<String, int>() ??
                                            {},
                                        oystaActivoVals:
                                            _opcionesRegistro?['oysta']?['valores']
                                                ?.cast<String, int>() ??
                                            {},
                                        idimCodigo: idim?['codigo'],
                                        oystaCodigo: oysta?['codigo'],
                                      ),
                                      const SizedBox(height: 24),
                                      Divider(
                                        color: Theme.of(context).dividerColor,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        "Botones Registrados",
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).textTheme.titleLarge?.color,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      ..._registros.map(
                                        (item) => Card(
                                          color: Theme.of(context).cardColor,
                                          child: ListTile(
                                            title: Text(
                                              "Botones en ${item['tipo']}: ${item['codigo']}",
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).textTheme.bodyLarge?.color,
                                              ),
                                            ),
                                            subtitle: Text(
                                              "Cantidad: ${item['cantidad']}",
                                            ),
                                            trailing: IconButton(
                                              icon: Icon(
                                                Icons.delete,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                              ),
                                              onPressed: () =>
                                                  _eliminarRegistro(
                                                    item['tipo'],
                                                  ),
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
