import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/previ_registro.dart';
import '../../services/api_service.dart';
import '../../services/previ_service.dart';
import '../../widgets/main_sidebar.dart';

class RegistroPreviScreen extends StatefulWidget {
  const RegistroPreviScreen({super.key});
  @override
  State<RegistroPreviScreen> createState() => _RegistroPreviScreenState();
}

class _RegistroPreviScreenState extends State<RegistroPreviScreen> {
  final _formKey = GlobalKey<FormState>();
  final _previCtrl = TextEditingController();
  final _clienteCtrl = TextEditingController();
  final _expedienteCtrl = TextEditingController();
  final _operarioCtrl = TextEditingController();
  final _operarioSoporteCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _service = const PreviService();
  final String? _currentUserOperario = _resolveCurrentUser();
  final List<File?> _images = List<File?>.filled(6, null);
  bool _sending = false;

  bool get _hasCurrentUserOperario =>
      (_currentUserOperario?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _operarioCtrl.text = _currentUserOperario ?? '';
  }

  static String? _resolveCurrentUser() {
    final user = ApiService.instance?.currentUser;
    if (user == null) return null;
    final username = user.username.trim();
    if (username.isNotEmpty) return username;
    final display = user.displayName().trim();
    return display.isNotEmpty ? display : null;
  }

  Future<void> _pickImage(int idx) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() {
        _images[idx] = File(picked.path);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_images[0] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La primera imagen es obligatoria')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
    });
    try {
      final registro = PreviRegistro(
        previ: _previCtrl.text.trim(),
        cliente: _clienteCtrl.text.trim(),
        expediente: _expedienteCtrl.text.trim(),
        operario: _operarioCtrl.text.trim(),
        operariosSoporte: _operarioSoporteCtrl.text.trim(),
        descripcion: _descCtrl.text.trim(),
      );
      await _service.crearRegistro(
        registro,
        _images.whereType<File>().toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registro guardado. Puede ingresar otro.'),
        ),
      );
      _resetForm();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  // Limpia los campos para permitir un nuevo registro conservando el operario
  // seleccionado y los operarios de soporte ya escritos.
  void _resetForm() {
    setState(() {
      _previCtrl.clear();
      _clienteCtrl.clear();
      _expedienteCtrl.clear();
      _descCtrl.clear();
      for (int i = 0; i < _images.length; i++) {
        _images[i] = null;
      }
      // No se limpia _operarioCtrl ni _operarioSoporteCtrl para que se "recuerden".
    });
  }

  @override
  void dispose() {
    _previCtrl.dispose();
    _clienteCtrl.dispose();
    _expedienteCtrl.dispose();
    _operarioCtrl.dispose();
    _operarioSoporteCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const EdgeNavHandle(),
        title: const Text(
          'Registro Previ',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.surface,
                  Theme.of(context).colorScheme.surfaceContainer,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth > 680
                      ? 640.0
                      : constraints.maxWidth - 24;
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: GlassPanel(
                          elevation: 10,
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _LabeledField(
                                    label: 'Previ/Cambio SKU',
                                    child: _glassField(
                                      context,
                                      TextFormField(
                                        controller: _previCtrl,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          hintText: 'Ingrese previ/cambio sku',
                                        ),
                                        validator: (v) =>
                                            v == null || v.trim().isEmpty
                                            ? 'Requerido'
                                            : null,
                                      ),
                                    ),
                                  ),
                                  _LabeledField(
                                    label: 'Cliente',
                                    child: _glassField(
                                      context,
                                      TextFormField(
                                        controller: _clienteCtrl,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          hintText: 'Ingrese cliente',
                                        ),
                                        validator: (v) =>
                                            v == null || v.trim().isEmpty
                                            ? 'Requerido'
                                            : null,
                                      ),
                                    ),
                                  ),
                                  _LabeledField(
                                    label: 'Expediente',
                                    child: _glassField(
                                      context,
                                      TextFormField(
                                        controller: _expedienteCtrl,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          hintText: 'Ingrese expediente',
                                        ),
                                      ),
                                    ),
                                  ),
                                  _LabeledField(
                                    label: 'Operario',
                                    child: _glassField(
                                      context,
                                      TextFormField(
                                        controller: _operarioCtrl,
                                        readOnly: _hasCurrentUserOperario,
                                        enabled: !_hasCurrentUserOperario
                                            ? null
                                            : false,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          hintText: 'Se usa tu usuario actual',
                                        ),
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.color
                                              ?.withOpacity(
                                                _hasCurrentUserOperario
                                                    ? 0.5
                                                    : 1.0,
                                              ),
                                        ),
                                        validator: (v) =>
                                            v == null || v.trim().isEmpty
                                            ? 'Requerido'
                                            : null,
                                      ),
                                    ),
                                  ),
                                  _LabeledField(
                                    label: 'Operarios de soporte',
                                    child: _glassField(
                                      context,
                                      TextFormField(
                                        controller: _operarioSoporteCtrl,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          hintText: 'Ingrese operarios',
                                        ),
                                      ),
                                    ),
                                  ),
                                  _LabeledField(
                                    label: 'Descripción',
                                    child: _glassField(
                                      context,
                                      TextFormField(
                                        controller: _descCtrl,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          hintText: 'Ingrese descripción',
                                        ),
                                        validator: (v) =>
                                            v == null || v.trim().isEmpty
                                            ? 'Requerido'
                                            : null,
                                        maxLines: 3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Imágenes (1 obligatoria + hasta 5 opcionales)',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: List.generate(6, (i) {
                                      final file = _images[i];
                                      return GestureDetector(
                                        onTap: () => _pickImage(i),
                                        child: GlassPanel(
                                          elevation: 4,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withOpacity(.18),
                                          child: Container(
                                            width: 90,
                                            height: 90,
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: i == 0 && file == null
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.error
                                                    : Theme.of(
                                                        context,
                                                      ).dividerColor,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              image: file != null
                                                  ? DecorationImage(
                                                      image: FileImage(file),
                                                      fit: BoxFit.cover,
                                                    )
                                                  : null,
                                            ),
                                            child: file == null
                                                ? Center(
                                                    child: Icon(
                                                      i == 0
                                                          ? Icons.add_a_photo
                                                          : Icons
                                                                .add_photo_alternate,
                                                      color: i == 0
                                                          ? Theme.of(
                                                              context,
                                                            ).colorScheme.error
                                                          : Theme.of(context)
                                                                .iconTheme
                                                                .color
                                                                ?.withOpacity(
                                                                  0.7,
                                                                ),
                                                    ),
                                                  )
                                                : null,
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                  const SizedBox(height: 22),
                                  ElevatedButton.icon(
                                    onPressed: _sending ? null : _submit,
                                    icon: const Icon(Icons.save),
                                    label: Text(
                                      _sending
                                          ? 'Guardando...'
                                          : 'REGISTRAR PREVI',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      foregroundColor: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
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
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

Widget _glassField(BuildContext context, Widget child) {
  return GlassPanel(
    elevation: 2,
    color: Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withOpacity(.5),
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: child,
    ),
  );
}

class GlassPanel extends StatelessWidget {
  final Widget child;
  final double elevation;
  final Color? color;
  final BorderRadiusGeometry? borderRadius;

  const GlassPanel({
    super.key,
    required this.child,
    this.elevation = 8,
    this.color,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(20);
    final panelColor =
        color ??
        Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.3);
    return Container(
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: radius,
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: elevation * 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}
