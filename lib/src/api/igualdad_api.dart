import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:configtool_granite_frontend/config.dart';
import 'package:provider/provider.dart';
import 'package:configtool_granite_frontend/main.dart';
import 'package:configtool_granite_frontend/services/api_service.dart';
import 'package:configtool_granite_frontend/models/smartphone.dart';
import 'package:configtool_granite_frontend/models/paged_response.dart';

/// Representa el usuario actual devuelto por el backend.
class User {
  final int id;
  final String username;
  final String role;
  final String empresa;

  User({
    required this.id,
    required this.username,
    required this.role,
    required this.empresa,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String,
      role: json['role'] as String,
      empresa: json['empresa_id'] as String,
    );
  }
}

class ExportExpedicionResult {
  final Uint8List bytes;
  final String? observaciones;

  const ExportExpedicionResult(this.bytes, {this.observaciones});
}

class IgualdadApi {
  // Use the centralized kBackendBaseUrl defined in `lib/config.dart`.
  static final Uri _baseUri = Uri.parse(kBackendBaseUrl);

  // GET /igualdad/resumen_semanal
  static Future<Map<String, dynamic>> getResumenSemanal({String? fecha}) async {
    final path = '/igualdad/resumen_semanal${fecha != null ? '?fecha=$fecha' : ''}';
    final body = await _doGet(path);
    return Map<String, dynamic>.from(body as Map);
  }

  // GET /igualdad/resumen_semanal/semanas
  static Future<List<Map<String, dynamic>>> getResumenSemanas({int? limit}) async {
    final query = limit != null ? '?limit=$limit' : '';
    final body = await _doGet('/igualdad/resumen_semanal/semanas$query');

    List<dynamic> raw;
    if (body is List) {
      raw = body;
    } else if (body is Map && body['semanas'] is List) {
      raw = List<dynamic>.from(body['semanas'] as List);
    } else {
      throw Exception('Respuesta inesperada al listar semanas de resumen semanal');
    }

    return raw.map<Map<String, dynamic>>((item) {
      if (item is Map<String, dynamic>) return item;
      if (item is Map) {
        return item.map<String, dynamic>((key, value) => MapEntry(key.toString(), value));
      }
      throw Exception('Elemento inválido en listado de semanas');
    }).toList();
  }

  // POST /igualdad/resumen_semanal/marcar_enviado
  static Future<void> marcarResumenSemanalEnviado({
    required String fecha,
    bool enviado = true,
    String? observaciones,
  }) async {
    final payload = <String, dynamic>{
      'fecha': fecha,
      'enviado': enviado,
      if (observaciones != null) 'observaciones': observaciones,
    };
    await _doPost('/igualdad/resumen_semanal/marcar_enviado', jsonBody: payload);
  }

  // ------------------ Nuevo ------------------

  /// GET /usuario/current
  /// Obtiene el usuario autenticado y su rol.
  static Future<User> getCurrentUser() async {
    final body = await _doGet('/usuario/current');
    return User.fromJson(Map<String, dynamic>.from(body as Map));
  }

  // POST /igualdad/entrada
  static Future<void> crearEntradaStock(Map<String, dynamic> body) async {
    final res = await _doPost('/igualdad/entrada', jsonBody: body);
    if (res is Map && (res['status'] == 201 || res['status'] == 200)) return;
    // ApiClient returns parsed body on success; when using http fallback we
    // will have thrown on non-success codes. If we get here, assume success.
  }

