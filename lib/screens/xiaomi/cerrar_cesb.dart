import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';
import '../../services/xiaomi_provider.dart';
import '../../widgets/main_sidebar.dart';

class CerrarCesbScreen extends StatefulWidget {
  final String? initialCesb;
  final bool isEmbedded;
  const CerrarCesbScreen({
    super.key,
    this.initialCesb,
    this.isEmbedded = false,
  });

  @override
  State<CerrarCesbScreen> createState() => _CerrarCesbScreenState();
}

class _CerrarCesbScreenState extends State<CerrarCesbScreen> {
  XiaomiTeam? _selectedTeam;
  bool _submitting = false;
  OverlayEntry? _edgeOverlay;

  List<dynamic> _pendingList = [];
  bool _loadingPending = false;
  Map<String, dynamic>? _activeCesb;
  Map<String, dynamic>? _nextCesb;
  String? _manuallySelectedNextCesbId;
  Map<String, String> _employeesMap = {};

  Timer? _timer;
  Duration _elapsed = Duration.zero;
  Map<String, dynamic>? _persistentPrinter;
  bool _isShowingPrinterDialog = false;

  Future<void> _loadPersistentPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('xiaomi_printer_id');
    final ip = prefs.getString('xiaomi_printer_ip');
    final name = prefs.getString('xiaomi_printer_name');
    if (id != null) {
      setState(() {
        _persistentPrinter = {
          'printer_id': int.tryParse(id) ?? id,
          'printer_name': name ?? 'Impresora Guardada',
        };
      });
    } else if (ip != null) {
      setState(() {
        _persistentPrinter = {
          'printer_ip': ip,
          'printer_name': name ?? ip,
        };
      });
    }
  }

  Future<void> _loadEmployees() async {
    try {
      final api = ApiService.instance?.client;
      if (api == null) return;
      final res = await api.get('/empleados/');
      if (res.ok && res.body is List) {
        final Map<String, String> tempMap = {};
        for (var u in res.body) {
          final username = u['usuario'] ?? '';
          final name = '${u['nombre'] ?? ''} ${u['apellido'] ?? ''}'.trim();
          if (username.isNotEmpty && name.isNotEmpty) {
            tempMap[username] = name;
          }
        }
        if (mounted) {
          setState(() {
            _employeesMap = tempMap;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading employees: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _edgeOverlay?.remove();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadPersistentPrinter();
    _loadEmployees();
    
    // Initialize teams and pending
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<XiaomiProvider>().initTeams();
      context.read<XiaomiProvider>().fetchSummary();
      _refreshData();
      
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

  Future<void> _refreshData() async {
    if (!mounted) return;
    setState(() => _loadingPending = true);
    try {
      final api = ApiService.instance?.client;
      if (api == null) return;
      
      final resp = await api.get('/xiaomieco/not_finished_cesb');
      if (resp.ok && resp.body is Map) {
        final items = resp.body['not_finished'] as List? ?? [];
        if (mounted) {
          setState(() {
            _pendingList = items;
            _evaluateState();
          });
        }
      }
      
      // Also refresh stats summary
      await context.read<XiaomiProvider>().fetchSummary();
    } catch (e) {
      debugPrint('Error refreshData: $e');
    } finally {
      if (mounted) setState(() => _loadingPending = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPrinters({
    String q = '',
    int limit = 1000,
  }) async {
    final client = ApiService.instance?.client;
    if (client == null) throw Exception('Servicio API no disponible');
    final encoded = Uri.encodeQueryComponent(q.trim());
    final res = await client.get('/serials/printers?q=$encoded&limit=$limit');
    if (!res.ok) throw Exception('Error fetching printers (${res.statusCode})');
    final body = res.body;
    if (body is List) {
      return body
          .whereType<Map>()
          .map((e) => _normalizePrinterEntry(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (body is Map) {
      for (final key in ['results', 'printers', 'data']) {
        if (body[key] is List) {
          return (body[key] as List)
              .whereType<Map>()
              .map((e) => _normalizePrinterEntry(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
      for (final v in body.values) {
        if (v is List) {
          return v
              .whereType<Map>()
              .map((e) => _normalizePrinterEntry(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
    }
    return [];
  }

  Map<String, dynamic> _normalizePrinterEntry(Map<String, dynamic> e) {
    String? id;
    try {
      id = (e['id_printer'] ?? e['id'] ?? e['printer_id'] ?? e['idPrinter'])
          ?.toString();
    } catch (_) {
      id = null;
    }
    String? name;
    try {
      name = (e['printer_name'] ?? e['name'] ?? e['printerName'])?.toString();
    } catch (_) {
      name = null;
    }
    String? ip;
    try {
      ip =
          (e['ip_address'] ??
                  e['ip'] ??
                  e['address'] ??
                  e['ip_address']?.toString())
              ?.toString();
    } catch (_) {
      ip = null;
    }
    final out = <String, dynamic>{};
    if (id != null && id.isNotEmpty) out['id_printer'] = int.tryParse(id) ?? id;
    if (name != null) out['printer_name'] = name;
    if (ip != null) out['ip_address'] = ip;
    for (final kv in e.entries) {
      if (!out.containsKey(kv.key)) out[kv.key.toString()] = kv.value;
    }
    return out;
  }

  Future<Map<String, dynamic>?> _getOrSelectPrinter(String title, {bool forceShow = false}) async {
    if (_persistentPrinter != null && !forceShow) return _persistentPrinter;
    if (_isShowingPrinterDialog) return null;

    _isShowingPrinterDialog = true;
    try {
      List<Map<String, dynamic>> printers = [];
      try {
        printers = await _fetchPrinters();
      } catch (e) {
        printers = [];
        if (mounted) {
          try {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error obteniendo impresoras: $e')),
            );
          } catch (_) {}
        }
      }

      Map<String, dynamic>? selectedPrinter;
      final txtIp = TextEditingController();

      if (!mounted) return null;

      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (printers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'No se encontraron impresoras en el servidor. Puedes introducir una IP manualmente.',
                    ),
                  )
                else
                  Column(
                    children: printers
                        .map(
                          (p) => RadioListTile<Map<String, dynamic>>(
                            value: p,
                            groupValue: selectedPrinter,
                            title: Text(
                              p['printer_name']?.toString() ??
                                  p['ip_address']?.toString() ??
                                  'Impresora',
                            ),
                            subtitle: Text(p['ip_address']?.toString() ?? ''),
                            onChanged: (v) {
                              selectedPrinter = v;
                              (c as Element).markNeedsBuild();
                            },
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: txtIp,
                  decoration: const InputDecoration(
                    labelText:
                        'IP de impresora (opcional, sobreescribe selección)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final nameCtrl = TextEditingController();
                final ipCtrl = TextEditingController();
                final addOk = await showDialog<bool>(
                  context: c,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Registrar Nueva Impresora'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: 'Nombre de Impresora'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: ipCtrl,
                          decoration: const InputDecoration(labelText: 'Dirección IP'),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Guardar'),
                      ),
                    ],
                  ),
                );
                
                if (addOk == true) {
                  final name = nameCtrl.text.trim();
                  final ip = ipCtrl.text.trim();
                  if (name.isNotEmpty && ip.isNotEmpty) {
                    final api = ApiService.instance?.client;
                    if (api != null) {
                      final res = await api.post('/serials/printers/add', jsonBody: {
                        'printer_name': name,
                        'ip_address': ip,
                      });
                      if (res.ok) {
                        try {
                          final freshPrinters = await _fetchPrinters();
                          printers = freshPrinters;
                        } catch (_) {}
                        (c as Element).markNeedsBuild();
                      } else {
                        final errorMsg = res.body is Map ? (res.body['error'] ?? res.error) : res.error;
                        if (c.mounted) {
                          ScaffoldMessenger.of(c).showSnackBar(
                            SnackBar(content: Text('Error: $errorMsg'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    }
                  }
                }
                nameCtrl.dispose();
                ipCtrl.dispose();
              },
              child: const Text('Añadir Impresora'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );

      final manualIp = txtIp.text.trim().isNotEmpty ? txtIp.text.trim() : null;
      txtIp.dispose();

      if (ok != true) return null;

      final result = <String, dynamic>{};
      if (manualIp != null) {
        result['printer_ip'] = manualIp;
        result['printer_name'] = manualIp;
      } else if (selectedPrinter != null) {
        if (selectedPrinter!['id_printer'] != null) {
          result['printer_id'] = selectedPrinter!['id_printer'];
        } else if (selectedPrinter!['ip_address'] != null) {
          result['printer_ip'] = selectedPrinter!['ip_address'];
        }
        result['printer_name'] = selectedPrinter!['printer_name'] ?? selectedPrinter!['ip_address'] ?? 'Impresora';
      } else if (printers.isNotEmpty) {
        final first = printers.first;
        if (first['id_printer'] != null) {
          result['printer_id'] = first['id_printer'];
        } else if (first['ip_address'] != null) {
          result['printer_ip'] = first['ip_address'];
        }
        result['printer_name'] = first['printer_name'] ?? first['ip_address'] ?? 'Impresora';
      } else {
        throw Exception('No printer selected or provided');
      }

      final prefs = await SharedPreferences.getInstance();
      if (result['printer_id'] != null) {
        await prefs.setString('xiaomi_printer_id', result['printer_id'].toString());
        await prefs.remove('xiaomi_printer_ip');
      } else if (result['printer_ip'] != null) {
        await prefs.setString('xiaomi_printer_ip', result['printer_ip'].toString());
        await prefs.remove('xiaomi_printer_id');
      }
      if (result['printer_name'] != null) {
        await prefs.setString('xiaomi_printer_name', result['printer_name'].toString());
      }

      setState(() {
        _persistentPrinter = result;
      });
      return result;
    } finally {
      _isShowingPrinterDialog = false;
    }
  }

  Future<void> _printCesbLabel(String cesb) async {
    final client = ApiService.instance?.client;
    if (client == null) return;
    
    if (_persistentPrinter == null) {
      final printer = await _getOrSelectPrinter('Seleccionar impresora para continuar');
      if (printer == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impresión cancelada. No se seleccionó impresora.')),
          );
        }
        return;
      }
    }
    
    if (_persistentPrinter == null) return;
    
    final payload = Map<String, dynamic>.from(_persistentPrinter!);
    payload['cesb'] = cesb;
    
    try {
      final resp = await client.post('/xiaomieco/print_cesb_label/', jsonBody: payload);
      if (mounted) {
        if (resp.ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Imprimiendo siguiente CESB: $cesb'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          final errorMsg = resp.body is Map ? (resp.body['error'] ?? resp.error) : resp.error;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al imprimir: $errorMsg'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de conexión con impresora: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleAfterFinishingCesb() async {
    final validatedList = _pendingList
        .where((item) => item?['fecha_hora_inicio'] == null && item?['fecha_hora_validado'] != null)
        .toList();
        
    final pendingNotValidated = _pendingList
        .where((item) => item?['fecha_hora_inicio'] == null && item?['fecha_hora_validado'] == null)
        .toList();

    if (validatedList.isNotEmpty) {
      if (_nextCesb != null && _nextCesb!['fecha_hora_validado'] != null) {
        final nextCesbName = _nextCesb!['cesb'];
        await _printCesbLabel(nextCesbName);
      }
    } else {
      if (pendingNotValidated.isNotEmpty) {
        await _showValidationDialog();
      } else {
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('¡Enhorabuena!'),
              content: const Text('Ha acabado todos los CESB.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Aceptar'),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  Future<void> _showValidationDialog() async {
    final ctrl = TextEditingController();
    final focus = FocusNode();
    bool validating = false;
    
    if (!mounted) return;
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> submitValidation() async {
            final code = ctrl.text.trim();
            if (code.isEmpty) return;
            
            setDialogState(() => validating = true);
            try {
              final success = await context.read<XiaomiProvider>().validateCesb(code);
              if (success) {
                await _refreshData();
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('CESB $code Validado con éxito'), backgroundColor: Colors.green),
                  );
                  await _handleAfterFinishingCesb();
                }
              } else {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Error al validar CESB $code'), backgroundColor: Colors.red),
                  );
                }
              }
            } finally {
              if (ctx.mounted) {
                setDialogState(() => validating = false);
                ctrl.clear();
                focus.requestFocus();
              }
            }
          }

          return AlertDialog(
            title: const Text('Validar más CESB'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'No quedan más CESB validados. Para continuar, escanea o introduce un nuevo CESB para validarlo:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: ctrl,
                    focusNode: focus,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Escanear CESB...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: validating 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            icon: const Icon(Icons.check_circle_rounded),
                            onPressed: submitValidation,
                          ),
                    ),
                    onSubmitted: (_) => submitValidation(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                },
                child: const Text('Cerrar'),
              ),
            ],
          );
        }
      ),
    );
    
    ctrl.dispose();
    focus.dispose();
  }


  void _evaluateState() {
    if (_selectedTeam == null) {
      _activeCesb = null;
      _nextCesb = null;
      _stopTimer();
      return;
    }

    // A CESB is "selectable" if it hasn't started yet, OR if it's paused.
    // Paused items have fecha_hora_inicio != null but fecha_hora_pausa != null.
    bool isSelectable(Map<String, dynamic>? item) {
      if (item == null) return false;
      final notStarted = item['fecha_hora_inicio'] == null;
      final isPaused = item['fecha_hora_pausa'] != null;
      return notStarted || isPaused;
    }

    // 1. Check if this team has an active CESB (started + not paused + not finished)
    // Match by team_name if available, otherwise fallback to team_id comparison
    final active = _pendingList.cast<Map<String, dynamic>?>().firstWhere(
      (item) {
        if (item == null) return false;
        // Must be started and NOT paused to be considered "active"
        if (item['fecha_hora_inicio'] == null) return false;
        if (item['fecha_hora_pausa'] != null) return false;
        final itemTeamName = item['team_name']?.toString().toLowerCase();
        final selectedTeamName = _selectedTeam!.nombre.toLowerCase();
        if (itemTeamName != null && itemTeamName.isNotEmpty) {
          return itemTeamName == selectedTeamName;
        }
        return item['team_id'] == _selectedTeam!.id;
      },
      orElse: () => null,
    );

    if (active != null) {
      _activeCesb = active;
      _nextCesb = null;
      
      final startTime = DateTime.parse(active['fecha_hora_inicio']);
      final pauseTimeStr = active['fecha_hora_pausa'];
      final pausedSeconds = (active['segundos_pausados'] as num?)?.toInt() ?? 0;
      
      _startTimer(
        startTime, 
        pauseTime: (pauseTimeStr != null && pauseTimeStr.toString().isNotEmpty) 
          ? DateTime.parse(pauseTimeStr) 
          : null,
        pausedSeconds: pausedSeconds,
      );
    } else {
      _activeCesb = null;
      _stopTimer();
      
      // 2. Find the NEXT CESB — not started OR paused (both are valid "next" tasks)
      Map<String, dynamic>? next;
      if (_manuallySelectedNextCesbId != null) {
        next = _pendingList.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['cesb'] == _manuallySelectedNextCesbId && isSelectable(item),
          orElse: () => null,
        );
      }
      
      // Fallback: paused items first (higher priority), then unstarted
      next ??= _pendingList.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['fecha_hora_pausa'] != null, // paused first
        orElse: () => null,
      );
      next ??= _pendingList.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['fecha_hora_inicio'] == null, // then unstarted
        orElse: () => null,
      );
      
      _nextCesb = next;
    }
  }


  void _startTimer(DateTime startTime, {DateTime? pauseTime, int pausedSeconds = 0}) {
    _timer?.cancel();
    
    void updateElapsed() {
      final now = DateTime.now();
      if (pauseTime != null) {
        // If paused, elapsed is fixed at the moment of pause
        _elapsed = pauseTime.difference(startTime) - Duration(seconds: pausedSeconds);
      } else {
        _elapsed = now.difference(startTime) - Duration(seconds: pausedSeconds);
      }
    }

    updateElapsed();
    
    if (pauseTime == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) {
          setState(() {
            updateElapsed();
          });
        }
      });
    } else {
      if (mounted) setState(() {});
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _elapsed = Duration.zero;
  }

  bool get _isSupervisor {
    final role = context.read<ApiService>().currentUser?.role?.toLowerCase();
    return role == 'admin' || role == 'chief' || role == 'clerc' || role == 'technitian';
  }

  Future<void> _onEmpezar() async {
    if (_nextCesb == null || _selectedTeam == null) return;
    
    // PRIORITY CHECK: Is it validated?
    if (_nextCesb!['fecha_hora_validado'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('El CESB ${_nextCesb!['cesb']} debe ser VALIDADO antes de empezar.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final success = await context.read<XiaomiProvider>().startCesb(
        _nextCesb!['cesb'], 
        _selectedTeam!.id
      );
      if (success) {
        await _refreshData();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _onFinalizar() async {
    if (_activeCesb == null || _selectedTeam == null) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Trabajo'),
        content: Text('¿Confirmas que habéis terminado el CESB "${_activeCesb!['cesb']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, Finalizar')),
        ],
      ),
    );

    if (proceed != true) return;

    setState(() => _submitting = true);
    try {
      final success = await context.read<XiaomiProvider>().finishCesb(
        _activeCesb!['cesb'], 
        _selectedTeam!.id
      );
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CESB Finalizado.')));
        await _refreshData();
        await _handleAfterFinishingCesb();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _onPausar() async {
    if (_activeCesb == null) return;
    setState(() => _submitting = true);
    try {
      final success = await context.read<XiaomiProvider>().pauseCesb(_activeCesb!['cesb']);
      if (success) await _refreshData();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _onReanudar() async {
    if (_activeCesb == null) return;
    setState(() => _submitting = true);
    try {
      final success = await context.read<XiaomiProvider>().resumeCesb(_activeCesb!['cesb']);
      if (success) await _refreshData();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final xiaomi = context.watch<XiaomiProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Ejecución (Xiaomi ECO)'),
        automaticallyImplyLeading: false,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [
          IconButton(
            onPressed: () => _refreshData(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primaryContainer.withOpacity(0.2),
                  theme.scaffoldBackgroundColor,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          if (xiaomi.isLoading && !xiaomi.isInitialized)
            const Center(child: CircularProgressIndicator())
          else
            SingleChildScrollView(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 10, bottom: 80),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    children: [
                      if (xiaomi.initStatus == 'missing')
                        _buildInitMissing(xiaomi)
                      else ...[
                        if (_selectedTeam == null)
                          _buildTeamSelector(xiaomi, theme)
                        else
                          _buildCompactTeamHeader(xiaomi, theme),
                        const SizedBox(height: 12),
                        if (_selectedTeam != null && _pendingList.any((item) => item?['fecha_hora_inicio'] == null && item?['fecha_hora_validado'] != null)) ...[
                          _buildPrinterConfigCard(theme),
                          const SizedBox(height: 12),
                        ],
                        _buildWorkControl(theme),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPrinterConfigCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.15)),
      ),
      color: theme.colorScheme.primary.withOpacity(0.02),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.print_rounded, color: theme.colorScheme.primary),
        title: Text(
          _persistentPrinter == null
              ? 'Impresora no configurada'
              : 'Impresora: ${_persistentPrinter!['printer_name'] ?? _persistentPrinter!['printer_ip'] ?? 'Impresora Guardada'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Pulsa para configurar o cambiar la impresora persistente'),
        trailing: const Icon(Icons.edit_rounded, size: 16),
        onTap: () async {
          final printer = await _getOrSelectPrinter('Configurar Impresora', forceShow: true);
          if (printer != null && mounted) {
            setState(() {});
          }
        },
      ),
    );
  }

  Widget _buildCompactTeamHeader(XiaomiProvider xiaomi, ThemeData theme) {
    final teamColor = _getColorFromName(_selectedTeam!.nombre);
    
    final perf = xiaomi.summary?.teamPerformance.firstWhere(
      (p) => p['nombre']?.toString().toLowerCase() == _selectedTeam?.nombre.toLowerCase(),
      orElse: () => <String, dynamic>{},
    );

    final qtyToday = perf?['qty'] ?? 0;
    final avgTime = perf?['avg_time'] ?? 0.0;
    final upm = perf?['upm'] ?? 0.0;

    final memberNames = _selectedTeam?.members.map((username) {
      return _employeesMap[username] ?? username;
    }).toList() ?? [];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: teamColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Equipo ${_selectedTeam!.nombre}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${memberNames.length} ${memberNames.length == 1 ? "persona" : "personas"})',
                  style: TextStyle(color: theme.hintColor, fontSize: 12),
                ),
                const Spacer(),
                if (_isSupervisor) ...[
                  _TeamActionButton(
                    icon: Icons.edit_rounded,
                    label: 'Editar',
                    color: Colors.amber.shade700,
                    onPressed: () => _showTeamDialog(team: _selectedTeam),
                  ),
                  const SizedBox(width: 6),
                ],
                _TeamActionButton(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Cambiar',
                  color: Colors.teal,
                  onPressed: () {
                    setState(() {
                      _selectedTeam = null;
                      _evaluateState();
                    });
                  },
                ),
              ],
            ),
            if (memberNames.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Miembros: ${memberNames.join(", ")}',
                  style: TextStyle(color: theme.hintColor, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildCompactStatItem('UPM', upm.toStringAsFixed(1), Colors.teal, theme),
                _buildCompactStatItem('Tiempo Medio', '${avgTime.toStringAsFixed(1)}m', Colors.indigo, theme),
                _buildCompactStatItem('Total Hoy', '$qtyToday', Colors.orange, theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactStatItem(String label, String value, Color color, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(fontSize: 11, color: theme.hintColor),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildTeamSelector(XiaomiProvider xiaomi, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Equipos de Trabajo',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (_isSupervisor)
                      TextButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Nuevo Equipo', style: TextStyle(fontSize: 13)),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _showTeamDialog(),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (xiaomi.todayTeams.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No hay equipos creados todavía para hoy.',
                        style: TextStyle(color: theme.hintColor),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: xiaomi.todayTeams.map((t) {
                      final isSelected = _selectedTeam?.id == t.id;
                      final teamColor = _getColorFromName(t.nombre);
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTeam = isSelected ? null : t;
                            _evaluateState();
                          });
                        },
                        onLongPress: _isSupervisor ? () => _showTeamDialog(team: t) : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 175,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? teamColor.withOpacity(0.12)
                                : theme.cardColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? teamColor : theme.dividerColor.withOpacity(0.15),
                              width: 2,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: teamColor.withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    )
                                  ]
                                : [],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: teamColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 1.5),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      t.nombre,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  if (_isSupervisor)
                                    GestureDetector(
                                      onTap: () => _showTeamDialog(team: t),
                                      child: Icon(
                                        Icons.edit_rounded,
                                        size: 14,
                                        color: theme.hintColor,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${t.members.length} ${t.members.length == 1 ? "persona" : "personas"}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
        if (_selectedTeam != null) ...[
          const SizedBox(height: 12),
          _buildSelectedTeamDetails(xiaomi, theme),
        ],
      ],
    );
  }

  Widget _buildSelectedTeamDetails(XiaomiProvider xiaomi, ThemeData theme) {
    final perf = xiaomi.summary?.teamPerformance.firstWhere(
      (p) => p['nombre']?.toString().toLowerCase() == _selectedTeam?.nombre.toLowerCase(),
      orElse: () => <String, dynamic>{},
    );

    final qtyToday = perf?['qty'] ?? 0;
    final avgTime = perf?['avg_time'] ?? 0.0;
    final upm = perf?['upm'] ?? 0.0;

    final memberNames = _selectedTeam?.members.map((username) {
      return _employeesMap[username] ?? username;
    }).toList() ?? [];

    final teamColor = _getColorFromName(_selectedTeam!.nombre);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: teamColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Detalles del Equipo: ${_selectedTeam!.nombre}',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isSupervisor) ...[
                  const SizedBox(width: 6),
                  _TeamActionButton(
                    icon: Icons.edit_rounded,
                    label: 'Editar equipo',
                    color: Colors.amber.shade700,
                    onPressed: () => _showTeamDialog(team: _selectedTeam),
                  ),
                ],
                const SizedBox(width: 6),
                _TeamActionButton(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Cambiar equipo',
                  color: Colors.teal,
                  onPressed: () {
                    setState(() {
                      _selectedTeam = null;
                      _evaluateState();
                    });
                  },
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              'INTEGRANTES DEL EQUIPO',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.hintColor,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            if (memberNames.isEmpty)
              Text(
                'No hay miembros en este equipo.',
                style: TextStyle(fontStyle: FontStyle.italic, color: theme.hintColor),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: memberNames.map((name) {
                  return Chip(
                    label: Text(name, style: const TextStyle(fontSize: 12)),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  );
                }).toList(),
              ),
            const Divider(height: 24),
            Text(
              'RENDIMIENTO DE HOY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.hintColor,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatBox(
                    title: 'UPM',
                    value: upm.toStringAsFixed(1),
                    subtitle: 'Unids. / Minuto',
                    icon: Icons.speed_rounded,
                    color: Colors.teal,
                    theme: theme,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatBox(
                    title: 'Tiempo Medio',
                    value: '${avgTime.toStringAsFixed(1)}m',
                    subtitle: 'Por CESB',
                    icon: Icons.timer_rounded,
                    color: Colors.indigo,
                    theme: theme,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatBox(
                    title: 'Total Hoy',
                    value: '$qtyToday',
                    subtitle: 'Unidades',
                    icon: Icons.inventory_2_rounded,
                    color: Colors.orange,
                    theme: theme,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Icon(icon, size: 14, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: theme.hintColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkControl(ThemeData theme) {
    if (_selectedTeam == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_work_rounded, size: 64, color: theme.disabledColor.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text('Selecciona un equipo para ver el trabajo asignado', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_activeCesb != null) {
      return _buildActiveWorkView(theme);
    }

    if (_nextCesb != null) {
      return _buildNextTaskView(theme);
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.done_all_rounded, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          const Text('No hay más CESB pendientes por ahora.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          const Text('¡Buen trabajo!', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildActiveWorkView(ThemeData theme) {
    final bool isPaused = _activeCesb?['fecha_hora_pausa'] != null;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: (isPaused ? Colors.orange : Colors.blue).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: (isPaused ? Colors.orange : Colors.blue).withOpacity(0.3), width: 2),
          ),
          child: Column(
            children: [
              Text(
                isPaused ? 'TRABAJO PAUSADO' : 'TRABAJO EN PROGRESO', 
                style: TextStyle(fontWeight: FontWeight.w900, color: isPaused ? Colors.orange : Colors.blue, letterSpacing: 2)
              ),
              const SizedBox(height: 20),
              Text(_activeCesb!['cesb'] ?? '', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
              Text('${_activeCesb!['sku']} - ${_activeCesb!['qty']} unidades', style: const TextStyle(fontSize: 18, color: Colors.grey)),
              const Divider(height: 40),
              const Text('TIEMPO TRANSCURRIDO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              Text(
                '${_elapsed.inHours.toString().padLeft(2, '0')}:${(_elapsed.inMinutes % 60).toString().padLeft(2, '0')}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 42, 
                  fontFamily: 'Courier', 
                  fontWeight: FontWeight.bold,
                  color: isPaused ? Colors.orange : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : (isPaused ? _onReanudar : _onPausar),
                  icon: Icon(isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                  label: Text(isPaused ? 'REANUDAR' : 'PAUSAR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPaused ? Colors.green : Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _onFinalizar,
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('FINALIZAR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () => _printCesbLabel(_activeCesb!['cesb']),
            icon: const Icon(Icons.print_rounded),
            label: const Text('REIMPRIMIR ETIQUETA CESB'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.5)),
              foregroundColor: theme.colorScheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        if (isPaused) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : () => _showTransferDialog(context),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('TRANSFERIR TAREA A OTRO EQUIPO'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'El tiempo de pausa no se contabiliza en el total.',
            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
          ),
        ],
      ],
    );
  }

  Widget _buildNextTaskView(ThemeData theme) {
    final isValidated = _nextCesb!['fecha_hora_validado'] != null;
    final isPausedNext = _nextCesb!['fecha_hora_pausa'] != null;

    // Include: not-started CESBs + paused CESBs (they need to appear for easy transfer/resume)
    final allPendingRaw = _pendingList
        .where((item) =>
            item?['fecha_hora_inicio'] == null ||
            item?['fecha_hora_pausa'] != null)
        .toList();

    // Deduplicate items by 'cesb' to prevent duplicate values in DropdownButton items.
    final Map<String, dynamic> seenCesbs = {};
    for (var item in allPendingRaw) {
      final String? cesbVal = item?['cesb']?.toString();
      if (cesbVal != null && !seenCesbs.containsKey(cesbVal)) {
        seenCesbs[cesbVal] = item;
      }
    }
    final allPending = seenCesbs.values.toList();

    final String? selectedCesbValue = _nextCesb?['cesb']?.toString();
    final bool hasValueInItems = allPending.any((item) => item['cesb']?.toString() == selectedCesbValue);
    final String? dropdownValue = hasValueInItems ? selectedCesbValue : null;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              if (allPending.length > 1) ...[
                const Text(
                  'SELECCIONAR TAREA PENDIENTE:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.1),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: dropdownValue,
                      dropdownColor: theme.cardColor,
                      items: allPending.map((item) {
                        final cesbName = item['cesb'] ?? 'Sin nombre';
                        final skuName = item['sku'] ?? '';
                        final isVal = item['fecha_hora_validado'] != null;
                        final isPaused = item['fecha_hora_pausa'] != null;
                        final Color itemColor = isPaused
                            ? Colors.amber.shade700
                            : (isVal ? Colors.green : Colors.red);
                        final String statusLabel = isPaused
                            ? 'PAUSADO'
                            : (isVal ? 'VALIDADO' : 'PENDIENTE');
                        return DropdownMenuItem<String>(
                          value: cesbName,
                          child: Row(
                            children: [
                              if (isPaused)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Icon(Icons.pause_circle_rounded, size: 14, color: Colors.amber.shade700),
                                ),
                              Expanded(
                                child: Text(
                                  '$cesbName - $skuName ($statusLabel)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: (isVal || isPaused) ? FontWeight.bold : FontWeight.normal,
                                    color: itemColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _manuallySelectedNextCesbId = val;
                            _evaluateState();
                          });
                        }
                      },
                    ),
                  ),
                ),
                const Divider(height: 32),
              ],
              const Text('TAREA SELECCIONADA', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 11, letterSpacing: 1.1)),
              const SizedBox(height: 16),
              Text(_nextCesb!['cesb'] ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text('${_nextCesb!['sku']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 12),
              if (isPausedNext)
                // Paused: show badge + both resume (this team) and transfer buttons
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade700.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.shade700.withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.pause_circle_rounded, size: 16, color: Colors.amber.shade700),
                          const SizedBox(width: 6),
                          Text(
                            'CESB PAUSADO',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _submitting
                                  ? null
                                  : () async {
                                      setState(() => _submitting = true);
                                      try {
                                        final success = await context
                                            .read<XiaomiProvider>()
                                            .resumeCesb(_nextCesb!['cesb']);
                                        if (success) await _refreshData();
                                      } finally {
                                        if (mounted) setState(() => _submitting = false);
                                      }
                                    },
                              icon: const Icon(Icons.play_arrow_rounded, size: 15),
                              label: const Text(
                                'REANUDAR',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _submitting
                                  ? null
                                  : () => _transferPausedToThisTeam(context),
                              icon: const Icon(Icons.swap_horiz_rounded, size: 15),
                              label: const Text(
                                'TRANSFERIR',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: (isValidated ? Colors.green : Colors.red).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isValidated ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                        size: 16,
                        color: isValidated ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          isValidated ? 'CESB VALIDADO Y RECIBIDO' : 'DEBE VALIDARSE PRIMERO (PENDIENTE)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isValidated ? Colors.green : Colors.red,
                          ),
                          overflow: TextOverflow.visible,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 40),
              _InfoItem(label: 'Unidades', value: '${_nextCesb!['qty']}'),
              _InfoItem(label: 'Cajas', value: '${_nextCesb!['cartons']}'),
              _InfoItem(label: 'Registrado el', value: (_nextCesb!['fecha_hora_registro'] ?? '').toString().replaceAll('T', ' ')),
            ],
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 70,
          child: ElevatedButton.icon(
            onPressed: _submitting
                ? null
                : isPausedNext
                    ? () async {
                        // Resume a paused CESB from the next-task view
                        setState(() => _submitting = true);
                        try {
                          final success = await context
                              .read<XiaomiProvider>()
                              .resumeCesb(_nextCesb!['cesb']);
                          if (success) await _refreshData();
                        } finally {
                          if (mounted) setState(() => _submitting = false);
                        }
                      }
                    : (!isValidated ? null : _onEmpezar),
            icon: Icon(
              isPausedNext ? Icons.play_arrow_rounded : Icons.play_arrow_rounded,
              size: 28,
            ),
            label: Text(
              isPausedNext ? 'REANUDAR TRABAJO' : 'EMPEZAR TRABAJO',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isPausedNext ? Colors.green : theme.colorScheme.primary,
              foregroundColor: isPausedNext
                  ? Colors.white
                  : theme.colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () => _printCesbLabel(_nextCesb!['cesb']),
            icon: const Icon(Icons.print_rounded),
            label: const Text('REIMPRIMIR ETIQUETA CESB'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.5)),
              foregroundColor: theme.colorScheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitMissing(XiaomiProvider xiaomi) {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.group_off_rounded, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'No hay equipos creados para hoy',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _isSupervisor 
                ? 'Como supervisor, puedes crear nuevos equipos o clonar los de ayer.'
                : 'Por favor, solicita a un supervisor (Admin/Chief) que cree los equipos del día.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.hintColor),
            ),
            if (_isSupervisor) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (xiaomi.yesterdayTeams.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () => xiaomi.cloneTeams(),
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Usar Equipos de Ayer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.secondary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showTeamDialog(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Crear Nuevo Equipo'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showTeamDialog({XiaomiTeam? team}) async {
    final isEditing = team != null;
    final List<String> colors = ['Rojo', 'Azul', 'Verde', 'Amarillo', 'Naranja', 'Morado', 'Rosa', 'Marrón', 'Gris', 'Negro'];
    String? selectedColor = isEditing ? team.nombre : colors[0];
    List<Map<String, dynamic>> allUsers = [];
    List<String> selectedUsernames = isEditing ? List.from(team.members) : [];
    String searchQuery = '';
    bool loadingUsers = true;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (loadingUsers) {
            ApiService.instance?.client.get('/empleados/').then((res) {
              if (res.ok && res.body is List) {
                final users = List<Map<String, dynamic>>.from(res.body)
                    .where((u) => u['activo'] == true || u['activo'] == 1)
                    .toList();
                users.sort((a, b) => (a['nombre'] ?? '').toString().compareTo((b['nombre'] ?? '').toString()));
                allUsers = users;
                setDialogState(() => loadingUsers = false);
              }
            });
            return const Center(child: CircularProgressIndicator());
          }

          final xiaomi = context.watch<XiaomiProvider>();
          final existing = xiaomi.todayTeams.cast<XiaomiTeam?>().firstWhere(
            (t) => t?.nombre == selectedColor,
            orElse: () => null,
          );
          final effectiveEditing = isEditing || existing != null;
          final targetTeamId = existing?.id ?? (isEditing ? team.id : null);

          final selectedUsersList = allUsers.where((u) => selectedUsernames.contains(u['usuario'])).toList();
          final availableUsersList = allUsers.where((u) {
            final username = u['usuario'] ?? '';
            final name = '${u['nombre']} ${u['apellido']}'.toLowerCase();
            final matchesSearch = searchQuery.isEmpty || name.contains(searchQuery);
            return !selectedUsernames.contains(username) && matchesSearch;
          }).toList();

          return AlertDialog(
            title: Text(effectiveEditing ? 'Editar Equipo' : 'Crear Equipo'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Color del Equipo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: colors.map((c) {
                        final isSelected = selectedColor == c;
                        final col = _getColorFromName(c);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                selectedColor = c;
                                final existing = xiaomi.todayTeams.cast<XiaomiTeam?>().firstWhere(
                                  (t) => t?.nombre == c,
                                  orElse: () => null,
                                );
                                if (existing != null) {
                                  selectedUsernames = List.from(existing.members);
                                } else if (!isEditing) {
                                  selectedUsernames = [];
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? col.withOpacity(0.15) : Colors.white12,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isSelected ? col : Colors.white24, width: 2),
                              ),
                              child: Row(
                                children: [
                                  Container(width: 10, height: 10, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                                  const SizedBox(width: 6),
                                  Text(c, style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Miembros Seleccionados (${selectedUsernames.length}):',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  if (selectedUsernames.isEmpty)
                    Text(
                      'Ningún miembro seleccionado aún.',
                      style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor, fontSize: 12),
                    )
                  else
                    Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      width: double.infinity,
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: selectedUsersList.map((u) {
                            final name = '${u['nombre']} ${u['apellido']}';
                            final username = u['usuario'] ?? '';
                            return InputChip(
                              label: Text(name, style: const TextStyle(fontSize: 11)),
                              onDeleted: () {
                                setDialogState(() {
                                  selectedUsernames.remove(username);
                                });
                              },
                              deleteIcon: const Icon(Icons.cancel, size: 14),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text('Buscar y Añadir Miembros:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar empleado...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (v) => setDialogState(() => searchQuery = v.toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.15)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: availableUsersList.isEmpty
                        ? Center(
                            child: Text(
                              'No se encontraron más empleados.',
                              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
                            ),
                          )
                        : ListView.builder(
                            itemCount: availableUsersList.length,
                            itemBuilder: (ctx, i) {
                              final u = availableUsersList[i];
                              final name = '${u['nombre']} ${u['apellido']}';
                              final username = u['usuario'] ?? '';
                              return ListTile(
                                title: Text(name, style: const TextStyle(fontSize: 13)),
                                subtitle: Text(username, style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
                                dense: true,
                                trailing: const Icon(Icons.add_circle_outline_rounded, size: 18, color: Colors.green),
                                onTap: () {
                                  setDialogState(() {
                                    selectedUsernames.add(username);
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: saving ? null : () async {
                  setDialogState(() => saving = true);
                  final success = effectiveEditing 
                    ? await xiaomi.updateTeam(targetTeamId!, selectedColor!, selectedUsernames)
                    : await xiaomi.createTeam(selectedColor!, selectedUsernames);
                  if (success && ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _getColorFromName(String name) {
    switch (name.toLowerCase()) {
      case 'rojo': return Colors.red;
      case 'azul': return Colors.blue;
      case 'verde': return Colors.green;
      case 'amarillo': return Colors.yellow;
      case 'naranja': return Colors.orange;
      case 'morado': return Colors.purple;
      case 'rosa': return Colors.pink;
      case 'marrón': return Colors.brown;
      case 'gris': return Colors.grey;
      case 'negro': return Colors.black;
      default: return Colors.blueGrey;
    }
  }

  /// Direct transfer of the paused [_nextCesb] to the currently selected team.
  Future<void> _transferPausedToThisTeam(BuildContext context) async {
    if (_nextCesb == null || _selectedTeam == null) return;

    final totalQty = int.tryParse(_nextCesb!['qty']?.toString() ?? '0') ?? 0;
    int completedByOld = 0;
    final ctrl = TextEditingController(text: '0');

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.swap_horiz_rounded, color: Colors.deepPurple),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Transferir a ${_selectedTeam!.nombre}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade700.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.pause_circle_rounded, color: Colors.amber.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_nextCesb!['cesb']}  •  ${_nextCesb!['sku']}  •  $totalQty uds',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '¿Cuántas unidades completó el equipo anterior?',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: completedByOld > 0
                        ? () => setS(() {
                              completedByOld = (completedByOld - 1).clamp(0, totalQty);
                              ctrl.text = completedByOld.toString();
                            })
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    color: Colors.deepPurple,
                  ),
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        suffixText: '/ $totalQty',
                      ),
                      onChanged: (v) => setS(() {
                        completedByOld = (int.tryParse(v) ?? 0).clamp(0, totalQty);
                      }),
                    ),
                  ),
                  IconButton(
                    onPressed: completedByOld < totalQty
                        ? () => setS(() {
                              completedByOld = (completedByOld + 1).clamp(0, totalQty);
                              ctrl.text = completedByOld.toString();
                            })
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                    color: Colors.deepPurple,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${totalQty - completedByOld} unidades quedan para ${_selectedTeam!.nombre}.',
                style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text('Transferir a ${_selectedTeam!.nombre}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      }),
    );
    ctrl.dispose();

    if (confirmed != true) return;

    setState(() => _submitting = true);
    try {
      final xiaomi = context.read<XiaomiProvider>();
      final result = await xiaomi.transferCesb(
        _nextCesb!['cesb'],
        completedByOld,
        _selectedTeam!.id,
      );
      if (!mounted) return;
      if (result != null && result['status'] == 'transferred') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'CESB transferido a ${_selectedTeam!.nombre}.\nNuevo CESB: ${result['new_cesb'] ?? ''}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
        await _refreshData();
      } else {
        final msg = result?['error'] ?? 'Error al transferir.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showTransferDialog(BuildContext context) async {
    if (_activeCesb == null) return;
    final xiaomi = context.read<XiaomiProvider>();
    final teams = xiaomi.todayTeams;
    final currentTeamId = _selectedTeam?.id;
    final otherTeams = teams.where((t) => t.id != currentTeamId).toList();

    if (otherTeams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay otros equipos disponibles para transferir.')),
      );
      return;
    }

    final totalQty = int.tryParse(_activeCesb!['qty']?.toString() ?? '0') ?? 0;
    int completedQty = 0;
    XiaomiTeam? selectedNewTeam;
    final completedCtrl = TextEditingController(text: '0');

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setS) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.swap_horiz_rounded, color: Colors.deepPurple),
                ),
                const SizedBox(width: 12),
                const Text('Transferir tarea', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CESB: ${_activeCesb!["cesb"]}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('SKU: ${_activeCesb!["sku"]}  •  Total: $totalQty uds', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Unidades completadas por el equipo actual:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        onPressed: completedQty > 0 ? () {
                          setS(() {
                            completedQty = (completedQty - 1).clamp(0, totalQty);
                            completedCtrl.text = completedQty.toString();
                          });
                        } : null,
                        icon: const Icon(Icons.remove_circle_outline),
                        color: Colors.deepPurple,
                      ),
                      Expanded(
                        child: TextField(
                          controller: completedCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            suffixText: '/ $totalQty',
                          ),
                          onChanged: (v) {
                            setS(() {
                              completedQty = (int.tryParse(v) ?? 0).clamp(0, totalQty);
                            });
                          },
                        ),
                      ),
                      IconButton(
                        onPressed: completedQty < totalQty ? () {
                          setS(() {
                            completedQty = (completedQty + 1).clamp(0, totalQty);
                            completedCtrl.text = completedQty.toString();
                          });
                        } : null,
                        icon: const Icon(Icons.add_circle_outline),
                        color: Colors.deepPurple,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quedan ${totalQty - completedQty} unidades para el nuevo equipo.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 20),
                  const Text('Equipo receptor:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<XiaomiTeam>(
                    value: selectedNewTeam,
                    hint: const Text('Seleccionar equipo'),
                    isExpanded: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: otherTeams.map((t) {
                      return DropdownMenuItem<XiaomiTeam>(
                        value: t,
                        child: Text(t.nombre, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (t) => setS(() => selectedNewTeam = t),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                onPressed: selectedNewTeam == null ? null : () => Navigator.of(ctx).pop(true),
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Transferir'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        });
      },
    );
    completedCtrl.dispose();

    if (confirmed != true || selectedNewTeam == null) return;

    setState(() => _submitting = true);
    try {
      final result = await xiaomi.transferCesb(
        _activeCesb!['cesb'],
        completedQty,
        selectedNewTeam!.id,
      );
      if (!mounted) return;
      if (result != null && result['status'] == 'transferred') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tarea transferida a ${selectedNewTeam!.nombre}. \nNuevo CESB: ${result['new_cesb'] ?? ''}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
        await _refreshData();
      } else {
        final msg = result?['error'] ?? 'Error al transferir la tarea.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _TeamActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _TeamActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: color),
      label: Text(
        label,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(color: color.withOpacity(0.5), width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value, 
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
