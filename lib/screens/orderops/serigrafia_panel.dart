import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' as excel_pkg;
import '../../api_client.dart';
import '../../models/agent_models.dart';
import '../../services/api_service.dart';
import '../../services/serigrafia_service.dart';
import '../../services/orderops_service.dart';
import './serigrafia_repository_screen.dart';

class SerigrafiaPanel extends StatefulWidget {
  final AgentOrder order;
  final OrderOpsDetail? detail;
  final OrderOpsService? service;

  const SerigrafiaPanel({
    super.key,
    required this.order,
    this.detail,
    this.service,
  });

  @override
  State<SerigrafiaPanel> createState() => _SerigrafiaPanelState();
}

class _SerigrafiaPanelState extends State<SerigrafiaPanel> {
  int _currentStep = 1;
  late SerigrafiaService _serigrafiaService;
  
  // Phase 1: Standard
  List<SerigrafiaStandard> _standards = [];
  SerigrafiaStandard? _selectedStandard;
  
  // Phase 2: Excel
  AgentOrderPhoto? _selectedAttachment;
  excel_pkg.Excel? _excel;
  List<String> _excelHeaders = [];
  bool _loadingExcel = false;
  
  // Phase 3: Mapping
  Map<String, String> _variableToColumnMapping = {};
  
  // Phase 4: Execution
  int _currentRowIndex = 1; // 1-indexed, starts after header
  bool _printing = false;
  
  // CI Inventory
  bool _requiresCI = false;
  String? _currentCiCode;
  bool _fetchingCI = false;
  
  // Registry Picking mode (if variable 'CI' exists)
  bool _isUsingExistingRegistry = false;

  @override
  void initState() {
    super.initState();
    final client = ApiService.instance?.client;
    if (client != null) {
      _serigrafiaService = SerigrafiaService(client);
      _loadStandards();
    }
  }

  Future<void> _loadStandards() async {
    final list = await _serigrafiaService.getStandards();
    if (mounted) {
       setState(() {
          _standards = list;
       });
    }
  }

