import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/serigrafia_service.dart';
import '../../widgets/main_sidebar.dart';
import '../../widgets/animated_background.dart';
import '../../themes/amazon_theme.dart';
import 'dart:ui';
import 'package:flutter/cupertino.dart';

class AmazonProyectosDashboard extends StatefulWidget {
  const AmazonProyectosDashboard({super.key});

  @override
  State<AmazonProyectosDashboard> createState() => _AmazonProyectosDashboardState();
}

class _AmazonProyectosDashboardState extends State<AmazonProyectosDashboard> {
  bool _loadingProjects = true;
  List<dynamic> _projects = [];
  dynamic _selectedProject;
  List<dynamic> _batches = [];
  bool _loadingBatches = false;
  List<SerigrafiaStandard> _standards = [];

  @override
  void initState() {
    super.initState();
    _fetchProjects();
    _fetchStandards();
  }

  Future<void> _fetchStandards() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final list = await SerigrafiaService(api.client).getStandards();
      if (mounted) setState(() => _standards = list);
    } catch (_) {}
  }

  Future<void> _fetchProjects() async {
    if (!mounted) return;
    setState(() => _loadingProjects = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.get('/amz/proyectos');
      if (res.ok && res.body is Map) {
        if (mounted) {
          setState(() {
            _projects = res.body['results'] ?? [];
            _loadingProjects = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingProjects = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loadingProjects = false);
    }
  }

  Future<void> _fetchBatches(dynamic project) async {
    if (!mounted) return;
    setState(() {
      _selectedProject = project;
      _loadingBatches = true;
      _batches = [];
    });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.get('/amz/proyectos/${project['id']}/batches');
      if (res.ok && res.body is Map) {
        if (mounted) {
          setState(() {
            _batches = res.body['results'] ?? [];
            _loadingBatches = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingBatches = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loadingBatches = false);
    }
  }

  void _showCreateProjectDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _CreateProjectDialog(onCreated: _fetchProjects),
    );
  }

  void _showCreateBatchDialog() {
    if (_selectedProject == null) return;
    showDialog(
      context: context,
      builder: (ctx) => _CreateBatchDialog(
        projectId: _selectedProject['id'],
        standards: _standards,
        onCreated: () => _fetchBatches(_selectedProject),
      ),
    );
  }

  void _showQCManagementDialog(dynamic project) {
    showDialog(
      context: context,
      builder: (ctx) => _QCManagementDialog(project: project),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    
    return AmazonTheme(
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: AnimatedBackgroundWidget(intensity: 0.4)),
            SafeArea(
              child: Row(
                children: [
                  const EdgeNavHandle(width: 32),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 24),
                          Expanded(
                            child: isMobile 
                              ? _buildMobileLayout() 
                              : _buildDesktopLayout(),
                          ),
                        ],
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
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.assignment_turned_in_rounded, size: 32, color: Colors.orange),
        const SizedBox(width: 12),
        const Text(
          'Amazon Proyectos',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _showCreateProjectDialog,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Proyecto'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 1, child: _buildProjectList()),
        const SizedBox(width: 24),
        Expanded(flex: 2, child: _buildBatchView()),
      ],
    );
  }

  Widget _buildMobileLayout() {
    if (_selectedProject != null) {
      return Column(
        children: [
          TextButton.icon(
            onPressed: () => setState(() => _selectedProject = null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Volver a proyectos'),
          ),
          Expanded(child: _buildBatchView()),
        ],
      );
    }
    return _buildProjectList();
  }

  Widget _buildProjectList() {
    if (_loadingProjects) return const Center(child: CircularProgressIndicator());
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Proyectos Activos (${_projects.length})', 
             style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: _projects.length,
            itemBuilder: (context, index) {
              final p = _projects[index];
              final isSelected = _selectedProject?['id'] == p['id'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: InkWell(
                  onTap: () => _fetchBatches(p),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected 
                        ? Colors.orange.withOpacity(0.15) 
                        : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? Colors.orange : Colors.white.withOpacity(0.1),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          p['project_type'] == 'ASIN FLIP' 
                            ? Icons.swap_horiz_rounded 
                            : Icons.inventory_2_rounded,
                          color: isSelected ? Colors.orange : Colors.white60,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p['name'] ?? 'Proyecto Sin Nombre',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isSelected ? Colors.orange : null,
                                ),
                              ),
                              Text(
                                p['program_name'] ?? 'General',
                                style: const TextStyle(fontSize: 12, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected) const Icon(Icons.chevron_right, color: Colors.orange),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBatchView() {
    if (_selectedProject == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.layers_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            const Text('Selecciona un proyecto para gestionar sus lotes', 
                       style: TextStyle(color: Colors.white38)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBatchHeader(),
        const SizedBox(height: 16),
        if (_loadingBatches) 
          const Center(child: CircularProgressIndicator())
        else if (_batches.isEmpty)
          const Expanded(
            child: Center(child: Text('Aún no hay lotes en este proyecto', style: TextStyle(color: Colors.white38))),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _batches.length,
              itemBuilder: (context, index) {
                final b = _batches[index];
                return _buildBatchCard(b);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildBatchHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'LOTES DE ${_selectedProject['name'].toString().toUpperCase()}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () => _showQCManagementDialog(_selectedProject),
            icon: const Icon(Icons.fact_check_rounded, color: Colors.blueAccent),
            tooltip: 'Gestionar Formulario QC',
          ),
          IconButton(
            onPressed: _showCreateBatchDialog,
            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.orange),
            tooltip: 'Crear Lote',
          ),
        ],
      ),
    );
  }

  Widget _buildBatchCard(dynamic batch) {
    final userRole = (ApiService.instance?.currentUser?.role ?? '').toLowerCase();
    final isElevated = !userRole.contains('operario') || userRole.contains('chief') || userRole.contains('admin');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Card(
        color: Colors.white.withOpacity(0.03),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          title: Text(batch['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.confirmation_number_outlined, size: 14, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text('Lote: ${batch['total_units']}', style: const TextStyle(color: Colors.white70)),
                    const SizedBox(width: 12),
                    const Icon(Icons.fact_check_outlined, size: 14, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text('QC: ${batch['qc_percentage']}%', style: const TextStyle(color: Colors.white70)),
                    const SizedBox(width: 12),
                    Icon(Icons.track_changes_rounded, size: 14, color: Colors.orange.withOpacity(0.5)),
                    const SizedBox(width: 4),
                    Text('Meta: ${batch['daily_production'] ?? 0}', style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                    if (batch['label_name'] != null) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.label_important_outline_rounded, size: 14, color: Colors.cyanAccent),
                      const SizedBox(width: 4),
                      Text('${batch['label_name']}', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isElevated)
                IconButton(
                  icon: const Icon(Icons.edit_note_rounded, color: Colors.blueAccent),
                  onPressed: () => _showEditBatchDialog(batch),
                  tooltip: 'Editar Lote',
                ),
              IconButton(
                icon: Icon(
                  Icons.arrow_circle_right_rounded, 
                  color: (batch['daily_production'] ?? 0) > 0 ? Colors.orange : Colors.grey.withOpacity(0.3), 
                  size: 32
                ),
                onPressed: () {
                  final daily = (batch['daily_production'] ?? 0);
                  if (daily > 0) {
                     Navigator.pushNamed(context, '/amazon/proyectos/batch/registration', arguments: batch);
                  } else {
                     if (isElevated) {
                        _showEditBatchDialog(batch);
                     } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Este lote aún no tiene meta diaria asignada. Contacte con un responsable.'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                     }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditBatchDialog(dynamic batch) async {
    final dailyCtrl = TextEditingController(text: batch['daily_production']?.toString() ?? '0');
    final totalUnitsCtrl = TextEditingController(text: batch['total_units']?.toString() ?? '0');
    final qcPctCtrl = TextEditingController(text: batch['qc_percentage']?.toString() ?? '10.0');
    SerigrafiaStandard? selectedStandard;
    if (batch['label_url'] != null) {
      try {
        selectedStandard = _standards.firstWhere((s) => s.url == batch['label_url']);
      } catch (_) {}
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        title: Text('Gestionar Lote: ${batch['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Establezca los parámetros para este lote.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: dailyCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Meta Diaria (Unidades)',
                prefixIcon: Icon(Icons.today, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: totalUnitsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Unidades Totales',
                prefixIcon: Icon(Icons.inventory_2, color: Colors.blue),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qcPctCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'QC Requerido (%)',
                prefixIcon: Icon(Icons.fact_check, color: Colors.green),
              ),
            ),
            const SizedBox(height: 16),
            if (_standards.isNotEmpty)
              DropdownButtonFormField<SerigrafiaStandard>(
                isExpanded: true,
                value: selectedStandard,
                decoration: const InputDecoration(
                  labelText: 'Etiqueta Bartender',
                  prefixIcon: Icon(Icons.label_outline_rounded, color: Colors.cyan),
                ),
                items: _standards.map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(s.name, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setDialogState(() => selectedStandard = v),
              )
            else
              const Text('No hay etiquetas en el repositorio', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () async {
              final daily = int.tryParse(dailyCtrl.text);
              final total = int.tryParse(totalUnitsCtrl.text);
              final qc = double.tryParse(qcPctCtrl.text);
              if (daily == null || total == null || qc == null) return;

              final api = Provider.of<ApiService>(context, listen: false);
              final res = await api.client.patch('/amz/batches/${batch['id']}', jsonBody: {
                'daily_production': daily,
                'total_units': total,
                'qc_percentage': qc,
                if (selectedStandard != null) 'label_url': selectedStandard!.url,
                if (selectedStandard != null) 'label_name': selectedStandard!.name,
              });
              if (res.ok) {
                Navigator.pop(ctx);
                _fetchBatches(_selectedProject);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.body['error'] ?? 'Error')));
              }
            },
            child: const Text('GUARDAR Y COMENZAR'),
          ),
        ],
      )),
    );
  }
}

class _CreateProjectDialog extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateProjectDialog({required this.onCreated});

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  String _type = 'GENERAL';
  final _nameCtrl = TextEditingController();
  final _progCtrl = TextEditingController();
  final _origAsinCtrl = TextEditingController();
  final _targAsinCtrl = TextEditingController();
  final _upcCtrl = TextEditingController();
  final _genAsinCtrl = TextEditingController();
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo Proyecto Amazon'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _type,
                items: const [
                  DropdownMenuItem(value: 'GENERAL', child: Text('GENERAL')),
                  DropdownMenuItem(value: 'ASIN FLIP', child: Text('ASIN FLIP')),
                ],
                onChanged: (v) => setState(() => _type = v!),
                decoration: const InputDecoration(labelText: 'Tipo de Proyecto'),
              ),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre del Proyecto'),
                validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _progCtrl,
                decoration: const InputDecoration(labelText: 'Nombre del Programa'),
              ),
              if (_type == 'ASIN FLIP') ...[
                TextFormField(controller: _origAsinCtrl, decoration: const InputDecoration(labelText: 'Original ASIN')),
                TextFormField(controller: _targAsinCtrl, decoration: const InputDecoration(labelText: 'Target ASIN')),
                TextFormField(controller: _upcCtrl, decoration: const InputDecoration(labelText: 'UPC')),
              ] else ...[
                TextFormField(controller: _genAsinCtrl, decoration: const InputDecoration(labelText: 'General ASIN')),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting ? const CupertinoActivityIndicator() : const Text('Crear'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post('/amz/proyectos', jsonBody: {
        'name': _nameCtrl.text,
        'project_type': _type,
        'program_name': _progCtrl.text,
        'original_asin': _origAsinCtrl.text,
        'target_asin': _targAsinCtrl.text,
        'upc': _upcCtrl.text,
        'general_asin': _genAsinCtrl.text,
      });
      if (res.ok) {
        widget.onCreated();
        Navigator.pop(context);
      }
    } finally {
      setState(() => _submitting = false);
    }
  }
}

class _CreateBatchDialog extends StatefulWidget {
  final int projectId;
  final List<SerigrafiaStandard> standards;
  final VoidCallback onCreated;
  const _CreateBatchDialog({required this.projectId, required this.standards, required this.onCreated});

  @override
  State<_CreateBatchDialog> createState() => _CreateBatchDialogState();
}

class _CreateBatchDialogState extends State<_CreateBatchDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _unitsCtrl = TextEditingController();
  final _dailyCtrl = TextEditingController();
  double _qcPct = 10.0;
  SerigrafiaStandard? _selectedStandard;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Crear Nuevo Lote'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre del Lote (Ej: Semana 12)'),
              validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null,
            ),
            TextFormField(
              controller: _unitsCtrl,
              decoration: const InputDecoration(labelText: 'Total Unidades'),
              keyboardType: TextInputType.number,
              validator: (v) => int.tryParse(v ?? '') == null ? 'Número inválido' : null,
            ),
            TextFormField(
              controller: _dailyCtrl,
              decoration: const InputDecoration(labelText: 'Objetivo Diario (Producción)'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n <= 0) return 'Debe ser mayor a 0';
                return null;
              },
            ),
            const SizedBox(height: 16),
            Text('Objetivo QC: ${_qcPct.toInt()}%'),
            Slider(
              value: _qcPct,
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (v) => setState(() => _qcPct = v),
            ),
            const SizedBox(height: 16),
            if (widget.standards.isNotEmpty)
              DropdownButtonFormField<SerigrafiaStandard>(
                isExpanded: true,
                value: _selectedStandard,
                decoration: const InputDecoration(
                  labelText: 'Etiqueta Bartender (Opcional)',
                  prefixIcon: Icon(Icons.label_outline_rounded, color: Colors.cyan),
                ),
                items: widget.standards.map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(s.name, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setState(() => _selectedStandard = v),
              )
            else
              const Text('No hay etiquetas en el repositorio', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting ? const CupertinoActivityIndicator() : const Text('Crear Lote'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post('/amz/proyectos/${widget.projectId}/batches', jsonBody: {
        'name': _nameCtrl.text,
        'total_units': int.parse(_unitsCtrl.text),
        'qc_percentage': _qcPct,
        'daily_production': int.parse(_dailyCtrl.text),
        if (_selectedStandard != null) 'label_url': _selectedStandard!.url,
        if (_selectedStandard != null) 'label_name': _selectedStandard!.name,
      });
      if (res.ok) {
        widget.onCreated();
        Navigator.pop(context);
      }
    } finally {
      setState(() => _submitting = false);
    }
  }
}

class _QCManagementDialog extends StatefulWidget {
  final dynamic project;
  const _QCManagementDialog({required this.project});

  @override
  State<_QCManagementDialog> createState() => _QCManagementDialogState();
}

class _QCManagementDialogState extends State<_QCManagementDialog> {
  List<dynamic> _templates = [];
  bool _loading = true;
  final _esCtrl = TextEditingController();
  final _enCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchTemplates();
  }

  Future<void> _fetchTemplates() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.get('/amz/proyectos/${widget.project['id']}/qc-templates');
      if (res.ok && mounted) {
        setState(() {
          _templates = res.body['results'] ?? [];
          _loading = false;
        });
      }
    } catch (_) {
       if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addQuestion() async {
    final es = _esCtrl.text.trim();
    final en = _enCtrl.text.trim();
    if (es.isEmpty || en.isEmpty) return;

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post('/amz/proyectos/${widget.project['id']}/qc-templates', jsonBody: {
        'question_text_es': es,
        'question_text_en': en,
      });
      if (res.ok) {
        _esCtrl.clear();
        _enCtrl.clear();
        _fetchTemplates();
      }
    } catch (_) {}
  }

  Future<void> _deleteQuestion(int id) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.delete('/amz/qc-templates/$id');
      if (res.ok) {
        _fetchTemplates();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Gestionar Formulario: ${widget.project['name']}'),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Preguntas de Control de Calidad', style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            if (_loading) 
              const Center(child: CupertinoActivityIndicator())
            else if (_templates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No hay preguntas. Agregue una abajo para habilitar el registro.', 
                      style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              )
            else
              SizedBox(
                height: 300,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _templates.length,
                  itemBuilder: (ctx, i) {
                    final t = _templates[i];
                    return ListTile(
                      title: Text(t['question_text_es'], style: const TextStyle(fontSize: 14)),
                      subtitle: Text(t['question_text_en'], style: const TextStyle(fontSize: 12, color: Colors.white38)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _deleteQuestion(t['id']),
                      ),
                    );
                  },
                ),
              ),
            const Divider(),
            const SizedBox(height: 8),
            const Text('AGREGAR PREGUNTA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
            TextField(
              controller: _esCtrl,
              decoration: const InputDecoration(labelText: 'Pregunta en Español', labelStyle: TextStyle(fontSize: 12)),
            ),
            TextField(
              controller: _enCtrl,
              decoration: const InputDecoration(labelText: 'English Question', labelStyle: TextStyle(fontSize: 12)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _addQuestion, 
              icon: const Icon(Icons.add), 
              label: const Text('Agregar al Formulario'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey.shade800),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
      ],
    );
  }
}
