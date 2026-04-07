import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  SharedPreferences? _prefs;

  // In-memory cookies map
  final Map<String, String> _cookies = {};
  String? _accessToken;
  DateTime? _accessTokenExpiry;
  void Function(ApiResult result)? onUnauthorized;

  bool get hasAccessToken => _accessToken != null && _accessToken!.isNotEmpty;
  bool get hasSessionCookie => _cookies.isNotEmpty;

  static const _cookieStorageKey = 'session_cookies_v1';
  static const _accessTokenKey = 'access_token_v1';
  static const _accessTokenExpiryKey = 'access_token_expiry_v1';

  /// If [allowBadCertificateForHosts] is provided and the app is running in
  /// debug mode, the internal HttpClient will accept self-signed certificates
  /// for the listed hosts. This is strictly for development/testing and is
  /// guarded by `kDebugMode` so it won't run in release builds.
  ApiClient({
    required this.baseUrl,
    http.Client? client,
    List<String>? allowBadCertificateForHosts,
    this.onUnauthorized,
  }) : _client = client ?? _createDefaultClient(allowBadCertificateForHosts);

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
        await saveSessionToStorage();
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
        try {
          _prefs ??= await SharedPreferences.getInstance();
          await _prefs!.remove(_cookieStorageKey);
          await _prefs!.remove(_accessTokenKey);
        } catch (e) {
          debugPrint('ApiClient.logout: failed clearing storage: $e');
        }
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

  /// Persist current cookies and access token to storage.
  Future<void> saveSessionToStorage() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      if (_cookies.isNotEmpty) {
        final cookieString = jsonEncode(_cookies);
        await _prefs!.setString(_cookieStorageKey, cookieString);
      } else {
        await _prefs!.remove(_cookieStorageKey);
      }

      if (_accessToken != null) {
        await _prefs!.setString(_accessTokenKey, _accessToken!);
      } else {
        await _prefs!.remove(_accessTokenKey);
      }

      if (_accessTokenExpiry != null) {
        await _prefs!.setString(
          _accessTokenExpiryKey,
          _accessTokenExpiry!.toIso8601String(),
        );
      } else {
        await _prefs!.remove(_accessTokenExpiryKey);
      }
    } catch (e) {
      debugPrint('[ApiClient] error saving session to storage: $e');
    }
  }

  /// Load cookies and access token from storage.
  Future<void> loadSessionFromStorage() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final cookieString = _prefs!.getString(_cookieStorageKey);
      if (cookieString != null && cookieString.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(cookieString);
        _cookies.clear();
        decoded.forEach((key, value) {
          _cookies[key] = value.toString();
        });
        debugPrint('[ApiClient] ${_cookies.length} cookies restored from storage');
      }

      final token = _prefs!.getString(_accessTokenKey);
      if (token != null && token.isNotEmpty) {
        _accessToken = token;
        debugPrint('[ApiClient] access token restored from storage');
      }

      final expiryStr = _prefs!.getString(_accessTokenExpiryKey);
      if (expiryStr != null && expiryStr.isNotEmpty) {
        _accessTokenExpiry = DateTime.tryParse(expiryStr);
        debugPrint('[ApiClient] token expiry restored: $_accessTokenExpiry');
      }
    } catch (e) {
      debugPrint('[ApiClient] error loading session from storage: $e');
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
  Future<Map<String, String>?> refreshAccessToken(String refreshToken) async {
    try {
      final uri = _uri('/api/auth/refresh/');
      final headers = {'Accept': 'application/json', 'Content-Type': 'application/json'};

      debugPrint('ApiClient -> POST ${uri.toString()} (refresh rotation)');
      final resp = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode({'refresh_token': refreshToken}),
      );
      debugPrint('ApiClient: refresh response status: ${resp.statusCode}');
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        try {
          if (resp.body.isNotEmpty) {
            final parsed = jsonDecode(resp.body);
            final access = _extractTokenFromParsed(parsed);
            
            // Extract the new rotated refresh token if the backend provides it
            String? newRefresh;
            if (parsed is Map) {
              newRefresh = (parsed['refresh'] ?? parsed['refresh_token'] ?? parsed['refreshToken']) as String?;
            }

            if (access != null && access.isNotEmpty) {
              _accessToken = access;
              debugPrint('ApiClient: token refresh successful');
              await saveSessionToStorage();
              return {
                'access_token': access,
                if (newRefresh != null) 'refresh_token': newRefresh,
              };
            }
          }
        } catch (e) {
          debugPrint('ApiClient: error parsing refresh response: $e');
        }
      } else {
        debugPrint('ApiClient: refresh failed. Status: ${resp.statusCode}, Body: ${resp.body}');
      }
    } catch (e) {
      debugPrint('ApiClient: error during refresh: $e');
    }
    return null;
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
      if (kDebugMode) debugPrint('ApiClient <- POST $path result: ${resp.statusCode}');
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

  void clearSession({bool forgetPersisted = true}) async {
    _cookies.clear();
    _accessToken = null;
    _accessTokenExpiry = null;
    if (forgetPersisted) {
      try {
        _prefs ??= await SharedPreferences.getInstance();
        await _prefs!.remove(_cookieStorageKey);
        await _prefs!.remove(_accessTokenKey);
        await _prefs!.remove(_accessTokenExpiryKey);
      } catch (_) {}
    }
  }

  void _emitUnauthorized(ApiResult result) {
    if (result.statusCode == 401 &&
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
