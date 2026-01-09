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
  final TextEditingController _fechaController = TextEditingController();
  final FocusNode _cesbFocus = FocusNode();

  bool _submitting = false;
  OverlayEntry? _edgeOverlay;

  @override
  void dispose() {
    _cesbController.dispose();
    _fechaController.dispose();
    _cesbFocus.dispose();
    _edgeOverlay?.remove();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
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
                  width: 28,
                  currentRoute: routeName,
                ),
              ),
            ),
          );
        },
      );
      overlay.insert(_edgeOverlay!);
    });
  }

  Future<void> _confirmAndSend() async {
    if (!_formKey.currentState!.validate()) return;
    final cesb = _cesbController.text.trim();
    final fecha = _fechaController.text.trim();

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
      if (fecha.isNotEmpty) payload['fecha_hora_fin'] = fecha;

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
          _fechaController.clear();
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
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: Padding(
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
                          TextFormField(
                            controller: _fechaController,
                            decoration: const InputDecoration(
                              labelText: 'Fecha/Hora (opcional)',
                              hintText: "YYYY-MM-DD HH:MM:SS (opcional)",
                            ),
                            keyboardType: TextInputType.datetime,
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
                                        _fechaController.clear();
                                      },
                                child: const Text('Limpiar'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _submitting ? null : _confirmAndSend,
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
    );
  }
}
