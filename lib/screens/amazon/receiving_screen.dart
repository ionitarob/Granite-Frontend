import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../api_client.dart';
import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';

/// Migrated ReceivingScreen: adapted to use ApiService.client
class ReceivingScreen extends StatefulWidget {
  const ReceivingScreen({super.key});
  @override
  State<ReceivingScreen> createState() => _ReceivingScreenState();
}

enum ReceivingMode { unitCase, pallet }

enum ReceivingAction { createPallet, addUnits, closePallet }

// New: Pallet mode mock actions (no backend yet)
enum PalletSpecialAction { purchaseOrder, transfer, other }

enum OtherMockAction { component, material, sidelined }

class _ReceivingScreenState extends State<ReceivingScreen>
    with TickerProviderStateMixin {
  static final RegExp _wplPattern = RegExp(r'^WPL-[A-Z0-9]{10}$');
  static const String _wplLetters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const String _wplDigits = '0123456789';
  ReceivingMode _mode = ReceivingMode.unitCase;
  ReceivingAction _action = ReceivingAction.createPallet;
  PalletSpecialAction _palletAction = PalletSpecialAction.purchaseOrder;
  OtherMockAction _otherAction = OtherMockAction.component;
  late AnimationController _panelController;
  late Animation<double> _fadeAnim;
  late AnimationController _bgController; // ambient animated background
  late AnimationController _headerController; // header reveal
  late Animation<double> _headerFade;
  // WPL auto-generates for new pallets (read-only there) but stays editable elsewhere.
  final TextEditingController _partNumberController = TextEditingController();
  String? _selectedDisposition;
  String? _selectedNode;
  String? _damageSubType; // Ungraded / Rebox / Recycle when Damage selected
  final List<String> _dispositionOptions = const [
    'Damage',
    'Defective',
    'Prime',
    'Problem Pending Solve',
    'Quarantine',
    'Repair',
    'Reserve',
    'Rework',
  ];
  static const Map<String, String> _dispositionLabels = {
    'Damage': 'Danio',
    'Defective': 'Defectuoso',
    'Prime': 'Prime',
    'Problem Pending Solve': 'Problema pendiente',
    'Quarantine': 'Cuarentena',
    'Repair': 'Reparacion',
    'Reserve': 'Reserva',
    'Rework': 'Retrabajo',
  };
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _poController = TextEditingController();
  final TextEditingController _palletIdController = TextEditingController();
  final TextEditingController _destinationLocationController =
      TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  // Mock pallet special action controllers
  final TextEditingController _wplSsccController = TextEditingController();
  final TextEditingController _transferWplController = TextEditingController();
  final TextEditingController _transferPartController = TextEditingController();
  final TextEditingController _otherPartController = TextEditingController();
  XFile? _pickedImage;
  bool _isSubmitting = false;
  bool _isPrintingLatest = false;
  final math.Random _rng = math.Random();
  OverlayEntry? _edgeOverlay;

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    ApiResult? resp;
    try {
      switch (_action) {
        case ReceivingAction.createPallet:
          resp = await _submitCreatePallet();
          if (resp != null) _handleResponse(resp, 'Palet creado');
          break;
        case ReceivingAction.addUnits:
          resp = await _submitAddUnits();
          if (resp != null) _handleResponse(resp, 'Unidad agregada');
          break;
        case ReceivingAction.closePallet:
          resp = await _submitClosePallet();
          if (resp != null) _handleResponse(resp, 'Palet cerrado');
          break;
      }
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _triggerLatestPalletPrint({bool silent = false}) async {
    if (!silent) {
      if (_isPrintingLatest) return;
      setState(() => _isPrintingLatest = true);
    }
    ApiResult? result;
    Object? lastError;
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final endpoints = <String>[
        '/amz/receiving/pallets/print_latest',
        '/amz/receiving/pallets/print_latest/',
        '/amz/pallets/print_latest',
        '/amz/pallets/print_latest/',
        '/receiving/pallets/print_latest',
        '/receiving/pallets/print_latest/',
      ];
      for (final route in endpoints) {
        try {
          final attempt = await api.client.post(route);
          result = attempt;
          if (attempt.ok) break;
        } catch (e) {
          lastError = e;
          result = null;
        }
      }

      if (result == null) {
        final msg = lastError?.toString() ?? 'Printer endpoint unreachable';
        _showSnack(
          silent
              ? 'Autoimpresion fallida: $msg'
              : 'Solicitud de impresion fallida: $msg',
        );
        return;
      }

      if (result.ok) {
        if (!silent) _showSnack('Ultimo palet enviado a la impresora');
        return;
      }

      final detail = _describePrintError(result);
      _showSnack(
        silent
            ? 'Autoimpresion fallida: $detail'
            : 'No se pudo imprimir el ultimo palet: $detail',
      );
    } catch (e) {
      final msg = 'Solicitud de impresion fallida: $e';
      _showSnack(silent ? 'Autoimpresion fallida: $msg' : msg);
    } finally {
      if (!silent && mounted) setState(() => _isPrintingLatest = false);
    }
  }

  String _describePrintError(ApiResult result) {
    String detail = '';
    final body = result.body;
    if (body != null) {
      try {
        if (body is Map) {
          detail =
              (body['error'] ??
                      body['message'] ??
                      body['detail'] ??
                      body['response'] ??
                      '')
                  .toString();
        } else {
          detail = body.toString();
        }
      } catch (_) {
        detail = body.toString();
      }
    }
    if (detail.contains('<html')) {
      detail = 'Endpoint no encontrado (HTTP ${result.statusCode})';
    }
    if (detail.isEmpty && result.error != null && result.error!.isNotEmpty) {
      detail = result.error!;
    }
    if (detail.isEmpty)
      detail = 'La impresora respondio con estado ${result.statusCode}';
    return detail;
  }

  String? _normalizedWpl() {
    final raw = _palletIdController.text.trim();
    if (raw.isEmpty) return null;
    final upper = raw.toUpperCase();
    if (raw != upper) {
      _palletIdController.value = TextEditingValue(
        text: upper,
        selection: TextSelection.collapsed(offset: upper.length),
      );
    }
    return upper;
  }

  Future<ApiResult?> _submitCreatePallet() async {
    final wpl = _normalizedWpl();
    if (wpl == null) {
      _showSnack('Se requiere el ID de palet WPL');
      return null;
    }
    if (!_wplPattern.hasMatch(wpl)) {
      _showSnack('El WPL debe seguir el formato WPL-XXXXXXXXXX');
      return null;
    }
    final loc = _locationController.text.trim();
    if (_selectedDisposition == null) {
      _showSnack('La disposicion del palet es obligatoria');
      return null;
    }
    if (_selectedDisposition == 'Damage' && _damageSubType == null) {
      _showSnack('El subtipo de danio es obligatorio');
      return null;
    }
    if (_selectedNode == null) {
      _showSnack('El nodo es obligatorio');
      return null;
    }
    if (loc.isEmpty) {
      _showSnack('La ubicacion es obligatoria');
      return null;
    }

    final api = Provider.of<ApiService>(context, listen: false);
    final notesValue = _notesController.text.trim();
    final body = <String, dynamic>{
      'wpl_id': wpl,
      'disposition': _effectiveDisposition(),
      'node': _selectedNode ?? 'KSP1',
      'asin_upc': null,
      'location_no': loc,
      'notes': notesValue.isEmpty ? null : notesValue,
    };
    if (_pickedImage != null) {
      try {
        final bytes = await _pickedImage!.readAsBytes();
        body['image_b64'] = base64Encode(bytes);
        body['image_name'] = _pickedImage!.path.split(RegExp(r'[\\/]')).last;
      } catch (_) {}
    }
    // Debug: print the outgoing JSON so we can inspect what the server receives.
    try {
      debugPrint(
        'Creating pallet - POST /amz/receiving/pallet -> ${jsonEncode(body)}',
      );
    } catch (_) {}

    ApiResult result = await api.client.post(
      '/amz/receiving/pallet',
      jsonBody: body,
    );
    // If server returns a validation error complaining about missing fields,
    // try the legacy endpoint as a fallback and log both responses.
    if (!result.ok && result.statusCode == 400) {
      try {
        debugPrint('Primary create_pallet returned 400: ${result.body}');
      } catch (_) {}

      // Try legacy JSON endpoint first as a direct fallback
      debugPrint('Retrying legacy POST /receiving/create_pallet (JSON)');
      final fallback = await api.client.post(
        '/receiving/create_pallet',
        jsonBody: body,
      );
      try {
        debugPrint(
          'Fallback (JSON) result: ${fallback.statusCode} - ${fallback.body}',
        );
      } catch (_) {}

      if (fallback.ok) {
        result = fallback;
      } else {
        // If JSON attempts failed with 400, the backend may expect
        // multipart/form-data. Try sending form fields (and an attached
        // image if present) as multipart and log the result.
        try {
          debugPrint('Attempting multipart/form-data POST to primary endpoint');
          final fields = <String, String>{
            'wpl_id': wpl,
            'disposition': _effectiveDisposition(),
            'node': _selectedNode ?? 'KSP1',
            'location_no': loc,
          };
          if (notesValue.isNotEmpty) fields['notes'] = notesValue;

          List<int>? fileBytes;
          String? fileName;
          if (_pickedImage != null) {
            try {
              fileBytes = await _pickedImage!.readAsBytes();
              fileName = _pickedImage!.path.split(RegExp(r'[\\/]')).last;
            } catch (_) {}
          }

          final mp = await api.client.postMultipart(
            '/amz/receiving/pallet',
            fields: fields,
            fileFieldName: 'image',
            fileName: fileName,
            fileBytes: fileBytes,
          );
          try {
            debugPrint('Multipart result: ${mp.statusCode} - ${mp.body}');
          } catch (_) {}
          result = mp;
        } catch (e) {
          debugPrint('Multipart attempt failed: $e');
          result = fallback;
        }
      }
    }

    if (result.ok) {
      unawaited(_triggerLatestPalletPrint(silent: true));
    }

    return result;
  }

  Future<ApiResult?> _submitAddUnits() async {
    final wpl = _normalizedWpl();
    if (wpl == null) {
      _showSnack('Se requiere el ID de palet WPL');
      return null;
    }
    if (!_wplPattern.hasMatch(wpl)) {
      _showSnack('El WPL debe seguir el formato WPL-XXXXXXXXXX');
      return null;
    }
    final pn = _partNumberController.text.trim();
    if (pn.isEmpty) {
      _showSnack('El numero de parte es obligatorio');
      return null;
    }
    final qty = int.tryParse(_quantityController.text.trim());
    if (qty == null || qty <= 0) {
      _showSnack('Cantidad no valida');
      return null;
    }
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      final palletResp = await api.client.get('/amz/receiving/pallet/$wpl');
      if (!palletResp.ok) {
        _showSnack('Palet no encontrado o sin acceso');
        return null;
      }
    } catch (e) {
      _showSnack('No se pudo verificar el palet: $e');
      return null;
    }
    final notes = _notesController.text.trim();
    final body = <String, dynamic>{
      'wpl_id': wpl,
      'part_number': pn,
      'quantity': qty,
      'purchase_order': _poController.text.trim().isEmpty
          ? null
          : _poController.text.trim(),
      'notes': notes.isEmpty ? null : notes,
    };
    if (_pickedImage != null) {
      try {
        final bytes = await _pickedImage!.readAsBytes();
        body['image_b64'] = base64Encode(bytes);
        body['image_name'] = _pickedImage!.path.split(RegExp(r'[\\/]')).last;
      } catch (_) {}
    }
    final res = await api.client.post(
      '/amz/receiving/pallet/$wpl/unit',
      jsonBody: body,
    );
    return res;
  }

  Future<ApiResult?> _submitClosePallet() async {
    final wpl = _normalizedWpl();
    if (wpl == null) {
      _showSnack('Se requiere el ID de palet WPL');
      return null;
    }
    if (!_wplPattern.hasMatch(wpl)) {
      _showSnack('El WPL debe seguir el formato WPL-XXXXXXXXXX');
      return null;
    }
    final loc = _destinationLocationController.text.trim();
    if (loc.isEmpty) {
      _showSnack('La ubicacion es obligatoria');
      return null;
    }
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      final palletResp = await api.client.get('/amz/receiving/pallet/$wpl');
      if (!palletResp.ok) {
        _showSnack('Palet no encontrado o sin acceso');
        return null;
      }
    } catch (e) {
      _showSnack('No se pudo verificar el palet: $e');
      return null;
    }
    final res = await api.client.post(
      '/amz/receiving/pallet/$wpl/close',
      jsonBody: {
        'wpl_id': wpl,
        'location_no': loc,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      },
    );
    return res;
  }

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fadeAnim = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeInOutCubic,
    );
    _panelController.forward();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();

    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _headerFade = CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOut,
    );
    _headerController.forward();

    _ensureWplId();

    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  void _changeMode(ReceivingMode m) {
    if (_mode == m) return;
    setState(() {
      _mode = m;
      _action = ReceivingAction.createPallet;
      _palletAction = PalletSpecialAction.purchaseOrder;
    });
    _ensureWplId();
  }

  void _changeAction(ReceivingAction a) {
    if (_action == a) return;
    setState(() => _action = a);
    _ensureWplId();
  }

  String _effectiveDisposition() {
    final base = _selectedDisposition ?? 'Prime';
    if (base == 'Damage' && _damageSubType != null) {
      return 'Damage_${_damageSubType!}';
    }
    return base;
  }

  String _generateWplId() {
    // Bias letters to mimic legacy WPL distributions while keeping digits mixed in.
    final buffer = StringBuffer('WPL-');
    for (var i = 0; i < 10; i++) {
      final pickLetter = _rng.nextDouble() < 0.7;
      if (pickLetter) {
        buffer.write(_wplLetters[_rng.nextInt(_wplLetters.length)]);
      } else {
        buffer.write(_wplDigits[_rng.nextInt(_wplDigits.length)]);
      }
    }
    return buffer.toString();
  }

  void _ensureWplId() {
    if (_action != ReceivingAction.createPallet) return;
    final current = _palletIdController.text.trim().toUpperCase();
    if (current.isNotEmpty && _wplPattern.hasMatch(current)) {
      if (_palletIdController.text != current) {
        _palletIdController.text = current;
      }
      return;
    }
    _assignNewWpl(clearForm: false);
  }

  void _assignNewWpl({required bool clearForm}) {
    _palletIdController.text = _generateWplId();
    if (!clearForm) return;
    setState(() {
      _partNumberController.clear();
      _locationController.clear();
      _notesController.clear();
      _pickedImage = null;
      _selectedDisposition = null;
      _damageSubType = null;
      _selectedNode = null;
    });
  }

  @override
  void dispose() {
    _edgeOverlay?.remove();
    _panelController.dispose();
    _bgController.dispose();
    _headerController.dispose();
    _partNumberController.dispose();
    _locationController.dispose();
    _quantityController.dispose();
    _poController.dispose();
    _palletIdController.dispose();
    _destinationLocationController.dispose();
    _notesController.dispose();
    _wplSsccController.dispose();
    _transferWplController.dispose();
    _transferPartController.dispose();
    _otherPartController.dispose();
    super.dispose();
  }

  void _handleResponse(ApiResult resp, String successMsg) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      _showSnack(successMsg);
      _resetAfterSubmit();
      return;
    }
    String detail = '';
    final body = resp.body;
    if (body != null) {
      try {
        if (body is Map) {
          detail = (body['detail'] ?? body['message'] ?? body['error'] ?? '')
              .toString();
          if (detail.isEmpty && body['errors'] != null)
            detail = body['errors'].toString();
        } else {
          detail = body.toString();
        }
      } catch (_) {
        detail = body.toString();
      }
    }
    if (detail.isEmpty) detail = 'Error desconocido';
    if (detail.length > 220) detail = detail.substring(0, 217) + '...';
    _showSnack('Fallo (${resp.statusCode}) - $detail');
  }

  void _resetAfterSubmit() {
    switch (_action) {
      case ReceivingAction.createPallet:
        // Generate a fresh pallet id and clear related fields.
        _assignNewWpl(clearForm: true);
        break;
      case ReceivingAction.addUnits:
        setState(() {
          _quantityController.clear();
          _partNumberController.clear();
          _poController.clear();
          _notesController.clear();
          _pickedImage = null;
        });
        break;
      case ReceivingAction.closePallet:
        setState(() {
          _palletIdController.clear();
          _destinationLocationController.clear();
          _notesController.clear();
        });
        break;
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: source, imageQuality: 75);
    if (img != null) {
      setState(() => _pickedImage = img);
    }
  }

  Future<void> _pickImageFromFilesystem() async {
    try {
      final res = await FilePicker.platform
          .pickFiles(
            type: FileType.custom,
            allowedExtensions: ['jpg', 'jpeg', 'png'],
            withData: false,
          )
          .timeout(const Duration(seconds: 25));
      if (res != null && res.files.isNotEmpty) {
        final path = res.files.single.path;
        if (path != null) {
          setState(() => _pickedImage = XFile(path));
        }
      } else {
        _showSnack('No se selecciono ningun archivo');
      }
    } on TimeoutException {
      _showSnack('Tiempo de espera agotado al abrir archivos');
    } catch (e) {
      _showSnack('Error al seleccionar archivo: $e');
    }
  }

  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  void _showImageSourcePicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (_isMobilePlatform)
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Camara'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
            ListTile(
              leading: Icon(
                _isMobilePlatform ? Icons.photo_library : Icons.folder_open,
              ),
              title: Text(
                _isMobilePlatform ? 'Galeria' : 'Buscar imagenes (PNG/JPG)',
              ),
              onTap: () {
                Navigator.pop(ctx);
                if (_isMobilePlatform) {
                  _pickImage(ImageSource.gallery);
                } else {
                  _pickImageFromFilesystem();
                }
              },
            ),
            if (_pickedImage != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Quitar imagen'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _pickedImage = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _imagePickerField() {
    final border = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.blueGrey.withOpacity(.3)),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: InkWell(
        onTap: _showImageSourcePicker,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: ShapeDecoration(
            color: Theme.of(context).colorScheme.surface,
            shape: border,
          ),
          child: Row(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.black26,
                  border: Border.all(color: Colors.white10),
                ),
                child: _pickedImage == null
                    ? const Icon(
                        Icons.image_outlined,
                        size: 32,
                        color: Colors.white54,
                      )
                    : FutureBuilder<Uint8List>(
                        future: _pickedImage!.readAsBytes(),
                        builder: (c, snap) {
                          if (!snap.hasData) {
                            return const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(snap.data!, fit: BoxFit.cover),
                          );
                        },
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Imagen de la unidad',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _pickedImage == null
                          ? 'Pulsa para capturar o elegir una foto.'
                          : 'Pulsa para cambiar o quitar la foto.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.add_a_photo_outlined, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 1020;
    final compact = size.width < 400;
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: _buildGlassAppBar(context, compact: compact),
      body: Stack(
        children: [
          _ReceivingBackground(animation: _bgController),
          // Soft overlay grid painter (ambient)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _bgController,
                builder: (_, __) {
                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;
                  return CustomPaint(
                    painter: _ReceivingAmbientPainter(
                      progress: _bgController.value,
                      isDark: isDark,
                    ),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SIDE MENU (glass) for wide layouts
                if (isWide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 10, 20),
                    child: _buildSideMenu(),
                  ),
                // MAIN CONTENT
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 18 : 32,
                      compact ? 8 : 24,
                      compact ? 18 : 32,
                      42,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FadeTransition(
                          opacity: _headerFade,
                          child: _TopModeSwitcher(
                            mode: _mode,
                            onChanged: _changeMode,
                          ),
                        ),
                        if (!isWide) ...[
                          const SizedBox(height: 16),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            child: _mode == ReceivingMode.unitCase
                                ? _MobileActionSwitcher(
                                    action: _action,
                                    onChanged: _changeAction,
                                  )
                                : _MobilePalletActionSwitcher(
                                    action: _palletAction,
                                    onChanged: (a) =>
                                        setState(() => _palletAction = a),
                                  ),
                          ),
                        ],
                        const SizedBox(height: 26),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 420),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.04),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: ScaleTransition(
                            key: ValueKey(
                              _mode == ReceivingMode.unitCase
                                  ? 'unit-${_action.name}'
                                  : 'pallet-${_palletAction.name}-${_otherAction.name}',
                            ),
                            scale: _fadeAnim,
                            child: _mode == ReceivingMode.unitCase
                                ? _buildActionPanel()
                                : _buildPalletSpecialPanel(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // EdgeNavHandle moved to OverlayEntry
        ],
      ),
    );
  }

  PreferredSizeWidget _buildGlassAppBar(
    BuildContext context, {
    required bool compact,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayA = isDark
        ? Colors.white.withOpacity(0.07)
        : Colors.black.withOpacity(0.06);
    final overlayB = isDark
        ? Colors.white.withOpacity(0.015)
        : Colors.black.withOpacity(0.02);
    final borderColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.06);
    return PreferredSize(
      preferredSize: const Size.fromHeight(70),
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 8 : 16, 10, compact ? 8 : 16, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: borderColor, width: 1),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [overlayA, overlayB],
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 42),
                  const SizedBox(width: 8),
                  const Hero(
                    tag: 'receivingHero',
                    child: Icon(
                      Icons.local_shipping,
                      size: 26,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  ShaderMask(
                    shaderCallback: (r) => LinearGradient(
                      colors: [primary, Colors.white],
                    ).createShader(r),
                    blendMode: BlendMode.srcIn,
                    child: const Text(
                      'Recepcion',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Actualizar panel',
                    onPressed: () =>
                        setState(() => _panelController.forward(from: 0)),
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSideMenu() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 250, maxWidth: 280),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              // adapt glass look for dark/light themes
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.07)
                    : Colors.black.withOpacity(0.06),
                width: 1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: Theme.of(context).brightness == Brightness.dark
                    ? [
                        Colors.white.withOpacity(0.07),
                        Colors.white.withOpacity(0.02),
                      ]
                    : [
                        Colors.white.withOpacity(0.92),
                        Colors.white.withOpacity(0.98),
                      ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black.withOpacity(0.4)
                      : Colors.black.withOpacity(0.06),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SideMenuHeader(title: 'Modos'),
                  const SizedBox(height: 8),
                  _SideMenuTile(
                    selected: _mode == ReceivingMode.unitCase,
                    icon: Icons.inventory_2_outlined,
                    title: 'Unidad / Caja',
                    subtitle: 'Recepcion detallada',
                    onTap: () => _changeMode(ReceivingMode.unitCase),
                  ),
                  _SideMenuTile(
                    selected: _mode == ReceivingMode.pallet,
                    icon: Icons.widgets_outlined,
                    title: 'Palet',
                    subtitle: 'Recepcion por lotes',
                    onTap: () => _changeMode(ReceivingMode.pallet),
                  ),
                  const SizedBox(height: 28),
                  _SideMenuHeader(title: 'Acciones'),
                  const SizedBox(height: 8),
                  if (_mode == ReceivingMode.unitCase) ...[
                    _SideMenuTile(
                      selected: _action == ReceivingAction.createPallet,
                      icon: Icons.add_box_outlined,
                      title: 'Crear palet',
                      subtitle: 'Nuevo contenedor',
                      onTap: () => _changeAction(ReceivingAction.createPallet),
                    ),
                    _SideMenuTile(
                      selected: _action == ReceivingAction.addUnits,
                      icon: Icons.playlist_add,
                      title: 'Agregar unidades',
                      subtitle: 'Escanear articulos',
                      onTap: () => _changeAction(ReceivingAction.addUnits),
                    ),
                    _SideMenuTile(
                      selected: _action == ReceivingAction.closePallet,
                      icon: Icons.lock_outline,
                      title: 'Cerrar palet',
                      subtitle: 'Finalizar',
                      onTap: () => _changeAction(ReceivingAction.closePallet),
                    ),
                  ] else ...[
                    _SideMenuTile(
                      selected:
                          _palletAction == PalletSpecialAction.purchaseOrder,
                      icon: Icons.receipt_long_outlined,
                      title: 'Pedido',
                      subtitle: 'Registrar WPL SSCC',
                      onTap: () => setState(
                        () => _palletAction = PalletSpecialAction.purchaseOrder,
                      ),
                    ),
                    _SideMenuTile(
                      selected: _palletAction == PalletSpecialAction.transfer,
                      icon: Icons.transform_outlined,
                      title: 'Transferencia',
                      subtitle: 'WPL + referencia',
                      onTap: () => setState(
                        () => _palletAction = PalletSpecialAction.transfer,
                      ),
                    ),
                    _SideMenuTile(
                      selected: _palletAction == PalletSpecialAction.other,
                      icon: Icons.category_outlined,
                      title: 'Otro',
                      subtitle: 'Componente/Material',
                      onTap: () => setState(
                        () => _palletAction = PalletSpecialAction.other,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionPanel() {
    return _GlassPanel(
      title: _panelTitle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _panelSubtitle(),
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 20),
          ..._panelFields(),
          const SizedBox(height: 20),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isSubmitting ? 'Trabajando...' : 'Enviar'),
              ),
              const SizedBox(width: 12),
              if (_action == ReceivingAction.createPallet)
                OutlinedButton.icon(
                  onPressed: _isPrintingLatest
                      ? null
                      : () => _triggerLatestPalletPrint(),
                  icon: _isPrintingLatest
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_outlined),
                  label: Text(
                    _isPrintingLatest ? 'Imprimiendo...' : 'Imprimir ultimo',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // New pallet special panel (mock actions)
  Widget _buildPalletSpecialPanel() {
    return _GlassPanel(
      title: _palletPanelTitle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _palletPanelSubtitle(),
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 20),
          ..._palletPanelFields(),
          const SizedBox(height: 20),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitPalletMock,
                icon: _isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isSubmitting ? 'Trabajando...' : 'Enviar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _palletPanelTitle() {
    switch (_palletAction) {
      case PalletSpecialAction.purchaseOrder:
        return 'Registro de pedido (Simulado)';
      case PalletSpecialAction.transfer:
        return 'Transferencia (Simulada)';
      case PalletSpecialAction.other:
        return 'Otro (${_otherActionLabel(_otherAction)}) (Simulado)';
    }
  }

  String _palletPanelSubtitle() {
    switch (_palletAction) {
      case PalletSpecialAction.purchaseOrder:
        return 'Introduce el WPL SSCC para registrar (placeholder).';
      case PalletSpecialAction.transfer:
        return 'Introduce WPL y ASIN / referencia para la transferencia (simulado).';
      case PalletSpecialAction.other:
        return 'Selecciona el subtipo y escribe la referencia (simulado).';
    }
  }

  String _otherActionLabel(OtherMockAction action) {
    switch (action) {
      case OtherMockAction.component:
        return 'Componente';
      case OtherMockAction.material:
        return 'Material';
      case OtherMockAction.sidelined:
        return 'Apartado';
    }
  }

  List<Widget> _palletPanelFields() {
    switch (_palletAction) {
      case PalletSpecialAction.purchaseOrder:
        return [
          _ControlledField(label: 'WPL SSCC', controller: _wplSsccController),
          const _MockInfoNote(),
        ];
      case PalletSpecialAction.transfer:
        return [
          _ControlledField(label: 'WPL', controller: _transferWplController),
          _ControlledField(
            label: 'ASIN / referencia',
            controller: _transferPartController,
          ),
          const _MockInfoNote(),
        ];
      case PalletSpecialAction.other:
        return [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniToggleChip(
                label: _otherActionLabel(OtherMockAction.component),
                selected: _otherAction == OtherMockAction.component,
                onTap: () =>
                    setState(() => _otherAction = OtherMockAction.component),
              ),
              _MiniToggleChip(
                label: _otherActionLabel(OtherMockAction.material),
                selected: _otherAction == OtherMockAction.material,
                onTap: () =>
                    setState(() => _otherAction = OtherMockAction.material),
              ),
              _MiniToggleChip(
                label: _otherActionLabel(OtherMockAction.sidelined),
                selected: _otherAction == OtherMockAction.sidelined,
                onTap: () =>
                    setState(() => _otherAction = OtherMockAction.sidelined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ControlledField(
            label: 'Numero de parte',
            controller: _otherPartController,
          ),
          const _MockInfoNote(),
        ];
    }
  }

  Future<void> _submitPalletMock() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(milliseconds: 400));
    try {
      switch (_palletAction) {
        case PalletSpecialAction.purchaseOrder:
          final v = _wplSsccController.text.trim();
          if (v.isEmpty) {
            _showSnack('Se requiere el WPL SSCC');
            return;
          }
          _showSnack('Pedido simulado registrado para $v');
          _wplSsccController.clear();
          break;
        case PalletSpecialAction.transfer:
          final w = _transferWplController.text.trim();
          final p = _transferPartController.text.trim();
          if (w.isEmpty || p.isEmpty) {
            _showSnack('Se requieren el WPL y la referencia');
            return;
          }
          _showSnack('Transferencia simulada: $p desde $w');
          _transferWplController.clear();
          _transferPartController.clear();
          break;
        case PalletSpecialAction.other:
          final pn = _otherPartController.text.trim();
          if (pn.isEmpty) {
            _showSnack('Se requiere el numero de parte');
            return;
          }
          final tipo = _otherActionLabel(_otherAction).toLowerCase();
          _showSnack('Registro simulado $tipo guardado para $pn');
          _otherPartController.clear();
          break;
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _panelTitle() {
    switch (_action) {
      case ReceivingAction.createPallet:
        return _mode == ReceivingMode.pallet
            ? 'Crear nuevo palet'
            : 'Crear palet (Unidad/Caja)';
      case ReceivingAction.addUnits:
        return 'Agregar unidades';
      case ReceivingAction.closePallet:
        return 'Cerrar palet';
    }
  }

  String _panelSubtitle() {
    switch (_action) {
      case ReceivingAction.createPallet:
        return 'Escanea el ASIN o UPC (o introducelo manualmente).';
      case ReceivingAction.addUnits:
        return 'Introduce WPL, referencia, cantidad, P/O opcional y adjunta una imagen.';
      case ReceivingAction.closePallet:
        return 'Introduce WPL, ubicacion final y notas opcionales para cerrar el palet.';
    }
  }

  List<Widget> _panelFields() {
    switch (_action) {
      case ReceivingAction.createPallet:
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: TextField(
              controller: _palletIdController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'ID de palet WPL *',
                suffixIcon: IconButton(
                  tooltip: 'Generar WPL',
                  icon: const Icon(Icons.autorenew),
                  onPressed: () => _assignNewWpl(clearForm: false),
                ),
              ),
            ),
          ),
          _DropdownField(
            label: 'Disposicion del palet *',
            items: _dispositionOptions,
            onChanged: (v) => setState(() {
              _selectedDisposition = v;
              _damageSubType = null;
            }),
            value: _selectedDisposition,
            displayLabels: _dispositionLabels,
          ),
          if ((_selectedDisposition ?? '') == 'Damage')
            _DamageSubtypeSelector(
              value: _damageSubType,
              onChanged: (v) => setState(() => _damageSubType = v),
            ),
          _DropdownField(
            label: 'Nodo *',
            items: const ['KSP1', 'KSP2', 'KSP5', 'KSP6'],
            onChanged: (v) => setState(() => _selectedNode = v),
            value: _selectedNode,
          ),
          _ControlledField(
            label: 'Ubicacion *',
            controller: _locationController,
          ),
          _imagePickerField(),
          _ControlledField(
            label: 'Notas (opcional)',
            controller: _notesController,
          ),
        ];
      case ReceivingAction.addUnits:
        return [
          _ControlledField(
            label: 'ID de palet WPL',
            controller: _palletIdController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
              LengthLimitingTextInputFormatter(14),
            ],
          ),
          _ControlledField(
            label: 'Referencia (P/N)',
            controller: _partNumberController,
          ),
          _ControlledField(label: 'Cantidad', controller: _quantityController),
          _ControlledField(label: 'P/O (opcional)', controller: _poController),
          _imagePickerField(),
          _ControlledField(
            label: 'Notas (opcional)',
            controller: _notesController,
          ),
        ];
      case ReceivingAction.closePallet:
        return [
          _ControlledField(
            label: 'ID de palet WPL',
            controller: _palletIdController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
              LengthLimitingTextInputFormatter(14),
            ],
          ),
          _ControlledField(
            label: 'Ubicacion *',
            controller: _destinationLocationController,
          ),
          _ControlledField(
            label: 'Notas (opcional)',
            controller: _notesController,
          ),
        ];
    }
  }
}

// Reuse small helpers from legacy file (kept local to this screen)

class _ControlledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  const _ControlledField({
    required this.label,
    required this.controller,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final List<String> items;
  final void Function(String?)? onChanged;
  final String? value;
  final Map<String, String>? displayLabels;
  const _DropdownField({
    required this.label,
    required this.items,
    this.onChanged,
    this.value,
    this.displayLabels,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: DropdownButtonFormField<String>(
        value: value,
        items: items
            .map(
              (e) => DropdownMenuItem<String>(
                value: e,
                child: Text(displayLabels?[e] ?? e),
              ),
            )
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _SideMenuHeader extends StatelessWidget {
  final String title;
  const _SideMenuHeader({required this.title});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4.0),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: .5,
      ),
    ),
  );
}

class _SideMenuTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SideMenuTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected ? cs.primary.withOpacity(.18) : cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? cs.primary : Colors.blueGrey.withOpacity(.25),
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected ? cs.primary : Colors.blueAccent,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopModeSwitcher extends StatelessWidget {
  final ReceivingMode mode;
  final ValueChanged<ReceivingMode> onChanged;
  const _TopModeSwitcher({required this.mode, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      children: [
        _ChipToggle(
          label: 'Unidad / Caja',
          selected: mode == ReceivingMode.unitCase,
          onTap: () => onChanged(ReceivingMode.unitCase),
        ),
        _ChipToggle(
          label: 'Palet',
          selected: mode == ReceivingMode.pallet,
          onTap: () => onChanged(ReceivingMode.pallet),
        ),
      ],
    );
  }
}

class _ChipToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChipToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withOpacity(.2) : cs.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected ? cs.primary : Colors.blueGrey.withOpacity(.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? cs.primary : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final String title;
  final Widget child;
  const _GlassPanel({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayA = isDark
        ? Colors.white.withOpacity(0.07)
        : Colors.black.withOpacity(0.06);
    final overlayB = isDark
        ? Colors.white.withOpacity(0.015)
        : Colors.black.withOpacity(0.02);
    final borderColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.06);
    final shadow = isDark
        ? Colors.black.withOpacity(0.45)
        : Colors.black.withOpacity(0.08);
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(30, 30, 30, 34),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: borderColor, width: 1),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [overlayA, overlayB],
            ),
            boxShadow: [
              BoxShadow(
                color: shadow,
                blurRadius: 36,
                spreadRadius: 2,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bubble_chart,
                    size: 22,
                    color: primary.withOpacity(0.9),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

// === Ambient Background Widgets ===
class _ReceivingBackground extends StatelessWidget {
  final Animation<double> animation;
  const _ReceivingBackground({required this.animation});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final colors = isDark
            ? [
                Color.lerp(primary.withOpacity(0.95), Colors.black, 0.4)!,
                Color.lerp(Colors.black, secondary.withOpacity(0.6), 0.25)!,
                Colors.black,
              ]
            : [
                Colors.white,
                Color.lerp(Colors.white, secondary.withOpacity(0.06), 0.15)!,
                Colors.white,
              ];
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
        );
      },
    );
  }
}

class _ReceivingAmbientPainter extends CustomPainter {
  final double progress;
  final bool isDark;
  _ReceivingAmbientPainter({required this.progress, this.isDark = true});
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.055);
    const spacing = 90.0;
    final shift = progress * spacing;
    for (double x = -spacing + shift; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x - 50, size.height), gridPaint);
    }
    for (double y = -spacing + shift; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 50), gridPaint);
    }
    final glowCenter = Offset(
      size.width * (0.5 + 0.22 * math.sin(progress * 2 * math.pi)),
      size.height * 0.33,
    );
    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              (isDark ? Colors.white : Colors.black).withOpacity(0.09),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(center: glowCenter, radius: size.width * 0.9),
          );
    canvas.drawCircle(glowCenter, size.width * 0.9, glow);
  }

  @override
  bool shouldRepaint(covariant _ReceivingAmbientPainter oldDelegate) => true;
}

