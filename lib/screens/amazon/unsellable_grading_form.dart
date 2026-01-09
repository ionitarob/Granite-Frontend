import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:configtool_granite_frontend/services/api_service.dart';
import '../../widgets/main_sidebar.dart';
import '../../main.dart';

// Server base URL
import '../../config.dart';

const String baseUrl = kBackendBaseUrl;

class UnsellableGradingForm extends StatefulWidget {
  const UnsellableGradingForm({super.key});

  @override
  State<UnsellableGradingForm> createState() => _UnsellableGradingFormState();
}

class _UnsellableGradingFormState extends State<UnsellableGradingForm> {
  final List<bool?> _respuestas = List.generate(11, (_) => null);
  final List<TextEditingController> _textControllers = List.generate(
    7,
    (_) => TextEditingController(),
  );
  final TextEditingController _commentsController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
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

  Future<void> _exportExcel() async {
    final now = DateTime.now();
    final formattedDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';

    final preguntas = <String, dynamic>{
      '¿Hay solo material de un único FC en la entrada de la zona de Grading?':
          _respuestas[0],
      '¿El material de la buffer area está correctamente identificado?':
          _respuestas[1],
      '¿En la zona de Sorting están todas las cubetas identificadas?':
          _respuestas[2],
      'DSN 1ra unidad PRIME': _textControllers[0].text.trim(),
      '¿Grading correcto 1ra PRIME?': _respuestas[3],
      'DSN 2da unidad PRIME': _textControllers[1].text.trim(),
      '¿Grading correcto 2da PRIME?': _respuestas[4],
      'DSN 1ra unidad WOOT': _textControllers[2].text.trim(),
      '¿Grading correcto 1ra WOOT?': _respuestas[5],
      'DSN 2da unidad WOOT': _textControllers[3].text.trim(),
      '¿Grading correcto 2da WOOT?': _respuestas[6],
      'DSN 1ra unidad VAS': _textControllers[4].text.trim(),
      '¿Grading correcto 1ra VAS?': _respuestas[7],
      'DSN 2da unidad VAS': _textControllers[5].text.trim(),
      '¿Grading correcto 2da VAS?': _respuestas[8],
      'DSN 1ra unidad DAMAGE': _textControllers[6].text.trim(),
      '¿Grading correcto 1ra DAMAGE?': _respuestas[9],
      '¿Se satura la zona de transferencia a OPS?': _respuestas[10],
      'Comentarios adicionales': _commentsController.text.trim(),
    };

    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    sheet.setColWidth(0, 40);
    sheet.setColWidth(1, 60);

    sheet.appendRow([
      'Quality Check - Unsellable Grading - $formattedDate',
      '',
    ]);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0),
    );
    sheet.appendRow(['Pregunta', 'Respuesta']);
    for (final entry in preguntas.entries) {
      final value = entry.value is bool
          ? (entry.value == true
                ? 'Sí'
                : entry.value == false
                ? 'No'
                : '')
          : entry.value.toString();
      sheet.appendRow([entry.key, value]);
    }

    final bytes = excel.encode()!;
    final filename = 'unsellable_grading_qc_$formattedDate.xlsx';
    final api = ApiService.instance;
    if (api != null) {
      final result = await api.client.postMultipart(
        '/amz/qc-report',
        fields: {'formType': 'unsellable_grading', 'timestamp': formattedDate},
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
        final msg = result.body ?? result.error ?? 'HTTP ${result.statusCode}';
        globalScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error al subir el QC: $msg')),
        );
      }
    } else {
      final uri = Uri.parse('$baseUrl/amz/qc-report');
      final request = http.MultipartRequest('POST', uri)
        ..fields['formType'] = 'unsellable_grading'
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
            content: Text('Error al subir el QC: HTTP ${response.statusCode}'),
          ),
        );
      }
    }
    _resetForm();
    _scrollToTop();
  }

  void _resetForm() {
    FocusScope.of(context).unfocus();
    setState(() {
      for (var i = 0; i < _respuestas.length; i++) {
        _respuestas[i] = null;
      }
      for (final c in _textControllers) {
        c.clear();
      }
      _commentsController.clear();
    });
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _edgeOverlay?.remove();
    for (final c in _textControllers) {
      c.dispose();
    }
    _commentsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'QC - Unsellable Grading',
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
                          'Zone Status',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildRadio(
                          0,
                          '1. ¿Hay solo material de un único FC en la entrada de la zona de Grading?',
                        ),
                        _buildRadio(
                          1,
                          '2. ¿El material de la buffer area está correctamente identificado?',
                        ),
                        _buildRadio(
                          2,
                          '3. ¿En la zona de Sorting están todas las cubetas identificadas?',
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
                          'Prime Unit Analysis',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildText(
                          '4. DSN de la 1ra unidad PRIME',
                          _textControllers[0],
                        ),
                        _buildRadio(3, '5. ¿Grading correcto 1ra PRIME?'),
                        const Divider(height: 32),
                        _buildText(
                          '6. DSN de la 2da unidad PRIME',
                          _textControllers[1],
                        ),
                        _buildRadio(4, '7. ¿Grading correcto 2da PRIME?'),
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
                          'Woot Unit Analysis',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildText(
                          '8. DSN de la 1ra unidad WOOT',
                          _textControllers[2],
                        ),
                        _buildRadio(5, '9. ¿Grading correcto 1ra WOOT?'),
                        const Divider(height: 32),
                        _buildText(
                          '10. DSN de la 2da unidad WOOT',
                          _textControllers[3],
                        ),
                        _buildRadio(6, '11. ¿Grading correcto 2da WOOT?'),
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
                          'VAS & Damage Analysis',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildText(
                          '12. DSN de la 1ra unidad VAS',
                          _textControllers[4],
                        ),
                        _buildRadio(7, '13. ¿Grading correcto 1ra VAS?'),
                        const Divider(height: 32),
                        _buildText(
                          '14. DSN de la 2da unidad VAS',
                          _textControllers[5],
                        ),
                        _buildRadio(8, '15. ¿Grading correcto 2da VAS?'),
                        const Divider(height: 32),
                        _buildText(
                          '16. DSN de la 1ra unidad DAMAGE',
                          _textControllers[6],
                        ),
                        _buildRadio(9, '17. ¿Grading correcto 1ra DAMAGE?'),
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
                          'Operational Efficiency',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildRadio(
                          10,
                          '18. ¿Se satura la zona de transferencia de material a OPS?',
                        ),
                        _buildText(
                          '19. Comentarios adicionales',
                          _commentsController,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _SubmitButton(
                  onPressed: _exportExcel,
                  label: 'SUBMIT QC REPORT',
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRadio(int i, String pregunta) {
    final theme = Theme.of(context);
    final isSelected = _respuestas[i] != null;
    final isYes = _respuestas[i] == true;
    final isNo = _respuestas[i] == false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pregunta, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            children: [
              _ChoiceButton(
                label: 'SÍ',
                isSelected: isYes,
                color: Colors.green,
                onTap: () => setState(() => _respuestas[i] = true),
              ),
              const SizedBox(width: 12),
              _ChoiceButton(
                label: 'NO',
                isSelected: isNo,
                color: Colors.red,
                onTap: () => setState(() => _respuestas[i] = false),
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

  Widget _buildText(String label, TextEditingController controller) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextFormField(
            controller: controller,
            maxLines: label.contains('Comentarios') ? 4 : 2,
            decoration: InputDecoration(
              filled: true,
              fillColor: theme.colorScheme.surface.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              hintText: 'Enter details...',
              contentPadding: const EdgeInsets.all(20),
            ),
          ),
        ],
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

  const _SubmitButton({required this.onPressed, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withOpacity(0.8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Text(
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
