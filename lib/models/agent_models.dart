import 'dart:convert';

class AgentOrder {
  final int idnbr;
  final String orderNbr;
  final String customer;
  final DateTime? orderDate;
  final String prioridad;
  final String estado;
  final String? family;
  final String? proyecto;
  final int? proyectoId;
  final bool archived;
  final bool isBlocked;
  final String riskLevel; // low, medium, high
  final String agentStatus;
  final double llmConfidence;
  final DateTime? lastTriagedAt;
  final DateTime? createdAt;

  // v2 Fields
  final String? department;
  final double? departmentConfidence;
  final String? departmentSource;
  final String? departmentReason;

  final double? estimatedRevenue;
  final double? estimatedCost;
  final double? estimatedMargin;
  final double? estimatedMarginPct;

  final String? sourceCommentsExcerpt;
  final String? sourcePrimarySku;
  final String? sourcePrimaryDesc;

  // Progress Fields
  final int planTotal;
  final int planDone;
  final int planOpen;
  final double planProgressPct;
  final String? planNextTask;

  // Completion Fields
  final DateTime? completedAt;
  final String? completionSummary;
  final String? completionAuthor;

  AgentOrder({
    required this.idnbr,
    required this.orderNbr,
    required this.customer,
    this.orderDate,
    required this.prioridad,
    required this.estado,
    this.family,
    this.proyecto,
    this.proyectoId,
    required this.archived,
    required this.isBlocked,
    required this.riskLevel,
    required this.agentStatus,
    required this.llmConfidence,
    this.lastTriagedAt,
    this.createdAt,
    this.department,
    this.departmentConfidence,
    this.departmentSource,
    this.departmentReason,
    this.estimatedRevenue,
    this.estimatedCost,
    this.estimatedMargin,
    this.estimatedMarginPct,
    this.sourceCommentsExcerpt,
    this.sourcePrimarySku,
    this.sourcePrimaryDesc,
    this.planTotal = 0,
    this.planDone = 0,
    this.planOpen = 0,
    this.planProgressPct = 0.0,
    this.planNextTask,
    this.completedAt,
    this.completionSummary,
    this.completionAuthor,
  });

  factory AgentOrder.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final rawProyecto = json['proyecto'];
    String? proyectoNombre;
    int? proyectoId;

    if (rawProyecto is Map) {
      proyectoNombre = rawProyecto['nombre']?.toString();
      final rawId = rawProyecto['id'];
      if (rawId is int) {
        proyectoId = rawId;
      } else if (rawId is String) {
        proyectoId = int.tryParse(rawId);
      }
    } else if (rawProyecto is String) {
      proyectoNombre = rawProyecto;
    }

    final explicitProyectoId = json['proyecto_id'];
    if (explicitProyectoId is int) {
      proyectoId = explicitProyectoId;
    } else if (explicitProyectoId is String) {
      proyectoId = int.tryParse(explicitProyectoId) ?? proyectoId;
    }

