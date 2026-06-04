import 'dart:convert';
import 'package:flutter/foundation.dart';
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
  final VoidCallback? onRefresh;

  const SerigrafiaPanel({
    super.key,
    required this.order,
    this.detail,
    this.service,
    this.onRefresh,
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
  
  // Phase 3: Mapping & Filtering
  Map<String, String> _variableToColumnMapping = {};
  int? _startCiFilter;
  int? _endCiFilter;
  final TextEditingController _startCiController = TextEditingController();
  final TextEditingController _endCiController = TextEditingController();
  
  // Phase 4: Execution
  int _currentRowIndex = 1; // 1-indexed, starts after header
  bool _printing = false;
  List<Map<String, dynamic>> _registries = [];
  
  // CI Inventory
  bool _requiresCI = false;
  String? _currentCiCode;
  bool _fetchingCI = false;
  
  // Registry Picking mode (if variable 'CI' exists)
  bool _isUsingExistingRegistry = false;
  final Map<String, Set<int>> _approvedLengthsByVariable = {};
  
  final FocusNode _scanFocusNode = FocusNode();
  final TextEditingController _scanController = TextEditingController();

  @override
  void dispose() {
    _startCiController.dispose();
    _endCiController.dispose();
    _scanFocusNode.dispose();
    _scanController.dispose();
    super.dispose();
  }

  excel_pkg.Sheet? get _firstSheet {
    if (_excel == null) return null;
    final sheets = _excel!.sheets;
    if (sheets.isEmpty) return null;
    return sheets.values.first;
  }

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
      _approvedLengthsByVariable.clear();
    });
    
    try {
      // Normalize path for web/api (replace backslashes from Windows paths)
      final normalizedPath = photo.filePath.replaceAll('\\', '/');
      final doc = await _serigrafiaService.downloadAndParseExcel(normalizedPath);
      
      if (doc != null && mounted) {
        setState(() {
          _excel = doc;
          // Use sheets instead of tables for 4.x compatibility and check if empty
          if (doc.sheets.values.isNotEmpty) {
            _excelHeaders = _serigrafiaService.getExcelHeaders(doc);
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
             final sheet = _excel?.sheets.values.isNotEmpty == true ? _firstSheet : null;
             if (sheet != null) {
               sheet.updateCell(
                 excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: _currentRowIndex),
                 excel_pkg.TextCellValue(_currentCiCode!),
               );
             }
          }
        });
      }
    } catch (_) {}
    setState(() => _fetchingCI = false);
  }

  void _startExecution() {
    if (_excel == null || _selectedStandard == null) return;
    
    // Validate mapping
    if (_allVariables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El estándar seleccionado no tiene variables configuradas. Verifica el repositorio.'), backgroundColor: Colors.orange),
      );
      return;
    }

    for (final v in _allVariables) {
      final colName = _variableToColumnMapping[v];
      if (colName == null || colName.isEmpty || !_excelHeaders.contains(colName)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falta mapear o es inválida la variable $v')),
        );
        return;
      }
    }
    
    setState(() => _currentStep = 4);
    _syncExcelWithDatabase();
  }

  Future<void> _saveAndUploadToServer({bool silent = false}) async {
    if (_excel == null) return;
    try {
      final bytes = _excel!.encode();
      if (bytes != null) {
        final originalName = _selectedAttachment?.fileName ?? "serigrafia.xlsx";
        // Always use a specific "Corrected" name on the server
        final targetName = "SERIGRAFIA_CORREGIDO_$originalName";
        
        final res = await _serigrafiaService.uploadExcel(widget.order.idnbr, Uint8List.fromList(bytes), targetName);
        
        if (!silent && mounted) {
           if (res.ok) {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excel sincronizado y guardado en Archivos'), backgroundColor: Colors.green));
             widget.onRefresh?.call();
           } else {
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar Excel: ${res.error}'), backgroundColor: Colors.red));
           }
        }
      }
    } catch (e) {
      if (!silent) debugPrint('Error en _saveAndUploadToServer: $e');
    }
  }

  Future<void> _syncExcelWithDatabase() async {
    if (_excel == null) return;
    
    // Show a loading indicator if needed, but since we are at Step 4, 
    // we can just run it once at the start.
    final registries = await _serigrafiaService.getRegistries(widget.order.idnbr, labelName: _selectedStandard!.name, includeProject: true);
    _registries = registries;
    
    if (registries.isEmpty) {
      _advanceToNextEmptyRow();
      return;
    }
    
    setState(() {
      final sheet = _firstSheet;
      if (sheet == null) return;
      
      // Iterate through each row in the Excel (skip header)
      for (int i = 1; i < sheet.maxRows; i++) {
        final row = sheet.rows[i];
        
        // Find a matching registry record for this row
        Map<String, dynamic>? match;
        
        // Strategy: Key matching. Only attempt to match on known unique identifiers
        // to prevent copying data based on generic fields like 'PRODUCTO' or 'MODELO'.
        final uniqueKeys = ['CI', 'CI_CODE', 'SERIAL'];
        
        for (final v in _allVariables) {
          if (!uniqueKeys.contains(v.toUpperCase().trim())) continue;
          
          final targetHeader = _variableToColumnMapping[v]?.toUpperCase().trim() ?? '';
          if (targetHeader.isEmpty) continue;
          
          int colIdx = -1;
          for (int k = 0; k < _excelHeaders.length; k++) {
            if (_excelHeaders[k].toUpperCase().trim() == targetHeader) {
              colIdx = k;
              break;
            }
          }
          
          if (colIdx != -1) {
            final excelVal = row.length > colIdx ? row[colIdx]?.value?.toString()?.trim() ?? '' : '';
            if (excelVal.isNotEmpty && excelVal.toLowerCase() != 'null') {
              // SMART MATCH: Try to find a registry by this value as EITHER a CI or a Serial
              match = registries.where((r) {
                final data = r['data'] as Map;
                final regCi = (data['CI'] ?? data['CI_CODE'])?.toString();
                final regSerial = data['SERIAL']?.toString();
                
                return regCi == excelVal || regSerial == excelVal;
              }).firstOrNull;
              
              if (match != null) break;
            }
          }
        }
        
        // If we found a match in DB, fix the Excel columns using DB data
        if (match != null) {
          final data = match['data'] as Map;
          for (final v in _allVariables) {
            final targetHeader = _variableToColumnMapping[v]?.toUpperCase().trim() ?? '';
            if (targetHeader.isEmpty) continue;
            
            int colIdx = -1;
            for (int k = 0; k < _excelHeaders.length; k++) {
              if (_excelHeaders[k].toUpperCase().trim() == targetHeader) {
                colIdx = k;
                break;
              }
            }
            
            if (colIdx != -1) {
              // PULL FROM DB: Get the canonical value for this variable (CI, SERIAL, etc)
              String? canonicalVal;
              final upperV = v.toUpperCase();
              if (upperV == 'CI' || upperV == 'CI_CODE') canonicalVal = (data['CI'] ?? data['CI_CODE'])?.toString();
              else if (upperV == 'SERIAL') canonicalVal = data['SERIAL']?.toString();
              else {
                // Fallback for other fields
                data.forEach((rk, rv) {
                  if (rk.toString().toUpperCase() == upperV) canonicalVal = rv?.toString();
                });
              }

              if (canonicalVal != null) {
                final currentVal = row.length > colIdx ? row[colIdx]?.value?.toString()?.trim() ?? '' : '';
                if (canonicalVal != currentVal) {
                  sheet.updateCell(
                    excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: i),
                    excel_pkg.TextCellValue(canonicalVal!),
                  );
                }
              }
            }
          }
        }
      }
    });

    _saveAndUploadToServer(silent: true);
    _advanceToNextEmptyRow();
  }

  void _advanceToNextEmptyRow() {
    if (_excel == null || _selectedStandard == null) return;
    final sheet = _firstSheet;
    if (sheet == null) return;
    
    // Performance optimization: Fetch rows once to avoid O(N^2) complexity
    final rows = sheet.rows;
    final maxRows = sheet.maxRows;
    
    // Pre-calculate column indices to avoid repeated indexOf calls and handle case/spacing
    final colIndices = <String, int>{};
    for (final v in _allVariables) {
      final targetHeader = _variableToColumnMapping[v]?.toUpperCase().trim() ?? '';
      int foundIdx = -1;
      if (targetHeader.isNotEmpty) {
        for (int k = 0; k < _excelHeaders.length; k++) {
          if (_excelHeaders[k].toUpperCase().trim() == targetHeader) {
            foundIdx = k;
            break;
          }
        }
      }
      colIndices[v] = foundIdx;
    }
    
    // Search for the first incomplete row
    for (int i = 1; i < maxRows; i++) {
      // 1. CI Range Filtering
      if (_startCiFilter != null || _endCiFilter != null) {
        // Find CI value for this row
        int? rowCi;
        for (final v in _allVariables) {
          if (v.toUpperCase() == 'CI' || v.toUpperCase() == 'CI_CODE') {
            final colIdx = colIndices[v] ?? -1;
            if (colIdx != -1) {
              final cell = _firstSheet!.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: i));
              final val = cell.value?.toString() ?? '';
              rowCi = int.tryParse(val.replaceAll(RegExp(r'[^0-9]'), ''));
              break;
            }
          }
        }
        
        if (rowCi != null) {
          if (_startCiFilter != null && rowCi < _startCiFilter!) continue;
          if (_endCiFilter != null && rowCi > _endCiFilter!) continue;
        } else {
          // If the row has no numeric CI but we have a filter active, we might want to skip it
          // unless it's a completely empty row we might use later.
          // For safety, if filtering is active and no CI found, skip.
          continue; 
        }
      }

      // Handle sparse rows in excel package
      if (i >= rows.length) {
        setState(() {
          _currentRowIndex = i;
          _currentCiCode = null;
        });
        if (_requiresCI) _fetchNextCI();
        return;
      }

      final row = rows[i];
      bool allFilled = true;
      
      for (final variableName in _allVariables) {
        final colIndex = colIndices[variableName] ?? -1;
        
        // Only check completion for variables that are actually mapped to a column.
        // If a variable is not mapped, we ignore it for completion checks.
        if (colIndex != -1) {
          final cell = _firstSheet!.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: i));
          final cellValue = cell.value?.toString()?.trim() ?? '';
          
          if (cellValue.isEmpty || cellValue.toLowerCase() == 'null' || cellValue.toLowerCase() == 'undefined') {
            allFilled = false;
            break;
          }
        }
      }
      
      if (!allFilled) {
        String? existingCi;
        for (final v in _allVariables) {
          if (v.toUpperCase() == 'CI' || v.toUpperCase() == 'CI_CODE') {
             final cIdx = colIndices[v] ?? -1;
             if (cIdx != -1) {
               existingCi = row.length > cIdx ? row[cIdx]?.value?.toString()?.trim() ?? '' : '';
             }
          }
        }

        setState(() {
          _currentRowIndex = i;
          _currentCiCode = (existingCi?.isNotEmpty == true && existingCi?.toLowerCase() != 'null') ? existingCi : null;
        });
        
        // Only fetch a new CI if the current row doesn't have one
        if (_requiresCI && _currentCiCode == null) {
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

  void _jumpToNextGap() {
    if (_excel == null || _firstSheet == null) return;
    final sheet = _firstSheet!;
    
    // Find column indices for CI and SERIAL
    int ciIdx = -1;
    int serialIdx = -1;
    
    for (final v in _allVariables) {
      final target = _variableToColumnMapping[v]?.toUpperCase().trim() ?? '';
      if (target.isEmpty) continue;
      
      for (int k = 0; k < _excelHeaders.length; k++) {
        if (_excelHeaders[k].toUpperCase().trim() == target) {
          if (v.toUpperCase() == 'CI' || v.toUpperCase() == 'CI_CODE') ciIdx = k;
          if (v.toUpperCase() == 'SERIAL') serialIdx = k;
        }
      }
    }
    
    if (ciIdx == -1 || serialIdx == -1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falta mapear CI o SERIAL para buscar huecos'), backgroundColor: Colors.orange));
      return;
    }

    for (int i = 1; i < sheet.maxRows; i++) {
      // 1. Respect CI Range Filter
      if (_startCiFilter != null || _endCiFilter != null) {
        final ciCell = sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: ciIdx, rowIndex: i));
        final val = ciCell.value?.toString() ?? '';
        final numeric = int.tryParse(val.replaceAll(RegExp(r'[^0-9]'), ''));
        if (numeric != null) {
          if (_startCiFilter != null && numeric < _startCiFilter!) continue;
          if (_endCiFilter != null && numeric > _endCiFilter!) continue;
        } else continue;
      }

      final ciVal = sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: ciIdx, rowIndex: i)).value?.toString()?.trim() ?? '';
      final serialVal = sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: serialIdx, rowIndex: i)).value?.toString()?.trim() ?? '';
      
      // A "Gap" is where CI exists but Serial is empty/null/undefined
      if (ciVal.isNotEmpty && ciVal.toLowerCase() != 'null' && 
          (serialVal.isEmpty || serialVal.toLowerCase() == 'null' || serialVal.toLowerCase() == 'undefined')) {
        setState(() => _currentRowIndex = i);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saltando al hueco en Fila ${i+1} (CI: $ciVal)'), backgroundColor: Colors.cyan));
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontraron más huecos en el rango'), backgroundColor: Colors.green));
  }

  void _autoDetectCiRange(String colName) {
    if (_excel == null || _firstSheet == null) return;
    
    final colIdx = _excelHeaders.indexOf(colName);
    if (colIdx == -1) return;
    
    int? minCi;
    int? maxCi;
    
    final sheet = _firstSheet!;
    List<int> candidates = [];
    
    for (int i = 1; i < sheet.maxRows; i++) {
      final cell = sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: i));
      final val = cell.value?.toString() ?? '';
      
      // Clean the string to keep only digits
      final digitsOnly = val.replaceAll(RegExp(r'[^0-9]'), '');
      if (digitsOnly.isEmpty) continue;
      
      final numeric = int.tryParse(digitsOnly);
      if (numeric != null) {
        // SMART FILTER: Only accept numbers that look like CIs 
        // (Typically 5 to 8 digits. Ignore 10+ digit serials and short codes)
        if (digitsOnly.length >= 5 && digitsOnly.length <= 8) {
          candidates.add(numeric);
        }
      }
    }
    
    if (candidates.isNotEmpty) {
      // MAJORITY FILTER: Group by first 2 digits and pick the most common prefix
      final Map<String, List<int>> groups = {};
      for (final c in candidates) {
        final prefix = c.toString().substring(0, 2);
        groups.putIfAbsent(prefix, () => []).add(c);
      }
      
      // Find the winner group (the one with the most entries)
      String? winnerPrefix;
      int maxCount = 0;
      groups.forEach((prefix, list) {
        if (list.length > maxCount) {
          maxCount = list.length;
          winnerPrefix = prefix;
        }
      });
      
      if (winnerPrefix != null) {
        final winnerList = groups[winnerPrefix]!..sort();
        final minCi = winnerList.first;
        final maxCi = winnerList.last;
        
        setState(() {
          _startCiFilter = minCi;
          _endCiFilter = maxCi;
          _startCiController.text = minCi.toString();
          _endCiController.text = maxCi.toString();
        });
        debugPrint('SerigrafiaPanel: Majority Auto-detected CI range (prefix $winnerPrefix): $minCi - $maxCi ($maxCount units)');
      }
    } else {
      // If no standard CIs found, maybe they are different. Clear filters to avoid garbage.
      setState(() {
        _startCiController.clear();
        _endCiController.clear();
        _startCiFilter = null;
        _endCiFilter = null;
      });
    }
  }

    Map<String, int>? _buildCiIntervalSummary() {
      if (_excel == null || _firstSheet == null) return null;
      if (_startCiFilter == null || _endCiFilter == null) return null;

      final start = _startCiFilter!;
      final end = _endCiFilter!;
      if (end < start) return null;

      String? ciVariable;
      for (final candidate in ['CI', 'CI_CODE']) {
        final mappedColumn = _variableToColumnMapping[candidate];
        if (mappedColumn != null && mappedColumn.isNotEmpty) {
          ciVariable = candidate;
          break;
        }
      }

      if (ciVariable == null) return null;

      final colName = _variableToColumnMapping[ciVariable];
      if (colName == null || colName.isEmpty) return null;

      final colIdx = _excelHeaders.indexOf(colName);
      if (colIdx == -1) return null;

      final sheet = _firstSheet!;
      final found = <int>{};

      for (int i = 1; i < sheet.maxRows; i++) {
        final cell = sheet.cell(
          excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: i),
        );
        final raw = cell.value?.toString() ?? '';
        final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
        final numeric = int.tryParse(digitsOnly);
        if (numeric == null) continue;
        if (numeric < start || numeric > end) continue;
        found.add(numeric);
      }

      final total = end - start + 1;
      final foundCount = found.length;
      final missing = total - foundCount;

      return {
        'total': total,
        'found': foundCount,
        'missing': missing < 0 ? 0 : missing,
      };
    }

    Widget _buildCiIntervalSummaryCard() {
      final summary = _buildCiIntervalSummary();
      if (summary == null) return const SizedBox.shrink();

      final total = summary['total'] ?? 0;
      final found = summary['found'] ?? 0;
      final missing = summary['missing'] ?? 0;

      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            const Icon(Icons.analytics_rounded, color: Colors.cyan, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Intervalo CI: $total valores esperados | Encontrados: $found | Faltan: $missing',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
            if (missing == 0)
              const Text(
                'COMPLETO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              )
            else
              Text(
                'PENDIENTES: $missing',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
          ],
        ),
      );
    }

  Widget _buildScanField(String field) {
    return SizedBox(
      width: 300,
      child: TextField(
        key: ValueKey('scan_field_${_currentRowIndex}_$field'),
        controller: _scanController,
        focusNode: _scanFocusNode,
        autofocus: true,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: 'ESCANEAR $field',
          border: const OutlineInputBorder(),
          hintText: 'Esperando escaneo...',
        ),
        onSubmitted: (val) async {
          final scanValue = val.trim();
          if (scanValue.isNotEmpty) {
            _scanController.clear();
            await _updateCell(field, scanValue);
            // Request focus back for the next field if any
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _scanFocusNode.requestFocus();
            });
          }
        },
      ),
    );
  }

  Widget _buildBrowseRegistryButton() {
    return ElevatedButton.icon(
      onPressed: _showRegistryManager,
      icon: const Icon(Icons.history_rounded),
      label: const Text('HISTORIAL / BUSCAR'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white10, 
        foregroundColor: Colors.cyan, 
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _updateCell(String variable, String value) async {
    final sheet = _firstSheet;
    if (sheet == null) return;
    
    final colName = _variableToColumnMapping[variable];
    if (colName == null) return;
    
    final colIdx = _excelHeaders.indexOf(colName);
    if (colIdx == -1) return;
    
    setState(() {
      // Optimization: only update if value changed
      final currentVal = sheet.rows[_currentRowIndex].length > colIdx 
          ? sheet.rows[_currentRowIndex][colIdx]?.value?.toString()?.trim() ?? '' 
          : '';
          
      if (currentVal != value) {
        sheet.updateCell(
          excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: _currentRowIndex),
          excel_pkg.TextCellValue(value),
        );
      }
    });
    
    // Auto-submit if complete
    await _checkCompletionAndSubmit();
  }

  Future<void> _checkCompletionAndSubmit() async {
    if (_excel == null) return;
    final sheet = _firstSheet;
    if (sheet == null) return;
    
    final row = sheet.rows[_currentRowIndex];
    
    final values = <String, String>{};
    bool isComplete = true;
    
    for (final v in _allVariables) {
      final targetHeader = _variableToColumnMapping[v]?.toUpperCase().trim() ?? '';
      int colIdx = -1;
      for (int k = 0; k < _excelHeaders.length; k++) {
        if (_excelHeaders[k].toUpperCase().trim() == targetHeader) {
          colIdx = k;
          break;
        }
      }
      
      if (colIdx != -1) {
        final val = row.length > colIdx ? row[colIdx]?.value?.toString()?.trim() ?? '' : '';
        if (val.isEmpty || val.toLowerCase() == 'null' || val.toLowerCase() == 'undefined') {
          isComplete = false;
          break;
        }
        values[v] = val;
      } else {
        isComplete = false;
        break;
      }
    }
    
    if (isComplete && !_printing) {
      await _printAndSubmit(values);
    }
  }

  Future<void> _showRegistryManager({String? initialQuery}) async {
    // Fetch registries with includeProject: true to ensure we have all data for duplicate detection,
    // but we will be careful about what we use for auto-syncing.
    final registries = await _serigrafiaService.getRegistries(widget.order.idnbr, labelName: _selectedStandard!.name, includeProject: true);

    final searchCtrl = TextEditingController(text: initialQuery ?? '');
    String searchQuery = initialQuery ?? '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = registries.where((r) {
              final dataStr = (r['data'] ?? {}).toString().toLowerCase();
              final ci = (r['ci'] ?? '').toString().toLowerCase();
              final serial = (r['serial'] ?? '').toString().toLowerCase();
              final op = (r['operator'] ?? '').toString().toLowerCase();
              final q = searchQuery.toLowerCase();
              
              return dataStr.contains(q) || ci.contains(q) || serial.contains(q) || op.contains(q);
            }).toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: Row(
                children: [
                  const Icon(Icons.history_rounded, color: Colors.cyan),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Historial de Registros', style: const TextStyle(color: Colors.cyan))),
                  SizedBox(
                    width: 250,
                    child: TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Buscar CI, Serial...',
                        prefixIcon: const Icon(Icons.search, size: 16),
                        suffixIcon: searchQuery.isNotEmpty 
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16), 
                              onPressed: () {
                                searchCtrl.clear();
                                setDialogState(() => searchQuery = '');
                              },
                            )
                          : null,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (v) => setDialogState(() => searchQuery = v),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 700,
                height: 500,
                child: filtered.isEmpty
                    ? const Center(child: Text('No hay registros registrados aún', style: TextStyle(color: Colors.white24)))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final r = filtered[index];
                          final data = r['data'] as Map;
                          final time = r['created_at'].toString().split('T').first;
                          return Card(
                            color: Colors.white.withOpacity(0.03),
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            child: ListTile(
                              leading: const Icon(Icons.inventory_2_outlined, color: Colors.cyan, size: 24),
                              title: Text(data['CI'] ?? data['CI_CODE'] ?? 'Sin CI', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                              subtitle: Text('${data['MAC'] ?? ''} | ${data['SERIAL'] ?? data['Serial'] ?? ''}\n$time - ${r['operator']}', style: const TextStyle(fontSize: 11, color: Colors.white38)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_note_rounded, color: Colors.cyan, size: 22),
                                    tooltip: 'Editar Registro',
                                    onPressed: () => _showEditRegistryDialog(r).then((updatedData) async {
                                      if (updatedData != null) {
                                         final refreshed = await _serigrafiaService.getRegistries(widget.order.idnbr);
                                         setDialogState(() {
                                            registries.clear();
                                            registries.addAll(refreshed);
                                         });
                                      }
                                    }),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 22),
                                    tooltip: 'Eliminar Registro',
                                    onPressed: () async {
                                      final ok = await _showConfirmDelete(r['id']);
                                      if (ok) {
                                        final refreshed = await _serigrafiaService.getRegistries(widget.order.idnbr);
                                        setDialogState(() {
                                          registries.clear();
                                          registries.addAll(refreshed);
                                        });
                                      }
                                    },
                                  ),
                                  const VerticalDivider(width: 20, indent: 10, endIndent: 10),
                                  ElevatedButton(
                                    onPressed: () {
                                      _applyRegistryToExcel(r);
                                      Navigator.pop(ctx);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.cyan.withOpacity(0.12), 
                                      foregroundColor: Colors.cyan,
                                      elevation: 0,
                                    ),
                                    child: const Text('USAR EN EXCEL'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CERRAR')),
              ],
            );
          },
        );
      },
    );
  }

  Future<Map<String, String>?> _showEditRegistryDialog(Map<String, dynamic> registry) async {
    final rawData = registry['data'] as Map;
    final controllers = <String, TextEditingController>{};
    rawData.forEach((k, v) {
      controllers[k.toString()] = TextEditingController(text: v.toString());
    });

    final res = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Editar Datos del Registro', style: TextStyle(color: Colors.cyan)),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Modifica los valores escaneados para este registro:', style: TextStyle(fontSize: 12, color: Colors.white38)),
                const SizedBox(height: 16),
                ...controllers.entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: e.value,
                      decoration: InputDecoration(
                        labelText: e.key, 
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
          FilledButton(
            onPressed: () async {
              final newData = <String, String>{};
              controllers.forEach((k, v) => newData[k] = v.text.trim());
              
              final updateRes = await _serigrafiaService.updateRegistry(registry['id'], {
                'data': newData,
                'ci': newData['CI'] ?? newData['CI_CODE'],
                'serial': newData['SERIAL'] ?? newData['Serial'],
              });
              
              if (updateRes.ok) {
                if (mounted) Navigator.pop(ctx, newData);
              } else {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${updateRes.error}'), backgroundColor: Colors.red));
              }
            },
            child: const Text('GUARDAR CAMBIOS'),
          ),
        ],
      ),
    );
    controllers.forEach((k, v) => v.dispose());
    return res;
  }

  Future<bool> _showConfirmDelete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Eliminar Registro Histórico'),
        content: const Text('¿Estás seguro de que deseas eliminar este registro?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) {
      final res = await _serigrafiaService.deleteRegistry(id);
      return res.ok;
    }
    return false;
  }

  void _applyRegistryToExcel(Map<String, dynamic> registry) {
    setState(() {
      final data = registry['data'] as Map;
      final sheet = _firstSheet;
      if (sheet == null) return;
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
            final currentVal = sheet.rows[_currentRowIndex].length > colIdx 
                ? sheet.rows[_currentRowIndex][colIdx]?.value?.toString()?.trim() ?? '' 
                : '';
            
            if (currentVal != value) {
              sheet.updateCell(
                excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: _currentRowIndex),
                excel_pkg.TextCellValue(value!),
              );
            }
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
      final wasUsingRegistry = _isUsingExistingRegistry;
      
      // 1. REGISTER FIRST (Database is the priority)
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
               SnackBar(content: Text('ERROR CRÍTICO: No se pudo guardar en base de datos. Impresión cancelada.\n${saveRes.error}'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
             );
           }
           setState(() => _printing = false);
           return; // ABORT PRINTING
        }
      }

      // 2. PRINT SECOND (Only if database is safe)
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
          // Update Local Excel
          final sheet = _firstSheet;
          if (sheet == null) return;
          
          values.forEach((varName, value) {
             final colName = _variableToColumnMapping[varName];
             final colIdx = _excelHeaders.indexOf(colName ?? '');
             if (colIdx != -1) {
                final currentVal = sheet.rows[_currentRowIndex].length > colIdx 
                    ? sheet.rows[_currentRowIndex][colIdx]?.value?.toString()?.trim() ?? '' 
                    : '';
                if (currentVal != value) {
                  sheet.updateCell(
                    excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: _currentRowIndex), 
                    excel_pkg.TextCellValue(value)
                  );
                }
             }
          });
          
          _isUsingExistingRegistry = false; // Reset for next unit
          _advanceToNextEmptyRow();
           
          // Auto-save Excel status to server (Original and Corregido)
          _saveAndUpload(silent: true);
          _saveAndUploadToServer(silent: true);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Registro guardado e impresión enviada exitosamente'), backgroundColor: Colors.green),
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
          if (wasUsingRegistry) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('ERROR DE IMPRESIÓN: $detail\nPulsa REIMPRIMIR si es necesario.'),
                backgroundColor: Colors.redAccent,
                duration: const Duration(seconds: 8),
              ),
            );
            // Do NOT advance or reset _isUsingExistingRegistry so they can retry printing the same existing unit
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Registro guardado, pero ERROR DE IMPRESIÓN: $detail\nPulsa REIMPRIMIR si es necesario.'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 8),
              ),
            );
            // Even if print fails, we already saved, so move on or allow retry
            _isUsingExistingRegistry = false; 
            _advanceToNextEmptyRow();
          }
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 650;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(isCompact),
              const Divider(height: 1, color: Colors.white10),
              Padding(
                padding: EdgeInsets.all(isCompact ? 12 : 24),
                child: _buildStepContent(isCompact),
              ),
              if (_currentStep > 1) _buildFooterActions(isCompact),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(bool isCompact) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 24, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.print_outlined, color: Colors.cyan, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isCompact ? 'SERIGRAFIADO' : 'FLUJO DE SERIGRAFIADO', 
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isCompact)
                  const Text('Automatización Excel-Print-Scan', style: TextStyle(fontSize: 10, color: Colors.white38)),
              ],
            ),
          ),
          if (isCompact) ...[
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.cyan),
              onSelected: (value) {
                if (value == 'reprint') {
                  _showReprintDialog();
                } else if (value == 'repository') {
                  Navigator.pushNamed(context, '/serials/repository').then((_) => _loadStandards());
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'reprint',
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Reimprimir'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'repository',
                  child: Row(
                    children: [
                      Icon(Icons.settings_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Configurar Repositorio'),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
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
          ],
          const SizedBox(width: 8),
          _buildStepDots(isCompact),
        ],
      ),
    );
  }

  Widget _buildStepDots(bool isCompact) {
    if (isCompact) {
      return Text(
        '$_currentStep/4',
        style: const TextStyle(
          color: Colors.cyan,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      );
    }
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

  Widget _buildStepContent(bool isCompact) {
    switch (_currentStep) {
      case 1: return _buildPhase1(isCompact);
      case 2: return _buildPhase2(isCompact);
      case 3: return _buildPhase3(isCompact);
      case 4: return _buildPhase4(isCompact);
      default: return const SizedBox();
    }
  }

  Widget _buildPhase1(bool isCompact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(isCompact ? 10 : 16),
          decoration: BoxDecoration(color: Colors.cyan.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.cyan.withOpacity(0.2))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CONFIGURACIÓN DEL FLUJO', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.cyan, fontSize: 10, letterSpacing: 1)),
              SwitchListTile(
                contentPadding: isCompact ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: Text('¿Requiere etiqueta de inventariado CI?', style: TextStyle(fontSize: isCompact ? 12 : 14, fontWeight: FontWeight.bold)),
                subtitle: Text('Genera y vincula automáticamente códigos de inventario de la base de datos', style: TextStyle(fontSize: isCompact ? 9 : 11, color: Colors.white38)),
                value: _requiresCI,
                activeColor: Colors.cyan,
                onChanged: (val) => setState(() => _requiresCI = val),
              ),
            ],
          ),
        ),
        SizedBox(height: isCompact ? 16 : 24),
        const Text('SELECCIONA EL ESTÁNDAR DE ETIQUETA', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey, fontSize: 10, letterSpacing: 1)),
        const SizedBox(height: 12),
        ..._standards.map((s) => _buildStandardTile(s, isCompact)),
        const SizedBox(height: 12),
        _buildManualStandardTile(isCompact),
      ],
    );
  }

  Widget _buildManualStandardTile(bool isCompact) {
    return InkWell(
      onTap: _showManualStandardDialog,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(isCompact ? 12 : 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_link_rounded, color: Colors.grey, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text('Configurar Estándar Manual', style: TextStyle(color: Colors.grey, fontSize: isCompact ? 12 : 14))),
            const Icon(Icons.edit_note_rounded, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStandardTile(SerigrafiaStandard s, bool isCompact) {
    final isSelected = _selectedStandard == s;
    return InkWell(
      onTap: () => setState(() {
        _selectedStandard = s;
        _currentStep = 2;
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(isCompact ? 12 : 16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyan.withOpacity(0.1) : Colors.white.withOpacity(0.05),
          border: Border.all(color: isSelected ? Colors.cyan : Colors.white.withOpacity(0.1)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.label_important_outline_rounded, color: Colors.cyan, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: isCompact ? 13 : 14)),
                  Text('${s.variables.join(', ')}', style: TextStyle(fontSize: isCompact ? 10 : 12, color: Colors.cyan)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
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



  Widget _buildPhase2(bool isCompact) {
    final photos = widget.detail?.photos ?? [];
    final excels = photos.where((p) => p.fileName.toLowerCase().endsWith('.xlsx') || p.fileName.toLowerCase().endsWith('.xls'));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PASO 2: SELECCIONA EL EXCEL DE ARCHIVOS', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey, fontSize: isCompact ? 10 : 11)),
        const SizedBox(height: 16),
        if (_loadingExcel) const Center(child: CircularProgressIndicator()),
        if (!_loadingExcel && excels.isEmpty) 
          const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No hay archivos Excel adjuntos en esta orden', textAlign: TextAlign.center, style: TextStyle(color: Colors.white24)))),
        if (!_loadingExcel)
          ...excels.map((p) => _buildExcelTile(p)),
      ],
    );
  }

  Future<void> _createExcelFromRegistries() async {
    setState(() => _loadingExcel = true);
    try {
      final registries = await _serigrafiaService.getRegistries(widget.order.idnbr, labelName: _selectedStandard?.name, includeProject: true);
      if (registries.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay coincidencias registradas en la base de datos para esta orden/estándar.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() => _loadingExcel = false);
        return;
      }

      final headers = _allVariables;
      if (headers.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El estándar seleccionado no tiene variables. Configura las variables del estándar primero.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() => _loadingExcel = false);
        return;
      }

      final excel = excel_pkg.Excel.createExcel();
      final sheetName = excel.sheets.keys.first;
      final sheet = excel[sheetName];

      sheet.appendRow(headers.map((h) => excel_pkg.TextCellValue(h)).toList());

      for (final r in registries) {
        final data = r['data'] as Map?;
        final List<excel_pkg.CellValue?> rowValues = [];
        for (final h in headers) {
          String? val;
          if (data != null) {
            data.forEach((k, v) {
              if (k.toString().toUpperCase() == h.toUpperCase()) {
                val = v.toString();
              }
            });
            if (val == null) {
              if (h.toUpperCase() == 'CI' || h.toUpperCase() == 'CI_CODE') val = r['ci']?.toString();
              else if (h.toUpperCase() == 'SERIAL') val = r['serial']?.toString();
            }
          }
          rowValues.add(excel_pkg.TextCellValue(val ?? ''));
        }
        sheet.appendRow(rowValues);
      }

      final bytes = excel.encode();
      if (bytes == null) {
        throw Exception('Error al codificar el archivo Excel.');
      }

      final cleanOrderNbr = widget.order.orderNbr?.replaceAll(RegExp(r'[^\w\-]'), '_') ?? widget.order.idnbr.toString();
      final fileName = 'Serigrafia_Manual_${cleanOrderNbr}.xlsx';
      final res = await _serigrafiaService.uploadExcel(
        widget.order.idnbr,
        Uint8List.fromList(bytes),
        fileName,
      );

      if (res.ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Archivo Excel creado de las coincidencias y guardado en archivos.'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onRefresh?.call();
        
        setState(() {
          _excel = excel;
          _excelHeaders = headers;
          if (_currentStep < 4) {
            _currentStep = 3;
          }
          _currentCiCode = null;
        });
      } else {
        throw Exception(res.error ?? 'Error desconocido al subir el archivo.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al crear Excel: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    setState(() => _loadingExcel = false);
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

  Widget _buildPhase3(bool isCompact) {
    if (_selectedStandard == null) return const SizedBox();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PASO 3: MAPEO Y FILTRO DE RANGO', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey, fontSize: isCompact ? 10 : 11)),
        const SizedBox(height: 16),
        
        // CI Range Filter Section
        Container(
          padding: EdgeInsets.all(isCompact ? 10 : 16),
          decoration: BoxDecoration(
            color: Colors.cyan.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.cyan.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.filter_alt_rounded, size: 16, color: Colors.cyan),
                  const SizedBox(width: 8),
                  Text('FILTRAR POR RANGO DE CI (OPCIONAL)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.cyan, fontSize: isCompact ? 10 : 11)),
                ],
              ),
              const SizedBox(height: 16),
              isCompact
                  ? Column(
                      children: [
                        TextField(
                          controller: _startCiController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'CI Inicial (ej: 816735)', border: OutlineInputBorder()),
                          onChanged: (val) => setState(() => _startCiFilter = int.tryParse(val)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _endCiController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'CI Final (ej: 816800)', border: OutlineInputBorder()),
                          onChanged: (val) => setState(() => _endCiFilter = int.tryParse(val)),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _startCiController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'CI Inicial (ej: 816735)', border: OutlineInputBorder()),
                            onChanged: (val) => setState(() => _startCiFilter = int.tryParse(val)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _endCiController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'CI Final (ej: 816800)', border: OutlineInputBorder()),
                            onChanged: (val) => setState(() => _endCiFilter = int.tryParse(val)),
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 8),
              Text('Si se define un rango, la app solo mostrará las filas que tengan un CI dentro de estos números.', style: TextStyle(fontSize: isCompact ? 9 : 10, color: Colors.white38)),
            ],
          ),
        ),
        
        SizedBox(height: isCompact ? 20 : 32),
        Text('MAPEO DE VARIABLES A COLUMNAS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: isCompact ? 9 : 10)),
        const SizedBox(height: 12),
        ..._allVariables.map((v) => _buildMappingRow(v, isCompact)),
        SizedBox(height: isCompact ? 20 : 32),
        Center(
          child: FilledButton.icon(
            onPressed: _startExecution,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Comenzar Procesamiento'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.cyan, 
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 24 : 32, vertical: isCompact ? 12 : 16)
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMappingRow(String variableName, bool isCompact) {
    final currentMapping = _variableToColumnMapping[variableName];
    if (isCompact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.cyan.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(variableName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.cyan)),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.white24),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _excelHeaders.contains(currentMapping) ? currentMapping : null,
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder()),
              hint: const Text('Seleccionar Columna', style: TextStyle(fontSize: 12)),
              items: _excelHeaders.map((h) => DropdownMenuItem(value: h, child: Text(h, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _variableToColumnMapping[variableName] = val);
                  if (variableName.toUpperCase() == 'CI' || variableName.toUpperCase() == 'CI_CODE') {
                    _autoDetectCiRange(val);
                  }
                }
              },
            ),
          ],
        ),
      );
    }
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
              onChanged: (val) {
                if (val != null) {
                  setState(() => _variableToColumnMapping[variableName] = val);
                  if (variableName.toUpperCase() == 'CI' || variableName.toUpperCase() == 'CI_CODE') {
                    _autoDetectCiRange(val);
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhase4(bool isCompact) {
    if (_excel == null) return const SizedBox();
    final sheet = _firstSheet;
    if (sheet == null) return const Center(child: Text('No se pudo encontrar la hoja de cálculo'));
    final rowData = sheet.rows[_currentRowIndex];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isCompact) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('PASO 4: ESCANEO Y REGISTRO', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey, fontSize: 10)),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.cyan),
                onSelected: (value) {
                  switch (value) {
                    case 'history':
                      _showRegistryManager();
                      break;
                    case 'sync':
                      _syncExcelWithDatabase();
                      break;
                    case 'export':
                      if (!_loadingExcel) _createExcelFromRegistries();
                      break;
                    case 'current':
                      _advanceToNextEmptyRow();
                      break;
                    case 'gap':
                      _jumpToNextGap();
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'history',
                    child: Row(
                      children: [
                        Icon(Icons.history_toggle_off_rounded, size: 18, color: Colors.cyan),
                        SizedBox(width: 8),
                        Text('Ver Historial', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'sync',
                    child: Row(
                      children: [
                        Icon(Icons.sync_rounded, size: 18, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('Forzar Sincronización', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'export',
                    child: Row(
                      children: [
                        Icon(Icons.download_for_offline_outlined, size: 18, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Exportar Relación', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'current',
                    child: Row(
                      children: [
                        Icon(Icons.fast_forward_rounded, size: 18, color: Colors.cyan),
                        SizedBox(width: 8),
                        Text('Volver al Actual', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'gap',
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, size: 18, color: Colors.cyan),
                        SizedBox(width: 8),
                        Text('Buscar Hueco', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 20, color: Colors.cyan),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _currentRowIndex > 1
                        ? () => setState(() => _currentRowIndex--)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text('Fila ${_currentRowIndex + 1} de ${sheet.maxRows}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyan)),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.cyan),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _currentRowIndex < sheet.maxRows - 1
                        ? () => setState(() => _currentRowIndex++)
                        : null,
                  ),
                ],
              ),
              if (_startCiFilter != null || _endCiFilter != null)
                 Container(
                   padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                   decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.orange.withOpacity(0.3))),
                   child: const Text('FILTRADO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange)),
                 ),
            ],
          ),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('PASO 4: ESCANEO Y REGISTRO', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey, fontSize: 11)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.history_toggle_off_rounded, size: 22, color: Colors.cyan),
                    tooltip: 'Ver Historial de Registros',
                    onPressed: _showRegistryManager,
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _syncExcelWithDatabase,
                    icon: const Icon(Icons.sync_rounded, size: 16, color: Colors.orange),
                    label: const Text('FORZAR SINCRONIZACIÓN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.orange.withOpacity(0.05),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _loadingExcel ? null : _createExcelFromRegistries,
                    icon: const Icon(Icons.download_for_offline_outlined, size: 16, color: Colors.green),
                    label: const Text('EXPORTAR RELACIÓN A EXCEL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.green.withOpacity(0.05),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _advanceToNextEmptyRow,
                    icon: const Icon(Icons.fast_forward_rounded, size: 16, color: Colors.cyan),
                    label: const Text('VOLVER AL ACTUAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.cyan)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.cyan.withOpacity(0.05),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _jumpToNextGap,
                    icon: const Icon(Icons.search_rounded, size: 16, color: Colors.cyan),
                    label: const Text('BUSCAR HUECO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.cyan)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.cyan.withOpacity(0.05),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 20, color: Colors.white12),
                  const SizedBox(width: 8),
                  if (_startCiFilter != null || _endCiFilter != null)
                     Container(
                       padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                       margin: const EdgeInsets.only(right: 8),
                       decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.orange.withOpacity(0.3))),
                       child: const Text('FILTRADO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange)),
                     ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 20, color: Colors.cyan),
                    tooltip: 'Fila Anterior',
                    onPressed: _currentRowIndex > 1
                        ? () => setState(() => _currentRowIndex--)
                        : null,
                  ),
                  Text('Fila ${_currentRowIndex + 1} de ${sheet.maxRows}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.cyan)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.cyan),
                    tooltip: 'Siguiente Fila',
                    onPressed: _currentRowIndex < sheet.maxRows - 1
                        ? () => setState(() => _currentRowIndex++)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _buildCiIntervalSummaryCard(),
        const SizedBox(height: 16),
        _buildCurrentRowPreview(rowData, isCompact),
        const SizedBox(height: 32),
        _buildScanningUI(),
      ],
    );
  }

  Widget _buildRawDataPreview(List<excel_pkg.Data?> row) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('VISTA PREVIA DE DATOS RAW (EXCEL)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38)),
                  Text('HOJA: ${_excel?.sheets.keys.firstWhere((k) => _excel?.sheets[k] == _firstSheet, orElse: () => "Desconocida")}', 
                    style: const TextStyle(fontSize: 10, color: Colors.cyan, fontWeight: FontWeight.bold)),
                ],
              ),
              Text('EXCEL ROW: ${_currentRowIndex + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(row.length, (i) {
                final header = _excelHeaders.length > i ? _excelHeaders[i] : '---';
                final val = row[i]?.value?.toString() ?? '(vacio)';
                final colLetter = String.fromCharCode(65 + (i % 26)); // A, B, C...
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: val.toLowerCase().contains('uk') ? Colors.cyan.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: val.toLowerCase().contains('uk') ? Colors.cyan.withOpacity(0.3) : Colors.transparent)
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('[$colLetter] $header', style: const TextStyle(fontSize: 9, color: Colors.cyan, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(val, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentRowPreview(List<excel_pkg.Data?> row, bool isCompact) {
    // Extract mapped variables only
    final mappedValues = <String, String>{};
    String? ciValue;

    for (final v in _allVariables) {
      final targetHeader = _variableToColumnMapping[v]?.toUpperCase().trim() ?? '';
      int colIdx = -1;
      for (int k = 0; k < _excelHeaders.length; k++) {
        if (_excelHeaders[k].toUpperCase().trim() == targetHeader) {
          colIdx = k;
          break;
        }
      }
      
      if (colIdx != -1) {
        // Use absolute coordinate access to prevent shifting
        final cell = _firstSheet!.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: _currentRowIndex));
        final val = cell.value?.toString()?.trim() ?? '';
        
        mappedValues[v] = val;
        // Check if this variable is CI or CI_CODE for a prominent display
        if (v.toUpperCase() == 'CI' || v.toUpperCase() == 'CI_CODE') {
          if (val.isNotEmpty && val.toLowerCase() != 'null') ciValue = val;
        }
      }
    }

    // SMART UI SWAPPER: Fix visual swaps (UK code in CI box, Number in Serial box)
    if (ciValue != null && ciValue!.toUpperCase().contains('UK')) {
       final serialVal = mappedValues['SERIAL'];
       // If Serial has a number but CI has the UK code, swap them for the UI
       if (serialVal != null && RegExp(r'^\d+$').hasMatch(serialVal)) {
          final temp = ciValue;
          ciValue = serialVal;
          mappedValues['SERIAL'] = temp!;
       }
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 12 : 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(isCompact ? 16 : 24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (ciValue != null) ...[
            Text('CÓDIGO DE INVENTARIO (CI)', style: TextStyle(fontSize: isCompact ? 9 : 10, fontWeight: FontWeight.w900, color: Colors.cyan, letterSpacing: isCompact ? 1.5 : 2)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showRegistryManager(initialQuery: ciValue),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  ciValue!,
                  style: TextStyle(fontSize: isCompact ? 32 : 48, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
                ),
              ),
            ),
            SizedBox(height: isCompact ? 12 : 24),
            Divider(color: Colors.white.withOpacity(0.05), indent: isCompact ? 10 : 40, endIndent: isCompact ? 10 : 40),
            SizedBox(height: isCompact ? 12 : 24),
          ],
          Text('DATOS DE LA ETIQUETA', style: TextStyle(fontSize: isCompact ? 8 : 9, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 1.5)),
          const SizedBox(height: 16),
          Wrap(
            spacing: isCompact ? 8 : 12,
            runSpacing: isCompact ? 8 : 12,
            alignment: WrapAlignment.center,
            children: mappedValues.entries.where((e) => e.key.toUpperCase() != 'CI' && e.key.toUpperCase() != 'CI_CODE').map((e) {
              final isMissing = e.value.isEmpty;
              return Container(
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 10 : 16, vertical: isCompact ? 6 : 10),
                decoration: BoxDecoration(
                  color: isMissing ? Colors.orange.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(isCompact ? 8 : 12),
                  border: Border.all(color: isMissing ? Colors.orange.withOpacity(0.3) : Colors.white.withOpacity(0.1)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${e.key}${!isMissing ? " (${_variableToColumnMapping[e.key]})" : ""}: ', 
                      style: TextStyle(fontSize: isCompact ? 9 : 10, fontWeight: FontWeight.bold, color: isMissing ? Colors.orange : Colors.white38)
                    ),
                    Text(
                      isMissing ? 'ESPERANDO...' : e.value,
                      style: TextStyle(
                        fontSize: isCompact ? 11 : 13,
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
            Text('Listo para imprimir', style: TextStyle(fontSize: isCompact ? 11 : 12, color: Colors.green, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildScanningUI() {
    final sheet = _firstSheet;
    if (sheet == null) return const SizedBox();
    
    String? fieldToScan;
    for (final v in _allVariables) {
      final targetHeader = _variableToColumnMapping[v]?.toUpperCase().trim() ?? '';
      int colIdx = -1;
      for (int k = 0; k < _excelHeaders.length; k++) {
        if (_excelHeaders[k].toUpperCase().trim() == targetHeader) {
          colIdx = k;
          break;
        }
      }
      
      final val = (colIdx != -1 && sheet.rows[_currentRowIndex].length > colIdx) 
          ? sheet.rows[_currentRowIndex][colIdx]?.value?.toString()?.trim() ?? '' 
          : '';
      
      if (val.isEmpty || val.toLowerCase() == 'null' || val.toLowerCase() == 'undefined') {
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

    // Emergency Controls for "Glitched" rows
    final bool isGlitched = fieldToScan == null && _requiresCI;
    
    if (fieldToScan == null && !isGlitched) {
       // ... existing printing logic ...
    }

    // If we have a value but it might be wrong (Glitched row)
    if (fieldToScan == null && _requiresCI) {
       return Center(
         child: Column(
           children: [
             const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
             const SizedBox(height: 16),
             const Text('Fila Detectada como "Completada"', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
             const Text('Si los datos son incorrectos (columnas movidas), usa estos controles:', style: TextStyle(fontSize: 10, color: Colors.white38)),
             const SizedBox(height: 24),
             Row(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 ElevatedButton.icon(
                   onPressed: () async {
                     setState(() {
                       _currentCiCode = null;
                       _updateCell('CI', '');
                       _updateCell('CI_CODE', '');
                     });
                     _fetchNextCI();
                   }, 
                   icon: const Icon(Icons.refresh), 
                   label: const Text('REGENERAR CI (NUEVO)')
                 ),
                 const SizedBox(width: 16),
                 ElevatedButton.icon(
                   onPressed: () {
                     // Force scan mode by resetting a field
                     setState(() {
                       _updateCell('SERIAL', '');
                     });
                   }, 
                   icon: const Icon(Icons.qr_code_scanner), 
                   label: const Text('RE-ESCANEAR SERIAL')
                 ),
               ],
             )
           ],
         ),
       );
    }
    
    if (fieldToScan == null) {
      if (_printing) {
        return const Center(
          child: Column(
            children: [
              Icon(Icons.print_rounded, color: Colors.green, size: 64),
              SizedBox(height: 16),
              Text('Imprimiendo...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              SizedBox(height: 8),
              CircularProgressIndicator(),
            ],
          ),
        );
      }
      
      return Center(
        child: Column(
          children: [
            const Icon(Icons.verified_rounded, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            const Text('Fila Completada', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green)),
            const Text('Esta fila ya tiene todos los datos registrados.', style: TextStyle(fontSize: 13, color: Colors.white38)),
            const SizedBox(height: 32),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    final values = <String, String>{};
                    final sheet = _firstSheet;
                    if (sheet == null) return;
                    
                    final row = sheet.rows[_currentRowIndex];
                    for (final v in _allVariables) {
                      final colName = _variableToColumnMapping[v];
                      final colIdx = _excelHeaders.indexOf(colName ?? '');
                      if (colIdx != -1) {
                         values[v] = row[colIdx]?.value?.toString() ?? '';
                      }
                    }
                    _printAndSubmit(values);
                  },
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('REIMPRIMIR ETIQUETA'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan, 
                    foregroundColor: Colors.white, 
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                       final sheet = _firstSheet;
                       if (sheet == null) return;
                       
                       for (final v in _allVariables) {
                         final colName = _variableToColumnMapping[v];
                         final colIdx = _excelHeaders.indexOf(colName ?? '');
                         if (colIdx != -1) {
                            sheet.updateCell(
                              excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: _currentRowIndex),
                              excel_pkg.TextCellValue(''),
                            );
                         }
                       }
                       _currentCiCode = null;
                       _isUsingExistingRegistry = false;
                    });
                  },
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('BORRAR Y RE-ESCANEAR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange, 
                    side: const BorderSide(color: Colors.orange), 
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        const Icon(Icons.qr_code_scanner_rounded, size: 48, color: Colors.cyan),
        const SizedBox(height: 16),
        Text('ESCANEANDO: $fieldToScan', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.cyan)),
        const SizedBox(height: 24),
        TextField(
          key: ValueKey('main_scan_${_currentRowIndex}_$fieldToScan'),
          controller: _scanController,
          focusNode: _scanFocusNode,
          autofocus: true,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            labelText: 'EN ESPERA DE ESCANEO...', 
            border: OutlineInputBorder(),
            hintText: 'Escanea un código para continuar'
          ),
          onSubmitted: (val) async {
            final scanValue = val.trim();
            if (scanValue.isEmpty) return;
            
            _scanController.clear();
            
            // 0. Check for CI vs Serial confusion (Removed because CIs can be numeric)
            
            // 1. Check for duplicates
            bool isDuplicate = _checkForDuplicate(fieldToScan!, scanValue);
            if (isDuplicate) {
               bool proceed = await _showValidationWarning(
                 'VALOR DUPLICADO',
                 'El valor "$scanValue" ya ha sido registrado en otra fila. ¿Deseas registrarlo de todos modos?'
               );
               if (!proceed) {
                 _scanFocusNode.requestFocus();
                 return;
               }
            }

            // 2. Check for length anomaly
            int? expectedLength = _getExpectedLength(fieldToScan!);
            final scannedLength = scanValue.length;
            if (expectedLength != null && scannedLength != expectedLength && !_isApprovedLength(fieldToScan!, scannedLength)) {
               bool proceed = await _showValidationWarning(
                 'ANOMALÍA DE LONGITUD',
                 'La longitud de este escaneo ($scannedLength) es diferente a la del primer registro ($expectedLength).\n¿Deseas permitir también esta longitud para el resto de la orden?'
               );
               if (!proceed) {
                 _scanFocusNode.requestFocus();
                 return;
               }
               _approveLength(fieldToScan!, scannedLength);
            }

            setState(() {
               final sheet = _firstSheet;
               if (sheet == null) return;
               
               final colName = _variableToColumnMapping[fieldToScan!];
               if (colName == null) return;
               
               final colIdx = _excelHeaders.indexOf(colName);
               
               final currentVal = sheet.rows[_currentRowIndex].length > colIdx 
                   ? sheet.rows[_currentRowIndex][colIdx]?.value?.toString()?.trim() ?? '' 
                   : '';
               
               if (currentVal != scanValue) {
                 sheet.updateCell(
                   excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: _currentRowIndex),
                   excel_pkg.TextCellValue(scanValue),
                 );
               }
               
               if (fieldToScan == 'CI' || fieldToScan == 'CI_CODE') {
                 _currentCiCode = scanValue;
               }
            });
            
            await _checkCompletionAndSubmit();
            
            // Ensure focus is requested back for the next field or row
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _scanFocusNode.requestFocus();
            });
          },
        ),
      ],
    );
  }

  bool _checkForDuplicate(String variable, String value) {
    if (_excel == null) return false;
    final sheet = _firstSheet;
    if (sheet == null) return false;
    
    final targetHeader = _variableToColumnMapping[variable]?.toUpperCase().trim() ?? '';
    
    int colIdx = -1;
    for (int k = 0; k < _excelHeaders.length; k++) {
      if (_excelHeaders[k].toUpperCase().trim() == targetHeader) {
        colIdx = k;
        break;
      }
    }

    // 1. Check all rows in current Excel for duplicates
    if (colIdx != -1) {
      for (int i = 1; i < sheet.maxRows; i++) {
         if (i == _currentRowIndex) continue;
         final row = sheet.rows[i];
         if (row.length > colIdx) {
            final cellVal = row[colIdx]?.value?.toString()?.trim();
            if (cellVal != null && cellVal.isNotEmpty && cellVal.toLowerCase() != 'null' && cellVal == value) return true;
         }
      }
    }

    // 2. Check database registries (fetched project-wide)
    for (final r in _registries) {
      // If it's a registry from THIS order, we probably already caught it in the Excel check,
      // but checking here is a good safety measure for unsaved/other sessions.
      final data = r['data'] is Map ? r['data'] as Map : {};
      for (final entry in data.entries) {
        final rk = entry.key.toString().toUpperCase().trim();
        final rv = entry.value?.toString()?.trim();
        
        // Match the variable name (case-insensitive)
        if (rk == variable.toUpperCase().trim()) {
          if (rv != null && rv.isNotEmpty && rv == value) {
            // Found a duplicate in the database!
            return true;
          }
        }
      }
    }

    return false;
  }

  int? _getExpectedLength(String variable) {
    if (_excel == null) return null;
    final sheet = _firstSheet;
    if (sheet == null) return null;
    
    final colName = _variableToColumnMapping[variable];
    final colIdx = _excelHeaders.indexOf(colName ?? '');
    if (colIdx == -1) return null;

    // Find the first row (starting from index 1) that has a non-empty value in this column
    // and use its length as a reference
    for (int i = 1; i < sheet.maxRows; i++) {
       final row = sheet.rows[i];
       if (row.length > colIdx) {
          final val = row[colIdx]?.value?.toString().trim() ?? '';
          if (val.isNotEmpty) return val.length;
       }
    }
    return null;
  }

  String _lengthKey(String variable) => variable.toUpperCase().trim();

  bool _isApprovedLength(String variable, int length) {
    return _approvedLengthsByVariable[_lengthKey(variable)]?.contains(length) ?? false;
  }

  void _approveLength(String variable, int length) {
    _approvedLengthsByVariable.putIfAbsent(_lengthKey(variable), () => <int>{}).add(length);
  }

  Future<bool> _showValidationWarning(String title, String message) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange, 
              foregroundColor: Colors.black,
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
            child: const Text('CONFIRMAR REGISTRO'),
          ),
        ],
      ),
    ) ?? false;
  }

  Widget _buildFooterActions(bool isCompact) {
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

  /// Create a clean copy of the Excel data to avoid shared string corruption
  /// common in excel package 4.x when modifying files multiple times.
  Uint8List? _safeEncode() {
    if (_excel == null) return null;
    
    try {
      final newExcel = excel_pkg.Excel.createExcel();
      
      // The new excel starts with 'Sheet1' by default
      final defaultSheetName = newExcel.sheets.keys.first;
      
      for (final sheetName in _excel!.sheets.keys) {
        final oldSheet = _excel!.sheets[sheetName]!;
        
        excel_pkg.Sheet newSheet;
        if (sheetName == _excel!.sheets.keys.first) {
          // Rename the default 'Sheet1' to the original first sheet name
          newExcel.rename(defaultSheetName, sheetName);
          newSheet = newExcel[sheetName];
        } else {
          newSheet = newExcel[sheetName];
        }

        // Copy data row by row
        for (int r = 0; r < oldSheet.maxRows; r++) {
          final row = oldSheet.rows[r];
          final List<excel_pkg.CellValue?> newRow = [];
          for (int c = 0; c < row.length; c++) {
            newRow.add(row[c]?.value);
          }
          newSheet.appendRow(newRow);
        }
        
        // Try to copy column widths
        final oldWidths = oldSheet.getColumnWidths;
        for (final colIdx in oldWidths.keys) {
          newSheet.setColumnWidth(colIdx, oldWidths[colIdx]!);
        }
      }
      
      final encoded = newExcel.encode();
      return encoded != null ? Uint8List.fromList(encoded) : null;
    } catch (e) {
      debugPrint('Safe Encode failed: $e. Falling back to regular encode.');
      final encoded = _excel!.encode();
      return encoded != null ? Uint8List.fromList(encoded) : null;
    }
  }

  Future<void> _saveAndUpload({bool silent = false}) async {
     if (_excel == null || _selectedAttachment == null) return;
     
     if (!silent) setState(() => _printing = true);
     try {
        final bytes = _safeEncode();
        if (bytes != null) {
           final api = ApiService.instance;
           if (api != null) {
              // Ensure filename has .xlsx extension if it was converted from .xls
              String fileName = _selectedAttachment!.fileName;
              if (fileName.toLowerCase().endsWith('.xls')) {
                fileName = fileName.substring(0, fileName.length - 4) + '.xlsx';
              }

              final res = await api.client.postMultipart(
                '/orderops/agent-orders/${widget.order.idnbr}/photos',
                fields: {'overwrite': 'true'},
                files: [
                  MultipartAttachment(
                    fieldName: 'file',
                    fileName: fileName,
                    bytes: bytes,
                  )
                ],
              );
              if (res.ok && !silent) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excel actualizado y subido exitosamente'), backgroundColor: Colors.green));
                 widget.onRefresh?.call();
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
              _serigrafiaService.getRegistries(widget.order.idnbr, labelName: _selectedStandard?.name, includeProject: true).then((results) {
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
