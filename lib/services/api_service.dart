import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_client.dart';
import '../models/user_model.dart';
import '../config.dart';

/// A small service that owns a single ApiClient instance and keeps
/// authentication tokens in memory. Optionally persists a refresh token
/// when the user opts in ("Remember me"). This reduces disk persistence
/// of short-lived access tokens while allowing persistent sessions via
/// refresh tokens.
class ApiService extends ChangeNotifier {
  /// Global singleton reference to the active ApiService instance.
  /// This is set in the constructor so non-visual code can access the
  /// authenticated client before a BuildContext is available.
  static ApiService? instance;

  final ApiClient client;
  
  static const _refreshTokenKey = 'refresh_token_v1';

  String? _refreshToken;
  User? _currentUser;
  bool _forcedLogoutTriggered = false;
  String? _forcedLogoutMessage;

  /// The currently authenticated user if known. Set after login.
  User? get currentUser => _currentUser;
  bool get isForcedLogoutActive => _forcedLogoutTriggered;
  String get forcedLogoutMessage => _forcedLogoutMessage ?? 'You are no longer logged in. Please login again.';

  /// Set the current user and notify listeners so UI can react.
  void setCurrentUser(User? u) {
    _currentUser = u;
    notifyListeners();
  }

  // Timers and notifiers to manage access token lifecycle and UI warnings.
  Timer? _refreshTimer;
  Timer? _warningTimer;
  // Notifier set to true shortly before token expiry so UI can warn the user.
  final ValueNotifier<bool> sessionExpiring = ValueNotifier<bool>(false);
  // Notifier set to true when refresh fails and session is considered expired.
  final ValueNotifier<bool> sessionExpired = ValueNotifier<bool>(false);
  // Seconds before expiry to warn the user and attempt refresh.
  final int _warningSeconds = 60;

  ApiService({String? baseUrl, List<String>? allowBadCertificateForHosts}) : client = ApiClient(baseUrl: baseUrl ?? kBackendBaseUrl, allowBadCertificateForHosts: allowBadCertificateForHosts) {
    client.onUnauthorized = _handleUnauthorizedResponse;
    _loadRefreshIfExists();
    // Expose the created instance globally so helpers can access the
    // authenticated client without a BuildContext (useful during app
    // startup when navigator context may not yet be available).
    instance = this;
  }

  Future<void> _loadRefreshIfExists() async {
    try {
      debugPrint('[ApiService] reading refresh token from shared_preferences');
      final prefs = await SharedPreferences.getInstance();
      final t = prefs.getString(_refreshTokenKey);
      if (t != null && t.isNotEmpty) {
        _refreshToken = t;
        debugPrint('[ApiService] loaded refresh token (${t.length} chars)');
      } else {
        debugPrint('[ApiService] refresh token is null/empty in shared_preferences');
      }
    } catch (e) {
      debugPrint('[ApiService] error reading from shared_preferences: $e');
    }
  }

  /// Attempts to automatically log in the user using persisted credentials.
  /// Returns true if the user is successfully authenticated.
  Future<bool> tryAutoLogin() async {
    debugPrint('[ApiService] tryAutoLogin start');
    // 1. Ensure any persisted refresh token is loaded
    await _loadRefreshIfExists();
    
    // 2. Load persisted cookies (useful for session-based auth)
    await client.loadSessionFromStorage();

    // 3. If we already have a valid access token (from storage), use it!
    if (client.hasAccessToken && !client.isTokenExpired()) {
      debugPrint('[ApiService] has valid access token from storage');
      final res = await client.me();
      if (res.ok && res.body != null) {
        _currentUser = User.fromJson(Map<String, dynamic>.from(res.body));
        notifyListeners();
        debugPrint('[ApiService] auto-login successful (stored token)');
        return true;
      }
    }

    // 4. Fallback: If we have a refresh token, try to get a fresh access token
    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      debugPrint('[ApiService] found refresh token, attempting refresh');
      final success = await refreshAccessToken();
      debugPrint('[ApiService] refreshAccessToken success: $success');
      if (success) {
        final res = await client.me();
        if (res.ok && res.body != null) {
          _currentUser = User.fromJson(Map<String, dynamic>.from(res.body));
          notifyListeners();
          debugPrint('[ApiService] auto-login successful (refreshed)');
          return true;
        }
      }
    }

