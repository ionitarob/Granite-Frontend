import '../api_client.dart';
import '../models/server_models.dart';
import 'api_service.dart';

class ServerRegistroResult {
  final String? id;
  final String serverSerial;
  final int piezasCount;

  const ServerRegistroResult({required this.serverSerial, this.id, required this.piezasCount});

  factory ServerRegistroResult.fromResponse(dynamic body, {required ServerRegistro fallback}) {
    String? id;
    int count = fallback.piezas.length;
    if (body is Map) {
      final rawId = body['id'] ?? body['_id'] ?? body['registro_id'];
      if (rawId != null) id = rawId.toString();
      final piezasRaw = body['piezas_count'] ?? body['piezas'];
      if (piezasRaw is int) {
        count = piezasRaw;
      } else if (piezasRaw is String) {
        count = int.tryParse(piezasRaw) ?? count;
      } else if (piezasRaw is List) {
        count = piezasRaw.length;
      }
    }
    return ServerRegistroResult(serverSerial: fallback.serverSerial, id: id, piezasCount: count);
  }
}

class ServerRegistroService {
  const ServerRegistroService();

  static const _basePath = '/servers/servidores';

  ApiClient get _client {
    final svc = ApiService.instance;
    if (svc == null) {
      throw StateError('ApiService is not initialized');
    }
    return svc.client;
  }

  Future<List<ServerRegistroResult>> guardarRegistros({
    required List<ServerRegistro> registros,
    required String previ,
    required String cliente,
    required String operario,
    required String descripcion,
  }) async {
    if (registros.isEmpty) return const [];
    final results = <ServerRegistroResult>[];
    for (final registro in registros) {
      final payload = <String, dynamic>{
        'previ': previ,
        'cliente': cliente,
        'operario': operario,
        'desc': descripcion,
        ...registro.toJson(),
      };
      final res = await _client.post(_basePath, jsonBody: payload);
      if (!res.ok) {
        throw _asException(res, fallback: 'Error guardando ${registro.serverSerial}');
      }
      results.add(ServerRegistroResult.fromResponse(res.body, fallback: registro));
    }
    return results;
  }

  Exception _asException(ApiResult result, {String? fallback}) {
    final msg = _extractMessage(result) ?? fallback ?? 'Error en la solicitud (${result.statusCode})';
    return Exception(msg);
  }

  String? _extractMessage(ApiResult result) {
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
}
