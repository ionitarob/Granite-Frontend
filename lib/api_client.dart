import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiResult {
  final bool ok;
  final int statusCode;
  final dynamic body;
  final String? error;
  final Map<String, String>? headers;

  ApiResult(this.ok, this.statusCode, {this.body, this.error, this.headers});
}

class MultipartAttachment {
  final String fieldName;
  final String fileName;
  final List<int> bytes;

  const MultipartAttachment({
    required this.fieldName,
    required this.fileName,
    required this.bytes,
  });
}

class ApiClient {
  final String baseUrl;
  final http.Client _client;
  final FlutterSecureStorage _storage;

  // In-memory cookies map
  final Map<String, String> _cookies = {};
  String? _accessToken;
  DateTime? _accessTokenExpiry;
  void Function(ApiResult result)? onUnauthorized;

  bool get hasAccessToken => _accessToken != null && _accessToken!.isNotEmpty;
  bool get hasSessionCookie => _cookies.isNotEmpty;

  static const _cookieStorageKey = 'session_cookies_v1';

  /// If [allowBadCertificateForHosts] is provided and the app is running in
  /// debug mode, the internal HttpClient will accept self-signed certificates
  /// for the listed hosts. This is strictly for development/testing and is
  /// guarded by `kDebugMode` so it won't run in release builds.
  ApiClient({
    required this.baseUrl,
    http.Client? client,
    FlutterSecureStorage? storage,
    List<String>? allowBadCertificateForHosts,
    this.onUnauthorized,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _client = client ?? _createDefaultClient(allowBadCertificateForHosts);

  static http.Client _createDefaultClient(
    List<String>? allowBadCertificateForHosts,
  ) {
    if (!kDebugMode) return http.Client();
    final inner = HttpClient();
    inner.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
          // In debug builds allow either any host (if list is null/empty) or the
          // specific hosts provided. This must NOT be enabled in production.
          if (allowBadCertificateForHosts == null ||
              allowBadCertificateForHosts.isEmpty) {
            return true;
          }
          return allowBadCertificateForHosts.contains(host);
        };
    return IOClient(inner);
  }

  Uri _uri(String path) => Uri.parse(baseUrl + path);

  Future<ApiResult> login(
    String username,
    String password, {
    bool persistSession = false,
  }) async {
    final uri = _uri('/api/auth/login/');
    try {
      final resp = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      _updateCookiesFromResponse(resp);

      // Try to extract access token from response body if present (common fields)
      try {
        if (resp.body.isNotEmpty) {
          final parsed = jsonDecode(resp.body);
          final token = _extractTokenFromParsed(parsed);
          if (token != null && token.isNotEmpty) {
            _accessToken = token;
            if (kDebugMode) {
              try {
                debugPrint(
                  'ApiClient: extracted access token (${_accessToken!.length} chars)',
                );
                debugPrint('ApiClient: token => ${_accessToken!}');
              } catch (_) {}
            }
          }
        }
      } catch (_) {
        // ignore parse errors here
      }

      if (persistSession) {
        await _saveCookiesToStorage();
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        dynamic body;
        if (resp.body.isNotEmpty) {
          try {
            body = jsonDecode(resp.body);
          } catch (e) {
            body = resp.body;
          }
        }
        return ApiResult(true, resp.statusCode, body: body);
      } else {
        return ApiResult(
          false,
          resp.statusCode,
          error: 'HTTP ${resp.statusCode}',
        );
      }
    } catch (e) {
      return ApiResult(false, -1, error: e.toString());
    }
  }

  Future<ApiResult> me() async {
    final uri = _uri('/api/auth/me/');
    try {
      final headers = _authHeaders();
      _logRequestHeaders('GET', uri, headers);
      final resp = await _client.get(uri, headers: headers);
      _updateCookiesFromResponse(resp);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        dynamic body;
        if (resp.body.isNotEmpty) {
          try {
            body = jsonDecode(resp.body);
          } catch (e) {
            body = resp.body;
          }
        }
        return ApiResult(true, resp.statusCode, body: body);
      } else {
        return ApiResult(
          false,
          resp.statusCode,
          error: 'HTTP ${resp.statusCode}',
        );
      }
    } catch (e) {
      return ApiResult(false, -1, error: e.toString());
    }
  }

