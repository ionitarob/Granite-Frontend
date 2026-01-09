import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../config.dart';
import '../../services/api_service.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/main_sidebar.dart';

const String baseUrl = kBackendBaseUrl;

class RegistroFichajeScreen extends StatefulWidget {
  const RegistroFichajeScreen({super.key});
  @override
  State<RegistroFichajeScreen> createState() => _RegistroFichajeScreenState();
}

class _RegistroFichajeScreenState extends State<RegistroFichajeScreen> {
  static const double _empleadoColWidth = 230;
  DateTime _fechaIni = DateTime.now().subtract(
    Duration(days: DateTime.now().weekday - 1),
  );
  DateTime _fechaFin = DateTime.now().add(
    Duration(days: 7 - DateTime.now().weekday),
  );
  String? _empresaId, _turno, _rolId, _nombre;
  List<Map<String, dynamic>> _empresas = [], _roles = [];
  bool _cargando = false;
  List<Map<String, dynamic>> _empleados = [];

  final _entradaCtrl = TextEditingController();
  final _salidaCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  OverlayEntry? _edgeOverlay;

  @override
  void initState() {
    super.initState();
    _cargarEmpresasYRoles();
    _cargarFichajes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    });
  }

  @override
  void dispose() {
    // remove overlay handle if present
    _edgeOverlay?.remove();
    _edgeOverlay = null;
    _entradaCtrl.dispose();
    _salidaCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarEmpresasYRoles() async {
    final api = ApiService.instance?.client;
    if (api == null) return;

    final respEmp = await api.get('/empresas');
    final respRol = await api.get('/roles');
    // Defensive parsing: some endpoints return a List directly, others return
    // a Map with a 'results' or 'data' list. Handle both to avoid type errors.
    List<Map<String, dynamic>> empresas = [];
    if (respEmp.ok && respEmp.body != null) {
      final b = respEmp.body;
      if (b is List) {
        empresas = List<Map<String, dynamic>>.from(b);
      } else if (b is Map) {
        if (b['results'] is List) {
          empresas = List<Map<String, dynamic>>.from(b['results']);
        } else if (b['data'] is List) {
          empresas = List<Map<String, dynamic>>.from(b['data']);
        }
      }
    }

    List<Map<String, dynamic>> roles = [];
    if (respRol.ok && respRol.body != null) {
      final b = respRol.body;
      if (b is List) {
        roles = List<Map<String, dynamic>>.from(b);
      } else if (b is Map) {
        if (b['results'] is List) {
          roles = List<Map<String, dynamic>>.from(b['results']);
        } else if (b['data'] is List) {
          roles = List<Map<String, dynamic>>.from(b['data']);
        }
      }
    }

    setState(() {
      _empresas = empresas;
      _roles = roles;
    });
  }

  Future<void> _cargarFichajes() async {
    setState(() => _cargando = true);
    final params = <String, String>{
      'fecha_ini': _fechaIni.toIso8601String().substring(0, 10),
      'fecha_fin': _fechaFin.toIso8601String().substring(0, 10),
      if (_empresaId?.isNotEmpty == true) 'empresa_id': _empresaId!,
      if (_turno?.isNotEmpty == true) 'turno': _turno!,
      if (_rolId?.isNotEmpty == true) 'rol_id': _rolId!,
      if (_nombre?.isNotEmpty == true) 'nombre': _nombre!,
    };
    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final path = '/fichajes/plan_vs_real?$queryString';

    try {
      final api = ApiService.instance?.client;
      if (api == null) {
        setState(() => _empleados = []);
        _mostrarError('Error: API no disponible');
        return;
      }

      final resp = await api.get(path);
      if (resp.ok && resp.body != null) {
        final data = resp.body as List;
        final empleados = data.cast<Map<String, dynamic>>();
        // Normalizamos y ordenamos los fichajes por hora para cada día
        _ordenarFichajesEnData(empleados);
        setState(() => _empleados = empleados);
      } else {
        setState(() => _empleados = []);
        _mostrarError('Error ${resp.statusCode}');
      }
    } catch (_) {
      setState(() => _empleados = []);
      _mostrarError('Error de red');
    } finally {
      setState(() => _cargando = false);
    }
  }

  // Ordena los fichajes reales por hora y calcula primera_entrada/ultima_salida
  void _ordenarFichajesEnData(List<Map<String, dynamic>> empleados) {
    for (final emp in empleados) {
      final dias = (emp['dias'] as List?) ?? const [];
      for (final dia in dias) {
        final fichajes =
            (dia['fichajes'] as List?)?.cast<Map<String, dynamic>>() ??
            <Map<String, dynamic>>[];
        fichajes.sort(
          (a, b) =>
              _timeToMinutes(a['hora']).compareTo(_timeToMinutes(b['hora'])),
        );
        // guardar ordenados
        dia['fichajes'] = fichajes;
        // primera entrada
        final primeraEntrada = fichajes.firstWhere(
          (f) => (f['tipo']?.toString().toLowerCase() ?? '') == 'entrada',
          orElse: () => <String, dynamic>{},
        );
        dia['primera_entrada'] = primeraEntrada.isEmpty
            ? null
            : (primeraEntrada['hora'] as String?);
        // última salida (como está ordenado, tomamos el último que sea salida)
        final ultimaSalida = fichajes.lastWhere(
          (f) => (f['tipo']?.toString().toLowerCase() ?? '') == 'salida',
          orElse: () => <String, dynamic>{},
        );
        dia['ultima_salida'] = ultimaSalida.isEmpty
            ? null
            : (ultimaSalida['hora'] as String?);
      }
    }
  }

  // Convierte "HH:MM" o "HH:MM:SS" en minutos para ordenar con seguridad
  int _timeToMinutes(dynamic value) {
    if (value == null) return -1;
    final s = value.toString().trim();
    if (s.isEmpty) return -1;
    final parts = s.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return h * 60 + m;
  }

  void _mostrarDetalleDia(Map<String, dynamic> dia, Map<String, dynamic> emp) {
    _entradaCtrl.text = (dia["planificado"]["hora_entrada"] ?? '') as String;
    _salidaCtrl.text = (dia["planificado"]["hora_salida"] ?? '') as String;
    _obsCtrl.text = (dia["planificado"]["observaciones"] ?? '') as String;
    String tipoDia = (dia["tipo_dia"] ?? 'laboral').toString();

    Future<String?> pick(String initial) async {
      final now = TimeOfDay.now();
      TimeOfDay base = now;
      if (initial.contains(':')) {
        final p = initial.split(':');
        final h = int.tryParse(p[0]);
        final m = int.tryParse(p[1]);
        if (h != null && m != null) base = TimeOfDay(hour: h, minute: m);
      }
      final sel = await showTimePicker(
        context: context,
        initialTime: base,
        helpText: 'Selecciona hora',
      );
      if (sel == null) return null;
      return '${sel.hour.toString().padLeft(2, '0')}:${sel.minute.toString().padLeft(2, '0')}';
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateD) {
            final size = MediaQuery.of(ctx).size;
            final maxHeight = size.height * 0.75; // limit dialog height
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SizedBox(
                  height: maxHeight,
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${emp["nombre"]} ${emp["apellido"]}\n${dia["fecha"]}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _entradaCtrl,
                                  readOnly: true,
                                  onTap: () async {
                                    final t = await pick(_entradaCtrl.text);
                                    if (t != null) {
                                      setStateD(() => _entradaCtrl.text = t);
                                    }
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Entrada',
                                    prefixIcon: const Icon(Icons.login),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _salidaCtrl,
                                  readOnly: true,
                                  onTap: () async {
                                    final t = await pick(_salidaCtrl.text);
                                    if (t != null) {
                                      setStateD(() => _salidaCtrl.text = t);
                                    }
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Salida',
                                    prefixIcon: const Icon(Icons.logout),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _obsCtrl,
                            minLines: 1,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: 'Observaciones',
                              prefixIcon: const Icon(Icons.note_alt_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final opt in [
                                'laboral',
                                'festivo',
                                'vacaciones',
                                'baja',
                              ])
                                ChoiceChip(
                                  label: Text(
                                    opt[0].toUpperCase() + opt.substring(1),
                                  ),
                                  selected: tipoDia == opt,
                                  onSelected: (_) =>
                                      setStateD(() => tipoDia = opt),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.save),
                                label: const Text('Guardar planificación'),
                                onPressed: () {
                                  // TODO: PUT planificación
                                  Navigator.pop(ctx);
                                  _cargarFichajes();
                                },
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.close),
                                label: const Text('Cancelar'),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Divider(height: 1),
                          const SizedBox(height: 14),
                          Text(
                            'Fichajes reales',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 260),
                            child: SingleChildScrollView(
                              child: _bloqueFichajesEditable(
                                dia["fichajes"],
                                emp["empleado_id"],
                                dia["fecha"],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _bloqueFichajesEditable(List? fichajes, int empleadoId, String fecha) {
    final horaCtrl = TextEditingController();
    String tipoNuevo = 'entrada';
    return StatefulBuilder(
      builder: (ctx, setStateD) {
        // aseguramos orden por hora para mostrar y borrar
        final List<Map<String, dynamic>> ordenados =
            (fichajes ?? <Map<String, dynamic>>[]).cast<Map<String, dynamic>>()
              ..sort(
                (a, b) => _timeToMinutes(
                  a['hora'],
                ).compareTo(_timeToMinutes(b['hora'])),
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Fichajes reales:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ...ordenados.map<Widget>(
              (f) => Row(
                children: [
                  Text(
                    "${f["hora"]} • ${f["tipo"]}${f["auto_generado"] == 1 ? " (auto)" : ""}",
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      final api = ApiService.instance?.client;
                      if (api != null) {
                        await api.delete('/fichajes/${f["id"]}');
                      }
                      if (!mounted) return;
                      navigator.pop();
                      _cargarFichajes();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: horaCtrl,
                    decoration: const InputDecoration(labelText: "HH:MM"),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: tipoNuevo,
                  items: ['entrada', 'salida']
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t[0].toUpperCase() + t.substring(1)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setStateD(() => tipoNuevo = v!),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.blue),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final parts = fecha.split('-');
                    final y = parts[0].padLeft(4, '0');
                    final m = parts[1].padLeft(2, '0');
                    final d = parts[2].padLeft(2, '0');
                    final fIso = '$y-$m-$d';
                    final hParts = horaCtrl.text.split(':');
                    final hh = hParts[0].padLeft(2, '0');
                    final mm = (hParts.length > 1 ? hParts[1] : '').padLeft(
                      2,
                      '0',
                    );
                    final hIso = '$hh:$mm';
                    final api = ApiService.instance?.client;
                    if (api != null) {
                      await api.post(
                        '/fichajes/manual',
                        jsonBody: {
                          'empleado_id': empleadoId,
                          'fecha_hora': '$fIso $hIso',
                          'tipo': tipoNuevo,
                          'auto_generado': 0,
                        },
                      );
                    }
                    if (!mounted) return;
                    navigator.pop();
                    _cargarFichajes();
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // Descarga el Excel del mes seleccionado y lo guarda localmente sin abrir navegador.
  Future<void> _exportarExcelMes() async {
    try {
      setState(() => _cargando = true);
      final y = _fechaIni.year.toString().padLeft(4, '0');
      final m = _fechaIni.month.toString().padLeft(2, '0');
      final path = '/fichajes/excel?mes=$y-$m';

      final api = ApiService.instance?.client;
      if (api == null) {
        _mostrarError('API no disponible');
        return;
      }

      final resp = await api.getBytes(path);
      if (!resp.ok) {
        _mostrarError('No se pudo exportar (HTTP ${resp.statusCode})');
        return;
      }

      // Sugerir nombre desde cabecera o fallback
      String filename = 'fichajes_$y-$m.xlsx';
      final dispo = resp.headers?['content-disposition'] ?? '';
      final match = RegExp(
        r'filename\*=UTF-8'
        '([^;\n]+)|filename="?([^";\n]+)"?',
      ).firstMatch(dispo);
      if (match != null) {
        final f1 = match.group(1);
        final f2 = match.group(2);
        final raw = (f1 ?? f2)?.trim();
        if (raw != null && raw.isNotEmpty) {
          filename = Uri.decodeFull(raw);
        }
      }

      final dir = await _defaultDownloadDir();
      final file = File('${dir.path}${Platform.pathSeparator}$filename');
      await file.writeAsBytes(resp.body as List<int>);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Guardado en ${file.path}'),
          action: SnackBarAction(
            label: 'Abrir',
            onPressed: () => OpenFilex.open(file.path),
          ),
        ),
      );
    } catch (e) {
      _mostrarError('Error al descargar: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // Intenta localizar la carpeta Descargas (o Documentos si no existe) por plataforma
  Future<Directory> _defaultDownloadDir() async {
    // iOS/Android: usar Documents; Windows/macOS/Linux: intentar Descargas
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        return await getApplicationDocumentsDirectory();
      }
    } catch (_) {
      // Platform not available in web or others
    }
    // Desktop fallbacks
    final docs = await getApplicationDocumentsDirectory();
    // Heurística para Descargas junto a Documents
    final parent = Directory(docs.path).parent;
    final candidates = <Directory>[
      Directory('${parent.path}${Platform.pathSeparator}Downloads'),
      Directory('${parent.path}${Platform.pathSeparator}Descargas'),
      Directory('${parent.path}${Platform.pathSeparator}Download'),
    ];
    for (final d in candidates) {
      if (await d.exists()) return d;
    }
    return docs;
  }

  @override
  Widget build(BuildContext context) {
    // calculamos la lista de días en orden
    final totalDias = _fechaFin.difference(_fechaIni).inDays + 1;
    final diasSemana = List<String>.generate(totalDias, (i) {
      final d = _fechaIni.add(Duration(days: i));
      return d.toIso8601String().substring(0, 10);
    });
    final hoyStr = DateTime.now().toIso8601String().substring(0, 10);

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        toolbarHeight: 64,
        title: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              color: theme.brightness == Brightness.dark
                  ? Colors.white.withAlpha(28)
                  : Colors.white.withAlpha(200),
              child: Text(
                'Control de Fichajes',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color:
                      theme.textTheme.titleLarge?.color ??
                      colorScheme.onSurface,
                  letterSpacing: .5,
                ),
              ),
            ),
          ),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
        ),
        actions: [
          Tooltip(
            message: 'Recargar',
            child: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _cargarFichajes,
            ),
          ),
          Tooltip(
            message: 'Exportar mes a Excel',
            child: IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: _exportarExcelMes,
            ),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(66),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: LiquidGlassCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: _buildFiltroSemana(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 0.9),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: EdgeNavHandle(
                  user: ApiService.instance?.currentUser,
                  width: 28,
                ),
              ),
            ),
          ),
          SafeArea(
            child: _cargando
                ? _buildLoading()
                : _empleados.isEmpty
                ? const Center(child: Text("Sin datos para este rango"))
                : Column(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Tabla principal (izquierda)
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, viewport) {
                                  // ancho del viewport disponible
                                  final double vw = viewport.maxWidth;
                                  // ancho real del grid (col empleado + dias * celda+gap)
                                  final int diasCount = diasSemana.length;
                                  const double cellW = 96;
                                  const double gap =
                                      6; // margen horizontal total por celda
                                  final double gridW =
                                      _empleadoColWidth +
                                      diasCount * (cellW + gap) +
                                      4; // + slack

                                  return SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.all(8),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(minWidth: vw),
                                      child: Center(
                                        child: SizedBox(
                                          width: gridW,
                                          child: LiquidGlassCard(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // cabecera
                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    SizedBox(
                                                      width: _empleadoColWidth,
                                                      child: const Center(
                                                        child: Padding(
                                                          padding:
                                                              EdgeInsets.symmetric(
                                                                vertical: 6,
                                                              ),
                                                          child: Text(
                                                            "Empleado",
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 15,
                                                              letterSpacing: .5,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    for (final fecha
                                                        in diasSemana)
                                                      _HeaderDia(
                                                        fecha: fecha,
                                                        esHoy: fecha == hoyStr,
                                                      ),
                                                  ],
                                                ),
                                                const Divider(
                                                  height: 28,
                                                  thickness: 1.3,
                                                ),
                                                _buildLegend(),
                                                const SizedBox(height: 6),
                                                // listado empleados
                                                Expanded(
                                                  child: SingleChildScrollView(
                                                    child: Column(
                                                      children: _empleados.map((
                                                        emp,
                                                      ) {
                                                        final mapDias = {
                                                          for (var d
                                                              in emp["dias"])
                                                            d["fecha"]
                                                                    as String:
                                                                d,
                                                        };
                                                        return Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                bottom: 10,
                                                              ),
                                                          child: Row(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .center,
                                                            children: [
                                                              SizedBox(
                                                                width:
                                                                    _empleadoColWidth,
                                                                child:
                                                                    _empleadoBubble(
                                                                      emp,
                                                                    ),
                                                              ),
                                                              for (final fecha
                                                                  in diasSemana)
                                                                _buildCeldaDia(
                                                                  emp,
                                                                  mapDias[fecha],
                                                                  esHoy:
                                                                      fecha ==
                                                                      hoyStr,
                                                                ),
                                                            ],
                                                          ),
                                                        );
                                                      }).toList(),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Panel de activos por empresa (derecha)
                            _panelActivos(hoyStr),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // Panel lateral de activos por empresa para la fecha indicada (hoy)
  Widget _panelActivos(String fecha) {
    final activos = _activosPorEmpresaParaFecha(fecha);
    // Orden y etiquetas fijas
    final etiquetas = const ['Marlex', 'ManPower', 'Cares', 'Ingram'];
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LiquidGlassCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Text(
                'Activos hoy',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.05,
              children: [
                for (final e in etiquetas)
                  _EmpresaActivosCard(empresa: e, activos: activos[e] ?? 0),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Calcula un mapa con el número de empleados activos (entradas > salidas) por empresa para una fecha.
  Map<String, int> _activosPorEmpresaParaFecha(String fecha) {
    final res = <String, int>{
      'Marlex': 0,
      'Ingram': 0,
      'ManPower': 0,
      'Cares': 0,
    };
    for (final emp in _empleados) {
      // localizar el día
      final dias = (emp['dias'] as List?) ?? const [];
      final dia = dias.cast<Map<String, dynamic>?>().firstWhere(
        (d) => (d?['fecha']?.toString() ?? '') == fecha,
        orElse: () => null,
      );
      if (dia == null) continue;
      final fichajes =
          (dia['fichajes'] as List?)?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];
      int entradas = 0, salidas = 0;
      for (final f in fichajes) {
        final t = (f['tipo']?.toString() ?? '').toLowerCase();
        if (t == 'entrada') entradas++;
        if (t == 'salida') salidas++;
      }
      final activo = entradas > salidas;
      if (!activo) continue;
      final nombreEmpresa = _normalizarEmpresaNombre(_empresaDeEmp(emp));
      if (nombreEmpresa == null) continue;
      res[nombreEmpresa] = (res[nombreEmpresa] ?? 0) + 1;
    }
    return res;
  }

  // Intenta obtener el nombre de empresa a partir del mapa de empleado.
  String? _empresaDeEmp(Map<String, dynamic> emp) {
    // Casos habituales: cadena directa
    final direct = emp['empresa'];
    if (direct is String && direct.trim().isNotEmpty) return direct.trim();
    // Objeto con nombre
    if (direct is Map) {
      final n = direct['nombre'] ?? direct['name'];
      if (n is String && n.trim().isNotEmpty) return n.trim();
    }
    // Campos alternativos
    final alt = emp['empresa_nombre'] ?? emp['nombre_empresa'];
    if (alt is String && alt.trim().isNotEmpty) return alt.trim();
    // Por id -> buscar en listado _empresas
    final id = emp['empresa_id']?.toString();
    if (id != null && id.isNotEmpty) {
      final found = _empresas.firstWhere(
        (e) => e['id']?.toString() == id,
        orElse: () => const {},
      );
      final name = (found['nombre'] ?? found['name'])?.toString();
      if (name != null && name.trim().isNotEmpty) return name.trim();
    }
    return null;
  }

  // Normaliza nombres variados a nuestras cuatro etiquetas, o null si no aplica.
  String? _normalizarEmpresaNombre(String? nombre) {
    if (nombre == null) return null;
    final s = nombre.toLowerCase();
    if (s.contains('marlex')) return 'Marlex';
    if (s.contains('ingram')) return 'Ingram';
    if (s.contains('man power') || s.contains('manpower')) return 'ManPower';
    if (s.contains('cares') || s.contains('ceres')) return 'Cares';
    return null;
  }

  // Barra de filtros y navegación de semana centrada
  Widget _buildFiltroSemana(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Tooltip(
            message: 'Semana anterior',
            child: IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                setState(() {
                  _fechaIni = _fechaIni.subtract(const Duration(days: 7));
                  _fechaFin = _fechaIni.add(const Duration(days: 6));
                });
                _cargarFichajes();
              },
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              backgroundColor: Colors.white.withValues(alpha: .7),
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.black.withValues(alpha: .06)),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.calendar_today, size: 17),
            label: Text(
              "${_fechaIni.toIso8601String().substring(0, 10)} → ${_fechaFin.toIso8601String().substring(0, 10)}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2023, 1, 1),
                lastDate: DateTime(2030, 12, 31),
                initialDateRange: DateTimeRange(
                  start: _fechaIni,
                  end: _fechaFin,
                ),
              );
              if (picked != null) {
                setState(() {
                  _fechaIni = picked.start;
                  _fechaFin = picked.end;
                });
                _cargarFichajes();
              }
            },
          ),
          Tooltip(
            message: 'Semana siguiente',
            child: IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                setState(() {
                  _fechaIni = _fechaIni.add(const Duration(days: 7));
                  _fechaFin = _fechaIni.add(const Duration(days: 6));
                });
                _cargarFichajes();
              },
            ),
          ),
          const SizedBox(width: 18),
          _buildFilterDropdown(
            hint: 'Empresa',
            value: _empresaId,
            items: _empresas.map((e) => e['id'].toString()).toList(),
            display: (v) =>
                _empresas.firstWhere((e) => e['id'].toString() == v)['nombre'],
            onChanged: (v) {
              setState(() => _empresaId = v);
              _cargarFichajes();
            },
          ),
          const SizedBox(width: 12),
          _buildFilterDropdown(
            hint: 'Turno',
            value: _turno,
            items: const ['Mañana', 'Tarde', 'Noche', 'Central'],
            display: (v) => v,
            onChanged: (v) {
              setState(() => _turno = v);
              _cargarFichajes();
            },
          ),
          const SizedBox(width: 12),
          _buildFilterDropdown(
            hint: 'Rol',
            value: _rolId,
            items: _roles.map((r) => r['id'].toString()).toList(),
            display: (v) =>
                _roles.firstWhere((r) => r['id'].toString() == v)['nombre'],
            onChanged: (v) {
              setState(() => _rolId = v);
              _cargarFichajes();
            },
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 160,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Nombre',
                isDense: true,
                filled: true,
                fillColor: Colors.white.withValues(alpha: .7),
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.black.withValues(alpha: .06),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.black.withValues(alpha: .06),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF64B5F6)),
                ),
              ),
              onSubmitted: (t) {
                setState(() => _nombre = t.trim().isEmpty ? null : t.trim());
                _cargarFichajes();
              },
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Limpiar filtros',
            child: IconButton(
              icon: const Icon(Icons.filter_alt_off),
              onPressed: () {
                setState(() {
                  _empresaId = _turno = _rolId = _nombre = null;
                });
                _cargarFichajes();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCeldaDia(
    Map<String, dynamic> emp,
    dynamic dia, {
    bool esHoy = false,
  }) {
    if (dia == null) {
      return Container(
        width: 96,
        height: 88,
        alignment: Alignment.center,
        decoration: _baseCellDecoration(esHoy: esHoy, muted: true),
        child: const Text(
          "Sin fichaje",
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
      );
    }
    final esFestivo = (dia["tipo_dia"] ?? '').toString().toLowerCase().contains(
      'festivo',
    );
    final tipoDia = (dia["tipo_dia"] ?? 'laboral').toString().toLowerCase();
    final plan = dia["planificado"] ?? {};

    Color horaPlanColor;
    if (esFestivo) {
      horaPlanColor = const Color(0xFFC62828);
    } else if (tipoDia == 'vacaciones') {
      horaPlanColor = const Color(0xFF3949AB);
    } else if (tipoDia == 'baja') {
      horaPlanColor = const Color(0xFF6A1B9A);
    } else {
      horaPlanColor = const Color(0xFF1565C0);
    }

    final primera = dia["primera_entrada"] as String?;
    final ultima = dia["ultima_salida"] as String?;

    return AnimatedScale(
      scale: esHoy ? 1.02 : 1.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      child: GestureDetector(
        onTap: () => _mostrarDetalleDia(dia, emp),
        child: Container(
          width: 96,
          height: 86,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          decoration: _baseCellDecoration(
            esHoy: esHoy,
            tipoDia: tipoDia,
            festivo: esFestivo,
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    FittedBox(
                      child: Text(
                        _lineaPlan(plan),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .2,
                          color: horaPlanColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _contenidoReal(
                      primera: primera,
                      ultima: ultima,
                      esFestivo: esFestivo,
                      tipoDia: tipoDia,
                    ),
                  ],
                ),
              ),
              if (tipoDia != 'laboral' && !esFestivo)
                Positioned(
                  top: 4,
                  right: 4,
                  child: _ChipTipoDia(tipo: tipoDia),
                ),
              if (esHoy)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: const Color(0xFF64B5F6),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String hint,
    String? value,
    required List<String> items,
    required String Function(String) display,
    required void Function(String?) onChanged,
  }) {
    final widths = {"Empresa": 176, "Turno": 136, "Rol": 136};
    return SizedBox(
      width: (widths[hint] ?? 160).toDouble(),
      child: DropdownButtonFormField<String>(
        key: ValueKey('${hint}_$value'),
        initialValue: value,
        hint: Text(hint),
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down, size: 14),
        iconSize: 14,
        items: items
            .map((v) => DropdownMenuItem(value: v, child: Text(display(v))))
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white.withValues(alpha: .7),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.black.withValues(alpha: .06)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.black.withValues(alpha: .06)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF64B5F6)),
          ),
        ),
      ),
    );
  }

  // ───── Helpers UI ─────

  BoxDecoration _baseCellDecoration({
    bool esHoy = false,
    String? tipoDia,
    bool festivo = false,
    bool muted = false,
  }) {
    Color base = Colors.white.withValues(alpha: 0.9);
    if (festivo) {
      base = const Color(0xFFE53935).withValues(alpha: .06);
    }
    if (tipoDia == 'vacaciones') {
      base = const Color(0xFF3949AB).withValues(alpha: .06);
    }
    if (tipoDia == 'baja') {
      base = const Color(0xFF6A1B9A).withValues(alpha: .06);
    }
    if (muted) {
      base = Colors.white.withValues(alpha: 0.75);
    }
    return BoxDecoration(
      color: base,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: esHoy
            ? const Color(0xFF64B5F6)
            : Colors.black.withValues(alpha: .05),
        width: esHoy ? 1.2 : 1.0,
      ),
      boxShadow: [
        if (!muted)
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
      ],
      gradient: esHoy
          ? LinearGradient(
              colors: [const Color(0xFFBBDEFB).withValues(alpha: .4), base],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
    );
  }

  Widget _buildLoading() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 8),
        const CircularProgressIndicator(strokeWidth: 5),
        const SizedBox(height: 18),
        Text(
          'Cargando fichajes...',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .9),
            fontWeight: FontWeight.w600,
            letterSpacing: .5,
          ),
        ),
      ],
    );
  }

  // Leyenda de colores e iconos
  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 8, bottom: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _legendChip(color: const Color(0xFF1565C0), texto: 'Planificado'),
            _legendChip(color: const Color(0xFF2E7D32), texto: 'Entrada real'),
            _legendChip(color: const Color(0xFFEF6C00), texto: 'Salida real'),
            _legendChip(color: const Color(0xFFC62828), texto: 'Festivo'),
            _legendChip(color: const Color(0xFF3949AB), texto: 'Vacaciones'),
            _legendChip(color: const Color(0xFF6A1B9A), texto: 'Baja'),
            _legendChip(
              color: const Color(0xFF42A5F5),
              texto: 'Hoy',
              borde: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendChip({
    required Color color,
    required String texto,
    bool borde = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: borde
            ? color.withValues(alpha: .10)
            : color.withValues(alpha: .14),
        shape: StadiumBorder(
          side: BorderSide(
            color: color.withValues(alpha: borde ? .8 : .35),
            width: .8,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            texto,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.darken(),
            ),
          ),
        ],
      ),
    );
  }

  // Construcción del texto plan
  String _lineaPlan(Map plan) {
    final e = (plan['hora_entrada'] ?? '-') as String;
    final s = (plan['hora_salida'] ?? '-') as String;
    if (e == '-' && s == '-') return '—';
    return '$e - $s';
  }

  Widget _contenidoReal({
    String? primera,
    String? ultima,
    required bool esFestivo,
    required String tipoDia,
  }) {
    Text styled(String txt, Color c) => Text(
      txt,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: c,
        height: 1.05,
      ),
      maxLines: 1,
      overflow: TextOverflow.clip,
    );
    if (esFestivo) {
      return styled('FESTIVO', Colors.red).center();
    }
    if (tipoDia == 'vacaciones') {
      return styled('VACACIONES', Colors.indigo).center();
    }
    if (tipoDia == 'baja') {
      return styled('BAJA', Colors.deepPurple).center();
    }
    if (primera == null && ultima == null) {
      return const Text(
        '—',
        style: TextStyle(fontSize: 11, color: Colors.grey),
      ).center();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (primera != null) styled(primera, Colors.green[700]!),
        if (ultima != null) styled(ultima, Colors.orange[700]!),
      ],
    ).center();
  }

  String _iniciales(dynamic nombre, dynamic apellido) {
    final n = (nombre ?? '').toString().trim();
    final a = (apellido ?? '').toString().trim();
    return '${n.isNotEmpty ? n[0] : ''}${a.isNotEmpty ? a[0] : ''}';
  }

  Widget _empleadoBubble(Map<String, dynamic> emp) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: .20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFF1565C0),
              child: Text(
                _iniciales(emp["nombre"], emp["apellido"]).toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                '${emp["nombre"]} ${emp["apellido"]}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Pequeña extensión para centrar rápidamente
extension _CenterExt on Widget {
  Widget center() => Center(child: this);
}

// ─────── LiquidGlassCard ───────

class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  const LiquidGlassCard({required this.child, super.key});
  @override
  Widget build(BuildContext ctx) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
          ),
          child: child,
        ),
      ),
    );
  }
}