    return AgentOrder(
      idnbr: json['idnbr'] as int? ?? 0,
      orderNbr: json['order_nbr'] as String? ?? 'UNKNOWN',
      customer: json['customer'] as String? ?? 'Unknown Customer',
      orderDate: json['order_date'] != null
          ? DateTime.tryParse(json['order_date'])
          : null,
      prioridad: json['prioridad'] as String? ?? 'Normal',
      estado: json['estado'] as String? ?? '',
      family: json['family'] as String?,
      proyecto: proyectoNombre,
      proyectoId: proyectoId,
      archived: json['archived'] as bool? ?? false,
      isBlocked: (json['is_blocked'] == 1 || json['is_blocked'] == true),
      riskLevel: json['risk_level'] as String? ?? 'low',
      agentStatus: json['agent_status'] as String? ?? 'pending',
      llmConfidence: asDouble(json['llm_confidence']) ?? 0.0,
      lastTriagedAt: json['last_triaged_at'] != null
          ? DateTime.tryParse(json['last_triaged_at'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      department: json['department'],
      departmentConfidence: asDouble(json['department_confidence']),
      departmentSource: json['department_source'],
      departmentReason: json['department_reason'],
      estimatedRevenue: asDouble(json['estimated_revenue']),
      estimatedCost: asDouble(json['estimated_cost']),
      estimatedMargin: asDouble(json['estimated_margin']),
      estimatedMarginPct: asDouble(json['estimated_margin_pct']),
      sourceCommentsExcerpt: json['source_comments_excerpt'],
      sourcePrimarySku: json['source_primary_sku'],
      sourcePrimaryDesc: json['source_primary_desc'],

      planTotal: json['plan_total'] as int? ?? 0,
      planDone: json['plan_done'] as int? ?? 0,
      planOpen: json['plan_open'] as int? ?? 0,
      planProgressPct: asDouble(json['plan_progress_pct']) ?? 0.0,
      planNextTask: json['plan_next_task'] as String?,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'])
          : null,
      completionSummary: json['completion_summary'] as String?,
      completionAuthor: json['completion_author'] as String?,
    );
  }
}

class AgentMemory {
  final int id;
  final String question;
  final String? answer;
  final String? status; // open, answered, ignored
  final String? department;
  final int? sourceIdnbr;
  final String? sourceExcerpt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AgentMemory({
    required this.id,
    required this.question,
    this.answer,
    this.status,
    this.department,
    this.sourceIdnbr,
    this.sourceExcerpt,
    this.createdAt,
    this.updatedAt,
  });

  factory AgentMemory.fromJson(Map<String, dynamic> json) {
    return AgentMemory(
      id: json['id'] as int? ?? 0,
      question: json['question'] as String? ?? '',
      answer: json['answer'] as String?,
      status: json['status'] as String?,
      department: json['department'] as String?,
      sourceIdnbr: json['source_idnbr'] as int?,
      sourceExcerpt: json['source_excerpt'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
    );
  }
}

class LatestLLM {
  final Map<String, dynamic> extractedRequirements;
  final List<String> blockers;
  final List<String> suggestedActions;
  final List<String> suggestedAssignees; // New field
  final double confidence;
  final String promptVersion;
  final DateTime? createdAt;

  LatestLLM({
    required this.extractedRequirements,
    required this.blockers,
    required this.suggestedActions,
    required this.suggestedAssignees,
    required this.confidence,
    required this.promptVersion,
    this.createdAt,
  });

  factory LatestLLM.fromJson(Map<String, dynamic> json) {
    // Helpers to safely parse JSON strings or return objects if already parsed
    Map<String, dynamic> parseMap(dynamic input) {
      if (input == null) return {};
      if (input is Map) return Map<String, dynamic>.from(input);
      if (input is String) {
        try {
          return jsonDecode(input);
        } catch (_) {
          return {};
        }
      }
      return {};
    }

    List<String> parseList(dynamic input) {
      if (input == null) return [];
      if (input is List) return input.map((e) => e.toString()).toList();
      if (input is String) {
        try {
          final decoded = jsonDecode(input);
          if (decoded is List) return decoded.map((e) => e.toString()).toList();
        } catch (_) {
          return [];
        }
      }
      return [];
    }

    double? asDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    return LatestLLM(
      extractedRequirements: parseMap(json['extracted_requirements']),
      blockers: parseList(json['blockers']),
      suggestedActions: parseList(json['suggested_actions']),
      suggestedAssignees: parseList(
        json['suggested_assignees'],
      ), // Parse new field
      confidence: asDouble(json['confidence']) ?? 0.0,
      promptVersion: json['prompt_version'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
    );
  }
}

class WorkItem {
  final int workItemId; // backend uses work_item_id
  final int idnbr; // backend uses idnbr, not order_id
  final String type;
  final String description;
  final String status; // open, in_progress, blocked, done
  final String? assignedTo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  WorkItem({
    required this.workItemId,
    required this.idnbr,
    required this.type,
    required this.description,
    required this.status,
    this.assignedTo,
    this.createdAt,
    this.updatedAt,
  });

