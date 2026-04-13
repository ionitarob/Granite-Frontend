import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../api_client.dart';
import '../models/agent_models.dart';

class OrderOpsService {
  final ApiClient _client;

  OrderOpsService(this._client);

  // --- Proyectos ---

  Future<List<Proyecto>> getProyectos() async {
    final result = await _client.get('/orderops/proyectos');
    if (!result.ok) throw Exception('Failed to load projects');
    final List<dynamic> data = result.body;
    return data.map((e) => Proyecto.fromJson(e)).toList();
  }

  Future<Proyecto> getProyectoDetail(int id) async {
    final result = await _client.get('/orderops/proyectos/$id');
    if (!result.ok) throw Exception('Failed to load project details');
    return Proyecto.fromJson(result.body);
  }

  Future<bool> createProyecto(String nombre, {String? description}) async {
    final result = await _client.post(
      '/orderops/proyectos',
      jsonBody: {
        'nombre': nombre,
        if (description != null) 'descripcion': description,
      },
    );
    return result.ok;
  }

  Future<bool> deleteProyecto(int id) async {
    final result = await _client.delete('/orderops/proyectos/$id');
    return result.ok;
  }

  Future<bool> updateProyecto(
    int id, {
    String? nombre,
    String? description,
    List<String>? subfamilies,
  }) async {
    final body = <String, dynamic>{};
    if (nombre != null) body['nombre'] = nombre;
    if (description != null) body['descripcion'] = description;
    if (subfamilies != null) body['subfamilies'] = subfamilies.join(',');

    final result = await _client.patch(
      '/orderops/proyectos/$id',
      jsonBody: body,
    );
    return result.ok;
  }

  /// Fetch list of orders for the agent queue
  Future<List<AgentOrder>> getAgentOrders({
    String? agentStatus,
    int? isBlocked, // 0 or 1
    String? department,
    int? includeSource, // 0 or 1
    int? limit,
  }) async {
    final queryParams = <String, String>{};
    if (agentStatus != null) queryParams['agent_status'] = agentStatus;
    if (department != null) queryParams['department'] = department;
    if (isBlocked != null) queryParams['is_blocked'] = isBlocked.toString();
    if (includeSource != null) {
      queryParams['include_source'] = includeSource.toString();
    }
    if (limit != null) queryParams['limit'] = limit.toString();

    final queryString = Uri(queryParameters: queryParams).query;
    // URL for list: /orderops/agent-orders
    final path =
        '/orderops/agent-orders${queryString.isNotEmpty ? '?$queryString' : ''}';

    final result = await _client.get(path);
    if (!result.ok) {
      debugPrint('OrderOpsService.getAgentOrders error: ${result.error}');
      throw Exception('Failed to load agent orders');
    }

    final data = result.body;
    List<dynamic> list = [];
    if (data is Map && data.containsKey('results')) {
      list = data['results'];
    } else if (data is List) {
      list = data;
    }

    return list.map((e) => AgentOrder.fromJson(e)).toList();
  }

  /// Fetch detail for a specific order by ID
  Future<OrderOpsDetail> getAgentOrder(int idnbr) async {
    // URL for detail: /orderops/agent-orders/<int:idnbr>
    final result = await _client.get('/orderops/agent-orders/$idnbr');
    if (!result.ok) {
      debugPrint('OrderOpsService.getAgentOrder error: ${result.error}');
      throw Exception('Failed to load order detail');
    }
    return OrderOpsDetail.fromJson(result.body);
  }

  /// Fetch work items
  Future<List<WorkItem>> getWorkItems({String? status, int? limit}) async {
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (limit != null) queryParams['limit'] = limit.toString();

    final queryString = Uri(queryParameters: queryParams).query;
    // URL for work items: /orderops/work-items
    final path =
        '/orderops/work-items${queryString.isNotEmpty ? '?$queryString' : ''}';

    final result = await _client.get(path);
    if (!result.ok) {
      debugPrint('OrderOpsService.getWorkItems error: ${result.error}');
      throw Exception('Failed to load work items');
    }

    List<dynamic> list = [];
    if (result.body is List) {
      list = result.body;
    } else if (result.body is Map && result.body.containsKey('results')) {
      list = result.body['results'];
    }

    return list.map((e) => WorkItem.fromJson(e)).toList();
  }

