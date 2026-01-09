import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../config.dart';
import '../../widgets/main_sidebar.dart';

const String baseUrl = kBackendBaseUrl;

class FichajeScreen extends StatefulWidget {
  const FichajeScreen({super.key});

  @override
  State<FichajeScreen> createState() => _FichajeScreenState();
}

class _FichajeScreenState extends State<FichajeScreen>
    with SingleTickerProviderStateMixin {
  String mensaje = "";
  Color fondoColor = Colors.transparent;
  final TextEditingController manualIdController = TextEditingController();
  final FocusNode focusNode = FocusNode();
  bool fichando = false;
  final Map<int, DateTime> _ultimosFichajesPorEmpleado = {};
  late AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusNode.requestFocus();
      _setStatusBarColor(Colors.transparent);
    });
  }

  @override
  void dispose() {
    manualIdController.dispose();
    focusNode.dispose();
    _bgController.dispose();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    super.dispose();
  }

  Future<void> _ficharEmpleado(int empleadoId) async {
    final ahora = DateTime.now();
    if (_ultimosFichajesPorEmpleado.containsKey(empleadoId)) {
      final ultima = _ultimosFichajesPorEmpleado[empleadoId]!;
      final diff = ahora.difference(ultima).inSeconds;
      if (diff < 5) {
        final restante = 5 - diff;
        return _mostrarMensaje(
          "⏳ Espera $restante s antes de fichar de nuevo.",
          tipo: _MsgTipo.info,
        );
      }
    }
    if (fichando) return;
    fichando = true;

    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/fichajes/fichar'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'empleado_id': empleadoId}),
      );
      if (!mounted) return;
      final data = json.decode(resp.body);
      if (resp.statusCode == 200) {
        final nombre = data['nombre'] ?? 'Empleado';
        final tipo = data['tipo'] ?? '';
        _ultimosFichajesPorEmpleado[empleadoId] = DateTime.now();
        if (tipo == 'entrada') {
          _mostrarMensaje(
            "✅ $nombre ha registrado una entrada.",
            tipo: _MsgTipo.success,
          );
        } else if (tipo == 'salida') {
          _mostrarMensaje(
            "✅ $nombre ha registrado una salida.",
            tipo: _MsgTipo.exit,
          );
        } else {
          _mostrarMensaje(
            "✅ $nombre ha fichado correctamente.",
            tipo: _MsgTipo.success,
          );
        }
      } else {
        _mostrarMensaje(
          data['error'] ?? "Error inesperado",
          tipo: _MsgTipo.error,
        );
      }
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje("Error de red o servidor", tipo: _MsgTipo.error);
    }

    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      fondoColor = Colors.transparent;
      mensaje = "";
    });
    manualIdController.clear();
    focusNode.requestFocus();
    fichando = false;
  }

  void _mostrarMensaje(String msg, {required _MsgTipo tipo}) {
    Color col;
    switch (tipo) {
      case _MsgTipo.success:
        col = Colors.green.shade400;
        break;
      case _MsgTipo.exit:
        col = Colors.orange.shade400;
        break;
      case _MsgTipo.error:
        col = Colors.red.shade400;
        break;
      default:
        col = Colors.blue.shade400;
    }
    setState(() {
      mensaje = msg;
      // Colorea toda la pantalla con el color correspondiente
      fondoColor = col;
    });
    _setStatusBarColor(col);
  }

  void _setStatusBarColor(Color c) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: c,
        statusBarIconBrightness: c.computeLuminance() > 0.5
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarColor: c,
        systemNavigationBarIconBrightness: c.computeLuminance() > 0.5
            ? Brightness.dark
            : Brightness.light,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bgController,
      builder: (_, __) {
        final t = _bgController.value;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(
                        Theme.of(context).colorScheme.surface,
                        Theme.of(context).colorScheme.primaryContainer,
                        t,
                      )!,
                      Color.lerp(
                        Theme.of(context).colorScheme.surface,
                        Theme.of(context).colorScheme.secondaryContainer,
                        1 - t,
                      )!,
                    ],
                  ),
                ),
              ),
              // Capa de color para cubrir toda la pantalla en eventos de fichaje/errores
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                color: fondoColor,
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: EdgeNavHandle(width: 28),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _BackButtonPro(),
                ),
              ),
              Center(
                child: GlassCard(
                  blur: 18,
                  color: Theme.of(context).cardColor.withValues(alpha: .8),
                  borderRadius: BorderRadius.circular(24),
                  elevation: 14,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Introduce ID de empleado:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: manualIdController,
                          focusNode: focusNode,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'ID',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.badge_outlined),
                          ),
                          onSubmitted: (v) {
                            final id = int.tryParse(v.trim());
                            if (id != null) {
                              _ficharEmpleado(id);
                            } else {
                              _mostrarMensaje(
                                "ID inválido",
                                tipo: _MsgTipo.error,
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              final id = int.tryParse(manualIdController.text);
                              if (id != null) {
                                _ficharEmpleado(id);
                              } else {
                                _mostrarMensaje(
                                  "ID inválido",
                                  tipo: _MsgTipo.error,
                                );
                              }
                            },
                            child: Text(
                              'Fichar',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (mensaje.isNotEmpty)
                          BadgeMensaje(mensaje: mensaje, tipo: fondoColor),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class BadgeMensaje extends StatelessWidget {
  final String mensaje;
  final Color tipo;
  const BadgeMensaje({super.key, required this.mensaje, required this.tipo});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tipo.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tipo.withValues(alpha: .6)),
      ),
      child: Text(
        mensaje,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final double blur;
  final Color color;
  final BorderRadius borderRadius;
  final double elevation;

  const GlassCard({
    super.key,
    required this.child,
    this.blur = 10,
    this.color = Colors.white54,
    this.borderRadius = BorderRadius.zero,
    this.elevation = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      elevation: elevation,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: borderRadius,
              border: Border.all(color: Colors.white.withValues(alpha: .15)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

enum _MsgTipo { success, exit, error, info }

class _BackButtonPro extends StatefulWidget {
  @override
  State<_BackButtonPro> createState() => _BackButtonProState();
}

class _BackButtonProState extends State<_BackButtonPro>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      lowerBound: 0.9,
      upperBound: 1.0,
    );
    _anim = _ctrl.drive(CurveTween(curve: Curves.easeOut));
    _ctrl.value = 1.0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    await _ctrl.reverse();
    await _ctrl.forward();
    if (!mounted) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _anim,
      child: InkWell(
        onTap: _tap,
        borderRadius: BorderRadius.circular(40),
        splashColor: Colors.white24,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back_ios, size: 20),
        ),
      ),
    );
  }
}