  factory WorkItem.fromJson(Map<String, dynamic> json) {
    return WorkItem(
      workItemId: json['work_item_id'] as int? ?? 0,
      idnbr: json['idnbr'] as int? ?? 0,
      type: json['type'] as String? ?? 'General',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      assignedTo: json['assigned_to'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
    );
  }
}

class AgentOrderQualityLog {
  final int id;
  final int idnbr;
  final String level; // Info, Warning, Error
  final String? author;
  final String message;
  final DateTime? createdAt;

  AgentOrderQualityLog({
    required this.id,
    required this.idnbr,
    required this.level,
    this.author,
    required this.message,
    this.createdAt,
  });

  factory AgentOrderQualityLog.fromJson(Map<String, dynamic> json) {
    return AgentOrderQualityLog(
      id: json['id'] as int? ?? 0,
      idnbr: json['idnbr'] as int? ?? 0,
      level: json['level'] as String? ?? 'Info',
      author: json['author'] as String?,
      message: json['message'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
    );
  }
}

class OrderOpsDetail {
  final AgentOrder agentOrder;
  final LatestLLM? latestLLM;
  final List<WorkItem> workItems;
  final List<AgentOrderQualityLog> qualityLogs; // New field
  final Map<String, dynamic>? sourceOrder;

  OrderOpsDetail({
    required this.agentOrder,
    this.latestLLM,
    required this.workItems,
    required this.qualityLogs,
    this.sourceOrder,
  });

  factory OrderOpsDetail.fromJson(Map<String, dynamic> json) {
    return OrderOpsDetail(
      agentOrder: AgentOrder.fromJson(json['agent_order'] ?? {}),
      latestLLM: json['latest_llm'] != null
          ? LatestLLM.fromJson(json['latest_llm'])
          : null,
      workItems: (json['work_items'] as List? ?? [])
          .map((item) => WorkItem.fromJson(item))
          .toList(),
      qualityLogs: (json['quality_logs'] as List? ?? [])
          .map((item) => AgentOrderQualityLog.fromJson(item))
          .toList(),
      sourceOrder: json['source_order'] as Map<String, dynamic>?,
    );
  }
}

class ChatMessage {
  final int? id;
  final String role; // 'human', 'assistant'
  final String content;
  final DateTime? createdAt;
  final bool isStreaming; // UI helper

  ChatMessage({
    this.id,
    required this.role,
    required this.content,
    this.createdAt,
    this.isStreaming = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int?,
      role: json['role'] as String? ?? 'assistant',
      // Check probable keys for message content
      content:
          json['content'] as String? ??
          json['text'] as String? ??
          json['message'] as String? ??
          '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
    );
  }
}

class AgentOrderObservation {
  final int id;
  final int idnbr;
  final int? proyectoId; // Link to a proyecto
  final String? author;
  final String body;
  final DateTime? createdAt;

  AgentOrderObservation({
    required this.id,
    required this.idnbr,
    this.proyectoId,
    this.author,
    required this.body,
    this.createdAt,
  });

  factory AgentOrderObservation.fromJson(Map<String, dynamic> json) {
    return AgentOrderObservation(
      id: json['id'] as int? ?? 0,
      idnbr: json['idnbr'] as int? ?? 0,
      proyectoId: json['proyecto_id'] as int?,
      author: json['author'] as String?,
      body: json['body'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
    );
  }
}

class AgentOrderPhoto {
  final int id;
  final int idnbr;
  final int? proyectoId; // Link to a proyecto
  final String? author;
  final String fileName;
  final String filePath;
  final String? scope;
  final DateTime? uploadedAt;

