import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:configtool_granite_frontend/services/api_service.dart';
import '../../widgets/main_sidebar.dart';
import '../../main.dart';

// Server base URL
import '../../config.dart';

const String baseUrl = kBackendBaseUrl;

class AsinFlipForm extends StatefulWidget {
  const AsinFlipForm({super.key});

  @override
  State<AsinFlipForm> createState() => _AsinFlipFormState();
}

class _AsinFlipFormState extends State<AsinFlipForm> {
  OverlayEntry? _edgeOverlay;

  @override
  void initState() {
    super.initState();
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
                    user: ApiService.instance?.currentUser,
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

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _dsnController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // 9 preguntas binarias: 7 originales + 2 de labeling
  final List<bool?> _preguntasBinarias = List<bool?>.filled(9, null);

  String? _wrapPuesto;
  String? _incidenciaCorregida;

  final List<String> _opcionesWrap = ['Sí', 'No', 'No aplica'];
  final List<String> _opcionesIncidencia = ['Sí', 'No', 'No aplica'];

  bool _isSaving = false;

  Future<void> _enviarFormulario() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final formData = <String, String>{
        'DSN': _dsnController.text.trim(),
        'Caja master cambiada': _preguntasBinarias[0]! ? 'Sí' : 'No',
        'Etiqueta correcta': _preguntasBinarias[1]! ? 'Sí' : 'No',
        'Relleno adecuado': _preguntasBinarias[2]! ? 'Sí' : 'No',
        'Sello correcto': _preguntasBinarias[3]! ? 'Sí' : 'No',
        'Cable de alimentación': _preguntasBinarias[4]! ? 'Sí' : 'No',
        'Petaca de alimentación': _preguntasBinarias[5]! ? 'Sí' : 'No',
        'Tamaño de elementos gráficos correcto': _preguntasBinarias[6]!
            ? 'Sí'
            : 'No',
        'Wrap puesto': _wrapPuesto!,
        'Incidencia corregida': _incidenciaCorregida!,
        'Longitud UPC correcta': _preguntasBinarias[7]! ? 'Sí' : 'No',
        'Longitud DSN correcta': _preguntasBinarias[8]! ? 'Sí' : 'No',
      };
      final now = DateTime.now();
      final formattedDate =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      sheet.appendRow(['Quality Check - ASIN Flip - $formattedDate', '']);
      sheet.appendRow(['Campo', 'Valor']);
      for (final entry in formData.entries) {
        sheet.appendRow([entry.key, entry.value]);
      }
      final bytes = excel.encode()!;
      final filename = 'asin_flip_qc_$formattedDate.xlsx';
      final api = ApiService.instance;
      if (api != null) {
        final result = await api.client.postMultipart(
          '/amz/qc-report',
          fields: {'formType': 'asin_flip', 'timestamp': formattedDate},
          fileFieldName: 'file',
          fileName: filename,
          fileBytes: bytes,
        );
        if (result.ok) {
          String? fileUrl;
          final body = result.body;
          if (body is Map) {
            final raw = body['file_url'];
            if (raw != null) fileUrl = raw.toString();
          }
          globalScaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Text(
                fileUrl != null
                    ? 'QC guardado en: $fileUrl'
                    : 'QC subido correctamente.',
              ),
            ),
          );
        } else {
          final msg =
              result.body ?? result.error ?? 'HTTP ${result.statusCode}';
          globalScaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Error al subir el QC: $msg')),
          );
        }
      } else {
        final uri = Uri.parse('$baseUrl/amz/qc-report');
        final request = http.MultipartRequest('POST', uri)
          ..fields['formType'] = 'asin_flip'
          ..fields['timestamp'] = formattedDate
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: filename,
              contentType: MediaType(
                'application',
                'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              ),
            ),
          );
        final response = await request.send();
        if (response.statusCode == 200) {
          final respStr = await response.stream.bytesToString();
          final jsonResp = jsonDecode(respStr);
          final fileUrl = jsonResp['file_url'];
          globalScaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('QC guardado en: $fileUrl')),
          );
        } else {
          globalScaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Text(
                'Error al subir el QC: HTTP ${response.statusCode}',
              ),
            ),
          );
        }
      }
      _resetForm();
      _scrollToTop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar el QC: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetForm() {
    FocusScope.of(context).unfocus();
    _formKey.currentState?.reset();
    _dsnController.clear();
    setState(() {
      _preguntasBinarias.fillRange(0, _preguntasBinarias.length, null);
      _wrapPuesto = null;
      _incidenciaCorregida = null;
    });
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.minScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildBinaryQuestion(int index, String text, {bool withInfo = false}) {
    final theme = Theme.of(context);
    final isSelected = _preguntasBinarias[index] != null;
    final isYes = _preguntasBinarias[index] == true;
    final isNo = _preguntasBinarias[index] == false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${index + 2}. $text',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (withInfo)
                IconButton(
                  icon: Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.primary,
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        title: const Text('Información'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Ejemplo de buena longitud de etiqueta:',
                            ),
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                'assets/etiqueta_ok.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cerrar'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ChoiceButton(
                label: 'SÍ',
                isSelected: isYes,
                color: Colors.green,
                onTap: () => setState(() => _preguntasBinarias[index] = true),
              ),
              const SizedBox(width: 12),
              _ChoiceButton(
                label: 'NO',
                isSelected: isNo,
                color: Colors.red,
                onTap: () => setState(() => _preguntasBinarias[index] = false),
              ),
            ],
          ),
          if (!isSelected)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                'Este campo es obligatorio',
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _edgeOverlay?.remove();
    _dsnController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final preguntas = [
      '¿La caja master está cambiada?',
      '¿La etiqueta muestra textos correctamente?',
      '¿Tiene puesto el relleno adecuado en la caja?',
      '¿El sello está correctamente puesto?',
      '¿Tiene el cable de alimentación?',
      '¿Tiene la petaca de alimentación?',
      '¿Tamaño de elementos gráficos correcto?',
      '¿Longitud UPC correcta?',
      '¿Longitud DSN correcta?',
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'QC - ASIN Flip',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF0F172A),
                    const Color(0xFF1E293B),
                    const Color(0xFF0F172A),
                  ]
                : [
                    const Color(0xFFF8FAFC),
                    const Color(0xFFE2E8F0),
                    const Color(0xFFF1F5F9),
                  ],
          ),
        ),
        child: SafeArea(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'General Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '1. Leer el DSN del terminal',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _dsnController,
                            maxLines: 2,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: theme.colorScheme.surface.withOpacity(
                                0.5,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              hintText: 'Scan or enter DSN...',
                              contentPadding: const EdgeInsets.all(20),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Este campo es obligatorio'
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Inspection Checklist',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          for (var i = 0; i < preguntas.length; i++)
                            _buildBinaryQuestion(
                              i,
                              preguntas[i],
                              withInfo: i == 7 || i == 8,
                            ),
                          const Divider(height: 48, thickness: 1),
                          const Text(
                            'Final Assessment',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            '10. ¿Wrap puesto?',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: theme.colorScheme.surface.withOpacity(
                                0.5,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                            ),
                            initialValue: _wrapPuesto,
                            items: _opcionesWrap
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _wrapPuesto = v),
                            validator: (v) =>
                                v == null ? 'Este campo es obligatorio' : null,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            '11. ¿Incidencia corregida?',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: theme.colorScheme.surface.withOpacity(
                                0.5,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                            ),
                            initialValue: _incidenciaCorregida,
                            items: _opcionesIncidencia
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _incidenciaCorregida = v),
                            validator: (v) =>
                                v == null ? 'Este campo es obligatorio' : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _SubmitButton(
                    onPressed: _isSaving ? () {} : _enviarFormulario,
                    label: _isSaving ? 'UPLOADING...' : 'SUBMIT QC REPORT',
                    isSaving: _isSaving,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _ChoiceButton({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withOpacity(isDark ? 0.3 : 0.2)
                : (isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.white.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color.withOpacity(0.5) : Colors.transparent,
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: isSelected
                    ? (isDark ? color.withOpacity(0.9) : color.withOpacity(1.0))
                    : theme.textTheme.bodyMedium?.color?.withOpacity(0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  const _GlassPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.white.withOpacity(0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(28), child: child),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  final bool isSaving;

  const _SubmitButton({
    required this.onPressed,
    required this.label,
    this.isSaving = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: isSaving
              ? [Colors.grey, Colors.grey.shade600]
              : [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withOpacity(0.8),
                ],
        ),
        boxShadow: [
          if (!isSaving)
            BoxShadow(
              color: theme.colorScheme.primary.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isSaving ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: isSaving
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
      ),
    );
  }
}