class _DamageSubtypeSelector extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _DamageSubtypeSelector({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: const InputDecoration(labelText: 'Subtipo de danio'),
        items: const [
          DropdownMenuItem(value: 'Ungraded', child: Text('Sin clasificar')),
          DropdownMenuItem(value: 'Rebox', child: Text('Reparar caja')),
          DropdownMenuItem(value: 'Recycle', child: Text('Reciclar')),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _MobileActionSwitcher extends StatelessWidget {
  final ReceivingAction action;
  final ValueChanged<ReceivingAction> onChanged;
  const _MobileActionSwitcher({required this.action, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionChip(
          label: 'Crear',
          icon: Icons.add_box_outlined,
          selected: action == ReceivingAction.createPallet,
          onTap: () => onChanged(ReceivingAction.createPallet),
        ),
        _ActionChip(
          label: 'Agregar unidades',
          icon: Icons.playlist_add,
          selected: action == ReceivingAction.addUnits,
          onTap: () => onChanged(ReceivingAction.addUnits),
        ),
        _ActionChip(
          label: 'Cerrar',
          icon: Icons.lock_outline,
          selected: action == ReceivingAction.closePallet,
          onTap: () => onChanged(ReceivingAction.closePallet),
        ),
      ],
    );
  }
}

class _MobilePalletActionSwitcher extends StatelessWidget {
  final PalletSpecialAction action;
  final ValueChanged<PalletSpecialAction> onChanged;
  const _MobilePalletActionSwitcher({
    required this.action,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionChip(
          label: 'Pedido',
          icon: Icons.receipt_long_outlined,
          selected: action == PalletSpecialAction.purchaseOrder,
          onTap: () => onChanged(PalletSpecialAction.purchaseOrder),
        ),
        _ActionChip(
          label: 'Transferencia',
          icon: Icons.transform_outlined,
          selected: action == PalletSpecialAction.transfer,
          onTap: () => onChanged(PalletSpecialAction.transfer),
        ),
        _ActionChip(
          label: 'Otro',
          icon: Icons.category_outlined,
          selected: action == PalletSpecialAction.other,
          onTap: () => onChanged(PalletSpecialAction.other),
        ),
      ],
    );
  }
}

class _MiniToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MiniToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withOpacity(.25) : cs.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? cs.primary : Colors.blueGrey.withOpacity(.35),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? cs.primary : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _MockInfoNote extends StatelessWidget {
  const _MockInfoNote();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(.4)),
      ),
      child: const Text(
        'Implementacion simulada: aun sin llamada a backend. Los valores no se guardan.',
        style: TextStyle(fontSize: 12, color: Colors.orangeAccent),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withOpacity(.25) : cs.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: selected ? cs.primary : Colors.blueGrey.withOpacity(.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? cs.primary : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? cs.primary : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
