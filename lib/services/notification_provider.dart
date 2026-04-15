import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import '../services/api_service.dart';
import 'dart:math' as math;

class GraniteNotification {
  final int id;
  final String tipo;
  final String titulo;
  final String mensaje;
  final bool leido;
  final DateTime fechaCreacion;
  final Map<String, dynamic>? data;

  GraniteNotification({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    required this.leido,
    required this.fechaCreacion,
    this.data,
  });

  factory GraniteNotification.fromJson(Map<String, dynamic> json) {
    return GraniteNotification(
      id: json['id'],
      tipo: json['tipo'],
      titulo: json['titulo'],
      mensaje: json['mensaje'],
      leido: json['leido'] ?? false,
      fechaCreacion: json['fecha_creacion'] != null 
        ? DateTime.parse(json['fecha_creacion']) 
        : DateTime.now(),
      data: json['data'],
    );
  }
}

class NotificationProvider extends ChangeNotifier {
  final ApiService apiService;
  List<GraniteNotification> _notifications = [];
  bool _isLoading = false;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  List<GraniteNotification> get notifications => _notifications;
  bool get isLoading => _isLoading;
  int get unreadCount => _notifications.where((n) => !n.leido).length;
  bool get isConnected => _isConnected;

  NotificationProvider({required this.apiService}) {
    // Listen to user changes to connect/disconnect WS
    apiService.addListener(_onUserChanged);
    _onUserChanged();
  }

  void _onUserChanged() {
    if (apiService.currentUser != null) {
      fetchNotifications();
      _connectWebSocket();
    } else {
      _disconnectWebSocket();
      _notifications = [];
      notifyListeners();
    }
  }

  Future<void> fetchNotifications() async {
    if (apiService.currentUser == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      final res = await apiService.client.get('/api/auth/notifications/');
      if (res.ok && res.body is List) {
        _notifications = (res.body as List)
            .map((json) => GraniteNotification.fromJson(json))
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addMockNotification() {
    final mock = GraniteNotification(
      id: DateTime.now().millisecondsSinceEpoch,
      tipo: 'debug',
      titulo: 'Notificación de Prueba',
      mensaje: 'Esta es una notificación generada localmente para probar el diseño.',
      leido: false,
      fechaCreacion: DateTime.now(),
      data: {'mock': true},
    );
    _notifications.insert(0, mock);
    notifyListeners();
  }

  void _connectWebSocket() {
    if (_channel != null) return;

    final token = apiService.client.accessToken;
    if (token == null) return;

    final wsUrl = '$kBackendWebSocketBase/ws/notifications/?token=$token';
    debugPrint('Connecting to WebSocket: $wsUrl');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _subscription = _channel!.stream.listen(
        (message) {
          _reconnectAttempts = 0; // Reset on success
          _isConnected = true;
          try {
            final data = json.decode(message);
            if (data['type'] == 'notification.new') {
              final notifJson = data['data'];
              _notifications.insert(0, GraniteNotification.fromJson(notifJson));
              notifyListeners();
              debugPrint('New notification received: ${data['data']['titulo']}');
            }
          } catch (e) {
            debugPrint('Error parsing notification message: $e');
          }
        },
        onError: (e) {
          debugPrint('WebSocket Stream Error: $e');
          _isConnected = false;
          _reconnect();
        },
        onDone: () {
          debugPrint('WebSocket Closed');
          _isConnected = false;
          _reconnect();
        },
      );
    } catch (e) {
      debugPrint('WebSocket Synchronous Connection Error: $e');
      _isConnected = false;
      _reconnect();
    }
  }

  void _reconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    
    _reconnectTimer?.cancel();
    
    _reconnectAttempts++;
    final delaySeconds = math.min(30, math.pow(2, math.min(6, _reconnectAttempts)).toInt());
    debugPrint('NotificationProvider scheduling reconnect in ${delaySeconds}s (attempt $_reconnectAttempts)');

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (apiService.currentUser != null) {
        _connectWebSocket();
      }
    });
  }

  void _disconnectWebSocket() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }

  Future<void> markAsRead(int id) async {
    try {
      final res = await apiService.client.post('/api/auth/notifications/read/', jsonBody: {'id': id});
      if (res.ok) {
        final index = _notifications.indexWhere((n) => n.id == id);
        if (index != -1) {
          final n = _notifications[index];
          _notifications[index] = GraniteNotification(
            id: n.id,
            tipo: n.tipo,
            titulo: n.titulo,
            mensaje: n.mensaje,
            leido: true,
            fechaCreacion: n.fechaCreacion,
            data: n.data,
          );
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      final res = await apiService.client.post('/api/auth/notifications/read/', jsonBody: {'all': true});
      if (res.ok) {
        _notifications = _notifications.map((n) {
          return GraniteNotification(
            id: n.id,
            tipo: n.tipo,
            titulo: n.titulo,
            mensaje: n.mensaje,
            leido: true,
            fechaCreacion: n.fechaCreacion,
            data: n.data,
          );
        }).toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
    }
  }

  @override
  void dispose() {
    apiService.removeListener(_onUserChanged);
    _disconnectWebSocket();
    super.dispose();
  }
}
