import 'package:flutter/material.dart';
import 'api_service.dart';

class XiaomiTeam {
  final int id;
  final String nombre;
  final List<String> members;

  XiaomiTeam({required this.id, required this.nombre, required this.members});

  factory XiaomiTeam.fromJson(Map<String, dynamic> json) {
    return XiaomiTeam(
      id: json['id'] ?? 0,
      nombre: json['nombre'] ?? '',
      members: List<String>.from(json['members'] ?? []),
    );
  }
}

class XiaomiStatsSummary {
  final Map<String, int> totals;
  final int pending;
  final List<Map<String, dynamic>> teamPerformance;
  final double historicalAvgUph;
  final double uphToday;
  final double uphWeek;
  final double avgExecutionTime;
  final Map<String, double> avgExecutionAll;
  final Map<String, double> uphAll;

  XiaomiStatsSummary({
    required this.totals,
    required this.pending,
    required this.teamPerformance,
    required this.historicalAvgUph,
    required this.uphToday,
    required this.uphWeek,
    required this.avgExecutionTime,
    required this.avgExecutionAll,
    required this.uphAll,
  });

  factory XiaomiStatsSummary.fromJson(Map<String, dynamic> json) {
    final t = Map<String, int>.from(json['totals'] ?? {});
    final uAll = Map<String, dynamic>.from(json['uph_all'] ?? {});
    final avgAllRaw = Map<String, dynamic>.from(json['avg_execution_all'] ?? {});
    return XiaomiStatsSummary(
      totals: t,
      pending: (json['pending'] as num?)?.toInt() ?? 0,
      teamPerformance: List<Map<String, dynamic>>.from(json['team_performance'] ?? []),
      historicalAvgUph: (json['historical_avg_uph'] as num?)?.toDouble() ?? 0.0,
      uphToday: (json['uph_today'] as num?)?.toDouble() ?? 0.0,
      uphWeek: (json['uph_week'] as num?)?.toDouble() ?? 0.0,
      avgExecutionTime: (json['avg_execution_time'] as num?)?.toDouble() ?? 0.0,
      avgExecutionAll: avgAllRaw.map((k, v) => MapEntry(k, (v as num).toDouble())),
      uphAll: uAll.map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}

class XiaomiProvider extends ChangeNotifier {
  final ApiService apiService;

  List<XiaomiTeam> _todayTeams = [];
  List<XiaomiTeam> _yesterdayTeams = [];
  bool _initialized = false;
  bool _loading = false;
  String? _initStatus; // 'exists', 'missing'

  XiaomiStatsSummary? _summary;
  List<Map<String, dynamic>> _uphTrend = [];
  List<Map<String, dynamic>> _teamHistory = [];
  bool _isHourlyTrend = false;
  bool _loadingTrend = false;
  bool _loadingTeamHistory = false;

  XiaomiProvider({required this.apiService});

  List<XiaomiTeam> get todayTeams => _todayTeams;
  List<XiaomiTeam> get yesterdayTeams => _yesterdayTeams;
  bool get isInitialized => _initialized;
  bool get isLoading => _loading;
  bool get isLoadingTrend => _loadingTrend;
  String? get initStatus => _initStatus;
  XiaomiStatsSummary? get summary => _summary;
  List<Map<String, dynamic>> get uphTrend => _uphTrend;
  List<Map<String, dynamic>> get teamHistory => _teamHistory;
  bool get isHourlyTrend => _isHourlyTrend;
  bool get isLoadingTeamHistory => _loadingTeamHistory;

  Future<void> initTeams() async {
    _loading = true;
    notifyListeners();
    try {
      final resp = await apiService.client.get('/xiaomieco/teams/init/');
      if (resp.ok && resp.body is Map) {
        _initStatus = resp.body['status'];
        if (_initStatus == 'exists') {
          final List raw = resp.body['teams'] ?? [];
          _todayTeams = raw.map((e) => XiaomiTeam.fromJson(e)).toList();
        } else {
          final List raw = resp.body['yesterday_teams'] ?? [];
          _yesterdayTeams = raw.map((e) => XiaomiTeam.fromJson(e)).toList();
        }
        _initialized = true;
      }
    } catch (e) {
      debugPrint('Error initTeams: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> createTeam(String color, List<String> members) async {
    try {
      final resp = await apiService.client.post('/xiaomieco/teams/create/', jsonBody: {
        'nombre': color,
        'members': members,
      });
      if (resp.ok) {
        await initTeams();
        return true;
      }
    } catch (e) {
      debugPrint('Error createTeam: $e');
    }
    return false;
  }

  Future<bool> updateTeam(int teamId, String color, List<String> members) async {
    try {
      final resp = await apiService.client.post('/xiaomieco/teams/update/', jsonBody: {
        'team_id': teamId,
        'nombre': color,
        'members': members,
      });
      if (resp.ok) {
        await initTeams();
        return true;
      }
    } catch (e) {
      debugPrint('Error updateTeam: $e');
    }
    return false;
  }

  Future<bool> cloneTeams() async {
    try {
      final resp = await apiService.client.post('/xiaomieco/teams/clone/');
      if (resp.ok) {
        await initTeams();
        return true;
      }
    } catch (e) {
      debugPrint('Error cloneTeams: $e');
    }
    return false;
  }

  Future<bool> validateCesb(String cesb) async {
    try {
      final resp = await apiService.client.post('/xiaomieco/validar_cesb/', jsonBody: {'cesb': cesb});
      return resp.ok;
    } catch (e) {
      debugPrint('Error validateCesb: $e');
    }
    return false;
  }

  Future<bool> unvalidateCesb(String cesb) async {
    try {
      final resp = await apiService.client.post('/xiaomieco/desvalidar_cesb/', jsonBody: {'cesb': cesb});
      return resp.ok;
    } catch (e) {
      debugPrint('Error unvalidateCesb: $e');
    }
    return false;
  }

  Future<bool> startCesb(String cesb, int teamId) async {
    try {
      final resp = await apiService.client.post('/xiaomieco/empezar_cesb/', jsonBody: {
        'cesb': cesb,
        'team_id': teamId,
      });
      return resp.ok;
    } catch (e) {
      debugPrint('Error startCesb: $e');
    }
    return false;
  }

  Future<bool> finishCesb(String cesb, int teamId) async {
    try {
      final resp = await apiService.client.post('/xiaomieco/cerrar_cesb/', jsonBody: {
        'cesb': cesb,
        'team_id': teamId,
      });
      return resp.ok;
    } catch (e) {
      debugPrint('Error finishCesb: $e');
    }
    return false;
  }

  Future<void> fetchSummary() async {
    _loading = true;
    notifyListeners();
    try {
      final resp = await apiService.client.get('/xiaomieco/stats/summary/');
      if (resp.ok && resp.body is Map) {
        _summary = XiaomiStatsSummary.fromJson(resp.body);
      }
    } catch (e) {
      debugPrint('Error fetchSummary: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> fetchUphTrend(DateTime start, DateTime end) async {
    _loadingTrend = true;
    notifyListeners();
    try {
      final startStr = start.toIso8601String();
      final endStr = end.toIso8601String();
      final resp = await apiService.client.get('/xiaomieco/stats/trend/?start=$startStr&end=$endStr');
      if (resp.ok && resp.body is Map) {
        _uphTrend = List<Map<String, dynamic>>.from(resp.body['trend'] ?? []);
        _isHourlyTrend = resp.body['is_hourly'] ?? false;
      }
    } catch (e) {
      debugPrint('Error fetchUphTrend: $e');
    } finally {
      _loadingTrend = false;
      notifyListeners();
    }
  }

  Future<void> fetchTeamPerformance(DateTime start, DateTime end) async {
    _loadingTeamHistory = true;
    notifyListeners();
    try {
      final startStr = start.toIso8601String().split('T')[0];
      final endStr = end.toIso8601String().split('T')[0];
      final resp = await apiService.client.get('/xiaomieco/stats/teams/?start=$startStr&end=$endStr');
      if (resp.ok && resp.body is Map) {
        _teamHistory = List<Map<String, dynamic>>.from(resp.body['teams'] ?? []);
      }
    } catch (e) {
      debugPrint('Error fetchTeamPerformance: $e');
    } finally {
      _loadingTeamHistory = false;
      notifyListeners();
    }
  }
}
