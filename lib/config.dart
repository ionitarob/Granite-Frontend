// Centralized configuration for backend endpoints.
// Use this constant wherever the API base URL is required so it remains
// consistent across the app.
const String kBackendBaseUrl = 'http://10.20.31.10:7000';

// Compute a websocket-compatible base URL from the HTTP(S) backend URL.
// If the backend uses HTTPS, this returns a wss:// URL; otherwise ws://.
String get kBackendWebSocketBase {
	if (kBackendBaseUrl.startsWith('https://')) return kBackendBaseUrl.replaceFirst('https://', 'wss://');
	if (kBackendBaseUrl.startsWith('http://')) return kBackendBaseUrl.replaceFirst('http://', 'ws://');
	return kBackendBaseUrl;
}
