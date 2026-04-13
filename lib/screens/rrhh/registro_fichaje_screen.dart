import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../widgets/liquid_glass_card.dart';
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
  bool _showMobileAdvancedFilters = false;

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
        
        // Remove inactive users UNLESS they have registry data in this period
        final filteredEmpleados = empleados.where((e) {
          if (e['activo'] == true || e['activo'] == 1) return true;
          // Inactive user: keep ONLY if they have ANY punches in the requested days
          final dias = (e['dias'] as List?) ?? [];
          for (final dia in dias) {
            final f = dia['fichajes'] as List?;
            if (f != null && f.isNotEmpty) return true;
          }
          return false;
        }).toList();

        // Normalizamos y ordenamos los fichajes por hora para cada día
        _ordenarFichajesEnData(filteredEmpleados);
        setState(() => _empleados = filteredEmpleados);
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
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _FichajeDiaDialog(
        emp: emp,
        dia: dia,
        onPatchGrid: (payload) {
          _patchDiaInMemory(
            empleadoId: payload.empleadoId,
            fecha: payload.fecha,
            fichajes: payload.fichajes,
            primeraEntrada: payload.primeraEntrada,
            ultimaSalida: payload.ultimaSalida,
          );
        },
      ),
    );
  }

  void _patchDiaInMemory({
    required int empleadoId,
    required String fecha, // YYYY-MM-DD
    List<Map<String, dynamic>>? fichajes,
    String? primeraEntrada,
    String? ultimaSalida,
  }) {
    // Find employee
    final empIndex = _empleados.indexWhere(
      (e) => e["empleado_id"] == empleadoId,
    );
    if (empIndex == -1) return;

    final emp = _empleados[empIndex];
    final dias = ((emp["dias"] as List?) ?? []).cast<Map<String, dynamic>>();

    final diaIndex = dias.indexWhere(
      (d) => (d["fecha"] ?? '').toString() == fecha,
    );
    if (diaIndex == -1) return;

    final dia = dias[diaIndex];

    if (fichajes != null) {
      dia["fichajes"] = fichajes;
    }
    if (primeraEntrada != null) {
      dia["primera_entrada"] = primeraEntrada;
    }
    if (ultimaSalida != null) {
      dia["ultima_salida"] = ultimaSalida;
    }

    // Write back (defensive)
    dias[diaIndex] = dia;
    emp["dias"] = dias;
    _empleados[empIndex] = emp;

    setState(() {});
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
    final isMobile = MediaQuery.of(context).size.width < 980;
    final mobileFilterHeight = _showMobileAdvancedFilters ? 196.0 : 108.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
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
        toolbarHeight: isMobile ? 58 : 64,
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
          preferredSize: Size.fromHeight(isMobile ? mobileFilterHeight : 66),
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
                    child: _buildFiltroSemana(context, isMobile: isMobile),
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

          SafeArea(
            child: _cargando
                ? _buildLoading()
                : _empleados.isEmpty
                ? const Center(child: Text("Sin datos para este rango"))
                : Column(
                    children: [
                      if (isMobile) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                          child: _panelActivosMobile(hoyStr),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Expanded(
                        child: isMobile
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 92),
                                child: _buildPlanVsRealTable(
                                  diasSemana: diasSemana,
                                  hoyStr: hoyStr,
                                  compact: true,
                                ),
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _buildPlanVsRealTable(
                                      diasSemana: diasSemana,
                                      hoyStr: hoyStr,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
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
  Widget _buildFiltroSemana(BuildContext context, {bool isMobile = false}) {
    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
              Expanded(
                child: LiquidGlassCard(
                  radius: 14,
                  elevated: false,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  onTap: () async {
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
                  child: Text(
                    "${_fechaIni.toIso8601String().substring(0, 10)} → ${_fechaFin.toIso8601String().substring(0, 10)}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
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
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Tooltip(
                message: _showMobileAdvancedFilters
                    ? 'Ocultar filtros'
                    : 'Mostrar filtros',
                child: IconButton(
                  icon: Icon(
                    _showMobileAdvancedFilters
                        ? Icons.tune_rounded
                        : Icons.tune_outlined,
                  ),
                  onPressed: () {
                    setState(() {
                      _showMobileAdvancedFilters = !_showMobileAdvancedFilters;
                    });
                  },
                ),
              ),
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
          if (_showMobileAdvancedFilters) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildFilterDropdown(
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
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFilterDropdown(
                    hint: 'Turno',
                    value: _turno,
                    items: const ['Mañana', 'Tarde', 'Noche', 'Central'],
                    display: (v) => v,
                    onChanged: (v) {
                      setState(() => _turno = v);
                      _cargarFichajes();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildFilterDropdown(
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
                ),
                const SizedBox(width: 8),
                Expanded(
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
              ],
            ),
          ],
        ],
      );
    }

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
          LiquidGlassCard(
            radius: 14,
            elevated: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            onTap: () async {
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.date_range_rounded, size: 18),
                const SizedBox(width: 10),
                Text(
                  "${_fechaIni.toIso8601String().substring(0, 10)} → ${_fechaFin.toIso8601String().substring(0, 10)}",
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: Colors.black.withValues(alpha: .5),
                ),
              ],
            ),
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

  Widget _buildPlanVsRealTable({
    required List<String> diasSemana,
    required String hoyStr,
    bool compact = false,
  }) {
    return LayoutBuilder(
      builder: (context, viewport) {
        final double vw = viewport.maxWidth;
        final int diasCount = diasSemana.length;
        final double cellW = compact ? 86 : 96;
        final double empleadoColWidth = compact ? 206 : _empleadoColWidth;
        const double gap = 6;
        final double gridW = empleadoColWidth + diasCount * (cellW + gap) + 4;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.all(compact ? 6 : 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: vw),
            child: Center(
              child: SizedBox(
                width: gridW,
                child: LiquidGlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 10 : 14,
                          compact ? 10 : 12,
                          compact ? 10 : 14,
                          compact ? 8 : 10,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.grid_view_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Planificación vs Real',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: compact ? 14 : 15,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Text(
                                '${_empleados.length} empleados',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: empleadoColWidth,
                            child: const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 6),
                                child: Text(
                                  'Empleado',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    letterSpacing: .5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          for (final fecha in diasSemana)
                            _HeaderDia(
                              fecha: fecha,
                              esHoy: fecha == hoyStr,
                              width: cellW,
                            ),
                        ],
                      ),
                      const Divider(height: 28, thickness: 1.3),
                      _buildLegend(),
                      const SizedBox(height: 6),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: _empleados.map((emp) {
                              final mapDias = {
                                for (var d in emp['dias']) d['fecha'] as String: d,
                              };
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: empleadoColWidth,
                                      child: _empleadoBubble(emp),
                                    ),
                                    for (final fecha in diasSemana)
                                      _buildCeldaDia(
                                        emp,
                                        mapDias[fecha],
                                        esHoy: fecha == hoyStr,
                                        cellWidth: cellW,
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
    );
  }

  Widget _panelActivosMobile(String fecha) {
    final activos = _activosPorEmpresaParaFecha(fecha);
    final etiquetas = const ['Marlex', 'ManPower', 'Cares', 'Ingram'];

    return LiquidGlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Activos hoy',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in etiquetas)
                  Container(
                    width: 74,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.06),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          e,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${activos[e] ?? 0}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCeldaDia(
    Map<String, dynamic> emp,
    dynamic dia, {
    bool esHoy = false,
    double cellWidth = 96,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (dia == null) {
      return _HoverCell(
        width: cellWidth,
        height: 86,
        tooltip: 'Sin fichajes ni planificación',
        child: Container(
          width: cellWidth,
          height: 86,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          alignment: Alignment.center,
          decoration: _baseCellDecoration(
            context: context,
            esHoy: esHoy,
            muted: true,
          ),
          child: Text(
            "—",
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black38,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    final tipoDia = (dia["tipo_dia"] ?? 'laboral').toString().toLowerCase();
    final esFestivo = tipoDia.contains('festivo');
    final plan = (dia["planificado"] ?? {}) as Map;

    final primera = dia["primera_entrada"] as String?;
    final ultima = dia["ultima_salida"] as String?;

    final tooltip = StringBuffer()
      ..writeln('Empleado: ${emp["nombre"]} ${emp["apellido"]}')
      ..writeln('Fecha: ${dia["fecha"]}')
      ..writeln('Tipo: ${tipoDia.toUpperCase()}')
      ..writeln('Plan: ${_lineaPlan(plan)}')
      ..writeln('Real: ${primera ?? "—"} / ${ultima ?? "—"}');

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

    final baseDecor = _baseCellDecoration(
      context: context,
      esHoy: esHoy,
      tipoDia: tipoDia,
      festivo: esFestivo,
    );

    return _HoverCell(
      width: cellWidth,
      height: 86,
      tooltip: tooltip.toString(),
      onTap: () => _mostrarDetalleDia(dia, emp),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        width: cellWidth,
        height: 86,
        decoration: baseDecor,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    child: Text(
                      _lineaPlan(plan),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .2,
                        color: horaPlanColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _contenidoReal(
                    context: context,
                    primera: primera,
                    ultima: ultima,
                    esFestivo: esFestivo,
                    tipoDia: tipoDia,
                  ),
                ],
              ),
            ),
            if (tipoDia != 'laboral' && !esFestivo)
              Positioned(top: 4, right: 4, child: _ChipTipoDia(tipo: tipoDia)),
            if (esHoy)
              const Positioned(
                top: 4,
                left: 4,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: Color(0xFF64B5F6),
                ),
              ),
          ],
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
    required BuildContext context,
    bool esHoy = false,
    String? tipoDia,
    bool festivo = false,
    bool muted = false,
    bool hovered = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;

    Color surface = isDark
        ? Colors.white.withValues(alpha: muted ? 0.04 : 0.07)
        : Colors.white.withValues(alpha: muted ? 0.65 : 0.85);

    // tintes suaves por tipo
    Color tint = Colors.transparent;
    if (festivo) tint = const Color(0xFFE53935).withValues(alpha: .10);
    if (tipoDia == 'vacaciones') {
      tint = const Color(0xFF3949AB).withValues(alpha: .10);
    }
    if (tipoDia == 'baja') {
      tint = const Color(0xFF6A1B9A).withValues(alpha: .10);
    }

    // hover: sube un pelín el “cristal”
    final hoverBoost = hovered ? (isDark ? 0.04 : 0.06) : 0.0;

    final borderColor = esHoy
        ? cs.primary.withValues(alpha: isDark ? 0.70 : 0.60)
        : (isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.06));

    return BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: borderColor, width: esHoy ? 1.4 : 1),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          surface.withValues(alpha: (surface.a + hoverBoost).clamp(0, 1)),
          surface.withValues(
            alpha: (surface.a + hoverBoost - 0.02).clamp(0, 1),
          ),
        ],
      ),
      boxShadow: [
        if (!muted)
          BoxShadow(
            color: (isDark ? Colors.black : Colors.black).withValues(
              alpha: isDark ? 0.40 : 0.12,
            ),
            blurRadius: hovered ? 18 : 12,
            offset: const Offset(0, 8),
          ),
      ],
      // overlay de tint
      backgroundBlendMode: BlendMode.srcOver,
      color: tint == Colors.transparent ? null : tint,
    );
  }

  Widget _buildLoading() {
    return Center(
      child: LiquidGlassCard(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 5),
            const SizedBox(height: 14),
            Text(
              'Cargando fichajes...',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: .3,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ],
        ),
      ),
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
    required BuildContext context,
    String? primera,
    String? ultima,
    required bool esFestivo,
    required String tipoDia,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget pill(String text, IconData icon, Color c) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: c,
                height: 1,
              ),
            ),
          ],
        ),
      );
    }

    if (esFestivo) {
      return pill(
        'Festivo',
        Icons.event_busy_rounded,
        const Color(0xFFE53935),
      ).center();
    }
    if (tipoDia == 'vacaciones') {
      return pill(
        'Vacaciones',
        Icons.beach_access_rounded,
        const Color(0xFF3949AB),
      ).center();
    }
    if (tipoDia == 'baja') {
      return pill(
        'Baja',
        Icons.healing_rounded,
        const Color(0xFF6A1B9A),
      ).center();
    }

    final hasAny =
        (primera != null && primera.trim().isNotEmpty) ||
        (ultima != null && ultima.trim().isNotEmpty);
    if (!hasAny) {
      return Text(
        '—',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white54 : Colors.black38,
        ),
      ).center();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (primera != null && primera.trim().isNotEmpty)
          pill(primera, Icons.login_rounded, const Color(0xFF2E7D32)),
        if (ultima != null && ultima.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          pill(ultima, Icons.logout_rounded, const Color(0xFFEF6C00)),
        ],
      ],
    ).center();
  }

  String _iniciales(dynamic nombre, dynamic apellido) {
    final n = (nombre ?? '').toString().trim();
    final a = (apellido ?? '').toString().trim();
    return '${n.isNotEmpty ? n[0] : ''}${a.isNotEmpty ? a[0] : ''}';
  }

  Widget _empleadoBubble(Map<String, dynamic> emp) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final nombre = '${emp["nombre"] ?? ""} ${emp["apellido"] ?? ""}'.trim();
    final empresa =
        _normalizarEmpresaNombre(_empresaDeEmp(emp)) ??
        (emp["empresa"]?.toString() ?? '');
    final turno = (emp["turno"] ?? '').toString();

    Widget tag(String t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        ),
      ),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white70 : Colors.black54,
        ),
      ),
    );

    final fechaFinRaw = emp['fecha_finalizacion']?.toString();
    final fechaFin = fechaFinRaw != null ? DateTime.tryParse(fechaFinRaw) : null;
    final now = DateTime.now();
    final isExpired = fechaFin != null && fechaFin.isBefore(DateTime(now.year, now.month, now.day));
    final isNearExp = fechaFin != null && !isExpired && fechaFin.isBefore(now.add(const Duration(days: 15)));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: LiquidGlassCard(
        radius: 18,
        blur: 18,
        elevated: false,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        borderColor: isExpired 
            ? Colors.red.withValues(alpha: 0.4) 
            : isNearExp 
                ? Colors.orange.withValues(alpha: 0.4) 
                : null,
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isExpired 
                      ? Colors.red.shade800 
                      : isNearExp 
                          ? Colors.orange.shade800 
                          : const Color(0xFF1565C0),
                  child: Text(
                    _iniciales(emp["nombre"], emp["apellido"]).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (isExpired || isNearExp)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Icon(
                      isExpired ? Icons.warning_rounded : Icons.timer_outlined,
                      size: 14,
                      color: isExpired ? Colors.red : Colors.orange,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre.isEmpty ? '—' : nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: isExpired ? Colors.red.shade900 : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      if (empresa.trim().isNotEmpty) tag(empresa),
                      if (turno.trim().isNotEmpty) tag(turno),
                    ],
                  ),
                ],
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

