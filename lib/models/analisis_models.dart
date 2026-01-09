class ProjectFund {
  final int? id;
  final String? idxiaomi;
  final double? fondos;
  final bool? activo;
  final String? descripcion;
  final double totalSpent;
  final int transactions;
  final double? remaining;

  ProjectFund({
    this.id,
    this.idxiaomi,
    this.fondos,
    this.activo,
    this.descripcion,
    required this.totalSpent,
    required this.transactions,
    this.remaining,
  });

  factory ProjectFund.fromJson(Map<String, dynamic> json) {
    return ProjectFund(
      id: json['id'] as int?,
      idxiaomi: _parseString(json['idxiaomi']),
      fondos: _parseDouble(json['fondos']),
      activo: json['activo'] as bool?,
      descripcion: _parseString(json['descripcion']),
      totalSpent: _parseDouble(json['total_spent']) ?? 0.0,
      transactions: json['transactions'] as int? ?? 0,
      remaining: _parseDouble(json['remaining']),
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }
}

class Transaction {
  final int? id;
  final String? csku;
  final String? previ;
  final String? servicio;
  final String? fabricante;
  final String? cliente;
  final String? idxiaomi;
  final String? descripcion;
  final String? unit;
  final String? observacion;
  final String? fechai;
  final String? fechaf;
  final String? claimacc;
  final String? internal;
  final String? estado;
  final double? cost;
  final String? user;
  final String? numsap;
  final String? palets;

  Transaction({
    this.id,
    this.csku,
    this.previ,
    this.servicio,
    this.fabricante,
    this.cliente,
    this.idxiaomi,
    this.descripcion,
    this.unit,
    this.observacion,
    this.fechai,
    this.fechaf,
    this.claimacc,
    this.internal,
    this.estado,
    this.cost,
    this.user,
    this.numsap,
    this.palets,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as int?,
      csku: ProjectFund._parseString(json['csku']),
      previ: ProjectFund._parseString(json['previ']),
      servicio: ProjectFund._parseString(json['servicio']),
      fabricante: ProjectFund._parseString(json['fabricante']),
      cliente: ProjectFund._parseString(json['cliente']),
      idxiaomi: ProjectFund._parseString(json['idxiaomi']),
      descripcion: ProjectFund._parseString(json['descripcion']),
      unit: ProjectFund._parseString(json['unit']),
      observacion: ProjectFund._parseString(json['observacion']),
      fechai: ProjectFund._parseString(json['fechai']),
      fechaf: ProjectFund._parseString(json['fechaf']),
      claimacc: ProjectFund._parseString(json['claimacc']),
      internal: ProjectFund._parseString(json['internal']),
      estado: ProjectFund._parseString(json['estado']),
      cost: ProjectFund._parseDouble(json['cost']),
      user: ProjectFund._parseString(json['user']),
      numsap: ProjectFund._parseString(json['numsap']),
      palets: ProjectFund._parseString(json['palets']),
    );
  }
}