  Future<ApiResult> logout() async {
    final uri = _uri('/api/auth/logout/');
    try {
      final headers = _authHeaders();
      _logRequestHeaders('POST', uri, headers);
      final resp = await _client.post(uri, headers: headers);
      _updateCookiesFromResponse(resp);
      // clear local cookies on 200
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _cookies.clear();
        _accessToken = null;
        await _storage.delete(key: _cookieStorageKey);
        return ApiResult(true, resp.statusCode);
      }
      return ApiResult(false, resp.statusCode);
    } catch (e) {
      return ApiResult(false, -1, error: e.toString());
    }
  }

  Map<String, String> _authHeaders() {
    final headers = <String, String>{'Accept': 'application/json'};

    if (_accessToken != null && _accessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${_accessToken!}';
      // Do NOT send cookies if we have a valid access token.
      // This prevents Django SessionAuthentication from kicking in and enforcing CSRF.
    } else {
      // Fallback to session cookies if no token
      final cookie = _buildCookieHeader();
      if (cookie.isNotEmpty) headers['Cookie'] = cookie;

      // Add CSRF token if present in cookies (Django requirement for session auth)
      if (_cookies.containsKey('csrftoken')) {
        headers['X-CSRFToken'] = _cookies['csrftoken']!;
      }
    }
    return headers;
  }

  String _buildCookieHeader() {
    if (_cookies.isEmpty) return '';
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void _updateCookiesFromResponse(http.Response resp) {
    try {
      // The server may return one or more Set-Cookie headers. http merges multiple set-cookie values
      // into a single header value separated by commas. We'll do a simple split and parse name=value pairs.
      final sc = resp.headers['set-cookie'];
      if (sc == null || sc.isEmpty) return;
      // Split by comma+space but handle simple cases.
      final parts = sc.split(RegExp(r', (?=[^;+=]*=)'));
      for (final part in parts) {
        final segs = part.split(';');
        if (segs.isEmpty) continue;
        final nameValue = segs[0];
        final nvParts = nameValue.split('=');
        if (nvParts.length < 2) continue;
        final name = nvParts[0].trim();
        final value = nvParts.sublist(1).join('=');
        _cookies[name] = value;
      }
    } catch (e) {
      if (kDebugMode) print('Failed to parse cookies: $e');
    }
  }

  Future<void> _saveCookiesToStorage() async {
    if (_cookies.isEmpty) return;
    // Save as header string
    final cookieStr = _buildCookieHeader();
    await _storage.write(key: _cookieStorageKey, value: cookieStr);
  }

  Future<void> loadCookiesFromStorage() async {
    final s = await _storage.read(key: _cookieStorageKey);
    if (s == null || s.isEmpty) return;
    // parse cookie header string like "k1=v1; k2=v2"
    final parts = s.split(';');
    for (final p in parts) {
      final kv = p.split('=');
      if (kv.length < 2) continue;
      final name = kv[0].trim();
      final value = kv.sublist(1).join('=').trim();
      _cookies[name] = value;
    }
  }

  String? _extractTokenFromParsed(dynamic parsed) {
    try {
      if (parsed == null) return null;
      // If the parsed response is a string, assume it's already the token
      if (parsed is String) return parsed;

      if (parsed is Map) {
        // Common top-level keys that may contain the token
        final candidates = [
          'access_token',
          'access',
          'token',
          'auth_token',
          'jwt',
          'id_token',
        ];
        for (final k in candidates) {
          if (!parsed.containsKey(k)) continue;
          final v = parsed[k];
          if (v == null) continue;
          if (v is String) {
            if (v.contains('.')) return v; // likely a JWT
            // otherwise return string (less ideal)
            return v;
          }
          if (v is Map) {
            // nested structure, try to find nested token strings
            for (final nk in ['token', 'access_token', 'jwt', 'value', 'raw']) {
              if (v.containsKey(nk) && v[nk] is String) {
                final s = v[nk] as String;
                if (s.contains('.')) return s;
                return s;
              }
            }
          }
        }

        // Fallback: try to find any string value that looks like a JWT (has two dots)
        for (final entry in parsed.entries) {
          final v = entry.value;
          if (v is String && v.split('.').length == 3) return v;
        }
      }
    } catch (_) {}
    return null;
  }

  DateTime? get accessTokenExpiry => _accessTokenExpiry;
  String? get accessToken => _accessToken;

  void _setAccessTokenAndExpiry(String? token) {
    _accessToken = token;
    _accessTokenExpiry = null;
    try {
      if (token != null && token.split('.').length == 3) {
        final parts = token.split('.');
        final payload = parts[1];
        String normalized = base64Url.normalize(payload);
        final decoded = utf8.decode(base64Url.decode(normalized));
        final Map<String, dynamic> map = jsonDecode(decoded);
        if (map.containsKey('exp')) {
          final exp = map['exp'];
          if (exp is int) {
            _accessTokenExpiry = DateTime.fromMillisecondsSinceEpoch(
              exp * 1000,
            );
          } else if (exp is String) {
            final ei = int.tryParse(exp);
            if (ei != null) {
              _accessTokenExpiry = DateTime.fromMillisecondsSinceEpoch(
                ei * 1000,
              );
            }
          }
        }
      }
    } catch (_) {
      // ignore any parse errors
    }
  }

  bool isTokenExpired({int bufferSeconds = 0}) {
    if (_accessTokenExpiry == null) return true;
    final now = DateTime.now().toUtc();
    final expiry = _accessTokenExpiry!.toUtc();
    return now.add(Duration(seconds: bufferSeconds)).isAfter(expiry);
  }

  /// Set the access token (in-memory) so other requests will include it.
  void setAccessToken(String? token) {
    _setAccessTokenAndExpiry(token);
  }

  /// Public wrapper to extract token from a parsed response object.
  String? extractTokenFromParsed(dynamic parsed) =>
      _extractTokenFromParsed(parsed);

  /// Try to refresh access token using a refresh token by calling the
  /// standard refresh endpoint. Returns true if a new access token was
  /// obtained and stored in memory.
  Future<bool> refreshAccessToken(String refreshToken) async {
    try {
      final uri = _uri('/api/auth/refresh/');
      final headers = _authHeaders();
      headers['Content-Type'] = 'application/json';

      final resp = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode({'refresh': refreshToken}),
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        try {
          final parsed = jsonDecode(resp.body);
          final token = _extractTokenFromParsed(parsed);
          if (token != null && token.isNotEmpty) {
            _accessToken = token;
            return true;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return false;
  }

  /// Authenticated GET helper that returns an ApiResult wrapping parsed JSON
  /// when possible. Path should start with a leading slash (e.g. '/amz/grading/options').
  Future<ApiResult> get(String path) async {
    final uri = _uri(path);
    try {
      final headers = _authHeaders();
      _logRequestHeaders('GET', uri, headers);
      final resp = await _client.get(uri, headers: headers);
      _updateCookiesFromResponse(resp);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        dynamic body;
        if (resp.body.isNotEmpty) {
          try {
            body = jsonDecode(resp.body);
          } catch (e) {
            body = resp.body;
          }
        }
        return ApiResult(true, resp.statusCode, body: body);
      }
      dynamic errBody;
      if (resp.body.isNotEmpty) {
        try {
          errBody = jsonDecode(resp.body);
        } catch (_) {
          errBody = resp.body;
        }
      }
      final result = ApiResult(
        false,
        resp.statusCode,
        body: errBody,
        error: 'HTTP ${resp.statusCode}',
      );
      _emitUnauthorized(result);
      return result;
    } catch (e) {
      return ApiResult(false, -1, error: e.toString());
    }
  }

  /// GET helper that returns raw bytes (useful for downloads such as
  /// Excel exports). This avoids attempting to decode the response body as
  /// JSON and gives callers the raw bytes via `body` when `ok` is true.
  Future<ApiResult> getBytes(String path) async {
    final uri = _uri(path);
    try {
      final headers = _authHeaders();
      _logRequestHeaders('GET', uri, headers);
      final resp = await _client.get(uri, headers: headers);
      _updateCookiesFromResponse(resp);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return ApiResult(
          true,
          resp.statusCode,
          body: resp.bodyBytes,
          headers: resp.headers,
        );
      }
      final result = ApiResult(
        false,
        resp.statusCode,
        error: 'HTTP ${resp.statusCode}',
        body: resp.bodyBytes,
        headers: resp.headers,
      );
      _emitUnauthorized(result);
      return result;
    } catch (e) {
      return ApiResult(false, -1, error: e.toString());
    }
  }

  /// Authenticated POST helper. If [jsonBody] is provided it will be
  /// encoded as JSON and Content-Type set accordingly.
  Future<ApiResult> post(
    String path, {
    dynamic jsonBody,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = _uri(path);
    try {
      final headers = _authHeaders();
      if (extraHeaders != null) headers.addAll(extraHeaders);
      if (jsonBody != null) headers['Content-Type'] = 'application/json';
      _logRequestHeaders('POST', uri, headers);
      final body = jsonBody != null ? jsonEncode(jsonBody) : null;
      final resp = await _client.post(uri, headers: headers, body: body);
      _updateCookiesFromResponse(resp);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        dynamic parsed;
        if (resp.body.isNotEmpty) {
          try {
            parsed = jsonDecode(resp.body);
          } catch (e) {
            parsed = resp.body;
          }
        }
        return ApiResult(true, resp.statusCode, body: parsed);
      }
      // attempt to parse error body
      dynamic errBody;
      if (resp.body.isNotEmpty) {
        try {
          errBody = jsonDecode(resp.body);
        } catch (_) {
          errBody = resp.body;
        }
      }
      final result = ApiResult(
        false,
        resp.statusCode,
        body: errBody,
        error: 'HTTP ${resp.statusCode}',
      );
      _emitUnauthorized(result);
      return result;
    } catch (e) {
      return ApiResult(false, -1, error: e.toString());
    }
  }

  /// Authenticated PUT helper. Mirrors [post] semantics but uses HTTP PUT.
  Future<ApiResult> put(
    String path, {
    dynamic jsonBody,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = _uri(path);
    try {
      final headers = _authHeaders();
      if (extraHeaders != null) headers.addAll(extraHeaders);
      if (jsonBody != null) headers['Content-Type'] = 'application/json';
      _logRequestHeaders('PUT', uri, headers);
      final body = jsonBody != null ? jsonEncode(jsonBody) : null;
      final resp = await _client.put(uri, headers: headers, body: body);
      _updateCookiesFromResponse(resp);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        dynamic parsed;
        if (resp.body.isNotEmpty) {
          try {
            parsed = jsonDecode(resp.body);
          } catch (e) {
            parsed = resp.body;
          }
        }
        return ApiResult(true, resp.statusCode, body: parsed);
      }
      dynamic errBody;
      if (resp.body.isNotEmpty) {
        try {
          errBody = jsonDecode(resp.body);
        } catch (_) {
          errBody = resp.body;
        }
      }
      final result = ApiResult(
        false,
        resp.statusCode,
        body: errBody,
        error: 'HTTP ${resp.statusCode}',
      );
      _emitUnauthorized(result);
      return result;
    } catch (e) {
      return ApiResult(false, -1, error: e.toString());
    }
  }

  /// Authenticated POST helper that returns a StreamedResponse (for SSE/NDJSON).
  /// The caller is responsible for handling the stream.
  Future<http.StreamedResponse> streamPost(
    String path, {
    dynamic jsonBody,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = _uri(path);
    final headers = _authHeaders();
    if (extraHeaders != null) headers.addAll(extraHeaders);
    if (jsonBody != null) headers['Content-Type'] = 'application/json';

    _logRequestHeaders('STREAM-POST', uri, headers);

    final req = http.Request('POST', uri);
    req.headers.addAll(headers);
    if (jsonBody != null) req.body = jsonEncode(jsonBody);

    return _client.send(req);
  }

  /// Authenticated PATCH helper.
  Future<ApiResult> patch(
    String path, {
    dynamic jsonBody,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = _uri(path);
    try {
      final headers = _authHeaders();
      if (extraHeaders != null) headers.addAll(extraHeaders);
      if (jsonBody != null) headers['Content-Type'] = 'application/json';
      _logRequestHeaders('PATCH', uri, headers);
      final body = jsonBody != null ? jsonEncode(jsonBody) : null;
      final resp = await _client.patch(uri, headers: headers, body: body);
      _updateCookiesFromResponse(resp);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        dynamic parsed;
        if (resp.body.isNotEmpty) {
          try {
            parsed = jsonDecode(resp.body);
          } catch (e) {
            parsed = resp.body;
          }
        }
        return ApiResult(true, resp.statusCode, body: parsed);
      }
      dynamic errBody;
      if (resp.body.isNotEmpty) {
        try {
          errBody = jsonDecode(resp.body);
        } catch (_) {
          errBody = resp.body;
        }
      }
      final result = ApiResult(
        false,
        resp.statusCode,
        body: errBody,
        error: 'HTTP ${resp.statusCode}',
      );
      _emitUnauthorized(result);
      return result;
    } catch (e) {
      return ApiResult(false, -1, error: e.toString());
    }
  }

  /// Authenticated DELETE helper. Uses HTTP DELETE and returns parsed body
  /// when possible.
  Future<ApiResult> delete(
    String path, {
    Map<String, String>? extraHeaders,
  }) async {
    final uri = _uri(path);
    try {
      final headers = _authHeaders();
      if (extraHeaders != null) headers.addAll(extraHeaders);
      _logRequestHeaders('DELETE', uri, headers);
      final resp = await _client.delete(uri, headers: headers);
      _updateCookiesFromResponse(resp);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        dynamic parsed;
        if (resp.body.isNotEmpty) {
          try {
            parsed = jsonDecode(resp.body);
          } catch (e) {
            parsed = resp.body;
          }
        }
        return ApiResult(true, resp.statusCode, body: parsed);
      }
      dynamic errBody;
      if (resp.body.isNotEmpty) {
        try {
          errBody = jsonDecode(resp.body);
        } catch (_) {
          errBody = resp.body;
        }
      }
      final result = ApiResult(
        false,
        resp.statusCode,
        body: errBody,
        error: 'HTTP ${resp.statusCode}',
      );
      _emitUnauthorized(result);
      return result;
    } catch (e) {
      return ApiResult(false, -1, error: e.toString());
    }
  }

  /// Send a multipart/form-data POST. Useful when the server expects
  /// form-encoded fields and file uploads. [fields] are form fields,
  /// and [fileBytes]/[fileName] optionally attach a single file under
  /// [fileFieldName] (defaults to 'file').
  Future<ApiResult> postMultipart(
    String path, {
    Map<String, String>? fields,
    String? fileFieldName,
    String? fileName,
    List<int>? fileBytes,
    List<MultipartAttachment>? files,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = _uri(path);
    try {
      final headers = _authHeaders();
      if (extraHeaders != null) headers.addAll(extraHeaders);
      // MultipartRequest expects headers to NOT contain a Content-Type
      // since it will set its own boundary-based content type.
      final req = http.MultipartRequest('POST', uri);
      req.headers.addAll(headers);
      if (fields != null && fields.isNotEmpty) req.fields.addAll(fields);
      if (files != null && files.isNotEmpty) {
        for (final attachment in files) {
          final mf = http.MultipartFile.fromBytes(
            attachment.fieldName,
            attachment.bytes,
            filename: attachment.fileName,
          );
          req.files.add(mf);
        }
      } else if (fileBytes != null && fileName != null) {
        final mf = http.MultipartFile.fromBytes(
          fileFieldName ?? 'file',
          fileBytes,
          filename: fileName,
        );
        req.files.add(mf);
      }
      _logRequestHeaders('MULTIPART-POST', uri, req.headers);
      final streamed = await _client.send(req);
      final resp = await http.Response.fromStream(streamed);
      _updateCookiesFromResponse(resp);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        dynamic parsed;
        if (resp.body.isNotEmpty) {
          try {
            parsed = jsonDecode(resp.body);
          } catch (e) {
            parsed = resp.body;
          }
        }
        return ApiResult(true, resp.statusCode, body: parsed);
      }
      dynamic errBody;
      if (resp.body.isNotEmpty) {
        try {
          errBody = jsonDecode(resp.body);
        } catch (_) {
          errBody = resp.body;
        }
      }
      final result = ApiResult(
        false,
        resp.statusCode,
        body: errBody,
        error: 'HTTP ${resp.statusCode}',
      );
      _emitUnauthorized(result);
      return result;
    } catch (e) {
      return ApiResult(false, -1, error: e.toString());
    }
  }

  void clearSession({bool forgetPersisted = true}) {
    _cookies.clear();
    _accessToken = null;
    _accessTokenExpiry = null;
    if (forgetPersisted) {
      // ignore: discarded_futures
      _storage.delete(key: _cookieStorageKey);
    }
  }

  void _emitUnauthorized(ApiResult result) {
    if ((result.statusCode == 401 || result.statusCode == 403) &&
        onUnauthorized != null) {
      try {
        onUnauthorized!(result);
      } catch (_) {}
    }
  }

  void _logRequestHeaders(String method, Uri uri, Map<String, String> headers) {
    if (kDebugMode) {
      try {
        // Simple debug output to help trace what headers are sent
        debugPrint('ApiClient -> $method ${uri.toString()}');
        headers.forEach((k, v) => debugPrint('  $k: $v'));
      } catch (_) {}
    }
  }
}
