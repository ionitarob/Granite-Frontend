import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../api_client.dart';
import '../models/agent_models.dart';

class OrderOpsService {
  final ApiClient _client;

  OrderOpsService(this._client);

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
  }) async {
    final body = <String, dynamic>{};
    if (department != null) body['department'] = department;
    if (estado != null) body['estado'] = estado;
    if (reason != null) body['reason'] = reason;
    if (markCompleted != null) body['mark_completed'] = markCompleted;
    if (completionSummary != null) {
      body['completion_summary'] = completionSummary;
    }
    if (completionAuthor != null) {
      body['completion_author'] = completionAuthor;
    }

    final result = await _client.patch(
      '/orderops/agent-orders/$idnbr/update',
      jsonBody: body,
    );
    return result.ok;
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
  }) async {
    final body = <String, dynamic>{'body': bodyText};
    if (author != null) body['author'] = author;
    final result = await _client.post(
      '/orderops/agent-orders/$idnbr/observations',
      jsonBody: body,
    );
    return result.ok;
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
  }) async {
    final body = <String, dynamic>{
      'file_name': fileName,
      'file_path': filePath,
    };
    if (author != null) body['author'] = author;
    final result = await _client.post(
      '/orderops/agent-orders/$idnbr/photos',
      jsonBody: body,
    );
    return result.ok;
  }

  /// Upload photo via multipart (Camera/Gallery)
  Future<bool> uploadPhoto(int idnbr, String fileName, List<int> bytes) async {
    final result = await _client.postMultipart(
      '/orderops/agent-orders/$idnbr/photos',
      fileName: fileName,
      fileBytes: bytes,
      fileFieldName: 'file',
    );
    return result.ok;
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
}