  Future<void> _loadExcel(AgentOrderPhoto photo) async {
    setState(() {
      _loadingExcel = true;
      _excel = null;
      _excelHeaders = [];
    });
    
    try {
      // Normalize path for web/api (replace backslashes from Windows paths)
      final normalizedPath = photo.filePath.replaceAll('\\', '/');
      final doc = await _serigrafiaService.downloadAndParseExcel(normalizedPath);
      
      if (doc != null && mounted) {
        setState(() {
          _excel = doc;
          final sheet = doc.tables.values.first;
          if (sheet.maxRows > 0) {
            _excelHeaders = sheet.rows.first.map((c) => c?.value?.toString() ?? '').toList();
          } else {
             _excelHeaders = [];
          }
          _selectedAttachment = photo;
          _currentStep = 3;
          _currentCiCode = null;
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo procesar el archivo Excel. Verifica que el archivo no esté dañado binariamente.'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al descargar el archivo: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _loadingExcel = false);
  }

  List<String> get _allVariables {
    final vars = _selectedStandard?.variables ?? [];
    final upper = vars.map((v) => v.toUpperCase()).toSet();
    final hasCiLike = upper.contains('CI') || upper.contains('CI_CODE');

    // If CI flow is enabled, only append CI_CODE when no CI-like variable exists.
    if (_requiresCI && !hasCiLike) {
      return [...vars, 'CI_CODE'];
    }
    return vars;
  }

  Future<void> _fetchNextCI() async {
    setState(() => _fetchingCI = true);
    try {
      final code = await _serigrafiaService.getNextInventoryCode();
      if (mounted) {
        setState(() {
          _currentCiCode = code;
          // If we have a mapping for CI_CODE, update the Excel cell immediately
          final colName = _variableToColumnMapping['CI_CODE'];
          final colIdx = _excelHeaders.indexOf(colName ?? '');
          if (colIdx != -1 && _currentCiCode != null) {
             _excel!.tables.values.first.updateCell(
               excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: _currentRowIndex),
               _currentCiCode!,
             );
          }
        });
      }
    } catch (_) {}
    setState(() => _fetchingCI = false);
  }

  void _startExecution() {
    if (_excel == null || _selectedStandard == null) return;
    
    // Validate mapping
    for (final v in _allVariables) {
      if (!_variableToColumnMapping.containsKey(v)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falta mapear la variable $v')),
        );
        return;
      }
    }
    
    setState(() => _currentStep = 4);
    _syncExcelWithDatabase();
  }

  Future<void> _syncExcelWithDatabase() async {
    if (_excel == null) return;
    
    // Show a loading indicator if needed, but since we are at Step 4, 
    // we can just run it once at the start.
    final registries = await _serigrafiaService.getRegistries(widget.order.idnbr);
    if (registries.isEmpty) {
      _advanceToNextEmptyRow();
      return;
    }
    
    setState(() {
      final sheet = _excel!.tables.values.first;
      
      // Iterate through each row in the Excel (skip header)
      for (int i = 1; i < sheet.maxRows; i++) {
        final row = sheet.rows[i];
        
        // Find a matching registry record for this row
        Map<String, dynamic>? match;
        
        // Strategy: Key matching. Try to find any variable that exists in the Excel row
        // and matches a registry record.
        for (final v in _allVariables) {
          final colIdx = _excelHeaders.indexOf(_variableToColumnMapping[v] ?? '');
          if (colIdx != -1) {
            final excelVal = row.length > colIdx ? row[colIdx]?.value?.toString()?.trim() ?? '' : '';
            if (excelVal.isNotEmpty) {
              // Try to find a registry that has this value for the same variable
              match = registries.where((r) {
                final data = r['data'] as Map;
                // Case-insensitive variable lookup
                dynamic regVal;
                data.forEach((rk, rv) {
                  if (rk.toString().toUpperCase() == v.toUpperCase()) regVal = rv;
                });
                return regVal?.toString()?.trim() == excelVal;
              }).firstOrNull;
              
              if (match != null) break;
            }
          }
        }
        
        // If we found a match, fill in the missing fields in Excel from the Registry
        if (match != null) {
          final data = match['data'] as Map;
          for (final v in _allVariables) {
            final colIdx = _excelHeaders.indexOf(_variableToColumnMapping[v] ?? '');
            if (colIdx != -1) {
              final excelVal = row.length > colIdx ? row[colIdx]?.value?.toString()?.trim() ?? '' : '';
              if (excelVal.isEmpty) {
                // Populate from registry
                dynamic regVal;
                data.forEach((rk, rv) {
                  if (rk.toString().toUpperCase() == v.toUpperCase()) regVal = rv;
                });
                if (regVal != null) {
                  sheet.updateCell(
                    excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: i),
                    regVal.toString(),
                  );
                }
              }
            }
          }
        }
      }
    });

    _advanceToNextEmptyRow();
  }

  void _advanceToNextEmptyRow() {
    if (_excel == null || _selectedStandard == null) return;
    final sheet = _excel!.tables.values.first;
    
    for (int i = 1; i < sheet.maxRows; i++) {
      final row = sheet.rows[i];
      bool allFilled = true;
      for (final variableName in _allVariables) {
        final colHeader = _variableToColumnMapping[variableName];
        final colIndex = _excelHeaders.indexOf(colHeader ?? '');
        if (colIndex != -1) {
          final cellValue = row.length > colIndex ? row[colIndex]?.value?.toString() ?? '' : '';
          if (cellValue.trim().isEmpty) {
            allFilled = false;
            break;
          }
        }
      }
      if (!allFilled) {
        setState(() {
          _currentRowIndex = i;
          _currentCiCode = null;
        });
        
        if (_requiresCI) {
           _fetchNextCI();
        }
        return;
      }
    }
    // If we get here, all rows are filled
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Todas las filas están completas')),
    );
  }

  Widget _buildScanField(String field) {
    final ctrl = TextEditingController();
    return SizedBox(
      width: 300,
      child: TextField(
        controller: ctrl,
        autofocus: true,
        textAlign: TextAlign.center,
        decoration: InputDecoration(labelText: 'ESCANEAR $field', border: const OutlineInputBorder()),
        onSubmitted: (val) {
          if (val.trim().isNotEmpty) {
            _updateCell(field, val.trim());
          }
        },
      ),
    );
  }

  Widget _buildBrowseRegistryButton() {
    return ElevatedButton.icon(
      onPressed: _showRegistryPicker,
      icon: const Icon(Icons.search_rounded),
      label: const Text('BUSCAR REGISTRO'),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.white12, foregroundColor: Colors.cyan, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
    );
  }

