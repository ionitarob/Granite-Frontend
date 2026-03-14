import 'dart:io';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as ms;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/server_models.dart';
import '../../services/api_service.dart';
import '../../services/order_input_formatter.dart';
import '../../services/orderops_service.dart';
import '../../services/server_registro_service.dart';
import '../../widgets/main_sidebar.dart';

class RegistroServidorScreen extends StatefulWidget {
  final bool isEmbedded;
  final String? initialPrevi;
  final String? initialCliente;
  final int? orderId;

  const RegistroServidorScreen({
    super.key,
    this.isEmbedded = false,
    this.initialPrevi,
    this.initialCliente,
    this.orderId,
  });

  @override
  State<RegistroServidorScreen> createState() => _RegistroServidorScreenState();
}

class _RegistroServidorScreenState extends State<RegistroServidorScreen> {
  final List<ServerRegistro> _servidores = [];
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _serverSerialCtrl = TextEditingController();
  final TextEditingController _previCtrl = TextEditingController();
  final TextEditingController _clienteCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _operarioCtrl = TextEditingController();
  // Focus nodes for auto navigation
  final FocusNode _serverSerialFocus = FocusNode();
  final FocusNode _pnFocus = FocusNode();
  final FocusNode _snFocus = FocusNode();
  final ServerRegistroService _registroService = const ServerRegistroService();
  final OrderOpsService? _orderOpsService = ApiService.instance == null
      ? null
      : OrderOpsService(ApiService.instance!.client);
  bool _uploading = false;
  final String? _currentUserOperario = _resolveCurrentUser();

  // Campos de pieza actual
  final TextEditingController _pnCtrl = TextEditingController();
  final TextEditingController _snCtrl = TextEditingController();
  int _serverIndexActivo = -1; // índice del servidor seleccionado

  bool get _metadataCompleta =>
      _previCtrl.text.trim().isNotEmpty &&
      _clienteCtrl.text.trim().isNotEmpty &&
      _descCtrl.text.trim().isNotEmpty &&
      _operarioCtrl.text.trim().isNotEmpty;

  bool get _puedeSubir =>
      _metadataCompleta &&
      _servidores.any(
        (s) => s.serverSerial.trim().isNotEmpty && s.piezas.isNotEmpty,
      );
  bool get _hasCurrentUserOperario =>
      (_currentUserOperario?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _operarioCtrl.text = _currentUserOperario ?? '';
    if ((widget.initialPrevi ?? '').trim().isNotEmpty) {
      _previCtrl.text = OrderInputFormatter.normalize(widget.initialPrevi!.trim());
    }
    if ((widget.initialCliente ?? '').trim().isNotEmpty) {
      _clienteCtrl.text = widget.initialCliente!.trim();
    }
  }

  Future<void> _registrarLogAccion(String message) async {
    if (widget.orderId == null || _orderOpsService == null) return;
    try {
      await _orderOpsService.updateAgentOrder(widget.orderId!, reason: message);
    } catch (_) {
      // Non-blocking logging.
    }
  }

  Future<bool> _subirPdfAArchivos(File file) async {
    if (widget.orderId == null || _orderOpsService == null) return false;
    final bytes = await file.readAsBytes();
    return await _orderOpsService.uploadPhoto(
      widget.orderId!,
      file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : 'registro_servidor.pdf',
      bytes,
    );
  }