  AgentOrderPhoto({
    required this.id,
    required this.idnbr,
    this.proyectoId,
    this.author,
    required this.fileName,
    required this.filePath,
    this.scope,
    this.uploadedAt,
  });

  factory AgentOrderPhoto.fromJson(Map<String, dynamic> json) {
    return AgentOrderPhoto(
      id: json['id'] as int? ?? 0,
      idnbr: json['idnbr'] as int? ?? 0,
      proyectoId: json['proyecto_id'] as int?,
      author: json['author'] as String?,
      fileName: json['file_name'] as String? ?? 'unknown.jpg',
      filePath: json['file_path'] as String? ?? '',
      scope: json['scope'] as String?,
      uploadedAt: json['uploaded_at'] != null
          ? DateTime.tryParse(json['uploaded_at'])
          : null,
    );
  }
}

class Proyecto {
  final int id;
  final String nombre;
  final String? description;
  final DateTime? createdAt;
  final List<AgentOrder>? orders;
  final List<AgentOrderObservation>? observations;
  final List<AgentOrderPhoto>? photos;

  Proyecto({
    required this.id,
    required this.nombre,
    this.description,
    this.createdAt,
    this.orders,
    this.observations,
    this.photos,
  });

  factory Proyecto.fromJson(Map<String, dynamic> json) {
    return Proyecto(
      id: json['id'] as int? ?? 0,
      nombre: json['nombre'] as String? ?? '',
      description: json['description'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      orders: json['orders'] is List
          ? List<dynamic>.from(json['orders']).map((e) => AgentOrder.fromJson(Map<String, dynamic>.from(e))).toList()
          : (json['agent_orders'] is List
              ? List<dynamic>.from(json['agent_orders']).map((e) => AgentOrder.fromJson(Map<String, dynamic>.from(e))).toList()
              : null),
      observations: json['observations'] is List
          ? List<dynamic>.from(json['observations']).map((e) => AgentOrderObservation.fromJson(Map<String, dynamic>.from(e))).toList()
          : null,
      photos: json['photos'] is List
          ? List<dynamic>.from(json['photos']).map((e) => AgentOrderPhoto.fromJson(Map<String, dynamic>.from(e))).toList()
          : null,
    );
  }
}

class AgentOrderService {
  final int id;
  final String? family;
  final String? description;
  final String? extraInfo1;
  final String? skuConfig;
  final double? coste;
  final double? pvdAdministracion;
  final double? margen;
  final double? tiempoMin;
  final String? personal;
  final String? collectionInfo;
  final double? orderUnitPrice;
  final double? theoreticalPvd;
  final bool isManual;
  final int? manualId;

  AgentOrderService({
    required this.id,
    this.family,
    this.description,
    this.extraInfo1,
    this.skuConfig,
    this.coste,
    this.pvdAdministracion,
    this.margen,
    this.tiempoMin,
    this.personal,
    this.collectionInfo,
    this.orderUnitPrice,
    this.theoreticalPvd,
    this.isManual = false,
    this.manualId,
  });

  factory AgentOrderService.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    return AgentOrderService(
      id: json['id'] as int? ?? 0,
      family: json['family'] as String?,
      description: json['description'] as String?,
      extraInfo1: json['extra_info_1'] as String?,
      skuConfig: json['sku_config'] as String?,
      coste: asDouble(json['coste']),
      pvdAdministracion:
          asDouble(json['pvd_administracion']) ?? asDouble(json['pvd']),
      margen: asDouble(json['margen']),
      tiempoMin: asDouble(json['tiempo_min']),
      personal: json['personal'] as String?,
      collectionInfo: json['collection_info'] as String?,
      orderUnitPrice: asDouble(json['order_unit_price']),
      theoreticalPvd: asDouble(json['theoretical_pvd']),
      isManual: json['is_manual'] as bool? ?? false,
      manualId: json['manual_id'] as int?,
    );
  }
}
