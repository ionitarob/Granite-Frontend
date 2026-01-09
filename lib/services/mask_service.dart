import '../api_client.dart';
import 'api_service.dart';

class MaskService {
  static const String _basePath = '/serials';

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

  static String _pathWithQuery(String path, Map<String, String> query) {
    if (query.isEmpty) return path;
    return Uri(path: path, queryParameters: query).toString();
  }

  // List masks with optional query
  static Future<List<Map<String, dynamic>>> list({
    String q = '',
    int limit = 200,
  }) async {
    final path = _pathWithQuery(
      '$_basePath/masks',
      {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'limit': '$limit',
      },
    );
    final res = await _client.get(path);
    if (!res.ok) {
      throw _asException(res, fallback: 'Failed to fetch masks');
    }
    final body = res.body;
    if (body is! Map) return const [];
    final items = body['masks'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => {
              'id': e['id'],
              'mask': e['mask']?.toString() ?? '',
            })
        .toList();
  }

  static Future<void> add(String mask) async {
    final res = await _client.post(
      '$_basePath/masks',
      jsonBody: {'mask': mask.trim()},
    );
    if (!res.ok) {
      throw _asException(res, fallback: 'Failed to add mask');
    }
  }

  static Future<void> update(int id, String newMask) async {
    final res = await _client.put(
      '$_basePath/masks/$id',
      jsonBody: {'mask': newMask.trim()},
    );
    if (!res.ok) {
      throw _asException(res, fallback: 'Failed to update mask');
    }
  }

  static Future<void> remove(int id) async {
    final res = await _client.delete('$_basePath/masks/$id');
    if (!res.ok) {
      throw _asException(res, fallback: 'Failed to delete mask');
    }
  }

  static Future<({bool suspicious, List<Map<String, dynamic>> matches})>
  checkSerial(String serial) async {
    final res = await _client.post(
      '$_basePath/masks/check',
      jsonBody: {'serial': serial.trim()},
    );
    if (!res.ok) {
      throw _asException(res, fallback: 'Failed to check serial');
    }
    final body = res.body;
    if (body is! Map) {
      return (suspicious: false, matches: const <Map<String, dynamic>>[]);
    }
    final rawMatches = body['matches'];
    final matches = (rawMatches is List)
        ? rawMatches
            .whereType<Map>()
            .map<Map<String, dynamic>>(
              (e) => {
                'mask': e['mask']?.toString() ?? '',
                'reason': e['reason']?.toString() ?? '',
                'score': (e['score'] is num) ? (e['score'] as num).toDouble() : null,
              },
            )
            .toList()
        : <Map<String, dynamic>>[];
    final suspiciousFlag = body['suspicious'] == true || matches.isNotEmpty;
    return (suspicious: suspiciousFlag, matches: matches);
  }
}
