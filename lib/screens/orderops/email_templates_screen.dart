import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api_client.dart';
import '../../services/api_service.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';

const _kVariables = [
  ('order_nbr', 'Número de orden'),
  ('cust_name', 'Cliente'),
  ('family', 'Familia'),
  ('proyecto', 'Proyecto'),
  ('agent_name', 'Persona Asignada'),
  ('date_finished', 'Fecha de finalización'),
  ('completion_summary', 'Resumen de finalización'),
  ('idnbr', 'ID interno'),
];

class EmailTemplatesScreen extends StatefulWidget {
  const EmailTemplatesScreen({super.key});

  @override
  State<EmailTemplatesScreen> createState() => _EmailTemplatesScreenState();
}

class _EmailTemplatesScreenState extends State<EmailTemplatesScreen> {
  List<Map<String, dynamic>> _templates = [];
  bool _loading = true;
  String? _error;

  ApiClient get _client =>
      Provider.of<ApiService>(context, listen: false).client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _client.get('/orderops/email-templates');
      if (!res.ok) throw Exception(res.error ?? 'Error');
      setState(() {
        _templates = List<Map<String, dynamic>>.from(res.body as List);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _delete(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar plantilla'),
        content: const Text('¿Seguro que quieres eliminar esta plantilla?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _client.delete('/orderops/email-templates/$id');
    if (mounted) _load();
  }

  Future<void> _openEditor([Map<String, dynamic>? template]) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TemplateEditorDialog(template: template),
    );
    if (result == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF4F6F9);
    final cardBg = isDark ? const Color(0xFF1A2535) : Colors.white;
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF2C3E50);
    final textMuted =
        isDark ? const Color(0xFF8899AA) : const Color(0xFF7F8C8D);

    final routeName = ModalRoute.of(context)?.settings.name;
    final user = Provider.of<ApiService>(context, listen: false).currentUser;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 12),
                  child: Row(
                    children: [
                      Icon(Icons.email_rounded,
                          color: Colors.blue.shade400, size: 24),
                      const SizedBox(width: 10),
                      Text('Plantillas de Email',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: textPrimary)),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: () => _openEditor(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Nueva plantilla'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                    child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: TextStyle(color: Colors.red.shade400)))
                      : _templates.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.mail_outline_rounded,
                                              size: 56, color: textMuted),
                                          const SizedBox(height: 12),
                                          Text('No hay plantillas todavía',
                                              style: TextStyle(
                                                  color: textMuted,
                                                  fontSize: 16)),
                                          const SizedBox(height: 16),
                                          ElevatedButton(
                                            onPressed: () => _openEditor(),
                                            child: const Text(
                                                'Crear primera plantilla'),
                                          ),
                                        ],
                                      ),
                                    )
                      : ListView.separated(
                          itemCount: _templates.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final t = _templates[i];
                            final active = t['is_active'] as bool? ?? true;
                            final families =
                                (t['families'] as String? ?? '').trim();
                            return Container(
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: active
                                      ? Colors.blue.shade700
                                          .withValues(alpha: 0.3)
                                      : Colors.grey.withValues(alpha: 0.2),
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: active
                                      ? Colors.blue.shade700
                                          .withValues(alpha: 0.15)
                                      : Colors.grey.withValues(alpha: 0.15),
                                  child: Icon(Icons.email_rounded,
                                      color: active
                                          ? Colors.blue.shade400
                                          : textMuted,
                                      size: 20),
                                ),
                                title: Row(
                                  children: [
                                    Text(t['name'] as String? ?? '',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: textPrimary)),
                                    const SizedBox(width: 8),
                                    if (!active)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text('Inactiva',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: textMuted)),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(t['subject'] as String? ?? '',
                                        style: TextStyle(
                                            color: textMuted, fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Row(children: [
                                      Icon(Icons.category_outlined,
                                          size: 12, color: textMuted),
                                      const SizedBox(width: 4),
                                      Text(
                                          families.isEmpty
                                              ? 'Todas las familias'
                                              : families,
                                          style: TextStyle(
                                              fontSize: 11, color: textMuted)),
                                      const SizedBox(width: 16),
                                      Icon(Icons.send_rounded,
                                          size: 12, color: textMuted),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                            t['to_emails'] as String? ?? '',
                                            style: TextStyle(
                                                fontSize: 11, color: textMuted),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    ]),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 20),
                                      color: Colors.blue.shade400,
                                      tooltip: 'Editar',
                                      onPressed: () => _openEditor(t),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 20),
                                      color: Colors.red.shade400,
                                      tooltip: 'Eliminar',
                                      onPressed: () =>
                                          _delete(t['id'] as int),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  ),
                ),
              ],
            ),
          ),
          // Edge nav handle — same arrow as all other screens
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: EdgeNavHandle(
                  user: user,
                  width: 32,
                  currentRoute: routeName,
                  showIndicator: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Block model
// ---------------------------------------------------------------------------

enum _BlockType { heading, paragraph, divider }

class _Block {
  _BlockType type;
  TextEditingController ctrl;
  _Block(this.type, String text)
      : ctrl = TextEditingController(text: text);
  void dispose() => ctrl.dispose();
}

/// Converts a list of blocks into styled HTML for the email.
String _blocksToHtml(List<_Block> blocks) {
  final buf = StringBuffer();
  buf.write(
    '<div style="font-family:Arial,Helvetica,sans-serif;max-width:600px;'
    'margin:0 auto;color:#2C3E50;font-size:15px;line-height:1.6;">',
  );
  for (final b in blocks) {
    switch (b.type) {
      case _BlockType.heading:
        buf.write(
          '<h2 style="color:#1A252F;font-size:20px;margin:0 0 12px;">'
          '${b.ctrl.text}'
          '</h2>',
        );
      case _BlockType.paragraph:
        buf.write(
          '<p style="margin:0 0 12px;">'
          '${b.ctrl.text}'
          '</p>',
        );
      case _BlockType.divider:
        buf.write(
          '<hr style="border:none;border-top:1px solid #ddd;margin:16px 0;">',
        );
    }
  }
  buf.write('</div>');
  return buf.toString();
}

/// Parses saved HTML back into blocks so editing an existing template works.
List<_Block> _htmlToBlocks(String html) {
  if (html.trim().isEmpty) return [_Block(_BlockType.paragraph, '')];
  final blocks = <_Block>[];
  // heading
  final hRe = RegExp(r'<h2[^>]*>(.*?)</h2>', dotAll: true);
  // paragraph
  final pRe = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true);
  // divider
  final hrRe = RegExp(r'<hr[^>]*/?>');

  // Walk through html in order
  int pos = 0;
  final lower = html.toLowerCase();
  while (pos < html.length) {
    int hIdx = lower.indexOf('<h2', pos);
    int pIdx = lower.indexOf('<p', pos);
    int hrIdx = lower.indexOf('<hr', pos);

    // find nearest tag
    int nearest = -1;
    String tag = '';
    for (final entry in [('h2', hIdx), ('p', pIdx), ('hr', hrIdx)]) {
      final idx = entry.$2;
      if (idx >= pos && (nearest == -1 || idx < nearest)) {
        nearest = idx;
        tag = entry.$1;
      }
    }
    if (nearest == -1) break;

    if (tag == 'h2') {
      final m = hRe.firstMatch(html.substring(nearest));
      if (m != null) {
        blocks.add(_Block(_BlockType.heading, m.group(1) ?? ''));
        pos = nearest + m.end;
      } else {
        pos = nearest + 4;
      }
    } else if (tag == 'p') {
      final m = pRe.firstMatch(html.substring(nearest));
      if (m != null) {
        blocks.add(_Block(_BlockType.paragraph, m.group(1) ?? ''));
        pos = nearest + m.end;
      } else {
        pos = nearest + 3;
      }
    } else {
      final m = hrRe.firstMatch(html.substring(nearest));
      blocks.add(_Block(_BlockType.divider, ''));
      pos = nearest + (m?.end ?? 4);
    }
  }
  return blocks.isEmpty ? [_Block(_BlockType.paragraph, '')] : blocks;
}