class _HoverCell extends StatefulWidget {
  final double width;
  final double height;
  final Widget child;
  final String? tooltip;
  final VoidCallback? onTap;

  const _HoverCell({
    required this.width,
    required this.height,
    required this.child,
    this.tooltip,
    this.onTap,
  });

  @override
  State<_HoverCell> createState() => _HoverCellState();
}

class _HoverCellState extends State<_HoverCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final themedChild = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      transform: Matrix4.identity()..scale(_hover ? 1.02 : 1.0),
      child: widget.child,
    );

    final clickable = MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: widget.onTap == null
          ? themedChild
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(14),
                child: themedChild,
              ),
            ),
    );

    if (widget.tooltip == null || widget.tooltip!.trim().isEmpty) {
      return clickable;
    }

    return Tooltip(
      message: widget.tooltip!,
      waitDuration: const Duration(milliseconds: 220),
      child: clickable,
    );
  }
}

// (Animated background removed for a more minimalist, static look)

// ─────── Header Día Widget ───────

class _HeaderDia extends StatelessWidget {
  final String fecha; // YYYY-MM-DD
  final bool esHoy;
  final double width;
  const _HeaderDia({
    required this.fecha,
    required this.esHoy,
    this.width = 96,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dt = DateTime.tryParse(fecha);

    final letra = dt != null
        ? ['L', 'M', 'X', 'J', 'V', 'S', 'D'][dt.weekday - 1]
        : '';
    final isWeekend =
        dt != null &&
        (dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday);

    final bg = esHoy
        ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.16)
        : isWeekend
        ? (isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04))
        : Colors.transparent;