  /// Update a work item's status or assignee.
  /// Returns a Map with 'ok' and optionally 'order_progress' info.
  Future<Map<String, dynamic>> updateWorkItem(
    int workItemId, {
    String? status,
    String? assignedTo,
  }) async {
    final body = <String, dynamic>{};
    if (status != null) body['status'] = status;
    if (assignedTo != null) body['assigned_to'] = assignedTo;

    // URL for update: /orderops/work-items/<int:work_item_id>
    final result = await _client.patch(
      '/orderops/work-items/$workItemId',
      jsonBody: body,
    );

    // Check if body has order_progress
    Map<String, dynamic> response = {'ok': result.ok};
    if (result.ok && result.body is Map) {
      if (result.body.containsKey('order_progress')) {
        response['order_progress'] = result.body['order_progress'];
      }
    }
    return response;
  }

  /// Trigger AI Triage for an order
  Future<bool> runTriage(int idnbr) async {
    final body = {'idnbr': idnbr};
    // URL for triage: /orderops/triage/run
    final result = await _client.post('/orderops/triage/run', jsonBody: body);
    return result.ok;
  }

  /// Update an order manually (e.g. override department or mark as completed)
  Future<bool> updateAgentOrder(
    int idnbr, {
    String? department,
    String? estado,
    String? reason,
    bool? markCompleted,
    String? completionSummary,
    String? completionAuthor,
    String? family,
    String? proyecto,
    int? proyectoId,
    List<String>? subfamilies,
    List<String>? completedFamilies,
  }) async {
    final body = <String, dynamic>{};
    if (department != null) body['department'] = department;
    if (estado != null) body['estado'] = estado;
    if (reason != null) body['reason'] = reason;
    if (markCompleted != null) body['mark_completed'] = markCompleted;
    if (family != null) body['family'] = family;
    if (proyectoId != null) {
      body['proyecto'] = proyectoId;
    } else if (proyecto != null) {
      body['proyecto'] = proyecto;
    }
    if (completionSummary != null) {
      body['completion_summary'] = completionSummary;
    }
    if (completionAuthor != null) {
      body['completion_author'] = completionAuthor;
    }
    if (subfamilies != null) body['subfamilies'] = subfamilies.join(',');
    if (completedFamilies != null) {
      body['completed_families'] = completedFamilies.join(',');
    }

    final result = await _client.patch(
      '/orderops/agent-orders/$idnbr/update',
      jsonBody: body,
    );
    return result.ok;
  }

  /// Same as updateAgentOrder but returns full ApiResult for rich error handling.
  Future<ApiResult> updateAgentOrderWithResult(
    int idnbr, {
    String? department,
    String? estado,
    String? reason,
    bool? markCompleted,
    String? completionSummary,
    String? completionAuthor,
    String? family,
    String? proyecto,
    int? proyectoId,
    List<String>? subfamilies,
    List<String>? completedFamilies,
  }) async {
    final body = <String, dynamic>{};
    if (department != null) body['department'] = department;
    if (estado != null) body['estado'] = estado;
    if (reason != null) body['reason'] = reason;
    if (markCompleted != null) body['mark_completed'] = markCompleted;
    if (family != null) body['family'] = family;
    if (proyectoId != null) {
      body['proyecto'] = proyectoId;
    } else if (proyecto != null) {
      body['proyecto'] = proyecto;
    }
    if (completionSummary != null) {
      body['completion_summary'] = completionSummary;
    }
    if (completionAuthor != null) {
      body['completion_author'] = completionAuthor;
    }
    if (subfamilies != null) body['subfamilies'] = subfamilies.join(',');
    if (completedFamilies != null) {
      body['completed_families'] = completedFamilies.join(',');
    }

    return await _client.patch(
      '/orderops/agent-orders/$idnbr/update',
      jsonBody: body,
    );
  }

  /// Post a comment for a work item (e.g. feedback to LLM)
  Future<bool> postWorkItemComment(
    int workItemId, {
    required String author,
    required String bodyText,
    String audience = 'llm', // or 'internal'
    bool runTriage = true,
  }) async {
    // URL: POST /orderops/work-items/{work_item_id}/comments
    final body = <String, dynamic>{
      'author': author,
      'body': bodyText,
      'audience': audience,
      'run_triage': runTriage,
    };

    final result = await _client.post(
      '/orderops/work-items/$workItemId/comments',
      jsonBody: body,
    );
    return result.ok;
  }

  // --- Agent Memory ---

