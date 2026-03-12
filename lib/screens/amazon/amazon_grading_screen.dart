import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../../services/api_service.dart';
import '../../widgets/main_sidebar.dart';
import '../../widgets/animated_background.dart';
import 'dart:ui';
import 'package:flutter/cupertino.dart'; // For macOS controls
import '../../themes/amazon_theme.dart';
import 'amz_find_dsn_screen.dart';

typedef JsonMap = Map<String, dynamic>;

class AmazonGradingScreen extends StatefulWidget {
  const AmazonGradingScreen({super.key});

  @override
  State<AmazonGradingScreen> createState() => _AmazonGradingScreenState();
}

class _AmazonGradingScreenState extends State<AmazonGradingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _focusRoot = FocusNode();

  bool _loading = true;
  bool _submitting = false;
  bool _showOverlay = false;
  bool _showErrorOverlay = false;
  String? errorMessage;
  String? bucket;

  Timer? _overlayTimer;
  OverlayEntry? _edgeOverlay;

  List<String> _fcOptions = [];
  String? _selectedFc;

  final _dsnController = TextEditingController();
  final _upcController = TextEditingController();
  final _dsnFocus = FocusNode();
  final _upcFocus = FocusNode();
  final _fcFocus = FocusNode();

  bool _isAccessory = false;
  int _labelOutCount = 0;

  final Map<String, String> _checkLabels = {
    'Factory_Seal_Intact': 'Sello OK',
    'Sticker_In_BB': 'Etiq/Imagen',
    'Corner_Crush': 'Golpe',
    'Rip_Tear_Scuff': 'Rotura/Rayón',
    'Holes': 'Agujero',
    'Dust_On_Beauty_Box': 'Polvo',
    'Water_Oil_Damage': 'Agua/Aceite',
    'Corner_Crush2': 'Golpe Grande',
    'Rip_Tear_Scuff2': 'Rotura/Rayón Grande',
    'Holes2': 'Agujero Grande',
    'sioc_unwrapped': 'SIOC Unwrapped',
    'label_out': 'Label Out',
    'Extreme_Damage': 'Caja Muy Rota/En Bolsa',
  };

  final Map<String, bool> _checks = {
    'Factory_Seal_Intact': false,
    'Sticker_In_BB': false,
    'Corner_Crush': false,
    'Rip_Tear_Scuff': false,
    'Holes': false,
    'Dust_On_Beauty_Box': false,
    'Water_Oil_Damage': false,
    'Corner_Crush2': false,
    'Rip_Tear_Scuff2': false,
    'Holes2': false,
    'sioc_unwrapped': false,
    'label_out': false,
    'Extreme_Damage': false,
  };

  final _leftKeys = [
    'Factory_Seal_Intact',
    'Sticker_In_BB',
    'Corner_Crush',
    'Rip_Tear_Scuff',
    'Holes',
    'label_out',
  ];
  final _rightKeys = [
    'Extreme_Damage',
    'Water_Oil_Damage',
    'Corner_Crush2',
    'Rip_Tear_Scuff2',
    'Holes2',
    'sioc_unwrapped',
    'Dust_On_Beauty_Box',
  ];

  @override
  void initState() {
    super.initState();
    _fetchFcOptions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_dsnFocus);

      // Insert a top-level overlay entry for the sidebar handle so it sits
      // above all other UI and reliably receives hover/click events.
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
    _overlayTimer?.cancel();
    _focusRoot.dispose();
    _dsnController.dispose();
    _upcController.dispose();
    _dsnFocus.dispose();
    _upcFocus.dispose();
    _fcFocus.dispose();
    // remove overlay handle if present
    _edgeOverlay?.remove();
    _edgeOverlay = null;
    super.dispose();
  }

  Future<void> _fetchFcOptions() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.client.loadCookiesFromStorage();
      // Changed from /amz/grading/options to /amz/grading/transfers per user request
      final res = await api.client.get('/amz/grading/transfers');

      if (res.ok && res.body is Map) {
        final data = res.body as JsonMap;
        // The new endpoint returns { "records": [ ... ] }
        final records = data['records'];
        List<String> extractedFcs = [];

        if (records is List) {
          final uniqueFcs = <String>{};
          for (var item in records) {
            if (item is Map) {
              final nameFile = item['name_file']?.toString();
              if (nameFile != null && nameFile.isNotEmpty) {
                // Use the full filename as requested by the user
                uniqueFcs.add(nameFile);
              }
            }
          }
          extractedFcs = uniqueFcs.toList()..sort();
        }

        // Only update state if we found valid FCs
        if (extractedFcs.isNotEmpty) {
          setState(() {
            _fcOptions = extractedFcs;
            _loading = false;
          });
          return;
        }
      }

      debugPrint('Error or empty transfers fetching FCs: ${res.statusCode}');
      // Fallback only if strictly necessary (network error), but user prefers endpoint data.
      // If endpoint returns empty list, we show empty.
      if (!res.ok) {
        _useFallbackFcOptions();
      } else {
        // Response OK but no data found -> Empty list (correct behavior)
        setState(() {
          _fcOptions = [];
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Exception loading FCs from transfers: $e');
      _useFallbackFcOptions();
    }
  }

  void _useFallbackFcOptions() {
    if (!mounted) return;
    setState(() {
      _fcOptions = ['BCN1', 'BCN2', 'BCN3', 'MAD4', 'SVQ1', 'VLC1', 'OTHERS'];
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || _selectedFc == null) {
      return;
    }
    _formKey.currentState?.save();

    setState(() {
      _submitting = true;
      bucket = null;
      errorMessage = null;
    });

    final body = <String, dynamic>{
      'DSN_Scan': _dsnController.text.toUpperCase(),
      'UPC_Scan': _upcController.text.toUpperCase(),
      'FC_Origin': _selectedFc,
      'Is_Accessory': _isAccessory ? 1 : 0,
      'label_out': _labelOutCount,
    };
    _checks.forEach((k, v) {
      if (k != 'label_out') body[k] = v ? 1 : 0;
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post('/amz/grading', jsonBody: body);
      final data = res.body;

      if (res.statusCode == 409 &&
          data is Map &&
          data['reset_fields'] == true) {
        _triggerErrorOverlay(
          resetFields: true,
          error: data['error']?.toString(),
        );
        return;
      }

      if (res.ok) {
        _dsnController.clear();
        _upcController.clear();
        setState(
          () =>
              bucket = (data is Map) ? data['grading_bucket'] as String? : null,
        );
        _triggerOverlay();
      } else {
        String? msg;
        if (data is Map) {
          for (final key in ['error_message', 'error', 'message', 'detail']) {
            final value = data[key];
            if (value is String && value.trim().isNotEmpty) {
              msg = value;
              break;
            }
          }
        }
        msg ??= res.error ?? 'Error servidor';
        _triggerErrorOverlay(error: msg);
      }
    } catch (e) {
      _triggerErrorOverlay(error: 'Error de red');
    } finally {
      setState(() {
        _submitting = false;
        _isAccessory = false;
      });
    }
  }

  void _triggerOverlay() {
    _overlayTimer?.cancel();
    setState(() {
      _showOverlay = true;
      FocusScope.of(context).requestFocus(_dsnFocus);
    });
    _overlayTimer = Timer(const Duration(seconds: 2), () {
      _overlayTimer = null;
      setState(() {
        _showOverlay = false;
        _checks.updateAll((_, __) => false);
        _labelOutCount = 0;
      });
      FocusScope.of(context).requestFocus(_dsnFocus);
    });
  }

  void _triggerErrorOverlay({bool resetFields = false, String? error}) {
    if (resetFields) {
      _formKey.currentState?.reset();
      _dsnController.clear();
      _upcController.clear();
      setState(() {
        _selectedFc = null;
        _checks.updateAll((k, v) => false);
        errorMessage = error;
      });
    } else {
      setState(() => errorMessage = error);
    }
    setState(() {
      _showErrorOverlay = true;
      FocusScope.of(context).requestFocus(_dsnFocus);
    });
    Timer(const Duration(seconds: 2), () {
      setState(() => _showErrorOverlay = false);
      FocusScope.of(context).requestFocus(_dsnFocus);
    });
  }

  Color _colorForBucket(String? b) {
    switch (b) {
      case 'PRIME':
        return Colors.green;
      case 'WOOT':
        return Colors.yellow.shade700;
      case 'VAS':
        return Colors.blue;
      case 'RECYCLE':
        return Colors.red;
      case 'RECYCLE DISCONTINUED':
        return Colors.purple;
      case 'RETURN':
        return Colors.orangeAccent;
      default:
        return Colors.black87;
    }
  }

  Future<void> _pickLabelOut() async {
    final count = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Labels quitadas'),
        children: List.generate(
          5,
          (i) => SimpleDialogOption(
            child: Text('${i + 1}'),
            onPressed: () => Navigator.pop(ctx, i + 1),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (count != null) setState(() => _labelOutCount = count);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final buttonHeight = isTablet ? screenHeight * .10 : screenHeight * .08;
    final fontIn = isTablet ? screenHeight * .025 : screenHeight * .020;
    final fontLbl = fontIn * .9;
    final switchScale = isTablet ? 2.0 : 1.5;

    return AmazonTheme(
      child: Builder(
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final colorScheme = theme.colorScheme;

          return Focus(
            focusNode: _focusRoot,
            child: Scaffold(
              backgroundColor: theme.scaffoldBackgroundColor,
              body: Stack(
                children: [
                  // Animated background behind everything
                  const Positioned.fill(
                    child: AnimatedBackgroundWidget(intensity: 0.8),
                  ),

                  // Content
                  if (_loading)
                    Center(
                      child: CircularProgressIndicator(
                        color: colorScheme.primary,
                      ),
                    )
                  else
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(40, 20, 20, 20),
                        child: _buildForm(
                          fontIn,
                          fontLbl,
                          switchScale,
                          buttonHeight,
                          isTablet,
                          screenHeight,
                        ),
                      ),
                    ),

                  if (_showOverlay && bucket != null)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _overlayTimer?.cancel();
                          _overlayTimer = null;
                          setState(() => _showOverlay = false);
                          FocusScope.of(context).requestFocus(_dsnFocus);
                        },
                        child: Container(
                          color: _colorForBucket(
                            bucket,
                          ).withAlpha((0.9 * 255).round()),
                          child: Center(
                            child: Text(
                              bucket!,
                              style: TextStyle(
                                fontSize: isTablet
                                    ? screenHeight * .14
                                    : screenHeight * .10,
                                fontWeight: FontWeight.bold,
                                color: bucket == 'WOOT'
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  if (_showErrorOverlay && errorMessage != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: true,
                        child: Container(
                          color: Colors.black.withOpacity(0.85),
                          child: Center(
                            child: Text(
                              errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isTablet
                                    ? screenHeight * .06
                                    : screenHeight * .04,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
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

  Widget _buildForm(
    double fontIn,
    double fontLbl,
    double switchScale,
    double buttonHeight,
    bool isTablet,
    double screenHeight,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.center,
              child: Text(
                'Grading Amazon',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            Positioned(
              right: 0,
              child: IconButton(
                icon: Icon(Icons.search, color: colorScheme.onSurface),
                tooltip: 'Buscar DSN',
                onPressed: _openFindDsn,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? Colors.black.withOpacity(0.2)
                      : Colors.white.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (errorMessage != null) _errorBanner(),

                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _buildMacInput(
                                    controller: _dsnController,
                                    focusNode: _dsnFocus,
                                    label: 'DSN',
                                    icon: Icons.qr_code,
                                    fontIn: fontIn,
                                    autoFocus: true,
                                    textInputAction: TextInputAction.next,
                                    onSubmitted: (_) async {
                                      final dsn = _dsnController.text
                                          .trim()
                                          .toUpperCase();
                                      if (dsn.startsWith('KSP')) {
                                        final answer = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text(
                                              '¿Es un accesorio?',
                                            ),
                                            content: const Text(
                                              'El DSN inicia con KSP. ¿Es un accesorio?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(
                                                  context,
                                                ).pop(false),
                                                child: const Text('No'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.of(
                                                  context,
                                                ).pop(true),
                                                child: const Text('Sí'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (!mounted) return;
                                        setState(
                                          () => _isAccessory = answer == true,
                                        );
                                      } else {
                                        _isAccessory = false;
                                      }
                                      FocusScope.of(
                                        context,
                                      ).requestFocus(_upcFocus);
                                    },
                                    validator: (v) => (v == null || v.isEmpty)
                                        ? 'Requerido'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildMacInput(
                                    controller: _upcController,
                                    focusNode: _upcFocus,
                                    label: 'UPC',
                                    icon: Icons.confirmation_number,
                                    fontIn: fontIn,
                                    textInputAction: TextInputAction.next,
                                    onSubmitted: (_) => FocusScope.of(
                                      context,
                                    ).requestFocus(_fcFocus),
                                    validator: (v) => (v == null || v.isEmpty)
                                        ? 'Requerido'
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              focusNode: _fcFocus,
                              isExpanded: true,
                              icon: Icon(
                                Icons.unfold_more_rounded,
                                color: colorScheme.onSurface.withOpacity(0.5),
                                size: 20,
                              ),
                              style: TextStyle(
                                fontSize: fontIn,
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              dropdownColor: theme.cardColor,
                              decoration: InputDecoration(
                                labelText: 'FC Origen / Transfer File',
                                labelStyle: TextStyle(
                                  fontSize: fontLbl,
                                  color: colorScheme.onSurface.withOpacity(0.6),
                                ),
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
                              selectedItemBuilder: (context) {
                                return _fcOptions.map((String item) {
                                  return Text(
                                    item,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: fontIn,
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  );
                                }).toList();
                              },
                              items: _fcOptions.map((o) {
                                final isLast = o == _fcOptions.last;
                                return DropdownMenuItem(
                                  value: o,
                                  child: Container(
                                    width: double.infinity,
                                    alignment: Alignment.centerLeft,
                                    decoration: isLast
                                        ? null
                                        : BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: colorScheme.onSurface
                                                    .withOpacity(0.1),
                                                width: 0.5,
                                              ),
                                            ),
                                          ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ), // Slight padding adjustment
                                    child: Text(
                                      o,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                );
                              }).toList(),
                              initialValue: _selectedFc,
                              onChanged: (v) => setState(() => _selectedFc = v),
                              validator: (v) => v == null ? 'Seleccione' : null,
                            ),
                            const SizedBox(height: 24),
                            // Checks Grid
                            Builder(
                              builder: (_) {
                                final maxLen = math.max(
                                  _leftKeys.length,
                                  _rightKeys.length,
                                );
                                return Column(
                                  children: List.generate(
                                    maxLen,
                                    (i) => Row(
                                      children: [
                                        Expanded(
                                          child: i < _leftKeys.length
                                              ? _boxedSwitch(
                                                  _leftKeys[i],
                                                  fontLbl,
                                                  switchScale,
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                        Expanded(
                                          child: i < _rightKeys.length
                                              ? _boxedSwitch(
                                                  _rightKeys[i],
                                                  fontLbl,
                                                  switchScale,
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 32),
                            Container(
                              width: double.infinity,
                              height: buttonHeight,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: LinearGradient(
                                  colors: [
                                    colorScheme.primary,
                                    colorScheme.primary.withOpacity(0.8),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: colorScheme.primary.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: _submitting ? null : _submit,
                                borderRadius: BorderRadius.circular(12),
                                child: _submitting
                                    ? const CupertinoActivityIndicator(
                                        color: Colors.white,
                                      )
                                    : Text(
                                        'Enviar Grading',
                                        style: TextStyle(
                                          fontSize: fontIn,
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

                      const SizedBox(height: 16),
                      if (bucket != null) _resultCard(fontIn),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openFindDsn() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AmzFindDsnScreen()));
  }

  Widget _boxedSwitch(String key, double fontSize, double scale) => Container(
    margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: scale * 0.8, // Slightly smaller for Cupertino
          child: CupertinoSwitch(
            value: key == 'label_out'
                ? (_labelOutCount > 0)
                : (_checks[key] ?? false),
            activeTrackColor: Theme.of(context).colorScheme.primary,
            onChanged: (v) async {
              if (key == 'label_out') {
                if (v) {
                  await _pickLabelOut();
                  setState(() {
                    _checks['label_out'] = _labelOutCount > 0;
                  });
                } else {
                  setState(() {
                    _labelOutCount = 0;
                    _checks['label_out'] = false;
                  });
                }
              } else {
                setState(() => _checks[key] = v);
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          key == 'label_out'
              ? 'Label Out${_labelOutCount > 0 ? ': $_labelOutCount' : ''}'
              : _checkLabels[key]!,
          style: TextStyle(fontSize: fontSize),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _errorBanner() => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.error,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(Icons.error, color: Theme.of(context).colorScheme.onError),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            errorMessage ?? '',
            style: TextStyle(color: Theme.of(context).colorScheme.onError),
          ),
        ),
      ],
    ),
  );

  Widget _buildMacInput({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    required double fontIn,
    bool autoFocus = false,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    FormFieldValidator<String>? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autoFocus,
      style: TextStyle(
        fontSize: fontIn,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: fontIn * 0.9,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        ),
        hintStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
        ),
        filled: true,
        fillColor: isDark
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
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
        suffixIcon: Icon(
          icon,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          size: 20,
        ),
      ),
    );
  }

  Widget _resultCard(double fontSize) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 8,
    color: Theme.of(context).cardColor,
    shadowColor: Colors.black.withOpacity(0.2),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            'RESULTADO',
            style: TextStyle(
              fontSize: fontSize * 0.6,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$bucket',
            style: TextStyle(
              fontSize: fontSize * 1.5,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    ),
  );
}
