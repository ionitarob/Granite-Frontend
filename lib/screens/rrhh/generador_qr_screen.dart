import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config.dart';
import '../../widgets/animated_background.dart';

const String baseUrl = kBackendBaseUrl;

class GeneradorQRScreen extends StatefulWidget {
  const GeneradorQRScreen({super.key});

  @override
  State<GeneradorQRScreen> createState() => _GeneradorQRScreenState();
}

class _GeneradorQRScreenState extends State<GeneradorQRScreen> {
  final TextEditingController _buscador = TextEditingController();

  List<Map<String, dynamic>> _empleados = [];
  List<Map<String, dynamic>> _resultados = [];
  Map<String, dynamic>? _empleadoSel;
  String? _qrBase64;
  String? _qrMensaje;
  String? _error;
  bool _cargando = true;
  bool _generando = false;

  @override
  void initState() {
    super.initState();
    _cargarEmpleados();
    _buscador.addListener(() => _filtrar(_buscador.text));
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _cargarEmpleados() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/empleados'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List<dynamic>;
        if (!mounted) return;
        setState(() {
          _empleados = data.cast<Map<String, dynamic>>();
          _resultados = _empleados;
          _cargando = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _error = 'Error al cargar empleados';
          _cargando = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error de conexión al cargar empleados';
        _cargando = false;
      });
    }
  }

  void _filtrar(String texto) {
    setState(() {
      _resultados = _empleados.where((e) {
        final nombreCompleto = "${e['nombre']} ${e['apellido']}".toLowerCase();
        return nombreCompleto.contains(texto.toLowerCase());
      }).toList();
    });
  }

  Future<void> _generarQR() async {
    if (_empleadoSel == null) return;

    final id = _empleadoSel!['id'];
    setState(() {
      _generando = true;
      _qrMensaje = null;
    });

    try {
      http.Response res = await http.get(Uri.parse('$baseUrl/qr_empleado/$id'));

      if (res.statusCode == 404) {
        res = await http.post(Uri.parse('$baseUrl/generar_qr/$id'));
      }

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (!mounted) return;
        setState(() {
          _qrBase64 = data['qr_base64'] as String?;
          _qrMensaje = null;
          _generando = false;
        });
      } else {
        throw Exception('HTTP ${res.statusCode}');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _qrBase64 = null;
        _qrMensaje = 'No se pudo generar el código QR';
        _generando = false;
      });
    }
  }

  Future<void> _imprimirBarTender() async {
    if (_empleadoSel == null) return;

    final id = _empleadoSel!['id'];

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/empleado/$id/imprimir_etiqueta_empleado'),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          _showSnack('Etiqueta enviada a BarTender');
        } else {
          _showSnack('Error: ${data['error'] ?? "Fallo al imprimir"}');
        }
      } else {
        _showSnack('Error HTTP ${res.statusCode}');
      }
    } catch (e) {
      _showSnack('Error de red: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Generador de QR'),
        backgroundColor: Colors.black.withValues(alpha: .15),
        elevation: 0,
      ),
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 1.05),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isVertical = constraints.maxWidth < 900;
                final previewWidth = isVertical
                    ? constraints.maxWidth
                    : constraints.maxWidth * 0.35;

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: isVertical
                      ? Column(
                          children: [
                            _buildSearchCard(theme),
                            const SizedBox(height: 16),
                            Expanded(child: _buildListCard(theme)),
                            const SizedBox(height: 16),
                            _buildPreviewCard(theme, previewWidth),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  _buildSearchCard(theme),
                                  const SizedBox(height: 16),
                                  Expanded(child: _buildListCard(theme)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: previewWidth.clamp(320.0, 460.0),
                              child: _buildPreviewCard(theme, previewWidth),
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

  Widget _buildSearchCard(ThemeData theme) {
    return _glass(
      theme,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selecciona un empleado',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _buscador,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o apellido',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white.withValues(alpha: .9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: .2)),
              ),
            ),
            onChanged: _filtrar,
          ),
        ],
      ),
    );
  }

  Widget _buildListCard(ThemeData theme) {
    if (_cargando) {
      return _glass(
        theme,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _glass(
        theme,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              onPressed: _cargarEmpleados,
            ),
          ],
        ),
      );
    }
    if (_resultados.isEmpty) {
      return _glass(
        theme,
        child: const Center(child: Text('No hay resultados para mostrar.')),
      );
    }
    return _glass(
      theme,
      child: ListView.separated(
        itemCount: _resultados.length,
        separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: .2)),
        itemBuilder: (context, index) {
          final emp = _resultados[index];
          return ListTile(
            title: Text('${emp['nombre']} ${emp['apellido']}'),
            subtitle: Text(emp['usuario']?.toString() ?? ''),
            trailing: IconButton(
              icon: const Icon(Icons.qr_code_2),
              onPressed: () {
                setState(() {
                  _empleadoSel = emp;
                  _qrBase64 = null;
                  _qrMensaje = 'Generando código...';
                });
                _generarQR();
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildPreviewCard(ThemeData theme, double width) {
    return _glass(
      theme,
      padding: const EdgeInsets.all(24),
      child: _empleadoSel == null
          ? const Center(
              child: Text('Selecciona un empleado para ver su QR'),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_empleadoSel!['nombre']} ${_empleadoSel!['apellido']}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                if (_qrBase64 != null)
                  Container(
                    width: width.clamp(180.0, 320.0),
                    height: width.clamp(180.0, 320.0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .12),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: Image.memory(base64Decode(_qrBase64!)),
                  )
                else if (_generando)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      _qrMensaje ?? 'Genera el QR para este empleado',
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.print),
                  label: const Text('Imprimir etiqueta'),
                  onPressed: _qrBase64 == null ? null : _imprimirBarTender,
                ),
              ],
            ),
    );
  }

  Widget _glass(
    ThemeData theme, {
    Widget? child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: theme.cardColor.withValues(alpha: .85),
            border: Border.all(color: Colors.white.withValues(alpha: .15)),
          ),
          child: child,
        ),
      ),
    );
  }
}
