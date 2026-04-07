import 'dart:typed_data';
import '../api_client.dart';
import '../models/analisis_models.dart';
import 'api_service.dart';

class AnalisisService {
  const AnalisisService();

  static const _fundsPath = '/serveis/funds/';
  static const _transactionsPath = '/serveis/transactions/';

  ApiClient get _client {
    final svc = ApiService.instance;
    if (svc == null) {
      throw StateError('ApiService is not initialized');
    }
    return svc.client;
  }

  Future<List<ProjectFund>> getFunds() async {
    final res = await _client.get(_fundsPath);
    if (!res.ok) {
      throw _asException(res, fallback: 'Error fetching funds');
    }

    final body = res.body;
    if (body is Map && body.containsKey('results')) {
      final results = body['results'] as List;
      return results.map((e) => ProjectFund.fromJson(e)).toList();
    } else if (body is List) {
      return body.map((e) => ProjectFund.fromJson(e)).toList();
    }

    return [];
  }

  Future<List<Transaction>> getTransactions(String idxiaomi) async {
    final encodedId = Uri.encodeQueryComponent(idxiaomi);
    final uri = '$_transactionsPath?idxiaomi=$encodedId';
    final res = await _client.get(uri);
    if (!res.ok) {
      throw _asException(res, fallback: 'Error fetching transactions');
    }

    final body = res.body;
    if (body is Map && body.containsKey('results')) {
      final results = body['results'] as List;
      return results.map((e) => Transaction.fromJson(e)).toList();
    } else if (body is List) {
      return body.map((e) => Transaction.fromJson(e)).toList();
    }

    return [];
  }

  Future<List<Transaction>> getOpenTransactions({String? idxiaomi}) async {
    var uri = '/serveis/transactions/open/';
    if (idxiaomi != null) {
      final encodedId = Uri.encodeQueryComponent(idxiaomi);
      uri += '?idxiaomi=$encodedId';
    }

    final res = await _client.get(uri);
    if (!res.ok) {
      throw _asException(res, fallback: 'Error fetching open transactions');
    }

    final body = res.body;
    if (body is Map && body.containsKey('results')) {
      final results = body['results'] as List;
      return results.map((e) => Transaction.fromJson(e)).toList();
    } else if (body is List) {
      return body.map((e) => Transaction.fromJson(e)).toList();
    }

    return [];
  }

  Future<List<Transaction>> getClosedTransactions({int? limit}) async {
    final uri = limit != null
        ? '/serveis/transactions/close/?limit=$limit'
        : '/serveis/transactions/close/';
    final res = await _client.get(uri);
    if (!res.ok) {
      throw _asException(res, fallback: 'Error fetching closed transactions');
    }

    final body = res.body;
    if (body is Map && body.containsKey('results')) {
      final results = body['results'] as List;
      return results.map((e) => Transaction.fromJson(e)).toList();
    } else if (body is List) {
      return body.map((e) => Transaction.fromJson(e)).toList();
    }

    return [];
  }

  Future<ProjectFund> createProjectFund(Map<String, dynamic> data) async {
    final res = await _client.post('/serveis/idxiaomi/', jsonBody: data);
    if (!res.ok) {
      throw _asException(res, fallback: 'Error creating project fund');
    }
    return ProjectFund.fromJson(res.body);
  }

  Future<Transaction> createAnalisis(Map<String, dynamic> data) async {
    final res = await _client.post('/serveis/analisis/', jsonBody: data);
    if (!res.ok) {
      throw _asException(res, fallback: 'Error creating service');
    }
    return Transaction.fromJson(res.body);
  }

  Future<void> createCliente(String name) async {
    final res = await _client.post(
      '/serveis/clientes/',
      jsonBody: {'cliente': name},
    );
    if (!res.ok) {
      throw _asException(res, fallback: 'Error creating client');
    }
  }

  Future<void> createFabricante(String name) async {
    final res = await _client.post(
      '/serveis/fabricantes/',
      jsonBody: {'fabricante': name},
    );
    if (!res.ok) {
      throw _asException(res, fallback: 'Error creating manufacturer');
    }
  }

  Future<void> createInternal(String name) async {
    final res = await _client.post(
      '/serveis/internal/',
      jsonBody: {'nombre': name},
    );
    if (!res.ok) {
      throw _asException(res, fallback: 'Error creating internal');
    }
  }

  Future<List<String>> getClientes() async {
    final res = await _client.get('/serveis/clientes/list/');
    if (!res.ok) return [];

    final body = res.body;
    List list = [];
    if (body is Map && body.containsKey('results')) {
      list = body['results'];
    } else if (body is List) {
      list = body;
    }

    return list.map((e) => e['cliente'].toString()).toList();
  }

  Future<List<String>> getFabricantes() async {
    final res = await _client.get('/serveis/fabricantes/list/');
    if (!res.ok) return [];

    final body = res.body;
    List list = [];
    if (body is Map && body.containsKey('results')) {
      list = body['results'];
    } else if (body is List) {
      list = body;
    }

    return list.map((e) => e['fabricante'].toString()).toList();
  }