  Future<List<AgentMemory>> getAgentMemory({
    String? status,
    String? department,
    int? limit,
  }) async {
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (department != null) queryParams['department'] = department;
    if (limit != null) queryParams['limit'] = limit.toString();

    final queryString = Uri(queryParameters: queryParams).query;
    final path =
        '/orderops/memory${queryString.isNotEmpty ? '?$queryString' : ''}';

    final result = await _client.get(path);
    if (!result.ok) {
      debugPrint('OrderOpsService.getAgentMemory error: ${result.error}');
      throw Exception('Failed to load agent memory');
    }

    final data = result.body;
    List<dynamic> list = [];
    if (data is Map && data.containsKey('results')) {
      list = data['results'];
    } else if (data is List) {
      list = data;
    }

    return list.map((e) => AgentMemory.fromJson(e)).toList();
  }

  Future<bool> updateAgentMemory(
    int memoryId, {
    required String answer,
    String? status,
    String? department,
  }) async {
    final body = <String, dynamic>{'answer': answer};
    if (status != null) body['status'] = status;
    if (department != null) body['department'] = department;

    final result = await _client.patch(
      '/orderops/memory/$memoryId',
      jsonBody: body,
    );
    return result.ok;
  }

  // --- Order Chat ---

  /// Fetch chat history for an order
  Future<List<ChatMessage>> getChatHistory(int idnbr) async {
    final result = await _client.get('/orderops/agent-orders/$idnbr/chat');
    if (!result.ok) {
      if (result.statusCode == 404) return [];
      throw Exception('Failed to load chat history');
    }

    if (result.body is List) {
      return (result.body as List).map((e) => ChatMessage.fromJson(e)).toList();
    } else if (result.body is Map) {
      final map = result.body as Map<String, dynamic>;
      // Handle pagination or wrapper
      if (map.containsKey('results') && map['results'] is List) {
        return (map['results'] as List)
            .map((e) => ChatMessage.fromJson(e))
            .toList();
      }
      if (map.containsKey('messages') && map['messages'] is List) {
        return (map['messages'] as List)
            .map((e) => ChatMessage.fromJson(e))
            .toList();
      }
    }

    return [];
  }

  /// Stream chat response from LLM (SSE)
  Stream<Map<String, dynamic>> streamChat(int idnbr, String message) async* {
    final response = await _client.streamPost(
      '/orderops/agent-orders/$idnbr/chat/stream',
      jsonBody: {'body': message},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to start stream: ${response.statusCode}');
    }

    // SSE Parser
    // Using transform(utf8.decoder) and LineSplitter is common, but SSE events can span lines.
    // However, typical python SSE implementations send "event: ...\ndata: ...\n\n"

    final stream = response.stream
        .transform(const Utf8Decoder())
        .transform(const LineSplitter());

    String? currentEvent;

    await for (final line in stream) {
      if (line.isEmpty) {
        // End of event dispatch
        currentEvent = null;
        continue;
      }

      if (line.startsWith('event: ')) {
        currentEvent = line.substring(7).trim();
      } else if (line.startsWith('data: ')) {
        final dataStr = line.substring(6);
        try {
          final data = jsonDecode(dataStr);
          yield {'event': currentEvent ?? 'message', 'data': data};
        } catch (_) {
          // ignore parsing error or empty data
        }
      }
    }
  }

  /// Restart an agent order (Hard Reset).
  /// Clears agent data and optionally runs triage immediately.
  Future<bool> restartAgentOrder(
    int idnbr, {
    bool runTriage = true,
    bool deleteAnsweredClarifications = false,
    String? author,
  }) async {
    final body = <String, dynamic>{
      'run_triage': runTriage,
      'delete_answered_clarifications': deleteAnsweredClarifications,
    };
    if (author != null) body['author'] = author;

    // URL: POST /orderops/agent-orders/{idnbr}/restart
    final result = await _client.post(
      '/orderops/agent-orders/$idnbr/restart',
      jsonBody: body,
    );
    return result.ok;
  }

  // --- Order Detail Extensions (Observations, Photos, Services) ---

  Future<List<AgentOrderObservation>> getObservations(int idnbr) async {
    final result = await _client.get(
      '/orderops/agent-orders/$idnbr/observations',
    );
    if (!result.ok) {
      debugPrint('OrderOpsService.getObservations error: ${result.error}');
      return [];
    }
    final data = result.body;
    List<dynamic> list = [];
    if (data is Map && data.containsKey('results')) {
      list = data['results'];
    }
    return list.map((e) => AgentOrderObservation.fromJson(e)).toList();
  }