    final fg = esHoy
        ? theme.colorScheme.primary
        : isWeekend
        ? (isDark ? Colors.white70 : Colors.black54)
        : (isDark ? Colors.white60 : Colors.blueGrey[700]!);

    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: esHoy
              ? theme.colorScheme.primary.withValues(alpha: 0.55)
              : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          Text(
            letra,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: fg,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            fecha.substring(5),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: .3,
              color: fg,
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Text(
                activos.toString(),
                key: ValueKey(activos),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1565C0),
                ),
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

class _DiaPatchPayload {
  final int empleadoId;
  final String fecha;
  final List<Map<String, dynamic>> fichajes;
  final String? primeraEntrada;
  final String? ultimaSalida;

  _DiaPatchPayload({
    required this.empleadoId,
    required this.fecha,
    required this.fichajes,
    required this.primeraEntrada,
    required this.ultimaSalida,
  });
}

class _FichajeDiaDialog extends StatefulWidget {
  final Map<String, dynamic> emp;
  final Map<String, dynamic> dia;
  final void Function(_DiaPatchPayload payload) onPatchGrid;

  const _FichajeDiaDialog({
    required this.emp,
    required this.dia,
    required this.onPatchGrid,
  });

  @override
  State<_FichajeDiaDialog> createState() => _FichajeDiaDialogState();
}

class _FichajeDiaDialogState extends State<_FichajeDiaDialog> {
  late final TextEditingController _entradaCtrl;
  late final TextEditingController _salidaCtrl;
  late final TextEditingController _obsCtrl;

