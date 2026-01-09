import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'amz_close_box_screen.dart';
import 'amz_find_box_screen.dart';
import 'amz_find_dsn_screen.dart';

import '../../themes/amazon_theme.dart';
import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';

class SortingScreen extends StatefulWidget {
  const SortingScreen({super.key});

  @override
  _SortingScreenState createState() => _SortingScreenState();
}

class _SortingScreenState extends State<SortingScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _dsnController = TextEditingController();
  final FocusNode _bucketFocusNode = FocusNode();
  final FocusNode _dsnFocusNode = FocusNode();

  bool _isLoading = false;
  String? _message;
  String? _remainingUnits;
  String? _boxesToClose;
  bool _isError = false;

  String? _selectedBucket;
  static const List<String> _buckets = [
    'PRIME',
    'WOOT',
    'VAS',
    'RETURN',
    'RECYCLE',
    'RECYCLE DISCONTINUED',
  ];

  OverlayEntry? _edgeOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_bucketFocusNode);
      if (mounted) {
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
                    user: Provider.of<ApiService>(
                      ctx,
                      listen: false,
                    ).currentUser,
                    width: 28,
                    currentRoute: routeName,
                  ),
                ),
              ),
            );
          },
        );
        overlay.insert(_edgeOverlay!);
      }
    });
  }

  @override
  void dispose() {
    _edgeOverlay?.remove();
    _dsnController.dispose();
    _bucketFocusNode.dispose();
    _dsnFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _message = null;
      _remainingUnits = null;
      _boxesToClose = null;
      _isError = false;
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post(
        '/amz/grading/sorting',
        jsonBody: {
          'Grading_Bucket': _selectedBucket,
          'DSN_Scan': _dsnController.text.trim(),
        },
      );

      if (res.ok && res.body is Map) {
        final data = res.body as Map<String, dynamic>;
        setState(() {
          _isError = false;
          _message = data['message'] ?? 'Operación completada.';
          _remainingUnits = data['remaining_units_message'] as String?;
          _boxesToClose = data['boxes_to_close_message'] as String?;
        });
      } else {
        setState(() {
          _isError = true;
          _message = res.error ?? 'Error servidor.';
        });
      }
    } catch (e) {
      setState(() {
        _isError = true;
        _message = 'Error de red: $e';
      });
    } finally {
      setState(() => _isLoading = false);
      _dsnController.clear();
      FocusScope.of(context).requestFocus(_dsnFocusNode);
    }
  }

  void _onToolSelected(String tool) {
    Widget screen;
    switch (tool) {
      case 'Cerrar Box':
        screen = const AmzCloseBoxScreen();
        break;
      case 'Buscar Box':
        screen = const AmzFindBoxScreen();
        break;
      case 'Buscar DSN':
        screen = const AmzFindDsnScreen();
        break;
      default:
        return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Color _bucketAccent(String? bucket) {
    // Use shades of orange to keep the Amazon theme consistent
    switch (bucket) {
      case 'PRIME':
        return Colors.deepOrange.shade300;
      case 'WOOT':
        return Colors.orange.shade300;
      case 'VAS':
        return Colors.orangeAccent.shade100;
      case 'RECYCLE':
        return Colors.deepOrange.shade700;
      case 'RECYCLE DISCONTINUED':
        return Colors.deepOrange.shade900;
      case 'RETURN':
        return Colors.orange.shade600;
      default:
        return Colors.orange.shade200;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AmazonTheme(
      child: Builder(
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return Scaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              // leading: const EdgeNavHandle(), // Moved to OverlayEntry
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.build_circle),
                  onSelected: _onToolSelected,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'Cerrar Box',
                      child: Text('Cerrar Box'),
                    ),
                    PopupMenuItem(
                      value: 'Buscar Box',
                      child: Text('Buscar Box'),
                    ),
                    PopupMenuItem(
                      value: 'Buscar DSN',
                      child: Text('Buscar DSN'),
                    ),
                  ],
                ),
              ],
            ),
            body: Stack(
              children: [
                const AnimatedLiquidBackground(),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: LiquidGlassCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'AMZ Grading',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 32,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sorting Production',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontSize: 20,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                DropdownButtonFormField<String>(
                                  focusNode: _bucketFocusNode,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: InputDecoration(
                                    prefixIcon: Icon(
                                      Icons.workspaces_outline,
                                      color: Colors.orangeAccent[100],
                                    ),
                                    labelText: 'Grading Bucket',
                                    labelStyle: const TextStyle(
                                      color: Colors.white,
                                    ),
                                    filled: true,
                                    fillColor: theme.cardColor.withAlpha(38),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.orangeAccent.shade700,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  dropdownColor: theme.cardColor,
                                  items: _buckets
                                      .map(
                                        (b) => DropdownMenuItem(
                                          value: b,
                                          child: Text(
                                            b,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  initialValue: _selectedBucket,
                                  onChanged: (v) {
                                    setState(() => _selectedBucket = v);
                                    FocusScope.of(
                                      context,
                                    ).requestFocus(_dsnFocusNode);
                                  },
                                  validator: (v) =>
                                      v == null ? 'Selecciona un bucket' : null,
                                ),
                                if (_selectedBucket != null) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Chip(
                                      avatar: const Icon(
                                        Icons.inventory_2_outlined,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      backgroundColor: _bucketAccent(
                                        _selectedBucket,
                                      ).withAlpha(89),
                                      label: Text(
                                        _selectedBucket!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                _buildTextField(
                                  controller: _dsnController,
                                  label: 'DSN Scan',
                                  icon: Icons.qr_code_scanner,
                                  focusNode: _dsnFocusNode,
                                  onSubmitted: (_) => _submit(),
                                ),
                                const SizedBox(height: 28),
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _submit,
                                    style: ElevatedButton.styleFrom(
                                      elevation: 10,
                                      backgroundColor:
                                          Colors.orangeAccent.shade700,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: _isLoading
                                        ? const CircularProgressIndicator(
                                            valueColor: AlwaysStoppedAnimation(
                                              Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Enviar',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_message != null) ...[
                            const SizedBox(height: 28),
                            SelectableText(
                              _message!,
                              style: TextStyle(
                                color: _isError
                                    ? Colors.redAccent.shade100
                                    : Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          if (!_isError && _remainingUnits != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _remainingUnits!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          if (!_isError && _boxesToClose != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _boxesToClose!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required FocusNode focusNode,
    Function(String)? onSubmitted,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: TextFormField(
          controller: controller,
          focusNode: focusNode,
          onFieldSubmitted: onSubmitted,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.orangeAccent[100]),
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white),
            filled: true,
            fillColor: Colors.white.withAlpha(15),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.orangeAccent.shade700,
                width: 2,
              ),
            ),
          ),
          validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
          textInputAction: TextInputAction.done,
        ),
      ),
    );
  }
}

// Small visual helpers used by the screen (kept local to avoid extra deps)
class AnimatedLiquidBackground extends StatelessWidget {
  const AnimatedLiquidBackground({super.key});
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFFFFA726), Color(0xFFEF6C00)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
  );
}

class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  const LiquidGlassCard({required this.child, super.key});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withAlpha(15),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.orangeAccent.withAlpha(51),
            width: 2,
          ),
        ),
        child: child,
      ),
    ),
  );
}