  Future<bool> postObservation(
    int idnbr,
    String bodyText, {
    String? author,
    int? proyectoId,
  }) async {
    final body = <String, dynamic>{'body': bodyText};
    if (author != null) body['author'] = author;
    if (proyectoId != null) body['proyecto_id'] = proyectoId;
    final result = await _client.post(
      '/orderops/agent-orders/$idnbr/observations',
      jsonBody: body,
    );
    return result.ok;
  }

  /// Update an existing observation (comment) on an agent order.
  Future<bool> updateObservation(
    int idnbr,
    int observationId,
    String bodyText, {
    String? author,
  }) async {
    final body = <String, dynamic>{'body': bodyText};
    if (author != null) body['author'] = author;

    // Preferred nested endpoint
    final result = await _client.patch(
      '/orderops/agent-orders/$idnbr/observations/$observationId',
      jsonBody: body,
    );

    // Fallback to flat endpoint for older backends
    if (result.statusCode == 404 || result.statusCode == 405) {
      final fallback = await _client.patch('/orderops/observations/$observationId', jsonBody: body);
      return fallback.ok;
    }

    return result.ok;
  }

  /// Delete an observation (comment) from an agent order.
  Future<bool> deleteObservation(int idnbr, int observationId) async {
    final nested = await _client.delete('/orderops/agent-orders/$idnbr/observations/$observationId');
    if (nested.ok) return true;

    final flat = await _client.delete('/orderops/observations/$observationId');
    return flat.ok;
  }

  Future<List<AgentOrderPhoto>> getPhotos(int idnbr) async {
    final result = await _client.get('/orderops/agent-orders/$idnbr/photos');
    if (!result.ok) {
      debugPrint('OrderOpsService.getPhotos error: ${result.error}');
      return [];
    }
    final data = result.body;
    List<dynamic> list = [];
    if (data is Map && data.containsKey('results')) {
      list = data['results'];
    }
    return list.map((e) => AgentOrderPhoto.fromJson(e)).toList();
  }

  Future<bool> postPhoto(
    int idnbr,
    String fileName,
    String filePath, {
    String? author,
    int? proyectoId,
  }) async {
    final body = <String, dynamic>{
      'file_name': fileName,
      'file_path': filePath,
    };
    if (author != null) body['author'] = author;
    if (proyectoId != null) body['proyecto_id'] = proyectoId;
    final result = await _client.post(
      '/orderops/agent-orders/$idnbr/photos',
      jsonBody: body,
    );
    return result.ok;
  }

  /// Upload photo via multipart (Camera/Gallery)
  Future<bool> uploadPhoto(
    int idnbr,
    String fileName,
    List<int> bytes, {
    int? proyectoId,
    String? scope,
  }) async {
    final result = await uploadPhotos(
      idnbr,
      [MultipartAttachment(fieldName: 'file', fileName: fileName, bytes: bytes)],
      proyectoId: proyectoId,
      scope: scope,
    );
    return result.ok;
  }

  /// Upload one or more files via multipart (supports drag/drop batches).
  Future<ApiResult> uploadPhotos(
    int idnbr,
    List<MultipartAttachment> files, {
    int? proyectoId,
    String? scope,
  }) async {
    final queryParams = <String, String>{};
    if (proyectoId != null) queryParams['proyecto_id'] = proyectoId.toString();
    if (scope != null && scope.trim().isNotEmpty) {
      queryParams['scope'] = scope.trim().toLowerCase();
    }
    final queryString = Uri(queryParameters: queryParams).query;
    final path =
        '/orderops/agent-orders/$idnbr/photos${queryString.isNotEmpty ? '?$queryString' : ''}';

    return _client.postMultipart(
      path,
      files: files,
    );
  }

  /// Register an existing server-side file path into Archivos.
  Future<bool> addArchivoManual(
    int idnbr,
    String fileName,
    String filePath, {
    String? author,
  }) async {
    final body = <String, dynamic>{
      'file_name': fileName,
      'file_path': filePath,
    };
    if (author != null) body['author'] = author;
    final result = await _client.post(
      '/orderops/agent-orders/$idnbr/photos/manual',
      jsonBody: body,
    );
    if (result.ok) return true;

    // Backward compatibility: older backends accept manual add on /photos.
    if (result.statusCode == 404 || result.statusCode == 405) {
      final legacy = await _client.post(
        '/orderops/agent-orders/$idnbr/photos',
        jsonBody: body,
      );
      return legacy.ok;
    }

    return false;
  }

