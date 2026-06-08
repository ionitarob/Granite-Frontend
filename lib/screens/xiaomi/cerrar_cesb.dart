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
    
    // Initialize teams and pending
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<XiaomiProvider>().initTeams();
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

    // 1. Check if this team has an active CESB (started but not finished)
    // Match by team_name if available, otherwise fallback to team_id comparison
    final active = _pendingList.cast<Map<String, dynamic>?>().firstWhere(
      (item) {
        if (item == null) return false;
        final itemTeamName = item['team_name']?.toString().toLowerCase();
        final selectedTeamName = _selectedTeam!.nombre.toLowerCase();
        if (itemTeamName != null && itemTeamName.isNotEmpty) {
          return itemTeamName == selectedTeamName && item['fecha_hora_inicio'] != null;
        }
        return item['team_id'] == _selectedTeam!.id && item['fecha_hora_inicio'] != null;
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
      
      // 2. Find the NEXT CESB based on priority (oldest date) and validation
      // Check if there is a manual selection that is still pending (fecha_hora_inicio == null)
      Map<String, dynamic>? next;
      if (_manuallySelectedNextCesbId != null) {
        next = _pendingList.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['cesb'] == _manuallySelectedNextCesbId && item?['fecha_hora_inicio'] == null,
          orElse: () => null,
        );
      }
      
      // Fallback to priority if no manual selection or if it's no longer valid
      next ??= _pendingList.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['fecha_hora_inicio'] == null,
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
                        _buildTeamSelector(xiaomi, theme),
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

  Widget _buildTeamSelector(XiaomiProvider xiaomi, ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Seleccionar tu equipo:', style: TextStyle(fontWeight: FontWeight.bold)),
                if (_isSupervisor)
                  IconButton(
                    icon: const Icon(Icons.group_add_rounded, color: Colors.blue, size: 20),
                    onPressed: () => _showTeamDialog(),
                    tooltip: 'Añadir nuevo equipo',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: xiaomi.todayTeams.map((t) {
                  final isSelected = _selectedTeam?.id == t.id;
                  final color = _getColorFromName(t.nombre);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onLongPress: _isSupervisor ? () => _showTeamDialog(team: t) : null,
                      child: Tooltip(
                        message: _isSupervisor ? 'Mantén pulsado para editar equipo' : t.nombre,
                        child: ChoiceChip(
                          label: Text(t.nombre, style: TextStyle(color: isSelected ? Colors.white : color, fontSize: 13)),
                          selected: isSelected,
                          selectedColor: color,
                          onSelected: (val) {
                            setState(() {
                              _selectedTeam = val ? t : null;
                              _evaluateState();
                            });
                          },
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
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
    final allPending = _pendingList
        .where((item) => item?['fecha_hora_inicio'] == null)
        .toList();

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
                      value: _nextCesb?['cesb'],
                      dropdownColor: theme.cardColor,
                      items: allPending.map((item) {
                        final cesbName = item['cesb'] ?? 'Sin nombre';
                        final skuName = item['sku'] ?? '';
                        final isVal = item['fecha_hora_validado'] != null;
                        return DropdownMenuItem<String>(
                          value: cesbName,
                          child: Text(
                            '$cesbName - $skuName (${isVal ? "VALIDADO" : "PENDIENTE"})',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isVal ? FontWeight.bold : FontWeight.normal,
                              color: isVal ? Colors.green : Colors.red,
                            ),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: (isValidated ? Colors.green : Colors.red).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isValidated ? Icons.check_circle_rounded : Icons.warning_amber_rounded, 
                         size: 16, color: isValidated ? Colors.green : Colors.red),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isValidated ? 'CESB VALIDADO Y RECIBIDO' : 'DEBE VALIDARSE PRIMERO (PENDIENTE)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isValidated ? Colors.green : Colors.red),
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
            onPressed: (_submitting || !isValidated) ? null : _onEmpezar,
            icon: const Icon(Icons.play_arrow_rounded, size: 28),
            label: const Text('EMPEZAR TRABAJO', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

          return AlertDialog(
            scrollable: true,
            title: Text(effectiveEditing ? 'Editar Equipo' : 'Crear Equipo'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Color del Equipo:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: colors.map((c) {
                        final isSelected = selectedColor == c;
                        final col = _getColorFromName(c);
                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
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
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? col.withOpacity(0.15) : Colors.white10,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isSelected ? col : Colors.white24, width: 2),
                              ),
                              child: Row(
                                children: [
                                  Container(width: 12, height: 12, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                                  const SizedBox(width: 8),
                                  Text(c),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Seleccionar Miembros:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (v) => setDialogState(() => searchQuery = v.toLowerCase()),
                  ),
                  const SizedBox(height: 12),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: allUsers.length,
                      itemBuilder: (ctx, i) {
                        final u = allUsers[i];
                        final name = '${u['nombre']} ${u['apellido']}';
                        if (searchQuery.isNotEmpty && !name.toLowerCase().contains(searchQuery)) return const SizedBox.shrink();
                        final username = u['usuario'] ?? '';
                        final isSelected = selectedUsernames.contains(username);
                        return CheckboxListTile(
                          title: Text(name),
                          value: isSelected,
                          onChanged: (v) {
                            setDialogState(() {
                              if (v == true) selectedUsernames.add(username);
                              else selectedUsernames.remove(username);
                            });
                          },
                        );
                      },
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