    debugPrint('[ApiService] auto-login failed');
    return false;
  }

  void _handleUnauthorizedResponse(ApiResult result) {
    if (_forcedLogoutTriggered) return;
    _forcedLogoutTriggered = true;
    _forcedLogoutMessage = _extractUnauthorizedMessage(result);
    _cancelSessionTimers();
    sessionExpiring.value = false;
    sessionExpired.value = true;
    client.clearSession(forgetPersisted: false);
    notifyListeners();
  }

  String _extractUnauthorizedMessage(ApiResult result) {
    final body = result.body;
    if (body is Map) {
      for (final key in ['detail', 'message', 'error']) {
        final value = body[key];
        if (value is String && value.trim().isNotEmpty) {
          return value;
        }
      }
    } else if (body is String && body.trim().isNotEmpty) {
      return body;
    }
    if (result.error != null && result.error!.trim().isNotEmpty) {
      return result.error!;
    }
    return 'You are no longer logged in. Please login again.';
  }

  Future<void> performForcedLogout() async {
    _cancelSessionTimers();
    sessionExpiring.value = false;
    client.clearSession();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_refreshTokenKey);
    } catch (_) {}
    _refreshToken = null;
    _forcedLogoutTriggered = false;
    _forcedLogoutMessage = null;
    sessionExpired.value = false;
    setCurrentUser(null);
  }

  void _cancelSessionTimers() {
    _warningTimer?.cancel();
    _warningTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Call login and keep access token in the shared ApiClient instance.
  /// If `persistRefresh` is true and the server returned a refresh token
  /// (common key names: 'refresh', 'refresh_token'), persist it.
  Future<ApiResult> login(String username, String password, {bool persistRefresh = false, bool persistCookies = false}) async {
    debugPrint('[ApiService] login attempt for: $username (persist: $persistRefresh)');
    final res = await client.login(username, password, persistSession: persistCookies);
    if (res.ok && res.body != null) {
      debugPrint('[ApiService] login success. Body type: ${res.body.runtimeType}');
      try {
        if (res.body is Map) {
          final mb = res.body as Map;
          debugPrint('[ApiService] login body keys: ${mb.keys.toList()}');
          final refresh = (mb['refresh'] ?? mb['refresh_token'] ?? mb['refreshToken']);
          if (refresh != null && refresh is String && refresh.isNotEmpty) {
            _refreshToken = refresh;
            debugPrint('[ApiService] found refresh token in response (${refresh.length} chars)');
            if (persistRefresh) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(_refreshTokenKey, _refreshToken!);
              debugPrint('[ApiService] refresh token persisted to shared_preferences');
            }
          } else {
            debugPrint('[ApiService] NO REFRESH TOKEN FOUND in response body');
          }
        } else {
          debugPrint('[ApiService] response body is not a Map: ${res.body}');
        }
      } catch (e) {
        debugPrint('[ApiService] error parsing login response: $e');
      }
      // After a successful login schedule token refresh/warnings if the
      // client exposes an access token expiry (JWT 'exp' claim).
      try {
        _scheduleTokenTimers();
      } catch (_) {}
    } else {
      debugPrint('[ApiService] login failed. Status: ${res.statusCode}, Error: ${res.error}');
    }
    return res;
  }

  Future<ApiResult> logout() async {
    // If we have a persisted refresh token but no in-memory access token,
    // try to refresh the access token first so the logout request includes
    // the Authorization header. This covers the case where the app was
    // restarted and only the refresh token was persisted.
    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      await refreshAccessToken();
    }

    final res = await client.logout();
    if (res.ok) {
      _refreshToken = null;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_refreshTokenKey);
      } catch (_) {}
      // Clear current user on successful logout
      _currentUser = null;
      notifyListeners();
    }
    return res;
  }

  /// Attempt to exchange refresh token for a new access token. Returns true
  /// on success. Uses ApiClient.refreshAccessToken() which calls the
  /// backend refresh endpoint and stores the access token in ApiClient.
  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null || _refreshToken!.isEmpty) return false;
    try {
      final resultMap = await client.refreshAccessToken(_refreshToken!);
      if (resultMap != null) {
        // If the backend rotated the refresh token, update it and persist it
        final newRefresh = resultMap['refresh_token'];
        if (newRefresh != null && newRefresh.isNotEmpty) {
          _refreshToken = newRefresh;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_refreshTokenKey, _refreshToken!);
            debugPrint('[ApiService] rotated refresh token persisted');
          } catch (e) {
            debugPrint('[ApiService] error persisting rotated token: $e');
          }
        }

        // Reset expired/expiring flags and reschedule timers
        sessionExpired.value = false;
        sessionExpiring.value = false;
        notifyListeners();
        try {
          _scheduleTokenTimers();
        } catch (_) {}
        return true;
      }
    } catch (_) {}
    return false;
  }

  void _scheduleTokenTimers() {
    _warningTimer?.cancel();
    _refreshTimer?.cancel();
    sessionExpiring.value = false;
    sessionExpired.value = false;

    final expiry = client.accessTokenExpiry;
    if (expiry == null) return; // nothing to schedule

    final now = DateTime.now().toUtc();
    final expiryUtc = expiry.toUtc();
    final secondsLeft = expiryUtc.difference(now).inSeconds;
    if (secondsLeft <= 0) {
      // Token already (almost) expired — attempt immediate refresh.
      refreshAccessToken().then((ok) {
        if (!ok) sessionExpired.value = true;
      });
      return;
    }

    // Schedule a warning shortly before expiry.
    if (secondsLeft > _warningSeconds) {
      final warnDelay = Duration(seconds: secondsLeft - _warningSeconds);
      _warningTimer = Timer(warnDelay, () {
        sessionExpiring.value = true;
      });
    } else {
      // Not enough time left — warn immediately.
      sessionExpiring.value = true;
    }

    // Schedule the refresh at expiry time.
    _refreshTimer = Timer(Duration(seconds: secondsLeft), () async {
      final ok = await refreshAccessToken();
      if (!ok) {
        sessionExpired.value = true;
      }
    });
  }

  @override
  void dispose() {
    _cancelSessionTimers();
    sessionExpiring.dispose();
    sessionExpired.dispose();
    if (ApiService.instance == this) ApiService.instance = null;
    super.dispose();
  }
}