  /// Delete an attached file from Archivos.
  /// Tries nested endpoint first, then fallback flat endpoint.
  Future<bool> deletePhoto(int idnbr, int photoId) async {
    final nested = await _client.delete(
      '/orderops/agent-orders/$idnbr/photos/$photoId',
    );
    if (nested.ok) return true;

    final flat = await _client.delete('/orderops/photos/$photoId');
    return flat.ok;
  }

  Future<List<AgentOrderService>> getServices(int idnbr) async {
    final result = await _client.get('/orderops/agent-orders/$idnbr/services');
    if (!result.ok) {
      debugPrint('OrderOpsService.getServices error: ${result.error}');
      return [];
    }
    final data = result.body;
    List<dynamic> list = [];
    if (data is Map && data.containsKey('results')) {
      list = data['results'];
    }
    return list.map((e) => AgentOrderService.fromJson(e)).toList();
  }

  /// Search the cotizaciones catalog
  Future<List<Map<String, dynamic>>> searchCotizaciones(String query) async {
    final result = await _client.get(
      '/orderops/catalog/services?q=${Uri.encodeComponent(query)}',
    );
    if (!result.ok) {
      debugPrint('OrderOpsService.searchCotizaciones error: ${result.error}');
      return [];
    }
    if (result.body is List) {
      return List<Map<String, dynamic>>.from(result.body);
    }
    return [];
  }

  /// Add a manual service association
  Future<bool> addManualService(int idnbr, Map<String, dynamic> data) async {
    final result = await _client.post(
      '/orderops/agent-orders/$idnbr/manual-services',
      jsonBody: data,
    );
    return result.ok;
  }

  /// Remove a manual service association
  Future<bool> removeManualService(int manualId) async {
    final result = await _client.delete('/orderops/manual-services/$manualId');
    return result.ok;
  }

  /// Fetch all unique families from the catalog
  Future<List<String>> getCatalogFamilies() async {
    final result = await _client.get('/orderops/catalog/families');
    if (!result.ok) {
      debugPrint('OrderOpsService.getCatalogFamilies error: ${result.error}');
      return [];
    }
    if (result.body is List) {
      return List<String>.from(result.body.map((e) => e.toString()));
    }
    return [];
  }

  /// Admin/chief: list cotizaciones rows with pagination and optional filters.
  Future<Map<String, dynamic>> listCotizacionesAdmin({
    String? query,
    String? family,
    int limit = 100,
    int offset = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (query != null && query.trim().isNotEmpty) {
      queryParams['q'] = query.trim();
    }
    if (family != null && family.trim().isNotEmpty) {
      queryParams['family'] = family.trim();
    }
    final qs = Uri(queryParameters: queryParams).query;
    final result = await _client.get('/orderops/catalog/cotizaciones?$qs');
    if (!result.ok || result.body is! Map) {
      throw Exception('No se pudo cargar cotizaciones');
    }
    return Map<String, dynamic>.from(result.body as Map);
  }

  /// Admin/chief: create cotizacion row.
  Future<bool> createCotizacion(Map<String, dynamic> payload) async {
    final result = await _client.post(
      '/orderops/catalog/cotizaciones',
      jsonBody: payload,
    );
    return result.ok;
  }

  /// Admin/chief: update cotizacion row.
  Future<bool> updateCotizacion(int id, Map<String, dynamic> payload) async {
    final result = await _client.patch(
      '/orderops/catalog/cotizaciones/$id',
      jsonBody: payload,
    );
    return result.ok;
  }

  /// Admin/chief: delete cotizacion row.
  Future<bool> deleteCotizacion(int id) async {
    final result = await _client.delete('/orderops/catalog/cotizaciones/$id');
    return result.ok;
  }

  /// Manually trigger SFTP/MSSQL order ingestion with real-time updates.
  Stream<Map<String, dynamic>> ingestOrders() async* {
    final streamedResponse = await _client.streamPost('/amz/orders/ingest');

    if (streamedResponse.statusCode != 200) {
      throw Exception('Failed to sync orders: ${streamedResponse.statusCode}');
    }

    await for (final line in streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6).trim();
        if (data.isNotEmpty) {
          try {
            yield json.decode(data) as Map<String, dynamic>;
          } catch (e) {
            if (kDebugMode) print('Error decoding stream data: $e');
          }
        }
      }
    }
  }
}