  void _updateCell(String variable, String value) {
    setState(() {
      final sheet = _excel!.tables.values.first;
      final colIdx = _excelHeaders.indexOf(_variableToColumnMapping[variable]!);
      sheet.updateCell(
        excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: _currentRowIndex),
        value,
      );
    });
    
    // Auto-submit if complete
    _checkCompletionAndSubmit();
  }

  void _checkCompletionAndSubmit() {
    if (_excel == null) return;
    final sheet = _excel!.tables.values.first;
    final row = sheet.rows[_currentRowIndex];
    
    final values = <String, String>{};
    bool isComplete = true;
    
    for (final v in _allVariables) {
      final colIdx = _excelHeaders.indexOf(_variableToColumnMapping[v] ?? '');
      if (colIdx != -1) {
        final val = row.length > colIdx ? row[colIdx]?.value?.toString() ?? '' : '';
        if (val.trim().isEmpty) {
          isComplete = false;
          break;
        }
        values[v] = val.trim();
      } else {
        isComplete = false;
        break;
      }
    }
    
    if (isComplete && !_printing) {
      _printAndSubmit(values);
    }
  }

  Future<void> _showRegistryPicker() async {
    final registries = await _serigrafiaService.getRegistries(widget.order.idnbr);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Registros del Proyecto', style: TextStyle(color: Colors.cyan)),
        content: SizedBox(
          width: 500,
          height: 400,
          child: registries.isEmpty 
            ? const Center(child: Text('No hay registros previos', style: TextStyle(color: Colors.white24)))
            : ListView.builder(
                itemCount: registries.length,
                itemBuilder: (context, index) {
                  final r = registries[index];
                  final data = r['data'] as Map;
                  final time = r['created_at'].toString().split('T').first;
                  return ListTile(
                    title: Text(data['CI'] ?? data['CI_CODE'] ?? 'Sin CI', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    subtitle: Text('${data['MAC'] ?? ''} | ${data['DSN'] ?? ''}\n$time - ${r['operator']}', style: const TextStyle(fontSize: 11, color: Colors.white38)),
                    isThreeLine: true,
                    onTap: () {
                      _applyRegistryToExcel(r);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
        ),
      ),
    );
  }

  void _applyRegistryToExcel(Map<String, dynamic> registry) {
    setState(() {
      final data = registry['data'] as Map;
      final sheet = _excel!.tables.values.first;
      _isUsingExistingRegistry = true; // Mark to skip DB save on print

      for (final variable in _allVariables) {
        // Try to find the value in the registry data
        // Check case-insensitive mapping
        String? value;
        data.forEach((k, v) {
          if (k.toString().toUpperCase() == variable.toUpperCase()) {
            value = v.toString();
          }
        });

        if (value != null) {
          final colIdx = _excelHeaders.indexOf(_variableToColumnMapping[variable] ?? '');
          if (colIdx != -1) {
            sheet.updateCell(
              excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: _currentRowIndex),
              value!,
            );
          }
        }
      }
    });

    // Auto-submit if picking from registry fills the row
    _checkCompletionAndSubmit();
  }

  Future<void> _printAndSubmit(Map<String, String> values) async {
    if (_selectedStandard == null || _printing) return;
    
    setState(() => _printing = true);
    try {
      final res = await _serigrafiaService
          .printLabel(_selectedStandard!, values)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => ApiResult(
              false,
              0,
              error: 'Timeout esperando respuesta de impresión (20s)',
            ),
          );
      if (res.ok && mounted) {
          // Update Local Excel (ensure everything is synced)
          final sheet = _excel!.tables.values.first;
          values.forEach((varName, value) {
             final colIdx = _excelHeaders.indexOf(_variableToColumnMapping[varName] ?? '');
             if (colIdx != -1) {
                sheet.updateCell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: _currentRowIndex), value);
             }
          });
          
          final wasUsingRegistry = _isUsingExistingRegistry;
          _isUsingExistingRegistry = false; // Reset for next unit
          _advanceToNextEmptyRow();
           
          // Persistence: Skip if we just reused an existing registry
          if (!wasUsingRegistry) {
            final currentUser = ApiService.instance?.currentUser?.username ?? 'unknown';
            final saveRes = await _serigrafiaService.saveRegistry(
              widget.order.idnbr,
              _selectedStandard!.name,
              values,
              operator: currentUser,
            );
            if (!saveRes.ok) {
               if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(content: Text('Error guardando en historial: ${saveRes.error}'), backgroundColor: Colors.orange),
                 );
               }
            }
          } else {
             print('Skipping registry save as unit was pulled from existing registry');
          }

          // Auto-save Excel status to server
          _saveAndUpload(silent: true);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Etiqueta enviada a impresión exitosamente'), backgroundColor: Colors.green),
            );
          }
      } else {
        if (mounted) {
          String detail = res.error ?? 'Respuesta inválida del servidor';
          final body = res.body;
          if (body is Map) {
            final backendError =
                body['error'] ?? body['details'] ?? body['response'] ?? body['message'];
            if (backendError != null && backendError.toString().trim().isNotEmpty) {
              detail = backendError.toString();
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error de impresión: $detail'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    } catch (e, st) {
      print('Exception in _printAndSubmit: $e');
      print('Stacktrace: $st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error inesperado: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _printing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Colors.white10),
          Padding(
            padding: const EdgeInsets.all(24),
            child: _buildStepContent(),
          ),
          if (_currentStep > 1) _buildFooterActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          const Icon(Icons.print_outlined, color: Colors.cyan, size: 24),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FLUJO DE SERIGRAFIADO', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              Text('Automatización Excel-Print-Scan', style: TextStyle(fontSize: 10, color: Colors.white38)),
            ],
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _showReprintDialog,
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('REIMPRIMIR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: TextButton.styleFrom(foregroundColor: Colors.cyan, padding: const EdgeInsets.symmetric(horizontal: 16)),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.cyan, size: 22),
            tooltip: 'Gestionar Repositorio',
            onPressed: () => Navigator.pushNamed(context, '/serials/repository').then((_) => _loadStandards()),
          ),
          const SizedBox(width: 8),
          _buildStepDots(),
        ],
      ),
    );
  }

  Widget _buildStepDots() {
    return Row(
      children: List.generate(4, (index) {
        final stepNum = index + 1;
        final isActive = stepNum == _currentStep;
        final isDone = stepNum < _currentStep;
        return Container(
          width: 24,
          height: 4,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: isActive ? Colors.cyan : (isDone ? Colors.cyan.withOpacity(0.5) : Colors.white10),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 1: return _buildPhase1();
      case 2: return _buildPhase2();
      case 3: return _buildPhase3();
      case 4: return _buildPhase4();
      default: return const SizedBox();
    }
  }

  Widget _buildPhase1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.cyan.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.cyan.withOpacity(0.2))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CONFIGURACIÓN DEL FLUJO', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.cyan, fontSize: 10, letterSpacing: 1)),
              SwitchListTile(
                title: const Text('¿Requiere etiqueta de inventariado CI?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: const Text('Genera y vincula automáticamente códigos de inventario de la base de datos', style: TextStyle(fontSize: 11, color: Colors.white38)),
                value: _requiresCI,
                activeColor: Colors.cyan,
                onChanged: (val) => setState(() => _requiresCI = val),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('SELECCIONA EL ESTÁNDAR DE ETIQUETA', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey, fontSize: 10, letterSpacing: 1)),
        const SizedBox(height: 12),
        ..._standards.map((s) => _buildStandardTile(s)),
        const SizedBox(height: 12),
        _buildManualStandardTile(),
      ],
    );
  }

  Widget _buildManualStandardTile() {
    return InkWell(
      onTap: _showManualStandardDialog,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.add_link_rounded, color: Colors.grey),
            SizedBox(width: 16),
            Expanded(child: Text('Configurar Estándar Manual', style: TextStyle(color: Colors.grey))),
            Icon(Icons.edit_note_rounded, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  void _showManualStandardDialog() {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final varCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurar Etiqueta Manual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre (ej: Xiaomi High)')),
            TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'URL de Impresión')),
            TextField(controller: varCtrl, decoration: const InputDecoration(labelText: 'Variables (separadas por coma, ej: DSN,MAC)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && urlCtrl.text.isNotEmpty) {
                 final s = SerigrafiaStandard(
                   name: nameCtrl.text,
                   url: urlCtrl.text,
                   variables: varCtrl.text.split(',').map((e) => e.trim().toUpperCase()).where((e) => e.isNotEmpty).toList(),
                 );
                 setState(() {
                   _selectedStandard = s;
                   _currentStep = 2;
                 });
                 Navigator.pop(ctx);
              }
            },
            child: const Text('ACEPTAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildStandardTile(SerigrafiaStandard s) {
    final isSelected = _selectedStandard == s;
    return InkWell(
      onTap: () => setState(() {
        _selectedStandard = s;
        _currentStep = 2;
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyan.withOpacity(0.1) : Colors.white.withOpacity(0.05),
          border: Border.all(color: isSelected ? Colors.cyan : Colors.white.withOpacity(0.1)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.label_important_outline_rounded, color: Colors.cyan),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${s.variables.join(', ')}', style: const TextStyle(fontSize: 12, color: Colors.cyan)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _buildPhase2() {
    final photos = widget.detail?.photos ?? [];
    final excels = photos.where((p) => p.fileName.toLowerCase().endsWith('.xlsx') || p.fileName.toLowerCase().endsWith('.xls'));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PASO 2: SELECCIONA EL EXCEL DE ARCHIVOS', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 16),
        if (_loadingExcel) const Center(child: CircularProgressIndicator()),
        if (!_loadingExcel && excels.isEmpty) 
          const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No hay archivos Excel adjuntos en esta orden', textAlign: TextAlign.center, style: TextStyle(color: Colors.white24)))),
        if (!_loadingExcel)
          ...excels.map((p) => _buildExcelTile(p)),
      ],
    );
  }

  Widget _buildExcelTile(AgentOrderPhoto p) {
    // If idnbr is different or null, it's likely a project file
    final isProjectFile = p.idnbr != widget.order.idnbr;

    return ListTile(
      onTap: () => _loadExcel(p),
      leading: Stack(
        alignment: Alignment.bottomRight,
        children: [
          const Icon(Icons.table_view_rounded, color: Colors.green, size: 32),
          if (isProjectFile)
            Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
              child: const Icon(Icons.folder_shared_rounded, size: 10, color: Colors.white),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(child: Text(p.fileName, overflow: TextOverflow.ellipsis)),
          if (isProjectFile)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.blue.withOpacity(0.3))),
              child: const Text('PROYECTO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue)),
            ),
        ],
      ),
      subtitle: Text('Subido el ${p.uploadedAt ?? 'Unknown'}'),
      trailing: const Icon(Icons.download_rounded, size: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildPhase3() {
    if (_selectedStandard == null) return const SizedBox();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PASO 3: MAPEO DE VARIABLES A COLUMNAS', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 16),
        ..._allVariables.map((v) => _buildMappingRow(v)),
        const SizedBox(height: 32),
        Center(
          child: FilledButton.icon(
            onPressed: _startExecution,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Comenzar Procesamiento'),
            style: FilledButton.styleFrom(backgroundColor: Colors.cyan, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
          ),
        ),
      ],
    );
  }

  Widget _buildMappingRow(String variableName) {
    final currentMapping = _variableToColumnMapping[variableName];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 120,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.cyan.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(variableName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.cyan)),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white24),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _excelHeaders.contains(currentMapping) ? currentMapping : null,
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder()),
              hint: const Text('Seleccionar Columna', style: TextStyle(fontSize: 12)),
              items: _excelHeaders.map((h) => DropdownMenuItem(value: h, child: Text(h, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (val) => setState(() => _variableToColumnMapping[variableName] = val!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhase4() {
    if (_excel == null) return const SizedBox();
    final sheet = _excel!.tables.values.first;
    final rowData = sheet.rows[_currentRowIndex];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('PASO 4: ESCANEO Y REGISTRO', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey, fontSize: 11)),
            Text('Fila ${_currentRowIndex + 1} de ${sheet.maxRows}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.cyan)),
          ],
        ),
        const SizedBox(height: 16),
        _buildCurrentRowPreview(rowData),
        const SizedBox(height: 32),
        _buildScanningUI(),
      ],
    );
  }

  Widget _buildCurrentRowPreview(List<excel_pkg.Data?> row) {
    // Extract mapped variables only
    final mappedValues = <String, String>{};
    String? ciValue;

    for (final v in _allVariables) {
      final colName = _variableToColumnMapping[v];
      final colIdx = _excelHeaders.indexOf(colName ?? '');
      if (colIdx != -1) {
        final val = row.length > colIdx ? row[colIdx]?.value?.toString() ?? '' : '';
        mappedValues[v] = val;
        // Check if this variable is CI or CI_CODE for a prominent display
        if (v.toUpperCase() == 'CI' || v.toUpperCase() == 'CI_CODE') {
          if (val.isNotEmpty) ciValue = val;
        }
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (ciValue != null) ...[
            const Text('CÓDIGO DE INVENTARIO (CI)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.cyan, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text(
              ciValue!,
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
            ),
            const SizedBox(height: 24),
            Divider(color: Colors.white.withOpacity(0.05), indent: 40, endIndent: 40),
            const SizedBox(height: 24),
          ],
          const Text('DATOS DE LA ETIQUETA', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 1.5)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: mappedValues.entries.where((e) => e.key.toUpperCase() != 'CI' && e.key.toUpperCase() != 'CI_CODE').map((e) {
              final isMissing = e.value.isEmpty;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isMissing ? Colors.orange.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isMissing ? Colors.orange.withOpacity(0.3) : Colors.white.withOpacity(0.1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${e.key}: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isMissing ? Colors.orange : Colors.white38)),
                    Text(
                      isMissing ? 'ESPERANDO...' : e.value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: isMissing ? Colors.orange : Colors.cyan,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          if (mappedValues.entries.length <= 1 && ciValue != null) 
            const Text('Listo para imprimir', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildScanningUI() {
    // Determine which field is currently being scanned
    String? fieldToScan;
    for (final v in _allVariables) {
      final colName = _variableToColumnMapping[v];
      final colIdx = _excelHeaders.indexOf(colName ?? '');
      final sheet = _excel!.tables.values.first;
      final val = sheet.rows[_currentRowIndex][colIdx]?.value?.toString() ?? '';
      if (val.trim().isEmpty) {
        fieldToScan = v;
        break;
      }
    }

    // Special case for "CI" variable: Show registry picker
    if (fieldToScan == 'CI') {
       return Center(
         child: Column(
           children: [
             const Icon(Icons.inventory_rounded, size: 48, color: Colors.cyan),
             const SizedBox(height: 16),
             const Text('Variable CI Detectada', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.cyan)),
             const Text('Puedes escanear el CI o seleccionarlo de un registro previo', style: TextStyle(fontSize: 12, color: Colors.white38)),
             const SizedBox(height: 32),
             Row(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 _buildScanField(fieldToScan!),
                 const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('O', style: TextStyle(color: Colors.white24))),
                 _buildBrowseRegistryButton(),
               ],
             ),
           ],
         ),
       );
    }
    
    // special case for CI_CODE: if it's the current field and we haven't fetched it yet
    if (fieldToScan == 'CI_CODE' && _currentCiCode == null && !_fetchingCI) {
       return Center(
         child: Column(
           children: [
             const Icon(Icons.auto_fix_high_rounded, size: 48, color: Colors.cyan),
             const SizedBox(height: 16),
             const Text('Generando Código de Inventario...', style: TextStyle(color: Colors.cyan)),
             const SizedBox(height: 24),
             _fetchingCI ? const CircularProgressIndicator() : ElevatedButton(onPressed: _fetchNextCI, child: const Text('Generar Manualmente')),
           ],
         ),
       );
    }
    
    if (fieldToScan == null) {
      return const Center(
        child: Column(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 64),
            SizedBox(height: 16),
            Text('Procesando...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            SizedBox(height: 8),
            CircularProgressIndicator(),
          ],
        ),
      );
    }
    
    final ctrl = TextEditingController();
    return Column(
      children: [
        const Icon(Icons.qr_code_scanner_rounded, size: 48, color: Colors.cyan),
        const SizedBox(height: 16),
        Text('ESCANEANDO: $fieldToScan', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.cyan)),
        const SizedBox(height: 24),
        TextField(
          controller: ctrl,
          autofocus: true,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(labelText: 'EN ESPERA DE ESCANEO...', border: OutlineInputBorder()),
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) {
               setState(() {
                  final sheet = _excel!.tables.values.first;
                  final colIdx = _excelHeaders.indexOf(_variableToColumnMapping[fieldToScan!]!);
                  sheet.updateCell(
                    excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: _currentRowIndex),
                    val.trim(),
                  );
               });
               _checkCompletionAndSubmit();
            }
          },
        ),
      ],
    );
  }

  Widget _buildFooterActions() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black26,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: () => setState(() {
              if (_currentStep == 4) _currentStep = 3;
              else if (_currentStep > 1) _currentStep--;
            }),
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('VOLVER'),
          ),
          if (_currentStep == 4)
            TextButton.icon(
              onPressed: _saveAndUpload,
              icon: const Icon(Icons.cloud_upload_outlined, size: 16),
              label: const Text('GUARDAR EXCEL'),
            ),
        ],
      ),
    );
  }

  Future<void> _saveAndUpload({bool silent = false}) async {
     if (_excel == null || _selectedAttachment == null) return;
     
     if (!silent) setState(() => _printing = true);
     try {
        final bytes = _excel!.encode();
        if (bytes != null) {
           final api = ApiService.instance;
           if (api != null) {
              final res = await api.client.postMultipart(
                '/orderops/agent-orders/${widget.order.idnbr}/photos',
                files: [
                  MultipartAttachment(
                    fieldName: 'file',
                    fileName: 'SERIGRAFIA_ACTUALIZADA_${_selectedAttachment!.fileName}',
                    bytes: bytes,
                  )
                ],
              );
              if (res.ok && !silent) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excel actualizado y subido exitosamente'), backgroundColor: Colors.green));
              }
           }
        }
     } catch (_) {}
     if (!silent) setState(() => _printing = false);
  }

  Future<void> _showReprintDialog() async {
    if (_selectedStandard == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona primero un estándar de etiqueta')));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        String searchQuery = '';
        List<Map<String, dynamic>>? registries;
        bool loading = true;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (loading && registries == null && errorMessage == null) {
              _serigrafiaService.getRegistries(widget.order.idnbr).then((results) {
                setDialogState(() {
                  registries = results;
                  loading = false;
                });
              }).catchError((err) {
                setDialogState(() {
                  errorMessage = err.toString();
                  loading = false;
                });
              });
            }

            final filtered = registries?.where((r) {
               final dataStr = jsonEncode(r['data']).toLowerCase();
               return dataStr.contains(searchQuery.toLowerCase());
            }).toList() ?? [];

            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: Row(
                children: [
                   const Text('Reimpresión de Etiquetas', style: TextStyle(color: Colors.cyan)),
                   const Spacer(),
                   if (registries != null) 
                     Text('${registries!.length} registros', style: const TextStyle(fontSize: 10, color: Colors.white24)),
                ],
              ),
              content: SizedBox(
                width: 600,
                height: 500,
                child: Column(
                  children: [
                    Text('Buscando en Orden ID: ${widget.order.idnbr}', style: const TextStyle(fontSize: 9, color: Colors.white24)),
                    const SizedBox(height: 8),
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Buscar por CI, Serial o MAC...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => setDialogState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: loading 
                        ? const Center(child: CircularProgressIndicator())
                        : errorMessage != null
                          ? Center(child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                                const SizedBox(height: 16),
                                Text('Error: $errorMessage', textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                              ],
                            ))
                          : filtered.isEmpty 
                            ? const Center(child: Text('No se encontraron registros', style: TextStyle(color: Colors.white24)))
                            : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final r = filtered[index];
                                final data = r['data'] as Map;
                                final time = r['created_at'].toString().split('T').first;
                                final vars = data.entries.map((e) => '${e.key}: ${e.value}').join(' | ');
                                
                                return ListTile(
                                  title: Text(data['CI'] ?? data['CI_CODE'] ?? 'Unidad #${r['id']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                  subtitle: Text('$vars\n$time - ${r['operator']}', style: const TextStyle(fontSize: 10, color: Colors.white38)),
                                  isThreeLine: true,
                                  trailing: ElevatedButton.icon(
                                    onPressed: () {
                                      _handleReprint(r);
                                      Navigator.pop(ctx);
                                    },
                                    icon: const Icon(Icons.print_rounded, size: 16),
                                    label: const Text('REIMPRIMIR'),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan, foregroundColor: Colors.black),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  Future<void> _handleReprint(Map<String, dynamic> registry) async {
    if (_selectedStandard == null) return;
    
    final data = Map<String, String>.from((registry['data'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())));
    
    setState(() => _printing = true);
    try {
      final res = await _serigrafiaService.printLabel(_selectedStandard!, data);
      if (res.ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reimpresión enviada correctamente'), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${res.error}'), backgroundColor: Colors.red));
      }
    } catch (_) {}
    setState(() => _printing = false);
  }
}