  // POST /igualdad/entrada/importar_registro
  static Future<Map<String, dynamic>> importarRegistroEntrada(
    Map<String, dynamic> body, {
    Uint8List? csvBytes,
    String? fileName,
  }) async {
    final fields = <String, String>{};
    body.forEach((key, value) {
      if (value == null) return;
      if (value is bool) {
        fields[key] = value ? 'true' : 'false';
      } else {
        fields[key] = value.toString();
      }
    });

    ApiService? svc = ApiService.instance;
    if (svc == null) {
      final ctx = globalNavigatorKey.currentContext;
      if (ctx != null) {
        try {
          svc = Provider.of<ApiService>(ctx, listen: false);
        } catch (_) {}
      }
    }

    dynamic res;
    if (svc != null && csvBytes != null && fileName != null) {
      final upload = await svc.client.postMultipart(
        '/igualdad/entrada/importar_registro',
        fields: fields,
        fileFieldName: 'file',
        fileName: fileName,
        fileBytes: csvBytes,
      );
      if (!upload.ok) {
        throw Exception('Error ${upload.statusCode}: ${upload.body ?? upload.error}');
      }
      res = upload.body;
    } else if (svc != null) {
      final jsonRes = await svc.client.post('/igualdad/entrada/importar_registro', jsonBody: body);
      if (!jsonRes.ok) {
        throw Exception('Error ${jsonRes.statusCode}: ${jsonRes.body ?? jsonRes.error}');
      }
      res = jsonRes.body;
    } else if (csvBytes != null && fileName != null) {
      final uri = _baseUri.replace(path: '/igualdad/entrada/importar_registro');
      final request = http.MultipartRequest('POST', uri);
      fields.forEach((key, value) => request.fields[key] = value);
      request.files.add(http.MultipartFile.fromBytes('file', csvBytes, filename: fileName));
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        res = _decodeBody(response.body);
      } else {
        throw Exception('Error ${response.statusCode}: ${response.body}');
      }
    } else {
      res = await _doPost('/igualdad/entrada/importar_registro', jsonBody: body);
    }

    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    throw Exception('Respuesta inesperada al importar registro de entrada');
  }

  static dynamic _decodeBody(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  // GET /igualdad/stock_resumen
  static Future<Map<String, dynamic>> getStockResumen() async {
    final body = await _doGet('/igualdad/stock_resumen');
    return Map<String, dynamic>.from(body as Map);
  }

  // GET /igualdad/idim_activo
  static Future<String?> getIdimActivo() async {
    try {
      final body = await _doGet('/igualdad/idim_activo');
      return (body as Map)['idim'] as String?;
    } catch (e) {
      // If the endpoint returns 404 via ApiClient it will surface as exception
      // so map that to null to keep previous behaviour.
      return null;
    }
  }

  // GET /igualdad/opciones_registro
  static Future<Map<String, dynamic>> getOpcionesRegistro() async {
    final body = await _doGet('/igualdad/opciones_registro');
    return Map<String, dynamic>.from(body as Map);
  }

  // POST /igualdad/registrar_smartphone
  static Future<void> registrarSmartphone(Map<String, dynamic> body) async {
    await _doPost('/igualdad/registrar_smartphone', jsonBody: body);
    // when using ApiClient, errors are thrown as ApiResult.ok == false; the
    // helper will throw on non-2xx codes, so if we get here it's ok.
  }

  // Manual override endpoints for Igualdad dashboard adjustments
  static Future<void> registrarEnviadoVodafone(Map<String, dynamic> body) async {
    await _postManualAdjustment('enviado_vodafone', body);
  }

  static Future<void> registrarEquiposNuevos(Map<String, dynamic> body) async {
    await _postManualAdjustment('equipos_nuevos', body);
  }

  static Future<void> registrarIrrecuperablesGeneral(Map<String, dynamic> body) async {
    await _postManualAdjustment('irrecuperables_general', body);
  }

  static Future<void> registrarIrrecuperables(Map<String, dynamic> body) async {
    await _postManualAdjustment('irrecuperables', body);
  }

  static Future<void> registrarEnDiagnostico(Map<String, dynamic> body) async {
    await _postManualAdjustment('en_diagnostico', body);
  }

  // POST /igualdad/registrar_irrecuperable_dispositivo
  /// Registra un dispositivo individual (SM o PULSERA) como irrecuperable.
  /// No incrementa IDIM_Devoluciones; el conteo aparece en ResumenSemanal
  /// bajo la categoría "Irrecuperables".
  static Future<void> registrarIrrecuperableDispositivo(
    Map<String, dynamic> body,
  ) async {
    await _doPost('/igualdad/registrar_irrecuperable_dispositivo', jsonBody: body);
  }

  static Future<void> registrarServiciosAdicionales(Map<String, dynamic> body) async {
    await _postManualAdjustment('servicios_adicionales', body);
  }

  /// GET /igualdad/registro/buscar?imei=...
  static Future<List<Map<String, dynamic>>> buscarRegistroEntrada({
    required String imei,
    bool exact = true,
    int limit = 20,
    String? numeroPedido,
    String? origen,
  }) async {
    final query = <String, String>{
      'imei': imei,
      'limit': limit.clamp(1, 100).toString(),
      'exact': exact ? '1' : '0',
    };
    if (numeroPedido != null && numeroPedido.isNotEmpty) {
      query['numero_pedido'] = numeroPedido;
    }
    if (origen != null && origen.isNotEmpty) {
      query['origen'] = origen;
    }
    final path = Uri(path: '/igualdad/registro/buscar', queryParameters: query).toString();
    final body = await _doGet(path);
    if (body is Map && body['data'] is List) {
      return List<Map<String, dynamic>>.from(
        (body['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    if (body is List) {
      return List<Map<String, dynamic>>.from(body.map((e) => Map<String, dynamic>.from(e as Map)));
    }
    return const [];
  }

  /// GET /igualdad/ultimos_smartphones?page=&size=
  static Future<PagedResponse<Smartphone>> getUltimosSmartphones({
    int page = 1,
    int size = 10,
    String? query,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'size': size.toString(),
    };
    if (query != null && query.trim().isNotEmpty) {
      params['q'] = query.trim();
    }
    final uri = Uri(path: '/igualdad/ultimos_smartphones', queryParameters: params);
    final body = await _doGet(uri.toString());
    return PagedResponse.fromJson(Map<String, dynamic>.from(body as Map), (j) => Smartphone.fromJson(j));
  }

  // DELETE /igualdad/smartphone/:id
  static Future<void> deleteSmartphone(int id) async {
    await _doDelete('/igualdad/smartphone/$id');
  }

  // PUT /igualdad/smartphone/:id
  static Future<void> updateSmartphone(int id, Map<String, dynamic> body) async {
    await _doPut('/igualdad/smartphone/$id', jsonBody: body);
  }

  // POST /igualdad/registrar_boton
  static Future<void> registrarBoton(String tipo) async {
    await _doPost('/igualdad/registrar_boton', jsonBody: {'registro': tipo});
  }

  // GET /igualdad/registros/botones
  static Future<List<dynamic>> getRegistrosBotones() async {
    final body = await _doGet('/igualdad/registros/botones');
    return List<dynamic>.from(body as List);
  }

  // DELETE /igualdad/boton/:tipo
  static Future<void> deleteBoton(String tipo) async {
    await _doDelete('/igualdad/boton/$tipo');
  }

  // POST /igualdad/registrar_powerbank
  static Future<void> registrarPowerbank(String tipo) async {
    await _doPost('/igualdad/registrar_powerbank', jsonBody: {'registro': tipo});
  }

  // GET /igualdad/registro_powerbanks
  static Future<List<dynamic>> getRegistroPowerbanks() async {
    final body = await _doGet('/igualdad/registro_powerbanks');
    return List<dynamic>.from(body as List);
  }

  // DELETE /igualdad/powerbank/:tipo
  static Future<void> deletePowerbank(String tipo) async {
    await _doDelete('/igualdad/powerbank/$tipo');
  }

  // POST /igualdad/registrar_pulsera
  static Future<void> registrarPulsera(Map<String, dynamic> body) async {
    await _doPost('/igualdad/registrar_pulsera', jsonBody: body);
  }

  static Future<Map<String, dynamic>> getUltimasPulseras({
    int page = 1,
    int perPage = 10,
    String? query,
  }) async {
    String q = '?page=${page.toString()}&per_page=${perPage.toString()}';
    if (query != null && query.trim().isNotEmpty) {
      q += '&q=${Uri.encodeQueryComponent(query.trim())}';
    }
    final body = await _doGet('/igualdad/pulseras$q');
    return Map<String, dynamic>.from(body as Map);
  }

  // DELETE /igualdad/pulsera/:id
  static Future<void> deletePulsera(int id) async {
    await _doDelete('/igualdad/pulsera/$id');
  }

  // PUT /igualdad/pulsera/:id/edit
  static Future<void> updatePulsera(int id, Map<String, dynamic> body) async {
    await _doPut('/igualdad/pulsera/$id/edit', jsonBody: body);
  }

  // POST /igualdad/cerrar_expedicion
  static Future<void> cerrarExpedicion(
    String tipo,
    String numeroExpedicion,
    String jjd,
  ) async {
    await _doPost('/igualdad/cerrar_expedicion', jsonBody: {
      'tipo': tipo,
      'numero_expedicion': numeroExpedicion,
      'jjd': jjd,
    });
  }

  // GET /igualdad/expediciones_cerradas
  static Future<List<dynamic>> getExpedicionesCerradas() async {
    final body = await _doGet('/igualdad/expediciones_cerradas');
    return List<dynamic>.from(body as List);
  }

  // PUT /igualdad/expediciones_cerradas/:id
  static Future<void> updateExpedicion(
    int id,
    Map<String, dynamic> body,
  ) async {
    await _doPut('/igualdad/expediciones_cerradas/$id', jsonBody: body);
  }

  /// Historial de expediciones antiguas (sólo SMA, SMV, Pulseras)
  static Future<List<dynamic>> getHistorialExpedicionesOld() async {
    final body = await _doGet('/igualdad/historial_expediciones_old');
    return List<dynamic>.from(body as List);
  }

  // GET /igualdad/exportar_expedicion?codigo=...
  static Future<ExportExpedicionResult> exportExpediciones(
    String codigo, {
    bool marcarEnviado = false,
    String? observaciones,
  }) async {
    final queryParams = <String, String>{'codigo': codigo};
    if (marcarEnviado) {
      queryParams['marcar_enviado'] = '1';
      final note = observaciones?.trim();
      if (note != null && note.isNotEmpty) {
        queryParams['observaciones'] = note;
      }
    }
    final queryString = Uri(queryParameters: queryParams).query;
    final pathWithQuery = '/igualdad/exportar_expedicion${queryString.isNotEmpty ? '?$queryString' : ''}';

    // Prefer ApiClient.getBytes when available so Authorization header/cookies
    // are sent. Fallback to raw http when ApiClient isn't accessible.
    ApiService? svc = ApiService.instance;
    if (svc == null) {
      final ctx = globalNavigatorKey.currentContext;
      if (ctx != null) {
        try {
          svc = Provider.of<ApiService>(ctx, listen: false);
        } catch (_) {}
      }
    }
    if (svc != null) {
      final r = await svc.client.getBytes(pathWithQuery);
      if (r.ok && r.body is Uint8List) {
        final header = _extractObservacionesHeader(r.headers);
        return ExportExpedicionResult(r.body as Uint8List, observaciones: header);
      }
      throw Exception('Error exportando ($codigo): ${r.error ?? r.body}');
    }

    final uri = _baseUri.replace(
      path: '/igualdad/exportar_expedicion',
      queryParameters: queryParams,
    );
    final res = await http.get(uri);
    if (res.statusCode == 200) {
      final header = _extractObservacionesHeader(res.headers);
      return ExportExpedicionResult(res.bodyBytes, observaciones: header);
    }
    final msg = res.body.isNotEmpty ? (jsonDecode(res.body)['error'] ?? res.body) : 'HTTP ${res.statusCode}';
    throw Exception('Error exportando ($codigo): $msg');
  }

  // ------------------ Helpers that prefer ApiClient when available ------------------

  static Future<void> _postManualAdjustment(String pathSegment, Map<String, dynamic> body) async {
    await _doPost('/igualdad/$pathSegment', jsonBody: body);
  }

  static Future<dynamic> _doGet(String pathWithQuery) async {
    // pathWithQuery should start with '/'
    // Try the global instance first, then navigator context, then fallback.
    ApiService? svc = ApiService.instance;
    if (svc == null) {
      final ctx = globalNavigatorKey.currentContext;
      if (ctx != null) {
        try {
          svc = Provider.of<ApiService>(ctx, listen: false);
        } catch (_) {}
      }
    }
    if (svc != null) {
      final res = await svc.client.get(pathWithQuery);
      if (res.ok) return res.body;
      throw Exception('Error ${res.statusCode}: ${res.body ?? res.error}');
    }
    // Fallback to raw http
    final uri = _baseUri.replace(path: pathWithQuery.split('?').first, queryParameters: (pathWithQuery.contains('?') ? Uri.splitQueryString(pathWithQuery.split('?').last) : null));
    final res = await http.get(uri);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        return jsonDecode(res.body);
      } catch (_) {
        return res.body;
      }
    }
    throw Exception('Error ${res.statusCode}: ${res.body}');
  }

  static Future<dynamic> _doPost(String path, {dynamic jsonBody}) async {
    ApiService? svc = ApiService.instance;
    if (svc == null) {
      final ctx = globalNavigatorKey.currentContext;
      if (ctx != null) {
        try {
          svc = Provider.of<ApiService>(ctx, listen: false);
        } catch (_) {}
      }
    }
    if (svc != null) {
      final res = await svc.client.post(path, jsonBody: jsonBody);
      if (res.ok) return res.body;
      throw Exception('Error ${res.statusCode}: ${res.body ?? res.error}');
    }
    final uri = _baseUri.replace(path: path);
    final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonBody != null ? jsonEncode(jsonBody) : null);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      try {
        return jsonDecode(resp.body);
      } catch (_) {
        return resp.body;
      }
    }
    throw Exception('Error ${resp.statusCode}: ${resp.body}');
  }

  static String? _extractObservacionesHeader(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return null;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'x-resumen-observaciones') {
        final value = entry.value.trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  static Future<dynamic> _doPut(String path, {dynamic jsonBody}) async {
    ApiService? svc = ApiService.instance;
    if (svc == null) {
      final ctx = globalNavigatorKey.currentContext;
      if (ctx != null) {
        try {
          svc = Provider.of<ApiService>(ctx, listen: false);
        } catch (_) {}
      }
    }
    if (svc != null) {
      try {
        final res = await svc.client.put(path, jsonBody: jsonBody);
        if (res.ok) return res.body;
      } catch (_) {}
      // fall through to http fallback
    }
    final uri = _baseUri.replace(path: path);
    final resp = await http.put(uri, headers: {'Content-Type': 'application/json'}, body: jsonBody != null ? jsonEncode(jsonBody) : null);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      try {
        return jsonDecode(resp.body);
      } catch (_) {
        return resp.body;
      }
    }
    throw Exception('Error ${resp.statusCode}: ${resp.body}');
  }

  static Future<void> _doDelete(String path) async {
    ApiService? svc = ApiService.instance;
    if (svc == null) {
      final ctx = globalNavigatorKey.currentContext;
      if (ctx != null) {
        try {
          svc = Provider.of<ApiService>(ctx, listen: false);
        } catch (_) {}
      }
    }
    if (svc != null) {
      try {
        final res = await svc.client.delete(path);
        if (res.ok) return;
      } catch (_) {}
      // fall through to http fallback
    }
    final uri = _baseUri.replace(path: path);
    final resp = await http.delete(uri);
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw Exception('Error ${resp.statusCode}: ${resp.body}');
  }
}