  // Add real punch
  late final TextEditingController _horaNuevaCtrl;
  String _tipoNuevo = 'entrada';
  late String _tipoDia; // laboral/festivo/vacaciones/baja

  late List<Map<String, dynamic>> _fichajes;
  bool _busyFichajes = false;

  @override
  void initState() {
    super.initState();

    final plan = (widget.dia["planificado"] ?? {}) as Map;
    _entradaCtrl = TextEditingController(
      text: (plan["hora_entrada"] ?? '').toString(),
    );
    _salidaCtrl = TextEditingController(
      text: (plan["hora_salida"] ?? '').toString(),
    );
    _obsCtrl = TextEditingController(
      text: (plan["observaciones"] ?? '').toString(),
    );

    _horaNuevaCtrl = TextEditingController();
    _tipoDia = (widget.dia["tipo_dia"] ?? 'laboral').toString().toLowerCase();

    // Local copy of real punches
    final raw = ((widget.dia["fichajes"] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    _fichajes = List<Map<String, dynamic>>.from(raw);
    // Don't auto-patch on init, just sort
    _fichajes.sort(
      (a, b) => _timeToMinutes(a['hora']).compareTo(_timeToMinutes(b['hora'])),
    );
  }

  @override
  void dispose() {
    _entradaCtrl.dispose();
    _salidaCtrl.dispose();
    _obsCtrl.dispose();
    _horaNuevaCtrl.dispose();
    super.dispose();
  }

  int _timeToMinutes(dynamic value) {
    if (value == null) return -1;
    final s = value.toString().trim();
    if (s.isEmpty) return -1;
    final parts = s.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return h * 60 + m;
  }

  void _sortAndCompute() {
    _fichajes.sort(
      (a, b) => _timeToMinutes(a['hora']).compareTo(_timeToMinutes(b['hora'])),
    );

    final primera = _fichajes.firstWhere(
      (f) => (f['tipo']?.toString().toLowerCase() ?? '') == 'entrada',
      orElse: () => <String, dynamic>{},
    );

    final ultima = _fichajes.lastWhere(
      (f) => (f['tipo']?.toString().toLowerCase() ?? '') == 'salida',
      orElse: () => <String, dynamic>{},
    );

    final primeraEntrada = primera.isEmpty
        ? null
        : (primera['hora'] as String?);
    final ultimaSalida = ultima.isEmpty ? null : (ultima['hora'] as String?);

    // Patch parent grid instantly
    final empleadoId = widget.emp["empleado_id"] as int;
    final fecha = (widget.dia["fecha"] ?? '').toString();

    widget.onPatchGrid(
      _DiaPatchPayload(
        empleadoId: empleadoId,
        fecha: fecha,
        fichajes: List<Map<String, dynamic>>.from(_fichajes),
        primeraEntrada: primeraEntrada,
        ultimaSalida: ultimaSalida,
      ),
    );
  }

  Future<String?> _pickTime(String initial) async {
    TimeOfDay base = TimeOfDay.now();
    if (initial.contains(':')) {
      final p = initial.split(':');
      final h = int.tryParse(p[0]);
      final m = int.tryParse(p.length > 1 ? p[1] : '0');
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

  String _nombreCompleto() {
    final n = (widget.emp["nombre"] ?? '').toString().trim();
    final a = (widget.emp["apellido"] ?? '').toString().trim();
    return ('$n $a').trim();
  }

  String _iniciales() {
    final n = (widget.emp["nombre"] ?? '').toString().trim();
    final a = (widget.emp["apellido"] ?? '').toString().trim();
    final i1 = n.isNotEmpty ? n[0] : '';
    final i2 = a.isNotEmpty ? a[0] : '';
    return (i1 + i2).toUpperCase();
  }

  // --- Actions with local state update ---

  Future<void> _deleteFichaje(dynamic id) async {
    final api = ApiService.instance?.client;
    if (api == null) return;

    setState(() => _busyFichajes = true);
    try {
      await api.delete('/fichajes/$id');
      _fichajes.removeWhere((x) => x["id"] == id);
      _sortAndCompute();
      setState(() {});
    } finally {
      if (mounted) setState(() => _busyFichajes = false);
    }
  }

  Future<void> _addFichajeManual() async {
    final api = ApiService.instance?.client;
    if (api == null) return;

    final hora = _horaNuevaCtrl.text.trim();
    final re = RegExp(r'^\d{2}:\d{2}$');
    if (!re.hasMatch(hora)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hora inválida. Usa HH:MM')));
      return;
    }

    final empleadoId = widget.emp["empleado_id"];
    final fecha = (widget.dia["fecha"] ?? '').toString(); // YYYY-MM-DD
    final fechaHora = '$fecha $hora';

    setState(() => _busyFichajes = true);
    try {
      final resp = await api.post(
        '/fichajes/manual',
        jsonBody: {
          'empleado_id': empleadoId,
          'fecha_hora': fechaHora,
          'tipo': _tipoNuevo,
          'auto_generado': 0,
        },
      );

      // Best-case: backend returns created record with ID
      Map<String, dynamic> created = {
        "id": DateTime.now().millisecondsSinceEpoch, // fallback temp id
        "hora": hora,
        "tipo": _tipoNuevo,
        "auto_generado": 0,
      };

      if (resp.ok && resp.body is Map) {
        final b = resp.body as Map;
        // try to map common keys
        created["id"] = b["id"] ?? created["id"];
        created["hora"] = b["hora"] ?? created["hora"];
        created["tipo"] = b["tipo"] ?? created["tipo"];
        created["auto_generado"] =
            b["auto_generado"] ?? created["auto_generado"];
      }

      _fichajes.add(created);
      _horaNuevaCtrl.clear();
      _sortAndCompute();
      setState(() {});
    } finally {
      if (mounted) setState(() => _busyFichajes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final maxW = 600.0;
    final maxH = MediaQuery.of(context).size.height * 0.78;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: LiquidGlassCard(
          radius: 26,
          blur: 20,
          elevated: true,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: SizedBox(
            height: maxH,
            child: Column(
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF1565C0),
                      child: Text(
                        _iniciales(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _nombreCompleto().isEmpty
                                ? 'Empleado'
                                : _nombreCompleto(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (widget.dia["fecha"] ?? '').toString(),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionTitle(
                          icon: Icons.event_available_rounded,
                          title: 'Planificación',
                        ),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: _TimeField(
                                label: 'Entrada',
                                icon: Icons.login_rounded,
                                controller: _entradaCtrl,
                                onPick: () async {
                                  final t = await _pickTime(_entradaCtrl.text);
                                  if (t != null)
                                    setState(() => _entradaCtrl.text = t);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _TimeField(
                                label: 'Salida',
                                icon: Icons.logout_rounded,
                                controller: _salidaCtrl,
                                onPick: () async {
                                  final t = await _pickTime(_salidaCtrl.text);
                                  if (t != null)
                                    setState(() => _salidaCtrl.text = t);
                                },
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

                        const SizedBox(height: 12),
                        _TipoDiaSelector(
                          value: _tipoDia,
                          onChanged: (v) => setState(() => _tipoDia = v),
                        ),

                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.save_rounded),
                                label: const Text('Guardar planificación'),
                                onPressed: () async {
                                  // TODO: aquí metes tu PUT real de planificación
                                  // - hora_entrada, hora_salida, observaciones, tipo_dia
                                  Navigator.of(context).pop();
                                  // widget.onReload(); // No longer needed
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.close),
                                label: const Text('Cancelar'),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 14),

                        _SectionTitle(
                          icon: Icons.punch_clock_rounded,
                          title: 'Fichajes reales',
                          trailing: Row(
                            children: [
                              Text(
                                '${_fichajes.length}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                              ),
                              if (_busyFichajes) ...[
                                const SizedBox(width: 8),
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (_fichajes.isEmpty)
                          _EmptyState(
                            text: 'No hay fichajes reales para este día.',
                            icon: Icons.hourglass_empty_rounded,
                          )
                        else
                          Column(
                            children: [
                              for (final f in _fichajes)
                                _FichajeRealTile(
                                  hora: (f["hora"] ?? '').toString(),
                                  tipo: (f["tipo"] ?? '')
                                      .toString()
                                      .toLowerCase(),
                                  auto: f["auto_generado"] == 1,
                                  onDelete: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (dCtx) => AlertDialog(
                                        title: const Text('Eliminar fichaje'),
                                        content: const Text(
                                          '¿Seguro que quieres borrar este fichaje?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(dCtx, false),
                                            child: const Text('Cancelar'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(dCtx, true),
                                            child: const Text('Eliminar'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok != true) return;
                                    await _deleteFichaje(f["id"]);
                                  },
                                ),
                            ],
                          ),

                        const SizedBox(height: 12),

                        // Add row
                        LiquidGlassCard(
                          radius: 18,
                          elevated: false,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _horaNuevaCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'HH:MM',
                                    prefixIcon: Icon(Icons.schedule_rounded),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              DropdownButton<String>(
                                value: _tipoNuevo,
                                underline: const SizedBox.shrink(),
                                items: const ['entrada', 'salida']
                                    .map(
                                      (t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(
                                          t[0].toUpperCase() + t.substring(1),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _tipoNuevo = v ?? 'entrada'),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Añadir fichaje',
                                icon: Icon(
                                  Icons.add_circle_rounded,
                                  size: 30,
                                  color: theme.colorScheme.primary,
                                ),
                                onPressed: _addFichajeManual,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;

  const _SectionTitle({required this.icon, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final VoidCallback onPick;

  const _TimeField({
    required this.label,
    required this.icon,
    required this.controller,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: onPick,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: const Icon(Icons.access_time_rounded),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _TipoDiaSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _TipoDiaSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const opts = ['laboral', 'festivo', 'vacaciones', 'baja'];

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final opt in opts)
          ChoiceChip(
            label: Text(opt[0].toUpperCase() + opt.substring(1)),
            selected: value == opt,
            onSelected: (_) => onChanged(opt),
          ),
      ],
    );
  }
}

class _FichajeRealTile extends StatelessWidget {
  final String hora;
  final String tipo; // entrada/salida
  final bool auto;
  final VoidCallback onDelete;

  const _FichajeRealTile({
    required this.hora,
    required this.tipo,
    required this.auto,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isEntrada = tipo == 'entrada';
    final c = isEntrada ? const Color(0xFF2E7D32) : const Color(0xFFEF6C00);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: c.withValues(alpha: 0.10),
        border: Border.all(color: c.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(
            isEntrada ? Icons.login_rounded : Icons.logout_rounded,
            color: c,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$hora • ${isEntrada ? "Entrada" : "Salida"}${auto ? " (auto)" : ""}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  final IconData icon;

  const _EmptyState({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LiquidGlassCard(
      radius: 18,
      elevated: false,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: isDark ? Colors.white54 : Colors.black45),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
