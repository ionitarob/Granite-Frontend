import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../widgets/animated_background.dart';
import '../../themes/amazon_theme.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

class AmazonBatchRegistration extends StatefulWidget {
  final dynamic batch;
  const AmazonBatchRegistration({required this.batch, super.key});

  @override
  State<AmazonBatchRegistration> createState() =>
      _AmazonBatchRegistrationState();
}

class _AmazonBatchRegistrationState extends State<AmazonBatchRegistration> {
  final _dsnCtrl = TextEditingController();
  final _macCtrl = TextEditingController();
  final _dsnFocus = FocusNode();

  bool _submitting = false;
  Map<String, dynamic>? _metrics;
  List<dynamic> _qcTemplates = [];
  WebSocketChannel? _metricsChannel;
  bool _connectingWS = false;
  int? _lastAlertedShuttleStart;
  bool _hasAlertedCurrentShuttle = false;
  bool _shuttleSubmitting = false;

  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _fetchMetrics();
    _fetchQCTemplates();
    _connectMetricsSocket();
    
    // Catch Tab or Enter from scanner to submit automatically
    _dsnFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent && 
          (event.logicalKey == LogicalKeyboardKey.tab || 
           event.logicalKey == LogicalKeyboardKey.enter)) {
        if (!_submitting) _processRegistration();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dsnFocus.requestFocus();
    });
  }

  void _connectMetricsSocket() {
    if (_connectingWS) return;
    _connectingWS = true;
    
    try {
      final api = ApiService.instance;
      if (api == null) return;
      
      final baseUrl = api.client.baseUrl.replaceAll('http://', 'ws://').replaceAll('https://', 'wss://');
      final wsUrl = '$baseUrl/ws/amz/batches/${widget.batch['id']}/metrics/';
      
      final token = api.client.accessToken;
      final Map<String, String> headers = {};
      if (token != null) headers['Authorization'] = 'Bearer $token';

      _metricsChannel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: headers,
        pingInterval: const Duration(seconds: 20),
      );

      _metricsChannel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data['type'] == 'batch_metrics_update' && mounted) {
              setState(() {
                _metrics = data['metrics'];
                _checkShuttleMilestone();
              });
            }
          } catch (e) {
            debugPrint('Error parsing metrics WS message: $e');
          }
        },
        onError: (e) {
          debugPrint('Metrics WS Error: $e');
          _reconnectWS();
        },
        onDone: () {
          debugPrint('Metrics WS Closed');
          _reconnectWS();
        },
      );
    } catch (e) {
       _reconnectWS();
    } finally {
      _connectingWS = false;
    }
  }

  void _reconnectWS() {
    if (!mounted) return;
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) _connectMetricsSocket();
    });
  }

  Future<void> _fetchMetrics() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.get(
        '/amz/batches/${widget.batch['id']}/metrics',
      );
      if (res.ok && mounted) {
        setState(() {
          _metrics = res.body;
          _checkShuttleMilestone();
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchQCTemplates() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.get(
        '/amz/proyectos/${widget.batch['project_id']}/qc-templates',
      );
      if (res.ok && mounted)
        setState(() => _qcTemplates = res.body['results'] ?? []);
    } catch (_) {}
  }

  Future<void> _toggleShuttle(String action) async {
    if (_shuttleSubmitting) return;

    int resumeCount = 0;
    if (action == 'start') {
      final TextEditingController ctrl = TextEditingController(text: '0');
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AmazonTheme(
          child: AlertDialog(
            backgroundColor: const Color(0xFF0A0A1A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.blueAccent, width: 1),
            ),
            title: const Text('INICIAR O REANUDAR SHUTTLE', 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ingresa las unidades que ya están en el shuttle (0 si es nuevo):', 
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 20),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w900, fontSize: 32),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    suffixText: 'UN',
                    suffixStyle: const TextStyle(color: Colors.white24, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white24)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('ACEPTAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
      if (confirm != true) return;
      resumeCount = int.tryParse(ctrl.text) ?? 0;
    }

    setState(() => _shuttleSubmitting = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post(
        '/amz/batches/${widget.batch['id']}/shuttle',
        jsonBody: {'action': action, 'resume_count': resumeCount},
      );
      if (res.ok) {
        // Broadcast will update metrics via WS, but let's fetch for safety
        await _fetchMetrics();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${res.body['error']}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de conexión')),
      );
    } finally {
      if (mounted) setState(() => _shuttleSubmitting = false);
    }
  }

  Future<void> _processRegistration({bool reprintOnly = false}) async {
    final dsn = _dsnCtrl.text.trim().toUpperCase();
    if (dsn.isEmpty || _submitting) return;

    setState(() {
      _submitting = true;
      if (!reprintOnly) _macCtrl.clear();
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.post(
        '/amz/batches/${widget.batch['id']}/register',
        jsonBody: {
          'dsn': dsn,
          'reprint_only': reprintOnly,
        },
      );

        if (res.ok) {
          final mac = res.body['mac'];
          setState(() => _macCtrl.text = mac ?? 'N/A');

          if (reprintOnly) {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(
                 content: Text('Etiqueta para $dsn reimpresa'),
                 backgroundColor: Colors.blue.shade800,
                 duration: const Duration(seconds: 2),
               ),
             );
             return;
          }

          // Determine if QC is needed for this unit (SMART LOGIC)
          final qcPct = (widget.batch['qc_percentage'] ?? 0).toDouble();
          final regCount = (_metrics?['registered_units'] as num? ?? 0).toDouble();
          final doneQC = (_metrics?['qc_units_done'] as num? ?? 0).toDouble();
          
          // Weighted probability: if we are behind the average required rate, increase chance.
          final expectedQCSoFar = (regCount + 1) * (qcPct / 100);
          double smartProb = qcPct;
          if (doneQC < expectedQCSoFar) {
            // We are behind! Increase probability to "catch up"
            // Multiplier reduced from 50 to 10 to avoid forcing QC on every unit immediately
            smartProb += (expectedQCSoFar - doneQC) * 10; 
          } else if (doneQC > expectedQCSoFar + 1) {
             // We are ahead, relax the requirement slightly
             smartProb = smartProb * 0.8; // Relaxed (was 0.5)
          }

          final rollout = _random.nextInt(100);

          if (rollout < smartProb && _qcTemplates.isNotEmpty) {
            _showQCForm(dsn);
          } else {
            _finishRegistrationAndReset(dsn);
          }
        } else {
          final error = res.body['error'] ?? 'Error en el registro';
          final details = res.body['details'];
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(error, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (details != null) Text(details.toString(), style: const TextStyle(fontSize: 12)),
                ],
              ),
              backgroundColor: res.statusCode == 409 ? Colors.orange.shade900 : Colors.red.shade900,
              duration: const Duration(seconds: 6),
              action: res.statusCode == 409 
                ? SnackBarAction(
                    label: 'SOLO REIMPRIMIR', 
                    textColor: Colors.white,
                    onPressed: () => _processRegistration(reprintOnly: true),
                  )
                : null,
            ),
          );
          
          if (res.statusCode != 409) {
            _dsnCtrl.clear();
            _dsnFocus.requestFocus();
          }
        }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error de conexión con el servidor'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showReprintDialog() async {
    final ctrl = TextEditingController();
    final dsn = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reimprimir Etiqueta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Introduce el DSN de la unidad que deseas reimprimir:'),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'ESCANEAR DSN',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code_2_rounded),
              ),
              autofocus: true,
              onSubmitted: (val) => Navigator.pop(ctx, val.trim().toUpperCase()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().toUpperCase()),
            child: const Text('REIMPRIMIR'),
          ),
        ],
      ),
    );

    if (dsn != null && dsn.isNotEmpty) {
      _dsnCtrl.text = dsn;
      _processRegistration(reprintOnly: true);
    }
  }

  void _showQCForm(String dsn) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _QCFormDialog(
        dsn: dsn,
        templates: _qcTemplates,
        batchId: widget.batch['id'],
        onSuccess: () {
          _finishRegistrationAndReset(dsn);
        },
      ),
    );
  }

  void _finishRegistrationAndReset(String dsn) {
    if (mounted) {
      _dsnCtrl.clear();
      // Keep MAC visible for a moment? Or clear it?
      // I'll clear it when starting new scan.
      _fetchMetrics();
      _dsnFocus.requestFocus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unidad $dsn registrada y etiqueta impresa'),
          backgroundColor: Colors.green.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final daily = (_metrics?['daily_production'] as num? ?? 0);
    final userRole = (ApiService.instance?.currentUser?.role ?? '').toLowerCase();
    final isElevated = !userRole.contains('operario') || userRole.contains('chief') || userRole.contains('admin');

    if (daily == 0 && _metrics != null && !isElevated) {
       return Scaffold(
         body: Center(
           child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               const Icon(Icons.lock_clock_rounded, size: 80, color: Colors.orange),
               const SizedBox(height: 24),
               const Text(
                 'Lote No Iniciado',
                 style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
               ),
               const SizedBox(height: 12),
               const Padding(
                 padding: EdgeInsets.symmetric(horizontal: 40),
                 child: Text(
                   'Este lote no puede procesarse hasta que un responsable establezca el objetivo de producción diaria.',
                   textAlign: TextAlign.center,
                   style: TextStyle(color: Colors.white60),
                 ),
               ),
               const SizedBox(height: 32),
               ElevatedButton(
                 onPressed: () => Navigator.pop(context),
                 child: const Text('VOLVER AL DASHBOARD'),
               ),
             ],
           ),
         ),
       );
    }

    return AmazonTheme(
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(
              child: AnimatedBackgroundWidget(intensity: 0.3),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: _buildRegistrationCard()),
                          const SizedBox(width: 24),
                          Expanded(flex: 2, child: _buildMetricsSidebar()),
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

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.batch['name'],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'SISTEMA DE REGISTRO & PRINT-ON-SCAN',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange.shade300,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistrationCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(48.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.print_rounded, size: 100, color: Colors.orange),
            const SizedBox(height: 48),
            TextFormField(
              controller: _dsnCtrl,
              focusNode: _dsnFocus,
              textInputAction: TextInputAction.send,
              onFieldSubmitted: (_) => _processRegistration(),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: 'ESCANEAR DSN',
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                ),
                floatingLabelAlignment: FloatingLabelAlignment.center,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                prefixIcon: const Icon(
                  Icons.qr_code_2_rounded,
                  color: Colors.orange,
                ),
                suffixIcon: _submitting
                    ? const CupertinoActivityIndicator()
                    : null,
                filled: true,
                fillColor: Colors.black12,
              ),
              style: const TextStyle(
                fontSize: 28,
                letterSpacing: 3,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _macCtrl,
              readOnly: true,
              focusNode: FocusNode(canRequestFocus: false),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: 'DIRECCIÓN MAC (AUTOFILL)',
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                ),
                floatingLabelAlignment: FloatingLabelAlignment.center,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                prefixIcon: const Icon(
                  Icons.lan_rounded,
                  color: Colors.white38,
                ),
                filled: true,
                fillColor: Colors.white10,
              ),
              style: const TextStyle(
                fontSize: 22,
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 64),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 72,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _processRegistration,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                        foregroundColor: Colors.white,
                        elevation: 8,
                        shadowColor: Colors.orange.withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: _submitting
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : const Text(
                              'REGISTRAR & IMPRIMIR',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: SizedBox(
                    height: 72,
                    child: OutlinedButton(
                    onPressed: _submitting ? null : _showReprintDialog,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.orange.withOpacity(0.5), width: 2),
                        foregroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.print_rounded, size: 24),
                          Text(
                            'REIMPRIMIR',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

   Widget _buildMetricsSidebar() {
    if (_metrics == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalUnits = (_metrics!['total_units'] as num? ?? 0).toDouble();
    final qcUnitsDone = (_metrics!['qc_units_done'] as num? ?? 0).toDouble();
    final qcUnitsDoneToday = (_metrics!['qc_units_done_today'] as num? ?? 0).toDouble();
    final qcReq = (_metrics!['qc_percentage_required'] as num? ?? 0).toDouble();
    
    // QC Calculations
    final qcReqUnitsTotal = (totalUnits * (qcReq / 100)).ceil();
    final totalQCProgress = (qcReqUnitsTotal > 0) ? (qcUnitsDone / qcReqUnitsTotal) : 0.0;
    
    final prodGoal = (_metrics!['daily_production'] as num? ?? 0).toDouble();
    final dailyQCTarget = (prodGoal * (qcReq / 100)).ceil();
    final dailyQCProgress = (dailyQCTarget > 0) ? (qcUnitsDoneToday / dailyQCTarget) : 0.0;

    // Production Calculations
    final prodDoneTotal = (_metrics!['registered_units'] as num? ?? 0).toDouble();
    final prodDoneToday = (_metrics!['registered_units_today'] as num? ?? 0).toDouble();
    final totalProdProgress = (totalUnits > 0) ? (prodDoneTotal / totalUnits) : 0.0;
    final dailyProdProgress = (prodGoal > 0) ? (prodDoneToday / prodGoal) : 0.0;


    return SingleChildScrollView(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricIndicator(
                  title: 'PRODUCCIÓN',
                  totalValue: totalProdProgress.clamp(0.0, 1.0),
                  dailyValue: dailyProdProgress.clamp(0.0, 1.0),
                  totalLabel: '${(totalProdProgress * 100).toStringAsFixed(1)}% Total',
                  dailyLabel: '${(dailyProdProgress * 100).toStringAsFixed(1)}% Hoy',
                  targetLabel: 'Hoy: ${prodDoneToday.toInt()} / ${prodGoal.toInt()} UN\nTotal: ${prodDoneTotal.toInt()} / ${totalUnits.toInt()}',
                  color: dailyProdProgress >= 1.0 
                      ? const Color(0xFF64B5F6) // Softer Premium Blue
                      : const Color(0xFFFFB74D), // Softer Premium Orange
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _MetricIndicator(
                  title: 'CALIDAD (QC)',
                  totalValue: totalQCProgress.clamp(0.0, 1.0),
                  dailyValue: dailyQCProgress.clamp(0.0, 1.0),
                  totalLabel: '${(totalQCProgress * 100).toStringAsFixed(1)}% Total',
                  dailyLabel: '${(dailyQCProgress * 100).toStringAsFixed(1)}% Hoy',
                  targetLabel: 'Hoy: ${qcUnitsDoneToday.toInt()}/${dailyQCTarget}\nTotal: ${qcUnitsDone.toInt()}/${qcReqUnitsTotal}',
                  color: dailyQCProgress >= 1.0
                      ? const Color(0xFF81C784) // Softer Premium Green
                      : const Color(0xFFFFB74D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ESTADÍSTICAS EN VIVO',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 1,
                    color: Colors.white38,
                  ),
                ),
                const Divider(height: 32, thickness: 1, color: Colors.white10),
                _buildMetricRow('Total Lote', '${_metrics!['total_units']} UN'),
                const SizedBox(height: 12),
                _buildMetricRow(
                  'Registros',
                  '${_metrics!['registered_units']} UN',
                ),
                const SizedBox(height: 12),
                _buildMetricRow(
                  'QC Realizados',
                  '${_metrics!['qc_units_done']} UN',
                ),
                const SizedBox(height: 12),
                _buildMetricRow(
                  'Estado Lote',
                  'EN PROCESO',
                  color: Colors.greenAccent,
                ),
                const Divider(height: 32, thickness: 1, color: Colors.white10),
                
                // SHUTTLE SECTION
                Row(
                  children: [
                    Icon(
                      Icons.local_shipping_rounded, 
                      size: 16, 
                      color: _metrics!['is_shuttle_active'] == true ? Colors.blueAccent : Colors.white24
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'SHUTTLE ACTUAL',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1,
                        color: _metrics!['is_shuttle_active'] == true ? Colors.white : Colors.white24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_metrics!['is_shuttle_active'] == true) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (_metrics!['shuttle_units'] as num? ?? 0) / 480,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation(Colors.blueAccent),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'PROGRESO',
                        style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_metrics!['shuttle_units']} / 480',
                        style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  if (_metrics!['shuttle_user'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Iniciado por: ${_metrics!['shuttle_user']}',
                      style: const TextStyle(color: Colors.white24, fontSize: 10, fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _shuttleSubmitting ? null : () => _toggleShuttle('close'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withOpacity(0.1),
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _shuttleSubmitting 
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                        : const Text('CERRAR SHUTTLE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ] else ...[
                  const Text(
                    'No hay un shuttle activo para este lote.',
                    style: TextStyle(color: Colors.white24, fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _shuttleSubmitting ? null : () => _toggleShuttle('start'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent.withOpacity(0.1),
                        side: const BorderSide(color: Colors.blueAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _shuttleSubmitting 
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent))
                        : const Text('INICIAR O REANUDAR SHUTTLE', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildMetricRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: color,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  void _checkShuttleMilestone() {
    if (_metrics == null) return;
    
    final bool active = _metrics!['is_shuttle_active'] ?? false;
    final int units = (_metrics!['shuttle_units'] as num? ?? 0).toInt();
    final int startTotal = (_metrics!['shuttle_start_total'] as num? ?? 0).toInt();

    if (!active) {
      _hasAlertedCurrentShuttle = false;
      return;
    }

    // If the shuttle start total changed (meaning a new shuttle was started)
    if (startTotal != _lastAlertedShuttleStart) {
      _lastAlertedShuttleStart = startTotal;
      _hasAlertedCurrentShuttle = false;
    }

    if (units >= 480 && !_hasAlertedCurrentShuttle) {
      _hasAlertedCurrentShuttle = true;
      _showShuttleMilestoneAlert(units, startTotal);
    }
  }

  void _showShuttleMilestoneAlert(int units, int count) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AmazonTheme(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AlertDialog(
            backgroundColor: const Color(0xFF0A0A1A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: const BorderSide(color: Colors.blueAccent, width: 2),
            ),
            title: const Column(
              children: [
                Icon(Icons.local_shipping_rounded, color: Colors.blueAccent, size: 64),
                SizedBox(height: 16),
                Text(
                  '¡SHUTTLE COMPLETADO!',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('IGNORAR', style: TextStyle(color: Colors.white38)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _toggleShuttle('close');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'CERRAR Y CONTINUAR',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricIndicator extends StatelessWidget {
  final String title;
  final double totalValue;
  final double dailyValue;
  final String totalLabel;
  final String dailyLabel;
  final String targetLabel;
  final Color color;

  const _MetricIndicator({
    required this.title,
    required this.totalValue,
    required this.dailyValue,
    required this.totalLabel,
    required this.dailyLabel,
    required this.targetLabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 24),
          Stack(
            alignment: Alignment.center,
            children: [
              // Outer Ring (Total)
              SizedBox(
                width: 140,
                height: 140,
                child: CircularProgressIndicator(
                  value: totalValue,
                  strokeWidth: 9,
                  backgroundColor: Colors.white.withOpacity(0.03),
                  color: color.withOpacity(0.25),
                  strokeCap: StrokeCap.round,
                ),
              ),
              // Inner Ring (Daily)
              SizedBox(
                width: 106,
                height: 106,
                child: CircularProgressIndicator(
                  value: dailyValue,
                  strokeWidth: 11,
                  backgroundColor: Colors.white.withOpacity(0.03),
                  color: color,
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dailyLabel,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    totalLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.white.withOpacity(0.3),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              targetLabel,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QCFormDialog extends StatefulWidget {
  final String dsn;
  final List<dynamic> templates;
  final int batchId;
  final VoidCallback onSuccess;

  const _QCFormDialog({
    required this.dsn,
    required this.templates,
    required this.batchId,
    required this.onSuccess,
  });

  @override
  State<_QCFormDialog> createState() => _QCFormDialogState();
}

class _QCFormDialogState extends State<_QCFormDialog> {
  final Map<int, String> _responses = {};
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: AlertDialog(
        backgroundColor: const Color(0xFF07070F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.orange.withOpacity(0.3)),
        ),
        title: Column(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              'CONTROL DE CALIDAD',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
            Text(
              'DSN: ${widget.dsn}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white38,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Text(
                    'Esta unidad ha sido seleccionada aleatoriamente para un control de calidad obligatorio.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ),
                const Divider(height: 32, color: Colors.white10),
                ...widget.templates
                    .map(
                      (t) => Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t['question_text_es'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            if (t['question_text_en'] != null)
                              Text(
                                t['question_text_en'],
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white38,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            const SizedBox(height: 12),
                            Row(
                              children: ['SI', 'NO'].map((opt) {
                                final isSelected = _responses[t['id']] == opt;
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4.0,
                                    ),
                                    child: InkWell(
                                      onTap: () => setState(
                                        () => _responses[t['id']] = opt,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? (opt == 'SI' ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2))
                                              : Colors.white.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? (opt == 'SI' ? Colors.greenAccent : Colors.redAccent)
                                                : Colors.white10,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            opt,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: isSelected
                                                  ? (opt == 'SI' ? Colors.greenAccent : Colors.redAccent)
                                                  : Colors.white70,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ],
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _submitting
                    ? const CupertinoActivityIndicator(color: Colors.black)
                    : const Text(
                        'FINALIZAR QC & REGISTRAR',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_responses.length < widget.templates.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor responda todas las preguntas')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      
      // Bulk submission format
      final responsesList = _responses.entries.map((e) => {
        'question_id': e.key,
        'response_text': e.value,
      }).toList();

      final res = await api.client.post(
        '/amz/batches/${widget.batchId}/qc-responses',
        jsonBody: {
          'dsn': widget.dsn,
          'responses': responsesList,
        },
      );

      if (res.ok) {
        widget.onSuccess();
        Navigator.pop(context);
      } else {
        final error = res.body['error'] ?? 'Error desconocido';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error guardando QC: $error'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error de conexión: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