// (Animated background removed for a more minimalist, static look)

// ─────── Header Día Widget ───────

class _HeaderDia extends StatelessWidget {
  final String fecha; // YYYY-MM-DD
  final bool esHoy;
  const _HeaderDia({required this.fecha, required this.esHoy});
  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(fecha);
    final letra = dt != null
        ? ['L', 'M', 'X', 'J', 'V', 'S', 'D'][dt.weekday - 1]
        : '';
    return Container(
      width: 96,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: esHoy
            ? const Color(0xFFBBDEFB).withValues(alpha: .6)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            letra,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: esHoy ? const Color(0xFF1976D2) : Colors.blueGrey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fecha.substring(5),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: .3,
              color: esHoy ? const Color(0xFF1976D2) : Colors.blueGrey[800],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────── Chip Tipo Día ───────

class _ChipTipoDia extends StatelessWidget {
  final String tipo; // vacaciones, baja, etc
  const _ChipTipoDia({required this.tipo});
  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (tipo) {
      case 'vacaciones':
        bg = Colors.indigo.withValues(alpha: .15);
        fg = Colors.indigo[600]!;
        break;
      case 'baja':
        bg = Colors.deepPurple.withValues(alpha: .15);
        fg = Colors.deepPurple[600]!;
        break;
      default:
        bg = Colors.blueGrey.withValues(alpha: .15);
        fg = Colors.blueGrey[700]!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: ShapeDecoration(
        color: bg,
        shape: StadiumBorder(
          side: BorderSide(color: fg.withValues(alpha: .4), width: .6),
        ),
      ),
      child: Text(
        tipo.toUpperCase(),
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
          color: fg,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

// ─────── Card de activos por empresa ───────
class _EmpresaActivosCard extends StatelessWidget {
  final String empresa;
  final int activos;
  const _EmpresaActivosCard({required this.empresa, required this.activos});

  @override
  Widget build(BuildContext context) {
    return LiquidGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              empresa,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              activos.toString(),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1565C0),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Activos',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────── Color util extension ───────
extension _ColorShade on Color {
  Color darken([double amount = .2]) {
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}
