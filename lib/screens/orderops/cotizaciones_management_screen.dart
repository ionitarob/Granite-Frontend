import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/orderops_service.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';

class CotizacionesManagementScreen extends StatefulWidget {
  const CotizacionesManagementScreen({super.key});

  @override
  State<CotizacionesManagementScreen> createState() =>
      _CotizacionesManagementScreenState();
}

class _CotizacionesManagementScreenState
    extends State<CotizacionesManagementScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _familyCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  int _total = 0;
  final int _limit = 100;
  int _offset = 0;
  List<Map<String, dynamic>> _rows = [];
  OverlayEntry? _edgeOverlay;
  int? _sortColumnIndex;
  bool _sortAscending = true;
  int? _editingRowId;
  bool _savingInline = false;
  final Map<String, TextEditingController> _inlineCtrls = {};

  static const Color _cPrimary = Color(0xFF1D4ED8);
  static const Color _cSecondary = Color(0xFF0F766E);
  static const Color _cAccent = Color(0xFFD97706);
  static const Color _cDanger = Color(0xFFDC2626);
  static const Color _cSurface = Color(0xFF0F172A);
  static const Color _cBorder = Color(0xFF334155);

  bool get _isPrivileged {
    final raw =
        (ApiService.instance?.currentUser?.role ?? '').trim().toLowerCase();
    final role = raw.startsWith('role_') ? raw.substring(5) : raw;
    return role == 'admin' || role == 'chief';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();

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

  @override
  void dispose() {
    _edgeOverlay?.remove();
    _edgeOverlay = null;
    _disposeInlineCtrls();
    _searchCtrl.dispose();
    _familyCtrl.dispose();
    super.dispose();
  }

  void _disposeInlineCtrls() {
    for (final c in _inlineCtrls.values) {
      c.dispose();
    }
    _inlineCtrls.clear();
  }

  void _startInlineEdit(Map<String, dynamic> row) {
    final id = int.tryParse(row['id']?.toString() ?? '');
    if (id == null) return;
    _disposeInlineCtrls();
    _inlineCtrls['family'] = TextEditingController(
      text: row['family']?.toString() ?? '',
    );
    _inlineCtrls['description'] = TextEditingController(
      text: row['description']?.toString() ?? '',
    );
    _inlineCtrls['extra_info_1'] = TextEditingController(
      text: row['extra_info_1']?.toString() ?? '',
    );
    _inlineCtrls['sku_config'] = TextEditingController(
      text: row['sku_config']?.toString() ?? '',
    );
    _inlineCtrls['sku_hp'] = TextEditingController(
      text: row['sku_hp']?.toString() ?? '',
    );
    _inlineCtrls['sku_lenovo'] = TextEditingController(
      text: row['sku_lenovo']?.toString() ?? '',
    );
    _inlineCtrls['coste'] = TextEditingController(
      text: row['coste']?.toString() ?? '',
    );
    _inlineCtrls['pvd'] = TextEditingController(
      text: row['pvd']?.toString() ?? '',
    );
    _inlineCtrls['margen'] = TextEditingController(
      text: row['margen']?.toString() ?? '',
    );
    _inlineCtrls['collection_info'] = TextEditingController(
      text: row['collection_info']?.toString() ?? '',
    );
    setState(() => _editingRowId = id);
  }

  void _cancelInlineEdit() {
    _disposeInlineCtrls();
    setState(() {
      _editingRowId = null;
      _savingInline = false;
    });
  }

  Future<void> _saveInlineEdit() async {
    final id = _editingRowId;
    if (id == null || _savingInline) return;
    final service = OrderOpsService(
      Provider.of<ApiService>(context, listen: false).client,
    );
    final payload = <String, dynamic>{
      'family': _inlineCtrls['family']?.text.trim() ?? '',
      'description': _inlineCtrls['description']?.text.trim() ?? '',
      'extra_info_1': _inlineCtrls['extra_info_1']?.text.trim() ?? '',
      'sku_config': _inlineCtrls['sku_config']?.text.trim() ?? '',
      'sku_hp': _inlineCtrls['sku_hp']?.text.trim() ?? '',
      'sku_lenovo': _inlineCtrls['sku_lenovo']?.text.trim() ?? '',
      'coste': _numOrNull(_inlineCtrls['coste']?.text ?? ''),
      'pvd': _numOrNull(_inlineCtrls['pvd']?.text ?? ''),
      'margen': _numOrNull(_inlineCtrls['margen']?.text ?? ''),
      'collection_info': _inlineCtrls['collection_info']?.text.trim() ?? '',
    };

    setState(() => _savingInline = true);
    try {
      final ok = await service.updateCotizacion(id, payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Cotización actualizada' : 'No se pudo guardar'),
        ),
      );
      if (ok) {
        await _load();
        _cancelInlineEdit();
      }
    } finally {
      if (mounted) setState(() => _savingInline = false);
    }
  }

  Future<void> _load() async {
    if (!_isPrivileged) return;
    if (_editingRowId != null) {
      _cancelInlineEdit();
    }
    final service = OrderOpsService(
      Provider.of<ApiService>(context, listen: false).client,
    );
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await service.listCotizacionesAdmin(
        query: _searchCtrl.text,
        family: _familyCtrl.text,
        limit: _limit,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _rows = (data['results'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _total = int.tryParse(data['total']?.toString() ?? '') ?? _rows.length;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createOrEdit({Map<String, dynamic>? initial}) async {
    final appTheme = Theme.of(context);
    final isDarkMode = appTheme.brightness == Brightness.dark;
    final service = OrderOpsService(
      Provider.of<ApiService>(context, listen: false).client,
    );
    final id = initial?['id'];
    final familyCtrl = TextEditingController(text: initial?['family']?.toString() ?? '');
    final descCtrl = TextEditingController(text: initial?['description']?.toString() ?? '');
    final extraCtrl = TextEditingController(text: initial?['extra_info_1']?.toString() ?? '');
    final skuCfgCtrl = TextEditingController(text: initial?['sku_config']?.toString() ?? '');
    final skuHpCtrl = TextEditingController(text: initial?['sku_hp']?.toString() ?? '');
    final skuLvCtrl = TextEditingController(text: initial?['sku_lenovo']?.toString() ?? '');
    final costeCtrl = TextEditingController(text: initial?['coste']?.toString() ?? '');
    final pvdCtrl = TextEditingController(text: initial?['pvd']?.toString() ?? '');
    final margenCtrl = TextEditingController(text: initial?['margen']?.toString() ?? '');
    final collectionCtrl = TextEditingController(text: initial?['collection_info']?.toString() ?? '');

    void disposeCtrls() {
      familyCtrl.dispose();
      descCtrl.dispose();
      extraCtrl.dispose();
      skuCfgCtrl.dispose();
      skuHpCtrl.dispose();
      skuLvCtrl.dispose();
      costeCtrl.dispose();
      pvdCtrl.dispose();
      margenCtrl.dispose();
      collectionCtrl.dispose();
    }

    final isMobile = MediaQuery.of(context).size.width < 900;

    final generalSection = _editorSection(
      title: 'General',
      color: _cPrimary,
      children: [
        _field(familyCtrl, 'Familia', icon: Icons.category_outlined),
        _field(descCtrl, 'Descripción', icon: Icons.description_outlined),
      ],
    );
    final skuSection = _editorSection(
      title: 'SKUs',
      color: _cSecondary,
      children: [
        _field(skuCfgCtrl, 'SKU Config', icon: Icons.qr_code_2),
        _field(skuHpCtrl, 'SKU HP', icon: Icons.memory_outlined),
        _field(skuLvCtrl, 'SKU Lenovo', icon: Icons.memory),
      ],
    );
    final pricingSection = _editorSection(
      title: 'Precios',
      color: _cAccent,
      children: [
        _field(
          costeCtrl,
          'Coste',
          icon: Icons.attach_money,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        _field(
          pvdCtrl,
          'PVD',
          icon: Icons.payments_outlined,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        _field(
          margenCtrl,
          'Margen',
          icon: Icons.trending_up,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
    );
    final extraSection = _editorSection(
      title: 'Metadatos',
      color: const Color(0xFF7C3AED),
      children: [
        _field(extraCtrl, 'Extra info 1', icon: Icons.info_outline),
        _field(collectionCtrl, 'Collection info', icon: Icons.collections_bookmark_outlined),
      ],
    );

    final editorContent = isMobile
        ? Column(
            children: [
              generalSection,
              const SizedBox(height: 10),
              skuSection,
              const SizedBox(height: 10),
              pricingSection,
              const SizedBox(height: 10),
              extraSection,
            ],
          )
        : Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: generalSection),
                    const SizedBox(width: 12),
                    Expanded(child: skuSection),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: pricingSection),
                    const SizedBox(width: 12),
                    Expanded(child: extraSection),
                  ],
                ),
              ),
            ],
          );

    final ok = isMobile
        ? await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (ctx) {
              return FractionallySizedBox(
                heightFactor: 0.95,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        isDarkMode
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFE2E8F0),
                        isDarkMode
                            ? const Color(0xFF1D4ED8).withOpacity(0.34)
                            : const Color(0xFFBFDBFE),
                      ],
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border.all(
                      color: isDarkMode
                          ? Colors.white.withOpacity(0.22)
                          : appTheme.colorScheme.outline.withOpacity(0.35),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white38,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          id == null ? 'Nueva cotización' : 'Editar cotización #$id',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                          textScaler: const TextScaler.linear(1),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: SingleChildScrollView(child: editorContent),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isDarkMode
                                      ? const Color(0xFFFCA5A5)
                                      : appTheme.colorScheme.error,
                                  side: BorderSide(
                                    color: isDarkMode
                                        ? const Color(0xFFEF4444)
                                        : appTheme.colorScheme.error,
                                  ),
                                  minimumSize: const Size(0, 46),
                                ),
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _cSecondary,
                                  foregroundColor: isDarkMode
                                      ? Colors.white
                                      : appTheme.colorScheme.onPrimary,
                                  minimumSize: const Size(0, 46),
                                ),
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('Guardar'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          )
        : await showGeneralDialog<bool>(
            context: context,
            barrierLabel: 'CotizacionEditor',
            barrierDismissible: true,
            barrierColor: Colors.black.withOpacity(0.62),
            transitionDuration: const Duration(milliseconds: 260),
            pageBuilder: (ctx, _, __) {
              return SafeArea(
                child: Center(
                  child: Material(
                    type: MaterialType.transparency,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 760),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF1E293B).withOpacity(0.96)
                                : appTheme.colorScheme.surface.withOpacity(0.98),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDarkMode
                                  ? Colors.white.withOpacity(0.20)
                                  : appTheme.colorScheme.outline.withOpacity(0.30),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(isDarkMode ? 0.45 : 0.16),
                                blurRadius: 30,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: _cPrimary.withOpacity(0.22),
                                        borderRadius: BorderRadius.circular(9),
                                        border: Border.all(color: _cPrimary.withOpacity(0.55)),
                                      ),
                                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        id == null ? 'Nueva cotización' : 'Editar cotización #$id',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: appTheme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Cerrar',
                                      onPressed: () => Navigator.of(ctx).pop(false),
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Completa los bloques para registrar la cotización.',
                                    style: TextStyle(
                                      color: isDarkMode
                                          ? Colors.white70
                                          : appTheme.colorScheme.onSurface.withOpacity(0.7),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: SingleChildScrollView(child: editorContent),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: appTheme.colorScheme.onSurface.withOpacity(0.75),
                                      ),
                                      onPressed: () => Navigator.of(ctx).pop(false),
                                      child: const Text('Cancelar'),
                                    ),
                                    const SizedBox(width: 10),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _cSecondary,
                                        foregroundColor: isDarkMode
                                            ? Colors.white
                                            : appTheme.colorScheme.onPrimary,
                                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: () => Navigator.of(ctx).pop(true),
                                      child: const Text('Guardar'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
            transitionBuilder: (context, animation, secondaryAnimation, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
                  child: child,
                ),
              );
            },
          );

    if (ok != true) {
      disposeCtrls();
      return;
    }

    final payload = <String, dynamic>{
      'family': familyCtrl.text.trim(),
      'description': descCtrl.text.trim(),
      'extra_info_1': extraCtrl.text.trim(),
      'sku_config': skuCfgCtrl.text.trim(),
      'sku_hp': skuHpCtrl.text.trim(),
      'sku_lenovo': skuLvCtrl.text.trim(),
      'coste': _numOrNull(costeCtrl.text),
      'pvd': _numOrNull(pvdCtrl.text),
      'margen': _numOrNull(margenCtrl.text),
      'collection_info': collectionCtrl.text.trim(),
    };

    setState(() => _loading = true);
    try {
      final result = id == null
          ? await service.createCotizacion(payload)
          : await service.updateCotizacion(int.parse(id.toString()), payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result
              ? (id == null ? 'Cotización creada' : 'Cotización actualizada')
              : 'No se pudo guardar la cotización'),
        ),
      );
      if (result) {
        await _load();
      }
    } finally {
      disposeCtrls();
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sortBy<T extends Comparable<Object?>>(
    int columnIndex,
    T Function(Map<String, dynamic> row) getField,
  ) {
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumnIndex = columnIndex;
        _sortAscending = true;
      }

      _rows.sort((a, b) {
        final aValue = getField(a);
        final bValue = getField(b);
        final result = Comparable.compare(aValue, bValue);
        return _sortAscending ? result : -result;
      });
    });
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    final id = int.tryParse(row['id']?.toString() ?? '');
    if (id == null) return;
    if (_editingRowId == id) {
      _cancelInlineEdit();
    }
    final service = OrderOpsService(
      Provider.of<ApiService>(context, listen: false).client,
    );
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cotización'),
        content: Text('¿Eliminar registro #$id?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final ok = await service.deleteCotizacion(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Cotización eliminada' : 'No se pudo eliminar')),
      );
      if (ok) await _load();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    IconData? icon,
    TextInputType? keyboardType,
  }) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon == null
              ? null
              : Icon(
                  icon,
                  size: 18,
                  color: isDarkMode
                      ? Colors.white70
                      : theme.colorScheme.onSurface.withOpacity(0.75),
                ),
          filled: true,
          fillColor: isDarkMode
              ? const Color(0xFF334155).withOpacity(0.50)
              : theme.colorScheme.surface,
          floatingLabelStyle: TextStyle(color: theme.colorScheme.onSurface),
          labelStyle: TextStyle(
            color: isDarkMode
                ? Colors.white70
                : theme.colorScheme.onSurface.withOpacity(0.72),
          ),
          hintStyle: TextStyle(
            color: isDarkMode
                ? Colors.white54
                : theme.colorScheme.onSurface.withOpacity(0.52),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.32)
                  : theme.colorScheme.outline.withOpacity(0.45),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _cSecondary.withOpacity(0.95), width: 1.8),
          ),
        ),
        style: TextStyle(color: theme.colorScheme.onSurface),
      ),
    );
  }

  Widget _editorSection({
    required String title,
    required Color color,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF1F2A44).withOpacity(0.72)
            : color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDarkMode
                      ? color
                      : Color.alphaBlend(
                          theme.colorScheme.onSurface.withOpacity(0.18),
                          color,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  double? _numOrNull(String value) {
    final t = value.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', '.'));
  }

  String _money(dynamic value) {
    final v = double.tryParse(value?.toString() ?? '');
    if (v == null) return '-';
    return v.toStringAsFixed(2);
  }

  Color _familyColor(String family) {
    final f = family.trim().toLowerCase();
    if (f.contains('serigra')) return const Color(0xFFF59E0B);
    if (f.contains('normal')) return const Color(0xFF2563EB);
    if (f.contains('asw') || f.contains('asw2') || f.contains('asw3')) {
      return const Color(0xFF7C3AED);
    }
    if (f.contains('lenovo')) return const Color(0xFF16A34A);
    if (f.contains('hp')) return const Color(0xFF0284C7);
    if (f.contains('gaming')) return const Color(0xFFDC2626);
    if (f.contains('ultra') || f.contains('premium')) {
      return const Color(0xFFD97706);
    }

    // Fallback: deterministic color per family text so unknown families
    // still get a distinct, stable visual identity.
    if (f.isEmpty) return const Color(0xFF64748B);
    const palette = <Color>[
      Color(0xFF2563EB),
      Color(0xFF16A34A),
      Color(0xFF7C3AED),
      Color(0xFFD97706),
      Color(0xFF0D9488),
      Color(0xFFDB2777),
      Color(0xFFEA580C),
      Color(0xFF0891B2),
      Color(0xFF65A30D),
      Color(0xFFB45309),
    ];

    var hash = 0;
    for (final code in f.codeUnits) {
      hash = ((hash * 31) + code) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  Widget _familyBadge(String family) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = _familyColor(family);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.20 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(isDark ? 0.72 : 0.55)),
      ),
      child: Text(
        family.isEmpty ? '-' : family,
        style: TextStyle(
          color: isDark
              ? color
              : Color.alphaBlend(theme.colorScheme.onSurface.withOpacity(0.10), color),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _kpiTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: 210,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(isDark ? 0.30 : 0.22),
            isDark
                ? _cSurface.withOpacity(0.72)
                : theme.colorScheme.surface.withOpacity(0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(isDark ? 0.45 : 0.35)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(isDark ? 0.22 : 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? Colors.white
                        : theme.colorScheme.onSurface.withOpacity(0.80),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Colors.white
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionsCell(Map<String, dynamic> row) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Editar',
          onPressed: () => _createOrEdit(initial: row),
          icon: const Icon(Icons.edit),
        ),
        IconButton(
          tooltip: 'Duplicar',
          onPressed: () {
            final cloned = Map<String, dynamic>.from(row)..remove('id');
            _createOrEdit(initial: cloned);
          },
          icon: const Icon(Icons.copy_all_outlined),
        ),
        IconButton(
          tooltip: 'Eliminar',
          onPressed: () => _deleteRow(row),
          icon: Icon(
            Icons.delete_outline,
            color: _cDanger,
          ),
        ),
      ],
    );
  }

  Widget _inlineInput(
    String key, {
    double width = 160,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: _inlineCtrls[key],
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: _cSurface.withOpacity(0.65),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: const OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: _cPrimary.withOpacity(0.30)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: _cPrimary, width: 1.6),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopDataTable() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final skuHpColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1);
    final skuLenovoColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
    final extraInfoColor = isDark ? const Color(0xFFFACC15) : const Color(0xFF92400E);
    final costeColor = isDark ? const Color(0xFFF97316) : const Color(0xFF9A3412);
    final pvdColor = isDark ? const Color(0xFF22C55E) : const Color(0xFF166534);
    final margenColor = isDark ? const Color(0xFFEAB308) : const Color(0xFF854D0E);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isDark
                ? _cSurface.withOpacity(0.90)
                : theme.colorScheme.surface,
            isDark
                ? const Color(0xFF111827).withOpacity(0.92)
                : theme.colorScheme.surfaceContainerHighest.withOpacity(0.86),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? _cBorder.withOpacity(0.85)
              : theme.colorScheme.outline.withOpacity(0.35),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              sortColumnIndex: _sortColumnIndex,
              sortAscending: _sortAscending,
              headingTextStyle: theme.textTheme.labelLarge?.copyWith(
                color: isDark ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
              dataTextStyle: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
              headingRowColor: WidgetStateProperty.all(
                isDark
                    ? _cPrimary.withOpacity(0.22)
                    : _cPrimary.withOpacity(0.12),
              ),
              dataRowColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return isDark
                      ? _cPrimary.withOpacity(0.16)
                      : _cPrimary.withOpacity(0.08);
                }
                return isDark
                    ? _cSurface.withOpacity(0.16)
                    : theme.colorScheme.surface.withOpacity(0.96);
              }),
              dataRowMinHeight: 54,
              dataRowMaxHeight: 74,
              columns: [
                DataColumn(
                  label: const Text('ID'),
                  onSort: (_, __) => _sortBy<num>(
                    0,
                    (r) => int.tryParse(r['id']?.toString() ?? '') ?? 0,
                  ),
                ),
                DataColumn(
                  label: const Text('Familia'),
                  onSort: (_, __) => _sortBy<String>(
                    1,
                    (r) => r['family']?.toString() ?? '',
                  ),
                ),
                const DataColumn(label: Text('Descripción')),
                DataColumn(
                  label: const Text('SKU Config'),
                  onSort: (_, __) => _sortBy<String>(
                    3,
                    (r) => r['sku_config']?.toString() ?? '',
                  ),
                ),
                DataColumn(
                  label: Text(
                    'SKU HP',
                    style: TextStyle(color: skuHpColor),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'SKU Lenovo',
                    style: TextStyle(color: skuLenovoColor),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Extra Info',
                    style: TextStyle(color: extraInfoColor),
                  ),
                ),
                DataColumn(
                  numeric: true,
                  label: Text(
                    'Coste',
                    style: TextStyle(color: costeColor),
                  ),
                  onSort: (_, __) => _sortBy<num>(
                    4,
                    (r) => double.tryParse(r['coste']?.toString() ?? '') ?? 0,
                  ),
                ),
                DataColumn(
                  numeric: true,
                  label: Text(
                    'PVD',
                    style: TextStyle(color: pvdColor),
                  ),
                  onSort: (_, __) => _sortBy<num>(
                    5,
                    (r) => double.tryParse(r['pvd']?.toString() ?? '') ?? 0,
                  ),
                ),
                DataColumn(
                  numeric: true,
                  label: Text(
                    'Margen',
                    style: TextStyle(color: margenColor),
                  ),
                  onSort: (_, __) => _sortBy<num>(
                    6,
                    (r) => double.tryParse(r['margen']?.toString() ?? '') ?? 0,
                  ),
                ),
                const DataColumn(label: Text('Collection')),
              ],
              rows: _rows.map((row) {
                final rowId = int.tryParse(row['id']?.toString() ?? '');
                final isEditing = rowId != null && rowId == _editingRowId;
                final familyColor = _familyColor(row['family']?.toString() ?? '');
                return DataRow(
                  color: WidgetStateProperty.resolveWith((states) {
                    if (isEditing) {
                      return isDark
                          ? _cSecondary.withOpacity(0.26)
                          : _cSecondary.withOpacity(0.14);
                    }
                    return familyColor.withOpacity(isDark ? 0.18 : 0.09);
                  }),
                  cells: [
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(row['id']?.toString() ?? '-'),
                          if (!isEditing) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.edit_note,
                              size: 14,
                              color: _cAccent.withOpacity(0.9),
                            ),
                          ],
                          if (isEditing) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Guardar fila',
                              onPressed: _savingInline ? null : _saveInlineEdit,
                              icon: _savingInline
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check_circle_outline),
                            ),
                            IconButton(
                              tooltip: 'Cancelar edición',
                              onPressed: _savingInline ? null : _cancelInlineEdit,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ],
                      ),
                      onDoubleTap: isEditing ? null : () => _startInlineEdit(row),
                    ),
                    DataCell(
                      isEditing
                          ? _inlineInput('family', width: 150)
                          : _familyBadge(row['family']?.toString() ?? ''),
                      onDoubleTap: isEditing ? null : () => _startInlineEdit(row),
                    ),
                    DataCell(
                      isEditing
                          ? _inlineInput('description', width: 320, maxLines: 2)
                          : SizedBox(
                              width: 320,
                              child: Text(
                                row['description']?.toString() ?? '',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                      onDoubleTap: isEditing ? null : () => _startInlineEdit(row),
                    ),
                    DataCell(
                      isEditing
                          ? _inlineInput('sku_config', width: 180)
                          : SizedBox(
                              width: 180,
                              child: SelectableText(
                                row['sku_config']?.toString() ?? '',
                              ),
                            ),
                      onDoubleTap: isEditing ? null : () => _startInlineEdit(row),
                    ),
                    DataCell(
                      isEditing
                          ? _inlineInput('sku_hp', width: 150)
                          : SizedBox(
                              width: 150,
                              child: SelectableText(
                                row['sku_hp']?.toString() ?? '',
                                style: TextStyle(color: skuHpColor),
                              ),
                            ),
                      onDoubleTap: isEditing ? null : () => _startInlineEdit(row),
                    ),
                    DataCell(
                      isEditing
                          ? _inlineInput('sku_lenovo', width: 150)
                          : SizedBox(
                              width: 150,
                              child: SelectableText(
                                row['sku_lenovo']?.toString() ?? '',
                                style: TextStyle(color: skuLenovoColor),
                              ),
                            ),
                      onDoubleTap: isEditing ? null : () => _startInlineEdit(row),
                    ),
                    DataCell(
                      isEditing
                          ? _inlineInput('extra_info_1', width: 180)
                          : SizedBox(
                              width: 180,
                              child: Text(
                                row['extra_info_1']?.toString() ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: extraInfoColor),
                              ),
                            ),
                      onDoubleTap: isEditing ? null : () => _startInlineEdit(row),
                    ),
                    DataCell(
                      isEditing
                          ? _inlineInput(
                              'coste',
                              width: 100,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            )
                          : Text(
                              _money(row['coste']),
                              style: TextStyle(
                                color: costeColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                      onDoubleTap: isEditing ? null : () => _startInlineEdit(row),
                    ),
                    DataCell(
                      isEditing
                          ? _inlineInput(
                              'pvd',
                              width: 100,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            )
                          : Text(
                              _money(row['pvd']),
                              style: TextStyle(
                                color: pvdColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                      onDoubleTap: isEditing ? null : () => _startInlineEdit(row),
                    ),
                    DataCell(
                      isEditing
                          ? _inlineInput(
                              'margen',
                              width: 100,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            )
                          : Text(
                              _money(row['margen']),
                              style: TextStyle(
                                color: margenColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                      onDoubleTap: isEditing ? null : () => _startInlineEdit(row),
                    ),
                    DataCell(
                      isEditing
                          ? _inlineInput('collection_info', width: 200)
                          : SizedBox(
                              width: 200,
                              child: Text(
                                row['collection_info']?.toString() ?? '',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      onDoubleTap: isEditing ? null : () => _startInlineEdit(row),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileList() {
    return ListView.separated(
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final row = _rows[i];
        final familyColor = _familyColor(row['family']?.toString() ?? '');
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                familyColor.withOpacity(0.28),
                _cSurface.withOpacity(0.88),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: familyColor.withOpacity(0.65)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row['description']?.toString() ?? 'Sin descripción',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('#${row['id'] ?? '-'}'),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _familyBadge(row['family']?.toString() ?? '-'),
                  _chip('SKU', row['sku_config']?.toString() ?? '-'),
                  _chip('Coste', _money(row['coste'])),
                  _chip('PVD', _money(row['pvd'])),
                  _chip('Margen', _money(row['margen'])),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: _actionsCell(row),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _cPrimary.withOpacity(0.42),
            _cSecondary.withOpacity(0.38),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _cPrimary.withOpacity(0.5)),
      ),
      child: Text(
        '$k: $v',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 900;
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 0.6),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1500),
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 10 : 16),
                  child: !_isPrivileged
                      ? const Center(
                          child: Text('Acceso restringido a admin/chief'),
                        )
                      : Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'OrderOps · Gestión Cotizaciones',
                                style: TextStyle(
                                  fontSize: isMobile ? 18 : 24,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Wrap(
                              spacing: 10,
                              children: [
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: isDark
                                        ? _cPrimary.withOpacity(0.28)
                                        : _cPrimary.withOpacity(0.22),
                                    foregroundColor: isDark
                                        ? Colors.white
                                        : theme.colorScheme.onPrimaryContainer,
                                  ),
                                  onPressed: _loading ? null : _load,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Refrescar'),
                                ),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _cSecondary,
                                    foregroundColor: isDark
                                        ? Colors.white
                                        : theme.colorScheme.onPrimary,
                                  ),
                                  onPressed: _loading
                                      ? null
                                      : () => _createOrEdit(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Nueva cotización'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            _kpiTile(
                              icon: Icons.dataset_rounded,
                              label: 'Registros Totales',
                              value: _total.toString(),
                              color: _cPrimary,
                            ),
                            _kpiTile(
                              icon: Icons.view_list_rounded,
                              label: 'Mostrados',
                              value: _rows.length.toString(),
                              color: _cSecondary,
                            ),
                            _kpiTile(
                              icon: Icons.layers_rounded,
                              label: 'Página',
                              value: '${(_offset ~/ _limit) + 1}',
                              color: _cAccent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  isDark
                                      ? _cSecondary.withOpacity(0.22)
                                      : _cSecondary.withOpacity(0.14),
                                  isDark
                                      ? _cPrimary.withOpacity(0.18)
                                      : _cPrimary.withOpacity(0.12),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? _cSecondary.withOpacity(0.55)
                                    : theme.colorScheme.outline.withOpacity(0.30),
                              ),
                            ),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.center,
                              children: [
                                SizedBox(
                                  width: 320,
                                  child: TextField(
                                    controller: _searchCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Buscar',
                                      hintText: 'Descripción, SKU Config, HP o Lenovo',
                                      prefixIcon: Icon(
                                        Icons.search,
                                        color: isDark
                                            ? Colors.white70
                                            : theme.colorScheme.onSurface.withOpacity(0.7),
                                      ),
                                      filled: true,
                                      fillColor: isDark
                                          ? _cSurface.withOpacity(0.55)
                                          : theme.colorScheme.surface,
                                      labelStyle: TextStyle(
                                        color: isDark
                                            ? Colors.white70
                                            : theme.colorScheme.onSurface.withOpacity(0.72),
                                      ),
                                      hintStyle: TextStyle(
                                        color: isDark
                                            ? Colors.white54
                                            : theme.colorScheme.onSurface.withOpacity(0.55),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: isDark
                                              ? _cPrimary.withOpacity(0.35)
                                              : theme.colorScheme.outline.withOpacity(0.38),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: _cPrimary,
                                          width: 1.6,
                                        ),
                                      ),
                                    ),
                                    onSubmitted: (_) {
                                      _offset = 0;
                                      _load();
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: 260,
                                  child: TextField(
                                    controller: _familyCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Familia',
                                      prefixIcon: Icon(
                                        Icons.category_outlined,
                                        color: isDark
                                            ? Colors.white70
                                            : theme.colorScheme.onSurface.withOpacity(0.7),
                                      ),
                                      filled: true,
                                      fillColor: isDark
                                          ? _cSurface.withOpacity(0.55)
                                          : theme.colorScheme.surface,
                                      labelStyle: TextStyle(
                                        color: isDark
                                            ? Colors.white70
                                            : theme.colorScheme.onSurface.withOpacity(0.72),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: isDark
                                              ? _cSecondary.withOpacity(0.35)
                                              : theme.colorScheme.outline.withOpacity(0.38),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: _cSecondary,
                                          width: 1.6,
                                        ),
                                      ),
                                    ),
                                    onSubmitted: (_) {
                                      _offset = 0;
                                      _load();
                                    },
                                  ),
                                ),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _cPrimary,
                                    foregroundColor: isDark
                                        ? Colors.white
                                        : theme.colorScheme.onPrimary,
                                  ),
                                  onPressed: _loading
                                      ? null
                                      : () {
                                          _offset = 0;
                                          _load();
                                        },
                                  icon: const Icon(Icons.search),
                                  label: const Text('Aplicar filtros'),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: isDark
                                        ? _cAccent
                                        : const Color(0xFF92400E),
                                    side: BorderSide(
                                      color: isDark
                                          ? _cAccent.withOpacity(0.65)
                                          : const Color(0xFFB45309).withOpacity(0.7),
                                    ),
                                  ),
                                  onPressed: _loading
                                      ? null
                                      : () {
                                          _searchCtrl.clear();
                                          _familyCtrl.clear();
                                          _offset = 0;
                                          _load();
                                        },
                                  icon: const Icon(Icons.clear_all),
                                  label: const Text('Limpiar'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_error != null)
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        if (!isMobile) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _cAccent.withOpacity(0.22),
                                  _cPrimary.withOpacity(0.2),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _cAccent.withOpacity(0.5),
                              ),
                            ),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: const [
                                Icon(Icons.mouse, size: 16, color: Color(0xFFF59E0B)),
                                Text(
                                  'Doble clic en cualquier celda para editar la fila.',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text('La fila activa se resalta en azul.'),
                                Text('Usa ✓ para guardar o ✕ para cancelar.'),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Expanded(
                          child: SizedBox(
                            width: double.infinity,
                            child: _loading
                                ? const Center(child: CircularProgressIndicator())
                                : isMobile
                                    ? _buildMobileList()
                                    : _buildDesktopDataTable(),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _loading || _offset == 0
                                  ? null
                                  : () {
                                      _offset = (_offset - _limit).clamp(0, _offset);
                                      _load();
                                    },
                              child: const Text('Anterior'),
                            ),
                            const SizedBox(width: 12),
                            TextButton(
                              onPressed: _loading || (_offset + _limit) >= _total
                                  ? null
                                  : () {
                                      _offset += _limit;
                                      _load();
                                    },
                              child: const Text('Siguiente'),
                            ),
                          ],
                        ),
                      ],
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
