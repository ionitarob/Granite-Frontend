import 'dart:async';
import 'dart:io';

import '../api_client.dart';
import '../models/previ_registro.dart';
import 'api_service.dart';

class PreviService {
  const PreviService();

  static const _basePath = '/servidores/calidad';

  static ApiClient get _client {
    final svc = ApiService.instance;
    if (svc == null) {
      throw StateError('ApiService is not initialized');
    }
    return svc.client;
  }

  static Exception _asException(ApiResult result, {String? fallback}) {
    final msg = _extractMessage(result) ?? fallback ?? 'Request failed (${result.statusCode})';
    return Exception(msg);
  }

  static String? _extractMessage(ApiResult result) {
    final body = result.body;
    if (body is Map) {
      for (final key in ['detail', 'message', 'error']) {
        final value = body[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    } else if (body is String && body.trim().isNotEmpty) {
      return body.trim();
    }
    if (result.error != null && result.error!.trim().isNotEmpty) {
      return result.error!.trim();
    }
    return null;
  }

  static String _buildPath(String path, [Map<String, String>? query]) {
    if (query == null || query.isEmpty) return path;
    return Uri(path: path, queryParameters: query).toString();
  }

  Future<int?> crearRegistro(PreviRegistro reg, List<File> images) async {
    final attachments = <MultipartAttachment>[];
    for (var i = 0; i < images.length; i++) {
      final file = images[i];
      final fileName = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'imagen${i + 1}.jpg';
      final bytes = await file.readAsBytes();
      attachments.add(MultipartAttachment(fieldName: 'imagen${i + 1}', fileName: fileName, bytes: bytes));
    }

    final res = await _client.postMultipart(
      _basePath,
      fields: reg.toFields(),
      files: attachments.isEmpty ? null : attachments,
    );
    if (!res.ok) {
      throw _asException(res, fallback: 'Error creando registro');
    }
    final body = res.body;
    if (body is Map) {
      final id = body['id'];
      if (id is int) return id;
      if (id is String) return int.tryParse(id);
    }
    return null;
  }

  Future<List<PreviRegistro>> listar({String? from, String? to, String? operario}) async {
    final params = <String, String>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (operario != null && operario.isNotEmpty) 'operario': operario,
    };

    final res = await _client.get(_buildPath(_basePath, params.isEmpty ? null : params));
    if (!res.ok) {
      throw _asException(res, fallback: 'Error listando registros');
    }
    final body = res.body;
    if (body is! Map) return const [];
    final records = body['records'];
    if (records is! List) return const [];
    return records.whereType<Map>().map((e) => PreviRegistro.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<PreviRegistro> obtener(int id) async {
    final res = await _client.get('$_basePath/$id');
    if (!res.ok) {
      throw _asException(res, fallback: 'Error obteniendo registro');
    }
    final body = res.body;
    if (body is Map) {
      return PreviRegistro.fromJson(body.cast<String, dynamic>());
    }
    throw Exception('Respuesta inválida');
  }

  Future<void> eliminar(int id) async {
    final res = await _client.delete('$_basePath/$id');
    if (!res.ok) {
      throw _asException(res, fallback: 'Error eliminando registro');
    }
  }

  Future<void> patch(int id, {String? descripcion, String? operariosSoporte}) async {
    final payload = <String, dynamic>{};
    if (descripcion != null) payload['desc'] = descripcion;
    if (operariosSoporte != null) payload['opsoporte'] = operariosSoporte;
    if (payload.isEmpty) return;
    final res = await _client.patch('$_basePath/$id', jsonBody: payload);
    if (!res.ok) {
      throw _asException(res, fallback: 'Error actualizando registro');
    }
  }

  Future<List<Map<String, dynamic>>> listarEmpleadosSinAmazon() async {
    try {
      final res = await _client.get('$_basePath/empleados').timeout(const Duration(seconds: 12));
      if (!res.ok) {
        throw _asException(res, fallback: 'No se pudieron obtener los empleados');
      }
      final body = res.body;
      if (body is! Map) throw Exception('Formato inesperado');
      final raw = body['empleados'];
      if (raw is List) {
        return raw.map((entry) {
          if (entry is Map) {
            return entry.map((k, v) => MapEntry(k.toString(), v));
          }
          return <String, dynamic>{'valor': entry.toString()};
        }).cast<Map<String, dynamic>>().toList();
      }
      throw Exception('Formato inesperado');
    } on TimeoutException {
      throw Exception('Timeout consultando empleados');
    }
  }
}
