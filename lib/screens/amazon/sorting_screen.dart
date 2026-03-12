import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'amz_close_box_screen.dart';
import 'amz_find_box_screen.dart';
import 'amz_find_dsn_screen.dart';

import '../../themes/amazon_theme.dart';
import '../../services/api_service.dart';
import '../../api_client.dart';
import '../../widgets/main_sidebar.dart';
import '../../widgets/animated_background.dart';
import 'package:flutter/cupertino.dart'; // For macOS controls

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
        '/amz/grading/sorting_sp',
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
          _message = _extractErrorMessage(res) ?? 'Error servidor.';
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

  String? _extractErrorMessage(ApiResult res) {
    final body = res.body;
    if (body is Map) {
      for (final key in ['message', 'error', 'error_message', 'detail']) {
        final value = body[key];
        if (value is String && value.trim().isNotEmpty) return value;
      }
    }
    return res.error;
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
          final colorScheme = theme.colorScheme;
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
                const AnimatedBackgroundWidget(intensity: 1.0),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.dark
                                ? Colors.black.withOpacity(0.2)
                                : Colors.white.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'AMZ Grading',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 32,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Sorting Production',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.7),
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
                                      style: TextStyle(
                                        color: colorScheme.onSurface,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      icon: Icon(
                                        Icons.unfold_more_rounded,
                                        color: colorScheme.onSurface
                                            .withOpacity(0.5),
                                        size: 20,
                                      ),
                                      decoration: InputDecoration(
                                        prefixIcon: Icon(
                                          Icons.workspaces_outline,
                                          color: colorScheme.primary,
                                        ),
                                        labelText: 'Grading Bucket',
                                        labelStyle: TextStyle(
                                          color: colorScheme.onSurface
                                              .withOpacity(0.6),
                                        ),
                                        filled: true,
                                        fillColor:
                                            theme.brightness == Brightness.dark
                                            ? Colors.black.withOpacity(0.1)
                                            : Colors.white.withOpacity(0.5),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 16,
                                              horizontal: 16,
                                            ),
                                      ),
                                      dropdownColor: theme.cardColor,
                                      selectedItemBuilder: (context) {
                                        return _buckets.map((String item) {
                                          return Text(
                                            item,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: colorScheme.onSurface,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          );
                                        }).toList();
                                      },
                                      items: _buckets.map((b) {
                                        final isLast = b == _buckets.last;
                                        return DropdownMenuItem(
                                          value: b,
                                          child: Container(
                                            width: double.infinity,
                                            decoration: isLast
                                                ? null
                                                : BoxDecoration(
                                                    border: Border(
                                                      bottom: BorderSide(
                                                        color: colorScheme
                                                            .onSurface
                                                            .withOpacity(0.1),
                                                        width: 0.5,
                                                      ),
                                                    ),
                                                  ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            child: Text(
                                              b,
                                              style: TextStyle(
                                                color: colorScheme.onSurface,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                      initialValue: _selectedBucket,
                                      onChanged: (v) {
                                        setState(() => _selectedBucket = v);
                                        FocusScope.of(
                                          context,
                                        ).requestFocus(_dsnFocusNode);
                                      },
                                      validator: (v) => v == null
                                          ? 'Selecciona un bucket'
                                          : null,
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
                                          ),
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
                                    Container(
                                      width: double.infinity,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        gradient: LinearGradient(
                                          colors: [
                                            colorScheme.primary,
                                            colorScheme.primary.withOpacity(
                                              0.8,
                                            ),
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: colorScheme.primary
                                                .withOpacity(0.3),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: CupertinoButton(
                                        padding: EdgeInsets.zero,
                                        onPressed: _isLoading ? null : _submit,
                                        borderRadius: BorderRadius.circular(12),
                                        child: _isLoading
                                            ? const CupertinoActivityIndicator(
                                                color: Colors.white,
                                              )
                                            : const Text(
                                                'Enviar',
                                                style: TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                  letterSpacing: 0.5,
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
                                        ? Colors.redAccent
                                        : colorScheme.onSurface,
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
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontSize: 16,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              if (!_isError && _boxesToClose != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _boxesToClose!,
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      onFieldSubmitted: onSubmitted,
      style: TextStyle(color: colorScheme.onSurface, fontSize: 18),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: colorScheme.primary),
        labelText: label,
        labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.6)),
        filled: true,
        fillColor: theme.brightness == Brightness.dark
            ? Colors.black.withOpacity(0.1)
            : Colors.white.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.primary.withOpacity(0.5),
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
      ),
      validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
      textInputAction: TextInputAction.done,
    );
  }
}