// ---------------------------------------------------------------------------
// Template editor dialog
// ---------------------------------------------------------------------------

class _TemplateEditorDialog extends StatefulWidget {
  final Map<String, dynamic>? template;
  const _TemplateEditorDialog({this.template});

  @override
  State<_TemplateEditorDialog> createState() => _TemplateEditorDialogState();
}

class _TemplateEditorDialogState extends State<_TemplateEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _familiesCtrl;
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _toCtrl;
  late final TextEditingController _ccCtrl;
  late List<_Block> _blocks;
  bool _isActive = true;
  bool _saving = false;
  String? _error;

  // Which controller receives variable insertions
  TextEditingController? _focusedCtrl;

  ApiClient get _client =>
      Provider.of<ApiService>(context, listen: false).client;

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    _nameCtrl     = TextEditingController(text: t?['name'] as String? ?? '');
    _familiesCtrl = TextEditingController(text: t?['families'] as String? ?? '');
    _subjectCtrl  = TextEditingController(text: t?['subject'] as String? ?? '');
    _toCtrl       = TextEditingController(text: t?['to_emails'] as String? ?? '');
    _ccCtrl       = TextEditingController(text: t?['cc_emails'] as String? ?? '');
    _isActive     = t?['is_active'] as bool? ?? true;
    _blocks       = _htmlToBlocks(t?['body_html'] as String? ?? '');
    _focusedCtrl  = _subjectCtrl;
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _familiesCtrl, _subjectCtrl, _toCtrl, _ccCtrl]) {
      c.dispose();
    }
    for (final b in _blocks) { b.dispose(); }
    super.dispose();
  }

  void _insertVariable(String key) {
    final ctrl = _focusedCtrl;
    if (ctrl == null) return;
    final token = '{{$key}}';
    final sel = ctrl.selection;
    final text = ctrl.text;
    final start = sel.start < 0 ? text.length : sel.start;
    final end   = sel.end   < 0 ? text.length : sel.end;
    ctrl.value = TextEditingValue(
      text: text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
  }

  void _addBlock(_BlockType type) {
    setState(() => _blocks.add(_Block(type, '')));
  }

  void _removeBlock(int i) {
    if (_blocks.length <= 1) return;
    setState(() {
      _blocks[i].dispose();
      _blocks.removeAt(i);
    });
  }

  void _moveBlock(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _blocks.length) return;
    setState(() {
      final tmp = _blocks[i];
      _blocks[i] = _blocks[j];
      _blocks[j] = tmp;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_blocks.every((b) => b.type == _BlockType.divider || b.ctrl.text.trim().isEmpty)) {
      setState(() => _error = 'El cuerpo del email no puede estar vacío');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final body = {
        'name':      _nameCtrl.text.trim(),
        'families':  _familiesCtrl.text.trim(),
        'subject':   _subjectCtrl.text.trim(),
        'body_html': _blocksToHtml(_blocks),
        'to_emails': _toCtrl.text.trim(),
        'cc_emails': _ccCtrl.text.trim(),
        'is_active': _isActive,
      };
      final id = widget.template?['id'] as int?;
      final res = id != null
          ? await _client.put('/orderops/email-templates/$id', jsonBody: body)
          : await _client.post('/orderops/email-templates', jsonBody: body);
      if (!res.ok) throw Exception(res.error ?? 'Error al guardar');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.template != null;

    return Dialog(
      backgroundColor: const Color(0xFF1A2535),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 800),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title bar ──────────────────────────────────────────────
                Row(children: [
                  Icon(Icons.email_rounded, color: Colors.blue.shade400, size: 22),
                  const SizedBox(width: 10),
                  Text(isEdit ? 'Editar plantilla' : 'Nueva plantilla',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ]),
                const SizedBox(height: 16),

                // ── Variable chips ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade900.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade800.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Insertar variable en el campo seleccionado:',
                          style: TextStyle(color: Colors.white60, fontSize: 12)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _kVariables.map((v) => ActionChip(
                          label: Text(v.$2,
                              style: const TextStyle(fontSize: 11, color: Colors.white)),
                          tooltip: '{{${v.$1}}}',
                          backgroundColor: Colors.blue.shade700.withValues(alpha: 0.3),
                          side: BorderSide(color: Colors.blue.shade600.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          onPressed: () => _insertVariable(v.$1),
                        )).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Scrollable form ────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name + families
                        Row(children: [
                          Expanded(child: _field(_nameCtrl, 'Nombre de la plantilla', required: true)),
                          const SizedBox(width: 12),
                          Expanded(child: _field(_familiesCtrl, 'Familias',
                              hint: 'SMARTPHONES,TABLETS — vacío = todas')),
                        ]),
                        const SizedBox(height: 12),

                        // Subject
                        _field(_subjectCtrl, 'Asunto del email', required: true,
                            onFocus: () => setState(() => _focusedCtrl = _subjectCtrl)),
                        const SizedBox(height: 16),

                        // ── Body builder ──────────────────────────────────
                        const Text('Cuerpo del email',
                            style: TextStyle(color: Colors.white70, fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),

                        ..._blocks.asMap().entries.map((e) {
                          final i = e.key;
                          final b = e.value;
                          return _buildBlock(b, i);
                        }),

                        // Add block buttons
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, children: [
                          _addBtn(Icons.title, 'Título', () => _addBlock(_BlockType.heading)),
                          _addBtn(Icons.notes, 'Párrafo', () => _addBlock(_BlockType.paragraph)),
                          _addBtn(Icons.horizontal_rule, 'Separador', () => _addBlock(_BlockType.divider)),
                        ]),
                        const SizedBox(height: 16),

                        // TO / CC
                        Row(children: [
                          Expanded(child: _field(_toCtrl, 'Para (TO)',
                              required: true, hint: 'email1@empresa.com, email2@empresa.com')),
                          const SizedBox(width: 12),
                          Expanded(child: _field(_ccCtrl, 'CC', hint: 'cc@empresa.com')),
                        ]),
                        const SizedBox(height: 12),

                        // Active toggle
                        Row(children: [
                          Switch(
                            value: _isActive,
                            onChanged: (v) => setState(() => _isActive = v),
                            activeTrackColor: Colors.blue.shade400,
                          ),
                          const SizedBox(width: 8),
                          Text(_isActive ? 'Plantilla activa' : 'Plantilla inactiva',
                              style: const TextStyle(color: Colors.white70)),
                        ]),

                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(_error!, style: TextStyle(color: Colors.red.shade400, fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _saving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(isEdit ? 'Guardar cambios' : 'Crear plantilla'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlock(_Block b, int i) {
    final isDivider = b.type == _BlockType.divider;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Block type indicator
          Container(
            width: 4,
            height: isDivider ? 32 : null,
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: BoxDecoration(
              color: b.type == _BlockType.heading
                  ? Colors.blue.shade400
                  : b.type == _BlockType.paragraph
                      ? Colors.green.shade400
                      : Colors.grey.shade600,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: isDivider
                ? Container(
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.horizontal_rule, color: Colors.white30, size: 18),
                        SizedBox(width: 6),
                        Text('Separador', style: TextStyle(color: Colors.white30, fontSize: 12)),
                      ],
                    ),
                  )
                : Focus(
                    onFocusChange: (focused) {
                      if (focused) setState(() => _focusedCtrl = b.ctrl);
                    },
                    child: TextField(
                      controller: b.ctrl,
                      onTap: () => setState(() => _focusedCtrl = b.ctrl),
                      maxLines: b.type == _BlockType.heading ? 1 : null,
                      minLines: b.type == _BlockType.heading ? 1 : 2,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: b.type == _BlockType.heading ? 16 : 14,
                        fontWeight: b.type == _BlockType.heading
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      decoration: InputDecoration(
                        hintText: b.type == _BlockType.heading
                            ? 'Título...'
                            : 'Escribe el texto del párrafo aquí...',
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.blue.shade400),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
          ),
          // Block controls
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 16),
                color: Colors.white38,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Subir',
                onPressed: i > 0 ? () => _moveBlock(i, -1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 16),
                color: Colors.white38,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Bajar',
                onPressed: i < _blocks.length - 1 ? () => _moveBlock(i, 1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                color: Colors.red.shade300,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Eliminar bloque',
                onPressed: _blocks.length > 1 ? () => _removeBlock(i) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _addBtn(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool required = false,
    String? hint,
    VoidCallback? onFocus,
  }) {
    return Focus(
      onFocusChange: (focused) { if (focused && onFocus != null) onFocus(); },
      child: TextFormField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        onTap: onFocus,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.blue.shade400),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null
            : null,
      ),
    );
  }
}