  Future<List<String>> getServicios() async {
    final res = await _client.get('/serveis/servicios/');
    if (!res.ok) return [];

    final body = res.body;
    List list = [];
    if (body is Map && body.containsKey('results')) {
      list = body['results'];
    } else if (body is List) {
      list = body;
    }

    return list
        .map((e) => (e['servicio'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<List<MasterService>> getMasterServicios() async {
    final res = await _client.get('/serveis/servicios/');
    if (!res.ok) return [];

    final body = res.body;
    List list = [];
    if (body is Map && body.containsKey('results')) {
      list = body['results'];
    } else if (body is List) {
      list = body;
    }

    return list.map((e) => MasterService.fromJson(e)).toList();
  }

  Future<void> createMasterServicio(String name, double? pvd) async {
    final res = await _client.post(
      '/serveis/servicios/create/',
      jsonBody: {'servicio': name, 'pvd': pvd},
    );
    if (!res.ok) {
      throw _asException(res, fallback: 'Error creating master service');
    }
  }

  Future<void> updateMasterServicioPrice(int id, double pvd) async {
    final res = await _client.patch(
      '/serveis/servicios/$id/',
      jsonBody: {'PVD': pvd},
    );
    if (!res.ok) {
      throw _asException(res, fallback: 'Error updating service price');
    }
  }

  Future<void> deleteMasterServicio(int id) async {
    final res = await _client.delete('/serveis/servicios/$id/');
    if (!res.ok) {
      throw _asException(res, fallback: 'Error deleting master service');
    }
  }

  Future<List<String>> getInternals() async {
    final res = await _client.get('/serveis/internal/list');
    if (!res.ok) return [];

    final body = res.body;
    List list = [];
    if (body is Map && body.containsKey('results')) {
      list = body['results'];
    } else if (body is List) {
      list = body;
    }

    return list.map((e) => e['nombre'].toString()).toList();
  }

  Future<Transaction> patchOpenTransaction(
    int id,
    Map<String, dynamic> data,
  ) async {
    final res = await _client.patch(
      '/serveis/transactions/open/$id/',
      jsonBody: data,
    );
    if (!res.ok) {
      throw _asException(res, fallback: 'Error updating transaction');
    }
    return Transaction.fromJson(res.body);
  }

  Future<void> deleteOpenTransaction(int id) async {
    final res = await _client.delete('/serveis/transactions/open/$id/');
    if (!res.ok) {
      throw _asException(res, fallback: 'Error deleting transaction');
    }
  }

  Future<void> closeTransaction(int id) async {
    final res = await _client.post('/serveis/transactions/close/$id/');
    if (!res.ok) {
      throw _asException(res, fallback: 'Error closing transaction');
    }
  }

  Future<Transaction> togglePaymentStatus(int id, bool paid) async {
    final res = await _client.post(
      '/serveis/transactions/pay/$id/',
      jsonBody: {
        'paid': paid ? 1 : 0,
        'pagado': paid ? 1 : 0,
        'PAID_STATUS': paid ? 1 : 0,
        'paid_status': paid ? 1 : 0,
      },
    );
    if (!res.ok) {
      throw _asException(res, fallback: 'Error updating payment status');
    }
    return Transaction.fromJson(res.body);
  }

  Exception _asException(ApiResult result, {String? fallback}) {
    final msg =
        _extractMessage(result) ??
        fallback ??
        'Error in request (${result.statusCode})';
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

  Future<Uint8List> exportTransactionsExcel({
    String? monthStr,
    String? yearStr,
    String? startDate,
    String? endDate,
  }) async {
    String uri = '/serveis/transactions/export/';
    final params = <String>[];
    if (monthStr != null) {
      params.add('month_str=${Uri.encodeQueryComponent(monthStr)}');
    }
    if (yearStr != null) {
      params.add('year_str=${Uri.encodeQueryComponent(yearStr)}');
    }
    if (startDate != null) {
      params.add('start_date=${Uri.encodeQueryComponent(startDate)}');
    }
    if (endDate != null) {
      params.add('end_date=${Uri.encodeQueryComponent(endDate)}');
    }

    if (params.isNotEmpty) {
      uri += '?${params.join('&')}';
    }

    final res = await _client.getBytes(uri);
    if (!res.ok) {
      throw _asException(
        res,
        fallback: 'Error exporting transactions to Excel',
      );
    }
    return res.body as Uint8List;
  }

  Future<List<Transaction>> getTransactionsByDate({
    String? monthStr,
    String? yearStr,
    String? startDate,
    String? endDate,
  }) async {
    String uri = '/serveis/transactions/by_date/';
    final params = <String>[];
    if (monthStr != null) {
      params.add('month_str=${Uri.encodeQueryComponent(monthStr)}');
    }
    if (yearStr != null) {
      params.add('year_str=${Uri.encodeQueryComponent(yearStr)}');
    }
    if (startDate != null) {
      params.add('start_date=${Uri.encodeQueryComponent(startDate)}');
    }
    if (endDate != null) {
      params.add('end_date=${Uri.encodeQueryComponent(endDate)}');
    }

    if (params.isNotEmpty) {
      uri += '?${params.join('&')}';
    }

    final res = await _client.get(uri);
    if (!res.ok) {
      throw _asException(res, fallback: 'Error fetching transactions by date');
    }

    final body = res.body;
    if (body is List) {
      return body.map((e) => Transaction.fromJson(e)).toList();
    }
    return [];
  }
}
