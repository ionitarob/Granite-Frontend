import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:configtool_granite_frontend/services/api_service.dart';
import 'package:configtool_granite_frontend/src/api/igualdad_api.dart';
import 'resumen_stock.dart';
import '../../widgets/main_sidebar.dart';

class CerrarIdimOystaScreen extends StatefulWidget {
  const CerrarIdimOystaScreen({super.key});

  @override
  State<CerrarIdimOystaScreen> createState() => _CerrarIdimOystaScreenState();
}

class _CerrarIdimOystaScreenState extends State<CerrarIdimOystaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _expedicionController = TextEditingController();
  final _jjdController = TextEditingController();

  String? _selectedTipo; // 'IDIM' o 'OYSTA'
  bool _loading = false;
  Map<String, dynamic>? _opcionesRegistro;
  bool _loadingOpciones = true;

  final List<List<Color>> _gradients = [
    [Colors.deepPurple, Colors.purple], // Default fallback
  ];
  int _currentGradient = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadOpciones();
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
    _expedicionController.dispose();
    _jjdController.dispose();
    super.dispose();
  }

  Future<void> _loadOpciones() async {
    setState(() => _loadingOpciones = true);
    try {
      final opciones = await IgualdadApi.getOpcionesRegistro();
      setState(() {
        _opcionesRegistro = opciones;
        if (_selectedTipo == null) {
          if (_opcionesRegistro?['idim'] != null) {
            _selectedTipo = 'IDIM';
          } else if (_opcionesRegistro?['oysta'] != null) {
            _selectedTipo = 'OYSTA';
          }
        }
      });
    } catch (e) {
      _showSnackBar('Error al cargar datos activos: $e', isError: true);
    } finally {
      setState(() => _loadingOpciones = false);
    }
  }

  Future<void> _submitCerrar() async {
    if (_selectedTipo == null) {
      _showSnackBar('Por favor selecciona qué quieres cerrar', isError: true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _loading = true);
    try {
      await IgualdadApi.cerrarExpedicion(
        _selectedTipo!,
        _expedicionController.text.trim(),
        _jjdController.text.trim(),
      );
      _showSnackBar('¡$_selectedTipo cerrado correctamente y nueva serie abierta!');
      _expedicionController.clear();
      _jjdController.clear();
      await _loadOpciones();
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green,
      ),
    );
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
                  // Glassmorphic panel
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: _loadingOpciones
                              ? Center(
                                  child: CircularProgressIndicator(
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                )
                              : SingleChildScrollView(
                                  child: Form(
                                    key: _formKey,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Cerrar IDIM / OYSTA",
                                          style: TextStyle(
                                            color: Theme.of(context).textTheme.titleLarge?.color,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          "Registra los datos de la expedición para cerrar el registro activo y abrir uno nuevo.",
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.color
                                                ?.withValues(alpha: 0.7),
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        DropdownButtonFormField<String>(
                                          initialValue: _selectedTipo,
                                          decoration: InputDecoration(
                                            labelText: "Selecciona qué cerrar",
                                            labelStyle: TextStyle(
                                              color: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.color
                                                  ?.withValues(alpha: 0.7),
                                            ),
                                            filled: true,
                                            fillColor: Theme.of(context)
                                                    .inputDecorationTheme
                                                    .fillColor ??
                                                Theme.of(context).cardColor.withValues(alpha: 0.5),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                          dropdownColor: Theme.of(context).cardColor,
                                          items: [
                                            if (idim != null)
                                              DropdownMenuItem(
                                                value: 'IDIM',
                                                child: Text(
                                                  "IDIM activo: ${idim['codigo']}",
                                                ),
                                              ),
                                            if (oysta != null)
                                              DropdownMenuItem(
                                                value: 'OYSTA',
                                                child: Text(
                                                  "OYSTA activo: ${oysta['codigo']}",
                                                ),
                                              ),
                                          ],
                                          onChanged: (v) => setState(
                                            () => _selectedTipo = v,
                                          ),
                                          validator: (value) =>
                                              value == null ? 'Por favor selecciona una opción' : null,
                                        ),
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          controller: _expedicionController,
                                          decoration: InputDecoration(
                                            labelText: "Número de Expedición",
                                            labelStyle: TextStyle(
                                              color: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.color
                                                  ?.withValues(alpha: 0.7),
                                            ),
                                            filled: true,
                                            fillColor: Theme.of(context)
                                                    .inputDecorationTheme
                                                    .fillColor ??
                                                Theme.of(context).cardColor.withValues(alpha: 0.5),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                          validator: (value) {
                                            if (value == null || value.trim().isEmpty) {
                                              return 'Por favor introduce el número de expedición';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          controller: _jjdController,
                                          decoration: InputDecoration(
                                            labelText: "Código JJD",
                                            labelStyle: TextStyle(
                                              color: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.color
                                                  ?.withValues(alpha: 0.7),
                                            ),
                                            filled: true,
                                            fillColor: Theme.of(context)
                                                    .inputDecorationTheme
                                                    .fillColor ??
                                                Theme.of(context).cardColor.withValues(alpha: 0.5),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                          validator: (value) {
                                            if (value == null || value.trim().isEmpty) {
                                              return 'Por favor introduce el código JJD';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 24),
                                        Center(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: BackdropFilter(
                                              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                              child: Material(
                                                color: _loading
                                                    ? Colors.grey.withValues(alpha: 0.5)
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withValues(alpha: 0.8),
                                                child: InkWell(
                                                  onTap: _loading ? null : _submitCerrar,
                                                  splashColor: Theme.of(context).splashColor,
                                                  child: SizedBox(
                                                    height: 48,
                                                    width: double.infinity,
                                                    child: Center(
                                                      child: _loading
                                                          ? const SizedBox(
                                                              height: 20,
                                                              width: 20,
                                                              child: CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                color: Colors.white,
                                                              ),
                                                            )
                                                          : Row(
                                                              mainAxisAlignment: MainAxisAlignment.center,
                                                              children: [
                                                                const Icon(
                                                                  Icons.lock,
                                                                  color: Colors.white,
                                                                  size: 20,
                                                                ),
                                                                const SizedBox(width: 8),
                                                                Text(
                                                                  "Cerrar $_selectedTipo",
                                                                  style: const TextStyle(
                                                                    color: Colors.white,
                                                                    fontWeight: FontWeight.bold,
                                                                    fontSize: 16,
                                                                  ),
                                                                ),
                                                              ],
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
                                        ResumenStock(
                                          stockReal: _opcionesRegistro?['stock']?.cast<String, int>() ?? {},
                                          idimActivoVals: _opcionesRegistro?['idim']?['valores']?.cast<String, int>() ?? {},
                                          oystaActivoVals: _opcionesRegistro?['oysta']?['valores']?.cast<String, int>() ?? {},
                                          idimCodigo: idim?['codigo'],
                                          oystaCodigo: oysta?['codigo'],
                                        ),
                                      ],
                                    ),
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
        ],
      ),
    );
  }
}
