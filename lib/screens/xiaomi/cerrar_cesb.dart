import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';

class CerrarCesbScreen extends StatefulWidget {
  const CerrarCesbScreen({super.key});

  @override
  State<CerrarCesbScreen> createState() => _CerrarCesbScreenState();
}

class _CerrarCesbScreenState extends State<CerrarCesbScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _cesbController = TextEditingController();

  final FocusNode _cesbFocus = FocusNode();

  List<Map<String, dynamic>> _empleados = [];
  Map<String, dynamic>? _selectedEmployee;
  bool _loadingEmpleados = false;

  bool _submitting = false;
  OverlayEntry? _edgeOverlay;
  TextEditingController? _employeeSearchController;

  @override
  void dispose() {
    _cesbController.dispose();
    _cesbFocus.dispose();
    _edgeOverlay?.remove();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargarEmpleados();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final routeName = ModalRoute.of(context)?.settings.name;
      final overlay = Overlay.of(context, rootOverlay: true);
      _edgeOverlay = OverlayEntry(
        builder: (ctx) {
          return Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: EdgeNavHandle(
                  user: Provider.of<ApiService>(ctx, listen: false).currentUser,
                  width: 32,
                  currentRoute: routeName,
                  showIndicator: true,
                ),
              ),
            ),
          );
        },
      );
      overlay.insert(_edgeOverlay!);
    });
  }

  Future<void> _cargarEmpleados() async {
    setState(() => _loadingEmpleados = true);
    try {
      final api = ApiService.instance?.client;
      if (api != null) {
        final res = await api.get('/empleados/');
        if (res.ok && res.body is List) {
          setState(() {
            _empleados = List<Map<String, dynamic>>.from(res.body);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading employees: $e');
    } finally {
      if (mounted) setState(() => _loadingEmpleados = false);
    }
  }

  Future<void> _confirmAndSend() async {
    if (!_formKey.currentState!.validate()) return;
    final cesb = _cesbController.text.trim();
    // final fecha = _fechaController.text.trim(); // Removed

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar'),
        content: Text('¿Quieres cerrar el CESB "$cesb"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    setState(() => _submitting = true);
    try {
      final api = ApiService.instance?.client;
      if (api == null) throw Exception('API client not available');

      final payload = <String, dynamic>{'cesb': cesb};
      if (_selectedEmployee != null) {
        payload['operario'] =
            _selectedEmployee!['usuario'] ?? _selectedEmployee!['username'];
      }

      final resp = await api.post('/xiaomieco/cerrar_cesb', jsonBody: payload);
      debugPrint(
        'cerrar_cesb -> status: ${resp.statusCode}, ok: ${resp.ok}, body: ${resp.body}',
      );

      if (!mounted) return;

      if (resp.ok) {
        final body = resp.body;
        if (body is Map &&
            body['updated'] is List &&
            (body['updated'] as List).isNotEmpty) {
          final count = (body['updated'] as List).length;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('CESB cerrado. Filas actualizadas: $count')),
          );
          _cesbController.clear();
          _employeeSearchController?.clear();
          setState(() {
            _selectedEmployee = null;
          });
          _cesbFocus.requestFocus();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se encontraron filas para el CESB indicado.'),
            ),
          );
        }
      } else {
        final err = resp.body ?? resp.error ?? 'HTTP ${resp.statusCode}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error del servidor: $err')));
      }
    } catch (e, st) {
      debugPrint('Error cerrar_cesb: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al enviar: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cerrar CESB'),
        automaticallyImplyLeading: false,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primaryContainer.withOpacity(0.6),
                  theme.scaffoldBackgroundColor,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _cesbController,
                                focusNode: _cesbFocus,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'CESB',
                                  hintText: 'Ingrese CESB',
                                ),
                                validator: (v) {
                                  final s = v?.trim() ?? '';
                                  if (s.isEmpty) return 'Introduce CESB';
                                  return null;
                                },
                                onFieldSubmitted: (_) {},
                              ),
                              const SizedBox(height: 12),
                              const SizedBox(height: 12),
                              if (_loadingEmpleados)
                                const CircularProgressIndicator()
                              else
                                Autocomplete<Map<String, dynamic>>(
                                  displayStringForOption: (option) =>
                                      '${option['nombre']} ${option['apellido']} (#${option['id']} - ${option['usuario'] ?? 'N/A'})',
                                  optionsBuilder: (textEditingValue) {
                                    if (textEditingValue.text.isEmpty) {
                                      return const Iterable<
                                        Map<String, dynamic>
                                      >.empty();
                                    }
                                    final query = textEditingValue.text
                                        .toLowerCase();
                                    return _empleados.where((emp) {
                                      final fullName =
                                          '${emp['nombre']} ${emp['apellido']}'
                                              .toLowerCase();
                                      final searchStr =
                                          '$fullName ${emp['id']} ${emp['usuario'] ?? ''}'
                                              .toLowerCase();
                                      return searchStr.contains(query);
                                    });
                                  },
                                  onSelected: (selection) {
                                    setState(() {
                                      _selectedEmployee = selection;
                                    });
                                  },
                                  fieldViewBuilder:
                                      (
                                        context,
                                        textEditingController,
                                        focusNode,
                                        onFieldSubmitted,
                                      ) {
                                        _employeeSearchController =
                                            textEditingController;
                                        return TextFormField(
                                          controller: textEditingController,
                                          focusNode: focusNode,
                                          decoration: InputDecoration(
                                            labelText:
                                                'Asignar a empleado (Buscar)',
                                            prefixIcon: const Icon(
                                              Icons.person_search,
                                            ),
                                            suffixIcon:
                                                _selectedEmployee != null
                                                ? const Icon(
                                                    Icons.check_circle,
                                                    color: Colors.green,
                                                  )
                                                : null,
                                          ),
                                          validator: (val) {
                                            if (_selectedEmployee == null &&
                                                (val == null || val.isEmpty)) {
                                              // Optional? User didn't specify strict requirement,
                                              // but "automatically make the username assigned" suggests it's key.
                                              // I'll make it optional for now unless told otherwise,
                                              // but actually if they search they probably want to assign.
                                              // If the text is empty and no selection, fine.
                                              // If text is not empty but no selection (didn't pick from list), warn?
                                              // Let's assume optional if they don't type anything.
                                              return null;
                                            }
                                            if (val != null &&
                                                val.isNotEmpty &&
                                                _selectedEmployee == null) {
                                              return 'Selecciona un empleado de la lista';
                                            }
                                            return null;
                                          },
                                        );
                                      },
                                ),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: _submitting
                                        ? null
                                        : () {
                                            _cesbController.clear();
                                            _employeeSearchController?.clear();
                                            setState(
                                              () => _selectedEmployee = null,
                                            );
                                            _cesbFocus.requestFocus();
                                          },
                                    child: const Text('Limpiar'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _submitting
                                        ? null
                                        : _confirmAndSend,
                                    child: _submitting
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Cerrar CESB'),
                                  ),
                                ],
                              ),
                            ],
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
    );
  }
}