  Future<void> _preguntarFinalizarOrden() async {
    if (widget.orderId == null || _orderOpsService == null) return;
    final shouldFinish = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar orden'),
        content: const Text('Deseas finalizar la orden ahora?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Si, finalizar'),
          ),
        ],
      ),
    );

    if (shouldFinish != true) {
      await _registrarLogAccion('Orden no finalizada despues de exportar PDF.');
      return;
    }

    final author = _operarioCtrl.text.trim().isNotEmpty
        ? _operarioCtrl.text.trim()
        : (_currentUserOperario ?? 'Sistema');
    final ok = await _orderOpsService.updateAgentOrder(
      widget.orderId!,
      estado: '5',
      reason: 'Orden finalizada desde Registro Servidor.',
      markCompleted: true,
      completionSummary: 'Se exporto PDF, se adjunto en Archivos y se finalizo la orden.',
      completionAuthor: author,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Orden finalizada correctamente.'
              : 'No se pudo finalizar la orden.',
        ),
      ),
    );
  }

  static String? _resolveCurrentUser() {
    final user = ApiService.instance?.currentUser;
    if (user == null) return null;
    final username = user.username.trim();
    if (username.isNotEmpty) return username;
    final display = user.displayName().trim();
    return display.isNotEmpty ? display : null;
  }

  Future<String?> _scanOneBarcode({String title = 'Escanear'}) async {
    // Evita llamar al plugin en plataformas no soportadas (ej: Windows / macOS / Linux desktop)
    // mobile_scanner ofrece implementaciones para Android / iOS y web.
    final bool supported = Platform.isAndroid || Platform.isIOS || kIsWeb;
    if (!supported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escaneo no soportado en esta plataforma.'),
        ),
      );
      return null;
    }
    return await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        String? scanned;
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 320,
            height: 420,
            child: Stack(
              children: [
                ms.MobileScanner(
                  onDetect: (ms.BarcodeCapture capture) {
                    if (scanned != null) return; // prevent multiple
                    final barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      scanned = barcodes.first.rawValue?.trim();
                      if (scanned != null && scanned!.isNotEmpty) {
                        Navigator.of(context).pop(scanned);
                      }
                    }
                  },
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      title,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _scanServerSerial() async {
    final res = await _scanOneBarcode(title: 'Escanear S/N Servidor');
    if (!mounted || res == null) return;
    setState(() => _serverSerialCtrl.text = res.trim());
    await _agregarServidor(autoFromScan: true);
    _focusPn();
    await _scanPn();
  }

  Future<void> _agregarServidor({bool autoFromScan = false}) async {
    if (_serverSerialCtrl.text.trim().isEmpty) return;
    setState(() {
      _servidores.add(
        ServerRegistro(serverSerial: _serverSerialCtrl.text.trim()),
      );
      _serverIndexActivo = _servidores.length - 1;
      _serverSerialCtrl.clear();
    });
    if (!autoFromScan) {
      _focusPn();
    }
  }

  void _seleccionarServidor(int idx) {
    setState(() => _serverIndexActivo = idx);
    _focusPn();
  }

  void _focusPn() {
    if (mounted) FocusScope.of(context).requestFocus(_pnFocus);
  }

  void _focusSn() {
    if (mounted) FocusScope.of(context).requestFocus(_snFocus);
  }

  Future<void> _scanPn() async {
    if (_serverIndexActivo < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agregue / seleccione un servidor primero'),
        ),
      );
      return;
    }
    final res = await _scanOneBarcode(title: 'Escanear P/N');
    if (!mounted || res == null) return;
    setState(() => _pnCtrl.text = res.trim());
    _focusSn();
    await _scanSn();
  }

  Future<void> _scanSn() async {
    if (_serverIndexActivo < 0) return;
    final res = await _scanOneBarcode(title: 'Escanear S/N');
    if (!mounted || res == null) return;
    setState(() => _snCtrl.text = res.trim());
    _agregarPieza(autoFromScan: true);
  }

  Future<bool> _guardarEnBackend({bool showSuccessSnack = true}) async {
    final formValid = _formKey.currentState?.validate() ?? true;
    if (!formValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete los campos requeridos.')),
      );
      return false;
    }
    final registrosValidos = _servidores
        .where((s) => s.serverSerial.trim().isNotEmpty && s.piezas.isNotEmpty)
        .toList(growable: false);
    if (registrosValidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Agregue al menos un servidor con piezas para guardar.',
          ),
        ),
      );
      return false;
    }
    FocusScope.of(context).unfocus();
    final previ = OrderInputFormatter.normalize(_previCtrl.text.trim());
    _previCtrl.value = TextEditingValue(
      text: previ,
      selection: TextSelection.collapsed(offset: previ.length),
    );
    final cliente = _clienteCtrl.text.trim();
    final descripcion = _descCtrl.text.trim();
    final operario = _operarioCtrl.text.trim();
    setState(() => _uploading = true);
    try {
      final results = await _registroService.guardarRegistros(
        registros: registrosValidos,
        previ: previ,
        cliente: cliente,
        operario: operario,
        descripcion: descripcion,
      );
      if (!mounted) return false;
      if (showSuccessSnack) {
        final total = results.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Se guardaron $total registro${total == 1 ? '' : 's'} en la base de datos.',
            ),
          ),
        );
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error guardando registros: $e')));
      return false;
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _agregarPieza({bool autoFromScan = false}) {
    if (_serverIndexActivo < 0) return;
    if (_pnCtrl.text.trim().isEmpty || _snCtrl.text.trim().isEmpty) return;
    setState(() {
      _servidores[_serverIndexActivo].piezas.add(
        PiezaRegistro(pn: _pnCtrl.text.trim(), sn: _snCtrl.text.trim()),
      );
      _pnCtrl.clear();
      _snCtrl.clear();
    });
    _focusPn();
    if (autoFromScan) {
      // Optionally immediately begin next P/N scan; comment out if undesired.
      // Future.microtask(_scanPn);
    }
  }

  Future<void> _exportarPdf() async {
    final synced = await _guardarEnBackend(showSuccessSnack: false);
    if (!synced) return;
    if (_servidores.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final doc = pw.Document();
      final fecha = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

      final List<pw.Widget> contenido = [];
      contenido.add(
        pw.Text(
          'Registro piezas Servidor',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
      );
      contenido.add(pw.SizedBox(height: 4));
      contenido.add(pw.Text('Fecha: $fecha'));
      contenido.add(pw.SizedBox(height: 12));

      for (int i = 0; i < _servidores.length; i++) {
        final servidor = _servidores[i];
        contenido.add(
          pw.Text(
            'Servidor ${i + 1} S/N: ${servidor.serverSerial}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        );
        contenido.add(pw.SizedBox(height: 6));
        contenido.add(_tablaServidor(servidor));
        if (i != _servidores.length - 1) {
          contenido.add(pw.SizedBox(height: 24));
        }
      }

      doc.addPage(
        pw.MultiPage(pageFormat: PdfPageFormat.a4, build: (ctx) => contenido),
      );

      final bytes = await doc.save();
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/registro_servidor_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      await OpenFilex.open(file.path);

      final uploaded = await _subirPdfAArchivos(file);
      if (uploaded) {
        await _registrarLogAccion('Archivo PDF agregado en Archivos: ${file.uri.pathSegments.last}');
      } else if (widget.orderId != null) {
        await _registrarLogAccion('No se pudo adjuntar el PDF en Archivos para la orden.');
      }

      await _preguntarFinalizarOrden();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              uploaded
                  ? 'Registros guardados, PDF generado y adjuntado en Archivos.'
                  : 'Registros guardados y PDF generado.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  pw.Widget _tablaServidor(ServerRegistro servidor) {
    if (servidor.piezas.isEmpty) {
      return pw.Text('Sin piezas registradas');
    }
    final headerStyle = pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      fontSize: 10,
    );
    final cellPad = const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4);

    pw.Widget headerCell(String text) => pw.Container(
      color: PdfColor.fromInt(0xFFE0E0E0),
      padding: cellPad,
      child: pw.Text(text, style: headerStyle, textAlign: pw.TextAlign.center),
    );

    pw.Widget textCell(String text) => pw.Padding(
      padding: cellPad,
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 9),
        textAlign: pw.TextAlign.center,
      ),
    );

    pw.Widget barcodeCell(String data) => pw.Padding(
      padding: cellPad.copyWith(top: 2, bottom: 2),
      child: pw.Center(
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.code128(),
          data: data,
          height: 40,
          width: 140, // wider barcode
          drawText: false,
        ),
      ),
    );

    return pw.Table(
      border: pw.TableBorder.all(
        width: 0.5,
        color: PdfColor.fromInt(0xFF000000),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(4), // more space for barcode
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(4), // more space for barcode
      },
      children: [
        pw.TableRow(
          children: [
            headerCell('P/N'),
            headerCell('P/N (Código)'),
            headerCell('S/N'),
            headerCell('S/N (Código)'),
          ],
        ),
        for (final pieza in servidor.piezas)
          pw.TableRow(
            children: [
              textCell(pieza.pn),
              barcodeCell(pieza.pn),
              textCell(pieza.sn),
              barcodeCell(pieza.sn),
            ],
          ),
      ],
    );
  }

  @override
  void dispose() {
    _serverSerialCtrl.dispose();
    _previCtrl.dispose();
    _clienteCtrl.dispose();
    _descCtrl.dispose();
    _operarioCtrl.dispose();
    _pnCtrl.dispose();
    _snCtrl.dispose();
    _serverSerialFocus.dispose();
    _pnFocus.dispose();
    _snFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecorationTheme(
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.5,
        ),
      ),
    );
    final bool hayRegistrosConPiezas = _servidores.any(
      (s) => s.serverSerial.trim().isNotEmpty && s.piezas.isNotEmpty,
    );
    return Scaffold(
      extendBodyBehindAppBar: !widget.isEmbedded,
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text(
                'Registro Servidor',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
              ),
              centerTitle: true,
              actions: [
                IconButton(
                  tooltip: 'Exportar PDF y registrar',
                  onPressed: (_uploading || !_puedeSubir) ? null : _exportarPdf,
                  icon: _uploading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        )
                      : const Icon(Icons.picture_as_pdf),
                ),
              ],
            ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.surface,
                  Theme.of(context).colorScheme.surfaceContainer,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: Form(
                key: _formKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide =
                        constraints.maxWidth > 900; // tablets / desktop
                    final isMedium =
                        constraints.maxWidth > 650; // landscape phones grandes
                    final isVeryNarrow =
                        constraints.maxWidth < 360; // teléfonos muy angostos

                    Widget servidoresSection = Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(inputDecorationTheme: inputDecoration),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GlassCard(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Datos del registro',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    if (isWide || isMedium)
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: _previCtrl,
                                              inputFormatters: [
                                                OrderInputFormatter(),
                                              ],
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).textTheme.bodyMedium?.color,
                                              ),
                                              decoration: const InputDecoration(
                                                labelText: 'Previ / Cambio SKU',
                                              ),
                                              validator: (v) =>
                                                  v == null || v.trim().isEmpty
                                                  ? 'Requerido'
                                                  : RegExp(r'^[A-Z0-9]{2}-[A-Z0-9]{5}-[A-Z0-9]{2}$')
                                                            .hasMatch(OrderInputFormatter.normalize(v))
                                                        ? null
                                                        : 'Formato invalido (XX-XXXXX-XX)',
                                              onChanged: (_) => setState(() {}),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: TextFormField(
                                              controller: _clienteCtrl,
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).textTheme.bodyMedium?.color,
                                              ),
                                              decoration: const InputDecoration(
                                                labelText: 'Cliente',
                                              ),
                                              validator: (v) =>
                                                  v == null || v.trim().isEmpty
                                                  ? 'Requerido'
                                                  : null,
                                              onChanged: (_) => setState(() {}),
                                            ),
                                          ),
                                        ],
                                      )
                                    else
                                      Column(
                                        children: [
                                          TextFormField(
                                            controller: _previCtrl,
                                            inputFormatters: [
                                              OrderInputFormatter(),
                                            ],
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).textTheme.bodyMedium?.color,
                                            ),
                                            decoration: const InputDecoration(
                                              labelText: 'Previ / Cambio SKU',
                                            ),
                                            validator: (v) =>
                                                v == null || v.trim().isEmpty
                                                ? 'Requerido'
                                                : RegExp(r'^[A-Z0-9]{2}-[A-Z0-9]{5}-[A-Z0-9]{2}$')
                                                          .hasMatch(OrderInputFormatter.normalize(v))
                                                      ? null
                                                      : 'Formato invalido (XX-XXXXX-XX)',
                                            onChanged: (_) => setState(() {}),
                                          ),
                                          const SizedBox(height: 8),
                                          TextFormField(
                                            controller: _clienteCtrl,
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).textTheme.bodyMedium?.color,
                                            ),
                                            decoration: const InputDecoration(
                                              labelText: 'Cliente',
                                            ),
                                            validator: (v) =>
                                                v == null || v.trim().isEmpty
                                                ? 'Requerido'
                                                : null,
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ],
                                      ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _operarioCtrl,
                                      readOnly: _hasCurrentUserOperario,
                                      enabled: !_hasCurrentUserOperario
                                          ? null
                                          : false,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.color
                                            ?.withOpacity(
                                              _hasCurrentUserOperario
                                                  ? 0.6
                                                  : 1.0,
                                            ),
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Operario',
                                        hintText: _hasCurrentUserOperario
                                            ? 'Se usa tu usuario actual'
                                            : null,
                                      ),
                                      validator: (v) =>
                                          v == null || v.trim().isEmpty
                                          ? 'Requerido'
                                          : null,
                                      onChanged: (_) => setState(() {}),
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _descCtrl,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.color,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'Descripción del trabajo',
                                      ),
                                      maxLines: 3,
                                      validator: (v) =>
                                          v == null || v.trim().isEmpty
                                          ? 'Requerido'
                                          : null,
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            GlassCard(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Servidores',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: _serverSerialCtrl,
                                            focusNode: _serverSerialFocus,
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).textTheme.bodyMedium?.color,
                                            ),
                                            textInputAction: TextInputAction.done,
                                            onFieldSubmitted: (_) => _agregarServidor(),
                                            decoration: InputDecoration(
                                              labelText:
                                                  'Serial del Servidor (S/N)',
                                              suffixIcon: IconButton(
                                                tooltip:
                                                    'Escanear serial servidor',
                                                icon: const Icon(
                                                  Icons.qr_code_scanner,
                                                ),
                                                onPressed: _scanServerSerial,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    if (_servidores.isNotEmpty)
                                      isWide || isMedium
                                          ? Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: _servidores
                                                  .asMap()
                                                  .entries
                                                  .map(
                                                    (e) => _buildServerChip(
                                                      e.key,
                                                      e.value.serverSerial,
                                                    ),
                                                  )
                                                  .toList(),
                                            )
                                          : SizedBox(
                                              height: 46,
                                              child: ListView.separated(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                itemBuilder: (ctx, i) {
                                                  final s = _servidores[i];
                                                  return _buildServerChip(
                                                    i,
                                                    s.serverSerial,
                                                  );
                                                },
                                                separatorBuilder: (_, __) =>
                                                    const SizedBox(width: 8),
                                                itemCount: _servidores.length,
                                              ),
                                            ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            GlassCard(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Piezas del Servidor',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    if (!isVeryNarrow)
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: _pnCtrl,
                                              focusNode: _pnFocus,
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).textTheme.bodyMedium?.color,
                                              ),
                                                textInputAction: TextInputAction.next,
                                                onFieldSubmitted: (_) => _focusSn(),
                                                decoration: InputDecoration(
                                                  labelText: 'P/N',
                                                  suffixIcon: IconButton(
                                                    icon: const Icon(
                                                      Icons.qr_code_scanner,
                                                    ),
                                                    onPressed: _scanPn,
                                                  ),
                                                ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextFormField(
                                              controller: _snCtrl,
                                              focusNode: _snFocus,
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).textTheme.bodyMedium?.color,
                                              ),
                                                textInputAction: TextInputAction.done,
                                                onFieldSubmitted: (_) => _agregarPieza(),
                                                decoration: InputDecoration(
                                                  labelText: 'S/N',
                                                  suffixIcon: IconButton(
                                                    icon: const Icon(
                                                      Icons.qr_code_scanner,
                                                    ),
                                                    onPressed: _scanSn,
                                                  ),
                                                ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    const SizedBox(height: 16),
                                    if (_serverIndexActivo >= 0)
                                      GlassCard(
                                        elevation: 4,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withOpacity(0.3),
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: _listaPiezas(
                                            _servidores[_serverIndexActivo],
                                          ),
                                        ),
                                      )
                                    else
                                      Text(
                                        'Seleccione o agregue un servidor',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).disabledColor,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (!isWide &&
                                !isMedium &&
                                _serverIndexActivo >= 0) ...[
                              const SizedBox(height: 16),
                              // Preview se muestra debajo en teléfonos angostos
                              GlassCard(
                                child: SizedBox(
                                  height: 320,
                                  child: _previewBarcodes(
                                    _servidores[_serverIndexActivo],
                                  ),
                                ),
                              ),
                            ],
                            if (widget.isEmbedded) ...[
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _uploading
                                      ? null
                                      : hayRegistrosConPiezas
                                      ? _exportarPdf
                                      : _scanServerSerial,
                                  icon: _uploading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          hayRegistrosConPiezas
                                              ? Icons.picture_as_pdf
                                              : Icons.qr_code_scanner,
                                        ),
                                  label: Text(
                                    _uploading
                                        ? 'Procesando...'
                                        : hayRegistrosConPiezas
                                        ? 'Exportar PDF y Registrar'
                                        : 'Escanear Servidor',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );

                    Widget previewSection = Padding(
                      padding: const EdgeInsets.only(
                        right: 16,
                        top: 16,
                        bottom: 16,
                      ),
                      child: GlassCard(
                        child: _serverIndexActivo < 0
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    'Seleccione un servidor',
                                    style: TextStyle(
                                      color: Theme.of(context).disabledColor,
                                    ),
                                  ),
                                ),
                              )
                            : _previewBarcodes(_servidores[_serverIndexActivo]),
                      ),
                    );

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: servidoresSection),
                          Expanded(flex: 2, child: previewSection),
                        ],
                      );
                    } else if (isMedium) {
                      // Landscape phone / tablet pequeño: fila pero preview más pequeño
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: servidoresSection),
                          Expanded(flex: 4, child: previewSection),
                        ],
                      );
                    } else {
                      // Teléfono vertical: columna
                      return servidoresSection; // preview ya incluido abajo si hay servidor
                    }
                  },
                ),
              ),
            ),
          ),
          if (!widget.isEmbedded)
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: EdgeNavHandle(openOnHover: false),
            ),
        ],
      ),
      floatingActionButton: widget.isEmbedded
          ? null
          : FloatingActionButton.extended(
              onPressed: _uploading
                  ? null
                  : hayRegistrosConPiezas
                  ? _exportarPdf
                  : _scanServerSerial,
              icon: _uploading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : Icon(
                      hayRegistrosConPiezas
                          ? Icons.picture_as_pdf
                          : Icons.qr_code_scanner,
                    ),
              label: Text(
                _uploading
                    ? 'Procesando...'
                    : hayRegistrosConPiezas
                    ? 'Exportar PDF y Registrar'
                    : 'Escanear Servidor',
              ),
            ),
    );
  }

  Widget _buildServerChip(int index, String serial) {
    final selected = index == _serverIndexActivo;
    return FilterChip(
      label: Text(
        serial,
        style: TextStyle(
          color: selected
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).textTheme.bodyMedium?.color,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: .5,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      selectedColor: Theme.of(context).colorScheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).dividerColor,
          width: 1.0,
        ),
      ),
      elevation: selected ? 2 : 0,
      pressElevation: 3,
      onSelected: (_) => _seleccionarServidor(index),
      avatar: selected
          ? Icon(
              Icons.check,
              size: 16,
              color: Theme.of(context).colorScheme.onPrimary,
            )
          : Icon(
              Icons.dns_outlined,
              size: 16,
              color: Theme.of(context).iconTheme.color,
            ),
    );
  }

  Widget _listaPiezas(ServerRegistro servidor) {
    if (servidor.piezas.isEmpty) {
      return Text(
        'Sin piezas añadidas',
        style: TextStyle(color: Theme.of(context).disabledColor),
      );
    }
    return DataTable(
      headingRowColor: WidgetStateProperty.all(
        Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      dataRowColor: WidgetStateProperty.all(
        Theme.of(context).colorScheme.surface,
      ),
      columns: const [
        DataColumn(label: Text('P/N')),
        DataColumn(label: Text('S/N')),
        DataColumn(label: Text('Acciones')),
      ],
      rows: servidor.piezas.asMap().entries.map((e) {
        final idx = e.key;
        final p = e.value;
        return DataRow(
          cells: [
            DataCell(Text(p.pn)),
            DataCell(Text(p.sn)),
            DataCell(
              IconButton(
                icon: Icon(
                  Icons.delete,
                  color: Theme.of(context).colorScheme.error,
                ),
                onPressed: () {
                  setState(() => servidor.piezas.removeAt(idx));
                },
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _previewBarcodes(ServerRegistro servidor) {
    if (servidor.piezas.isEmpty) {
      return Center(
        child: Text(
          'Escanee o añada piezas',
          style: TextStyle(color: Theme.of(context).disabledColor),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: servidor.piezas.length,
      itemBuilder: (ctx, i) {
        final pieza = servidor.piezas[i];
        return GlassCard(
          elevation: 4,
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'P/N: ${pieza.pn}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(
                  height: 50,
                  child: BarcodeWidget(
                    barcode: Barcode.code128(),
                    data: pieza.pn,
                    drawText: false,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'S/N: ${pieza.sn}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(
                  height: 50,
                  child: BarcodeWidget(
                    barcode: Barcode.code128(),
                    data: pieza.sn,
                    drawText: false,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.elevation = 8,
    this.color,
    this.borderRadius,
    super.key,
  });

  final Widget child;
  final double elevation;
  final Color? color;
  final BorderRadiusGeometry? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(20);
    final cardColor =
        color ??
        Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.3);
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: radius,
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: elevation * 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}
