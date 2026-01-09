import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../themes/amazon_theme.dart';
import '../../widgets/main_sidebar.dart';

class AmzCloseBoxScreen extends StatefulWidget {
  const AmzCloseBoxScreen({super.key});

  @override
  State<AmzCloseBoxScreen> createState() => _AmzCloseBoxScreenState();
}

class _AmzCloseBoxScreenState extends State<AmzCloseBoxScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _boxController = TextEditingController();
  final FocusNode _boxFocus = FocusNode();

  bool _submitting = false;
  String? _message;

  OverlayEntry? _edgeOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_boxFocus);
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
    _boxFocus.dispose();
    _boxController.dispose();
    _edgeOverlay?.remove();
    super.dispose();
  }

  Future<void> _closeBox() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    // Use shared ApiService client to send authenticated request
    final api = Provider.of<ApiService>(context, listen: false);
    final res = await api.client.post(
      '/amz/grading/sorting/close_box',
      jsonBody: {'box_name': _boxController.text.trim()},
    );
    if (res.ok) {
      setState(() {
        _message = 'Caja cerrada correctamente';
        _boxController.clear();
      });
    } else {
      try {
        final body = res.body as Map<String, dynamic>?;
        setState(
          () => _message = body != null
              ? (body['error'] ?? 'Error desconocido')
              : (res.error ?? 'Error desconocido'),
        );
      } catch (_) {
        setState(() => _message = res.error ?? 'Error desconocido');
      }
    }

    FocusScope.of(context).requestFocus(_boxFocus);
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return AmazonTheme(
      child: Builder(
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return Focus(
            focusNode: FocusNode(),
            child: Scaffold(
              backgroundColor: theme.scaffoldBackgroundColor,
              body: Stack(
                children: [
                  // gradient background
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary.withOpacity(0.9),
                          theme.colorScheme.surface,
                        ],
                      ),
                    ),
                  ),
                  // content
                  SafeArea(
                    child: Column(
                      children: [
                        Container(
                          height: 120,
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Stack(
                            children: [
                              // EdgeNavHandle moved to OverlayEntry
                              Center(
                                child: Text(
                                  'Cerrar Caja Amazon',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 12,
                                  sigmaY: 12,
                                ),
                                child: Container(
                                  width: MediaQuery.of(ctx).size.width * 0.9,
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface
                                        .withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.08),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Form(
                                        key: _formKey,
                                        child: TextFormField(
                                          controller: _boxController,
                                          focusNode: _boxFocus,
                                          autofocus: true,
                                          style: TextStyle(
                                            color: theme.colorScheme.onSurface,
                                          ),
                                          textInputAction: TextInputAction.done,
                                          onFieldSubmitted: (_) {
                                            if (!_submitting) _closeBox();
                                          },
                                          decoration: InputDecoration(
                                            labelText: 'Número de Caja',
                                            labelStyle: TextStyle(
                                              color: theme.colorScheme.onSurface
                                                  .withOpacity(0.8),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.3),
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                            ),
                                            prefixIcon: Icon(
                                              Icons.archive,
                                              color: theme.colorScheme.onSurface
                                                  .withOpacity(0.9),
                                            ),
                                          ),
                                          validator: (v) =>
                                              (v == null || v.isEmpty)
                                              ? 'Debes ingresar un número de caja'
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: theme
                                                .colorScheme
                                                .onPrimary
                                                .withOpacity(0.12),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 16,
                                            ),
                                            elevation: 0,
                                          ),
                                          onPressed: _submitting
                                              ? null
                                              : _closeBox,
                                          child: _submitting
                                              ? CircularProgressIndicator(
                                                  color: theme
                                                      .colorScheme
                                                      .onPrimary,
                                                )
                                              : Text(
                                                  'Cerrar Caja',
                                                  style: TextStyle(
                                                    color: theme
                                                        .colorScheme
                                                        .onPrimary,
                                                  ),
                                                ),
                                        ),
                                      ),
                                      if (_message != null) ...[
                                        const SizedBox(height: 20),
                                        Text(
                                          _message!,
                                          style: TextStyle(
                                            color: theme.colorScheme.onSurface,
                                            fontWeight: FontWeight.bold,
                                          ),
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
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
